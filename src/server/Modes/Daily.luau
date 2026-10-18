--!strict
-- The Daily Run (game/daily.ts, ui/DailyRun.tsx, Race.tsx startDaily): one quarter-mile run a day
-- that's the same for everyone: the day's venue and weather (seeded `daily-<day>`) and the day's
-- stock loaner car, raced against the par ghost. It costs a time trial's fuel (TRIAL_FUEL) and can
-- be run as often as you like; the web store's dailyResult keeps the day's best in the save and
-- pays the first run of the day (DAILY_PAY by medal).

local Daily = {}
Daily.id = "daily"

local ZERO = { engine = 0, turbo = 0, tires = 0, weight = 0 }

function Daily.start(self: any, s: any, _arg: any, _car: any, _myPi: number): (any?, string?)
	local game = self.mods.game
	local daily, trial = game("daily"), game("trial")
	local run = daily.dailyRun()
	-- A time trial's fuel, not a race's (Race.tsx startDaily).
	if not self.mods.store.spendFuel(trial.TRIAL_FUEL) then
		s.showNeed("fuel", trial.TRIAL_FUEL - s.fuel, "the Daily Run")
		return nil, "need fuel"
	end
	return {
		-- The par ghost (Race.tsx's `daily` DragRace): id "trial", so mastery leaves it out.
		rival = {
			id = "trial",
			name = "👻 Par",
			carName = run.car.name,
			model = run.car.id,
			color = "#eceff1",
			pi = run.pi,
			shift = 1,
			prize = daily.DAILY_PAY[1],
		},
		venue = run.venue.id,
		weatherSeed = `daily-{run.day}`,
		ghost = run.par,
		car = { model = run.car.id, color = run.color, upgrades = table.clone(ZERO) },
		fuel = false,
		extra = { day = run.day },
	},
		nil
end

function Daily.finish(self: any, s: any, p: any, _won: boolean, myTime: number, _theirTime: number, result: any)
	local daily = self.mods.game("daily")
	local run = daily.dailyRun(p.extra.day)
	local was = s.daily
	local paidBefore = was ~= nil and was.day == run.day and was.paid
	self.mods.store.useGame.getState().dailyResult(myTime)
	local now = self.mods.store.useGame.getState().daily
	-- What the result card shows (DailyRun.tsx DailyResult): the medal, par, today's best and
	-- whether this run was the one that paid.
	result.medal = daily.dailyMedal(run, myTime)
	result.par = run.par
	result.medals = run.medals
	result.best = if now and now.day == run.day and now.best ~= nil then now.best else myTime
	result.paidNow = not paidBefore
end

return Daily
