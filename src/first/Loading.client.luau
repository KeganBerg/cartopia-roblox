--!strict
-- Runs first on every client (ReplicatedFirst) and keeps the game covered (LoadingScreen) until
-- everything the player will see has arrived, so nobody sees the town pop in piece by piece:
--   1. the place itself (game.Loaded)
--   2. the server's 3D shapes (it sets ShapesLoaded / ShapesTotal on Workspace as they come in)
--   3. the player's own town, drawn by the server (their TownReady attribute), and the shop's
--      model library
--   4. the town's parts streamed to this client, and the countryside drawn round it
--   5. every mesh, texture and picture in view, downloaded (ContentProvider:PreloadAsync)
-- Then it fades away. If something never arrives it still lifts after MAX seconds.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MAX = 120 -- seconds before the cover lifts whatever is still missing

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local LoadingScreen = require(script.Parent:WaitForChild("LoadingScreen"))
local screen = LoadingScreen.new(playerGui)
ReplicatedFirst:RemoveDefaultLoadingScreen()

local started = os.clock()
local spin = RunService.RenderStepped:Connect(function(dt)
	screen:step(dt)
end)

local function timeLeft(): number
	return MAX - (os.clock() - started)
end

-- Waits until check() is true (polling, as the attributes it reads come from the server).
local function waitFor(check: () -> boolean)
	while not check() and timeLeft() > 0 do
		task.wait(0.1)
	end
end

-- The sky's colours for the town's time of day, once the shared game code has replicated.
task.spawn(function()
	local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
	local ok, tod = pcall(function()
		local Js = require(Game:WaitForChild("__js")) :: any
		Js.setClock(function()
			return DateTime.now().UnixTimestampMillis
		end)
		local clock = require(Game:WaitForChild("clock")) :: any
		local n = clock.nightAmount(clock.dayPhase())
		return if n > 0.7 then "night" elseif n > 0.08 then "dusk" else "day"
	end)
	if ok then
		screen:tint(tod)
	end
end)

-- 1. The place.
screen:set("Loading", 0.02)
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- 2. The 3D shapes, which the server loads once when it starts.
screen:set("Unpacking the cars and buildings", 0.05)
waitFor(function()
	local total = workspace:GetAttribute("ShapesTotal") :: number?
	local done = workspace:GetAttribute("ShapesLoaded") :: number?
	if total and done and total > 0 then
		screen:set("Unpacking the cars and buildings", 0.05 + 0.4 * done / total)
	end
	return workspace:GetAttribute("ShapesReady") == true
end)

-- 3. The player's town.
screen:set("Building your town", 0.45)
waitFor(function()
	-- And the server's model library, which the shop's pictures are drawn from.
	return player:GetAttribute("TownReady") == true and ReplicatedStorage:FindFirstChild("ModelLibrary") ~= nil
end)

local function myTown(): Instance?
	local towns = workspace:FindFirstChild("Towns")
	if towns then
		for _, f in towns:GetChildren() do
			if f:GetAttribute("Owner") == player.UserId then
				return f
			end
		end
	end
	return nil
end
waitFor(function()
	return myTown() ~= nil
end)

-- 4. Its parts streamed in round its middle, and the countryside round it.
screen:set("Building your town", 0.5)
local town = myTown()
local origin = if town then town:GetAttribute("Origin") :: Vector3? else nil
if origin and workspace.StreamingEnabled then
	pcall(player.RequestStreamAroundAsync, player, origin, math.max(1, math.min(30, timeLeft())))
end
screen:set("Planting the countryside", 0.55)
waitFor(function()
	local c = workspace:FindFirstChild("Countryside")
	return c ~= nil and c:GetAttribute("Drawn") == true
end)

-- 5. Every mesh, texture and picture in them, downloaded together.
local function contentOf(root: Instance?, into: { [string]: boolean })
	if not root then
		return
	end
	for _, d in root:GetDescendants() do
		local ids: { string } = {}
		if d:IsA("MeshPart") then
			ids = { d.MeshId, d.TextureID }
		elseif d:IsA("Decal") then -- Textures too
			ids = { d.Texture }
		elseif d:IsA("ImageLabel") or d:IsA("ImageButton") then
			ids = { d.Image }
		elseif d:IsA("SpecialMesh") then
			ids = { d.MeshId, d.TextureId }
		end
		for _, id in ids do
			if id ~= "" then
				into[id] = true
			end
		end
	end
end
local wanted: { [string]: boolean } = {}
contentOf(myTown(), wanted)
contentOf(workspace:FindFirstChild("Countryside"), wanted)
contentOf(ReplicatedStorage:FindFirstChild("MeshLibrary"), wanted)
contentOf(playerGui, wanted)
local list: { string } = {}
for id in wanted do
	table.insert(list, id)
end
local total, done = #list, 0
screen:set("Painting the town", 0.6)
if total > 0 then
	-- In a few batches at once, so one slow download doesn't hold up the rest.
	local BATCHES = 8
	local running = 0
	for b = 1, BATCHES do
		local batch = {}
		for i = b, total, BATCHES do
			table.insert(batch, list[i])
		end
		if #batch > 0 then
			running += 1
			task.spawn(function()
				pcall(ContentProvider.PreloadAsync, ContentProvider, batch, function()
					done += 1
					screen:set("Painting the town", 0.6 + 0.38 * done / total)
				end)
				running -= 1
			end)
		end
	end
	waitFor(function()
		return running == 0
	end)
end

-- A couple of frames so the first drawn frame has everything, then fade out.
screen:set("Here we go", 1)
for _ = 1, 3 do
	RunService.RenderStepped:Wait()
end
if timeLeft() <= 0 then
	warn("[Cartopia] Still loading after " .. MAX .. " seconds; showing the game anyway.")
end
local fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
for _, d in screen.gui:GetDescendants() do
	if d:IsA("Frame") or d:IsA("TextButton") then
		TweenService:Create(d, fade, { BackgroundTransparency = 1 }):Play()
	end
	if d:IsA("TextLabel") or d:IsA("TextButton") then
		TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
	end
	if d:IsA("UIStroke") then
		TweenService:Create(d, fade, { Transparency = 1 }):Play()
	end
end
task.wait(0.5)
spin:Disconnect()
screen.gui:Destroy()
