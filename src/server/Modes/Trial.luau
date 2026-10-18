--!strict
-- The weekly Time Trial (game/trial.ts, ui/TimeTrial.tsx, lib/trialServer.ts): one venue a week,
-- a solo run against a ghost, and a board of everyone's best times that starts over every Monday
-- 00:00 UTC. A run chases the player's own best this week, or a par time for their car until they
-- have one. Times go on the board kept by server/Boards ("trial"); last week's place pays a prize
-- (TRIAL_PRIZES) through the web store's claimTrialPrize.
--
-- The time is the server's own replay of the run, so it can't be made up.

local Trial = {}
Trial.id = "trial"

local MEDAL = { "🥇", "🥈", "🥉" }

local function board(self: any): any
	return self.mods.boards.trial
end

-- What a run chases: the player's best this week, else par for their car.
local function target(self: any, week: string, userId: number, myPi: number): (number, string)
	local best = board(self):best(week, userId)
	if best then
		return best, "Your best"
	end
	local race = self.mods.game("race")
	return math.round(race.raceFloor(myPi) * 1.3 * 100) / 100, "Par"
end

-- The car a row on the board shows (its paint, finish and parts), as trialServer.ts boardLook.
local function look(car: any): any
	local out = { model = car.model, color = car.color }
	for _, k in { "finish", "skin", "modSkin", "panels", "trim", "mods", "hat", "stripe" } do
		if car[k] ~= nil then
			out[k] = car[k]
		end
	end
	return out
end

-- The page: this week's venue and board, the player's best and place, and last weeks' prizes
-- not yet claimed.
function Trial.list(self: any, s: any, _arg: any, userId: number): any
	local trial, data = self.mods.game("trial"), self.mods.data
	local week = trial.trialWeek()
	local b = board(self):board(week, userId, 10)
	local prizes = {}
	for w, t in board(self):weeks(userId) do
		if w < week and (s.trials.claimed or {})[w] == nil then
			local place = board(self):place(w, t)
			local p = trial.trialPrize(place)
			table.insert(prizes, { week = w, place = place, t = t, bucks = p.bucks, coins = p.coins, trophies = p.trophies })
		end
	end
	table.sort(prizes, function(a, c)
		return a.week < c.week
	end)
	local car, myPi = self:_car(s)
	local chase, ghost = target(self, week, userId, if car then myPi else 10)
	return {
		week = week,
		venue = trial.trialVenue(week).id,
		leftMs = data.msToNextWeek(),
		board = b,
		prizes = prizes,
		target = chase,
		ghost = ghost,
	}
end

-- Claims last week's prize (arg: the week).
function Trial.act(self: any, s: any, arg: any, userId: number): (any?, string?)
	local trial = self.mods.game("trial")
	if type(arg) ~= "table" or type(arg.claim) ~= "string" then
		return nil, "not a prize"
	end
	local week = arg.claim
	if week >= trial.trialWeek() then
		return nil, "That week isn't over yet"
	end
	if (s.trials.claimed or {})[week] ~= nil then
		return nil, "Already claimed"
	end
	local t = board(self):weeks(userId)[week]
	if not t then
		return nil, "No time that week"
	end
	local place = board(self):place(week, t)
	self.mods.store.useGame.getState().claimTrialPrize(week, place)
	local p = trial.trialPrize(place)
	return { week = week, place = place, medal = MEDAL[place] or `#{place}`, bucks = p.bucks, coins = p.coins, trophies = p.trophies }, nil
end

function Trial.start(self: any, _s: any, _arg: any, car: any, myPi: number, userId: number): (any?, string?)
	local trial, data = self.mods.game("trial"), self.mods.data
	local week = trial.trialWeek()
	local v = trial.trialVenue(week)
	local chase, ghost = target(self, week, userId, myPi)
	local def = data.carDef(car.model)
	return {
		rival = {
			id = "trial",
			name = `👻 {ghost}`,
			carName = def.name,
			model = def.id,
			color = "#eceff1",
			pi = myPi,
			shift = 1,
			prize = 0,
		},
		venue = v.id,
		weatherSeed = `trial-{week}`,
		ghost = chase,
		extra = { week = week, target = chase, ghost = ghost, before = board(self):best(week, userId) },
	},
		nil
end

function Trial.finish(self: any, s: any, p: any, _won: boolean, myTime: number, _theirTime: number, result: any)
	local e = p.extra
	if myTime >= math.huge then
		result.trial = { target = e.target, ghost = e.ghost, before = e.before }
		return
	end
	local car = self.mods.raceCar.raceCarOf(s.cars, s.raceCar)
	local row = {
		town = s.townName,
		pi = p.spec.myPi,
		car = self.mods.data.carDef(p.model).name,
		look = if car then look(car) else { model = p.model },
	}
	local kept = board(self):submit(e.week, p.userId, myTime, row)
	local place, total = board(self):place(e.week, kept)
	result.trial = { t = myTime, kept = kept, before = e.before, target = e.target, ghost = e.ghost, place = place, total = total }
end

return Trial
