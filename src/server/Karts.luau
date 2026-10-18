--!strict
-- Kart races (the web game's ui/Kart.tsx KartGame, started from ui/Race.tsx): the Grand Prix's
-- rounds, Bumper Blast and a custom race, three laps round a kart circuit (game/kart.ts) against
-- five AI karts.
--
-- The server starts a race as the web's race screen does (Race.tsx startGp / startParty): it
-- checks the race is open, spends the fuel, and picks the grid (gpKartField / blastField), the
-- circuit, its rules and a seed. The client drives the race (Shared.Game.kart's KartRace, stepped
-- at the web's own 120 Hz) and reports where it finished and in what time. Steering can't be
-- replayed here cheaply, so the finish is checked for sense instead: a race must be waiting, it
-- counts once, and it can't have been run faster than a kart could physically go round, nor
-- sooner than it took. Then it pays through the web store's own actions: gpResult for a Grand
-- Prix round, finishRace with the party prize for the others.

local Karts = {}
Karts.__index = Karts

-- Bumper Blast's drivers (Race.tsx BLASTERS).
local BLASTERS = { "Crash Carla", "Dent Dexter", "Fender Fran", "Wreck Rex", "Smash Sami", "Bonk Benny", "Crunch Cleo", "Rumble Ray" }
-- The Grand Prix series' cups (Race.tsx GP_CUP).
local GP_CUP = { "🥉", "🏆", "🏆", "👑" }
local STOCK = { engine = 0, turbo = 0, tires = 0, weight = 0 }

-- The five lights before GO (Kart.tsx: one every 0.6 s from 1.2 s, then up to 0.4 s more).
Karts.LIGHTS = 0.6 + 6 * 0.6
-- The fastest a kart can ever go, as a share of its top speed: max boost (1.45) at the back of
-- the field (catch-up 1.05) in phantom mode (1.1), with some to spare.
Karts.TOP_SHARE = 1.7
-- The shortest way round three laps, as a share of the centre line: the inside of every bend.
Karts.LINE_SHARE = 0.8

export type Mods = {
	store: any,
	data: any,
	kart: any,
	gpBeat: any,
	raceCar: any,
	fairRace: any,
	boosts: any,
	random: any,
	clock: () -> number,
}

type Pending = {
	kind: string,
	series: string?,
	round: number?,
	field: number,
	prize: number,
	minTime: number,
	startedAt: number,
}

export type Karts = typeof(setmetatable({} :: { towns: any, mods: Mods, pending: { [number]: Pending } }, Karts))

function Karts.new(towns: any, mods: Mods): Karts
	return setmetatable({ towns = towns, mods = mods, pending = {} }, Karts)
end

local function round(x: number): number
	return math.floor(x + 0.5)
end

local function piOf(data: any, car: any): number
	return data.performance(data.carDef(car.model), car.upgrades, car.mods)
end

-- A Grand Prix round's named rival (Race.tsx gpRival): the car nearest their PI, in one of its colours.
function Karts.gpRival(self: Karts, series: any, r: number, clears: number): any
	local data, fairRace = self.mods.data, self.mods.fairRace
	local target = data.gpRivalPi(series, r, clears)
	local car = fairRace.carNear(target)
	return { name = series.rivals[r + 1], pi = target, model = car.id, color = car.colors[r % #car.colors + 1], carName = car.name }
end

-- The car PI the series' final needs before it counts (Race.tsx gpFinalNeed; 0 before the final).
function Karts.finalNeed(self: Karts, series: any, clears: number, r: number): number
	local data = self.mods.data
	if r ~= data.GP_ROUNDS - 1 then
		return 0
	end
	local need = self.mods.gpBeat.gpClearPi(data.gpRivalPi(series, data.GP_ROUNDS - 1, clears))
	return if need == nil or need ~= need then math.huge else need
end

-- One kart on the grid: its driver and the car it looks like (ChaseCar).
local function racer(data: any, name: string, pi: number, ai: boolean, skill: number?, car: any): any
	return {
		name = name,
		pi = pi,
		ai = ai,
		skill = skill,
		weight = data.carDef(car.model).weight,
		model = car.model,
		color = car.color,
		finish = car.finish,
		skin = car.skin,
		modSkin = car.modSkin,
		panels = car.panels,
		mods = car.mods,
		trim = car.trim,
		hat = car.hat,
		stripe = car.stripe,
	}
end

-- A Grand Prix round's grid (Race.tsx gpKartField): the round's rival in their usual car and PI,
-- the rest of the series' cast a little slower, and the player at the back.
function Karts._gpField(self: Karts, series: any, r: number, rival: any, car: any): { any }
	local data, fairRace, kart = self.mods.data, self.mods.fairRace, self.mods.kart
	local grid = kart.gpField(series.rivals, r, rival.pi, { name = "You", pi = piOf(data, car) })
	local out = {}
	for i, f in grid do
		if not f.ai then
			out[i] = racer(data, "You", f.pi, false, nil, car)
		else
			local c = if f.name == rival.name then data.carDef(rival.model) else fairRace.carNear(f.pi)
			local color = if f.name == rival.name then rival.color else c.colors[(i - 1) % #c.colors + 1]
			out[i] = racer(data, f.name, f.pi, true, f.skill, { model = c.id, color = color })
		end
	end
	return out
end

-- A party race's grid (Race.tsx blastField): five rivals in random cars at rivalPi, then the player.
function Karts._partyField(self: Karts, car: any, rivalPi: number): { any }
	local data, rng = self.mods.data, self.mods.random
	local names = table.clone(BLASTERS)
	for i = #names, 2, -1 do
		local j = rng:NextInteger(1, i)
		names[i], names[j] = names[j], names[i]
	end
	local out = {}
	for i = 1, 5 do
		local c = data.CARS[rng:NextInteger(1, #data.CARS)]
		out[i] = racer(data, names[i], rivalPi, true, 0.45 + (i - 1) * 0.1, { model = c.id, color = c.colors[(i - 1) % #c.colors + 1] })
	end
	out[6] = racer(data, "You", piOf(data, car), false, nil, car)
	return out
end

-- The quickest three laps of this circuit could ever take with this grid.
function Karts.minTime(self: Karts, track: any, field: { any }, rules: any): number
	local kart = self.mods.kart
	local top = 0
	for _, f in field do
		top = math.max(top, kart.kartStats(if rules.blast then kart.BLAST_PI else f.pi).top)
	end
	return kart.LAPS * track.len * Karts.LINE_SHARE / (top * Karts.TOP_SHARE)
end

local function bool(v: any): boolean?
	if v == nil or v == false then
		return false
	end
	return if v == true then true else nil
end

-- Starts a kart race. kind "gp" with the series id, "blast" for Bumper Blast, or "custom" with
-- { track (0-based), reverse, rules = { obstacles, blast, maxBoost } }. Returns what the client
-- needs to run it, or nil and why.
function Karts.start(self: Karts, userId: number, kind: any, arg: any): (any?, string?)
	local m = self.mods
	local data, store, kart, raceCar = m.data, m.store, m.kart, m.raceCar
	local out: any = nil
	local why: string? = nil
	if kind ~= "gp" and kind ~= "blast" and kind ~= "custom" then
		return nil, "not a race"
	end
	-- A custom race's pick, checked before anything is spent.
	local pick: any = nil
	if kind == "custom" then
		if type(arg) ~= "table" or type(arg.track) ~= "number" or arg.track ~= math.floor(arg.track) or not kart.TRACKS[arg.track + 1] then
			return nil, "pick a circuit"
		end
		local rules = if type(arg.rules) == "table" then arg.rules else {}
		local reverse, ob, bl, mb = bool(arg.reverse), bool(rules.obstacles), bool(rules.blast), bool(rules.maxBoost)
		if reverse == nil or ob == nil or bl == nil or mb == nil then
			return nil, "pick the rules"
		end
		pick = { track = arg.track, reverse = reverse, rules = { obstacles = ob, blast = bl, maxBoost = mb } }
	elseif kind == "blast" then
		-- Race.tsx blastPick: any circuit, either way round.
		pick = { track = m.random:NextInteger(0, #kart.TRACKS - 1), reverse = m.random:NextNumber() < 0.5, rules = { blast = true } }
	end
	self.towns:_with(userId, function(s: any)
		s.tick(self.towns.now())
		local car = raceCar.raceCarOf(s.cars, s.raceCar)
		if not car then
			why = "You need a car to race"
			return
		end
		local field, def, reverse, rules, prize, title
		local series: any, r: number? = nil, nil
		if kind == "gp" then
			local si = nil
			for i, sr in data.GP_SERIES do
				if sr.id == arg then
					series, si = sr, i - 1
				end
			end
			if not series then
				why = "pick a Grand Prix"
				return
			end
			local gp = s.gp or {}
			local prog = gp[series.id] or { round = 0, clears = 0 }
			if not data.gpOpen(gp, si, store.gateLevel(s)) then
				s.showNeed("level", series.unlockLevel, series.name)
				why = "That race isn't open yet"
				return
			end
			if #s.cars < series.minCars then
				why = `This cup needs {series.minCars} cars in your garage`
				return
			end
			r = prog.round
			local need = self:finalNeed(series, prog.clears or 0, r :: number)
			local best = raceCar.bestCar(s.cars)
			if need > 0 and (if best then piOf(data, best) else 0) < need then
				why = `The final needs a car with PI {need} or more`
				s.toast(why)
				return
			end
			if not store.spendFuel(data.RACE_FUEL) then
				s.showNeed("fuel", data.RACE_FUEL - s.fuel, "a Grand Prix race")
				why = "need fuel"
				return
			end
			local rival = self:gpRival(series, r :: number, prog.clears or 0)
			local tr = kart.gpTrack(r)
			def, reverse = tr.def, tr.reverse
			rules = { obstacles = reverse }
			field = self:_gpField(series, r :: number, rival, car)
			prize = data.gpReward(series, r)
			title = `{GP_CUP[si + 1] or "🏆"} {(r :: number) + 1}/{data.GP_ROUNDS} · {def.icon} {def.short}{if reverse then " ↺" else ""}`
		else
			if not store.spendFuel(data.RACE_FUEL) then
				s.showNeed("fuel", data.RACE_FUEL - s.fuel, "a race")
				why = "need fuel"
				return
			end
			def, reverse, rules = kart.TRACKS[pick.track + 1], pick.reverse, pick.rules
			field = self:_partyField(car, if rules.blast then kart.BLAST_PI else piOf(data, car))
			prize = kart.partyPrize(s.level)
			title = if kind == "custom" then `🛠️ Custom · {def.icon} {def.short}{if reverse then " ↺" else ""}` else `💥 Bumper Blast · {def.icon} {def.short}`
		end
		local track = kart.buildTrack(def, reverse)
		local trackIndex = 0
		for i, t in kart.TRACKS do
			if t == def then
				trackIndex = i - 1
			end
		end
		self.pending[userId] = {
			kind = kind,
			series = if series then series.id else nil,
			round = r,
			field = #field,
			prize = prize,
			minTime = self:minTime(track, field, rules),
			startedAt = m.clock(),
		}
		out = {
			kind = kind,
			series = if series then series.id else nil,
			round = r,
			track = trackIndex,
			reverse = reverse,
			rules = rules,
			field = field,
			seed = m.random:NextInteger(0, 999999),
			prize = prize,
			title = title,
			pick = if kind == "custom" then pick else nil,
		}
	end)
	if not out then
		return nil, why
	end
	return out
end

-- Finishes the race started last: the player's place (1 = first) and time over the line.
-- Returns what the podium shows, or nil and why.
function Karts.finish(self: Karts, userId: number, arg: any): (any?, string?)
	local p = self.pending[userId]
	if not p then
		return nil, "no race"
	end
	local place = type(arg) == "table" and arg.place
	local time = type(arg) == "table" and arg.time
	if type(place) ~= "number" or place ~= math.floor(place) or place < 1 or place > p.field or type(time) ~= "number" or time ~= time or time == math.huge then
		self.pending[userId] = nil
		return nil, "bad race"
	end
	-- One finish per start, and no faster than a kart could go round, nor sooner than it took.
	self.pending[userId] = nil
	local took = self.mods.clock() - p.startedAt
	if time < p.minTime or took < (Karts.LIGHTS + time) * 0.85 then
		return nil, "too quick"
	end
	local won = place == 1
	local result: any = { place = place, time = time, won = won }
	self.towns:_with(userId, function(s: any)
		local store = self.mods.store
		local before = { coins = s.coins, xp = s.xp, level = s.level, trophies = s.trophies, bucks = s.bucks, cars = #s.cars }
		local act = store.useGame.getState
		if p.kind == "gp" then
			act().gpResult(p.series, won, place, p.field)
		else
			act().finishRace(won, p.prize)
		end
		local after = act()
		result.coins = after.coins - before.coins
		result.trophies = after.trophies - before.trophies
		result.bucks = after.bucks - before.bucks
		result.xp = if after.xp == before.xp and after.level == before.level then 0 else store.lastRaceXpPaid()
		result.levelUp = after.level > before.level
		-- The series won: the mystery box's car (the town's gpPrize pop-up shows it).
		if p.kind == "gp" and #after.cars > before.cars and after.gpPrize then
			result.gpPrize = { series = after.gpPrize.series, model = after.gpPrize.model, color = after.gpPrize.color }
		end
		if p.kind == "gp" then
			local prog = (after.gp or {})[p.series :: string] or { round = 0, clears = 0 }
			result.gp = { round = prog.round or 0, clears = prog.clears or 0 }
		end
	end)
	return result
end

function Karts.close(self: Karts, userId: number)
	self.pending[userId] = nil
end

return Karts
