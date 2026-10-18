--!nocheck
-- Tests for the server's kart races (Karts): the Grand Prix's rounds, Bumper Blast and custom
-- races, started and paid on a starter town run by Towns with the transpiled store. The races
-- are driven with the converted kart rules (Shared.Game.kart), as the client drives them.

local Karts = require("../src/server/Karts")
local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

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
local store = require(G .. "store")
local data = require(G .. "data")
local kart = require(G .. "kart")
local L = require(G .. "lualib_bundle")

local function setup()
	local towns = Towns.new(store, function()
		return NOW
	end)
	towns:open(1, nil)
	local t = 0
	local karts = Karts.new(towns, {
		store = store,
		data = data,
		kart = kart,
		gpBeat = require(G .. "gpBeat"),
		raceCar = require(G .. "raceCar"),
		fairRace = require(G .. "fairRace"),
		boosts = require(G .. "boosts"),
		random = rng(11),
		clock = function()
			return t
		end,
	})
	return karts, towns, function(dt)
		t += dt
	end
end

-- A town that can enter the Rookie Cup: level 2 and three cars.
local function rookie(towns)
	towns:_with(1, function(s)
		local cars = table.clone(s.cars)
		for i, id in { "pip", "bug" } do
			table.insert(cars, { uid = `extra{i}`, model = id, color = "#ff0000", upgrades = { engine = 0, turbo = 0, tires = 0, weight = 0 } })
		end
		store.useGame.setState({ level = 2, cars = cars, fuel = 50 })
	end)
end

-- Runs a started race the way the client does (KartRace at 120 Hz, the player's kart on the AI's
-- own line), returning the player's place and time over the line.
local function drive(started)
	local def = kart.TRACKS[started.track + 1]
	local track = kart.buildTrack(def, started.reverse)
	local race = L.__TS__New(kart.KartRace, track, started.field, started.seed, started.rules)
	local me = 0
	for i, f in started.field do
		if not f.ai then
			me = i
		end
	end
	local inputs = {}
	for i = 1, #started.field do
		inputs[i] = kart.idleInput()
	end
	for _ = 1, 120 * 300 do
		local k = race.karts[me]
		inputs[me] = race:autoInput(k, race:order(), false)
		race:step(1 / 120, inputs, true)
		if k.done ~= nil then
			break
		end
	end
	local k = race.karts[me]
	assert(k.done ~= nil, "the kart never finished")
	return race:place(k), k.done
end

return function(test)
	test("karts: the Grand Prix needs its level and cars", function()
		local karts, towns = setup()
		local started, why = karts:start(1, "gp", "rookie")
		assert(started == nil and why == "That race isn't open yet", tostring(why))
		towns:_with(1, function()
			store.useGame.setState({ level = 2 })
		end)
		started, why = karts:start(1, "gp", "rookie")
		assert(started == nil and why:find("3 cars"), tostring(why))
		assert(karts:start(1, "gp", "nobody") == nil, "unknown series")
		assert(karts:start(1, "drag") == nil, "not a kart race")
	end)

	test("karts: a Grand Prix round starts with its grid, spends fuel and pays the place", function()
		local karts, towns, wait = setup()
		rookie(towns)
		local fuel = towns:snapshot(1).save.fuel
		local started, why = karts:start(1, "gp", "rookie")
		assert(started, `start: {why}`)
		assert(towns:snapshot(1).save.fuel == fuel - data.RACE_FUEL, "fuel spent")
		assert(#started.field == kart.FIELD, `{#started.field} karts`)
		assert(started.field[kart.FIELD].name == "You" and not started.field[kart.FIELD].ai, "the player at the back")
		assert(started.field[1].name == "Dusty Dan" and started.field[1].pi == data.gpRivalPi(data.GP_SERIES[1], 0, 0), "the round's rival first")
		assert(started.track == 0 and started.reverse == false and not started.rules.obstacles, "Main Street, forwards, no obstacles")
		assert(started.prize == data.gpReward(data.GP_SERIES[1], 0), "prize")
		assert(started.title == "🥉 1/6 · 🏙️ Main St", started.title)
		local place, time = drive(started)
		wait(Karts.LIGHTS + time + 1)
		local coins = towns:snapshot(1).save.coins
		local result, err = karts:finish(1, { place = place, time = time })
		assert(result, `finish: {err}`)
		assert(result.place == place and result.won == (place == 1), "the place")
		assert(towns:snapshot(1).save.coins > coins and result.coins > 0, "paid")
		assert(result.gp.round == (if place == 1 then 1 else 0), `round {result.gp.round}`)
		local again, why2 = karts:finish(1, { place = place, time = time })
		assert(again == nil and why2 == "no race", "counts once")
	end)

	test("karts: a finish faster than a kart can go, or sooner than it took, is refused", function()
		local karts, towns, wait = setup()
		rookie(towns)
		assert(karts:start(1, "gp", "rookie"))
		wait(100)
		local result, why = karts:finish(1, { place = 1, time = 10 })
		assert(result == nil and why == "too quick", tostring(why))
		assert(karts:start(1, "gp", "rookie"))
		wait(5)
		result, why = karts:finish(1, { place = 1, time = 70 })
		assert(result == nil and why == "too quick", tostring(why))
		assert(karts:start(1, "gp", "rookie"))
		wait(100)
		result, why = karts:finish(1, { place = 9, time = 70 })
		assert(result == nil and why == "bad race", tostring(why))
	end)

	test("karts: the reversed rounds have obstacles, and the final asks for a quick car", function()
		local karts, towns = setup()
		rookie(towns)
		towns:_with(1, function(s)
			store.useGame.setState({ gp = { rookie = { round = 3, clears = 0 } } })
		end)
		local started = assert(karts:start(1, "gp", "rookie"))
		assert(started.reverse and started.rules.obstacles and started.track == 0, "Main Street reversed")
		local need = karts:finalNeed(data.GP_SERIES[1], 0, data.GP_ROUNDS - 1)
		assert(need > 0, "the final has a PI floor")
		towns:_with(1, function(s)
			store.useGame.setState({ gp = { rookie = { round = data.GP_ROUNDS - 1, clears = 0 } } })
		end)
		local best = require(G .. "raceCar").bestCar(towns:snapshot(1).save.cars)
		local myPi = data.performance(data.carDef(best.model), best.upgrades, best.mods)
		local ok, why = karts:start(1, "gp", "rookie")
		if myPi < need then
			assert(ok == nil and why:find("PI"), tostring(why))
		else
			assert(ok, tostring(why))
		end
	end)

	test("karts: Bumper Blast and a custom race pay the party prize", function()
		local karts, towns, wait = setup()
		towns:_with(1, function()
			store.useGame.setState({ fuel = 50 })
		end)
		local started, why = karts:start(1, "blast")
		assert(started, `blast: {why}`)
		assert(started.rules.blast and #started.field == 6, "blast rules")
		assert(started.title:find("Bumper Blast"), started.title)
		assert(started.prize == kart.partyPrize(towns:snapshot(1).save.level), "party prize")
		local place, time = drive(started)
		wait(Karts.LIGHTS + time + 1)
		local result = assert(karts:finish(1, { place = place, time = time }))
		assert(result.coins > 0, "paid")
		assert(karts:start(1, "custom", { track = 7, reverse = false, rules = {} }) == nil, "no such circuit")
		assert(karts:start(1, "custom", { track = 1, reverse = "yes", rules = {} }) == nil, "bad pick")
		started, why = karts:start(1, "custom", { track = 2, reverse = true, rules = { obstacles = true, maxBoost = true } })
		assert(started, `custom: {why}`)
		assert(started.track == 2 and started.reverse and started.rules.obstacles and started.rules.maxBoost and not started.rules.blast, "the pick")
		assert(started.title == "🛠️ Custom · 🏜️ Canyon ↺", started.title)
		assert(started.pick and started.pick.track == 2, "the pick to race again")
	end)
end
