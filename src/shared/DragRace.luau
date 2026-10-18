--!strict
-- One drag race, run the way the web game's race screen runs it (ui/Race.tsx DragRace): the
-- countdown, revving on the line, the launch at GO, shifts, the boost and an AI rival, stepped at
-- the web game's fixed RACE_DT with its own physics (Shared.Game.race).
--
-- The client runs it live and records every press with the step it landed on. The server runs the
-- same race again from those presses (DragRace.replay) and pays what that run earns, so the result
-- can't be made up: the same Luau code on both sides gives the same times to the last digit.
--
-- The rival's driving comes from a seeded random stream the server picks, so the replay drives
-- the rival the same way too.

-- String requires, as the converted game code uses, so tests can run it with plain Luau too.
local race = require("./Game/race") :: any
local data = require("./Game/data") :: any
local grip = require("./Game/grip") :: any
local distance = require("./Game/distance") :: any

local DragRace = {}

DragRace.DT = race.RACE_DT :: number
-- The countdown: 3, 2, 1, GO, 700 ms a step (Race.tsx).
DragRace.COUNT_STEP = 0.7
DragRace.GO_TICK = math.round(3 * 0.7 / race.RACE_DT)
-- A race that hasn't finished after this long is over (the car never got going).
DragRace.MAX_SECONDS = 60
DragRace.MAX_TICKS = DragRace.GO_TICK + math.round(60 / race.RACE_DT)
-- At most this many presses count (nobody needs more; it keeps a replay cheap).
DragRace.MAX_EVENTS = 300

export type Rival = { pi: number, shift: number, skill: string? }
-- What the venue and the weather do to a car's grip (Shared.Game.grip conditions).
export type Grip = { lo: number, hi: number, spin: number, dust: number }
-- What both sides agree on before the race: the cars, the strip's grip for each and the rival's
-- driving. Grip left out is a clean dry strip. build: the player's car's build (distance.ts), set
-- for races over a set distance (a half mile or a mile), where it costs some pull.
-- ghost: a solo run (time trials, the Daily Run): no rival, just a ghost that finishes in that
-- many seconds (trial.ts ghostDist), pulling away from the line and then holding its pace.
export type Spec = { myPi: number, mySkill: string?, rival: Rival, seed: number, track: number, grip: Grip?, theirGrip: Grip?, build: number?, ghost: number? }

-- Where a ghost that finishes in `time` is after t seconds (trial.ts ghostDist, GHOST_CURVE 1.6).
function DragRace.ghostDist(t: number, time: number, track: number): number
	return track * math.clamp(t / time, 0, 1) ^ 1.6
end

local function gripOf(g: Grip?): Grip
	return g or grip.CLEAR
end
-- A press: "down" (pedal down: revs before GO, a shift after), "up" (pedal up), "boost".
export type Event = { tick: number, kind: string }

-- A small seeded random stream (Park-Miller, as the web game's venues use).
local function stream(seed: number): () -> number
	local s = seed % 2147483646 + 1
	return function()
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
end

export type Race = {
	spec: Spec,
	tick: number,
	me: any,
	them: any,
	held: boolean,
	rpm: number, -- revs on the line, before GO
	aiShift: { number },
	aiReaction: number,
	events: { Event },
	-- What happened, for the screen: the last call ("PERFECT LAUNCH!", "Good", ...) and when.
	call: string?,
	callTick: number,
	launch: string?,
	perfect: number,
	shifts: number,
	top: number,
	theirBoostAt: number?,
	spin: boolean, -- the wheels are spinning (for the smoke and the "Wheelspin" note)
	done: boolean,
}

function DragRace.new(spec: Spec): Race
	local r = stream(spec.seed)
	local cleanness = spec.rival.shift
	-- The rival's shift point in each gear: a clean driver shifts inside the perfect band, a sloppy
	-- one too early (Race.tsx).
	local aiShift = {}
	local theirs = gripOf(spec.theirGrip)
	for g = 0, race.TOP_GEAR - 1 do
		local b = race.shiftBand(g, theirs.lo, theirs.hi, race.AI_BAND)
		aiShift[g + 1] = b.lo + (b.hi - b.lo) * (0.25 + 0.6 * r()) - (1 - cleanness) * (0.06 + 0.1 * r())
	end
	return {
		spec = spec,
		tick = 0,
		me = race.freshRacer(false),
		them = race.freshRacer(false),
		held = false,
		rpm = race.IDLE,
		aiShift = aiShift,
		aiReaction = race.aiReaction(cleanness, r()),
		events = {},
		call = nil,
		callTick = 0,
		launch = nil,
		perfect = 0,
		shifts = 0,
		top = 0,
		theirBoostAt = nil,
		spin = false,
		done = false,
	}
end

-- Seconds since GO (negative during the countdown).
function DragRace.time(r: Race): number
	return (r.tick - DragRace.GO_TICK) * DragRace.DT
end

local function say(r: Race, call: string)
	r.call = call
	r.callTick = r.tick
end

-- A press, applied before the next step. Returns false when it doesn't count (too many, or after
-- the finish).
function DragRace.input(r: Race, kind: string): boolean
	if r.done or #r.events >= DragRace.MAX_EVENTS then
		return false
	end
	local me = r.me
	if kind == "down" then
		if not me.launched then
			r.held = true
		elseif me.finished == nil and me.gear < race.TOP_GEAR then
			local g = gripOf(r.spec.grip)
			local band = race.shiftBand(me.gear, g.lo, g.hi)
			local s = race.shiftQuality(me.rpm, band.lo, band.hi)
			local q, label = s.q, s.label
			if data.smoothShift(r.spec.mySkill) and label == "Good" then
				q, label = 1.08, "SMOOTH!"
			end
			race.shiftRacer(me, q)
			r.shifts += 1
			if q >= 1 then
				r.perfect += 1
				say(r, if me.streak >= 2 then `Perfect shift x{me.streak}!` else label)
			else
				say(r, label)
			end
		else
			return false
		end
	elseif kind == "up" then
		r.held = false
	elseif kind == "boost" then
		if not race.fireBoost(me) then
			return false
		end
		say(r, "BOOST!")
	else
		return false
	end
	table.insert(r.events, { tick = r.tick, kind = kind })
	return true
end

-- One step of RACE_DT.
function DragRace.step(r: Race)
	if r.done then
		return
	end
	local spec = r.spec
	local me, th = r.me, r.them
	local dt = DragRace.DT
	if r.tick < DragRace.GO_TICK then
		-- Holding the pedal revs the engine; inside the launch band the needle climbs slower.
		local band = race.LAUNCH_BAND
		local inBand = r.rpm >= band.lo and r.rpm <= band.hi
		local rate = if r.held then race.REV_UP * (if inBand then race.REV_HOLD else 1) else -race.REV_DOWN
		r.rpm = math.clamp(r.rpm + rate * dt, race.IDLE, 1.02)
		me.rpm = r.rpm
		r.tick += 1
		return
	end
	if not me.launched then
		-- Off the line at GO, on whatever revs the driver is holding.
		r.launch = race.revLaunch(me, r.rpm)
		say(r, r.launch :: string)
		r.held = false
	end
	r.tick += 1
	local t = DragRace.time(r)
	local myGrip, theirGrip = gripOf(spec.grip), gripOf(spec.theirGrip)
	local mine = data.skillBoost(spec.mySkill, me, th) * data.skillDrag(spec.rival.skill, me, t) * grip.gripMul(myGrip, me.gear, me.rpm, t)
	if spec.build then
		mine *= distance.characterMul(spec.build, me.gear, me.dist)
	end
	race.stepRacer(me, spec.myPi, dt, t, mine, spec.track)
	r.top = math.max(r.top, me.speed)
	r.spin = me.launched and me.finished == nil and (grip.spinning(myGrip, me.gear, me.rpm, t) or (me.gear == 0 and me.quality < 0.84))
	if spec.ghost then
		local was = th.dist
		th.dist = DragRace.ghostDist(t, spec.ghost, spec.track)
		th.speed = (th.dist - was) / dt
		if th.finished == nil and t >= spec.ghost then
			th.finished = spec.ghost
		end
		if (me.finished ~= nil and th.finished ~= nil) or r.tick >= DragRace.MAX_TICKS then
			r.done = true
		end
		return
	end
	-- The rival: off the line after its reaction, shifting at its shift points, boost in fourth.
	if not th.launched and t >= r.aiReaction then
		race.launchRacer(th, r.aiReaction)
	end
	if th.launched and th.gear < race.TOP_GEAR and th.rpm >= r.aiShift[th.gear + 1] then
		local band = race.shiftBand(th.gear, theirGrip.lo, theirGrip.hi, race.AI_BAND)
		local q = race.shiftQuality(th.rpm, band.lo, band.hi, false)
		race.shiftRacer(th, if data.smoothShift(spec.rival.skill) and q.label == "Good" then 1.08 else q.q)
	end
	if th.gear >= race.AI_BOOST_GEAR and race.fireBoost(th) then
		r.theirBoostAt = r.tick
	end
	local theirs = data.skillBoost(spec.rival.skill, th, me) * data.skillDrag(spec.mySkill, th, t) * grip.gripMul(theirGrip, th.gear, th.rpm, t)
	race.stepRacer(th, spec.rival.pi, dt, t, theirs, spec.track)
	if (me.finished ~= nil and th.finished ~= nil) or r.tick >= DragRace.MAX_TICKS then
		r.done = true
	end
end

-- The finish times (math.huge for a car that never finished).
function DragRace.times(r: Race): (number, number)
	return r.me.finished or math.huge, r.them.finished or math.huge
end

-- Checks a list of presses from a client: in order, inside the race, known kinds, not too many.
function DragRace.valid(events: any): boolean
	if type(events) ~= "table" or #events > DragRace.MAX_EVENTS then
		return false
	end
	local last = 0
	for i, e in events do
		if type(i) ~= "number" or type(e) ~= "table" then
			return false
		end
		local tick, kind = e.tick, e.kind
		if type(tick) ~= "number" or tick ~= math.floor(tick) or tick < last or tick > DragRace.MAX_TICKS then
			return false
		end
		if kind ~= "down" and kind ~= "up" and kind ~= "boost" then
			return false
		end
		last = tick
	end
	return true
end

-- Runs a whole race from its presses (as the server does). Presses that don't count are skipped,
-- just as they were on the client.
function DragRace.replay(spec: Spec, events: { Event }): Race
	local r = DragRace.new(spec)
	local i = 1
	while not r.done do
		while events[i] and events[i].tick <= r.tick do
			DragRace.input(r, events[i].kind)
			i += 1
		end
		DragRace.step(r)
	end
	return r
end

return DragRace
