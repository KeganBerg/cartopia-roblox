--!nocheck
-- Draws the shared world (server/World) with a few towns claimed on it, as the server does, plus
-- a player driving their car (server/Drive), and writes the parts for tools/emulate/render.mjs:
--
--   lune run tools/emulate/world.luau build/place.rbxl
--
-- writes build/world.json (parts), build/world-claim-gui.json and -cam.json (the claim screen
-- seen from above) and build/world-drive-gui.json and -cam.json (driving between towns).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Gui = require("./gui")
local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local NOW = 1760000000000
emu.require(RS.Shared.Game.__js).setClock(function()
	return NOW
end)
local store = emu.require(RS.Shared.Game.store)
local Towns = emu.require(SSS.Server.Towns)
local TownView = emu.require(SSS.Server.TownView)
local World = emu.require(SSS.Server.World)
local Drive = emu.require(SSS.Server.Drive)
local Builder = emu.require(RS.Shared.Models.Builder)
if process.env.NO_MESHES == nil then
	Emu.fakeMeshPacks(emu)
	Builder.loadMeshes(1)
end

TownView.sharedGround = true
local world = World.build(game.Workspace, TownView.MEADOW, function(p)
	TownView.groundTexture(p, "meadow", Vector3.new(80, 0, 80))
end)
local towns = Towns.new(store, function()
	return NOW
end)
local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
-- Three neighbours on the first plots; one has built a few more things.
local names = { "Rosaville", "Milo Junction", "Sunny Hollow" }
for i = 0, 2 do
	local id = i + 1
	towns:open(id, nil)
	towns:run(id, "renameTown", names[id])
	if i == 1 then
		towns:_with(id, function(s)
			local save = towns:save(id)
			save.coins = 1e6
			save.level = 20
			s.loadSave(save)
		end)
		towns:run(id, "placeBuilding", "rescue", 12, 12)
	end
	local view = TownView.new(folder, `Player{id}`, World.origin(i), id, function() end)
	view:render(towns:save(id))
	World.setOwner(world, i, id, ({ "Rosa", "Milo", "Sunny" })[id])
end

-- A claimed plot's FREE PLOT sign is gone, words and all.
for _, d in world.Plots.Plot0:GetDescendants() do
	if d:IsA("SurfaceGui") then
		assert(not d.Enabled, "plot 0 is claimed but still says FREE PLOT")
	end
end

-- A player driving: an avatar stand-in with their car welded round it, on the road between the
-- hub and the first plots.
local character = Instance.new("Model")
character.Name = "Driver"
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.Transparency = 1
root.Parent = character
local humanoid = Instance.new("Humanoid")
humanoid.HipHeight = 2
humanoid.Parent = character
local start = World.gate(0)
-- On the ring road by Rosaville's gate, heading along it with the town on the left.
local at = start.Position + Vector3.new(-260, 3, 0)
root.CFrame = CFrame.lookAt(at, at + Vector3.new(1, 0, 0))
character.PrimaryPart = root
character.Parent = game.Workspace
local driver = Instance.new("Player")
driver.Name = "Driver"
driver.UserId = 9
pcall(function()
	driver.Character = character
end)
local car = Builder.build("pip", roblox.Color3.fromHex("#d6283b"))
local ok, err = pcall(Drive.set, driver, car)
if not ok then
	print("drive:", err)
end

-- The traffic and verges on the roads (client WorldLife), run for a while round the driver.
local WorldLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.WorldLife)
pcall(Builder.useLibrary, 1)
local stepRoads = WorldLife.attach(world)
local eye = root.CFrame.Position
for _ = 1, 30 * 20 do
	stepRoads(1 / 30, eye, nil)
end
local onRoad = 0
for _, m in WorldLife.cars() do
	onRoad += 1
end
print(`{onRoad} road cars in sight, {#game.Workspace.Verges:GetChildren()} verge stretches built`)

local parts = {}
for _, d in game.Workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		table.insert(parts, Gui.partOf(d))
	end
end
fs.writeFile("build/world.json", serde.encode("json", { parts = parts }))
print(`drew {#parts} parts on {World.COUNT} plots`)

-- Bubbles over the plots, as the claim screen shows them (Popups/Claim).
local bubbles = {}
for _, m in world.Plots:GetChildren() do
	local pad = m:FindFirstChild("Pad")
	local at = pad.CFrame.Position + Vector3.new(0, 30, 0)
	local text = if m:GetAttribute("Free") then "🏡 Claim" else `🏠 {m:GetAttribute("OwnerName")}`
	table.insert(bubbles, { at = { at.X, at.Y, at.Z }, text = text, size = { 130, 40 } })
end
local function cam(name, from, at, fov)
	fs.writeFile(`build/world-{name}-cam.json`, serde.encode("json", { from = { from.X, from.Y, from.Z }, at = { at.X, at.Y, at.Z }, fov = fov, far = 12000 }))
end
-- (serde writes an empty table as {}, so the empty node list is spelled out.)
fs.writeFile("build/world-claim-gui.json", '{"nodes":[],"bubbles":' .. serde.encode("json", bubbles) .. "}")
-- The town camera's angle (75, 80, 75), stood back to see the hub and the first ring.
local dir = Vector3.new(75, 80, 75).Unit
cam("claim", dir * 5200, Vector3.zero, 45)
-- Behind the car, as Roblox's follow camera sits.
local back = root.CFrame * CFrame.new(30, 45, 110)
-- Only what's near the car (as the game streams it in).
local near = {}
for _, p in parts do
	local dx, dz = p.cf[1] - root.CFrame.Position.X, p.cf[3] - root.CFrame.Position.Z
	if math.sqrt(dx * dx + dz * dz) < 1800 then
		table.insert(near, p)
	end
end
fs.writeFile("build/world-drive.json", serde.encode("json", { parts = near }))
cam("drive", back.Position, (root.CFrame * CFrame.new(-160, 0, -260)).Position, 70)
print("cameras written")
