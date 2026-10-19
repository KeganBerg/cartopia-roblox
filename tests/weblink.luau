--!nocheck
-- Tests for bringing a web town over (server/WebLink): codes cleaned up as typed, paid web packs
-- taken back out (gems, coins, parts and their cars), Robux buys made here kept, and the database's
-- answers turned into a town or a reason. The town opens in the real store afterwards.

local WebLink = require("../src/server/WebLink")
local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

local function car(uid, model)
	return { uid = uid, model = model or "hatch", color = "#e53935", upgrades = { engine = 0, turbo = 0, tires = 0, weight = 0 } }
end

local function fakeHttp(status, body)
	local sent = {}
	return {
		sent = sent,
		JSONEncode = function(_, v)
			sent.body = v
			return "{}"
		end,
		JSONDecode = function(_, s)
			return body
		end,
		RequestAsync = function(_, req)
			sent.req = req
			if status == "throw" then
				error("HttpService is not allowed to access ROBLOX resources")
			end
			return { Success = status == 200, StatusCode = status, Body = "x" }
		end,
	}
end

return function(test)
	test("web link: codes are cleaned up as typed", function()
		assert(WebLink.clean("abcd-2345") == "ABCD2345")
		assert(WebLink.clean(" AB CD 23 45 ") == "ABCD2345")
		assert(WebLink.clean("ABCD234") == nil, "too short")
		assert(WebLink.clean("ABCD2340") == nil, "0 isn't a code letter")
		assert(WebLink.clean(42) == nil)
	end)

	test("web link: paid web packs stay on the web", function()
		local web = { townName = "Webville", level = 12, bucks = 100, coins = 5000, parts = 30, raceCar = "pk-2", purchases = 2, admin = true,
			cars = { car("c1"), car("pk-2", "scatto") } }
		local paid = { { seq = 1, bucks = 70, coins = 0, parts = 0 }, { seq = 2, bucks = 0, coins = 6000, parts = 10, car = "scatto" } }
		local s = WebLink.strip(web, paid, nil)
		assert(s.bucks == 30, `gems {s.bucks}`)
		assert(s.coins == 0, "coins stop at 0")
		assert(s.parts == 20)
		assert(#s.cars == 1 and s.cars[1].uid == "c1", "pack car left behind")
		assert(s.raceCar == nil, "race car was the pack car")
		assert(s.admin == nil, "no web admin")
		assert(s.purchases == nil, "purchase count starts from this town's")
		assert(s.level == 12 and s.townName == "Webville")
		assert(web.bucks == 100 and #web.cars == 2, "web save untouched")
	end)

	test("web link: Robux buys made here stay", function()
		local web = { bucks = 5, coins = 10, parts = 0, cars = { car("c1") } }
		local here = { purchases = 3, bucks = 900, cars = { car("start"), car("pk-3", "vento") } }
		local s = WebLink.strip(web, {}, here)
		assert(s.purchases == 3)
		assert(s.bucks == 900)
		assert(#s.cars == 2 and s.cars[2].uid == "pk-3")
		local none = WebLink.strip(web, {}, { purchases = 0, bucks = 900, cars = {} })
		assert(none.bucks == 5, "no Robux buys: the web's earned gems")
	end)

	test("web link: the database's answers", function()
		local http = fakeHttp(200, { state = { level = 3 }, paid = {} })
		local got, why = WebLink.claim(http, "ABCD2345", 77)
		assert(got and got.state.level == 3 and why == nil)
		assert(http.sent.body.p_code == "ABCD2345" and http.sent.body.p_roblox_user == 77)
		assert(http.sent.req.Headers.apikey == WebLink.KEY and http.sent.req.Method == "POST")
		assert(select(2, WebLink.claim(fakeHttp(200, { error = "code" }), "ABCD2345", 77)) == "code")
		assert(select(2, WebLink.claim(fakeHttp(200, { error = "other" }), "ABCD2345", 77)) == "other")
		assert(select(2, WebLink.claim(fakeHttp(500, {}), "ABCD2345", 77)) == "offline")
		assert(select(2, WebLink.claim(fakeHttp("throw", {}), "ABCD2345", 77)) == "offline")
	end)

	test("web link: the brought-over town opens", function()
		local store = require("../src/shared/Game/store")
		local towns = Towns.new(store, function()
			return NOW
		end)
		towns:open(1, nil)
		local web = towns:save(1)
		web.townName = "Webville"
		web.bucks = 50
		local s = WebLink.strip(web, { { seq = 1, bucks = 20, coins = 0, parts = 0 } }, towns:save(1))
		towns:close(1)
		towns:open(1, s)
		local after = towns:save(1)
		assert(after.townName == "Webville")
		assert(after.bucks == 30, `gems {after.bucks}`)
	end)
end
