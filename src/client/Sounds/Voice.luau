--!strict
-- The tutorial's spoken lines (the web's lib/tutorialVoice.ts), from Kegan's recordings in one
-- uploaded sprite. A line plays when its step comes up, stops when the step changes or the
-- tutorial ends, and once it has been heard to the end it isn't said again. It plays through the
-- Voice group, so the Sound switch silences it.
--
--   Voice.say("03-collect")   say the line for the step on screen (nil: say nothing)
--   Voice.stop()              the tutorial ended or closed
--
-- Which line goes with which step (the web's ui/Tutorial.tsx STEPS, in order):
--   1  "Welcome to Cartopia!..."                        01-welcome
--   2  "Tap a pulsing ⛽ bubble to send a car on a..."   02-pizza-job
--   3  "When the gold $ pops up, tap it to collect."     03-collect
--   4  build a shop: 04-build-shop; once placing (mode "place"): 05-build-lot-tap on a touch
--      screen, 06-build-lot-click with a mouse
--   5  find cars: 07-built-find while still editing the town, else 08-find-cars
--   6  "Restore a find in Rusty's bay..."               09-restore
--   7  "Make it yours: one paint, one set of rims."     10-paint-rims
--   8  "Races use gas..."                               11-gas
--   9  "While Rusty works, tap RACE for your first race!" 12-first-race
-- Voice.forStep(n, { placing, touch, editing }) gives the same answer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AudioAssets")) :: any
local Mixer = require(script.Parent.Mixer)

local Voice = {}

Voice.LINES = {
	"01-welcome", "02-pizza-job", "03-collect", "04-build-shop", "05-build-lot-tap", "06-build-lot-click",
	"07-built-find", "08-find-cars", "09-restore", "10-paint-rims", "11-gas", "12-first-race",
}

-- The line for tutorial step n (1-based, as listed above).
function Voice.forStep(n: number, s: { placing: boolean?, touch: boolean?, editing: boolean? }?): string?
	local o = s or {}
	if n == 4 then
		return if o.placing then (if o.touch then "05-build-lot-tap" else "06-build-lot-click") else "04-build-shop"
	elseif n == 5 then
		return if o.editing then "07-built-find" else "08-find-cars"
	end
	local by = { "01-welcome", "02-pizza-job", "03-collect", nil, nil, "09-restore", "10-paint-rims", "11-gas", "12-first-race" }
	return by[n]
end

local SPRITE = Assets.sprites.voice
local said: { [string]: boolean } = {}
local want: string? = nil
local playing: Sound? = nil

function Voice.stop()
	want = nil
	if playing then
		playing:Destroy()
		playing = nil
	end
end

function Voice.say(id: string?)
	if id == want and playing then
		return
	end
	Voice.stop()
	want = id
	if not id or said[id] or Mixer.muted() or SPRITE.id == 0 then
		return
	end
	local part = SPRITE.regions[id]
	local s = part and Mixer.sound(SPRITE.id, Mixer.voice, `Voice {id}`)
	if not s then
		return
	end
	Mixer.region(s, part.start, part.length)
	s.Volume = 1
	playing = s
	s.Ended:Connect(function()
		if playing == s then
			playing = nil
			said[id] = true
			s:Destroy()
		end
	end)
	s:Play()
end

return Voice
