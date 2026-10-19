--!strict
-- Live drag races between two players in this server, as the web game's live challenges
-- (lib/live.ts, ui/ChallengeBell.tsx and the referee in 0009_live_race_referee.sql).
--
-- A player challenges another from the Race menu's Live page or the Social menu. The challenge
-- waits in the other player's 🏁 bell for INVITE seconds; Accept starts the race for both. Each
-- game races its own car (Shared.DragRace, the race mode "live" in server/Modes) and sends where
-- its car is a few times a second, which the server passes to the other to draw their car. At
-- the line each sends its presses; the server races each run again from them, and the faster
-- run wins (the other has WAIT seconds to finish, or loses). The winner gets the web's live prize.

local Duels = {}
Duels.__index = Duels

Duels.INVITE = 45 -- seconds a challenge stays open
Duels.WAIT = 25 -- seconds to wait for the other racer's finish
Duels.COOLDOWN = 20 -- seconds before challenging the same player again after a no
Duels.RELAY_RATE = 30 -- position messages a second a racer may send
Duels.LONGEST = 120 -- seconds after which a race nobody finished is over (a game that hung)

export type Mods = {
	clock: () -> number,
	-- Sends one player's game a message: (userId, event, payload).
	send: (userId: number, event: string, payload: any) -> (),
	-- What another player sees of a racer: { name, town, level, carName, model, color, pi, ... }.
	card: (userId: number) -> any?,
	-- Whether a player is in this server with a town to race from.
	here: (userId: number) -> boolean,
	-- Waits a moment (task.wait in the game).
	wait: (s: number) -> (),
}

type Invite = { id: string, from: number, to: number, at: number }
type Race = { id: string, a: number, b: number, at: number, times: { [number]: number }, started: { [number]: boolean } }

export type Duels = typeof(setmetatable(
	{} :: {
		mods: Mods,
		seq: number,
		invites: { [string]: Invite },
		races: { [string]: Race },
		of: { [number]: string },
		cool: { [string]: number },
		budget: { [number]: { n: number, at: number } },
	},
	Duels
))

function Duels.new(mods: Mods): Duels
	return setmetatable({ mods = mods, seq = 0, invites = {}, races = {}, of = {}, cool = {}, budget = {} }, Duels)
end

-- Drops challenges that have run out.
function Duels._prune(self: Duels)
	local now = self.mods.clock()
	for id, inv in self.invites do
		if now - inv.at > Duels.INVITE then
			self.invites[id] = nil
		end
	end
end

-- The challenges waiting for a player, newest first, each with who sent it.
function Duels.invitesFor(self: Duels, userId: number): { any }
	self:_prune()
	local now = self.mods.clock()
	local out = {}
	for _, inv in self.invites do
		if inv.to == userId then
			local card = self.mods.card(inv.from) or {}
			local row = table.clone(card)
			row.id, row.from, row.left = inv.id, inv.from, math.max(0, math.ceil(Duels.INVITE - (now - inv.at)))
			table.insert(out, row)
		end
	end
	table.sort(out, function(x, y)
		return x.left > y.left
	end)
	return out
end

-- Tells a player's game what's waiting in their bell.
function Duels._tell(self: Duels, userId: number)
	self.mods.send(userId, "invites", self:invitesFor(userId))
end

-- The challenge a player has out, if any.
function Duels._outgoing(self: Duels, userId: number): Invite?
	for _, inv in self.invites do
		if inv.from == userId then
			return inv
		end
	end
	return nil
end

-- The other players here a player could race (the Live page's list): each one's card with id,
-- closed (already in a live race), wait (said no a moment ago) and asked (this player's challenge
-- out to them). ids: everyone in the server.
function Duels.others(self: Duels, userId: number, ids: { number }): { any }
	self:_prune()
	local now = self.mods.clock()
	local out = self:_outgoing(userId)
	local list = {}
	for _, id in ids do
		if id ~= userId and self.mods.here(id) then
			local row = table.clone(self.mods.card(id) or {})
			row.id = id
			row.closed = self.of[id] ~= nil
			row.wait = (self.cool[`{userId}>{id}`] or -math.huge) > now
			row.asked = out ~= nil and out.to == id
			table.insert(list, row)
		end
	end
	table.sort(list, function(x, y)
		return (x.pi or 0) > (y.pi or 0)
	end)
	return list
end

-- Challenges another player here. Returns the challenge's id, or nil and why not.
function Duels.challenge(self: Duels, from: number, to: number): (string?, string?)
	self:_prune()
	if from == to then
		return nil, "no"
	end
	if not self.mods.here(to) then
		return nil, "not here"
	end
	if self.of[from] or self.of[to] then
		return nil, "racing"
	end
	local key = `{from}>{to}`
	if (self.cool[key] or -math.huge) > self.mods.clock() then
		return nil, "wait"
	end
	-- One challenge out at a time: a new one replaces the last.
	local old = self:_outgoing(from)
	if old then
		self.invites[old.id] = nil
		self:_tell(old.to)
	end
	self.seq += 1
	local id = `duel-{from}-{self.seq}`
	self.invites[id] = { id = id, from = from, to = to, at = self.mods.clock() }
	self:_tell(to)
	return id, nil
end

-- Calls off the player's challenge (the Cancel on the waiting card).
function Duels.cancel(self: Duels, from: number)
	local inv = self:_outgoing(from)
	if inv then
		self.invites[inv.id] = nil
		self:_tell(inv.to)
	end
end

-- Answers a challenge. Accepting starts the race for both: each game gets "go" with the race's id
-- and the other racer. Returns the race id, or nil and why not.
function Duels.answer(self: Duels, userId: number, id: string, accept: boolean): (string?, string?)
	self:_prune()
	local inv = self.invites[id]
	if not inv or inv.to ~= userId then
		return nil, "expired"
	end
	self.invites[id] = nil
	if not accept then
		self.cool[`{inv.from}>{inv.to}`] = self.mods.clock() + Duels.COOLDOWN
		self.mods.send(inv.from, "declined", { id = id })
		self:_tell(userId)
		return nil, "declined"
	end
	if self.of[inv.from] or self.of[userId] or not self.mods.here(inv.from) then
		self:_tell(userId)
		return nil, "racing"
	end
	-- Anything else either of them had waiting, sent or got, goes.
	for other, o in self.invites do
		if o.from == inv.from or o.from == userId or o.to == inv.from or o.to == userId then
			self.invites[other] = nil
			self:_tell(o.to)
		end
	end
	local race: Race = { id = id, a = inv.from, b = userId, at = self.mods.clock(), times = {}, started = {} }
	self.races[id] = race
	self.of[inv.from], self.of[userId] = id, id
	self.mods.send(inv.from, "go", { id = id, vs = userId, card = self.mods.card(userId) })
	self.mods.send(userId, "go", { id = id, vs = inv.from, card = self.mods.card(inv.from) })
	self:_tell(userId)
	return id, nil
end

-- The race a player is in and who against, or nil.
function Duels.racing(self: Duels, userId: number): (string?, number?)
	local id = self.of[userId]
	local race = id and self.races[id]
	if not race then
		return nil, nil
	end
	if self.mods.clock() - race.at > Duels.LONGEST then
		self.of[race.a], self.of[race.b], self.races[race.id] = nil, nil, nil
		return nil, nil
	end
	return race.id, if race.a == userId then race.b else race.a
end

-- Passes a racer's position on to the other: { t, dist, speed, burning }.
function Duels.relay(self: Duels, userId: number, payload: any)
	local id, vs = self:racing(userId)
	if not id or type(payload) ~= "table" then
		return
	end
	local t, dist = tonumber(payload.t), tonumber(payload.dist)
	if not t or not dist or t ~= t or dist ~= dist then
		return
	end
	local now = self.mods.clock()
	local b = self.budget[userId]
	if b == nil or now - b.at >= 1 then
		local fresh = { n = 0, at = now }
		self.budget[userId] = fresh
		b = fresh
	end
	local spent = b :: { n: number, at: number }
	spent.n += 1
	if spent.n > Duels.RELAY_RATE then
		return
	end
	local speed = tonumber(payload.speed) or 0
	self.mods.send(vs :: number, "pos", { t = t, dist = dist, speed = speed, burning = payload.burning == true, done = payload.done == true })
end

-- A racer's finish (the server's own replay of their run), and the other's once they have one:
-- waits up to WAIT seconds for it. Returns the other's time, or math.huge if they never finished.
function Duels.finish(self: Duels, userId: number, time: number): number
	local id, vs = self:racing(userId)
	local race = id and self.races[id]
	if not race or not vs then
		return math.huge
	end
	race.times[userId] = time
	self.mods.send(vs, "finished", { t = time })
	local waited = 0
	while race.times[vs] == nil and waited < Duels.WAIT and self.mods.here(vs) do
		self.mods.wait(0.25)
		waited += 0.25
	end
	local their = race.times[vs] or math.huge
	self:_close(race, userId)
	return their
end

-- A racer is done with the race: once both are, it's gone.
function Duels._close(self: Duels, race: Race, userId: number)
	if self.of[userId] == race.id then
		self.of[userId] = nil
	end
	if self.of[race.a] ~= race.id and self.of[race.b] ~= race.id then
		self.races[race.id] = nil
	end
end

-- A player left the server, or quit the race: their challenges go, and an unfinished race is
-- called off for the other.
function Duels.leave(self: Duels, userId: number)
	for id, inv in self.invites do
		if inv.from == userId or inv.to == userId then
			self.invites[id] = nil
			if inv.from == userId then
				self:_tell(inv.to)
			end
		end
	end
	local id, vs = self:racing(userId)
	local race = id and self.races[id]
	if race then
		if race.times[userId] == nil then
			race.times[userId] = math.huge
			if vs and race.times[vs] == nil then
				self.mods.send(vs, "off", { id = id })
			end
		end
		self:_close(race, userId)
	end
	self.budget[userId] = nil
end

return Duels
