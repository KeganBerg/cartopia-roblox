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
local socialRemote = remotes:WaitForChild("Social") :: RemoteFunction
local webLinkRemote = remotes:WaitForChild("WebLink") :: RemoteFunction

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
	["like limit"] = "That's all 40 likes for today",
	["liked"] = "You already liked this town",
	["gift limit"] = "That's all 10 gifts for today",
	["card limit"] = "That's all 20 postcards for today",
	["sent today"] = "One a day to each friend",
	["not a friend"] = "Send these to friends or drivers in this server",
	["town not loaded"] = "Your town is still loading",
	["slow down"] = "Slow down a little",
	["need fuel"] = "Not enough fuel to race",
	["You need a car to race"] = "You need a car to race",
	["That race isn't open yet"] = "That race isn't open yet",
	["too quick"] = "That race didn't count. Try again.",
	filter = "Couldn't check that name. Try again.",
	["paid crates restricted"] = "Gem crates aren't available where you live",
	["not here"] = "They've left this server",
	["racing"] = "One of you is already in a live race",
	["wait"] = "Give them a moment before asking again",
	["expired"] = "That challenge has run out",
	["declined"] = "Maybe next time",
	["crew house"] = "Build a Crew House first",
	["coins"] = "Not enough coins",
	["in a crew"] = "You're already in a crew",
	["name"] = "Crew names are 3 to 24 letters",
	["tag"] = "Tags are 2 to 4 letters or numbers",
	["name taken"] = "Another crew has that name",
	["tag taken"] = "Another crew has that tag",
	["name filtered"] = "Try a different crew name",
	["tag filtered"] = "Try a different tag",
	["motto filtered"] = "Try a different motto",
	["motto"] = "Mottos are 140 letters at most",
	["closed"] = "That crew isn't taking new drivers",
	["full"] = "That crew is full",
	["level"] = "Your level is too low for that crew",
	["asks"] = "You can ask 5 crews at a time",
	["busy"] = "That crew has too many requests right now",
	["gone"] = "That crew is gone",
	["rank"] = "Only the Leader or a Co-Leader can do that",
	["no crew"] = "You're not in a crew",
	["asked today"] = "You already asked today",
	["no parts"] = "You have no parts to give",
	["part full"] = "That request is already filled",
	["part limit"] = "You can give 5 to each request and 20 a day",
	["chest expired"] = "That crew chest has expired",
	["chest opened"] = "You already opened that crew chest",
	["chest points"] = "Add 30 crew points to earn the chest",
	["chest locked"] = "Your crew has not reached its goal yet",
	["battle locked"] = "That battle chest isn't yours to open",
	["war locked"] = "Your crew needs more war points for that chest",
	["war points"] = "Score 20 war points yourself to earn war chests",
	["no war"] = "Your crew has no war this week",
	["not rival"] = "They're not in the rival crew",
	["no ghost"] = "They have no car to race yet",
	["no war races"] = "No war races left today",
	["try again"] = "That didn't work. Try again.",
	["not playing"] = "They aren't playing Cartopia right now",
	["not friends"] = "You can only join your friends",
	["couldn't join"] = "Couldn't join their server. Try again.",
	["already helped"] = "You already helped there today",
	["town done"] = "That's all 5 helps here today",
	["day done"] = "You've helped plenty of towns today. Come back tomorrow!",
	["not a business"] = "Only businesses need a hand",
	["already in a party"] = "You're already in a kart party",
	["The party has already started"] = "That kart party has already started",
	["The party is full"] = "That kart party is full",
	["Wait for someone to join"] = "Wait for someone to join your party",
	["Your visitor already left town."] = "Your visitor already left town.",
	["You already raced them"] = "Your visitor already left town.",
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

-- Spins today's Daily Spin on the server (server/Crates spin, through the Crate remote). Returns
-- the spin { slice, open } for the wheel to land on, or nil (with a toast saying why).
function Remote.spin(): any?
	local sent, ok, result = pcall(crateRemote.InvokeServer, crateRemote, "wheel")
	if not sent then
		warn(`[Cartopia] wheel: {ok}`)
		failed:Fire("Couldn't reach the server. Try again.")
		return nil
	end
	if not ok then
		warn(`[Cartopia] wheel refused: {result}`)
		failed:Fire(if result == "spun today" then "Spun today. Back tomorrow!" else WHY[result] or "Couldn't spin. Try again.")
		return nil
	end
	return result
end

-- The Bank's gem and car packs (server/Purchases): "shop" -> { open, packs = { [id] = { robux,
-- owned } } }, or "buy" with a pack id, which opens Roblox's purchase prompt. Returns ok and the
-- answer or why not ("soon", "crew", "owned").
function Remote.bank(op: string, id: string?): (boolean, any)
	local bankRemote = remotes:FindFirstChild("Bank") :: RemoteFunction?
	if not bankRemote then
		return false, "soon"
	end
	local sent, ok, result = pcall(bankRemote.InvokeServer, bankRemote, op, id)
	if not sent then
		warn(`[Cartopia] bank {op}: {ok}`)
		return false, "no answer"
	end
	return ok, result
end

-- Playing together (server/Social): "players", "visit" (user id), "home", "help" (building uid)
-- or "join" (a friend's user id). Returns ok and the answer, toasting why when it's refused.
function Remote.social(op: string, arg: any?, quiet: boolean?): (boolean, any)
	local sent, ok, result = pcall(socialRemote.InvokeServer, socialRemote, op, arg)
	if not sent then
		warn(`[Cartopia] social {op}: {ok}`)
		failed:Fire("Couldn't reach the server. Try again.")
		return false, "no answer"
	end
	if not ok and not quiet then
		failed:Fire(WHY[result] or "That didn't work. Try again.")
	end
	return ok, result
end

-- Brings the player's web town over with a code from the web game's Settings (server/WebLink).
-- Returns ok, or false and what to tell the player.
local LINK_WHY = {
	code = "That code didn't work. Get a new one on the web.",
	other = "That web town is already on another Roblox account",
	offline = "Couldn't reach the web game. Try again soon.",
	tries = "Too many tries. Rejoin to try again.",
	["slow down"] = "Wait a moment, then try again",
	["town not loaded"] = "Your town is still loading",
}
function Remote.webLink(code: string): (boolean, string?)
	local sent, ok, why = pcall(webLinkRemote.InvokeServer, webLinkRemote, code)
	if not sent then
		return false, "Couldn't reach the server. Try again."
	end
	if ok then
		return true, nil
	end
	return false, LINK_WHY[why] or "That didn't work. Try again."
end

-- Town visitors (server/Visitors): "next", or "claim" / "leave" with the visitor's id. Returns ok
-- and the answer or why not, quietly (the visitors' own toasts say what happened).
function Remote.visitor(op: string, id: string?): (boolean, any)
	local visitorRemote = remotes:FindFirstChild("Visitor") :: RemoteFunction?
	if not visitorRemote then
		return false, "soon"
	end
	local sent, ok, result = pcall(visitorRemote.InvokeServer, visitorRemote, op, id)
	if not sent then
		warn(`[Cartopia] visitor {op}: {ok}`)
		return false, "no answer"
	end
	return ok, result
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
