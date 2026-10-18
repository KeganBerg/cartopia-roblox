--!nocheck
-- Tests for the server's crates (Crates): opening one with the web store's own openCrate, on a
-- starter town run by Towns.

local Crates = require("../src/server/Crates")
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
	return Crates.new(towns, store, require(G .. "crates")), towns
end

return function(test)
	test("crates: a street crate opens, takes its price and gives its prize", function()
		local crates, towns = setup()
		local before = towns:snapshot(1).save
		local opens, why = crates:open(1, "street", nil, 1)
		assert(opens, `open: {why}`)
		assert(#opens == 1 and opens[1].crate == "street" and opens[1].drop.kind, "one open with a drop")
		local after = towns:snapshot(1).save
		assert(after.stats.cratesOpened == (before.stats.cratesOpened or 0) + 1, "counted")
		local won = if opens[1].drop.coins then opens[1].drop.coins else 0
		assert(after.coins == before.coins - opens[1].cost.coins + won, `coins {before.coins} -> {after.coins}`)
	end)

	test("crates: ten at once, and a crate above the level is refused", function()
		local crates, towns = setup()
		towns:_with(1, function()
			require(G .. "store").useGame.setState({ coins = 1000000 })
		end)
		local opens = assert(crates:open(1, "street", nil, 10))
		assert(#opens == 10, `{#opens} opens`)
		local none, why = crates:open(1, "diamond", nil, 1)
		assert(none == nil and why == "not opened", tostring(why))
		assert(towns:snapshot(1).need, "says what's needed")
	end)

	test("crates: an unknown crate or a free crate the town doesn't have is refused", function()
		local crates = setup()
		assert(crates:open(1, "nope", nil, 1) == nil, "unknown")
		assert(crates:open(1, "street", "cup:nope", 1) == nil, "not a free crate of theirs")
	end)
end
