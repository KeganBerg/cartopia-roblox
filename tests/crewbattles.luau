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
			return { id = id, name = "Crew " .. id, tag = id:upper(), emblem = "🏁", color = "#ffffff", members = (w.members or {})[id] or {} }
		end,
		ghost = function(uid)
			return (w.ghosts or {})[uid]
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

	test("crew battles: war chests at 40% and 100% of par, win or lose", function()
		local w = make({ row("a", 1000, 3), row("b", 1000, 3) })
		-- (Crew "a" from make() has no members listed, so its par counts the scorers, at least 2.)
		w.b:races(1, "a", "Ann", 10, 0)
		local v = w.b:battle(1, "a").current
		expectEq(v.par, R.par * 2, "par for two")
		expectEq(v.tiers[1].need, math.ceil(R.par * 2 * 0.4), "first tier")
		expectEq(v.tiers[1].reached, false, "not yet")
		w.b:races(1, "a", "Ann", 30, 10)
		w.b:races(2, "a", "Bo", 5, 0)
		v = w.b:battle(1, "a").current
		expectEq(v.par, R.par * 2, "still two")
		expectEq(v.tiers[1].claimable, true, "first war chest")
		expectEq(v.tiers[2].reached, false, "second not yet")
		expectEq(w.b:battle(2, "a").current.tiers[1].claimable, false, "too few points of his own")
		expectEq(w.b:battle(1, "a", { ["tier1:2026-10-19"] = true }).current.tiers[1].claimable, false, "claimed")
	end)

	test("crew battles: the war log, record and league", function()
		local w = make({ row("a", 1000, 3) })
		expectEq(w.b:battle(1, "a").league.name, "Bronze", "a new crew")
		-- Three weeks: two big wins against street crews, then a quiet loss.
		for week = 1, 3 do
			if week < 3 then
				for _ = 1, 6 do
					w.b:races(1, "a", "Ann", 100, 100)
					w.now += R.bankMax * R.bankSeconds
				end
			else
				w.b:battleOf("a")
			end
			w.now = MONDAY + week * 7 * DAY
		end
		local b = w.b:battle(1, "a")
		expectEq(#b.log, 3, "three wars")
		expectEq(b.log[1].result, "loss", "newest first")
		expectEq(b.log[2].result, "win", "a win")
		expectEq(b.log[2].rival.bot, true, "against a street crew")
		expectEq(b.record.wins, 2, "wins")
		expectEq(b.record.losses, 1, "losses")
		expectEq(b.record.streak, 0, "the streak broke")
		expectEq(b.league.rating, 1000 + 2 * 30 - 15, "rating")
		expectEq(b.league.name, "Bronze", "league (1045)")
		expectEq(b.league.next.name, "Silver", "next league")
		expectEq(#w.b:battle(1, "a").log, 3, "results kept")
	end)

	test("crew battles: war races on the map, stars and the daily limit", function()
		local w = make({ row("a", 1000, 3), row("b", 1000, 3), row("c", 99999, 3) })
		w.members = { b = { ["5"] = { name = "Cy" } } }
		w.ghosts = { [5] = { t = 8.0, car = "Fast", model = "pip", color = "#000000", pi = 100, town = "Cy Town" } }
		expectEq(CrewBattles.stars(8.1, 8), 0, "slower: no stars")
		expectEq(CrewBattles.stars(7.95, 8), 1, "a win")
		expectEq(CrewBattles.stars(7.9, 8), 2, "by 1%")
		expectEq(CrewBattles.stars(7.7, 8), 3, "by 3%")
		expectEq(select(2, w.b:attackStart(1, "a", "6", 7)), "not rival", "only the rival crew's members")
		local spot = w.b:attackStart(1, "a", "5", 7)
		expectEq(spot.their, 8.0, "their ghost's time")
		expectEq(spot.left, R.attacksPerDay - 1, "one used")
		local r = w.b:attackFinish(1, "a", "Ann", spot, 7.7, true)
		expectEq(r.stars, 3, "three stars")
		expectEq((w.b:score("a", "2026-10-19")), 3 * R.starPoints, "war points")
		local lost = w.b:attackFinish(1, "a", "Ann", w.b:attackStart(1, "a", "5", 7), math.huge, true)
		expectEq(lost.won, false, "an unfinished run is a loss")
		w.b:attackStart(1, "a", "5", 7)
		expectEq(select(2, w.b:attackStart(1, "a", "5", 7)), "no war races", "three a day")
		expectEq(w.b:attacksLeft(1), 0, "none left")
		-- Both crews see the races, each from its own side.
		local mine = w.b:battle(1, "a").current
		expectEq(#mine.attacks, 2, "two finished")
		expectEq(mine.attacks[2].side, "us", "ours")
		expectEq(mine.them.roster[1].t, 8.0, "their roster with times")
		w.members.b["9"] = { name = "Di" }
		expectEq(w.b:view(w.b:battleOf("b"), "b", 9).attacks[1].side, "them", "theirs from the other side")
		w.now += DAY
		expectEq(w.b:attacksLeft(1), R.attacksPerDay, "back the next day")
		-- A street crew's drivers race a par for the racer's car, tougher for stronger drivers.
		local x = w.b:battleOf("c")
		local bot = w.b:attackStart(2, "c", "bot1", 7)
		expectEq(bot.their, CrewBattles.streetTime(7, x.bot.members[1].w), "street par")
		expectEq(select(2, w.b:attackStart(2, "c", "bot99", 7)), "not rival", "no such driver")
	end)
end
