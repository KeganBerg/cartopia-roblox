--!strict
-- The game's music and sounds, from Kegan's recordings of the web game's (uploaded by
-- tools/audio/build.mjs and tools/models/upload.mjs, ids in Shared.AudioAssets):
--   Mixer     the sound groups, the player's Music / Town sounds / Effects settings, Mixer.hold
--   Sfx       sound effects, named as the web's sfx.* calls (Sfx.coin(), Sfx.crate.open("gold"))
--   Music     the town's music: three day and three night songs a season, shuffled
--   Ambience  the town's sounds and its weather (Ambience.setWeather, Ambience.thunder)
--   Club      the nightclub's track for the night, louder near the club
--   Rave      Rave Mode's build-up and drop (Rave.start(dropAt), Rave.stop())
--   Voice     the tutorial's spoken lines (Voice.say(line))
-- Sounds.start() sets them all going (client entry point).

local Sounds = {}

Sounds.Mixer = require(script.Mixer)
Sounds.Sfx = require(script.Sfx)
Sounds.Music = require(script.Music)
Sounds.Ambience = require(script.Ambience)
Sounds.Club = require(script.Club)
Sounds.Rave = require(script.Rave)
Sounds.Voice = require(script.Voice)

function Sounds.start()
	Sounds.Sfx.preload()
	Sounds.Music.start()
	Sounds.Ambience.start()
	Sounds.Club.start()
	Sounds.Rave.listen()
	-- The sounds the town's actions made on the server (buying, collecting, levelling up...).
	-- The first snapshot is the town arriving: nothing to hear in it.
	local Remote = require(script.Parent.Remote) :: any
	local first = true
	Remote.changed:Connect(function(snap)
		if first then
			first = false
			return
		end
		Sounds.Sfx.heard(snap.sounds)
	end)
end

return Sounds
