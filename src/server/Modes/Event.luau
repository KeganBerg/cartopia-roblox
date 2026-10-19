--!strict
-- The weekly event (game/events.ts, Race.tsx startEvent/eventRival): this week's venue and sky,
-- five rivals around the PI the player entered with (kept for the week by the web store's
-- eventEnter), the last a boss. Beating the boss wins the event's skin and a bonus (twice over
-- when the skin's already owned), paid by the web store's eventResult with the prize card
-- (Race.tsx EventPrizePopup). Once all five are won it waits for next week's event.

local Event = {}
Event.id = "event"

-- The PI the player races this week's event at: the one they entered with, else their best car's.
function Event.base(self: any, s: any): number
	local p = self.mods.game("events").eventProgress(s.event)
	if p and p.pi then
		return p.pi
	end
	local best = self.mods.raceCar.bestCar(s.cars)
	return if best then self.mods.raceCar.carPi(best) else 0
end

function Event.start(self: any, s: any, _arg: any, _car: any, _myPi: number): (any?, string?)
	local game, data = self.mods.game, self.mods.data
	local events = game("events")
	local p = events.eventProgress(s.event)
	if p and p.won >= events.EVENT_RACES then
		return nil, "Event cleared! Back next week"
	end
	-- Entering locks the PI in for the week, so only once the race can start (fuel and all).
	if s.fuel < data.RACE_FUEL then
		s.showNeed("fuel", data.RACE_FUEL - s.fuel, "an event race")
		return nil, "need fuel"
	end
	s.eventEnter(Event.base(self, s))
	p = events.eventProgress(self.mods.store.useGame.getState().event)
	local e = events.eventFor(p.week)
	return {
		rival = self.mods.tourRivals.event(game, p.pi, p.won, p.week),
		venue = e.venue,
		night = e.night,
		sky = e.sky,
		weatherSeed = `event-{p.week}-{p.won}`,
		extra = { week = p.week, race = p.won },
	},
		nil
end

function Event.finish(self: any, _s: any, p: any, won: boolean, _myTime: number, _theirTime: number, result: any)
	local useGame = self.mods.store.useGame
	useGame.getState().eventResult(won)
	local after = useGame.getState()
	result.event = after.event
	-- The boss's skin and bonus (EventPrizePopup), shown once the race screen is gone.
	result.eventPrize = if won and self.mods.game("events").eventIsBoss(p.extra.race) then after.eventPrize else nil
end

return Event
