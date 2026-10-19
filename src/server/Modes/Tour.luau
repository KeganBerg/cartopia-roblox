--!strict
-- The Pro Tour (game/tour.ts, Race.tsx startTour/tourRival): the endless ladder that opens once
-- the campaign's first chapter is cleared. Legs of five races at a venue (the fifth a boss), the
-- rivals climbing in PI, the distance stepping up within each leg. The race is always the next one
-- (the races won so far); the web store's tourResult pays it and, for a boss, the leg bonus with
-- the prize card (Race.tsx TourPrizePopup).

local Tour = {}
Tour.id = "tour"

function Tour.start(self: any, s: any, _arg: any, _car: any, _myPi: number): (any?, string?)
	local game, data = self.mods.game, self.mods.data
	if not data.campaignCleared(s.campaign, data.CAMPAIGN[1]) then
		return nil, `Clear {data.CAMPAIGN[1].name} to open the Pro Tour`
	end
	local tour = game("tour")
	local race = s.tour or 0
	local leg = tour.tourLeg(tour.tourLegOf(race))
	return {
		rival = self.mods.tourRivals.tour(game, race),
		venue = leg.venue,
		dist = game("distance").tourDist(race),
		night = leg.night,
		weatherSeed = `tour-{race}`,
		extra = { race = race },
	},
		nil
end

function Tour.finish(self: any, _s: any, p: any, won: boolean, _myTime: number, _theirTime: number, result: any)
	local useGame = self.mods.store.useGame
	useGame.getState().tourResult(won, p.rival.pi)
	local after = useGame.getState()
	result.tour = after.tour or 0
	-- The boss's leg bonus (TourPrizePopup), shown once the race screen is gone.
	local tour = self.mods.game("tour")
	result.legBonus = if won and tour.tourIsBoss(p.extra.race) then tour.tourLegBonus(tour.tourLegOf(p.extra.race)) else nil
end

return Tour
