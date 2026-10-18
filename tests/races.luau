--!nocheck
-- Tests for the server's races (Races): rivals, starting a race, and paying it from the client's
-- presses, on a starter town run by Towns with the transpiled store.

local Races = require("../src/server/Races")
local Towns = require("../src/server/Towns")
local DragRace = require("../src/shared/DragRace")
local race = require("../src/shared/Game/race")
local Js = require("../src/shared/Game/__js")

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

-- Plain Luau has no Random: a seeded stand-in with the two calls Races uses.
local function rng(seed)
	local x = seed
	local function nextNumber()
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
	return {
		NextNumber = function(_)
			return nextNumber()
		end,
		NextInteger = function(_, lo, hi)
			return lo + math.floor(nextNumber() * (hi - lo + 1))
		end,
	}
end

local G = "../src/shared/Game/"
local function setup()
	local store = require(G .. "store")
	local towns = Towns.new(store, function()
		return NOW
	end)
	towns:open(1, nil)
	local t = 0
	local races = Races.new(towns, {
		store = store,
		data = require(G .. "data"),
		raceCar = require(G .. "raceCar"),
		fairRace = require(G .. "fairRace"),
		fairPi = require(G .. "fairPi"),
		grip = require(G .. "grip"),
		weather = require(G .. "weather"),
		venues = require(G .. "scene_venues"),
		paintRivals = require(G .. "paintRivals"),
		rivals = require(G .. "rivals"),
		distance = require(G .. "distance"),
		DragRace = DragRace,
		random = rng(7),
		clock = function()
			return t
		end,
		modes = {
			world = require("../src/server/Modes/World"),
			daily = require("../src/server/Modes/Daily"),
		},
		game = function(name)
			return require(G .. name)
		end,
	})
	return races, towns, function(dt)
		t += dt
	end
end

-- Drives a race the way a good player does, as the client would, and returns the presses.
local function drive(spec)
	local r = DragRace.new(spec)
	local holdTick = math.round(1.7 / DragRace.DT)
	local released = false
	while not r.done do
		if r.tick == holdTick then
			DragRace.input(r, "down")
		end
		if r.me.launched and not released then
			DragRace.input(r, "up")
			released = true
		end
		if r.me.launched and r.me.finished == nil and r.me.gear < race.TOP_GEAR and r.me.rpm >= 0.9 then
			DragRace.input(r, "down")
		end
		if r.me.gear >= 3 and not r.me.boostUsed then
			DragRace.input(r, "boost")
		end
		DragRace.step(r)
	end
	return r
end

return function(test)
	test("races: three quick rivals that stay until one is raced", function()
		local races = setup()
		local a = races:quickRivals(1)
		assert(#a == 3, `{#a} rivals`)
		assert(races:quickRivals(1) == a, "same rivals")
		for _, r in a do
			assert(type(r.pi) == "number" and r.prize > 0 and r.carName, "rival card")
		end
	end)

	test("races: a quick race starts, spends fuel and pays a win", function()
		local races, towns, wait = setup()
		local fuel = towns:snapshot(1).save.fuel
		local coins = towns:snapshot(1).save.coins
		local started, why = races:start(1, "quick", 1)
		assert(started, `start: {why}`)
		assert(started.venue and started.venue.name, "venue")
		assert(started.spec.grip and started.spec.theirGrip, "grip")
		assert(towns:snapshot(1).save.fuel < fuel, "fuel spent")
		local run = drive(started.spec)
		local mine, theirs = DragRace.times(run)
		wait(DragRace.GO_TICK * DragRace.DT + mine + 1)
		local result, err = races:finish(1, run.events)
		assert(result, `finish: {err}`)
		assert(result.won == (mine < theirs), "same winner as the client saw")
		if result.won then
			assert(towns:snapshot(1).save.coins > coins, "paid")
		end
	end)

	test("races: a race finished too soon is refused", function()
		local races, _, wait = setup()
		local started = assert(races:start(1, "quick", 2))
		local run = drive(started.spec)
		wait(1)
		local result, why = races:finish(1, run.events)
		assert(result == nil and why == "too quick", tostring(why))
	end)

	test("races: the campaign lists its chapters and starts the first race", function()
		local races, _, wait = setup()
		local chapters = races:campaign(1)
		assert(#chapters > 0 and chapters[1].open and chapters[1].races[1].open, "first race open")
		local started, why = races:start(1, "campaign", { chapter = 0, race = 0 })
		assert(started, `start: {why}`)
		local run = drive(started.spec)
		wait(60)
		local result = assert(races:finish(1, run.events))
		assert(type(result.stars) == "number", "stars")
	end)

	test("races: paint rivals race at their venue over their distance, and a first win opens the colour", function()
		local races, towns, wait = setup()
		local list = races:rows(1)
		assert(#list == 16 and list[1].prize > 0 and list[1].wins == 0, "roster")
		-- Marina races over a half mile at the beach.
		local started, why = races:start(1, "row", "marina")
		assert(started, `start: {why}`)
		assert(started.spec.track == 800 and started.spec.build ~= nil, "half mile with the build")
		assert(started.venue.id == "beach", started.venue.id)
		local run = drive(started.spec)
		local mine, theirs = DragRace.times(run)
		wait(60)
		local result = assert(races:finish(1, run.events))
		assert(result.won == (mine < theirs), "same winner")
		local row = towns:snapshot(1).save.rivalRow or {}
		if result.won then
			assert(result.paint == "#00acc1" and row.marina == 1, "colour won")
			assert(races:rows(1)[6].wins == 1, "counted")
		else
			assert(result.paint == nil and (row.marina or 0) == 0, "no colour")
		end
		assert(races:start(1, "row", "nobody") == nil, "unknown rival")
	end)

	test("races: the rival in town, then double or nothing", function()
		local races, towns, wait = setup()
		local rivals = require(G .. "rivals")
		local store = require(G .. "store")
		local started, why = races:start(1, "rival")
		assert(started == nil and why:find("level"), tostring(why))
		towns:_with(1, function()
			store.useGame.setState({ level = rivals.RIVAL_LEVEL, xp = 0 })
		end)
		started, why = races:start(1, "rival")
		assert(started, `start: {why}`)
		assert(started.rival.id == "rival-" .. rivals.RIVALS[1].id and started.rival.visit == 0, started.rival.id)
		local run = drive(started.spec)
		local mine, theirs = DragRace.times(run)
		wait(60)
		local result = assert(races:finish(1, run.events))
		assert(result.won == (mine < theirs), "same winner")
		if not result.won then
			assert(races:start(1, "bet") == nil, "no bet after a loss")
			return
		end
		assert(result.bet == started.rival.prize, "double or nothing offered")
		local fuel = towns:snapshot(1).save.fuel
		local coins = towns:snapshot(1).save.coins
		local again = assert(races:start(1, "bet"))
		assert(again.stake == result.bet and towns:snapshot(1).save.fuel == fuel, "no fuel for the rematch")
		-- Leaving it half way loses the stake.
		races:close(1)
		assert(towns:snapshot(1).save.coins == coins - result.bet, "stake lost")
		assert(races:start(1, "bet") == nil, "only once")
	end)

	test("races: the World Tour opens at Street Racer and pays through worldTourResult", function()
		local races, towns, wait = setup()
		local store = require(G .. "store")
		local wt = require(G .. "worldTour")
		local started, why = races:start(1, "world", 0)
		assert(started == nil and why:find("World Tour"), tostring(why))
		towns:_with(1, function()
			store.useGame.setState({ trophies = 400 })
		end)
		assert(races:start(1, "world", 1) == nil, "only the next country")
		started, why = races:start(1, "world", 0)
		assert(started, `start: {why}`)
		assert(started.venue.id == "giza" and started.rival.id == "world-0", started.venue.id)
		assert(started.rival.prize == wt.worldPrize(0, true), "first-win prize")
		local run = drive(started.spec)
		local mine, theirs = DragRace.times(run)
		wait(60)
		local result = assert(races:finish(1, run.events))
		assert(result.won == (mine < theirs), "same winner")
		assert((towns:snapshot(1).save.worldTour or 0) == (if result.won then 1 else 0), "progress")
	end)

	test("races: the Daily Run races the day's loaner against par and pays the first run", function()
		local races, towns, wait = setup()
		local daily = require(G .. "daily")
		local trial = require(G .. "trial")
		local run = daily.dailyRun()
		local save = towns:snapshot(1).save
		local fuel, coins = save.fuel, save.coins
		local started, why = races:start(1, "daily", nil)
		assert(started, `start: {why}`)
		assert(started.rival.id == "trial" and started.spec.ghost == run.par, "par ghost")
		assert(started.car and started.car.model == run.car.id and started.car.color == run.color, "loaner")
		assert(started.spec.myPi == run.pi, `stock loaner PI {started.spec.myPi} vs {run.pi}`)
		assert(started.venue.id == run.venue.id, "the day's venue")
		assert(towns:snapshot(1).save.fuel == fuel - trial.TRIAL_FUEL, "a trial's fuel")
		local r = drive(started.spec)
		local mine = DragRace.times(r)
		wait(60)
		local result = assert(races:finish(1, r.events))
		assert(result.paidNow and result.par == run.par and result.best == mine, "first run")
		local pay = daily.DAILY_PAY[math.min(daily.dailyMedal(run, mine), #daily.DAILY_MEDALS - 1) + 1]
		assert(result.coins > 0 and towns:snapshot(1).save.coins > coins, `paid {result.coins} (base {pay})`)
		local d = towns:snapshot(1).save.daily
		assert(d and d.day == run.day and d.paid and d.best == mine, "kept in the save")
		local m = towns:snapshot(1).save.mastery or {}
		assert(next(m) == nil or not m[run.car.id], "no mastery for a ghost run")
		-- Again: no pay the second time.
		started = assert(races:start(1, "daily", nil))
		r = drive(started.spec)
		wait(60)
		local c2 = towns:snapshot(1).save.coins
		result = assert(races:finish(1, r.events))
		assert(not result.paidNow and towns:snapshot(1).save.coins == c2, "only the first run pays")
	end)

	test("races: a ghost run finishes at the ghost's time", function()
		local spec = { myPi = 40, rival = { pi = 0, shift = 1 }, seed = 3, track = 400, ghost = 13.5 }
		local run = drive(spec)
		local _, theirs = DragRace.times(run)
		assert(theirs == 13.5, tostring(theirs))
	end)
end
