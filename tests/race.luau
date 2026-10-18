--!nocheck
-- Tests for the drag race (Shared.DragRace): a replay from the recorded presses gives exactly
-- the race the client saw, and it plays like the web game's (a clean run beats a sloppy one).

local DragRace = require("../src/shared/DragRace")
local race = require("../src/shared/Game/race")

local SPEC = { myPi = 40, mySkill = nil, rival = { pi = 38, shift = 0.6, skill = nil }, seed = 12345, track = 400 }

-- A driver: holds the pedal from `holdAt` seconds into the countdown, shifts when the needle
-- passes `shiftAt`, fires the boost in `boostGear`.
local function drive(spec, holdAt, shiftAt, boostGear)
	local r = DragRace.new(spec)
	local holdTick = math.round(holdAt / DragRace.DT)
	local released = false
	while not r.done do
		if r.tick == holdTick then
			DragRace.input(r, "down")
		end
		if r.me.launched and not released then
			DragRace.input(r, "up")
			released = true
		end
		if r.me.launched and r.me.finished == nil and r.me.gear < race.TOP_GEAR and r.me.rpm >= shiftAt then
			DragRace.input(r, "down")
		end
		if boostGear and r.me.gear >= boostGear and not r.me.boostUsed then
			DragRace.input(r, "boost")
		end
		DragRace.step(r)
	end
	return r
end

return function(test)
	test("a replay matches the live race to the last digit", function()
		local live = drive(SPEC, 1.7, 0.9, 3)
		local again = DragRace.replay(SPEC, live.events)
		local a1, b1 = DragRace.times(live)
		local a2, b2 = DragRace.times(again)
		assert(a1 == a2 and b1 == b2, `live {a1}/{b1}, replay {a2}/{b2}`)
		assert(a1 < math.huge and b1 < math.huge, "both finish")
	end)
	test("a clean run beats a sloppy one", function()
		local clean = DragRace.times(drive(SPEC, 1.7, 0.9, 3))
		local sloppy = DragRace.times(drive(SPEC, 0.2, 0.6, nil))
		assert(clean < sloppy, `clean {clean}, sloppy {sloppy}`)
	end)
	test("holding into the launch band gives a perfect launch", function()
		local r = drive(SPEC, 1.7, 0.9, 3)
		assert(r.launch == "PERFECT LAUNCH!", tostring(r.launch))
	end)
	test("the same seed drives the rival the same way", function()
		local _, a = DragRace.times(drive(SPEC, 1.7, 0.9, 3))
		local _, b = DragRace.times(drive(SPEC, 0.5, 0.7, 2))
		assert(a == b, `{a} vs {b}`)
	end)
	test("bad press lists are refused", function()
		assert(DragRace.valid({ { tick = 5, kind = "down" }, { tick = 9, kind = "up" } }))
		assert(not DragRace.valid({ { tick = 9, kind = "down" }, { tick = 5, kind = "up" } }))
		assert(not DragRace.valid({ { tick = 1.5, kind = "down" } }))
		assert(not DragRace.valid({ { tick = 1, kind = "warp" } }))
		assert(not DragRace.valid("nope"))
	end)
end
