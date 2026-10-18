--!strict
-- The town's music, as the web game's lib/townMusic.ts plays it: every season has three day songs
-- and three night songs, and it shuffles like a game soundtrack: one song, a moment's quiet, then a
-- different one that suits the season and the time of day, never one of the last three played.
-- (On the web the songs are synthesised as they play; here they're Kegan's recordings of them.)
--
-- It sits under the town sounds, fades out during races and arcade games (Mixer.hold), gives way
-- to the nightclub as the camera nears it (Club) and to Rave Mode's music (Rave), and follows the
-- Menu's Music switch and slider (the Music group). A song faded out for more than two seconds is
-- let go, so coming back starts a fresh one, as on the web.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("AudioAssets")) :: any
local clock = require(Shared:WaitForChild("Game"):WaitForChild("clock")) :: any
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local Mixer = require(script.Parent.Mixer)

local Music = {}

-- How loud the music runs at full slider, to sit just above the town sounds (townMusic.ts TRIM).
local TRIM = 0.38

type Song = { key: string, season: string, night: boolean, id: number, length: number }
local SONGS: { Song } = {}
for key, e in Assets.music do
	-- "fall-day-cider-mill": season, time of day, then the song's name.
	local season, time = string.match(key, "^(%a+)%-(%a+)%-")
	if season and time then
		table.insert(SONGS, { key = key, season = season, night = time == "night", id = e.id, length = e.length or 120 })
	end
end
table.sort(SONGS, function(a, b)
	return a.key < b.key
end)

-- The songs for this season and time of day that are uploaded, leaving out the last few played if
-- there are others (townMusic.ts songsFor).
local recent: { string } = {}
function Music.songsFor(night: boolean, season: string): { Song }
	local fit = {}
	for _, s in SONGS do
		if s.night == night and s.season == season and s.id ~= 0 then
			table.insert(fit, s)
		end
	end
	for k = 1, #recent do
		local fresh = {}
		for _, s in fit do
			if not table.find(recent, s.key, k) then
				table.insert(fresh, s)
			end
		end
		if #fresh > 0 then
			return fresh
		end
	end
	return fit
end

-- How much the music gives way to something else (the club near, 0..1), and whether Rave Mode
-- has the music bus. Set by Club and Rave.
local duck = 0
function Music.duck(v: number)
	duck = math.clamp(v, 0, 1)
end
local rave = false
function Music.rave(on: boolean)
	rave = on
end

local playing: Song? = nil
local sound: Sound? = nil
local resting = 0 -- while between songs: when the next one may start (os.clock)
local quietSince = 0

local nowPlaying = Instance.new("BindableEvent")
Music.changed = nowPlaying.Event
function Music.nowPlaying(): string?
	return playing and playing.key
end

local function target(): number
	local m = Mixer.settings().music
	if not m.on or Mixer.muted() or Mixer.held() or rave then
		return 0
	end
	return TRIM * (1 - duck)
end

local function drop()
	if sound then
		sound:Destroy()
	end
	sound = nil
	if playing then
		playing = nil
		nowPlaying:Fire()
	end
end

local function start(night: boolean)
	local choices = Music.songsFor(night, Catalog.SEASON)
	if #choices == 0 then
		return
	end
	local song = choices[math.random(1, #choices)]
	table.insert(recent, song.key)
	if #recent > 3 then
		table.remove(recent, 1)
	end
	local s = Mixer.sound(song.id, Mixer.music, song.key)
	if not s then
		return
	end
	playing = song
	sound = s
	s.Volume = 0
	s:Play()
	-- The recording ends with the song ringing out; then a moment's quiet before the next.
	s.Ended:Connect(function()
		if sound == s then
			drop()
			resting = os.clock() + math.random() * 1
		end
	end)
	nowPlaying:Fire()
end

function Music.start()
	RunService.Heartbeat:Connect(function(dt)
		local v = target()
		local now = os.clock()
		if v > 0.001 then
			quietSince = 0
			if not sound and now >= resting then
				start(clock.nightAmount(clock.dayPhase()) > 0.5)
			end
			if sound then
				Mixer.ease(sound, v, 0.8, dt)
			end
		elseif sound then
			Mixer.ease(sound, 0, 0.3, dt)
			if quietSince == 0 then
				quietSince = now
			elseif now - quietSince > 2 then
				drop()
			end
		end
	end)
end

return Music
