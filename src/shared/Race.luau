--!strict
-- Drag race physics, ported from the web game's src/game/race.ts. The server uses the same code as
-- the client to referee races (raceFloor), so keep both versions in step.
-- Gears are 0-based (0 = first) to match the web game; the per-gear tables are indexed gear + 1.

local RaceFloors = require("./RaceFloors")

local Race = {}

Race.TRACK = 400
Race.GEAR_POWER = { 1, 0.85, 0.72, 0.6 }

-- Boost: how hard it pushes in each gear (it only spins the tires in first), and how long a full tank lasts.
Race.BOOST_MUL = { 0.85, 1.1, 1.25, 1.35 }
Race.BOOST_SECONDS = 1.6
-- What a launch fills the tank with by reaction time (seconds after GO), and what each shift adds.
Race.LAUNCH_FILL = { perfect = 0.34, good = 0.15 }
Race.SHIFT_FILL = { perfect = 0.22, good = 0.1 }
-- Pressing before GO is a jump start: off the line this many seconds after GO, with wheelspin
-- through first gear and nothing in the boost tank.
Race.JUMP_START_DELAY = 0.6
Race.JUMP_START_Q = 0.8
-- A player who never presses goes anyway after this long.
Race.AUTO_LAUNCH = 1.2

-- launched: off the line yet (racers made for the floor and the stand-ins start launched).
-- boost: the boost tank, 0-1, filled by a clean launch and clean shifts. burning: boost is firing.
-- boostUsed: boost fires once a race. streak: clean shifts in a row. finished: finish time, nil until then.
export type Racer = {
	gear: number,
	rpm: number,
	speed: number,
	dist: number,
	quality: number,
	finished: number?,
	launched: boolean,
	boost: number,
	burning: boolean,
	boostUsed: boolean,
	streak: number,
}

function Race.freshRacer(launched: boolean?): Racer
	local l = if launched == nil then true else launched
	return {
		gear = 0,
		rpm = 0,
		speed = 0,
		dist = 0,
		quality = 1,
		finished = nil,
		launched = l,
		boost = if l then Race.LAUNCH_FILL.perfect else 0,
		burning = false,
		boostUsed = false,
		streak = 0,
	}
end

function Race.stepRacer(r: Racer, piVal: number, dt: number, t: number, mul: number?)
	if r.finished ~= nil or not r.launched then
		return
	end
	local m = mul or 1
	local climb = (1.25 - r.gear * 0.16) * (0.85 + piVal / 300)
	-- Top gear just holds near the redline; lower gears bounce off the limiter.
	r.rpm = math.min(if r.gear == 3 then 0.95 else 1.05, r.rpm + climb * dt)
	local overRev = r.rpm >= 1
	if r.burning then
		m *= Race.BOOST_MUL[r.gear + 1]
		r.boost -= dt / Race.BOOST_SECONDS
		if r.boost <= 0 then
			r.boost = 0
			r.burning = false
		end
	end
	local accel = (piVal / 100) * 70 * Race.GEAR_POWER[r.gear + 1] * r.quality * (if overRev then 0.25 else 1) * (0.4 + r.rpm * 0.6)
	r.speed += accel * m * dt
	r.speed *= 1 - 0.04 * dt
	r.dist += r.speed * dt
	if r.dist >= Race.TRACK then
		r.finished = t
	end
end

-- lo..hi is the perfect window; rain and snow narrow it (see grip.ts in the web game).
function Race.shiftQuality(rpm: number, lo: number?, hi: number?): (number, string)
	local l, h = lo or 0.78, hi or 0.93
	if rpm >= l and rpm <= h then
		return 1.08, "PERFECT!"
	end
	if rpm >= 0.65 and rpm < l then
		return 0.95, "Good"
	end
	if rpm > h then
		return 0.85, "Late"
	end
	return 0.75, "Early"
end

-- Off the line `reaction` seconds after GO (negative: a jump start, which the caller holds until
-- JUMP_START_DELAY). Returns the call to show.
function Race.launchRacer(r: Racer, reaction: number): string
	r.launched = true
	if reaction < 0 then
		r.quality = Race.JUMP_START_Q
		r.boost = 0
		return "JUMP START!"
	end
	if reaction <= 0.25 then
		r.boost = Race.LAUNCH_FILL.perfect
		return "PERFECT LAUNCH!"
	end
	if reaction <= 0.5 then
		r.boost = Race.LAUNCH_FILL.good
		return "Good launch"
	end
	r.boost = 0
	return "Slow launch"
end

-- Up a gear with shift quality q (1.08 perfect, 0.95 good). Clean shifts fill the boost tank.
function Race.shiftRacer(r: Racer, q: number)
	r.quality = q
	r.gear += 1
	r.rpm = 0.35
	r.streak = if q >= 1 then r.streak + 1 else 0
	local fill = if q >= 1 then Race.SHIFT_FILL.perfect elseif q >= 0.95 then Race.SHIFT_FILL.good else 0
	r.boost = math.min(1, r.boost + fill)
end

-- Fires the boost: it burns until the tank is empty, and once a race.
function Race.fireBoost(r: Racer): boolean
	if r.boostUsed or r.boost <= 0 or not r.launched or r.finished ~= nil then
		return false
	end
	r.boostUsed = true
	r.burning = true
	return true
end

-- AI rivals: reaction off the line by how cleanly they shift (0 sloppy to 1 clean; roll is 0-1
-- random), and they fire their boost as they reach this gear.
function Race.aiReaction(cleanness: number, roll: number): number
	return 0.12 + (1 - cleanness) * 0.3 + roll * 0.12
end
Race.AI_BOOST_GEAR = 2

-- The fastest a car with this PI can finish: a perfect launch the instant the lights go green,
-- every shift perfect at the best shift point, the boost fired at the best moment, with whichever
-- skill helps most, less 2.5% for uneven frame timing. The referee raises any faster reported time
-- to this.
Race.MAX_RACE_PI = 250

type SkillFn = (Racer, number) -> number
-- No skill at all is left out: Slipstream pushes at least as hard everywhere.
local SKILL_BOOST: { SkillFn } = {
	function(r) -- launch
		return if r.gear == 0 then 1.2 else 1
	end,
	function(r) -- nitro
		return if r.gear == 3 then 1.15 else 1
	end,
	function() -- slipstream
		return 1.08
	end,
	function(_, t) -- oil
		return if t < 2.5 then 1.1 else 1
	end,
	function(r) -- torque
		return if r.gear <= 1 then 1.1 else 1
	end,
	function(r) -- freeze
		return if r.gear == 1 then 1.1 else 1
	end,
}

-- One perfect run: shift at `at` rpm, fire the boost at `fireAt` seconds. Returns the finish
-- time and when the last shift happened.
function Race.perfectRun(piVal: number, skill: SkillFn, at: number, fireAt: number): (number, number)
	local r = Race.freshRacer()
	local dt = 1 / 240
	local t = 0
	local lastShift = 0
	while r.finished == nil and t < 120 do
		t += dt
		if r.gear < 3 and r.rpm >= at then
			Race.shiftRacer(r, 1.08)
			lastShift = t
		end
		if t >= fireAt then
			Race.fireBoost(r)
		end
		Race.stepRacer(r, piVal, dt, t, skill(r, t))
	end
	return r.finished or math.huge, lastShift
end

-- The best shift point is always near the top of the perfect band, and a time is only ever
-- floored, so a few points and a coarse-then-fine search for the boost are plenty.
local floors: { [number]: number } = {}
function Race.raceFloor(piVal: number): number
	local known = floors[piVal] or RaceFloors[piVal]
	if known then
		return known
	end
	return Race.computeRaceFloor(piVal)
end

-- The slow search behind raceFloor (about a second per PI). Only PIs outside RaceFloors get here.
function Race.computeRaceFloor(piVal: number): number
	local best = math.huge
	for _, skill in SKILL_BOOST do
		for _, at in { 0.9, 0.92, 0.93 } do
			-- Firing later than just after the tank is full only loses time.
			local _, lastShift = Race.perfectRun(piVal, skill, at, math.huge)
			local near, nearT = 0, math.huge
			local fireAt = 0
			while fireAt <= lastShift + 0.6 do
				local time = Race.perfectRun(piVal, skill, at, fireAt)
				if time < nearT then
					near, nearT = fireAt, time
				end
				fireAt += 0.1
			end
			fireAt = math.max(0, near - 0.1)
			while fireAt <= near + 0.1 do
				nearT = math.min(nearT, (Race.perfectRun(piVal, skill, at, fireAt)))
				fireAt += 0.02
			end
			best = math.min(best, nearT)
		end
	end
	local floor = math.floor(best * 0.975 * 1000) / 1000
	floors[piVal] = floor
	return floor
end

-- One clean pull, as the garage dyno runs it: every shift perfect at 85%, no skill.
-- Calls `each` with the racer after every step, and returns the finish time.
Race.DYNO_DT = 1 / 120
function Race.dynoPull(piVal: number, each: ((Racer, number) -> ())?): number
	local r = Race.freshRacer()
	local t = 0
	while r.finished == nil and t < 120 do
		t += Race.DYNO_DT
		if r.gear < 3 and r.rpm >= 0.85 then
			r.quality = 1.08
			r.gear += 1
			r.rpm = 0.35
		end
		Race.stepRacer(r, piVal, Race.DYNO_DT, t)
		if each then
			each(r, t)
		end
	end
	return math.floor((r.finished or t) * 100 + 0.5) / 100
end

return Race
