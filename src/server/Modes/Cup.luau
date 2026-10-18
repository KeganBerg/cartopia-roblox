--!strict
-- Class Cups (game/cups.ts, ui/ClassCups.tsx): three races per car class that only a car of that
-- class can enter. The host is a car of the class itself (Race.tsx cupRival), eased like every
-- rival. Paid by the web store's cupResult: double the first time, and the first win in each race
-- gives a free crate (the town's freeCrates, opened at the Crate Depot).

local Cup = {}
Cup.id = "cup"

function Cup.start(self: any, s: any, arg: any, car: any, _myPi: number): (any?, string?)
	local game = self.mods.game
	local cups, classes, data, fairRace = game("cups"), game("classes"), self.mods.data, self.mods.fairRace
	local r = if type(arg) == "string" then cups.cupRace(arg) else nil
	if not r then
		return nil, "pick a race"
	end
	local cls = classes.carClass(r.cls)
	if not cups.cupFits(r, car.model) then
		return nil, `Race with a {cls.name} car for this cup`
	end
	local host = data.carDef(r.car)
	local shift = cups.cupShift(r)
	local skill = if r.tier >= 2 then host.skill else nil
	local wins = (s.cups or {})[r.id] or 0
	return {
		rival = {
			id = `cup-{r.id}`,
			name = `{cls.icon} {host.name}`,
			carName = host.name,
			model = host.id,
			color = r.color,
			pi = fairRace.fairNow(r.pi, shift, skill),
			shift = shift,
			skill = skill,
			boss = r.tier == 3,
			prize = cups.cupPrize(r, wins == 0),
			wins = wins,
		},
		venue = r.venue,
		dist = r.dist,
		night = r.night,
		weatherSeed = `cup-{r.id}`,
		extra = { id = r.id },
	},
		nil
end

function Cup.finish(self: any, s: any, p: any, won: boolean, _myTime: number, _theirTime: number, result: any)
	local cups = self.mods.game("cups")
	local useGame = self.mods.store.useGame
	local id = p.extra.id
	local r = cups.cupRace(id)
	local before = (s.cups or {})[id] or 0
	local classBefore = cups.cupWon(s.cups, r.cls)
	useGame.getState().cupResult(id, won)
	local after = useGame.getState()
	result.cupWins = (after.cups or {})[id] or 0
	-- The first win's free crate (ClassCups.tsx CupPrizePopup), shown on the result card instead.
	if won and before == 0 then
		result.cupCrate = cups.CUP_CRATE
	end
	-- The whole class's cup, won for the first time.
	if won and not classBefore and cups.cupWon(after.cups, r.cls) then
		result.cupClass = r.cls
	end
	if after.cupPrize ~= nil then
		useGame.getState().closeCupPrize()
	end
end

return Cup
