--!nocheck
-- Previews the campuses' and the funfair's life (client/CampusLife, client/FairCrowd): a starter
-- town cleared and given an Elementary School, a High School, the University, a Driving Academy and
-- a funfair (all at LEVEL, 8 by default), drawn by the server's TownView, with their people and
-- learner cars run for a few seconds on the client in daylight. Writes build/shot-campus.json and a
-- camera for each lot, build/shot-campus-<def>-cam.json, for render.mjs.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/campus.luau build/place.rbxl
--   CHROMIUM=... node tools/emulate/render.mjs <web> build/shot-campus.json out.png - \
--     "$(cat build/shot-campus-school-cam.json)"
--
-- LEVEL=<n> picks the lots' level, RUN_FOR=<s> how long they've run, NIGHT=1 runs them at night
-- (the kids and runners gone home, a few students about), TRACE=1 prints where the learner cars
-- are every half second (they stop at the stop line and queue).

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
local SSS = game:GetService("ServerScriptService")

local Js = emu.require(RS.Shared.Game.__js)
local clock = emu.require(RS.Shared.Game.clock)
-- A time in the day (or the night, with NIGHT=1), found by stepping a minute at a time (a town
-- day is 20 minutes long).
local NOW = 1760000000000
local wantNight = process.env.NIGHT ~= nil
for _ = 1, 40 do
	local night = clock.nightAmount(clock.dayPhase(NOW))
	if (if wantNight then night > 0.9 else night < 0.05) and clock.isNight(NOW) == wantNight then
		break
	end
	NOW += 60 * 1000
end
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
-- The starter town's ring road and middle road stay; its buildings make way for the lots.
local level = tonumber(process.env.LEVEL or "") or 8
save.buildings = {
	{ uid = "university", def = "university", x = 5, z = 12, level = level },
	{ uid = "highschool", def = "highschool", x = 9, z = 13, level = level },
	{ uid = "school", def = "school", x = 13, z = 13, level = level },
	{ uid = "academy", def = "academy", x = 16, z = 13, level = level },
	{ uid = "funfair", def = "funfair", x = 6, z = 6, level = level },
}

local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
if process.env.NO_MESHES == nil then
	Emu.fakeMeshPacks(emu)
	emu.require(RS.Shared.Models.Builder).loadMeshes(1)
end
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)

local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local CampusLife = emu.require(Client.CampusLife)
local FairCrowd = emu.require(Client.FairCrowd)
local scanC, stepC = CampusLife.attach(view.folder, game.Workspace)
local scanF, stepF = FairCrowd.attach(view.folder, game.Workspace)
scanC()
scanF()
local seconds = tonumber(process.env.RUN_FOR or "") or 6
for f = 1, math.floor(seconds * 60) do
	stepC(1 / 60)
	stepF(1 / 60)
	if process.env.TRACE and f % 30 == 0 then
		local life = game.Workspace.Campuses:FindFirstChild("CampusLife:academy")
		local line = {}
		for _, m in life:GetChildren() do
			if m:IsA("Model") and string.sub(m.Name, 1, 7) == "learner" then
				local p = m:FindFirstChild("Part", true) or m:FindFirstChildWhichIsA("BasePart", true)
				local l = (p.CFrame.Position - Vector3.new(100, 0, 40)) / 10
				table.insert(line, string.format("%s(%.2f,%.2f)", m.Name, l.X, l.Z))
			end
		end
		print(string.format("t=%.1f %s", f / 60, table.concat(line, " ")))
	end
end

local function count(holder)
	local n, shown = 0, 0
	for _, d in holder:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
			if d.CFrame.Position.Y > -100 and d.Transparency < 1 then
				shown += 1
			end
		end
	end
	return n, shown
end
for _, life in game.Workspace.Campuses:GetChildren() do
	local n, shown = count(life)
	print(`{life.Name}: {n} parts, {shown} in place`)
end
for _, life in game.Workspace.FairCrowds:GetChildren() do
	local n, shown = count(life)
	print(`{life.Name}: {n} parts, {shown} in place`)
end

local Gui = require("./gui")
local parts = {}
for _, d in game.Workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 and d.CFrame.Position.Y > -100 then
		table.insert(parts, Gui.partOf(d))
	end
end
fs.writeFile("build/shot-campus.json", serde.encode("json", { parts = parts }))

-- A camera over each lot: TownCamera's angle, close enough to see the people.
local function cam(name, from, at, fov)
	fs.writeFile(`build/shot-campus-{name}-cam.json`, serde.encode("json", { from = { from.X, from.Y, from.Z }, at = { at.X, at.Y, at.Z }, fov = fov }))
end
for _, b in save.buildings do
	local model = view.folder.Buildings:FindFirstChild(b.uid)
	assert(model, `no {b.def} model drawn`)
	local hit = model:FindFirstChild("Hit")
	local middle = hit.CFrame.Position - Vector3.new(0, hit.Size.Y / 2, 0)
	local span = math.max(hit.Size.X, hit.Size.Z)
	cam(b.def, middle + Vector3.new(75, 80, 75).Unit * (span * 1.3 / 2 / math.tan(math.rad(20))), middle, 40)
	-- Down at a person's eye, for the people close up.
	cam(`{b.def}-low`, middle + Vector3.new(span * 0.55, 9, span * 0.55), middle + Vector3.new(0, 3, 0), 50)
	print(`{b.def} at {middle}, turn {model:GetAttribute("Turn")}`)
end
print(`wrote build/shot-campus.json ({#parts} parts)`)
