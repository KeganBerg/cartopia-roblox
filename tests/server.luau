--!nocheck
-- Tests for the server modules: session-locked saves (Saves) and running towns (Towns), with an
-- in-memory DataStore and the transpiled store.

local Saves = require("../src/server/Saves")
local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")

-- A DataStore stand-in: UpdateAsync with Roblox's rules (returning nil leaves the value alone).
-- Values are copied in and out, as a real DataStore serialises them.
local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = copy(x)
	end
	return out
end
local function fakeStore()
	local data, fail, calls = {}, 0, 0
	local store = { data = data, message = "DataStore request was rejected" }
	function store:UpdateAsync(key, fn)
		calls += 1
		if fail > 0 then
			fail -= 1
			error(store.message)
		end
		local new = fn(copy(data[key]))
		if new ~= nil then
			data[key] = copy(new)
		end
		return new
	end
	function store.failNext(n)
		fail = n
	end
	function store.calls()
		return calls
	end
	return store
end

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

return function(test)
	local clock = 1000
	local function saves(store, job)
		return Saves.new({ store = store, job = job, now = function() return clock end, wait = function() end })
	end

	test("saves: a new player gets nil, then their save back", function()
		local store = fakeStore()
		local a = saves(store, "A")
		expectEq(a:load(1), nil, "first load")
		expectEq(a:write(1, { coins = 5 }, true), true, "write")
		expectEq(a:load(1).coins, 5, "second load")
	end)

	test("saves: remembers when the save was last written, for the welcome back", function()
		local store = fakeStore()
		local a = saves(store, "A")
		a:load(1)
		expectEq(a:lastSeen(1), nil, "a new player")
		clock = 5000
		a:write(1, { coins = 1 }, true)
		clock = 9000
		local b = saves(store, "B")
		b:load(1)
		expectEq(b:lastSeen(1), 5000, "last written")
		clock = 1000
	end)

	test("saves: another server can't load or write a locked town", function()
		local store = fakeStore()
		local a, b = saves(store, "A"), saves(store, "B")
		a:load(1)
		local ok, err = pcall(b.load, b, 1)
		expectEq(ok, false, "B loads while A holds the lock")
		expectEq(err.reason, "locked", "why")
		expectEq(b:write(1, { coins = 999 }), false, "B writes without the lock")
		a:write(1, { coins = 7 }, true)
		expectEq(b:load(1).coins, 7, "B loads after A releases")
	end)

	test("saves: a stale lock from a crashed server is taken over", function()
		local store = fakeStore()
		local a, b = saves(store, "A"), saves(store, "B")
		a:load(1)
		a:write(1, { coins = 3 })
		clock += Saves.LOCK_TTL + 1
		expectEq(b:load(1).coins, 3, "B takes over")
		expectEq(a:write(1, { coins = 0 }), false, "A's late write is refused")
		expectEq(store.data.town_1.save.coins, 3, "stored coins")
	end)

	test("saves: retries through DataStore errors", function()
		local store = fakeStore()
		local a = saves(store, "A")
		store.failNext(Saves.RETRIES - 1)
		expectEq(a:load(1), nil, "load after errors")
		expectEq(a:holds(1), true, "holds the lock")
	end)

	test("saves: a DataStore that keeps failing is a failure, not a lock", function()
		local store = fakeStore()
		local a = saves(store, "A")
		store.failNext(Saves.RETRIES)
		local ok, err = pcall(a.load, a, 1)
		expectEq(ok, false, "load")
		expectEq(err.reason, "failed", "why")
	end)

	test("saves: Studio without API access gives up at once", function()
		local store = fakeStore()
		store.message = "StudioAccessToApisNotAllowed: You must publish this place to the web to access DataStore. 403"
		local a = saves(store, "studio")
		store.failNext(Saves.RETRIES)
		local ok, err = pcall(a.load, a, 1)
		expectEq(ok, false, "load")
		expectEq(err.reason, "off", "why")
		expectEq(store.calls(), 1, "tries")
		expectEq(a:holds(1), false, "holds the lock")
	end)

	test("saves: a Studio session takes back its own lock from an earlier one", function()
		local store = fakeStore()
		saves(store, "studio"):load(1) -- an earlier Play that stopped without saving
		expectEq(saves(store, "studio"):load(1), nil, "next Play loads")
	end)

	local now = Js.JsDate.UTC(2026, 9, 17, 12)
	Js.setClock(function()
		return now
	end)
	local store = require("../src/shared/Game/store")
	local towns = Towns.new(store, function()
		return now
	end)

	test("towns: checks client requests", function()
		expectEq(Towns.check("buyCar", { "pip", "#c62828" }, 2), true, "buyCar")
		expectEq(Towns.check("loadSave", { {} }, 1), false, "loadSave")
		expectEq(Towns.check("finishRace", { true, 1e9 }, 2), false, "finishRace")
		expectEq(Towns.check("buyCar", { "pip" }, 1), false, "missing argument")
		expectEq(Towns.check("buyCar", { "pip", "#fff", 1 }, 3), false, "extra argument")
		expectEq(Towns.check("bulldoze", { 0 / 0, 1 }, 2), false, "NaN")
		expectEq(Towns.check("upgradeCar", { "c1", "rocket" }, 2), false, "unknown slot")
		expectEq(Towns.check("assignCar", { "b1", nil }, 2), true, "optional nil")
	end)

	test("towns: each player's town is separate, and survives a save round trip", function()
		towns:open(1, nil)
		towns:open(2, nil)
		local coins = towns:save(2).coins
		expectEq(towns:run(1, "buyCar", "pip", "#c62828"), false, "no car before Rusty's Rescue")
		expectEq(towns:snapshot(1).toasts[1], "Build Rusty's Rescue first. Rusty finds you new cars!", "toast")
		expectEq(towns:run(1, "placeBuilding", "rescue", 12, 12), true, "player 1 builds Rusty's")
		expectEq(towns:run(1, "buyCar", "pip", "#c62828"), true, "player 1 buys a car")
		expectEq(#towns:save(1).cars, #towns:save(2).cars + 1, "only player 1 has the car")
		expectEq(towns:save(2).coins, coins, "player 2's coins")
		local saved = copy(towns:save(1))
		towns:close(1)
		towns:open(1, saved)
		expectEq(#towns:save(1).cars, #saved.cars, "cars after reload")
		expectEq(towns:save(1).coins, saved.coins, "coins after reload")
	end)

	test("towns: the Flair and Trophy Road pages' actions", function()
		expectEq(Towns.check("seeFlair", {}, 0), true, "seeFlair")
		expectEq(Towns.check("seeFlair", { 9 }, 1), false, "seeFlair takes nothing")
		expectEq(Towns.check("pickFlair", { "trail", "frost" }, 2), true, "pickFlair")
		expectEq(Towns.check("pickFlair", { "hat", "frost" }, 2), false, "pickFlair kind")
		expectEq(Towns.check("claimRoad", { 5 }, 1), false, "claimRoad takes nothing")
		towns:open(4, nil)
		towns:run(4, "seeFlair")
		expectEq(towns:save(4).flairSeen, 2, "the two starters seen")
		towns:run(4, "pickFlair", "trail", "frost")
		expectEq(towns:save(4).trail, nil, "a locked trail can't be picked")
		towns:_with(4, function()
			store.useGame.setState({ trophies = 120 })
		end)
		towns:run(4, "pickFlair", "trail", "frost")
		expectEq(towns:save(4).trail, "frost", "an open trail is picked")
		local coins = towns:save(4).coins
		towns:run(4, "claimRoad")
		expectEq(towns:save(4).road, 4, "four stops claimed")
		assert(towns:save(4).coins > coins, "the stops pay coins")
	end)

	test("towns: jobs pay out on the server clock", function()
		towns:open(3, nil)
		local pizza
		for _, b in towns:save(3).buildings do
			if b.def == "pizza" then
				pizza = b.uid
				break
			end
		end
		assert(pizza, "starter town has a pizza place")
		towns:run(3, "tapBuilding", pizza)
		local coins = towns:save(3).coins
		now += 60 * 60 * 1000
		towns:run(3, "tapBuilding", pizza)
		assert(towns:save(3).coins > coins, "collecting the job pays coins")
		local snap = towns:snapshot(3)
		assert(#snap.toasts >= 0 and snap.save.coins == towns:save(3).coins, "snapshot")
		expectEq(#towns:snapshot(3).toasts, 0, "toasts are only sent once")
	end)

	test("towns: the tutorial moves on one step at a time, and only once each step is done", function()
		towns:open(5, nil)
		expectEq(towns:save(5).tutorial, 0, "a new town starts the tutorial")
		local function refused(name, ...)
			local ok = pcall(towns.run, towns, 5, name, ...)
			return not ok
		end
		expectEq(refused("setTutorial", 2), true, "two steps at once")
		expectEq(refused("setTutorial", 99), true, "straight to done")
		expectEq(refused("setTutorial", 0.5), true, "half a step")
		expectEq(refused("setTutorial", 1), false, "Next on the welcome step")
		expectEq(towns:save(5).tutorial, 1, "on the pizza step")
		expectEq(refused("setTutorial", 2), true, "the pizza step before a job")
		expectEq(refused("setTutorial", 0), true, "a step back")
		local pizza
		for _, b in towns:save(5).buildings do
			if b.def == "pizza" then
				pizza = b.uid
				break
			end
		end
		towns:run(5, "tapBuilding", pizza)
		expectEq(refused("setTutorial", 2), false, "a job started")
		expectEq(refused("setTutorial", 3), true, "the collect step before collecting")
		now += 60 * 60 * 1000
		towns:run(5, "tapBuilding", pizza)
		expectEq(refused("setTutorial", 3), false, "collected")
		expectEq(refused("setTutorial", 4), true, "Rusty's not built yet")
		expectEq(refused("tutorialStyle", "x", "#e53935", "#e53935"), true, "the free paint before its step")
		expectEq(refused("skipTutorial", 50), true, "a skip naming a later paint step")
		expectEq(refused("skipTutorial", 6), false, "Skip")
		expectEq(towns:save(5).tutorial, 99, "skipped")
		expectEq(towns:save(5).freePaint, true, "skipped before the paint pick: the free paint waits")
		expectEq(refused("skipTutorial", 6), true, "skipping twice")
		expectEq(refused("setTutorial", 99), true, "done is done")
	end)

	test("towns: the goal screen finishes the tutorial; old towns skip it, new ones don't", function()
		towns:open(6, nil)
		towns:_with(6, function()
			store.useGame.setState({ tutorial = 9 })
		end)
		towns:run(6, "setTutorial", 99)
		expectEq(towns:save(6).tutorial, 99, "Let's go! on the goal screen")
		-- A town saved before the port had a tutorial: still step 0, but played.
		towns:open(7, nil)
		local fresh = copy(towns:save(7))
		local played = copy(fresh)
		played.level = 4
		towns:close(7)
		towns:open(7, played)
		expectEq(towns:save(7).tutorial, 99, "a played town at step 0 skips the tutorial")
		towns:close(7)
		towns:open(7, fresh)
		expectEq(towns:save(7).tutorial, 0, "a fresh town at step 0 keeps it")
		local mid = copy(fresh)
		mid.tutorial, mid.level = 5, 2
		towns:close(7)
		towns:open(7, mid)
		expectEq(towns:save(7).tutorial, 5, "a town part way through carries on")
	end)
	test("towns: a new season leaves the last one's recap until its card is closed", function()
		local day = 86400000
		local was = now
		-- Ten days into the first season.
		local start = require("../src/shared/Game/data").SEASON_START + 10 * day
		now = start
		towns:open(8, nil)
		local first = towns:save(8)
		expectEq(first.seasonBase ~= nil, true, "a fresh town takes a snapshot")
		expectEq(first.recap, nil, "and has nothing to look back on")
		local n = first.seasonBase.n
		-- Play a little this season: two races, one won.
		towns:_with(8, function(s)
			local stats = table.clone(s.stats)
			stats.races = (stats.races or 0) + 2
			stats.racesWon = (stats.racesWon or 0) + 1
			store.useGame.setState({ stats = stats })
		end)
		towns:tick(8)
		expectEq(towns:save(8).recap, nil, "no recap while the season runs")
		-- The next season starts.
		now = start + 43 * day
		towns:tick(8)
		local after = towns:save(8)
		expectEq(after.seasonBase.n, n + 1, "the snapshot moves to the new season")
		expectEq(after.recap ~= nil, true, "the recap waits on the town")
		expectEq(after.recap.n, n, "of the season that ended")
		expectEq(after.recap.races, 2, "its races")
		expectEq(after.recap.wins, 1, "its wins")
		-- Survives a reload, then the card's button clears it.
		local saved = copy(after)
		towns:close(8)
		towns:open(8, saved)
		expectEq(towns:save(8).recap ~= nil, true, "kept through a reload")
		expectEq(Towns.check("closeRecap", {}, 0), true, "closeRecap is allowed")
		towns:run(8, "closeRecap")
		expectEq(towns:save(8).recap, nil, "closed")
		-- A season with nothing played leaves no recap.
		now = start + 85 * day
		towns:tick(8)
		expectEq(towns:save(8).recap, nil, "nothing played, nothing to show")
		expectEq(towns:save(8).seasonBase.n, n + 2, "but the snapshot still moves on")
		now = was
	end)

	test("prefs: settings are cleaned, and sound and settings changes keep each other", function()
		local Prefs = require("../src/server/Prefs")
		local p = Prefs.clean(nil)
		expectEq(p.ui.graphics, "auto", "graphics default")
		expectEq(p.ui.askSell, true, "asks by default")
		expectEq(p.ui.reduceMotion, nil, "follows the device")
		local bad = Prefs.cleanUi({ graphics = "ultra", fps = "yes", askLeave = false, calmFlash = true, tips = { "gems", "gems", 5, string.rep("x", 40) } })
		expectEq(bad.graphics, "auto", "unknown graphics")
		expectEq(bad.fps, false, "fps must be true")
		expectEq(bad.askLeave, false, "turned off")
		expectEq(bad.calmFlash, true, "calm flashing")
		expectEq(#bad.tips, 1, "tips deduped and checked")
		local many = {}
		for i = 1, 50 do
			many[i] = `t{i}`
		end
		expectEq(#Prefs.cleanUi({ tips = many }).tips, Prefs.MAX_TIPS, "tips capped")
		local a = Prefs.merge(p, { ui = { graphics = "saver", tips = { "gems" } } })
		expectEq(a.ui.graphics, "saver", "settings change")
		expectEq(a.music.volume, 0.5, "sound kept")
		local b = Prefs.merge(a, { music = { on = false, volume = 0.2 }, town = { on = true, volume = 1 }, effects = 0.3 })
		expectEq(b.music.on, false, "sound change")
		expectEq(b.ui.graphics, "saver", "settings kept through a sound change")
		expectEq(b.ui.tips[1], "gems", "tips kept")
	end)
end
