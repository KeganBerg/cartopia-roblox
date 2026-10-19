--!nocheck
-- Gets in a townsfolk car and one of the player's own on foot with server/GetIn (run in the
-- emulator) and checks the car welded round the avatar (server/Drive), then gets out again.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/getin.luau build/place.rbxl

local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
-- The mesh packs as Roblox loads them, so the cars are built from their real shapes (GetIn loads a
-- car's own packs first when they're missing).
Emu.fakeMeshPacks(emu)
emu.require(RS.Shared.Models.Builder).loadMeshes(1)

local Js = emu.require(RS.Shared.Game.__js)
local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)
local store = emu.require(RS.Shared.Game.store)
local Towns = emu.require(SSS.Server.Towns)
local towns = Towns.new(store, function()
	return NOW
end)
towns:open(1, nil)
local save = towns:snapshot(1).save

local remotes = Instance.new("Folder")
remotes.Name = "Cartopia"
remotes.Parent = RS
local GetIn = emu.require(SSS.Server.GetIn)

-- An avatar.
local player = Instance.new("Player")
player.Name = "Player1"
player.UserId = 1
local character = Instance.new("Model")
local root = Instance.new("Part")
root.Name = "HumanoidRootPart"
root.Size = Vector3.new(2, 2, 1)
root.Transparency = 1
root.CFrame = CFrame.new(10, 3, 0)
root.Parent = character
local head = Instance.new("Part")
head.Name = "Head"
head.CFrame = CFrame.new(10, 4.5, 0)
head.Parent = character
local humanoid = Instance.new("Humanoid")
-- Lune's Humanoid has no defaults to read.
humanoid.Health = 100
humanoid.HipHeight = 2
humanoid.Sit = false
humanoid.Parent = character
character.Parent = game.Workspace
character.PrimaryPart = root
player.Character = character

local function check(cond, msg)
	if not cond then
		error(msg, 2)
	end
	print(`  ok   {msg}`)
end

-- towns:save is what the server reads the player's cars from.
local function enter(spec)
	return GetIn.enter(player, towns, spec)
end

local ok, why = enter({ uid = "visitor:local:1", model = "civic", color = "#1e88e5", cf = CFrame.new(100, 0, 0) })
check(not ok and why == "too far", "a car out of reach can't be got in")
ok, why = enter({ uid = "visitor:local:1", model = "zenith", color = "#000000", cf = CFrame.new(14, 0, 0) })
check(not ok, `a special car isn't a town car ({why})`)
ok, why = enter({ uid = "nope", model = "pip", cf = CFrame.new(14, 0, 0) })
check(not ok and why == "not your car", "a uid that isn't yours is refused")

local carCf = CFrame.new(14, 0, 0) * CFrame.Angles(0, math.pi / 2, 0)
ok, why = enter({ uid = "visitor:local:1", model = "civic", color = "#1e88e5", cf = carCf })
check(ok == true, `gets in a townsfolk car ({why})`)
local car = character:FindFirstChild("Car")
check(car ~= nil, "the car is welded round the avatar (server/Drive)")
check(player:GetAttribute("Driving") == true, "the player is driving")
check(head.Transparency == 1, "the avatar is hidden inside")
check((root.CFrame.Position - Vector3.new(14, 0, 0)).Magnitude < 6, `the avatar moved to the car: {root.CFrame.Position}`)
-- The avatar faces the car's nose (+X here): its look is +X.
local look = root.CFrame.LookVector
check(look.X > 0.99, `the avatar faces the car's nose: {look}`)
ok, why = enter({ uid = "visitor:local:2", model = "civic", cf = carCf })
check(not ok and why == "already driving", "can't get in a second car")

local at, uid = GetIn.exit(player)
check(at ~= nil and uid == "visitor:local:1", "gets out, and says which car")
check(character:FindFirstChild("Car") == nil and player:GetAttribute("Driving") == nil, "the car goes")
check(head.Transparency == 0, "the avatar shows again")
local nose = at:VectorToWorldSpace(Vector3.new(0, 0, 1))
check(nose.X > 0.99, `the car is left facing the way it was driven: {nose}`)
local d = (root.CFrame.Position - at.Position)
check(Vector3.new(d.X, 0, d.Z).Magnitude > 4, `out beside it: {root.CFrame.Position}`)
check(GetIn.exit(player) == nil, "getting out twice does nothing")

-- One of the player's own.
local mine = save.cars[1]
ok, why = enter({ uid = mine.uid, model = "ignored", cf = CFrame.new(14, 0, 0) })
check(ok == true, `gets in their own car ({why})`)
GetIn.exit(player)
print("getin: all good")
