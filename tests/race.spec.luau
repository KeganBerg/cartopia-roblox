--!nocheck
-- Ported from the web game's src/game/race.test.ts.
local Race = require("../src/shared/Race")
local RaceFloors = require("../src/shared/RaceFloors")
local expect = require("./expect")

return function(test)
	test("has a referee floor for every PI up to MAX_RACE_PI", function()
		expect(#RaceFloors).toBe(Race.MAX_RACE_PI)
		for pi = 2, Race.MAX_RACE_PI do
			expect(RaceFloors[pi]).toBeLessThan(RaceFloors[pi - 1])
		end
	end)

	test("never calls a perfect honest race too fast", function()
		for _, pi in { 15, 40, 80, 120 } do
			for _, dt in { 1 / 30, 1 / 60, 1 / 144 } do
				local r = Race.freshRacer()
				local t = 0
				while r.finished == nil do
					t += dt
					if r.gear < 3 and r.rpm >= 0.8 then
						r.quality = 1.08
						r.gear += 1
						r.rpm = 0.35
					end
					Race.stepRacer(r, pi, dt, t, if r.gear == 0 then 1.2 else 1)
				end
				expect(r.finished).toBeGreaterThan(Race.raceFloor(pi))
			end
		end
	end)

	test("never calls a perfect boosted race too fast, whenever the boost fires", function()
		for _, pi in { 15, 40, 80, 120, 200 } do
			for _, fireAt in { 0.3, 0.8, 1.5, 2.5 } do
				local r = Race.freshRacer(false)
				local dt = 1 / 144
				local t = 0
				while r.finished == nil do
					t += dt
					if not r.launched then
						Race.launchRacer(r, 0)
					end
					if r.gear < 3 and r.rpm >= 0.92 then
						Race.shiftRacer(r, 1.08)
					end
					if t >= fireAt then
						Race.fireBoost(r)
					end
					Race.stepRacer(r, pi, dt, t, if r.gear == 0 then 1.2 else 1)
				end
				expect(r.finished).toBeGreaterThan(Race.raceFloor(pi))
			end
		end
	end)

	local function run(launchAt, fire, shiftAt)
		shiftAt = shiftAt or 0.9
		local r = Race.freshRacer(false)
		local dt = 1 / 120
		local t = 0
		while r.finished == nil and t < 60 do
			t += dt
			if not r.launched and t >= (if launchAt < 0 then Race.JUMP_START_DELAY else launchAt) then
				Race.launchRacer(r, launchAt)
			end
			if r.launched and r.gear < 3 and r.rpm >= shiftAt then
				Race.shiftRacer(r, if shiftAt >= 0.78 and shiftAt <= 0.93 then 1.08 else 0.75)
			end
			if fire(r, t) then
				Race.fireBoost(r)
			end
			Race.stepRacer(r, 60, dt, t)
		end
		return r.finished
	end
	local never = function()
		return false
	end
	local midRace = function(r)
		return r.gear >= 2
	end

	test("rewards a quick launch and punishes a jump start", function()
		expect(run(0.2, never)).toBeLessThan(run(0.6, never))
		expect(run(-1, never)).toBeGreaterThan(run(0.2, never))
	end)

	test("fills the tank from a clean launch and clean shifts, and fires once", function()
		local r = Race.freshRacer(false)
		Race.launchRacer(r, 0.1)
		for _ = 1, 3 do
			Race.shiftRacer(r, 1.08)
		end
		expect(r.boost).toBeCloseTo(1)
		expect(r.streak).toBe(3)
		expect(Race.fireBoost(r)).toBe(true)
		expect(Race.fireBoost(r)).toBe(false)
		local sloppy = Race.freshRacer(false)
		Race.launchRacer(sloppy, 0.8)
		for _ = 1, 3 do
			Race.shiftRacer(sloppy, 0.75)
		end
		expect(sloppy.boost).toBe(0)
		expect(Race.fireBoost(sloppy)).toBe(false)
	end)

	test("is worth firing mid-race, and wasted off the line", function()
		expect(run(0.2, midRace)).toBeLessThan(run(0.2, never))
		expect(run(0.2, function(r)
			return r.launched
		end)).toBeGreaterThan(run(0.2, midRace))
	end)

	test("lets clean driving beat a quicker car driven sloppily", function()
		local clean = run(0.15, midRace)
		local r = Race.freshRacer(false)
		local dt = 1 / 120
		local t = 0
		while r.finished == nil do
			t += dt
			if not r.launched and t >= 0.6 then
				Race.launchRacer(r, 0.6)
			end
			if r.launched and r.gear < 3 and r.rpm >= 0.7 then
				Race.shiftRacer(r, 0.95)
			end
			Race.stepRacer(r, 68, dt, t)
		end
		expect(clean).toBeLessThan(r.finished)
	end)

	test("garage dyno gets quicker with every point of PI and never beats the referee", function()
		local last = math.huge
		for pi = 10, 200, 5 do
			local t = Race.dynoPull(pi)
			expect(t).toBeLessThan(last)
			expect(t).toBeGreaterThan(Race.raceFloor(pi))
			last = t
		end
	end)
end
