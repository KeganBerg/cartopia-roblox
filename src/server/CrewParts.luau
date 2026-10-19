--!strict
-- Crew part requests, as the web game's supabase/migrations/0070_postcards_crew_parts.sql and
-- lib/crewParts.ts: once a UTC day a crew member can ask their crew for 10 parts. Crewmates give
-- one of their own parts at a time, at most 5 to any one request and 20 a day. The asker collects
-- what has been given (on opening the Crew tab, or with Collect), for up to a week.
--
-- In Roblox it's one DataStore, "CrewParts_v1", changed with UpdateAsync: "a:<crewId>:<day>" a
-- crew's requests that day ({ [askerId] = { name, want, given, by = { [giverId] = n }, at } }),
-- "g:<userId>:<day>" how many parts a player has given that day, and "u:<userId>" a player's own
-- asks ({ asks = { [day] = crewId }, claimed = { [day] = n } }, the last 7 days). Without
-- DataStores (tests, the emulator) everything lives in memory.

local CrewParts = {}
CrewParts.__index = CrewParts

CrewParts.ASK = 10 -- parts asked for (web CREW_ASK)
CrewParts.GIVE_MAX = 5 -- to any one request (web CREW_GIVE_MAX)
CrewParts.DAY_MAX = 20 -- given a day
CrewParts.KEEP = 7 -- days a request can still be collected
local STORE = "CrewParts_v1"
local DAY = 86400

export type Mods = {
	plain: ((name: string) -> any)?,
	clock: () -> number,
}

export type CrewParts = typeof(setmetatable(
	{} :: {
		mods: Mods,
		mem: { [string]: any },
	},
	CrewParts
))

function CrewParts.new(mods: Mods): CrewParts
	return setmetatable({ mods = mods, mem = {} }, CrewParts)
end

local function dayName(t: number): string
	return os.date("!%Y-%m-%d", t) :: string
end

function CrewParts._get(self: CrewParts, key: string): any
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
function CrewParts._update(self: CrewParts, key: string, fn: (any) -> any): boolean
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

-- Asks the crew for parts today. "asked", or "already" when they asked today, or "try again".
function CrewParts.ask(self: CrewParts, userId: number, crewId: string, name: string): string
	local now = self.mods.clock()
	local day = dayName(now)
	local result = "try again"
	local ok = self:_update(`a:{crewId}:{day}`, function(reqs: any): any
		local key = tostring(userId)
		if reqs[key] then
			result = "already"
			return nil
		end
		result = "asked"
		reqs[key] = { name = name, want = CrewParts.ASK, given = 0, by = {}, at = now }
		return reqs
	end)
	if not ok or result ~= "asked" then
		return if ok then result else "try again"
	end
	-- (One ask a day, whichever crew: a second crew's ask the same day is refused here.)
	local first = true
	self:_update(`u:{userId}`, function(u: any): any
		u.asks = u.asks or {}
		if u.asks[day] and u.asks[day] ~= crewId then
			first = false
			return nil
		end
		local asks, claimed = {}, {}
		local oldest = dayName(now - CrewParts.KEEP * DAY)
		for d, id in u.asks do
			if d > oldest then
				asks[d] = id
			end
		end
		for d, n in u.claimed or {} do
			if d > oldest then
				claimed[d] = n
			end
		end
		asks[day] = crewId
		u.asks, u.claimed = asks, claimed
		return u
	end)
	if not first then
		self:_update(`a:{crewId}:{day}`, function(reqs: any): any
			reqs[tostring(userId)] = nil
			return reqs
		end)
		return "already"
	end
	return "asked"
end

-- Today's requests in a crew, newest first: { id (the asker), name, want, given, mine }.
function CrewParts.list(self: CrewParts, crewId: string, userId: number): { any }
	local reqs = self:_get(`a:{crewId}:{dayName(self.mods.clock())}`) or {}
	local list = {}
	for id, r in reqs do
		table.insert(list, { id = tonumber(id), name = r.name, want = r.want, given = r.given, mine = (r.by or {})[tostring(userId)] or 0, at = r.at })
	end
	table.sort(list, function(a, b)
		return (a.at or 0) > (b.at or 0)
	end)
	return list
end

-- Gives one part to a crewmate's request today. "given", "full", "limit", "own" or "no". The
-- caller takes the part from the giver's town when it's "given".
function CrewParts.give(self: CrewParts, userId: number, crewId: string, asker: number): string
	if asker == userId then
		return "own"
	end
	local day = dayName(self.mods.clock())
	local gKey = `g:{userId}:{day}`
	local today = self:_get(gKey)
	if type(today) == "number" and today >= CrewParts.DAY_MAX then
		return "limit"
	end
	local result = "no"
	local ok = self:_update(`a:{crewId}:{day}`, function(reqs: any): any
		local r = reqs[tostring(asker)]
		if not r then
			result = "no"
			return nil
		end
		r.by = r.by or {}
		local mine = r.by[tostring(userId)] or 0
		if r.given >= r.want then
			result = "full"
			return nil
		end
		if mine >= CrewParts.GIVE_MAX then
			result = "limit"
			return nil
		end
		result = "given"
		r.given += 1
		r.by[tostring(userId)] = mine + 1
		return reqs
	end)
	if not ok then
		return "no"
	end
	if result == "given" then
		local plain = self.mods.plain
		if plain then
			pcall(function()
				plain(STORE):UpdateAsync(gKey, function(old: any): any
					return (if type(old) == "number" then old else 0) + 1
				end)
			end)
		else
			self.mem[gKey] = (self.mem[gKey] or 0) + 1
		end
	end
	return result
end

-- Takes what crewmates have given to the player's asks this week: the parts to add (0 when none).
function CrewParts.claim(self: CrewParts, userId: number): number
	local u = self:_get(`u:{userId}`) or {}
	-- What each ask has had so far.
	local given: { [string]: number } = {}
	for day, crewId in u.asks or {} do
		local reqs = self:_get(`a:{crewId}:{day}`) or {}
		local r = reqs[tostring(userId)]
		if r and r.given > ((u.claimed or {})[day] or 0) then
			given[day] = r.given
		end
	end
	if next(given) == nil then
		return 0
	end
	local got = 0
	local ok = self:_update(`u:{userId}`, function(rec: any): any
		got = 0
		rec.claimed = rec.claimed or {}
		for day, n in given do
			local before = rec.claimed[day] or 0
			if n > before then
				got += n - before
				rec.claimed[day] = n
			end
		end
		return if got > 0 then rec else nil
	end)
	return if ok then got else 0
end

return CrewParts
