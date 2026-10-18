--!strict
-- Weekly boards of best times (the Time Trial's, as the web game's trial_board,
-- supabase/migrations/0026_time_trials.sql): lowest time first, one row per player, kept per week.
--
-- In Roblox each week is an OrderedDataStore ("<name>_<week>", value = milliseconds), with each
-- row's details (town, car, PI, the car's look) in a DataStore beside it, and each player's own
-- weeks (for last week's prizes) in another. Without DataStores (tests, the emulator, a Studio
-- place that can't reach them) the boards live in memory.
--
-- Reads are cached for a short while, so a busy menu doesn't use up the DataStore budget.

local Boards = {}
Boards.__index = Boards

export type Row = { owner: number, town: string?, t: number, pi: number?, car: string?, look: any, place: number }
export type Board = { week: string, total: number, top: { Row }, me: { t: number, place: number }? }

-- How long a read stays fresh, in seconds, and the most rows counted for a place.
local FRESH = 30
local COUNT_CAP = 5000

export type Backend = {
	-- The ordered store for a board's week, and a plain store for details and players' weeks.
	ordered: (name: string) -> any,
	plain: (name: string) -> any,
}

export type Boards = typeof(setmetatable(
	{} :: {
		name: string,
		backend: Backend?,
		clock: () -> number,
		mem: { [string]: { [number]: number } },
		info: { [string]: any },
		mine: { [number]: { [string]: number } },
		cache: { [string]: { at: number, value: any } },
	},
	Boards
))

-- name: the board's name ("Trial"); backend: DataStores, or nil to keep everything in memory;
-- clock: seconds, for the cache.
function Boards.new(name: string, backend: Backend?, clock: () -> number): Boards
	return setmetatable({ name = name, backend = backend, clock = clock, mem = {}, info = {}, mine = {}, cache = {} }, Boards)
end

local function ms(t: number): number
	return math.round(t * 1000)
end

function Boards._cached(self: Boards, key: string, get: () -> any): any
	local c = self.cache[key]
	local now = self.clock()
	if c and now - c.at < FRESH then
		return c.value
	end
	local value = get()
	self.cache[key] = { at = now, value = value }
	return value
end

function Boards._forget(self: Boards, week: string)
	for k in self.cache do
		if string.find(k, week, 1, true) then
			self.cache[k] = nil
		end
	end
end

-- A player's best this week, in seconds (nil: no time yet).
function Boards.best(self: Boards, week: string, userId: number): number?
	local b = self.backend
	if not b then
		local m = (self.mem[week] or {})[userId]
		return if m then m / 1000 else nil
	end
	local ok, v = pcall(function()
		return b.ordered(`{self.name}_{week}`):GetAsync(tostring(userId))
	end)
	return if ok and type(v) == "number" then v / 1000 else nil
end

-- Posts a time; the board keeps the player's best. row: what the board shows for them (town,
-- car name, PI, the car's look). Returns the time kept.
function Boards.submit(self: Boards, week: string, userId: number, t: number, row: any): number
	local value = ms(t)
	local kept = value
	local b = self.backend
	if not b then
		local w = self.mem[week] or {}
		self.mem[week] = w
		if w[userId] == nil or value < w[userId] then
			w[userId] = value
			self.info[`{week}:{userId}`] = row
		end
		kept = w[userId]
		local mine = self.mine[userId] or {}
		self.mine[userId] = mine
		mine[week] = kept
	else
		local improved = false
		pcall(function()
			b.ordered(`{self.name}_{week}`):UpdateAsync(tostring(userId), function(old: number?): number?
				if old ~= nil and old <= value then
					kept = old
					improved = false
					return nil
				end
				kept = value
				improved = true
				return value
			end)
		end)
		if improved then
			pcall(function()
				b.plain(`{self.name}Rows`):SetAsync(`{week}:{userId}`, row)
			end)
		end
		pcall(function()
			b.plain(`{self.name}Mine`):UpdateAsync(tostring(userId), function(old: any): any
				local mine = if type(old) == "table" then old else {}
				if mine[week] == nil or kept < mine[week] then
					mine[week] = kept
				end
				-- Only the last few weeks matter (unclaimed prizes).
				local weeks = {}
				for w in mine do
					table.insert(weeks, w)
				end
				table.sort(weeks)
				for i = 1, #weeks - 8 do
					mine[weeks[i]] = nil
				end
				return mine
			end)
		end)
	end
	self:_forget(week)
	return kept / 1000
end

-- The weeks a player set a time in, with their time in seconds.
function Boards.weeks(self: Boards, userId: number): { [string]: number }
	local out = {}
	local b = self.backend
	if not b then
		for w, v in self.mine[userId] or {} do
			out[w] = v / 1000
		end
		return out
	end
	local ok, v = pcall(function()
		return b.plain(`{self.name}Mine`):GetAsync(tostring(userId))
	end)
	if ok and type(v) == "table" then
		for w, t in v do
			if type(w) == "string" and type(t) == "number" then
				out[w] = t / 1000
			end
		end
	end
	return out
end

-- Every time on a week's board, lowest first, as { owner, value } (up to `limit`).
function Boards._sorted(self: Boards, week: string, limit: number, below: number?): { { owner: number, value: number } }
	local out = {}
	local b = self.backend
	if not b then
		for owner, v in self.mem[week] or {} do
			if below == nil or v < below then
				table.insert(out, { owner = owner, value = v })
			end
		end
		table.sort(out, function(x, y)
			return if x.value == y.value then x.owner < y.owner else x.value < y.value
		end)
		while #out > limit do
			table.remove(out)
		end
		return out
	end
	pcall(function()
		local pages = b.ordered(`{self.name}_{week}`):GetSortedAsync(true, math.min(100, limit), nil, if below then below - 1 else nil)
		while true do
			for _, e in pages:GetCurrentPage() do
				table.insert(out, { owner = tonumber(e.key) or 0, value = e.value })
				if #out >= limit then
					return
				end
			end
			if pages.IsFinished then
				return
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	return out
end

-- A time's place on a week's board (1 = fastest), and how many are on it.
function Boards.place(self: Boards, week: string, t: number): (number, number)
	local value = ms(t)
	local faster = self:_cached(`place:{week}:{value}`, function()
		return #self:_sorted(week, COUNT_CAP, value)
	end)
	local total = self:_cached(`total:{week}`, function()
		return #self:_sorted(week, COUNT_CAP)
	end)
	return faster + 1, math.max(total, faster + 1)
end

-- The week's board: the top `n` with their details, and the player's own time and place.
function Boards.board(self: Boards, week: string, userId: number, n: number?): Board
	local count = n or 10
	local top: { Row } = self:_cached(`top:{week}:{count}`, function()
		local rows = {}
		for i, e in self:_sorted(week, count) do
			local info: any = nil
			if self.backend then
				local backend = self.backend :: Backend
				pcall(function()
					info = backend.plain(`{self.name}Rows`):GetAsync(`{week}:{e.owner}`)
				end)
			else
				info = self.info[`{week}:{e.owner}`]
			end
			info = if type(info) == "table" then info else {}
			rows[i] = { owner = e.owner, town = info.town, t = e.value / 1000, pi = info.pi, car = info.car, look = info.look, place = i }
		end
		return rows
	end)
	local mine = self:best(week, userId)
	local me = nil
	local total = 0
	if mine then
		local place, all = self:place(week, mine)
		me = { t = mine, place = place }
		total = all
	else
		total = self:_cached(`total:{week}`, function()
			return #self:_sorted(week, COUNT_CAP)
		end)
	end
	return { week = week, total = total, top = top, me = me }
end

return Boards
