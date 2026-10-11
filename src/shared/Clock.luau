--!strict
-- The town clock, ported from src/game/clock.ts. One in-game day lasts 20 real minutes, tied to the
-- real clock so every player sees the same time of day.

local Util = require("./Util")

local Clock = {}

Clock.DAY_MS = 20 * 60 * 1000

-- 0 = noon, 0.5 = midnight.
function Clock.dayPhase(now: number?): number
	return ((now or Util.nowMs()) % Clock.DAY_MS) / Clock.DAY_MS
end

-- How dark it is, 0 (day) to 1 (night), with gentle dusk and dawn ramps.
function Clock.nightAmount(phase: number): number
	local d = math.abs(phase - 0.5) -- 0 at midnight, 0.5 at noon
	if d < 0.14 then
		return 1
	end
	if d > 0.26 then
		return 0
	end
	return 1 - (d - 0.14) / 0.12
end

-- How much of a sunset tint to add: peaks halfway through dusk and dawn.
function Clock.duskAmount(phase: number): number
	local n = Clock.nightAmount(phase)
	return math.max(0, 1 - math.abs(n - 0.35) / 0.35)
end

-- Night spots open halfway through dusk and close halfway through dawn
-- (phase 0.3 to 0.7, 8 real minutes of every 20).
Clock.OPEN_FROM = 0.3
Clock.OPEN_TO = 0.7

function Clock.isNight(now: number?): boolean
	local p = Clock.dayPhase(now)
	return p >= Clock.OPEN_FROM and p < Clock.OPEN_TO
end

-- Milliseconds until the next opening (0 while open).
function Clock.msUntilNight(now: number?): number
	local p = Clock.dayPhase(now)
	if p >= Clock.OPEN_FROM and p < Clock.OPEN_TO then
		return 0
	end
	return ((if p < Clock.OPEN_FROM then Clock.OPEN_FROM else 1 + Clock.OPEN_FROM) - p) * Clock.DAY_MS
end

return Clock
