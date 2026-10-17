--!strict
-- The client's link to its town on the server. Keeps a copy of the town in the shared store
-- (useGame), loaded from what the server sends, so UI code can read it the way the web game's
-- UI does. Changes go through Remote.act; the server's answer comes back as a new snapshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any

local remotes = ReplicatedStorage:WaitForChild("Cartopia")
local actRemote = remotes:WaitForChild("Act") :: RemoteFunction
local townEvent = remotes:WaitForChild("Town") :: RemoteEvent

local Remote = {}

-- Asks the server to run a store action, e.g. Remote.act("tapBuilding", uid).
-- Returns ok and the action's result (or why it was refused).
function Remote.act(name: string, ...: any): (boolean, any)
	return actRemote:InvokeServer(name, ...)
end

townEvent.OnClientEvent:Connect(function(snap)
	store.useGame.getState().loadSave(snap.save)
	store.useGame.setState({ need = snap.need, panel = snap.panel })
	for _, text in snap.toasts do
		print(`[Cartopia] {text}`) -- placeholder until the HUD shows toasts
	end
end)

return Remote
