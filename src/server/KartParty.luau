--!strict
-- Kart parties: live kart races between the players in this server, as the web game's kart
-- parties (ui/LiveKartParty.tsx, lib/kartNet.ts, and the referee in its 0058_kart_parties.sql).
--
-- A player opens a party; anyone else in the server can join it from the Race menu's Live page
-- until the host starts it (2 to 6 players, AI karts filling the rest of the grid). On Go the
-- server deals the race: the circuit, the seed, the grid and who drives which kart (the AI belong
-- to the host's game, as on the web). Every player's game then runs the whole race and drives its
-- own kart, copying the others from what they send (Shared.Game.lib_kartNet's KartLink); the
-- server only passes those messages on, stamped with who sent them.
--
-- The lights go out once everyone's game has the circuit drawn, or START_WAIT seconds after the
-- deal. Each player reports a finish time, which can't beat the fastest time their kart could
-- manage (kartFloor) nor the time since the lights went out. Places go by time once every
-- player still here has reported, or SETTLE seconds after the first report (anyone still out is
-- behind everyone who reported). Each is paid the web's live kart prize through finishRace.

local KartParty = {}
KartParty.__index = KartParty

KartParty.MAX = 6 -- players in a party (game/kart.ts FIELD)
KartParty.START_WAIT = 8 -- seconds after the deal before the lights go regardless
KartParty.SETTLE = 60 -- seconds after the first finish before the places are settled
KartParty.LOBBY_TIME = 600 -- an unstarted party closes after this long
-- Messages a player's game may pass on to the others in its race, and how many a second.
KartParty.RELAY = { snap = true, notes = true }
KartParty.RELAY_RATE = 30

-- The web's KART_CREW: the AI drivers that fill a party's grid.
local KART_CREW = { "Lugnut Lou", "Dizzy Dash", "Turbo Tess", "Skid Mark", "Polly Piston", "Revvin Kevin", "Nitro Nell", "Gravel Gus" }
local STOCK = { engine = 0, turbo = 0, tires = 0, weight = 0 }

export type Mods = {
	store: any,
	data: any,
	kart: any,
	raceCar: any,
	boosts: any,
	random: any,
	clock: () -> number,
	-- Runs fn after s seconds (task.delay in the game).
	delay: (s: number, fn: () -> ()) -> (),
	-- Sends one player's game a message: (userId, event, payload).
	send: (userId: number, event: string, payload: any) -> (),
	-- The name a player shows to the others (their display name).
	name: (userId: number) -> string,
	-- Called once a player has been paid, to send their town (optional).
	paid: ((userId: number) -> ())?,
}

type Party = {
	id: string,
	host: number,
	players: { number },
	openedAt: number,
	-- Once dealt:
	dealt: boolean,
	field: { any }?,
	owners: { string }?,
	pis: { [number]: number },
	prizes: { [number]: number },
	ready: { [number]: boolean },
	goAt: number?,
	times: { [number]: number },
	left: { [number]: boolean },
	firstAt: number?,
	done: boolean,
}

export type KartParty = typeof(setmetatable(
	{} :: { towns: any, mods: Mods, parties: { [string]: Party }, of: { [number]: string }, seq: number, budget: { [number]: { n: number, at: number } } },
	KartParty
))

function KartParty.new(towns: any, mods: Mods): KartParty
	return setmetatable({ towns = towns, mods = mods, parties = {}, of = {}, seq = 0, budget = {} }, KartParty)
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

-- The live kart race prize against players of this PI (ui/LiveKart.tsx liveKartPrize).
function KartParty.prize(oppPi: number): number
	return 300 + oppPi * 8
end

-- The fastest three laps a kart of this PI could ever drive (the web's kart_floor(pi)): the
-- shortest racing line on any circuit, 1040 for three laps, at 1.6 times its top speed.
function KartParty.kartFloor(pi: number): number
	local top = 15 + 9 * (1 - math.exp(-math.max(pi, 1) / 90))
	return math.floor(1040 / (top * 1.6) * 1000 + 0.5) / 1000
end

-- One kart on the grid, as server/Karts deals them: its driver and the car it looks like.
local function racer(data: any, name: string, pi: number, ai: boolean, skill: number?, car: any): any
	return {
		name = name,
		pi = pi,
		ai = ai,
		skill = skill,
		weight = data.carDef(car.model).weight,
		model = car.model,
		color = car.color,
		finish = car.finish,
		skin = car.skin,
		modSkin = car.modSkin,
		panels = car.panels,
		mods = car.mods,
		trim = car.trim,
		hat = car.hat,
		stripe = car.stripe,
	}
end

-- The grid (LiveKartParty.tsx partyField): AI at the front around the party's PI, then the
-- guests, then the host at the back. Returns it and, per kart, who drives it (the host the AI).
-- players: host first, each { id, name, pi, car }.
function KartParty.field(data: any, seed: number, partyPi: number, players: { any }): ({ any }, { string })
	local r = seed
	local function rand(): number
		r = (r * 16807) % 2147483647
		return r / 2147483647
	end
	local keyed = {}
	for i, n in KART_CREW do
		keyed[i] = { n = n, k = rand() }
	end
	table.sort(keyed, function(a, b)
		return a.k < b.k
	end)
	local field, owners = {}, {}
	local host = tostring(players[1].id)
	for i = 0, KartParty.MAX - #players - 1 do
		local pi = math.max(5, round(partyPi * (0.9 + i * 0.05)))
		local cars = table.clone(data.CARS)
		local gap = {}
		for _, c in cars do
			gap[c.id] = math.abs(data.performance(c, STOCK) - pi)
		end
		table.sort(cars, function(a, b)
			if gap[a.id] ~= gap[b.id] then
				return gap[a.id] < gap[b.id]
			end
			return a.id < b.id
		end)
		local c = cars[i % 2 + 1]
		table.insert(field, racer(data, keyed[i + 1].n, pi, true, 0.6 + i * 0.08, { model = c.id, color = c.colors[i % #c.colors + 1] }))
		table.insert(owners, host)
	end
	for n = 2, #players do
		local p = players[n]
		table.insert(field, racer(data, p.name, p.pi, false, nil, p.car))
		table.insert(owners, tostring(p.id))
	end
	table.insert(field, racer(data, players[1].name, players[1].pi, false, nil, players[1].car))
	table.insert(owners, host)
	return field, owners
end

local function contains(list: { number }, id: number): boolean
	return table.find(list, id) ~= nil
end

-- A player's race car and its PI, or nil when they have none.
function KartParty._car(self: KartParty, userId: number): (any?, number)
	local data, raceCar = self.mods.data, self.mods.raceCar
	if not self.towns:isOpen(userId) then
		return nil, 0
	end
	local car, pi = nil, 0
	self.towns:_with(userId, function(s: any)
		car = raceCar.raceCarOf(s.cars, s.raceCar)
		if car then
			pi = data.performance(data.carDef(car.model), car.upgrades, car.mods)
		end
	end)
	return car, pi
end

-- What the Live page shows of a party.
function KartParty.view(self: KartParty, party: Party): any
	local players = {}
	for _, id in party.players do
		local car, pi = self:_car(id)
		table.insert(players, { id = id, name = self.mods.name(id), pi = pi, model = car and car.model, color = car and car.color })
	end
	return { id = party.id, host = party.host, hostName = self.mods.name(party.host), players = players, dealt = party.dealt, max = KartParty.MAX }
end

-- Every party still open to join, and the one this player is in.
function KartParty.list(self: KartParty, userId: number): any
	local open = {}
	local now = self.mods.clock()
	for _, p in self.parties do
		if not p.dealt and now - p.openedAt > KartParty.LOBBY_TIME then
			self:_disband(p, "The kart party closed")
		end
	end
	for _, p in self.parties do
		if not p.dealt and #p.players < KartParty.MAX and not contains(p.players, userId) then
			table.insert(open, self:view(p))
		end
	end
	table.sort(open, function(a, b)
		return a.id < b.id
	end)
	local mine = self.of[userId] and self.parties[self.of[userId]]
	return { open = open, mine = if mine then self:view(mine) else nil }
end

-- Tells everyone in the party (and everyone looking at the Live page) what changed.
function KartParty._changed(self: KartParty, party: Party?)
	if party then
		local v = self:view(party)
		for _, id in party.players do
			self.mods.send(id, "party", v)
		end
	end
	self.mods.send(0, "parties", nil)
end

function KartParty._disband(self: KartParty, party: Party, why: string?)
	self.parties[party.id] = nil
	for _, id in party.players do
		if self.of[id] == party.id then
			self.of[id] = nil
		end
		if not party.dealt then
			self.mods.send(id, "party", { gone = true, why = why })
		end
	end
	self.mods.send(0, "parties", nil)
end

function KartParty.open(self: KartParty, userId: number): (any?, string?)
	if self.of[userId] then
		return nil, "already in a party"
	end
	local car = self:_car(userId)
	if not car then
		return nil, "You need a car to race"
	end
	self.seq += 1
	local party: Party = {
		id = `{userId}-{self.seq}`,
		host = userId,
		players = { userId },
		openedAt = self.mods.clock(),
		dealt = false,
		pis = {},
		prizes = {},
		ready = {},
		times = {},
		left = {},
		done = false,
	}
	self.parties[party.id] = party
	self.of[userId] = party.id
	self:_changed(party)
	return self:view(party)
end

function KartParty.join(self: KartParty, userId: number, id: any): (any?, string?)
	local party = type(id) == "string" and self.parties[id] or nil
	if self.of[userId] then
		return nil, "already in a party"
	end
	if not party or party.dealt then
		return nil, "The party has already started"
	end
	if #party.players >= KartParty.MAX then
		return nil, "The party is full"
	end
	if not self:_car(userId) then
		return nil, "You need a car to race"
	end
	table.insert(party.players, userId)
	self.of[userId] = party.id
	self:_changed(party)
	return self:view(party)
end

-- Leaving: before the start, off the roster (the host calls it off for everyone); during the
-- race, the others' games hand the kart to an AI driver and the player is placed as unfinished.
function KartParty.leave(self: KartParty, userId: number)
	local party = self.of[userId] and self.parties[self.of[userId]]
	self.of[userId] = nil
	if not party then
		return
	end
	if not party.dealt then
		if userId == party.host then
			self:_disband(party, `{self.mods.name(userId)} called off the party`)
			return
		end
		table.remove(party.players, table.find(party.players, userId) :: number)
		self:_changed(party)
		return
	end
	-- Over the line already: still paid by place once it's settled.
	if party.times[userId] ~= nil then
		return
	end
	party.left[userId] = true
	self:_go(party)
	self:_decide(party)
end

-- The host starts it: the server deals the race to every player in the party.
function KartParty.go(self: KartParty, userId: number): (any?, string?)
	local m = self.mods
	local data, kart = m.data, m.kart
	local party = self.of[userId] and self.parties[self.of[userId]]
	if not party or party.host ~= userId then
		return nil, "not your party"
	end
	if party.dealt then
		return nil, "The party has already started"
	end
	local racers = {}
	for _, id in party.players do
		local car, pi = self:_car(id)
		if car then
			table.insert(racers, { id = id, name = m.name(id), pi = pi, car = car })
		end
	end
	if #racers < 2 then
		return nil, "Wait for someone to join"
	end
	local sum = 0
	for _, r in racers do
		sum += r.pi
	end
	local seed = m.random:NextInteger(1, 2147483000)
	local trackIndex = m.random:NextInteger(0, #kart.TRACKS - 1)
	local reverse = m.random:NextNumber() < 0.5
	local field, owners = KartParty.field(data, seed, round(sum / #racers), racers)
	party.dealt = true
	party.players = {}
	party.field, party.owners = field, owners
	local def = kart.TRACKS[trackIndex + 1]
	for _, r in racers do
		table.insert(party.players, r.id)
		party.pis[r.id] = r.pi
		-- Each is raced for the others' PI (LiveKartParty.tsx prize).
		local others = 0
		for _, o in racers do
			if o.id ~= r.id then
				others += o.pi
			end
		end
		party.prizes[r.id] = KartParty.prize(round(others / (#racers - 1)))
	end
	for id in self.of do
		if self.of[id] == party.id and not contains(party.players, id) then
			self.of[id] = nil
		end
	end
	for _, r in racers do
		local me = 0
		for i, o in owners do
			if o == tostring(r.id) then
				me = i - 1
			end
		end
		m.send(r.id, "setup", {
			kind = "live",
			track = trackIndex,
			reverse = reverse,
			rules = {},
			field = field,
			seed = seed,
			prize = party.prizes[r.id],
			title = `🏎️ Kart party ×{#racers} · {def.icon} {def.short}{if reverse then " ↺" else ""}`,
			live = { id = party.id, me = me, owners = owners, mine = tostring(r.id) },
		})
	end
	m.delay(KartParty.START_WAIT, function()
		self:_go(party, true)
	end)
	self:_changed(nil)
	return true
end

-- A player's game has the circuit drawn.
function KartParty.ready(self: KartParty, userId: number)
	local party = self.of[userId] and self.parties[self.of[userId]]
	if party and party.dealt then
		party.ready[userId] = true
		self:_go(party)
	end
end

-- The lights, once everyone still here is ready (or force: the wait is over).
function KartParty._go(self: KartParty, party: Party, force: boolean?)
	if party.goAt or not party.dealt then
		return
	end
	if not force then
		for _, id in party.players do
			if not party.ready[id] and not party.left[id] then
				return
			end
		end
	end
	party.goAt = self.mods.clock()
	for _, id in party.players do
		if not party.left[id] then
			self.mods.send(id, "go", nil)
		end
	end
end

-- Passes a race message on to the rest of the party, stamped with who sent it.
function KartParty.relay(self: KartParty, userId: number, event: any, payload: any)
	local party = self.of[userId] and self.parties[self.of[userId]]
	if not party or not party.dealt or party.done or not KartParty.RELAY[event] or type(payload) ~= "table" then
		return
	end
	local now = self.mods.clock()
	local b = self.budget[userId] or { n = KartParty.RELAY_RATE, at = now }
	b.n = math.min(KartParty.RELAY_RATE, b.n + (now - b.at) * KartParty.RELAY_RATE)
	b.at = now
	self.budget[userId] = b
	if b.n < 1 then
		return
	end
	b.n -= 1
	payload.from = tostring(userId)
	for _, id in party.players do
		if id ~= userId and not party.left[id] then
			self.mods.send(id, event, payload)
		end
	end
end

-- A player's finish time; the verdict follows once the places are settled.
function KartParty.finish(self: KartParty, userId: number, t: any): (any?, string?)
	local party = self.of[userId] and self.parties[self.of[userId]]
	if not party or not party.dealt or not party.goAt then
		return nil, "no race"
	end
	if type(t) ~= "number" or t ~= t or t <= 0 or t > 900 then
		return nil, "bad time"
	end
	local now = self.mods.clock()
	if (now - party.goAt) < t * 0.85 then
		return nil, "too quick"
	end
	if not party.done and party.times[userId] == nil then
		party.times[userId] = math.floor(math.max(t, KartParty.kartFloor(party.pis[userId] or 1)) * 1000 + 0.5) / 1000
		if not party.firstAt then
			party.firstAt = now
			self.mods.delay(KartParty.SETTLE, function()
				self:_decide(party, true)
			end)
		end
	end
	self:_decide(party)
	return true
end

-- Where a player came among the players (kart_party_view): ahead of them, everyone with a better
-- time (or any time, when they have none); a tie goes to whoever is earlier in the list.
function KartParty.place(party: Party, userId: number): number
	local mine = table.find(party.players, userId) :: number
	local myT = party.times[userId]
	local place = 1
	for i, id in party.players do
		local t = party.times[id]
		if i ~= mine and t ~= nil and (myT == nil or t < myT or (t == myT and i < mine)) then
			place += 1
		end
	end
	return place
end

-- Settles the places once everyone still here has a time (or force: the wait is over), pays
-- everyone and tells them.
function KartParty._decide(self: KartParty, party: Party, force: boolean?)
	if party.done or not party.firstAt then
		return
	end
	if not force then
		for _, id in party.players do
			if party.times[id] == nil and not party.left[id] then
				return
			end
		end
	end
	party.done = true
	local of = #party.players
	local boosts = self.mods.boosts
	for _, id in party.players do
		local place = KartParty.place(party, id)
		local prize = party.prizes[id]
		local verdict: any = { place = place, of = of, time = party.times[id], coins = 0 }
		-- Everyone still here is paid by place (still on the road counts as behind the finishers).
		if not party.left[id] and self.towns:isOpen(id) then
			self.towns:_with(id, function(s: any)
				local before = s.coins
				local loss = round(prize * boosts.placeShare(place, of, true))
				self.mods.store.useGame.getState().finishRace(place == 1, prize, { mode = "kart", live = true, loss = loss })
				verdict.coins = self.mods.store.useGame.getState().coins - before
			end)
			if self.mods.paid then
				self.mods.paid(id)
			end
		end
		if not party.left[id] then
			self.mods.send(id, "verdict", verdict)
		end
	end
	self.parties[party.id] = nil
	for _, id in party.players do
		if self.of[id] == party.id then
			self.of[id] = nil
		end
	end
end

-- A player who left the server.
function KartParty.forget(self: KartParty, userId: number)
	self:leave(userId)
	self.budget[userId] = nil
end

return KartParty
