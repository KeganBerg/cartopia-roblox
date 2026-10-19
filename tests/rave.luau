--!nocheck
-- Tests for Rave Mode's timing (shared/RaveTime, and the converted game/techno.ts) and the town
-- weather schedule (game/weather.ts) the client modules draw.

local Js = require("../src/shared/Game/__js")
local G = "../src/shared/Game/"

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

local function near(a, b, eps)
	assert(math.abs(a - b) <= (eps or 1e-9), `{a} ~= {b}`)
end

return function(test)
	local RaveTime = require("../src/shared/RaveTime")
	local techno = require(G .. "techno")
	local clock = require(G .. "clock")
	local weather = require(G .. "weather")

	test("techno: our own track's tempo and build-up, as on the web", function()
		assert(techno.TECHNO_BPM == 150, `bpm {techno.TECHNO_BPM}`)
		near(techno.SIXTEENTH_MS, 100)
		assert(techno.BUILD_MS == 10000)
		assert(techno.CYCLE_BARS == 24)
		assert(techno.WEEKLY.day == 5 and techno.WEEKLY.hour == 22 and techno.WEEKLY.minutes == 1)
	end)

	test("techno: the beat kicks on the drop and flashes, builds up before it", function()
		local drop = NOW + 10000
		local b = techno.technoBeat(drop, drop)
		assert(b.n == 0 and b.beat == 0 and b.bar == 0 and b.section == "drop")
		near(b.kick, 1)
		near(b.drop, 1)
		local before = techno.technoBeat(drop - 5000, drop)
		near(before.build, 0.5)
		assert(before.kick == 0, "no kick in the build-up")
		-- The breakdown (bars 20-23 of each cycle) has no kick.
		local brk = techno.technoBeat(drop + 21 * techno.BAR_MS, drop)
		assert(brk.section == "break" and brk.kick == 0)
		assert(techno.technoBeat(drop + 400, drop).side == -1)
	end)

	test("techno: starting a rave pulls the town clock into the night, and back after", function()
		local day = clock.dayPhase(NOW)
		techno.startEvent("techno", { from = NOW, ["until"] = NOW + RaveTime.BUTTON_MS })
		assert(techno.technoOn(NOW))
		near(techno.technoToDrop(NOW), 10000)
		NOW += 6000
		near(clock.dayPhase(NOW), 0.5, 1e-6)
		NOW += RaveTime.BUTTON_MS
		assert(not techno.technoOn(NOW))
		techno.stopEvent("techno")
		NOW += 7000
		near(clock.dayPhase(NOW), clock.naturalPhase(NOW), 1e-9)
		assert(day == day)
	end)

	test("rave button: 68.2 seconds from the press, a second press changes nothing", function()
		local w = RaveTime.press(1000, nil, 10000)
		assert(w.from == 1000 and w.drop == 11000 and w.to == 69200)
		local again = RaveTime.press(30000, w, 10000)
		assert(again == w, "a press while on keeps the rave")
		local later = RaveTime.press(70000, w, 10000)
		assert(later.from == 70000, "a press after it ended starts a new one")
	end)

	test("weekly rave: Friday 10 pm local, a minute, with the ten seconds before", function()
		-- A UTC calendar for the test (the client uses the device's own).
		local function date(s)
			return os.date("!*t", s)
		end
		local function time(t)
			-- os.time reads local time; turn the UTC fields into epoch seconds by hand.
			local days = 0
			local y, m, d = t.year, t.month, t.day
			if m <= 2 then
				y -= 1
				m += 12
			end
			days = 365 * y + y // 4 - y // 100 + y // 400 + (153 * (m - 3) + 2) // 5 + d - 719469
			return days * 86400 + t.hour * 3600 + t.min * 60 + t.sec
		end
		-- 2026-10-16 is a Friday.
		local drop = time({ year = 2026, month = 10, day = 16, hour = 22, min = 0, sec = 0 }) * 1000
		assert(os.date("!*t", drop // 1000).wday == 6, "a Friday")
		local w = RaveTime.weekly(drop + 30000, techno.WEEKLY, 10000, date, time)
		assert(w and w.drop == drop and w.from == drop - 10000 and w.to == drop + 60000)
		assert(RaveTime.weekly(drop - 5000, techno.WEEKLY, 10000, date, time), "on through the build-up")
		assert(RaveTime.weekly(drop - 20000, techno.WEEKLY, 10000, date, time) == nil)
		assert(RaveTime.weekly(drop + 61000, techno.WEEKLY, 10000, date, time) == nil)
		assert(RaveTime.weekly(drop - 86400000, techno.WEEKLY, 10000, date, time) == nil, "not on Thursday")
	end)

	test("weather: the schedule rolls every kind the town shows, and the feel adds up", function()
		local seen = {}
		local t = NOW
		for _ = 1, 20000 do
			seen[weather.spellKind(math.floor(t / weather.SPELL_MS), "spring")] = true
			t += weather.SPELL_MS
		end
		for _, k in { "clear", "rain", "storm", "drizzle", "fog", "clearing", "mist" } do
			assert(seen[k], `spring never rolled {k}`)
		end
		local w = weather.weatherNow(NOW)
		local sum = 0
		for _, k in weather.WEATHER_KINDS do
			sum += w.mix[k]
		end
		near(sum, 1, 1e-6)
		weather.setCalmSky(true)
		local calm = weather.weatherNow(NOW + 20 * 60 * 1000)
		assert(calm.mix.clear > 0.99 and calm.rain == 0, "the tutorial's sky is clear")
		weather.setCalmSky(false)
	end)
end
