-- Server entry point. The server owns the economy: every town runs on the server (Towns), saves
-- go to a DataStore with session locking (Saves), and clients only ask for changes through the
-- Cartopia.Act remote, which the server checks before running.
--
-- Remotes (in ReplicatedStorage.Cartopia):
--   Act    RemoteFunction  client -> server: (action, ...args) -> ok, result or error text
--   Town   RemoteEvent     server -> client: { save, need, panel, toasts } after every change
--   Race   RemoteFunction  client -> server: ("rivals" | "campaign" | "start" | "finish", ...)
--                          -> ok, result or error text (see Races)
--   Crate  RemoteFunction  client -> server: (crate id, free source?, count) -> ok, the opens or why;
--                          ("wheel") spins the Daily Spin -> ok, the spin { slice, open } or why
--   Arcade RemoteFunction  client -> server: ("state" | "start" | "submit" | "board" | "prizes" |
--                          "claim", ...) -> ok, result or why (see Arcade)
--   Bank   RemoteFunction  client -> server: ("shop") -> the gem and car packs on sale, or
--                          ("buy", pack id) -> ok, or why not; opens Roblox's purchase prompt
--   Meshes RemoteFunction  client -> server: (car id) -> loads that car's mod meshes into
--                          ReplicatedStorage.MeshLibrary, answering once they're in
--
-- Each player's town is drawn in Workspace.Towns (TownView) on its own lot, from the web game's
-- own models (Shared.Models), and redrawn whenever it changes.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local Ghosts = require(script.Ghosts)
local Crates = require(script.Crates)
local Arcade = require(script.Arcade)
local Policies = require(script.Policies)
local Purchases = require(script.Purchases)
local Policy = require(ReplicatedStorage.Shared.Policy)
local Splash = require(script.Splash)
local Sky = require(script.Sky)
local Builder = require(ReplicatedStorage.Shared.Models.Builder)

local AUTOSAVE = 5 * 60 -- seconds; well inside Saves.LOCK_TTL
local TICK = 1 -- seconds between town clock ticks, as on the web

local saves = Saves.new({
	store = DataStoreService:GetDataStore("Towns_v1"),
	job = if RunService:IsStudio() then "studio" else game.JobId,
	now = os.time,
})
local towns = Towns.new(require(Game.store), now)
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
	ghosts = ghosts,
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
local arcadeRemote = Instance.new("RemoteFunction")
arcadeRemote.Name = "Arcade"
arcadeRemote.Parent = remotes
local bankRemote = Instance.new("RemoteFunction")
bankRemote.Name = "Bank"
bankRemote.Parent = remotes
local meshRemote = Instance.new("RemoteFunction")
meshRemote.Name = "Meshes"
meshRemote.Parent = remotes
remotes.Parent = ReplicatedStorage

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

-- Every town gets its own lot, in a grid LOT studs apart; the first is at the spawn. Far enough
-- apart that one town's countryside (out to 2,000 studs, see client/Countryside) never reaches the
-- next town.
local LOT = 4500
local views: { [Player]: any } = {}
local slots: { [number]: Player } = {}

local function takeSlot(player: Player): number
	local i = 0
	while slots[i] do
		i += 1
	end
	slots[i] = player
	return i
end

local function lotOrigin(i: number): Vector3
	return Vector3.new((i % 4) * LOT, 0, (i // 4) * LOT)
end

-- Where a player stands in their town: the cross street in the middle of the starter town.
local function spawnAt(player: Player)
	local view = views[player]
	local character = player.Character
	if view and character then
		character:PivotTo(CFrame.new(view:tileToWorld(11.5, 11) + Vector3.new(0, 5, 0)))
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

Players.PlayerAdded:Connect(function(player)
	task.spawn(policies.load, policies, player)
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
	towns:open(player.UserId, data)
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
	local start = os.clock()
	while not meshesReady and os.clock() - start < 45 do
		task.wait(0.2)
	end
	if not player.Parent then
		return
	end
	local slot = takeSlot(player)
	views[player] = TownView.new(townsFolder, player.Name, lotOrigin(slot), player.UserId, function(uid)
		tap(player, uid)
	end)
	player:SetAttribute("TownSlot", slot)
	push(player, true)
	spawnAt(player)
	-- The town is drawn: the player's loading screen can wait for it to stream in and lift.
	player:SetAttribute("TownReady", true)
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
	arcade:close(player.UserId)
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
		end
	end
	sent[player] = nil
	budget[player] = nil
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
	if not towns:isOpen(player.UserId) then
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
