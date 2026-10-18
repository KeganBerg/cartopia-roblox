--!strict
-- The town's sounds under the music: a bed for the season and the time of day (Kegan's recordings
-- of the web game's lib/ambience.ts soundscape: birds and traffic by day, crickets and owls at
-- night), which turns to rain, a storm, wind or snow with the weather, and thunder on a strike.
--
-- Each season's beds are one uploaded sprite (tools/audio/build.mjs): "day-calm", "night-rain",
-- "day-storm" (summer), "day-wind" (fall), "night-snow" (winter)... They all loop at once and
-- cross-fade: day into night with the clock (clock.nightAmount), calm into the weather's beds as
-- the weather comes in. A season with no bed for a kind of weather (no wind in spring) keeps the
-- nearest it has.
--
-- The weather is the web's own (Shared.Game.weather, weatherNow), unless something drives it:
--   Ambience.setWeather("storm", 0.8)   a kind from weather.WEATHER_KINDS and how strong (0..1)
--   Ambience.setWeather(nil)            back to the town's own weather
--   Ambience.thunder(loud, delayMs)     a thunderclap (weather.strike() calls this too)
-- It follows the Menu's Town sounds switch and slider (the Town group), is quiet during races and
-- arcade games (Mixer.hold), and turns down by half under Rave Mode, as on the web.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("AudioAssets")) :: any
local Game = Shared:WaitForChild("Game")
local clock = require(Game:WaitForChild("clock")) :: any
local weather = require(Game:WaitForChild("weather")) :: any
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local Mixer = require(script.Parent.Mixer)
local Sfx = require(script.Parent.Sfx)

local Ambience = {}

local KINDS = { "calm", "rain", "storm", "wind", "snow" }

type Bed = { sound: Sound, time: string, kind: string }
local beds: { Bed } = {}
local have: { [string]: boolean } = {}

local override: { kind: string, strength: number }? = nil
function Ambience.setWeather(kind: string?, strength: number?)
	override = if kind then { kind = kind, strength = math.clamp(strength or 1, 0, 1) } else nil
end

local rave = false
function Ambience.rave(on: boolean)
	rave = on
end

function Ambience.thunder(loud: number?, delayMs: number?)
	if Mixer.held() or not Mixer.settings().town.on then
		return
	end
	task.delay((delayMs or 0) / 1000, Sfx.thunder, loud)
end

-- How much of each bed the weather calls for: rain, storm, wind and snow, 0..1 each.
local function want(): { [string]: number }
	local rain, snow, wind, storm
	if override then
		local feel = weather.FEEL[override.kind] or weather.FEEL.clear
		local k = override.strength
		rain, snow, wind = feel.rain * k, feel.snow * k, feel.wind * k
		storm = if override.kind == "storm" or override.kind == "blizzard" then k else 0
	else
		local w = weather.weatherNow()
		rain, snow, wind = w.rain or 0, w.snow or 0, w.wind or 0
		storm = math.max(w.mix and w.mix.storm or 0, w.mix and w.mix.blizzard or 0)
	end
	local out = { rain = 0, storm = 0, wind = 0, snow = 0 }
	-- A storm is its own bed where the season has one, else heavy rain.
	if have.storm then
		out.storm = rain * math.min(1, storm)
		out.rain = rain - out.storm
	else
		out.rain = rain
	end
	-- Snow without a snow bed sounds like quiet rain; rain without a rain bed, like snow.
	if have.snow then
		out.snow = snow
	elseif have.rain then
		out.rain = math.max(out.rain, snow * 0.6)
	end
	if not have.rain and have.snow then
		out.snow = math.max(out.snow, rain)
	end
	if have.wind then
		out.wind = wind
	end
	return out
end

local level = 0
function Ambience.start()
	local sprite = Assets.sprites[`weather-{Catalog.SEASON}`]
	if not sprite or sprite.id == 0 then
		return
	end
	for name, part in sprite.regions do
		local time, kind = string.match(name, "^(%a+)%-(%a+)$")
		if time and kind and table.find(KINDS, kind) then
			local s = Mixer.sound(sprite.id, Mixer.town, `Weather {name}`)
			if s then
				Mixer.region(s, part.start, part.length, true)
				table.insert(beds, { sound = s, time = time, kind = kind })
				have[kind] = true
			end
		end
	end
	weather.onThunder(function(delay: number, loud: number)
		Ambience.thunder(loud, delay)
	end)
	local started = false
	RunService.Heartbeat:Connect(function(dt)
		local on = Mixer.settings().town.on and not Mixer.muted() and not Mixer.held()
		-- Quiet while held, and half under Rave Mode; fades in and out over about a second.
		level += ((if on then (if rave then 0.5 else 1) else 0) - level) * (1 - math.exp(-dt / 0.8))
		if level < 0.001 then
			if started then
				for _, b in beds do
					b.sound.Volume = 0
					b.sound:Pause()
				end
				started = false
			end
			return
		end
		if not started then
			started = true
			for _, b in beds do
				if b.sound.IsPaused then
					b.sound:Resume()
				else
					b.sound:Play()
				end
			end
		end
		local night = clock.nightAmount(clock.dayPhase())
		local w = want()
		-- The weather's beds take over from the calm one; their shares never add up past all of it.
		local total = w.rain + w.storm + w.wind + w.snow
		local scale = if total > 1 then 1 / total else 1
		local mix = { calm = math.max(0, 1 - total * scale), rain = w.rain * scale, storm = w.storm * scale, wind = w.wind * scale, snow = w.snow * scale }
		for _, b in beds do
			local share = (if b.time == "night" then night else 1 - night) * (mix[b.kind] or 0)
			-- Equal-power cross-fades, so the town doesn't dip halfway through one.
			b.sound.Volume = level * math.sqrt(share)
		end
	end)
end

return Ambience
