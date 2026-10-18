--!nocheck
-- Turns a skinned car round in the emulator with the game's own Skins and SkinMotion, and writes
-- what each step looks like for tools/emulate/render.mjs, to see the skin's glow slide under the
-- paint (parallax) and fade between its two moments. The car is a stand-in made of blocks (the
-- sandbox has no uploaded car meshes) and the tiles are the baked ones in tools/models/skins/.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/skins.luau build/place.rbxl <skin number> [steps]
--   then for each build/skin-<i>.json: node tools/emulate/render.mjs <web> build/skin-<i>.json out.png - "$(cat build/skin-<i>-cam.json)"

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local Gui = require("./gui")
local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local n = tonumber(process.args[2] or "3")
local steps = tonumber(process.args[3] or "6")

-- The tiles as the model build would list them (Catalog.TEXTURES), named for render.mjs, which
-- finds them in build/textures/.
local skins = serde.decode("json", fs.readFile("tools/models/skins/skins.json"))
local entry
for _, s in skins.skins do
	if s.n == n then
		entry = s
	end
end
assert(entry, `no skin {n}`)
fs.writeDir("build/textures")
local Catalog = emu.require(RS.Shared.Models.Catalog)
Catalog.TEXTURES = Catalog.TEXTURES or {}
for key, file in { [`skin_{n}`] = entry.base, [`skinglow_{n}`] = entry.glow, [`skinglow2_{n}`] = entry.glow2 } do
	fs.writeFile(`build/textures/{file:gsub("%.png$", "")}.png`, fs.readFile(`tools/models/skins/{file}`))
	Catalog.TEXTURES[key] = { image = 1, span = skins.span * Catalog.SCALE, name = file:gsub("%.png$", ""), depth = if key:match("glow") then entry.depth * Catalog.SCALE else nil }
end
local Skins = emu.require(RS.Shared.Models.Skins)
local SkinMotion = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.SkinMotion)

-- A blocky car: body, cabin and hood, in the paint.
local car = Instance.new("Model")
car.Name = "Car"
for _, b in { { 0, 2, 0, 9, 3, 18 }, { 0, 4.8, 1.5, 8, 2.6, 8 }, { 0, 3.7, -6, 8.4, 0.4, 5 } } do
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = Vector3.new(b[4], b[5], b[6])
	p.CFrame = CFrame.new(b[1], b[2], b[3])
	p.Color = roblox.Color3.fromRGB(40, 90, 200)
	p:SetAttribute("Paint", true)
	p.Parent = car
end
for _, x in { -4.6, 4.6 } do
	for _, z in { -5.5, 5.5 } do
		local w = Instance.new("Part")
		w.Anchored = true
		w.Shape = roblox.Enum.PartType.Cylinder
		w.Size = Vector3.new(1.4, 4, 4)
		w.CFrame = CFrame.new(x, 2, z)
		w.Color = roblox.Color3.fromRGB(25, 25, 25)
		w.Parent = car
	end
end
car.Parent = game.Workspace
for _, p in car:GetChildren() do
	if p:GetAttribute("Paint") then
		Skins.lay(p, n)
	end
end
SkinMotion.watch(game.Workspace)

local cam = game.Workspace.CurrentCamera
local at = Vector3.new(0, 3, 0)
for i = 1, steps do
	-- Round the car's front corner, a step at a time, and on through the glows' fade.
	local a = 0.5 + (i - 1) * 0.12
	local from = at + Vector3.new(math.sin(a), 0.55, -math.cos(a)).Unit * 22
	cam.CFrame = CFrame.new(from)
	SkinMotion.step((i - 1) * 0.25)
	local parts = {}
	for _, p in car:GetChildren() do
		table.insert(parts, Gui.partOf(p))
	end
	local glow = car:GetChildren()[1]:FindFirstChild("SkinGlow")
	print(`step {i}: glow offset {glow.OffsetStudsU}, {glow.OffsetStudsV}, see-through {glow.Transparency}`)
	fs.writeFile(`build/skin-{i}.json`, serde.encode("json", { parts = parts }))
	fs.writeFile(`build/skin-{i}-cam.json`, serde.encode("json", { at = { at.X, at.Y, at.Z }, from = { from.X, from.Y, from.Z }, fov = 40 }))
end
