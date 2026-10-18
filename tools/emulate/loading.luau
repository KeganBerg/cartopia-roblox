--!nocheck
-- Builds the loading screen (ReplicatedFirst.Loading.LoadingScreen) part way through, in each
-- time of day, and writes its layout for render.mjs to picture.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/loading.luau build/place.rbxl
--   node tools/emulate/render.mjs <web repo> build/empty.json build/loading-day.png build/loading-day-gui.json

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local Gui = require("./gui")
local roblox = require("@lune/roblox")

local emu = Emu.load(process.args[1] or "build/place.rbxl")
local LoadingScreen = emu.require(emu.game:GetService("ReplicatedFirst").Loading.LoadingScreen)
fs.writeFile("build/empty.json", "{\"parts\": []}")
for _, tod in { "day", "dusk", "night" } do
	local holder = roblox.Instance.new("Folder")
	local screen = LoadingScreen.new(holder)
	screen:tint(tod)
	screen:set("Painting the town", 0.72)
	screen:step(10)
	fs.writeFile(`build/loading-{tod}-gui.json`, serde.encode("json", { nodes = Gui.dump(screen.gui, 1280, 800), bubbles = {} }))
end
print("wrote build/loading-*-gui.json")
