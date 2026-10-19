--!strict
-- Crew battles, as the web game's supabase/migrations/0050_crew_battles.sql and ui/CrewBattle.tsx:
-- every week (Monday 00:00 UTC to Monday) each crew is matched against one rival crew, and the two
-- race for the most battle points.
--   * A race run +1, a race won +3 more (from each save, as the crew goal's points); a live race
--     won +10, or +25 against a member of the rival crew (at most 3 a day against the same player).
--   * Save points come out of a bank per player that refills 1 point every 3 seconds (up to 300),
--     and a member's points count up to 500 a week, so one grinder can't carry a crew.
--   * Matching happens the first time a crew is seen in a week: the crew still free that week that
--     is closest in power and size (no more than three times stronger or weaker, and played in the
--     last two weeks), or else a street crew run by the server, whose score climbs through the week
--     on a fixed curve sized to the crew (45 points a member, at least 2 members).
--   * When the week ends, members of the winning crew (both, on a draw) who scored at least 20
--     claim a victory chest during the following week, and the winner's top scorer an MVP chest
--     too. Both are crew chests (data.CREW_CHEST), counted with the weekly goal's (server/CrewGoals).
--
-- The war chests and war log (web 0113): once the crew's score reaches 40% of its par (45 points a
-- member, counting everyone in the crew or who scored for it, at least 2), and again at 100%, each
-- member who scored at least 20 claims a war chest, win or lose, that week or the next. Each crew
-- keeps its last wars ("h:<crewId>", results filled in once a week is over) for its record, its
-- league and the log.
--
-- In Roblox it's one DataStore, "CrewBattles_v1", changed with UpdateAsync: "m:<week>" the week's
-- battles ({ of = { [crewId] = battleId }, b = { [battleId] = battle } }), "p:<crewId>:<week>" a
-- crew's points ({ [userId] = { p, r, w, l, h, name } }) and "k:<userId>" a player's bank and live
-- wins counted today. Without DataStores (tests, the emulator) everything lives in memory.

local CrewBattles = {}
CrewBattles.__index = CrewBattles

CrewBattles.RULES = { race = 1, win = 3, live = 10, h2h = 25, livePerRival = 3, memberCap = 500, minPoints = 20, bankMax = 300, bankSeconds = 3, botPerMember = 45, botMinMembers = 2, par = 45, tiers = { 0.4, 1 } }
-- The war league (web lib/battles LEAGUES): a rating from the crew's record.
CrewBattles.LEAGUES = {
	{ id = "bronze", icon = "🥉", name = "Bronze", min = 0 },
	{ id = "silver", icon = "🥈", name = "Silver", min = 1050 },
	{ id = "gold", icon = "🥇", name = "Gold", min = 1150 },
	{ id = "platinum", icon = "💠", name = "Platinum", min = 1300 },
	{ id = "diamond", icon = "💎", name = "Diamond", min = 1500 },
}
local RULES = CrewBattles.RULES
local STORE = "CrewBattles_v1"
local DAY = 86400
local WEEK = 7 * DAY

-- The street crews (invented names, as the web game's battle_bot).
local STREET = {
	{ "Rust Belt Rollers", "RBR" },
	{ "Midnight Mufflers", "MMF" },
	{ "Chrome Coyotes", "CHC" },
	{ "Gravel Ghosts", "GGH" },
	{ "Neon Nomads", "NEO" },
	{ "Torque Tribe", "TQT" },
	{ "Velvet Pistons", "VPS" },
	{ "Asphalt Owls", "OWL" },
	{ "Turbo Tortoises", "TRT" },
	{ "Redline Rascals", "RLR" },
	{ "Backfire Bandits", "BFB" },
	{ "Dune Drifters", "DDR" },
	{ "Harbor Hounds", "HHD" },
	{ "Frost Fangs", "FFG" },
}
local DRIVERS = { "Dusty Vance", "Gearbox Gil", "Lola Lugnut", "Skid Marlowe", "Penny Piston", "Hal Hubcap", "Rosa Redline", "Bo Burnout", "Ziggy Zorn", "Mags Malone", "Tex Torque", "Ivy Ignition", "Cruz Clutch", "Nova Knox", "Rex Radiator", "Juno Jetstream", "Otis Overdrive", "Sunny Shifter" }
local VENUES = { "main", "beach", "desert", "snow", "farm", "docks" }

export type Mods = {
	plain: ((name: string) -> any)?,
	clock: () -> number,
	-- The crews to match against (server/Crews' browser lines: id, members, power, seen) and one
	-- crew's look ({ id, name, tag, emblem, color, members = { [userId] = { name } } }).
	crews: () -> { any },
	crew: (id: string) -> any?,
	emblems: { string },
	colors: { string },
}

export type CrewBattles = typeof(setmetatable(
	{} :: {
		mods: Mods,
		mem: { [string]: any },
		-- Battles already matched (they never change), by "<crew>:<week>".
		known: { [string]: any },
	},
	CrewBattles
))

function CrewBattles.new(mods: Mods): CrewBattles
	return setmetatable({ mods = mods, mem = {}, known = {} }, CrewBattles)
end

-- The Monday a week starts on (days since 1970) and its name.
local function weekDay(t: number): number
	local d = math.floor(t / DAY)
	return d - (d + 3) % 7
end
local function weekName(day: number): string
	return os.date("!%Y-%m-%d", day * DAY) :: string
end
-- When a week ("2026-10-19") starts, in seconds (UTC; days from the civil date, so no time zones).
local function weekStart(week: string): number
	local y, m, d = week:match("^(%d+)-(%d+)-(%d+)$")
	local yy, mm, dd = tonumber(y) or 1970, tonumber(m) or 1, tonumber(d) or 1
	if mm <= 2 then
		yy -= 1
	end
	local era = yy // 400
	local yoe = yy - era * 400
	local doy = (153 * (if mm > 2 then mm - 3 else mm + 9) + 2) // 5 + dd - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	return (era * 146097 + doe - 719468) * DAY
end
CrewBattles.weekStart = weekStart
function CrewBattles.weeks(t: number): (string, string)
	local d = weekDay(t)
	return weekName(d), weekName(d - 7)
end

-- A number from 0 to 1 that's always the same for the same text (FNV-1a).
function CrewBattles.roll(seed: string): number
	local h = 2166136261
	for i = 1, #seed do
		h = bit32.bxor(h, string.byte(seed, i))
		h = (h * 16777619) % 4294967296
	end
	return h / 4294967296
end
local roll = CrewBattles.roll

function CrewBattles._get(self: CrewBattles, key: string): any
	local plain = self.mods.plain
	if not plain then
		local v = self.mem[key]
		return if type(v) == "table" then table.clone(v) else v
	end
	local ok, v = pcall(function()
		return plain(STORE):GetAsync(key)
	end)
	return if ok then v else nil
end

function CrewBattles._update(self: CrewBattles, key: string, fn: (any) -> any): boolean
	local plain = self.mods.plain
	if not plain then
		local old = self.mem[key]
		local v = fn(if type(old) == "table" then table.clone(old) else {})
		if v ~= nil then
			self.mem[key] = v
		end
		return true
	end
	return (pcall(function()
		plain(STORE):UpdateAsync(key, function(old: any): any
			return fn(if type(old) == "table" then old else {})
		end)
	end))
end

-- A street crew sized to the crew it meets: name, look, drivers and the score it will reach.
-- wonLast: the crew won its battle last week (a little tougher).
function CrewBattles.bot(self: CrewBattles, crewId: string, week: string, members: number, wonLast: boolean?): any
	local seed = crewId .. week
	local n = math.max(members, RULES.botMinMembers)
	local pick = STREET[1 + math.floor(roll(seed .. "name") * #STREET)]
	-- 0.80 to 1.15 of par, a little tougher after a win.
	local diff = 0.8 + roll(seed .. "diff") * 0.35 + (if wonLast then 0.1 else 0)
	local first = math.floor(roll(seed .. "driver") * #DRIVERS)
	local drivers = {}
	for i = 1, math.min(math.max(n, 3), 6) do
		table.insert(drivers, { name = DRIVERS[1 + (first + i * 7) % #DRIVERS], w = math.round((0.4 + roll(seed .. "w" .. i) * 1.2) * 100) / 100 })
	end
	local emblems, colors = self.mods.emblems, self.mods.colors
	return {
		name = pick[1],
		tag = pick[2],
		emblem = emblems[1 + math.floor(roll(seed .. "emblem") * #emblems)],
		color = colors[1 + math.floor(roll(seed .. "color") * #colors)],
		total = math.round(RULES.botPerMember * n * diff),
		members = drivers,
	}
end

-- A street crew's score at a moment: it races in bursts through the week (an hour at a time, some
-- hours idle) and reaches its total as the week ends.
function CrewBattles.botScore(bot: any, seed: string, week: string, at: number): number
	local start = weekStart(week)
	local e = math.clamp((at - start) / 3600, 0, 168)
	local sum, got = 0, 0
	for h = 0, 167 do
		local w = if roll(seed .. "h" .. h) < 0.45 then 0 else roll(seed .. "v" .. h)
		sum += w
		got += w * math.clamp(e - h, 0, 1)
	end
	return if sum > 0 then math.floor(bot.total * got / sum) else 0
end

-- A crew's score in a week: its members' points, each capped.
function CrewBattles.score(self: CrewBattles, crewId: string?, week: string): (number, any)
	if not crewId then
		return 0, {}
	end
	local pts = self:_get(`p:{crewId}:{week}`) or {}
	local n = 0
	for _, p in pts do
		n += math.min(p.p or 0, RULES.memberCap)
	end
	return n, pts
end

-- The battle a crew is in this week, matching it the first time (members: its size now).
function CrewBattles.battleOf(self: CrewBattles, crewId: string, which: string?): any?
	local now = self.mods.clock()
	local this = CrewBattles.weeks(now)
	local week: string = which or this
	local seen = self.known[`{crewId}:{week}`]
	if seen then
		return seen
	end
	local m = self:_get(`m:{week}`) or {}
	local id = (m.of or {})[crewId]
	if id and (m.b or {})[id] then
		self.known[`{crewId}:{week}`] = m.b[id]
		return m.b[id]
	end
	if week ~= this then
		return nil
	end
	-- Not matched yet this week: find the closest crew still free.
	local mine, cands = nil, {}
	for _, c in self.mods.crews() do
		if c.id == crewId then
			mine = c
		else
			table.insert(cands, c)
		end
	end
	local myPw, myN = math.max(mine and mine.power or 0, 1), mine and mine.members or 1
	local _, lastWeek = CrewBattles.weeks(now)
	local wonLast = self:result(crewId, lastWeek) == "win"
	local made: any = nil
	self:_update(`m:{week}`, function(w: any): any
		made = nil
		w.of, w.b = w.of or {}, w.b or {}
		if w.of[crewId] then
			made = w.b[w.of[crewId]]
			return nil
		end
		local best, bestScore = nil, math.huge
		for _, c in cands do
			local pw = math.max(c.power or 0, 1)
			if not w.of[c.id] and (c.seen or 0) > now - 14 * DAY and pw <= myPw * 3 and myPw <= pw * 3 then
				local d = math.abs(math.log(pw) - math.log(myPw)) + math.abs((c.members or 1) - myN) * 0.15
				if d < bestScore or (d == bestScore and best and c.id < best.id) then
					best, bestScore = c, d
				end
			end
		end
		local bid = `{week}:{crewId}`
		local x = {
			id = bid,
			week = week,
			a = crewId,
			b = if best then best.id else nil,
			bot = if best then nil else self:bot(crewId, week, myN, wonLast),
			venue = VENUES[1 + math.floor(roll(crewId .. week .. "venue") * #VENUES)],
		}
		w.b[bid] = x
		w.of[crewId] = bid
		if best then
			w.of[best.id] = bid
		end
		made = x
		return w
	end)
	if made then
		self.known[`{crewId}:{week}`] = made
		self:_note(crewId, made)
		if made.b then
			self:_note(made.b, made)
		end
	end
	return made
end

-- Adds a war to a crew's history (newest first, 52 kept), once.
function CrewBattles._note(self: CrewBattles, crewId: string, x: any)
	self:_update(`h:{crewId}`, function(h: any): any
		h.wars = h.wars or {}
		for _, w in h.wars do
			if w.week == x.week then
				return nil
			end
		end
		table.insert(h.wars, 1, { week = x.week, venue = x.venue })
		while #h.wars > 52 do
			table.remove(h.wars)
		end
		return h
	end)
end

-- A crew's finished wars, newest first ({ week, venue, result, us, them, rival }); fills in the
-- results of weeks that have ended since it last looked (they never change after).
function CrewBattles.history(self: CrewBattles, crewId: string): { any }
	local h = self:_get(`h:{crewId}`) or {}
	local this = CrewBattles.weeks(self.mods.clock())
	local done, filled = {}, {}
	for _, w in h.wars or {} do
		if w.week < this then
			if w.result == nil then
				local x = self:battleOf(crewId, w.week)
				if x then
					local us = self:score(crewId, w.week)
					local them = self:rivalScore(x, crewId)
					local other = if x.bot then nil else self.mods.crew(if crewId == x.a then x.b else x.a)
					w.us, w.them = us, them
					w.result = if us > them then "win" elseif us < them then "loss" else "draw"
					w.rival = if x.bot
						then { bot = true, name = x.bot.name, tag = x.bot.tag, emblem = x.bot.emblem, color = x.bot.color }
						else { bot = false, id = if crewId == x.a then x.b else x.a, name = if other then other.name else "A crew", tag = if other then other.tag else "??", emblem = if other then other.emblem else "🏁", color = if other then other.color else "#546e7a" }
					filled[w.week] = w
				end
			end
			if w.result then
				table.insert(done, w)
			end
		end
	end
	if next(filled) then
		self:_update(`h:{crewId}`, function(r: any): any
			for _, w in r.wars or {} do
				local f = filled[w.week]
				if f and w.result == nil then
					w.result, w.us, w.them, w.rival = f.result, f.us, f.them, f.rival
				end
			end
			return r
		end)
	end
	return done
end

-- A crew's record (wins, losses, draws and its winning streak) and league from its finished wars.
function CrewBattles.record(wars: { any }): (any, any)
	local r = { wins = 0, losses = 0, draws = 0, streak = 0 }
	local counting = true
	for _, w in wars do
		if w.result == "win" then
			r.wins += 1
		elseif w.result == "loss" then
			r.losses += 1
		else
			r.draws += 1
		end
		if counting and w.result == "win" then
			r.streak += 1
		else
			counting = false
		end
	end
	local rating = math.max(0, 1000 + r.wins * 30 - r.losses * 15)
	local at = 1
	for i, l in CrewBattles.LEAGUES do
		if rating >= l.min then
			at = i
		end
	end
	local l = CrewBattles.LEAGUES[at]
	local nxt = CrewBattles.LEAGUES[at + 1]
	return r, { id = l.id, icon = l.icon, name = l.name, rating = rating, next = if nxt then { name = nxt.name, icon = nxt.icon, min = nxt.min } else nil }
end

-- The war score a crew aims for in a week: par a member, counting everyone in it now and everyone
-- who scored for it that week (so members leaving mid-war don't lower the bar), at least two.
function CrewBattles.par(self: CrewBattles, crewId: string, week: string): number
	local seen = {}
	local n = 0
	local c = self.mods.crew(crewId)
	for uid in (c and c.members) or {} do
		seen[tostring(uid)] = true
		n += 1
	end
	local _, pts = self:score(crewId, week)
	for uid in pts do
		if not seen[tostring(uid)] then
			seen[tostring(uid)] = true
			n += 1
		end
	end
	return RULES.par * math.max(n, RULES.botMinMembers)
end

-- The rival's score: the other crew's, or the street crew's so far (all of it once the week is over).
function CrewBattles.rivalScore(self: CrewBattles, x: any, crewId: string): number
	if x.bot then
		return CrewBattles.botScore(x.bot, x.id, x.week, math.min(self.mods.clock(), self:_weekEnd(x.week)))
	end
	return (self:score(if crewId == x.a then x.b else x.a, x.week))
end

function CrewBattles._weekEnd(_self: CrewBattles, week: string): number
	return weekStart(week) + WEEK
end

-- "win", "loss" or "draw" for a crew once its battle's week is over (nil while it's on, or none).
function CrewBattles.result(self: CrewBattles, crewId: string, week: string): string?
	if week >= CrewBattles.weeks(self.mods.clock()) then
		return nil
	end
	local x = self:battleOf(crewId, week)
	if not x then
		return nil
	end
	local us = self:score(crewId, week)
	local them = self:rivalScore(x, crewId)
	return if us > them then "win" elseif us < them then "loss" else "draw"
end

-- Adds points to a player's crew this week (the battle is matched first, as on the web).
function CrewBattles._add(self: CrewBattles, userId: number, crewId: string, name: string, kind: { r: number?, w: number?, l: number?, h: number? }, points: number)
	if points <= 0 then
		return
	end
	local week = CrewBattles.weeks(self.mods.clock())
	self:battleOf(crewId)
	self:_update(`p:{crewId}:{week}`, function(pts: any): any
		local key = tostring(userId)
		local p = pts[key] or { p = 0, r = 0, w = 0, l = 0, h = 0 }
		p.p += points
		p.r += kind.r or 0
		p.w += kind.w or 0
		p.l += kind.l or 0
		p.h += kind.h or 0
		p.name = name
		p.at = self.mods.clock()
		pts[key] = p
		return pts
	end)
end

-- Races run and won since the last save, out of the player's bank. Returns the points added.
function CrewBattles.races(self: CrewBattles, userId: number, crewId: string, name: string, races: number, wins: number): number
	local function whole(v: any): number
		local n = tonumber(v) or 0
		return if n ~= n then 0 else math.clamp(math.floor(n), 0, 100000)
	end
	local dw = whole(wins)
	local dr = math.max(whole(races), dw)
	local raw = dr * RULES.race + dw * RULES.win
	if raw <= 0 then
		return 0
	end
	local now = self.mods.clock()
	local got = 0
	if not self:_update(`k:{userId}`, function(k: any): any
		local bank = if k.bank == nil then RULES.bankMax else math.min(k.bank + math.max(0, now - (k.at or now)) / RULES.bankSeconds, RULES.bankMax)
		got = math.min(raw, math.floor(bank))
		k.bank, k.at = bank - got, now
		return k
	end) or got <= 0 then
		return 0
	end
	-- Races and wins are scaled down together when the bank runs short.
	self:_add(userId, crewId, name, { r = dr * got // raw, w = dw * got // raw }, got)
	return got
end

-- A live race won: +10, or +25 against a member of the rival crew; at most 3 a day against the same
-- player. theirCrew: the loser's crew (nil: none). Returns the points added.
function CrewBattles.live(self: CrewBattles, winner: number, crewId: string, name: string, loser: number, theirCrew: string?): number
	local now = self.mods.clock()
	local day = os.date("!%Y-%m-%d", now) :: string
	local counted = false
	self:_update(`k:{winner}`, function(k: any): any
		counted = false
		local live = if k.liveDay == day then k.live or {} else {}
		local key = tostring(loser)
		if (live[key] or 0) >= RULES.livePerRival then
			return nil
		end
		live[key] = (live[key] or 0) + 1
		k.live, k.liveDay = live, day
		counted = true
		return k
	end)
	if not counted then
		return 0
	end
	local x = self:battleOf(crewId)
	local h2h = theirCrew ~= nil and theirCrew ~= crewId and x ~= nil and (x.a == theirCrew or x.b == theirCrew)
	local points = if h2h then RULES.h2h else RULES.live
	self:_add(winner, crewId, name, { l = 1, h = if h2h then 1 else 0 }, points)
	return points
end

-- One side of a battle as the game shows it.
function CrewBattles._side(self: CrewBattles, x: any, crewId: string?, isBot: boolean): any
	if isBot then
		local score = self:rivalScore(x, x.a)
		local wsum = 0
		for _, m in x.bot.members do
			wsum += m.w
		end
		local members = {}
		for i, m in x.bot.members do
			table.insert(members, { id = `bot{i}`, name = m.name, points = math.floor(score * m.w / math.max(wsum, 0.01)) })
		end
		table.sort(members, function(a, b)
			return a.points > b.points
		end)
		return { bot = true, name = x.bot.name, tag = x.bot.tag, emblem = x.bot.emblem, color = x.bot.color, score = score, members = members }
	end
	local c = if crewId then self.mods.crew(crewId) else nil
	local score, pts = self:score(crewId, x.week)
	local members = {}
	for uid, p in pts do
		table.insert(members, { id = tonumber(uid), name = p.name or "Driver", points = math.min(p.p or 0, RULES.memberCap), races = p.r, wins = p.w, live = p.l, h2h = p.h, at = p.at or 0 })
	end
	table.sort(members, function(a, b)
		if a.points ~= b.points then
			return a.points > b.points
		end
		return a.at < b.at
	end)
	return {
		bot = false,
		id = crewId,
		name = if c then c.name else "A crew",
		tag = if c then c.tag else "??",
		emblem = if c then c.emblem else "🏁",
		color = if c then c.color else "#546e7a",
		score = score,
		members = members,
	}
end

-- A battle from one crew's side: us, them, the result once it's over, and the chests this player
-- has coming (claimable: kinds not yet claimed; claimed: what they have).
function CrewBattles.view(self: CrewBattles, x: any, crewId: string, userId: number, claimed: { [string]: boolean }?): any
	local us = self:_side(x, crewId, false)
	local them = self:_side(x, if crewId == x.a then x.b else x.a, x.bot ~= nil)
	local mine = 0
	for _, m in us.members do
		if m.id == userId then
			mine = m.points
		end
	end
	local result = self:result(crewId, x.week)
	local mvp = us.members[1] ~= nil and us.members[1].id == userId
	local due = {}
	if result and result ~= "loss" and mine >= RULES.minPoints then
		table.insert(due, "battle")
		if result == "win" and mvp then
			table.insert(due, "mvp")
		end
	end
	local claimable = {}
	for _, kind in due do
		if not (claimed and claimed[`{kind}:{x.week}`]) then
			table.insert(claimable, kind)
		end
	end
	-- The war chest track: a chest at each tier of par, win or lose.
	local par = self:par(crewId, x.week)
	local tiers = {}
	for i, f in RULES.tiers do
		local need = math.ceil(par * f)
		local reached = us.score >= need
		local got = claimed ~= nil and claimed[`tier{i}:{x.week}`] == true
		table.insert(tiers, { tier = i, need = need, reached = reached, claimed = got, claimable = reached and not got and mine >= RULES.minPoints })
	end
	return { week = x.week, venue = x.venue, result = result, mine = mine, mvp = mvp, us = us, them = them, due = due, claimable = claimable, par = par, tiers = tiers }
end

-- The player's crew battle: this week's (when they're in a crew) and last week's, for its result and
-- chests (the crew they scored most for then, or else their crew now). claimed: the chests they've
-- had (server/CrewGoals' opened keys).
function CrewBattles.battle(self: CrewBattles, userId: number, crewId: string?, claimed: { [string]: boolean }?): any
	local now = self.mods.clock()
	local this, last = CrewBattles.weeks(now)
	local current = nil
	if crewId then
		local x = self:battleOf(crewId)
		if x then
			current = self:view(x, crewId, userId, claimed)
		end
	end
	local lastView = nil
	local lastCrew = crewId
	-- (Points are kept per crew: which crew did they score for last week?)
	local k = self:_get(`k:{userId}`) or {}
	if type(k.scored) == "table" and k.scored[last] then
		lastCrew = k.scored[last]
	end
	if lastCrew then
		local x = self:battleOf(lastCrew, last)
		if x then
			lastView = self:view(x, lastCrew, userId, claimed)
		end
	end
	local wars = if crewId then self:history(crewId) else {}
	local record, league = CrewBattles.record(wars)
	local log = {}
	for i = 1, math.min(#wars, 8) do
		table.insert(log, wars[i])
	end
	return { week = this, rules = RULES, left = (weekDay(now) + 7) * DAY - now, current = current, last = lastView, record = record, league = league, log = log }
end

-- Notes which crew a player scored for this week (for last week's chest after changing crews).
function CrewBattles.scoredFor(self: CrewBattles, userId: number, crewId: string)
	local this, last = CrewBattles.weeks(self.mods.clock())
	local k = self:_get(`k:{userId}`) or {}
	if type(k.scored) == "table" and k.scored[this] == crewId then
		return
	end
	self:_update(`k:{userId}`, function(r: any): any
		local scored = {}
		for wk, id in r.scored or {} do
			if wk == this or wk == last then
				scored[wk] = id
			end
		end
		scored[this] = crewId
		r.scored = scored
		return r
	end)
end

return CrewBattles
