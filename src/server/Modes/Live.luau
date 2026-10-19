--!strict
-- Live drag races against another player in this server (server/Duels; the web game's live
-- challenges, lib/live.ts). Each racer's game races its own car; the rival on the strip is the
-- other player, drawn from where their game says their car is. Who won goes by the server's own
-- replay of both runs, and the winner gets the web's live prize, 300 + 8 a point of the loser's PI
-- (Race.tsx liveReward); a loss pays the live share of it, as finishRace does for live races.

local Live = {}
Live.id = "live"

-- The web's liveReward.
function Live.prize(pi: number): number
	return 300 + pi * 8
end

-- arg: { duel = the race's id }, once both have said yes.
function Live.start(self: any, _s: any, arg: any, _car: any, _myPi: number, userId: number): (any?, string?)
	local duels = self.mods.duels
	local id, vs = duels:racing(userId)
	if not id or type(arg) ~= "table" or arg.duel ~= id then
		return nil, "That race is over"
	end
	local card = self.mods.liveCard(vs) or {}
	local pi = tonumber(card.pi) or 1
	return {
		rival = {
			id = `live:{vs}`,
			name = card.name or "Racer",
			carName = card.carName or "Car",
			model = card.model or "pip",
			color = card.color or "#eceff1",
			mods = card.mods,
			panels = card.panels,
			trim = card.trim,
			skin = card.skin,
			modSkin = card.modSkin,
			pi = pi,
			shift = 1,
			prize = Live.prize(pi),
		},
		-- Both racers get the same street and sky.
		venue = self.mods.venues.pickVenue(id).id,
		weatherSeed = id,
		extra = { duel = id, vs = vs },
	},
		nil
end

-- p.extra.their: the other racer's time (server/Duels.finish, before this runs), or math.huge.
function Live.finish(self: any, _s: any, p: any, _won: boolean, myTime: number, _theirTime: number, result: any)
	local their = p.extra.their or math.huge
	local won = myTime < math.huge and myTime <= their
	result.won = won
	result.theirTime = their
	result.live = true
	self.mods.store.useGame.getState().finishRace(won, p.rival.prize, { live = true })
end

return Live
