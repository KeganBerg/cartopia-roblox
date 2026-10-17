-- Client entry point: camera, input, HUD and effects will hang off this. For now it sets the clock
-- and connects to the server (Remote).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Js = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"):WaitForChild("__js"))
Js.setClock(function()
	return DateTime.now().UnixTimestampMillis
end)

require(script.Remote)
