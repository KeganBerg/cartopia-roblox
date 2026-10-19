--!nocheck
-- Checks the road traffic's cars (client/WorldLife, client/CarDetail): built before the meshes
-- arrive they're stand-in boxes, and once the meshes are in they're built again for real; far off
-- their small pieces hide. Prints what it found and fails on a box left behind:
--
--   lune run tools/emulate/roadcars.luau build/place.rbxl

local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local Builder = emu.require(RS.Shared.Models.Builder)
local cam = Instance.new("Camera")
cam.FieldOfView = 70
cam.ViewportSize = roblox.Vector2.new(1280, 800)
game.Workspace.CurrentCamera = cam

local world = Instance.new("Folder")
world.Name = "World"
world:SetAttribute("Pitch", 1400)
world:SetAttribute("Rings", 2)
world.Parent = game.Workspace

local WorldLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.WorldLife)
local step = WorldLife.attach(world)
local eye = Vector3.new(700, 40, 700)
cam.CFrame = CFrame.new(eye)

local function count()
	local boxes, cars, hidden = 0, 0, 0
	for _, m in game.Workspace.RoadTraffic:GetChildren() do
		cars += 1
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				if d:GetAttribute("Mesh") ~= nil and not d:IsA("MeshPart") then
					boxes += 1
				end
				-- (Lune has no default for it, so an unset one can't be read.)
				local ok, ltm = pcall(function()
					return d.LocalTransparencyModifier
				end)
				if ok and ltm == 1 then
					hidden += 1
				end
			end
		end
	end
	return cars, boxes, hidden
end

for _ = 1, 30 do
	step(1 / 30, eye, nil)
end
local cars, boxes = count()
print(`before the meshes: {cars} cars, {boxes} stand-in boxes`)
assert(boxes > 0, "expected boxes before the meshes arrive")

Emu.fakeMeshPacks(emu)
Builder.loadMeshes(1)
for _ = 1, 60 do
	step(1 / 30, eye, nil)
end
local cars2, boxes2, hidden = count()
print(`after the meshes: {cars2} cars, {boxes2} stand-in boxes, {hidden} small pieces hidden far off`)
assert(cars2 == cars, "lost cars in the swap")
assert(boxes2 == 0, "boxes left after the meshes arrived")
assert(hidden > 0, "nothing hidden far off")
local near = 0
for _, m in WorldLife.cars() do
	if (m:GetPivot().Position - eye).Magnitude < 150 then
		near += 1
	end
end
print(`{near} cars within 150 studs; ok`)
