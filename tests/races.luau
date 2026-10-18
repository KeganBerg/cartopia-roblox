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
		DragRace = DragRace,
		random = rng(7),
		clock = function()
			return t
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
end
