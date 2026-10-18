--!nocheck
-- Tests for server/Social: the help rules ported from the web's game/help.ts, and helping a town
-- being visited, with the transpiled store.

local Social = require("../src/server/Social")
local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

return function(test)
	test("social: the shop picker's hash matches the web's", function()
		-- From node: Math.imul FNV-1a over UTF-16 units, >>> 0.
		expectEq(Social._hash("123:2026-10-18:b7"), 258379566, "plain")
		expectEq(Social._hash("x"), 4245442695, "one letter")
		expectEq(Social._hash("héllo🚗"), 2150270467, "accent and emoji")
	end)

	test("social: help pay and thank-yous match game/help.ts", function()
		local p = Social.helpPrize(10, 3, 1)
		expectEq(p.coins, 20 + 50 + 20, "coins")
		expectEq(p.xp, 4, "xp")
		expectEq(p.parts, 0, "parts")
		expectEq(Social.helpPrize(1, 99, 5).parts, 2, "last help's parts")
		expectEq(Social.helpPrize(1, 99, 5).coins, 20 + 5 + 90, "shop level capped at 10")
		expectEq(Social.helpAct("carwash").icon, "🧽", "wash")
		expectEq(Social.helpAct("pizza").did, "served customers", "pizza")
		expectEq(Social.helpAct("mystery").did, "tidied up", "fallback")
	end)

	local now = Js.JsDate.UTC(2026, 9, 18, 12)
	Js.setClock(function()
		return now
	end)
	local store = require("../src/shared/Game/store")
	local data = require("../src/shared/Game/data")
	local towns = Towns.new(store, function()
		return now
	end)

	test("social: helping a friend's businesses pays, five a town, once each", function()
		towns:open(11, nil)
		towns:open(12, nil)
		-- The host builds some businesses to help at.
		local shops = {}
		for _, b in towns:save(12).buildings do
			if Social.helpable(data.buildingDef(b.def)) then
				table.insert(shops, b.uid)
			end
		end
		-- Copies of a business on spare tiles (help doesn't care where they stand).
		local save = towns:save(12)
		local model
		for _, b in save.buildings do
			if Social.helpable(data.buildingDef(b.def)) then
				model = b
			end
		end
		for i = 1, 6 do
			local b = table.clone(model)
			b.uid = `extra{i}`
			b.x, b.z = i * 3, 20
			table.insert(save.buildings, b)
			table.insert(shops, b.uid)
		end
		towns:_with(12, function(s)
			s.loadSave(save)
		end)
		assert(#shops >= 6, `need 6 businesses, have {#shops}`)
		local social = Social.new({ towns = towns, data = data, today = store.today })
		local coins = towns:save(11).coins
		local r, why = social:help(11, 12, shops[1])
		assert(r, why)
		expectEq(towns:save(11).coins, coins + r.coins, "paid")
		expectEq(select(2, social:help(11, 12, shops[1])), "already helped", "same shop twice")
		expectEq(select(2, social:help(11, 11, shops[1])), "not visiting", "own town")
		for i = 2, 5 do
			assert(social:help(11, 12, shops[i]))
		end
		expectEq(towns:save(11).helped["12"], store.today(), "town marked helped")
		expectEq(select(2, social:help(11, 12, shops[6])), "town done", "sixth help")
		expectEq(#social:townInfo(11, 12).helped, 5, "banner's count")
		local toasts = towns:snapshot(11).toasts
		expectEq(string.find(toasts[#toasts], "all helped out", 1, true) ~= nil, true, "last toast")
	end)
end
