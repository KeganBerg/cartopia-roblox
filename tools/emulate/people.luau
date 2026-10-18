--!nocheck
-- Lines up townspeople (client TownLife's figures) on a patch of pavement, a few mid-stride, one
-- seated and one with a dog, and writes their parts for tools/emulate/render.mjs to picture close up.
--
--   lune run tools/emulate/people.luau build/place.rbxl build/people.json
--   node tools/emulate/render.mjs <web repo> build/people.json build/people.png - '{"at":[0,3,0],"from":[0,5,26],"fov":40}'

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame

local place, out = process.args[1] or "build/place.rbxl", process.args[2] or "build/people.json"
local emu = Emu.load(place)
local game = emu.game
local TownLife = emu.require(game:GetService("StarterPlayer").StarterPlayerScripts.Client.TownLife)
local Gui = require("./gui")

local folder = Instance.new("Folder")
folder.Name = "Townspeople"
folder.Parent = game.Workspace
-- Every hairdo and top, in shirts and skins from the game's lists.
local LOOKS = {
	{ "tee", "short", false, "walk" },
	{ "stripe", "long", false, "walk" },
	{ "jacket", "cap", false, "linger" },
	{ "hoodie", "ponytail", true, "walk" },
	{ "polo", "bun", false, "linger" },
	{ "tee", "curly", true, "dog" },
	{ "jacket", "buzz", false, "sit" },
	{ "tee", "beanie", false, "jog" },
}
local n = #LOOKS
local SPACING = tonumber(process.env.SPACING or "") or 3.2
local parts = {}
for i, l in LOOKS do
	local p = TownLife._person(`p{i * 7919}`, "1", { 0, 0 })
	p.type = if l[4] == "dog" then "dog" elseif l[4] == "jog" then "jogger" else "walker"
	p.look.top, p.look.hair, p.look.shorts = l[1], l[2], l[3]
	if l[2] == "beanie" then
		p.colors.hair = "#d32f2f"
	end
	p.pos = { (i - (n + 1) / 2) * SPACING / 10, 0 }
	p.dogPos = { p.pos[1] + 0.25, 0.25 }
	p.heading = tonumber(process.env.HEADING or "") or 0
	p.state = if l[4] == "linger" or l[4] == "sit" then "linger" else "walk"
	p.sit = l[4] == "sit"
	p.stride = i * 0.9
	p.fig = TownLife._figure(p, folder)
	local list, cfs = {}, {}
	TownLife._draw(Vector3.new(0, 0, 0), p, 1.3, nil, list, cfs)
	for j, x in list do
		x.CFrame = cfs[j]
	end
end
local ground = Instance.new("Part")
ground.Size = Vector3.new(80, 1, 60)
ground.CFrame = CFrame.new(0, -0.5, 0)
ground.Color = roblox.Color3.fromRGB(176, 160, 150)
ground.Parent = game.Workspace
table.insert(parts, Gui.partOf(ground))
-- A Roblox character's height, for scale: a thin post 5.3 studs tall at the end of the line.
local post = Instance.new("Part")
post.Size = Vector3.new(0.2, 5.3, 0.2)
post.CFrame = CFrame.new((n + 1) / 2 * SPACING, 2.65, 0)
post.Color = roblox.Color3.fromRGB(30, 30, 30)
post.Parent = game.Workspace
table.insert(parts, Gui.partOf(post))
local count = 0
for _, d in folder:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 and d.CFrame.Position.Y > -100 then
		table.insert(parts, Gui.partOf(d))
		count += 1
	end
end
fs.writeFile(out, serde.encode("json", { parts = parts }))
print(`drew {n} townspeople in {count} parts`)
