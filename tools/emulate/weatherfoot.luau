--!nocheck
-- Rain, snow and sand seen on foot (client/TownWeather with a street-level camera): checks no drop
-- ever falls within TownWeather.NEAR studs of the lens, whichever way the camera looks and the
-- wind blows, and that the drops ride along with the box (LockedToPart) so walking or driving
-- never runs into them. Back in the town view the old bird's-eye box comes back.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/weatherfoot.luau build/place.rbxl

local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client

local Js = emu.require(RS.Shared.Game.__js)
local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)
local TownCamera = emu.require(client.TownCamera)
local TownWeather = emu.require(client.TownWeather)
local walking = true
TownCamera.isWalking = function()
	return walking
end

local cam = game.Workspace.CurrentCamera
if not cam then
	cam = roblox.Instance.new("Camera")
	cam.Parent = game.Workspace
	game.Workspace.CurrentCamera = cam
end
cam.FieldOfView = 70

local bad = 0
local function check(cond, msg)
	if not cond then
		bad += 1
		print("FAIL " .. msg)
	end
end

-- Every corner and edge-middle of the emitter box, carried along its fall for the emitter's longest life.
local function nearest(k, e, eye)
	local box = k.sky
	local half = box.Size / 2
	local local_v = Vector3.new(0, -1, 0) * e.Speed.Max
	local best = math.huge
	for _, sx in { -1, -0.5, 0, 0.5, 1 } do
		for _, sz in { -1, -0.5, 0, 0.5, 1 } do
			for step = 0, 20 do
				local t = e.Lifetime.Max * step / 20
				local p = box.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, 0, half.Z * sz) + local_v * t)
				if p.Y >= -1 then
					local flat = Vector3.new(p.X - eye.X, 0, p.Z - eye.Z)
					best = math.min(best, flat.Magnitude)
				end
			end
		end
	end
	return best
end

for _, kind in { "drizzle", "rain", "storm", "snow", "blizzard", "dust" } do
	TownWeather.pin(kind)
	for yaw = 0, 345, 15 do
		for _, pitch in { -60, -20, 0, 15 } do
			local eye = Vector3.new(120, 8, -40)
			cam.CFrame = CFrame.new(eye) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0)
			TownWeather.step(NOW, 1)
			local k = TownWeather.kit()
			local snowy = kind == "snow" or kind == "blizzard" or kind == "dust"
			local e = if snowy then k.snow else k.rain[1]
			check(e.Enabled, `{kind}: nothing falling`)
			check(e.LockedToPart, `{kind}: drops don't ride with the box on foot`)
			local d = nearest(k, e, eye)
			-- (Snow and sand spread a few degrees off their line, so allow them a couple of studs.)
			check(d >= TownWeather.NEAR - 3, `{kind} yaw {yaw} pitch {pitch}: a drop falls {math.floor(d)} studs from the lens`)
			-- And the box is in front of the camera, not behind it.
			local ahead = (k.sky.CFrame.Position - eye) * Vector3.new(1, 0, 1)
			local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude > 0.01 then
				check(ahead:Dot(look.Unit) > 0, `{kind} yaw {yaw}: the weather is behind the camera`)
			end
		end
	end
	print(`{kind}: ok (span {TownWeather.last.frame.span}, top {TownWeather.last.frame.top})`)
end

-- Back to the town view: the bird's-eye box, drops left where they fall.
walking = false
TownWeather.pin("rain")
cam.CFrame = CFrame.lookAt(Vector3.new(750, 800, 750), Vector3.new(0, 0, 0))
TownWeather.step(NOW, 1)
check(not TownWeather.kit().rain[1].LockedToPart, "town view: drops still locked to the box")
check(not TownWeather.last.frame.free, "town view: still the street-level box")

print(if bad == 0 then "weather on foot: all good" else `weather on foot: {bad} problems`)
process.exit(if bad == 0 then 0 else 1)
