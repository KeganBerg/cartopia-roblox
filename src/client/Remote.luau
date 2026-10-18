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
local raceRemote = remotes:WaitForChild("Race") :: RemoteFunction
local crateRemote = remotes:WaitForChild("Crate") :: RemoteFunction
local meshRemote = remotes:WaitForChild("Meshes") :: RemoteFunction

local Remote = {}

-- Fires after every snapshot from the server: (snap) where snap is { save, need, panel, toasts }.
local changed = Instance.new("BindableEvent")
Remote.changed = changed.Event
-- The last snapshot, or nil until the town arrives.
Remote.last = nil :: any
Remote.search = nil :: any

-- Fires when the server couldn't run an action at all (not loaded yet, too many taps, an error),
-- with what to tell the player, so a tap never silently does nothing.
local failed = Instance.new("BindableEvent")
Remote.failed = failed.Event

local WHY = {
	["town not loaded"] = "Your town is still loading",
	["slow down"] = "Slow down a little",
	["need fuel"] = "Not enough fuel to race",
	["You need a car to race"] = "You need a car to race",
	["That race isn't open yet"] = "That race isn't open yet",
	["too quick"] = "That race didn't count. Try again.",
	filter = "Couldn't check that name. Try again.",
	["paid crates restricted"] = "Buying crates isn't available where you live",
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

-- Asks the server's race desk (server/Races): "rivals", "campaign", "start" { mode, which } or
-- "finish" (the race's presses). Returns ok and the answer, toasting why when it's refused
-- (quiet: no toast, for the menu's own lookups).
function Remote.race(op: string, arg: any?, quiet: boolean?): (boolean, any)
	local sent, ok, result = pcall(raceRemote.InvokeServer, raceRemote, op, arg)
	if not sent then
		warn(`[Cartopia] race {op}: {ok}`)
		failed:Fire("Couldn't reach the server. Try again.")
		return false, "no answer"
	end
	if not ok then
		warn(`[Cartopia] race {op} refused: {result}`)
		-- Out of fuel opens the fuel menu instead (the server sends it with the snapshot).
		if not quiet and result ~= "need fuel" then
			failed:Fire(WHY[result] or "That didn't work. Try again.")
		end
	end
	return ok, result
end

-- Opens crates on the server (server/Crates): count of crate id, or the free crate from source
-- `free`. Returns the opens for the reveal, or nil (the "you need" popup or a toast says why).
function Remote.crate(id: string, free: string?, count: number?): { any }?
	local sent, ok, result = pcall(crateRemote.InvokeServer, crateRemote, id, free, count or 1)
	if not sent then
		warn(`[Cartopia] crate {id}: {ok}`)
		failed:Fire("Couldn't reach the server. Try again.")
		return nil
	end
	if not ok then
		warn(`[Cartopia] crate {id} refused: {result}`)
		-- Short on coins or level opens the "you need" popup instead (sent with the snapshot).
		if result ~= "not opened" then
			failed:Fire(WHY[result] or "Couldn't open the crate. Try again.")
		end
		return nil
	end
	return result
end

townEvent.OnClientEvent:Connect(function(snap)
	store.useGame.getState().loadSave(snap.save)
	store.useGame.setState({ need = snap.need, panel = snap.panel })
	-- One-off news for the pop-ups (client/Popups); each pop-up clears its own when closed.
	if snap.popups and next(snap.popups) ~= nil then
		store.useGame.setState(snap.popups)
	end
	Remote.last = snap
	-- Rusty's search in progress (not part of the save), or nil.
	Remote.search = snap.search
	changed:Fire(snap)
end)

-- Asks the server for a car's mod meshes (they load the first time a car needs them) and waits
-- until they're here. Returns at once when they already are.
local meshesHere: { [string]: boolean } = {}
function Remote.meshesFor(car: string)
	if meshesHere[car] then
		return
	end
	local sent, ok = pcall(meshRemote.InvokeServer, meshRemote, car)
	if sent and ok then
		meshesHere[car] = true
	end
end

return Remote
