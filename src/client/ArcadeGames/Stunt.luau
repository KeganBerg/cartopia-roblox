--!strict
-- Stunt Ramp, as the web game's StuntGame (ui/ArcadeMore.tsx) and StuntScene
-- (scene/StuntScene.tsx): a dirt arena seen side on, a yellow take-off ramp, a row of buses, and
-- a landing deck with a target that moves further out every jump. Four jumps: stop the power
-- needle, then in the air hold the left half of the screen to flip and the right half to barrel
-- roll; let go to land flat. Every number is the web's, from Shared.Game.arcadeMore (converted
-- from game/arcadeMore.ts).
--
-- play(ctx) draws the arena at ctx.origin, runs the countdown and the four jumps, and calls
-- ctx.finish(score, { score, line }) at the end (or ctx.finish(0, { quit = true }) on the X).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local M = require(Game.arcadeMore) :: any
local data = require(Game.data) :: any
local Builder = require(Shared.Models.Builder) :: any
local Paint = require(Shared.Models.Paint) :: any
local Mods = require(Shared.Models.Mods) :: any
local Panels = require(Shared.Models.Panels) :: any
local Trim = require(Shared.Models.Trim) :: any
local Skins = require(Shared.Models.Skins) :: any
local Catalog = require(Shared.Models.Catalog) :: any
local Pictures = require(Shared.Pictures) :: any
local Ui = require(script.Parent.Parent.Ui)

local Stunt = { id = "stunt" }

local S = 10 -- studs per web unit, as every converted model
local LEN = 1.8
local ANGLE = 0.5 -- ramp angle
local RAMP = 2.6 -- ramp deck length
local H = RAMP * math.sin(ANGLE) -- take-off height
local RUN = RAMP * math.cos(ANGLE)
local LAND_X = 6 -- where the landing deck starts; short of this is the bus row
local DECK_END = 18
local START_X = -14
local SPIN = 8 -- flip speed, radians a second
local ROLL = 9.5 -- barrel roll speed
local SLOW = 0.4 -- slow motion on the way down to the deck
local DUST = 40
local FOV = 50 -- ArcadeMore STUNT_CAM

local SHIRTS = { "#e53935", "#fafafa", "#1e88e5", "#fdd835", "#43a047", "#ff7043", "#8e24aa", "#26c6da" }
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

-- Words painted on a sign's front (scene/signTexture.ts): a SurfaceGui on the part's +Z face.
local function sign(p: BasePart, text: string, bg: string, fg: string)
	local g = Instance.new("SurfaceGui")
	g.Face = Enum.NormalId.Back
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 20
	g.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = hex(bg)
	l.TextColor3 = hex(fg)
	l.FontFace = Ui.DISPLAY
	l.TextScaled = true
	l.Text = text
	l.Parent = g
	g.Parent = p
end

local function library(kind: string, id: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local folder = lib and lib:FindFirstChild(kind)
	local src = folder and folder:FindFirstChild(id)
	local m: Model? = if src then src:Clone() :: Model else Builder.build(id)
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

local function lengthOf(m: Model): number
	local _, size = m:GetBoundingBox()
	return math.max(1, size.Z)
end

-- The player's car as the town draws it (paint, panels, trim, hat, mods, skin).
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

-- A simple fan (ArcadeScenery Crowd, drawn as a body and a head) standing at y facing +z.
local function fan(into: Instance, at: CFrame, i: number)
	local size = 1.3
	local k = (i * 2654435761) % 4294967296
	part({ Name = "Fan", Size = Vector3.new(0.17, 0.42, 0.15) * size * S, CFrame = at * CFrame.new(0, 0.21 * size * S, 0), Color = hex(SHIRTS[k % #SHIRTS + 1]) }, into)
	part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.16 * size * S, CFrame = at * CFrame.new(0, 0.5 * size * S, 0), Color = hex(SKIN[(k // 64) % #SKIN + 1]) }, into)
end

-- ArcadeScenery Grandstand: rows of seats stepping back, a cantilever roof, fans on the seats.
local function grandstand(into: Instance, at: (number, number, number) -> CFrame, x: number, z: number, width: number, rows: number, roof: string)
	for r = 0, rows - 1 do
		part({ Name = "Seats", Size = Vector3.new(width, 0.35 + r * 0.4, 0.7) * S, CFrame = at(x, 0.17 + r * 0.2, z - r * 0.7), Color = hex(if r % 2 == 1 then "#cfd8dc" else "#b0bec5"), Material = Enum.Material.Concrete }, into)
	end
	for _, sd in { -1, 1 } do
		part({ Name = "Post", Size = Vector3.new(0.12, 3.2 + rows * 0.4, 0.12) * S, CFrame = at(x + sd * (width / 2 - 0.1), 1.6 + rows * 0.2, z - rows * 0.7 + 0.3), Color = hex("#455a64") }, into)
	end
	part({ Name = "Roof", Size = Vector3.new(width + 0.4, 0.1, rows * 0.7 + 0.6) * S, CFrame = at(x, 3.2 + rows * 0.4, z - rows * 0.35) * CFrame.Angles(0.12, 0, 0), Color = hex(roof) }, into)
	local n = 0
	for r = 0, rows - 1 do
		for i = 0, math.floor(width / 0.55) - 1 do
			if (i * 7 + r * 3) % 5 ~= 0 then
				n += 1
				fan(into, at(x - width / 2 + 0.3 + i * 0.55 + (r % 2) * 0.2, 0.35 + r * 0.4, z - r * 0.7), n + r * 97)
			end
		end
	end
end

-- Everything that never moves: the dirt arena, ramp, landing deck, barriers, flood light towers,
-- flags and the big screen (StuntScene ArenaScenery).
local function arena(into: Instance, at: (number, number, number) -> CFrame)
	local g = part({ Name = "Grass", Size = Vector3.new(140, 0.2, 80) * S, CFrame = at(0, -0.2, 0), Color = hex(Catalog.GRASS or "#a9b552") }, into)
	local t = (Catalog.TEXTURES or {}).grass
	if t and t.image ~= 0 then
		local tex = Instance.new("Texture")
		tex.Face = Enum.NormalId.Top
		Pictures.set(tex, "Texture", t.image)
		tex.StudsPerTileU = 50
		tex.StudsPerTileV = 50
		tex:SetAttribute("Image", t.name)
		tex.Parent = g
	end
	part({ Name = "Sand", Size = Vector3.new(60, 0.1, 32) * S, CFrame = at(2, -0.05, 9), Color = hex("#d9a46c"), Material = Enum.Material.Sand }, into)
	-- Tyre tracks down the run-up, and the start line.
	for _, z in { -0.35, 0.35 } do
		part({ Name = "Track", Size = Vector3.new(14 * S, 0.3, 0.22 * S), CFrame = at(-9, 0, z) * CFrame.new(0, 0.15, 0), Color = hex("#4e342e"), Transparency = 0.55 }, into)
	end
	part({ Name = "Start", Size = Vector3.new(0.25 * S, 0.3, 2.4 * S), CFrame = at(START_X + 0.9, 0, 0) * CFrame.new(0, 0.15, 0), Color = hex("#fafafa") }, into)
	-- Take-off ramp: a yellow steel deck with chevrons on a scaffold.
	local deck = at(-RUN / 2, H / 2, 0) * CFrame.Angles(0, 0, ANGLE)
	part({ Name = "Ramp", Size = Vector3.new(RAMP, 0.1, 2.4) * S, CFrame = deck, Color = hex("#fbc02d"), Material = Enum.Material.Metal }, into)
	for _, x in { -0.8, 0, 0.8 } do
		part({ Name = "Chevron", Size = Vector3.new(0.3 * S, 0.2, 2.3 * S), CFrame = deck * CFrame.new(x * S, 0.05 * S + 0.1, 0), Color = hex("#212121") }, into)
	end
	for _, x in { -RUN + 0.5, -RUN / 2, -0.1 } do
		for _, z in { -1.1, 1.1 } do
			local h = math.max(0.05, (x + RUN) * math.tan(ANGLE))
			part({ Name = "Scaffold", Size = Vector3.new(0.08, h, 0.08) * S, CFrame = at(x, h / 2, z), Color = hex("#455a64") }, into)
		end
	end
	part({ Name = "RampBack", Size = Vector3.new(0.1, H, 2.3) * S, CFrame = at(-0.1, H / 2, 0), Color = hex("#37474f") }, into)
	-- Landing deck: a long packed-dirt mound with distance boards, then a slope down.
	part({ Name = "Deck", Size = Vector3.new(DECK_END - LAND_X, H, 3) * S, CFrame = at((LAND_X + DECK_END) / 2, H / 2, 0), Color = hex("#c8a27a"), Material = Enum.Material.Sand }, into)
	part({ Name = "Slope", Size = Vector3.new(math.sqrt(16 + H * H), 0.3, 3) * S, CFrame = at(DECK_END + 2, H / 2 - 0.25, 0) * CFrame.Angles(0, 0, -math.atan(H / 4)), Color = hex("#c8a27a"), Material = Enum.Material.Sand }, into)
	part({ Name = "Edge", Size = Vector3.new(0.12, H + 0.02, 3.02) * S, CFrame = at(LAND_X + 0.05, H / 2, 0), Color = hex("#e53935") }, into)
	for i = 0, 5 do
		local x = LAND_X + 2 + i * 2
		part({ Name = "Line", Size = Vector3.new(0.08 * S, 0.2, 3 * S), CFrame = at(x, H, 0) * CFrame.new(0, 0.1, 0), Color = hex("#fafafa") }, into)
		local board = part({ Name = "Board", Size = Vector3.new(0.6, 0.45, 0.05) * S, CFrame = at(x, H + 0.45, -1.55), Color = hex("#212121") }, into)
		sign(board, `{x}m`, "#212121", "#ffd54f")
		part({ Name = "BoardPost", Size = Vector3.new(0.04, 0.22, 0.04) * S, CFrame = at(x, H + 0.11, -1.55), Color = hex("#455a64") }, into)
	end
	-- Hay bales down the run-up.
	for i = 0, 6 do
		part({ Name = "Hay", Size = Vector3.new(1.1, 0.5, 0.55) * S, CFrame = at(START_X + 1 + i * 1.6, 0.25, -1.6), Color = hex(if i % 2 == 1 then "#e0c068" else "#d4b45a"), Material = Enum.Material.Fabric }, into)
	end
	-- Barriers in sponsor colours round the back of the arena.
	local words = { "STUNT SHOW", "NITRO", "CARTOPIA", "BIG AIR" }
	local colours = { "#e53935", "#1e88e5", "#fb8c00", "#6a1b9a" }
	for i = 0, 23 do
		local x = -26 + i * 2.4
		part({ Name = "Barrier", Size = Vector3.new(2.3, 0.8, 0.45) * S, CFrame = at(x, 0.4, -5.5), Color = hex("#eceff1"), Material = Enum.Material.Concrete }, into)
		local banner = part({ Name = "Banner", Size = Vector3.new(2.1, 0.5, 0.02) * S, CFrame = at(x, 0.45, -5.5 + 0.235), Color = hex(colours[i % 4 + 1]) }, into)
		sign(banner, words[i % 4 + 1], colours[i % 4 + 1], "#ffffff")
	end
	-- The big screen over the stands.
	for _, x in { -3, 3 } do
		part({ Name = "ScreenPost", Size = Vector3.new(0.3, 8, 0.3) * S, CFrame = at(3 + x, 4, -14), Color = hex("#37474f") }, into)
	end
	part({ Name = "Screen", Size = Vector3.new(7, 2.6, 0.3) * S, CFrame = at(3, 7.5, -14), Color = hex("#212121") }, into)
	local face = part({ Name = "ScreenFace", Size = Vector3.new(6.6, 2.2, 0.02) * S, CFrame = at(3, 7.5, -14 + 0.16), Color = hex("#0d47a1") }, into)
	sign(face, "BIG AIR", "#0d47a1", "#ffd54f")
	-- Flood light towers.
	for _, x in { -18, 8, 26 } do
		part({ Name = "Tower", Shape = Enum.PartType.Cylinder, Size = Vector3.new(10, 0.3, 0.3) * S, CFrame = at(x, 5, -7) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#78909c") }, into)
		part({ Name = "Lights", Size = Vector3.new(2, 1, 0.2) * S, CFrame = at(x, 10, -6.8), Color = hex("#455a64") }, into)
		for _, dx in { -0.6, 0, 0.6 } do
			for _, dy in { -0.25, 0.25 } do
				part({ Name = "Bulb", Size = Vector3.new(0.45, 0.4, 0.02) * S, CFrame = at(x + dx, 10 + dy, -7 + 0.31), Color = hex("#fff8e1"), Material = Enum.Material.Neon }, into)
			end
		end
	end
	-- Flags along the deck.
	local flagColours = { "#e53935", "#fdd835", "#1e88e5" }
	for i = 0, 4 do
		local x = LAND_X + 1 + i * 3
		part({ Name = "FlagPole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.6, 0.05, 0.05) * S, CFrame = at(x, H + 0.8, 1.6) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#cfd8dc") }, into)
		part({ Name = "Flag", Size = Vector3.new(0.5, 0.32, 0.02) * S, CFrame = at(x + 0.25, H + 1.4, 1.6), Color = hex(flagColours[i % 3 + 1]) }, into)
	end
	grandstand(into, at, 0, -8, 30, 5, "#1e88e5")
	grandstand(into, at, 24, -8, 14, 4, "#e53935")
end

function Stunt.play(ctx: any)
	local origin: Vector3 = ctx.origin
	local rng = Random.new(ctx.seed or 1)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(origin + Vector3.new(x, y, z) * S)
	end

	local world = Instance.new("Folder")
	world.Name = "StuntRamp"
	arena(world, at)

	-- The row of buses (and the odd car) parked across the gap.
	local bus: any = nil
	local pool = {}
	for _, c in data.CARS do
		if c.body == "bus" and not bus then
			bus = c
		end
		if not c.parked and not data.isBike(c.body) then
			table.insert(pool, c)
		end
	end
	for i = 0, 4 do
		local c = if bus and i % 2 == 0 then bus else pool[(i * 7) % #pool + 1]
		local m = library("Cars", c.id)
		if m then
			Builder.paint(m, hex(c.colors[i % #c.colors + 1]))
			m:ScaleTo(m:GetScale() * LEN * 1.6 * S / lengthOf(m))
			m:PivotTo(at(1 + i * 1.05, 0, 0))
			m.Parent = world
		end
	end
	-- Fire pots at each end of the deck: they flare on a clean landing.
	local flames: { BasePart } = {}
	local flameAt: { CFrame } = {}
	for _, x in { LAND_X + 0.5, DECK_END - 0.5 } do
		for _, z in { -1.3, 1.3 } do
			part({ Name = "Pot", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 0.34, 0.34) * S, CFrame = at(x, H + 0.1, z) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#37474f") }, world)
			table.insert(flames, part({ Name = "Flame", Size = Vector3.new(0.3, 1.4, 0.3) * S, CFrame = at(x, H + 0.9, z), Color = hex("#ff9100"), Material = Enum.Material.Neon, Transparency = 1 }, world))
			table.insert(flameAt, at(x, H + 0.2, z))
		end
	end
	-- The landing target: a painted bullseye that moves further out every jump.
	local target = Instance.new("Model")
	target.Name = "Target"
	part({ Name = "Outer", Size = Vector3.new(M.TARGET_W * S, 0.2, 2.8 * S), CFrame = CFrame.new(0, 0.1, 0), Color = hex("#ffd54f"), Transparency = 0.15 }, target)
	part({ Name = "Middle", Size = Vector3.new(M.TARGET_W * 0.6 * S, 0.3, 2.8 * S), CFrame = CFrame.new(0, 0.15, 0), Color = hex("#e53935") }, target)
	part({ Name = "Bull", Size = Vector3.new(M.TARGET_W * 0.22 * S, 0.4, 2.8 * S), CFrame = CFrame.new(0, 0.2, 0), Color = hex("#fafafa") }, target)
	target.WorldPivot = CFrame.new()
	target.Parent = world
	local puffParts: { BasePart } = {}
	local puffs = {}
	for i = 1, DUST do
		puffParts[i] = part({ Name = "Dust", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3 * S, Color = hex("#c8a27a"), Transparency = 1 }, world)
		puffs[i] = { x = 0, y = -9, z = 0, vx = 0, vy = 0, life = 0 }
	end
	local carModel = playerCar(ctx.car)
	carModel:ScaleTo(carModel:GetScale() * LEN * S / lengthOf(carModel))
	carModel.Name = "Player"
	carModel.Parent = world
	local _, carSize = carModel:GetBoundingBox()
	local shadowPart = part({ Name = "CarShadow", Size = Vector3.new(LEN * 1.25 * S, 0.02, carSize.X * 1.2), Color = Ui.BLACK, Transparency = 0.7 }, world)
	world.Parent = workspace

	local s = {
		jump = 0, score = 0, phase = "aim", power = 0, needle = 0, wasDown = false,
		x = START_X, y = 0, vx = 0, vy = 0, spin = 0, roll = 0, pitch = 0, t = 0, wait = 0, fire = 0, done = false, slow = false,
		last = nil :: any, zoom = 1,
		running = false, clock = 0, count = 3, countT = 0, endT = 0,
	}
	local input = { down = false, roll = false }
	ctx.input = input -- for the preview harness (tools/emulate/arcade-delstunt.luau)
	ctx.state = s

	local function puff(x: number, y: number, n: number)
		for _ = 1, n do
			local p
			for _, q in puffs do
				if q.life <= 0 then
					p = q
					break
				end
			end
			if not p then
				return
			end
			p.x, p.y, p.z = x + (rng:NextNumber() - 0.5) * 0.8, y, (rng:NextNumber() - 0.5) * 1.2
			p.vx, p.vy, p.life = (rng:NextNumber() - 0.5) * 2, 0.6 + rng:NextNumber() * 1.2, 1
		end
	end

	-- ── Camera ──
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
	local short = view.Y <= 500
	local insetTop, insetLeft, insetRight = 0, 0, 0
	pcall(function()
		local r = GuiService.TopbarInset
		if r.Height > 0 then
			insetTop, insetLeft, insetRight = r.Min.Y, r.Min.X, view.X - r.Max.X
		end
	end)
	local root = Ui.new("Frame", { Name = "Stunt", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	-- The whole screen takes presses (.arc-scrub): the left half flips, the right half rolls;
	-- either one stops the power needle.
	local pad = Ui.new("TextButton", { Name = "Press", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Active = true, Parent = root })
	-- Slow motion darkens the edges (.stunt-slow).
	local vignette = Ui.new("Frame", { Name = "Slow", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = root }, {
		Ui.new("UIStroke", { Thickness = 60, Color = Ui.BLACK, Transparency = 0.7, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
	})
	local top = Ui.new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 64 + insetTop), BackgroundColor3 = hex("#0a1e3c"), BorderSizePixel = 0, Parent = root })
	Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }), Parent = top })
	Ui.text({ Name = "Title", Text = "🔥 Stunt Ramp", TextSize = if short then 16 else 20, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(math.max(14, insetLeft + 4), insetTop + 8), Size = UDim2.new(1, -120, 0, 36), Shadow = 2, ShadowTransparency = 0.65, ShadowColor = Ui.BLACK, Parent = root })
	local finish: (boolean) -> ()
	Ui.closeButton({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -math.max(12, insetRight + 4), 0, insetTop + 8), Size = UDim2.fromOffset(40, 40), Parent = root }, function()
		finish(true)
	end)
	local hudTop = math.max(if short then 36 else 50, insetTop + 50)
	local row = Ui.new("Frame", { Name = "Hud", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, hudTop), Size = UDim2.new(1, -16, 0, 34), BackgroundTransparency = 1, Parent = root }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function pill(order: number, w: number, size: number): TextLabel
		local f = Ui.new("Frame", { Name = "Pill", LayoutOrder = order, Size = UDim2.fromOffset(w, 32), BackgroundColor3 = hex("#1b1f24"), BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = row }, { Ui.round() })
		return Ui.text({ Size = UDim2.fromScale(1, 1), TextSize = size, Text = "", Parent = f })
	end
	local jumpText = pill(1, 80, 18)
	local scoreText = pill(2, 84, 22)
	local targetText = pill(3, 76, 18)
	-- The power meter (.arc-power): red, yellow, green near the top, red at the very top.
	local power = Ui.new("Frame", { Name = "Power", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -(if short then 52 else 70)), Size = UDim2.fromOffset(math.min(320, view.X * 0.7), 24), BackgroundColor3 = Ui.WHITE, ClipsDescendants = true, Parent = root }, {
		Ui.new("UICorner", { CornerRadius = UDim.new(0, 12) }),
		Ui.new("UIStroke", { Thickness = 3, Color = Ui.WHITE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }),
		Ui.new("UIGradient", { Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, hex("#e53935")),
			ColorSequenceKeypoint.new(0.6, hex("#fdd835")),
			ColorSequenceKeypoint.new(0.88, hex("#00e676")),
			ColorSequenceKeypoint.new(1, hex("#e53935")),
		}) }),
	})
	local needle = Ui.new("Frame", { Name = "Needle", Size = UDim2.fromScale(0, 1), BackgroundColor3 = hex("#1b1f24"), BackgroundTransparency = 0.65, BorderSizePixel = 0, Parent = power })
	Ui.new("Frame", { Name = "Mark", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = hex("#1b1f24"), BorderSizePixel = 0, Parent = needle })
	local tip = Ui.text({ Name = "Tip", Text = "Tap at full power", TextSize = 20, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -(if short then 8 else 26)), Size = UDim2.new(1, 0, 0, 26), Shadow = 2, ShadowTransparency = 0.6, ShadowColor = Ui.BLACK, Parent = root })
	tip.Visible = false
	-- The two pads drawn while the car runs and flies (.stunt-pads).
	local pads = Ui.new("Frame", { Name = "Pads", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26), Size = UDim2.new(1, -36, 0, 92), BackgroundTransparency = 1, Visible = false, Parent = root })
	for i, p in { { "🔄", "Flip" }, { "🌀", "Roll" } } do
		local c = Ui.new("Frame", { Name = p[2], AnchorPoint = Vector2.new(i - 1, 0), Position = UDim2.fromScale(i - 1, 0), Size = UDim2.fromOffset(92, 92), BackgroundColor3 = hex("#1b1f24"), BackgroundTransparency = 0.55, Parent = pads }, { Ui.round(), Ui.stroke(3, Ui.WHITE, 0.15) })
		Ui.text({ Text = p[1], TextSize = 34, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 40), Parent = c })
		Ui.text({ Text = p[2], TextSize = 15, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 18), Parent = c })
	end
	-- What the jump scored (.arc-callout).
	local callout = Ui.new("Frame", { Name = "Callout", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.new(1, 0, 0, 100), BackgroundTransparency = 1, Visible = false, Parent = root })
	local calloutScale = Ui.new("UIScale", { Parent = callout })
	local calloutBig = Ui.text({ Name = "Points", Text = "", TextSize = if short then 40 else 56, Size = UDim2.new(1, 0, 0, if short then 46 else 62), Shadow = 4, ShadowTransparency = 0.6, ShadowColor = Ui.BLACK, Parent = callout })
	local calloutSmall = Ui.text({ Name = "Tricks", Text = "", TextSize = 26, Position = UDim2.fromOffset(0, if short then 48 else 64), Size = UDim2.new(1, 0, 0, 30), Shadow = 3, ShadowTransparency = 0.6, ShadowColor = Ui.BLACK, Parent = callout })
	local calloutAge = 99
	local countText = Ui.text({ Name = "Count", Text = "3", TextSize = if short then 72 else 110, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.new(1, 0, 0, 120), Shadow = 5, ShadowTransparency = 0.65, ShadowColor = Ui.BLACK, Parent = root })

	-- ── Input ──
	local conns: { RBXScriptConnection } = {}
	local presses: { [InputObject]: boolean } = {}
	table.insert(conns, pad.InputBegan:Connect(function(io: InputObject)
		if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
			presses[io] = true
			if io.Position.X < view.X / 2 then
				input.down = true
			else
				input.roll = true
			end
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(io: InputObject)
		if presses[io] then
			presses[io] = nil
			input.down = false
			input.roll = false
		elseif io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.Up or io.KeyCode == Enum.KeyCode.W then
			input.down = false
		elseif io.KeyCode == Enum.KeyCode.Right or io.KeyCode == Enum.KeyCode.D then
			input.roll = false
		end
	end))
	-- Space or up flips, right or D rolls.
	table.insert(conns, UserInputService.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if processed then
			return -- typing in chat
		elseif io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.Up or io.KeyCode == Enum.KeyCode.W then
			input.down = true
		elseif io.KeyCode == Enum.KeyCode.Right or io.KeyCode == Enum.KeyCode.D then
			input.roll = true
		end
	end))

	local finished = false
	finish = function(quit: boolean)
		if finished then
			return
		end
		finished = true
		RunService:UnbindFromRenderStep("ArcadeStunt")
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
			ctx.finish(s.score, { score = s.score, line = `🔥 {Ui.commas(s.score)} pts` })
		end
	end
	ctx.stop = function()
		finish(true)
	end

	local function frame(rawDt: number)
		-- 3, 2, 1 (650 ms each), then GO! for 600 ms, the jumps live from GO.
		s.clock += rawDt
		local t = s.clock
		if s.count >= 0 then
			s.countT += math.min(rawDt, 1 / 20)
			local step = if s.count > 0 then 0.65 else 0.6
			if s.countT >= step then
				s.countT -= step
				s.count -= 1
				if s.count == 0 then
					s.running = true
				end
			end
			countText.Visible = s.count >= 0
			Ui.setText(countText, if s.count == 0 then "GO!" else tostring(s.count))
		end
		local running = s.running
		-- Slow motion on the way down, so there's time to let go and land flat.
		s.slow = s.phase == "air" and s.vy < 0 and s.y - (if s.x >= LAND_X - 1 then H else 0.9) < 1.8
		local dt = math.min(rawDt, 1 / 20) * (if s.slow then SLOW else 1)
		local down = running and (input.down or input.roll)
		local press = down and not s.wasDown
		s.wasDown = down
		s.wait = math.max(0, s.wait - dt)

		if s.phase == "aim" then
			-- The needle sweeps up and down; a press locks it.
			if running then
				s.needle += dt * 1.6
			end
			s.power = 1 - math.abs(1 - (s.needle % 2))
			if press and s.wait <= 0 and not s.done then
				s.phase = "run"
			end
		elseif s.phase == "run" then
			-- Accelerate to take-off speed by the foot of the ramp, then ride up it.
			local v = M.launchSpeed(s.power)
			if s.x < -RUN then
				s.vx = math.min(v, s.vx + v * 0.9 * dt)
				s.x += s.vx * dt
				s.pitch = 0
				if rng:NextNumber() < 0.4 then
					puff(s.x - 0.8, 0.05, 1)
				end
			else
				s.vx = v
				s.x += v * math.cos(ANGLE) * dt
				s.y = (s.x + RUN) * math.tan(ANGLE)
				s.pitch = ANGLE
				if s.x >= 0 then
					s.phase = "air"
					s.x, s.y = 0, H
					s.vx, s.vy = v * math.cos(ANGLE), v * math.sin(ANGLE)
					s.spin, s.t = 0, 0
				end
			end
		elseif s.phase == "air" then
			s.t += dt
			s.x += s.vx * dt
			s.vy -= M.GRAVITY * dt
			s.y += s.vy * dt
			if running and input.down then
				s.spin += SPIN * dt
			end
			if running and input.roll then
				s.roll += ROLL * dt
			end
			s.pitch = s.spin + math.atan2(s.vy, s.vx) * 0.4
			-- Down at deck height (or onto the buses if short).
			local floor = if s.x >= LAND_X then H else 0.9
			if s.vy < 0 and s.y <= floor then
				local ok = s.x >= LAND_X and s.x <= DECK_END and M.landed(s.spin) and M.landed(s.roll)
				local bull = ok and M.onTarget(s.x, s.jump)
				local pts = if ok then M.jumpScore(s.x, s.spin, s.roll, bull) else 0
				s.score += pts
				s.last = { pts = pts, flips = if ok then M.flips(s.spin) else 0, rolls = if ok then M.flips(s.roll) else 0, target = bull, ok = ok }
				s.jump += 1
				s.y = floor
				puff(s.x, floor, 14)
				calloutAge = 0
				if ok then
					s.phase = "roll"
					s.pitch, s.roll = 0, 0
					s.fire = if bull then 2 else 1.2
				else
					s.phase = "crash"
					s.vy = 3
				end
				s.wait = 1.8
			end
		elseif s.phase == "roll" then
			s.vx = math.max(0, s.vx - 7 * dt)
			s.x += s.vx * dt
			s.pitch *= 0.8
		elseif s.phase == "crash" then
			-- Tumble and settle.
			s.vy -= M.GRAVITY * dt
			s.y = math.max(if s.x >= LAND_X then H else 0.9, s.y + s.vy * dt)
			s.x += s.vx * 0.3 * dt
			s.pitch += dt * 6 * math.max(0, s.wait - 0.8)
			if rng:NextNumber() < 0.3 then
				puff(s.x, s.y, 1)
			end
		end
		if (s.phase == "roll" or s.phase == "crash") and s.wait <= 0 then
			if s.jump >= M.STUNT_JUMPS then
				s.done = true
			else
				s.phase, s.x, s.y, s.vx, s.vy, s.spin, s.roll, s.pitch, s.needle, s.wait = "aim", START_X, 0, 0, 0, 0, 0, 0, 0, 0.4
			end
		end

		-- The car: facing down the track, pitched by the flip and turned by the roll.
		carModel:PivotTo(at(s.x, s.y, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(-s.pitch, 0, 0) * CFrame.Angles(0, 0, s.roll))
		local ground = if s.x >= LAND_X and s.x <= DECK_END + 0.5 then H elseif s.x > 0.5 and s.x < LAND_X then 0.9 elseif s.x >= -RUN and s.x <= 0 then (s.x + RUN) * math.tan(ANGLE) else 0
		shadowPart.CFrame = at(s.x, ground, 0) * CFrame.new(0, 0.15, 0) * (if s.x >= -RUN and s.x < 0 then CFrame.Angles(0, 0, ANGLE) else CFrame.identity)
		shadowPart.Transparency = if ground > 0.85 and ground < 0.95 then 1 else 0.7
		local j = math.min(M.STUNT_JUMPS - 1, s.jump - (if s.phase == "roll" or s.phase == "crash" then 1 else 0))
		local bump = 1 + math.sin(t * 4) * 0.04
		target:PivotTo(at(M.targetX(math.max(0, j)), H + 0.012, 0))
		target:ScaleTo(bump)
		s.fire = math.max(0, s.fire - dt)
		for i, f in flames do
			local hgt = 0.6 + math.sin(t * 30 + i) * 0.3 + s.fire
			f.Transparency = if s.fire > 0 then 1 - math.min(1, s.fire) * 0.9 else 1
			f.Size = Vector3.new(0.3, 1.4 * hgt, 0.3) * S
			f.CFrame = flameAt[i] * CFrame.new(0, f.Size.Y / 2, 0)
		end
		for i, p in puffs do
			if p.life > 0 then
				p.life -= dt * 0.8
				p.x += p.vx * dt
				p.y += p.vy * dt
			end
			local pp = puffParts[i]
			pp.Transparency = if p.life > 0 then 0.45 + (1 - p.life) * 0.4 else 1
			pp.Size = Vector3.one * (0.15 + (1 - math.max(0, p.life)) * 0.45) * 2 * S
			pp.CFrame = at(p.x, if p.life > 0 then p.y else -9, p.z)
		end
		-- Side-on camera that pans with the car; further out on a narrow screen, wide at the needle
		-- to show the gap, in tight on the car once it's moving.
		local tan = math.tan(math.rad(FOV / 2))
		local wide = view.X > view.Y
		local close = if s.phase == "aim" then 1 elseif s.slow then 0.55 else 0.68
		local far = math.max(4.6 / tan, (if wide then 8.5 else 4.4) / (tan * (view.X / view.Y)))
		s.zoom += (close - s.zoom) * math.min(1, dt * 2.5)
		local dist = far * s.zoom
		local lead = if s.phase == "aim" then (if wide then 4 else 1.5) else 1
		local cx = if wide then math.clamp(s.x + lead, -12, 16) else math.clamp(s.x + lead, -13, 17)
		local look = origin + Vector3.new(cx, if wide then 1.4 else 2.4, 0) * S
		local eye = origin + Vector3.new(cx - dist * 0.12, 1.4 + dist * 0.28, dist) * S
		camPos = if camPos then camPos:Lerp(eye, math.min(1, dt * 3)) else eye
		cam.CFrame = CFrame.lookAt(camPos :: Vector3, look)

		-- HUD
		local shownJump = math.min(M.STUNT_JUMPS, s.jump + (if s.phase == "aim" or s.phase == "run" or s.phase == "air" then 1 else 0))
		Ui.setText(jumpText, `🏁 {shownJump}/{M.STUNT_JUMPS}`)
		Ui.setText(scoreText, Ui.commas(s.score))
		Ui.setText(targetText, `🎯 {M.targetX(shownJump - 1)}m`)
		power.Visible = s.phase == "aim"
		needle.Size = UDim2.fromScale(s.power, 1)
		tip.Visible = s.phase == "aim" and running
		pads.Visible = s.phase == "run" or s.phase == "air"
		vignette.Visible = s.slow
		local last = s.last
		callout.Visible = last ~= nil and (s.phase == "roll" or s.phase == "crash")
		if callout.Visible and last then
			calloutAge += rawDt
			calloutScale.Scale = if calloutAge < 0.3 then 0.7 + calloutAge else 1
			if last.ok then
				local tricks = {}
				if last.flips > 0 then
					table.insert(tricks, if last.flips > 1 then `{last.flips}× flip` else "Flip")
				end
				if last.rolls > 0 then
					table.insert(tricks, if last.rolls > 1 then `{last.rolls}× roll` else "Roll")
				end
				if last.target then
					table.insert(tricks, "🎯")
				end
				Ui.setText(calloutBig, `+{last.pts}`)
				Ui.setColor(calloutBig, hex("#ffd54f"))
				Ui.setText(calloutSmall, table.concat(tricks, " + "))
			else
				Ui.setText(calloutBig, "Wipeout!")
				Ui.setColor(calloutBig, hex("#ff8a80"))
				Ui.setText(calloutSmall, "")
			end
		end
		-- The web puts its result card up at once over the arena; here the hub draws it, so the
		-- arena stays a moment first.
		if s.done then
			s.endT += rawDt
			if s.endT >= 0.6 then
				finish(false)
			end
		end
	end
	RunService:BindToRenderStep("ArcadeStunt", Enum.RenderPriority.Camera.Value + 1, frame)
	frame(0)
end

return Stunt
