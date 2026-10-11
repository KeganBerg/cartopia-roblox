--!strict
-- Small helpers that make Luau behave like the JavaScript the web game was written in, so ported
-- formulas give the exact same numbers on both.

local Util = {}

-- JavaScript's Math.round: halves round up (toward +infinity). Luau's math.round rounds halves away
-- from zero, which differs for negatives, so ported code always uses this.
function Util.round(x: number): number
	return math.floor(x + 0.5)
end

function Util.clamp(x: number, lo: number, hi: number): number
	return math.min(hi, math.max(lo, x))
end

-- Milliseconds since the Unix epoch, the unit every time in the web game uses. os.time() only has
-- whole seconds, so the Roblox entry scripts swap in DateTime with Util.setClock.
local clock = function(): number
	return os.time() * 1000
end
function Util.setClock(fn: () -> number)
	clock = fn
end
function Util.nowMs(): number
	return clock()
end

function Util.find<T>(list: { T }, pred: (T) -> boolean): T?
	for _, v in list do
		if pred(v) then
			return v
		end
	end
	return nil
end

function Util.filter<T>(list: { T }, pred: (T) -> boolean): { T }
	local out = {}
	for _, v in list do
		if pred(v) then
			table.insert(out, v)
		end
	end
	return out
end

function Util.includes<T>(list: { T }?, value: T): boolean
	if not list then
		return false
	end
	return table.find(list, value) ~= nil
end

-- ---- UTC calendar (no os.date, so it runs the same in Studio, on servers and in the CLI) ----
local DAY_MS = 86400000
Util.DAY_MS = DAY_MS

-- Days since 1970-01-01 for a UTC civil date (Howard Hinnant's days_from_civil). month is 1-12.
function Util.daysFromCivil(y: number, m: number, d: number): number
	y = if m <= 2 then y - 1 else y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = math.floor((153 * mp + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

-- The UTC year, month (1-12) and day for a day number.
function Util.civilFromDays(z: number): (number, number, number)
	z += 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = if mp < 10 then mp + 3 else mp - 9
	local y = yoe + era * 400 + (if m <= 2 then 1 else 0)
	return y, m, d
end

-- JavaScript's Date.UTC(year, monthIndex, day, hours): monthIndex is 0-11, and days past the end
-- of a month roll over the way Date.UTC does.
function Util.utc(year: number, monthIndex: number, day: number?, hours: number?): number
	local y = year + math.floor(monthIndex / 12)
	local m = monthIndex % 12 + 1
	return (Util.daysFromCivil(y, m, 1) + (day or 1) - 1) * DAY_MS + (hours or 0) * 3600000
end

-- Day of the week, 0 = Sunday, like getUTCDay().
function Util.utcDay(t: number): number
	return (math.floor(t / DAY_MS) + 4) % 7
end

return Util
