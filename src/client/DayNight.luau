--!strict
-- The town's light through the day, as the web game's DayNight and look.ts: the shared 20-minute
-- town clock (game/clock.ts, the same for every player) turns the sun, and the light colours and
-- colour grade blend between the day, golden-hour and night keys, nudged for the season. Roblox
-- stands in for the web's post-processing with ColorCorrection, Bloom and Atmosphere.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local clock = require(Shared:WaitForChild("Game"):WaitForChild("clock")) :: any
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any

local DayNight = {}

type Key = {
	sun: Color3,
	sunIntensity: number,
	sky: Color3,
	ground: Color3,
	hemi: number,
	env: number,
	exposure: number,
	contrast: number,
	saturation: number,
	vibrance: number,
	highlights: Vector3,
	bloom: number,
	threshold: number,
}

local function key(k: { [string]: any }): Key
	return {
		sun = Color3.fromHex(k.sun),
		sunIntensity = k.sunIntensity,
		sky = Color3.fromHex(k.sky),
		ground = Color3.fromHex(k.ground),
		hemi = k.hemi,
		env = k.env,
		exposure = k.exposure,
		contrast = k.contrast,
		saturation = k.saturation,
		vibrance = k.vibrance,
		highlights = Vector3.new(k.highlights[1], k.highlights[2], k.highlights[3]),
		bloom = k.bloom,
		threshold = k.threshold,
	}
end

-- look.ts DAY, DUSK and NIGHT (the town's keys).
local DAY = key({ sun = "#ffd9a2", sunIntensity = 1.8, sky = "#cfd2ea", ground = "#b09868", hemi = 0.74, env = 0.4, exposure = 0.94, contrast = 1.01, saturation = 0.96, vibrance = 0.12, highlights = { 0.05, 0.022, -0.02 }, bloom = 0.32, threshold = 0.95 })
local DUSK = key({ sun = "#ff9a50", sunIntensity = 1.85, sky = "#b890c8", ground = "#74563e", hemi = 0.52, env = 0.3, exposure = 0.97, contrast = 1.07, saturation = 1.08, vibrance = 0.18, highlights = { 0.1, 0.04, -0.045 }, bloom = 0.85, threshold = 0.72 })
local NIGHT = key({ sun = "#a4a8f0", sunIntensity = 0.38, sky = "#5858b0", ground = "#221c2e", hemi = 0.5, env = 0.1, exposure = 1.06, contrast = 1.08, saturation = 0.6, vibrance = 0.05, highlights = { 0.09, 0.04, -0.03 }, bloom = 1.9, threshold = 0.4 })

-- look.ts SEASON_NUDGE: the season's sun colour and how strongly it shows by day.
local NUDGE = {
	spring = { sun = Color3.fromHex("#fff0e4"), amount = 0.25, saturation = 0.02 },
	summer = { sun = Color3.fromHex("#ffeccc"), amount = 0.2, saturation = 0.04 },
	fall = { sun = Color3.fromHex("#ffcf90"), amount = 0.4, saturation = 0.05 },
	winter = { sun = Color3.fromHex("#f2eeff"), amount = 0.35, saturation = -0.06 },
}

local function lerp(a: Key, b: Key, t: number): Key
	local function n(x: number, y: number): number
		return x + (y - x) * t
	end
	return {
		sun = a.sun:Lerp(b.sun, t),
		sunIntensity = n(a.sunIntensity, b.sunIntensity),
		sky = a.sky:Lerp(b.sky, t),
		ground = a.ground:Lerp(b.ground, t),
		hemi = n(a.hemi, b.hemi),
		env = n(a.env, b.env),
		exposure = n(a.exposure, b.exposure),
		contrast = n(a.contrast, b.contrast),
		saturation = n(a.saturation, b.saturation),
		vibrance = n(a.vibrance, b.vibrance),
		highlights = a.highlights:Lerp(b.highlights, t),
		bloom = n(a.bloom, b.bloom),
		threshold = n(a.threshold, b.threshold),
	}
end

-- look.ts lightDir: where the town's light comes from (the sun by day, easing off the horizon in
-- the morning and evening; the moon's spot by night). Phase 0 is noon and 0.5 midnight.
local NOON = Vector3.new(25, 40, 15).Unit
local MOON_DIR = Vector3.new(-10, 40, 25).Unit
local function lightDir(phase: number, night: number): Vector3
	local d = math.abs(phase - 0.5)
	local x = math.clamp((d - 0.2) / 0.3, 0, 1)
	local high = x * x * (3 - 2 * x)
	local el = math.rad(22 + 43 * high)
	local swing = (1 - high) * 1.1 * (if phase < 0.5 then -1 else 1)
	local az = math.atan2(NOON.X, NOON.Z) + swing
	local sun = Vector3.new(math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el))
	return sun:Lerp(MOON_DIR, night).Unit
end

local function effect<T>(class: string, name: string): T
	local e = Lighting:FindFirstChild(name)
	if not e then
		e = Instance.new(class)
		e.Name = name;
		(e :: Instance).Parent = Lighting
	end
	return e :: any
end

local function apply(now: number)
	local phase = clock.dayPhase(now)
	local night, dusk = clock.nightAmount(phase), clock.duskAmount(phase)
	local look = lerp(lerp(DAY, NIGHT, night), DUSK, dusk)
	local nudge = NUDGE[Catalog.SEASON] or NUDGE.summer
	local sun = look.sun:Lerp(nudge.sun, nudge.amount * (1 - night) * (1 - dusk))

	-- The light never sets: the web game lights the town from 22 to 65 degrees up by day and from
	-- the moon's fixed spot by night (look.ts lightDir), and Roblox's own night would leave the town
	-- black. So the Roblox sun stands where the web's light is, and the keys above give it the
	-- moon's colour and strength at night. At latitude 0 the sun's height is 90 - 15 degrees an hour
	-- from noon.
	local dir = lightDir(phase, night)
	local el = math.deg(math.asin(math.clamp(dir.Y, -1, 1)))
	Lighting.GeographicLatitude = 0
	Lighting.ClockTime = 12 + (if dir.X < 0 then 1 else -1) * (90 - el) / 15
	Lighting.Brightness = look.sunIntensity * 1.4
	Lighting.ColorShift_Top = sun
	Lighting.OutdoorAmbient = look.sky:Lerp(look.ground, 0.35):Lerp(Color3.new(0, 0, 0), 1 - math.clamp(look.hemi + 0.35, 0, 1))
	Lighting.Ambient = Lighting.OutdoorAmbient:Lerp(Color3.new(0, 0, 0), 0.5)
	Lighting.EnvironmentDiffuseScale = look.env
	Lighting.EnvironmentSpecularScale = look.env
	Lighting.ExposureCompensation = math.log(look.exposure, 2)

	local grade = effect("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	grade.Contrast = (look.contrast - 1) * 1.5
	grade.Saturation = look.saturation - 1 + look.vibrance * 0.5 + nudge.saturation
	-- Warm highlights: the web adds a signed tint to bright tones; a gentle multiply comes closest.
	local h = look.highlights
	grade.TintColor = Color3.new(1, math.clamp(1 - (h.X - h.Y) * 1.2, 0.85, 1), math.clamp(1 - (h.X - h.Z) * 1.2, 0.8, 1))

	local bloom = effect("BloomEffect", "Glow") :: BloomEffect
	bloom.Intensity = look.bloom * 0.6
	bloom.Threshold = look.threshold + 0.25
	bloom.Size = 24

	local air = effect("Atmosphere", "Air") :: Atmosphere
	-- Light: the town camera stands several hundred studs back (TownCamera), and thick air would
	-- wash the whole town out.
	air.Density = 0.08
	air.Offset = 0
	air.Color = look.sky
	air.Decay = look.ground
	air.Glare = dusk * 0.6
	air.Haze = 0.5 + dusk
end

function DayNight.start()
	task.spawn(function()
		while true do
			apply(DateTime.now().UnixTimestampMillis)
			-- A town day lasts 20 minutes, so a quarter-second step is smooth enough and costs nothing.
			task.wait(0.25)
		end
	end)
end

DayNight.apply = apply

return DayNight
