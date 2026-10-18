--!strict
-- Drag races, run by the server so nobody can pay themselves a win.
--
-- The client asks to start a race (Quick Race against one of three rivals, or a campaign race).
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
}

type Pending = {
	mode: string,
	spec: any,
	rival: RivalCard,
	chapter: string?,
	race: number?,
	model: string,
	startedAt: number,
}

export type Mods = {
	store: any,
	data: any,
	raceCar: any,
	fairRace: any,
	fairPi: any,
	grip: any,
	weather: any,
	venues: any,
	DragRace: any,
	random: Random,
	clock: () -> number, -- seconds, for how long a race took
}

export type Races = typeof(setmetatable(
	{} :: { towns: any, mods: Mods, quick: { [number]: { pi: number, list: { RivalCard } } }, pending: { [number]: Pending } },
	Races
))

function Races.new(towns: any, mods: Mods): Races
	return setmetatable({ towns = towns, mods = mods, quick = {}, pending = {} }, Races)
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
	local myPi = self.towns:_with(userId, function(s: any)
		local _, pi = self:_car(s)
		return if pi > 0 then pi else 10
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

-- Starts a race. mode "quick" with the rival's number (1-3), or "campaign" with { chapter, race }
-- (0-based, as the web game counts). Returns what the client needs to run it, or nil and why.
function Races.start(self: Races, userId: number, mode: string, arg: any): (any?, string?)
	local data, store = self.mods.data, self.mods.store
	local rival: RivalCard? = nil
	local chapter: string?, raceNo: number? = nil, nil
	local spec: any = nil
	local model = ""
	local why: string? = nil
	local where: any = nil
	if mode == "quick" then
		if type(arg) ~= "number" or arg ~= math.floor(arg) or arg < 1 or arg > 3 then
			return nil, "pick a rival"
		end
		rival = self:quickRivals(userId)[arg]
	elseif mode ~= "campaign" then
		return nil, "not a race"
	end
	self.towns:_with(userId, function(s: any)
		s.tick(self.towns.now())
		local car, myPi = self:_car(s)
		if not car then
			why = "You need a car to race"
			return
		end
		model = car.model
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
		end
		if not store.spendFuel(data.RACE_FUEL) then
			s.showNeed("fuel", data.RACE_FUEL - s.fuel, "a race")
			why = "need fuel"
			return
		end
		local r = rival :: RivalCard
		local m = self.mods
		local def = data.carDef(car.model)
		-- Somewhere different each Quick Race; a campaign chapter races at its own venue. The sky
		-- and the strip's grip come with it (Race.tsx DragRace: raceWeather, conditions).
		local v = if chapter then m.venues.venue(data.CAMPAIGN[(arg :: any).chapter + 1].venue) else m.venues.pickVenue(nil, function()
			return m.random:NextNumber()
		end)
		local sky = m.weather.raceWeather(v.id)
		local mine = m.grip.conditions(sky.kind, v.id, m.grip.carGrip(def, car.upgrades, car.mods), car.mods)
		local theirs = m.grip.conditions(sky.kind, v.id, data.carDef(r.model).grip or 50)
		-- Every AI rival is one this car can beat with perfect driving (fairPi.ts), as the web's
		-- race screen makes sure of for every race.
		local racePi = m.fairPi.fairRivalPi(r.pi, myPi, r.shift, r.skill)
		if mode == "quick" then
			r = table.clone(r)
			r.prize = round(150 + racePi * 6)
			rival = r
		end
		spec = {
			myPi = myPi,
			mySkill = def.skill,
			rival = { pi = racePi, shift = r.shift, skill = r.skill },
			seed = m.random:NextInteger(1, 2147483646),
			track = data.TRACK or 400,
			grip = { lo = mine.lo, hi = mine.hi, spin = mine.spin, dust = mine.dust },
			theirGrip = { lo = theirs.lo, hi = theirs.hi, spin = theirs.spin, dust = theirs.dust },
		}
		where = { id = v.id, name = v.name, icon = v.icon, sky = sky.kind, note = m.grip.conditionsNote(mine) }
	end)
	if not spec then
		return nil, why
	end
	local r = rival :: RivalCard
	self.pending[userId] = { mode = mode, spec = spec, rival = r, chapter = chapter, race = raceNo, model = model, startedAt = self.mods.clock() }
	return { spec = spec, rival = r, mode = mode, venue = where }
end

-- Finishes the race started last, from the client's presses: races it again and pays it.
-- Returns the result for the result card, or nil and why.
function Races.finish(self: Races, userId: number, events: any): (any?, string?)
	local DragRace = self.mods.DragRace
	local p = self.pending[userId]
	if not p then
		return nil, "no race"
	end
	self.pending[userId] = nil
	if not DragRace.valid(events) then
		return nil, "bad race"
	end
	local run = DragRace.replay(p.spec, events)
	local myTime, theirTime = DragRace.times(run)
	-- The race can't finish sooner than it takes to run (the countdown and the player's own time).
	local took = self.mods.clock() - p.startedAt
	local need = DragRace.GO_TICK * DragRace.DT + math.min(myTime, theirTime, DragRace.MAX_SECONDS)
	if took < need * 0.85 then
		return nil, "too quick"
	end
	local won = myTime < theirTime
	local result: any = { won = won, myTime = myTime, theirTime = theirTime, launch = run.launch, perfect = run.perfect, shifts = run.shifts, top = run.top }
	self.towns:_with(userId, function(s: any)
		local before = { coins = s.coins, xp = s.xp, level = s.level, trophies = s.trophies }
		local store = self.mods.store.useGame.getState
		if p.mode == "campaign" then
			result.stars = store().campaignResult(p.chapter, p.race, myTime, theirTime, p.rival.pi)
		else
			store().finishRace(won, p.rival.prize)
		end
		store().masteryRace(p.model, won, if p.mode == "campaign" then "campaign" else "drag", p.rival.pi > p.spec.myPi)
		local after = store()
		result.coins = after.coins - before.coins
		result.trophies = after.trophies - before.trophies
		result.xp = self.mods.store.lastRaceXpPaid()
		result.levelUp = after.level > before.level
	end)
	-- A Quick Race win or loss deals new rivals next time.
	if p.mode == "quick" then
		self.quick[userId] = nil
	end
	return result
end

function Races.close(self: Races, userId: number)
	self.quick[userId] = nil
	self.pending[userId] = nil
end

return Races
