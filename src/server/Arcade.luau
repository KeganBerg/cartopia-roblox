--!strict
-- The arcade, on the server: Getaway Chase, Parking Pro, Pit Stop, Car Wash Frenzy, Delivery Dash
-- and Stunt Ramp (the web game's ui/Arcade.tsx, ArcadeMore.tsx, ArcadeBoards.tsx, lib/arcadeBoard.ts
-- and supabase/migrations/0086_arcade_boards.sql, 0087_arcade_prizes.sql).
--
-- A run is started here (the fuel or one of the day's free plays is spent, as ArcadeBits payFuel
-- does), played on the client, and its result sent back. The result must be possible in the time
-- the run took (0086 arcade_ok, and a like check for Parking Pro, which has no board on the web).
-- The pay is worked out here from the converted rules (game/arcade.ts chaseReward, parkReward,
-- parkStars; game/arcadeMore.ts starReward with pitStars, washStars, dashStars, stuntStars) and
-- paid through the web store's own finishArcade, so a client can't name its own pay.
--
-- Each board game posts to a weekly board (server/Boards, one per game; Pit Stop keeps the lowest
-- time, the rest the highest number), and the top 3 of each finished week win a Gold crate
-- (0087): claiming one adds 'arcade:<week>:<game>' to the town's freeCrates, which the Crate Depot
-- opens like a cup prize. Bests, lot stars, the day's free plays and claimed prizes are kept per
-- player (on the web the first three are in the browser's localStorage).

local Arcade = {}
Arcade.__index = Arcade

local GAMES: { [string]: boolean } = { chase = true, park = true, pit = true, wash = true, delivery = true, stunt = true }
-- The games with weekly boards (lib/arcadeBoard.ts BOARD_GAMES): Parking Pro's lots are a ladder.
Arcade.BOARD_GAMES = { "chase", "stunt", "delivery", "wash", "pit" }
local STAR_GAMES = { "pit", "wash", "delivery", "stunt" }

-- 0086: a run's result must come within 10 minutes of its start, and starts 3 seconds apart.
local RUN_TTL = 10 * 60
local START_GAP = 3
-- Board rows shown (arcade_board: the top 20).
local TOP = 20
-- Boards keep the lowest number first, so the higher-is-better games go on as HIGH - value.
local HIGH = 1000000
-- Parking Pro has no server check on the web. Its run can't beat driving straight at the car's top
-- speed (scene/ParkScene.tsx MAX_FWD) from the start to the spot, then holding still (0.6 s).
local PARK_TOP_SPEED = 3.4
local PARK_HOLD = 0.6
local DAY_MS = 86400000

export type Record = {
	chase: number,
	park: { number },
	stars: { [string]: { stars: number, best: number } },
	free: { day: string, used: { [string]: number } },
	claimed: { [string]: boolean },
}

-- Where per-player records are kept: get returns the saved record (or nil), set writes it.
export type Store = {
	get: (userId: number) -> any,
	set: (userId: number, record: Record) -> boolean,
}

export type Mods = {
	store: any, -- Shared.Game.store
	data: any, -- Shared.Game.data
	arcade: any, -- Shared.Game.arcade
	arcadeMore: any, -- Shared.Game.arcadeMore
	trial: any, -- Shared.Game.trial (trialWeek: the Monday a week starts, as SQL this_week())
	boards: { [string]: any }, -- one server/Boards per board game
	records: Store?, -- nil keeps records in memory
	clock: () -> number, -- seconds, for how long a run took
	now: () -> number, -- milliseconds since the epoch, for weeks and days
	random: () -> number, -- a seed for each run
}

type Run = { game: string, lot: number?, at: number, seed: number }

export type Arcade = typeof(setmetatable(
	{} :: { towns: any, mods: Mods, runs: { [number]: Run }, lastStart: { [number]: { [string]: number } }, records: { [number]: Record }, mem: { [number]: Record } },
	Arcade
))

function Arcade.new(towns: any, mods: Mods): Arcade
	return setmetatable({ towns = towns, mods = mods, runs = {}, lastStart = {}, records = {}, mem = {} }, Arcade)
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) ~= math.huge
end

-- 0086 arcade_ok: is result v possible from a run that lasted secs seconds? (Caps are generous on
-- purpose: they stop made-up numbers, not good players.)
function Arcade.ok(game: string, v: any, secs: number): boolean
	if not finite(v) or v < 0 then
		return false
	end
	if game == "chase" then
		return v <= 400 * secs and v <= 250000
	elseif game == "pit" then
		return v >= 4 and v <= secs and v <= 120
	elseif game == "wash" then
		return v <= secs and v <= 60
	elseif game == "delivery" then
		return v <= secs / 3 and v <= 60
	elseif game == "stunt" then
		return v <= 6000 and v <= 1500 * math.floor(secs / 3)
	end
	return false
end

-- Parking Pro's like check: the time is no longer than the run and no shorter than a straight
-- drive to the spot; bumps are a whole number up to the most a run allows.
function Arcade.parkOk(arcade: any, lot: number, time: any, bumps: any, secs: number): boolean
	if not finite(time) or time < 0 or time > secs then
		return false
	end
	if not finite(bumps) or bumps < 0 or bumps % 1 ~= 0 or bumps > arcade.PARK_MAX_BUMPS then
		return false
	end
	local def = arcade.PARK_LOTS[lot]
	local d = math.sqrt((def.start.x - def.spot.x) ^ 2 + (def.start.z - def.spot.z) ^ 2)
	local reach = math.max(def.spot.w, def.spot.l) / 2 + arcade.PARK_LEN / 2
	return time >= math.max(0, d - reach) / PARK_TOP_SPEED + PARK_HOLD
end

-- Days since 1970-01-01 for a civil date (Howard Hinnant's days_from_civil).
local function daysFrom(y: number, m: number, d: number): number
	y -= if m <= 2 then 1 else 0
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local doy = (153 * (m + (if m > 2 then -3 else 9)) + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return era * 146097 + doe - 719468
end

-- A week key ("2026-10-12", its Monday) as milliseconds since the epoch, or nil if it isn't one.
function Arcade.weekMs(week: string): number?
	local y, m, d = string.match(week, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
	if not y then
		return nil
	end
	local days = daysFrom(tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number)
	-- 1970-01-01 was a Thursday: a Monday is 4 days on from a multiple of 7.
	if (days - 4) % 7 ~= 0 then
		return nil
	end
	return days * DAY_MS
end

-- The UTC day, for the free plays (the web uses the device's own day).
local function dayOf(ms: number): string
	return tostring(ms // DAY_MS)
end

local function fresh(): Record
	return { chase = 0, park = {}, stars = {}, free = { day = "", used = {} }, claimed = {} }
end

-- The player's record, loaded once a session.
function Arcade._record(self: Arcade, userId: number): Record
	local r = self.records[userId]
	if r then
		return r
	end
	local saved: any = nil
	if self.mods.records then
		saved = (self.mods.records :: Store).get(userId)
	else
		saved = self.mem[userId]
	end
	local out = fresh()
	if type(saved) == "table" then
		out.chase = if finite(saved.chase) then saved.chase else 0
		for i, v in (if type(saved.park) == "table" then saved.park else {}) do
			if type(i) == "number" and finite(v) then
				out.park[i] = v
			end
		end
		for _, id in STAR_GAMES do
			local v = type(saved.stars) == "table" and saved.stars[id]
			if type(v) == "table" and finite(v.stars) and finite(v.best) then
				out.stars[id] = { stars = math.clamp(v.stars, 0, 3), best = v.best }
			end
		end
		if type(saved.free) == "table" and type(saved.free.day) == "string" and type(saved.free.used) == "table" then
			out.free = { day = saved.free.day, used = table.clone(saved.free.used) }
		end
		if type(saved.claimed) == "table" then
			out.claimed = table.clone(saved.claimed)
		end
	end
	self.records[userId] = out
	return out
end

function Arcade._write(self: Arcade, userId: number): boolean
	local r = self:_record(userId)
	if self.mods.records then
		return (self.mods.records :: Store).set(userId, r)
	end
	self.mem[userId] = table.clone(r)
	return true
end

-- Free plays left today for a game (game/arcade.ts freeLeft).
function Arcade.freeLeft(self: Arcade, userId: number, game: string): number
	local r = self:_record(userId)
	if r.free.day ~= dayOf(self.mods.now()) then
		return self.mods.arcade.FREE_PLAYS
	end
	return math.max(0, self.mods.arcade.FREE_PLAYS - (r.free.used[game] or 0))
end

-- The hub's numbers: bests, lot stars, star games' bests, free plays left and the fuel a run costs.
function Arcade.state(self: Arcade, userId: number): any
	local r = self:_record(userId)
	local free = {}
	for id in GAMES do
		free[id] = self:freeLeft(userId, id)
	end
	local stars = {}
	for _, id in STAR_GAMES do
		stars[id] = r.stars[id] or { stars = 0, best = 0 }
	end
	return { chase = r.chase, park = table.clone(r.park), stars = stars, free = free, fuel = self.mods.arcade.ARCADE_FUEL }
end

-- Starts a run: checks the game (and for Parking Pro, that the lot is open), spends a free play or
-- the fuel, and hands back the seed. lot is 1-based. Returns nil and why when it can't start (the
-- town's "you need" note says what fuel is short).
function Arcade.start(self: Arcade, userId: number, game: any, lot: any): (any?, string?)
	if type(game) ~= "string" or not GAMES[game] then
		return nil, "no such game"
	end
	local arcade = self.mods.arcade
	local r = self:_record(userId)
	local lotN: number? = nil
	if game == "park" then
		if not finite(lot) or lot % 1 ~= 0 or lot < 1 or lot > #arcade.PARK_LOTS then
			return nil, "no such lot"
		end
		-- lotOpen takes the 0-based index (converted from the web).
		if not arcade.lotOpen(r.park, lot - 1) then
			return nil, "lot locked"
		end
		lotN = lot
	end
	local t = self.mods.clock()
	local last = self.lastStart[userId] or {}
	self.lastStart[userId] = last
	if last[game] and t - last[game] < START_GAP then
		return nil, "slow down"
	end
	local hasCar = self.towns:_with(userId, function(s: any): boolean
		return #(s.cars or {}) > 0
	end)
	if not hasCar then
		return nil, "no car"
	end
	-- Pay for the run (ArcadeBits payFuel): a free play, else the fuel.
	local free = self:freeLeft(userId, game) > 0
	if free then
		local day = dayOf(self.mods.now())
		if r.free.day ~= day then
			r.free = { day = day, used = {} }
		end
		r.free.used[game] = (r.free.used[game] or 0) + 1
		self:_write(userId)
	else
		local paid = self.towns:_with(userId, function(s: any): boolean
			s.tick(self.towns.now())
			if self.mods.store.spendFuel(arcade.ARCADE_FUEL) then
				return true
			end
			local g = self.mods.store.useGame.getState()
			g.showNeed("fuel", arcade.ARCADE_FUEL - g.fuel, if game == "park" then "a parking run" else "an arcade run")
			return false
		end)
		if not paid then
			return nil, "need fuel"
		end
	end
	last[game] = t
	local seed = math.floor(self.mods.random() * 1e9)
	self.runs[userId] = { game = game, lot = lotN, at = t, seed = seed }
	return { seed = seed, game = game, lot = lotN, free = free, freeLeft = self:freeLeft(userId, game) }, nil
end

-- Stars for a star game's result (as ArcadeMore.tsx: Pit Stop by its time, the rest by their count).
function Arcade._stars(self: Arcade, game: string, v: number): number
	local more = self.mods.arcadeMore
	if game == "pit" then
		return more.pitStars(v)
	elseif game == "wash" then
		return more.washStars(v)
	elseif game == "delivery" then
		return more.dashStars(v)
	end
	return more.stuntStars(v)
end

-- Board values: what the board keeps (lowest first) for a result, and back.
local function toBoard(game: string, v: number): number
	return if game == "pit" then v else (HIGH - v) / 1000
end
local function fromBoard(game: string, t: number): number
	return if game == "pit" then t else math.round(HIGH - t * 1000)
end

-- A game's board this week as the web's arcade_board: { week, game, total, top = { owner, town,
-- best, place }, me = { best, place }? }.
function Arcade.board(self: Arcade, userId: number, game: any): (any?, string?)
	if type(game) ~= "string" or not self.mods.boards[game] then
		return nil, "no such board"
	end
	local week = self.mods.trial.trialWeek(self.mods.now())
	local b = self.mods.boards[game]:board(week, userId, TOP)
	local top = {}
	for i, row in b.top do
		top[i] = { owner = row.owner, town = row.town, best = fromBoard(game, row.t), place = row.place }
	end
	local me = if b.me then { best = fromBoard(game, b.me.t), place = b.me.place } else nil
	return { week = week, game = game, total = b.total, top = top, me = me }, nil
end

-- Finishes the run in progress: checks it, pays it and records it. result: Pit Stop's seconds,
-- Chase's score, Wash, Delivery and Stunt's count or score, Parking Pro's seconds (with
-- detail.bumps and detail.parked). Returns what the result card shows: { coins, xp, xpGain,
-- stars?, record, best, board?, place? }.
function Arcade.submit(self: Arcade, userId: number, game: any, result: any, detail: any): (any?, string?)
	local run = self.runs[userId]
	if not run or run.game ~= game then
		return nil, "no run to finish"
	end
	self.runs[userId] = nil
	local secs = self.mods.clock() - run.at
	if secs > RUN_TTL then
		return nil, "no run to finish"
	end
	local d = if type(detail) == "table" then detail else {}
	if d.quit == true then
		return { coins = 0, xp = 0, xpGain = 0, quit = true }, nil
	end
	local arcade, more = self.mods.arcade, self.mods.arcadeMore
	local r = self:_record(userId)
	local level = self.towns:_with(userId, function(s: any): number
		return s.level
	end)
	local out: any = { record = false }
	local pay = { coins = 0, xp = 0 }
	local paid = false
	if game == "park" then
		local lot = run.lot :: number
		local bumps = d.bumps
		if not Arcade.parkOk(arcade, lot, result, bumps, secs) then
			return nil, "bad result"
		end
		local parked = d.parked == true and bumps < arcade.PARK_MAX_BUMPS
		local stars = if parked then arcade.parkStars(result, bumps, arcade.PARK_LOTS[lot].par) else 0
		pay = arcade.parkReward(lot - 1, stars, level)
		paid = stars > 0
		if stars > (r.park[lot] or 0) then
			-- Lots before it keep their stars (or none, as a sparse list on the web).
			for i = 1, lot - 1 do
				r.park[i] = r.park[i] or 0
			end
			r.park[lot] = stars
			out.record = true
		end
		out.stars = stars
		out.parked = parked
		out.time = result
		out.bumps = bumps
		out.lot = lot
	else
		if not Arcade.ok(game, result, secs) then
			return nil, "bad result"
		end
		if game == "chase" then
			local score = math.floor(result)
			pay = arcade.chaseReward(score, level)
			paid = true
			out.record = score > r.chase
			if out.record then
				r.chase = score
			end
		else
			local stars = self:_stars(game, result)
			pay = more.starReward(stars, level)
			paid = stars > 0
			-- recordStars: a better result needs at least a star.
			local old = r.stars[game] or { stars = 0, best = 0 }
			local better = stars > 0 and (old.best == 0 or (if more.lowerIsBetter(game) then result < old.best else result > old.best))
			r.stars[game] = { stars = math.max(old.stars, stars), best = if better then result else old.best }
			out.record = better
			out.stars = stars
		end
	end
	self:_write(userId)
	if paid then
		self.towns:_with(userId, function(s: any)
			s.tick(self.towns.now())
			s.finishArcade(pay.coins, pay.xp)
		end)
	end
	out.coins = pay.coins
	out.xp = pay.xp
	out.xpGain = self.mods.data.xpGain(level, pay.xp)
	out.result = result
	-- The weekly board (Chase always posts; the star games when there's a result, as the web).
	local board = self.mods.boards[game]
	if board and (game == "chase" or result > 0) then
		local week = self.mods.trial.trialWeek(self.mods.now())
		local town = self.towns:_with(userId, function(s: any): string
			return s.townName
		end)
		board:submit(week, userId, toBoard(game, result), { town = town })
		local b = self:board(userId, game)
		out.board = b
		out.place = if b and b.me then b.me.place else nil
	end
	return out, nil
end

-- 0087 arcade_prizes: the player's top-3 finishes on the last 4 finished weeks, newest first,
-- each { week, game, place, claimed }. A week is finished 10 minutes after the next Monday.
function Arcade.prizes(self: Arcade, userId: number): { any }
	local r = self:_record(userId)
	local now = self.mods.now()
	local thisWeek = Arcade.weekMs(self.mods.trial.trialWeek(now)) :: number
	local out = {}
	for _, game in Arcade.BOARD_GAMES do
		local board = self.mods.boards[game]
		for week, t in board:weeks(userId) do
			local ms = Arcade.weekMs(week)
			if ms and ms >= thisWeek - 28 * DAY_MS and now >= ms + 7 * DAY_MS + 10 * 60000 then
				local place = board:place(week, t)
				if place <= 3 then
					table.insert(out, { week = week, game = game, place = place, claimed = r.claimed[`arcade:{week}:{game}`] == true })
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return if a.week == b.week then a.game < b.game else a.week > b.week
	end)
	return out
end

-- Claims a Gold crate won on a finished week (0087 arcade_prize_ok): marks it claimed, then puts
-- its source in the town's freeCrates for the Crate Depot to open. Returns { source }.
function Arcade.claim(self: Arcade, userId: number, week: any, game: any): (any?, string?)
	if type(week) ~= "string" or type(game) ~= "string" then
		return nil, "no such prize"
	end
	local prize = nil
	for _, p in self:prizes(userId) do
		if p.week == week and p.game == game then
			prize = p
		end
	end
	if not prize then
		return nil, "no such prize"
	end
	if prize.claimed then
		return nil, "already claimed"
	end
	local source = `arcade:{week}:{game}`
	local r = self:_record(userId)
	r.claimed[source] = true
	if not self:_write(userId) then
		r.claimed[source] = nil
		return nil, "try again"
	end
	self.towns:_with(userId, function(s: any)
		local have = table.clone(s.freeCrates or {})
		if not table.find(have, source) then
			table.insert(have, source)
		end
		self.mods.store.useGame.setState({ freeCrates = have, updatedAt = self.towns.now() })
	end)
	return { source = source, week = week, game = game, place = prize.place }, nil
end

-- The player left: forget their run and cached record (it was written after every change).
function Arcade.close(self: Arcade, userId: number)
	self.runs[userId] = nil
	self.lastStart[userId] = nil
	self.records[userId] = nil
end

return Arcade
