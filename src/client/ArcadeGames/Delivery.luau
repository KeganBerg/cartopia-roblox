--!strict
-- Delivery Dash, as the web game's DeliveryGame (ui/ArcadeMore.tsx) and DeliveryScene
-- (scene/DeliveryScene.tsx): a grid town of shop and house blocks seen from above. Pick up at
-- the glowing shop spot, drop at the glowing house, as many as you can before the clock runs out;
-- a hot drop (inside the hot-pizza window) adds a few seconds, bumping traffic costs some. Every
-- number is the web's, from Shared.Game.arcadeMore (converted from game/arcadeMore.ts), and the
-- car drives against the kerbs with Shared.Game.collide (game/collide.ts).
--
-- play(ctx) draws the scene at ctx.origin, runs the countdown and the round, and calls
-- ctx.finish(drops, { drops, line }) at the end (or ctx.finish(0, { quit = true }) on the X).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local M = require(Game.arcadeMore) :: any
local collide = require(Game.collide) :: any
local data = require(Game.data) :: any
local Builder = require(Shared.Models.Builder) :: any
local Paint = require(Shared.Models.Paint) :: any
local Mods = require(Shared.Models.Mods) :: any
local Panels = require(Shared.Models.Panels) :: any
local Trim = require(Shared.Models.Trim) :: any
local Skins = require(Shared.Models.Skins) :: any
local Pictures = require(Shared.Pictures) :: any
local Catalog = require(Shared.Models.Catalog) :: any
local Ui = require(script.Parent.Parent.Ui)

local Delivery = { id = "delivery" }

local S = 10 -- studs per web unit, as every converted model
local LEN = 1.5 -- the cars' length (web units)
local MAX_FWD = 8.5
local MAX_REV = 3
local WALK = 0.9 -- sidewalk inside each block's edge
local SPARKS = 14
local TRAFFIC = 7
local TRAFFIC_R = 0.62 -- a traffic car as a circle, for the bump test
local K = 1.15 -- ArcadeScenery's model scale
local FOV = 50 -- ArcadeMore DASH_CAM

local BLOCK, STREET, GRID, TOWN = M.BLOCK, M.STREET, M.GRID, M.TOWN

-- The player's own shop types stand in the web's shop blocks once they have four; the hub
-- doesn't pass the town, so this is the web's standard high street (ArcadeScenery FALLBACK).
local POOL = { "pizza", "donut", "burger", "diner", "motel", "carwash", "tires", "gas", "bowling", "icecream", "coffee", "tacos" }

local SHIRTS = { "#e53935", "#fafafa", "#1e88e5", "#fdd835", "#43a047", "#ff7043", "#8e24aa", "#26c6da" }
local PANTS = { "#37474f", "#1565c0", "#4e342e", "#263238", "#5d4037", "#283593" }
local SKIN = { "#f1c27d", "#e0ac69", "#c68642", "#8d5524", "#ffdbac" }

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- One of the web game's ground textures over a part's top (the town's lawn image).
local function grass(p: BasePart, span: number)
	local t = (Catalog.TEXTURES or {}).grass
	if not t or t.image == 0 then
		return
	end
	local tex = Instance.new("Texture")
	tex.Face = Enum.NormalId.Top
	Pictures.set(tex, "Texture", t.image)
	tex.StudsPerTileU = span
	tex.StudsPerTileV = span
	tex:SetAttribute("Image", t.name)
	tex.Parent = p
end

-- A model from the client's library (what the server shares), else built from the catalog.
local function library(kind: string, id: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local folder = lib and lib:FindFirstChild(kind)
	local src = folder and folder:FindFirstChild(id)
	local m: Model?
	if src then
		m = src:Clone() :: Model
	elseif kind == "Buildings" then
		local name = Builder.buildingName(id, 1)
		m = name and Builder.build(name)
	else
		m = Builder.build(id)
	end
	if m then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
			end
		end
	end
	return m
end

-- Scales a model about its pivot (Model:ScaleTo), keeping its pivot where it is.
local function scaleModel(m: Model, k: number)
	m:ScaleTo(m:GetScale() * k)
end

-- The car's footprint on the ground as drawn, in web units in its own frame (scene/footprint.tsx).
local function footprintOf(m: Model): { w: number, l: number, cz: number }
	local pivot = m:GetPivot()
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.9 then
			local rel = pivot:ToObjectSpace(d.CFrame)
			local h = d.Size / 2
			for _, c in { Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, -1) } do
				local w = rel * (h * c)
				lo = lo:Min(w)
				hi = hi:Max(w)
			end
		end
	end
	if lo.X == math.huge then
		return { w = LEN * 0.5, l = LEN, cz = 0, top = 0.5 } :: any
	end
	return { w = (hi.X - lo.X) / S, l = (hi.Z - lo.Z) / S, cz = (hi.Z + lo.Z) / 2 / S, top = hi.Y / S } :: any
end

-- The player's car as the town draws it (paint, panels, trim, hat, mods, skin), LEN long.
local function playerCar(car: any): Model
	local m = library("Cars", car.model) or Instance.new("Model")
	Paint.apply(m, Paint.jobOf(car), library("Stripes", car.model))
	Panels.apply(m, car.model, car.panels, car.finish, Builder.build)
	Trim.apply(m, car.model, car.trim, car.color)
	Paint.wearHat(m, car.model, car.hat, Builder.build)
	Mods.fit(m, car.model, car.mods, Builder.build)
	Skins.apply(m, car.skin, car.modSkin)
	return m
end

-- How long the car is as built (studs), for scaling it to LEN.
local function lengthOf(m: Model): number
	local _, size = m:GetBoundingBox()
	return math.max(1, size.Z)
end

-- Town traffic: everyday cars up and down the streets, each on its own road and lane.
type Mover = { axis: string, line: number, dir: number, pos: number, speed: number }
local function movers(): { Mover }
	local out = {}
	for i = 0, TRAFFIC - 1 do
		table.insert(out, {
			axis = if i % 2 == 1 then "x" else "z",
			line = M.roadLine((i * 3 + 1) % (GRID + 1)),
			dir = if i % 3 ~= 0 then 1 else -1,
			pos = -TOWN / 2 + ((i * 17) % TOWN),
			speed = 3.2 + (i % 4) * 0.5,
		})
	end
	return out
end
local function trafficLooks(): { { model: string, color: string } }
	local bodies = { sedan = true, compact = true, van = true, suv = true, hatch = true, wagon = true, ev = true }
	local pool = {}
	for _, c in data.CARS do
		if not c.parked and not data.isBike(c.body) and bodies[c.body] then
			table.insert(pool, c)
		end
	end
	local out = {}
	for i = 0, TRAFFIC - 1 do
		local c = pool[(i * 5 + 2) % #pool + 1]
		table.insert(out, { model = c.id, color = c.colors[i % #c.colors + 1] })
	end
	return out
end
-- Where a mover is: on its road, kept to the right-hand lane for its direction.
local function moverAt(m: Mover): (number, number, number)
	local lane = 0.72 * m.dir
	if m.axis == "x" then
		return m.pos, m.line + lane, if m.dir > 0 then math.pi / 2 else -math.pi / 2
	end
	return m.line - lane, m.pos, if m.dir > 0 then 0 else math.pi
end

-- Shop blocks and house blocks alternate like a checkerboard.
local function isShops(bx: number, bz: number): boolean
	return (bx + bz) % 2 == 0
end
type Spot = { bx: number, bz: number, side: number, x: number, z: number }
local SHOP_SPOTS: { Spot } = {}
local HOUSE_SPOTS: { Spot } = {}
for bx = 0, GRID - 1 do
	for bz = 0, GRID - 1 do
		for _, side in { 0, 2 } do
			local at = M.kerbSpot(bx, bz, side)
			table.insert(if isShops(bx, bz) then SHOP_SPOTS else HOUSE_SPOTS, { bx = bx, bz = bz, side = side, x = at[1], z = at[2] })
		end
	end
end

local function pickFar(list: { Spot }, x: number, z: number, rng: Random): Spot
	local ok = {}
	for _, s in list do
		local d = math.sqrt((s.x - x) ^ 2 + (s.z - z) ^ 2)
		if d > 7 and d < 24 then
			table.insert(ok, s)
		end
	end
	local from = if #ok > 0 then ok else list
	return from[rng:NextInteger(1, #from)]
end

-- ── The town ─────────────────────────────────────────────────────────────────────────────────

-- One block: kerbed sidewalk round a lawn, two buildings facing each of its north and south
-- streets, trees and lamps down the east and west sides, a hydrant or a bin.
local function block(into: Instance, at: (number, number, number) -> CFrame, bx: number, bz: number)
	local cx, cz = M.blockCentre(bx), M.blockCentre(bz)
	local function w(x: number, y: number, z: number): CFrame
		return at(cx + x, y, cz + z)
	end
	local lawn = part({ Name = "Lawn", Size = Vector3.new(BLOCK - WALK * 2, 0.12, BLOCK - WALK * 2) * S, CFrame = w(0, 0.061, 0), Color = hex(Catalog.GRASS or "#a9b552") }, into)
	grass(lawn, 17)
	for i = 0, 3 do
		local a = i * math.pi / 2
		local turn = CFrame.Angles(0, a, 0)
		part({ Name = "Walk", Size = Vector3.new(BLOCK, 0.12, WALK) * S, CFrame = w(0, 0, 0) * turn * CFrame.new(0, 0.06 * S, (BLOCK / 2 - WALK / 2) * S), Color = hex("#eadfc8"), Material = Enum.Material.Pavement }, into)
		part({ Name = "Kerb", Size = Vector3.new(BLOCK, 0.13, 0.08) * S, CFrame = w(0, 0, 0) * turn * CFrame.new(0, 0.065 * S, (BLOCK / 2 - 0.04) * S), Color = hex("#cfd2d6") }, into)
	end
	local shops = isShops(bx, bz)
	for k = 0, 3 do
		local id = if shops then POOL[(bx * 5 + bz * 3 + k) % #POOL + 1] else "house"
		local def = data.buildingDef(id)
		local south = k >= 2
		local x = (if k % 2 == 1 then 1 else -1) * 1.4
		local fit = math.min(1, 2.6 / (def.w * data.TILE * K))
		local depth = def.h * data.TILE * K * fit
		local z = (if south then 1 else -1) * (BLOCK / 2 - WALK - depth / 2 - 0.05)
		local b = library("Buildings", id)
		if b then
			scaleModel(b, K * fit)
			b:PivotTo(w(x, 0.12, z) * CFrame.Angles(0, if south then 0 else math.pi, 0))
			b.Parent = into
		end
	end
	for _, sd in { -1, 1 } do
		for _, z in { -1.6, 1.6 } do
			local tree = library("Buildings", if (bx + bz + (if z > 0 then 1 else 0)) % 3 == 0 then "pine" else "tree")
			if tree then
				scaleModel(tree, K * 0.7)
				tree:PivotTo(w(sd * (BLOCK / 2 - WALK / 2), 0.12, z))
				tree.Parent = into
			end
		end
		-- A street lamp (ArcadeScenery Lamp), its arm out over the road.
		local base = w(sd * (BLOCK / 2 - 0.3), 0, sd * 2.6) * CFrame.Angles(0, if sd > 0 then -math.pi / 2 else math.pi / 2, 0)
		local pole = hex("#37474f")
		part({ Name = "LampPole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8 * K, 0.1 * K, 0.1 * K) * S, CFrame = base * CFrame.new(0, 0.9 * K * S, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = pole }, into)
		part({ Name = "LampArm", Size = Vector3.new(0.05, 0.04, 0.5) * K * S, CFrame = base * CFrame.new(0, 1.78 * K * S, 0.25 * K * S), Color = pole }, into)
		part({ Name = "LampBulb", Size = Vector3.new(0.16, 0.07, 0.22) * K * S, CFrame = base * CFrame.new(0, 1.72 * K * S, 0.48 * K * S), Color = hex("#fff3c4"), Material = Enum.Material.Neon }, into)
	end
	if (bx + bz) % 2 == 1 then
		part({ Name = "Hydrant", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.26, 0.14, 0.14) * K * S, CFrame = w(BLOCK / 2 - 0.45, 0.12 + 0.13 * K, -0.9) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#e53935") }, into)
	else
		part({ Name = "Bin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.34, 0.21, 0.21) * K * S, CFrame = w(-BLOCK / 2 + 0.45, 0.12 + 0.17 * K, 0.9) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#2e7d32") }, into)
	end
end

local function town(into: Instance, at: (number, number, number) -> CFrame)
	-- Grass beyond the town, then the asphalt (layers kept well apart for Roblox's far camera).
	local outer = part({ Name = "Grass", Size = Vector3.new(TOWN + 60, 0.2, TOWN + 60) * S, CFrame = at(0, -0.15, 0), Color = hex(Catalog.GRASS or "#a9b552") }, into)
	grass(outer, 34)
	part({ Name = "Asphalt", Size = Vector3.new(TOWN, 0.1, TOWN) * S, CFrame = at(0, -0.05, 0), Color = hex("#9ba1a8"), Material = Enum.Material.Asphalt }, into)
	local paint = function(x: number, z: number, w: number, l: number, color: string)
		part({ Name = "Paint", Size = Vector3.new(w * S, 0.3, l * S), CFrame = at(x, 0, z) * CFrame.new(0, 0.15, 0), Color = hex(color) }, into)
	end
	-- Centre dashes on every street and zebras at every crossing.
	for i = 0, GRID do
		local c = M.roadLine(i)
		for b = 0, GRID - 1 do
			local mid = M.blockCentre(b)
			for k = -2, 2 do
				paint(mid + k * 1.3, c, 0.7, 0.09, "#ffd54f")
				paint(c, mid + k * 1.3, 0.09, 0.7, "#ffd54f")
			end
		end
	end
	for i = 0, GRID do
		for j = 0, GRID do
			local cx, cz = M.roadLine(i), M.roadLine(j)
			for _, sd in { -1, 1 } do
				for n = 0, 4 do
					paint(cx - 1.1 + n * 0.55, cz + sd * (STREET / 2 + 0.45), 0.28, 0.7, "#fafafa")
				end
			end
		end
	end
	for bx = 0, GRID - 1 do
		for bz = 0, GRID - 1 do
			block(into, at, bx, bz)
		end
	end
	-- A ring of trees round the edge of town.
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		local r = TOWN / 2 + 3 + (i % 3)
		local tree = library("Buildings", if i % 2 == 1 then "pine" else "tree")
		if tree then
			scaleModel(tree, K)
			tree:PivotTo(at(math.cos(a) * r, 0, math.sin(a) * r))
			tree.Parent = into
		end
	end
	-- People on the sidewalks (ArcadeScenery Crowd, drawn simply: legs, body, head).
	for i = 0, 39 do
		local bx, bz = i % GRID, math.floor(i / GRID) % GRID
		local side = i % 4
		local along = ((i * 37) % 10) / 10 - 0.5
		local off = BLOCK / 2 - WALK / 2
		local d = ({ { along * 5, -off }, { off, along * 5 }, { along * 5, off }, { -off, along * 5 } })[side + 1]
		local size = 1.3 * 0.9
		local base = at(M.blockCentre(bx) + d[1], 0.12, M.blockCentre(bz) + d[2]) * CFrame.Angles(0, side * math.pi / 2 + math.pi, 0)
		local k = (i * 2654435761) % 4294967296
		local hip = 0.24 * size
		part({ Name = "Legs", Size = Vector3.new(0.14, 0.24, 0.07) * size * S, CFrame = base * CFrame.new(0, hip / 2 * S, 0), Color = hex(PANTS[(k // 8) % #PANTS + 1]) }, into)
		part({ Name = "Body", Size = Vector3.new(0.17, 0.3, 0.15) * size * S, CFrame = base * CFrame.new(0, (hip + 0.15 * size) * S, 0), Color = hex(SHIRTS[k % #SHIRTS + 1]) }, into)
		part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.16 * size * S, CFrame = base * CFrame.new(0, (hip + 0.36 * size) * S, 0), Color = hex(SKIN[(k // 64) % #SKIN + 1]) }, into)
	end
end

-- ── The HUD ──────────────────────────────────────────────────────────────────────────────────

-- A dark pill like the web's .arc-hud span.
local function pill(parent: Instance, order: number, w: number, h: number): Frame
	return Ui.new("Frame", { Name = "Pill", LayoutOrder = order, Size = UDim2.fromOffset(w, h), BackgroundColor3 = hex("#1b1f24"), BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = parent }, { Ui.round() })
end

local function label(parent: Instance, size: number, props: { [string]: any }?): TextLabel
	local p: { [string]: any } = { Size = UDim2.fromScale(1, 1), TextSize = size, Text = "", TextColor3 = Ui.WHITE, Parent = parent }
	for k, v in (props or {}) :: { [string]: any } do
		p[k] = v
	end
	return Ui.text(p)
end

-- What the hold-to-press buttons and the steer slider need from one input.
local function isPress(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

function Delivery.play(ctx: any)
	local origin: Vector3 = ctx.origin
	local rng = Random.new(ctx.seed or 1)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(origin + Vector3.new(x, y, z) * S)
	end

	local world = Instance.new("Folder")
	world.Name = "DeliveryDash"
	town(world, at)

	-- The player's car, LEN long, with the pizza box on its roof while an order is on board.
	local carModel = playerCar(ctx.car)
	scaleModel(carModel, LEN * S / lengthOf(carModel))
	local foot = footprintOf(carModel) :: any
	carModel.Name = "Player"
	carModel.Parent = world
	local boxParts = {
		part({ Name = "PizzaBox", Size = Vector3.new(0.46, 0.1, 0.46) * S, Color = hex("#d7a86e"), Transparency = 1 }, world),
		part({ Name = "PizzaLabel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, 0.28, 0.28) * S, Color = hex("#e53935"), Transparency = 1 }, world),
	}
	local shadowPart = part({ Name = "CarShadow", Size = Vector3.new(foot.w * 1.2, 0.02, LEN * 1.1) * S, Color = Ui.BLACK, Transparency = 0.7 }, world)

	local looks = trafficLooks()
	local trafficModels: { Model } = {}
	for i, look in looks do
		local m = library("Cars", look.model) or Instance.new("Model")
		Builder.paint(m, hex(look.color))
		scaleModel(m, LEN * S / lengthOf(m))
		m.Name = `Traffic{i}`
		m.Parent = world
		trafficModels[i] = m
	end

	-- The beacon over the spot to drive to: a glowing column and a ring painted on the road.
	local beam = part({ Name = "Beam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 1.5, 1.5) * S, Color = hex("#ffb300"), Material = Enum.Material.Neon, Transparency = 0.75 }, world)
	local ringParts: { BasePart } = {}
	local RING = 32
	local rr = M.DROP_R - M.DROP_LINE / 2
	for i = 1, RING do
		ringParts[i] = part({ Name = "Ring", Size = Vector3.new(M.DROP_LINE * S, 0.3, 2 * math.pi * rr / RING * S * 1.08), Color = Ui.WHITE, Transparency = 0.2 }, world)
	end
	-- The arrow by the car that points at it: a flat white triangle.
	local arrowL = part({ Name = "Arrow", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.05 * S, 0.6 * S, 0.24 * S), Color = Ui.WHITE, Material = Enum.Material.Neon }, world)
	local arrowR = part({ Name = "Arrow", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.05 * S, 0.6 * S, 0.24 * S), Color = Ui.WHITE, Material = Enum.Material.Neon }, world)
	local sparkParts: { BasePart } = {}
	for i = 1, SPARKS do
		sparkParts[i] = part({ Name = "Spark", Size = Vector3.one * 0.07 * S, Color = hex("#ffcc66"), Material = Enum.Material.Neon, Transparency = 1 }, world)
	end
	world.Parent = workspace

	-- ── State, as DeliveryScene's st ──
	local start = { x = M.blockCentre(1) + BLOCK / 2 + STREET / 2, z = M.blockCentre(2), h = math.pi }
	local s = {
		pose = { x = start.x, z = start.z, h = start.h },
		v = 0, t = 0, left = M.DASH_TIME, drops = 0, carrying = false, target = pickFar(SHOP_SPOTS, start.x, start.z, rng),
		cool = 0, done = false, hotUntil = 0, hotFor = 1, streak = 0, hitCool = 0,
		movers = movers(),
		jolt = 0, pitch = 0, roll = 0, joltT = 0, shake = 0,
		sparks = {} :: { any },
		running = false, clock = 0, count = 3, countT = 0, endT = 0,
	}
	for i = 1, SPARKS do
		s.sparks[i] = { x = 0, y = 0, z = 0, vx = 0, vy = 0, vz = 0, age = 1 }
	end
	local input = { steer = 0, gas = 0, brake = 0, keyGas = false, keyBrake = false, left = false, right = false, touchBrake = false, thumb = 0 }
	ctx.input = input -- for the preview harness (tools/emulate/arcade-delstunt.luau)
	ctx.state = s

	-- ── Camera: the round takes it, and gives it back at the end ──
	local cam = workspace.CurrentCamera
	local old = { type = cam.CameraType, cf = cam.CFrame, fov = cam.FieldOfView }
	local TownCamera = (function()
		local ok, m = pcall(require, (script.Parent.Parent :: any).TownCamera)
		return if ok then m else nil
	end)() :: any
	if TownCamera then
		TownCamera.setPaused(true)
	end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FOV
	local camPos: Vector3? = nil

	-- ── HUD ──
	local gui: ScreenGui = ctx.gui
	local view = cam.ViewportSize
	local tall = view.Y > view.X
	local touch = UserInputService.TouchEnabled
	local insetTop, insetLeft, insetRight = 0, 0, 0
	pcall(function()
		local r = GuiService.TopbarInset
		if r.Height > 0 then
			insetTop, insetLeft, insetRight = r.Min.Y, r.Min.X, view.X - r.Max.X
		end
	end)
	local root = Ui.new("Frame", { Name = "Delivery", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	-- The top bar (.rf-top): the game's name and the X.
	local top = Ui.new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 64 + insetTop), BackgroundColor3 = hex("#0a1e3c"), BorderSizePixel = 0, Parent = root })
	Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }), Parent = top })
	Ui.text({ Name = "Title", Text = "🍕 Delivery Dash", TextSize = if tall then 18 else 20, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(math.max(14, insetLeft + 4), insetTop + 8), Size = UDim2.new(1, -120, 0, 36), Shadow = 2, ShadowTransparency = 0.65, ShadowColor = Ui.BLACK, Parent = root })
	local quitting = false
	local finish: (boolean) -> ()
	Ui.closeButton({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -math.max(12, insetRight + 4), 0, insetTop + 8), Size = UDim2.fromOffset(40, 40), Parent = root }, function()
		if not quitting then
			quitting = true
			finish(true)
		end
	end)
	-- The pills (.arc-hud): the clock, what to do next, drops so far.
	local hudTop = math.max(if tall then 50 else 50, insetTop + 50)
	local row = Ui.new("Frame", { Name = "Hud", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, hudTop), Size = UDim2.new(1, -16, 0, 36), BackgroundTransparency = 1, Parent = root }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local clockPill = pill(row, 1, 100, 36)
	local clockText = label(clockPill, 24)
	local spotPill = pill(row, 2, 118, 30)
	local spotText = label(spotPill, 18)
	local dropPill = pill(row, 3, 62, 30)
	local dropText = label(dropPill, 18)
	-- The hot-pizza timer under the pills (.dash-hot).
	local hot = Ui.new("Frame", { Name = "Hot", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, hudTop + 44), Size = UDim2.fromOffset(math.min(200, view.X * 0.5) + 30, 22), BackgroundTransparency = 1, Visible = false, Parent = root })
	Ui.text({ Text = "🔥", TextSize = 20, Size = UDim2.fromOffset(24, 22), Parent = hot })
	local hotBar = Ui.new("Frame", { Position = UDim2.new(0, 30, 0.5, -6), Size = UDim2.new(1, -30, 0, 12), BackgroundColor3 = hex("#1b1f24"), BackgroundTransparency = 0.5, BorderSizePixel = 0, ClipsDescendants = true, Parent = hot }, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Ui.stroke(2, Ui.WHITE),
	})
	local hotFill = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = hotBar }, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0, 6) }),
		Ui.new("UIGradient", { Color = Ui.seq("#ff3d00", "#ffab00") }),
	})
	-- The pop-up line for drops and bumps (.chase-pop).
	local popText = Ui.text({ Name = "Pop", Text = "", TextSize = 30, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.28), Size = UDim2.new(1, 0, 0, 44), Shadow = 3, ShadowTransparency = 0.55, ShadowColor = Ui.BLACK, Parent = root })
	popText.Visible = false
	local popScale = Ui.new("UIScale", { Parent = popText })
	local popAge = 99
	local function pop(text: string, kind: string)
		Ui.setText(popText, text)
		Ui.setColor(popText, hex(if kind == "hit" then "#ff8a80" elseif kind == "hot" then "#ff9e40" else "#ffd54f"))
		popText.TextSize = if kind == "hot" then 34 else 30
		local face = popText:FindFirstChild("Face") :: TextLabel?
		if face then
			face.TextSize = popText.TextSize
		end
		popAge = 0
	end
	-- The countdown (ArcadeBits Countdown).
	local countText = Ui.text({ Name = "Count", Text = "3", TextSize = if view.Y < 500 then 72 else 110, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.new(1, 0, 0, 120), Shadow = 5, ShadowTransparency = 0.65, ShadowColor = Ui.BLACK, Parent = root })

	-- Touch: a BRAKE button and the steer slider (DriveControls TouchDrive, gas always on);
	-- a keyboard drives with WASD or the arrows (useDriveKeys).
	local controls = Ui.new("Frame", { Name = "Controls", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = root })
	local conns: { RBXScriptConnection } = {}
	local stickOwner: InputObject? = nil
	local stickX0 = 0
	local stick: Frame? = nil
	local knob: Frame? = nil
	local hint: Frame? = nil
	if touch then
		local zone = Ui.new("TextButton", {
			Name = "Steer", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Active = true,
			AnchorPoint = if tall then Vector2.new(0.5, 1) else Vector2.new(0, 1),
			Position = if tall then UDim2.new(0.5, 0, 1, 0) else UDim2.new(0, 0, 1, 0),
			Size = if tall then UDim2.new(1, -16, 0, math.max(150, view.Y * 0.3)) else UDim2.new(0.46, 0, 0.62, 0),
			Parent = controls,
		})
		local h = Ui.new("Frame", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = if tall then UDim2.new(0.5, 0, 1, -26) else UDim2.new(0, 110, 1, -40), Size = UDim2.fromOffset(150, 32), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.58, Parent = zone }, { Ui.round() })
		Ui.text({ Text = "◀ slide to steer ▶", Body = true, TextSize = 13, Size = UDim2.fromScale(1, 1), TextTransparency = 0.1, Parent = h })
		hint = h
		local st = Ui.new("Frame", { Name = "Stick", Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Visible = false, Parent = zone })
		Ui.new("Frame", { Name = "Track", Position = UDim2.fromOffset(-76, -12), Size = UDim2.fromOffset(152, 24), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.62, Parent = st }, { Ui.new("UICorner", { CornerRadius = UDim.new(0, 12) }), Ui.stroke(2, Ui.WHITE, 0.55) })
		local kn = Ui.new("Frame", { Name = "Knob", Position = UDim2.fromOffset(-30, -30), Size = UDim2.fromOffset(60, 60), BackgroundColor3 = Ui.WHITE, Parent = st }, { Ui.round(), Ui.new("UIGradient", { Color = Ui.seq("#ffffff", "#cfd8dc"), Rotation = 60 }) })
		stick, knob = st, kn
		table.insert(conns, zone.InputBegan:Connect(function(io: InputObject)
			if stickOwner or not isPress(io) then
				return
			end
			stickOwner = io
			stickX0 = io.Position.X
			st.Position = UDim2.fromOffset(io.Position.X - zone.AbsolutePosition.X, io.Position.Y - zone.AbsolutePosition.Y)
			st.Visible = true
			h.Visible = false
		end))
		-- The brake (.dc-brake), above the slider on a tall screen, bottom right on a wide one.
		local brake = Ui.new("TextButton", {
			Name = "Brake", Text = "BRAKE", TextSize = 13, FontFace = Ui.DISPLAY, TextColor3 = Ui.WHITE, AutoButtonColor = false,
			BackgroundColor3 = hex("#b71c1c"), BackgroundTransparency = 0.35,
			AnchorPoint = Vector2.new(if tall then 0 else 1, 1),
			Position = if tall then UDim2.new(0, 16, 1, -(math.max(150, view.Y * 0.3) - 40)) else UDim2.new(1, -130, 1, -18),
			Size = UDim2.fromOffset(80, 80), Parent = controls,
		}, { Ui.round(), Ui.stroke(3, Ui.WHITE, 0.3) })
		table.insert(conns, brake.InputBegan:Connect(function(io: InputObject)
			if isPress(io) then
				input.touchBrake = true
				brake.BackgroundTransparency = 0
				brake.BackgroundColor3 = hex("#d50000")
			end
		end))
		table.insert(conns, brake.InputEnded:Connect(function(io: InputObject)
			if isPress(io) then
				input.touchBrake = false
				brake.BackgroundTransparency = 0.35
				brake.BackgroundColor3 = hex("#b71c1c")
			end
		end))
	else
		-- A short line of key hints for a PC (.dc-keys).
		local keys = Ui.new("Frame", { Name = "Keys", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(170, 30), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.55, Parent = controls }, { Ui.round() })
		Ui.text({ Text = "W A S D or arrows", Body = true, TextSize = 12, Size = UDim2.fromScale(1, 1), Parent = keys })
	end
	table.insert(conns, UserInputService.InputChanged:Connect(function(io: InputObject)
		if io == stickOwner and stick and knob then
			-- thumbSteer with ARCADE_FEEL (range 56, no dead zone, curve 1), clamped to the screen.
			local range = 56
			local leftRoom = math.max(20, math.min(range, stickX0 - 14))
			local rightRoom = math.max(20, math.min(range, view.X - stickX0 - 14))
			local dx = math.clamp(io.Position.X - stickX0, -leftRoom, rightRoom)
			local side = if dx < 0 then leftRoom else rightRoom
			local a = math.abs(dx * range / side)
			input.thumb = -math.sign(dx) * math.min(1, a / range)
			knob.Position = UDim2.fromOffset(-30 + dx, -30)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(io: InputObject)
		if io == stickOwner then
			stickOwner = nil
			input.thumb = 0
			if stick then
				stick.Visible = false
			end
			if knob then
				knob.Position = UDim2.fromOffset(-30, -30)
			end
			if hint then
				hint.Visible = true
			end
		end
	end))
	local KEYS: { [Enum.KeyCode]: string } = {
		[Enum.KeyCode.Left] = "left", [Enum.KeyCode.A] = "left", [Enum.KeyCode.Right] = "right", [Enum.KeyCode.D] = "right",
		[Enum.KeyCode.Up] = "keyGas", [Enum.KeyCode.W] = "keyGas", [Enum.KeyCode.Down] = "keyBrake", [Enum.KeyCode.S] = "keyBrake",
	}
	table.insert(conns, UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
		local k = KEYS[io.KeyCode]
		if k and not processed then -- not while typing in chat
			(input :: any)[k] = true
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(io: InputObject)
		local k = KEYS[io.KeyCode]
		if k then
			(input :: any)[k] = false
		end
	end))

	-- ── The end ──
	local finished = false
	finish = function(quit: boolean)
		if finished then
			return
		end
		finished = true
		RunService:UnbindFromRenderStep("ArcadeDelivery")
		for _, c in conns do
			c:Disconnect()
		end
		world:Destroy()
		root:Destroy()
		cam.CameraType = old.type
		cam.CFrame = old.cf
		cam.FieldOfView = old.fov
		if TownCamera then
			TownCamera.setPaused(false)
		end
		if quit then
			ctx.finish(0, { quit = true })
		else
			ctx.finish(s.drops, { drops = s.drops, line = `🍕 {s.drops} delivered` })
		end
	end
	ctx.stop = function()
		finish(true)
	end

	local function placeArrow(ax: number, az: number, a: number, y: number, show: boolean)
		local base = at(ax, y, az) * CFrame.Angles(0, a, 0)
		-- Two right-angled wedges make the triangle, its tip ahead (+z).
		arrowL.CFrame = base * CFrame.new(-0.12 * S, 0, 0) * CFrame.fromMatrix(Vector3.zero, Vector3.new(0, 1, 0), Vector3.new(0, 0, 1), Vector3.new(1, 0, 0))
		arrowR.CFrame = base * CFrame.new(0.12 * S, 0, 0) * CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0))
		arrowL.Transparency = if show then 0 else 1
		arrowR.Transparency = if show then 0 else 1
	end

	local function frame(rawDt: number)
		local dt = math.min(rawDt, 1 / 20)
		s.clock += dt
		local t = s.clock
		-- 3, 2, 1 (650 ms each), then GO! for 600 ms, the round live from GO.
		if s.count >= 0 then
			s.countT += dt
			local step = if s.count > 0 then 0.65 else 0.6
			if s.countT >= step then
				s.countT -= step
				s.count -= 1
				if s.count == 0 then
					s.running = true
					controls.Visible = true
				end
			end
			countText.Visible = s.count >= 0
			Ui.setText(countText, if s.count == 0 then "GO!" else tostring(s.count))
		end
		local live = s.running and not s.done
		if live then
			s.t += dt
			s.left -= dt
		end
		input.steer = if stickOwner then input.thumb else (if input.left then 1 else 0) - (if input.right then 1 else 0)
		input.brake = if input.keyBrake or input.touchBrake then 1 else 0
		input.gas = if input.keyGas or (touch and input.brake == 0) then 1 else 0
		local pedal = if live then input.gas - input.brake else 0
		if pedal > 0 then
			s.v = math.min(MAX_FWD, s.v + (if s.v < 0 then 14 else 6) * dt)
		elseif pedal < 0 then
			s.v = math.max(-MAX_REV, s.v - (if s.v > 0 then 14 else 6) * dt)
		else
			s.v = math.sign(s.v) * math.max(0, math.abs(s.v) - 5 * dt)
		end
		s.cool = math.max(0, s.cool - dt)
		if s.v ~= 0 then
			local steer = if live then input.steer else 0
			local h = s.pose.h + steer * 2.4 * math.sign(s.v) * math.min(1, math.abs(s.v) / 2.5) * dt
			local nxt = { x = s.pose.x + math.sin(h) * s.v * dt, z = s.pose.z + math.cos(h) * s.v * dt, h = h }
			-- The car's own measured box against the kerbs: scrape along them, rock and spark on a knock.
			local r = collide.step(s.pose, s.v, nxt, foot, M.TOWN_SOLIDS)
			s.pose = r.pose
			s.v = r.v
			if r.impact > 0.4 then
				local hard = r.impact > 2.2
				if s.cool <= 0 then
					s.cool = if hard then 0.4 else 0.3
				end
				local c, sn = math.cos(s.pose.h), math.sin(s.pose.h)
				local along, across = r.nx * sn + r.nz * c, r.nx * c - r.nz * sn
				local jolt = math.min(1, r.impact / 6)
				if jolt > s.jolt * math.exp(-s.joltT * 4) then
					s.jolt, s.pitch, s.roll, s.joltT = jolt, along, across, 0
					if hard then
						s.shake = math.max(s.shake, 0.25 * s.jolt + 0.1)
					end
				end
				-- Sparks where the car meets the kerb.
				local b = collide.carBox(s.pose, foot)
				local ext = (math.abs(across) * b.w + math.abs(along) * b.l) / 2
				local px, pz = b.x - r.nx * ext, b.z - r.nz * ext
				local n = math.min(4, math.ceil(r.impact))
				local made = 0
				for _, p in s.sparks do
					if made >= n then
						break
					end
					if p.age >= 1 then
						local sp = 1.5 + rng:NextNumber() * 2.5
						p.x, p.y, p.z = px, 0.15, pz
						p.vx = r.nx * sp + (rng:NextNumber() - 0.5) * 2
						p.vy = 1 + rng:NextNumber() * 2
						p.vz = r.nz * sp + (rng:NextNumber() - 0.5) * 2
						p.age = 0
						made += 1
					end
				end
			end
		end
		s.joltT += dt
		s.shake = math.max(0, s.shake - dt)
		-- Traffic rolls along its roads and wraps round town; bumping one costs time.
		s.hitCool = math.max(0, s.hitCool - dt)
		local mine = collide.carBox(s.pose, foot)
		for i, m in s.movers do
			if live then
				m.pos += m.dir * m.speed * M.trafficPace(s.drops) * dt
				if m.pos > TOWN / 2 + 2 then
					m.pos -= TOWN + 4
				end
				if m.pos < -TOWN / 2 - 2 then
					m.pos += TOWN + 4
				end
			end
			local x, z, h = moverAt(m)
			trafficModels[i]:PivotTo(at(x, 0, z) * CFrame.Angles(0, h, 0))
			local push = if live then collide.circlePush(mine, { x = x, z = z, r = TRAFFIC_R }) else nil
			if push then
				-- Shoved back out of the other car, and a few seconds lost on the clock.
				s.pose = { x = s.pose.x + push.x, z = s.pose.z + push.z, h = s.pose.h }
				s.v *= -0.3
				if s.hitCool <= 0 then
					s.hitCool = 1
					s.left -= M.TRAFFIC_HIT
					s.shake = 0.3
					pop(`💥 -{M.TRAFFIC_HIT}s`, "hit")
				end
			end
		end
		if live then
			local g = s.target
			if M.atDrop(s.pose.x, s.pose.z, g) then
				if s.carrying then
					local isHot = s.t <= s.hotUntil
					s.streak = if isHot then s.streak + 1 else 0
					local bonus = M.clockBonus(M.dropBonus(isHot, s.streak - 1), s.t, s.left)
					s.drops += 1
					s.left += bonus
					pop(if isHot then `🔥 Hot!{if bonus > 0 then ` +{bonus}s` else ""}{if s.streak > 1 then `  ×{s.streak}` else ""}` else "🍕 +1", if isHot then "hot" else "drop")
					s.carrying = false
					s.target = pickFar(SHOP_SPOTS, s.pose.x, s.pose.z, rng)
				else
					s.carrying = true
					s.target = pickFar(HOUSE_SPOTS, s.pose.x, s.pose.z, rng)
					s.hotFor = M.hotWindow(math.sqrt((s.target.x - s.pose.x) ^ 2 + (s.target.z - s.pose.z) ^ 2), s.drops)
					s.hotUntil = s.t + s.hotFor
				end
			end
			if s.left <= 0 then
				s.left = 0
				s.done = true
			end
		end
		-- The car, rocking away from a knock and settling in a few wobbles.
		local wob = s.jolt * math.exp(-s.joltT * 7) * math.cos(s.joltT * 26)
		local carCf = at(s.pose.x, 0, s.pose.z) * CFrame.Angles(0, s.pose.h, 0)
		carModel:PivotTo(carCf * CFrame.Angles(-s.pitch * wob * 0.16, 0, s.roll * wob * 0.12))
		shadowPart.CFrame = carCf * CFrame.new(0, 0.12, foot.cz * S)
		local deck = foot.top + 0.06
		boxParts[1].CFrame = carCf * CFrame.new(0, (deck + 0.05) * S, -0.1 * S)
		boxParts[2].CFrame = carCf * CFrame.new(0, (deck + 0.101) * S, -0.1 * S) * CFrame.Angles(0, 0, math.pi / 2)
		for _, p in boxParts do
			p.Transparency = if s.carrying then 0 else 1
		end
		for i, p in s.sparks do
			if p.age < 1 then
				p.age += dt * 2.6
				p.vy -= 14 * dt
				p.x += p.vx * dt
				p.y = math.max(0.03, p.y + p.vy * dt)
				p.z += p.vz * dt
			end
			local sp = sparkParts[i]
			sp.Transparency = if p.age < 1 then 0 else 1
			sp.Size = Vector3.one * 0.07 * S * math.max(0.05, 1 - p.age)
			sp.CFrame = at(p.x, p.y, p.z)
		end
		-- The beacon: green over a house with an order on board, amber over the shop.
		local tx, tz = s.target.x, s.target.z
		beam.CFrame = at(tx, 3, tz) * CFrame.Angles(0, 0, math.pi / 2)
		beam.Color = hex(if s.carrying then "#00e676" else "#ffb300")
		beam.Transparency = 1 - (0.22 + math.sin(t * 5) * 0.08)
		for i, p in ringParts do
			local a = (i - 1) / RING * math.pi * 2
			p.CFrame = at(tx + math.cos(a) * rr, 0, tz + math.sin(a) * rr) * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, -a, 0)
		end
		local a = math.atan2(tx - s.pose.x, tz - s.pose.z)
		local far = math.sqrt((tx - s.pose.x) ^ 2 + (tz - s.pose.z) ^ 2) > 3
		placeArrow(s.pose.x + math.sin(a) * 1.4, s.pose.z + math.cos(a) * 1.4, a, 0.9 + math.sin(t * 6) * 0.08, far)
		-- Follow from above and a little behind (north stays up), further out on a narrow screen.
		local back = if tall then 1.35 else 1
		local look = origin + Vector3.new(s.pose.x, 0, s.pose.z - 1) * S
		local eye = origin + Vector3.new(s.pose.x, 12 * back, s.pose.z + 6.5 * back) * S
		camPos = if camPos then camPos:Lerp(eye, math.min(1, dt * 4)) else eye
		local from = camPos :: Vector3
		if s.shake > 0 then
			from += Vector3.new(rng:NextNumber() - 0.5, rng:NextNumber() - 0.5, rng:NextNumber() - 0.5) * s.shake * S
		end
		cam.CFrame = CFrame.lookAt(from, look)

		-- HUD
		Ui.setText(clockText, `⏱ {math.ceil(math.max(0, s.left))}s`)
		local low = s.left < 10
		clockPill.BackgroundColor3 = hex(if low then "#c62828" else "#1b1f24")
		clockPill.BackgroundTransparency = if low then 0.15 else 0.35
		local tick = if low and (t % 1) < 0.5 then 1.12 else 1
		clockPill.Size = UDim2.fromOffset(100 * tick, 36 * tick)
		Ui.setText(spotText, if s.carrying then "🏠 Deliver" else "🍕 Pick up")
		spotPill.BackgroundColor3 = hex(if s.carrying then "#009646" else "#1b1f24")
		spotPill.BackgroundTransparency = if s.carrying then 0.15 else 0.35
		Ui.setText(dropText, `✅ {s.drops}`)
		local hotLeft = if s.carrying then math.max(0, (s.hotUntil - s.t) / s.hotFor) else 0
		hot.Visible = s.carrying and hotLeft > 0
		hotFill.Size = UDim2.fromScale(hotLeft, 1)
		popAge += dt
		popText.Visible = popAge < 0.9
		if popText.Visible then
			-- chase-pop: grow in, hold, drift up and fade.
			local k = popAge / 0.9
			popScale.Scale = if k < 0.15 then 0.6 + k / 0.15 * 0.5 elseif k < 0.3 then 1.1 - (k - 0.15) / 0.15 * 0.1 else 1
			local rise = if k < 0.75 then k / 0.75 * 10 else 10 + (k - 0.75) / 0.25 * 14
			popText.Position = UDim2.new(0.5, 0, 0.28, -rise)
			local fade = if k < 0.15 then 1 - k / 0.15 elseif k > 0.75 then (k - 0.75) / 0.25 else 0
			popText.TextTransparency = 0.55 + fade * 0.45
			local face = popText:FindFirstChild("Face") :: TextLabel?
			if face then
				face.TextTransparency = fade
			end
		end
		-- The web puts its result card up at once over the stopped town; here the hub draws it,
		-- so the town stays a moment first.
		if s.done then
			controls.Visible = false
			s.endT += dt
			if s.endT >= 0.8 then
				finish(false)
			end
		end
	end
	RunService:BindToRenderStep("ArcadeDelivery", Enum.RenderPriority.Camera.Value + 1, frame)
	frame(0)
end

return Delivery
