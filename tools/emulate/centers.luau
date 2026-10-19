--!nocheck
-- Previews the life at the merged Fresh Mart and motel (client/StoreDoorLife): a starter town given a
-- 2x2 Fresh Mart at level 8 and a 2x2 motel at level 9 along the bottom road, and a Fresh Mart pair
-- at level 7 on the top road, drawn by the server's TownView, with the shoppers and guests run for a
-- while on the client. Writes build/shot-centers-<t>.json at each of the SHOTS times (seconds), and
-- build/shot-centers-<name>-cam.json cameras for render.mjs.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/centers.luau build/place.rbxl
--   CHROMIUM=... node tools/emulate/render.mjs <web> build/shot-centers-6.json out.png - \
--     "$(cat build/shot-centers-market-cam.json)"
--
-- SHOTS=<t,t,...> picks the times (4,6.5,9 by default); SEED=<n> who goes where when (7).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3 = roblox.Instance, roblox.Vector3

math.randomseed(tonumber(process.env.SEED or "") or 7)
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
towns:_with(1, function()
	store.useGame.setState({ coins = 10000000, level = 40 })
end)
local save = towns:snapshot(1).save
-- Room along the bottom road (z = 19): the tree at 11,17 makes way for the motel.
local keep = {}
for _, b in save.buildings do
	if not (b.def == "tree" and b.x == 11 and b.z == 17) then
		table.insert(keep, b)
	end
end
save.buildings = keep
-- Four markets in a square merge into one block (merge.ts code 2), anchored at the top-left one.
local function block(def, x, z, level, code, cells)
	for i, at in cells do
		table.insert(save.buildings, { uid = `{def}{x}{z}:{i}`, def = def, x = x + at[1], z = z + at[2], level = level, merge = if i == 1 then code else nil })
	end
end
local SQUARE = { { 0, 0 }, { 2, 0 }, { 0, 1 }, { 2, 1 } }
block("market", 5, 17, 8, 2, SQUARE)
block("motel", 10, 17, 9, 2, SQUARE)
-- A pair on the top road (z = 4), facing it.
block("market", 12, 5, 7, 21, { { 0, 0 }, { 2, 0 } })

local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
if process.env.NO_MESHES == nil then
	Emu.fakeMeshPacks(emu)
	emu.require(RS.Shared.Models.Builder).loadMeshes(1)
end
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)

local StoreDoorLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.StoreDoorLife)
local scan, step = StoreDoorLife.attach(view.folder, game.Workspace)
scan()

local Gui = require("./gui")
local function shot(t)
	local parts = {}
	for _, d in game.Workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and d.CFrame.Position.Y > -100 then
			table.insert(parts, Gui.partOf(d))
		end
	end
	fs.writeFile(`build/shot-centers-{t}.json`, serde.encode("json", { parts = parts }))
	-- Who's out and how open the doors are.
	local out, doors = 0, 0
	for _, c in game.Workspace.Centers:GetChildren() do
		for _, d in c:GetDescendants() do
			if d:IsA("BasePart") and d.CFrame.Position.Y > -100 then
				if d.Parent:IsA("Model") then
					out += 1
				else
					doors += 1
				end
			end
		end
	end
	-- Who's at the 2x2 market's doors (its middle is at -100, 120; the doors 8 studs in front).
	local atDoor = 0
	for _, d in game.Workspace.Centers:GetDescendants() do
		local p = d:IsA("BasePart") and d.Parent:IsA("Model") and d.CFrame.Position
		if p and math.abs(p.X + 100) < 6 and p.Z > 118 and p.Z < 136 then
			atDoor += 1
		end
	end
	print(`t={t}s: {#game.Workspace.Centers:GetChildren()} centres, {out} figure parts out, {doors} door parts showing, {atDoor} at the market's doors; wrote build/shot-centers-{t}.json ({#parts} parts)`)
end

local shots = {}
for t in string.gmatch(process.env.SHOTS or "4,6.5,9", "[^,]+") do
	table.insert(shots, tonumber(t))
end
table.sort(shots)
local t = 0
for _, at in shots do
	while t < at - 1e-6 do
		step(1 / 30)
		t += 1 / 30
	end
	shot(at)
end

-- Cameras: over each centre from the road, and close up at the market's doors.
local function cam(name, from, at, fov)
	fs.writeFile(`build/shot-centers-{name}-cam.json`, serde.encode("json", { from = { from.X, from.Y, from.Z }, at = { at.X, at.Y, at.Z }, fov = fov }))
end
for _, m in view.folder.Buildings:GetChildren() do
	local def = m:GetAttribute("Def")
	if (def == "market" or def == "motel") and m:GetAttribute("Merged") then
		local hit = m:FindFirstChild("Hit")
		local c = hit.CFrame.Position - Vector3.new(0, hit.Size.Y / 2, 0)
		local name = if m:GetAttribute("Merged") == 2 then "pair" else def
		-- The bottom-road blocks face +z; the pair faces -z (the top road).
		local dir = if c.Z > 0 then 1 else -1
		cam(name, c + Vector3.new(0, 55, dir * 95), c + Vector3.new(0, 4, dir * 10), 40)
		cam(`{name}-close`, c + Vector3.new(-26, 13, dir * 42), c + Vector3.new(0, 5, dir * 10), 45)
		print(name, c, m:GetAttribute("Turn"), hit.Size)
	end
end
