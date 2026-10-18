--!strict
-- Has the server look up the images inside the loading screen's pictures
-- (ReplicatedFirst.Loading.SplashImages) first, then every texture's (see Shared.Pictures).
--
-- Also names each player's race car and paint (SplashCar, SplashPaint on the player) as soon as
-- their save is open, so their own car parks on the loading screen.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Images = require(ReplicatedFirst:WaitForChild("Loading"):WaitForChild("SplashImages")) :: any
local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"):WaitForChild("Catalog")) :: any
local Pictures = require(script.Parent.Pictures)

local Splash = {}

local function resolve(id: number?)
	Pictures.resolve(id, true)
end

-- The pictures every player sees, looked up once when the server starts.
-- In the order they're needed: the screen as it looks now (the time of day worked out as the
-- loading screen does), then the other times of day.
function Splash.start()
	local m = (DateTime.now().UnixTimestampMillis % 1200000) / 1200000
	local d = math.abs(m + 0.05 * math.sin(2 * math.pi * m) - 0.5)
	local x = math.clamp((0.3 - d) / 0.2, 0, 1)
	local n = x * x * (3 - 2 * x)
	local now = if n > 0.7 then "night" elseif n > 0.08 then "dusk" else "day"
	-- Ahead of the 3D shapes: this time of day's screen, then the other times of day's.
	resolve(Images.wordmark)
	resolve(Images.vignette)
	resolve(Images.shadow)
	local tiles = Images.tiles or {}
	for _, time in { now, "day", "dusk", "night" } do
		for _, kind in { Images.town, Images.sun } do
			resolve(kind[time].wide)
			resolve(kind[time].tall)
		end
		-- Big screens' sharper tiles of them.
		for _, name in { "town", "sun" } do
			for _, shape in { "wide", "tall" } do
				for _, t in tiles[`{name}-{time}-{shape}`] or {} do
					resolve(t.id)
				end
			end
		end
	end
	-- Then every texture: the ground's first, as each town is drawn on it.
	local textures = Catalog.TEXTURES or {}
	for _, key in { "grass", "meadow" } do
		resolve(textures[key] and textures[key].image)
	end
	for _, t in textures do
		Pictures.resolve(t.image)
	end
end

-- A player's car (a CARS id) and paint (#rrggbb) for their loading screen.
function Splash.forPlayer(player: Player, model: string?, paint: string?)
	local car = model and Images.cars[model]
	if car then
		resolve(car.car)
		resolve(car.paint)
	else
		local hotshot = Images.cars.hotshot
		if hotshot then
			resolve(hotshot.car)
			resolve(hotshot.paint)
		end
	end
	player:SetAttribute("SplashPaint", paint)
	player:SetAttribute("SplashCar", model or "hotshot")
end

return Splash
