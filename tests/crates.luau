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
	test("wheel: today's spin is rolled on the server with the web's odds, paid once, then refused", function()
		local crates, towns = setup()
		local wheel = require(G .. "wheel")
		local before = towns:snapshot(1).save
		local spin, why = crates:open(1, "wheel")
		assert(spin, `spin: {why}`)
		local slice = wheel.wheelSlice(spin.slice)
		assert(slice and spin.open.crate == "wheel", `a slice of the wheel: {spin.slice}`)
		local after = towns:snapshot(1).save
		assert(after.lastDaily == require(G .. "store").today(), "marked spun today")
		local coins = if spin.open.drop.kind == "coins" or spin.open.drop.kind == "skindupe" then spin.open.drop.coins else 0
		assert(after.coins == before.coins + coins, `coins {before.coins} -> {after.coins} (+{coins})`)
		assert(after.bucks == before.bucks + wheel.spinGems(spin.open), `gems {before.bucks} -> {after.bucks}`)
		local again, why2 = crates:open(1, "wheel")
		assert(again == nil and why2 == "spun today", tostring(why2))
		assert(towns:snapshot(1).save.coins == after.coins, "nothing more paid")
	end)

	test("wheel: many spins land on every slice about as often as the web's weights say", function()
		local store = require(G .. "store")
		local wheel = require(G .. "wheel")
		local crates, towns = setup()
		local seen = {}
		local N = 2000
		for _ = 1, N do
			towns:_with(1, function()
				store.useGame.setState({ lastDaily = "2000-01-01" })
			end)
			local spin = assert(crates:open(1, "wheel"))
			seen[spin.slice] = (seen[spin.slice] or 0) + 1
		end
		for _, s in wheel.WHEEL do
			local want = wheel.wheelPct(s) / 100 * N
			local got = seen[s.id] or 0
			-- A part or skin slice pays as coins-m when it has nothing to give, so leave those three out.
			if s.id ~= wheel.WHEEL_FALLBACK and (s.kind == "coins" or s.kind == "gems" or s.kind == "jackpot") then
				assert(math.abs(got - want) < 4 * math.sqrt(want) + 5, `{s.id}: {got} of {N}, want about {want}`)
			end
		end
	end)
end
