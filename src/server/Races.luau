--!strict
-- Drag races, run by the server so nobody can pay themselves a win.
--
-- The client asks to start a race (Quick Race against one of three rivals, a campaign race, a
-- paint rival, the rival in town, or a double-or-nothing rematch against them). A Quick Race won
-- brings a faster challenger straight away (game/challenger.ts), and a loss offers the rematch:
-- either is mode "next".
-- The server checks the race is open, spends the fuel, picks the rival exactly as the web game's
-- race screen does (ui/Race.tsx: makeRivals, campaignRival, eased by fairRace.fairNow so the race
-- car can always win), and hands back the race: both cars and a seed for the rival's driving.
-- The client drives it live (Shared.DragRace) and sends back its presses. The server races the
-- same race again from them and pays what that run earned, through the web store's own actions
-- (finishRace, campaignResult, masteryRace).

local Races = {}
Races.__index = Races

-- Quick Race rival towns (Race.tsx TOWNS).
local TOWNS = { "Transamsylvania", "Gearville", "Piston Peak", "Nitro Bay", "Chrome City", "Rustbelt Row", "Turbo Falls", "Muffler Hills" }
local STOCK = { engine = 0, turbo = 0, tires = 0, weight = 0 }

-- What the client shows for a rival.
export type RivalCard = {
	id: string,
	name: string,
	carName: string,
	model: string,
	color: string,
	pi: number,
	shift: number,
	skill: string?,
	boss: boolean?,
	prize: number,
	-- Paint rivals (game/paintRivals.ts): their colour (also `color`), tier, venue and distance.
	icon: string?,
	tier: number?,
	wins: number?,
	venue: string?,
	dist: string?,
	night: boolean?,
	line: string?,
	-- The rival in town (game/rivals.ts): who, and which visit.
	visit: number?,
}

type Pending = {
	mode: string,
	spec: any,
	rival: RivalCard,
	chapter: string?,
	race: number?,
	model: string,
	startedAt: number,
	-- The paint rival or town rival raced.
	who: string?,
	-- A double-or-nothing rematch: what's riding on it.
	stake: number?,
	-- What a mode from server/Modes kept for its finish.
	extra: any,
	userId: number,
}

-- A town rival race won, with a rematch for double or nothing on offer until another race.
type Bet = { card: RivalCard, who: string, stake: number }

export type Mods = {
	store: any,
	data: any,
	raceCar: any,
	fairRace: any,
	fairPi: any,
	grip: any,
	weather: any,
	venues: any,
	paintRivals: any,
	rivals: any,
	distance: any,
	DragRace: any,
	random: Random,
	clock: () -> number, -- seconds, for how long a race took
	-- The other race modes (server/Modes): each by its mode name.
	modes: { [string]: Mode }?,
	-- A converted game module by name (Shared.Game.<name>), for the modes.
	game: ((string) -> any)?,
	-- Weekly time boards by name (server/Boards), for the modes.
	boards: { [string]: any }?,
	-- Everyone's ghosts and taunts (server/Ghosts), and whose ghosts a player can race:
	-- { userId, name, here? } for everyone else in the server and their friends.
	ghosts: any?,
	people: ((userId: number) -> { any })?,
	-- The town visitors (server/Visitors), for street races against a visiting racer.
	visitors: any?,
}

-- A race mode beyond the ones built in here (server/Modes/*.luau). Each is a table of functions
-- given the Races object and the town's state (run inside towns:_with, so the web store's
-- actions are live):
--   list(self, s, arg, userId): what the race menu's page for the mode shows, or nil
--   act(self, s, arg, userId): something done outside a race (claim a prize), or nil and why
--   start(self, s, arg, car, myPi, userId): the race to run, or nil and why. Returns a table with
--     rival (a RivalCard), and optionally venue (id), dist, night, weatherSeed, sky, ghost (a
--     solo run against a ghost finishing in that many seconds), car (a loaner { model, color,
--     upgrades } raced instead of the player's car), fuel (false: free) and extra (anything the
--     client needs back, kept on the pending race too)
--   finish(self, s, p, won, myTime, theirTime, result): pays the race through the web store and
--     adds to `result` what the result card shows. Mastery counts the race by its rival's id, as
--     the web game does (mastery.ts masteryMode).
export type Mode = {
	id: string,
	list: ((self: any, s: any, arg: any, userId: number) -> any)?,
	act: ((self: any, s: any, arg: any, userId: number) -> (any?, string?))?,
	start: (self: any, s: any, arg: any, car: any, myPi: number, userId: number) -> (any?, string?),
	finish: (self: any, s: any, p: any, won: boolean, myTime: number, theirTime: number, result: any) -> (),
}

export type Races = typeof(setmetatable(
	{} :: {
		towns: any,
		mods: Mods,
		quick: { [number]: { pi: number, list: { RivalCard } } },
		pending: { [number]: Pending },
		bets: { [number]: Bet },
		-- After a Quick Race (or a challenger): the next challenger after a win, the rematch after a loss.
		nextUp: { [number]: RivalCard },
	},
	Races
))

function Races.new(towns: any, mods: Mods): Races
	return setmetatable({ towns = towns, mods = mods, quick = {}, pending = {}, bets = {}, nextUp = {} }, Races)
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

-- The player's race car (the one picked, else the best) and its PI, from the town's state.
function Races._car(self: Races, s: any): (any, number)
	local car = self.mods.raceCar.raceCarOf(s.cars, s.raceCar)
	if not car then
		return nil, 0
	end
	return car, self.mods.raceCar.carPi(car)
end

-- Quick Race: three rivals at 0.8, 0.95 and 1.1 of the race car's PI (Race.tsx makeRivals),
-- each eased to what the car can beat. They stay the same until one is raced.
function Races.quickRivals(self: Races, userId: number): { RivalCard }
	local data, fairRace, rng = self.mods.data, self.mods.fairRace, self.mods.random
	-- From the town's best car, as Race.tsx makeRivals(bestCar(cars)).
	local myPi = self.towns:_with(userId, function(s: any)
		local best = self.mods.raceCar.bestCar(s.cars)
		return if best then self.mods.raceCar.carPi(best) else 10
	end)
	-- The same rivals until one is raced, or the race car changes.
	local known = self.quick[userId]
	if known and known.pi == myPi then
		return known.list
	end
	local list: { RivalCard } = {}
	self.towns:_with(userId, function(s: any)
		local towns = table.clone(TOWNS)
		for i = #towns, 2, -1 do
			local j = rng:NextInteger(1, i)
			towns[i], towns[j] = towns[j], towns[i]
		end
		for i, f in { 0.8, 0.95, 1.1 } do
			local target = math.max(10, round(myPi * f + (rng:NextNumber() * 6 - 3)))
			local best, bestGap = nil, math.huge
			for _, c in data.CARS do
				local gap = math.abs(data.performance(c, STOCK) - target)
				if gap < bestGap then
					best, bestGap = c, gap
				end
			end
			local car = best :: any
			local pi = fairRace.fairNow(target, 1, car.skill)
			list[i] = {
				id = `ai-{i - 1}`,
				name = towns[i],
				carName = car.name,
				model = car.id,
				color = car.colors[rng:NextInteger(1, #car.colors)],
				pi = pi,
				shift = 1,
				skill = car.skill,
				prize = round(150 + pi * 6),
			}
		end
	end)
	self.quick[userId] = { pi = myPi, list = list }
	return list
end

-- What a Quick Race rival or challenger pays (Race.tsx reward): challengers half as much again.
function Races._quickPrize(self: Races, id: string, pi: number): number
	local bonus = if id:sub(1, 5) == "chal-" then (self.mods.game :: any)("challenger").CHALLENGER_BONUS else 1
	return round((150 + pi * 6) * bonus)
end

-- The challenger after beating `beaten` (Race.tsx: makeChallenger(n, race.pi, car.model, pi(car))).
-- The card shows their own PI, as the web's does; the race eases it like every rival's.
function Races._challenger(self: Races, beaten: RivalCard, model: string, myPi: number): RivalCard
	local n = if beaten.id:sub(1, 5) == "chal-" then (tonumber(beaten.id:sub(6)) or 0) + 1 else 0
	local rng = self.mods.random
	local c = (self.mods.game :: any)("challenger").makeChallenger(n, beaten.pi, model, myPi, function()
		return rng:NextNumber()
	end)
	return {
		id = c.id,
		name = c.town,
		carName = c.carName,
		model = c.model,
		color = c.color,
		pi = c.pi,
		shift = 1,
		skill = c.skill,
		prize = self:_quickPrize(c.id, c.pi),
	}
end

-- A campaign race's rival (Race.tsx campaignRival), eased to the race car, and its prize.
function Races._campaignRival(self: Races, s: any, ci: number, i: number): RivalCard
	local data, fairRace = self.mods.data, self.mods.fairRace
	local ch = data.CAMPAIGN[ci + 1]
	local target = data.campaignRivalPi(ch, i)
	local car: any = nil
	if ch.cars and ch.cars[i + 1] then
		for _, c in data.CARS do
			if c.id == ch.cars[i + 1] then
				car = c
			end
		end
	end
	car = car or fairRace.carNear(target)
	local shift = if data.rookieRace(ci, i, s.racesWon) then data.ROOKIE_SHIFT else data.campaignShift(ci, i)
	local skill = if data.campaignRivalSkills(ci, i) then car.skill else nil
	local pi = fairRace.fairNow(target, shift, skill)
	local first = (s.campaign[data.campaignRaceId(ch, i)] or 0) == 0
	return {
		id = `camp-{ch.id}-{i}`,
		name = ch.rivals[i + 1],
		carName = car.name,
		model = car.id,
		color = car.colors[(ci + i) % #car.colors + 1],
		pi = pi,
		shift = shift,
		skill = skill,
		boss = i == data.CAMPAIGN_RACES - 1,
		prize = data.campaignReward(ch, i, first, pi),
	}
end

-- Every campaign chapter for the race menu: open or not, its races' stars, rivals and prizes.
function Races.campaign(self: Races, userId: number): { any }
	local data, store = self.mods.data, self.mods.store
	local out = {}
	self.towns:_with(userId, function(s: any)
		local level = store.gateLevel(s)
		for ci, ch in data.CAMPAIGN do
			local races = {}
			for i = 0, data.CAMPAIGN_RACES - 1 do
				local stars = s.campaign[data.campaignRaceId(ch, i)] or 0
				local before = if i == 0 then 1 else s.campaign[data.campaignRaceId(ch, i - 1)] or 0
				races[i + 1] = { stars = stars, open = before > 0, rival = self:_campaignRival(s, ci - 1, i) }
			end
			out[ci] = {
				id = ch.id,
				name = ch.name,
				blurb = ch.blurb,
				venue = ch.venue,
				open = data.campaignOpen(s.campaign, ci - 1, level),
				starsNeed = data.campaignStarsNeed(ci - 1),
				cleared = data.campaignCleared(s.campaign, ch),
				coins = ch.coins,
				bucks = ch.bucks,
				trophies = ch.trophies,
				starBucks = ch.starBucks,
				races = races,
			}
		end
	end)
	return out
end

-- A paint rival's card (Race.tsx rowRival): their own car in their colour, eased to the race car.
function Races._rowCard(self: Races, s: any, r: any): RivalCard
	local data, pr, fairRace = self.mods.data, self.mods.paintRivals, self.mods.fairRace
	local car = data.carDef(r.car)
	local shift = pr.rowShift(r)
	local skill = if pr.rowSkills(r) then car.skill else nil
	local wins = (s.rivalRow or {})[r.id] or 0
	return {
		id = `row-{r.id}`,
		name = `{r.icon} {r.name}`,
		carName = car.name,
		model = car.id,
		color = r.paint,
		pi = fairRace.fairNow(r.pi, shift, skill),
		shift = shift,
		skill = skill,
		boss = r.tier == 5,
		prize = pr.rowPrize(r, wins == 0),
		icon = r.icon,
		tier = r.tier,
		wins = wins,
		venue = r.venue,
		dist = r.dist,
		night = r.night,
		line = r.line,
	}
end

-- Every paint rival for the race menu, in the roster's order.
function Races.rows(self: Races, userId: number): { RivalCard }
	local out = {}
	self.towns:_with(userId, function(s: any)
		for i, r in self.mods.paintRivals.PAINT_RIVALS do
			out[i] = self:_rowCard(s, r)
		end
	end)
	return out
end

-- The rival in town and the race against them on this visit (Rivals.tsx rivalMatch: a car near
-- the town's best one), or nil and why there's no race.
function Races._townCard(self: Races, s: any): (RivalCard?, string?)
	local data, rv, fairRace, store = self.mods.data, self.mods.rivals, self.mods.fairRace, self.mods.store
	local cur = rv.currentRival(store.gateLevel(s), s.rivals or {}, self.towns.now())
	if not cur then
		return nil, "Every rival is beaten"
	elseif cur.locked then
		return nil, `Rivals come to town at level {rv.RIVAL_LEVEL}`
	elseif (cur.away or 0) > 0 then
		return nil, `{cur.def.name} is tuning up`
	end
	local best = 10
	for _, c in s.cars do
		best = math.max(best, data.performance(data.carDef(c.model), c.upgrades, c.mods))
	end
	local ladder = rv.rivalPi(cur.def, cur.visit, best)
	local car, gap = nil, math.huge
	for _, c in data.CARS do
		local d = math.abs(data.performance(c, STOCK) - ladder)
		if d < gap then
			car, gap = c, d
		end
	end
	local idx = (table.find(rv.RIVALS, cur.def) or 1) - 1
	local skill = if idx >= 2 or cur.visit == rv.RIVAL_VISITS - 1 then car.skill else nil
	local shift = rv.rivalShift(cur.def, cur.visit)
	local pi = fairRace.fairNow(ladder, shift, skill)
	return {
		id = `rival-{cur.def.id}`,
		name = `{cur.def.icon} {cur.def.name}`,
		carName = car.name,
		model = car.id,
		color = cur.def.color,
		pi = pi,
		shift = shift,
		skill = skill,
		boss = cur.visit == rv.RIVAL_VISITS - 1,
		prize = rv.rivalPrize(pi),
		icon = cur.def.icon,
		visit = cur.visit,
	},
		cur.def.id
end

-- A double-or-nothing rematch not raced (or left half way) is lost, as the web's forfeitBet.
function Races._forfeit(self: Races, userId: number)
	local p = self.pending[userId]
	if p and p.stake and self.towns:isOpen(userId) then
		self.pending[userId] = nil
		local stake = p.stake
		self.towns:_with(userId, function(_s: any)
			self.mods.store.useGame.getState().rivalBet(false, stake)
		end)
	end
end

-- Starts a race. mode "quick" with the rival's number (1-3), "campaign" with { chapter, race }
-- (0-based, as the web game counts), "row" with a paint rival's id, "rival" for the rival in
-- town, or "bet" for double or nothing after beating them. Returns what the client needs to run
-- it, or nil and why.
function Races.start(self: Races, userId: number, mode: string, arg: any): (any?, string?)
	local data, store = self.mods.data, self.mods.store
	local rival: RivalCard? = nil
	local chapter: string?, raceNo: number? = nil, nil
	local spec: any = nil
	local model = ""
	local why: string? = nil
	local where: any = nil
	local who: string? = nil
	local stake: number? = nil
	self:_forfeit(userId)
	local bet = self.bets[userId]
	self.bets[userId] = nil
	local nextUp = self.nextUp[userId]
	self.nextUp[userId] = nil
	if mode == "quick" then
		if type(arg) ~= "number" or arg ~= math.floor(arg) or arg < 1 or arg > 3 then
			return nil, "pick a rival"
		end
		rival = self:quickRivals(userId)[arg]
	elseif mode == "next" then
		if not nextUp then
			return nil, "no race on offer"
		end
		rival = nextUp
	elseif mode == "bet" then
		if not bet then
			return nil, "no bet on offer"
		end
		rival, who, stake = bet.card, bet.who, bet.stake
	elseif mode == "row" then
		if type(arg) ~= "string" or not self.mods.paintRivals.paintRival(arg) then
			return nil, "pick a rival"
		end
		who = arg
	elseif mode ~= "campaign" and mode ~= "rival" and not (self.mods.modes and self.mods.modes[mode]) then
		return nil, "not a race"
	end
	local modeDef: Mode? = if self.mods.modes then self.mods.modes[mode] else nil
	local extra: any = nil
	local loaner: any = nil
	local ghost: number? = nil
	local sky: string? = nil
	local night: boolean? = nil
	self.towns:_with(userId, function(s: any)
		s.tick(self.towns.now())
		local car, myPi = self:_car(s)
		if not car then
			why = "You need a car to race"
			return
		end
		model = car.model
		local fuelFree = false
		local venueId: string? = nil
		local dist: string? = nil
		local weatherSeed: string? = nil
		if mode == "campaign" then
			local ci, i = type(arg) == "table" and arg.chapter, type(arg) == "table" and arg.race
			if type(ci) ~= "number" or type(i) ~= "number" or ci ~= math.floor(ci) or i ~= math.floor(i) then
				why = "pick a race"
				return
			end
			local ch = data.CAMPAIGN[ci + 1]
			if not ch or i < 0 or i >= data.CAMPAIGN_RACES then
				why = "pick a race"
				return
			end
			local before = if i == 0 then 1 else s.campaign[data.campaignRaceId(ch, i - 1)] or 0
			if not data.campaignOpen(s.campaign, ci, store.gateLevel(s)) or before == 0 then
				why = "That race isn't open yet"
				return
			end
			rival = self:_campaignRival(s, ci, i)
			chapter, raceNo = ch.id, i
			venueId = ch.venue
		elseif mode == "row" then
			local def = self.mods.paintRivals.paintRival(who)
			rival = self:_rowCard(s, def)
			venueId, dist, weatherSeed = def.venue, def.dist, `row-{def.id}`
		elseif mode == "rival" then
			local card, id = self:_townCard(s)
			if not card then
				why = id
				return
			end
			rival, who = card, id
		elseif modeDef then
			local got, err = modeDef.start(self, s, arg, car, myPi, userId)
			if not got then
				why = err or "That race isn't open"
				return
			end
			rival = got.rival
			venueId, dist, weatherSeed = got.venue, got.dist, got.weatherSeed
			extra, ghost, sky, night = got.extra, got.ghost, got.sky, got.night
			if got.car then
				-- A loaner (the Daily Run): raced instead of the player's own car.
				loaner = got.car
				car = got.car
				model = got.car.model
				myPi = data.performance(data.carDef(got.car.model), got.car.upgrades or STOCK, got.car.mods)
			end
			if got.fuel == false then
				fuelFree = true
			end
		end
		-- The rematch is on the house: it was the last race's fuel.
		if mode ~= "bet" and not fuelFree and not store.spendFuel(data.RACE_FUEL) then
			s.showNeed("fuel", data.RACE_FUEL - s.fuel, "a race")
			why = "need fuel"
			return
		end
		local r = rival :: RivalCard
		local m = self.mods
		local def = data.carDef(car.model)
		-- Somewhere different each Quick Race and town rival race; campaign chapters and paint
		-- rivals race at their own venue. The sky and the strip's grip come with it (Race.tsx
		-- DragRace: raceWeather, conditions).
		local v = if venueId then m.venues.venue(venueId) else m.venues.pickVenue(nil, function()
			return m.random:NextNumber()
		end)
		local sky = m.weather.raceWeather(v.id, weatherSeed, sky)
		local mine = m.grip.conditions(sky.kind, v.id, m.grip.carGrip(def, car.upgrades, car.mods), car.mods)
		local theirs = m.grip.conditions(sky.kind, v.id, data.carDef(r.model).grip or 50)
		-- Over a half mile or a mile the car's build counts (distance.ts): it races with it, and the
		-- rival is eased to what a buildless car as quick as this one can beat.
		local track = data.TRACK or 400
		local build: number? = nil
		local fairOf = myPi
		if dist then
			track = m.distance.DIST[dist].m
			build = m.distance.raceCharacter(def)
			fairOf = m.fairPi.buildPi(myPi, build, track)
		end
		-- Every AI rival is one this car can beat with perfect driving (fairPi.ts), as the web's
		-- race screen makes sure of for every race.
		local racePi = if ghost then r.pi else m.fairPi.fairRivalPi(r.pi, fairOf, r.shift, r.skill)
		if mode == "quick" or mode == "next" then
			r = table.clone(r)
			r.prize = self:_quickPrize(r.id, racePi)
			rival = r
		end
		spec = {
			myPi = myPi,
			mySkill = def.skill,
			rival = { pi = racePi, shift = r.shift, skill = r.skill },
			seed = m.random:NextInteger(1, 2147483646),
			track = track,
			build = build,
			grip = { lo = mine.lo, hi = mine.hi, spin = mine.spin, dust = mine.dust },
			theirGrip = { lo = theirs.lo, hi = theirs.hi, spin = theirs.spin, dust = theirs.dust },
			ghost = ghost,
		}
		where = { id = v.id, name = v.name, icon = v.icon, sky = sky.kind, note = m.grip.conditionsNote(mine), dist = dist, night = if mode == "row" then r.night else night }
	end)
	if not spec then
		-- Still on offer after a race that didn't start (no fuel, say).
		self.nextUp[userId] = nextUp
		return nil, why
	end
	local r = rival :: RivalCard
	self.pending[userId] = { mode = mode, spec = spec, rival = r, chapter = chapter, race = raceNo, model = model, startedAt = self.mods.clock(), who = who, stake = stake, extra = extra, userId = userId }
	return { spec = spec, rival = r, mode = mode, venue = where, stake = stake, extra = extra, car = loaner }
end

-- Finishes the race started last, from the client's presses: races it again and pays it.
-- Returns the result for the result card, or nil and why.
function Races.finish(self: Races, userId: number, events: any): (any?, string?)
	local DragRace = self.mods.DragRace
	local p = self.pending[userId]
	if not p then
		return nil, "no race"
	end
	if not DragRace.valid(events) then
		self:_forfeit(userId)
		self.pending[userId] = nil
		return nil, "bad race"
	end
	local run = DragRace.replay(p.spec, events)
	local myTime, theirTime = DragRace.times(run)
	-- The race can't finish sooner than it takes to run (the countdown and the player's own time).
	local took = self.mods.clock() - p.startedAt
	local need = DragRace.GO_TICK * DragRace.DT + math.min(myTime, theirTime, DragRace.MAX_SECONDS)
	if took < need * 0.85 then
		-- A rematch for double or nothing that doesn't count is lost.
		self:_forfeit(userId)
		self.pending[userId] = nil
		return nil, "too quick"
	end
	self.pending[userId] = nil
	-- A dead heat goes to the player, as on the web.
	local won = myTime < theirTime or (myTime == theirTime and myTime < math.huge)
	local result: any = { won = won, myTime = myTime, theirTime = theirTime, launch = run.launch, perfect = run.perfect, shifts = run.shifts, top = run.top }
	local bet: Bet? = nil
	self.towns:_with(userId, function(s: any)
		local before = { coins = s.coins, xp = s.xp, level = s.level, trophies = s.trophies, bucks = s.bucks }
		local modeDef: Mode? = if self.mods.modes then self.mods.modes[p.mode] else nil
		local store = self.mods.store.useGame.getState
		if p.mode == "campaign" then
			result.stars = store().campaignResult(p.chapter, p.race, myTime, theirTime, p.rival.pi)
			-- The result card's next race in the chapter once this one has ever been won, else a
			-- retry (Race.tsx campNextOf); nothing after the boss.
			local data = self.mods.data
			for ci, ch in data.CAMPAIGN do
				if ch.id == p.chapter then
					local now = store()
					local beaten = (now.campaign[data.campaignRaceId(ch, p.race)] or 0) > 0
					local n = if beaten then (p.race :: number) + 1 else p.race :: number
					if n < data.CAMPAIGN_RACES then
						result.next = { chapter = ci - 1, race = n, prize = self:_campaignRival(now, ci - 1, n).prize, retry = not beaten }
					end
				end
			end
		elseif p.mode == "row" then
			local first = ((s.rivalRow or {})[p.who] or 0) == 0
			store().rowResult(p.who, won)
			if won and first then
				result.paint = p.rival.color
			end
		elseif p.mode == "rival" then
			local bonus = store().rivalResult(p.who, won, p.rival.prize)
			result.bonus = bonus
			-- A win (unless they just quit) offers double or nothing on the prize.
			if won and not bonus then
				bet = { card = p.rival, who = p.who :: string, stake = p.rival.prize }
				result.bet = p.rival.prize
			end
		elseif p.mode == "bet" then
			store().rivalBet(won, p.stake)
		elseif modeDef then
			modeDef.finish(self, s, p, won, myTime, theirTime, result)
		else
			store().finishRace(won, p.rival.prize)
		end
		-- The rival's id says which mode the race counts under for mastery (mastery.ts
		-- masteryMode); solo runs against a ghost don't count.
		local mode = if p.mode == "campaign" then "campaign" elseif p.mode == "quick" or p.mode == "next" then "drag" else "rival"
		if modeDef then
			mode = if p.spec.ghost then nil else self.mods.game("mastery").masteryMode(p.rival.id)
		end
		if mode then
			-- What the race unlocked in mastery (ClassCups.tsx MasteryPrizePopup), for the result card.
			store().closeMasteryPrize()
			store().masteryRace(p.model, won, mode, p.rival.pi > p.spec.myPi)
			local prize = store().masteryPrize
			if prize then
				result.mastery = prize
				store().closeMasteryPrize()
			end
		end
		local after = store()
		result.coins = after.coins - before.coins
		result.trophies = after.trophies - before.trophies
		result.bucks = after.bucks - before.bucks
		-- A race that paid no XP (double or nothing, a solo run) shows none.
		result.xp = if p.mode == "bet" or (after.xp == before.xp and after.level == before.level) then 0 else self.mods.store.lastRaceXpPaid()
		result.levelUp = after.level > before.level
	end)
	self.bets[userId] = bet :: any
	-- A Quick Race win or loss deals new rivals next time, and offers the next race: a faster
	-- challenger after a win, the rematch after a loss.
	if p.mode == "quick" or p.mode == "next" then
		self.quick[userId] = nil
		local up = if won then self:_challenger(p.rival, p.model, p.spec.myPi) else p.rival
		self.nextUp[userId] = up
		result.next = { name = up.name, prize = up.prize, challenger = won }
	end
	return result
end

-- What the race menu's page for a mode from server/Modes shows.
function Races.list(self: Races, userId: number, mode: any, arg: any): any?
	local def = if type(mode) == "string" and self.mods.modes then self.mods.modes[mode] else nil
	if not def or not def.list then
		return nil
	end
	local out = nil
	self.towns:_with(userId, function(s: any)
		s.tick(self.towns.now())
		out = (def.list :: any)(self, s, arg, userId)
	end)
	return out
end

-- Something a mode from server/Modes does outside a race (claiming last week's Time Trial prize).
-- Returns its answer, or nil and why.
function Races.act(self: Races, userId: number, mode: any, arg: any): (any?, string?)
	local def = if type(mode) == "string" and self.mods.modes then self.mods.modes[mode] else nil
	if not def or not def.act then
		return nil, "not a race"
	end
	local out, why = nil, nil
	self.towns:_with(userId, function(s: any)
		s.tick(self.towns.now())
		out, why = (def.act :: any)(self, s, arg, userId)
	end)
	return out, why
end

-- Turns down double or nothing (the result card's Keep button), or leaves it.
function Races.keep(self: Races, userId: number)
	self.bets[userId] = nil
end

function Races.close(self: Races, userId: number)
	self:_forfeit(userId)
	self.bets[userId] = nil
	self.quick[userId] = nil
	self.nextUp[userId] = nil
	self.pending[userId] = nil
end

return Races
