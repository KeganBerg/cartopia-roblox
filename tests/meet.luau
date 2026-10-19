--!nocheck
-- Tests for server/Meet: displays newest first, and likes (one a town, 40 a day).

local Meet = require("../src/server/Meet")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

return function(test)
	test("meet: displays come newest first, with their cars", function()
		local now = 100
		local m = Meet.new(nil, function()
			return now
		end, function()
			return "2026-10-19"
		end)
		m:publish(1, "Ann", "Annville", 5, { { uid = "a", model = "pip", color = "#ff0000", upgrades = { 1, 2 } } })
		now = 200
		m:publish(2, "Bo", "Bo Town", 7, { { uid = "b", model = "zed", color = "#00ff00" } })
		m:publish(3, "Cy", "Nowhere", 1, {})
		local d = m:displays()
		expectEq(#d, 2, "displays (an empty garage shows nothing)")
		expectEq(d[1].name, "Bo", "newest first")
		expectEq(d[2].cars[1].model, "pip", "car kept")
		expectEq(d[2].cars[1].upgrades, nil, "only the look is kept")
	end)

	test("meet: one like a town, forty a day, never your own", function()
		local day = "2026-10-19"
		local m = Meet.new(nil, function()
			return 0
		end, function()
			return day
		end)
		expectEq(m:like(1, 1), "self", "own display")
		expectEq(m:like(1, 2), "liked", "first like")
		expectEq(m:like(1, 2), "already", "second like")
		expectEq(m:likes(2), 1, "count")
		local l = m:likesFor(1, { 2, 3 })
		expectEq(l["2"].liked, true, "liked flag")
		expectEq(l["3"].likes, 0, "no likes")
		for i = 3, 41 do
			expectEq(m:like(1, i), "liked", `like {i}`)
		end
		expectEq(m:like(1, 99), "limit", "41st like today")
		day = "2026-10-20"
		expectEq(m:like(1, 99), "liked", "a new day")
	end)

	test("meet: a player's card puts the cars on show first, then the rest by PI", function()
		local m = Meet.new(nil, function()
			return 0
		end, function()
			return "2026-10-19"
		end)
		local pis = { a = 300, b = 500, c = 400, d = 200 }
		local save = { townName = "Annville", level = 9, trophies = 12, racesWon = 4, cars = {
			{ uid = "a", model = "pip", color = "#ff0000", upgrades = {} },
			{ uid = "b", model = "pip", color = "#00ff00", upgrades = {} },
			{ uid = "c", model = "pip", color = "#0000ff", upgrades = {} },
			{ uid = "d", model = "pip", color = "#ffffff", upgrades = {} },
			{ model = "broken" },
		} }
		local card = Meet.cardOf(save, { save.cars[4] }, function(c)
			return pis[c.uid]
		end)
		expectEq(#card.cars, 4, "cars (a broken one is left out)")
		expectEq(card.cars[1].uid, "d", "on show first")
		expectEq(card.cars[2].uid, "b", "then the fastest")
		expectEq(card.cars[4].uid, "a", "slowest last")
		expectEq(card.cars[2].pi, 500, "each car's PI")
		expectEq(card.cars[1].upgrades, nil, "only the look is kept")
		expectEq(card.bestPi, 500, "best PI")
		expectEq(card.raceWins, 4, "wins")
		expectEq(card.showcase[1], "d", "showcase")
		m:saveCard(1, "Ann", card)
		local kept = m:card(1)
		expectEq(kept.name, "Ann", "kept card's name")
		expectEq(kept.town, "Annville", "kept card's town")
		expectEq(m:card(2), nil, "no card")
		m.mem.MeetCards_v1["1"] = nil
		m:saveCard(1, "Ann", card)
		expectEq(m:card(1), nil, "an unchanged card isn't written again")
		card.level = 10
		m:saveCard(1, "Ann", card)
		expectEq(m:card(1).level, 10, "a changed card is")
	end)
end
