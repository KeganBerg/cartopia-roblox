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
local Paint = require(ReplicatedStorage.Shared.Models.Paint)
local Builder = require(ReplicatedStorage.Shared.Models.Builder)
local Mods = require(ReplicatedStorage.Shared.Models.Mods)
local Panels = require(ReplicatedStorage.Shared.Models.Panels)
local Trim = require(ReplicatedStorage.Shared.Models.Trim)
local Skins = require(ReplicatedStorage.Shared.Models.Skins)
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Mastery = require(script.Parent.Mastery)
local TownCamera = require(script.Parent.TownCamera)
local DayNight = require(script.Parent.DayNight)
local Sfx = require(script.Parent.Sounds.Sfx)
local Builder = require(ReplicatedStorage.Shared.Models.Builder) :: any
local venues = require(Game.scene_venues) :: any

local DragStrip = {}

-- The web's race scene in studs: 0.25 world units per metre of race, 10 studs per unit.
local S = 10 -- studs per web unit
local STUDS_PER_M = 0.25 * S
local LANE = 0.75 * S -- each car's lane, either side of the middle
local ROAD = 1.6 * S -- half the street's width (RaceVenues ROAD)
local WALK = 1.0 * S -- the sidewalk or shoulder (RaceVenues WALK)
local RUN_OUT = 150 * STUDS_PER_M -- past the line, where the cars slow to a stop
local DRESS = 150 * S -- how far past the finish the street is lined (RaceScene DRESS)
local CAR_SCALE = 1.4
local ORIGIN = Vector3.new(-30000, 0, 0) -- far from every town and its countryside

-- Main Street is lined with shops (RaceScene useStreet's FALLBACK row), a tree or palm after each.
local FALLBACK = { "pizza", "donut", "burger", "diner", "house", "motel", "carwash", "tires", "gas", "bowling", "icecream", "house" }

local LIT = { "#ff1744", "#ff1744", "#ffab00" } -- the countdown's lamps, lit

local strip: Model? = nil
local horizon: Model? = nil
local stripKey = ""

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

-- Main Street's shops on their paving, facing the road, with a tree or palm in the gap after each
-- (RaceScene useStreet and StreetShops streetPieces).
-- len: the strip's length in web units.
local function mainStreet(into: Model, len: number)
	local slots = {}
	for _, side in { -1, 1 } do
		local z = -10 + (if side > 0 then 1.5 else 0)
		local i = if side > 0 then 3 else 0
		while z < (DRESS / S + len) + 30 do
			local def = FALLBACK[i % #FALLBACK + 1]
			i += 1
			local w = data.buildingDef(def).w * data.TILE
			table.insert(slots, { z = z + w / 2, side = side, def = def })
			z += w + 1.4
		end
	end
	for i, sl in slots do
		local d = data.buildingDef(sl.def)
		local depth = d.h * data.TILE
		local turn = if sl.side < 0 then math.pi / 2 else -math.pi / 2
		local at = CFrame.new(ORIGIN + Vector3.new(sl.side * (1.6 + 1.0 + depth / 2 + 0.1), 0, sl.z) * S) * CFrame.Angles(0, turn, 0)
		part({ Name = "Paving", Size = Vector3.new(d.w * data.TILE - 0.1, 0.05, depth - 0.1) * S, CFrame = at * CFrame.new(0, 0.2, 0), Color = hex("#eadfc8"), Material = Enum.Material.Pavement }, into)
		local b = library("Buildings", sl.def)
		if b then
			b:PivotTo(at)
			b.Parent = into
		end
		local tree = library("Buildings", if (i - 1) % 3 ~= 0 then "tree" else "palm")
		if tree then
			tree:PivotTo(CFrame.new(ORIGIN + Vector3.new(sl.side * (1.6 + 1.0 + 0.9), 0, sl.z + d.w + 0.7) * S))
			tree.Parent = into
		end
	end
end

-- The countdown bar hanging under the START banner (RaceScene StartLights): three lamps, the reds
-- coming on with the count and all green at GO. Returns the bar and its lamps, left to right as the
-- drivers see them.
local function startLights(into: Model): (Model, { BasePart })
	local bar = Instance.new("Model")
	bar.Name = "StartLights"
	bar.Parent = into
	local at = function(x: number, y: number, z: number): CFrame
		return CFrame.new(ORIGIN + Vector3.new(x, 2.5 + y, -0.85 + z) * S)
	end
	part({ Name = "Hanger", Size = Vector3.new(0.05, 0.3, 0.05) * S, CFrame = at(0, 0.32, 0), Color = hex("#263238") }, bar)
	part({ Name = "Box", Size = Vector3.new(1.25, 0.36, 0.14) * S, CFrame = at(0, 0, 0), Color = hex("#212121") }, bar)
	local lamps = {}
	for i = 0, 2 do
		local lamp = part({ Name = `Lamp{i + 1}`, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 0.26, 0.26) * S, CFrame = at((1 - i) * 0.38, 0, -0.08) * CFrame.Angles(0, math.pi / 2, 0), Color = hex("#3a1010") }, bar)
		lamps[i + 1] = lamp
	end
	return bar, lamps
end

-- The strip at a venue: the web game's own drag strip and scenery (Shared.Models.RaceScenery,
-- converted from RaceScene.tsx and RaceVenues.tsx), Main Street's shops, and the far horizon, which
-- rides along with the camera. Built once per venue, then kept.
-- dist: the race's distance ("quarter", "half" or "mile"); the longer strips are their own models,
-- their street and finish line further on, under the quarter mile's horizon. A build without
-- the longer one races on the quarter mile's street, the finish line just isn't drawn.
local function buildStrip(venueId: string, dist: string?): (Model, Model?)
	local long = if dist and dist ~= "quarter" and Builder.has(`race:{venueId}:{dist}`) then dist else nil
	local key = `{venueId}:{long or "quarter"}`
	if strip and stripKey == key then
		return strip, horizon
	end
	if strip then
		strip:Destroy()
	end
	local m = Instance.new("Model")
	m.Name = "DragStrip"
	local scene = (if long then Builder.build(`race:{venueId}:{long}`) else Builder.build(`race:{venueId}`)) or Builder.build("race:main")
	if scene then
		scene.Name = "Scene"
		scene:PivotTo(CFrame.new(ORIGIN))
		scene.Parent = m
	end
	local far = Builder.build(`race:{venueId}:far`)
	if far then
		far.Name = "Horizon"
		far:PivotTo(CFrame.new(ORIGIN))
		far.Parent = m
	end
	if venueId == "main" then
		mainStreet(m, (if long == "half" then 200 elseif long == "mile" then 400 else 100))
	end
	startLights(m)
	m.Parent = workspace
	strip, horizon, stripKey = m, far, key
	return m, far
end

-- A car on the strip, with its boost flame and wheelspin smoke.
local function placeCar(model: string, job: Paint.Job, hat: any, mods: { string }?, panels: any, trim: any, skin: string?, modSkin: any, x: number, parent: Instance): (Model, BasePart, ParticleEmitter)
	local m = library("Cars", model) or Instance.new("Model")
	Paint.apply(m, job, library("Stripes", model))
	Panels.apply(m, model, panels, job.finish, Builder.build)
	Trim.apply(m, model, trim, job.color)
	Paint.wearHat(m, model, hat, Builder.build)
	Mods.fit(m, model, mods, Builder.build)
	Skins.apply(m, skin, modSkin)
	-- The racers are drawn 1.4 times their town size, as RaceScene draws them.
	local pivot = m:GetPivot()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size *= CAR_SCALE
			d.CFrame = pivot * (rel - rel.Position + rel.Position * CAR_SCALE)
		end
	end
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

-- A button on the result card: its words, its colour, and what it does once the race screen
-- has closed (instead of going back to the menu).
export type Button = { text: string, kind: string?, go: (() -> ())? }
-- What a mode adds to the race screen: its title, and the result card's heading, the rival's
-- words and buttons for a result (each left out for the usual ones).
-- view: draws extra lines on the result card from height y down (a time trial's best, the Daily
-- Run's par) and returns the height it reached.
export type Extras = {
	title: string?,
	icon: string?,
	view: ((card: Frame, res: any, y: number) -> number)?,
	heading: ((res: any) -> string?)?,
	quote: ((res: any) -> string?)?,
	buttons: ((res: any) -> { Button }?)?,
}

-- Opens the race. started: what Remote.race("start") answered ({ spec, rival, mode, venue });
-- car: the race car (an owned car); onExit: back to the race menu.
function DragStrip.run(ctx: any, started: any, car: any, onExit: () -> (), extras: Extras?)
	local spec, rival, venue = started.spec, started.rival, started.venue or {}
	local ex: Extras = extras or {}
	local r = DragRace.new(spec)
	local len = spec.track * STUDS_PER_M
	local look = venues.venue(venue.id or "main")
	local world, far = buildStrip(look.id, venue.dist)
	-- The venue's haze, as RaceScene's fog: the far end of the road is lost in it.
	DayNight.setRaceFog({ color = hex(look.fog), near = look.fogNear * S, far = look.fogFar * S })
	local carsFolder = Instance.new("Folder")
	carsFolder.Name = "RaceCars"
	carsFolder.Parent = world
	local meModel, meFlame, meSmoke = placeCar(car.model, Paint.jobOf(car), car.hat, car.mods, car.panels, car.trim, car.skin, car.modSkin, LANE, carsFolder)
	local themModel, themFlame, themSmoke = placeCar(rival.model, { color = rival.color }, nil, rival.mods, rival.panels, rival.trim, rival.skin, rival.modSkin, -LANE, carsFolder)
	if spec.ghost then
		-- A solo run's ghost: see-through, as the web's trial ghost.
		for _, d in themModel:GetDescendants() do
			if d:IsA("BasePart") then
				d.Transparency = math.max(d.Transparency, 0.6)
				d.CastShadow = false
			end
		end
	end
	local bar = world:FindFirstChild("StartLights") :: Model
	local lamps = {}
	for i = 1, 3 do
		lamps[i] = bar:FindFirstChild(`Lamp{i}`) :: BasePart
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
		DayNight.setRaceFog(nil)
		cam.FieldOfView = oldFov
		TownCamera.setPaused(false)
		onExit()
	end
	-- Closes the race screen and does `go` instead of going back to the menu.
	local function leave(go: () -> ())
		local back = onExit
		onExit = go
		close()
		onExit = back
	end

	-- ── Top: the title and the X ─────────────────────────────────────────────────────────────
	local title = ex.title or `Drag Race vs {rival.name}`
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
	-- Each car's skill, flashed while it is working (Race.tsx skill-flash); the rival's takes the
	-- place of its boost note.
	local mySkill = spec.mySkill and data.SKILLS[spec.mySkill]
	local theirSkill = rival.skill and data.SKILLS[rival.skill]
	local skillNote = Ui.text({ Text = if mySkill then `{mySkill.icon} {mySkill.name}!` else "", TextSize = 24, AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0, 20, 0, 70), Size = UDim2.fromOffset(320, 30), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromHex("#ffe082"), Stroke = 2.5, Shadow = 2, Visible = false, Parent = screen })
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
			-- A shift: the good click on a perfect (or smooth) one, as Race.tsx press.
			local perfect = r.perfect
			if DragRace.input(r, "down") then
				Sfx.shift(r.perfect > perfect)
			end
		end
	end
	local function pressUp()
		if r.held then
			DragRace.input(r, "up")
		end
	end
	local function fireBoost()
		if counting and r.tick >= DragRace.GO_TICK then
			if DragRace.input(r, "boost") then
				Sfx.boost()
			end
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
		if won then
			Sfx.win()
		else
			Sfx.lose()
		end
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
		line(ex.icon or (if won then "🏆" else "🏁"), 14, 54)
		local heading = (ex.heading and ex.heading(res)) or (if won then "YOU WIN!" elseif margin and margin < 0.3 then "SO CLOSE!" else "OUTRUN!")
		line(heading, 76, 40, if won then Color3.fromHex("#2e7d32") else Color3.fromHex("#c62828"), { Stroke = 0 })
		line(`{if won then `You beat {rival.name}` else `{rival.name} took it`}{if margin then string.format(" by %.2fs", margin) else ""}`, 122, 17, Ui.MUTED, { Body = true })
		local y = 150
		-- What the rival says about it (Rivals.tsx RivalResult's bubble).
		local quote = ex.quote and ex.quote(res)
		if quote then
			local bubble = Ui.new("Frame", { Position = UDim2.fromOffset(30, y), Size = UDim2.new(1, -60, 0, 34), BackgroundColor3 = Ui.WHITE, Parent = card }, { Ui.corner(12), Ui.stroke(2, Ui.LINE) })
			Ui.text({ Text = quote, Body = true, TextSize = 14, TextWrapped = true, TextColor3 = Ui.INK, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Parent = bubble })
			y += 44
		end
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
		local coins = res.coins or 0
		local loot = if coins < 0 then `💸 -{money(-coins)}` else `💵 +{money(coins)}`
		if (res.bucks or 0) > 0 then
			loot ..= `   💎 +{res.bucks}`
		end
		if (res.trophies or 0) > 0 then
			loot ..= `   🏆 +{res.trophies}`
		end
		if (res.xp or 0) > 0 then
			loot ..= `   ⭐ +{res.xp} XP`
		end
		if ex.view then
			y = ex.view(card, res, y)
		end
		-- A solo run pays nothing, so it shows no loot.
		if coins ~= 0 or (res.bucks or 0) > 0 or (res.trophies or 0) > 0 or (res.xp or 0) > 0 then
			line(loot, y, 22, Ui.INK)
			y += 40
		end
		-- A paint rival's colour, won (PaintRivals.tsx PaintPrizePopup).
		if res.paint then
			local name = "Paint"
			for _, p in data.PAINTS do
				if p.color == res.paint then
					name = p.name
				end
			end
			local row = Ui.new("Frame", { Name = "PaintPrize", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(300, 34), BackgroundColor3 = Color3.fromHex("#fff8e1"), Parent = card }, { Ui.corner(12), Ui.stroke(2, Color3.fromHex("#ffb300")) })
			Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromHex(res.paint), Parent = row }, { Ui.round(), Ui.stroke(2, Ui.LINE) })
			Ui.text({ Text = `{name} unlocked`, TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -50, 1, 0), Parent = row })
			y += 44
		end
		-- What the race unlocked in mastery (ClassCups.tsx MasteryPrizePopup).
		if res.mastery then
			y = Mastery.prize(card, res.mastery, y)
		end
		if not won and rival.pi > spec.myPi then
			line(`Your PI {spec.myPi} < their PI {rival.pi}. Upgrade your car in the Garage.`, y, 14, Color3.fromHex("#c62828"), { Body = true })
			y += 24
		end
		local buttons: { Button } = (ex.buttons and ex.buttons(res)) or { { text = if won then "Collect" else "Back" } }
		local row = Ui.new("Frame", { Name = "Buttons", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.new(1, -40, 0, 50), BackgroundTransparency = 1, Parent = card }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, b in buttons do
			local w = if #buttons == 1 then 200 else math.floor((380 - 10 * (#buttons - 1)) / #buttons)
			local _s, face = Ui.buy({ LayoutOrder = i, Size = UDim2.fromOffset(w, 50), Parent = row }, b.text, b.kind or "green", function()
				if b.go then
					leave(b.go)
				else
					close()
				end
			end, if #buttons == 1 then 22 else 16)
			face.Name = `Button{i}`
		end
		shadow.Size = UDim2.fromOffset(420, y + 84)
	end

	local function showFailed(why: string)
		Sfx.lose()
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
	local lastCount = -1 -- the count last beeped (3, 2, 1, then 0 at GO)
	local wasLaunched = false

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
		meFlame.CFrame = CFrame.new(ORIGIN + Vector3.new(LANE, 1.6 * CAR_SCALE, mz - 12 * CAR_SCALE))
		meFlame.Transparency = if me.burning then 0.15 else 1
		themFlame.CFrame = CFrame.new(ORIGIN + Vector3.new(-LANE, 1.6 * CAR_SCALE, tz - 12 * CAR_SCALE))
		themFlame.Transparency = if th.burning then 0.15 else 1
		;(meSmoke.Parent :: BasePart).CFrame = CFrame.new(ORIGIN + Vector3.new(LANE, 0.6, mz - 9 * CAR_SCALE))
		;(themSmoke.Parent :: BasePart).CFrame = CFrame.new(ORIGIN + Vector3.new(-LANE, 0.6, tz - 9 * CAR_SCALE))
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

		-- The far hills and skyline ride along with the camera (RaceVenues Horizon).
		if far then
			far:PivotTo(CFrame.new(ORIGIN.X, ORIGIN.Y, (camPos :: Vector3).Z))
		end

		-- The countdown bar: the reds come on with the count (amber on the last), all green at GO.
		-- It drops out of sight just before the camera reaches it, as on the web.
		local n = if r.tick < DragRace.GO_TICK then 3 - math.floor(r.tick * DragRace.DT / DragRace.COUNT_STEP) else 0
		if counting and n ~= lastCount and n >= 0 and n <= 3 then
			lastCount = n
			Sfx.countdown(n == 0)
		end
		-- Off the line at GO: the launch's call gets a shift click (Race.tsx callLaunch).
		if r.me.launched and not wasLaunched then
			wasLaunched = true
			Sfx.shift(type(r.launch) == "string" and r.launch:sub(1, 7) == "PERFECT")
		end
		for i, lamp in lamps do
			local on = counting and (n == 0 or i <= 4 - n)
			lamp.Color = if not on then hex("#3a1010") elseif n == 0 then hex("#00e676") else hex(LIT[i])
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		local camAt = (camPos :: Vector3) - ORIGIN
		local shown = camAt.Z < (-0.85 - 1.6) * S or camAt.Y < 2 * S or camAt.Y > 3.6 * S
		for _, d in bar:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if shown then 0 else 1
			end
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
		local theirsOn = theirSkill ~= nil and r.theirSkillOn
		Ui.setText(theirNote, if theirsOn then `{rival.name}: {theirSkill.icon} {theirSkill.name}!` else `{rival.name}: 🔥 Boost!`)
		theirNote.Visible = not r.done and (theirsOn or th.burning)
		skillNote.Visible = mySkill ~= nil and r.mySkillOn and not r.done
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
		-- Where the tutorial's hand points (client/Popups/Tutorial): the pedal on the line, then
		-- SHIFT each time its light says now (the web's .shift-btn.launch and .shift-btn.now).
		local tut = if me.finished ~= nil or r.done then nil elseif onLine then (if counting then "launch" else nil) elseif light == "now" then "shift-now" else nil
		if shiftFace:GetAttribute("Tut") ~= tut then
			shiftFace:SetAttribute("Tut", tut)
		end
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
