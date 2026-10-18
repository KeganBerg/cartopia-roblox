--!strict
-- The drag race screen, as the web game's DragRace (ui/Race.tsx) and RaceScene: the street fills
-- the screen with both cars on it, the controls float over it. Hold HOLD on the line to rev into
-- the yellow band, go at GO, then tap SHIFT with the needle in the green; BOOST once the tank
-- has filled. The race runs on Shared.DragRace at its fixed step, exactly as the server will
-- replay it from the presses sent at the end, and the result card shows what the server paid.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local race = require(Game.race) :: any
local data = require(Game.data) :: any
local DragRace = require(ReplicatedStorage.Shared.DragRace)
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local TownCamera = require(script.Parent.TownCamera)

local DragStrip = {}

-- The web's race scene in studs: 0.25 world units per metre of race, 10 studs per unit.
local STUDS_PER_M = 2.5
local LANE = 7.5 -- each car's lane, either side of the middle
local ROAD = 16 -- half the street's width
local WALK = 10 -- the sidewalk
local RUN_OUT = 150 * STUDS_PER_M -- past the line, where the cars slow to a stop
local TAIL = 120 -- street behind the start line
local ORIGIN = Vector3.new(-30000, 0, 0) -- far from every town and its countryside

-- Ground colours by venue (the web's venues each have their own scenery).
local GROUND = { beach = "#e8d79a", desert = "#d9b277", snow = "#eef4fa", farm = "#8fbf5a", docks = "#8a96a3" }
-- The buildings along the street: the web's FALLBACK row.
local ROW = { "pizza", "donut", "burger", "diner", "house", "motel", "carwash", "tires", "gas", "bowling", "icecream", "house" }

local strip: Model? = nil
local stripLength = 0

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

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function library(kind: string, id: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local src = lib and lib:FindFirstChild(kind) and (lib :: any)[kind]:FindFirstChild(id)
	if not src then
		return nil
	end
	local m = src:Clone() :: Model
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	return m
end

-- The street: asphalt with lane lines, sidewalks and kerbs, the start line and its light tree,
-- a chequered finish under a banner, shops along both sides and grass beyond. Built once, then
-- kept; only the ground colour follows the venue.
local function buildStrip(track: number): Model
	local len = track * STUDS_PER_M
	if strip and stripLength == len then
		return strip
	end
	if strip then
		strip:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "DragStrip"
	local z0, z1 = -TAIL, len + RUN_OUT + 60
	local mid, long = (z0 + z1) / 2, z1 - z0
	local at = function(x: number, y: number, z: number): CFrame
		return CFrame.new(ORIGIN + Vector3.new(x, y, z))
	end
	part({ Name = "Ground", Size = Vector3.new(1400, 2, long + 800), CFrame = at(0, -1.2, mid), Color = hex("#7cb342"), Material = Enum.Material.Grass }, m)
	part({ Name = "Asphalt", Size = Vector3.new(ROAD * 2, 1, long), CFrame = at(0, -0.4, mid), Color = hex("#3b4048"), Material = Enum.Material.Asphalt }, m)
	for _, side in { -1, 1 } do
		part({ Name = "Kerb", Size = Vector3.new(1.2, 1.4, long), CFrame = at(side * (ROAD + 0.6), -0.2, mid), Color = hex("#d7dde3") }, m)
		part({ Name = "Walk", Size = Vector3.new(WALK, 1.2, long), CFrame = at(side * (ROAD + 1.2 + WALK / 2), -0.3, mid), Color = hex("#b9c0c8"), Material = Enum.Material.Concrete }, m)
		-- Lane edges.
		part({ Name = "Edge", Size = Vector3.new(0.6, 0.1, long), CFrame = at(side * (ROAD - 1.5), 0.12, mid), Color = hex("#f5f5f5") }, m)
	end
	-- The dashed middle line.
	for z = z0, z1, 24 do
		part({ Name = "Dash", Size = Vector3.new(0.6, 0.1, 12), CFrame = at(0, 0.12, z + 6), Color = hex("#ffd54f") }, m)
	end
	-- Start line, and the light tree beside it.
	part({ Name = "StartLine", Size = Vector3.new(ROAD * 2, 0.1, 1.6), CFrame = at(0, 0.13, 0), Color = hex("#ffffff") }, m)
	local tree = Instance.new("Model")
	tree.Name = "Tree"
	tree.Parent = m
	local tx = -(ROAD + 4) -- on the sidewalk, to the right of the cars
	part({ Name = "Pole", Size = Vector3.new(1, 18, 1), CFrame = at(tx, 9, 8), Color = hex("#263238") }, tree)
	part({ Name = "Box", Size = Vector3.new(3.4, 9, 1.6), CFrame = at(tx, 16, 8), Color = hex("#1b1f24") }, tree)
	for i = 1, 3 do
		local lamp = part({ Name = `Lamp{i}`, Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), CFrame = at(tx, 19.5 - i * 2.4, 7.1), Color = hex("#3a1010"), Material = Enum.Material.SmoothPlastic }, tree)
		lamp:SetAttribute("Lamp", i)
	end
	-- The finish: a chequered band across the road under a banner on two posts.
	local cells = 16
	for i = 0, cells - 1 do
		for j = 0, 1 do
			part({ Name = "Check", Size = Vector3.new(ROAD * 2 / cells, 0.1, 2), CFrame = at(-ROAD + (i + 0.5) * ROAD * 2 / cells, 0.14, len + (j - 0.5) * 2), Color = if (i + j) % 2 == 0 then hex("#ffffff") else hex("#111111") }, m)
		end
	end
	for _, side in { -1, 1 } do
		part({ Name = "Post", Size = Vector3.new(1.4, 30, 1.4), CFrame = at(side * (ROAD + 2), 15, len), Color = hex("#eceff1") }, m)
	end
	local banner = part({ Name = "Banner", Size = Vector3.new(ROAD * 2 + 5, 5.5, 0.6), CFrame = at(0, 27, len), Color = hex("#d32f2f") }, m)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.CanvasSize = Vector2.new(400, 60)
		g.Parent = banner
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = "FINISH"
		t.TextScaled = true
		t.FontFace = Ui.DISPLAY
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Parent = g
	end
	-- Bunting over the start.
	for i = 0, 11 do
		local x = -ROAD - 2 + (i + 0.5) * (ROAD * 2 + 4) / 12
		local sag = 1.6 * (1 - ((i + 0.5) / 6 - 1) ^ 2)
		part({ Name = "Flag", Size = Vector3.new(2, 2.2, 0.2), CFrame = at(x, 30 - sag, 4) * CFrame.Angles(0, 0, math.rad(45)), Color = hex(({ "#ff1744", "#ffd54f", "#2979ff", "#00e676" })[i % 4 + 1]) }, m)
	end
	for _, side in { -1, 1 } do
		part({ Name = "Post", Size = Vector3.new(1, 31, 1), CFrame = at(side * (ROAD + 2), 15.5, 4), Color = hex("#eceff1") }, m)
	end
	-- Shops along both sides, facing the street, with lamps between.
	for _, side in { -1, 1 } do
		local z = z0 + 10
		local n = if side > 0 then 0 else 5
		while z < z1 - 20 do
			n += 1
			local id = ROW[n % #ROW + 1]
			local b = library("Buildings", id)
			if b then
				local _, size = b:GetBoundingBox()
				local depth, width = size.Z, size.X
				local turn = if side > 0 then -math.pi / 2 else math.pi / 2
				b:PivotTo(at(side * (ROAD + 1.2 + WALK + 4 + depth / 2), 0, z + width / 2) * CFrame.Angles(0, turn, 0))
				b.Parent = m
				z += width + 8
			else
				z += 40
			end
			part({ Name = "LampPost", Size = Vector3.new(0.6, 14, 0.6), CFrame = at(side * (ROAD + 2.5), 7, z - 4), Color = hex("#37474f") }, m)
			part({ Name = "LampHead", Size = Vector3.new(3, 0.8, 1.4), CFrame = at(side * (ROAD + 1.2), 14, z - 4), Color = hex("#fff59d"), Material = Enum.Material.Neon }, m)
		end
	end
	m.Parent = workspace
	strip, stripLength = m, len
	return m
end

local function paintCar(m: Model, color: Color3)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Paint") then
			d.Color = color
		end
	end
end

-- A car on the strip, with its boost flame and wheelspin smoke.
local function placeCar(model: string, color: string, x: number, parent: Instance): (Model, BasePart, ParticleEmitter)
	local m = library("Cars", model) or Instance.new("Model")
	paintCar(m, hex(color))
	m.Parent = parent
	local flame = part({ Name = "Flame", Size = Vector3.new(2.2, 1.2, 4), Color = hex("#ff9100"), Material = Enum.Material.Neon, Transparency = 1 }, parent)
	local smokeAt = part({ Name = "Smoke", Size = Vector3.new(1, 1, 1), Transparency = 1 }, parent)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(0.6, 1)
	smoke.Rate = 40
	smoke.Speed = NumberRange.new(4, 8)
	smoke.SpreadAngle = Vector2.new(40, 20)
	smoke.EmissionDirection = Enum.NormalId.Back
	smoke.Enabled = false
	smoke.Parent = smokeAt
	m:PivotTo(CFrame.new(ORIGIN + Vector3.new(x, 0, 0)))
	m:SetAttribute("X", x)
	return m, flame, smoke
end

local function money(n: number): string
	return `${Ui.commas(n)}`
end

-- Opens the race. started: what Remote.race("start") answered ({ spec, rival, mode, venue });
-- car: the race car ({ model, color }); onExit: back to the race menu.
function DragStrip.run(ctx: any, started: any, car: any, onExit: () -> ())
	local spec, rival, venue = started.spec, started.rival, started.venue or {}
	local r = DragRace.new(spec)
	local len = spec.track * STUDS_PER_M
	local world = buildStrip(spec.track)
	local ground = world:FindFirstChild("Ground") :: BasePart
	ground.Color = hex(GROUND[venue.id] or "#7cb342")
	ground.Material = if GROUND[venue.id] and venue.id ~= "farm" then Enum.Material.Sand else Enum.Material.Grass
	local carsFolder = Instance.new("Folder")
	carsFolder.Name = "RaceCars"
	carsFolder.Parent = world
	local meModel, meFlame, meSmoke = placeCar(car.model, car.color, LANE, carsFolder)
	local themModel, themFlame, themSmoke = placeCar(rival.model, rival.color, -LANE, carsFolder)
	local lamps = {}
	for _, d in (world:FindFirstChild("Tree") :: Model):GetChildren() do
		local i = d:GetAttribute("Lamp")
		if i then
			lamps[i :: number] = d :: BasePart
		end
	end

	-- The town's HUD steps aside for the race's own screen, laid out the same way (the web's
	-- 1280x800, scaled to fit); the race takes the camera.
	local root: Frame = ctx.gui
	local hudGui = root:FindFirstAncestorOfClass("ScreenGui") :: ScreenGui
	local raceGui = Ui.new("ScreenGui", { Name = "Race", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = hudGui.Parent })
	local screen = Ui.new("Frame", { Name = "RaceScreen", Size = root.Size, BackgroundTransparency = 1, Parent = raceGui })
	local hudScale = root:FindFirstChildOfClass("UIScale")
	local scale = Ui.new("UIScale", { Scale = if hudScale then hudScale.Scale else 1, Parent = screen })
	hudGui.Enabled = false
	TownCamera.setPaused(true)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local oldFov = cam.FieldOfView
	cam.FieldOfView = 55

	local conns: { RBXScriptConnection } = {}
	-- Follow the HUD's fit when the window changes.
	table.insert(conns, root:GetPropertyChangedSignal("Size"):Connect(function()
		screen.Size = root.Size
		scale.Scale = if hudScale then hudScale.Scale else 1
	end))
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		for _, c in conns do
			c:Disconnect()
		end
		RunService:UnbindFromRenderStep("DragStrip")
		raceGui:Destroy()
		carsFolder:Destroy()
		hudGui.Enabled = true
		cam.FieldOfView = oldFov
		TownCamera.setPaused(false)
		onExit()
	end

	-- ── Top: the title and the X ─────────────────────────────────────────────────────────────
	local title = `Drag Race vs {rival.name}`
	Ui.text({ Text = title, TextSize = 26, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.new(1, -200, 0, 34), Stroke = 2.5, Shadow = 3, Parent = screen })
	local quit = Ui.closeButton({ Name = "Leave", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(44, 44), Parent = screen }, function()
		if r.done then
			return
		end
		close()
	end)

	-- ── The lanes: how far along each car is ───────────────────────────────────────────────────
	local lanes = Ui.new("Frame", { Name = "Lanes", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.fromOffset(520, 64), BackgroundTransparency = 1, Visible = false, Parent = screen }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local laneDots = {}
	for i, lane in { { name = `You · {data.carDef(car.model).name}`, color = car.color }, { name = `{rival.name} · {rival.carName}`, color = rival.color } } do
		local row = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Color3.fromHex("#0d1b2a"), BackgroundTransparency = 0.35, Parent = lanes }, { Ui.corner(14), Ui.stroke(2, Ui.WHITE, 0.6) })
		Ui.text({ Text = lane.name, Body = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -46, 1, 0), TextTransparency = 0.15, Parent = row })
		Ui.new("Frame", { Name = "Finish", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(0.95, 0, 0, 3), Size = UDim2.new(0, 4, 1, -6), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = row })
		laneDots[i] = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.025, 0, 0.5, 0), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromHex(lane.color), ZIndex = 2, Parent = row }, { Ui.round(), Ui.stroke(2.5, Ui.WHITE) })
	end

	-- ── The venue chip, the countdown, and the calls ─────────────────────────────────────────
	local chip = Ui.shadowed({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 64), Size = UDim2.fromOffset(300, 58), Parent = screen }, { radius = 16, stroke = 2.5, drop = 3, colors = "navy" })
	local chipFace = chip:FindFirstChild("Face") :: Frame
	Ui.text({ Text = venue.icon or "🏁", TextSize = 30, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(44, 58), Parent = chipFace })
	Ui.text({ Text = venue.note or "Race venue", Body = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(60, 8), Size = UDim2.new(1, -70, 0, 16), TextColor3 = Color3.fromHex("#cfe0ff"), Parent = chipFace })
	Ui.text({ Text = venue.name or "Drag strip", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(60, 24), Size = UDim2.new(1, -70, 0, 26), Shadow = 2, Parent = chipFace })

	local count = Ui.text({ Text = "", TextSize = 120, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(400, 140), Stroke = 5, Shadow = 6, Parent = screen })
	local hint = Ui.text({ Text = "", TextSize = 22, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.4, 80), Size = UDim2.fromOffset(600, 30), Stroke = 2.5, Shadow = 2, Parent = screen })
	local callLabel = Ui.text({ Text = "", TextSize = 46, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(700, 60), Stroke = 4, Shadow = 4, Parent = screen })
	local spinNote = Ui.text({ Text = "💨 Wheelspin", TextSize = 22, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.fromOffset(300, 30), Stroke = 2.5, Shadow = 2, Visible = false, Parent = screen })
	local theirNote = Ui.text({ Text = `{rival.name}: 🔥 Boost!`, TextSize = 20, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 70), Size = UDim2.fromOffset(320, 28), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromHex("#ffab91"), Stroke = 2.5, Shadow = 2, Visible = false, Parent = screen })

	-- ── Bottom: BOOST under the left thumb, the tach in the middle, SHIFT under the right ─────
	local bottom = Ui.new("Frame", { Name = "Controls", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(1, -40, 0, 190), BackgroundTransparency = 1, Parent = screen })

	local boostBtn = Ui.new("TextButton", { Name = "Boost", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.fromOffset(130, 130), BackgroundColor3 = Color3.fromHex("#1b1f24"), BackgroundTransparency = 0.15, Parent = bottom }, { Ui.round(), Ui.stroke(4, Color3.fromHex("#ff9100")) })
	-- The tank: an orange disc that grows from the middle as clean driving fills it.
	local boostFill = Ui.new("Frame", { Name = "Fill", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0, 0), BackgroundColor3 = Color3.fromHex("#ff6d00"), BorderSizePixel = 0, Parent = boostBtn }, { Ui.round() })
	Ui.text({ Text = "🔥", TextSize = 44, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 50), ZIndex = 2, Parent = boostBtn })
	local boostText = Ui.text({ Text = "BOOST", TextSize = 20, Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 24), Stroke = 2, ZIndex = 2, Parent = boostBtn })

	local dialRing = Ui.stroke(4, Color3.fromHex("#cfd8dc"))
	local dial = Ui.new("Frame", { Name = "Tach", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(180, 180), BackgroundColor3 = Color3.fromHex("#1b1f24"), BackgroundTransparency = 0.15, Parent = bottom }, { Ui.round(), dialRing })
	local speed = Ui.text({ Text = "0 km/h", TextSize = 24, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.fromOffset(220, 30), Stroke = 2.5, Shadow = 2, Parent = dial })
	-- The arc as dots, every 6 degrees from -210 to 30, coloured for the band each refresh.
	local dots = {}
	for a = -210, 30, 6 do
		local rad = math.rad(a)
		local d = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(rad) * 70, 0.5, math.sin(rad) * 70), Size = UDim2.fromOffset(11, 11), BackgroundColor3 = Color3.fromHex("#37474f"), BorderSizePixel = 0, Parent = dial }, { Ui.round() })
		table.insert(dots, { f = d, at = (a + 210) / 240 })
	end
	local needle = Ui.new("Frame", { Name = "Needle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(132, 6), BackgroundTransparency = 1, ZIndex = 3, Parent = dial })
	Ui.new("Frame", { Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Color3.fromHex("#ff9100"), BorderSizePixel = 0, ZIndex = 3, Parent = needle }, { Ui.round() })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.fromHex("#eceff1"), ZIndex = 4, Parent = dial }, { Ui.round() })
	local gearText = Ui.text({ Text = "GEAR 1", TextSize = 20, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 30), Size = UDim2.fromOffset(120, 24), ZIndex = 4, Parent = dial })

	local shiftShadow, shiftFace = Ui.button({ Name = "Shift", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -6), Size = UDim2.fromOffset(200, 120), Parent = bottom }, "green", nil, { radius = 26, stroke = 4, drop = 6, dark = 0.35 })
	local _ = shiftShadow
	local shiftText = Ui.text({ Text = "HOLD ▶", TextSize = 36, Size = UDim2.fromScale(1, 1), Stroke = 3, Shadow = 3, Parent = shiftFace })
	local shiftGrad = shiftFace:FindFirstChildWhichIsA("UIGradient")

	-- ── Presses ───────────────────────────────────────────────────────────────────────────────
	local counting = false -- the countdown is running (after a moment to see the street)
	local held: InputObject? = nil
	local spaceHeld = false
	local function pressDown()
		if not counting or r.done or r.me.finished ~= nil then
			return
		end
		if not r.me.launched then
			if not r.held then
				DragRace.input(r, "down")
			end
		else
			DragRace.input(r, "down")
		end
	end
	local function pressUp()
		if r.held then
			DragRace.input(r, "up")
		end
	end
	local function fireBoost()
		if counting and r.tick >= DragRace.GO_TICK then
			DragRace.input(r, "boost")
		end
	end
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	-- Acts the instant a finger lands, and lets go when that finger lifts, wherever it is by then.
	table.insert(conns, shiftFace.InputBegan:Connect(function(input: InputObject)
		if isPress(input) and not held then
			held = input
			pressDown()
		end
	end))
	table.insert(conns, boostBtn.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			fireBoost()
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input == held or (held and input.UserInputType == Enum.UserInputType.MouseButton1 and held.UserInputType == Enum.UserInputType.MouseButton1) then
			held = nil
			if not spaceHeld then
				pressUp()
			end
		elseif input.KeyCode == Enum.KeyCode.Space then
			spaceHeld = false
			if not held then
				pressUp()
			end
		end
	end))
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			spaceHeld = true
			pressDown()
		elseif input.KeyCode == Enum.KeyCode.B or input.KeyCode == Enum.KeyCode.Up then
			fireBoost()
		end
	end))

	-- ── The result card ───────────────────────────────────────────────────────────────────────
	local function showResult(res: any)
		local won = res.won
		local overlay = Ui.new("Frame", { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#0a1630"), BackgroundTransparency = 0.45, ZIndex = 45, Parent = screen })
		local shadow, card = Ui.shadowed({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 470), Parent = overlay }, { radius = 24, stroke = 4, drop = 8, color = Ui.SHEET })
		local _ = shadow
		local function line(text: string, y: number, size: number, color: Color3?, props: { [string]: any }?)
			local p: { [string]: any } = { Text = text, TextSize = size, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, size + 6), TextColor3 = color or Ui.INK, Parent = card }
			for k, v in (props or {}) :: { [string]: any } do
				p[k] = v
			end
			return Ui.text(p)
		end
		local margin = if res.theirTime < math.huge then math.abs(res.theirTime - res.myTime) else nil
		line(if won then "🏆" else "🏁", 14, 54)
		line(if won then "YOU WIN!" elseif margin and margin < 0.3 then "SO CLOSE!" else "OUTRUN!", 76, 40, if won then Color3.fromHex("#2e7d32") else Color3.fromHex("#c62828"), { Stroke = 0 })
		line(`{if won then `You beat {rival.name}` else `{rival.name} took it`}{if margin then string.format(" by %.2fs", margin) else ""}`, 122, 17, Ui.MUTED, { Body = true })
		local y = 150
		if won and type(res.stars) == "number" then
			line(string.rep("★", res.stars) .. string.rep("☆", 3 - res.stars), y, 30, Color3.fromHex("#ffb300"))
			y += 38
		end
		-- Both times, the winner's in green.
		local times = Ui.new("Frame", { Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 56), BackgroundTransparency = 1, Parent = card }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }),
		})
		local rows: { { any } } = { { "You", res.myTime, won }, { rival.name, res.theirTime, not won } }
		for i, t in rows do
			local box = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.new(0.5, -5, 1, 0), BackgroundColor3 = if t[3] then Color3.fromHex("#e8f5e9") else Ui.WHITE, Parent = times }, { Ui.corner(12), Ui.stroke(2, if t[3] then Color3.fromHex("#43a047") else Ui.EDGE) })
			Ui.text({ Text = t[1], Body = true, TextSize = 12, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 4), TextColor3 = Ui.MUTED, Parent = box })
			local secs: number = t[2]
			Ui.text({ Text = if secs < math.huge then string.format("%.2fs", secs) else "DNF", TextSize = 22, Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 24), TextColor3 = Ui.INK, Parent = box })
		end
		y += 66
		-- How the run went: launch, perfect shifts, top speed.
		local launch = res.launch or ""
		local launchWord = if launch:sub(1, 7) == "PERFECT" then "Perfect" elseif launch:sub(1, 4) == "Good" then "Good" elseif launch:sub(1, 5) == "WHEEL" then "Spin" else "Bogged"
		line(`Launch {launchWord}  ·  Perfect {res.perfect}/{math.max(res.shifts, 1)}  ·  Top {race.kmh(res.top)} km/h`, y, 15, Ui.MUTED, { Body = true })
		y += 30
		local loot = `💵 +{money(res.coins or 0)}`
		if (res.trophies or 0) > 0 then
			loot ..= `   🏆 +{res.trophies}`
		end
		loot ..= `   ⭐ +{res.xp or 0} XP`
		line(loot, y, 22, Ui.INK)
		y += 40
		if not won and rival.pi > spec.myPi then
			line(`Your PI {spec.myPi} < their PI {rival.pi}. Upgrade your car in the Garage.`, y, 14, Color3.fromHex("#c62828"), { Body = true })
			y += 24
		end
		Ui.buy({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(200, 50), Parent = card }, if won then "Collect" else "Back", "green", close, 22)
		shadow.Size = UDim2.fromOffset(420, y + 84)
	end

	local function showFailed(why: string)
		local overlay = Ui.new("Frame", { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#0a1630"), BackgroundTransparency = 0.45, ZIndex = 45, Parent = screen })
		local _, card = Ui.shadowed({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(400, 220), Parent = overlay }, { radius = 24, stroke = 4, drop = 8, color = Ui.SHEET })
		Ui.text({ Text = "NO RESULT", TextSize = 34, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 40), TextColor3 = Ui.INK, Parent = card })
		Ui.text({ Text = why, Body = true, TextSize = 16, Position = UDim2.fromOffset(20, 76), Size = UDim2.new(1, -40, 0, 50), TextWrapped = true, TextColor3 = Ui.MUTED, Parent = card })
		Ui.buy({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(180, 48), Parent = card }, "Back", "green", close, 20)
	end

	-- ── The loop: fixed steps of DragRace.DT, the picture every frame ─────────────────────────
	local acc = 0
	local wait = 1.2 -- seconds of the street before the countdown
	local sentFinish = false
	local runOut = { { z = 0, v = 0 }, { z = 0, v = 0 } } -- each car past the line, coasting to a stop
	local camPos: Vector3? = nil
	local band = { lo = 0, hi = 0 }
	local bandKey = ""
	local lastCall: number = -1

	local function carZ(i: number, racer: any): number
		local ro = runOut[i]
		if racer.finished == nil then
			ro.z, ro.v = racer.dist * STUDS_PER_M, racer.speed * STUDS_PER_M
		end
		return ro.z
	end
	local function coast(dt: number)
		for i, racer in { r.me, r.them } do
			local ro = runOut[i]
			if racer.finished ~= nil and ro.z < len + RUN_OUT then
				local left = math.max(1, len + RUN_OUT * 0.92 - ro.z)
				ro.v = math.max(0, ro.v - (ro.v * ro.v) / (2 * left) * dt)
				ro.z = math.min(len + RUN_OUT, ro.z + ro.v * dt)
			end
		end
	end

	local function frame(dt: number)
		if wait > 0 then
			wait -= dt
			counting = wait <= 0
		else
			acc += math.min(0.1, dt)
			while acc >= DragRace.DT and not r.done do
				DragRace.step(r)
				acc -= DragRace.DT
			end
		end
		coast(dt)
		local me, th = r.me, r.them
		local mz, tz = carZ(1, me), carZ(2, th)
		meModel:PivotTo(CFrame.new(ORIGIN + Vector3.new(LANE, 0, mz)))
		themModel:PivotTo(CFrame.new(ORIGIN + Vector3.new(-LANE, 0, tz)))
		meFlame.CFrame = CFrame.new(ORIGIN + Vector3.new(LANE, 1.6, mz - 12))
		meFlame.Transparency = if me.burning then 0.15 else 1
		themFlame.CFrame = CFrame.new(ORIGIN + Vector3.new(-LANE, 1.6, tz - 12))
		themFlame.Transparency = if th.burning then 0.15 else 1
		;(meSmoke.Parent :: BasePart).CFrame = CFrame.new(ORIGIN + Vector3.new(LANE, 0.6, mz - 9))
		;(themSmoke.Parent :: BasePart).CFrame = CFrame.new(ORIGIN + Vector3.new(-LANE, 0.6, tz - 9))
		local t = DragRace.time(r)
		meSmoke.Enabled = r.spin or (me.launched and t < 0.6)
		themSmoke.Enabled = th.launched and t < 0.6

		-- The chase camera, off my rear bumper (RaceScene's chase view).
		local pace = math.min(1, me.speed / 80)
		local lead = math.max(mz, tz)
		local want = ORIGIN + Vector3.new(LANE * 0.5, 22, mz - 42 - pace * 8)
		local look = ORIGIN + Vector3.new(LANE * 0.3, 3, math.min(mz + 30 + (lead - mz) * 0.3, len + RUN_OUT + 40))
		camPos = if camPos then camPos:Lerp(want, math.min(1, dt * 8)) else want
		cam.CFrame = CFrame.lookAt(camPos :: Vector3, look)

		-- The light tree: one red lamp per count, all amber at GO.
		local n = if r.tick < DragRace.GO_TICK then 3 - math.floor(r.tick * DragRace.DT / DragRace.COUNT_STEP) else 0
		for i, lamp in lamps do
			local on = counting and ((n > 0 and i <= 4 - n) or (n == 0 and t < 1.5))
			lamp.Color = if not on then hex("#3a1010") elseif n == 0 then hex("#00e676") else hex("#ff1744")
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end

		-- Overlay.
		chip.Visible = not counting or n > 0
		lanes.Visible = n == 0 and t > 0.8
		for i, racer in { me, th } do
			laneDots[i].Position = UDim2.new(0.025 + math.min(1, racer.dist / spec.track) * 0.925, 0, 0.5, 0)
		end
		Ui.setText(count, if counting and n > 0 then tostring(n) elseif counting and t < 0.5 then "GO!" else "")
		Ui.setColor(count, if n == 0 then Color3.fromHex("#76ff03") else Ui.WHITE)
		local onLine = not me.launched
		local light = ""
		local b = if onLine then race.LAUNCH_BAND else race.shiftBand(me.gear, (spec.grip or {}).lo, (spec.grip or {}).hi)
		local rpm = me.rpm
		if me.finished == nil and not (not onLine and me.gear >= race.TOP_GEAR) then
			light = if rpm >= b.lo and rpm <= b.hi then "now" elseif rpm > b.hi then "late" elseif rpm >= b.lo - 0.12 then "soon" else ""
		end
		Ui.setText(hint, if onLine and counting and n > 0 then (if r.held then (if light == "now" then "Hold it there!" elseif light == "late" then "Too many revs!" else "Revving...") else "Hold the pedal: revs in the green") else "")
		if r.call and r.callTick ~= lastCall then
			lastCall = r.callTick
			Ui.setText(callLabel, r.call)
		end
		if r.call and (r.tick - r.callTick) * DragRace.DT > 0.9 then
			Ui.setText(callLabel, "")
		end
		spinNote.Visible = r.spin and callLabel.Text == ""
		theirNote.Visible = th.burning and not me.finished
		Ui.setText(speed, `{race.kmh(me.speed)} km/h`)
		Ui.setText(gearText, `GEAR {me.gear + 1}`)
		needle.Rotation = -210 + math.min(1.05, rpm) * 240
		local key = `{onLine}{b.lo}{b.hi}`
		if key ~= bandKey then
			bandKey = key
			band = b
			for _, d in dots do
				d.f.BackgroundColor3 = if d.at >= band.lo and d.at <= band.hi then (if onLine then hex("#ffd54f") else hex("#76ff03")) elseif d.at >= 0.95 then hex("#ff1744") else hex("#37474f")
			end
		end
		dialRing.Color = if light == "now" then hex("#76ff03") elseif light == "late" then hex("#ff1744") elseif light == "soon" then hex("#ffd54f") else hex("#cfd8dc")
		Ui.setText(shiftText, if onLine then "HOLD ▶" else "SHIFT ▲")
		if shiftGrad then
			local c = if light == "now" then Ui.COLORS.green elseif light == "late" then Ui.COLORS.red elseif light == "soon" then Ui.COLORS.gold else (if onLine then Ui.COLORS.green else { "#5aa9ff", "#2263d6" })
			shiftGrad.Color = Ui.seq(c[1], c[2])
		end
		local spent = me.boostUsed and not me.burning
		local fill = if spent then 0 else math.clamp(me.boost, 0, 1)
		boostFill.Size = UDim2.fromScale(fill, fill)
		Ui.setText(boostText, if spent then "USED" else "BOOST")
		boostBtn.BackgroundTransparency = if spent then 0.5 else 0.15

		-- Both across the line: the server races it again from the presses and pays it.
		if r.done and not sentFinish then
			sentFinish = true
			bottom.Visible = false
			quit.Visible = false
			Ui.setText(hint, "Checking the result...")
			task.spawn(function()
				task.wait(1.2)
				local ok, res = Remote.race("finish", r.events, true)
				if closed then
					return
				end
				Ui.setText(hint, "")
				if ok then
					showResult(res)
				else
					showFailed(if res == "too quick" then "That race finished too fast to count." else "The race server couldn't check that race. Your fuel was spent; try again.")
				end
			end)
		end
	end
	RunService:BindToRenderStep("DragStrip", Enum.RenderPriority.Camera.Value + 2, frame)
	return close
end

return DragStrip
