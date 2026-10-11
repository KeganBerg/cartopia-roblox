--!strict
-- Game rules over the catalog, ported from the web game's src/game/data.ts. The tables themselves
-- (buildings, cars, mods, goals...) are generated into Catalog.luau and re-exported here, so
-- `Data.CARS`, `Data.performance(...)` and so on read like the web version.
-- Lists are 1-based here; ids, levels and gears keep the web game's numbering.

local Catalog = require("./Catalog")
local Clock = require("./Clock")
local T = require("./Types")
local Util = require("./Util")

type BuildingDef = T.BuildingDef
type CarDef = T.CarDef
type ModDef = T.ModDef
type Upgrades = T.Upgrades

local round = Util.round
local DAY_MS = Util.DAY_MS

local Data = setmetatable({}, { __index = Catalog })

-- ---- Events ----

-- The month and day on the US East Coast, like "10-31" (EST is UTC-5, EDT UTC-4 from 2am on the
-- second Sunday in March to 2am on the first Sunday in November).
local function eastCoastDay(now: number): string
	local y = Util.civilFromDays(math.floor(now / DAY_MS))
	local function nthSunday(month: number, n: number): number
		local first = Util.daysFromCivil(y, month, 1)
		local dow = (first + 4) % 7 -- 0 = Sunday
		return first + (7 - dow) % 7 + (n - 1) * 7
	end
	local dstStart = nthSunday(3, 2) * DAY_MS + 7 * 3600000 -- 2am EST
	local dstEnd = nthSunday(11, 1) * DAY_MS + 6 * 3600000 -- 2am EDT
	local offset = if now >= dstStart and now < dstEnd then 4 else 5
	local _, m, d = Util.civilFromDays(math.floor((now - offset * 3600000) / DAY_MS))
	return string.format("%02d-%02d", m, d)
end
Data.eastCoastDay = eastCoastDay

function Data.activeEvent(now: number?): T.GameEvent?
	local day = eastCoastDay(now or Util.nowMs())
	return Util.find(Catalog.EVENTS, function(e)
		return day >= e.from and day < e.to
	end)
end

-- Midnight on the East Coast when the event ends, roughly (good enough for a countdown).
function Data.eventEndsAt(e: T.GameEvent, now: number?): number
	local year = Util.civilFromDays(math.floor((now or Util.nowMs()) / DAY_MS))
	local m, d = string.match(e.to, "^(%d+)-(%d+)$")
	return Util.utc(year, (tonumber(m) :: number) - 1, tonumber(d), 4)
end

-- ---- Land ----

function Data.plotPrice(bought: number): number
	return round((5000 * math.pow(1.45, bought)) / 500) * 500
end

-- ---- Buildings ----

-- A save can hold a building this build doesn't know yet. It gets a harmless stand-in: no jobs, no
-- fuel, can't be sold, drawn as a covered lot. The save keeps the real id.
local parkedDefs: { [string]: BuildingDef } = {}
local function parkedDef(id: string): BuildingDef
	local d = parkedDefs[id]
	if not d then
		d = { id = id, name = "Coming Soon", kind = "decor", w = 1, h = 1, price = 0, unlockLevel = 99, color = "#ffb300", roof = "#455a64", parked = true }
		parkedDefs[id] = d
	end
	return d :: BuildingDef
end

local buildingById: { [string]: BuildingDef } = {}
for _, b in Catalog.BUILDINGS do
	buildingById[b.id] = b
end

function Data.knownBuilding(id: string): boolean
	return buildingById[id] ~= nil
end

function Data.buildingDef(id: string): BuildingDef
	return buildingById[id] or parkedDef(id)
end

-- Building upgrades: businesses, parts makers, gas stations and houses go from level 1 to 10.
function Data.upgradable(d: BuildingDef): boolean
	if d.parked then
		return false
	end
	local hasJobs = d.jobSeconds ~= nil and d.jobSeconds ~= 0 and d.kind ~= "obstacle"
	local hasFuel = d.fuelCap ~= nil and d.fuelCap ~= 0
	return hasJobs or hasFuel or d.kind == "house"
end

-- A missing (or nonsense) level is level 1.
function Data.buildingLevel(b: { level: any? }): number
	local n = tonumber(b.level)
	if n == nil or n ~= n or n == 0 then
		n = 1
	end
	return Util.clamp(math.floor(n :: number), 1, Catalog.MAX_BUILDING_LEVEL)
end

-- The level a running job pays at: locked when it started (older saves: the current level).
function Data.jobLevel(b: { level: any?, jobLevel: number? }): number
	if b.jobLevel == nil then
		return Data.buildingLevel(b)
	end
	return Data.buildingLevel({ level = math.min(b.jobLevel, Data.buildingLevel(b)) })
end

-- +10% coins and parts and +5% XP per level, 8% shorter jobs (rounded to 5s).
function Data.upgradePayout(d: BuildingDef, level: number): number
	return round((d.payout or 0) * (1 + 0.1 * (level - 1)))
end
function Data.upgradePartsPayout(d: BuildingDef, level: number): number
	return round((d.partsPayout or 0) * (1 + 0.1 * (level - 1)))
end
function Data.upgradeXp(d: BuildingDef, level: number): number
	return round((d.xp or 0) * (1 + 0.05 * (level - 1)))
end
function Data.upgradeJobSeconds(d: BuildingDef, level: number): number
	if not d.jobSeconds or d.jobSeconds == 0 then
		return 0
	end
	return math.max(10, round((d.jobSeconds * math.pow(0.92, level - 1)) / 5) * 5)
end
-- Max fuel a building adds: a gas station's tank grows 2 a level; every house level above 1 adds 1.
function Data.upgradeFuelCap(d: BuildingDef, level: number): number
	if d.fuelCap and d.fuelCap ~= 0 then
		return d.fuelCap + 2 * (level - 1)
	end
	return if d.kind == "house" then level - 1 else 0
end

-- Cost to go from `level` to `level + 1`: 75% of the build price, 50% more each level, plus parts
-- from level 4 up. Houses start at $300 and grow 55% a level.
function Data.buildingUpgradeCost(d: BuildingDef, level: number): { coins: number, parts: number }
	local coins = if d.kind == "house"
		then round((300 * math.pow(1.55, level - 1)) / 50) * 50
		else math.max(100, round((d.price * 0.75 * math.pow(1.5, level - 1)) / 50) * 50)
	return { coins = coins, parts = if level >= 4 then (level - 2) * 2 else 0 }
end

-- Houses: a house at levels 1-3, apartments at 4-6 and a tower at 7-10.
function Data.homeStage(level: number): string
	return if level >= 7 then "tower" elseif level >= 4 then "apartments" else "house"
end
local HOME_NAMES = { house = "House", apartments = "Apartments", tower = "Sky Tower" }
local RESIDENTS = { 2, 3, 4, 6, 8, 10, 13, 16, 20, 24 }
function Data.houseResidents(level: number): number
	return RESIDENTS[Util.clamp(level, 1, Catalog.MAX_BUILDING_LEVEL)]
end
-- What a building is called at a level (only houses change name).
function Data.levelName(d: BuildingDef, level: number): string
	return if d.kind == "house" then (HOME_NAMES :: any)[Data.homeStage(level)] else d.name
end
function Data.buildingUpgradeXp(level: number): number
	return 10 + level * 5
end
-- Extra model height an upgraded building gains, on the same lot (in web units; see Units).
function Data.levelLift(level: number?): number
	return 0.26 * (Util.clamp(level or 1, 1, Catalog.MAX_BUILDING_LEVEL) - 1)
end

-- ---- Cars and race skills ----

function Data.isBike(body: string): boolean
	return Util.includes(Catalog.BIKES, body)
end

export type SkillRacer = { gear: number, dist: number }

-- Boost to the skill owner's own car right now.
function Data.skillBoost(sk: string?, me: SkillRacer, them: SkillRacer): number
	if sk == "launch" and me.gear == 0 then
		return 1.2
	end
	if sk == "nitro" and me.gear == 3 then
		return 1.15
	end
	if sk == "slipstream" and me.dist > 0 and me.dist < them.dist then
		return 1.08
	end
	if sk == "torque" and me.gear <= 1 then
		return 1.1
	end
	return 1
end
-- Slow-down the skill puts on the other car (t: seconds since the start).
function Data.skillDrag(sk: string?, them: SkillRacer, t: number): number
	if sk == "oil" and t < 2.5 then
		return 0.9
	end
	if sk == "freeze" and them.gear == 1 then
		return 0.9
	end
	return 1
end
-- In a live race the other car is simulated on its owner's client, so slow-downs boost our own
-- car by the same amount in the same window instead.
function Data.liveSkillBoost(sk: string?, me: SkillRacer, them: SkillRacer, t: number): number
	if sk == "oil" then
		return if t < 2.5 then 1.1 else 1
	end
	if sk == "freeze" then
		return if me.gear == 1 then 1.1 else 1
	end
	return Data.skillBoost(sk, me, them)
end
-- A shift the driver timed "Good" counts as perfect with Smooth Shifter.
function Data.smoothShift(sk: string?): boolean
	return sk == "smooth"
end

function Data.restoreCost(car: CarDef): number
	return math.max(200, round((car.price + (car.bucks or 0) * 1000) * 0.25 / 10) * 10)
end
function Data.rushBucks(msLeft: number): number
	return math.max(1, math.ceil(msLeft / 1800000))
end

-- Same idea as buildingDef: a car from a newer build drives as the starter car under a placeholder
-- name, can't be sold or scrapped, and keeps its real id.
local parkedCars: { [string]: CarDef } = {}
local function parkedCar(id: string): CarDef
	local c = parkedCars[id]
	if not c then
		local copy = table.clone(Catalog.CARS[1])
		copy.id = id
		copy.name = "Coming Soon"
		copy.price = 0
		copy.bucks = nil
		copy.skill = nil
		copy.likes = {}
		copy.parked = true
		parkedCars[id] = copy
		c = copy
	end
	return c :: CarDef
end

local carById: { [string]: CarDef } = {}
for _, c in Catalog.CARS do
	carById[c.id] = c
end
function Data.carDef(id: string): CarDef
	return carById[id] or parkedCar(id)
end

-- ---- Drivers ----
-- A driver adds 10% to the coins every job pays, or 25% at a business it loves.

function Data.isOpen(d: BuildingDef, now: number?): boolean
	return not d.nightOnly or Clock.isNight(now)
end
function Data.takesDriver(d: BuildingDef): boolean
	return not d.parked and d.jobSeconds ~= nil and d.jobSeconds ~= 0 and d.kind ~= "obstacle"
end
function Data.loves(car: CarDef, buildingId: string): boolean
	return Util.includes(car.likes, buildingId)
end
function Data.driverBonus(car: CarDef, buildingId: string): number
	return if Data.loves(car, buildingId) then Catalog.FAVORITE_BONUS else Catalog.DRIVER_BONUS
end
-- Coins a job pays with this driver (nil: no working driver).
function Data.driverPayout(d: BuildingDef, level: number, car: CarDef?): number
	return round(Data.upgradePayout(d, level) * (1 + (if car then Data.driverBonus(car, d.id) else 0)))
end

-- ---- Garage upgrades and mods ----

function Data.upgradeCost(car: CarDef, level: number): { coins: number, parts: number }
	return {
		coins = round((car.price + (car.bucks or 0) * 1000) * 0.15 * (level + 1) + 200),
		parts = 2 + level * 3,
	}
end

function Data.modFits(m: ModDef, body: string): boolean
	if m.only then
		return Util.includes(m.only, body)
	end
	return not Util.includes(m.notOn, body)
end

local modById: { [string]: ModDef } = {}
for _, m in Catalog.MODS do
	modById[m.id] = m
end
function Data.modDef(id: string): ModDef?
	return modById[id]
end
function Data.modStats(id: string): { power: number, grip: number, weight: number }
	local m = modById[id]
	return { power = if m then m.power else 0, grip = if m then m.grip else 0, weight = if m then m.weight else 0 }
end
function Data.modCost(id: string): { coins: number, parts: number, bucks: number }
	local m = modById[id]
	return { coins = if m then m.coins else 0, parts = if m then m.parts else 0, bucks = if m then m.bucks else 0 }
end
-- The fitted mod in each slot (the first known one wins if a save lists two). Given a body, parts
-- that don't fit it are skipped.
function Data.fittedMods(mods: { string }?, body: string?): { [string]: string }
	local out: { [string]: string } = {}
	local list: { string } = mods or {}
	for _, id in list do
		local m = modById[id]
		if m and not out[m.slot] and (not body or Data.modFits(m, body)) then
			out[m.slot] = id
		end
	end
	return out
end
-- Every mod bought for a car: `ownedMods` plus whatever is fitted. Known ids only, no repeats.
function Data.ownedMods(car: { mods: { string }?, ownedMods: { string }? }): { string }
	local out, seen = {}, {}
	local lists: { { string } } = { car.ownedMods or {}, car.mods or {} }
	for _, list in lists do
		for _, id in list do
			if not seen[id] then
				seen[id] = true
				if modById[id] then
					table.insert(out, id)
				end
			end
		end
	end
	return out
end
function Data.modXp(id: string): number
	local m = modById[id]
	return 10 + (if m then m.unlockLevel else 0) * 3
end

-- Performance index: what races are decided on (plus the driver's shifting).
function Data.performance(car: CarDef, up: Upgrades, mods: { string }?): number
	local power, grip, weight = 0, 0, 0
	for _, id in Data.fittedMods(mods, car.body) do
		local s = Data.modStats(id)
		power += s.power
		grip += s.grip
		weight += s.weight
	end
	power = car.power + up.engine * 4 + up.turbo * 3 + power
	grip = car.grip + up.tires * 4 + grip
	weight = math.max(5, car.weight - up.weight * 4 + weight)
	return round(power * 0.6 + grip * 0.3 + (100 - weight) * 0.1)
end

-- ---- Progression and fuel ----

-- XP needed to go from `level` to `level + 1`.
function Data.xpToNext(level: number): number
	return round(100 * math.pow(level, 2.15))
end
function Data.baseFuelCap(level: number): number
	return 15 + level * 2
end
-- Bucks to fill the tank to the cap in one go: at least 3, and 1 per 5 fuel it adds.
function Data.refillBucks(fuelToAdd: number): number
	return math.max(Catalog.REFILL_BUCKS, math.ceil(fuelToAdd / 5))
end

-- ---- Grand Prix ----

-- Rival PI for a round; each completed run of the series adds 8%.
function Data.gpRivalPi(s: T.GpSeries, round_: number, clears: number): number
	return round((s.basePi + round_ * s.step) * (1 + clears * 0.08))
end
function Data.gpReward(s: T.GpSeries, round_: number): number
	return s.prize + round_ * round(s.prize / 4)
end

-- ---- Campaign ----
-- Race indexes `i` are 0-based (0 to CAMPAIGN_RACES - 1), matching the saved race ids; chIndex is
-- 0-based too.

function Data.campaignRaceId(ch: T.CampaignChapter, i: number): string
	return `{ch.id}-{i}`
end
function Data.campaignRivalPi(ch: T.CampaignChapter, i: number): number
	return round(ch.pi[1] + ((ch.pi[2] - ch.pi[1]) * i) / (Catalog.CAMPAIGN_RACES - 1))
end
-- How cleanly a rival shifts, 0 (early, sloppy) to 1 (every shift perfect), across the whole campaign.
function Data.campaignShift(chIndex: number, i: number): number
	return math.min(1, (chIndex + i / (Catalog.CAMPAIGN_RACES - 1)) / (#Catalog.CAMPAIGN - 1))
end
-- Rivals use their car's skill from the third chapter on; bosses always do.
function Data.campaignRivalSkills(chIndex: number, i: number): boolean
	return chIndex >= 2 or i == Catalog.CAMPAIGN_RACES - 1
end
-- The first win of each race pays the most; replays pay about a quick race.
function Data.campaignReward(ch: T.CampaignChapter, i: number, first: boolean): number
	local full = 100 + Data.campaignRivalPi(ch, i) * 10
	return if first then full else round((full * 0.6) / 10) * 10
end
-- Stars for a win: one for winning, two for beating them by 3% of their time, three for 6%.
function Data.campaignStars(myTime: number, theirTime: number): number
	if not (myTime < theirTime) then
		return 0
	end
	local lead = if theirTime == math.huge then 1 else (theirTime - myTime) / theirTime
	return if lead >= 0.06 then 3 elseif lead >= 0.03 then 2 else 1
end
local function everyRace(done: { [string]: number }, ch: T.CampaignChapter, stars: number): boolean
	for i = 0, Catalog.CAMPAIGN_RACES - 1 do
		if (done[Data.campaignRaceId(ch, i)] or 0) < stars then
			return false
		end
	end
	return true
end
function Data.campaignCleared(done: { [string]: number }, ch: T.CampaignChapter): boolean
	return everyRace(done, ch, 1)
end
function Data.campaignPerfect(done: { [string]: number }, ch: T.CampaignChapter): boolean
	return everyRace(done, ch, 3)
end

-- ---- Collection book ----

type OwnedCar = { model: string }

function Data.setOwned(set: T.CarSet, cars: { OwnedCar }): number
	local n = 0
	for _, m in set.cars do
		if Util.find(cars, function(c)
			return c.model == m
		end) then
			n += 1
		end
	end
	return n
end
function Data.setComplete(set: T.CarSet, cars: { OwnedCar }): boolean
	return Data.setOwned(set, cars) == #set.cars
end
-- Sets the player owns every car of but hasn't claimed yet.
function Data.readySets(s: { cars: { OwnedCar }, claimedSets: { string }? }): { T.CarSet }
	return Util.filter(Catalog.CAR_SETS, function(set)
		return not Util.includes(s.claimedSets, set.id) and Data.setComplete(set, s.cars)
	end)
end
-- Where to get a car: the Showroom (with its level or bucks price) or Rusty's searches.
function Data.carSource(car: CarDef): { icon: string, text: string }
	if car.season then
		return { icon = "🏁", text = `Season {car.season} prize` }
	end
	if car.rescueOnly then
		local spot: T.RescueSpot? = nil
		for _, sp in Catalog.RESCUE_SPOTS do
			local has = Util.find(sp.cars, function(c)
				return c.model == car.id
			end)
			if has and (spot == nil or sp.unlockLevel < (spot :: T.RescueSpot).unlockLevel) then
				spot = sp
			end
		end
		return { icon = "🔧", text = if spot then `Rusty's · {spot.name}` else "Rusty's" }
	end
	if car.bucks and car.bucks ~= 0 then
		return { icon = "🚘", text = `Showroom · 💎{car.bucks}` }
	end
	return { icon = "🚘", text = `Showroom · Lv {car.unlockLevel}` }
end

-- ---- Daily and weekly tasks ----

local function roundTo(n: number, to: number): number
	return math.max(to, round(n / to) * to)
end
-- How many of a task to do at a player level, by pool and task id (`n` in the web game).
local TASK_COUNTS: { [string]: { [string]: (number) -> number } } = {
	daily = {
		jobs = function(l)
			return math.min(8 + l * 2, 40)
		end,
		coins = function(l)
			return roundTo(1500 + l * 700, 500)
		end,
		races = function()
			return 3
		end,
		wins = function()
			return 2
		end,
		campaign = function()
			return 1
		end,
		search = function()
			return 1
		end,
		upgrade = function()
			return 1
		end,
		build = function()
			return 1
		end,
		service = function()
			return 2
		end,
		paint = function()
			return 1
		end,
	},
	weekly = {
		jobs = function(l)
			return math.min(60 + l * 10, 250)
		end,
		coins = function(l)
			return roundTo(12000 + l * 5000, 1000)
		end,
		wins = function()
			return 15
		end,
		campaign = function()
			return 5
		end,
		search = function()
			return 5
		end,
		upgrade = function()
			return 8
		end,
		build = function()
			return 5
		end,
		gp = function()
			return 1
		end,
		mods = function()
			return 2
		end,
	},
}
Data.TASK_COUNTS = TASK_COUNTS

function Data.taskCount(period: string, id: string, level: number): number
	return TASK_COUNTS[period][id](level)
end

function Data.payAt(p: { coins: number, coinsPerLevel: number, xp: number, xpPerLevel: number }, level: number): { coins: number, xp: number }
	return { coins = p.coins + p.coinsPerLevel * level, xp = p.xp + p.xpPerLevel * level }
end

-- UTC calendar keys: the day like 2026-10-11 and the ISO week like 2026-W41.
function Data.dayKey(t: number?): string
	local y, m, d = Util.civilFromDays(math.floor((t or Util.nowMs()) / DAY_MS))
	return string.format("%04d-%02d-%02d", y, m, d)
end
function Data.weekKey(t: number?): string
	local now = t or Util.nowMs()
	local days = math.floor(now / DAY_MS)
	local day = (Util.utcDay(now) + 6) % 7 -- Monday 0
	local thuY = Util.civilFromDays(days - day + 3)
	local thu = (days - day + 3) * DAY_MS
	local week = math.ceil(((thu - Util.utc(thuY, 0, 1)) / DAY_MS + 1) / 7)
	return string.format("%d-W%02d", thuY, week)
end
-- Milliseconds until the next UTC midnight, and until the next Monday 00:00 UTC.
function Data.msToNextDay(t: number?): number
	return DAY_MS - ((t or Util.nowMs()) % DAY_MS)
end
function Data.msToNextWeek(t: number?): number
	local now = t or Util.nowMs()
	return Data.msToNextDay(now) + (7 - ((Util.utcDay(now) + 6) % 7) - 1) * DAY_MS
end

-- Picks a period's tasks: a fixed shuffle per key, so every server draws the same three.
-- Same hash and shuffle as the web game, so a player sees the same tasks on both.
local function imul(a: number, b: number): number
	local ah, al = bit32.rshift(a, 16), bit32.band(a, 0xffff)
	local bh, bl = bit32.rshift(b, 16), bit32.band(b, 0xffff)
	return bit32.band(al * bl + bit32.lshift(bit32.band(ah * bl + al * bh, 0xffff), 16), 0xffffffff)
end
Data.imul = imul

function Data.drawTasks(period: string, key: string, level: number, owned: (string) -> boolean): { { id: string, n: number } }
	local pool: { T.TaskDef } = if period == "daily" then Catalog.DAILY_TASKS else Catalog.WEEKLY_TASKS
	local h = 2166136261
	for i = 1, #key do
		h = imul(bit32.bxor(h, string.byte(key, i)), 16777619)
	end
	local function rand(): number
		h = bit32.bxor(imul(bit32.bxor(h, bit32.rshift(h, 15)), 2246822507), imul(bit32.bxor(h, bit32.rshift(h, 13)), 3266489909))
		h = bit32.bxor(h, bit32.rshift(h, 16))
		return h / 4294967296
	end
	local ok = Util.filter(pool, function(t)
		return level >= (t.level or 1) and (not t.needs or owned(t.needs))
	end)
	-- Same Fisher-Yates as the web game, on 0-based positions.
	for i = #ok - 1, 1, -1 do
		local j = math.floor(rand() * (i + 1))
		ok[i + 1], ok[j + 1] = ok[j + 1], ok[i + 1]
	end
	local out = {}
	for i = 1, math.min(Catalog.TASKS_PER_PERIOD, #ok) do
		table.insert(out, { id = ok[i].id, n = Data.taskCount(period, ok[i].id, level) })
	end
	return out
end

-- ---- Season track ----

local SEASON_NAMES: { { name: string, icon: string, car: string? } } = {
	{ name = "Midnight Run", icon = "🌙", car = "nightfall" },
}
function Data.seasonNumber(t: number?): number
	return math.max(1, math.floor(((t or Util.nowMs()) - Catalog.SEASON_START) / (Catalog.SEASON_DAYS * DAY_MS)) + 1)
end
function Data.seasonOf(n: number): { n: number, name: string, icon: string, car: string? }
	local d = SEASON_NAMES[n]
	if d then
		return { n = n, name = d.name, icon = d.icon, car = d.car }
	end
	return { n = n, name = `Season {n}`, icon = "🏁" }
end
function Data.seasonEndsAt(n: number): number
	return Catalog.SEASON_START + n * Catalog.SEASON_DAYS * DAY_MS
end
-- Season number (as a string, like the web game's JSON) to the car its last tier gives.
function Data.seasonCars(): { [string]: string }
	local out = {}
	for i, d in SEASON_NAMES do
		if d.car then
			out[tostring(i)] = d.car
		end
	end
	return out
end

-- ---- Roadside services ----

function Data.servicePay(level: number, kind: string): number
	return if kind == "tires" then 60 + level * 15 else 40 + level * 10
end
function Data.gasCanCost(level: number): number
	return 30 + level * 15
end
function Data.flatFixCost(level: number): number
	return 50 + level * 25
end

-- ---- Paint ----

function Data.finishDef(id: string?): { id: string, name: string, coins: number, unlockLevel: number, blurb: string }
	return Util.find(Catalog.FINISHES, function(f)
		return f.id == id
	end) or Catalog.FINISHES[1]
end

-- What a paint job costs on a car: each part that changes is charged once. A neon or gold colour
-- costs a buck instead of coins; taking stripes off is free. A missing stripe is nil (or false).
function Data.paintJobCost(car: { color: string, finish: string?, stripe: (string | false)? }, job: { color: string, finish: string, stripe: (string | false)? }): { coins: number, bucks: number }
	local coins, bucks = 0, 0
	if job.color ~= car.color then
		local p = Util.find(Catalog.PAINTS, function(x)
			return x.color == job.color
		end)
		if p and p.bucks and p.bucks ~= 0 then
			bucks += p.bucks
		else
			coins += Catalog.PAINT_COST
		end
	end
	if job.finish ~= (car.finish or "gloss") then
		coins += Data.finishDef(job.finish).coins
	end
	local was = car.stripe or nil
	local now = job.stripe or nil
	if now ~= was and now then
		coins += Catalog.STRIPE_COST
	end
	return { coins = coins, bucks = bucks }
end

-- ---- Skins ----

function Data.skinDef(id: string?): T.SkinDef?
	if not id then
		return nil
	end
	return Util.find(Catalog.SKINS, function(s)
		return s.id == id
	end)
end
-- The shader number for a car's skin, 0 for none (or one this version doesn't know).
function Data.skinNumber(id: string?): number
	local d = Data.skinDef(id)
	return if d then d.n else 0
end
-- Every skin the player can put on a car right now.
function Data.ownedSkins(s: { level: number, claimedSets: { string }?, skins: { string }? }, pool: { T.SkinDef }?): { string }
	local out = {}
	for _, d in pool or Catalog.SKINS do
		local u = d.unlock
		local have = Util.includes(s.skins, d.id)
			or (u.level ~= nil and s.level >= u.level)
			or (u.set ~= nil and Util.includes(s.claimedSets, u.set))
		if have then
			table.insert(out, d.id)
		end
	end
	return out
end
-- Season track tiers (1-based) that give a skin on top of their usual prize.
function Data.seasonSkin(tier: number): T.SkinDef?
	return Util.find(Catalog.SKINS, function(d)
		return d.unlock.season == tier
	end)
end

function Data.modSkinDef(id: string?): T.SkinDef?
	if not id then
		return nil
	end
	return Util.find(Catalog.MOD_SKINS, function(s)
		return s.id == id
	end)
end
function Data.modSkinNumber(id: string?): number
	local d = Data.modSkinDef(id)
	return if d then d.n else 0
end
function Data.ownedModSkins(s: { level: number, claimedSets: { string }?, modSkins: { string }? }): { string }
	return Data.ownedSkins({ level = s.level, claimedSets = s.claimedSets, skins = s.modSkins }, Catalog.MOD_SKINS)
end
function Data.seasonModSkin(tier: number): T.SkinDef?
	return Util.find(Catalog.MOD_SKINS, function(d)
		return d.unlock.season == tier
	end)
end

-- Garage power: the combined PI of a player's five best cars.
function Data.garagePower(cars: { { model: string, upgrades: Upgrades, mods: { string }? } }): number
	local pis = {}
	for _, c in cars do
		table.insert(pis, Data.performance(Data.carDef(c.model), c.upgrades, c.mods))
	end
	table.sort(pis, function(a, b)
		return a > b
	end)
	local sum = 0
	for i = 1, math.min(Catalog.POWER_CARS, #pis) do
		sum += pis[i]
	end
	return sum
end

-- ---- Daily deals ----
-- Three discounted items a day, the same for everyone. Each slot rotates through its own list by
-- UTC day number: list[(day * step + slot) % length].

function Data.dealDef(id: string): T.DealDef?
	return Util.find(Catalog.DEALS, function(d)
		return d.id == id
	end)
end
-- Days since the epoch for a "YYYY-MM-DD" key.
function Data.dayNumber(day: string): number
	local y, m, d = string.match(day, "^(%d+)-(%d+)-(%d+)$")
	return Util.daysFromCivil(tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number)
end
function Data.dealsFor(day: string): { T.DealDef }
	local n = Data.dayNumber(day)
	local out = {}
	for i, s in Catalog.DEAL_SLOTS do
		local len = #s.deals
		table.insert(out, s.deals[(n * s.step + (i - 1)) % len + 1])
	end
	return out
end

local function off10(n: number, off: number): number
	return round((n * (1 - off)) / 10) * 10
end

export type DealOffer = {
	name: string,
	icon: string,
	unlockLevel: number,
	was: { coins: number, bucks: number },
	now: { coins: number, bucks: number },
	parts: number,
}
-- What a deal sells and for how much. `parts` is the parts price of a mod (never discounted).
function Data.dealOffer(d: T.DealDef): DealOffer
	if d.kind == "parts" then
		local n = d.n or 0
		return { name = `{n} Parts`, icon = "⚙", unlockLevel = 1, was = { coins = n * 50, bucks = 0 }, now = { coins = off10(n * 50, d.off), bucks = 0 }, parts = 0 }
	elseif d.kind == "fuel" then
		local R = Catalog.REFILL_BUCKS
		return { name = "Full tank", icon = "⛽", unlockLevel = 1, was = { coins = 0, bucks = R }, now = { coins = 0, bucks = math.max(1, round(R * (1 - d.off))) }, parts = 0 }
	elseif d.kind == "decor" then
		local b = Data.buildingDef(d.item or "")
		local bucks = b.bucks or 0
		return {
			name = b.name,
			icon = "🌳",
			unlockLevel = b.unlockLevel,
			was = { coins = b.price, bucks = bucks },
			now = { coins = off10(b.price, d.off), bucks = if bucks ~= 0 then math.max(1, round(bucks * (1 - d.off))) else 0 },
			parts = 0,
		}
	elseif d.kind == "mod" then
		local m = Data.modDef(d.item or "")
		local coins = if m then m.coins else 0
		return {
			name = if m then m.name else "Mod",
			icon = "🪽",
			unlockLevel = if m then m.unlockLevel else 1,
			was = { coins = coins, bucks = 0 },
			now = { coins = off10(coins, d.off), bucks = 0 },
			parts = if m then m.parts else 0,
		}
	end
	-- paint
	local f = Data.finishDef(d.item)
	return { name = `{f.name} paint`, icon = "🎨", unlockLevel = f.unlockLevel, was = { coins = f.coins, bucks = 0 }, now = { coins = off10(f.coins, d.off), bucks = 0 }, parts = 0 }
end
-- How much town worth a deal adds beyond what was paid. Fuel and paint aren't part of town worth.
function Data.dealSave(d: T.DealDef): number
	if d.kind == "fuel" or d.kind == "paint" then
		return 0
	end
	local o = Data.dealOffer(d)
	return o.was.coins - o.now.coins
end

-- ---- Town visitors ----

function Data.visitorPrize(kind: string, level: number, roll: number?): { coins: number, xp: number, parts: number, bucks: number }
	local p = (Catalog.VISITORS :: any)[kind].pay
	local r = roll or math.random()
	return {
		coins = round(p.coins + p.coinsPerLevel * level),
		xp = round(p.xp + p.xpPerLevel * level),
		parts = p.parts,
		bucks = if r < p.bucksChance then 1 else 0,
	}
end

return Data
