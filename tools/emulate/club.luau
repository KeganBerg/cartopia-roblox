--!nocheck
-- Previews the nightclub at night (client/ClubLife) and a thought bubble (client/Thought): a
-- starter town given a club, drawn by the server's TownView, with the townspeople (TownLife) and the
-- club's dancers, bouncer and searchlights run for a while on the client after dark, and a tap on
-- someone in the club's line. Writes build/shot-club.json, build/shot-club-gui.json and
-- build/shot-club-{town,door,roof}-cam.json for render.mjs.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/club.luau build/place.rbxl
--   CHROMIUM=... node tools/emulate/render.mjs <web> build/shot-club.json out.png \
--     build/shot-club-gui.json "$(cat build/shot-club-door-cam.json)"
--
-- LEVEL=<n> picks the club's level (6 by default), RUN_FOR=<s> how long the night has run (90).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3, Enum = roblox.Instance, roblox.Vector3, roblox.Enum

local place = process.args[1] or "build/place.rbxl"
local emu = Emu.load(place)
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local Js = emu.require(RS.Shared.Game.__js)
local clock = emu.require(RS.Shared.Game.clock)
-- The middle of a night: the club's open and it's dark.
local NOW = 1760000000000
while not (clock.isNight(NOW) and clock.nightAmount(clock.dayPhase(NOW)) > 0.95) do
	NOW += 10000
end
Js.setClock(function()
	return NOW
end)
local store = emu.require(RS.Shared.Game.store)
local Towns = emu.require(SSS.Server.Towns)
local TownView = emu.require(SSS.Server.TownView)

local towns = Towns.new(store, function()
	return NOW
end)
towns:open(1, nil)
towns:_with(1, function()
	store.useGame.setState({ coins = 100000000, level = 40 })
end)
-- The club (2x1) somewhere on a road.
local placed = nil
for _, at in { { 12, 12 }, { 16, 4 }, { 4, 16 }, { 20, 12 }, { 12, 20 }, { 8, 8 }, { 16, 16 }, { -8, 12 }, { 12, -8 } } do
	local before = #towns:snapshot(1).save.buildings
	towns:run(1, "placeBuilding", "club", at[1], at[2])
	local after = towns:snapshot(1).save.buildings
	if #after > before then
		placed = after[#after]
		break
	end
end
assert(placed, "no room for the club")
local level = tonumber(process.env.LEVEL or "") or 6
local save = towns:snapshot(1).save
for _, b in save.buildings do
	if b.uid == placed.uid then
		b.level = level
	end
end

local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
if process.env.NO_MESHES == nil then
	Emu.fakeMeshPacks(emu)
	emu.require(RS.Shared.Models.Builder).loadMeshes(1)
end
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)

-- The client: a player and their PlayerGui (for the thought bubble).
local player = Instance.new("Player")
player.Name = "Player1"
player.UserId = 1
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = player
local players = game:GetService("Players")
players.LocalPlayer = player
player.Parent = players
local screen = Instance.new("ScreenGui")
screen.Parent = playerGui

local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local TownLife = emu.require(client.TownLife)
local ClubLife = emu.require(client.ClubLife)
local update, step = TownLife.attach(view.folder)
update(save)
local scan, clubStep = ClubLife.attach(view.folder, game.Workspace)
scan()
local seconds = tonumber(process.env.RUN_FOR or "") or 90
for _ = 1, math.floor(seconds * 30) do
	NOW += 1000 / 30
	step(1 / 30)
	clubStep(1 / 30)
end

local model = view.folder.Buildings:FindFirstChild(placed.uid)
assert(model, "no club model drawn")
local q = TownLife._queues[`b{placed.uid}`] or {}
local out = 0
for _, f in game.Workspace.Townspeople:GetChildren() do
	local any = f:FindFirstChildWhichIsA("BasePart")
	if any and any.CFrame.Position.Y > -100 then
		out += 1
	end
end
print(`club level {level} at {placed.x},{placed.z}: {#q} in line, {out} townspeople out`)

-- Tap someone: the one at the front of the line if there is a line, else whoever's out.
local Thought = emu.require(client.Thought)
local who = q[1]
if not who then
	for _, f in game.Workspace.Townspeople:GetChildren() do
		local any = f:FindFirstChildWhichIsA("BasePart")
		if any and any.CFrame.Position.Y > -100 then
			who = { id = f.Name }
			break
		end
	end
end
local head = nil
if who then
	local fig = game.Workspace.Townspeople:FindFirstChild(who.id)
	-- The head: the biggest ball on it.
	for _, d in fig:GetChildren() do
		if d:IsA("Part") and d.Shape == Enum.PartType.Ball and (not head or d.Size.X > head.Size.X) then
			head = d
		end
	end
end
if who and who.dest then
	local where, there = TownLife._whereOf(who)
	Thought.show(who.id, head, where, there, TownLife._thoughtOf(who), true)
	print(`thought: [{where}] {TownLife._thoughtOf(who)}`)
end

local Gui = require("./gui")
local parts = {}
for _, d in game.Workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 and d.CFrame.Position.Y > -100 then
		table.insert(parts, Gui.partOf(d))
	end
end
fs.writeFile("build/shot-club.json", serde.encode("json", { parts = parts }))
fs.writeFile("build/shot-club-gui.json", serde.encode("json", { nodes = Gui.dump(screen, 1280, 800) }))

local hit = model:FindFirstChild("Hit")
local middle = hit.CFrame.Position - Vector3.new(0, hit.Size.Y / 2, 0)
local turn = model:GetAttribute("Turn") or 0
local function local_(x, y, z)
	local a = turn * math.pi / 2
	return middle + Vector3.new(x * math.cos(a) + z * math.sin(a), y, -x * math.sin(a) + z * math.cos(a))
end
local function cam(name, from, at, fov)
	fs.writeFile(`build/shot-club-{name}-cam.json`, serde.encode("json", { from = { from.X, from.Y, from.Z }, at = { at.X, at.Y, at.Z }, fov = fov }))
end
cam("town", middle + Vector3.new(75, 80, 75).Unit * 260, middle, 30)
cam("door", local_(2, 9, 40), local_(-5, 4, 6), 50)
cam("roof", local_(0, 40, 30), local_(0, 16, -2), 50)
if head then
	cam("face", head.CFrame.Position + Vector3.new(0, 1, 0) + (local_(0, 0, 14) - middle), head.CFrame.Position, 50)
end
print(`wrote build/shot-club.json ({#parts} parts)`)
