--!nocheck
-- Draws a starter town with the game's own TownView and Builder (run in the emulator) and writes
-- every part it made to a JSON file, for tools/emulate/render.mjs to picture.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/town.luau build/place.rbxl build/town.json

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3 = roblox.Instance, roblox.Vector3

local place, out = process.args[1] or "build/place.rbxl", process.args[2] or "build/town.json"
local emu = Emu.load(place)
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")

local Js = emu.require(RS.Shared.Game.__js)
local NOW = 1760000000000
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
-- A busy town: a job running, one done, some new buildings and a bought car.
local save = towns:snapshot(1).save
local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
-- Meshes aren't uploaded here; render.mjs draws each from its geometry instead.
emu.require(RS.Shared.Models.Builder).previewMeshes = process.env.NO_MESHES == nil
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)
-- The countryside the client draws round the town.
local Countryside = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Countryside)
Countryside.draw(Vector3.new(0, 0, 0), folder)(save)

local Gui = require("./gui")
local parts = {}
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		table.insert(parts, Gui.partOf(d))
	end
end
fs.writeFile(out, serde.encode("json", { parts = parts, buildings = #save.buildings, cars = #save.cars }))
print(`drew {#parts} parts: {#save.buildings} buildings, {#save.roads} road tiles, {#save.cars} cars`)

-- The client: the HUD over this town, optionally with a screen open (process.args[4]).
local player = Instance.new("Player")
player.Name = "Player1"
player.UserId = 1
local playerGui = Instance.new("PlayerGui")
playerGui.Parent = player
local players = game:GetService("Players")
local okSet = pcall(function()
	players.LocalPlayer = player
end)
if not okSet or players.LocalPlayer ~= player then
	error("emulator: can't set Players.LocalPlayer")
end
player.Parent = players
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return NOW / 1000
end)
local remotes = Instance.new("Folder")
remotes.Name = "Cartopia"
local function make(class, name, parent)
	local i = Instance.new(class)
	i.Name = name
	i.Parent = parent
	return i
end
make("RemoteFunction", "Act", remotes)
make("RemoteEvent", "Town", remotes)
make("RemoteFunction", "Race", remotes)
remotes.Parent = RS
-- The model library the server makes for shop pictures.
local Builder = emu.require(RS.Shared.Models.Builder)
local data = emu.require(RS.Shared.Game.data)
local lib = Instance.new("Folder")
lib.Name = "ModelLibrary"
for _, kind in { "Cars", "Buildings" } do
	make("Folder", kind, lib)
end
for _, car in data.CARS do
	local m = Builder.build(car.id)
	if m then
		m.Name = car.id
		m.Parent = lib.Cars
	end
end
for _, def in data.BUILDINGS do
	local name = Builder.buildingName(def.id, 1)
	local m = name and Builder.build(name)
	if m then
		m.Name = def.id
		m.Parent = lib.Buildings
	end
end
lib.Parent = RS

local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local Remote = emu.require(client.Remote)
local snap = towns:snapshot(1)
store.useGame.getState().loadSave(snap.save)
Remote.last = snap
local hud = emu.require(client.Hud).start()
if process.args[4] then
	hud.openPanel(process.args[4])
end
local W, H = 1280, 800
local bubbles = {}
for _, b in playerGui:GetDescendants() do
	if b:IsA("BillboardGui") and b.Adornee then
		local label = b:FindFirstChildWhichIsA("TextLabel", true)
		local at = b.Adornee.CFrame.Position + b.StudsOffsetWorldSpace
		table.insert(bubbles, { at = { at.X, at.Y, at.Z }, text = label and label.Text or "", size = { b.Size.X.Offset, b.Size.Y.Offset } })
	end
end
fs.writeFile(process.args[3] or "build/gui.json", serde.encode("json", { nodes = Gui.dump(hud.gui, W, H), bubbles = bubbles }))
print(`screens laid out, {#bubbles} job bubbles`)
