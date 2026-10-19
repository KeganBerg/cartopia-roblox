--!nocheck
-- Tests for the town visitors (server/Visitors) and the street race against a visiting racer
-- (server/Modes/Street through server/Races), on a starter town run by Towns.

local Visitors = require("../src/server/Visitors")
local Races = require("../src/server/Races")
local Towns = require("../src/server/Towns")
local DragRace = require("../src/shared/DragRace")
local race = require("../src/shared/Game/race")
local Js = require("../src/shared/Game/__js")

local G = "../src/shared/Game/"
local data = require(G .. "data")

local function rng(seed)
	local x = seed
	return function()
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
end

local function setup(seed, records)
	local clock = { t = 1760000000000 }
	Js.setClock(function()
		return clock.t
	end)
	local store = require(G .. "store")
	local towns = Towns.new(store, function()
		return clock.t
	end)
	towns:open(1, nil)
	-- Past the tutorial, with the starter town's roads.
	towns:_with(1, function()
		store.useGame.setState({ tutorial = 99 })
	end)
	local random = rng(seed or 11)
	local visitors = Visitors.new(towns, { store = store, data = data, random = random, now = function()
		return clock.t
	end, records = records })
	return visitors, towns, clock, store
end

-- A visitor of `kind`, made the way next() makes one, put in town.
local function bring(visitors, towns, clock, kind)
	local v
	towns:_with(1, function(s)
		v = visitors:_make(s, kind, clock.t)
	end)
	visitors.cur[1] = v
	return v
end

local function drive(spec)
	local r = DragRace.new(spec)
	local holdTick = math.round(1.7 / DragRace.DT)
	local released = false
	while not r.done do
		if r.tick == holdTick then
			DragRace.input(r, "down")
		end
		if r.me.launched and not released then
			DragRace.input(r, "up")
			released = true
		end
		if r.me.launched and r.me.finished == nil and r.me.gear < race.TOP_GEAR and r.me.rpm >= 0.9 then
			DragRace.input(r, "down")
		end
		if r.me.gear >= 3 and not r.me.boostUsed then
			DragRace.input(r, "boost")
		end
		DragRace.step(r)
	end
	return r
end

local function racesFor(towns, visitors, store)
	local t = 0
	local races = Races.new(towns, {
		store = store,
		data = data,
		raceCar = require(G .. "raceCar"),
		fairRace = require(G .. "fairRace"),
		fairPi = require(G .. "fairPi"),
		grip = require(G .. "grip"),
		weather = require(G .. "weather"),
		venues = require(G .. "scene_venues"),
		paintRivals = require(G .. "paintRivals"),
		rivals = require(G .. "rivals"),
		distance = require(G .. "distance"),
		DragRace = DragRace,
		random = {
			NextNumber = function()
				return 0.5
			end,
			NextInteger = function(_, lo, hi)
				return math.floor((lo + hi) / 2)
			end,
		},
		clock = function()
			return t
		end,
		modes = { street = require("../src/server/Modes/Street") },
		game = function(name)
			return require(G .. name)
		end,
		visitors = visitors,
	})
	return races, function(dt)
		t += dt
	end
end

return function(test)
	test("visitors: nobody comes during the tutorial; then one does, and stays until it's paid", function()
		local visitors, towns, clock, store = setup()
		towns:_with(1, function()
			store.useGame.setState({ tutorial = 3 })
		end)
		local w, why = visitors:next(1)
		assert(w.wait and why == "not ready", "not during the tutorial")
		towns:_with(1, function()
			store.useGame.setState({ tutorial = 99 })
		end)
		local v = assert(visitors:next(1))
		assert(v.id and data.VISITORS[v.kind], `a visitor: {v.kind}`)
		assert(v.kind ~= "barn", "barn tips are off")
		assert(v.expiresAt == clock.t + data.VISITORS[v.kind].minutes * 60000, "their time")
		local level = towns:snapshot(1).save.level
		local p = data.VISITORS[v.kind].pay
		assert(v.coins == math.floor(p.coins + p.coinsPerLevel * level + 0.5), "coins from the level")
		assert(v.bucks == 0 or v.bucks == data.VISITOR_BUCKS, "gems")
		clock.t += 1000
		assert(visitors:next(1).id == v.id, "the same visitor while in town")
	end)

	test("visitors: tourists pay their tip once, through the store's visitorPrize", function()
		local visitors, towns, clock = setup()
		local v = bring(visitors, towns, clock, "tourist")
		local before = towns:snapshot(1).save
		local paid, why = visitors:claim(1, v.id)
		assert(paid, `claim: {why}`)
		local snap = towns:snapshot(1)
		assert(snap.save.coins == before.coins + v.coins, `coins {before.coins} -> {snap.save.coins}`)
		assert(snap.save.parts == before.parts + v.parts, "parts")
		assert(snap.save.visits == (before.visits or 0) + 1, "claim counted")
		assert(string.find(snap.toasts[#snap.toasts], "tourists loved", 1, true), tostring(snap.toasts[1]))
		local again, why2 = visitors:claim(1, v.id)
		assert(again == nil and why2 == "no such visitor", "paid once")
	end)

	test("visitors: the mystery car is gone after its time and the grace; a wrong id pays nothing", function()
		local visitors, towns, clock = setup()
		local v = bring(visitors, towns, clock, "mystery")
		assert(v.model == "zenith" and v.color == "#15151d", "the black supercar")
		assert(visitors:claim(1, "nope") == nil, "not theirs")
		assert(visitors:claim(1, 5) == nil, "not an id")
		clock.t = v.expiresAt + Visitors.GRACE_MS + 1
		local none, why = visitors:claim(1, v.id)
		assert(none == nil and why == "the visitor left", tostring(why))
		local v2 = bring(visitors, towns, clock, "mystery")
		clock.t = v2.expiresAt + Visitors.GRACE_MS - 1
		assert(visitors:claim(1, v2.id), "within the grace")
	end)

	test("visitors: a street racer can't be claimed by tapping, only beaten", function()
		local visitors, towns, clock = setup()
		local v = bring(visitors, towns, clock, "racer")
		local none, why = visitors:claim(1, v.id)
		assert(none == nil and why == "race first", tostring(why))
		assert(v.name:find(" from ", 1, true), "who and where from")
		assert(not data.carDef(v.model).bucks, "an everyday car")
	end)

	test("visitors: none sooner than the gap, at most a day's worth, and the record is kept", function()
		local saved = {}
		local records = {
			get = function(id)
				return saved[id]
			end,
			set = function(id, rec)
				saved[id] = rec
			end,
		}
		local visitors, _, clock = setup(5, records)
		local v = assert(visitors:next(1))
		visitors:leave(1, v.id)
		local w = visitors:next(1)
		assert(w.wait and w.wait > 200 and w.wait <= data.VISIT_GAP_MIN * 60, `wait {w.wait}`)
		assert(saved[1] and saved[1].n == 1, "kept")
		-- A new session reads the record: still no visitor before the gap.
		local visitors2, towns2, clock2 = setup(6, records)
		clock2.t = clock.t + 1000
		assert(visitors2:next(1).wait, "the gap holds across a rejoin")
		local n = 1
		for _ = 1, 40 do
			clock2.t += data.VISIT_GAP_MIN * 60000
			local x = visitors2:next(1)
			if x.id then
				n += 1
				visitors2:leave(1, x.id)
			end
		end
		-- 40 gaps of 4 minutes is under three hours: the day's cap or the day's end comes first.
		assert(n <= data.VISITS_PER_DAY, `{n} today`)
		local _ = towns2
	end)

	test("visitors: kinds come about as often as the web's weights say, never the barn", function()
		local visitors = setup(3)
		local seen = { racer = 0, tourist = 0, mystery = 0, barn = 0 }
		local N = 4000
		for _ = 1, N do
			local k = visitors:rollKind(false)
			seen[k] += 1
		end
		assert(seen.barn == 0, "no barn")
		local total = data.VISITORS.racer.weight + data.VISITORS.tourist.weight + data.VISITORS.mystery.weight
		for _, k in { "racer", "tourist", "mystery" } do
			local want = data.VISITORS[k].weight / total
			local got = seen[k] / N
			assert(math.abs(got - want) < 0.03, `{k}: {got} vs {want}`)
		end
		local withBarn = 0
		for _ = 1, N do
			if visitors:rollKind(true) == "barn" then
				withBarn += 1
			end
		end
		assert(withBarn > 0, "the barn when asked for")
	end)

	test("visitors: a racer's PI is near the town's best car", function()
		local visitors, towns, clock = setup(9)
		local best = 0
		towns:_with(1, function(s)
			best = visitors:_bestPi(s)
		end)
		for _ = 1, 50 do
			local v = bring(visitors, towns, clock, "racer")
			assert(v.pi >= math.floor(best * 0.95) and v.pi <= math.ceil(best * 1.1), `pi {v.pi} vs {best}`)
		end
		assert(Visitors.piFactor(0.1, 1) == 1.1 and Visitors.piFactor(0.5, 0) == 0.95, "the factor")
	end)

	test("visitors: a barn find is a car from a spot the level has opened", function()
		local visitors = setup(4)
		local open = {}
		for _, sp in data.RESCUE_SPOTS do
			if sp.unlockLevel <= 1 then
				for _, c in sp.cars do
					open[c.model] = true
				end
			end
		end
		for _ = 1, 100 do
			local car = visitors:_barnCar(1)
			assert(open[car.model] and car.uid, `{car.model} at level 1`)
		end
	end)

	test("street race: free of fuel, pays the race and the racer's bonus on a win, once", function()
		local visitors, towns, clock, store = setup(2)
		local races, wait = racesFor(towns, visitors, store)
		local v = bring(visitors, towns, clock, "racer")
		local before = towns:snapshot(1).save
		local started, why = races:start(1, "street", v.id)
		assert(started, `start: {why}`)
		assert(started.rival.id == `street-{v.id}` and started.rival.name == v.name, "the racer")
		assert(towns:snapshot(1).save.fuel == before.fuel, "no fuel")
		local again = races:start(1, "street", v.id)
		assert(again == nil, "one race per visitor")
		local v2 = v
		clock.t += 60000
		local run = drive(started.spec)
		local mine, theirs = DragRace.times(run)
		wait(DragRace.GO_TICK * DragRace.DT + mine + 1)
		local coins0 = towns:snapshot(1).save.coins
		local res = assert(races:finish(1, run.events))
		local after = towns:snapshot(1).save
		assert(res.street, "street result")
		-- Good driving beats every rival (they're eased to what the car can beat).
		assert(mine <= theirs and res.won, "won")
		do
			assert(res.street.paid, "a win pays the bonus")
			assert(res.street.paid.coins == v2.coins, "the racer's bonus")
			-- The race prize can come boosted (the day's first win): at least prize + bonus.
			assert(after.coins - coins0 == res.coins and res.coins >= started.rival.prize + v2.coins, `coins {coins0} -> {after.coins} (race {started.rival.prize} + {v2.coins})`)
			assert(after.visits == (before.visits or 0) + 1, "claim counted")
		end
		assert(visitors:current(1) == nil, "they leave after the race")
	end)

	test("street race: a loss sends the racer off without their bonus", function()
		local visitors, towns, clock, store = setup(2)
		local races, wait = racesFor(towns, visitors, store)
		local v = bring(visitors, towns, clock, "racer")
		local started = assert(races:start(1, "street", v.id))
		clock.t += 60000
		-- Never launching: a sure loss.
		local r = DragRace.new(started.spec)
		while not r.done do
			DragRace.step(r)
		end
		wait(DragRace.MAX_SECONDS + 10)
		local visits = towns:snapshot(1).save.visits or 0
		local res = assert(races:finish(1, r.events))
		assert(not res.won and not res.street.paid, "lost")
		local snap = towns:snapshot(1)
		assert((snap.save.visits or 0) == visits, "no claim")
		local said = false
		for _, t in snap.toasts do
			if t:find("drove off laughing", 1, true) then
				said = true
			end
		end
		assert(said, "the racer gloats")
		assert(races:start(1, "street", v.id) == nil, "gone")
	end)

	test("street race: only against the racer in town", function()
		local visitors, towns, clock, store = setup(2)
		local races = racesFor(towns, visitors, store)
		local t = bring(visitors, towns, clock, "tourist")
		assert(races:start(1, "street", t.id) == nil, "not a racer")
		assert(races:start(1, "street", "v123") == nil, "not here")
		assert(races:start(1, "street", nil) == nil, "no id")
	end)
end
