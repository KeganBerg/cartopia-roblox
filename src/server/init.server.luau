-- Server entry point. The server owns the economy: every town runs on the server (Towns), saves
-- go to a DataStore with session locking (Saves), and clients only ask for changes through the
-- Cartopia.Act remote, which the server checks before running.
--
-- Remotes (in ReplicatedStorage.Cartopia):
--   Act    RemoteFunction  client -> server: (action, ...args) -> ok, result or error text
--   Town   RemoteEvent     server -> client: { save, need, panel, toasts } after every change

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local Js = require(Game.__js)

-- Millisecond clock, so day keys, seasons and events match the web game to the second.
local function now(): number
	return DateTime.now().UnixTimestampMillis
end
Js.setClock(now)

local Saves = require(script.Saves)
local Towns = require(script.Towns)

local AUTOSAVE = 5 * 60 -- seconds; well inside Saves.LOCK_TTL
local TICK = 1 -- seconds between town clock ticks, as on the web

local saves = Saves.new({
	store = DataStoreService:GetDataStore("Towns_v1"),
	job = if RunService:IsStudio() then "studio" else game.JobId,
	now = os.time,
})
local towns = Towns.new(require(Game.store), now)

local remotes = Instance.new("Folder")
remotes.Name = "Cartopia"
local act = Instance.new("RemoteFunction")
act.Name = "Act"
act.Parent = remotes
local townEvent = Instance.new("RemoteEvent")
townEvent.Name = "Town"
townEvent.Parent = remotes
remotes.Parent = ReplicatedStorage

-- Last save sent to each player, so ticks that change nothing send nothing.
local sent: { [Player]: string } = {}

local function push(player: Player, force: boolean?)
	local snap = towns:snapshot(player.UserId)
	local key = HttpService:JSONEncode(snap.save)
	if force or #snap.toasts > 0 or sent[player] ~= key then
		sent[player] = key
		townEvent:FireClient(player, snap)
	end
end

local function save(player: Player, release: boolean?)
	if towns:isOpen(player.UserId) and saves:holds(player.UserId) then
		saves:write(player.UserId, towns:save(player.UserId), release)
	end
end

Players.PlayerAdded:Connect(function(player)
	local ok, data = pcall(saves.load, saves, player.UserId)
	if not ok then
		warn(`[Cartopia] {data}`)
		player:Kick("Your town is still open on another server. Please try again in a minute.")
		return
	end
	if not player.Parent then -- left while loading: just let the lock go
		saves:write(player.UserId, data, true)
		return
	end
	towns:open(player.UserId, data)
	push(player, true)
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
	save(player, true)
	towns:close(player.UserId)
	sent[player] = nil
	budget[player] = nil
end)

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
	local ran, result = pcall(towns.run, towns, player.UserId, name, table.unpack(args, 1, args.n))
	if not ran then
		warn(`[Cartopia] {player.Name} {name}: {result}`)
		return false, "error"
	end
	push(player)
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
