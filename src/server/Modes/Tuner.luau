--!strict
-- Tuner Trials (game/tuner.ts, ui/TunerTrials.tsx): races you can only enter in a car built for
-- them. Each trial names the parts that must be fitted and how far the engine and turbo must be
-- tuned; the host drives a car already built that way (hostMods), at the trial's own venue,
-- distance and sky. Paid by the web store's tunerResult (double the first time); the first win of
-- some trials unlocks a custom paint pattern, shown on the result card.

local Tuner = {}
Tuner.id = "tuner"

function Tuner.start(self: any, s: any, arg: any, car: any, _myPi: number): (any?, string?)
	local game = self.mods.game
	local tuner, data, fairRace = game("tuner"), self.mods.data, self.mods.fairRace
	local t = if type(arg) == "string" then tuner.tunerTrial(arg) else nil
	if not t then
		return nil, "pick a trial"
	end
	-- Race.tsx startTuner: only in a car built for it (the page sends you to the Garage otherwise).
	if not tuner.buildReady(t, car) then
		return nil, "Fit the parts this trial asks for first"
	end
	local hc = data.carDef(t.car)
	local shift = tuner.tunerShift(t)
	local skill = if t.tier >= 2 then hc.skill else nil
	local wins = (s.tuner or {})[t.id] or 0
	-- Race.tsx trialRival.
	return {
		rival = {
			id = `tuner-{t.id}`,
			name = `{t.icon} {t.host}`,
			carName = hc.name,
			model = hc.id,
			color = t.color,
			mods = tuner.hostMods(t),
			pi = fairRace.fairNow(t.pi, shift, skill),
			shift = shift,
			skill = skill,
			boss = t.tier == 3,
			prize = tuner.tunerPrize(t, wins == 0),
			icon = t.icon,
			tier = t.tier,
			wins = wins,
			venue = t.venue,
			dist = t.dist,
			night = t.night,
		},
		venue = t.venue,
		dist = t.dist,
		night = t.night,
		weatherSeed = `tuner-{t.id}`,
		extra = { id = t.id },
	},
		nil
end

function Tuner.finish(self: any, s: any, p: any, won: boolean, _myTime: number, _theirTime: number, result: any)
	local id = p.extra.id
	local t = self.mods.game("tuner").tunerTrial(id)
	local first = ((s.tuner or {})[id] or 0) == 0
	local store = self.mods.store.useGame.getState
	store().tunerResult(id, won)
	-- The web's TunerPrizePopup: here the result card shows the pattern instead.
	if store().tunerPrize ~= nil then
		store().closeTunerPrize()
	end
	result.wins = (store().tuner or {})[id] or 0
	if won and first and t and t.pattern then
		result.pattern = t.pattern
	end
end

return Tuner
