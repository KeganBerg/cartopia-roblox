-- Client entry point: sets the clock, starts the town's day and night (DayNight), connects to the server (Remote), draws the countryside round the town (Countryside), its traffic and townspeople (TownLife) and the race and crowd at a Speedway (SpeedwayLife), and starts the HUD, which
-- owns the screens, job bubbles and building placement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Js = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"):WaitForChild("__js"))
Js.setClock(function()
	return DateTime.now().UnixTimestampMillis
end)

require(script.DayNight).start()
require(script.TownCamera).start()
require(script.Remote)
require(script.Countryside).start()
require(script.TownLife).start()
require(script.SpeedwayLife).start()
require(script.Hud).start()
