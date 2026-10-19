--!strict
-- The Pro Tour's and the weekly event's rivals (ui/Race.tsx tourRival, eventRival), shared by the
-- server's race modes (server/Modes/Tour, Event) and their pages in the race menu, so the rows on
-- the page are the races the server starts. Each rival brings the car nearest its PI and is eased
-- to what the player's race car can beat (Race.tsx fair, fairRace.fairNow).
--
-- `game(name)` gives a converted rules module (Shared.Game), so the tests can run it in plain Luau.

local TourRivals = {}

export type Rival = {
	id: string,
	name: string,
	carName: string,
	model: string,
	color: string,
	pi: number,
	shift: number,
	skill: string?,
	boss: boolean,
	prize: number,
}

-- The Pro Tour's race number `race` (the races won so far), over its distance.
function TourRivals.tour(game: (string) -> any, race: number): Rival
	local tour, fairRace, distance = game("tour"), game("fairRace"), game("distance")
	local target = tour.tourRivalPi(race)
	local car = fairRace.carNear(target)
	local shift = tour.tourShift(race)
	local skill = if tour.tourSkills(race) then car.skill else nil
	local pi = fairRace.fairNow(target, shift, skill, distance.DIST[distance.tourDist(race)].m)
	return {
		id = `tour-{race}`,
		name = tour.tourRivalName(race),
		carName = car.name,
		model = car.id,
		color = car.colors[race % #car.colors + 1],
		pi = pi,
		shift = shift,
		skill = skill,
		boss = tour.tourIsBoss(race),
		-- What the web's race button shows and tourResult pays (fairRace.tourPayNow).
		prize = tour.tourPrize(race, pi),
	}
end

-- This week's event's race `race` (0-4), around `base`: the PI the player entered with.
function TourRivals.event(game: (string) -> any, base: number, race: number, week: string?): Rival
	local events, fairRace = game("events"), game("fairRace")
	local e = events.eventFor(week)
	local target = events.eventRivalPi(base, race)
	local car = fairRace.carNear(target)
	local shift = events.eventShift(race)
	local skill = if race >= 2 then car.skill else nil
	return {
		id = `event-{e.id}-{race}`,
		name = e.rivals[race + 1],
		carName = car.name,
		model = car.id,
		color = car.colors[race % #car.colors + 1],
		pi = fairRace.fairNow(target, shift, skill),
		shift = shift,
		skill = skill,
		boss = events.eventIsBoss(race),
		prize = events.eventPrize(base, race),
	}
end

return TourRivals
