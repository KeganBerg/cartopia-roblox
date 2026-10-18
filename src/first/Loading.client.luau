--!strict
-- Runs first on every client (ReplicatedFirst) and keeps the game covered (LoadingScreen) until
-- everything the player will see has arrived, so nobody sees the town pop in piece by piece:
--   1. the place itself (game.Loaded)
--   2. the server's 3D shapes (it sets ShapesLoaded / ShapesTotal on Workspace as they come in)
--   3. the player's own town, drawn by the server (their TownReady attribute), and the shop's
--      model library; or, in a new server, the shared world's hub where they pick a plot first
--      (NeedsPlot: their town is built once they've claimed one, see client/Popups/Claim)
--   4. the town's parts streamed to this client, and the countryside drawn round it
--   5. every mesh, texture and picture in view, downloaded (ContentProvider:PreloadAsync). Only
--      what's in view: the whole mesh library is thousands of meshes, most of them never seen
--      from the town, and waiting for all of it kept phones on this screen for minutes.
-- Then the player's car drives off and it fades away. If something never arrives it still lifts
-- after MAX seconds.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MAX = 120 -- seconds before the cover lifts whatever is still missing
local LABEL = "Loading your town…" -- the web's words; the bar shows how far along it is

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local LoadingScreen = require(script.Parent:WaitForChild("LoadingScreen"))
-- The server looks up each picture's own image id when the upload gave a decal's (see
-- server/Splash) and shares it as a Workspace attribute.
local screen = LoadingScreen.new(playerGui, {
	content = function(id: number): (string, boolean?)
		local image = workspace:GetAttribute(`Splash{id}`) :: string?
		if image then
			return image, true
		end
		return `rbxassetid://{id}`, false
	end,
})
ReplicatedFirst:RemoveDefaultLoadingScreen()
-- The server finds hundreds of them, often several a frame: the screen catches up once a frame.
local refreshing = false
workspace.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 6) == "Splash" and not refreshing then
		refreshing = true
		task.defer(function()
			refreshing = false
			screen:refreshImages()
		end)
	end
end)

-- The town's time of day, worked out as the web's loading screen does (from game/clock.ts: the
-- 20-minute day, eased), so the screen is right from its first frame.
do
	local m = (DateTime.now().UnixTimestampMillis % 1200000) / 1200000
	local d = math.abs(m + 0.05 * math.sin(2 * math.pi * m) - 0.5)
	local x = math.clamp((0.3 - d) / 0.2, 0, 1)
	local n = x * x * (3 - 2 * x)
	screen:setTime(if n > 0.7 then "night" elseif n > 0.08 then "dusk" else "day")
end

-- The player's race car, which the server names as soon as their save is open; the Hot Shot if
-- it hasn't after a few seconds.
local function useCar()
	screen:setCar(player:GetAttribute("SplashCar") :: string?, player:GetAttribute("SplashPaint") :: string?)
end
player:GetAttributeChangedSignal("SplashCar"):Connect(useCar)
task.delay(4, function()
	if not screen.model then
		useCar()
	end
end)
if player:GetAttribute("SplashCar") then
	useCar()
end
-- Its own pictures first, so they're up while everything else loads.
task.spawn(function()
	pcall(ContentProvider.PreloadAsync, ContentProvider, screen:images())
end)

-- The player's character waits, anchored, while their town streams in round it: with no ground
-- under it yet it fell through to the place's base block, a few studs down, and stood in a pit.
local holding = true
local function hold(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if root and holding then
		root.Anchored = true
	end
end
local holdConn = player.CharacterAdded:Connect(hold)
if player.Character then
	task.spawn(hold, player.Character)
end

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

-- 1. The place.
screen:set(LABEL, 0.02)
if not game:IsLoaded() then
	game.Loaded:Wait()
end

-- 2. The 3D shapes, which the server loads once when it starts.
screen:set(LABEL, 0.05)
waitFor(function()
	local total = workspace:GetAttribute("ShapesTotal") :: number?
	local done = workspace:GetAttribute("ShapesLoaded") :: number?
	if total and done and total > 0 then
		screen:set(LABEL, 0.05 + 0.4 * done / total)
	end
	return workspace:GetAttribute("ShapesReady") == true
end)

-- 3. The player's town.
screen:set(LABEL, 0.45)
waitFor(function()
	-- And the server's model library, which the shop's pictures are drawn from.
	return (player:GetAttribute("TownReady") == true or player:GetAttribute("NeedsPlot") == true) and ReplicatedStorage:FindFirstChild("ModelLibrary") ~= nil
end)
local picking = player:GetAttribute("TownReady") ~= true

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
	return picking or myTown() ~= nil
end)

-- 4. Its parts streamed in round its middle, and the countryside round it.
screen:set(LABEL, 0.5)
local town = myTown()
local origin = if town then town:GetAttribute("Origin") :: Vector3? elseif picking then Vector3.zero else nil
if origin and workspace.StreamingEnabled then
	pcall(player.RequestStreamAroundAsync, player, origin, math.max(1, math.min(30, timeLeft())))
end
screen:set(LABEL, 0.55)
waitFor(function()
	local c = workspace:FindFirstChild("Countryside")
	return picking or (c ~= nil and c:GetAttribute("Drawn") == true)
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
contentOf(playerGui, wanted)
local list: { string } = {}
for id in wanted do
	table.insert(list, id)
end
local total, done = #list, 0
screen:set(LABEL, 0.6)
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
					screen:set(LABEL, 0.6 + 0.38 * done / total)
				end)
				running -= 1
			end)
		end
	end
	waitFor(function()
		return running == 0
	end)
end

-- A couple of frames so the first drawn frame has everything, then the car drives off.
for _ = 1, 3 do
	RunService.RenderStepped:Wait()
end
if timeLeft() <= 0 then
	warn("[Cartopia] Still loading after " .. MAX .. " seconds; showing the game anyway.")
end
-- Let the character go, standing on whatever is under it now.
holding = false
holdConn:Disconnect()
do
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and root then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(root.Position + Vector3.new(0, 4, 0), Vector3.new(0, -100, 0), params)
		if hit and humanoid then
			local up = humanoid.HipHeight + root.Size.Y / 2 + 0.1
			character:PivotTo(CFrame.new(hit.Position + Vector3.new(0, up, 0)) * root.CFrame.Rotation)
		end
		root.Anchored = false
	end
end
screen:finish()
spin:Disconnect()
