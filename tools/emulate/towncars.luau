--!nocheck
-- Runs a town's traffic (client TownLife) with the camera down at street level and checks every
-- car's wheels stay on the car (shared/Models/Wheels, client/CarDetail):
--
--   lune run tools/emulate/towncars.luau build/place.rbxl

local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
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
local towns = Towns.new(store, function()
	return NOW
end)
towns:open(1, nil)
local save = towns:snapshot(1).save
local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
Emu.fakeMeshPacks(emu)
local Builder = emu.require(RS.Shared.Models.Builder)
Builder.loadMeshes(1)
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)
pcall(Builder.useLibrary, 1)

local cam = Instance.new("Camera")
cam.FieldOfView = 70
cam.ViewportSize = roblox.Vector2.new(1280, 800)
cam.CFrame = CFrame.lookAt(Vector3.new(0, 20, 0), Vector3.new(50, 0, 50))
game.Workspace.CurrentCamera = cam

local TownLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.TownLife)
local update, step = TownLife.attach(view.folder)
update(save)

local Catalog = emu.require(RS.Shared.Models.Catalog)
local worst, worstName = 0, ""
local checked = 0
local worstBody = 0
local function check()
	local models = {}
	for _, m in view.folder.Cars:GetChildren() do
		table.insert(models, m)
	end
	for _, m in models do
		local id = m:GetAttribute("Model")
		local wheels = id and Catalog.WHEELS[id]
		if not wheels then
			continue
		end
		local pivot = m:GetPivot()
		if pivot.Position.Y < -1000 then
			continue
		end
		local big, bigSize = nil, 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Size.Magnitude > bigSize then
				big, bigSize = d, d.Size.Magnitude
			end
		end
		if big then
			local bd = pivot:PointToObjectSpace(big.CFrame.Position).Magnitude / m:GetScale()
			if bd > worstBody then
				worstBody = bd
			end
		end
		for _, n in wheels do
			local w = m:FindFirstChild(tostring(n))
			if w then
				local rel = pivot:PointToObjectSpace(w.CFrame.Position)
				-- A wheel sits within a car's length of its pivot (scaled).
				local d = rel.Magnitude / m:GetScale()
				checked += 1
				if d > worst then
					worst, worstName = d, `{m.Name} ({id}) wheel {n}`
				end
			end
		end
	end
end
for i = 1, 40 * 30 do
	-- The camera follows a car now and then, near enough that wheels turn.
	if i % 60 == 0 then
		local list = view.folder.Cars:GetChildren()
		local m = list[1 + (i // 60) % math.max(1, #list)]
		if m then
			local p = m:GetPivot().Position
			cam.CFrame = CFrame.lookAt(p + Vector3.new(30, 15, 30), p)
		end
	end
	step(1 / 30)
	if i % 15 == 0 then
		check()
	end
end
-- An update from the server lands a car's body back on its parking spot: the next frame puts it
-- back on the car (it used to stay there, leaving the wheels on the road on their own).
local m = nil
for _, c in view.folder.Cars:GetChildren() do
	if c:GetPivot().Position.Y > -1000 then
		m = c
	end
end
assert(m, "no car on the road")
local big, bigSize = nil, 0
for _, d in m:GetDescendants() do
	if d:IsA("BasePart") and d.Size.Magnitude > bigSize then
		big, bigSize = d, d.Size.Magnitude
	end
end
local cam2 = m:GetPivot().Position
cam.CFrame = CFrame.lookAt(cam2 + Vector3.new(20, 10, 20), cam2)
big.CFrame = big.CFrame + Vector3.new(300, 0, 0)
for _ = 1, 10 do
	step(1 / 30)
end
local off = m:GetPivot():PointToObjectSpace(big.CFrame.Position).Magnitude / m:GetScale()
print(`body knocked 300 studs away comes back to {string.format("%.1f", off)} studs from the car's pivot`)
assert(off < 12, "the body stayed away from its car")
print(`body furthest {string.format("%.1f", worstBody)} studs from pivot`)
print(`{#view.folder.Cars:GetChildren()} cars; checked {checked} wheel placements; furthest wheel {string.format("%.1f", worst)} studs from its car's middle ({worstName})`)
assert(checked > 0, "no wheels checked")
assert(worst < 7, "a wheel left its car")
print("ok")
