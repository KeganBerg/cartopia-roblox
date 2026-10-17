--!nocheck
-- Calls the transpiled game rules with every input in Golden.luau and checks they answer exactly
-- what the web game does. Each adapter takes the case's args (ids, not objects), makes the same call
-- tools/gen-golden.mjs made in JavaScript, and returns the same shape it recorded.

local Data = require("../src/shared/Game/data")
local Race = require("../src/shared/Game/race")
local Golden = require("./Golden")
local NULL = require("./Null")

local function n(v)
	if v == NULL then
		return nil
	end
	return v
end
local function orNull(v)
	if v == nil then
		return NULL
	end
	return v
end

local UPS = {
	{ engine = 0, turbo = 0, tires = 0, weight = 0 },
	{ engine = 5, turbo = 5, tires = 5, weight = 5 },
	{ engine = 2, turbo = 0, tires = 4, weight = 1 },
}
local MOD_SETS = { {}, {}, { "flamepipes", "chrome", "nope", "twintips" }, {} }
for i, m in Data.MODS do
	table.insert(MOD_SETS[2], m.id)
	if (i - 1) % 3 == 0 then
		table.insert(MOD_SETS[4], m.id)
	end
end
local OWN_SETS = { {}, { "rescue" }, { "rescue", "gas" } }
local PAINT_CARS = { { color = "#c62828" }, { color = "#c62828", finish = "matte", stripe = "#fafafa" } }

local function ids(list)
	local out = {}
	for _, x in list do
		table.insert(out, x.id)
	end
	return out
end

local adapters = {}

-- Buildings
function adapters.upgradable(id)
	return Data.upgradable(Data.buildingDef(id))
end
function adapters.takesDriver(id)
	return Data.takesDriver(Data.buildingDef(id))
end
function adapters.buildingStats(id, l)
	local b = Data.buildingDef(id)
	return {
		payout = Data.upgradePayout(b, l),
		parts = Data.upgradePartsPayout(b, l),
		xp = Data.upgradeXp(b, l),
		seconds = Data.upgradeJobSeconds(b, l),
		fuel = Data.upgradeFuelCap(b, l),
		cost = Data.buildingUpgradeCost(b, l),
		name = Data.levelName(b, l),
	}
end
function adapters.buildingDef(id)
	local d = Data.buildingDef(id)
	return { parked = d.parked, name = d.name }
end
function adapters.buildingLevel(level)
	return Data.buildingLevel({ level = n(level) })
end
function adapters.jobLevel(level, jobLevel)
	return Data.jobLevel({ level = level, jobLevel = n(jobLevel) })
end
adapters.houseResidents = Data.houseResidents
adapters.levelLift = Data.levelLift

-- Cars
function adapters.restoreCost(id)
	return Data.restoreCost(Data.carDef(id))
end
function adapters.carSource(id)
	return Data.carSource(Data.carDef(id))
end
function adapters.upgradeCost(id, l)
	return Data.upgradeCost(Data.carDef(id), l)
end
function adapters.performance(id, ui, mi)
	return Data.performance(Data.carDef(id), UPS[ui + 1], MOD_SETS[mi + 1])
end
function adapters.fittedMods(mi, body)
	return Data.fittedMods(MOD_SETS[mi + 1], body)
end
function adapters.driverPayout(b, l, c)
	return Data.driverPayout(Data.buildingDef(b), l, Data.carDef(c))
end
function adapters.carDef(id)
	local c = Data.carDef(id)
	return { parked = c.parked, price = c.price, likes = #c.likes }
end
function adapters.ownedMods(owned, mods)
	return Data.ownedMods({ ownedMods = owned, mods = mods })
end
adapters.modXp = Data.modXp
function adapters.garagePower()
	local cars = {}
	for i = 1, 9 do
		table.insert(cars, { model = Data.CARS[i].id, upgrades = UPS[(i - 1) % 3 + 1], mods = MOD_SETS[(i - 1) % 4 + 1] })
	end
	return Data.garagePower(cars)
end

-- Progression
adapters.xpToNext = Data.xpToNext
adapters.plotPrice = Data.plotPrice
adapters.refillBucks = Data.refillBucks

-- Grand Prix and campaign
function adapters.gp(id, r, c)
	local s
	for _, x in Data.GP_SERIES do
		if x.id == id then
			s = x
		end
	end
	return { pi = Data.gpRivalPi(s, r, c), reward = Data.gpReward(s, r) }
end
function adapters.campaign(ci, i)
	local ch = Data.CAMPAIGN[ci + 1]
	return {
		pi = Data.campaignRivalPi(ch, i),
		first = Data.campaignReward(ch, i, true),
		again = Data.campaignReward(ch, i, false),
		shift = Data.campaignShift(ci, i),
		skills = Data.campaignRivalSkills(ci, i),
	}
end
adapters.campaignStars = Data.campaignStars

function adapters.skills(sk, me, them, t)
	sk = n(sk)
	return { boost = Data.skillBoost(sk, me, them), drag = Data.skillDrag(sk, them, t), live = Data.liveSkillBoost(sk, me, them, t) }
end

-- Calendar
function adapters.calendar(t)
	local e = Data.activeEvent(t)
	return {
		day = Data.dayKey(t),
		week = Data.weekKey(t),
		nextDay = Data.msToNextDay(t),
		nextWeek = Data.msToNextWeek(t),
		season = Data.seasonNumber(t),
		event = orNull(e and e.id),
		eventEnds = Data.eventEndsAt(Data.EVENTS[1], t),
	}
end
adapters.seasonOf = Data.seasonOf
adapters.seasonCars = Data.seasonCars

function adapters.drawTasks(period, key, level, oi)
	return Data.drawTasks(if period == "daily" then Data.DAILY_TASKS else Data.WEEKLY_TASKS, key, level, function(id)
		return table.find(OWN_SETS[oi + 1], id) ~= nil
	end)
end

-- Deals
function adapters.dealsFor(day)
	return ids(Data.dealsFor(day))
end
function adapters.dealOffer(id)
	local d = Data.dealDef(id)
	return { offer = Data.dealOffer(d), save = Data.dealSave(d) }
end

-- Paint and skins
function adapters.paintJobCost(ci, color, finish, stripe)
	return Data.paintJobCost(PAINT_CARS[ci + 1], { color = color, finish = finish, stripe = n(stripe) })
end
adapters.ownedSkins = Data.ownedSkins
function adapters.ownedModSkins(s)
	return Data.ownedModSkins({ level = s.level, claimedSets = s.claimedSets, modSkins = s.skins })
end
function adapters.seasonSkin(t)
	local a, b = Data.seasonSkin(t), Data.seasonModSkin(t)
	return { car = orNull(a and a.id), mod = orNull(b and b.id) }
end

-- Collection sets
local OWNED = {}
for i, c in Data.CARS do
	if (i - 1) % 2 == 0 then
		table.insert(OWNED, { model = c.id })
	end
end
function adapters.setOwned(id)
	for _, s in Data.CAR_SETS do
		if s.id == id then
			return Data.setOwned(s, OWNED)
		end
	end
	return nil
end
function adapters.readySets()
	local all = {}
	for _, c in Data.CARS do
		table.insert(all, { model = c.id })
	end
	return ids(Data.readySets({ cars = all, claimedSets = { "daily" } }))
end

adapters.visitorPrize = Data.visitorPrize
function adapters.services(l)
	return { tires = Data.servicePay(l, "tires"), gas = Data.servicePay(l, "gas"), can = Data.gasCanCost(l), flat = Data.flatFixCost(l) }
end

-- Race
adapters.dynoPull = Race.dynoPull
adapters.computeRaceFloor = Race.raceFloor
function adapters.shiftQuality(rpm, lo, hi)
	return Race.shiftQuality(rpm, n(lo), n(hi))
end
function adapters.scriptedRace(pi, react, shiftAt, fireGear, skill)
	fireGear, skill = n(fireGear), n(skill)
	local r = Race.freshRacer(false)
	local dt = 1 / 60
	local t = 0
	local calls = {}
	while r.finished == nil and t < 60 do
		t += dt
		if not r.launched and t >= (if react < 0 then Race.JUMP_START_DELAY else react) then
			table.insert(calls, Race.launchRacer(r, react))
		end
		if r.launched and r.gear < 3 and r.rpm >= shiftAt then
			Race.shiftRacer(r, Race.shiftQuality(r.rpm).q)
		end
		if fireGear ~= nil and r.gear >= fireGear then
			Race.fireBoost(r)
		end
		Race.stepRacer(r, pi, dt, t, Data.skillBoost(skill, r, { gear = 0, dist = 0 }))
	end
	return { finished = orNull(r.finished), speed = r.speed, streak = r.streak, boostUsed = r.boostUsed, calls = calls }
end

-- ---- Comparison ----

local function show(v): string
	if type(v) == "table" then
		if v == NULL then
			return "null"
		end
		local parts = {}
		for k, x in v do
			table.insert(parts, `{k}={show(x)}`)
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	if type(v) == "number" then
		return string.format("%.17g", v)
	end
	return tostring(v)
end

-- Exact match: same numbers to the last bit, same strings, same keys. An absent Luau field matches
-- a JavaScript null or false only where the web value is missing too.
local function same(a, b): boolean
	if a == b or (b == NULL and a == nil) then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" or a == NULL or b == NULL then
		return false
	end
	for k, v in a do
		if not same(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

return function(test)
	local failures, counts = {}, {}
	for _, c in Golden do
		local fn = adapters[c.fn]
		assert(fn, `no adapter for {c.fn}`)
		local ok, got = pcall(fn, table.unpack(c.args, 1, #c.args))
		counts[c.fn] = (counts[c.fn] or 0) + 1
		if not ok then
			table.insert(failures, `{c.fn}({show(c.args)}) errored: {got}`)
		elseif not same(got, c.out) then
			table.insert(failures, `{c.fn}({show(c.args)})\n      web:  {show(c.out)}\n      luau: {show(got)}`)
		end
	end
	test(`matches the web game on {#Golden} golden cases`, function()
		if #failures > 0 then
			local shown = {}
			for i = 1, math.min(15, #failures) do
				shown[i] = "    " .. failures[i]
			end
			error(`{#failures} mismatches:\n` .. table.concat(shown, "\n"), 0)
		end
	end)
end
