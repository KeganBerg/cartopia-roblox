--!strict
-- Rave Mode's music, as the web game's lib/technoMusic.ts plays its techno track: a ten-second
-- build-up that fades in from silence through the warning so nobody is startled, then the drop,
-- looping (Kegan's recordings: build-up and drop-loop). Everyone hears the same moment: where it
-- is comes from the wall clock and the drop, not from when this player's sound started.
--
--   Rave.start(dropAt)   dropAt: when the drop lands, in ms since the epoch (Unix time), as the
--                        web's technoDrop(); the build-up plays through the ten seconds before.
--                        Leave it out for a drop ten seconds from now.
--   Rave.stop()          the event's over: a short fade, then the town's music comes back.
--   Rave.isOn()
--
-- It runs on the Music switch and slider, louder than the town's music (it's a party), falls
-- silent while muted and during races and arcade games, and the town's music and the club give
-- way to it while it's on (the town's sounds turn down by half).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Assets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AudioAssets")) :: any
local Mixer = require(script.Parent.Mixer)
local Music = require(script.Parent.Music)
local Ambience = require(script.Parent.Ambience)
local Club = require(script.Parent.Club)

local Rave = {}

-- techno.ts BUILD_MS: the warning before the drop.
local BUILD = 10
-- How loud it runs at full music slider (technoMusic.ts TRIM for our own track).
local TRIM = 0.85

local BUILDUP = Assets.rave["build-up"]
local DROP = Assets.rave["drop-loop"]

local dropAt: number? = nil
local changed = Instance.new("BindableEvent")
Rave.changed = changed.Event

local buildSound: Sound? = nil
local dropSound: Sound? = nil
local quietSince = 0

local function tell(on: boolean)
	Music.rave(on)
	Club.rave(on)
	Ambience.rave(on)
end

function Rave.isOn(): boolean
	return dropAt ~= nil
end

function Rave.start(at: number?)
	dropAt = at or DateTime.now().UnixTimestampMillis + BUILD * 1000
	tell(true)
	changed:Fire(true)
end

function Rave.stop()
	if not dropAt then
		return
	end
	dropAt = nil
	tell(false)
	changed:Fire(false)
end

-- How far faded in, s seconds after the warning started: from silence to full over the warning,
-- gently at first (technoMusic.ts fadeAt).
function Rave.fadeAt(s: number): number
	local x = math.clamp(s / BUILD, 0, 1)
	return x * x
end

local function free()
	if buildSound then
		buildSound:Destroy()
	end
	if dropSound then
		dropSound:Destroy()
	end
	buildSound, dropSound = nil, nil
end

-- Keeps a sound where it should be, moving it only when it's drifted (a moment's hitch).
local function keep(s: Sound, want: number, loop: number?)
	local off = math.abs(s.TimePosition - want)
	if loop then
		off = math.min(off, loop - off)
	end
	if s.IsLoaded and off > 0.08 then
		s.TimePosition = want
	end
end

-- Runs the music while an event is on (Sounds.start calls it once).
function Rave.listen()
	RunService.Heartbeat:Connect(function(dt)
		local m = Mixer.settings().music
		local on = dropAt ~= nil and m.on and not Mixer.muted() and not Mixer.held()
		if not on then
			local tau = if dropAt then 0.2 else 0.8
			for _, s in { buildSound, dropSound } do
				if s then
					Mixer.ease(s :: Sound, 0, tau, dt)
				end
			end
			if buildSound or dropSound then
				if quietSince == 0 then
					quietSince = os.clock()
				elseif os.clock() - quietSince > 4 then
					free()
				end
			end
			return
		end
		quietSince = 0
		local s = (DateTime.now().UnixTimestampMillis - ((dropAt :: number) - BUILD * 1000)) / 1000
		local level = TRIM * Rave.fadeAt(s)
		if s < BUILD then
			if not buildSound and BUILDUP and BUILDUP.id ~= 0 then
				buildSound = Mixer.sound(BUILDUP.id, Mixer.music, "Rave build-up")
				if buildSound then
					buildSound:Play()
				end
			end
			if buildSound then
				keep(buildSound, math.max(0, s))
				Mixer.ease(buildSound, level, 0.15, dt)
			end
		else
			if buildSound then
				Mixer.ease(buildSound, 0, 0.1, dt)
				if s > BUILD + 1 then
					buildSound:Destroy()
					buildSound = nil
				end
			end
			if not dropSound and DROP and DROP.id ~= 0 then
				dropSound = Mixer.sound(DROP.id, Mixer.music, "Rave drop")
				if dropSound then
					Mixer.region(dropSound, DROP.loop.start, DROP.loop.length, true)
					dropSound:Play()
				end
			end
			if dropSound then
				keep(dropSound, DROP.loop.start + (s - BUILD) % DROP.loop.length, DROP.loop.length)
				Mixer.ease(dropSound, level, 0.15, dt)
			end
		end
	end)
end

return Rave
