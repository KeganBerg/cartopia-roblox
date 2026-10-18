--!nocheck
-- Tests for the server's arcade (server/Arcade): starting a run (free plays, then fuel), the
-- plausibility checks ported from supabase/migrations/0086_arcade_boards.sql arcade_ok, the pay
-- from the converted rules, the weekly boards and the top-3 Gold crate prizes (0087).

local Arcade = require("../src/server/Arcade")
local Towns = require("../src/server/Towns")
local Boards = require("../src/server/Boards")
local Js = require("../src/shared/Game/__js")

local G = "../src/shared/Game/"
-- Wednesday 2026-10-14 12:00 UTC.
local WED = 1791979200000
local NOW = WED
Js.setClock(function()
	return NOW
end)

local function setup()
	local store = require(G .. "store")
	local towns = Towns.new(store, function()
		return NOW
	end)
	local t = 0
	local boards = {}
	for _, g in Arcade.BOARD_GAMES do
		boards[g] = Boards.new(`Arcade_{g}`, nil, function()
			return t
		end)
	end
	local n = 0
	local arcade = Arcade.new(towns, {
		store = store,
		data = require(G .. "data"),
		arcade = require(G .. "arcade"),
		arcadeMore = require(G .. "arcadeMore"),
		trial = require(G .. "trial"),
		boards = boards,
		clock = function()
			return t
		end,
		now = function()
			return NOW
		end,
		random = function()
			n += 1
			return (n * 0.37) % 1
		end,
	})
	local function town(id)
		towns:open(id, nil)
		towns:_with(id, function(s)
			store.useGame.setState({ level = 10, fuel = 50 })
		end)
	end
	-- What finishArcade pays for `coins` now: arcade boosts (game/boosts.ts) can multiply it.
	local function boosted(id, coins)
		return towns:_with(id, function(s)
			local b = require(G .. "boosts").boostFor(s.boosts, "arcade", coins > 0, NOW, coins > 0)
			return math.floor(coins * b.mult + 0.5)
		end)
	end
	local function get(id, k)
		return towns:_with(id, function(s)
			return s[k]
		end)
	end
	return arcade, towns, town, get, function(dt)
		t += dt
	end, boosted
end

local function eq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

return function(test)
	local arcade = require(G .. "arcade")
	local more = require(G .. "arcadeMore")
	local data = require(G .. "data")

	test("arcade_ok matches the web's SQL caps", function()
		-- chase: under 400 points a second, 250k at most
		assert(Arcade.ok("chase", 4000, 10))
		assert(not Arcade.ok("chase", 4001, 10))
		assert(not Arcade.ok("chase", 250001, 10000))
		assert(not Arcade.ok("chase", -1, 10))
		assert(not Arcade.ok("chase", 0 / 0, 10))
		-- pit: at least 4 s, no longer than the run, 120 at most
		assert(Arcade.ok("pit", 8.4, 20))
		assert(not Arcade.ok("pit", 3.9, 20))
		assert(not Arcade.ok("pit", 21, 20))
		assert(not Arcade.ok("pit", 121, 500))
		-- wash: a car a second, 60 at most
		assert(Arcade.ok("wash", 30, 30))
		assert(not Arcade.ok("wash", 31, 30))
		assert(not Arcade.ok("wash", 61, 100))
		-- delivery: one every 3 seconds, 60 at most
		assert(Arcade.ok("delivery", 10, 30))
		assert(not Arcade.ok("delivery", 11, 30))
		assert(not Arcade.ok("delivery", 61, 1000))
		-- stunt: 6000 at most, 1500 per whole 3 seconds
		assert(Arcade.ok("stunt", 3000, 6))
		assert(not Arcade.ok("stunt", 3001, 8.9))
		assert(not Arcade.ok("stunt", 6001, 100))
		assert(not Arcade.ok("park", 10, 100))
	end)

	test("week keys and finished weeks", function()
		eq(Arcade.weekMs("2026-10-12"), 1791763200000, "Monday 12 Oct 2026")
		eq(Arcade.weekMs("2026-10-13"), nil, "a Tuesday")
		eq(Arcade.weekMs("soon"), nil, "not a date")
		eq(require(G .. "trial").trialWeek(WED), "2026-10-12", "this week")
	end)

	test("runs start free three times a day, then cost fuel", function()
		local a, _, town, get, tick, boosted = setup()
		town(1)
		for i = 1, 3 do
			local run = assert(a:start(1, "chase"))
			assert(run.free, "free play")
			eq(run.freeLeft, 3 - i, "free left")
			a:submit(1, "chase", 0, { quit = true })
			tick(5)
		end
		eq(get(1, "fuel"), 50, "free plays cost no fuel")
		local run = assert(a:start(1, "chase"))
		assert(not run.free)
		eq(get(1, "fuel"), 50 - arcade.ARCADE_FUEL, "fuel spent")
		-- Starts 3 seconds apart, as 0086.
		local none, why = a:start(1, "chase")
		eq(none, nil, "too soon")
		eq(why, "slow down", "why")
		-- No fuel: refused with the "you need" note.
		tick(5)
		local towns = a.towns
		towns:_with(1, function(s)
			require(G .. "store").useGame.setState({ fuel = 1 })
		end)
		local _, need = a:start(1, "chase")
		eq(need, "need fuel", "out of fuel")
		eq(get(1, "need").res, "fuel", "need note")
		-- Other games still have their own free plays; a new day refills them.
		assert(a:start(1, "pit")).free = true
		NOW += 86400000
		eq(a:freeLeft(1, "chase"), arcade.FREE_PLAYS, "a new day")
		NOW = WED
		assert(not a:start(1, "nope"))
	end)

	test("chase pays chaseReward when the score is plausible", function()
		local a, _, town, get, tick, boosted = setup()
		town(1)
		eq(select(2, a:submit(1, "chase", 100, {})), "no run to finish", "needs a start")
		assert(a:start(1, "chase"))
		tick(30)
		local coins = get(1, "coins")
		-- 30 s can't make 12,001+ points.
		eq(select(2, a:submit(1, "chase", 12001, {})), "bad result", "too many points")
		eq(get(1, "coins"), coins, "nothing paid")
		eq(select(2, a:submit(1, "chase", 100, {})), "no run to finish", "a refused run is over")
		tick(5)
		assert(a:start(1, "chase"))
		tick(40)
		local want = arcade.chaseReward(3000, 10)
		local gets = boosted(1, want.coins)
		local r = assert(a:submit(1, "chase", 3000, {}))
		eq(r.coins, want.coins, "coins")
		eq(r.xp, want.xp, "xp")
		eq(r.xpGain, data.xpGain(10, want.xp), "xp shown")
		assert(r.record, "a first score is a best")
		eq(get(1, "coins"), coins + gets, "paid into the town")
		eq(get(1, "stats").arcadePlays, 1, "counted as an arcade play")
		eq(r.place, 1, "first on the board")
		eq(r.board.top[1].best, 3000, "board shows the score")
		eq(a:state(1).chase, 3000, "best kept")
		tick(5)
		assert(a:start(1, "chase"))
		tick(40)
		assert(not assert(a:submit(1, "chase", 2000, {})).record, "a lower score isn't a best")
		eq(a:board(1, "chase").me.best, 3000, "the board keeps the best")
	end)

	test("parking pro: lots open in turn, times are checked, stars pay parkReward", function()
		local a, _, town, get, tick, boosted = setup()
		town(1)
		eq(select(2, a:start(1, "park", 2)), "lot locked", "lot 2 locked")
		eq(select(2, a:start(1, "park", 99)), "no such lot", "no lot 99")
		assert(a:start(1, "park", 1))
		tick(20)
		-- Lot 1 is 9.5 apart: no car parks in 1 second.
		eq(select(2, a:submit(1, "park", 1, { bumps = 0, parked = true })), "bad result", "too quick")
		tick(5)
		assert(a:start(1, "park", 1))
		tick(20)
		eq(select(2, a:submit(1, "park", 25, { bumps = 0, parked = true })), "bad result", "longer than the run")
		tick(5)
		assert(a:start(1, "park", 1))
		tick(20)
		local coins = get(1, "coins")
		local gets = boosted(1, arcade.parkReward(0, 3, 10).coins)
		local r = assert(a:submit(1, "park", 8, { bumps = 0, parked = true }))
		eq(r.stars, arcade.parkStars(8, 0, arcade.PARK_LOTS[1].par), "stars")
		eq(r.stars, 3, "three stars under par")
		local want = arcade.parkReward(0, 3, 10)
		eq(r.coins, want.coins, "coins")
		eq(get(1, "coins"), coins + gets, "paid")
		eq(r.board, nil, "no board for parking")
		eq(a:state(1).park[1], 3, "lot stars kept")
		tick(5)
		-- Lot 2 is open now; a run with too many dents pays nothing.
		assert(a:start(1, "park", 2))
		tick(20)
		coins = get(1, "coins")
		local bad = assert(a:submit(1, "park", 10, { bumps = 3, parked = true }))
		eq(bad.stars, 0, "dented out")
		eq(get(1, "coins"), coins, "no pay")
		eq(select(2, a:submit(1, "park", 10, { bumps = 3 })), "no run to finish", "one submit a run")
	end)

	test("star games pay starReward and keep bests (Pit Stop lowest)", function()
		local a, _, town, get, tick, boosted = setup()
		town(1)
		assert(a:start(1, "pit"))
		tick(15)
		local coins = get(1, "coins")
		local gets = boosted(1, more.starReward(3, 10).coins)
		local r = assert(a:submit(1, "pit", 8.2, {}))
		eq(r.stars, more.pitStars(8.2), "pit stars")
		eq(r.coins, more.starReward(3, 10).coins, "pit pay")
		eq(get(1, "coins"), coins + gets, "paid")
		tick(5)
		assert(a:start(1, "pit"))
		tick(15)
		assert(not assert(a:submit(1, "pit", 9.5, {})).record, "slower isn't a best")
		eq(a:state(1).stars.pit.best, 8.2, "pit best is the lowest")
		eq(a:board(1, "pit").me.best, 8.2, "pit board keeps the lowest")
		-- Wash: 2 cars is no stars, so no pay and no best.
		tick(5)
		assert(a:start(1, "wash"))
		tick(30)
		coins = get(1, "coins")
		local w = assert(a:submit(1, "wash", 2, {}))
		eq(w.stars, 0, "no stars")
		eq(get(1, "coins"), coins, "no pay")
		eq(a:state(1).stars.wash.best, 0, "no best without a star")
		-- Delivery and stunt.
		tick(5)
		assert(a:start(1, "delivery"))
		tick(62)
		local dd = assert(a:submit(1, "delivery", 6, {}))
		eq(dd.stars, more.dashStars(6), "delivery stars")
		tick(5)
		assert(a:start(1, "stunt"))
		tick(5)
		eq(select(2, a:submit(1, "stunt", 2000, {})), "bad result", "2000 in 5 seconds")
		tick(5)
		assert(a:start(1, "stunt"))
		tick(20)
		local st = assert(a:submit(1, "stunt", 2100, {}))
		eq(st.stars, 3, "stunt stars")
		eq(st.coins, more.starReward(3, 10).coins, "stunt pay")
	end)

	test("weekly boards rank players, and top 3 win a Gold crate once", function()
		local a, towns, town, get, tick, boosted = setup()
		for id = 1, 4 do
			town(id)
		end
		local function run(id, game, v, secs)
			assert(a:start(id, game))
			tick(secs)
			return assert(a:submit(id, game, v, {}))
		end
		run(1, "stunt", 1200, 20)
		run(2, "stunt", 1800, 20)
		run(3, "stunt", 600, 20)
		local last = run(4, "stunt", 300, 20)
		eq(last.place, 4, "fourth")
		local b = a:board(2, "stunt")
		eq(b.total, 4, "four on the board")
		eq(b.top[1].best, 1800, "highest first")
		eq(b.top[1].owner, 2, "player 2 leads")
		eq(b.me.place, 1, "my place")
		run(1, "pit", 9, 20)
		run(2, "pit", 8, 20)
		eq(a:board(1, "pit").top[1].owner, 2, "lowest pit time first")
		-- Not finished yet: no prizes.
		eq(#a:prizes(1), 0, "week still on")
		-- Next Monday 00:05 is still within the 10 minutes' grace.
		NOW = Arcade.weekMs("2026-10-19") + 5 * 60000
		eq(#a:prizes(1), 0, "grace period")
		NOW += 10 * 60000
		local p1 = a:prizes(1)
		eq(#p1, 2, "player 1: 2nd at pit and stunt")
		eq(#a:prizes(4), 0, "fourth wins nothing")
		local stunt = nil
		for _, p in p1 do
			if p.game == "stunt" then
				stunt = p
			end
		end
		eq(stunt.place, 2, "second at stunt")
		eq(stunt.claimed, false, "not claimed")
		eq(select(2, a:claim(1, "2026-10-19", "stunt")), "no such prize", "this week isn't won")
		local got = assert(a:claim(1, "2026-10-12", "stunt"))
		eq(got.source, "arcade:2026-10-12:stunt", "source")
		local free = get(1, "freeCrates")
		eq(free[#free], "arcade:2026-10-12:stunt", "in freeCrates")
		eq(select(2, a:claim(1, "2026-10-12", "stunt")), "already claimed", "once")
		-- The claim outlives the session (records are written after each change).
		a:close(1)
		eq(select(2, a:claim(1, "2026-10-12", "stunt")), "already claimed", "after a rejoin")
		-- Four weeks on, the prize has gone.
		NOW = Arcade.weekMs("2026-11-16") + 20 * 60000
		eq(#a:prizes(2), 0, "too old")
		NOW = WED
		local _ = towns
	end)
end
