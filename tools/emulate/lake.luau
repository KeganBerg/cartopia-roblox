--!nocheck
-- Previews the countryside lake's life (client/LakeLife): the forest and lake Countryside draws round
-- a town, with the fisherman, gulls and ducks run for a few seconds on the client. Writes
-- build/shot-lake.json and build/shot-lake-{name}-cam.json for render.mjs.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/lake.luau build/place.rbxl
--   CHROMIUM=... node tools/emulate/render.mjs <web> build/shot-lake.json out.png - \
--     "$(cat build/shot-lake-close-cam.json)"
--
-- RUN_FOR=<s> how long the lake has run (40 by default: he's rowed out and cast, and some gulls are
-- down); SEED=<n> seeds math.random; WINTER=1 runs it as the winter build would (the lake iced
-- over: gulls only).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3 = roblox.Instance, roblox.Vector3

local place = process.args[1] or "build/place.rbxl"
local emu = Emu.load(place)
local game = emu.game
local RS = game:GetService("ReplicatedStorage")

-- Particle bursts can't be drawn here: count them.
local rings = 0
roblox.implementMethod("ParticleEmitter", "Emit", function(_, n)
	rings += n or 1
end)

math.randomseed(tonumber(process.env.SEED or "") or 7)

if process.env.WINTER then
	emu.require(RS.Shared.Models.Catalog).SEASON = "winter"
end
local Builder = emu.require(RS.Shared.Models.Builder)
if process.env.NO_MESHES == nil then
	Emu.fakeMeshPacks(emu)
	Builder.loadMeshes(1)
	pcall(Builder.useLibrary, 1)
end
-- The forest ring with its lake, as Countryside draws it round a town at the origin.
local root = Instance.new("Folder")
root.Name = "Countryside"
local forest = Builder.build("outskirts:forest")
assert(forest, "no forest model")
forest:PivotTo(roblox.CFrame.new(0, 0, 0))
forest.Parent = root
root.Parent = game.Workspace

local LakeLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.LakeLife)
local scan, step = LakeLife.attach(Vector3.new(0, 0, 0), game.Workspace)
scan()
print(`hid {LakeLife.hideBaked(forest, Vector3.new(0, 0, 0))} pieces of the still frame baked into the forest`)
local seconds = tonumber(process.env.RUN_FOR or "") or 40
for _ = 1, math.floor(seconds * 30) do
	step(1 / 30)
end
local life = game.Workspace:FindFirstChild("LakeLife")
assert(life, "no LakeLife drawn")
local shown = 0
for _, d in life:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 and d.CFrame.Position.Y > -100 then
		shown += 1
	end
end
print(`lake after {seconds}s: {#life:GetDescendants()} instances, {shown} parts in place, {rings} ripple rings sent out`)

-- The parts near the lake: the scenery round it and the life on it.
local L = LakeLife.LAKE
local middle = Vector3.new(L.x * 10, 0, L.z * 10)
local Gui = require("./gui")
local parts = {}
local boat = nil
-- Without build/meshes.json render.mjs draws a mesh as its box, and the forest's merged meshes
-- (trees, the cabin, the lake's water and sand) are boxes hundreds of studs across: those are left
-- out, and the ground, the shore and the water drawn as stand-ins (discs, which render.mjs
-- stretches into the lake's ellipse). The dock's small meshes stay.
local function standIn(shape, size, at, color)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = at
	p.Color = roblox.Color3.fromHex(color)
	table.insert(parts, Gui.partOf(p))
end
local flat = roblox.CFrame.Angles(0, 0, math.pi / 2)
standIn(roblox.Enum.PartType.Block, Vector3.new(900, 1, 900), roblox.CFrame.new(middle - Vector3.new(0, 1, 0)), "#7cb342")
standIn(roblox.Enum.PartType.Cylinder, Vector3.new(0.1, (L.rx + 1.2) * 20, (L.rz + 1.2) * 20), roblox.CFrame.new(middle + Vector3.new(0, -0.44, 0)) * flat, "#b6a27a")
standIn(roblox.Enum.PartType.Cylinder, Vector3.new(0.1, L.rx * 20, L.rz * 20), roblox.CFrame.new(middle + Vector3.new(0, L.y * 10 - 0.05, 0)) * flat, if process.env.WINTER then "#dcecf7" else "#2f7aa6")
for _, d in game.Workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		local p = d.CFrame.Position
		local mesh = d:IsA("MeshPart") or d:GetAttribute("Mesh") ~= nil
		if mesh and not d:IsDescendantOf(life) and (d.Size.Y > 3 or d.Size.X > 60) then
			continue
		end
		if p.Y > -100 and p.Y < 400 and (Vector3.new(p.X, 0, p.Z) - middle).Magnitude < 420 then
			table.insert(parts, Gui.partOf(d))
			if d:IsDescendantOf(life) and string.lower(d.Color:ToHex()) == "2e7d6b" and not boat then
				boat = p
			end
		end
	end
end
fs.writeFile("build/shot-lake.json", serde.encode("json", { parts = parts }))
print(`wrote build/shot-lake.json ({#parts} parts), boat at {boat}`)

local function cam(name, from, at, fov)
	fs.writeFile(`build/shot-lake-{name}-cam.json`, serde.encode("json", { from = { from.X, from.Y, from.Z }, at = { at.X, at.Y, at.Z }, fov = fov }))
end
-- The whole lake from over the dock, the boat close up, and the ducks.
cam("lake", middle + Vector3.new(260, 160, 160), middle + Vector3.new(0, 0, 0), 45)
if boat then
	cam("close", boat + Vector3.new(14, 9, 16), boat + Vector3.new(0, 2, 0), 45)
end
-- A gull in the air.
for _, d in life:GetChildren() do
	if d:IsA("BasePart") and string.lower(d.Color:ToHex()) == "fafafa" and d.CFrame.Position.Y > 20 then
		local p = d.CFrame.Position
		cam("gull", p + Vector3.new(0, 9, 0.5), p, 40)
		break
	end
end
-- The hen and her ducklings, and the dock's end where gulls stand.
for _, d in life:GetChildren() do
	if d:IsA("BasePart") and string.lower(d.Color:ToHex()) == "9b7451" then
		local p = d.CFrame.Position
		cam("ducks", p + Vector3.new(8, 5, 9), p + Vector3.new(-1, 0, -1), 40)
		break
	end
end
local dock = Vector3.new(-675, 2, -120)
cam("dock", dock + Vector3.new(-6, 9, 22), dock + Vector3.new(-12, 3, 0), 45)
