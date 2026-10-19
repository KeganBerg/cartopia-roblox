--!strict
-- Friends' mail (the web game's lib/gifts.ts and lib/postcards.ts, supabase/migrations
-- 0025_friend_gifts.sql and 0070_postcards_crew_parts.sql):
--   * Helping someone's town leaves them a note worth 10 fuel: one per town a day, 30 a day.
--   * A gift of 15 fuel or 5 parts: one per friend a day, 10 a day.
--   * Notes wait until their owner collects them, oldest first, 10 paid a day; the rest wait.
--   * A postcard: one of six pictures and one of eight set messages (no free text), one per
--     friend a day, 20 a day. The last 14 days' cards show in the mail.
--
-- In Roblox a player's mail is kept in "Mail_v1" (by owner) and what they've sent today in
-- "MailSent_v1" (by sender), both changed with UpdateAsync so two servers can't both spend or pay
-- the same thing. Without DataStores (tests, the emulator) everything lives in memory.

local Mail = {}
Mail.__index = Mail

Mail.HELP_FUEL = 10
Mail.GIFTS = { fuel = 15, parts = 5 }
Mail.GIFTS_PER_DAY = 10
Mail.HELPS_PER_DAY = 30
Mail.CLAIMS_PER_DAY = 10
Mail.CARDS_PER_DAY = 20
Mail.CARDS = { "sunset", "neon", "beach", "snow", "flag", "garage" }
Mail.MESSAGES = 8
local KEEP_NOTES = 50
local KEEP_CARDS = 40
local CARD_DAYS = 14

export type Backend = { plain: (name: string) -> any }

export type Mail = typeof(setmetatable(
	{} :: {
		backend: Backend?,
		clock: () -> number,
		today: () -> string,
		mem: { [string]: { [string]: any } },
	},
	Mail
))

-- clock: seconds (os.time); today: today's date key (UTC), for the daily limits.
function Mail.new(backend: Backend?, clock: () -> number, today: () -> string): Mail
	return setmetatable({ backend = backend, clock = clock, today = today, mem = {} }, Mail)
end

function Mail._get(self: Mail, store: string, key: string): any
	local b = self.backend
	if not b then
		return (self.mem[store] or {})[key]
	end
	local ok, v = pcall(function()
		return b.plain(store):GetAsync(key)
	end)
	return if ok then v else nil
end

-- Changes a stored value in one step (UpdateAsync). fn returns the new value, or nil to leave it.
-- True when the store took it (or nothing needed writing).
function Mail._update(self: Mail, store: string, key: string, fn: (any) -> any): boolean
	local b = self.backend
	if not b then
		self.mem[store] = self.mem[store] or {}
		local v = fn(self.mem[store][key])
		if v ~= nil then
			self.mem[store][key] = v
		end
		return true
	end
	return (pcall(function()
		b.plain(store):UpdateAsync(key, fn)
	end))
end

-- Counts a send against the sender's day: "ok", "already" (this one, to them, today) or "limit".
function Mail._spend(self: Mail, from: number, to: number, kind: string, perDay: number): string
	local today = self.today()
	local result = "no"
	local ok = self:_update("MailSent_v1", tostring(from), function(old: any): any
		local v = if type(old) == "table" and old.day == today then old else { day = today }
		local sent = v[kind] or {}
		if sent[tostring(to)] then
			result = "already"
			return nil
		end
		local n = 0
		for _ in sent do
			n += 1
		end
		if n >= perDay then
			result = "limit"
			return nil
		end
		sent = table.clone(sent)
		sent[tostring(to)] = true
		v = table.clone(v)
		v[kind] = sent
		result = "ok"
		return v
	end)
	return if ok then result else "no"
end

-- Puts an entry in someone's mail ("notes" or "cards").
function Mail._deliver(self: Mail, to: number, list: string, entry: any): boolean
	return self:_update("Mail_v1", tostring(to), function(old: any): any
		local v: any = if type(old) == "table" then table.clone(old) else {}
		local items = table.clone(v[list] or {})
		v.next = (v.next or 0) + 1
		local e = table.clone(entry)
		e.id = v.next
		table.insert(items, e)
		local keep = if list == "notes" then KEEP_NOTES else KEEP_CARDS
		while #items > keep do
			table.remove(items, 1)
		end
		v[list] = items
		return v
	end)
end

local function from(self: Mail, userId: number, name: string, town: string): any
	return { from = userId, name = name, town = town, at = self.clock() }
end

-- A note for the owner of a town the player just helped. True when it was left.
function Mail.help(self: Mail, helper: number, name: string, town: string, owner: number): boolean
	if helper == owner or owner <= 0 then
		return false
	end
	if self:_spend(helper, owner, "helps", Mail.HELPS_PER_DAY) ~= "ok" then
		return false
	end
	local e = from(self, helper, name, town)
	e.kind, e.amount = "help", Mail.HELP_FUEL
	return self:_deliver(owner, "notes", e)
end

-- Today's gift for a friend: item "fuel" or "parts". "sent", "already", "limit" or "no".
function Mail.gift(self: Mail, sender: number, name: string, town: string, to: number, item: string): string
	local amount = Mail.GIFTS[item]
	if sender == to or to <= 0 or not amount then
		return "no"
	end
	local r = self:_spend(sender, to, "gifts", Mail.GIFTS_PER_DAY)
	if r ~= "ok" then
		return r
	end
	local e = from(self, sender, name, town)
	e.kind, e.amount = item, amount
	return if self:_deliver(to, "notes", e) then "sent" else "no"
end

-- A postcard: card one of Mail.CARDS, msg 0 to 7. "sent", "already", "limit" or "no".
function Mail.postcard(self: Mail, sender: number, name: string, town: string, to: number, card: string, msg: number): string
	if sender == to or to <= 0 or not table.find(Mail.CARDS, card) or msg ~= math.floor(msg) or msg < 0 or msg >= Mail.MESSAGES then
		return "no"
	end
	local r = self:_spend(sender, to, "cards", Mail.CARDS_PER_DAY)
	if r ~= "ok" then
		return r
	end
	local e = from(self, sender, name, town)
	e.card, e.msg = card, msg
	return if self:_deliver(to, "cards", e) then "sent" else "no"
end

-- Who the player has sent a gift and a postcard today: { gifts = { [id] = true }, cards = ... }.
function Mail.sentToday(self: Mail, sender: number): any
	local v = self:_get("MailSent_v1", tostring(sender))
	if type(v) ~= "table" or v.day ~= self.today() then
		return { gifts = {}, cards = {} }
	end
	return { gifts = v.gifts or {}, cards = v.cards or {} }
end

-- The player's mail: notes and the last 14 days' postcards, newest first, and the newest card
-- they've looked at.
function Mail.inbox(self: Mail, userId: number): any
	local v = self:_get("Mail_v1", tostring(userId))
	if type(v) ~= "table" then
		v = {}
	end
	local notes, cards = {}, {}
	for i = #(v.notes or {}), 1, -1 do
		table.insert(notes, v.notes[i])
	end
	local since = self.clock() - CARD_DAYS * 86400
	for i = #(v.cards or {}), 1, -1 do
		local c = v.cards[i]
		if (c.at or 0) >= since then
			table.insert(cards, c)
		end
	end
	return { notes = notes, cards = cards, seen = v.seen or 0 }
end

-- How many things are waiting: notes, and postcards newer than the last one looked at.
function Mail.count(self: Mail, userId: number): number
	local box = self:inbox(userId)
	local n = #box.notes
	for _, c in box.cards do
		if c.id > box.seen then
			n += 1
		end
	end
	return n
end

-- Marks every postcard as looked at.
function Mail.see(self: Mail, userId: number)
	self:_update("Mail_v1", tostring(userId), function(old: any): any
		if type(old) ~= "table" or not old.cards or #old.cards == 0 then
			return nil
		end
		local top = old.cards[#old.cards].id
		if (old.seen or 0) >= top then
			return nil
		end
		local v = table.clone(old)
		v.seen = top
		return v
	end)
end

-- Collects waiting notes, oldest first, up to 10 a day: { fuel, parts, count, left }.
function Mail.claim(self: Mail, userId: number): any
	local today = self.today()
	local got = { fuel = 0, parts = 0, count = 0, left = 0 }
	local ok = self:_update("Mail_v1", tostring(userId), function(old: any): any
		got = { fuel = 0, parts = 0, count = 0, left = 0 }
		if type(old) ~= "table" or not old.notes or #old.notes == 0 then
			return nil
		end
		local v = table.clone(old)
		local used = if v.claimDay == today then v.claimed or 0 else 0
		local room = math.max(0, Mail.CLAIMS_PER_DAY - used)
		local rest = {}
		for _, n in old.notes do
			if got.count < room then
				got.count += 1
				if n.kind == "parts" then
					got.parts += n.amount
				else
					got.fuel += n.amount
				end
			else
				table.insert(rest, n)
			end
		end
		got.left = #rest
		if got.count == 0 then
			return nil
		end
		v.notes = rest
		v.claimDay, v.claimed = today, used + got.count
		return v
	end)
	if not ok then
		return { fuel = 0, parts = 0, count = 0, left = 0 }
	end
	return got
end

return Mail
