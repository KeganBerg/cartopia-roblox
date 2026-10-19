--!nocheck
-- Runs a town's traffic (client TownLife) for a while and checks every car it draws: which cars
-- are out (only the player's own, as the web game's TownCars.tsx), that each stays on the town's
-- roads or its own lot, sits on the ground, and never jumps across the town between frames.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/traffic.luau build/place.rbxl [seconds] [cars]

local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3 = roblox.Instance, roblox.Vector3

local emu = Emu.load(process.args[1] or "build/place.rbxl")
local seconds = tonumber(process.args[2] or "") or 90
local extra = tonumber(process.args[3] or "") or 8
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
-- A few more cars of the player's own, so the roads are busy.
towns:_with(1, function()
	local s = store.useGame.getState()
	local cars = table.clone(s.cars)
	for i = 1, extra do
		local c = table.clone(cars[1])
		c.uid = `extra{i}`
		table.insert(cars, c)
	end
	store.useGame.setState({ cars = cars })
end)
local save = towns:snapshot(1).save
local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
Emu.fakeMeshPacks(emu)
emu.require(RS.Shared.Models.Builder).loadMeshes(1)
pcall(emu.require(RS.Shared.Models.Builder).useLibrary, 1)
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)

local TownLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.TownLife)
local update, step = TownLife.attach(view.folder)
update(save)

local owned = {}
for _, c in save.cars do
	owned[c.uid] = true
end
local onRoad = {}
for _, r in save.roads do
	onRoad[r] = true
end
local lots = {}
for _, b in save.buildings do
	lots[`{b.x},{b.z}`] = true
end

local DT = 1 / 30
local last = {}
local strangers, jumps, offRoad, high, seen = {}, 0, 0, 0, {}
-- The tightest following distance seen at speed (web units, bumper to bumper, over speed).
local tightest, tightV = math.huge, 0
local stuck = {}
local waiting, moving = 0, 0
for f = 1, math.floor(seconds / DT) do
	step(DT)
	TownLife._traffic.agents:forEach(function(_, a, uid)
		if a.parked <= 0 and not a.stalled then
			if a.v < 0.05 then
				waiting += 1
			else
				moving += 1
			end
		end
		if a.wait > 15 and a.parked <= 0 and not stuck[uid] then
			stuck[uid] = true
			print(`  stuck {math.floor(a.wait)}s at {f * DT // 1}s: {uid} at {math.floor(a.x * 10)}, {math.floor(a.z * 10)} studs behind {a.gapTo or "nothing"} (gap {math.floor(a.gap * 100) / 100}) stalled {a.stalled} tow {a.tow} leaving {a.leaving}`)
		elseif a.wait < 1 then
			stuck[uid] = nil
		end
		if a.gapTo and a.v > 1 and not a.ot and a.gap / a.v < tightest then
			tightest, tightV = a.gap / a.v, a.v
		end
	end)
	local all = view.folder.Cars:GetChildren()
	local extraFolder = game.Workspace:FindFirstChild("TownTraffic")
	if extraFolder then
		for _, m in extraFolder:GetChildren() do
			table.insert(all, m)
		end
	end
	for _, m in all do
		local p = m:GetPivot().Position
		if p.Y < -1000 then
			last[m.Name] = nil
			continue
		end
		seen[m.Name] = true
		local tx, tz = view:worldToTile(p)
		local key = `{tx},{tz}`
		if not onRoad[key] and not lots[key] then
			offRoad += 1
			if offRoad <= 5 then
				print(`  off the road: {m.Name} at tile {key} ({p})`)
			end
		end
		if p.Y > 2 or p.Y < -2 then
			high += 1
			if high <= 5 then
				print(`  off the ground: {m.Name} at {p}`)
			end
		end
		local was = last[m.Name]
		if was and (Vector3.new(p.X, 0, p.Z) - was).Magnitude > 12 then
			jumps += 1
			if jumps <= 5 then
				print(`  jumped: {m.Name} {was} -> {p}`)
			end
		end
		last[m.Name] = Vector3.new(p.X, 0, p.Z)
	end
	if extraFolder then
		for _, m in extraFolder:GetChildren() do
			if m:GetPivot().Position.Y > -1000 then
				strangers[m.Name] = true
			end
		end
	end
end
local out, n = {}, 0
TownLife._traffic.agents:forEach(function(_, _, uid)
	n += 1
	if not owned[uid] then
		strangers[uid] = true
	end
end)
for uid in strangers do
	table.insert(out, uid)
end
local drawn = 0
for _ in seen do
	drawn += 1
end
print(`after {seconds}s: {n} cars in the traffic, {drawn} of the player's {#save.cars} drawn, {#out} not theirs`)
print(`  frames off the road {offRoad}, off the ground {high}, jumps {jumps}`)
print(`  cars standing still in traffic: {math.floor(waiting / math.max(1, waiting + moving) * 100)}% of the time`)
print(`  closest following at speed: {math.floor(tightest * 100) / 100}s behind (at {math.floor(tightV * 100) / 100} units/s)`)
if #out > 0 then
	print(`  not the player's: {table.concat(out, ", ")}`)
end
assert(#out == 0 and offRoad == 0 and high == 0 and jumps == 0 and tightest > 0.6, "town traffic check failed")
print("town traffic ok")
