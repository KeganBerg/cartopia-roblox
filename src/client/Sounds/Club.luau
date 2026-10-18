--!strict
-- The nightclub's music, as the web game's lib/clubSet.ts picks it: while the club is open (at
-- night) it plays one track all night, a different one each night, from Kegan's recordings of the
-- web's eighteen club tracks (01-deep ... 18-witch). The track and where it is come from the town
-- clock, so every player hears the same moment of the same track: night n plays trackOf(n), and
-- the track has been looping since the night began.
--
-- It's louder the nearer the camera is to the club, and the town's music gives way to it as it
-- does (Music.duck). It follows the Town sounds switch and slider, is quiet during races and
-- arcade games, and stops under Rave Mode (Rave has the music then).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared:WaitForChild("AudioAssets")) :: any
local Game = Shared:WaitForChild("Game")
local clock = require(Game:WaitForChild("clock")) :: any
local store = require(Game:WaitForChild("store")) :: any
local ClubSet = require(Shared:WaitForChild("ClubSet")) :: any
local Mixer = require(script.Parent.Mixer)
local Music = require(script.Parent.Music)
local Town = require(script.Parent.Parent.Town)

local Club = {}

-- The tracks in the web's GROOVES order (clubGrooves.ts), which the recordings are numbered by.
type Track = { key: string, id: number, start: number, length: number }
local TRACKS: { Track } = {}
for key, e in Assets.club do
	if e.loop then
		table.insert(TRACKS, { key = key, id = e.id, start = e.loop.start, length = e.loop.length })
	end
end
table.sort(TRACKS, function(a, b)
	return a.key < b.key
end)

function Club.trackOf(night: number): number
	return ClubSet.trackOf(night, #TRACKS)
end

-- How near the club sounds, 0..1: 1 with the camera close by, nothing from the far side of town.
local function near(): number
	if not clock.isNight() then
		return 0
	end
	local s = store.useGame.getState()
	local club = nil
	for _, b in s.buildings or {} do
		if b.def == "club" then
			club = b
			break
		end
	end
	if not club then
		return 0
	end
	local at = Town.tileToWorld(club.x, club.z)
	local folder = Town.folder()
	local cam = workspace.CurrentCamera
	if not at or not folder or not cam then
		return 0
	end
	local tile = (folder:GetAttribute("TileSize") :: number?) or 8
	local d = (cam.CFrame.Position - at).Magnitude / tile
	return math.clamp(1 - (d - 6) / 24, 0, 1)
end

local rave = false
function Club.rave(on: boolean)
	rave = on
end

local current: Track? = nil
local sound: Sound? = nil
local function stop()
	if sound then
		sound:Destroy()
	end
	sound = nil
	current = nil
end

function Club.start()
	if #TRACKS == 0 then
		return
	end
	local acc = 0
	local n = 0
	RunService.Heartbeat:Connect(function(dt)
		-- How near only changes as the camera moves; once every few frames is plenty.
		acc += dt
		if acc >= 0.1 then
			acc = 0
			n = if rave or Mixer.held() or Mixer.muted() or not Mixer.settings().town.on then 0 else near()
			Music.duck(n)
		end
		if n <= 0.001 then
			if sound then
				Mixer.ease(sound, 0, 0.3, dt)
				if sound.Volume < 0.005 then
					stop()
				end
			end
			return
		end
		local wall = DateTime.now().UnixTimestampMillis
		local night = math.floor(wall / clock.DAY_MS)
		local track = TRACKS[Club.trackOf(night) + 1]
		if track ~= current or not sound then
			stop()
			if track.id == 0 then
				return
			end
			current = track
			sound = Mixer.sound(track.id, Mixer.town, `Club {track.key}`)
			if not sound then
				return
			end
			Mixer.region(sound, track.start, track.length, true)
			sound:Play()
		end
		local s = sound :: Sound
		-- Where everyone is in tonight's track: looping since the night began.
		local want = track.start + ((wall - night * clock.DAY_MS) / 1000) % track.length
		if s.IsLoaded and math.abs(s.TimePosition - want) > 0.25 and math.abs(s.TimePosition - want) < track.length - 0.25 then
			s.TimePosition = want
		end
		Mixer.ease(s, n, 0.5, dt)
	end)
end

return Club
