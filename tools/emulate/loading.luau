--!nocheck
-- Builds the loading screen (ReplicatedFirst.Loading.LoadingScreen) as it looks a few seconds in,
-- for each time of day on a wide and a phone screen, and writes its layout for render.mjs, which
-- draws the pictures from build/splash (run tools/splash/build.mjs first).
--
--   node tools/splash/build.mjs <web repo> && rojo build -o build/place.rbxl
--   lune run tools/emulate/loading.luau build/place.rbxl [car] [#paint] [seconds] [standin|go]
-- "standin" draws it before any picture has downloaded; "late" with the pictures arriving after
-- the layout has settled; "go" half way through the car driving off.
--   node tools/emulate/render.mjs <web repo> build/empty.json out.png build/loading-day-wide-gui.json

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Emu = require("./roblox")
local Gui = require("./gui")
local roblox = require("@lune/roblox")

local emu = Emu.load(process.args[1] or "build/place.rbxl")
local car, paint, at = process.args[2] or "hotshot", process.args[3] or "#d32f2f", tonumber(process.args[4]) or 2.5
local mode = process.args[5]
local folder = emu.game:GetService("ReplicatedFirst").Loading
-- Pretend every picture is uploaded and downloaded.
local Images = emu.require(folder.SplashImages)
local n = 0
local function fake(t)
	for k, v in t do
		if type(v) == "number" and v == 0 and k ~= "cx" and k ~= "cy" and k ~= "x" and k ~= "y" then
			n += 1
			t[k] = n
		elseif type(v) == "table" then
			fake(v)
		end
	end
end
fake(Images.sun)
fake(Images.town)
fake(Images.cars)
fake(Images.tiles)
Images.wordmark = 9001
Images.vignette = 9002
Images.shadow = 9003
local LoadingScreen = emu.require(folder.LoadingScreen)
fs.writeFile("build/empty.json", "{\"parts\": []}")
for _, size in { { "wide", 1280, 800 }, { "phone", 390, 844 }, { "landscape", 932, 430 } } do
	for _, tod in { "day", "dusk", "night" } do
		local screen
		screen = LoadingScreen.new(roblox.Instance.new("Folder"), {
			isLoaded = function()
				if mode == "late" then
					return screen.clock > 3
				end
				return mode ~= "standin"
			end,
			size = roblox.Vector2.new(size[2], size[3]),
		})
		screen:setTime(tod)
		screen:setCar(car, paint)
		screen:set("Loading your town…", 0.45)
		for _ = 1, math.floor(at * 30) do
			screen:step(1 / 30)
		end
		if mode == "go" then
			screen.goSince = screen.clock
			for _ = 1, 12 do
				screen:step(1 / 30)
			end
		end
		fs.writeFile(`build/loading-{tod}-{size[1]}-gui.json`, serde.encode("json", { nodes = Gui.dump(screen.gui, size[2], size[3]), bubbles = {} }))
	end
end
print("wrote build/loading-*-gui.json")
