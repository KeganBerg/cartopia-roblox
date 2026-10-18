--!strict
-- The loading screen's pictures (ReplicatedFirst.Loading.SplashImages) as the clients should ask
-- for them. Open Cloud may hand back a decal's id for an uploaded picture rather than its image's;
-- a decal loads with InsertService, and its Texture names the image. Each id found that way is
-- shared as a Workspace attribute Splash<id> = "rbxassetid://<image>", which the loading screen
-- uses in place of the raw id.
--
-- Also names each player's race car and paint (SplashCar, SplashPaint on the player) as soon as
-- their save is open, so their own car parks on the loading screen.

local InsertService = game:GetService("InsertService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")

local Images = require(ReplicatedFirst:WaitForChild("Loading"):WaitForChild("SplashImages")) :: any

local Splash = {}

local tried: { [number]: boolean } = {}

local function resolve(id: number)
	if id == 0 or tried[id] then
		return
	end
	tried[id] = true
	task.spawn(function()
		local ok, model = pcall(InsertService.LoadAsset, InsertService, id)
		if not ok or not model then
			return -- already an image's own id
		end
		local decal = model:FindFirstChildWhichIsA("Decal", true)
		local texture = decal and decal.Texture
		if texture and texture ~= "" then
			workspace:SetAttribute(`Splash{id}`, texture)
		end
		model:Destroy()
	end)
end

-- The pictures every player sees, looked up once when the server starts.
function Splash.start()
	resolve(Images.wordmark)
	resolve(Images.vignette)
	for _, kind in { Images.sun, Images.town } do
		for _, shapes in kind do
			resolve(shapes.wide)
			resolve(shapes.tall)
		end
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
