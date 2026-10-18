--!strict
-- Ghost races (ui/GhostRace.tsx, lib/ghosts.ts): race the ghost of another player's best run,
-- the players in this server and Roblox friends who've played, then leave them a preset taunt.
-- A player's ghost is their fastest server-kept time (ghost races and Time Trials), or a par for
-- their best car until they have one; the times and taunts are kept by server/Ghosts. No prizes:
-- it's for bragging rights, as on the web.
--
-- The time is the server's own replay of the run, raised to the referee's floor for the car's PI
-- as ghost_submit does, so it can't be made up.

local Ghost = {}
Ghost.id = "ghost"

local function ghosts(self: any): any
	return self.mods.ghosts
end

local function floor(self: any): (number) -> number
	local race = self.mods.game("race")
	return function(pi: number): number
		return race.raceFloor(pi)
	end
end

-- Keeps the player's own par card (their race car and town) up to date for others to race.
local function card(self: any, s: any, userId: number)
	local car, myPi = self:_car(s)
	if car then
		ghosts(self):card(userId, { car = self.mods.data.carDef(car.model).name, model = car.model, color = car.color, pi = myPi, town = s.townName })
	end
end

-- The page: everyone here and friends with a ghost to race, your best, and taunts left for you.
function Ghost.list(self: any, s: any, _arg: any, userId: number): any
	card(self, s, userId)
	local people = {}
	local raceFloor = floor(self)
	for _, p in (self.mods.people :: any)(userId) do
		local g = ghosts(self):of(p.userId, raceFloor)
		if g then
			table.insert(people, { owner = p.userId, name = p.name, here = p.here, town = g.town, t = g.t, par = g.par, car = g.car, model = g.model, color = g.color, pi = g.pi })
		end
	end
	table.sort(people, function(a, b)
		if (a.here == true) ~= (b.here == true) then
			return a.here == true
		end
		return (a.t or math.huge) < (b.t or math.huge)
	end)
	local inbox = {}
	for _, t in ghosts(self):inbox(userId) do
		table.insert(inbox, { id = t.id, from = t.from, town = t.town, taunt = t.taunt, text = ghosts(self).tauntText(t.taunt), won = t.won, t = t.t, their = t.their })
	end
	return { people = people, inbox = inbox, best = ghosts(self):best(userId), fuel = self.mods.data.RACE_FUEL }
end

-- { taunt = id }: leaves a taunt from the last run ("sent", "limit" or "no").
-- { seen = { ids } }: clears taunts once read.
function Ghost.act(self: any, s: any, arg: any, userId: number): (any?, string?)
	if type(arg) ~= "table" then
		return nil, "not a taunt"
	end
	if arg.seen ~= nil then
		ghosts(self):seen(userId, arg.seen)
		return true, nil
	end
	return ghosts(self):taunt(userId, arg.taunt, s.townName), nil
end

-- arg: { vs = the player's UserId }.
function Ghost.start(self: any, s: any, arg: any, _car: any, _myPi: number, userId: number): (any?, string?)
	local vs = if type(arg) == "table" then arg.vs else nil
	if type(vs) ~= "number" or vs ~= math.floor(vs) or vs == userId then
		return nil, "pick a ghost"
	end
	card(self, s, userId)
	local g = ghosts(self):of(vs, floor(self))
	if not g or not g.t then
		return nil, "Their garage is empty. Nothing to race yet!"
	end
	return {
		rival = {
			id = "ghost",
			name = `👻 {g.town}`,
			carName = g.car,
			model = g.model,
			color = g.color,
			pi = g.pi,
			shift = 1,
			prize = 0,
		},
		venue = "main",
		weatherSeed = `ghost-{vs}`,
		ghost = g.t,
		extra = { vs = vs, their = g.t, par = g.par, town = g.town },
	},
		nil
end

function Ghost.finish(self: any, s: any, p: any, _won: boolean, myTime: number, _theirTime: number, result: any)
	local e = p.extra
	if myTime >= math.huge then
		result.ghost = { their = e.their, par = e.par, town = e.town }
		return
	end
	local race = self.mods.game("race")
	local myPi = p.spec.myPi
	local kept = math.round(math.max(myTime, race.raceFloor(myPi)) * 1000) / 1000
	local won = kept < e.their
	result.won = won
	local car = self.mods.raceCar.raceCarOf(s.cars, s.raceCar)
	ghosts(self):record(p.userId, kept, myPi, self.mods.data.carDef(p.model).name, p.model, if car then car.color else "#eceff1")
	ghosts(self):finished(p.userId, e.vs, kept, e.their, won)
	local taunts = {}
	for _, t in ghosts(self).TAUNTS do
		if won or not t.brag then
			table.insert(taunts, { id = t.id, text = t.text })
		end
	end
	result.ghost = { kept = kept, their = e.their, won = won, best = ghosts(self):best(p.userId), par = e.par, town = e.town, vs = e.vs, taunts = taunts }
end

return Ghost
