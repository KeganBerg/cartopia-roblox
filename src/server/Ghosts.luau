--!strict
-- Ghost races (lib/ghosts.ts, ui/GhostRace.tsx, supabase/migrations/0030_friend_ghosts.sql and
-- 0068_friendly_taunts.sql): race the ghost of another player's best run, then leave them a
-- preset taunt they see the next time they play.
--
--   * A player's ghost is their fastest server-kept time, from ghost races or any weekly Time
--     Trial. Players with no time yet race as a par time for their best car.
--   * Taunts come from a fixed list (TAUNTS): no free text reaches another player. Brag taunts
--     only after a win. One taunt per run, 3 a day to the same player and 20 a day in all.
--
-- In Roblox each player's ghost is a row in the "Ghosts_v1" DataStore (their best, the car it was
-- set in, and a card of their best car for the par), and their taunts waiting to be read are in
-- "GhostTaunts_v1". Without DataStores (tests, the emulator) both live in memory.

local Ghosts = {}
Ghosts.__index = Ghosts

-- The preset taunts (ghosts.ts TAUNTS), friendliest first. Brag ones need a win.
Ghosts.TAUNTS = {
	{ id = 10, text = "GG! 🤝" },
	{ id = 14, text = "Nice race! 👏" },
	{ id = 11, text = "Rematch? 🔁" },
	{ id = 12, text = "You're quick! ⚡" },
	{ id = 13, text = "I'll be back 😤" },
	{ id = 0, text = "Eat my dust! 💨", brag = true },
	{ id = 1, text = "Too slow! 🐢", brag = true },
	{ id = 2, text = "Nice try, rookie 😎", brag = true },
	{ id = 3, text = "See you at the finish line 🏁", brag = true },
	{ id = 4, text = "Your ghost needs a tune-up 🔧", brag = true },
	{ id = 5, text = "Catch me if you can 🏎️", brag = true },
}

-- 0030: a taunt goes within 10 minutes of the run; 3 a day to one player, 20 a day in all; the
-- inbox keeps a week of taunts, 20 at most.
local TAUNT_WINDOW = 10 * 60
local PER_FRIEND = 3
local PER_DAY = 20
local INBOX_DAYS = 7
local INBOX_MAX = 20
-- How long a read stays fresh, in seconds.
local FRESH = 30

export type Card = { car: string, model: string, color: string, pi: number, town: string }
-- What racing a player's ghost looks like (ghost_of): its time (nil: no car yet), whether it's a
-- par, and the car.
export type Ghost = { owner: number, t: number?, par: boolean, car: string, model: string, color: string, pi: number, town: string }
export type Taunt = { id: number, from: number, town: string, taunt: number, won: boolean, t: number, their: number?, at: number }

export type Backend = {
	-- The ghosts' and the taunt inboxes' DataStores.
	ghosts: any,
	taunts: any,
}

type Last = { vs: number, t: number, their: number?, won: boolean, at: number, taunted: boolean }

export type Ghosts = typeof(setmetatable(
	{} :: {
		backend: Backend?,
		clock: () -> number,
		mem: { [number]: any },
		inboxes: { [number]: any },
		cache: { [number]: { at: number, value: any } },
		last: { [number]: Last },
	},
	Ghosts
))

-- backend: DataStores, or nil to keep everything in memory; clock: seconds since 1970 (os.time).
function Ghosts.new(backend: Backend?, clock: () -> number): Ghosts
	return setmetatable({ backend = backend, clock = clock, mem = {}, inboxes = {}, cache = {}, last = {} }, Ghosts)
end

function Ghosts.tauntText(id: number): string
	for _, t in Ghosts.TAUNTS do
		if t.id == id then
			return t.text
		end
	end
	return "👻"
end

local function day(at: number): number
	return at // 86400
end

-- A row from one of the stores, through `update(row) -> row` when given (UpdateAsync), else read.
function Ghosts._row(self: Ghosts, which: "ghosts" | "taunts", userId: number, update: ((any) -> any)?): any
	local b = self.backend
	if not b then
		local mem = if which == "ghosts" then self.mem else self.inboxes
		if update then
			mem[userId] = update(mem[userId])
		end
		return mem[userId]
	end
	local store = b[which]
	local ok, v = pcall(function()
		if update then
			return store:UpdateAsync(tostring(userId), function(old: any)
				return update(old)
			end)
		end
		return store:GetAsync(tostring(userId))
	end)
	return if ok then v else nil
end

-- A player's ghost row, cached for a short while (others' rows are read often from the menu).
function Ghosts._ghostRow(self: Ghosts, userId: number): any
	local c = self.cache[userId]
	local now = self.clock()
	if c and now - c.at < FRESH then
		return c.value
	end
	local v = self:_row("ghosts", userId)
	self.cache[userId] = { at = now, value = v }
	return v
end

function Ghosts._update(self: Ghosts, userId: number, f: (any) -> any): any
	local v = self:_row("ghosts", userId, function(old: any)
		return f(if type(old) == "table" then old else {})
	end)
	self.cache[userId] = { at = self.clock(), value = v }
	return v
end

-- Keeps a player's best car (their par, while they have no time) and town name up to date.
function Ghosts.card(self: Ghosts, userId: number, card: Card)
	local row = self:_ghostRow(userId)
	local old = if type(row) == "table" then row.card else nil
	if type(old) == "table" and old.car == card.car and old.model == card.model and old.color == card.color and old.pi == card.pi and old.town == card.town then
		return
	end
	self:_update(userId, function(r: any)
		r.card = card
		return r
	end)
end

-- A player's best server-kept time (nil: none yet).
function Ghosts.best(self: Ghosts, userId: number): number?
	local row = self:_ghostRow(userId)
	return if type(row) == "table" and type(row.t) == "number" then row.t else nil
end

-- A new server-kept time (a ghost race or a Time Trial run): kept if it's the player's best.
function Ghosts.record(self: Ghosts, userId: number, t: number, pi: number, car: string, model: string, color: string)
	local best = self:best(userId)
	if best and best <= t then
		return
	end
	self:_update(userId, function(r: any)
		if type(r.t) ~= "number" or t < r.t then
			r.t, r.pi, r.car, r.model, r.color, r.setAt = t, pi, string.sub(car, 1, 40), model, color, self.clock()
		end
		return r
	end)
end

-- What a player's ghost runs (ghost_of): their best, or a par for their best car. raceFloor: the
-- referee's fastest legal time for a PI (race.ts raceFloor), for the par. Nil: they've never
-- played, or have no car.
function Ghosts.of(self: Ghosts, userId: number, raceFloor: (number) -> number): Ghost?
	local row = self:_ghostRow(userId)
	if type(row) ~= "table" then
		return nil
	end
	local card = if type(row.card) == "table" then row.card else {}
	if type(row.t) == "number" then
		return {
			owner = userId,
			t = row.t,
			par = false,
			car = row.car or card.car or "Mystery car",
			model = row.model or card.model or "pip",
			color = row.color or card.color or "#eceff1",
			pi = row.pi or card.pi or 0,
			town = card.town or "Racer",
		}
	end
	if type(card.pi) ~= "number" then
		return nil
	end
	return {
		owner = userId,
		t = math.round(raceFloor(card.pi) * 1.3 * 100) / 100,
		par = true,
		car = card.car or "Mystery car",
		model = card.model or "pip",
		color = card.color or "#eceff1",
		pi = card.pi,
		town = card.town or "Racer",
	}
end

-- A finished ghost race: what a taunt from it would be about.
function Ghosts.finished(self: Ghosts, userId: number, vs: number, t: number, their: number?, won: boolean)
	self.last[userId] = { vs = vs, t = t, their = their, won = won, at = self.clock(), taunted = false }
end

-- Leaves a preset taunt for the player from the last run (ghost_taunt): "sent", "limit" or "no".
function Ghosts.taunt(self: Ghosts, userId: number, taunt: any, town: string): string
	local last = self.last[userId]
	local now = self.clock()
	if type(taunt) ~= "number" or not last or last.taunted or now - last.at > TAUNT_WINDOW then
		return "no"
	end
	local def = nil
	for _, t in Ghosts.TAUNTS do
		if t.id == taunt then
			def = t
		end
	end
	if not def or (def.brag and not last.won) then
		return "no"
	end
	-- Today's count, in the sender's own row.
	local today = day(now)
	local over = false
	self:_update(userId, function(r: any)
		local sent = if type(r.sent) == "table" and r.sent.day == today then r.sent else { day = today, n = 0, to = {} }
		local key = tostring(last.vs)
		if sent.n >= PER_DAY or (sent.to[key] or 0) >= PER_FRIEND then
			over = true
			return r
		end
		sent.n += 1
		sent.to[key] = (sent.to[key] or 0) + 1
		r.sent = sent
		return r
	end)
	if over then
		return "limit"
	end
	last.taunted = true
	self:_row("taunts", last.vs, function(old: any)
		local box = if type(old) == "table" then old else { next = 1, list = {} }
		table.insert(box.list, 1, { id = box.next, from = userId, town = town, taunt = taunt, won = last.won, t = last.t, their = last.their, at = now })
		box.next += 1
		while #box.list > INBOX_MAX do
			table.remove(box.list)
		end
		return box
	end)
	return "sent"
end

-- Taunts waiting for a player from the last week, newest first (taunt_inbox).
function Ghosts.inbox(self: Ghosts, userId: number): { Taunt }
	local box = self:_row("taunts", userId)
	local out = {}
	local now = self.clock()
	if type(box) == "table" and type(box.list) == "table" then
		for _, t in box.list do
			if now - (t.at or 0) <= INBOX_DAYS * 86400 then
				table.insert(out, t)
			end
		end
	end
	return out
end

-- Clears taunts once they've been read (taunts_seen).
function Ghosts.seen(self: Ghosts, userId: number, ids: any)
	if type(ids) ~= "table" or #ids == 0 then
		return
	end
	local gone = {}
	for _, id in ids do
		if type(id) == "number" then
			gone[id] = true
		end
	end
	self:_row("taunts", userId, function(old: any)
		if type(old) ~= "table" or type(old.list) ~= "table" then
			return old
		end
		local keep = {}
		for _, t in old.list do
			if not gone[t.id] then
				table.insert(keep, t)
			end
		end
		old.list = keep
		return old
	end)
end

return Ghosts
