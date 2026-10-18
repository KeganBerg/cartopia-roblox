--!strict
-- The World Tour (game/worldTour.ts, ui/WorldTour.tsx): nine racers, one per country, beaten in
-- order once the player's reputation reaches Street Racer. Each brings a random car near their PI
-- (from the five closest) and races at their own venue, distance and sky. Paid by the web store's
-- worldTourResult (double the first time), which also unlocks Tour Blue after the last one.

local World = {}
World.id = "world"

function World.start(self: any, s: any, arg: any, _car: any, _myPi: number): (any?, string?)
	local game = self.mods.game
	local wt, reputation, data, fairRace = game("worldTour"), game("reputation"), self.mods.data, self.mods.fairRace
	if type(arg) ~= "number" or arg ~= math.floor(arg) then
		return nil, "pick a race"
	end
	local i = arg
	local r = wt.WORLD_TOUR[i + 1]
	local beaten = s.worldTour or 0
	if not r or i > beaten then
		return nil, "That race isn't open yet"
	end
	local rep = reputation.reputation({ trophies = s.trophies, stats = s.stats, cups = s.cups, mastery = s.mastery })
	if rep.tier < wt.WORLD_TOUR_REP then
		return nil, `Reach {reputation.REP_TITLES[wt.WORLD_TOUR_REP + 1].name} to start the World Tour`
	end
	local rng = self.mods.random
	local car = wt.worldCar(i, function()
		return rng:NextNumber()
	end)
	local shift = wt.worldShift(i)
	local skill = if i >= 3 then car.skill else nil
	local track = self.mods.distance.DIST[r.dist].m
	return {
		rival = {
			id = `world-{i}`,
			name = `{r.flag} {r.name}`,
			carName = car.name,
			model = car.id,
			color = car.colors[rng:NextInteger(1, #car.colors)],
			pi = fairRace.fairNow(r.pi, shift, skill, track),
			shift = shift,
			skill = skill,
			boss = i == #wt.WORLD_TOUR - 1,
			prize = wt.worldPrize(i, i == beaten),
			line = r.hello,
		},
		venue = r.venue,
		dist = r.dist,
		night = r.night,
		weatherSeed = `world-{i}`,
		extra = { i = i },
	},
		nil
end

function World.finish(self: any, s: any, p: any, won: boolean, _myTime: number, _theirTime: number, result: any)
	local i = p.extra.i
	local before = s.worldTour or 0
	self.mods.store.useGame.getState().worldTourResult(i, won)
	local after = self.mods.store.useGame.getState().worldTour or 0
	result.beaten = after
	result.champion = after > before and after >= #self.mods.game("worldTour").WORLD_TOUR
end

return World
