--!nocheck
-- Previews the Big Bison travel stop and the Bubble Car Spa (client/CentreLife): a starter town
-- given a merged block of four level 8 gas stations and one of four level 8 car washes (each a
-- 2x2 block, 4x2 tiles), drawn by the server's TownView, with their life run for a few seconds on
-- the client. Writes build/shot-travelwash.json and build/shot-travelwash-<name>-cam.json for
-- render.mjs.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/travelwash.luau build/place.rbxl
--   CHROMIUM=... node tools/emulate/render.mjs <web> build/shot-travelwash.json out.png - \
--     "$(cat build/shot-travelwash-travel-cam.json)"
--
-- LEVEL=<n> picks the blocks' level (8 by default; 7-10 are the centres), RUN_FOR=<s> how long
-- their life has run, MERGE=<code> the block's shape (2 = 2x2 by default, 21 a pair along x).

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
	store.useGame.setState({ coins = 100000000, level = 60 })
end)
local save = towns:snapshot(1).save
local level = tonumber(process.env.LEVEL or "") or 8
local code = tonumber(process.env.MERGE or "") or 2
-- Each block across the top of town, between the ring road (z = 4) and the showroom, facing the
-- ring road. Gas stations and car washes are 2x1 lots.
local function block(def: string, x0: number, z0: number)
	local cols, rows = 2, 2
	if code == 21 then
		cols, rows = 2, 1
	end
	for j = 0, rows - 1 do
		for i = 0, cols - 1 do
			local b = { uid = `{def}{i}{j}`, def = def, x = x0 + i * 2, z = z0 + j, level = level }
			if i == 0 and j == 0 then
				b.merge = code
			end
			table.insert(save.buildings, b)
		end
	end
end
block("gas", 9, 5)
block("carwash", 14, 5)

local folder = Instance.new("Folder")
folder.Name = "Towns"
folder.Parent = game.Workspace
if process.env.NO_MESHES == nil then
	Emu.fakeMeshPacks(emu)
	emu.require(RS.Shared.Models.Builder).loadMeshes(1)
end
local view = TownView.new(folder, "Player1", Vector3.new(0, 0, 0), 1, function() end)
view:render(save)

-- The centres' life, run for RUN_FOR seconds (6 by default: cars part way through their visits).
if process.env.NO_LIFE == nil then
	local CentreLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.CentreLife)
	local scan, step = CentreLife.attach(view.folder, game.Workspace)
	scan()
	local seconds = tonumber(process.env.RUN_FOR or "") or 6
	for f = 1, math.floor(seconds * 60) do
		step(1 / 60)
		-- TRACE=1: where the cars are each second (pumps and tunnel queue).
		if process.env.TRACE and f % 60 == 0 then
			local out = {}
			for uid, c in CentreLife._centres do
				for _, life in c.lives do
					if life.slots then
						for _, sl in life.slots do
							table.insert(out, `{sl.phase:sub(1, 1)}{string.format("%.0f", sl.t)}`)
						end
					else
						for _, u in life.tunnels do
							for _, q in u.queue do
								table.insert(out, `[{q.phase} {string.format("%.2f", q.x)}]`)
							end
							table.insert(out, `gate {string.format("%.1f", u.gateUp)}`)
						end
					end
					table.insert(out, "|")
				end
			end
			print(`{f // 60}s`, table.concat(out, " "))
		end
	end
	local holder = game.Workspace:FindFirstChild("Centres")
	for _, life in holder:GetChildren() do
		local shown = 0
		for _, d in life:GetDescendants() do
			if d:IsA("BasePart") and d.CFrame.Position.Y > -100 then
				shown += 1
			end
		end
		local cars, out = 0, 0
		for _, m in life:GetChildren() do
			if m:IsA("Model") then
				cars += 1
				local piece = m:FindFirstChildWhichIsA("BasePart", true)
				if piece and piece.CFrame.Position.Y > -100 then
					out += 1
				end
			end
		end
		print(`{life.Name}: {#life:GetDescendants()} instances, {shown} parts in place, {out} of {cars} cars out`)
	end
end

local Gui = require("./gui")
-- Hidden on this screen (the server's grown station, CentreLife hides): left out of the picture.
local function faded(d): boolean
	local ok, v = pcall(function()
		return d.LocalTransparencyModifier
	end)
	return ok and v >= 1
end
local parts = {}
for _, d in game.Workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 and d.CFrame.Position.Y > -100 and not faded(d) then
		table.insert(parts, Gui.partOf(d))
	end
end
fs.writeFile("build/shot-travelwash.json", serde.encode("json", { parts = parts }))

-- Cameras over each block: the town view (TownCamera's angle at 390x844), and closer in.
local function cam(name, from, at, fov)
	fs.writeFile(`build/shot-travelwash-{name}-cam.json`, serde.encode("json", { from = { from.X, from.Y, from.Z }, at = { at.X, at.Y, at.Z }, fov = fov }))
end
for _, uid in { "gas00", "carwash00" } do
	local model = view.folder.Buildings:FindFirstChild(uid)
	assert(model, `no {uid} model drawn`)
	local hit = model:FindFirstChild("Hit")
	local middle = hit.CFrame.Position - Vector3.new(0, hit.Size.Y / 2, 0)
	local name = if uid == "gas00" then "travel" else "wash"
	-- They face the ring road at -z: look from that side.
	cam(name, middle + Vector3.new(-50, 70, -90).Unit * 230, middle, 40)
	cam(`{name}-close`, middle + Vector3.new(-30, 40, -70), middle + Vector3.new(0, 4, 0), 50)
	cam(`{name}-top`, middle + Vector3.new(0, 200, -20), middle, 40)
	-- Down among it, on the block's own frame (studs; +z towards the road): over the front pumps,
	-- or from the kiosk end along the tunnel's glass front.
	local frame = roblox.CFrame.new(middle) * roblox.CFrame.Angles(0, model:GetAttribute("Turn") * math.pi / 2, 0)
	if name == "travel" then
		cam(`{name}-low`, frame:PointToWorldSpace(Vector3.new(10, 18, 34)), frame:PointToWorldSpace(Vector3.new(-2, 3, 6)), 50)
	else
		cam(`{name}-low`, frame:PointToWorldSpace(Vector3.new(-38, 16, -2)), frame:PointToWorldSpace(Vector3.new(-5, 4, -13)), 50)
		-- Through the glass at the brushes.
		cam(`{name}-glass`, frame:PointToWorldSpace(Vector3.new(-4, 14, 8)), frame:PointToWorldSpace(Vector3.new(-14, 3, -13)), 55)
	end
end
print(`wrote build/shot-travelwash.json ({#parts} parts)`)
