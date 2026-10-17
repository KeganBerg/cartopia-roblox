--!nocheck
-- Tests for the server modules: session-locked saves (Saves) and running towns (Towns), with an
-- in-memory DataStore and the transpiled store.

local Saves = require("../src/server/Saves")
local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")

-- A DataStore stand-in: UpdateAsync with Roblox's rules (returning nil leaves the value alone).
-- Values are copied in and out, as a real DataStore serialises them.
local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end
local function fakeStore()
	local data, fail = {}, 0
	local store = { data = data }
	function store:UpdateAsync(key, fn)
		if fail > 0 then
			fail -= 1
			error("DataStore request was rejected")
		end
		local new = fn(copy(data[key]))
		if new ~= nil then
			data[key] = copy(new)
		end
		return new
	end
	function store.failNext(n)
		fail = n
	end
	return store
end

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

return function(test)
	local clock = 1000
	local function saves(store, job)
		return Saves.new({ store = store, job = job, now = function() return clock end, wait = function() end })
	end

	test("saves: a new player gets nil, then their save back", function()
		local store = fakeStore()
		local a = saves(store, "A")
		expectEq(a:load(1), nil, "first load")
		expectEq(a:write(1, { coins = 5 }, true), true, "write")
		expectEq(a:load(1).coins, 5, "second load")
	end)

	test("saves: another server can't load or write a locked town", function()
		local store = fakeStore()
		local a, b = saves(store, "A"), saves(store, "B")
		a:load(1)
		local ok = pcall(b.load, b, 1)
		expectEq(ok, false, "B loads while A holds the lock")
		expectEq(b:write(1, { coins = 999 }), false, "B writes without the lock")
		a:write(1, { coins = 7 }, true)
		expectEq(b:load(1).coins, 7, "B loads after A releases")
	end)

	test("saves: a stale lock from a crashed server is taken over", function()
		local store = fakeStore()
		local a, b = saves(store, "A"), saves(store, "B")
		a:load(1)
		a:write(1, { coins = 3 })
		clock += Saves.LOCK_TTL + 1
		expectEq(b:load(1).coins, 3, "B takes over")
		expectEq(a:write(1, { coins = 0 }), false, "A's late write is refused")
		expectEq(store.data.town_1.save.coins, 3, "stored coins")
	end)

	test("saves: retries through DataStore errors", function()
		local store = fakeStore()
		local a = saves(store, "A")
		store.failNext(Saves.RETRIES - 1)
		expectEq(a:load(1), nil, "load after errors")
		expectEq(a:holds(1), true, "holds the lock")
	end)

	local now = Js.JsDate.UTC(2026, 9, 17, 12)
	Js.setClock(function()
		return now
	end)
	local store = require("../src/shared/Game/store")
	local towns = Towns.new(store, function()
		return now
	end)

	test("towns: checks client requests", function()
		expectEq(Towns.check("buyCar", { "pip", "#c62828" }, 2), true, "buyCar")
		expectEq(Towns.check("loadSave", { {} }, 1), false, "loadSave")
		expectEq(Towns.check("finishRace", { true, 1e9 }, 2), false, "finishRace")
		expectEq(Towns.check("buyCar", { "pip" }, 1), false, "missing argument")
		expectEq(Towns.check("buyCar", { "pip", "#fff", 1 }, 3), false, "extra argument")
		expectEq(Towns.check("bulldoze", { 0 / 0, 1 }, 2), false, "NaN")
		expectEq(Towns.check("upgradeCar", { "c1", "rocket" }, 2), false, "unknown slot")
		expectEq(Towns.check("assignCar", { "b1", nil }, 2), true, "optional nil")
	end)

	test("towns: each player's town is separate, and survives a save round trip", function()
		towns:open(1, nil)
		towns:open(2, nil)
		local coins = towns:save(2).coins
		expectEq(towns:run(1, "buyCar", "pip", "#c62828"), false, "no car before Rusty's Rescue")
		expectEq(towns:snapshot(1).toasts[1], "Build Rusty's Rescue first. Rusty finds you new cars!", "toast")
		expectEq(towns:run(1, "placeBuilding", "rescue", 12, 12), true, "player 1 builds Rusty's")
		expectEq(towns:run(1, "buyCar", "pip", "#c62828"), true, "player 1 buys a car")
		expectEq(#towns:save(1).cars, #towns:save(2).cars + 1, "only player 1 has the car")
		expectEq(towns:save(2).coins, coins, "player 2's coins")
		local saved = copy(towns:save(1))
		towns:close(1)
		towns:open(1, saved)
		expectEq(#towns:save(1).cars, #saved.cars, "cars after reload")
		expectEq(towns:save(1).coins, saved.coins, "coins after reload")
	end)

	test("towns: jobs pay out on the server clock", function()
		towns:open(3, nil)
		local pizza
		for _, b in towns:save(3).buildings do
			if b.def == "pizza" then
				pizza = b.uid
				break
			end
		end
		assert(pizza, "starter town has a pizza place")
		towns:run(3, "tapBuilding", pizza)
		local coins = towns:save(3).coins
		now += 60 * 60 * 1000
		towns:run(3, "tapBuilding", pizza)
		assert(towns:save(3).coins > coins, "collecting the job pays coins")
		local snap = towns:snapshot(3)
		assert(#snap.toasts >= 0 and snap.save.coins == towns:save(3).coins, "snapshot")
		expectEq(#towns:snapshot(3).toasts, 0, "toasts are only sent once")
	end)
end
