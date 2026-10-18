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

-- Fires after every snapshot from the server: (snap) where snap is { save, need, panel, toasts }.
local changed = Instance.new("BindableEvent")
Remote.changed = changed.Event
-- The last snapshot, or nil until the town arrives.
Remote.last = nil :: any

-- Fires when the server couldn't run an action at all (not loaded yet, too many taps, an error),
-- with what to tell the player, so a tap never silently does nothing.
local failed = Instance.new("BindableEvent")
Remote.failed = failed.Event

local WHY = {
	["town not loaded"] = "Your town is still loading",
	["slow down"] = "Slow down a little",
}

-- Asks the server to run a store action, e.g. Remote.act("tapBuilding", uid).
-- Returns ok and the action's result (or why it was refused).
function Remote.act(name: string, ...: any): (boolean, any)
	local sent, ok, result = pcall(actRemote.InvokeServer, actRemote, name, ...)
	if not sent then
		warn(`[Cartopia] {name}: {ok}`)
		failed:Fire("Couldn't reach the server. Try again.")
		return false, "no answer"
	end
	if not ok then
		warn(`[Cartopia] {name} refused: {result}`)
		failed:Fire(WHY[result] or "That didn't work. Try again.")
	end
	return ok, result
end

townEvent.OnClientEvent:Connect(function(snap)
	store.useGame.getState().loadSave(snap.save)
	store.useGame.setState({ need = snap.need, panel = snap.panel })
	Remote.last = snap
	changed:Fire(snap)
end)

return Remote
