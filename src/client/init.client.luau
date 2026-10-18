-- Client entry point: sets the clock, starts the town's day and night (DayNight), connects to the server (Remote), draws the countryside round the town (Countryside), the far land and sky past it (Horizon), its traffic and townspeople (TownLife), the traffic and verges on the roads between plots (WorldLife), getting in any car on foot (GetIn) and the race and crowd at a Speedway (SpeedwayLife), sets car skins moving (SkinMotion), starts the music and sounds (Sounds), and starts the HUD, which
-- owns the screens, job bubbles and building placement, and the badge over Rusty's (RescueBadge).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Js = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"):WaitForChild("__js"))
Js.setClock(function()
	return DateTime.now().UnixTimestampMillis
end)

require(script.DayNight).start()
require(script.TownCamera).start()
require(script.Remote)
require(script.Countryside).start()
require(script.Horizon).start()
require(script.TownLife).start()
require(script.WorldLife).start()
require(script.GetIn).start()
require(script.SpeedwayLife).start()
require(script.SkinMotion).start()
require(script.Hud).start()
-- The town's weather and Rave Mode, over what DayNight and the HUD draw.
require(script.TownWeather).start()
require(script.Rave).start()
require(script.RescueBadge).start()
require(script.Sounds).start()
