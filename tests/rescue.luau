--!nocheck
-- Tests for Rusty's Rescue on the server: a search, the tow home, a restore and its collection,
-- all run by the web store's own actions through Towns (as the client's Act remote does).

local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

local G = "../src/shared/Game/"
local function setup()
	local store = require(G .. "store")
	local towns = Towns.new(store, function()
		return NOW
	end)
	towns:open(1, nil)
	-- A town with Rusty's built and coins to spend.
	towns:_with(1, function(s)
		local b = table.clone(s.buildings)
		table.insert(b, { id = "rusty1", def = "rescue", x = 40, z = 40, rot = 0, level = 1 })
		store.useGame.setState({ coins = 100000, bucks = 500, buildings = b })
	end)
	return towns, store
end

return function(test)
	test("rescue: a search takes its cost, shows in the snapshot, and the tow home ends it", function()
		local towns = setup()
		local before = towns:snapshot(1).save.coins
		towns:run(1, "startSearch", "suburbs")
		local snap = towns:snapshot(1)
		assert(snap.search and #snap.search.pins > 0, "search in the snapshot")
		assert(snap.save.coins == before - 500, `coins {before} -> {snap.save.coins}`)
		-- Reveal spots until one is a flat or all are open.
		for i = 0, #snap.search.pins - 1 do
			towns:run(1, "revealPin", i)
			if towns:snapshot(1).search.flat then
				towns:run(1, "fixTruck")
			end
		end
		towns:run(1, "towHome")
		local after = towns:snapshot(1)
		assert(after.search == nil, "search over")
	end)

	test("rescue: abandoning a search clears it", function()
		local towns = setup()
		towns:run(1, "startSearch", "suburbs")
		towns:run(1, "abandonSearch")
		assert(towns:snapshot(1).search == nil, "search cleared")
	end)

	test("rescue: a car from the lot restores, then collects into the garage once", function()
		local towns, store = setup()
		towns:_with(1, function()
			store.useGame.setState({ junkyard = { { uid = "j1", model = "pip", rarity = "common" } } })
		end)
		local cars = #towns:snapshot(1).save.cars
		towns:run(1, "restoreCar", "j1")
		local snap = towns:snapshot(1).save
		assert(snap.restoring and snap.restoring.model == "pip", "in the bay")
		assert(#snap.junkyard == 0, "off the lot")
		NOW += 24 * 3600 * 1000
		towns:run(1, "collectRestored", "RUSTY1", 0)
		towns:run(1, "collectRestored", "RUSTY1", 0)
		local done = towns:snapshot(1).save
		assert(#done.cars == cars + 1, `{cars} -> {#done.cars} cars`)
		assert(done.restoring == nil, "bay free again")
	end)
end
