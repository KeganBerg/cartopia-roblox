-- Client entry point: camera, input, HUD and effects will hang off this. Placeholder for now.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"))

Util.setClock(function()
	return DateTime.now().UnixTimestampMillis
end)
