--!strict
-- The world past the countryside, as the web game's free view shows it (Horizon.tsx): land
-- rolling out to the horizon, 15,000 studs each way, with a snowy mountain range and wind farm
-- behind the town, farmland, a railway, a highway and a distant city ahead of it, a lake between
-- wooded hills on one side and hot-air balloons over forest on the other; and over it all the
-- web game's sky, baked into skyboxes for each step of the town's day (Horizon.sky, which
-- DayNight calls with the clock).
--
-- The land is the web game's own, converted by tools/models/build.mjs ("horizon:land" in
-- Shared.Models.Scenery), and drawn here on the client round this player's town only. Its meshes
-- load after everything else (Builder.loadLate), so it appears a little after the town does. The
-- wind turbines' rotors and the balloons are left out of it and moved here (Horizon.movers).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Models = Shared:WaitForChild("Models")
local Builder = require(Models:WaitForChild("Builder")) :: any
local Scenery = require(Models:WaitForChild("Scenery")) :: any
local SkyImages = require(Models:WaitForChild("SkyImages")) :: any
local Game = Shared:WaitForChild("Game")
local clock = require(Game:WaitForChild("clock")) :: any
local weather = require(Game:WaitForChild("weather")) :: any

local Horizon = {}

local LAND = "horizon:land"

-- Every mesh the far land needs, by key.
local function meshKeys(): { string }
	local keys, seen = {}, {}
	for _, p in Scenery.MODELS[LAND] or {} do
		local key = p[13]
		if p[1] == "m" and type(key) == "string" and not seen[key] then
			seen[key] = true
			table.insert(keys, key)
		end
	end
	return keys
end

-- Waits (up to timeout seconds) until the server has shared every mesh of the far land, and says
-- whether it did: a model built with some missing would leave holes in the hills for good.
local function waitForMeshes(timeout: number): boolean
	local library = ReplicatedStorage:WaitForChild("MeshLibrary", timeout)
	if not library then
		return false
	end
	local keys = meshKeys()
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		local missing = false
		for _, key in keys do
			if not library:FindFirstChild(key) then
				missing = true
				break
			end
		end
		if not missing then
			return true
		end
		task.wait(1)
	end
	return false
end

-- Other players' towns stand on their own lots, 4,500 studs apart, which is out among this
-- town's hills: their meadows (always streamed in) would show through as flat green squares, so
-- they're hidden here, as is the place's spare Ground block when it isn't under this town.
local function hideOthers(mine: Folder)
	local function hide(m: Instance)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end
		m.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end)
	end
	local towns = mine.Parent :: Instance
	local function check(f: Instance)
		if f ~= mine then
			local meadow = f:WaitForChild("Meadow", 30)
			if meadow then
				hide(meadow)
			end
		end
	end
	for _, f in towns:GetChildren() do
		task.spawn(check, f)
	end
	towns.ChildAdded:Connect(check)
	local ground = workspace:FindFirstChild("Ground")
	local origin: Vector3 = mine:GetAttribute("Origin") :: any
	if ground and ground:IsA("BasePart") and (ground.Position - origin).Magnitude > 1000 then
		ground.LocalTransparencyModifier = 1
	end
end

-- In the shared world (server/World) the land round a town is the world's own ground, roads and
-- neighbours, out to the ground's edge. The far land is drawn round the world's middle instead, with
-- every piece that lies wholly on the world's ground left out, and the rest sunk SINK studs: its
-- flat land, a few studs either side of the world's ground, cut through it in patches that flickered
-- as the camera moved, and sunk it stays out of sight under it.
local SINK = 5

-- How far (studs, each way from its middle) the shared world's ground reaches, or nil outside it.
-- As server/World works it out: half a plot past the last ring, and 600 more.
local function worldReach(): number?
	local world = workspace:FindFirstChild("World")
	local pitch = world and world:GetAttribute("Pitch")
	local rings = world and world:GetAttribute("Rings")
	if type(pitch) ~= "number" or type(rings) ~= "number" then
		return nil
	end
	return (rings + 0.5) * pitch + 600
end

-- Whether a box (middle x, z and size sx, sz, studs from the land's middle) lies wholly within
-- clear of it each way.
local function within(x: number, z: number, sx: number, sz: number, clear: number): boolean
	return math.abs(x) + sx / 2 < clear and math.abs(z) + sz / 2 < clear
end

-- Draws the far land round a town whose middle is at origin, into parent. clear: leave out the
-- pieces wholly within that many studs of origin each way, and sink the rest (the shared world).
function Horizon.draw(origin: Vector3, parent: Instance, clear: number?): Model?
	local land = Builder.build(LAND)
	if not land then
		return nil
	end
	for _, d in land:GetDescendants() do
		if d:IsA("BasePart") then
			d.CastShadow = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	land:PivotTo(CFrame.new(origin - Vector3.new(0, if clear then SINK else 0, 0)))
	if clear then
		for _, d in land:GetDescendants() do
			if d:IsA("BasePart") then
				local at = d.CFrame.Position - origin
				local size = d.CFrame:VectorToWorldSpace(d.Size)
				if within(at.X, at.Z, math.abs(size.X), math.abs(size.Z), clear) then
					d:Destroy()
				end
			end
		end
	end
	land.Parent = parent
	return land
end

-- ---- What moves: the wind farm's rotors and the hot-air balloons ------------------------------
-- Built from plain parts here (Horizon.tsx's shapes, web units x 10) and moved every frame the
-- way the web game moves them: about fifty anchored parts in one BulkMoveTo, cheap on phones.

local TAU = 2 * math.pi
local WHITE = Color3.fromHex("#f2f4f5")
local BLADE = 300 -- studs, the web's 30

-- Horizon.tsx BALLOONS: angle round the town, distance, height, colour, drift speed.
local A_WOODS, A_LAKE = -math.pi / 4, 3 * math.pi / 4
local BALLOONS = {
	{ a = A_WOODS - 0.25, r = 3300, y = 950, c = "#e53935", v = 0.012 },
	{ a = A_WOODS + 0.1, r = 4200, y = 1200, c = "#fdd835", v = -0.009 },
	{ a = A_WOODS + 0.42, r = 3000, y = 800, c = "#1e88e5", v = 0.01 },
	{ a = A_LAKE - 0.5, r = 3800, y = 1100, c = "#8e24aa", v = -0.011 },
}

local function part(parent: Instance, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Color = color
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.Parent = parent
	return p
end

type Piece = { part: BasePart, at: CFrame }

-- Builds the rotors and balloons round a town whose middle is at origin, into parent, and
-- returns a function that moves them on: dt seconds since the last call, t since they appeared.
-- clear and the sinking as Horizon.draw: rotors whose tower it left out are left out too.
function Horizon.movers(origin: Vector3, parent: Instance, clear: number?): (dt: number, t: number) -> ()
	local folder = Instance.new("Folder")
	folder.Name = "HorizonMovers"
	folder.Parent = parent
	local turbines = Scenery.TURBINES or {}
	if clear then
		local kept = {}
		for _, tb in turbines do
			if not within(tb[1], tb[3], 0, 0, clear) then
				table.insert(kept, { tb[1], tb[2] - SINK, tb[3], tb[4], tb[5] })
			end
		end
		turbines = kept
	end

	-- Three blades round a hub, turning about the rotor's own z (Horizon.tsx WindFarm), each
	-- rotor starting from its own angle.
	local rotors: { { Piece } } = {}
	local spins: { number } = {}
	for i, t in turbines do
		local pieces: { Piece } = {}
		for b = 0, 2 do
			table.insert(pieces, {
				part = part(folder, Vector3.new(24, BLADE, 6), WHITE),
				at = CFrame.Angles(0, 0, b / 3 * TAU) * CFrame.new(0, BLADE / 2 + 10, 0),
			})
		end
		table.insert(pieces, { part = part(folder, Vector3.new(46, 46, 46), WHITE, Enum.PartType.Ball), at = CFrame.identity })
		rotors[i] = pieces
		spins[i] = t[5] * TAU
	end

	-- An envelope, a white band under it and a basket hanging below.
	local balloons: { { Piece } } = {}
	local flock = Instance.new("Folder")
	flock.Name = "Balloons"
	flock.Parent = folder
	for i, b in BALLOONS do
		local envelope = part(flock, Vector3.new(180, 220, 180), Color3.fromHex(b.c))
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = envelope
		balloons[i] = {
			{ part = envelope, at = CFrame.identity },
			{
				part = part(flock, Vector3.new(40, 157, 157), Color3.new(1, 1, 1), Enum.PartType.Cylinder),
				at = CFrame.new(0, -55, 0) * CFrame.Angles(0, 0, math.pi / 2),
			},
			{ part = part(flock, Vector3.new(32, 26, 32), Color3.fromHex("#8d6e63")), at = CFrame.new(0, -150, 0) },
		}
	end

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local flying = true
	return function(dt: number, t: number)
		local w = weather.weatherNow()
		local n = 0
		local function place(pieces: { Piece }, cf: CFrame)
			for _, p in pieces do
				n += 1
				parts[n] = p.part
				cframes[n] = cf * p.at
			end
		end
		-- The rotors face the town together and turn faster in a breeze.
		local speed = 0.9 + w.wind * 2.2
		for i, tb in turbines do
			spins[i] += math.min(dt, 0.1) * speed * (0.85 + tb[5] * 0.3)
			place(rotors[i], CFrame.new(origin + Vector3.new(tb[1], tb[2], tb[3])) * CFrame.fromEulerAnglesYXZ(0, tb[4], spins[i]))
		end
		-- The balloons only fly in fair weather, by day.
		local night = clock.nightAmount(clock.dayPhase(DateTime.now().UnixTimestampMillis))
		local fly = night < 0.5 and w.rain < 0.2 and w.snow < 0.2 and w.wind < 0.6
		if fly ~= flying then
			flying = fly
			flock.Parent = if fly then folder else nil
		end
		if fly then
			for i, b in BALLOONS do
				local k = i - 1
				local a = b.a + math.sin(t * b.v * 3 + k) * 0.08 + t * b.v * 0.1
				local at = origin + Vector3.new(math.cos(a) * b.r, b.y + math.sin(t * 0.3 + k * 2) * 40, math.sin(a) * b.r)
				place(balloons[i], CFrame.new(at) * CFrame.Angles(0, t * 0.05 + k, 0))
			end
		end
		for j = #parts, n + 1, -1 do
			parts[j] = nil
			cframes[j] = nil
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function Horizon.start()
	local Town = require(script.Parent.Town)
	task.spawn(function()
		local folder: Folder? = nil
		while not folder do
			folder = Town.folder()
			if not folder then
				task.wait(0.5)
			end
		end
		hideOthers(folder :: Folder)
		-- Without its meshes (not uploaded yet, or a pack that failed) the land would be a city
		-- and some cars standing on nothing, so it waits for the next server instead.
		if not waitForMeshes(180) then
			return
		end
		Builder.useLibrary(5)
		-- Round this player's town, or in the shared world round its middle, past its ground.
		local reach = worldReach()
		local origin: Vector3 = if reach then Vector3.zero else (folder :: Folder):GetAttribute("Origin") :: any
		local land = Horizon.draw(origin, workspace, reach)
		if land then
			land.Name = "Horizon"
		end
		local move = Horizon.movers(origin, workspace, reach)
		local t = 0
		RunService.RenderStepped:Connect(function(dt)
			t += dt
			move(dt, t)
		end)
	end)
end

-- ---- The sky ---------------------------------------------------------------------------------

local FACES = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }
local shown: { [string]: string } = {}
-- The step showing, and the steps whose six pictures have downloaded: the sky moves on to a new
-- step only once all of it is in, so it never shows some faces of one time and some of another.
local current: any = nil
local ready: { [any]: boolean } = {}
local loading: { [any]: boolean } = {}

-- An uploaded picture's id as the sky should ask for it: the image inside the decal Open Cloud
-- made, once the server has looked it up (server/Sky), else the id as it is.
local function image(id: number): string
	local found = workspace:GetAttribute(`Sky{id}`)
	return if type(found) == "string" then found else `rbxassetid://{id}`
end

-- Shows the baked sky for a phase of the town clock (0 noon, 0.5 midnight) and returns the
-- colour the far land fades into at that time, or nil while the sky isn't uploaded (Roblox's
-- own sky shows then).
function Horizon.sky(phase: number): Color3?
	local d = math.abs(phase - 0.5)
	local best, gap = nil, math.huge
	for _, step in SkyImages.steps do
		local g = math.abs(step.d - d)
		if g < gap then
			best, gap = step, g
		end
	end
	if not best or best.faces.Up == 0 then
		return nil
	end
	if best ~= current then
		if current == nil or ready[best] then
			current = best
		elseif not loading[best] then
			loading[best] = true
			local step = best
			task.spawn(function()
				local list = {}
				for _, face in FACES do
					table.insert(list, image(step.faces[face]))
				end
				pcall(ContentProvider.PreloadAsync, ContentProvider, list)
				ready[step] = true
			end)
		end
	end
	best = current
	local sky = Lighting:FindFirstChildWhichIsA("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Name = "Sky"
		sky.Parent = Lighting
	end
	local s = sky :: Sky
	-- The sun is Roblox's (DayNight stands it where the web game's light is); the stars and the
	-- clouds are baked in.
	s.CelestialBodiesShown = true
	s.MoonAngularSize = 0
	s.StarCount = 0
	for _, face in FACES do
		local want = image(best.faces[face])
		if shown[face] ~= want then
			shown[face] = want;
			(s :: any)[`Skybox{face}`] = want
		end
	end
	return Color3.fromHex(best.haze)
end

return Horizon
