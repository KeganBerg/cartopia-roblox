-- Server entry point. The server owns the economy: every town runs on the server (Towns), saves
-- go to a DataStore with session locking (Saves), and clients only ask for changes through the
-- Cartopia.Act remote, which the server checks before running.
--
-- Remotes (in ReplicatedStorage.Cartopia):
--   Act    RemoteFunction  client -> server: (action, ...args) -> ok, result or error text
--   Town   RemoteEvent     server -> client: { save, need, panel, toasts } after every change
--   Race   RemoteFunction  client -> server: ("rivals" | "campaign" | "start" | "finish", ...)
--                          -> ok, result or error text (see Races); "kartStart" { kind, which }
--                          and "kartFinish" { place, time } for kart races (see Karts); "partyList",
--                          "partyOpen", "partyJoin" id, "partyLeave", "partyGo", "partyFinish" time
--                          for kart parties with the others in this server (see KartParty)
--   Kart   RemoteEvent     both ways, for a kart party: the client sends "ready" and its race's
--                          "snap" and "notes"; the server sends "party", "parties", "setup", "go",
--                          the others' "snap" and "notes", and the "verdict"
--   Crate  RemoteFunction  client -> server: (crate id, free source?, count) -> ok, the opens or why;
--                          ("wheel") spins the Daily Spin -> ok, the spin { slice, open } or why
--   Arcade RemoteFunction  client -> server: ("state" | "start" | "submit" | "board" | "prizes" |
--                          "claim", ...) -> ok, result or why (see Arcade)
--   Bank   RemoteFunction  client -> server: ("shop") -> the gem and car packs on sale, or
--                          ("buy", pack id) -> ok, or why not; opens Roblox's purchase prompt
--   Meshes RemoteFunction  client -> server: (car id) -> loads that car's mod meshes into
--                          ReplicatedStorage.MeshLibrary, answering once they're in
--   Social RemoteFunction  client -> server: ("players" | "visit" | "home" | "help" | "join", arg)
--                          -> ok, result or error text: playing together (see Social)
--   GetIn  RemoteFunction  client -> server: ("enter", car) | ("exit"): getting in any car on
--                          foot and out again (see GetIn)
--   Visitor RemoteFunction client -> server: ("next") | ("claim", id) | ("leave", id): town
--                          visitors, their prizes rolled here (see Visitors)
--   WebLink RemoteFunction client -> server: (code) -> ok, or why not: brings the player's web
--                          town over, earned progress only (see WebLink)
--   AdminRemote            only in the owner's own PlayerGui.CartopiaAdmin: the admin panel's
--                          testing tools, checked by user id on every call (see Admin)
--
-- Each player's town is drawn in Workspace.Towns (TownView) on its own lot, from the web game's
-- own models (Shared.Models), and redrawn whenever it changes.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TextChatService = game:GetService("TextChatService")
local TextService = game:GetService("TextService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local Js = require(Game.__js)

-- Millisecond clock, so day keys, seasons and events match the web game to the second.
local function now(): number
	return DateTime.now().UnixTimestampMillis
end
Js.setClock(now)

local Saves = require(script.Saves)
local Towns = require(script.Towns)
local TownView = require(script.TownView)
local Races = require(script.Races)
local Karts = require(script.Karts)
local KartParty = require(script.KartParty)
local Boards = require(script.Boards)
local Ghosts = require(script.Ghosts)
local Crates = require(script.Crates)
local Arcade = require(script.Arcade)
local Policies = require(script.Policies)
local Purchases = require(script.Purchases)
local Policy = require(ReplicatedStorage.Shared.Policy)
local Splash = require(script.Splash)
local Social = require(script.Social)
local Leaders = require(script.Leaders)
local Meet = require(script.Meet)
local Mail = require(script.Mail)
local Duels = require(script.Duels)
local Invites = require(script.Invites)
local Crews = require(script.Crews)
local CrewGoals = require(script.CrewGoals)
local World = require(script.World)
local Drive = require(script.Drive)
local Sky = require(script.Sky)
local Prefs = require(script.Prefs)
local WebLink = require(script.WebLink)
local Builder = require(ReplicatedStorage.Shared.Models.Builder)
local GetIn = require(script.GetIn)
local Visitors = require(script.Visitors)
local Admin = require(script.Admin)
local Rave = require(script.Rave)

local AUTOSAVE = 5 * 60 -- seconds; well inside Saves.LOCK_TTL
local TICK = 1 -- seconds between town clock ticks, as on the web

local saves = Saves.new({
	store = DataStoreService:GetDataStore("Towns_v1"),
	job = if RunService:IsStudio() then "studio" else game.JobId,
	now = os.time,
})
local towns = Towns.new(require(Game.store), now, require(Game.lib_sound))
-- Everyone's ghost (their best time, or their best car for a par) and the taunts left for them.
local ghosts = Ghosts.new({
	ghosts = DataStoreService:GetDataStore("Ghosts_v1"),
	taunts = DataStoreService:GetDataStore("GhostTaunts_v1"),
}, os.time)
-- Each player's Roblox friends (the first 200), kept for a while: whose ghosts they can race.
local friendsOf: { [number]: { at: number, list: { any } } } = {}
local function friends(userId: number): { any }
	local known = friendsOf[userId]
	if known and os.clock() - known.at < 300 then
		return known.list
	end
	local list = {}
	pcall(function()
		local pages = Players:GetFriendsAsync(userId)
		for _ = 1, 2 do
			for _, f in pages:GetCurrentPage() do
				table.insert(list, { userId = f.Id, name = f.DisplayName })
			end
			if pages.IsFinished then
				break
			end
			pages:AdvanceToNextPageAsync()
		end
	end)
	friendsOf[userId] = { at = os.clock(), list = list }
	return list
end
-- Surprise visitors in town: who comes and what they pay is rolled here (server/Visitors); each
-- player's last arrival and the day's count are kept in Visitors_v1, so a rejoin doesn't reset them.
local visitorRecords = DataStoreService:GetDataStore("Visitors_v1")
local visitors = Visitors.new(towns, {
	store = require(Game.store),
	data = require(Game.data),
	random = function(): number
		return math.random()
	end,
	now = now,
	records = {
		get = function(userId: number): any
			return visitorRecords:GetAsync(tostring(userId))
		end,
		set = function(userId: number, rec: any)
			visitorRecords:SetAsync(tostring(userId), rec)
		end,
	},
})
-- Live drag races between players here (server/Duels, the race mode "live"). Messages go out on
-- the Duel remote, made with the others below.
local duelEvent: RemoteEvent? = nil
-- What another racer sees of a player: their name, town, level and race car.
local function liveCard(userId: number): any?
	local player = Players:GetPlayerByUserId(userId)
	if not player or not towns:isOpen(userId) then
		return nil
	end
	local save = towns:save(userId)
	local data = require(Game.data) :: any
	local car = (require(Game.raceCar) :: any).raceCarOf(save.cars or {}, save.raceCar)
	local out: any = { name = player.DisplayName, town = save.townName, level = save.level or 1, userId = userId }
	if car then
		out.carName = data.carDef(car.model).name
		out.model, out.color = car.model, car.color
		out.mods, out.panels, out.trim, out.skin, out.modSkin = car.mods, car.panels, car.trim, car.skin, car.modSkin
		out.pi = data.performance(data.carDef(car.model), car.upgrades, car.mods)
	end
	return out
end
local duels = Duels.new({
	clock = os.clock,
	send = function(userId: number, event: string, payload: any)
		local player = Players:GetPlayerByUserId(userId)
		if player and duelEvent then
			duelEvent:FireClient(player, event, payload)
		end
	end,
	card = liveCard,
	here = function(userId: number): boolean
		return Players:GetPlayerByUserId(userId) ~= nil and towns:isOpen(userId)
	end,
	wait = function(s: number)
		task.wait(s)
	end,
})
local races = Races.new(towns, {
	store = require(Game.store),
	data = require(Game.data),
	raceCar = require(Game.raceCar),
	fairRace = require(Game.fairRace),
	fairPi = require(Game.fairPi),
	grip = require(Game.grip),
	weather = require(Game.weather),
	venues = require(Game.scene_venues),
	paintRivals = require(Game.paintRivals),
	rivals = require(Game.rivals),
	distance = require(Game.distance),
	DragRace = require(ReplicatedStorage.Shared.DragRace),
	tourRivals = require(ReplicatedStorage.Shared.TourRivals),
	random = Random.new(),
	clock = os.clock,
	-- The other race modes, by name (server/Modes: each module's `id`).
	modes = (function()
		local out = {}
		for _, m in script.Modes:GetChildren() do
			if m:IsA("ModuleScript") then
				local mode = (require :: any)(m)
				out[mode.id] = mode
			end
		end
		return out
	end)(),
	game = function(name: string): any
		return require(Game:FindFirstChild(name) :: ModuleScript)
	end,
	boards = {
		trial = Boards.new("Trial", {
			ordered = function(name: string): any
				return DataStoreService:GetOrderedDataStore(name)
			end,
			plain = function(name: string): any
				return DataStoreService:GetDataStore(name)
			end,
		}, os.clock),
	},
	ghosts = ghosts,
	visitors = visitors,
	duels = duels,
	liveCard = liveCard,
	-- Whose ghosts a player can race: everyone else in this server, then their friends.
	people = function(userId: number): { any }
		local out, seen = {}, { [userId] = true }
		for _, p in Players:GetPlayers() do
			if not seen[p.UserId] then
				seen[p.UserId] = true
				table.insert(out, { userId = p.UserId, name = p.DisplayName, here = true })
			end
		end
		for _, f in friends(userId) do
			if not seen[f.userId] then
				seen[f.userId] = true
				table.insert(out, f)
			end
		end
		return out
	end,
})
-- Each player's Roblox rules (PolicyService), strict until known; crates check them before opening.
local policies = Policies.new(game:GetService("PolicyService"), Policy, task.wait)
local crates = Crates.new(towns, require(Game.store), require(Game.crates), function(userId, pay, free)
	return Policy.canOpenCrate(policies:get(userId), pay, free)
end)
local social = Social.new({
	towns = towns,
	data = require(Game.data),
	today = (require(Game.store) :: any).today,
	helps = (function()
		local ok, store = pcall(function()
			return DataStoreService:GetDataStore("Helps_v1")
		end)
		return if ok then store else nil
	end)(),
})

-- The arcade: one weekly board per board game, and each player's bests, free plays and claimed
-- prizes in the Arcade_v1 DataStore.
local arcadeRecords = DataStoreService:GetDataStore("Arcade_v1")
local arcade = Arcade.new(towns, {
	store = require(Game.store),
	data = require(Game.data),
	arcade = require(Game.arcade),
	arcadeMore = require(Game.arcadeMore),
	trial = require(Game.trial),
	boards = (function()
		local out = {}
		for _, g in Arcade.BOARD_GAMES do
			out[g] = Boards.new(`Arcade_{g}`, {
				ordered = function(name: string): any
					return DataStoreService:GetOrderedDataStore(name)
				end,
				plain = function(name: string): any
					return DataStoreService:GetDataStore(name)
				end,
			}, os.clock)
		end
		return out
	end)(),
	records = {
		get = function(userId: number): any
			local ok, v = pcall(arcadeRecords.GetAsync, arcadeRecords, tostring(userId))
			-- A failed read mustn't start a fresh record over the saved one (Studio without API
			-- access plays on a fresh one).
			if not ok and not RunService:IsStudio() then
				error(`arcade record: {v}`)
			end
			return if ok then v else nil
		end,
		set = function(userId: number, record: any): boolean
			return (pcall(arcadeRecords.SetAsync, arcadeRecords, tostring(userId), record))
		end,
	},
	clock = os.clock,
	now = now,
	random = function(): number
		return math.random()
	end,
})
-- Kart races: the Grand Prix, Bumper Blast and custom races (server/Karts).
local karts = Karts.new(towns, {
	store = require(Game.store),
	data = require(Game.data),
	kart = require(Game.kart),
	gpBeat = require(Game.gpBeat),
	raceCar = require(Game.raceCar),
	fairRace = require(Game.fairRace),
	boosts = require(Game.boosts),
	random = Random.new(),
	clock = os.clock,
})

local remotes = Instance.new("Folder")
remotes.Name = "Cartopia"
local kartEvent = Instance.new("RemoteEvent")
kartEvent.Name = "Kart"
kartEvent.Parent = remotes
-- Kart parties with the other players in this server (server/KartParty).
local parties = KartParty.new(towns, {
	store = require(Game.store),
	data = require(Game.data),
	kart = require(Game.kart),
	raceCar = require(Game.raceCar),
	boosts = require(Game.boosts),
	random = Random.new(),
	clock = os.clock,
	delay = function(s: number, fn: () -> ())
		task.delay(s, fn)
	end,
	-- userId 0: everyone in the server.
	send = function(userId: number, event: string, payload: any)
		if userId == 0 then
			kartEvent:FireAllClients(event, payload)
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		if player then
			kartEvent:FireClient(player, event, payload)
		end
	end,
	name = function(userId: number): string
		local player = Players:GetPlayerByUserId(userId)
		return if player then player.DisplayName else "A racer"
	end,
})
kartEvent.OnServerEvent:Connect(function(player: Player, event: any, payload: any)
	if event == "ready" then
		parties:ready(player.UserId)
	else
		parties:relay(player.UserId, event, payload)
	end
end)
duelEvent = Instance.new("RemoteEvent")
;(duelEvent :: RemoteEvent).Name = "Duel"
;(duelEvent :: RemoteEvent).Parent = remotes
;(duelEvent :: RemoteEvent).OnServerEvent:Connect(function(player: Player, event: any, payload: any)
	if event == "pos" then
		duels:relay(player.UserId, payload)
	end
end)
local act = Instance.new("RemoteFunction")
act.Name = "Act"
act.Parent = remotes
local townEvent = Instance.new("RemoteEvent")
townEvent.Name = "Town"
townEvent.Parent = remotes
local raceRemote = Instance.new("RemoteFunction")
raceRemote.Name = "Race"
raceRemote.Parent = remotes
local crateRemote = Instance.new("RemoteFunction")
crateRemote.Name = "Crate"
crateRemote.Parent = remotes
local arcadeRemote = Instance.new("RemoteFunction")
arcadeRemote.Name = "Arcade"
arcadeRemote.Parent = remotes
local bankRemote = Instance.new("RemoteFunction")
bankRemote.Name = "Bank"
bankRemote.Parent = remotes
local meshRemote = Instance.new("RemoteFunction")
meshRemote.Name = "Meshes"
meshRemote.Parent = remotes
local socialRemote = Instance.new("RemoteFunction")
socialRemote.Name = "Social"
socialRemote.Parent = remotes
local visitorRemote = Instance.new("RemoteFunction")
visitorRemote.Name = "Visitor"
visitorRemote.Parent = remotes
local webLinkRemote = Instance.new("RemoteFunction")
webLinkRemote.Name = "WebLink"
webLinkRemote.Parent = remotes
local prefsRemote = Instance.new("RemoteEvent")
prefsRemote.Name = "Prefs"
prefsRemote.Parent = remotes
-- Rave Mode's button (the DJ only), shared with every server.
Rave.start(remotes)
remotes.Parent = ReplicatedStorage
Prefs.start(DataStoreService:GetDataStore("Prefs_v1"), prefsRemote, Players)
GetIn.start(towns)

Splash.start()
Sky.start()

-- The mesh packs load first, so towns are drawn with real meshes rather than stand-in boxes.
-- Workspace's ShapesLoaded / ShapesTotal / ShapesReady attributes tell the clients' loading screen
-- (ReplicatedFirst/Loading) how far along this is. Towns are drawn as soon as the meshes are in;
-- the model library for the shop pictures is built after that, while players are already in.
local meshesReady = false
task.spawn(function()
	Builder.loadMeshes(45, function(done, total)
		workspace:SetAttribute("ShapesLoaded", done)
		workspace:SetAttribute("ShapesTotal", total)
	end)
	meshesReady = true
	workspace:SetAttribute("ShapesReady", true)
	-- The race venues' and rescue lot's own meshes come in next, then the race venues' at full
	-- detail (Builder.sharpenRaces), again for any that came late.
	task.spawn(function()
		Builder.loadVenues(60)
		Builder.sharpenRaces()
		task.delay(120, Builder.sharpenRaces)
	end)
	-- The far land past the countryside (client/Horizon) comes in behind, while players are already in.
	Builder.loadLate()
	-- A copy of every car and building for the client's shop pictures and placement ghost.
	local library = Instance.new("Folder")
	library.Name = "ModelLibrary"
	for _, kind in { "Cars", "Buildings", "Stripes" } do
		local f = Instance.new("Folder")
		f.Name = kind
		f.Parent = library
	end
	local data = require(Game.data) :: any
	for _, car in data.CARS do
		local m = Builder.build(car.id, Color3.fromHex(car.colors[1]))
		if m then
			m.Name = car.id
			m.Parent = library.Cars
		end
		local stripes = Builder.build(`stripe:{car.id}`)
		if stripes then
			stripes.Name = car.id
			stripes.Parent = library.Stripes
		end
	end
	for _, def in data.BUILDINGS do
		local name = Builder.buildingName(def.id, 1)
		local m = if name then Builder.build(name) else nil
		if m then
			m.Name = def.id
			m.Parent = library.Buildings
		end
	end
	-- The landmarks merged level 10 houses become, for the Upgrade sheet's picture.
	for _, name in { "landmark:vanguard", "landmark:globe" } do
		local m = Builder.build(name)
		if m then
			m.Name = name
			m.Parent = library.Buildings
		end
	end
	library.Parent = ReplicatedStorage
end)

local townsFolder = Instance.new("Folder")
townsFolder.Name = "Towns"
townsFolder.Parent = workspace

-- The shared world (server/World): a hub with plots round it. Players pick a free plot when they
-- join ("claim"), and their town is built there.
TownView.sharedGround = true
local world = World.build(workspace, TownView.MEADOW, function(p)
	TownView.groundTexture(p, "meadow", Vector3.new(80, 0, 80))
end, TownView.GRASS)
local views: { [Player]: any } = {}
local slots: { [number]: Player } = {}

local function viewOf(userId: number): any
	for p, v in views do
		if p.UserId == userId then
			return v
		end
	end
	return nil
end

-- The plot a player owns, or nil before they've claimed one.
local function slotOf(player: Player): number?
	for i, p in slots do
		if p == player then
			return i
		end
	end
	return nil
end

-- Where a player stands: the cross street in the middle of their town, or the hub before they
-- have one. Always on foot: the town view is played from above, and driving starts from there.
local function spawnAt(player: Player)
	local view = views[player]
	local character = player.Character
	if not character then
		return
	end
	if view then
		character:PivotTo(CFrame.new(view:tileToWorld(11.5, 11) + Vector3.new(0, 5, 0)))
	else
		character:PivotTo(CFrame.new(0, 5, 160))
	end
end

-- Last save sent to each player, so ticks that change nothing send nothing.
local sent: { [Player]: string } = {}

local function push(player: Player, force: boolean?)
	local snap = towns:snapshot(player.UserId)
	local key = HttpService:JSONEncode(snap.save)
	if force or #snap.toasts > 0 or #snap.sounds > 0 or snap.panel ~= nil or snap.need ~= nil or sent[player] ~= key then
		sent[player] = key
		townEvent:FireClient(player, snap)
		local view = views[player]
		if view then
			local ok, err = pcall(view.render, view, snap.save)
			if not ok then
				warn(`[Cartopia] drawing {player.Name}'s town: {err}`)
			end
		end
	end
end

-- A kart party's prizes reach the town's snapshot at once.
parties.mods.paid = function(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		push(player)
	end
end

-- Players on their way to a friend's server (Social "join"): their save is already written.
local leaving: { [Player]: boolean } = {}

-- Lending a hand at a business in the town a player is visiting (server/Social).
-- Friends' mail (server/Mail): help notes, gifts and postcards, and the count waiting for each
-- player (their "Mail" attribute, for the HUD's gift bell).
local mail = Mail.new({
	plain = function(name: string): any
		return DataStoreService:GetDataStore(name)
	end,
}, os.time, function(): string
	return os.date("!%Y-%m-%d") :: string
end)
local function mailCount(userId: number)
	local player = Players:GetPlayerByUserId(userId)
	if player then
		player:SetAttribute("Mail", mail:count(userId))
	end
end
local function townOf(userId: number): string
	local town = if towns:isOpen(userId) then towns:save(userId).townName else nil
	return if type(town) == "string" then town else "My Town"
end

local function helpAt(player: Player, uid: string): (any?, string?)
	local host = player:GetAttribute("Visiting")
	if type(host) ~= "number" or not towns:isOpen(player.UserId) or leaving[player] then
		return nil, "not visiting"
	end
	local ok, result, why = pcall(social.help, social, player.UserId, host, uid)
	if not ok then
		warn(`[Cartopia] {player.Name} help: {result}`)
		return nil, "error"
	end
	if result then
		player:SetAttribute("Helped", table.concat(result.helped, ","))
		-- The first help in a town today leaves its owner a note worth a little fuel.
		if #result.helped == 1 then
			task.spawn(function()
				if pcall(mail.help, mail, player.UserId, player.DisplayName, townOf(player.UserId), host) then
					mailCount(host)
				end
			end)
		end
	end
	push(player)
	return result, why
end

-- Clicking a building in the world taps it, like a tap on the web.
local function tap(player: Player, uid: string)
	if not towns:isOpen(player.UserId) then
		return
	end
	local ran, err = pcall(towns.run, towns, player.UserId, "tapBuilding", uid)
	if not ran then
		warn(`[Cartopia] {player.Name} tapBuilding: {err}`)
	end
	push(player)
end

-- A player's best car and town name, so others can race their ghost (as a par for that car)
-- before they have a time of their own.
local function ghostCard(userId: number)
	local card = towns:_with(userId, function(s: any)
		local car, pi = races:_car(s)
		return if car then { car = (require(Game.data) :: any).carDef(car.model).name, model = car.model, color = car.color, pi = pi, town = s.townName } else nil
	end)
	if card then
		ghosts:card(userId, card)
	end
end

-- The player leaderboards (server/Leaders): Power, Wins, Trophies and Level, all time and weekly.
local leaders = Leaders.new({
	ordered = function(name: string): any
		return DataStoreService:GetOrderedDataStore(name)
	end,
	plain = function(name: string): any
		return DataStoreService:GetDataStore(name)
	end,
}, os.clock, function(): string
	return (require(Game.data) :: any).weekKey(os.time() * 1000)
end)
local function leaderStats(userId: number): any
	local s = towns:save(userId)
	return Leaders.stats(s, (require(Game.data) :: any).garagePower(s.cars or {}))
end

-- The Car Meet (server/Meet): everyone's display of three cars, and likes.
local meet = Meet.new({
	ordered = function(name: string): any
		return DataStoreService:GetOrderedDataStore(name)
	end,
	plain = function(name: string): any
		return DataStoreService:GetDataStore(name)
	end,
}, os.time, function(): string
	return os.date("!%Y-%m-%d") :: string
end)
local function showcase(userId: number): { any }
	local s = towns:save(userId)
	return (require(Game.meet) :: any).showcaseOf(s.cars or {}, s.showcase)
end
-- A player's card (Social's player cards): their public numbers and cars, on show first.
local function cardOf(userId: number): any
	local data = require(Game.data) :: any
	return Meet.cardOf(towns:save(userId), showcase(userId), function(c: any): number
		return data.performance(data.carDef(c.model), c.upgrades, c.mods)
	end)
end

-- Crews (server/Crews): kept in one DataStore every server shares.
local crews = Crews.new({
	plain = function(name: string): any
		return DataStoreService:GetDataStore(name)
	end,
	clock = os.time,
	newId = function(): string
		return HttpService:GenerateGUID(false)
	end,
	emblems = (require(Game.data) :: any).CLAN_EMBLEMS,
	colors = (require(Game.data) :: any).CLAN_COLORS,
})
-- What a crew keeps of a player: their name, town and numbers.
local function crewWho(userId: number): Crews.Who
	local player = Players:GetPlayerByUserId(userId)
	local st = leaderStats(userId)
	local town = towns:save(userId).townName
	return { name = if player then player.DisplayName else "Driver", town = if type(town) == "string" then town else nil, level = st.level, power = st.power, wins = st.race_wins, trophies = st.trophies }
end

-- Crew weekly goals (server/CrewGoals): each save credits the jobs and races made since the last
-- one to the player's crew, as the web game's crew_track_points trigger.
local crewGoals = CrewGoals.new({
	plain = function(name: string): any
		return DataStoreService:GetDataStore(name)
	end,
	clock = os.time,
})
-- The jobs and races each player's town had when last counted.
local crewSeen: { [number]: { jobs: number, races: number } } = {}
-- now: counted before this returns (else in the background, as a save goes on).
local function crewPoints(userId: number, now: boolean?)
	local stats = towns:save(userId).stats or {}
	local jobs, races = tonumber(stats.jobs) or 0, tonumber(stats.races) or 0
	local seen = crewSeen[userId]
	crewSeen[userId] = { jobs = jobs, races = races }
	if not seen or (jobs <= seen.jobs and races <= seen.races) then
		return
	end
	local function count()
		local id = crews:mineId(userId)
		local c = id and crews:crew(id)
		if not c then
			return
		end
		local members = 0
		for _ in c.members do
			members += 1
		end
		local _, reached = crewGoals:add(userId, c.id, members, jobs - seen.jobs, races - seen.races)
		if not reached then
			return
		end
		-- Everyone in the crew who's in this server hears it.
		for uid in c.members do
			local other = Players:GetPlayerByUserId(tonumber(uid) or 0)
			if other and towns:isOpen(other.UserId) then
				towns:_with(other.UserId, function(st: any)
					st.toast("🧰 Your crew hit its weekly goal! Open your crew chest.")
				end)
				push(other)
			end
		end
	end
	if now then
		pcall(count)
	else
		task.spawn(pcall, count)
	end
end
-- Pays the crew chests a player has opened that their town hasn't had yet (one per chest).
local function payCrewChests(player: Player)
	local userId = player.UserId
	local total = crewGoals:chests(userId)
	if not towns:isOpen(userId) or total <= (towns:save(userId).crewChests or 0) then
		return
	end
	towns:_with(userId, function(st: any)
		local useGame = (require(Game.store) :: any).useGame
		for _ = (st.crewChests or 0) + 1, total do
			useGame.getState().openCrewChest()
		end
	end)
	push(player)
end

-- Writes a player's town, with the Robux purchases it holds (Purchases). True when it wrote.
local purchases
local function saveId(userId: number, release: boolean?): boolean
	if towns:isOpen(userId) and saves:holds(userId) then
		local receipts = purchases:toSave(userId)
		local wrote = saves:write(userId, towns:save(userId), release, receipts)
		if wrote and receipts then
			purchases:saved(userId, receipts)
		end
		pcall(ghostCard, userId)
		local player = Players:GetPlayerByUserId(userId)
		if wrote and player then
			local town = towns:save(userId).townName
			task.spawn(pcall, leaders.record, leaders, userId, player.DisplayName, if type(town) == "string" then town else "My Town", leaderStats(userId), release)
			task.spawn(pcall, meet.publish, meet, userId, player.DisplayName, if type(town) == "string" then town else "My Town", towns:save(userId).level or 1, showcase(userId))
			task.spawn(pcall, function()
				meet:saveCard(userId, player.DisplayName, cardOf(userId))
			end)
			task.spawn(pcall, crews.touch, crews, userId, crewWho(userId))
		end
		if wrote then
			pcall(crewPoints, userId)
		end
		return wrote
	end
	return false
end
purchases = Purchases.new(towns, require(Game.store), require(Game.bucksPacks), function(userId)
	return saveId(userId)
end)

local function save(player: Player, release: boolean?)
	saveId(player.UserId, release)
end

-- Invite rewards (server/Invites): a new player who joined from a friend's game invite counts as
-- theirs, and both get gems once the new player reaches level 10.
local invites = Invites.new({
	plain = function(name: string): any
		return DataStoreService:GetDataStore(name)
	end,
})
-- Players whose own reward has been looked at this session (at level 10 or more).
local inviteChecked: { [number]: boolean } = {}
local function payInvites(player: Player)
	local userId = player.UserId
	if not towns:isOpen(userId) then
		return
	end
	local level = towns:save(userId).level or 1
	local mine = 0
	if level >= Invites.INVITE_LEVEL and not inviteChecked[userId] then
		inviteChecked[userId] = true
		mine = invites:reached(userId, level)
	end
	local theirs = invites:claim(userId)
	if mine + theirs <= 0 or not towns:isOpen(userId) then
		return
	end
	towns:_with(userId, function(s: any)
		(require(Game.store) :: any).useGame.setState({ bucks = (s.bucks or 0) + mine + theirs })
		if mine > 0 then
			s.toast(`🎁 +{mine} Gems · invite reward for reaching level {Invites.INVITE_LEVEL}`)
		end
		if theirs > 0 then
			s.toast(`🎁 +{theirs} Gems · a friend you invited reached level {Invites.INVITE_LEVEL}`)
		end
	end)
	push(player)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(policies.load, policies, player)
	-- What friends left in the mail, checked now and then (other servers can't tell this one).
	task.spawn(function()
		while player.Parent do
			pcall(mailCount, player.UserId)
			task.wait(120)
		end
	end)
	-- Whether Roblox lets this player chat: the HUD's CHAT button only shows when it does.
	task.spawn(function()
		local ok, can = pcall(TextChatService.CanUserChatAsync, TextChatService, player.UserId)
		player:SetAttribute("CanChat", ok and can == true)
	end)
	local ok, data, receipts = pcall(saves.load, saves, player.UserId)
	if not ok then
		local failure = if type(data) == "table" then data else { reason = "failed", message = tostring(data) }
		warn(`[Cartopia] {failure.message}`)
		if RunService:IsStudio() and failure.reason ~= "locked" then
			-- Testing in Studio without saves: play on a fresh town that is never written.
			warn("[Cartopia] Saves are off, so this town won't be saved. To test saving, publish the place and turn on Game Settings > Security > Enable Studio Access to API Services.")
			data = nil
		elseif failure.reason == "locked" then
			player:Kick("Your town is still open on another server. Please try again in a minute.")
			return
		else
			player:Kick("Couldn't load your town right now. Please try again in a minute.")
			return
		end
	end
	if not player.Parent then -- left while loading: just let the lock go
		saves:write(player.UserId, data, true)
		return
	end
	purchases:load(player.UserId, receipts)
	local newPlayer = data == nil
	towns:open(player.UserId, data)
	pcall(crewPoints, player.UserId)
	-- Joined from a friend's invite with no town yet: theirs (server/Invites). Then any invite
	-- gems waiting, now and every couple of minutes (other servers can't tell this one).
	task.spawn(function()
		local okJoin, join = pcall(player.GetJoinData, player)
		local ref = if okJoin and type(join) == "table" then tonumber(join.ReferredByPlayerId) else nil
		pcall(invites.arrive, invites, player.UserId, ref, newPlayer)
		pcall(payCrewChests, player)
		while player.Parent do
			pcall(payInvites, player)
			task.wait(120)
		end
	end)
	-- How long they were away (since their save was last written): the welcome back shows it, and
	-- two days or more turns on double pay for the next few races, as the web's noteAway.
	local seen = saves:lastSeen(player.UserId)
	if seen then
		local away = math.max(0, (os.time() - seen) * 1000)
		player:SetAttribute("AwayMs", away)
		pcall(towns.run, towns, player.UserId, "noteAway", away)
	end
	-- Their own race car on their loading screen.
	pcall(function()
		local save = towns:snapshot(player.UserId).save
		local car = (require(Game.raceCar) :: any).raceCarOf(save.cars or {}, save.raceCar)
		Splash.forPlayer(player, car and car.model, car and car.color)
	end)
	if not player.Parent then
		return
	end
	push(player, true)
	-- They pick a plot first (the claim screen, Popups/Claim); the loading screen lifts for it
	-- straight away, without waiting for the server's 3D shapes: the plot map has none, and they
	-- keep loading while the player picks (claim waits for any still missing).
	player:SetAttribute("NeedsPlot", true)
	spawnAt(player)
	player.CharacterAdded:Connect(function()
		task.wait()
		spawnAt(player)
	end)
end)

-- Web codes tried per player this session, and when last: a code can't be guessed by trying.
local linkTries: { [Player]: { n: number, at: number } } = {}
-- When each player last asked for a visitor (Visitor "next"), and how often they may.
local visitorAsked: { [Player]: number } = {}
local VISITOR_ASK_GAP = 5
-- Rate limit: a burst of 20 actions, refilling 10 a second.
local budget: { [Player]: { n: number, at: number } } = {}
local function allow(player: Player): boolean
	local b = budget[player] or { n = 20, at = os.clock() }
	b.n = math.min(20, b.n + (os.clock() - b.at) * 10)
	b.at = os.clock()
	budget[player] = b
	if b.n < 1 then
		return false
	end
	b.n -= 1
	return true
end

Players.PlayerRemoving:Connect(function(player)
	-- First, so a double-or-nothing rematch left half way is settled in the save.
	races:close(player.UserId)
	duels:leave(player.UserId)
	inviteChecked[player.UserId] = nil
	-- (After the last save, which counted their last crew points.)
	task.defer(function()
		crewSeen[player.UserId] = nil
	end)
	karts:close(player.UserId)
	parties:forget(player.UserId)
	arcade:close(player.UserId)
	visitors:close(player.UserId)
	visitorAsked[player] = nil
	linkTries[player] = nil
	save(player, true)
	towns:close(player.UserId)
	purchases:forget(player.UserId)
	policies:forget(player.UserId)
	if views[player] then
		views[player]:destroy()
		views[player] = nil
	end
	for i, p in slots do
		if p == player then
			slots[i] = nil
			World.setOwner(world, i, nil)
		end
	end
	sent[player] = nil
	budget[player] = nil
	leaving[player] = nil
	social:forget(player.UserId)
	-- Anyone visiting their town is just on an empty plot now.
	for _, other in Players:GetPlayers() do
		if other:GetAttribute("Visiting") == player.UserId then
			other:SetAttribute("Visiting", nil)
			other:SetAttribute("Helped", nil)
		end
	end
end)

-- Names players type that others can see (a town's name, a restored car's plate), by action and
-- argument: Roblox's text filter runs on them before the town keeps them.
local TYPED = { renameTown = 1, collectRestored = 1 }
local function filtered(player: Player, text: string): string?
	if not text:match("%S") then
		return text
	end
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForBroadcastAsync()
	end)
	return if ok then result else nil
end

act.OnServerInvoke = function(player: Player, name: any, ...: any)
	if not towns:isOpen(player.UserId) or leaving[player] then
		return false, "town not loaded"
	end
	if not allow(player) then
		return false, "slow down"
	end
	local args = table.pack(...)
	local ok, why = Towns.check(name, args, args.n)
	if not ok then
		return false, why
	end
	local typed = TYPED[name]
	if typed and type(args[typed]) == "string" then
		local clean = filtered(player, args[typed])
		if not clean then
			return false, "filter"
		end
		args[typed] = clean
	end
	local ran, result = pcall(towns.run, towns, player.UserId, name, table.unpack(args, 1, args.n))
	if not ran then
		warn(`[Cartopia] {player.Name} {name}: {result}`)
		return false, "error"
	end
	push(player)
	return true, result
end

raceRemote.OnServerInvoke = function(player: Player, op: any, arg: any)
	if not towns:isOpen(player.UserId) then
		return false, "town not loaded"
	end
	if not allow(player) then
		return false, "slow down"
	end
	-- A live race's finish: the server's replay of this run, then the other racer's (waited for
	-- here, outside the town), for the race mode "live" to call it.
	local live = races.pending[player.UserId]
	if op == "finish" and live and live.mode == "live" then
		local DragRace = require(ReplicatedStorage.Shared.DragRace) :: any
		local myTime = math.huge
		if DragRace.valid(arg) then
			myTime = DragRace.times(DragRace.replay(live.spec, arg))
		end
		live.extra.their = duels:finish(player.UserId, myTime)
	end
	local ran, result, why = pcall(function(): (any, any)
		if op == "rivals" then
			return races:quickRivals(player.UserId), nil
		elseif op == "campaign" then
			return races:campaign(player.UserId), nil
		elseif op == "rows" then
			return races:rows(player.UserId), nil
		elseif op == "list" and type(arg) == "table" then
			return races:list(player.UserId, arg.mode, arg.which), nil
		elseif op == "act" and type(arg) == "table" then
			return races:act(player.UserId, arg.mode, arg.which)
		elseif op == "keep" then
			races:keep(player.UserId)
			return true, nil
		elseif op == "start" and type(arg) == "table" then
			return races:start(player.UserId, arg.mode, arg.which)
		elseif op == "finish" then
			return races:finish(player.UserId, arg)
		elseif op == "duel" and type(arg) == "number" then
			-- Challenges another player here to a live drag race (server/Duels).
			local id, why = duels:challenge(player.UserId, arg)
			return if id then { id = id } else nil, why
		elseif op == "duelAnswer" and type(arg) == "table" and type(arg.id) == "string" then
			local id, why = duels:answer(player.UserId, arg.id, arg.yes == true)
			return if id then { id = id } else nil, why
		elseif op == "duelCancel" then
			duels:cancel(player.UserId)
			return true, nil
		elseif op == "duelList" then
			local ids = {}
			for _, other in Players:GetPlayers() do
				table.insert(ids, other.UserId)
			end
			return duels:others(player.UserId, ids), nil
		elseif op == "duelInvites" then
			return duels:invitesFor(player.UserId), nil
		elseif op == "duelLeave" then
			duels:leave(player.UserId)
			return true, nil
		elseif op == "kartStart" and type(arg) == "table" then
			return karts:start(player.UserId, arg.kind, arg.which)
		elseif op == "kartFinish" then
			return karts:finish(player.UserId, arg)
		elseif op == "partyList" then
			return parties:list(player.UserId), nil
		elseif op == "partyOpen" then
			return parties:open(player.UserId)
		elseif op == "partyJoin" then
			return parties:join(player.UserId, arg)
		elseif op == "partyLeave" then
			parties:leave(player.UserId)
			return true, nil
		elseif op == "partyGo" then
			return parties:go(player.UserId)
		elseif op == "partyFinish" then
			return parties:finish(player.UserId, arg)
		end
		return nil, "not a race"
	end)
	if not ran then
		warn(`[Cartopia] {player.Name} race {op}: {result}`)
		return false, "error"
	end
	if op == "start" or op == "finish" or op == "act" or op == "kartStart" or op == "kartFinish" or op == "partyFinish" then
		push(player)
	end
	if result == nil then
		return false, why
	end
	return true, result
end

arcadeRemote.OnServerInvoke = function(player: Player, op: any, a: any, b: any, c: any)
	if not towns:isOpen(player.UserId) then
		return false, "town not loaded"
	end
	if not allow(player) then
		return false, "slow down"
	end
	local ran, result, why = pcall(function(): (any, any)
		if op == "state" then
			return arcade:state(player.UserId), nil
		elseif op == "start" then
			return arcade:start(player.UserId, a, b)
		elseif op == "submit" then
			return arcade:submit(player.UserId, a, b, c)
		elseif op == "board" then
			return arcade:board(player.UserId, a)
		elseif op == "prizes" then
			return arcade:prizes(player.UserId), nil
		elseif op == "claim" then
			return arcade:claim(player.UserId, a, b)
		end
		return nil, "not an arcade call"
	end)
	if not ran then
		warn(`[Cartopia] {player.Name} arcade {op}: {result}`)
		return false, "error"
	end
	if op == "start" or op == "submit" or op == "claim" then
		push(player)
	end
	if result == nil then
		return false, why
	end
	return true, result
end

-- A car's mod meshes, for the garage pictures (each car's pack loads once for everyone).
meshRemote.OnServerInvoke = function(_player: Player, car: any)
	if type(car) ~= "string" or not Builder.has(car) then
		return false
	end
	Builder.loadFor(car)
	return true
end

crateRemote.OnServerInvoke = function(player: Player, id: any, free: any, count: any)
	if not towns:isOpen(player.UserId) then
		return false, "town not loaded"
	end
	if not allow(player) then
		return false, "slow down"
	end
	local ran, result, why = pcall(crates.open, crates, player.UserId, id, free, count)
	if not ran then
		warn(`[Cartopia] {player.Name} crate {id}: {result}`)
		return false, "error"
	end
	push(player)
	if result == nil then
		return false, why
	end
	return true, result
end

-- Town visitors (server/Visitors): "next" asks for the next visitor (the one in town, a new one,
-- or { wait = seconds }), "claim" taps tourists or the mystery car for their prize, "leave" sends
-- the visitor on. Asking is held to once every few seconds on top of the usual budget.
webLinkRemote.OnServerInvoke = function(player: Player, raw: any)
	local userId = player.UserId
	if not towns:isOpen(userId) or not saves:holds(userId) then
		return false, "town not loaded"
	end
	local t = linkTries[player] or { n = 0, at = 0 }
	linkTries[player] = t
	if t.n >= 8 then
		return false, "tries"
	end
	if os.clock() - t.at < 3 then
		return false, "slow down"
	end
	local code = WebLink.clean(raw)
	if not code then
		return false, "code"
	end
	t.n += 1
	t.at = os.clock()
	if not HttpService.HttpEnabled then
		warn("[Cartopia] Web link needs Game Settings > Security > Allow HTTP Requests")
		return false, "offline"
	end
	local got, why = WebLink.claim(HttpService :: any, code, userId)
	if not got then
		return false, why
	end
	if not towns:isOpen(userId) or not player.Parent then
		return false, "town not loaded"
	end
	local here = towns:save(userId)
	local ok, err = pcall(function()
		local save = WebLink.strip(got.state, got.paid, here)
		-- Out of any race or kart party first, so nothing settles into the old town afterwards.
		races:close(userId)
		karts:close(userId)
		towns:close(userId)
		towns:open(userId, save)
	end)
	if not ok then
		warn(`[Cartopia] {player.Name} web link: {err}`)
		if not towns:isOpen(userId) then
			towns:open(userId, here)
		end
		return false, "failed"
	end
	save(player)
	push(player, true)
	return true, nil
end

visitorRemote.OnServerInvoke = function(player: Player, op: any, id: any)
	if not towns:isOpen(player.UserId) or leaving[player] then
		return false, "town not loaded"
	end
	if not allow(player) then
		return false, "slow down"
	end
	if op == "next" then
		local last = visitorAsked[player]
		if last and os.clock() - last < VISITOR_ASK_GAP then
			return false, "slow down"
		end
		visitorAsked[player] = os.clock()
		-- Not while visiting someone else's town (lib/visitors.ts ready()).
		if player:GetAttribute("Visiting") ~= nil then
			return true, { wait = 60 }
		end
	elseif op ~= "claim" and op ~= "leave" then
		return false, "not a visitor call"
	end
	if op ~= "next" and (type(id) ~= "string" or #id > 40) then
		return false, "no such visitor"
	end
	local ran, result, why = pcall(function(): (any, any)
		if op == "next" then
			return visitors:next(player.UserId)
		elseif op == "claim" then
			return visitors:claim(player.UserId, id)
		end
		return visitors:leave(player.UserId, id), nil
	end)
	if not ran then
		warn(`[Cartopia] {player.Name} visitor {op}: {result}`)
		return false, "error"
	end
	push(player)
	if result == nil then
		return false, why
	end
	return true, result
end

-- Playing together (server/Social): who's here, visiting their towns, helping, and joining a
-- friend's server.
local friendsCache: { [string]: boolean } = {}
local function areFriends(a: Player, b: number): boolean
	local key = `{math.min(a.UserId, b)}:{math.max(a.UserId, b)}`
	if friendsCache[key] == nil then
		local ok, yes = pcall(a.IsFriendsWith, a, b)
		if not ok then
			return false
		end
		friendsCache[key] = yes
	end
	return friendsCache[key]
end

-- Who's in whose town: a player standing (or driving) on someone else's plot is visiting them,
-- which the visit banner and help bubbles follow (Popups/Visit).
local function setVisiting(player: Player, host: number?)
	if player:GetAttribute("Visiting") == host then
		return
	end
	player:SetAttribute("Visiting", host)
	-- The businesses they've already helped there today (the help bubbles show a tick).
	player:SetAttribute("Helped", if host then table.concat(social:helped(player.UserId, host), ",") else nil)
end

-- The player's race car, built for driving (server/Drive), or nil for the stand-in.
local raceCar = require(Game.raceCar) :: any
local function carFor(player: Player): Model?
	local save = towns:save(player.UserId)
	local car = raceCar.raceCarOf(save.cars or {}, save.raceCar)
	if not car then
		return nil
	end
	local ok, model = pcall(Builder.build, car.model, if car.color then Color3.fromHex(car.color) else nil)
	return if ok then model else nil
end

local function startDriving(player: Player)
	if not Drive.isDriving(player) then
		Drive.set(player, carFor(player))
	end
end

-- Drives the player over to the host's plot: in their car, on the road outside the town.
local function driveTo(player: Player, host: Player): any
	local i = slotOf(host)
	local character = player.Character
	if not i or not character then
		return nil
	end
	character:PivotTo(World.gate(i) + Vector3.new(0, 6, 0))
	startDriving(player)
	setVisiting(player, host.UserId)
	return social:townInfo(player.UserId, host.UserId)
end

-- Back to the town view over their own town: out of the car, home, wherever they'd driven to.
local function goHome(player: Player)
	Drive.set(player, false)
	setVisiting(player, nil)
	spawnAt(player)
end

-- Claims plot `want` (or the first free one) for the player and builds their town on it.
local function claim(player: Player, want: any): (number?, string?)
	local have = slotOf(player)
	if have then
		return have, nil
	end
	-- In a server that has only just started, its 3D shapes may still be coming in: the town is
	-- drawn once they're in, so it has no stand-in boxes (the Claim banner shows how far along).
	local start = os.clock()
	while not meshesReady and os.clock() - start < 45 do
		task.wait(0.2)
	end
	if not player.Parent then
		return nil, "left"
	end
	have = slotOf(player)
	if have then
		return have, nil
	end
	local i: number
	if type(want) == "number" then
		if want ~= math.floor(want) or want < 0 or want >= World.COUNT then
			return nil, "not a plot"
		end
		if slots[want] then
			return nil, "plot taken"
		end
		i = want
	else
		i = 0
		while slots[i] do
			i += 1
		end
		if i >= World.COUNT then
			return nil, "no plots"
		end
	end
	slots[i] = player
	views[player] = TownView.new(townsFolder, player.Name, World.origin(i), player.UserId, function(uid)
		tap(player, uid)
	end, function(visitor, uid)
		-- Someone visiting lends a hand at one of this town's businesses.
		if visitor:GetAttribute("Visiting") == player.UserId then
			helpAt(visitor, uid)
		end
	end)
	World.setOwner(world, i, player.UserId, player.DisplayName)
	player:SetAttribute("TownSlot", i)
	player:SetAttribute("NeedsPlot", nil)
	push(player, true)
	Drive.set(player, false)
	spawnAt(player)
	player:SetAttribute("TownReady", true)
	return i, nil
end

-- Every half second: whose plot each player is on.
task.spawn(function()
	while true do
		task.wait(0.5)
		for _, player in Players:GetPlayers() do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local i = World.plotAt(root.Position)
				local owner = if i then slots[i] else nil
				setVisiting(player, if owner and owner ~= player and towns:isOpen(owner.UserId) then owner.UserId else nil)
			end
		end
	end
end)

-- Writes the save and lets its lock go, then sends the player to the friend's server. If the
-- teleport fails the lock is taken back and they play on here.
local function join(player: Player, friend: number): (any?, string?)
	if not areFriends(player, friend) then
		return nil, "not friends"
	end
	local ok, _, _, placeId, jobId = pcall(TeleportService.GetPlayerPlaceInstanceAsync, TeleportService, friend)
	if not ok or not jobId or jobId == "" then
		return nil, "not playing"
	end
	if jobId == game.JobId then
		local here = Players:GetPlayerByUserId(friend)
		local town = here and towns:isOpen(friend) and driveTo(player, here)
		if town then
			return { here = true, town = town }, nil
		end
		return nil, "not playing"
	end
	if placeId ~= game.PlaceId then
		return nil, "not playing"
	end
	leaving[player] = true
	races:close(player.UserId)
	save(player, true)
	local options = Instance.new("TeleportOptions")
	options.ServerInstanceId = jobId
	local sent, err = pcall(TeleportService.TeleportAsync, TeleportService, placeId, { player }, options)
	if not sent then
		warn(`[Cartopia] {player.Name} join: {err}`)
		pcall(saves.load, saves, player.UserId)
		leaving[player] = nil
		return nil, "couldn't join"
	end
	return { here = false }, nil
end

TeleportService.TeleportInitFailed:Connect(function(player: Player)
	if leaving[player] and player.Parent then
		pcall(saves.load, saves, player.UserId)
		leaving[player] = nil
	end
end)

socialRemote.OnServerInvoke = function(player: Player, op: any, arg: any)
	if not towns:isOpen(player.UserId) or leaving[player] then
		return false, "town not loaded"
	end
	if not allow(player) then
		return false, "slow down"
	end
	local ran, result, why = pcall(function(): (any, any)
		if op == "players" then
			-- Everyone else in this server with a town, friends first.
			local out = {}
			for _, other in Players:GetPlayers() do
				if other ~= player and towns:isOpen(other.UserId) and views[other] then
					local save = towns:save(other.UserId)
					table.insert(out, {
						id = other.UserId,
						name = other.DisplayName,
						user = other.Name,
						townName = save.townName,
						level = save.level,
						trophies = save.trophies or 0,
						cars = #(save.cars or {}),
						friend = areFriends(player, other.UserId),
						helped = #social:helped(player.UserId, other.UserId),
					})
				end
			end
			return out, nil
		elseif op == "visit" and type(arg) == "number" then
			local host = Players:GetPlayerByUserId(arg)
			if not host or host == player or not towns:isOpen(arg) or not views[host] then
				return nil, "not here"
			end
			return driveTo(player, host), nil
		elseif op == "town" and type(arg) == "number" then
			-- The visit banner's details, for a town they drove into.
			if player:GetAttribute("Visiting") ~= arg or not towns:isOpen(arg) then
				return nil, "not here"
			end
			return social:townInfo(player.UserId, arg), nil
		elseif op == "home" then
			goHome(player)
			return true, nil
		elseif op == "drive" then
			if not views[player] then
				return nil, "claim first"
			end
			startDriving(player)
			return true, nil
		elseif op == "claim" then
			return claim(player, arg)
		elseif op == "help" and type(arg) == "string" and #arg <= 64 then
			return helpAt(player, arg)
		elseif op == "leaders" and type(arg) == "table" and table.find(Leaders.METRICS, arg.metric) and (arg.period == "all" or arg.period == "week") then
			-- A leaderboard (Social's Leaderboards tab), with who on it is in this server.
			local stats = leaderStats(player.UserId)
			local town = towns:save(player.UserId).townName
			pcall(leaders.record, leaders, player.UserId, player.DisplayName, if type(town) == "string" then town else "My Town", stats)
			local rows, mine = leaders:board(arg.metric, arg.period, player.UserId, stats)
			local out = {}
			for _, r in rows do
				local here = Players:GetPlayerByUserId(r.id)
				table.insert(out, { id = r.id, name = r.name, town = r.town, level = r.level, value = r.value, here = here ~= nil and here ~= player and views[here] ~= nil })
			end
			return { rows = out, mine = mine }, nil
		elseif op == "meet" then
			-- The Car Meet (Social's Meet tab): drivers in this server first, then recent displays.
			local out, seen = {}, {}
			for _, other in Players:GetPlayers() do
				if other ~= player and towns:isOpen(other.UserId) and views[other] then
					local cars = {}
					for _, c in showcase(other.UserId) do
						table.insert(cars, Meet.carOf(c))
					end
					if #cars > 0 then
						local town = towns:save(other.UserId).townName
						table.insert(out, { id = other.UserId, name = other.DisplayName, town = town, level = towns:save(other.UserId).level, cars = cars, here = true })
						seen[other.UserId] = true
					end
				end
			end
			for _, d in meet:displays() do
				if d.id ~= player.UserId and not seen[d.id] then
					table.insert(out, d)
				end
			end
			local owners = { player.UserId }
			for _, d in out do
				table.insert(owners, d.id)
			end
			return { displays = out, likes = meet:likesFor(player.UserId, owners) }, nil
		elseif op == "like" and type(arg) == "number" then
			local r = meet:like(player.UserId, arg)
			if r ~= "liked" then
				return nil, if r == "limit" then "like limit" elseif r == "already" then "liked" else "no"
			end
			return { likes = meet:likes(arg) }, nil
		elseif op == "mail" then
			-- The gift bell's mail, and who they've sent a gift or postcard today.
			local box = mail:inbox(player.UserId)
			box.sent = mail:sentToday(player.UserId)
			player:SetAttribute("Mail", #box.notes)
			mail:see(player.UserId)
			return box, nil
		elseif op == "invites" then
			-- The Friends tab's invite line (server/Invites).
			return invites:stats(player.UserId), nil
		elseif op == "sent" then
			return mail:sentToday(player.UserId), nil
		elseif op == "claimMail" then
			local got = mail:claim(player.UserId)
			if got.count > 0 then
				towns:_with(player.UserId, function(s)
					s.receiveGifts(got.fuel, got.parts)
				end)
				saveId(player.UserId)
			end
			if got.left > 0 then
				towns:_with(player.UserId, function(s)
					s.toast(if got.count > 0 then `{got.left} more waiting. You can collect 10 a day.` else "You've collected 10 today. The rest wait for tomorrow.")
				end)
			end
			push(player)
			player:SetAttribute("Mail", got.left)
			return got, nil
		elseif (op == "gift" or op == "postcard") and type(arg) == "table" and type(arg.to) == "number" then
			-- A gift (15 fuel or 5 parts) or a postcard, for a friend or a driver in this server.
			local to = arg.to
			local other = Players:GetPlayerByUserId(to)
			if to == player.UserId or not (other or areFriends(player, to)) then
				return nil, "not a friend"
			end
			local r
			if op == "gift" then
				r = mail:gift(player.UserId, player.DisplayName, townOf(player.UserId), to, arg.item)
			else
				r = mail:postcard(player.UserId, player.DisplayName, townOf(player.UserId), to, arg.card, tonumber(arg.msg) or -1)
			end
			if r == "limit" then
				return nil, if op == "gift" then "gift limit" else "card limit"
			elseif r == "already" then
				return nil, "sent today"
			elseif r ~= "sent" then
				return nil, "no"
			end
			local name = if type(arg.name) == "string" and #arg.name <= 40 then arg.name else nil
			towns:_with(player.UserId, function(s)
				s.befriend(tostring(to), op, name)
				if op == "gift" then
					s.toast(`Sent {if arg.item == "parts" then "⚙" else "⛽"} {Mail.GIFTS[arg.item]} {arg.item}!`)
				else
					s.toast("💌 Postcard sent!")
				end
			end)
			push(player)
			task.spawn(pcall, mailCount, to)
			return { sent = true }, nil
		elseif op == "crew" then
			-- The Crew tab: the player's crew (and its requests, for officers), or the browser.
			local mine = crews:mine(player.UserId)
			local house = Purchases.hasCrewHouse(towns:save(player.UserId))
			-- Points made since the last save count straight away.
			pcall(crewPoints, player.UserId, true)
			pcall(payCrewChests, player)
			if mine then
				local members = 0
				for _ in mine.crew.members do
					members += 1
				end
				mine.house = house
				mine.goal = crewGoals:goal(player.UserId, mine.crew.id, members)
				return mine, nil
			end
			return { house = house, browse = crews:browse(if type(arg) == "string" then arg:sub(1, 24) else nil), asked = crews:asked(player.UserId), level = towns:save(player.UserId).level or 1, goal = crewGoals:goal(player.UserId, nil, 0) }, nil
		elseif op == "crewChest" and type(arg) == "string" then
			-- Opening a crew chest: recorded first, then paid (data.CREW_CHEST, store.openCrewChest).
			local total, no = crewGoals:open(player.UserId, arg)
			if not total then
				return nil, no
			end
			payCrewChests(player)
			return { chests = total }, nil
		elseif op == "crewCreate" and type(arg) == "table" then
			-- Starting a crew: a Crew House and $2,000 (data.CLAN_COST), charged once it's made.
			local data = require(Game.data) :: any
			local s = towns:save(player.UserId)
			if not Purchases.hasCrewHouse(s) then
				return nil, "crew house"
			end
			if (s.coins or 0) < data.CLAN_COST then
				return nil, "coins"
			end
			local spec = table.clone(arg)
			for _, k in { "name", "motto" } do
				if type(spec[k]) ~= "string" then
					return nil, k
				end
				local clean = filtered(player, spec[k])
				if not clean or clean ~= spec[k] then
					return nil, if k == "name" then "name filtered" else "motto filtered"
				end
			end
			local tag = Crews.cleanTag(spec.tag)
			local cleanTag = tag and filtered(player, tag)
			if tag and cleanTag ~= tag then
				return nil, "tag filtered"
			end
			local id, no = crews:create(player.UserId, crewWho(player.UserId), spec)
			if not id then
				return nil, no
			end
			towns:_with(player.UserId, function(st: any)
				(require(Game.store) :: any).useGame.setState({ coins = math.max(0, (st.coins or 0) - data.CLAN_COST) })
			end)
			push(player)
			return { id = id }, nil
		elseif op == "crewAsk" and type(arg) == "string" then
			return crews:ask(player.UserId, crewWho(player.UserId), arg)
		elseif op == "crewCancel" and type(arg) == "string" then
			crews:cancel(player.UserId, arg)
			return true, nil
		elseif op == "crewRespond" and type(arg) == "table" and type(arg.id) == "number" then
			return crews:respond(player.UserId, arg.id, arg.yes == true)
		elseif op == "crewLeave" then
			local ok, no = crews:leave(player.UserId)
			return if ok then true else nil, no
		elseif op == "crewKick" and type(arg) == "number" then
			local ok, no = crews:kick(player.UserId, arg)
			return if ok then true else nil, no
		elseif op == "crewRank" and type(arg) == "table" and type(arg.id) == "number" then
			local ok, no = crews:setRank(player.UserId, arg.id, arg.rank)
			return if ok then true else nil, no
		elseif op == "crewSettings" and type(arg) == "table" then
			local spec = table.clone(arg)
			if type(spec.motto) ~= "string" or filtered(player, spec.motto) ~= spec.motto then
				return nil, "motto filtered"
			end
			local ok, no = crews:settings(player.UserId, spec)
			return if ok then true else nil, no
		elseif op == "card" and type(arg) == "number" then
			-- Another player's card: from their town when they're in this server, else as last saved.
			local other = Players:GetPlayerByUserId(arg)
			local card: any
			if other and towns:isOpen(arg) then
				card = cardOf(arg)
				card.name = other.DisplayName
			else
				card = meet:card(arg)
			end
			if not card then
				return nil, "no card"
			end
			card.id = arg
			card.here = other ~= nil and other ~= player and views[other] ~= nil
			card.mine = arg == player.UserId
			card.likes = meet:likesFor(player.UserId, { arg })[tostring(arg)]
			card.crew = crews:badge(arg)
			return card, nil
		elseif op == "join" and type(arg) == "number" then
			return join(player, arg)
		end
		return nil, "not a social action"
	end)
	if not ran then
		warn(`[Cartopia] {player.Name} social {op}: {result}`)
		return false, "error"
	end
	if result == nil then
		return false, why
	end
	return true, result
end

-- The gem and car packs: what's on sale, and buying one (Roblox's own prompt; ProcessReceipt pays).
bankRemote.OnServerInvoke = function(player: Player, op: any, id: any)
	if not towns:isOpen(player.UserId) then
		return false, "town not loaded"
	end
	if not allow(player) then
		return false, "slow down"
	end
	if op == "shop" then
		return true, purchases:shop(player.UserId)
	elseif op == "buy" then
		local product, why = purchases:canBuy(player.UserId, id)
		if not product then
			return false, why
		end
		-- The town is saved first, so whatever was just earned is safe before the prompt.
		task.spawn(save, player)
		MarketplaceService:PromptProductPurchase(player, product)
		return true, nil
	end
	return false, "unknown"
end

MarketplaceService.ProcessReceipt = function(info: any)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, result = pcall(purchases.process, purchases, info.PlayerId, info.ProductId, tostring(info.PurchaseId))
	if not ok then
		warn(`[Cartopia] receipt {info.PurchaseId} for {player.Name}: {result}`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if towns:isOpen(player.UserId) then
		push(player)
	end
	return if result == "granted" then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- The experience's Developer Products, matched to packs by name; looked up again every few minutes
-- so a product made while servers run goes on sale in them too.
task.spawn(function()
	while true do
		local ok, err = pcall(function()
			local list = {}
			local pages = MarketplaceService:GetDeveloperProductsAsync()
			while true do
				for _, d in pages:GetCurrentPage() do
					table.insert(list, { name = d.Name, product = d.ProductId, robux = d.PriceInRobux })
				end
				if pages.IsFinished then
					break
				end
				pages:AdvanceToNextPageAsync()
			end
			purchases:setProducts(list)
		end)
		if not ok then
			warn(`[Cartopia] reading the gem packs' products: {err}`)
		end
		task.wait(if ok then 600 else 60)
	end
end)

-- The admin panel (server/Admin): testing tools for Kegan's account only, checked here by user id.
local admin = Admin.new({
	towns = towns,
	store = require(Game.store),
	data = require(Game.data),
	visitors = visitors,
	player = function(userId: number): any
		return Players:GetPlayerByUserId(userId)
	end,
	players = function(): { any }
		return Players:GetPlayers()
	end,
	push = function(player: any, force: boolean?)
		push(player, force)
	end,
	save = function(player: any)
		save(player)
	end,
	hub = function(): CFrame
		return CFrame.new(0, 5, 160)
	end,
	plot = function(i: number): CFrame?
		return World.gate(i)
	end,
	plots = World.COUNT,
	rave = function(player: any): (boolean, string?)
		return Rave.go(player)
	end,
	stats = function(): { [string]: any }
		local Stats = game:GetService("Stats")
		return {
			memoryMb = math.floor(Stats:GetTotalMemoryUsageMb()),
			physicsFps = math.floor(workspace:GetRealPhysicsFPS()),
			heartbeatMs = math.floor(Stats.HeartbeatTimeMs * 10) / 10,
			uptime = math.floor(time()),
			players = #Players:GetPlayers(),
			instances = Stats.InstanceCount,
			version = game.PlaceVersion,
			job = if game.JobId == "" then "studio" else string.sub(game.JobId, 1, 8),
		}
	end,
	now = now,
	uid = function(): string
		return HttpService:GenerateGUID(false)
	end,
})
admin:start(Players)

-- The town clock: jobs finish, fuel refills, tasks roll over.
task.spawn(function()
	while true do
		task.wait(TICK)
		for _, player in Players:GetPlayers() do
			if towns:isOpen(player.UserId) then
				local ok, err = pcall(towns.tick, towns, player.UserId)
				if ok then
					push(player)
				else
					warn(`[Cartopia] tick {player.Name}: {err}`)
				end
			end
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(AUTOSAVE)
		for _, player in Players:GetPlayers() do
			task.spawn(save, player)
		end
	end
end)

game:BindToClose(function()
	local left = 0
	for _, player in Players:GetPlayers() do
		left += 1
		task.spawn(function()
			save(player, true)
			left -= 1
		end)
	end
	while left > 0 do
		task.wait()
	end
end)
