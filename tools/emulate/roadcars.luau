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
print(`{near} cars within 150 studs`)

-- The wheels: on a car near the camera they roll (turning round the axle, staying in place).
local Catalog = emu.require(RS.Shared.Models.Catalog)
local car, cd = nil, math.huge
for _, m in WorldLife.cars() do
	local d = (m:GetPivot().Position - eye).Magnitude
	if d < cd and Catalog.WHEELS[m:GetAttribute("Model")] then
		car, cd = m, d
	end
end
assert(car, "no car with wheels in sight")
local wheel = car:FindFirstChild(tostring(Catalog.WHEELS[car:GetAttribute("Model")][1]))
local function relOf()
	return car:GetPivot():ToObjectSpace(wheel.CFrame)
end
local before = relOf()
for _ = 1, 10 do
	step(1 / 30, eye, nil)
end
local after = relOf()
local turned = math.deg(math.acos(math.clamp(before.UpVector:Dot(after.UpVector), -1, 1)))
local drift = (before.Position - after.Position).Magnitude
print(`wheel of {car:GetAttribute("Model")} {math.floor(cd)} studs off: turned {math.floor(turned)}°, moved {string.format("%.3f", drift)} studs on the car`)
assert(turned > 1, "wheels didn't turn")
assert(drift < 0.6, "wheel wandered off its axle")
print("ok")

-- SHOT=1 also writes build/roadcars.json and -cam.json for render.mjs: behind the nearest car,
-- as the follow camera sits behind the player's.
if process.env.SHOT then
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local Gui = require("./gui")
	local best, bd = nil, math.huge
	for _, m in WorldLife.cars() do
		local d = (m:GetPivot().Position - eye).Magnitude
		if d < bd then
			best, bd = m, d
		end
	end
	local at = best:GetPivot()
	local from = (at * CFrame.new(-4, 14, -38)).Position
	local look = (at * CFrame.new(0, 3, 60)).Position
	cam.CFrame = CFrame.lookAt(from, look)
	step(1 / 30, from, nil)
	local parts = {}
	for _, d in game.Workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local ok, ltm = pcall(function()
				return d.LocalTransparencyModifier
			end)
			if not (ok and ltm == 1) and (d.CFrame.Position - from).Magnitude < 2500 then
				table.insert(parts, Gui.partOf(d))
			end
		end
	end
	fs.writeFile("build/roadcars.json", serde.encode("json", { parts = parts }))
	fs.writeFile("build/roadcars-cam.json", serde.encode("json", { from = { from.X, from.Y, from.Z }, at = { look.X, look.Y, look.Z }, fov = 70, far = 6000 }))
	print(`wrote build/roadcars.json ({#parts} parts)`)
end
