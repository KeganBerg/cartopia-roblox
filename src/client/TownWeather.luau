--!strict
-- The town's weather, as the web game's scene/Weather.tsx, weatherLook.ts and the weather half of
-- Atmosphere.tsx / skyFx.ts: the shared schedule (game/weather.ts, converted: every player sees
-- the same shower at the same moment) drives
--   - the light: overcast dims and greys the sun and the colour grade, snow brightens, a summer
--     scorcher warms it, lightning flashes it (weatherLook);
--   - the haze: fog, mist and whiteouts thicken the town's Atmosphere towards the haze colour;
--   - rain, snow and splashes: particle emitters in a box over the ground at the middle of the
--     view, so the weather always fills the screen (Precip);
--   - lightning in storms: a jagged bolt of beams somewhere in view, then weather.strike() so a
--     sound can rumble (onThunder);
--   - a rainbow over the town after a shower, while the streets are still wet;
--   - the ground: roads dark and wet in the rain, lawns and lots white and roads slushy in snow.
--
-- DayNight owns the light and sets it a few times a second; this nudges what it set, every frame,
-- from what DayNight last wrote (see `nudge`), so the two never fight or compound. The skybox and
-- horizon are not touched. During a race (DayNight.raceFog) the town's weather stands down.
--
-- Cost: three invisible parts (the sky box, the ground plate and a fixed anchor) carry every
-- emitter, beam and attachment; nothing is created per drop or per frame.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local weather = require(Game:WaitForChild("weather")) :: any
local clock = require(Game:WaitForChild("clock")) :: any
local season = require(Game:WaitForChild("scene_season")) :: any
local DayNight = require(script.Parent.DayNight)

local TownWeather = {}

local U = 10 -- studs per web unit (Catalog.SCALE, TownCamera.STUDS_PER_UNIT)

-- Weather.tsx SIZES: how many drops, splashes and flakes at full strength (small: phones).
-- Roblox draws particles on the CPU's side of the budget, so the town keeps half the web's drops.
local SIZES = {
	small = { rain = 700, splash = 130, snow = 550 },
	big = { rain = 1400, splash = 260, snow = 1100 },
}
local RAIN_EMITTERS = 4 -- the downpour split over a few emitters, so no one emitter's rate is huge

local RAIN_DAY = Color3.fromHex("#d6e2ee")
local RAIN_NIGHT = Color3.fromHex("#8c9ab5")
local SNOW_NIGHT = Color3.fromHex("#9fabc4")
local SPLASH = Color3.fromHex("#e3edf7")
local HAZE_DAY = Color3.fromHex("#cacbd2")
local HAZE_SNOW = Color3.fromHex("#eef2f7")
local HAZE_NIGHT = Color3.fromHex("#201f3a")
local HAZE_DUST = Color3.fromHex("#d6b48c")
local FLASH_SKY = Color3.fromHex("#dfe6ff")
local DUST_SUN = Color3.fromHex("#ffb070")
local HEAT_SUN = Color3.fromHex("#fff1d0")
local BOLT = Color3.fromHex("#eef0ff")

-- Built-in particle pictures every Roblox client has: a star (squashed into a streak for rain),
-- a soft round glow (snowflakes) and a ring (splashes).
local TEX_RAIN = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SNOW = "rbxasset://textures/particles/forcefield_glow_main.dds"
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end
local function smooth(a: number, b: number, x: number): number
	local t = clamp01((x - a) / (b - a))
	return t * t * (3 - 2 * t)
end
local function grey(c: Color3, amount: number): Color3
	local l = c.R * 0.2126 + c.G * 0.7152 + c.B * 0.0722
	return c:Lerp(Color3.new(l, l, l), amount)
end
local function scale(c: Color3, k: number): Color3
	return Color3.new(math.clamp(c.R * k, 0, 1), math.clamp(c.G * k, 0, 1), math.clamp(c.B * k, 0, 1))
end

-- weatherLook.ts gloomOf: how much lamps and headlights come on in daytime gloom (0..1).
function TownWeather.gloomOf(w: any): number
	return math.min(1, math.max(0, (w.cloud - 0.45) / 0.45) + w.haze * 0.5)
end

-- weatherLook.ts hazeColor: pale grey by day, whiter in snow, deep blue at night.
function TownWeather.hazeColor(w: any, night: number): Color3
	return HAZE_DAY:Lerp(HAZE_SNOW, if w.snow > 0 then math.min(1, w.snow * 1.5) else 0):Lerp(HAZE_DUST, math.min(1, w.dust * 1.2)):Lerp(HAZE_NIGHT, night)
end

-- skyFx.ts: the finishing touches worked out from the weather and the time of day (the parts the
-- town draws here: fog banks, how low they lie, and the rainbow).
function TownWeather.skyFx(w: any, phase: number, seasonName: string?): { banks: number, low: number, rainbow: number }
	local s = seasonName or season.SEASON
	local night = clock.nightAmount(phase)
	local day = 1 - night
	local mix = w.mix
	local fog, mist, clearing, drizzle = mix.fog or 0, mix.mist or 0, mix.clearing or 0, mix.drizzle or 0
	local steam = if s == "winter" then 0 else clearing * smooth(0.1, 0.5, w.wet) * day
	local banks = math.max(fog, 0.75 * mist, 0.32 * drizzle, 0.3 * steam)
	local low = if banks > 0 then clamp01((0.75 * mist + 0.32 * drizzle + 0.3 * steam) / banks) else 1
	local rainbow = if s == "winter" then 0 else clearing * smooth(0.12, 0.4, w.wet) * smooth(0.5, 0.8, day)
	return { banks = banks, low = low, rainbow = rainbow }
end

-- ?weather=<kind> on the web: one kind at full strength, for testing (nil goes back to the schedule).
local pinned: any = nil
function TownWeather.pin(kind: string?)
	if not kind then
		pinned = nil
		return
	end
	local f = weather.FEEL[kind]
	assert(f, `no weather kind {kind}`)
	pinned = {
		kind = kind,
		strength = 1,
		mix = weather.mixOf(kind),
		rain = f.rain,
		snow = f.snow,
		cloud = f.cloud,
		haze = f.haze,
		wind = f.wind,
		dust = f.dust,
		wet = if f.rain > 0 then 1 elseif kind == "clearing" then 0.7 else 0,
		cover = if f.snow > 0 then 1 else 0,
		flash = 0,
	}
end

-- The weather right now: the shared schedule, or the pinned kind.
function TownWeather.now(now: number): any
	return pinned or weather.weatherNow(now)
end

-- Reduce flashing (web game/flashing.ts): softer lightning. Read from the player's CalmFlashing
-- attribute, which Rave Mode's heads-up (and, later, the menu) sets.
local function calm(): boolean
	local p = Players.LocalPlayer
	return p ~= nil and p:GetAttribute("CalmFlashing") == true
end

-- ---------- The light ----------
-- `written[inst][prop]` is what this module last wrote (read back, so rounding can't fool it);
-- anything else there is a fresh value from DayNight and becomes the new base.
local written: { [Instance]: { [string]: any } } = {}
local base: { [Instance]: { [string]: any } } = {}
local function nudge(inst: Instance?, prop: string, f: (any) -> any)
	if not inst then
		return
	end
	local i = inst :: any
	local w = written[inst]
	if not w then
		w = {}
		written[inst] = w
		base[inst] = {}
	end
	local cur = i[prop]
	if w[prop] == nil or cur ~= w[prop] then
		base[inst][prop] = cur
	end
	i[prop] = f(base[inst][prop])
	w[prop] = i[prop]
end
-- Puts back what DayNight set (a race starting, or the module stopping).
local function release()
	for inst, props in base do
		for prop, v in props do
			if inst.Parent ~= nil then
				(inst :: any)[prop] = v
			end
		end
	end
	written = {}
	base = {}
end

-- weatherLook.ts weatherLook plus Weather.tsx TownFog, on top of DayNight's light.
local function light(w: any, night: number, fx: { banks: number, low: number, rainbow: number })
	local c = w.cloud
	local heat = w.mix.heat or 0
	local flash = w.flash or 0
	nudge(Lighting, "Brightness", function(v)
		return v * (1 - 0.72 * c) * (1 + 0.08 * heat)
	end)
	nudge(Lighting, "ColorShift_Top", function(v)
		local sun = grey(v, 0.7 * c)
		if w.dust > 0 then
			sun = sun:Lerp(DUST_SUN, 0.5 * w.dust)
		end
		return sun:Lerp(HEAT_SUN, 0.35 * heat)
	end)
	nudge(Lighting, "OutdoorAmbient", function(v)
		-- The sky's fill greys under cloud and rises off lying snow; a flash lights the whole sky.
		local k = (1 - 0.1 * c) * (1 + 0.3 * w.snow)
		return scale(grey(v, 0.6 * c), k):Lerp(FLASH_SKY, math.min(1, flash * 0.8))
	end)
	nudge(Lighting, "Ambient", function(v)
		return scale(grey(v, 0.6 * c), 1 + 0.3 * w.snow):Lerp(FLASH_SKY, math.min(1, flash * 0.5))
	end)
	nudge(Lighting, "ExposureCompensation", function(v)
		local exposure = 2 ^ v
		local e = exposure * (1 - 0.22 * c) * (1 + 0.16 * w.snow) * (1 + 0.05 * heat) + 0.3 * flash
		return math.log(math.max(e, 0.05), 2)
	end)
	local grade = Lighting:FindFirstChild("Grade")
	nudge(grade, "Saturation", function(v)
		return v - 0.35 * c - 0.06 * heat
	end)
	nudge(grade, "Contrast", function(v)
		-- DayNight writes (contrast - 1) * 1.5.
		return v - (0.05 * c + 0.1 * w.haze) * 1.5
	end)
	nudge(grade, "TintColor", function(v)
		-- Cool highlights under cloud, warm ones on a scorcher or in blowing dust.
		local warm = 0.035 * heat + 0.04 * w.dust
		return Color3.new(math.clamp(v.R * (1 - 0.01 * c) * (1 + warm * 0.4), 0, 1), v.G, math.clamp(v.B * (1 + 0.012 * c) * (1 - warm), 0, 1))
	end)
	nudge(Lighting:FindFirstChild("Glow"), "Intensity", function(v)
		return v * (1 + 0.3 * c) -- lamps and headlights glow in the gloom
	end)
	-- The haze: far fog thins under ground banks, which carry most of a fog's look on the web
	-- (heightFog.ts). Roblox has one Atmosphere, so both thicken it, banks a little less when low.
	local air = Lighting:FindFirstChild("Air")
	local far = w.haze * (1 - fx.banks)
	local k = clamp01(math.max(far, fx.banks * (1 - 0.35 * fx.low)))
	if air then
		local haze = TownWeather.hazeColor(w, night)
		nudge(air, "Density", function(v)
			return v + (0.42 - v) * k
		end)
		nudge(air, "Haze", function(v)
			return v + (2.6 - v) * k
		end)
		nudge(air, "Color", function(v)
			return v:Lerp(haze, math.min(1, k * 1.5 + c * 0.3))
		end)
		nudge(air, "Decay", function(v)
			return v:Lerp(haze, math.min(1, k * 1.5 + c * 0.3))
		end)
		nudge(air, "Glare", function(v)
			return v * (1 - c)
		end)
	end
end

-- ---------- What falls ----------
type Kit = {
	folder: Folder,
	sky: Part,
	ground: Part,
	anchor: Part,
	rain: { ParticleEmitter },
	snow: ParticleEmitter,
	splash: ParticleEmitter,
	bolt: { Beam },
	boltAt: { Attachment },
	bow: { Beam },
	bowAt: { { Attachment } },
}
local kit: Kit? = nil

local function holder(name: string, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.Parent = parent
	return p
end

local function emitter(parent: Instance, texture: string, dir: Enum.NormalId): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = dir
	e.Rate = 0
	e.Enabled = false
	e.LightInfluence = 0
	e.LockedToPart = false
	e.Parent = parent
	return e
end

local function build(): Kit
	local folder = Instance.new("Folder")
	folder.Name = "TownWeather"
	local sky = holder("WeatherSky", folder)
	local ground = holder("WeatherGround", folder)
	-- Lightning and the rainbow hang off a part that never moves, so their places stay put.
	local anchor = holder("WeatherAnchor", folder)
	anchor.CFrame = CFrame.new()
	local rain = {}
	for i = 1, RAIN_EMITTERS do
		local e = emitter(sky, TEX_RAIN, Enum.NormalId.Bottom)
		e.Name = `Rain{i}`
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Squash = NumberSequence.new(3)
		table.insert(rain, e)
	end
	local snow = emitter(sky, TEX_SNOW, Enum.NormalId.Bottom)
	snow.Name = "Snow"
	snow.SpreadAngle = Vector2.new(6, 6)
	local splash = emitter(ground, TEX_RING, Enum.NormalId.Top)
	splash.Name = "Splash"
	splash.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	splash.Speed = NumberRange.new(0.01)
	-- Lightning: a main stroke of SEGS - 6 beams and one fork of 6.
	local bolt, boltAt = {}, {}
	for i = 1, 24 do
		local a = Instance.new("Attachment")
		a.Name = `Bolt{i}`
		a.Parent = anchor
		table.insert(boltAt, a)
	end
	for i = 1, 22 do
		local b = Instance.new("Beam")
		b.Name = `Bolt{i}`
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 1
		b.Color = ColorSequence.new(BOLT)
		b.Enabled = false
		b.Parent = anchor
		table.insert(bolt, b)
	end
	-- The rainbow: six bands of the main bow and six of the faint second bow outside it.
	local bow, bowAt = {}, {}
	for i = 1, 12 do
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Name, a1.Name = `Bow{i}a`, `Bow{i}b`
		a0.Parent, a1.Parent = anchor, anchor
		local b = Instance.new("Beam")
		b.Name = `Bow{i}`
		b.Attachment0, b.Attachment1 = a0, a1
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 24
		b.Enabled = false
		b.Parent = anchor
		table.insert(bow, b)
		table.insert(bowAt, { a0, a1 })
	end
	folder.Parent = workspace
	return { folder = folder, sky = sky, ground = ground, anchor = anchor, rain = rain, snow = snow, splash = splash, bolt = bolt, boltAt = boltAt, bow = bow, bowAt = bowAt }
end

-- Weather.tsx frameFor (bird's-eye): the ground point in the middle of the screen, how big a box
-- fills the view, and how many studs a pixel is there.
type Frame = { center: Vector3, span: number, top: number, px: number, dist: number }
function TownWeather.frame(cam: Camera): Frame
	local cf = cam.CFrame
	local fwd = cf.LookVector
	local t = if fwd.Y < -0.05 then -cf.Position.Y / fwd.Y else 1000
	local center = cf.Position + fwd * t
	center = Vector3.new(center.X, 0, center.Z)
	local dist = (cf.Position - center).Magnitude
	local view = cam.ViewportSize
	local vy = math.max(view.Y, 2)
	local tall = 2 * dist * math.tan(math.rad(cam.FieldOfView / 2))
	local wide = tall * math.max(view.X, 2) / vy
	local h = tall / math.max(0.3, -fwd.Y)
	-- Rounded up in steps so zooming doesn't reshuffle every drop.
	local span = math.min(2400, math.ceil((math.max(wide, h) * 1.15 + 14 * U) / (8 * U)) * 8 * U)
	return { center = center, span = span, top = math.max(22 * U, cf.Position.Y * 0.6), px = tall / vy, dist = dist }
end

local function small(cam: Camera): boolean
	local v = cam.ViewportSize
	return math.min(v.X, v.Y) < 700
end

local function seq(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], math.clamp(p[2], 0, 1)))
	end
	return NumberSequence.new(keys)
end

-- Weather.tsx Precip, in emitter terms: the same drops per area, speeds, colours and wind.
local function precip(k: Kit, w: any, night: number, fr: Frame, sizes: { rain: number, splash: number, snow: number })
	local gust = w.wind * 9 * U
	local rain = math.min(1, w.rain)
	local snowAmt = math.min(1, math.max(w.snow, w.dust))
	local rainV = Vector3.new(gust, -26 * U, gust * 0.35)
	local snowSpeed = 3.2 * U * (1 + w.wind * 0.6)
	local snowV = Vector3.new(gust * 1.4, -snowSpeed, gust * 0.5)
	-- The sky box tilts so its underside faces the way the drops fly.
	local v = if rain >= snowAmt then rainV else snowV
	local down = v.Unit
	local right = down:Cross(Vector3.new(0, 0, 1))
	if right.Magnitude < 1e-3 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	local back = right:Cross(-down).Unit
	local top = fr.center + Vector3.new(0, fr.top, 0)
	k.sky.CFrame = CFrame.fromMatrix(top - down * 0, right, -down, back)
	k.sky.Size = Vector3.new(fr.span, 1, fr.span)
	k.ground.CFrame = CFrame.new(fr.center + Vector3.new(0, 0.04 * U, 0))
	k.ground.Size = Vector3.new(fr.span * 0.8, 0.2, fr.span * 0.8)

	-- Rain: long thin streaks lined up with how they fall.
	local fall = fr.top / rainV.Magnitude
	local alive = sizes.rain * rain
	local len = 1.3 * U * (0.6 + 0.4 * w.rain)
	local opacity = math.min(1, 0.32 + 0.25 * w.rain + (w.flash or 0) * 0.3)
	local rainColor = RAIN_DAY:Lerp(RAIN_NIGHT, night)
	for _, e in k.rain do
		e.Enabled = alive > 1
		e.Rate = alive / fall / #k.rain
		e.Lifetime = NumberRange.new(fall * 0.95, fall * 1.05)
		e.Speed = NumberRange.new(rainV.Magnitude)
		-- Squash 3 makes a particle about four times taller and a quarter as wide.
		e.Size = NumberSequence.new(math.max(len / 4, fr.px * 1.5))
		e.Color = ColorSequence.new(rainColor)
		e.Transparency = seq({ { 0, 1 }, { 0.06, 1 - opacity }, { 1, 1 - opacity } })
	end

	-- Snow (or blowing sand): soft flakes drifting down with the wind.
	local sand = w.dust > w.snow
	local sv = if sand then Vector3.new(gust * 2.4, -1.5 * U, gust * 0.8) else snowV
	local slife = fr.top / sv.Magnitude
	local flakes = sizes.snow * snowAmt
	local s = k.snow
	s.Enabled = flakes > 1
	s.Rate = flakes / slife
	s.Lifetime = NumberRange.new(slife * 0.95, slife * 1.05)
	s.Speed = NumberRange.new(sv.Magnitude * 0.75, sv.Magnitude * 1.25)
	s.Size = NumberSequence.new(math.max(0.1 * U, (if sand then 3.4 else 4.2) * fr.px) * 0.8)
	local flake = if sand then Color3.fromHex("#b48650") else Color3.new(1, 1, 1):Lerp(SNOW_NIGHT, night * 0.6)
	s.Color = ColorSequence.new(flake)
	local so = if sand then 0.7 else 0.95
	s.Transparency = seq({ { 0, 1 }, { 0.06, 1 - so }, { 1, 1 - so } })

	-- Splashes: rings spreading where the drops land.
	local p = k.splash
	local cycle = 1 / 1.9
	local rings = sizes.splash * math.min(1, w.rain * 1.3)
	p.Enabled = rings > 1
	p.Rate = rings / cycle
	p.Lifetime = NumberRange.new(cycle * 0.8, cycle * 1.3)
	p.Size = seq({ { 0, 0.1 * U }, { 1, 0.32 * U } })
	p.Color = ColorSequence.new(SPLASH)
	local po = 0.55 * (1 - night * 0.5)
	p.Transparency = seq({ { 0, 1 - po }, { 1, 1 } })
end

-- ---------- Lightning ----------
-- Weather.tsx flashCurve: the flash's brightness t seconds after a strike, and Reduce flashing's
-- single soft glow.
local function flashCurve(t: number): number
	if t < 0 then
		return 0
	elseif t < 0.07 then
		return 1
	elseif t < 0.13 then
		return 0.25
	elseif t < 0.2 then
		return 0.85
	end
	return math.max(0, 0.85 * (1 - (t - 0.2) / 0.45))
end
local function softFlash(t: number): number
	return if t < 0 then 0 else 0.3 * math.max(0, 1 - math.abs(t - 0.25) / 0.25)
end

-- Puts an attachment at a place in the world (its part stands at the origin).
local function place(_k: Kit, a: Attachment, world: CFrame)
	a.CFrame = world
end

local storm = { next = 3 + math.random() * 5, at = -10 }
local function placeBolt(k: Kit, fr: Frame)
	local g = fr.center + Vector3.new((math.random() - 0.5) * fr.span * 0.5, 0, (math.random() - 0.5) * fr.span * 0.5)
	local height = 45 * U
	local width = 0.12 * U + fr.px * 2.5
	local main = 16
	local pts = {}
	for i = 0, main do
		local j = if i == 0 or i == main then 0 else 1
		table.insert(pts, Vector3.new(g.X + j * (math.random() - 0.5) * 3.2 * U, height * (1 - i / main), g.Z + j * (math.random() - 0.5) * 3.2 * U))
	end
	for i = 1, main + 1 do
		place(k, k.boltAt[i], CFrame.new(pts[i]))
	end
	for i = 1, main do
		local b = k.bolt[i]
		b.Attachment0, b.Attachment1 = k.boltAt[i], k.boltAt[i + 1]
		b.Width0, b.Width1 = width, width
	end
	-- One fork off the upper half.
	local at = pts[3 + math.random(0, 3)]
	local dir = Vector3.new((math.random() - 0.5) * 2, -2.2, (math.random() - 0.5) * 2).Unit
	place(k, k.boltAt[main + 2], CFrame.new(at))
	for i = 1, 6 do
		local nxt = at + dir * 2.6 * U + Vector3.new((math.random() - 0.5) * 1.4 * U, 0, (math.random() - 0.5) * 1.4 * U)
		local a1 = if main + 2 + i <= #k.boltAt then k.boltAt[main + 2 + i] else nil
		if not a1 then
			break
		end
		place(k, a1, CFrame.new(nxt))
		local b = k.bolt[main + i]
		b.Attachment0, b.Attachment1 = k.boltAt[main + 1 + i], a1
		b.Width0, b.Width1 = width * 0.6, width * 0.6
		at = nxt
	end
end

local function lightning(k: Kit, w: any, t: number, fr: Frame)
	local stormy = w.kind == "storm" and w.rain > 0.5
	if stormy and t > storm.next then
		storm.at = t
		storm.next = t + 4 + math.random() * 9
		placeBolt(k, fr)
		-- Sound travels slower than light: a far strike rumbles in later and softer.
		local far = math.random()
		weather.strike(400 + far * 2200, 1 - far * 0.6)
	elseif not stormy and storm.next < t + 2 then
		storm.next = t + 2 + math.random() * 4
	end
	local f = (if calm() then softFlash else flashCurve)(t - storm.at)
	w.flash = f
	local tr = 1 - math.min(1, f * 1.4)
	for _, b in k.bolt do
		b.Enabled = f > 0.01 and b.Attachment0 ~= nil
		b.Transparency = NumberSequence.new(tr)
	end
end

-- ---------- Rainbow ----------
-- Atmosphere.tsx: seen from above, a fixed bow over the middle of town (BOW_RADIUS 18), red outside
-- to violet inside, a faint second bow outside it the other way round, fading towards the ground.
local BOW_RADIUS = 18 * U
local function hue(h: number): Color3
	local function ch(o: number): number
		return math.clamp(math.abs(((h * 6 + o) % 6) - 3) - 1, 0, 1)
	end
	return Color3.new(ch(0), ch(4), ch(2))
end
local function rainbow(k: Kit, o: number, cam: Camera, origin: Vector3)
	local on = o > 0.01
	for _, b in k.bow do
		b.Enabled = on
	end
	if not on then
		return
	end
	local cf = cam.CFrame
	local up, right, fwd = cf.UpVector, cf.RightVector, cf.LookVector
	-- Pulled towards the camera so it hangs over the roofs, and shrunk to look the same size.
	local d = (origin - cf.Position):Dot(fwd)
	local pull = math.min(d * 0.4, 200)
	local s = (d - pull) / math.max(d, 1)
	local feet = origin - up * BOW_RADIUS * 0.25 * s - fwd * pull
	for i = 1, 12 do
		local second = i > 6
		local j = if second then i - 6 else i
		local b = (j - 0.5) / 6
		local r = (if second then 1.1 + b * 0.09 else 0.96 - b * 0.1) * BOW_RADIUS * s
		local a = (if second then 0.35 else 1) * math.sin(b * math.pi) * o * 0.55
		local beam = k.bow[i]
		local a0, a1 = k.bowAt[i][1], k.bowAt[i][2]
		-- Each band is a half circle: a cubic curve from one foot to the other, its handles
		-- straight up 4/3 of the radius (the attachments' X axis points up the screen).
		place(k, a0, CFrame.fromMatrix(feet - right * r, up, right))
		place(k, a1, CFrame.fromMatrix(feet + right * r, up, right))
		beam.CurveSize0 = r * 4 / 3
		beam.CurveSize1 = -r * 4 / 3
		local w = (if second then 0.09 else 0.1) * BOW_RADIUS * s / 6 * 1.15
		beam.Width0, beam.Width1 = w, w
		beam.Color = ColorSequence.new(hue(b * 0.78))
		local tr = 1 - a
		beam.Transparency = seq({ { 0, 1 }, { 0.08, 1 - a * 0.3 }, { 0.18, tr }, { 0.82, tr }, { 0.92, 1 - a * 0.3 }, { 1, 1 } })
	end
end

-- ---------- Each frame ----------
local started = false
local active = false
local function townOrigin(): Vector3
	local towns = workspace:FindFirstChild("Towns")
	local me = Players.LocalPlayer
	if towns and me then
		for _, f in towns:GetChildren() do
			if f:GetAttribute("Owner") == me.UserId then
				local o = f:GetAttribute("Origin")
				if typeof(o) == "Vector3" then
					return o
				end
			end
		end
	end
	return Vector3.zero
end

-- ---------- The ground (weatherLook.ts wetRoad and weatherBaked) ----------
-- Rain darkens what faces up (roads by a third, lawns and lots a little); snow lies white on the
-- lawns and lots and in grey slush on the roads. No new parts: the town's own ground pieces
-- (TownView's Turf, Lot and Asphalt) are recoloured, each keeping what it was in attributes so
-- it always goes back to its own colour. The meadows round the town stay as they are, as on the web.
local SNOW_COAT = Color3.new(0.93, 0.95, 0.98)
local SLUSH = Color3.new(0.78, 0.82, 0.86)
local groundParts: { BasePart } = {}
local groundScan = -math.huge
local groundWas = { wet = 0, cover = 0 }

local function groundLook(p: BasePart, wet: number, cover: number)
	local base = p:GetAttribute("WeatherColor")
	if typeof(base) ~= "Color3" then
		base = p.Color
		p:SetAttribute("WeatherColor", base)
	end
	local tex = p:FindFirstChild("Ground")
	if tex and tex:IsA("Texture") and tex:GetAttribute("WeatherT") == nil then
		tex:SetAttribute("WeatherT", tex.Transparency)
	end
	if p.Name == "Asphalt" then
		-- Dark and wet, then grey slush in patches (about half the road on average).
		local c = scale(base :: Color3, 1 - 0.32 * wet)
		p.Color = c:Lerp(SLUSH, cover * 0.6 * 0.85)
	else
		-- Facing up: a glossy film in the rain, a white coat in the snow.
		local snowy = math.min(1, cover * 1.1)
		p.Color = scale(base :: Color3, 1 - 0.12 * wet):Lerp(SNOW_COAT, snowy)
		if tex and tex:IsA("Texture") then
			local t0 = tex:GetAttribute("WeatherT") :: number
			tex.Transparency = t0 + (1 - t0) * snowy * 0.9
			tex.Color3 = scale(Color3.new(1, 1, 1), 1 - 0.12 * wet)
		end
	end
end

local function groundRestore()
	for _, p in groundParts do
		local base = p:GetAttribute("WeatherColor")
		if typeof(base) == "Color3" then
			p.Color = base
		end
		p:SetAttribute("WeatherColor", nil)
		local tex = p:FindFirstChild("Ground")
		if tex and tex:IsA("Texture") then
			local t0 = tex:GetAttribute("WeatherT")
			if type(t0) == "number" then
				tex.Transparency = t0
			end
			tex.Color3 = Color3.new(1, 1, 1)
			tex:SetAttribute("WeatherT", nil)
		end
	end
	groundParts = {}
	groundScan = -math.huge
end

local GROUND_NAMES = { Turf = true, Lot = true, Asphalt = true }
local function ground(w: any, t: number)
	local wet = math.clamp(w.wet or 0, 0, 1)
	local cover = math.clamp(w.cover or 0, 0, 1)
	if wet < 0.005 and cover < 0.005 then
		if #groundParts > 0 then
			groundRestore()
		end
		groundWas.wet, groundWas.cover = 0, 0
		return
	end
	-- New plots and roads turn up now and then: look again every few seconds.
	local fresh = false
	if t - groundScan > 4 then
		groundScan = t
		local towns = workspace:FindFirstChild("Towns")
		local seen = {}
		for _, p in groundParts do
			seen[p] = true
		end
		if towns then
			for _, d in towns:GetDescendants() do
				if GROUND_NAMES[d.Name] and d:IsA("BasePart") and not seen[d] then
					table.insert(groundParts, d)
					fresh = true
				end
			end
		end
	end
	-- Only when the weather has moved on enough to see (it changes over minutes).
	if not fresh and math.abs(wet - groundWas.wet) < 0.01 and math.abs(cover - groundWas.cover) < 0.01 then
		return
	end
	groundWas.wet, groundWas.cover = wet, cover
	local keep = {}
	for _, p in groundParts do
		if p.Parent then
			groundLook(p, wet, cover)
			table.insert(keep, p)
		end
	end
	groundParts = keep
end

-- What the last step drew, for the emulator's pictures and tests.
TownWeather.last = nil :: any

-- One frame of town weather at `now` (ms), `t` seconds into the session.
function TownWeather.step(now: number, t: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if DayNight.raceFog ~= nil then
		-- A race brings its own sky: put the town's light back and stop drawing.
		if active then
			active = false
			release()
			groundRestore()
			groundWas.wet, groundWas.cover = 0, 0
			if kit then
				kit.folder.Parent = nil
			end
		end
		return
	end
	local k = kit or build()
	kit = k
	if not active then
		active = true
		k.folder.Parent = workspace
	end
	local w = TownWeather.now(now)
	local phase = clock.dayPhase(now)
	local night = clock.nightAmount(phase)
	local fx = TownWeather.skyFx(w, phase)
	local fr = TownWeather.frame(cam)
	lightning(k, w, t, fr)
	light(w, night, fx)
	precip(k, w, night, fr, if small(cam) then SIZES.small else SIZES.big)
	rainbow(k, fx.rainbow, cam, townOrigin())
	ground(w, t)
	TownWeather.last = { weather = w, night = night, fx = fx, frame = fr }
end

-- The parts this draws with, for the emulator's pictures.
function TownWeather.kit(): any
	return kit
end

function TownWeather.start()
	if started then
		return
	end
	started = true
	-- A brand new player's first minutes are always sunny (App.tsx: setCalmSky through the tutorial).
	local store = require(Game:WaitForChild("store")) :: any
	local Remote = require(script.Parent.Remote) :: any
	local function calmSky()
		local s = store.useGame.getState()
		weather.setCalmSky((s.tutorial or 0) < 99)
	end
	calmSky()
	Remote.changed:Connect(calmSky)
	local t0 = os.clock()
	-- After DayNight's own step, so the nudges land on this frame's light.
	RunService:BindToRenderStep("TownWeather", Enum.RenderPriority.Camera.Value + 2, function()
		TownWeather.step(DateTime.now().UnixTimestampMillis, os.clock() - t0)
	end)
end

return TownWeather
