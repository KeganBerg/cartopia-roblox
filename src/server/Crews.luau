--!strict
-- Crews, as the web game's crews (lib/clans.ts, supabase/migrations/0004_clans_leaderboards.sql,
-- 0015_security_hardening.sql and 0103_crew_ranks.sql):
--   * Starting one needs a Crew House and $2,000 (data.CLAN_COST, charged by the caller): a name
--     (3-24 letters, nobody else's), a tag (2-4 letters or digits, nobody else's), an emblem and a
--     colour from the game's lists, a motto (140 letters at most), the level needed and who may join.
--   * Up to 20 drivers (data.CLAN_CAP). Open: anyone at the level joins. Request: a Leader or
--     Co-Leader says yes (5 requests out a player, 30 waiting a crew). Closed: nobody new.
--   * Leader 👑 does everything; a Co-Leader 🎖️ changes the settings, answers requests and
--     removes Members; Members 🛡️ race. Making someone Leader hands the lead over (the old Leader
--     becomes a Co-Leader). When the Leader leaves, the longest-serving Co-Leader takes over, else
--     the longest-serving Member; the last one out closes the crew.
--   * A crew's power, wins, trophies and levels are its members' added up (each member's power is
--     their five best cars' PI, data.garagePower).
--
-- In Roblox it's all one DataStore, "Crews_v1", changed with UpdateAsync: "c:<id>" each crew,
-- "p:<userId>" the crew a player is in, "r:<userId>" the crews they've asked to join, "n:<name>"
-- and "t:<TAG>" the names taken, and "list" every crew's line in the browser. A player's crew is
-- claimed first ("p:"), so two servers can't put them in two crews. Without DataStores (tests,
-- the emulator) everything lives in memory.

local Crews = {}
Crews.__index = Crews

Crews.CAP = 20
Crews.MAX_ASKS = 5 -- requests a player can have out
Crews.MAX_WAITING = 30 -- requests waiting at a crew
Crews.MOTTO = 140
Crews.MODES = { open = true, request = true, closed = true }
Crews.RANKS = { leader = 0, co_leader = 1, member = 2 }
local STORE = "Crews_v1"

export type Member = { role: string, at: number, name: string, town: string?, level: number, power: number, wins: number, trophies: number, wk: string?, base: any? }
export type Crew = {
	id: string,
	name: string,
	tag: string,
	emblem: string,
	color: string,
	motto: string,
	minLevel: number,
	joinMode: string,
	cap: number,
	at: number,
	members: { [string]: Member },
	requests: { [string]: { at: number, name: string, level: number, power: number } },
}

-- What a player brings: their name, town and numbers.
export type Who = { name: string, town: string?, level: number, power: number, wins: number, trophies: number }

export type Mods = {
	-- The DataStore by name (nil: in memory).
	plain: ((name: string) -> any)?,
	clock: () -> number,
	-- A new crew's id.
	newId: () -> string,
	-- The emblems and colours a crew can pick (data.CLAN_EMBLEMS, data.CLAN_COLORS).
	emblems: { string },
	colors: { string },
	-- This week's key ("2026-W42", data.weekKey), for the crews board's weekly gains (nil: none).
	week: (() -> string)?,
}

export type Crews = typeof(setmetatable(
	{} :: {
		mods: Mods,
		mem: { [string]: any },
	},
	Crews
))

function Crews.new(mods: Mods): Crews
	return setmetatable({ mods = mods, mem = {} }, Crews)
end

function Crews._get(self: Crews, key: string): any
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

-- Changes a stored value in one step. fn gets the old value and returns the new one, nil to leave
-- it, or false to remove it. True when the store took it.
function Crews._update(self: Crews, key: string, fn: (any) -> any): boolean
	local plain = self.mods.plain
	if not plain then
		local old = self.mem[key]
		local v = fn(if type(old) == "table" then table.clone(old) else old)
		if v == false then
			self.mem[key] = nil
		elseif v ~= nil then
			self.mem[key] = v
		end
		return true
	end
	return (pcall(function()
		local store = plain(STORE)
		local removing = false
		store:UpdateAsync(key, function(old: any): any
			local v = fn(old)
			removing = v == false
			if removing then
				return nil
			end
			return v
		end)
		if removing then
			store:RemoveAsync(key)
		end
	end))
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- The crew's line in the browser: its look, members and totals.
-- week: this week's key; members' gains since they were first seen in it are added up as the
-- week's (the web's clan_leaderboard week_* columns).
function Crews.summary(c: Crew, week: string?): any
	local power, wins, trophies, levels = 0, 0, 0, 0
	local wPower, wWins, wTrophies, wLevels = 0, 0, 0, 0
	for _, m in c.members do
		power += m.power or 0
		wins += m.wins or 0
		trophies += m.trophies or 0
		levels += m.level or 0
		local base = m.base
		if week and m.wk == week and type(base) == "table" then
			wPower += math.max(0, (m.power or 0) - (base.power or 0))
			wWins += math.max(0, (m.wins or 0) - (base.wins or 0))
			wTrophies += math.max(0, (m.trophies or 0) - (base.trophies or 0))
			wLevels += math.max(0, (m.level or 0) - (base.level or 0))
		end
	end
	return {
		id = c.id,
		name = c.name,
		tag = c.tag,
		emblem = c.emblem,
		color = c.color,
		motto = c.motto,
		minLevel = c.minLevel,
		joinMode = c.joinMode,
		cap = c.cap,
		members = count(c.members),
		power = power,
		wins = wins,
		trophies = trophies,
		levels = levels,
		wk = week,
		week = { power = wPower, wins = wWins, trophies = wTrophies, levels = wLevels },
		-- When a member last played (crew battles only match crews still playing).
		seen = (c :: any).seen or c.at,
	}
end

-- Keeps the browser's line for a crew up to date (nil: gone).
function Crews._list(self: Crews, id: string, c: Crew?)
	self:_update("list", function(old: any): any
		local list = if type(old) == "table" then old else {}
		list[id] = if c then Crews.summary(c, self.mods.week and self.mods.week()) else nil
		return list
	end)
end

-- Every crew, strongest first. q: only those whose name or tag has it.
function Crews.browse(self: Crews, q: string?): { any }
	local list = self:_get("list")
	local out = {}
	local find = if q and q ~= "" then q:lower() else nil
	for _, row in (if type(list) == "table" then list else {}) :: { [string]: any } do
		if not find or row.name:lower():find(find, 1, true) or row.tag:lower():find(find, 1, true) then
			table.insert(out, row)
		end
	end
	table.sort(out, function(a, b)
		if a.power ~= b.power then
			return a.power > b.power
		end
		return a.name < b.name
	end)
	return out
end

-- The crew a player is in, or nil.
function Crews.mineId(self: Crews, userId: number): string?
	local id = self:_get(`p:{userId}`)
	return if type(id) == "string" then id else nil
end

function Crews.crew(self: Crews, id: string): Crew?
	local c = self:_get(`c:{id}`)
	return if type(c) == "table" then c else nil
end

-- A player's crew and rank, as they see it: { crew, role, requests? } or nil.
function Crews.mine(self: Crews, userId: number): any?
	local id = self:mineId(userId)
	local c = id and self:crew(id)
	if not c then
		return nil
	end
	local me = c.members[tostring(userId)]
	if not me then
		-- Removed while away: the claim goes.
		self:_update(`p:{userId}`, function(old: any): any
			return if old == id then false else nil
		end)
		return nil
	end
	return { crew = c, role = me.role, summary = Crews.summary(c, self.mods.week and self.mods.week()) }
end

-- The crews a player has asked to join.
function Crews.asked(self: Crews, userId: number): { string }
	local r = self:_get(`r:{userId}`)
	return if type(r) == "table" then r else {}
end

-- The badge shown on a player's card: { tag, emblem, color, name } or nil.
function Crews.badge(self: Crews, userId: number): any?
	local m = self:mine(userId)
	if not m then
		return nil
	end
	return { id = m.crew.id, tag = m.crew.tag, emblem = m.crew.emblem, color = m.crew.color, name = m.crew.name }
end

local function member(who: Who, role: string, at: number): Member
	return { role = role, at = at, name = who.name, town = who.town, level = who.level, power = who.power, wins = who.wins, trophies = who.trophies }
end

-- Checks the look a crew picks: nil when fine, else why not.
function Crews._checkLook(self: Crews, spec: any): string?
	if type(spec.emblem) ~= "string" or not table.find(self.mods.emblems, spec.emblem) then
		return "emblem"
	end
	if type(spec.color) ~= "string" or not table.find(self.mods.colors, spec.color) then
		return "color"
	end
	if type(spec.motto) ~= "string" or utf8.len(spec.motto) == nil or (utf8.len(spec.motto) :: number) > Crews.MOTTO then
		return "motto"
	end
	if type(spec.minLevel) ~= "number" or spec.minLevel ~= math.floor(spec.minLevel) or spec.minLevel < 1 or spec.minLevel > 99 then
		return "level"
	end
	if type(spec.joinMode) ~= "string" or not Crews.MODES[spec.joinMode] then
		return "mode"
	end
	return nil
end

-- A crew name: 3-24 letters, trimmed. nil if it isn't one.
function Crews.cleanName(name: any): string?
	if type(name) ~= "string" then
		return nil
	end
	local s = name:match("^%s*(.-)%s*$") :: string
	local n = utf8.len(s)
	if not n or n < 3 or n > 24 then
		return nil
	end
	return s
end

-- A tag: 2-4 capital letters or digits.
function Crews.cleanTag(tag: any): string?
	if type(tag) ~= "string" then
		return nil
	end
	local t = tag:upper()
	return if t:match("^[A-Z0-9][A-Z0-9][A-Z0-9]?[A-Z0-9]?$") then t else nil
end

-- Takes a name or tag key for a crew (false: someone else has it).
function Crews._claim(self: Crews, key: string, id: string): boolean
	local took = false
	local ok = self:_update(key, function(old: any): any
		took = old == nil or old == id
		return if took then id else nil
	end)
	return ok and took
end

function Crews._release(self: Crews, key: string, id: string)
	self:_update(key, function(old: any): any
		return if old == id then false else nil
	end)
end

-- Puts a player in a crew's claim ("p:"), if they're in none. True when it did.
function Crews._claimPlayer(self: Crews, userId: number, id: string): boolean
	return self:_claim(`p:{userId}`, id)
end

-- Starts a crew, with the player as its Leader. spec: { name, tag, emblem, color, motto,
-- minLevel, joinMode } (the name and motto already through Roblox's filter). Returns the crew's
-- id, or nil and why not ("in a crew", "name", "tag", "name taken", "tag taken", ...).
function Crews.create(self: Crews, userId: number, who: Who, spec: any): (string?, string?)
	if type(spec) ~= "table" then
		return nil, "name"
	end
	local name, tag = Crews.cleanName(spec.name), Crews.cleanTag(spec.tag)
	if not name then
		return nil, "name"
	end
	if not tag then
		return nil, "tag"
	end
	local bad = self:_checkLook(spec)
	if bad then
		return nil, bad
	end
	if self:mine(userId) then
		return nil, "in a crew"
	end
	local id = self.mods.newId()
	if not self:_claimPlayer(userId, id) then
		return nil, "in a crew"
	end
	if not self:_claim(`n:{name:lower()}`, id) then
		self:_release(`p:{userId}`, id)
		return nil, "name taken"
	end
	if not self:_claim(`t:{tag}`, id) then
		self:_release(`n:{name:lower()}`, id)
		self:_release(`p:{userId}`, id)
		return nil, "tag taken"
	end
	local now = self.mods.clock()
	local c: Crew = {
		id = id,
		name = name,
		tag = tag,
		emblem = spec.emblem,
		color = spec.color,
		motto = spec.motto,
		minLevel = spec.minLevel,
		joinMode = spec.joinMode,
		cap = Crews.CAP,
		at = now,
		members = { [tostring(userId)] = member(who, "leader", now) },
		requests = {},
	}
	if not self:_update(`c:{id}`, function()
		return c
	end) then
		self:_release(`t:{tag}`, id)
		self:_release(`n:{name:lower()}`, id)
		self:_release(`p:{userId}`, id)
		return nil, "try again"
	end
	self:_list(id, c)
	self:_dropAsks(userId)
	return id, nil
end

-- Clears a player's requests everywhere (they joined or started a crew).
function Crews._dropAsks(self: Crews, userId: number)
	local asked = self:asked(userId)
	if #asked == 0 then
		return
	end
	for _, id in asked do
		self:_update(`c:{id}`, function(c: any): any
			if type(c) ~= "table" or not c.requests[tostring(userId)] then
				return nil
			end
			c.requests[tostring(userId)] = nil
			return c
		end)
	end
	self:_update(`r:{userId}`, function()
		return false
	end)
end

-- Adds a player to a crew whose claim they already hold: "joined", or why not.
function Crews._add(self: Crews, userId: number, who: Who, id: string, asLevel: boolean): string
	local result = "gone"
	local now = self.mods.clock()
	local ok = self:_update(`c:{id}`, function(c: any): any
		if type(c) ~= "table" then
			result = "gone"
			return nil
		end
		if c.members[tostring(userId)] then
			result = "joined"
			return nil
		end
		if count(c.members) >= c.cap then
			result = "full"
			return nil
		end
		if asLevel and who.level < c.minLevel then
			result = "level"
			return nil
		end
		c.members[tostring(userId)] = member(who, "member", now)
		c.requests[tostring(userId)] = nil
		result = "joined"
		return c
	end)
	if not ok then
		result = "try again"
	end
	if result ~= "joined" then
		self:_release(`p:{userId}`, id)
		return result
	end
	local c = self:crew(id)
	if c then
		self:_list(id, c)
	end
	self:_dropAsks(userId)
	return "joined"
end

-- Joins an open crew, or asks to join one that takes requests. Returns "joined" or "requested",
-- or nil and why not ("in a crew", "closed", "full", "level", "asks", "busy", "gone").
function Crews.ask(self: Crews, userId: number, who: Who, id: string): (string?, string?)
	if type(id) ~= "string" then
		return nil, "gone"
	end
	if self:mine(userId) then
		return nil, "in a crew"
	end
	local c = self:crew(id)
	if not c then
		return nil, "gone"
	end
	if c.joinMode == "closed" then
		return nil, "closed"
	end
	if count(c.members) >= c.cap then
		return nil, "full"
	end
	if who.level < c.minLevel then
		return nil, "level"
	end
	if c.joinMode == "open" then
		if not self:_claimPlayer(userId, id) then
			return nil, "in a crew"
		end
		local r = self:_add(userId, who, id, true)
		return if r == "joined" then "joined" else nil, if r == "joined" then nil else r
	end
	-- A request: on the player's list (5 at most), then at the crew (30 at most).
	local room = false
	self:_update(`r:{userId}`, function(old: any): any
		local list = if type(old) == "table" then old else {}
		if table.find(list, id) then
			room = true
			return nil
		end
		room = #list < Crews.MAX_ASKS
		if not room then
			return nil
		end
		table.insert(list, id)
		return list
	end)
	if not room then
		return nil, "asks"
	end
	local now = self.mods.clock()
	local waiting = false
	self:_update(`c:{id}`, function(old: any): any
		if type(old) ~= "table" then
			return nil
		end
		if old.requests[tostring(userId)] then
			waiting = true
			return nil
		end
		waiting = count(old.requests) < Crews.MAX_WAITING
		if not waiting then
			return nil
		end
		old.requests[tostring(userId)] = { at = now, name = who.name, level = who.level, power = who.power }
		return old
	end)
	if not waiting then
		self:cancel(userId, id)
		return nil, "busy"
	end
	return "requested", nil
end

-- Takes back a request to join.
function Crews.cancel(self: Crews, userId: number, id: string)
	self:_update(`r:{userId}`, function(old: any): any
		if type(old) ~= "table" then
			return nil
		end
		local i = table.find(old, id)
		if not i then
			return nil
		end
		table.remove(old, i)
		return if #old == 0 then false else old
	end)
	self:_update(`c:{id}`, function(c: any): any
		if type(c) ~= "table" or not c.requests[tostring(userId)] then
			return nil
		end
		c.requests[tostring(userId)] = nil
		return c
	end)
end

-- The crew an officer runs, and their rank: (crew, role) or nil.
function Crews._officer(self: Crews, userId: number): (Crew?, string?)
	local m = self:mine(userId)
	if not m or m.role == "member" then
		return nil, nil
	end
	return m.crew, m.role
end

-- A Leader or Co-Leader answers a request: "joined", "declined" or "gone" (they joined somewhere
-- else or took it back), or nil and why not.
function Crews.respond(self: Crews, userId: number, other: number, accept: boolean): (string?, string?)
	local c = self:_officer(userId)
	if not c then
		return nil, "rank"
	end
	local req = c.requests[tostring(other)]
	if not req then
		return "gone", nil
	end
	if not accept then
		self:cancel(other, c.id)
		return "declined", nil
	end
	if count(c.members) >= c.cap then
		return nil, "full"
	end
	if not self:_claimPlayer(other, c.id) then
		self:cancel(other, c.id)
		return "gone", nil
	end
	local who: Who = { name = req.name, level = req.level, power = req.power, wins = 0, trophies = 0 }
	local r = self:_add(other, who, c.id, false)
	if r == "joined" then
		return "joined", nil
	elseif r == "full" then
		return nil, "full"
	end
	return "gone", nil
end

-- Who takes the lead when the Leader goes: the longest-serving Co-Leader, else Member.
local function heir(c: Crew, leaving: string): string?
	local best, bestRank, bestAt = nil, math.huge, math.huge
	for uid, m in c.members do
		if uid ~= leaving then
			local rank = Crews.RANKS[m.role] or 2
			if rank < bestRank or (rank == bestRank and m.at < bestAt) then
				best, bestRank, bestAt = uid, rank, m.at
			end
		end
	end
	return best
end
Crews.heir = heir

-- Takes a player out of their crew (they left, or were removed). The last one out closes it.
function Crews._remove(self: Crews, id: string, userId: number)
	local gone: Crew? = nil
	local kept: Crew? = nil
	self:_update(`c:{id}`, function(c: any): any
		gone, kept = nil, nil
		if type(c) ~= "table" or not c.members[tostring(userId)] then
			return nil
		end
		local was = c.members[tostring(userId)].role
		c.members[tostring(userId)] = nil
		if next(c.members) == nil then
			gone = c
			return false
		end
		if was == "leader" then
			local h = heir(c, tostring(userId))
			if h then
				c.members[h].role = "leader"
			end
		end
		kept = c
		return c
	end)
	self:_release(`p:{userId}`, id)
	local closed = gone
	if closed then
		self:_release(`n:{closed.name:lower()}`, id)
		self:_release(`t:{closed.tag}`, id)
		for uid in closed.requests do
			self:cancel(tonumber(uid) :: number, id)
		end
		self:_list(id, nil)
	elseif kept then
		self:_list(id, kept)
	end
end

-- Leaves the player's crew.
function Crews.leave(self: Crews, userId: number): (boolean, string?)
	local id = self:mineId(userId)
	if not id then
		return false, "no crew"
	end
	self:_remove(id, userId)
	return true, nil
end

-- What the viewer may do to a crewmate: nobody acts on the Leader; Co-Leaders only on Members.
function Crews.canRemove(me: string, them: string): boolean
	return them ~= "leader" and (me == "leader" or (me == "co_leader" and them == "member"))
end

-- Removes a crewmate.
function Crews.kick(self: Crews, userId: number, other: number): (boolean, string?)
	local c, role = self:_officer(userId)
	if not c or not role then
		return false, "rank"
	end
	local them = c.members[tostring(other)]
	if not them then
		return false, "gone"
	end
	if not Crews.canRemove(role, them.role) then
		return false, "rank"
	end
	self:_remove(c.id, other)
	return true, nil
end

-- The Leader sets a crewmate's rank; making them Leader hands the lead over.
function Crews.setRank(self: Crews, userId: number, other: number, rank: any): (boolean, string?)
	if rank ~= "leader" and rank ~= "co_leader" and rank ~= "member" then
		return false, "rank"
	end
	local id = self:mineId(userId)
	if not id or other == userId then
		return false, "rank"
	end
	local why: string? = "rank"
	local done = false
	self:_update(`c:{id}`, function(c: any): any
		done, why = false, "rank"
		if type(c) ~= "table" then
			return nil
		end
		local me, them = c.members[tostring(userId)], c.members[tostring(other)]
		if not me or me.role ~= "leader" then
			return nil
		end
		if not them then
			why = "gone"
			return nil
		end
		them.role = rank
		if rank == "leader" then
			me.role = "co_leader"
		end
		done, why = true, nil
		return c
	end)
	return done, why
end

-- A Leader or Co-Leader changes the crew's emblem, colour, motto, level needed or who may join
-- (the name and tag never change). Going closed drops the requests waiting.
function Crews.settings(self: Crews, userId: number, spec: any): (boolean, string?)
	if type(spec) ~= "table" then
		return false, "motto"
	end
	local bad = self:_checkLook(spec)
	if bad then
		return false, bad
	end
	local c = self:_officer(userId)
	if not c then
		return false, "rank"
	end
	local dropped: { string } = {}
	local kept: Crew? = nil
	self:_update(`c:{c.id}`, function(old: any): any
		kept = nil
		if type(old) ~= "table" then
			return nil
		end
		old.emblem, old.color, old.motto, old.minLevel, old.joinMode = spec.emblem, spec.color, spec.motto, spec.minLevel, spec.joinMode
		dropped = {}
		if spec.joinMode == "closed" then
			for uid in old.requests do
				table.insert(dropped, uid)
			end
			old.requests = {}
		end
		kept = old
		return old
	end)
	for _, uid in dropped do
		self:cancel(tonumber(uid) :: number, c.id)
	end
	if kept then
		self:_list(c.id, kept)
	end
	return kept ~= nil, if kept then nil else "try again"
end

-- Brings a member's name and numbers up to date in their crew (when they've changed).
function Crews.touch(self: Crews, userId: number, who: Who)
	local id = self:mineId(userId)
	if not id then
		return
	end
	local kept: Crew? = nil
	self:_update(`c:{id}`, function(c: any): any
		kept = nil
		local m = if type(c) == "table" then c.members[tostring(userId)] else nil
		if not m then
			return nil
		end
		-- (Seen is kept to the day, so a save doesn't always mean a write.)
		local now = self.mods.clock()
		local stale = (c.seen or c.at or 0) < now - 86400
		-- Their numbers when first seen this week, for the week's gains.
		local wk = self.mods.week and self.mods.week()
		local newWeek = wk ~= nil and m.wk ~= wk
		if newWeek then
			m.wk, m.base = wk, { power = who.power, wins = who.wins, trophies = who.trophies, level = who.level }
		end
		if not stale and not newWeek and m.name == who.name and m.town == who.town and m.level == who.level and m.power == who.power and m.wins == who.wins and m.trophies == who.trophies then
			return nil
		end
		m.name, m.town, m.level, m.power, m.wins, m.trophies = who.name, who.town, who.level, who.power, who.wins, who.trophies
		if stale then
			c.seen = now
		end
		kept = c
		return c
	end)
	if kept then
		self:_list(id, kept)
	end
end

return Crews
