--!strict
-- Little extras in the town's sky, as the web game's scene/SkyExtras.tsx and SeasonFx.tsx (their
-- timing is the web's own game/skyExtras.ts, converted: Shared.Game.skyExtras):
--   the moon through the real lunar calendar, drawn in the sun's place at night (DayNight stands
--   Roblox's sun where the web's night light is);
--   the northern lights from 1 to 2 in the morning on the player's own clock, on clear nights:
--   from the town view a soft glow across the top of the screen, on foot curtains low over the
--   far city;
--   a shooting star every 20 to 60 seconds on clear nights;
--   something flying over every minute or two: an airliner, the news helicopter, and on fair days
--   a balloon, the banner plane or the blimp, now and then a cartoon rocket, nothing in a storm;
--   and the season's fliers over the town: falling leaves in fall, blossom petals in spring, snow
--   in winter.
-- The pictures are baked by tools/sky/build.mjs (Shared.Models.SkyImages) and the fly-by models
-- converted from the web's by tools/models ("fly:*" in Shared.Models.Catalog).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Models = Shared:WaitForChild("Models")
local clock = require(Game:WaitForChild("clock")) :: any
local weather = require(Game:WaitForChild("weather")) :: any
local extras = require(Game:WaitForChild("skyExtras")) :: any
local season = require(Game:WaitForChild("scene_season")) :: any
local Js = require(Game:WaitForChild("__js")) :: any
local Lualib = require(Game:WaitForChild("lualib_bundle")) :: any
local SkyImages = require(Models:WaitForChild("SkyImages")) :: any
local Catalog = require(Models:WaitForChild("Catalog")) :: any
local Builder = require(Models:WaitForChild("Builder")) :: any

local Town = require(script.Parent.Town)
local TownCamera = require(script.Parent.TownCamera)
local ClockShift = require(script.Parent.ClockShift)

local SkyExtras = {}

local STUDS = 10 -- per web unit
local TAU = 2 * math.pi

-- An uploaded picture as Roblox should ask for it (server/Sky looks up the image inside each
-- decal), or nil while it isn't uploaded.
local function image(id: number?): string?
	if not id or id == 0 then
		return nil
	end
	local found = workspace:GetAttribute(`Sky{id}`)
	return if type(found) == "string" then found else `rbxassetid://{id}`
end

local function night(): number
	return clock.nightAmount(clock.dayPhase(ClockShift.now()))
end

-- The player's own wall clock, as a web Date (whose hours read as UTC here).
local function localDate(): any
	local t = os.date("*t") :: any
	-- Days since 1970-01-01 of that calendar date (H. Hinnant's days_from_civil).
	local y = if t.month <= 2 then t.year - 1 else t.year
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local doy = (153 * (t.month + (if t.month > 2 then -3 else 9)) + 2) // 5 + t.day - 1
	local days = era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
	return Lualib.__TS__New(Js.JsDate, ((days * 24 + t.hour) * 60 + t.min) * 60000 + t.sec * 1000)
end

local gui: ScreenGui? = nil
local function layer(): ScreenGui
	if gui then
		return gui
	end
	local g = Instance.new("ScreenGui")
	g.Name = "SkyExtras"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	-- Under every screen and the HUD: it's the sky.
	g.DisplayOrder = -10
	local player = Players.LocalPlayer
	g.Parent = if player then player:WaitForChild("PlayerGui") else game:GetService("StarterGui")
	gui = g
	return g
end

-- ---- The moon ---------------------------------------------------------------------------------
-- Horizon.tsx draws its disc 0.034 rad across; the baked picture's disc fills 1/1.6 of it.
local MOON_SIZE = math.deg(0.034 * 2) * 1.6
local SUN_SIZE = 21 -- Roblox's own

local function moon(n: number)
	local sky = Lighting:FindFirstChildWhichIsA("Sky")
	if not sky then
		return
	end
	local phases = SkyImages.moon or {}
	local pic = nil
	if n > 0.5 and #phases > 0 then
		local phase = extras.moonPhase(ClockShift.now())
		pic = image(phases[math.floor(phase * #phases + 0.5) % #phases + 1])
	end
	local want = pic or "rbxasset://sky/sun.jpg"
	if sky.SunTextureId ~= want then
		sky.SunTextureId = want
	end
	-- The sun shrinks away as night falls and the moon grows in its place (and back at dawn), so
	-- neither pops in: night 0.35 to 0.5 the sun goes, 0.5 to 0.65 the moon comes.
	local size = if pic
		then MOON_SIZE * math.clamp((n - 0.5) / 0.15, 0, 1)
		else SUN_SIZE * math.clamp((0.5 - n) / 0.15, 0, 1)
	if math.abs(sky.SunAngularSize - size) > 0.01 then
		sky.SunAngularSize = size
	end
end

-- ---- Northern lights --------------------------------------------------------------------------
-- The strip is 14 curtains long (the web band's span); the town view shows about 3.2 per screen
-- height of width, the band on foot 14 across 2.6 radians of horizon low over the far city.
local A_CITY = -3 * math.pi / 4
local BAND_WIDE = 2.6
local BAND_R = 12000 -- studs: in front of the sky, behind the far land's hills
local EL0, EL1 = math.rad(1), math.rad(24)
local PANELS = 8
local STRIP_W, STRIP_H = 2048, 256

local aurora: { screen: ImageLabel?, band: { Part }, labels: { ImageLabel }, folder: Folder? } = { band = {}, labels = {} }

local function auroraBand(pic: string)
	local folder = Instance.new("Folder")
	folder.Name = "Aurora"
	for i = 1, PANELS do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		local h = BAND_R * (math.tan(EL1) - math.tan(EL0))
		p.Size = Vector3.new(2 * BAND_R * math.sin(BAND_WIDE / PANELS / 2) * 1.01, h, 1)
		local s = Instance.new("SurfaceGui")
		s.Face = Enum.NormalId.Front
		s.LightInfluence = 0
		s.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		s.CanvasSize = Vector2.new(STRIP_W / PANELS, STRIP_H)
		s.Parent = p
		local l = Instance.new("ImageLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Image = pic
		l.ImageRectSize = Vector2.new(STRIP_W / PANELS, STRIP_H)
		l.ImageRectOffset = Vector2.new((i - 1) * STRIP_W / PANELS, 0)
		l.Parent = s
		p.Parent = folder
		aurora.band[i] = p
		aurora.labels[i] = l
	end
	aurora.folder = folder
end

local function auroraScreen(pic: string)
	local l = Instance.new("ImageLabel")
	l.Name = "Aurora"
	l.BackgroundTransparency = 1
	-- The web's quad spans the top 35% of the screen.
	l.Size = UDim2.fromScale(1, 0.35)
	l.Image = pic
	l.Visible = false
	l.Parent = layer()
	-- Over the roofs its foot is soft, so it doesn't rule a line across the town.
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.55, 0), NumberSequenceKeypoint.new(1, 1) })
	fade.Parent = l
	aurora.screen = l
end

local auroraHour, auroraChecked = 0, -math.huge
local function northernLights(t: number, n: number, w: any, walking: boolean)
	if t - auroraChecked > 5 then
		auroraChecked = t
		auroraHour = extras.auroraHour(localDate())
	end
	local o = auroraHour * n * (if extras.skyPins:has("aurora") then 1 else extras.skyClear(w))
	local pic = image(SkyImages.aurora)
	if not pic then
		return
	end
	if not aurora.screen then
		auroraScreen(pic)
		auroraBand(pic)
	end
	local screen = aurora.screen :: ImageLabel
	local folder = aurora.folder :: Folder
	screen.Visible = not walking and o > 0.01
	local onFoot = walking and o > 0.01
	folder.Parent = if onFoot then workspace else nil
	-- The curtains drift slowly along (the web's rays move through them).
	local drift = 0.5 + 0.35 * math.sin(t * 0.01)
	if screen.Visible then
		local view = (workspace.CurrentCamera :: Camera).ViewportSize
		local span = math.min(STRIP_W * 0.9, 3.2 * view.X / math.max(1, view.Y) / 14 * STRIP_W)
		screen.ImageRectSize = Vector2.new(span, STRIP_H)
		screen.ImageRectOffset = Vector2.new((STRIP_W - span) * drift, 0)
		-- Over the roofs it's a soft glow, so the town stays easy to read.
		screen.ImageTransparency = 1 - math.clamp(o * 0.32 / 1.1 * 2, 0, 1)
	end
	if onFoot then
		local cam = (workspace.CurrentCamera :: Camera).CFrame.Position
		local y = BAND_R * (math.tan(EL0) + math.tan(EL1)) / 2
		local parts, cframes = {}, {}
		for i, p in aurora.band do
			local a = A_CITY - BAND_WIDE / 2 + (i - 0.5) * BAND_WIDE / PANELS
			local at = cam + Vector3.new(math.cos(a) * BAND_R, y, math.sin(a) * BAND_R)
			parts[i] = p
			cframes[i] = CFrame.lookAt(at, Vector3.new(cam.X, at.Y, cam.Z))
			aurora.labels[i].ImageTransparency = 1 - math.clamp(o, 0, 1)
		end
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- ---- Shooting stars ---------------------------------------------------------------------------
-- A thin streak across the top half of the screen: the tail fading out behind a bright head.
type Meteor = { at: number, dur: number, a: Vector2, b: Vector2 }
local meteor: Meteor? = nil
local nextMeteor = -1
local streak: Frame? = nil

local function streakFrame(): Frame
	if streak then
		return streak
	end
	local f = Instance.new("Frame")
	f.Name = "ShootingStar"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(0.95, 0.97, 1)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Visible = false
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.75, 0.55), NumberSequenceKeypoint.new(1, 0) })
	g.Parent = f
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = f
	f.Parent = layer()
	streak = f
	return f
end

local function shootingStars(t: number, n: number, w: any)
	if nextMeteor < 0 then
		nextMeteor = t + extras.meteorGap(math.random())
	end
	if t >= nextMeteor then
		nextMeteor = t + extras.meteorGap(math.random())
		local ok = if extras.skyPins:has("meteor") then n > 0.3 else n > 0.7 and extras.skyClear(w) > 0.5
		if ok then
			-- In pixels from the middle of the screen, y up, as the web's bird's-eye streak.
			local view = (workspace.CurrentCamera :: Camera).ViewportSize
			local side = if math.random() < 0.5 then -1 else 1
			local a = Vector2.new((math.random() - 0.5) * view.X * 0.7, view.Y * (0.15 + math.random() * 0.3))
			local ang = math.rad(20 + math.random() * 20)
			local len = math.min(view.X, view.Y) * (0.3 + math.random() * 0.15)
			meteor = { at = t, dur = 0.7 + math.random() * 0.5, a = a, b = a + Vector2.new(side * math.cos(ang) * len, -math.sin(ang) * len) }
		end
	end
	local m = meteor
	local f = streak
	if not m then
		if f then
			f.Visible = false
		end
		return
	end
	local k = (t - m.at) / m.dur
	if k >= 1 then
		meteor = nil
		return
	end
	f = streakFrame()
	-- The head races along; the tail trails a third of the path behind it.
	local head = 0.15 + 0.85 * k
	local tail = math.max(0, head - 0.35)
	local view = (workspace.CurrentCamera :: Camera).ViewportSize
	local p0 = m.a:Lerp(m.b, tail)
	local p1 = m.a:Lerp(m.b, head)
	local mid = (p0 + p1) / 2
	local d = p1 - p0
	f.Size = UDim2.fromOffset(math.max(1, d.Magnitude), 2)
	f.Position = UDim2.fromOffset(view.X / 2 + mid.X, view.Y / 2 - mid.Y)
	f.Rotation = math.deg(math.atan2(-d.Y, d.X))
	f.BackgroundTransparency = 1 - math.sin(math.pi * k) ^ 0.6 * 0.95
	f.Visible = true
end

-- ---- Fly-overs --------------------------------------------------------------------------------
-- Seconds to cross, how high over the town from the town view (web units), and on foot how far
-- up the sky (degrees) over a spot well ahead.
local FLIGHT = {
	plane = { dur = 34, y = 34, el = 9 },
	heli = { dur = 28, y = 24, el = 6 },
	banner = { dur = 40, y = 24, el = 6 },
	blimp = { dur = 95, y = 36, el = 8 },
	balloon = { dur = 80, y = 26, el = 6 },
	rocket = { dur = 7, y = 24, el = 2 },
}
local AHEAD = 180
local LIVERIES, BANNERS, BALLOONS = 5, 4, 4
-- The town's balloon, in one of its colourings, picked once a visit.
local townBalloon = math.random(1, BALLOONS)

type Flight = { kind: string, model: Model, at: number, dur: number, from: Vector3, to: Vector3, scale: number, walking: boolean }
local flight: Flight? = nil
local nextFlight = -1
local built: { [string]: Model } = {}
-- Each built fly-over's turning parts (Catalog.SPINS): the point and axis they turn about, how
-- fast, how far round they are, and each part where it sits at rest (from the model's middle).
type Spinner = { at: Vector3, axis: Vector3, speed: number, angle: number, parts: { { part: BasePart, rest: CFrame } } }
local spinners: { [Model]: { Spinner } } = {}
local spinParts: { BasePart } = {}
local spinFrames: { CFrame } = {}
local lastSpin = -1

-- The model for a fly-over, once every mesh it needs has arrived (else nil: it waits for the next).
local function flyModel(name: string): Model?
	local hit = built[name]
	if hit then
		return hit
	end
	local parts = Catalog.MODELS[name]
	if not parts then
		return nil
	end
	for _, p in parts do
		if p[1] == "m" and not Builder.hasMesh(p[13]) then
			return nil
		end
	end
	local m = Builder.build(name)
	if not m then
		return nil
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	m.Name = "FlyOver"
	local list: { Spinner } = {}
	for _, s in ((Catalog :: any).SPINS or {})[name] or {} do
		local parts = {}
		for _, i in s.parts do
			local part = m:FindFirstChild(tostring(i))
			if part and part:IsA("BasePart") then
				table.insert(parts, { part = part, rest = part.CFrame })
			end
		end
		table.insert(list, {
			at = Vector3.new(s.at[1], s.at[2], s.at[3]),
			axis = Vector3.new(s.axis[1], s.axis[2], s.axis[3]).Unit,
			speed = s.speed,
			angle = math.random() * 2 * math.pi,
			parts = parts,
		})
	end
	spinners[m] = list
	built[name] = m
	return m
end

local function modelFor(kind: string): Model?
	local look = math.random(0, 999)
	local name = if kind == "plane"
		then `fly:plane:{look % LIVERIES + 1}`
		elseif kind == "banner" then `fly:banner:{look % BANNERS + 1}`
		elseif kind == "balloon" then `fly:balloon:{townBalloon}`
		else `fly:{kind}`
	return flyModel(name)
end

-- Straight across the middle of the view, a little to one side, at its height: from the town
-- view the spot at that height over the middle of the screen, on foot a spot well ahead.
local function route(kind: string, model: Model, t: number, walking: boolean): Flight
	local f = (FLIGHT :: any)[kind]
	local cam = workspace.CurrentCamera :: Camera
	local fwd = cam.CFrame.LookVector
	local mid, span, scale
	if walking then
		scale = 4
		local ahead = Vector3.new(fwd.X, 0, fwd.Z)
		ahead = if ahead.Magnitude > 1e-3 then ahead.Unit else Vector3.new(0, 0, -1)
		mid = cam.CFrame.Position + ahead * AHEAD * STUDS
		mid += Vector3.new(0, AHEAD * STUDS * math.tan(math.rad(f.el)), 0)
		span = 420 * STUDS
	else
		scale = 1
		local view = cam.ViewportSize
		-- Where the middle of the screen meets the ground.
		local eye = cam.CFrame.Position
		local ground = if fwd.Y < -1e-3 then eye + fwd * (-eye.Y / fwd.Y) else eye
		mid = ground - fwd * (f.y * STUDS / math.max(0.2, -fwd.Y))
		local dist = (mid - cam.CFrame.Position).Magnitude
		local wide = 2 * dist * math.tan(math.rad(cam.FieldOfView) / 2) * view.X / math.max(1, view.Y)
		span = math.max(40 * STUDS, wide * 1.3)
	end
	-- Across the view, at any angle from straight across to about 40 degrees off it.
	local yaw = math.atan2(fwd.X, fwd.Z) + math.pi / 2 + (math.random() - 0.5) * 1.4 + (if math.random() < 0.5 then math.pi else 0)
	local vel = Vector3.new(math.sin(yaw), 0, math.cos(yaw))
	local side = Vector3.new(vel.Z, 0, -vel.X)
	mid += side * (math.random() - 0.5) * span * 0.25
	local from, to = mid - vel * span / 2, mid + vel * span / 2
	if kind == "rocket" then
		-- It starts low and climbs out of sight.
		from -= Vector3.new(0, 14 * scale * STUDS, 0)
	end
	if model:GetScale() ~= scale then
		model:ScaleTo(scale)
	end
	return {
		kind = kind,
		model = model,
		at = t,
		dur = f.dur * (0.85 + math.random() * 0.3),
		from = from,
		to = to,
		scale = scale,
		walking = walking,
	}
end

local function flyOvers(t: number, n: number, w: any, walking: boolean)
	-- The first one comes over a little sooner than the rest.
	if nextFlight < 0 then
		nextFlight = t + extras.flyByGap(math.random()) * 0.3
	end
	if not flight and t >= nextFlight then
		local fair = w.rain < 0.1 and w.snow < 0.1 and w.wind < 0.5 and w.haze < 0.4
		local storm = (w.mix.storm or 0) + (w.mix.blizzard or 0) > 0.5
		local kind = extras.pickFlyBy(math.random(), math.random(), n, fair, storm)
		local model = kind and modelFor(kind)
		if kind and model then
			flight = route(kind, model, t, walking)
		else
			nextFlight = t + extras.flyByGap(math.random())
		end
	end
	local s = flight
	if not s then
		return
	end
	local k = (t - s.at) / s.dur
	-- Switching view mid-flight ends it: its path was set for the other view.
	if k >= 1 or s.walking ~= walking then
		s.model.Parent = nil
		flight = nil
		nextFlight = t + extras.flyByGap(math.random())
		return
	end
	local at = s.from:Lerp(s.to, k)
	local vel = (s.to - s.from).Unit
	local heading = math.atan2(vel.X, vel.Z)
	local u = s.scale * STUDS
	local turn
	if s.kind == "balloon" then
		-- Bobs gently and turns slowly as it drifts.
		at += Vector3.new(0, math.sin(t * 0.4) * 0.6 * u, 0)
		turn = CFrame.Angles(0, t * 0.05, 0)
	elseif s.kind == "heli" then
		-- Nose down as it pushes along, rocking a little.
		turn = CFrame.fromEulerAnglesYXZ(0.14 + math.sin(t * 0.8) * 0.02, heading, math.sin(t * 0.6) * 0.04)
	elseif s.kind == "blimp" then
		-- Pitches and wallows gently.
		at += Vector3.new(0, math.sin(t * 0.3) * 0.3 * u, 0)
		turn = CFrame.fromEulerAnglesYXZ(math.sin(t * 0.25) * 0.03, heading, 0)
	elseif s.kind == "rocket" then
		-- Climbs as it goes, nose first.
		at += Vector3.new(0, k * k * 40 * u, 0)
		local dir = ((s.to - s.from) + Vector3.new(0, 80 * k * u, 0)).Unit
		local axis = Vector3.yAxis:Cross(dir)
		turn = if axis.Magnitude > 1e-4 then CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(dir.Y, -1, 1))) else CFrame.identity
	else
		turn = CFrame.Angles(0, heading, 0)
	end
	local pivot = CFrame.new(at) * turn
	s.model:PivotTo(pivot)
	-- Rotors and props turn (FlyByModels.tsx useFrame), about their own hubs.
	local dt = if lastSpin < 0 then 0 else math.min(t - lastSpin, 0.1)
	lastSpin = t
	local n = 0
	for _, sp in spinners[s.model] or {} do
		sp.angle += dt * sp.speed
		local hub = sp.at * s.scale
		local spin = pivot * CFrame.new(hub) * CFrame.fromAxisAngle(sp.axis, sp.angle) * CFrame.new(-hub)
		for _, p in sp.parts do
			n += 1
			spinParts[n] = p.part
			spinFrames[n] = spin * (p.rest - p.rest.Position + p.rest.Position * s.scale)
		end
	end
	for j = #spinParts, n + 1, -1 do
		spinParts[j] = nil
		spinFrames[j] = nil
	end
	if n > 0 then
		workspace:BulkMoveTo(spinParts, spinFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if s.model.Parent ~= workspace then
		s.model.Parent = workspace
	end
end

-- ---- The season's fliers ----------------------------------------------------------------------
-- SeasonFx.tsx: over the town's middle, 56 x 56 web units, falling from 22 up; a shared breeze
-- leans them all one way, blowing much harder in windy weather. Nothing new takes off at night or
-- while rain knocks leaves and petals down; the last ones still drift to the ground.
local FX = {
	fall = { colors = { "#ff7a1a", "#ffa726", "#e53935", "#ffd54f", "#d2691e" }, fall = 1.1, sway = 1.2, size = 0.6, kind = "leaf", count = 60 },
	winter = { colors = { "#ffffff", "#f1f5ff" }, fall = 1.6, sway = 0.5, size = 0.15, kind = "flake", count = 320 },
	spring = { colors = { "#f8bbd0", "#ffffff", "#f48fb1" }, fall = 0.8, sway = 1.4, size = 0.4, kind = "petal", count = 280 },
}
local SPAN, TOP = 56, 22
-- A leaf shape is about 1.2 across; snow is a few pixels from the town view.
local SHAPE = { leaf = 1.2, petal = 1, flake = 1 }

local fliers: { emitters: { ParticleEmitter }, fx: any, walking: boolean? }? = nil

function SkyExtras.seasonStart(origin: Vector3)
	local fx = (FX :: any)[season.SEASON]
	local pic = fx and image(SkyImages.fliers and SkyImages.fliers[fx.kind])
	if not fx or not pic then
		return
	end
	local area = Instance.new("Part")
	area.Name = "SeasonFliers"
	area.Anchored = true
	area.CanCollide = false
	area.CanQuery = false
	area.CanTouch = false
	area.Transparency = 1
	area.Size = Vector3.new(SPAN * STUDS, 1, SPAN * STUDS)
	area.CFrame = CFrame.new(origin + Vector3.new(0, TOP * STUDS, 0))
	area.Parent = workspace
	local life = TOP / (fx.fall * 0.7)
	local emitters = {}
	for _, c in fx.colors do
		local e = Instance.new("ParticleEmitter")
		e.Texture = pic
		e.Color = ColorSequence.new(Color3.fromHex(c))
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.EmissionDirection = Enum.NormalId.Bottom
		e.Speed = NumberRange.new(fx.fall * 0.7 * STUDS, fx.fall * 1.3 * STUDS)
		e.Lifetime = NumberRange.new(life * 0.8, life)
		e.Rate = fx.count / life / #fx.colors
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = if fx.kind == "flake" then NumberRange.new(0, 0) else NumberRange.new(-160, 160)
		e.SpreadAngle = Vector2.new(15, 15)
		e.LightInfluence = 1
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.04, if fx.kind == "flake" then 0.1 else 0), NumberSequenceKeypoint.new(0.95, 0), NumberSequenceKeypoint.new(1, 1) })
		e.Drag = 0.6
		e.Parent = area
		table.insert(emitters, e)
	end
	fliers = { emitters = emitters, fx = fx }
end

local breezeAt = -math.huge
local function seasonFliers(t: number, n: number, w: any, walking: boolean)
	local s = fliers
	if not s then
		return
	end
	local fx = s.fx
	local on = not (n > 0.5 or w.rain > 0.15)
	-- Sized to read from the town view; on foot leaves and petals shrink (snow stays a few dots).
	if s.walking ~= walking then
		s.walking = walking
		local k = if walking and fx.kind ~= "flake" then 0.4 else 1
		local size = fx.size * SHAPE[fx.kind] * k * STUDS
		for _, e in s.emitters do
			e.Size = NumberSequence.new(size * 0.75, size * 1.25)
		end
	end
	-- The breeze settles where it blows them (drag towards the wind's own speed), checked now and then.
	if t - breezeAt > 0.5 then
		breezeAt = t
		local gust = (0.6 + math.sin(t * 0.23) * 0.5 + math.max(0, math.sin(t * 0.61)) * 0.9) * (1 + w.wind * 3)
		local wind = Vector3.new(gust * fx.sway, 0, gust * fx.sway * 0.4) * STUDS
		for _, e in s.emitters do
			e.Enabled = on
			e.Acceleration = (wind - Vector3.new(0, fx.fall * STUDS, 0)) * e.Drag
		end
	end
end

-- ---- Running it --------------------------------------------------------------------------------

-- One frame, t seconds in (tools/emulate calls it directly for previews).
function SkyExtras.tick(t: number, walking: boolean)
	local n = night()
	local w = weather.weatherNow()
	moon(n)
	northernLights(t, n, w, walking)
	shootingStars(t, n, w)
	flyOvers(t, n, w, walking)
	seasonFliers(t, n, w, walking)
end

function SkyExtras.start()
	task.spawn(function()
		local folder = nil
		while not folder do
			folder = Town.folder()
			if not folder then
				task.wait(0.5)
			end
		end
		-- The pictures' ids resolve on the server shortly after it starts.
		task.wait(2)
		SkyExtras.seasonStart((folder :: Folder):GetAttribute("Origin") :: any)
		local t = 0
		RunService.RenderStepped:Connect(function(dt)
			t += math.min(dt, 0.1)
			SkyExtras.tick(t, TownCamera.isWalking())
		end)
	end)
end

return SkyExtras
