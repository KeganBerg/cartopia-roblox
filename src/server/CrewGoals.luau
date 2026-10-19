--!strict
-- A crew's weekly goal and its chests, as the web game's supabase/migrations/0027_crew_weekly_goal.sql
-- and ui/CrewGoal.tsx:
--   * Every crew shares one target a week (Monday 00:00 UTC to Monday): 120 points per member,
--     counted as at least 3 members. Members add points by playing: 1 per business collected
--     (stats.jobs) and 3 per race (stats.races).
--   * A member's points count up to 360 towards the crew, so the crew has to pull together.
--   * Points come out of a bank per player that refills 1 point every 4 seconds (up to 240).
--   * When the crew reaches the target, every member who added at least 30 points that week opens a
--     crew chest (data.CREW_CHEST, paid by store.openCrewChest). A chest stays openable through the
--     following week. One crew chest per player per week, whichever crew they were in.
--
-- In Roblox it's one DataStore, "CrewGoals_v1", changed with UpdateAsync: "w:<crewId>:<week>" a
-- crew's week ({ target, reached, pts = { [userId] = { p, j, r } } }) and "k:<userId>" a player's
-- own record ({ bank, at, chests, opened = { [week] = crewId }, helped = { [week] = { [crewId] =
-- points } } }). Without DataStores (tests, the emulator) everything lives in memory.

local CrewGoals = {}
CrewGoals.__index = CrewGoals

CrewGoals.RULES = { job = 1, race = 3, perMember = 120, minMembers = 3, memberCap = 360, minPoints = 30, bankMax = 240, bankSeconds = 4 }
local RULES = CrewGoals.RULES
local STORE = "CrewGoals_v1"
local DAY = 86400

export type Mods = {
	plain: ((name: string) -> any)?,
	clock: () -> number,
}

export type CrewGoals = typeof(setmetatable(
	{} :: {
		mods: Mods,
		mem: { [string]: any },
	},
	CrewGoals
))

function CrewGoals.new(mods: Mods): CrewGoals
	return setmetatable({ mods = mods, mem = {} }, CrewGoals)
end

-- The Monday (UTC) a week starts on, as days since 1970 (a Thursday).
local function weekDay(t: number): number
	local d = math.floor(t / DAY)
	return d - (d + 3) % 7
end

local function weekName(day: number): string
	return os.date("!%Y-%m-%d", day * DAY) :: string
end

-- This week's name ("2026-10-19") and last week's.
function CrewGoals.weeks(t: number): (string, string)
	local d = weekDay(t)
	return weekName(d), weekName(d - 7)
end

-- Seconds until the next week starts.
function CrewGoals.left(t: number): number
	return (weekDay(t) + 7) * DAY - t
end

-- The target for a crew of this many members.
function CrewGoals.target(members: number): number
	return RULES.perMember * math.max(members, RULES.minMembers)
end

function CrewGoals._get(self: CrewGoals, key: string): any
	local plain = self.mods.plain
	if not plain then
		local v = self.mem[key]
		return if type(v) == "table" then table.clone(v) else v
	end
	local ok, v = pcall(function()
		return plain(STORE):GetAsync(key)
	end)
	return if ok then v else nil
end

-- Changes a stored value in one step: fn gets the old value (a table) and returns the new one, or
-- nil to leave it. True when the store took it.
function CrewGoals._update(self: CrewGoals, key: string, fn: (any) -> any): boolean
	local plain = self.mods.plain
	if not plain then
		local old = self.mem[key]
		local v = fn(if type(old) == "table" then table.clone(old) else {})
		if v ~= nil then
			self.mem[key] = v
		end
		return true
	end
	return (pcall(function()
		plain(STORE):UpdateAsync(key, function(old: any): any
			return fn(if type(old) == "table" then old else {})
		end)
	end))
end

-- Points a crew has in a week, each member's share capped.
local function total(w: any): number
	local n = 0
	for _, p in w.pts or {} do
		n += math.min(p.p or 0, RULES.memberCap)
	end
	return n
end

-- New jobs and races a player made, credited to their crew. members: how many the crew has now.
-- Returns the points that went in and whether this made the crew reach its goal.
function CrewGoals.add(self: CrewGoals, userId: number, crewId: string, members: number, jobs: number, races: number): (number, boolean)
	local function whole(v: any): number
		local n = tonumber(v) or 0
		return if n ~= n then 0 else math.clamp(math.floor(n), 0, 100000)
	end
	jobs, races = whole(jobs), whole(races)
	local raw = jobs * RULES.job + races * RULES.race
	if raw <= 0 then
		return 0, false
	end
	local now = self.mods.clock()
	local week = CrewGoals.weeks(now)
	-- Spend from the bank, which refills with time.
	local got = 0
	if not self:_update(`k:{userId}`, function(k: any): any
		local bank = if k.bank == nil then RULES.bankMax else math.min(k.bank + math.max(0, now - (k.at or now)) / RULES.bankSeconds, RULES.bankMax)
		got = math.min(raw, math.floor(bank))
		k.bank, k.at = bank - got, now
		if got > 0 then
			-- Which crews they helped (this week and last only), for last week's chest.
			local helped = {}
			local last = select(2, CrewGoals.weeks(now))
			for wk, v in k.helped or {} do
				if wk == week or wk == last then
					helped[wk] = v
				end
			end
			helped[week] = helped[week] or {}
			helped[week][crewId] = (helped[week][crewId] or 0) + got
			k.helped = helped
		end
		return k
	end) then
		return 0, false
	end
	if got <= 0 then
		return 0, false
	end
	-- Jobs and races are scaled down together when the bank runs short.
	local reachedNow = false
	self:_update(`w:{crewId}:{week}`, function(w: any): any
		reachedNow = false
		local key = tostring(userId)
		w.pts = w.pts or {}
		local p = w.pts[key] or { p = 0, j = 0, r = 0 }
		p.p += got
		p.j += jobs * got // raw
		p.r += races * got // raw
		w.pts[key] = p
		if not w.reached then
			local target = CrewGoals.target(members)
			if total(w) >= target then
				w.reached, w.target = true, target
				reachedNow = true
			end
		end
		return w
	end)
	return got, reachedNow
end

-- One week of a crew's goal, as the Crew tab shows it.
function CrewGoals.view(self: CrewGoals, crewId: string, week: string, userId: number, members: number, k: any?): any
	local w = self:_get(`w:{crewId}:{week}`) or {}
	k = k or self:_get(`k:{userId}`) or {}
	local list = {}
	for id, p in w.pts or {} do
		table.insert(list, { id = tonumber(id), points = math.min(p.p or 0, RULES.memberCap), jobs = p.j or 0, races = p.r or 0 })
	end
	table.sort(list, function(a, b)
		return a.points > b.points
	end)
	local mine = (w.pts or {})[tostring(userId)]
	return {
		week = week,
		target = w.target or CrewGoals.target(members),
		points = total(w),
		reached = w.reached == true,
		mine = if mine then mine.p or 0 else 0,
		opened = (k :: any).opened ~= nil and (k :: any).opened[week] ~= nil,
		members = list,
	}
end

-- The player's crew goal: this week (when they're in a crew), last week's when its chest still
-- waits, the chests they've opened in all, and the seconds until the week ends.
function CrewGoals.goal(self: CrewGoals, userId: number, crewId: string?, members: number): any
	local now = self.mods.clock()
	local week, last = CrewGoals.weeks(now)
	local k = self:_get(`k:{userId}`) or {}
	local lastView = nil
	if not (k.opened and k.opened[last]) then
		for id, pts in (k.helped or {})[last] or {} do
			if pts >= RULES.minPoints then
				local v = self:view(id, last, userId, members, k)
				if v.reached and v.mine >= RULES.minPoints then
					lastView = v
					break
				end
			end
		end
	end
	return {
		rules = RULES,
		left = CrewGoals.left(now),
		chests = k.chests or 0,
		current = if crewId then self:view(crewId, week, userId, members, k) else nil,
		last = lastView,
	}
end

-- Opens this week's or last week's crew chest. Returns the chests the player has opened in all
-- (the server pays up to that), or nil and why not.
function CrewGoals.open(self: CrewGoals, userId: number, week: any): (number?, string?)
	local now = self.mods.clock()
	local this, last = CrewGoals.weeks(now)
	if week ~= this and week ~= last then
		return nil, "chest expired"
	end
	local k = self:_get(`k:{userId}`) or {}
	if k.opened and k.opened[week] then
		return nil, "chest opened"
	end
	-- The crew they helped most that week that reached its goal.
	local best, bestPts, short = nil, 0, false
	for id, pts in (k.helped or {})[week] or {} do
		local w = self:_get(`w:{id}:{week}`) or {}
		local mine = (w.pts or {})[tostring(userId)]
		local p = if mine then mine.p or 0 else 0
		if w.reached then
			if p >= RULES.minPoints and p > bestPts then
				best, bestPts = id, p
			elseif p < RULES.minPoints then
				short = true
			end
		end
	end
	if not best then
		return nil, if short then "chest points" else "chest locked"
	end
	local chests: number? = nil
	local ok = self:_update(`k:{userId}`, function(r: any): any
		chests = nil
		r.opened = r.opened or {}
		if r.opened[week] then
			return nil
		end
		-- Only this week's and last week's are kept.
		local opened = {}
		for wk, id in r.opened do
			if wk == this or wk == last then
				opened[wk] = id
			end
		end
		opened[week] = best
		r.opened = opened
		r.chests = (r.chests or 0) + 1
		chests = r.chests
		return r
	end)
	if not ok then
		return nil, "try again"
	end
	if chests == nil then
		return nil, "chest opened"
	end
	return chests, nil
end

-- The chests a player has opened in all (what their town should have been paid for).
function CrewGoals.chests(self: CrewGoals, userId: number): number
	local k = self:_get(`k:{userId}`) or {}
	return k.chests or 0
end

return CrewGoals
