--!nocheck
-- Tests for Robux purchases (server/Purchases): gem and car packs paid through the web store's own
-- applyPurchases, each PurchaseId granted once even when Roblox sends its receipt again, and a grant
-- whose save didn't write held back until a save carries it.

local Purchases = require("../src/server/Purchases")
local Towns = require("../src/server/Towns")
local Saves = require("../src/server/Saves")
local Js = require("../src/shared/Game/__js")

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

local G = "../src/shared/Game/"
local PACKS = require(G .. "bucksPacks")

local function setup(crew)
	local store = require(G .. "store")
	local towns = Towns.new(store, function()
		return NOW
	end)
	towns:open(1, nil)
	if crew ~= false then
		towns:_with(1, function(s)
			store.useGame.setState({ stored = { { uid = "crew-1", def = "crew" } } })
		end)
	end
	local disk = { writes = 0, fail = false }
	local p
	p = Purchases.new(towns, store, PACKS, function(userId)
		if disk.fail then
			return false
		end
		local list = p:toSave(userId)
		disk.writes += 1
		disk.save = towns:save(userId)
		disk.receipts = list
		p:saved(userId, list)
		return true
	end)
	local list = {}
	for i, pack in PACKS.ALL_PACKS do
		table.insert(list, { name = pack.name, product = 1000 + i, robux = 10 * i })
	end
	p:setProducts(list)
	local passes = {}
	for i, pack in PACKS.ALL_PACKS do
		if pack.car then
			table.insert(passes, { id = pack.id, pass = 2000 + i, robux = 20 * i })
		end
	end
	p:setPasses(passes)
	p:load(1, {})
	return p, towns, disk
end

local function passOf(id)
	for i, pack in PACKS.ALL_PACKS do
		if pack.id == id then
			return 2000 + i
		end
	end
	error(id)
end

local function productOf(id)
	for i, pack in PACKS.ALL_PACKS do
		if pack.id == id then
			return 1000 + i
		end
	end
	error(id)
end

return function(test)
	test("purchases: a gem pack pays its gems, coins and parts for the level, once", function()
		local p, towns, disk = setup()
		local before = towns:save(1)
		local bag = productOf("bag")
		assert(p:process(1, bag, "r1") == "granted", "granted")
		local after = towns:save(1)
		local grant = PACKS.packGrant(PACKS.ALL_PACKS[3], before.level)
		assert(after.bucks == before.bucks + grant.bucks, `gems {before.bucks} -> {after.bucks}`)
		assert(after.coins == before.coins + grant.coins and grant.coins > 0, "coins")
		assert(after.parts == before.parts + grant.parts and grant.parts > 0, "parts")
		assert(after.purchases == 1, "purchase counted")
		assert(disk.receipts[1] == "r1" and disk.save.bucks == after.bucks, "saved with its receipt")
		-- Roblox sends the same receipt again: granted, nothing added.
		assert(p:process(1, bag, "r1") == "granted", "again")
		assert(towns:save(1).bucks == after.bucks, "not paid twice")
	end)

	test("purchases: a receipt saved on another server is granted without paying again", function()
		local p, towns = setup()
		p:load(1, { "old" })
		local before = towns:save(1).bucks
		assert(p:process(1, productOf("handful"), "old") == "granted")
		assert(towns:save(1).bucks == before, "already in the save")
	end)

	test("purchases: a grant whose save fails waits, and isn't paid twice", function()
		local p, towns, disk = setup()
		disk.fail = true
		local before = towns:save(1).bucks
		assert(p:process(1, productOf("handful"), "r2") == "later", "not granted before it's saved")
		local mid = towns:save(1).bucks
		assert(mid == before + 300, "in the town already")
		assert(p:process(1, productOf("handful"), "r2") == "later", "still not saved")
		assert(towns:save(1).bucks == mid, "not paid twice")
		disk.fail = false
		assert(p:process(1, productOf("handful"), "r2") == "granted", "granted once saved")
		assert(towns:save(1).bucks == mid and disk.receipts[1] == "r2", "saved once")
	end)

	test("purchases: a car pack is a Game Pass that brings its car and gems once", function()
		local p, towns, disk = setup()
		local id, why, kind = p:canBuy(1, "car-scatto")
		assert(id == passOf("car-scatto") and why == nil and kind == "pass", "sold as its pass")
		assert(select(3, p:canBuy(1, "bag")) == "product", "gem packs stay products")
		assert(p:shop(1).packs["car-scatto"].robux ~= nil, "pass price shown")
		local gems = towns:save(1).bucks
		assert(p:grantPass(1, passOf("car-scatto")) == "granted")
		local save = towns:save(1)
		local car
		for _, c in save.cars do
			if c.model == "scatto" then
				car = c
			end
		end
		assert(car and car.uid == "pk-1", "car in the garage")
		assert(save.bucks == gems + 400, "and its gems")
		assert(table.find(disk.receipts, "pass:car-scatto"), "saved with its receipt")
		local none, why2 = p:canBuy(1, "car-scatto")
		assert(none == nil and why2 == "owned", tostring(why2))
		assert(p:shop(1).packs["car-scatto"].owned == true, "shop says owned")
		-- Seen again (rejoining, or the prompt's finish and the join check both): not paid twice.
		assert(p:grantPass(1, passOf("car-scatto")) == "granted")
		assert(towns:save(1).bucks == save.bucks, "not paid twice")
		assert(p:grantPass(1, 42) == "unknown", "not a car pack's pass")
	end)

	test("purchases: a pass bought on the game page pays on joining a server, once", function()
		local p, towns = setup()
		p:load(1, { "pass:car-sora" })
		local gems = towns:save(1).bucks
		assert(p:grantPass(1, passOf("car-sora")) == "granted", "already paid on another server")
		assert(towns:save(1).bucks == gems, "not paid again")
		assert(p:grantPass(2, passOf("car-sora")) == "later", "no town loaded yet")
	end)

	test("purchases: a pass's receipt is kept however many purchases come after it", function()
		local p = setup()
		assert(p:grantPass(1, passOf("car-scatto")) == "granted")
		for i = 1, Purchases.KEEP + 5 do
			p:process(1, productOf("handful"), `r{i}`)
		end
		local list = p:toSave(1)
		assert(#list == Purchases.KEEP + 1 and list[1] == "pass:car-scatto", `{#list} {list[1]}`)
	end)

	test("purchases: a pass off sale isn't sold but still pays its owner", function()
		local p, towns = setup()
		p:setPasses({ { id = "car-scatto", pass = passOf("car-scatto") } })
		assert(select(2, p:canBuy(1, "car-scatto")) == "soon", "not on sale")
		assert(select(2, p:canBuy(1, "car-sora")) == "soon", "no pass yet")
		local gems = towns:save(1).bucks
		assert(p:grantPass(1, passOf("car-scatto")) == "granted", "owner paid")
		assert(towns:save(1).bucks == gems + 400)
	end)

	test("purchases: a car pack bought as a Developer Product still pays, one car per account", function()
		local p, towns = setup()
		assert(p:process(1, productOf("car-scatto"), "r3") == "granted")
		local gems = towns:save(1).bucks
		-- Its pass later too: gems only, no second car.
		assert(p:grantPass(1, passOf("car-scatto")) == "granted")
		local n = 0
		for _, c in towns:save(1).cars do
			if c.model == "scatto" then
				n += 1
			end
		end
		assert(n == 1 and towns:save(1).bucks == gems + 400, "gems only")
	end)

	test("purchases: no Crew House, no product yet, or an unknown pack can't be bought", function()
		local p = setup(false)
		assert(p:shop(1).open == false, "shop closed")
		assert(select(2, p:canBuy(1, "bag")) == "crew", "needs the Crew House")
		local q = setup()
		q:setProducts({})
		assert(select(2, q:canBuy(1, "bag")) == "soon", "no product yet")
		assert(q:shop(1).packs.bag.robux == nil, "no price shown")
		assert(select(2, q:canBuy(1, "nope")) == "unknown", "unknown")
		assert(select(2, q:canBuy(1, "car-brawler")) == "unknown", "retired packs aren't sold")
	end)

	test("purchases: no town loaded yet, or a product that isn't a pack, waits", function()
		local p = setup()
		assert(p:process(2, productOf("bag"), "r5") == "later", "player 2 has no town")
		assert(p:process(1, 42, "r6") == "later", "not a pack")
	end)

	test("purchases: receipts are written with the save and come back when it loads", function()
		local data = {}
		local fake = {
			UpdateAsync = function(_, key, fn)
				local out = fn(data[key])
				if out ~= nil then
					data[key] = out
				end
			end,
		}
		local a = Saves.new({ store = fake, job = "a", now = function() return 1 end, wait = function() end })
		a:load(7)
		assert(a:write(7, { coins = 5 }, false, { "r1", "r2" }), "wrote")
		assert(a:write(7, { coins = 6 }, true), "a save without receipts keeps them")
		local b = Saves.new({ store = fake, job = "b", now = function() return 2 end, wait = function() end })
		local save, receipts = b:load(7)
		assert(save.coins == 6 and #receipts == 2 and receipts[2] == "r2", "came back")
	end)
end
