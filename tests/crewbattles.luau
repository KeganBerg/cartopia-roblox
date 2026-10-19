--!nocheck
-- Tests for server/CrewBattles: weekly matching, street crews, points, live wins and the chests.

local CrewBattles = require("../src/server/CrewBattles")
local R = CrewBattles.RULES

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

-- Monday 19 October 2026, 12:00 UTC.
local MONDAY = 1792411200
local DAY = 86400

local function make(list)
	local w = { now = MONDAY, list = list or {} }
	w.b = CrewBattles.new({
		clock = function()
			return w.now
		end,
		crews = function()
			return w.list
		end,
		crew = function(id)
			return { id = id, name = "Crew " .. id, tag = id:upper(), emblem = "🏁", color = "#ffffff" }
		end,
		emblems = { "🏁", "🔥" },
		colors = { "#ff0000", "#00ff00" },
	})
	return w
end

local function row(id, power, members, seen)
	return { id = id, power = power, members = members, seen = seen or MONDAY }
end

return function(test)
	test("crew battles: weeks and the street crew's curve", function()
		expectEq(CrewBattles.weekStart("2026-10-19"), MONDAY - 12 * 3600, "midnight UTC")
		expectEq(CrewBattles.weeks(MONDAY - 12 * 3600 - 1), "2026-10-12", "Sunday night is last week")
		local w = make()
		local bot = w.b:bot("c", "2026-10-19", 1)
		expectEq(#bot.members, 3, "at least three drivers shown")
		local par = R.botPerMember * R.botMinMembers
		assert(bot.total >= math.floor(par * 0.8) and bot.total <= math.ceil(par * 1.15), "total near par")
		expectEq(CrewBattles.botScore(bot, "s", "2026-10-19", MONDAY - 13 * 3600), 0, "nothing before the week")
		expectEq(CrewBattles.botScore(bot, "s", "2026-10-19", MONDAY + 7 * DAY), bot.total, "all of it at week end")
		local a = CrewBattles.botScore(bot, "s", "2026-10-19", MONDAY + DAY)
		local b = CrewBattles.botScore(bot, "s", "2026-10-19", MONDAY + 3 * DAY)
		assert(a <= b and b <= bot.total, "climbs through the week")
		expectEq(w.b:bot("c", "2026-10-19", 1).name, bot.name, "the same street crew every time")
	end)

	test("crew battles: matched with the closest playing crew, else a street crew", function()
		local w = make({ row("a", 1000, 3), row("near", 1500, 3), row("far", 2900, 3), row("huge", 9000, 3), row("gone", 1000, 3, MONDAY - 20 * DAY) })
		local x = w.b:battleOf("a")
		expectEq(x.b, "near", "closest in power")
		expectEq(w.b:battleOf("near").id, x.id, "the same battle from both sides")
		local y = w.b:battleOf("far")
		expectEq(y.b, nil, "nobody free near enough")
		assert(y.bot ~= nil, "a street crew instead")
		expectEq(w.b:battleOf("gone").b, nil, "idle crews aren't picked")
		expectEq(w.b:battleOf("a", "2026-10-12"), nil, "past weeks aren't matched")
	end)

	test("crew battles: race points come out of the bank, capped per member", function()
		local w = make({ row("a", 1000, 3), row("b", 1000, 3) })
		expectEq(w.b:races(1, "a", "Ann", 2, 1), 2 * R.race + R.win, "races and a win")
		expectEq(w.b:races(1, "a", "Ann", 1000, 0), R.bankMax - 5, "the bank runs dry")
		expectEq(w.b:races(1, "a", "Ann", 5, 0), 0, "nothing left")
		w.now += 30
		expectEq(w.b:races(1, "a", "Ann", 50, 0), 30 // R.bankSeconds, "refilled with time")
		expectEq(w.b:races(1, "a", "Ann", -3, 0 / 0), 0, "nonsense counts nothing")
		for _ = 1, 3 do
			w.now += R.bankMax * R.bankSeconds
			w.b:races(1, "a", "Ann", 1000, 0)
		end
		expectEq((w.b:score("a", "2026-10-19")), R.memberCap, "one member's share is capped")
	end)

	test("crew battles: live wins, head to head and the daily cap", function()
		local w = make({ row("a", 1000, 3), row("b", 1000, 3), row("c", 99999, 3) })
		expectEq(w.b:live(1, "a", "Ann", 2, "b"), R.h2h, "beat the rival crew")
		expectEq(w.b:live(1, "a", "Ann", 3, "c"), R.live, "beat someone else")
		expectEq(w.b:live(1, "a", "Ann", 4, nil), R.live, "beat someone with no crew")
		expectEq(w.b:live(1, "a", "Ann", 2, "b"), R.h2h, "twice")
		expectEq(w.b:live(1, "a", "Ann", 2, "b"), R.h2h, "three times")
		expectEq(w.b:live(1, "a", "Ann", 2, "b"), 0, "not a fourth time today")
		w.now += DAY
		expectEq(w.b:live(1, "a", "Ann", 2, "b"), R.h2h, "again tomorrow")
		local v = w.b:battle(1, "a").current
		expectEq(v.us.members[1].h2h, 4, "head-to-head wins counted")
		expectEq(v.us.score, 4 * R.h2h + 2 * R.live, "the crew's score")
		expectEq(v.them.score, 0, "the rival's")
		expectEq(v.result, nil, "still on")
	end)

	test("crew battles: the result and victory and MVP chests", function()
		local w = make({ row("a", 1000, 3), row("b", 1000, 3) })
		w.b:races(1, "a", "Ann", 30, 10)
		w.b:races(2, "a", "Bo", 3, 0)
		w.b:races(5, "b", "Cy", 20, 0)
		w.b:scoredFor(1, "a")
		w.now += 7 * DAY
		local v = w.b:battle(1, "a").last
		expectEq(v.result, "win", "more points wins")
		expectEq(table.concat(v.claimable, ","), "battle,mvp", "victory and MVP chests")
		expectEq(table.concat(w.b:battle(2, "a").last.claimable, ","), "", "too few points for a chest")
		expectEq(w.b:battle(5, "b").last.result, "loss", "the other side lost")
		expectEq(#w.b:battle(5, "b").last.claimable, 0, "no chest for a loss")
		expectEq(#w.b:battle(1, "a", { ["battle:2026-10-19"] = true, ["mvp:2026-10-19"] = true }).last.claimable, 0, "claimed once")
		-- Changing crews keeps last week's chest.
		expectEq(table.concat(w.b:battle(1, nil).last.claimable, ","), "battle,mvp", "after leaving")
		-- This week is a new battle.
		expectEq(w.b:battle(1, "a").current.week, "2026-10-26", "next week's battle")
	end)
end
