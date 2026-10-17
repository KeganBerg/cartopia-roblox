-- Client entry point: sets the clock, connects to the server (Remote) and starts the HUD, which
-- owns the screens, job bubbles and building placement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Js = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"):WaitForChild("__js"))
Js.setClock(function()
	return DateTime.now().UnixTimestampMillis
end)

require(script.Remote)
require(script.Hud).start()
