--!strict
-- Where the game's sound goes, and the player's sound settings (the web's Menu > Settings: Music
-- and Town sounds each on/off with a volume, and an Effects volume), kept with their account.
--
-- Everything plays through SoundService.Cartopia, the group the Sound switch mutes, split into
-- Music, Town (weather and the club), Effects and Voice. The players (Music, Ambience, Club, Rave)
-- each fade their own sounds; the groups carry the player's sliders.
--
-- Mixer.hold(key, true) quiets the town's music and sounds, as the web does during races and
-- arcade games (its renderGate): TownCamera's setPaused holds it while another screen has the camera.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Mixer = {}

local function group(name: string, parent: Instance): SoundGroup
	local g = parent:FindFirstChild(name)
	if g and g:IsA("SoundGroup") then
		return g
	end
	local made = Instance.new("SoundGroup")
	made.Name = name
	made.Volume = 1
	made.Parent = parent
	return made
end

local master = group("Cartopia", SoundService)
Mixer.master = master
Mixer.music = group("Music", master)
Mixer.town = group("Town", master)
Mixer.effects = group("Effects", master)
Mixer.voice = group("Voice", master)

-- The sounds themselves live here (a Sound plays everywhere when it isn't in a part).
local holder = SoundService:FindFirstChild("CartopiaSounds") or Instance.new("Folder")
holder.Name = "CartopiaSounds"
holder.Parent = SoundService
Mixer.holder = holder

export type Settings = { music: { on: boolean, volume: number }, town: { on: boolean, volume: number }, effects: number }
-- The web's defaults: music on at half, town sounds on and fairly quiet, effects full.
local settings: Settings = { music = { on = true, volume = 0.5 }, town = { on = true, volume = 0.7 }, effects = 1 }

local changed = Instance.new("BindableEvent")
Mixer.changed = changed.Event

local function apply()
	Mixer.music.Volume = if settings.music.on then settings.music.volume else 0
	Mixer.town.Volume = if settings.town.on then settings.town.volume else 0
	Mixer.effects.Volume = settings.effects
end

function Mixer.settings(): Settings
	return settings
end

local function clamp01(v: any, fallback: number): number
	return if type(v) == "number" and v == v then math.clamp(v, 0, 1) else fallback
end

local function read(raw: any): Settings
	local t = if type(raw) == "table" then raw else {}
	local m = if type(t.music) == "table" then t.music else {}
	local w = if type(t.town) == "table" then t.town else {}
	return {
		music = { on = if type(m.on) == "boolean" then m.on else true, volume = clamp01(m.volume, 0.5) },
		town = { on = if type(w.on) == "boolean" then w.on else true, volume = clamp01(w.volume, 0.7) },
		effects = clamp01(t.effects, 1),
	}
end

-- Saved with the account by the server (server/Prefs), a moment after the last change.
local saving = false
local function save()
	if saving then
		return
	end
	saving = true
	task.delay(2, function()
		saving = false
		local remotes = ReplicatedStorage:FindFirstChild("Cartopia")
		local prefs = remotes and remotes:FindFirstChild("Prefs")
		if prefs and prefs:IsA("RemoteEvent") then
			prefs:FireServer(settings)
		end
	end)
end

-- Mixer.set({ music = { on = false } }) or { effects = 0.5 }: changes only what's given.
function Mixer.set(patch: any)
	local next = read({
		music = if patch.music then { on = if patch.music.on ~= nil then patch.music.on else settings.music.on, volume = patch.music.volume or settings.music.volume } else settings.music,
		town = if patch.town then { on = if patch.town.on ~= nil then patch.town.on else settings.town.on, volume = patch.town.volume or settings.town.volume } else settings.town,
		effects = if patch.effects ~= nil then patch.effects else settings.effects,
	})
	settings = next
	apply()
	changed:Fire()
	save()
end

-- The Sound switch (Hud's button and the Menu's) turns the whole group down to 0.
function Mixer.muted(): boolean
	return master.Volume <= 0.001
end

local holds: { [string]: boolean } = {}
local holdChanged = Instance.new("BindableEvent")
Mixer.holdChanged = holdChanged.Event
function Mixer.hold(key: string, on: boolean)
	if (holds[key] == true) == on then
		return
	end
	holds[key] = if on then true else nil
	holdChanged:Fire()
end
function Mixer.held(): boolean
	return next(holds) ~= nil
end

-- A Sound for an uploaded asset (id 0: not uploaded yet, so nil), in a group.
function Mixer.sound(id: number, into: SoundGroup, name: string?): Sound?
	if id == 0 then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name or tostring(id)
	s.SoundId = `rbxassetid://{id}`
	s.SoundGroup = into
	s.Volume = 0
	s.Parent = holder
	return s
end

-- Plays only the part of a sprite from start for length seconds (looping it, if loop).
function Mixer.region(s: Sound, start: number, length: number, loop: boolean?)
	s.PlaybackRegionsEnabled = true
	if loop then
		s.Looped = true
		s.LoopRegion = NumberRange.new(start, start + length)
		s.PlaybackRegion = NumberRange.new(math.max(0, start - 0.5), start + length + 0.5)
	else
		s.PlaybackRegion = NumberRange.new(start, start + length)
	end
end

-- Eases a sound's volume towards v, with a time constant of tau seconds, over dt seconds.
function Mixer.ease(s: Sound, v: number, tau: number, dt: number)
	local a = 1 - math.exp(-dt / math.max(tau, 0.001))
	s.Volume += (v - s.Volume) * a
end

-- The settings the server kept for this account, once they arrive.
local me = Players.LocalPlayer
local function loaded()
	local raw = me:GetAttribute("SoundPrefs")
	if type(raw) == "string" then
		local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
		if ok then
			settings = read(data)
			apply()
			changed:Fire()
		end
	end
end
apply()
if me then
	loaded()
	me:GetAttributeChangedSignal("SoundPrefs"):Connect(loaded)
end

return Mixer
