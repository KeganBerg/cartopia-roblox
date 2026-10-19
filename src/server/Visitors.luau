--!strict
-- Surprise visitors in town (the web's lib/visitors.ts, with its server's visitor_next() and
-- visitor_claim() from supabase/migrations/0111_gems_x10.sql and 0038): every few minutes someone
-- turns up, a street racer, tourists or a mystery car, each with a prize fixed when it arrives.
--
-- The web asks its server for a signed-in player's visitor, and the server picks the kind and fixes
-- the prize; here this module is that server. The client asks for the next visitor when its own
-- timer says so ("next"); the server keeps to the same rules as visitor_next(): the visitor still
-- in town comes back, none sooner than VISIT_GAP_MIN minutes after the last, at most
-- VISITS_PER_DAY a UTC day. It also dresses the visitor (the web's client-side dress(): a racer's
-- car and PI near the town's best car, a camper full of tourists, a black supercar), since the
-- street race is run on the server and its rival can't come from the client.
--
-- Tourists and the mystery car pay when tapped ("claim", within the visitor's time plus the web
-- server's 15 seconds' grace). A street racer pays only by being beaten, in a street race started
-- through server/Races (mode "street", server/Modes/Street), which calls startStreet and
-- finishStreet here. Rusty's barn tips are off on the web (Kegan 2026-10-15: roomForBarn() is
-- false), so they never come here either; the barn find's roll is kept for when they're back.

local Visitors = {}
Visitors.__index = Visitors

-- The web's lib/visitors.ts RACERS and TOWNS.
local RACERS = { "Vinnie Vroom", "Dash Delgado", "Skid Malone", "Roxy Redline", "Turbo Tess", "Nitro Nate", "Clutch Carla", "Burnout Bo" }
local TOWNS = { "Nitro Bay", "Piston Peak", "Chrome City", "Turbo Falls", "Gearville", "Muffler Hills" }
local CAMPERS = { "#ffe082", "#80deea", "#f8bbd0", "#c5e1a5" }
-- Object.keys(VISITORS), the order the kinds are rolled in.
local KINDS = { "racer", "tourist", "mystery", "barn" }
local STOCK = { engine = 0, turbo = 0, tires = 0, weight = 0 }
-- Barn tips are off (lib/visitors.ts roomForBarn).
Visitors.BARN = false
-- visitor_claim(): a little grace for the trip to the server; a street race takes a while to run.
Visitors.GRACE_MS = 15000
-- visitor_claim(): a racer can't be "beaten" sooner than this after turning up.
Visitors.RACE_FIRST_MS = 10000
-- The web's town has to have this many roads before anyone visits (lib/visitors.ts ready()).
Visitors.MIN_ROADS = 4

export type Visit = {
	id: string,
	kind: string,
	coins: number,
	xp: number,
	parts: number,
	bucks: number,
	createdAt: number,
	expiresAt: number,
	model: string,
	color: string,
	name: string,
	pi: number,
	body: string,
	group: number?,
	-- A street race has been started against them (one race per visitor).
	raced: boolean?,
	-- Paid, or sent on their way: nothing more to claim.
	done: boolean?,
}

-- What's kept between visits: the last arrival, the day's count, the day's barn finds.
type Record = { lastAt: number, day: string, n: number, barn: number }

export type Mods = {
	store: any,
	data: any,
	-- 0 <= x < 1.
	random: () -> number,
	-- Milliseconds since the epoch.
	now: () -> number,
	-- Where each player's record is kept between sessions (a DataStore); optional.
	records: { get: (userId: number) -> any, set: (userId: number, rec: any) -> () }?,
}

export type Visitors = typeof(setmetatable({} :: { towns: any, mods: Mods, cur: { [number]: Visit }, recs: { [number]: Record }, seq: number }, Visitors))

function Visitors.new(towns: any, mods: Mods): Visitors
	return setmetatable({ towns = towns, mods = mods, cur = {}, recs = {}, seq = 0 }, Visitors)
end

local function pick<T>(self: Visitors, list: { T }): T
	return list[math.floor(self.mods.random() * #list) + 1]
end

-- The UTC day of a time in ms, as the SQL's date_trunc('day', now() at time zone 'utc').
local function dayOf(ms: number): string
	return os.date("!%Y-%m-%d", math.floor(ms / 1000)) :: string
end

function Visitors._record(self: Visitors, userId: number): Record
	local rec = self.recs[userId]
	if rec then
		return rec
	end
	local saved: any = nil
	if self.mods.records then
		local ok, v = pcall(self.mods.records.get, userId)
		saved = if ok then v else nil
	end
	local made: Record = {
		lastAt = if type(saved) == "table" and type(saved.lastAt) == "number" then saved.lastAt else 0,
		day = if type(saved) == "table" and type(saved.day) == "string" then saved.day else "",
		n = if type(saved) == "table" and type(saved.n) == "number" then saved.n else 0,
		barn = if type(saved) == "table" and type(saved.barn) == "number" then saved.barn else 0,
	}
	self.recs[userId] = made
	return made
end

-- A street racer's PI against your best car: most are within 5% either way, one in five is 5-10%
-- quicker (lib/visitors.ts visitorPiFactor).
function Visitors.piFactor(r: number, r2: number): number
	return if r < 0.2 then 1.05 + r2 * 0.05 else 0.95 + r2 * 0.1
end

-- The town's best car's PI, at least 10 (lib/visitors.ts bestPi).
function Visitors._bestPi(self: Visitors, s: any): number
	local data = self.mods.data
	local best = 10
	for _, c in s.cars or {} do
		best = math.max(best, data.performance(data.carDef(c.model), c.upgrades, c.mods))
	end
	return best
end

-- Picks the kind as visitor_next() does: by the VISITORS weights, the barn only when asked for.
function Visitors.rollKind(self: Visitors, barn: boolean): string
	local data = self.mods.data
	local total = 0
	for _, k in KINDS do
		if k ~= "barn" or barn then
			total += data.VISITORS[k].weight
		end
	end
	local r = self.mods.random() * total
	local kind = KINDS[1]
	for _, k in KINDS do
		if k == "barn" and not barn then
			continue
		end
		kind = k
		r -= data.VISITORS[k].weight
		if r <= 0 then
			break
		end
	end
	return kind
end

-- A visitor of `kind`, with its prize (visitor_next(): from the town's level) and its look
-- (lib/visitors.ts dress()).
function Visitors._make(self: Visitors, s: any, kind: string, t: number): Visit
	local data = self.mods.data
	local p = data.VISITORS[kind].pay
	local level = s.level or 1
	local model, color, pi, name = "camper", pick(self, CAMPERS), 0, ""
	if kind == "racer" then
		pi = math.floor(self:_bestPi(s) * Visitors.piFactor(self.mods.random(), self.mods.random()) + 0.5)
		local best, gap = nil, math.huge
		for _, c in data.CARS do
			if c.bucks then
				continue
			end
			local d = math.abs(data.performance(c, STOCK) - pi)
			if d < gap then
				best, gap = c, d
			end
		end
		local car = best :: any
		model, color = car.id, pick(self, car.colors)
		name = `{pick(self, RACERS)} from {pick(self, TOWNS)}`
	elseif kind == "mystery" then
		model, color = "zenith", "#15151d"
	end
	local group = if kind == "tourist" then data.touristGroup(data.touristScore(s.buildings or {}), self.mods.random()) else 1
	self.seq += 1
	return {
		id = `v{t}{self.seq}`,
		kind = kind,
		coins = math.floor(p.coins + p.coinsPerLevel * level + 0.5),
		xp = math.floor(p.xp + p.xpPerLevel * level + 0.5),
		parts = p.parts,
		bucks = if self.mods.random() < p.bucksChance then data.VISITOR_BUCKS else 0,
		createdAt = t,
		expiresAt = t + data.VISITORS[kind].minutes * 60000,
		model = model,
		color = color,
		name = name,
		pi = pi,
		body = data.carDef(model).body,
		group = if group > 1 then group else nil,
	}
end

-- What the client gets for a visitor: everything but the server's own marks.
local function card(v: Visit): any
	return {
		id = v.id,
		kind = v.kind,
		coins = v.coins,
		xp = v.xp,
		parts = v.parts,
		bucks = v.bucks,
		expiresAt = v.expiresAt,
		model = v.model,
		color = v.color,
		name = v.name,
		pi = v.pi,
		body = v.body,
		group = v.group,
	}
end

-- The visitor in town, if any (not yet paid or gone, and within its time).
function Visitors.current(self: Visitors, userId: number): Visit?
	local v = self.cur[userId]
	if v and not v.done and self.mods.now() <= v.expiresAt then
		return v
	end
	return nil
end

-- visitor_next(): the visitor still in town, a new one, or { wait = seconds } until one can come.
-- Nobody visits a town still in the tutorial or with too few roads to drive on.
function Visitors.next(self: Visitors, userId: number): (any?, string?)
	local t = self.mods.now()
	local here = self:current(userId)
	if here then
		return card(here), nil
	end
	local rec = self:_record(userId)
	local gap = self.mods.data.VISIT_GAP_MIN * 60000
	if rec.lastAt > t - gap then
		return { wait = math.ceil((rec.lastAt + gap - t) / 1000) }, nil
	end
	local today = dayOf(t)
	if rec.day ~= today then
		rec.day, rec.n, rec.barn = today, 0, 0
	end
	if rec.n >= self.mods.data.VISITS_PER_DAY then
		local midnight = (t // 86400000 + 1) * 86400000
		return { wait = math.ceil((midnight - t) / 1000) }, nil
	end
	local v: Visit? = nil
	local why: string? = nil
	self.towns:_with(userId, function(s: any)
		s.tick(t)
		if (s.tutorial or 0) < 99 or #(s.roads or {}) < Visitors.MIN_ROADS then
			why = "not ready"
			return
		end
		local rusty = false
		if Visitors.BARN and rec.barn < self.mods.data.BARN_PER_DAY then
			for _, b in s.buildings or {} do
				if b.def == "rescue" then
					rusty = true
				end
			end
		end
		v = self:_make(s, self:rollKind(rusty), t)
	end)
	if not v then
		return { wait = 60 }, why
	end
	local made = v :: Visit
	rec.lastAt = t
	rec.n += 1
	if made.kind == "barn" then
		rec.barn += 1
	end
	self.cur[userId] = made
	if self.mods.records then
		pcall(self.mods.records.set, userId, { lastAt = rec.lastAt, day = rec.day, n = rec.n, barn = rec.barn })
	end
	return card(made), nil
end

-- A barn find (visitor_claim(), the web's rollBarnCar): one of the cars at the rescue spots the
-- town's level has opened, mostly commons.
function Visitors._barnCar(self: Visitors, level: number): any
	local data = self.mods.data
	local pool = {}
	local total = 0
	for _, sp in data.RESCUE_SPOTS do
		if sp.unlockLevel <= level then
			for _, c in sp.cars do
				table.insert(pool, c)
				total += data.BARN_RARITY[c.rarity]
			end
		end
	end
	local r = self.mods.random() * total
	local c = pool[1]
	for _, o in pool do
		c = o
		r -= data.BARN_RARITY[o.rarity]
		if r <= 0 then
			break
		end
	end
	self.seq += 1
	return { uid = `r{self.mods.now()}{self.seq}`, model = c.model, rarity = c.rarity }
end

-- 12345 -> "12,345" (toLocaleString).
local function commas(n: number): string
	local out = tostring(math.floor(n)):reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return if out:sub(1, 1) == "," then out:sub(2) else out
end

-- What the web's thanks() toasts once a visitor has paid.
local function thanks(self: Visitors, v: Visit, p: any): string
	local bits = {}
	if p.coins > 0 then
		table.insert(bits, `+${commas(p.coins)}`)
	end
	if p.parts > 0 then
		table.insert(bits, `+{p.parts} parts`)
	end
	if p.bucks > 0 then
		table.insert(bits, `+{p.bucks} gems`)
	end
	if p.xp > 0 then
		table.insert(bits, `+{p.xp} XP`)
	end
	local list = table.concat(bits, ", ")
	if v.kind == "barn" and p.car then
		return `🛻 Rusty towed a {self.mods.data.carDef(p.car.model).name} home! It's in storage.`
	elseif v.kind == "racer" then
		return `🏁 You beat the street racer! Bonus {list}`
	elseif v.kind == "tourist" then
		return `📸 The tourists loved your town! Tip: {list}`
	end
	return `❓ Caught the mystery car! {list}`
end

-- Pays a visitor through the web store's visitorPrize, inside the town (`s` is its state).
function Visitors._pay(self: Visitors, _s: any, v: Visit): any
	local store = self.mods.store.useGame.getState
	local now = store()
	local paid: any = { coins = v.coins, xp = v.xp, parts = v.parts, bucks = v.bucks, seq = (now.visits or 0) + 1 }
	if v.kind == "barn" then
		paid.car = self:_barnCar(now.level or 1)
	end
	v.done = true
	store().visitorPrize(paid)
	store().toast(thanks(self, v, paid))
	return { kind = v.kind, coins = paid.coins, xp = paid.xp, parts = paid.parts, bucks = paid.bucks, car = paid.car }
end

-- The visitor `id` if it's this player's and still to be paid, within its time and the grace.
function Visitors._live(self: Visitors, userId: number, id: any): (Visit?, string?)
	local v = self.cur[userId]
	if type(id) ~= "string" or not v or v.id ~= id or v.done then
		return nil, "no such visitor"
	end
	if self.mods.now() > v.expiresAt + Visitors.GRACE_MS then
		v.done = true
		return nil, "the visitor left"
	end
	return v, nil
end

-- Tapping tourists or the mystery car (visitor_claim()): pays their prize. A street racer pays
-- only by being beaten in a street race. Returns what was paid, or nil and why.
function Visitors.claim(self: Visitors, userId: number, id: any): (any?, string?)
	local v, why = self:_live(userId, id)
	if not v then
		return nil, why
	end
	if v.kind == "racer" then
		return nil, "race first"
	end
	local out: any, err: string? = nil, nil
	self.towns:_with(userId, function(s: any)
		s.tick(self.mods.now())
		if v.kind == "barn" and #(s.junkyard or {}) >= self.mods.data.STORAGE_MAX then
			s.toast("Storage is full. Restore or scrap a car first, then call Rusty back.")
			err = "storage full"
			return
		end
		out = self:_pay(s, v)
	end)
	return out, err
end

-- Sends the visitor on their way (No thanks, or their time ran out): nothing more to claim.
function Visitors.leave(self: Visitors, userId: number, id: any): boolean
	local v = self.cur[userId]
	if type(id) ~= "string" or not v or v.id ~= id then
		return false
	end
	v.done = true
	return true
end

-- The street racer `id`, for a street race against them: once only, while they're in town.
function Visitors.startStreet(self: Visitors, userId: number, id: any): (Visit?, string?)
	local v = self:current(userId)
	if type(id) ~= "string" or not v or v.id ~= id or v.kind ~= "racer" then
		return nil, "Your visitor already left town."
	end
	if v.raced then
		return nil, "You already raced them"
	end
	v.raced = true
	return v, nil
end

-- The street race against `id` is over (Race.tsx's street onFinish): a win collects their bonus
-- (as claimVisitor), a loss sends them off laughing. Run inside the town (`s`). Returns what the
-- bonus paid, or nil.
function Visitors.finishStreet(self: Visitors, s: any, userId: number, id: string, won: boolean): any?
	local v = self.cur[userId]
	if not v or v.id ~= id or v.kind ~= "racer" or v.done then
		return nil
	end
	local store = self.mods.store.useGame.getState
	if not won then
		v.done = true
		store().toast(`{string.split(v.name, " from ")[1]} smoked you and drove off laughing.`)
		return nil
	end
	local t = self.mods.now()
	if t > v.expiresAt + Visitors.GRACE_MS or t < v.createdAt + Visitors.RACE_FIRST_MS then
		v.done = true
		store().toast("Your visitor already left town.")
		return nil
	end
	return self:_pay(s, v)
end

-- The street rival's card for server/Races, as Race.tsx's street race makes it.
function Visitors.rival(self: Visitors, v: Visit): any
	local def = self.mods.data.carDef(v.model)
	return {
		id = `street-{v.id}`,
		name = v.name,
		carName = def.name,
		model = v.model,
		color = v.color,
		pi = v.pi,
		shift = 1,
		skill = def.skill,
		-- Race.tsx reward(): the race's own prize, paid by finishRace.
		prize = math.floor(150 + v.pi * 6 + 0.5),
		street = { coins = v.coins, parts = v.parts, bucks = v.bucks },
	}
end

function Visitors.close(self: Visitors, userId: number)
	self.cur[userId] = nil
	self.recs[userId] = nil
end

return Visitors
