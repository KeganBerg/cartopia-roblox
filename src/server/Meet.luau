--!strict
-- The Car Meet (the web game's lib/meet.ts and supabase/migrations/0030_car_meet_likes.sql, 0092):
-- every player's display of up to three cars (game/meet showcaseOf: their picks, or their three
-- best), the most recently seen displays to look through, and likes: one like per town, ever, and
-- at most 40 likes a day.
--
-- In Roblox a display is kept in "MeetDisplays_v1" (by owner) when the town is saved, with when it
-- was saved in the OrderedDataStore "MeetRecent_v1" (newest first). Like counts are in
-- "MeetLikes_v1" (by owner) and who each player has liked in "MeetLiked_v1". Without DataStores
-- (tests, the emulator) everything lives in memory.
--
-- Player cards (the web game's lib/playerCard.ts): another player's public numbers and their cars,
-- the ones on show first. Kept in "MeetCards_v1" (by owner) when the town is saved, for players who
-- aren't in this server.

local Meet = {}
Meet.__index = Meet

Meet.PER_DAY = 40
local RECENT = 30
local FRESH = 60
-- The car fields a display carries (enough to draw the car as it looks in its owner's garage).
local CAR_KEYS = { "uid", "model", "color", "finish", "stripe", "hat", "mods", "panels", "trim", "skin", "modSkin" }
-- A card carries this many cars at most (the web's STRIP_MAX).
Meet.CARD_CARS = 40

export type Backend = {
	ordered: (name: string) -> any,
	plain: (name: string) -> any,
}

export type Meet = typeof(setmetatable(
	{} :: {
		backend: Backend?,
		clock: () -> number,
		today: () -> string,
		mem: { [string]: { [string]: any } },
		recent: { [number]: number },
		cache: { at: number, value: any }?,
		likeCache: { [number]: number },
			cardKeys: { [number]: string },
	},
	Meet
))

-- clock: seconds (os.time); today: today's date key, for the daily limit.
function Meet.new(backend: Backend?, clock: () -> number, today: () -> string): Meet
	return setmetatable({ backend = backend, clock = clock, today = today, mem = {}, recent = {}, cache = nil, likeCache = {}, cardKeys = {} }, Meet)
end

-- A car as a display carries it.
function Meet.carOf(car: any): any
	local out = {}
	for _, k in CAR_KEYS do
		out[k] = car[k]
	end
	return out
end

function Meet._get(self: Meet, store: string, key: string): any
	local b = self.backend
	if not b then
		return (self.mem[store] or {})[key]
	end
	local ok, v = pcall(function()
		return b.plain(store):GetAsync(key)
	end)
	return if ok then v else nil
end

function Meet._set(self: Meet, store: string, key: string, value: any)
	local b = self.backend
	if not b then
		self.mem[store] = self.mem[store] or {}
		self.mem[store][key] = value
		return
	end
	pcall(function()
		b.plain(store):SetAsync(key, value)
	end)
end

-- Changes a stored value in one step (UpdateAsync), returning the new value.
function Meet._update(self: Meet, store: string, key: string, fn: (any) -> any): any
	local b = self.backend
	if not b then
		self.mem[store] = self.mem[store] or {}
		local v = fn(self.mem[store][key])
		if v ~= nil then
			self.mem[store][key] = v
		end
		return self.mem[store][key]
	end
	local out = nil
	local ok = pcall(function()
		b.plain(store):UpdateAsync(key, function(old)
			local v = fn(old)
			out = if v ~= nil then v else old
			return v
		end)
	end)
	return if ok then out else nil
end

-- Puts a player's display up (on save). cars: their showcase (game/meet showcaseOf).
function Meet.publish(self: Meet, userId: number, name: string, town: string, level: number, cars: { any })
	if userId <= 0 or #cars == 0 then
		return
	end
	local list = {}
	for _, c in cars do
		table.insert(list, Meet.carOf(c))
	end
	self:_set("MeetDisplays_v1", tostring(userId), { name = name, town = town, level = level, cars = list })
	local now = self.clock()
	local b = self.backend
	if b then
		pcall(function()
			b.ordered("MeetRecent_v1"):SetAsync(tostring(userId), now)
		end)
	else
		self.recent[userId] = now
	end
end

-- The most recently seen displays, newest first: { id, name, town, level, cars }.
function Meet.displays(self: Meet): { any }
	local now = self.clock()
	if self.cache and now - self.cache.at < FRESH then
		return self.cache.value
	end
	local ids: { number } = {}
	local b = self.backend
	if b then
		local ok, page = pcall(function()
			return b.ordered("MeetRecent_v1"):GetSortedAsync(false, RECENT):GetCurrentPage()
		end)
		if ok and page then
			for _, e in page do
				local id = tonumber(e.key)
				if id then
					table.insert(ids, id)
				end
			end
		end
	else
		for id in self.recent do
			table.insert(ids, id)
		end
		table.sort(ids, function(a, c)
			if self.recent[a] ~= self.recent[c] then
				return self.recent[a] > self.recent[c]
			end
			return a < c
		end)
	end
	local out = {}
	for _, id in ids do
		local d = self:_get("MeetDisplays_v1", tostring(id))
		if type(d) == "table" and type(d.cars) == "table" and #d.cars > 0 then
			table.insert(out, { id = id, name = d.name, town = d.town, level = d.level, cars = d.cars })
		end
	end
	self.cache = { at = now, value = out }
	return out
end

function Meet.likes(self: Meet, owner: number): number
	local v = self:_get("MeetLikes_v1", tostring(owner))
	return if type(v) == "number" then v else 0
end

-- Who the player has liked, and how many likes they've given today.
function Meet._liked(self: Meet, userId: number): any
	local v = self:_get("MeetLiked_v1", tostring(userId))
	return if type(v) == "table" then v else { owners = {}, day = "", n = 0 }
end

-- Likes on these displays and whether the viewer has liked each: { [owner] = { likes, liked } }.
function Meet.likesFor(self: Meet, viewer: number, owners: { number }): { [string]: any }
	local mine = self:_liked(viewer)
	local out = {}
	for _, o in owners do
		out[tostring(o)] = { likes = self:likes(o), liked = (mine.owners or {})[tostring(o)] == true }
	end
	return out
end

-- Likes a display: "liked", or why not ("self", "already", "limit", "no").
function Meet.like(self: Meet, viewer: number, owner: number): string
	if viewer == owner then
		return "self"
	end
	local today = self.today()
	local result = "no"
	self:_update("MeetLiked_v1", tostring(viewer), function(old: any): any
		local v = if type(old) == "table" then old else { owners = {}, day = today, n = 0 }
		v.owners = v.owners or {}
		if v.owners[tostring(owner)] then
			result = "already"
			return nil
		end
		if v.day ~= today then
			v.day, v.n = today, 0
		end
		if v.n >= Meet.PER_DAY then
			result = "limit"
			return nil
		end
		v.owners[tostring(owner)] = true
		v.n += 1
		result = "liked"
		return v
	end)
	if result == "liked" then
		self:_update("MeetLikes_v1", tostring(owner), function(old: any): any
			return (if type(old) == "number" then old else 0) + 1
		end)
	end
	return result
end

-- A player's card from their save. shown: their cars on show (game/meet showcaseOf); pi: a car's
-- performance index. Cars: the ones on show, then the rest by PI, each with its pi.
function Meet.cardOf(save: any, shown: { any }, pi: (any) -> number): any
	local cars = {}
	local best = 0
	for _, c in save.cars or {} do
		if type(c) == "table" and type(c.uid) == "string" and type(c.model) == "string" then
			local p = math.floor(pi(c))
			best = math.max(best, p)
			table.insert(cars, { car = c, pi = p })
		end
	end
	local on: { [string]: boolean } = {}
	local out, showcase = {}, {}
	for _, c in shown do
		on[c.uid] = true
		table.insert(showcase, c.uid)
	end
	table.sort(cars, function(a, b)
		local sa, sb = on[a.car.uid] == true, on[b.car.uid] == true
		if sa ~= sb then
			return sa
		end
		if sa then
			return (table.find(showcase, a.car.uid) :: number) < (table.find(showcase, b.car.uid) :: number)
		end
		if a.pi ~= b.pi then
			return a.pi > b.pi
		end
		return a.car.uid < b.car.uid
	end)
	for i, e in cars do
		if i > Meet.CARD_CARS then
			break
		end
		local c = Meet.carOf(e.car)
		c.pi = e.pi
		table.insert(out, c)
	end
	return {
		town = if type(save.townName) == "string" then save.townName else "My Town",
		level = math.floor(tonumber(save.level) or 1),
		trophies = math.floor(tonumber(save.trophies) or 0),
		raceWins = math.floor(tonumber(save.racesWon) or 0),
		bestPi = best,
		cars = out,
		showcase = showcase,
	}
end

-- Keeps a player's card for players in other servers (on save), when anything on it changed.
function Meet.saveCard(self: Meet, userId: number, name: string, card: any)
	if userId <= 0 then
		return
	end
	local parts = { name, card.town, card.level, card.trophies, card.raceWins, table.concat(card.showcase, ",") }
	for _, c in card.cars do
		table.insert(parts, `{c.uid}{c.model}{c.color}{c.pi}{c.finish}{c.skin}{c.hat}`)
	end
	local key = table.concat(parts :: { any }, "|")
	if self.cardKeys[userId] == key then
		return
	end
	self.cardKeys[userId] = key
	local stored = table.clone(card)
	stored.name = name
	self:_set("MeetCards_v1", tostring(userId), stored)
end

-- A kept card, or nil.
function Meet.card(self: Meet, userId: number): any
	local v = self:_get("MeetCards_v1", tostring(userId))
	return if type(v) == "table" and type(v.cars) == "table" then v else nil
end

return Meet
