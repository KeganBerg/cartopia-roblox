--!strict
-- A street race against the street racer visiting town (lib/visitors.ts, Race.tsx's street race):
-- a drag race against their car at their PI, free of fuel, once per visitor. It pays the race's own
-- prize through the web store's finishRace, as any race; beating them also collects the visitor's
-- bonus (server/Visitors finishStreet, the web's claimVisitor), and losing sends them off.
-- `which` is the visitor's id; the visitors desk is the Races mods' `visitors`.

local Street = {}
Street.id = "street"

function Street.start(self: any, _s: any, arg: any, _car: any, _myPi: number, userId: number): (any?, string?)
	local visitors = self.mods.visitors
	if not visitors then
		return nil, "not a race"
	end
	local v, why = visitors:startStreet(userId, arg)
	if not v then
		return nil, why
	end
	return {
		rival = visitors:rival(v),
		fuel = false,
		extra = { id = v.id, coins = v.coins, parts = v.parts, bucks = v.bucks },
	},
		nil
end

function Street.finish(self: any, s: any, p: any, won: boolean, _myTime: number, _theirTime: number, result: any)
	self.mods.store.useGame.getState().finishRace(won, p.rival.prize)
	local paid = self.mods.visitors:finishStreet(s, p.userId, p.extra.id, won)
	result.street = { won = won, paid = paid }
end

return Street
