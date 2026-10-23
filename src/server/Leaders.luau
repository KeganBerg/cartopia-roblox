--!strict
-- The player leaderboards (the web game's player_leaderboard view, lib/clans.ts fetchBoard):
-- Power (the PI of a player's 5 best cars), Wins, Trophies and Level, all time or gained this
-- week (since Monday, UTC).
--
-- In Roblox each board is an OrderedDataStore: "Leaders_<metric>" (all time) and
-- "Leaders_<metric>_<week>" (this week's gains). A player's numbers at the start of the week sit in
-- "LeadersBase_<week>", and the details a row shows (town, name, level, the four numbers) in
-- "LeadersInfo". Without DataStores (tests, the emulator) everything lives in memory.
--
-- Rows are written when a town is saved, at most once a minute a player and only when a number
-- changed; reads are cached for a minute, so a busy menu doesn't use up the DataStore budget.

local Leaders = {}
Leaders.__index = Leaders

Leaders.METRICS = { "power", "race_wins", "trophies", "level" }
local FRESH = 60
local WRITE_GAP = 60
local TOP = 50

export type Stats = { power: number, race_wins: number, trophies: number, level: number }
export type Info = { name: string, town: string, level: number, stats: Stats, crew: any? }
export type Row = { id: number, name: string, town: string, level: number, value: number, place: number, crew: any? }
export type Backend = {
	ordered: (name: string) -> any,
	plain: (name: string) -> any,
}

export type Leaders = typeof(setmetatable(
	{} :: {
		backend: Backend?,
		clock: () -> number,
		week: () -> string,
		mem: { [string]: { [number]: number } },
		memPlain: { [string]: { [number]: any } },
		cache: { [string]: { at: number, value: any } },
		last: { [number]: { at: number, key: string, crew: string? } },
		bases: { [string]: Stats },
	},
	Leaders
))

-- backend: DataStores, or nil for memory; clock: seconds; week: this week's key ("2026-W42").
function Leaders.new(backend: Backend?, clock: () -> number, week: () -> string): Leaders
	return setmetatable({ backend = backend, clock = clock, week = week, mem = {}, memPlain = {}, cache = {}, last = {}, bases = {} }, Leaders)
end

-- A save's numbers for the boards. power: data.garagePower(cars).
function Leaders.stats(save: any, power: number): Stats
	return {
		power = math.floor(power or 0),
		race_wins = math.floor(tonumber(save.racesWon) or 0),
		trophies = math.floor(tonumber(save.trophies) or 0),
		level = math.floor(tonumber(save.level) or 1),
	}
end

function Leaders._board(metric: string, week: string?): string
	return if week then `Leaders_{metric}_{week}` else `Leaders_{metric}`
end

function Leaders._set(self: Leaders, board: string, userId: number, value: number)
	local b = self.backend
	if not b then
		self.mem[board] = self.mem[board] or {}
		self.mem[board][userId] = value
		return
	end
	pcall(function()
		b.ordered(board):SetAsync(tostring(userId), value)
	end)
end

function Leaders._getPlain(self: Leaders, store: string, userId: number): any
	local b = self.backend
	if not b then
		return (self.memPlain[store] or {})[userId]
	end
	local ok, v = pcall(function()
		return b.plain(store):GetAsync(tostring(userId))
	end)
	return if ok then v else nil
end

function Leaders._setPlain(self: Leaders, store: string, userId: number, value: any)
	local b = self.backend
	if not b then
		self.memPlain[store] = self.memPlain[store] or {}
		self.memPlain[store][userId] = value
		return
	end
	pcall(function()
		b.plain(store):SetAsync(tostring(userId), value)
	end)
end

-- The player's numbers when this week began (taken the first time they're seen this week).
function Leaders._base(self: Leaders, week: string, userId: number, now: Stats): Stats
	local key = `{week}:{userId}`
	if self.bases[key] then
		return self.bases[key]
	end
	local store = `LeadersBase_{week}`
	local base = self:_getPlain(store, userId)
	if type(base) ~= "table" then
		base = now
		self:_setPlain(store, userId, base)
	end
	self.bases[key] = base
	return base
end

-- Puts a player's numbers on the boards (on save). force skips the once-a-minute limit; crew: the
-- crew's badge ({ tag, emblem, color }) shown on their rows.
function Leaders.record(self: Leaders, userId: number, name: string, town: string, stats: Stats, force: boolean?, crew: any?)
	if userId <= 0 then
		return
	end
	local badge = if type(crew) == "table" then { tag = crew.tag, emblem = crew.emblem, color = crew.color } else nil
	local key = `{stats.power}:{stats.race_wins}:{stats.trophies}:{stats.level}:{town}:{name}:{badge and badge.tag or ""}:{badge and badge.emblem or ""}:{badge and badge.color or ""}`
	local now = self.clock()
	local last = self.last[userId]
	if last and last.key == key then
		return
	end
	-- (A new crew badge goes up at once.)
	local look = `{badge and badge.tag or ""}:{badge and badge.emblem or ""}:{badge and badge.color or ""}`
	if last and not force and now - last.at < WRITE_GAP and last.crew == look then
		return
	end
	self.last[userId] = { at = now, key = key, crew = look }
	local week = self.week()
	local base = self:_base(week, userId, stats)
	for _, m in Leaders.METRICS do
		local v = (stats :: any)[m]
		self:_set(Leaders._board(m), userId, v)
		self:_set(Leaders._board(m, week), userId, math.max(0, v - ((base :: any)[m] or v)))
	end
	self:_setPlain("LeadersInfo", userId, { name = name, town = town, level = stats.level, stats = stats, crew = badge })
end

-- The top rows of a board: { id, value } best first.
function Leaders._sorted(self: Leaders, board: string, n: number): { { id: number, value: number } }
	local b = self.backend
	local out: { { id: number, value: number } } = {}
	if not b then
		for id, v in self.mem[board] or {} do
			table.insert(out, { id = id, value = v })
		end
		table.sort(out, function(a, c)
			if a.value ~= c.value then
				return a.value > c.value
			end
			return a.id < c.id
		end)
		while #out > n do
			table.remove(out)
		end
		return out
	end
	local ok, page = pcall(function()
		return b.ordered(board):GetSortedAsync(false, n):GetCurrentPage()
	end)
	if ok and page then
		for _, e in page do
			local id = tonumber(e.key)
			if id and type(e.value) == "number" then
				table.insert(out, { id = id, value = e.value })
			end
		end
	end
	return out
end

-- A board: metric ("power", "race_wins", "trophies" or "level"), period ("all" or "week").
-- Rows best first with their details; this week's board leaves out players who gained nothing.
-- me and stats: the asking player and their numbers now; their own value comes back too when
-- they aren't in the top rows (further down, or not written yet).
function Leaders.board(self: Leaders, metric: string, period: string, me: number?, stats: Stats?): ({ Row }, number?)
	assert(table.find(Leaders.METRICS, metric), `no board {metric}`)
	local week = if period == "week" then self.week() else nil
	local board = Leaders._board(metric, week)
	local now = self.clock()
	local c = self.cache[board]
	local rows: { Row }
	if c and now - c.at < FRESH then
		rows = c.value
	else
		rows = {}
		for _, e in self:_sorted(board, TOP) do
			if week and e.value <= 0 then
				continue
			end
			local info = self:_getPlain("LeadersInfo", e.id)
			if type(info) ~= "table" then
				info = {}
			end
			table.insert(rows, {
				id = e.id,
				name = if type(info.name) == "string" then info.name else "Driver",
				town = if type(info.town) == "string" then info.town else "A town",
				level = tonumber(info.level) or 1,
				value = e.value,
				place = #rows + 1,
				crew = if type(info.crew) == "table" and type(info.crew.tag) == "string" then info.crew else nil,
			})
		end
		self.cache[board] = { at = now, value = rows }
	end
	local mine: number? = nil
	if me and stats then
		local found = false
		for _, r in rows do
			if r.id == me then
				found = true
			end
		end
		if not found then
			local v = (stats :: any)[metric]
			if week then
				v = math.max(0, v - ((self:_base(week, me, stats) :: any)[metric] or v))
			end
			mine = v
		end
	end
	return rows, mine
end

-- The crews board (the web's Crews scope, its clan_leaderboard view): crews ranked by their members'
-- numbers added up, all time or gained this week, best first, the top 50. list: Crews:browse()'s
-- lines; week: this week's key (a line summed in another week counts nothing this week).
local CREW_FIELD = { power = "power", race_wins = "wins", trophies = "trophies", level = "levels" }
function Leaders.crews(list: { any }, metric: string, period: string, week: string): { any }
	local field = CREW_FIELD[metric]
	assert(field, `no board {metric}`)
	local out = {}
	for _, c in list do
		local value = if period == "week"
			then (if c.wk == week and type(c.week) == "table" then tonumber(c.week[field]) or 0 else 0)
			else tonumber(c[field]) or 0
		table.insert(out, { id = c.id, name = c.name, tag = c.tag, emblem = c.emblem, color = c.color, members = c.members or 0, cap = c.cap, value = value })
	end
	table.sort(out, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.name < b.name
	end)
	while #out > TOP do
		table.remove(out)
	end
	for i, c in out do
		c.place = i
	end
	return out
end

-- Forgets the cached boards (after a write the asker should see at once, in tests).
function Leaders.refresh(self: Leaders)
	self.cache = {}
end

return Leaders
