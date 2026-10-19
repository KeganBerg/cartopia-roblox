--!strict
-- The town's light through the day, as the web game's DayNight and look.ts: the shared 20-minute
-- town clock (game/clock.ts, the same for every player) turns the sun, and the light colours and
-- colour grade blend between the day, golden-hour and night keys, nudged for the season. Roblox
-- stands in for the web's post-processing with ColorCorrection, Bloom and Atmosphere.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local clock = require(Shared:WaitForChild("Game"):WaitForChild("clock")) :: any
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local Horizon = require(script.Parent.Horizon)
local ClockShift = require(script.Parent.ClockShift)

local DayNight = {}

-- Set by the race screen while a race runs: its venue's fog colour and distances (studs). A room
-- (the Daily Spin's tyre shop) also shuts out the sun: only its own lamps and `ambient` light it.
export type Fog = { color: Color3, near: number, far: number, room: { ambient: Color3 }? }
DayNight.raceFog = nil :: Fog?
DayNight.indoor = nil :: any
local airKept: Atmosphere? = nil

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
	-- At latitude 0 Roblox's sun can only stand on the east-west arc through the top of the sky, so
	-- it stands at the point of that arc nearest the web's light: its angle from straight up
	-- towards +X (east, the morning side), one hour per 15 degrees. That moves smoothly whichever
	-- way the web's light swings (picking a side by the light's own east-west sign jumped the sun
	-- from one horizon to the other at dusk).
	local dir = lightDir(phase, night)
	Lighting.GeographicLatitude = 0
	Lighting.ClockTime = 12 - math.deg(math.atan2(dir.X, math.max(dir.Y, 0.05))) / 15
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

	-- Indoors (the Crate Depot, closed in high over the town): its own dim light and dark haze, the
	-- town's air stepping out as for a race.
	local inside = DayNight.indoor
	if inside then
		if airKept == nil then
			airKept = Lighting:FindFirstChild("Air") :: Atmosphere?
			if airKept then
				airKept.Parent = nil
			end
		end
		Lighting.Ambient = inside.ambient
		Lighting.OutdoorAmbient = inside.ambient
		Lighting.Brightness = inside.brightness
		Lighting.ExposureCompensation = inside.exposure
		Lighting.EnvironmentDiffuseScale = 0.3
		Lighting.EnvironmentSpecularScale = 0.6
		bloom.Intensity = inside.bloom
		bloom.Threshold = inside.threshold
		grade.Saturation = inside.saturation
		grade.Contrast = inside.contrast
		grade.TintColor = Color3.new(1, 1, 1)
		Lighting.FogColor = inside.fog
		Lighting.FogStart = inside.fogStart
		Lighting.FogEnd = inside.fogEnd
		return
	end

	-- The web game's sky for this time of day, and the colour the far land fades into.
	local haze = Horizon.sky(phase)

	-- A race brings its venue's haze (RaceScene's linear fog). Roblox ignores Lighting's fog while an
	-- Atmosphere is in Lighting, so the town's air steps out for the race.
	local race = DayNight.raceFog
	if race then
		if airKept == nil then
			airKept = Lighting:FindFirstChild("Air") :: Atmosphere?
			if airKept then
				airKept.Parent = nil
			end
		end
		Lighting.FogColor = if race.room then race.color else race.color:Lerp(Color3.fromHex("#1d2740"), night)
		Lighting.FogStart = race.near
		Lighting.FogEnd = race.far
		local room = race.room
		if room then
			Lighting.Brightness = 0
			Lighting.Ambient = room.ambient
			Lighting.OutdoorAmbient = room.ambient
			Lighting.EnvironmentDiffuseScale = 0
			Lighting.EnvironmentSpecularScale = 0.3
			Lighting.ExposureCompensation = math.log(1.15, 2)
			-- WheelScene's grade: brighter neon glow, a little more colour.
			bloom.Intensity = 0.9
			bloom.Threshold = 0.85
			grade.Saturation = 0.15
			grade.Contrast = 0.1
		end
		return
	elseif airKept then
		airKept.Parent = Lighting
		airKept = nil
	end
	Lighting.FogEnd = 100000
	local air = effect("Atmosphere", "Air") :: Atmosphere
	-- Light: the town camera stands several hundred studs back (TownCamera), and thick air would
	-- wash the whole town out.
	-- Thinner the further back the camera stands: the air's haze builds with distance, and from the
	-- shared world's zoomed-out views (Popups/Claim stands back several thousand studs) the whole
	-- map drowned in it. Scaling by the camera's height keeps the haze over any view about the
	-- same as over a town.
	local cam = workspace.CurrentCamera
	local height = if cam then cam.CFrame.Position.Y else 0
	air.Density = 0.08 * math.clamp(450 / math.max(height, 1), 0.08, 1)
	air.Offset = 0
	air.Color = haze or look.sky
	air.Decay = haze or look.ground
	air.Glare = dusk * 0.6
	air.Haze = 0.5 + dusk
end

function DayNight.start()
	-- Every frame, just after the camera moves (and before TownWeather nudges what it sets), so the
	-- light glides rather than stepping.
	RunService:BindToRenderStep("DayNight", Enum.RenderPriority.Camera.Value + 1, function()
		apply(ClockShift.now())
	end)
end

DayNight.apply = apply

-- Starts or ends a race's fog, at once rather than at the next tick.
function DayNight.setRaceFog(fog: Fog?)
	DayNight.raceFog = fog
	apply(ClockShift.now())
end

export type Indoor = { ambient: Color3, brightness: number, exposure: number, bloom: number, threshold: number, saturation: number, contrast: number, fog: Color3, fogStart: number, fogEnd: number }

-- Starts or ends an indoor scene's light (CrateScene), at once.
function DayNight.setIndoor(look: Indoor?)
	DayNight.indoor = look
	apply(ClockShift.now())
end

return DayNight
