--!nocheck
-- Previews the Speedway's life (client/SpeedwayLife): a starter town given a Speedway at level 8
-- (upper deck and all), drawn by the server's TownView, with the race and the crowd run for a few
-- seconds on the client. Writes build/shot-speedway-{town,close}.json and -cam.json for render.mjs.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/speedway.luau build/place.rbxl
--   CHROMIUM=... SIZE=390x844 node tools/emulate/render.mjs <web> build/shot-speedway-town.json \
--     out.png "" "$(cat build/shot-speedway-town-cam.json)"
--
-- LEVEL=<n> picks the Speedway's level (8 by default), RUN_FOR=<s> how long the race has run.

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

local place = process.args[1] or "build/place.rbxl"
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
local save = towns:snapshot(1).save
-- The Speedway (2x2) in the middle of town, by the pizza places.
local level = tonumber(process.env.LEVEL or "") or 8
table.insert(save.buildings, { uid = "speedway", def = "stadium", x = 11, z = 13, level = level })

local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
if process.env.NO_MESHES == nil then
	Emu.fakeMeshPacks(emu)
	emu.require(RS.Shared.Models.Builder).loadMeshes(1)
end
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)

-- The race and crowd, run for RUN_FOR (2.4 by default: cars part way round, fans cheering them).
local SpeedwayLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.SpeedwayLife)
local scan, step = SpeedwayLife.attach(view.folder, game.Workspace)
scan()
local seconds = tonumber(process.env.RUN_FOR or "") or 2.4
for _ = 1, math.floor(seconds * 60) do
	step(1 / 60)
end

local model = view.folder.Buildings:FindFirstChild("speedway")
assert(model, "no Speedway model drawn")
local life = game.Workspace.Speedways:GetChildren()[1]
assert(life, "no SpeedwayLife drawn")
local shown = 0
for _, d in life:GetDescendants() do
	if d:IsA("BasePart") and d.CFrame.Position.Y > -100 then
		shown += 1
	end
end
-- Arms hang along their own -y: a raised one's up points down.
local raised = 0
for _, d in life:GetChildren() do
	if d:IsA("BasePart") and d:FindFirstChildOfClass("SpecialMesh") and d.Size.Y > d.Size.X * 3 and d.CFrame.UpVector.Y < 0 then
		raised += 1
	end
end
print(`Speedway level {level}: {#life:GetChildren()} parts of race and crowd, {shown} in place, {raised} arms up`)

local Gui = require("./gui")
local parts = {}
for _, d in game.Workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 and d.CFrame.Position.Y > -100 then
		table.insert(parts, Gui.partOf(d))
	end
end
fs.writeFile("build/shot-speedway.json", serde.encode("json", { parts = parts }))

-- Cameras: the town view (TownCamera's angle and zoom at 390x844) over the Speedway, and close up.
local hit = model:FindFirstChild("Hit")
local middle = hit.CFrame.Position - Vector3.new(0, hit.Size.Y / 2, 0)
local function cam(name, from, at, fov)
	fs.writeFile(`build/shot-speedway-{name}-cam.json`, serde.encode("json", { from = { from.X, from.Y, from.Z }, at = { at.X, at.Y, at.Z }, fov = fov }))
end
local zoom = math.clamp(math.sqrt(390 * 844) / 24, 18, 38)
local tall = 844 / zoom * 10
cam("town", middle + Vector3.new(75, 80, 75).Unit * (tall / 2 / math.tan(math.rad(15))), middle, 30)
-- The town view zoomed right in (about five web units of ground on screen).
cam("near", middle + Vector3.new(75, 80, 75).Unit * (50 / 2 / math.tan(math.rad(15))), middle + Vector3.new(0, 4, 0), 30)
cam("close", middle + Vector3.new(-20, 34, 48), middle + Vector3.new(4, 4, -4), 50)
cam("stands", middle + Vector3.new(-6, 14, 12), middle + Vector3.new(10, 6, -6), 60)
print(`wrote build/shot-speedway.json ({#parts} parts)`)
