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
-- RUSTY=ready|working|find: Rusty's Rescue in the town, its bay in that state, for its badge.
local rusty = process.env.RUSTY
if rusty then
	towns:_with(1, function()
		store.useGame.setState({ coins = 1000000, level = 30 })
	end)
	local placed = false
	for _, at in { { 12, 12 }, { 16, 4 }, { 4, 16 }, { 20, 12 }, { 12, 20 }, { -8, 12 }, { 12, -8 } } do
		local before = #towns:snapshot(1).save.buildings
		towns:run(1, "placeBuilding", "rescue", at[1], at[2])
		if #towns:snapshot(1).save.buildings > before then
			placed = true
			break
		end
	end
	assert(placed, "no room for Rusty's")
	towns:_with(1, function()
		local r = if rusty == "find" then nil else { uid = "r1", model = "bug", rarity = "common", minutes = 5, endsAt = if rusty == "ready" then NOW - 1 else NOW + 200000 }
		store.useGame.setState({ restoring = r })
	end)
end
-- A busy town: a job running, one done, some new buildings and a bought car.
local save = towns:snapshot(1).save
local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
-- The uploaded mesh packs, loaded the way the server does (InsertService stand-in: see
-- Emu.fakeMeshPacks); render.mjs draws each from its geometry. NO_MESHES=1 previews the boxes the
-- game shows before a pack is uploaded.
if process.env.NO_MESHES == nil then
	Emu.fakeMeshPacks(emu)
	emu.require(RS.Shared.Models.Builder).loadMeshes(1)
end
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)
-- The countryside the client draws round the town.
local Countryside = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Countryside)
if process.env.NO_MESHES == nil then
	-- Lune's instances have no ChildAdded, which useLibrary connects last: the meshes are in by then.
	pcall(emu.require(RS.Shared.Models.Builder).useLibrary, 1)
end
Countryside.draw(Vector3.new(0, 0, 0), folder)(save)
-- HORIZON=<sky step>: the far land and the sky (client Horizon) as well, at that step of the day
-- (1 is noon; see Shared.Models.SkyImages). Written to the JSON as sky and fog for render.mjs.
-- HORIZON_T=<seconds> moves the rotors and balloons on that far.
local skyStep = tonumber(process.env.HORIZON or "")
local sky, fog = nil, nil
if skyStep then
	local Builder = emu.require(RS.Shared.Models.Builder)
	if process.env.NO_MESHES == nil then
		Builder.loadLate()
		pcall(Builder.useLibrary, 1)
	end
	local Horizon = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.Horizon)
	Horizon.draw(Vector3.new(0, 0, 0), folder)
	-- The turning rotors and the balloons, HORIZON_T seconds after they appeared.
	local t = tonumber(process.env.HORIZON_T or "") or 0
	Horizon.movers(Vector3.new(0, 0, 0), folder)(1 / 30, t)
	local SkyImages = emu.require(RS.Shared.Models.SkyImages)
	local step = SkyImages.steps[skyStep]
	sky = { step = skyStep - 1, season = SkyImages.SEASON }
	-- The web game's far fog (Horizon.tsx FarFog: 170 to 1,820 units), in the sky's horizon colour.
	fog = { color = string.sub(step.haze, 2), start = 1700, ["end"] = 18200 }
end
-- LIFE=<seconds>: the town's traffic and townspeople (client TownLife), run that long.
local life = tonumber(process.env.LIFE or "")
if life then
	local TownLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.TownLife)
	local update, step = TownLife.attach(view.folder)
	update(save)
	for _ = 1, math.floor(life * 30) do
		step(1 / 30)
	end
	local walking, cars = 0, 0
	for _, f in game.Workspace.Townspeople:GetChildren() do
		local any = f:FindFirstChildWhichIsA("BasePart")
		if any and any.CFrame.Position.Y > -100 then
			walking += 1
		end
	end
	TownLife._traffic.agents:forEach(function(_, a, uid)
		cars += 1
		print(`  {uid} at {math.floor(a.x * 10)}, {math.floor(a.z * 10)} studs, speed {math.floor(a.v * 100) / 100}, shown {a.show}`)
	end)
	for _, m in view.folder.Cars:GetChildren() do
		print(`  model {m.Name} pivot {m:GetPivot().Position} scale {m:GetScale()}`)
	end
	print(`after {life}s: {cars} cars driving, {walking} of {#game.Workspace.Townspeople:GetChildren()} townspeople out`)
end

local Gui = require("./gui")
local parts = {}
-- The place file's own parts too (Workspace.Ground), which once sat over the whole town, and what
-- TownLife adds (townspeople, traffic lights).
for _, d in game.Workspace:GetChildren() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		table.insert(parts, Gui.partOf(d))
	end
end
for _, name in { "Townspeople", "TrafficSignals" } do
	local f = game.Workspace:FindFirstChild(name)
	for _, d in if f then f:GetDescendants() else {} do
		if d:IsA("BasePart") and d.Transparency < 1 and d.CFrame.Position.Y > -100 then
			table.insert(parts, Gui.partOf(d))
		end
	end
end
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		table.insert(parts, Gui.partOf(d))
	end
end
fs.writeFile(out, serde.encode("json", { parts = parts, buildings = #save.buildings, cars = #save.cars, sky = sky, fog = fog }))
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
make("RemoteFunction", "Crate", remotes)
make("RemoteFunction", "Meshes", remotes)
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
emu.require(client.RescueBadge).start(playerGui)
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
