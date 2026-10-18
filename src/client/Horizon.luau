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
-- load after everything else (Builder.loadLate), so it appears a little after the town does.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Models = Shared:WaitForChild("Models")
local Builder = require(Models:WaitForChild("Builder")) :: any
local Scenery = require(Models:WaitForChild("Scenery")) :: any
local SkyImages = require(Models:WaitForChild("SkyImages")) :: any

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

-- Draws the far land round a town whose middle is at origin, into parent.
function Horizon.draw(origin: Vector3, parent: Instance): Model?
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
	land:PivotTo(CFrame.new(origin))
	land.Parent = parent
	return land
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
		local land = Horizon.draw((folder :: Folder):GetAttribute("Origin") :: any, workspace)
		if land then
			land.Name = "Horizon"
		end
	end)
end

-- ---- The sky ---------------------------------------------------------------------------------

local FACES = { "Bk", "Dn", "Ft", "Lf", "Rt", "Up" }
local shown: { [string]: string } = {}

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
