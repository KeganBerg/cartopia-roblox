--!strict
-- The Speedway's life, as the web game's scene/SpeedwayLife.tsx draws it inside the 'stadium'
-- building: race cars lapping the track nose to tail, and fans standing at their grandstand seats
-- (three rows, and two more on the upper deck from level 7) who throw their arms up as the cars come
-- past and when the wave goes round the stands.
--
-- Where every seat and fan goes, and how an arm hangs, is the web game's own code, converted:
-- scene/speedwayLayout.ts and scene/speedwayCrowd.ts (Shared.Game.scene_speedwayLayout,
-- scene_speedwayCrowd). The cars' laps and the cheering are SpeedwayLife.tsx's useFrame, here.
--
-- It all runs on this player's client, like TownLife: it never changes the game, and the server's
-- stadium model (TownView) leaves the race and the crowd out (tools/models/export.test.tsx). Kept
-- cheap for phones: seats and bodies are placed once; each frame moves the few cars and only the
-- arms that are up or on their way up or down, all in one BulkMoveTo.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local layout = require(Game:WaitForChild("scene_speedwayLayout")) :: any
local crowd = require(Game:WaitForChild("scene_speedwayCrowd")) :: any
local peopleGeo = require(Game:WaitForChild("scene_peopleGeo")) :: any
local people = require(Game:WaitForChild("scene_people")) :: any
local lualib = require(Game:WaitForChild("lualib_bundle")) :: any
local three = require(Game:WaitForChild("__three")) :: any

local SpeedwayLife = {}

local S = Catalog.SCALE -- studs per web unit
local TRACK, ARC0, ARC = layout.TRACK, layout.ARC0, layout.ARC
local FAN, BODY, SEAT = crowd.FAN, crowd.BODY, crowd.SEAT
local ARM_LEN = peopleGeo.ARM_LEN

-- SpeedwayLife.tsx: seat colours, one a row from the front (the deck's two rows last), the fans'
-- shirts and the race cars' paint.
local SEAT_COLORS = { "#1e88e5", "#fdd835", "#e53935", "#1e88e5", "#fdd835" }
local SHIRTS = { "#e53935", "#fafafa", "#1e88e5", "#fdd835", "#43a047", "#ff7043", "#8e24aa", "#26c6da" }
local PAINT = { "#d32f2f", "#1565c0", "#fdd835", "#2e7d32", "#fafafa", "#ff6d00", "#6a1b9a", "#212121", "#00acc1", "#c2185b" }
-- One lap every ~3 s, the cars nose to tail.
local LAP = 2.1

-- Arms are moved at most this often (a second's worth of frames), and not at all from further off
-- than FAR studs, where nobody can see an arm.
local ARM_RATE = 30
local FAR = 1600

local HIDDEN = CFrame.new(0, -10000, 0)

-- A three.js Matrix4 (column-major, web units) as a CFrame in studs.
local function cframeOf(m: any): CFrame
	local e = m.elements
	return CFrame.new(e[13] * S, e[14] * S, e[15] * S, e[1], e[5], e[9], e[2], e[6], e[10], e[3], e[7], e[11])
end

local function part(parent: Instance, shape: Enum.PartType?, size: Vector3, cf: CFrame, color: string): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromHex(color)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ellipsoid(parent: Instance, size: Vector3, cf: CFrame, color: string): Part
	local p = part(parent, Enum.PartType.Block, size, cf, color)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- A box `w`, `h`, `d` web units with its middle at (x, y, z), in a frame's web units.
local function box(parent: Instance, frame: CFrame, w: number, h: number, d: number, x: number, y: number, z: number, color: string): Part
	return part(parent, nil, Vector3.new(w, h, d) * S, frame * CFrame.new(x * S, y * S, z * S), color)
end

---------------------------------------------------------------------------------------------------
-- The GT race car (SpeedwayLife.tsx raceCar): nose to +z, wheels on y = 0. Each piece is
-- { offset, size, colour or "paint", shape }.

type Piece = { at: CFrame, size: Vector3, color: string?, shape: Enum.PartType? }
local CAR: { Piece } = {}
local function carBox(w: number, h: number, d: number, x: number, y: number, z: number, color: string?)
	table.insert(CAR, { at = CFrame.new(x * S, y * S, z * S), size = Vector3.new(w, h, d) * S, color = color })
end
carBox(0.44, 0.1, 0.9, 0, 0.105, 0, nil)
carBox(0.4, 0.05, 0.16, 0, 0.08, 0.44, nil)
carBox(0.46, 0.015, 0.2, 0, 0.06, 0.38, "#262626")
carBox(0.32, 0.1, 0.36, 0, 0.205, -0.06, "#1c2430")
carBox(0.28, 0.012, 0.26, 0, 0.26, -0.06, nil)
carBox(0.06, 0.012, 0.5, 0, 0.161, 0.2, "#f5f5f5")
for _, x in { -0.13, 0.13 } do
	carBox(0.08, 0.025, 0.012, x, 0.12, 0.454, "#fff8d0")
end
for _, x in { -0.14, 0.14 } do
	carBox(0.08, 0.025, 0.012, x, 0.12, -0.454, "#7a0000")
end
for _, x in { -0.14, 0.14 } do
	carBox(0.02, 0.1, 0.03, x, 0.205, -0.4, "#262626")
end
carBox(0.46, 0.02, 0.09, 0, 0.26, -0.41, "#262626")
-- Wheels: Roblox's cylinders already run along x, the axle.
for _, xz in { { -0.215, 0.29 }, { 0.215, 0.29 }, { -0.215, -0.29 }, { 0.215, -0.29 } } do
	table.insert(CAR, {
		at = CFrame.new(xz[1] * S, 0.075 * S, xz[2] * S),
		size = Vector3.new(0.06, 0.15, 0.15) * S,
		color = "#1a1a1a",
		shape = Enum.PartType.Cylinder,
	})
end

---------------------------------------------------------------------------------------------------
-- One Speedway's race and crowd.

type Fan = { seat: any, at: CFrame, arms: { BasePart }, rest: boolean }
export type Life = {
	folder: Folder,
	frame: CFrame,
	cars: { { BasePart } },
	fans: { Fan },
	armClock: number,
	step: (self: Life, time: number, dt: number, list: { BasePart }, cfs: { CFrame }) -> (),
	destroy: (self: Life) -> (),
}

local Life = {}
Life.__index = Life

-- Builds the race and crowd for a Speedway at `lvl` whose model sits at `frame` (its middle on the
-- ground, turned as TownView turns it). `small`: a phone, where fans' hands and the seat posts are left off.
function SpeedwayLife.new(parent: Instance, frame: CFrame, lvl: number, small: boolean?): Life
	local folder = Instance.new("Folder")
	folder.Name = "SpeedwayLife"
	-- The town isn't merged-scaled here (TownView draws each building at its own size), so the
	-- block's stretch is 1 both ways.
	local sx, sz, k = 1, 1, 1
	local stands = crowd.speedwayStands(lvl, k)
	local seats, aisles = stands.seats, stands.aisles

	-- Seats and stair nosings don't move: placed once, facing the track.
	local m = lualib.__TS__New(three.Matrix4)
	local seatW, cushionD = SEAT.w, SEAT.panFront - SEAT.panBack
	for _, s in seats do
		local at = frame * cframeOf(crowd.seatMatrix(s, sx, sz, m))
		local color = SEAT_COLORS[s.row + 1]
		box(folder, at, seatW, 0.016, cushionD, 0, SEAT.panTop - 0.008, (SEAT.panFront + SEAT.panBack) / 2, color)
		box(folder, at, seatW, SEAT.backTop - 0.03, 0.014, 0, (SEAT.backTop + 0.03) / 2, SEAT.backFront - 0.007, color)
		-- The post under the cushion hardly shows; a phone goes without it.
		if not small then
			box(folder, at, 0.05, SEAT.panTop - 0.016, 0.022, 0, (SEAT.panTop - 0.016) / 2, -0.004, "#455a64")
		end
	end
	for _, s in aisles do
		box(folder, frame * cframeOf(crowd.seatMatrix(s, sx, sz, m)), 0.09, 0.008, 0.02, 0, 0, 0, "#fafafa")
	end

	-- Fans stand still at their seats (peopleGeo.ts figures at FAN times their size, seat-local):
	-- legs, body, head and hair placed once; arms (and hands) hung from the shoulders each frame.
	local fans: { Fan } = {}
	local LEG = BODY.hip / FAN
	local z = BODY.at / FAN
	local function fig(x: number, y: number, zz: number): CFrame
		return CFrame.new(x * FAN * S, y * FAN * S, zz * FAN * S)
	end
	for i, seatIndex in stands.fans do
		local n = i - 1 -- the web's fan index
		local s = seats[seatIndex + 1]
		local at = frame * cframeOf(crowd.seatMatrix(s, sx, sz, m))
		local tee = SHIRTS[(n * 5 + 1) % #SHIRTS + 1]
		local skin = people.SKIN[(n * 7 + 2) % #people.SKIN + 1]
		-- Both legs (legGeo) as one block, shoes and all, feet on the step.
		part(folder, nil, Vector3.new(0.15, LEG + 0.01, 0.07) * FAN * S, at * fig(0, (LEG + 0.01) / 2, z), people.PANTS[n % #people.PANTS + 1])
		ellipsoid(folder, Vector3.new(0.17, 0.33, 0.17) * FAN * S, at * fig(0, LEG + 0.15, z), tee)
		part(folder, Enum.PartType.Ball, Vector3.one * 0.16 * FAN * S, at * fig(0, LEG + 0.36, z), skin)
		ellipsoid(folder, Vector3.new(0.17, 0.12, 0.17) * FAN * S, at * fig(0, LEG + 0.4, z - 0.02), people.HAIR[(n * 3) % #people.HAIR + 1])
		local arms = {}
		for _ = 1, 2 do
			table.insert(arms, ellipsoid(folder, Vector3.new(0.056, 0.196, 0.056) * FAN * S, HIDDEN, tee))
			if not small then
				table.insert(arms, part(folder, Enum.PartType.Ball, Vector3.one * 0.052 * FAN * S, HIDDEN, skin))
			end
		end
		table.insert(fans, { seat = s, at = at, arms = arms, rest = false })
	end

	-- A small field with room between cars: 2 at level 1 up to 4 at level 10.
	local cars = {}
	for i = 1, math.round((2 + math.floor(lvl / 4)) * k) do
		local paint = PAINT[((i - 1) * 3) % #PAINT + 1]
		local list = {}
		for _, p in CAR do
			table.insert(list, part(folder, p.shape, p.size, HIDDEN, p.color or paint))
		end
		table.insert(cars, list)
	end

	folder.Parent = parent
	local self = setmetatable({ folder = folder, frame = frame, cars = cars, fans = fans, armClock = 0 }, Life)
	return (self :: any) :: Life
end

-- Arm and hand of one fan, hung from the shoulder (crowd.armMatrix), as seat-local CFrames.
local ARM = lualib.__TS__New(three.Matrix4)
local ARM_AT = CFrame.new(0, -ARM_LEN / 2 * FAN * S, 0)
local HAND_AT = CFrame.new(0, (-ARM_LEN - 0.006) * FAN * S, 0.005 * FAN * S)

-- Moves everything on to `time` seconds: the cars every frame, the arms ARM_RATE times a second.
-- Adds what moved to BulkMoveTo's lists.
function Life.step(self: Life, time: number, dt: number, list: { BasePart }, cfs: { CFrame })
	local n = #self.cars
	local gap = math.pi * 2 / n
	local angles = table.create(n)
	for i, car in self.cars do
		local j = i - 1
		-- Evenly spaced round the lap, closing up and dropping back a little, weaving across the lane.
		local a = time * LAP + j * gap + math.sin(time * 0.7 + j * 1.9) * gap * 0.12
		local r = TRACK.lane + math.sin(time * 0.9 + j * 2.1) * 0.05
		local x, z = math.sin(a) * r, math.cos(a) * r
		angles[i] = math.atan2(x, z)
		local cf = self.frame * CFrame.new(x * S, 0.06 * S, z * S) * CFrame.fromEulerAnglesYXZ(0, math.atan2(math.cos(a), -math.sin(a)), -0.05)
		for p, piece in car do
			table.insert(list, piece)
			table.insert(cfs, cf * CAR[p].at)
		end
	end

	self.armClock -= dt
	if self.armClock > 0 then
		return
	end
	self.armClock = 1 / ARM_RATE
	-- Arms: down at their sides, thrown up as a car comes past and as the wave sweeps the stands.
	local sweep = ((time / 7) % 1) * 1.6 - 0.3
	for i, f in self.fans do
		local s = f.seat
		local near = math.pi
		for _, ca in angles do
			local d = math.abs((((s.a - ca) % (math.pi * 2)) + math.pi * 3) % (math.pi * 2) - math.pi)
			if d < near then
				near = d
			end
		end
		local idx = i - 1
		local pep = (idx * 0.618) % 1
		local w = math.exp(-((((s.a - ARC0) / ARC - sweep) / 0.07) ^ 2))
		local cheer = math.min(1, math.max(w, math.exp(-((near / 0.4) ^ 2)) * (0.5 + pep * 0.5)))
		-- Hanging still: placed once, then left alone until the next cheer.
		if cheer < 0.01 then
			if f.rest then
				continue
			end
			cheer = 0
			f.rest = true
		else
			f.rest = false
		end
		local per = #f.arms // 2
		for side = -1, 1, 2 do
			local wave = math.sin(time * 9 + idx * 2 + side)
			local arm = f.at * cframeOf(crowd.armMatrix(side, cheer, wave, ARM))
			local first = if side < 0 then 1 else per + 1
			table.insert(list, f.arms[first])
			table.insert(cfs, arm * ARM_AT)
			if per > 1 then
				table.insert(list, f.arms[first + 1])
				table.insert(cfs, arm * HAND_AT)
			end
		end
	end
end

function Life.destroy(self: Life)
	self.folder:Destroy()
end

---------------------------------------------------------------------------------------------------
-- Every Speedway in the player's town.

local function smallScreen(): boolean
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 700
end

-- Where a building model TownView drew stands: its middle on the ground, turned as it was turned.
local function frameOf(model: Model): CFrame?
	local hit = model:FindFirstChild("Hit") :: BasePart?
	local turn = model:GetAttribute("Turn")
	if not hit or type(turn) ~= "number" then
		return nil
	end
	local p = hit.CFrame.Position
	return CFrame.new(p.X, p.Y - hit.Size.Y / 2, p.Z) * CFrame.Angles(0, turn * math.pi / 2, 0)
end

-- Keeps a Life for every Speedway in `town` (its Buildings folder); returns a function that looks
-- for new, moved or upgraded ones, and one that moves them all on (each frame).
function SpeedwayLife.attach(town: Folder, parent: Instance?): (() -> (), (dt: number) -> ())
	local buildings = town:WaitForChild("Buildings")
	local holder = Instance.new("Folder")
	holder.Name = "Speedways"
	holder.Parent = parent or workspace
	local lives: { [string]: { life: Life, key: string } } = {}
	local small = smallScreen()

	local function scan()
		local seen = {}
		for _, m in buildings:GetChildren() do
			if not m:IsA("Model") or m:GetAttribute("Def") ~= "stadium" then
				continue
			end
			local frame = frameOf(m)
			if not frame then
				continue
			end
			local lvl = (m:GetAttribute("Level") :: number?) or 1
			local key = `{lvl}|{frame}`
			seen[m.Name] = true
			local have = lives[m.Name]
			if have and have.key ~= key then
				have.life:destroy()
				have = nil
			end
			if not have then
				lives[m.Name] = { life = SpeedwayLife.new(holder, frame, lvl, small), key = key }
			end
		end
		for uid, have in lives do
			if not seen[uid] then
				have.life:destroy()
				lives[uid] = nil
			end
		end
	end

	-- Seconds since the town was first drawn (the web's clock.elapsedTime).
	local time = 0
	local function step(dt: number)
		time += dt
		local list: { BasePart } = {}
		local cfs: { CFrame } = {}
		local cam = workspace.CurrentCamera
		for _, have in lives do
			local life = have.life
			if cam and (cam.CFrame.Position - life.frame.Position).Magnitude > FAR then
				continue
			end
			life:step(time, dt, list, cfs)
		end
		if #list > 0 then
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	return scan, step
end

function SpeedwayLife.start()
	local Town = require(script.Parent.Town) :: any
	local Remote = require(script.Parent.Remote) :: any
	task.spawn(function()
		local folder: Folder? = nil
		while not folder do
			folder = Town.folder()
			if not folder then
				task.wait(0.5)
			end
		end
		local scan, step = SpeedwayLife.attach(folder :: Folder)
		-- The server redraws a building when it's built, moved or upgraded; buildings also stream in
		-- and out, so look again every second as well as on every change.
		Remote.changed:Connect(function()
			task.defer(scan)
		end)
		scan()
		local wait = 0
		RunService.RenderStepped:Connect(function(dt)
			wait -= dt
			if wait <= 0 then
				wait = 1
				scan()
			end
			step(math.min(dt, 0.1))
		end)
	end)
end

return SpeedwayLife
