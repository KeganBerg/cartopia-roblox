--!strict
-- Playing together: visiting other players' towns in this server and helping their businesses,
-- as the web game's Friends menu and VisitBanner do (ui/Friends.tsx, lib/help.ts, game/help.ts).
--
-- A visit is the visitor's "Visiting" attribute (the host's user id): the server moves their
-- avatar to the host's lot, and their client points its camera there. Help works as on the web:
-- tap one of the host's businesses to lend a hand and be paid for it, HELPS_PER_TOWN a town and
-- HELPS_PER_DAY in all each UTC day. The day's helps are kept in a DataStore so leaving and coming
-- back doesn't reset them (the web keeps them in its town_helps table).
--
-- The rules (game/help.ts) are ported here by hand: the converter can't take its regexes.

local Social = {}
Social.__index = Social

-- game/help.ts HELP_TABLE.
Social.HELPS_PER_TOWN = 5
Social.HELPS_PER_DAY = 40
local T = { coins = 20, coinsPerLevel = 5, coinsPerShopLevel = 10, xp = 2, xpPerFiveLevels = 1, lastParts = 2 }
Social.ASKING = 8

-- A business with a job to help with (not decor, houses or obstacles).
function Social.helpable(def: any): boolean
	return def ~= nil and (def.jobSeconds or 0) > 0 and def.kind ~= "obstacle" and not def.parked
end

-- What one help pays: level is the helper's level, shopLevel the business's, nth which of today's
-- helps in this town it is (1-based). Finishing the town adds parts.
function Social.helpPrize(level: number, shopLevel: number, nth: number): { coins: number, xp: number, parts: number }
	return {
		coins = T.coins + T.coinsPerLevel * level + T.coinsPerShopLevel * (math.max(1, math.min(10, shopLevel)) - 1),
		xp = T.xp + T.xpPerFiveLevels * math.floor(level / 5),
		parts = if nth == Social.HELPS_PER_TOWN then T.lastParts else 0,
	}
end

-- FNV-1a over the string's UTF-16 code units, as help.ts's hash (Math.imul, >>> 0).
local function hash(text: string): number
	local h = 2166136261
	for _, code in utf8.codes(text) do
		local units: { number } = if code >= 0x10000 then { 0xD800 + bit32.rshift(code - 0x10000, 10), 0xDC00 + bit32.band(code - 0x10000, 0x3FF) } else { code }
		for _, u in units do
			h = bit32.bxor(h, u)
			-- Math.imul(h, 16777619): the low 32 bits of the product, done in halves so no
			-- precision is lost in a double.
			local lo = bit32.band(h, 0xFFFF) * 16777619
			local hi = bit32.band(bit32.rshift(h, 16) * 16777619, 0xFFFF)
			h = bit32.band(lo + bit32.lshift(hi, 16), 0xFFFFFFFF)
		end
	end
	return h
end
Social._hash = hash

-- The shops that ask for a hand today (askingForHelp): a few picked by owner and date, so the
-- town isn't covered in bubbles and the picks change every day. Help is taken at any business.
function Social.asking(shops: { any }, ownerId: string, day: string): { any }
	if #shops <= Social.ASKING then
		return shops
	end
	local sorted = table.clone(shops)
	local keys = {}
	for _, b in sorted do
		keys[b] = hash(`{ownerId}:{day}:{b.uid}`)
	end
	table.sort(sorted, function(a, b)
		return keys[a] < keys[b]
	end)
	return table.move(sorted, 1, Social.ASKING, 1, {})
end

-- How you lend a hand at each kind of business: the badge icon and the thank-you (helpAct).
local ACTS: { { any } } = {
	{ { "wash" }, "🧽", "scrubbed cars" },
	{ { "tires", "lube", "bodyshop", "tuner", "parts", "muffler", "brakes", "wraps", "dynolab", "engines", "racefab" }, "🔧", "fixed a car" },
	{ { "gas" }, "⛽", "pumped gas" },
	{ { "pizza", "burger", "donut", "icecream", "diner", "tacos", "hotdog", "coffee" }, "🍔", "served customers" },
	{ { "cinema", "bowling", "arcade", "club", "stadium", "minigolf", "funfair", "waterpark", "haunted" }, "🎟️", "sold tickets" },
	{ { "pool" }, "🛟", "kept watch at the pool" },
	{ { "laundry" }, "🧺", "folded laundry" },
	{ { "vet" }, "🐾", "walked the dogs" },
	{ { "postoffice" }, "📮", "sorted the mail" },
	{ { "library" }, "📚", "shelved books" },
	{ { "busdepot" }, "🚌", "washed the buses" },
	{ { "cityhall" }, "📋", "filed the paperwork" },
	{ { "motel", "hotel" }, "🛏️", "made the beds" },
	{ { "school", "academy", "university" }, "📚", "helped in class" },
	{ { "hospital", "firehouse", "police" }, "🩹", "lent a hand" },
	{ { "market" }, "🛒", "stocked shelves" },
	{ { "offices", "hq", "glasstower", "helipad" }, "📋", "sorted the mail" },
}
function Social.helpAct(id: string): { icon: string, did: string }
	for _, act in ACTS do
		for _, word in act[1] do
			if string.find(id, word, 1, true) then
				return { icon = act[2], did = act[3] }
			end
		end
	end
	return { icon = "🧹", did = "tidied up" }
end

-- A day's helps for one helper: how many in all, and which businesses in each town.
export type Day = { n: number, towns: { [string]: { string } } }

export type Deps = {
	towns: any, -- server/Towns
	data: any, -- Shared.Game.data
	today: () -> string, -- the UTC day, as the web's today()
	-- A DataStore (UpdateAsync) for the day's helps, or nil to keep them in memory only.
	helps: any?,
}

export type Social = typeof(setmetatable({} :: { deps: Deps, days: { [number]: { day: string, rec: Day } } }, Social))

function Social.new(deps: Deps): Social
	return setmetatable({ deps = deps, days = {} }, Social)
end

-- The helper's helps for today, loaded once a day from the DataStore.
function Social._day(self: Social, helperId: number): Day
	local day = self.deps.today()
	local have = self.days[helperId]
	if have and have.day == day then
		return have.rec
	end
	local rec: Day = { n = 0, towns = {} }
	local store = self.deps.helps
	if store then
		local ok, got = pcall(function()
			return store:GetAsync(`{day}_{helperId}`)
		end)
		if ok and type(got) == "table" and type(got.n) == "number" and type(got.towns) == "table" then
			rec = got
		end
	end
	self.days[helperId] = { day = day, rec = rec }
	return rec
end

function Social._keep(self: Social, helperId: number)
	local store = self.deps.helps
	local have = self.days[helperId]
	if not store or not have then
		return
	end
	local key, rec = `{have.day}_{helperId}`, table.clone(have.rec)
	task.spawn(function()
		pcall(function()
			store:SetAsync(key, rec)
		end)
	end)
end

function Social.forget(self: Social, userId: number)
	self.days[userId] = nil
end

-- Businesses in the host's town the helper has already helped today.
function Social.helped(self: Social, helperId: number, hostId: number): { string }
	return self:_day(helperId).towns[tostring(hostId)] or {}
end

-- What the visit banner and help bubbles need about a town being visited.
function Social.townInfo(self: Social, helperId: number, hostId: number): any
	local save = self.deps.towns:save(hostId)
	local data = self.deps.data
	local shops = {}
	for _, b in save.buildings or {} do
		if Social.helpable(data.buildingDef(b.def)) then
			table.insert(shops, b)
		end
	end
	local asking = {}
	for _, b in Social.asking(shops, tostring(hostId), self.deps.today()) do
		table.insert(asking, b.uid)
	end
	local day = self:_day(helperId)
	return {
		host = hostId,
		townName = save.townName,
		level = save.level,
		trophies = save.trophies or 0,
		cars = #(save.cars or {}),
		land = save.land,
		roads = save.roads,
		asking = asking,
		helped = day.towns[tostring(hostId)] or {},
		dayFull = day.n >= Social.HELPS_PER_DAY,
	}
end

-- The helper lends a hand at business uid in the host's town. Pays the helper (the store's
-- visitorPrize) and returns { coins, xp, parts, helped } or nil and why not.
function Social.help(self: Social, helperId: number, hostId: number, uid: string): (any?, string?)
	local towns = self.deps.towns
	if helperId == hostId or not towns:isOpen(hostId) or not towns:isOpen(helperId) then
		return nil, "not visiting"
	end
	local host = towns:save(hostId)
	local b = nil
	for _, x in host.buildings or {} do
		if x.uid == uid then
			b = x
		end
	end
	local data = self.deps.data
	if not b or not Social.helpable(data.buildingDef(b.def)) then
		return nil, "not a business"
	end
	local day = self:_day(helperId)
	local key = tostring(hostId)
	local done = day.towns[key] or {}
	if table.find(done, uid) then
		return nil, "already helped"
	end
	if #done >= Social.HELPS_PER_TOWN then
		return nil, "town done"
	end
	if day.n >= Social.HELPS_PER_DAY then
		return nil, "day done"
	end
	local level = towns:save(helperId).level or 1
	local nth = #done + 1
	local prize = Social.helpPrize(level, data.buildingLevel(b), nth)
	done = table.clone(done)
	table.insert(done, uid)
	day.towns[key] = done
	day.n += 1
	self:_keep(helperId)
	local act = Social.helpAct(b.def)
	local def = data.buildingDef(b.def)
	local finished = nth >= Social.HELPS_PER_TOWN
	towns:_with(helperId, function(s)
		-- The first help on a visit counts towards friendship (game/friendship.ts).
		if nth == 1 then
			s.befriend(key, "help", host.townName)
		end
		s.visitorPrize({ coins = prize.coins, xp = prize.xp, parts = prize.parts, bucks = 0 })
		s.toast(if finished
			then `🤝 {host.townName} is all helped out! +${prize.coins}{if prize.parts > 0 then `, +{prize.parts} parts` else ""}`
			else `{act.icon} You {act.did} at {def.name}! +${prize.coins}`)
		if finished then
			s.markHelped(key)
		end
	end)
	return { coins = prize.coins, xp = prize.xp, parts = prize.parts, helped = done }
end

return Social
