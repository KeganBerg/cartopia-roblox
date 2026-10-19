--!strict
-- War races (the web game's crew war map, 0114 and lib/warMap.ts): race a rival crew member's
-- ghost, or a street crew driver's par for your own car, for stars and war points for your crew
-- (server/CrewBattles). Timed like ghost races: the server's own replay of the run, raised to the
-- referee's floor for the car's PI. No prizes of its own: the war chests pay for the points.

local War = {}
War.id = "war"

-- arg: { target = a rival member's UserId (as text), or "bot1".. }.
function War.start(self: any, s: any, arg: any, _car: any, myPi: number, userId: number): (any?, string?)
	local war = self.mods.crewWar
	if not war then
		return nil, "no war"
	end
	local crewId = war.crewOf(userId)
	if not crewId then
		return nil, "no crew"
	end
	-- (Fuel first: starting counts one of the day's war races.)
	local fuel = self.mods.data.RACE_FUEL
	if (s.fuel or 0) < fuel then
		s.showNeed("fuel", fuel - (s.fuel or 0), "a war race")
		return nil, "need fuel"
	end
	local race = self.mods.game("race")
	local target = if type(arg) == "table" then arg.target else nil
	local spot, why = war.battles:attackStart(userId, crewId, target, race.raceFloor(myPi))
	if not spot then
		return nil, why
	end
	return {
		rival = {
			id = "war",
			name = `⚔️ {spot.name}`,
			carName = spot.car or "Street car",
			model = spot.model or "pip",
			color = spot.color or "#eceff1",
			pi = spot.pi or myPi,
			shift = 1,
			prize = 0,
		},
		venue = "main",
		weatherSeed = `war-{spot.battle}-{spot.target}`,
		ghost = spot.their,
		extra = { war = spot, crew = crewId, town = s.townName },
	},
		nil
end

function War.finish(self: any, _s: any, p: any, _won: boolean, myTime: number, _theirTime: number, result: any)
	local war = self.mods.crewWar
	local e = p.extra
	local race = self.mods.game("race")
	local kept = if myTime < math.huge then math.round(math.max(myTime, race.raceFloor(p.spec.myPi)) * 1000) / 1000 else math.huge
	local name = war.nameOf(p.userId)
	-- Points go to the crew the race started for, while the racer is still in it.
	local r = war.battles:attackFinish(p.userId, e.crew, name, e.war, kept, war.crewOf(p.userId) == e.crew)
	result.won = r.won
	result.war = { won = r.won, stars = r.stars, points = r.points, kept = if kept < math.huge then kept else nil, their = r.their, name = e.war.name, left = war.battles:attacksLeft(p.userId) }
end

return War
