-- Server entry point. The server owns the economy: every town runs on the server (Towns), saves
-- go to a DataStore with session locking (Saves), and clients only ask for changes through the
-- Cartopia.Act remote, which the server checks before running.
--
-- Remotes (in ReplicatedStorage.Cartopia):
--   Act    RemoteFunction  client -> server: (action, ...args) -> ok, result or error text
--   Town   RemoteEvent     server -> client: { save, need, panel, toasts } after every change
--   Race   RemoteFunction  client -> server: ("rivals" | "campaign" | "start" | "finish", ...)
--                          -> ok, result or error text (see Races)
--   Crate  RemoteFunction  client -> server: (crate id, free source?, count) -> ok, the opens or why
--   Meshes RemoteFunction  client -> server: (car id) -> loads that car's mod meshes into
--                          ReplicatedStorage.MeshLibrary, answering once they're in
--   Social RemoteFunction  client -> server: ("players" | "visit" | "home" | "help" | "join", arg)
--                          -> ok, result or error text: playing together (see Social)
--
-- Each player's town is drawn in Workspace.Towns (TownView) on its own lot, from the web game's
-- own models (Shared.Models), and redrawn whenever it changes.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
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
local Boards = require(script.Boards)
local Crates = require(script.Crates)
local Policies = require(script.Policies)
local Policy = require(ReplicatedStorage.Shared.Policy)
local Splash = require(script.Splash)
local Social = require(script.Social)
local World = require(script.World)
local Drive = require(script.Drive)
local Builder = require(ReplicatedStorage.Shared.Models.Builder)

local AUTOSAVE = 5 * 60 -- seconds; well inside Saves.LOCK_TTL
local TICK = 1 -- seconds between town clock ticks, as on the web

local saves = Saves.new({
	store = DataStoreService:GetDataStore("Towns_v1"),
	job = if RunService:IsStudio() then "studio" else game.JobId,
	now = os.time,
})
local towns = Towns.new(require(Game.store), now)
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

local remotes = Instance.new("Folder")
remotes.Name = "Cartopia"
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
local meshRemote = Instance.new("RemoteFunction")
meshRemote.Name = "Meshes"
meshRemote.Parent = remotes
local socialRemote = Instance.new("RemoteFunction")
socialRemote.Name = "Social"
socialRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

Splash.start()

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
end)
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
	if force or #snap.toasts > 0 or snap.panel ~= nil or snap.need ~= nil or sent[player] ~= key then
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

-- Players on their way to a friend's server (Social "join"): their save is already written.
local leaving: { [Player]: boolean } = {}

-- Lending a hand at a business in the town a player is visiting (server/Social).
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

local function save(player: Player, release: boolean?)
	if towns:isOpen(player.UserId) and saves:holds(player.UserId) then
		saves:write(player.UserId, towns:save(player.UserId), release)
	end
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(policies.load, policies, player)
	-- Whether Roblox lets this player chat: the HUD's CHAT button only shows when it does.
	task.spawn(function()
		local ok, can = pcall(TextChatService.CanUserChatAsync, TextChatService, player.UserId)
		player:SetAttribute("CanChat", ok and can == true)
	end)
	local ok, data = pcall(saves.load, saves, player.UserId)
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
	towns:open(player.UserId, data)
	-- Their own race car on their loading screen.
	pcall(function()
		local save = towns:snapshot(player.UserId).save
		local car = (require(Game.raceCar) :: any).raceCarOf(save.cars or {}, save.raceCar)
		Splash.forPlayer(player, car and car.model, car and car.color)
	end)
	local start = os.clock()
	while not meshesReady and os.clock() - start < 45 do
		task.wait(0.2)
	end
	if not player.Parent then
		return
	end
	push(player, true)
	-- They pick a plot first (the claim screen, Popups/Claim); the loading screen lifts for it.
	player:SetAttribute("NeedsPlot", true)
	spawnAt(player)
	player.CharacterAdded:Connect(function()
		task.wait()
		spawnAt(player)
	end)
end)

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
	save(player, true)
	towns:close(player.UserId)
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
		end
		return nil, "not a race"
	end)
	if not ran then
		warn(`[Cartopia] {player.Name} race {op}: {result}`)
		return false, "error"
	end
	if op == "start" or op == "finish" or op == "act" then
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
