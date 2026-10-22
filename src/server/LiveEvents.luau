--!strict
-- Live events on the server, as the web game's live_events table (supabase/migrations/
-- 0055_live_events.sql, 0095_admin_panel.sql's admin_live_start / admin_live_end) and
-- lib/liveEventsSync.ts: switches for every player in every server at once, started and ended
-- from the admin panel (server/Admin, the owner only). Kinds, as the web's:
--   night / day   pins the town clock (game/liveEvents.ts forcedPhase)
--   rave          Rave Mode in every town (game/techno.ts)
--   weather       one sky for everyone (payload.kind, game/weather.ts)
--   banner        a message pinned on every screen (client/LiveBanner.luau)
-- Any of them may carry payload.message, shown once as a toast when it starts.
--
-- The list lives in a DataStore (so a server that starts later, or misses a message, still
-- picks it up: every server re-reads it once a minute, as the web's slow poll) and each change is
-- sent to every running server through MessagingService, which applies the same change, so
-- players switch within seconds. If either is down this server still runs its own events, in
-- memory. Players see the list through Workspace's LiveEvents attribute: JSON, server clock, ms.

local LiveEvents = {}
LiveEvents.__index = LiveEvents

LiveEvents.KINDS = { night = true, day = true, rave = true, weather = true, banner = true }
LiveEvents.WEATHER = { clear = true, rain = true, storm = true, drizzle = true, fog = true, wind = true, snow = true, blizzard = true, mist = true, heat = true }
LiveEvents.MAX_MINUTES = 1440
LiveEvents.MAX_MESSAGE = 120
-- How long an ended event stays in the list, so the sky can ease back (liveEvents.ts EASE_MS is 8s).
LiveEvents.KEEP_MS = 60000

export type Event = { id: number, kind: string, payload: { [string]: any }, from: number, to: number }
-- A change to the list, the same in every server: an event started, or events ended.
export type Change = { op: "start", e: Event } | { op: "end", kind: string?, at: number }

export type Mods = {
	now: () -> number,
	random: () -> number,
	-- The stored list, changed by fn (DataStore UpdateAsync); nil if it can't be reached.
	update: ((list: { Event }) -> { Event }) -> { Event }?,
	-- Reads the stored list; nil if it can't be reached.
	read: () -> { Event }?,
	-- Sends a change to every other server.
	publish: (change: Change) -> (),
	-- Shows the list to the players here.
	show: (list: { Event }) -> (),
	-- Roblox's text filter on the owner's message for everyone, or nil if it can't be shown.
	filter: (userId: number, text: string) -> string?,
}

export type LiveEvents = typeof(setmetatable({} :: { mods: Mods, list: { Event }, seq: number }, LiveEvents))

function LiveEvents.new(mods: Mods): LiveEvents
	return setmetatable({ mods = mods, list = {}, seq = 0 }, LiveEvents)
end

-- An event ended at `at`: it stops there, and started at least a second before (as the SQL does).
local function cut(e: Event, at: number)
	e.to = at
	e.from = math.min(e.from, at - 1000)
end

-- Applies a change to a list (a copy), dropping events long over. Returns it and how many ended.
function LiveEvents.apply(list: { Event }, change: Change, now: number): ({ Event }, number)
	local out: { Event } = {}
	local n = 0
	for _, e in list do
		if type(e) == "table" and type(e.to) == "number" and e.to > now - LiveEvents.KEEP_MS then
			table.insert(out, table.clone(e))
		end
	end
	if change.op == "start" then
		local new = change.e
		local at = new.from
		-- live_event_start: a new one ends the running one of its kind; night and day end each other.
		local clock = new.kind == "night" or new.kind == "day"
		for _, e in out do
			if e.from <= at and e.to > at and (e.kind == new.kind or (clock and (e.kind == "night" or e.kind == "day"))) then
				cut(e, at)
			end
		end
		local seen = false
		for _, e in out do
			seen = seen or e.id == new.id
		end
		if not seen then
			table.insert(out, table.clone(new))
		end
	elseif change.op == "end" then
		for _, e in out do
			if e.to > change.at and (change.kind == nil or e.kind == change.kind) then
				cut(e, change.at)
				n += 1
			end
		end
	end
	table.sort(out, function(a, b)
		return a.from < b.from
	end)
	return out, n
end

-- Only well-formed events from the store or another server.
local function clean(list: any): { Event }
	local out: { Event } = {}
	if type(list) ~= "table" then
		return out
	end
	for _, e in list do
		if type(e) == "table" and type(e.id) == "number" and type(e.kind) == "string" and LiveEvents.KINDS[e.kind]
			and type(e.from) == "number" and type(e.to) == "number" and e.to - e.from <= LiveEvents.MAX_MINUTES * 60000 + 1000 then
			local payload: { [string]: any } = {}
			if type(e.payload) == "table" then
				if type(e.payload.message) == "string" then
					payload.message = string.sub(e.payload.message, 1, LiveEvents.MAX_MESSAGE)
				end
				if type(e.payload.kind) == "string" and LiveEvents.WEATHER[e.payload.kind] then
					payload.kind = e.payload.kind
				end
				payload.by = "admin"
			end
			table.insert(out, { id = e.id, kind = e.kind, payload = payload, from = e.from, to = e.to })
		end
	end
	return out
end
LiveEvents.clean = clean

-- The events running now or just over: what players are shown.
function LiveEvents.current(self: LiveEvents): { Event }
	local now = self.mods.now()
	local out = {}
	for _, e in self.list do
		if e.to > now - LiveEvents.KEEP_MS then
			table.insert(out, e)
		end
	end
	return out
end

-- Makes a change here, in the store and in every other server.
function LiveEvents._change(self: LiveEvents, change: Change): number
	local m = self.mods
	local now = m.now()
	local n: number
	self.list, n = LiveEvents.apply(self.list, change, now)
	m.update(function(stored: { Event })
		return (LiveEvents.apply(clean(stored), change, now))
	end)
	m.publish(change)
	m.show(self:current())
	return n
end

-- admin_live_start: an event of `kind` for `minutes` from now. Returns its id, or nil and why.
-- The caller is checked by server/Admin (the owner only) before this is reached.
function LiveEvents.start(self: LiveEvents, userId: number, kind: any, minutes: any, payload: any): (number?, string?)
	if type(kind) ~= "string" or not LiveEvents.KINDS[kind] then
		return nil, "bad kind"
	end
	if type(minutes) ~= "number" or minutes ~= math.floor(minutes) or minutes < 1 or minutes > LiveEvents.MAX_MINUTES then
		return nil, "bad minutes"
	end
	payload = if type(payload) == "table" then payload else {}
	local out: { [string]: any } = { by = "admin" }
	if kind == "weather" then
		local sky = payload.kind
		if type(sky) ~= "string" or not LiveEvents.WEATHER[sky] then
			return nil, "bad weather"
		end
		out.kind = sky
	end
	local msg = if type(payload.message) == "string" then string.sub(string.match(payload.message, "^%s*(.-)%s*$") or "", 1, LiveEvents.MAX_MESSAGE) else ""
	if kind == "banner" and msg == "" then
		return nil, "empty"
	end
	if msg ~= "" then
		local shown = self.mods.filter(userId, msg)
		if not shown or shown ~= msg then
			return nil, "not allowed words"
		end
		out.message = msg
	end
	local now = self.mods.now()
	-- Unique enough across servers (the millisecond, a random part and this server's count), and
	-- small enough to stay exact in JSON.
	self.seq += 1
	local id = (now % 1e9) * 1000 + (math.floor(self.mods.random() * 1000) + self.seq) % 1000
	self:_change({ op = "start", e = { id = id, kind = kind, payload = out, from = now, to = now + minutes * 60000 } })
	return id, nil
end

-- admin_live_end: ends the running events of one kind, or all of them (nil). Returns how many.
function LiveEvents.finish(self: LiveEvents, kind: any): (number?, string?)
	if kind ~= nil and (type(kind) ~= "string" or not LiveEvents.KINDS[kind]) then
		return nil, "bad kind"
	end
	return self:_change({ op = "end", kind = kind, at = self.mods.now() }), nil
end

-- A change from another server.
function LiveEvents.received(self: LiveEvents, change: any)
	if type(change) ~= "table" then
		return
	end
	local now = self.mods.now()
	if change.op == "start" then
		local e = clean({ change.e })[1]
		if not e then
			return
		end
		self.list = LiveEvents.apply(self.list, { op = "start", e = e }, now)
	elseif change.op == "end" and type(change.at) == "number" and (change.kind == nil or LiveEvents.KINDS[change.kind]) then
		self.list = LiveEvents.apply(self.list, { op = "end", kind = change.kind, at = change.at }, now)
	else
		return
	end
	self.mods.show(self:current())
end

-- Re-reads the stored list (on start, then once a minute). Keeps what's here when it can't.
function LiveEvents.refresh(self: LiveEvents)
	local read = self.mods.read()
	if not read then
		return
	end
	local now = self.mods.now()
	local list = clean(read)
	-- Events this server ended (or heard ended) that the store hasn't caught up with yet keep
	-- their end.
	local mine: { [number]: Event } = {}
	for _, e in self.list do
		mine[e.id] = e
	end
	local stored: { [number]: boolean } = {}
	for _, e in list do
		stored[e.id] = true
		local here = mine[e.id]
		if here and here.to < e.to then
			e.to, e.from = here.to, here.from
		end
	end
	-- Ones the store missed (it was down when they started) carry on here.
	for id, e in mine do
		if not stored[id] then
			table.insert(list, e)
		end
	end
	self.list = LiveEvents.apply(list, { op = "end", kind = "none", at = now }, now)
	self.mods.show(self:current())
end

-- Wires it up in Roblox: the DataStore, MessagingService and Workspace's attribute.
function LiveEvents.roblox(): LiveEvents
	local HttpService = game:GetService("HttpService")
	local MessagingService = game:GetService("MessagingService")
	local TextService = game:GetService("TextService")
	local TOPIC = "CartopiaLive"
	local KEY = "live"
	local store: any = nil
	pcall(function()
		store = game:GetService("DataStoreService"):GetDataStore("LiveEvents_v1")
	end)
	local live: LiveEvents
	live = LiveEvents.new({
		now = function(): number
			return DateTime.now().UnixTimestampMillis
		end,
		random = math.random,
		update = function(fn)
			if not store then
				return nil
			end
			local ok, result = pcall(function()
				return store:UpdateAsync(KEY, function(old: any)
					return fn(if type(old) == "table" then old else {})
				end)
			end)
			return if ok then result else nil
		end,
		read = function()
			if not store then
				return nil
			end
			local ok, result = pcall(function()
				return store:GetAsync(KEY)
			end)
			return if ok then (if type(result) == "table" then result else {}) else nil
		end,
		publish = function(change)
			task.spawn(pcall, function()
				MessagingService:PublishAsync(TOPIC, change)
			end)
		end,
		show = function(list)
			local ok, json = pcall(HttpService.JSONEncode, HttpService, list)
			workspace:SetAttribute("LiveEvents", if ok then json else "[]")
		end,
		filter = function(userId: number, text: string): string?
			local ok, result = pcall(function()
				return TextService:FilterStringAsync(text, userId):GetNonChatStringForBroadcastAsync()
			end)
			return if ok then result else nil
		end,
	})
	workspace:SetAttribute("LiveEvents", "[]")
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(msg: any)
				live:received(msg.Data)
			end)
		end)
	end)
	task.spawn(function()
		while true do
			live:refresh()
			task.wait(60)
		end
	end)
	return live
end

return LiveEvents
