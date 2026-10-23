--!nocheck
-- Presses every button on every screen, in the emulator, and reports the ones that throw an
-- error or reach the server with a request it refuses.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/clicks.luau build/place.rbxl

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

-- Real signals, one per instance and event, so clicks can be fired.
local VERBOSE = process.args[2] == "-v"
local nextId = 0
local handlerErrors = {}
local signals = {}
local function idOf(inst)
	local id = inst:GetAttribute("__emu")
	if not id then
		nextId += 1
		id = nextId
		inst:SetAttribute("__emu", id)
	end
	return id
end
local function signalFor(inst, name)
	local key = idOf(inst) .. name
	local s = signals[key]
	if s then
		return s
	end
	local fns = {}
	s = { fns = fns }
	function s:Connect(fn)
		local c = { Connected = true }
		fns[c] = fn
		function c:Disconnect()
			fns[c] = nil
			c.Connected = false
		end
		return c
	end
	function s:Once(fn)
		local c
		c = s:Connect(function(...)
			c:Disconnect()
			fn(...)
		end)
		return c
	end
	function s:Wait() end
	function s:Fire(...)
		-- Each handler runs on its own, as in Roblox: one that throws doesn't stop the rest.
		for _, fn in table.clone(fns) do
			local ok, err = pcall(fn, ...)
			if not ok and not string.find(tostring(err), "has been destroyed") then
				table.insert(handlerErrors, `{name}: {err}`)
			end
		end
	end
	signals[key] = s
	return s
end
for _, pair in { { "GuiButton", "Activated" }, { "RunService", "RenderStepped" }, { "RunService", "Stepped" }, { "GuiButton", "MouseButton1Down" }, { "GuiButton", "MouseButton1Up" }, { "Instance", "Destroying" }, { "Instance", "ChildAdded" }, { "BindableEvent", "Event" }, { "RemoteEvent", "OnClientEvent" }, { "TextBox", "FocusLost" }, { "GuiObject", "InputBegan" }, { "GuiObject", "InputChanged" }, { "UserInputService", "InputBegan" }, { "UserInputService", "InputChanged" }, { "UserInputService", "InputEnded" } } do
	roblox.implementProperty(pair[1], pair[2], function(inst)
		return signalFor(inst, pair[2])
	end)
end
roblox.implementMethod("BindableEvent", "Fire", function(inst, ...)
	signalFor(inst, "Event"):Fire(...)
end)
-- Destroy fires Destroying first, as Roblox does.
local destroy = Instance.new("Folder").Destroy
roblox.implementMethod("Instance", "Destroy", function(inst)
	for _, d in inst:GetDescendants() do
		local id = d:GetAttribute("__emu")
		if id and signals[id .. "Destroying"] then
			signals[id .. "Destroying"]:Fire()
		end
	end
	local id = inst:GetAttribute("__emu")
	if id and signals[id .. "Destroying"] then
		signals[id .. "Destroying"]:Fire()
	end
	inst.Parent = nil
end)

local Emu = require("./roblox")
local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local NOW = 1760000000000
local Js = emu.require(RS.Shared.Game.__js)
Js.setClock(function()
	return NOW
end)
local store = emu.require(RS.Shared.Game.store)
local Towns = emu.require(SSS.Server.Towns)
local towns = Towns.new(store, function()
	return NOW
end)
towns:open(1, nil)
-- A town with a car shop and a car, so the garage and upgrade screens have something in them.
towns:run(1, "placeBuilding", "rescue", 12, 12)
towns:run(1, "buyCar", "pip", "#c62828")
-- Today's Daily Spin taken, so it doesn't open itself at the start (client/Popups/DailySpin); the
-- wheel is spun on purpose further down.
towns:_with(1, function()
	-- Past the tutorial, so the HUD shows every button (a new town at step 0 is walked at the end).
	store.useGame.setState({ lastDaily = store.today(), tutorial = 99 })
end)

local player = Instance.new("Player")
player.Name = "Player1"
player.UserId = 1
pcall(function() player.DisplayName = "Player1" end)
Instance.new("PlayerGui").Parent = player
local players = game:GetService("Players")
players.LocalPlayer = player
player.Parent = players
-- Roblox's rules for this player (server/Policies sets these): paid crates allowed, as in most
-- places; the crate depot is also pictured restricted further down.
local Policy = emu.require(game:GetService("ReplicatedStorage").Shared.Policy)
local function setRules(info)
	for k, v in Policy.toAttributes(Policy.fromInfo(info)) do
		player:SetAttribute(k, v)
	end
end
setRules({ ArePaidRandomItemsRestricted = false })
-- The town visitors' clock (ms past NOW), which the client's clock keeps to (see the visitors below).
local visitClock = 0
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return (NOW + visitClock) / 1000
end)
local remotes = Instance.new("Folder")
remotes.Name = "Cartopia"
local act = Instance.new("RemoteFunction")
act.Name = "Act"
act.Parent = remotes
local townEvent = Instance.new("RemoteEvent")
townEvent.Name = "Town"
townEvent.Parent = remotes
local raceRemote = Instance.new("RemoteFunction")
raceRemote.Name = "Race"
raceRemote.Parent = remotes
local crateRemote = Instance.new("RemoteFunction")
crateRemote.Name = "Crate"
crateRemote.Parent = remotes
local meshRemote = Instance.new("RemoteFunction")
meshRemote.Name = "Meshes"
meshRemote.Parent = remotes
local socialRemote = Instance.new("RemoteFunction")
socialRemote.Name = "Social"
socialRemote.Parent = remotes
local bankRemote = Instance.new("RemoteFunction")
bankRemote.Name = "Bank"
bankRemote.Parent = remotes
local kartEvent = Instance.new("RemoteEvent")
kartEvent.Name = "Kart"
kartEvent.Parent = remotes
-- The race desk, as init.server.luau makes it (a seeded stand-in for Random).
local seed = 7
local G = RS.Shared.Game
local raceClock = 0
local races = emu.require(SSS.Server.Races).new(towns, {
	store = store,
	data = emu.require(G.data),
	raceCar = emu.require(G.raceCar),
	fairRace = emu.require(G.fairRace),
	fairPi = emu.require(G.fairPi),
	grip = emu.require(G.grip),
	weather = emu.require(G.weather),
	venues = emu.require(G.scene_venues),
	paintRivals = emu.require(G.paintRivals),
	rivals = emu.require(G.rivals),
	distance = emu.require(G.distance),
	DragRace = emu.require(RS.Shared.DragRace),
	tourRivals = emu.require(RS.Shared.TourRivals),
	random = {
		NextNumber = function()
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end,
		NextInteger = function(self, lo, hi)
			return lo + math.floor(self:NextNumber() * (hi - lo + 1))
		end,
	},
	clock = function()
		return raceClock
	end,
	modes = (function()
		local out = {}
		for _, m in SSS.Server.Modes:GetChildren() do
			local mode = emu.require(m)
			out[mode.id] = mode
		end
		return out
	end)(),
	game = function(name)
		return emu.require(G[name])
	end,
	boards = {
		trial = emu.require(SSS.Server.Boards).new("Trial", nil, function()
			return raceClock
		end),
	},
	ghosts = emu.require(SSS.Server.Ghosts).new(nil, function()
		return NOW // 1000 + raceClock
	end),
	-- Two other players to race: one here with a time, a friend with only a par.
	people = function()
		return { { userId = 2, name = "Mika", here = true }, { userId = 3, name = "Juno" } }
	end,
})
-- The kart desk, as init.server.luau makes it.
local karts = emu.require(SSS.Server.Karts).new(towns, {
	store = store,
	data = emu.require(G.data),
	kart = emu.require(G.kart),
	gpBeat = emu.require(G.gpBeat),
	raceCar = emu.require(G.raceCar),
	fairRace = emu.require(G.fairRace),
	boosts = emu.require(G.boosts),
	random = races.mods.random,
	clock = function()
		return raceClock
	end,
})
-- The kart party desk, as init.server.luau makes it: player 1 is this client, player 2 (Rosa)
-- has no game here, so what the server sends her is kept in partySent.
local partyTimers, partySent = {}, {}
-- checkSend, once it's defined below.
local partyCheck = nil
local parties = emu.require(SSS.Server.KartParty).new(towns, {
	store = store,
	data = emu.require(G.data),
	kart = emu.require(G.kart),
	raceCar = emu.require(G.raceCar),
	boosts = emu.require(G.boosts),
	random = races.mods.random,
	clock = function()
		return raceClock
	end,
	delay = function(sec, fn)
		table.insert(partyTimers, { at = raceClock + sec, fn = fn })
	end,
	send = function(userId, event, payload)
		if partyCheck then
			partyCheck(`kart {event}`, payload)
		end
		if userId == 1 or userId == 0 then
			signalFor(kartEvent, "OnClientEvent"):Fire(event, payload)
		end
		if userId ~= 1 then
			table.insert(partySent, { to = userId, event = event, payload = payload })
		end
	end,
	name = function(userId)
		return if userId == 1 then "You" else "Rosa"
	end,
})
-- Live drag races (server/Duels), as init.server.luau makes them: Rosa (player 2) has no game
-- here, so what she's sent is kept in duelSent.
local duelEvent = Instance.new("RemoteEvent")
duelEvent.Name = "Duel"
duelEvent.Parent = remotes
local duelSent = {}
local duels = emu.require(SSS.Server.Duels).new({
	clock = function()
		return raceClock
	end,
	send = function(userId, event, payload)
		if partyCheck then
			partyCheck(`duel {event}`, payload)
		end
		if userId == 1 then
			signalFor(duelEvent, "OnClientEvent"):Fire(event, payload)
		else
			table.insert(duelSent, { to = userId, event = event, payload = payload })
		end
	end,
	card = function(userId)
		return { name = if userId == 1 then "You" else "Rosa", town = if userId == 1 then "Home" else "Rosaville", level = 6, carName = "Pip", model = "pip", color = "#8e24aa", pi = 14, userId = userId }
	end,
	here = function(userId)
		return userId == 1 or userId == 2
	end,
	wait = function(sec)
		raceClock += sec
	end,
})
races.mods.duels = duels
races.mods.liveCard = duels.mods.card
-- What the client sends on the Prefs remote (its settings, to be kept with the account).
local prefsSent = {}
roblox.implementMethod("RemoteEvent", "FireServer", function(remote, event, payload)
	if remote.Name == "Prefs" then
		table.insert(prefsSent, event)
	end
	if remote.Name == "Duel" then
		partyCheck(`duel {event} from the client`, payload)
		if event == "pos" then
			duels:relay(1, payload)
		end
	end
	if remote.Name == "Kart" then
		partyCheck(`kart {event} from the client`, payload)
		if event == "ready" then
			parties:ready(1)
		else
			parties:relay(1, event, payload)
		end
	end
end)
do
	local g = races.mods.ghosts
	g:card(2, { car = "Pip", model = "pip", color = "#1e88e5", pi = 14, town = "Gearville" })
	g:record(2, 14.212, 14, "Pip", "pip", "#1e88e5")
	g:card(3, { car = "Pip", model = "pip", color = "#43a047", pi = 12, town = "Nitro Bay" })
	-- Mika left a taunt after beating Player1's ghost.
	g:finished(2, 1, 13.9, 14.4, true)
	g:taunt(2, 0, "Gearville")
end
-- Render steps, run by hand.
local renderSteps = {}
roblox.implementMethod("RunService", "BindToRenderStep", function(_, name, _, fn)
	renderSteps[name] = fn
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_, name)
	renderSteps[name] = nil
end)
remotes.Parent = RS
local lib = Instance.new("Folder")
lib.Name = "ModelLibrary"
lib:SetAttribute("Ready", true)
for _, kind in { "Cars", "Buildings", "Stripes" } do
	local f = Instance.new("Folder")
	f.Name = kind
	f.Parent = lib
end
lib.Parent = RS
-- SHOTS=1: the real models, and pictures of the race screens (build/shot-*.json, for render.mjs).
local SHOTS = process.env.SHOTS ~= nil
-- Previews draw the Call Cards from build/callcards as if their sheets were uploaded (render.mjs
-- finds each sheet by its Key), so the cards show their real scenes rather than stand-ins.
if SHOTS and require("@lune/fs").isFile("build/callcards/list.json") then
	local looks = emu.require(RS.Shared.CallCardLooks)
	for i in looks.sheets do
		looks.sheets[i] = i
	end
end
-- And the HUD's currency icons from build/icons (tools/icons/build.mjs), the same way.
if SHOTS and require("@lune/fs").isFile("build/icons/list.json") then
	emu.require(RS.Shared.IconImages).sheet = 1
end
if SHOTS then
	local Builder = emu.require(RS.Shared.Models.Builder)
	Builder.previewMeshes = true
	local data = emu.require(RS.Shared.Game.data)
	for _, car in data.CARS do
		local m = Builder.build(car.id, roblox.Color3.fromHex(car.colors[1]))
		if m then
			m.Name = car.id
			m.Parent = lib.Cars
		end
		local stripes = Builder.build(`stripe:{car.id}`)
		if stripes then
			stripes.Name = car.id
			stripes.Parent = lib.Stripes
		end
	end
	for _, def in data.BUILDINGS do
		local name = Builder.buildingName(def.id, 1)
		local m = name and Builder.build(name)
		if m then
			m.Name = def.id
			m.Parent = lib.Buildings
		end
	end
	for _, name in { "landmark:vanguard", "landmark:globe" } do
		local m = Builder.build(name)
		if m then
			m.Name = name
			m.Parent = lib.Buildings
		end
	end
end

-- What Roblox can't send through a remote, or HttpService:JSONEncode can't encode (the server
-- encodes every save to see if it changed): functions, NaN and infinities, tables mixing list and
-- named keys, lists with holes, and number keys that aren't a list.
local function unsafe(v, at, out, seen)
	local t = type(v)
	if t == "function" or t == "userdata" or t == "thread" then
		table.insert(out, `{at}: a {t}`)
	elseif t == "number" and (v ~= v or math.abs(v) == math.huge) then
		table.insert(out, `{at}: {v}`)
	elseif t == "table" then
		if seen[v] then
			return
		end
		seen[v] = true
		local n, strings, numbers = #v, 0, 0
		for k, x in v do
			if type(k) == "string" then
				strings += 1
			elseif type(k) == "number" then
				numbers += 1
			else
				table.insert(out, `{at}: a {type(k)} key`)
			end
			unsafe(x, `{at}.{tostring(k)}`, out, seen)
		end
		if strings > 0 and numbers > 0 then
			table.insert(out, `{at}: mixes list and named keys`)
		elseif numbers ~= n then
			table.insert(out, `{at}: number keys that aren't a list ({numbers} keys, length {n})`)
		end
	end
	return out
end
local function checkSend(what, v)
	for _, problem in unsafe(v, what, {}, {}) or {} do
		table.insert(calls, `CAN'T SEND {problem}`)
	end
end

partyCheck = checkSend

-- The server end of Cartopia.Act, as init.server.luau runs it.
local calls = {}
local function raceDesk(op, arg)
	local live = races.pending[1]
	if op == "finish" and live and live.mode == "live" then
		local DragRace = emu.require(RS.Shared.DragRace)
		local myTime = math.huge
		if DragRace.valid(arg) then
			myTime = DragRace.times(DragRace.replay(live.spec, arg))
		end
		live.extra.their = duels:finish(1, myTime)
	end
	local ran, result, why = pcall(function()
		if op == "duel" and type(arg) == "number" then
			local id, no = duels:challenge(1, arg)
			return if id then { id = id } else nil, no
		elseif op == "duelAnswer" and type(arg) == "table" then
			local id, no = duels:answer(1, arg.id, arg.yes == true)
			return if id then { id = id } else nil, no
		elseif op == "duelCancel" then
			duels:cancel(1)
			return true, nil
		elseif op == "duelInvites" then
			return duels:invitesFor(1), nil
		elseif op == "duelList" then
			return duels:others(1, { 1, 2 }), nil
		elseif op == "duelLeave" then
			duels:leave(1)
			return true, nil
		end
		if op == "rivals" then
			return races:quickRivals(1), nil
		elseif op == "campaign" then
			return races:campaign(1), nil
		elseif op == "rows" then
			return races:rows(1), nil
		elseif op == "list" and type(arg) == "table" then
			return races:list(1, arg.mode, arg.which), nil
		elseif op == "act" and type(arg) == "table" then
			return races:act(1, arg.mode, arg.which)
		elseif op == "start" and type(arg) == "table" then
			return races:start(1, arg.mode, arg.which)
		elseif op == "finish" then
			return races:finish(1, arg)
		elseif op == "kartStart" and type(arg) == "table" then
			return karts:start(1, arg.kind, arg.which)
		elseif op == "kartFinish" then
			return karts:finish(1, arg)
		elseif op == "partyList" then
			return parties:list(1), nil
		elseif op == "partyOpen" then
			return parties:open(1)
		elseif op == "partyJoin" then
			return parties:join(1, arg)
		elseif op == "partyLeave" then
			parties:leave(1)
			return true, nil
		elseif op == "partyGo" then
			return parties:go(1)
		elseif op == "partyFinish" then
			return parties:finish(1, arg)
		end
		return nil, "not a race"
	end)
	if not ran then
		table.insert(calls, `SERVER ERROR race {op}: {result}`)
		return false, "error"
	end
	checkSend(`race {op} result`, result)
	-- The emulator's client and server share one store, which the server leaves on its blank
	-- state: put the town back, as every snapshot does.
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	if result == nil then
		table.insert(calls, `race {op} refused: {why}`)
		return false, why
	end
	table.insert(calls, `ok race {op}`)
	return true, result
end
-- The server end of Cartopia.Crate.
local crateDesk = emu.require(SSS.Server.Crates).new(towns, store, emu.require(G.crates), function(_, pay, free)
	return Policy.canOpenCrate(Policy.fromAttributes(function(k)
		return player:GetAttribute(k)
	end), pay, free)
end)
-- The server end of Cartopia.Visitor (server/Visitors), on a clock of its own (visitClock ms past
-- NOW), with a seeded stand-in for math.random; the street race mode reaches it through the race desk.
local visitSeed = 5
local visitorDesk = emu.require(SSS.Server.Visitors).new(towns, {
	store = store,
	data = emu.require(G.data),
	random = function()
		visitSeed = (visitSeed * 1103515245 + 12345) % 2147483648
		return visitSeed / 2147483648
	end,
	now = function()
		return NOW + visitClock
	end,
})
races.mods.visitors = visitorDesk
local visitorRemote = Instance.new("RemoteFunction")
visitorRemote.Name = "Visitor"
visitorRemote.Parent = remotes
local webLinkRemote = Instance.new("RemoteFunction")
webLinkRemote.Name = "WebLink"
webLinkRemote.Parent = remotes
local function visitorCall(op, id)
	local ran, result, why = pcall(function()
		if op == "next" then
			return visitorDesk:next(1)
		elseif op == "claim" then
			return visitorDesk:claim(1, id)
		elseif op == "leave" then
			return visitorDesk:leave(1, id), nil
		end
		return nil, "not a visitor call"
	end)
	if not ran then
		table.insert(calls, `SERVER ERROR visitor {op}: {result}`)
		return false, "error"
	end
	checkSend(`visitor {op} result`, result)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	if result == nil then
		-- A visitor that left or was already paid is the game's own "too slow" (it says so).
		table.insert(calls, if why == "no such visitor" or why == "the visitor left" then `ok visitor {op} (gone)` else `visitor {op} refused: {why}`)
		return false, why
	end
	table.insert(calls, `ok visitor {op}`)
	return true, result
end
-- Playing together: a second player in the server (Rosa, not a friend yet) with a town to visit,
-- and Roblox friends elsewhere (Milo in another Cartopia server, Ada online, Sam offline).
towns:open(2, nil)
towns:run(2, "renameTown", "Rosaville")
local rosa = Instance.new("Player")
rosa.Name = "RosaRacer"
rosa.UserId = 2
pcall(function() rosa.DisplayName = "Rosa" end)
rosa.Parent = players
roblox.implementMethod("Players", "GetPlayerByUserId", function(_, id)
	for _, p in players:GetChildren() do
		if p:IsA("Player") and p.UserId == id then
			return p
		end
	end
	return nil
end)
roblox.implementMethod("Player", "IsFriendsWith", function(_, id)
	return id == 3 or id == 4 or id == 5
end)
roblox.implementMethod("Player", "GetFriendsOnline", function()
	return {
		{ VisitorId = 3, UserName = "MiloMoves", DisplayName = "Milo", PlaceId = game.PlaceId, GameId = "other-server", LocationType = 4 },
		{ VisitorId = 4, UserName = "AdaDrives", DisplayName = "Ada", PlaceId = 1234, GameId = "elsewhere", LocationType = 4 },
	}
end)
roblox.implementMethod("Players", "GetFriendsAsync", function()
	return {
		GetCurrentPage = function()
			return {
				{ Id = 3, Username = "MiloMoves", DisplayName = "Milo", IsOnline = true },
				{ Id = 4, Username = "AdaDrives", DisplayName = "Ada", IsOnline = true },
				{ Id = 5, Username = "SamSpeed", DisplayName = "Sam", IsOnline = false },
			}
		end,
	}
end)
roblox.implementMethod("SocialService", "CanSendGameInviteAsync", function()
	return true
end)
roblox.implementMethod("SocialService", "PromptGameInvite", function() end)
local Social = emu.require(SSS.Server.Social)
local social = Social.new({ towns = towns, data = emu.require(G.data), today = store.today })
-- The leaderboards (server/Leaders, kept in memory): a few drivers, Rosa in this server.
local Leaders = emu.require(SSS.Server.Leaders)
local leaders = Leaders.new(nil, function()
	return 0
end, function()
	return "2026-W42"
end)
for i, d in { { 2, "Rosa", "Rosaville", 640, 31, 52, 14 }, { 7, "Kai", "Kai Harbour", 910, 77, 120, 23 }, { 8, "Mina", "Mina Falls", 455, 12, 30, 9 } } do
	-- (Kai's crew tag shows on his rows.)
	leaders:record(d[1], d[2], d[3], { power = d[4], race_wins = d[5], trophies = d[6], level = d[7] }, nil, if i == 2 then { tag = "HK", emblem = "👑", color = "#1e88e5" } else nil)
end
-- The Car Meet (server/Meet, in memory): two displays, one already liked.
local Meet = emu.require(SSS.Server.Meet)
local meetDesk = Meet.new(nil, function()
	return 0
end, function()
	return "2026-10-19"
end)
do
	local Gm = emu.require(G.meet)
	local rosa = towns:save(2)
	meetDesk:publish(2, "Rosa", "Rosaville", rosa.level, Gm.showcaseOf(rosa.cars, nil))
	meetDesk:publish(7, "Kai", "Kai Harbour", 23, Gm.showcaseOf(towns:save(1).cars, nil))
	meetDesk:like(7, 2)
	meetDesk:like(1, 7)
end
-- Friends' mail (server/Mail, in memory): Rosa helped and sent fuel; Kai sent a postcard.
local Mail = emu.require(SSS.Server.Mail)
local mailDesk = Mail.new(nil, function()
	return 0
end, function()
	return "2026-10-19"
end)
mailDesk:help(2, "Rosa", "Rosaville", 1)
mailDesk:gift(2, "Rosa", "Rosaville", 1, "fuel")
mailDesk:gift(7, "Kai", "Kai Harbour", 1, "parts")
mailDesk:postcard(7, "Kai", "Kai Harbour", 1, "sunset", 2)
-- Crews (server/Crews, in memory): Rosa's open crew and Kai's, which takes requests.
local crewHouse = false
local crewN = 0
-- Crew weekly goals, on the real clock (the week is today's).
local goalDesk = emu.require(SSS.Server.CrewGoals).new({ clock = os.time })
local partsDesk = emu.require(SSS.Server.CrewParts).new({ clock = os.time })
-- Crew battles: their clock (moved on a week to end one), the desk and my opened chests.
local battles: any = { now = os.time() }
function battles.opened()
	local out = {}
	for k in (goalDesk:_get("k:1") or {}).opened or {} do
		out[k] = true
	end
	return out
end
local crewDesk = emu.require(SSS.Server.Crews).new({
	clock = function()
		return raceClock
	end,
	newId = function()
		crewN += 1
		return `crew{crewN}`
	end,
	emblems = emu.require(G.data).CLAN_EMBLEMS,
	colors = emu.require(G.data).CLAN_COLORS,
})
battles.desk = emu.require(SSS.Server.CrewBattles).new({
	clock = function()
		return battles.now
	end,
	crews = function()
		return crewDesk:browse()
	end,
	crew = function(id)
		return crewDesk:crew(id)
	end,
	emblems = emu.require(G.data).CLAN_EMBLEMS,
	colors = emu.require(G.data).CLAN_COLORS,
})
-- War races (server/Modes/War) reach the crew war through the race desk's mods.
races.mods.crewWar = {
	battles = battles.desk,
	crewOf = function(userId)
		return crewDesk:mineId(userId)
	end,
	nameOf = function()
		return "You"
	end,
}
local function crewWho(userId)
	local save = towns:save(1)
	return { name = if userId == 1 then "You" else "Rosa", town = save.townName, level = save.level or 1, power = 120, wins = save.racesWon or 0, trophies = save.trophies or 0 }
end
crewDesk:create(2, { name = "Rosa", town = "Rosaville", level = 12, power = 340, wins = 41, trophies = 52 }, { name = "Night Riders", tag = "NITE", emblem = "🐺", color = "#8e24aa", motto = "Fast at night, faster by day", minLevel = 1, joinMode = "open" })
crewDesk:create(7, { name = "Kai", town = "Kai Harbour", level = 30, power = 910, wins = 120, trophies = 77 }, { name = "Harbour Kings", tag = "HK", emblem = "👑", color = "#1e88e5", motto = "Ask nicely", minLevel = 5, joinMode = "request" })
local function socialDesk(op, arg)
	local ran, result, why = pcall(function()
		if op == "players" then
			local save = towns:save(2)
			return { { id = 2, name = "Rosa", user = "RosaRacer", townName = save.townName, level = save.level, trophies = save.trophies or 0, cars = #save.cars, friend = false, helped = #social:helped(1, 2) } }, nil
		elseif op == "visit" and arg == 2 then
			player:SetAttribute("Visiting", 2)
			player:SetAttribute("Helped", table.concat(social:helped(1, 2), ","))
			return social:townInfo(1, 2), nil
		elseif op == "leaders" and type(arg) == "table" then
			local save = towns:save(1)
			local stats = Leaders.stats(save, emu.require(G.data).garagePower(save.cars))
			local rows, mine = leaders:board(arg.metric, arg.period, 1, stats)
			for _, r in rows do
				r.here = r.id == 2
			end
			if arg.scope == "crews" then
				return { crews = Leaders.crews(crewDesk:browse(), arg.metric, arg.period, "2026-W42"), myCrew = crewDesk:mineId(1) }, nil
			end
			return { rows = rows, mine = mine }, nil
		elseif op == "meet" then
			local out = {}
			for _, d in meetDesk:displays() do
				d.here = d.id == 2
				table.insert(out, d)
			end
			return { displays = out, likes = meetDesk:likesFor(1, { 1, 2, 7 }) }, nil
		elseif op == "mail" then
			local box = mailDesk:inbox(1)
			box.sent = mailDesk:sentToday(1)
			mailDesk:see(1)
			return box, nil
		elseif op == "invites" then
			return { joined = 2, reached = 1, gems = 100, waiting = 0 }, nil
		elseif op == "sent" then
			return mailDesk:sentToday(1), nil
		elseif op == "claimMail" then
			local got = mailDesk:claim(1)
			towns:_with(1, function(s)
				s.receiveGifts(got.fuel, got.parts)
			end)
			return got, nil
		elseif op == "gift" then
			local r = mailDesk:gift(1, "You", "Home", arg.to, arg.item)
			return if r == "sent" then { sent = true } else nil, r
		elseif op == "postcard" then
			local r = mailDesk:postcard(1, "You", "Home", arg.to, arg.card, arg.msg)
			return if r == "sent" then { sent = true } else nil, r
		elseif op == "crew" then
			local mine = crewDesk:mine(1)
			if mine then
				local n = 0
				for _ in mine.crew.members do
					n += 1
				end
				mine.house = crewHouse
				mine.goal = goalDesk:goal(1, mine.crew.id, n)
				local got = partsDesk:claim(1)
				if got > 0 then
					towns:_with(1, function(st)
						store.useGame.setState({ parts = (st.parts or 0) + got })
					end)
					signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
				end
				mine.parts = partsDesk:list(mine.crew.id, 1)
				mine.battle = battles.desk:battle(1, mine.crew.id, battles.opened())
				return mine, nil
			end
			return { house = crewHouse, browse = crewDesk:browse(arg), asked = crewDesk:asked(1), level = towns:save(1).level or 1, goal = goalDesk:goal(1, nil, 0), battle = battles.desk:battle(1, nil, battles.opened()) }, nil
		elseif op == "crewLadder" then
			-- Rosa has a run, Mina a par, and I have no time yet.
			local c = crewDesk:crew(crewDesk:mineId(1) or "")
			if not c then
				return nil, "no crew"
			end
			local rows = {}
			for uid, m in c.members do
				local id = tonumber(uid)
				if id == 2 then
					table.insert(rows, 1, { id = id, name = m.name, t = 9.512, par = false, car = "Comet GT", pi = 340 })
				else
					table.insert(rows, { id = id, name = m.name, t = if id == 1 then nil else 14.2, par = true, car = if id == 1 then nil else "Pip", pi = 120 })
				end
			end
			return { rows = rows, fuel = 5 }, nil
		elseif op == "crewPartsAsk" then
			local r = partsDesk:ask(1, crewDesk:mineId(1), "You")
			return if r == "asked" then true else nil, r
		elseif op == "crewPartGive" then
			local r = partsDesk:give(1, crewDesk:mineId(1), arg)
			if r ~= "given" then
				return nil, r
			end
			towns:_with(1, function(st)
				store.useGame.setState({ parts = math.max(0, (st.parts or 0) - 1) })
			end)
			signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
			return true, nil
		elseif op == "crewBattleChest" then
			local last = battles.desk:battle(1, crewDesk:mineId(1), battles.opened()).last
			if not last or not table.find(last.claimable, arg) then
				return nil, "battle locked"
			end
			local total = goalDesk:addChest(1, `{arg}:{last.week}`, last.us.id)
			towns:_with(1, function(st)
				for _ = (st.crewChests or 0) + 1, total do
					store.useGame.getState().openCrewChest()
				end
			end)
			signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
			return { chests = total }, nil
		elseif op == "crewWarChest" then
			local b = battles.desk:battle(1, crewDesk:mineId(1), battles.opened())
			local v = if b.current and b.current.week == arg.week then b.current else b.last
			local t = v and v.tiers[arg.tier]
			if not t or not t.claimable then
				return nil, "war locked"
			end
			local total = goalDesk:addChest(1, `tier{arg.tier}:{arg.week}`, v.us.id)
			towns:_with(1, function(st)
				for _ = (st.crewChests or 0) + 1, total do
					store.useGame.getState().openCrewChest()
				end
			end)
			signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
			return { chests = total }, nil
		elseif op == "crewChest" then
			local total, no = goalDesk:open(1, arg)
			if not total then
				return nil, no
			end
			towns:_with(1, function(st)
				for _ = (st.crewChests or 0) + 1, total do
					store.useGame.getState().openCrewChest()
				end
			end)
			signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
			return { chests = total }, nil
		elseif op == "crewCreate" then
			if not crewHouse then
				return nil, "crew house"
			end
			local id, no = crewDesk:create(1, crewWho(1), arg)
			return if id then { id = id } else nil, no
		elseif op == "crewAsk" then
			return crewDesk:ask(1, crewWho(1), arg)
		elseif op == "crewCancel" then
			crewDesk:cancel(1, arg)
			return true, nil
		elseif op == "crewRespond" then
			return crewDesk:respond(1, arg.id, arg.yes == true)
		elseif op == "crewLeave" then
			local ok, no = crewDesk:leave(1)
			return if ok then true else nil, no
		elseif op == "crewKick" then
			local ok, no = crewDesk:kick(1, arg)
			return if ok then true else nil, no
		elseif op == "crewRank" then
			local ok, no = crewDesk:setRank(1, arg.id, arg.rank)
			return if ok then true else nil, no
		elseif op == "crewSettings" then
			local ok, no = crewDesk:settings(1, arg)
			return if ok then true else nil, no
		elseif op == "card" then
			local d = emu.require(G.data)
			local c = Meet.cardOf(towns:save(arg), emu.require(G.meet).showcaseOf(towns:save(arg).cars, nil), function(car)
				return d.performance(d.carDef(car.model), car.upgrades, car.mods)
			end)
			c.name, c.here, c.mine = "Rosa", arg == 2, arg == 1
			c.likes = meetDesk:likesFor(1, { arg })[tostring(arg)]
			c.crew = crewDesk:badge(arg)
			return c, nil
		elseif op == "like" then
			local r = meetDesk:like(1, arg)
			if r ~= "liked" then
				return nil, r
			end
			return { likes = meetDesk:likes(arg) }, nil
		elseif op == "home" then
			player:SetAttribute("Driving", nil)
			player:SetAttribute("Visiting", nil)
			player:SetAttribute("Helped", nil)
			return true, nil
		elseif op == "help" and type(arg) == "string" then
			local r, w = social:help(1, 2, arg)
			if r then
				player:SetAttribute("Helped", table.concat(r.helped, ","))
			end
			return r, w
		elseif op == "drive" then
			player:SetAttribute("Driving", true)
			return true, nil
		elseif op == "claim" then
			return 0, nil
		elseif op == "join" then
			return { here = false }, nil
		end
		return nil, "not a social action"
	end)
	if not ran then
		table.insert(calls, `SERVER ERROR social {op}: {result}`)
		return false, "error"
	end
	checkSend(`social {op} result`, result)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	if result == nil then
		table.insert(calls, `social {op} refused: {why}`)
		return false, why
	end
	table.insert(calls, `ok social {op}`)
	return true, result
end

-- The server end of Cartopia.Bank (server/Purchases), with every product made.
local bankDesk = emu.require(SSS.Server.Purchases).new(towns, store, emu.require(G.bucksPacks), function()
	return true
end)
do
	local list = {}
	for i, p in emu.require(G.bucksPacks).ALL_PACKS do
		table.insert(list, { name = p.name, product = i, robux = math.floor(p.price * 80 + 0.5) })
	end
	bankDesk:setProducts(list)
	bankDesk:load(1, {})
end
-- The admin panel's remote (server/Admin), answered further down.
local adminCall = function(...)
	return false, "not set up"
end
roblox.implementMethod("RemoteFunction", "InvokeServer", function(remote, name, ...)
	if remote.Name == "AdminRemote" then
		return adminCall(name, ...)
	elseif remote.Name == "Social" then
		return socialDesk(name, ...)
	elseif remote.Name == "Visitor" then
		return visitorCall(name, ...)
	elseif remote.Name == "WebLink" then
		-- No web game in the previews: every code is a wrong one.
		return false, "code"
	elseif remote.Name == "Race" then
		return raceDesk(name, ...)
	elseif remote.Name == "Meshes" then
		-- Every mesh is already here in the previews.
		return true
	elseif remote.Name == "Bank" then
		-- The Bank: every pack's product made at a made-up price, so the cards show prices.
		if name == "shop" then
			local shop = bankDesk:shop(1)
			checkSend("bank shop", shop)
			table.insert(calls, "ok bank shop")
			return true, shop
		end
		local product, why = bankDesk:canBuy(1, ...)
		table.insert(calls, if product then `ok bank buy {...}` else `bank buy refused: {why}`)
		return product ~= nil, why
	elseif remote.Name == "Crate" then
		local ran, result, why = pcall(crateDesk.open, crateDesk, 1, name, ...)
		if not ran then
			table.insert(calls, `SERVER ERROR crate {name}: {result}`)
			return false, "error"
		end
		checkSend(`crate {name} result`, result)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		if result == nil then
			-- Short on coins or level: the town's "you need" popup says so, as on the web.
			table.insert(calls, if why == "not opened" then `ok crate {name} (needs more)` else `crate {name} refused: {why}`)
			return false, why
		end
		table.insert(calls, `ok crate {name}`)
		return true, result
	end
	local args = table.pack(...)
	local ok, why = Towns.check(name, args, args.n)
	if not ok then
		table.insert(calls, `REFUSED {why}`)
		return false, why
	end
	local ran, result = pcall(towns.run, towns, 1, name, table.unpack(args, 1, args.n))
	if not ran then
		table.insert(calls, `SERVER ERROR {name}: {result}`)
		return false, "error"
	end
	table.insert(calls, `ok {name}`)
	local snap = towns:snapshot(1)
	checkSend(`{name} snapshot`, snap)
	checkSend(`{name} result`, result)
	signalFor(townEvent, "OnClientEvent"):Fire(snap)
	return true, result
end)

local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local Remote = emu.require(client.Remote)
signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
local hud = emu.require(client.Hud).start()

-- The admin panel (server/Admin): the server puts it in the owner's PlayerGui only. Here player 1
-- stands in for the owner (ADMIN_ONLY=1 checks just this); every page is opened and every button pressed, and SHOTS=1 pictures
-- each page (build/shot-admin-<page>-gui.json).
local function adminCheck()
	-- Live events (server/LiveEvents) for the admin panel's Live page: no DataStore or MessagingService
	-- here, so this server's own list, shown through Workspace's LiveEvents attribute as JSON.
	local liveDesk = emu.require(SSS.Server.LiveEvents).new({
		-- The server's clock, as players see it (GetServerTimeNow).
		now = function()
			return game:GetService("Workspace"):GetServerTimeNow() * 1000
		end,
		random = math.random,
		update = function()
			return nil
		end,
		read = function()
			return nil
		end,
		publish = function() end,
		show = function(list)
			game:GetService("Workspace"):SetAttribute("LiveEvents", require("@lune/serde").encode("json", list))
		end,
		filter = function(_, text)
			return text
		end,
	})
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	local Gui = require("./gui")
	local Admin = emu.require(SSS.Server.Admin)
	Admin.IDS[1] = true
	local desk = Admin.new({
		towns = towns,
		store = store,
		data = emu.require(RS.Shared.Game.data),
		visitors = { _record = function()
			return { lastAt = 0, n = 0 }
		end, cur = {} },
		player = function(id)
			return if id == 1 then player else nil
		end,
		players = function()
			return { player }
		end,
		push = function()
			signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		end,
		save = function() end,
		hub = function()
			return roblox.CFrame.new(0, 5, 160)
		end,
		plot = function()
			return roblox.CFrame.new(0, 5, 0)
		end,
		plots = 12,
		rave = function()
			return true, nil
		end,
		live = liveDesk,
		stats = function()
			return { memoryMb = 900, physicsFps = 60, heartbeatMs = 2, uptime = 600, players = 1, instances = 40000, version = 1, job = "emu" }
		end,
		now = function()
			return NOW
		end,
		uid = function()
			return "emu"
		end,
	})
	-- Every button is pressed in the same instant here, which the panel's rate limit would refuse.
	desk._allow = function()
		return true
	end
	local adminCalls = {}
	adminCall = function(op, ...)
		local ran, ok, result = pcall(desk.run, desk, player, op, ...)
		if not ran then
			table.insert(adminCalls, `SERVER ERROR admin {op}: {ok}`)
			return false, "error"
		end
		if not ok and result ~= "not here" and result ~= "no character" and result ~= "bad amount" and result ~= "not confirmed" then
			table.insert(adminCalls, `admin {op} refused: {result}`)
		end
		return ok, result
	end
	local holder = Instance.new("ScreenGui")
	holder.Name = "CartopiaAdmin"
	local remote = Instance.new("RemoteFunction")
	remote.Name = "AdminRemote"
	remote.Parent = holder
	SSS.Server.Admin.Panel:Clone().Parent = holder
	holder.Parent = player.PlayerGui
	handlerErrors = {}
	emu.require(holder.Panel)
	Emu.resumeWaits()
	local function find(root, name)
		for _, d in root:GetDescendants() do
			if d.Name == name then
				return d
			end
		end
		return nil
	end
	local function press(shadow)
		local face = shadow and (if shadow:IsA("GuiButton") then shadow else shadow:FindFirstChildWhichIsA("GuiButton", true))
		if face then
			signalFor(face, "Activated"):Fire()
			Emu.resumeWaits()
		end
	end
	press(find(holder, "AdminButton"))
	assert(find(holder, "Panel"), "the admin panel didn't open")
	local pages = { "Money", "Cars", "World", "Move", "Players", "Live" }
	for _, name in pages do
		-- The page's tab: a button whose label says its name.
		local tabs = find(holder, "Pages")
		for _, l in tabs:GetDescendants() do
			if l:IsA("TextLabel") and l.Name == "Label" and l.Text == name then
				press(l.Parent)
				break
			end
		end
		if SHOTS or process.env.ADMIN_SHOTS then
			fs.writeFile(`build/shot-admin-{string.lower(name)}-gui.json`, serde.encode("json", { nodes = Gui.dump(holder, 1280, 800), bubbles = {} }))
		end
		-- Every button on the page once (the careful ones only arm; nothing here can't be undone).
		local page = find(holder, "Page")
		local n = 0
		if page then
			for _, b in page:GetDescendants() do
				if b:IsA("GuiButton") and n < 40 then
					n += 1
					pcall(function()
						signalFor(b, "Activated"):Fire()
					end)
				end
			end
			Emu.resumeWaits()
		end
		print(`admin {name}: pressed {n} buttons`)
	end
	print(`admin calls: {#adminCalls} problems {table.concat(adminCalls, "; ")}; handler errors: {table.concat(handlerErrors, "; ")}`)
	assert(#adminCalls == 0 and #handlerErrors == 0, "the admin panel had problems")
end
if process.env.ADMIN_ONLY then
	adminCheck()
	process.exit(0)
end

local function buttons(root)
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Visible then
			local hidden = false
			local p = d.Parent
			while p and p ~= root do
				if p:IsA("GuiObject") and not p.Visible then
					hidden = true
				end
				p = p.Parent
			end
			if not hidden then
				table.insert(out, d)
			end
		end
	end
	return out
end
local function path(b, root)
	local names = {}
	local p = b
	while p and p ~= root do
		local label = p:FindFirstChildWhichIsA("TextLabel", true)
		table.insert(names, 1, p.Name .. (if p == b and label and label.Text ~= "" then `"{label.Text}"` else ""))
		p = p.Parent
	end
	return table.concat(names, "/")
end

-- The race screen, while a race is on.
local function raceScreen()
	local g = player.PlayerGui:FindFirstChild("Race")
	return g and g:FindFirstChild("RaceScreen")
end

-- Whether anything listens for presses on a button.
local function hears(b)
	-- (MouseButton1Down/Up alone is only the press-in look, not a handler.)
	for _, ev in { "Activated", "InputBegan" } do
		if next(signalFor(b, ev).fns) ~= nil then
			return true
		end
	end
	return false
end
-- The listening button a button sits inside, if any: a press on the inner one never reaches it.
local function coveredOf(b)
	local p = b.Parent
	while p do
		if p:IsA("GuiButton") and hears(p) then
			return p
		end
		if p:GetAttribute("SinkTaps") then
			return nil
		end
		p = p.Parent
	end
	return nil
end

local bad, total, silent = 0, 0, 0
-- Buttons that do nothing but sit inside one that does. In Roblox a tap stops at the topmost
-- button, so a tap there is lost: the shop's price buttons were this, on every card.
local deadSeen = {}
local function scanDead(label)
	for _, b in buttons(hud.gui) do
		-- SinkTaps: a button there on purpose to stop taps (a menu's sheet over its backdrop).
		local cover = not hears(b) and not b:GetAttribute("SinkTaps") and coveredOf(b)
		if cover then
			local key = `{path(b, hud.gui)} in {path(cover, hud.gui)}`
			if not deadSeen[key] then
				deadSeen[key] = true
				bad += 1
				print(`[{label}] DEAD SPOT {key}: a tap there does nothing`)
			end
		end
	end
end
local function clickAll(label, open, screen)
	-- `screen`: where the menu draws when it isn't the HUD (a full-screen scene's own gui).
	local function root()
		return screen and screen() or hud.gui
	end
	open()
	local n = #buttons(root())
	scanDead(label)
	for i = 1, n do
		hud.ctx.close()
		open()
		local b = buttons(root())[i]
		if not b then
			continue
		end
		total += 1
		local where = path(b, root())
		calls = {}
		handlerErrors = {}
		local wired = hears(b)
		local shape = {}
		for _, d in root():GetDescendants() do
			if d:IsA("GuiObject") and d.Visible then
				shape[d] = true
			end
		end
		local beforeN = #root():GetDescendants()
		local beforeText = {}
		for _, d in root():GetDescendants() do
			if d:IsA("TextLabel") then
				table.insert(beforeText, d.Text)
			end
		end
		local ok, err = pcall(function()
			signalFor(b, "MouseButton1Down"):Fire()
			signalFor(b, "MouseButton1Up"):Fire()
			signalFor(b, "Activated"):Fire()
		end)
		if not ok then
			bad += 1
			print(`[{label}] ERROR {where}: {err}`)
		elseif not wired and coveredOf(b) then
			-- Counted by scanDead.
		elseif not wired then
			silent += 1
			print(`[{label}] not wired: {where}`)
		end
		if VERBOSE and ok and wired then
			local afterText = {}
			for _, d in root():GetDescendants() do
				if d:IsA("TextLabel") then
					table.insert(afterText, d.Text)
				end
			end
			local changed = #root():GetDescendants() ~= beforeN or table.concat(afterText, "|") ~= table.concat(beforeText, "|")
			print(`[{label}] {if changed or #calls > 0 then "does something" else "NO VISIBLE EFFECT"}: {where} {table.concat(calls, ", ")}`)
		end
		scanDead(label)
		-- The shutter (client/ShotMode) hides every menu: bring them back for the next press.
		emu.require(client.ShotMode).exit()
		-- A race a click started: leave it, so the next click starts from the menu again.
		local raceScreen = raceScreen()
		if raceScreen then
			local leave = raceScreen:FindFirstChild("Leave")
			if leave then
				signalFor(leave:FindFirstChild("Face"), "Activated"):Fire()
			end
		end
		for _, e in handlerErrors do
			bad += 1
			print(`[{label}] ERROR {where}: {e}`)
		end
		for _, c in calls do
			if c:sub(1, 2) ~= "ok" then
				bad += 1
				print(`[{label}] {where}: {c}`)
			end
		end
	end
	hud.ctx.close()
end

clickAll("hud", function() end)
-- Rusty's Rescue, with a car on the lot and one in the bay, so every part of it has buttons.
local function rustyTown()
	towns:_with(1, function(s)
		local b = table.clone(s.buildings)
		local has = false
		for _, x in b do
			has = has or x.def == "rescue"
		end
		if not has then
			table.insert(b, { id = "rusty1", def = "rescue", x = 40, z = 40, rot = 0, level = 1 })
		end
		store.useGame.setState({
			buildings = b,
			coins = 1000000,
			parts = 200,
			level = 30,
			junkyard = { { uid = "j1", model = "woodie", rarity = "scarce" }, { uid = "j2", model = "pip", rarity = "common" }, { uid = "j3", model = "miata", rarity = "rare" } },
			restoring = { uid = "r1", model = "bug", rarity = "common", minutes = 5, endsAt = NOW + 120000 },
		})
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
end
rustyTown()
for _, p in { "shop", "cars", "garage", "showroom", "goals", "menu", "inventory", "race", "book", "crates", "rescue", "season", "deals", "friends" } do
	clickAll(p, function()
		hud.openPanel(p)
	end)
end
-- The HUD again at level 30: the Star Pass and Daily Deals buttons are up.
clickAll("hud30", function() end)
-- The Daily Spin, with today's spin still to take each time (Spin spins it on the server).
local function unspun()
	towns:_with(1, function()
		store.useGame.setState({ lastDaily = "2000-01-01" })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
end
-- Lune's Destroy is its own and can't fire Destroying, so the Daily Spin's tyre shop (taken down
-- when its panel goes) is closed by hand, as Roblox would.
local wheelGone = nil
local function wheelOpened()
	local p = hud.root:FindFirstChild("Panel")
	wheelGone = p and signalFor(p, "Destroying")
end
local function closeWheel()
	hud.ctx.close()
	if wheelGone then
		wheelGone:Fire()
		wheelGone = nil
	end
end
clickAll("daily", function()
	closeWheel()
	unspun()
	hud.openPanel("daily")
	wheelOpened()
end, function()
	return player.PlayerGui:FindFirstChild("DailySpin") or hud.gui
end)
closeWheel()
clickAll("cards", function()
	hud.openPanel("cars", "cards")
end)
clickAll("hats", function()
	hud.openPanel("cars", "garage")
	local b = hud.gui:FindFirstChild("hats", true)
	if b then
		signalFor(b, "Activated"):Fire()
	end
end)
clickAll("mods", function()
	hud.openPanel("cars", "garage")
	local b = hud.gui:FindFirstChild("mods", true)
	if b then
		signalFor(b, "Activated"):Fire()
	end
end)
clickAll("custom", function()
	hud.openPanel("cars", "garage")
	local b = hud.gui:FindFirstChild("custom", true)
	if b then
		signalFor(b, "Activated"):Fire()
	end
end)
clickAll("trim", function()
	hud.openPanel("cars", "garage")
	local b = hud.gui:FindFirstChild("trim", true)
	if b then
		signalFor(b, "Activated"):Fire()
	end
end)
clickAll("paint", function()
	hud.openPanel("cars", "garage")
	local b = hud.gui:FindFirstChild("paint", true)
	if b then
		signalFor(b, "Activated"):Fire()
	end
end)
-- A car stuck on a job (a flat tire, or out of gas): its fix-it sheet, opened as Goals' Go › does.
local function stuckCar(how)
	local uid
	towns:_with(1, function()
		local cars = {}
		for i, c in store.useGame.getState().cars do
			cars[i] = table.clone(c)
			cars[i].flat = if i == 1 and how == "flat" then true else nil
			cars[i].lowFuel = if i == 1 and how == "gas" then true else nil
		end
		uid = cars[1].uid
		store.useGame.setState({ cars = cars })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	return uid
end
for _, how in { "flat", "gas" } do
	clickAll(how, function()
		hud.openPanel("flat", stuckCar(how))
	end)
end
stuckCar(nil)
-- The shop's price buttons, tapped the way a player taps them: each must start building (an
-- affordable one) or open the "you need" popup (a locked or too dear one), never nothing.
do
	local Placement = emu.require(client.Placement)
	local tabs = { "cars", "business", "homes", "services", "rec" }
	local tried, dead = 0, 0
	for _, tab in tabs do
		local n = 1
		while true do
			hud.ctx.close()
			Placement.cancel()
			hud.openPanel("shop")
			local tabFace = hud.gui:FindFirstChild(tab, true)
			if tabFace then
				signalFor(tabFace:FindFirstChild("Face") or tabFace, "Activated"):Fire()
			end
			local prices = {}
			for _, d in hud.gui:GetDescendants() do
				-- A price button: a button inside a card in the shop's grid.
				if d:IsA("GuiButton") and d.Parent and d.Parent.Parent and d.Parent.Parent:IsA("GuiButton") and d:FindFirstAncestor("Grid") then
					table.insert(prices, d)
				end
			end
			local b = prices[n]
			if not b then
				break
			end
			local l = b:FindFirstChildWhichIsA("TextLabel", true)
			local text = if l then l.Text else ""
			local before = #hud.gui:GetDescendants()
			signalFor(b, "Activated"):Fire()
			tried += 1
			local building = Placement.active()
			local popup = hud.gui:FindFirstChild("Need", true) ~= nil or #hud.gui:GetDescendants() ~= before
			if not building and not popup and text ~= "✔ Built" then
				dead += 1
				bad += 1
				print(`[shop prices] tapping "{text}" on the {tab} tab did nothing`)
			end
			n += 1
		end
	end
	hud.ctx.close()
	Placement.cancel()
	print(`shop prices: {tried} tapped, {dead} did nothing`)
end
print(`{total} buttons pressed, {bad} problems, {silent} not wired`)

	local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Gui = require("./gui")
-- SHOTS_ONLY=tools-: only the pictures whose names start with it, without the real models (quick
-- pictures of menus). (Read here: the file's top level is out of local slots.)
local function shot(name, world, w, h)
	local only = process.env.SHOTS_ONLY
	if not SHOTS and not (only and name:sub(1, #only) == only) then
		return
	end
	local parts = {}
	if world then
		for _, d in world:GetDescendants() do
			-- An invisible part still shows the words on its SurfaceGui (the Daily Spin's amounts, a
			-- kart circuit's crowds).
			if d:IsA("BasePart") and (d.Transparency < 1 or d:FindFirstChildOfClass("SurfaceGui")) then
				table.insert(parts, Gui.partOf(d))
			end
		end
	end
	-- Lighting's fog, when a race has set it (Roblox draws it only with no Atmosphere in Lighting).
	local lighting = game:GetService("Lighting")
	local fog = if lighting.FogEnd < 10000 and not lighting:FindFirstChildOfClass("Atmosphere")
		then { color = lighting.FogColor:ToHex(), start = lighting.FogStart, ["end"] = lighting.FogEnd }
		else nil
	-- Beams (light columns): their two ends, widths, colour and fade.
	local beams = {}
	if world then
		for _, d in world:GetDescendants() do
			if d:IsA("Beam") and d.Enabled and d.Attachment0 and d.Attachment1 then
				-- (The emulator has no WorldPosition: from the part they're on.)
				local a = d.Attachment0.Parent.CFrame * d.Attachment0.Position
				local b = d.Attachment1.Parent.CFrame * d.Attachment1.Position
				local tk = d.Transparency.Keypoints
				table.insert(beams, { from = { a.X, a.Y, a.Z }, to = { b.X, b.Y, b.Z }, width = { d.Width0, d.Width1 }, color = d.Color.Keypoints[1].Value:ToHex(), fade = { tk[1].Value, tk[#tk].Value }, glow = d.LightEmission })
			end
		end
	end
	-- A room's own lamps (the Daily Spin's tyre shop shuts the sun out).
	local lights = {}
	if world then
		for _, d in world:GetDescendants() do
			if (d:IsA("PointLight") or d:IsA("SpotLight")) and d.Parent and d.Parent:IsA("BasePart") then
				local cf = (d.Parent :: any).CFrame
				table.insert(lights, {
					kind = d.ClassName,
					at = { cf.Position.X, cf.Position.Y, cf.Position.Z },
					dir = { cf.LookVector.X, cf.LookVector.Y, cf.LookVector.Z },
					color = d.Color:ToHex(),
					brightness = d.Brightness,
					range = d.Range,
					angle = if d:IsA("SpotLight") then d.Angle else nil,
				})
			end
		end
	end
	local room = if lighting.Brightness == 0 then { ambient = lighting.OutdoorAmbient:ToHex() } else nil
	fs.writeFile(`build/shot-{name}.json`, serde.encode("json", { parts = parts, fog = fog, lights = lights, room = room, beams = if #beams > 0 then beams else nil }))
	local toasts = hud.gui:FindFirstChild("Toasts", true)
	if toasts then
		for _, t in toasts:GetChildren() do
			if t:IsA("GuiObject") then
				t:Destroy()
			end
		end
	end
	local raceGui = player.PlayerGui:FindFirstChild("Race") or player.PlayerGui:FindFirstChild("DailySpin") or player.PlayerGui:FindFirstChild("RescueSearch")
	if name:find("^depot%-") or name:find("^page%-") or name:find("^panel%-") or name:find("^cards") or name:find("^crew%-") then
		-- The crate depot, race pages and menus are on the HUD, whatever screen an earlier check
		-- left behind.
		raceGui = nil
	end
	fs.writeFile(`build/shot-{name}-gui.json`, serde.encode("json", { nodes = Gui.dump(raceGui or hud.gui, w or 1280, h or 800), bubbles = {} }))
	local cam = game.Workspace.CurrentCamera
	local cf = cam.CFrame
	local at = cf.Position + cf.LookVector * 50
	fs.writeFile(`build/shot-{name}-cam.json`, serde.encode("json", { from = { cf.Position.X, cf.Position.Y, cf.Position.Z }, at = { at.X, at.Y, at.Z }, fov = cam.FieldOfView }))
end
-- Walk: the camera follows the avatar, and the second press brings the town view back.
do
	hud.ctx.close()
	local walkShadow = hud.gui:FindFirstChild("WalkButton", true)
	local walkButton = walkShadow and (if walkShadow:IsA("GuiButton") then walkShadow else walkShadow:FindFirstChildWhichIsA("GuiButton", true))
	assert(walkButton, "no Walk button")
	shot("hud", nil)
	-- MENU_SHOTS=1: just the HUD and a few menus (Deals, Star Pass, the garage), then stop.
	if process.env.MENU_SHOTS then
		local data = emu.require(RS.Shared.Game.data)
		towns:_with(1, function()
			store.useGame.setState({ coins = 4215, bucks = 145, parts = 35, deals = { day = "2000-01-01", used = {} }, season = { n = data.seasonNumber(NOW), stars = 45, claimed = { 0, 1 } } })
		end)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		-- The coin, gem and parts pills, whatever this point of the run hides.
		local left = hud.gui:FindFirstChild("Left", true)
		if left then
			left.Visible = true
		end
		shot("m-hud", nil)
		for _, p in { "deals", "season", "cars" } do
			hud.ctx.close()
			hud.openPanel(p)
			shot(`m-{p}`, nil)
		end
		hud.ctx.close()
		process.exit(0)
	end
	signalFor(walkButton, "Activated"):Fire()
	assert(game.Workspace.CurrentCamera.CameraType == roblox.Enum.CameraType.Custom, "walking didn't hand the camera to the avatar")
	-- The label under the button reads MY TOWN, in its letters and its shadow alike.
	local function walkWords(): { string }
		local out = {}
		for _, d in walkShadow.Parent:GetDescendants() do
			if d:IsA("TextLabel") and (d.Text == "DRIVE" or d.Text == "MY TOWN") then
				table.insert(out, d.Text)
			end
		end
		return out
	end
	for _, w in walkWords() do
		assert(w == "MY TOWN", `the Drive button shows "{w}" while driving`)
	end
	-- Their town on a plot out in the shared world (a stand-in folder, as TownView marks it).
	local made = game.Workspace:FindFirstChild("Towns") == nil
	local towns = game.Workspace:FindFirstChild("Towns") or Instance.new("Folder")
	towns.Name = "Towns"
	towns.Parent = game.Workspace
	local stand = Instance.new("Folder")
	stand.Name = "WalkTest"
	stand:SetAttribute("Owner", 1)
	stand:SetAttribute("Origin", roblox.Vector3.new(1400, 0, -1400))
	stand.Parent = towns
	-- Drive off to the side of the town first.
	pcall(function()
		player.Character:PivotTo(roblox.CFrame.new(600, 5, 600))
	end)
	signalFor(walkButton, "Activated"):Fire()
	assert(game.Workspace.CurrentCamera.CameraType == roblox.Enum.CameraType.Scriptable, "the town view didn't come back")
	-- Wherever they drove to, the town view comes back centred on their own town.
	local mine = emu.require(client.Town).folder()
	if mine then
		local origin = mine:GetAttribute("Origin")
		local focus = game.Workspace.CurrentCamera.Focus.Position
		assert(math.abs(focus.X - origin.X) < 1 and math.abs(focus.Z - origin.Z) < 1, `the town view came back at {focus}, not over the town at {origin}`)
		print("walk: town view back over the town's middle")
	end
	stand:Destroy()
	if made then
		towns:Destroy()
	end
	emu.require(client.TownCamera).lookAt(roblox.Vector3.zero)
	print("walk: on and off")
end
-- Merged buildings: a town of merged blocks drawn by the server's TownView (each block once, grown
-- to fill it; level 10 houses as the Vanguard and Globe Towers; colour themes), Merge mode's
-- badges (merge, turn, split), a merged block turned in Move, the Upgrade sheet of a block that
-- becomes a landmark, and Shop > Upgrades with its merged and stacked cards.
do
	hud.ctx.close()
	local TownView = emu.require(SSS.Server.TownView)
	local Placement = emu.require(client.Placement)
	local kept
	towns:_with(1, function(s)
		kept = s.buildings
		local list = {}
		local n = 0
		local rusty = false
		local function put(def, x, z, extra)
			n += 1
			local b = { uid = `m{n}`, def = def, x = x, z = z, jobEndsAt = nil }
			for k, v in extra or {} do
				b[k] = v
			end
			table.insert(list, b)
			return b
		end
		for _, b in kept do
			if b.def == "showroom" or b.def == "garage" or b.def == "gas" or b.def == "tree" then
				table.insert(list, b)
			elseif b.def == "rescue" and not rusty then
				rusty = true
				-- Kept (the Shop wants Rusty's), out of the blocks' way.
				local r = table.clone(b)
				r.x, r.z, r.rot = 16, 17, nil
				table.insert(list, r)
			end
		end
		-- Four level 10 houses: the Vanguard Tower. Eight: the Globe Tower.
		for j = 0, 1 do
			for i = 0, 1 do
				put("house", 5 + i, 5 + j, { level = 10, merge = if i == 0 and j == 0 then 2 else nil })
			end
		end
		for j = 0, 1 do
			for i = 0, 3 do
				put("house", 5 + i, 12 + j, { level = 10, merge = if i == 0 and j == 0 then 42 elseif i == 2 and j == 0 then 2 else nil })
			end
		end
		-- A 2x2 of pizza places with a driver and a job running, a pair of burger joints in mint.
		for j = 0, 1 do
			for i = 0, 1 do
				put("pizza", 8 + i, 5 + j, { merge = if i == 0 and j == 0 then 2 else nil, jobEndsAt = if i == 0 then NOW + 20000 else nil })
			end
		end
		put("burger", 11, 5, { merge = 21, tint = "mint" })
		put("burger", 12, 5, { tint = "mint" })
		-- A 4x4 block of pizza places.
		for j = 0, 3 do
			for i = 0, 3 do
				put("pizza", 10 + i, 13 + j, { merge = if i == 0 and j == 0 then 4 else nil })
			end
		end
		-- Loose ones that could merge: four rose houses in a square, and two pizza places.
		for j = 0, 1 do
			for i = 0, 1 do
				put("house", 14 + i, 5 + j, { level = 3, tint = "rose" })
			end
		end
		put("pizza", 17, 5)
		put("pizza", 18, 5)
		-- Flower beds merged along z (decor: no lot).
		put("flowers", 16, 13, { merge = 12 })
		put("flowers", 16, 14)
		s.buildings = list
		s.coins = 5000000
		s.parts = 5000
		s.level = 40
		-- In the town's own colours (pressing every City look button above left it all white).
		s.cityTheme = nil
		-- A driver at the pizza block.
		if s.cars[1] then
			for _, b in list do
				b.car = if b.uid == "m13" then s.cars[1].uid elseif b.car == s.cars[1].uid then nil else b.car
			end
		end
	end)
	local snap = towns:snapshot(1)
	signalFor(townEvent, "OnClientEvent"):Fire(snap)
	local townsFolder = Instance.new("Folder")
	townsFolder.Name = "Towns"
	townsFolder.Parent = game.Workspace
	local view = TownView.new(townsFolder, "Player1", roblox.Vector3.new(0, 0, 0), 1, function(uid)
		towns:run(1, "tapBuilding", uid)
	end)
	-- Drawn without the cars' mods, whose meshes the emulator can't load.
	local function draw(save)
		for _, c in save.cars do
			c.mods, c.panels = nil, nil
		end
		view:render(save)
	end
	draw(snap.save)
	local drawn = view.folder.Buildings
	-- Each block draws once, from its top-left building.
	assert(drawn:FindFirstChild("m1") and not drawn:FindFirstChild("m2"), "the Vanguard block didn't draw as one building")
	assert(drawn:FindFirstChild("m5") and not drawn:FindFirstChild("m6") and not drawn:FindFirstChild("m7"), "the Globe block didn't draw as one building")
	assert(drawn.m1:GetAttribute("Name") == "Vanguard Tower", `the Vanguard block is named {drawn.m1:GetAttribute("Name")}`)
	assert(drawn.m5:GetAttribute("Name") == "Globe Tower", `the Globe block is named {drawn.m5:GetAttribute("Name")}`)
	assert(drawn:FindFirstChild("m19") and not drawn:FindFirstChild("m20"), "the 4x4 block didn't draw as one building")
	assert(drawn.m19.Hit.Size.X > 70, "the 4x4 block's tap box doesn't cover it")
	assert(drawn:FindFirstChild("m35") and drawn:FindFirstChild("m36"), "loose houses went missing")
	local function setCamera(from, at)
		game.Workspace.CurrentCamera.CFrame = roblox.CFrame.lookAt(from, at)
	end
	-- Every building answers a tap, houses too (they open their Upgrade sheet).
	calls = {}
	local click = drawn.m35.Hit:FindFirstChildOfClass("ClickDetector")
	assert(click, "a house has no ClickDetector")
	print(`merges: {#drawn:GetChildren()} buildings drawn for {#snap.save.buildings} in the save`)
	setCamera(roblox.Vector3.new(170, 260, 300), roblox.Vector3.new(0, 0, 0))
	Emu.resumeWaits()
	shot("merges-town", view.folder)
	-- Merge mode: a Merge badge on every block that could merge, and turn / split on merged ones.
	hud.openPanel("edit", "merge")
	local marks = player.PlayerGui:FindFirstChild("EditMarks", true)
	assert(marks, "Merge mode drew no badges")
	local merges, splits = {}, {}
	for _, d in marks:GetChildren() do
		if d:IsA("BillboardGui") and d.Name == "Merge" then
			local l = d:FindFirstChildWhichIsA("TextLabel", true)
			table.insert(merges, `{l and l.Text or "?"} at {d:GetAttribute("Anchor")}`)
		elseif d:IsA("BillboardGui") and d.Name == "Split" then
			table.insert(splits, d)
		end
	end
	print(`merge mode: {table.concat(merges, ", ")}; {#splits} merged blocks`)
	assert(#splits == 6, `{#splits} split badges for 6 merged blocks`)
	local fours = 0
	for _, t in merges do
		if string.find(t, "×4", 1, true) then
			fours += 1
		end
	end
	assert(fours >= 1 and #merges >= 2, "the four rose houses and the pizza pair have no Merge badges")
	shot("merges-mode", view.folder)
	local function pressIn(gui, text)
		for _, d in gui:GetDescendants() do
			if d:IsA("TextButton") then
				local l = d:FindFirstChildWhichIsA("TextLabel", true)
				if l and string.find(l.Text, text, 1, true) then
					calls = {}
					handlerErrors = {}
					signalFor(d, "Activated"):Fire()
					assert(#handlerErrors == 0, table.concat(handlerErrors, "; "))
					return calls[1] or "nothing"
				end
			end
		end
		return "no button"
	end
	-- Merge the four rose houses (×4), turn the burger pair, split the flower beds.
	local mergeBadge
	for _, d in marks:GetChildren() do
		local l = d:IsA("BillboardGui") and d.Name == "Merge" and d:FindFirstChildWhichIsA("TextLabel", true)
		if l and string.find(l.Text, "×4", 1, true) then
			mergeBadge = d
		end
	end
	local r = pressIn(mergeBadge, "Merge")
	assert(r == "ok mergeBlock", `Merge ×4: {r}`)
	draw(towns:snapshot(1).save)
	assert(drawn:FindFirstChild("m35") and not drawn:FindFirstChild("m36"), "the merged rose houses still draw apart")
	marks = player.PlayerGui:FindFirstChild("EditMarks", true)
	local burgerTools
	for _, d in marks:GetChildren() do
		if d:IsA("BillboardGui") and d.Name == "Split" and d.Adornee then
			local p = d.Adornee.CFrame.Position
			-- The burger pair's middle: tiles 11.5, 5.
			if math.abs(p.X - (11.5 - 11.5) * 20) < 1 and math.abs(p.Z - (5 - 11.5) * 20) < 1 then
				burgerTools = d
			end
		end
	end
	assert(burgerTools, "no turn and split badges over the burger pair")
	r = pressIn(burgerTools, "🔄")
	assert(r == "ok rotateBlock", `turning the burger pair: {r}`)
	local turned = towns:snapshot(1).save
	draw(turned)
	marks = player.PlayerGui:FindFirstChild("EditMarks", true)
	r = pressIn(marks, "Split")
	assert(r == "ok splitBlock", `splitting a block: {r}`)
	print("merge mode: merge, turn and split ok")
	hud.ctx.close()
	Placement.cancel()
	-- The rose block's Upgrade sheet, and a Vanguard block's (at max level).
	hud.openPanel("upgrade", "m35")
	shot("merges-upgrade", nil)
	hud.ctx.close()
	hud.openPanel("upgrade", "m1")
	shot("merges-upgrade-landmark", nil)
	hud.ctx.close()
	-- Four level 9 houses: the upgrade makes them the Vanguard Tower, and the sheet says so.
	towns:_with(1, function(s)
		for _, b in s.buildings do
			if b.uid == "m35" or b.uid == "m36" or b.uid == "m37" or b.uid == "m38" then
				b.level = 9
			end
		end
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.openPanel("upgrade", "m35")
	local saysTower = false
	for _, d in hud.gui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Vanguard Tower" then
			saysTower = true
		end
	end
	assert(saysTower, "the Upgrade sheet doesn't say four level 9 houses become the Vanguard Tower")
	shot("merges-upgrade-becomes", nil)
	hud.ctx.close()
	hud.openPanel("shop", "upgrades")
	local k4 = false
	for _, d in hud.gui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "🧩×4" then
			k4 = true
		end
	end
	assert(k4, "Shop > Upgrades has no 🧩×4 card")
	shot("merges-shop", nil)
	-- Scrolled down to the maxed ones.
	local shopGrid = hud.gui:FindFirstChild("Grid", true)
	if shopGrid then
		shopGrid.CanvasPosition = roblox.Vector2.new(0, 520)
	end
	shot("merges-shop-max", nil)
	hud.ctx.close()
	-- Play mode again, with the job badges' merge chips.
	draw(towns:snapshot(1).save)
	emu.require(client.Jobs).refresh()
	shot("merges-play", view.folder)
	-- Put the town back for what follows.
	towns:_with(1, function(s)
		s.buildings = kept
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	townsFolder:Destroy()
	print("merges: drawn, merged, turned, upgraded")
end
if SHOTS then
	for _, p in { "shop", "goals", "menu", "cars" } do
		hud.ctx.close()
		hud.openPanel(p)
		shot(`panel-{p}`, nil)
	end
	-- The menu's Settings tab, with the web town code box, and the swap question after Link.
	do
		hud.ctx.close()
		-- The Daily Spin's own screen would cover the menu.
		local spin = hud.gui.Parent and hud.gui.Parent:FindFirstChild("DailySpin")
		if spin then
			spin:Destroy()
		end
		hud.openPanel("menu")
		local t = hud.gui:FindFirstChild("settings", true)
		assert(t, "no settings tab")
		signalFor(t:FindFirstChild("Face") or t, "Activated"):Fire()
		local box = hud.gui:FindFirstChild("WebCode", true)
		assert(box, "no web code box")
		shot("menu-settings", nil)
		box.Text = "ABCD2345"
		local link
		for _, d in box.Parent.Parent:GetDescendants() do
			if d:IsA("TextButton") and d.Parent and d.Parent:FindFirstChildWhichIsA("TextLabel", true) then
				for _, l in d:GetDescendants() do
					if l:IsA("TextLabel") and l.Text == "Link" then
						link = d
					end
				end
			end
		end
		assert(link, "no Link button")
		signalFor(link, "Activated"):Fire()
		assert(hud.gui:FindFirstChild("Confirm", true), "no swap question")
		shot("menu-settings-swap", nil)
		hud.gui:FindFirstChild("Confirm", true):Destroy()
		hud.ctx.close()
	end
	-- Goals: each tab, then the story done (the 📖 ✔ chip, endless goals with their pictures).
	local function goalsTab(id)
		hud.ctx.close()
		hud.openPanel("goals")
		local t = hud.gui:FindFirstChild(id, true)
		assert(t, `no {id} tab`)
		signalFor(t:FindFirstChild("Face") or t, "Activated"):Fire()
	end
	for _, id in { "story", "daily", "weekly" } do
		goalsTab(id)
		shot(`goals-{id}`, nil)
	end
	local before
	towns:_with(1, function()
		local s = store.useGame.getState()
		before = { claimedGoals = s.claimedGoals, tutorial = s.tutorial, endless = s.endless }
		local all = {}
		for _, g in emu.require(G.data).GOALS do
			if not g.event then
				table.insert(all, g.id)
			end
		end
		store.useGame.setState({ claimedGoals = all, tutorial = 99, endless = { n = 7, day = "", today = 0, drawn = 3, goals = { { k = 1, kind = "bldgUp", def = "pizza", n = 3, base = 0 }, { k = 2, kind = "carUp", def = s.cars[1].uid, n = 2, base = 0 }, { k = 3, kind = "wins", n = 5, base = 0 } } } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	goalsTab("story")
	shot("goals-endless", nil)
	towns:_with(1, function()
		store.useGame.setState(before)
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	for _, how in { "flat", "gas" } do
		hud.ctx.close()
		hud.openPanel("flat", stuckCar(how))
		shot(`flat-{how}`, nil)
	end
	stuckCar(nil)
	for _, t in { "hub", "quick", "campaign", "rivals" } do
		hud.ctx.close()
		hud.openPanel("race", t)
		shot(`menu-{t}`, nil)
	end
	-- The front page's tiles move (client/Motion loops): frames of them a quarter second apart,
	-- run by firing only the loops the page started.
	do
		local rs = signalFor(game:GetService("RunService"), "RenderStepped")
		local before = {}
		for c in rs.fns do
			before[c] = true
		end
		hud.ctx.close()
		hud.openPanel("race", "hub")
		local loops = {}
		for c, fn in rs.fns do
			if not before[c] then
				table.insert(loops, fn)
			end
		end
		for f = 1, 20 do
			for _, fn in loops do
				fn(0.25)
			end
			shot(`hub-anim-{f}`, nil)
		end
	end
	hud.ctx.close()
	hud.openPanel("book")
	shot("book", nil)
	-- Social: the Friends tab, then a visit to Rosa's town with one shop helped.
	hud.ctx.close()
	player:SetAttribute("CanChat", true)
	hud.openPanel("friends")
	shot("panel-friends", nil)
	hud.ctx.close()
	-- Where Roblox allows sharing: the invite button and its reward.
	player:SetAttribute("PolicyReady", true)
	player:SetAttribute("PolicySharing", true)
	hud.openPanel("friends")
	Emu.resumeWaits()
	if not hud.gui:FindFirstChild("InviteNote", true) then
		bad += 1
		print("INVITES: no invite reward line on the Friends tab")
	end
	shot("panel-friends-invite", nil)
	hud.ctx.close()
	player:SetAttribute("PolicyReady", nil)
	player:SetAttribute("PolicySharing", nil)
	-- The Leaderboards tab (the trophy pill and Top racers open it).
	hud.openPanel("friends", "leaders")
	local boardRows = 0
	for _, d in hud.gui:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "Kai", 1, true) then
			boardRows += 1
		end
	end
	assert(boardRows > 0, "the leaderboard shows no rows")
	local kaiRow = hud.gui:FindFirstChild("Kai", true)
	assert(kaiRow and kaiRow:FindFirstChild("CrewTag"), "Kai's leaderboard row has no crew tag")
	shot("panel-leaders", nil)
	-- The Crews board: a crew of Rosa's ranked by its members combined.
	if not crewDesk:mineId(2) then
		crewDesk:create(2, { name = "Rosa", town = "Rosaville", level = 9, power = 420, wins = 3, trophies = 5 }, { name = "Road Hogs", tag = "HOG", emblem = emu.require(G.data).CLAN_EMBLEMS[1], color = emu.require(G.data).CLAN_COLORS[1], motto = "", minLevel = 1, joinMode = "open" })
	end
	local crewsSwitch = hud.gui:FindFirstChild("crews", true)
	assert(crewsSwitch, "no Crews switch on the leaderboard")
	signalFor(if crewsSwitch:IsA("GuiButton") then crewsSwitch else crewsSwitch:FindFirstChildWhichIsA("GuiButton", true), "Activated"):Fire()
	local hogs = hud.gui:FindFirstChild("Road Hogs", true)
	assert(hogs and hogs:FindFirstChild("Crest"), "the Crews board doesn't show Road Hogs with its crest")
	local hogLine = false
	for _, d in hogs:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "420", 1, true) and string.find(d.Text, "[HOG]", 1, true) then
			hogLine = true
		end
	end
	assert(hogLine, "Road Hogs' row doesn't show its power and tag")
	print("leaders: crews board")
	crewDesk:leave(2)
	hud.ctx.close()
	-- The Car Meet tab: your display, then Rosa's and Kai's; like Rosa's.
	hud.openPanel("friends", "meet")
	local likeRosa
	for _, d in hud.gui:GetDescendants() do
		if d.Name == "Display2" then
			likeRosa = d:FindFirstChild("Like", true)
		end
	end
	assert(likeRosa, "no like button on Rosa's display")
	shot("panel-meet", nil)
	local likeButton = if likeRosa:IsA("GuiButton") then likeRosa else likeRosa:FindFirstChildWhichIsA("GuiButton", true)
	signalFor(likeButton, "Activated"):Fire()
	assert(meetDesk:likes(2) == 2, `liking Rosa's display left {meetDesk:likes(2)} likes`)
	print("meet: displays, like")
	-- Rosa's card: tap her display.
	local openRosa
	for _, d in hud.gui:GetDescendants() do
		if d.Name == "Display2" then
			openRosa = d:FindFirstChild("Open")
		end
	end
	assert(openRosa, "no way to open Rosa's card")
	signalFor(openRosa, "Activated"):Fire()
	local cardGui = hud.gui:FindFirstChild("PlayerCard", true)
	assert(cardGui, "Rosa's card didn't open")
	local strip = cardGui:FindFirstChild("Strip", true)
	assert(strip and #strip:GetChildren() > 1, "Rosa's card shows no cars")
	assert(cardGui:FindFirstChild("Visit", true), "no Visit on Rosa's card")
	shot("panel-card", nil)
	print("meet: player card")
	hud.ctx.close()
	-- Crews: locked without a Crew House; then the browser, starting one, running it, and joining
	-- Rosa's.
	do
		local problems = {}
		local function press(name)
			local d = hud.gui:FindFirstChild(name, true)
			local b = d and (if d:IsA("GuiButton") then d else d:FindFirstChildWhichIsA("GuiButton", true))
			if not b then
				table.insert(problems, `no {name} button`)
				return false
			end
			signalFor(b, "Activated"):Fire()
			Emu.resumeWaits()
			return true
		end
		hud.openPanel("clan")
		Emu.resumeWaits()
		if not hud.gui:FindFirstChild("Locked", true) then
			table.insert(problems, "no Crew House lock")
		end
		shot("crew-locked", nil)
		hud.ctx.close()
		crewHouse = true
		hud.openPanel("friends", "clan")
		Emu.resumeWaits()
		if not (hud.gui:FindFirstChild("CrewNITE", true) and hud.gui:FindFirstChild("CrewHK", true)) then
			table.insert(problems, "the browser doesn't list both crews")
		end
		shot("crew-browse", nil)
		press("StartCrew")
		local form = hud.gui:FindFirstChild("Create", true)
		local nameBox = form and form:FindFirstChild("Name", true)
		local tagBox = form and form:FindFirstChild("Tag", true)
		local mottoBox = form and form:FindFirstChild("Motto", true)
		if nameBox and tagBox and mottoBox then
			nameBox.Text = "Sunset Drifters"
			tagBox.Text = "sd!x9"
			mottoBox.Text = "We drift at golden hour"
		else
			table.insert(problems, "the start form is missing its name, tag or motto box")
		end
		press("Emblem3")
		press("#00897b")
		shot("crew-create", nil)
		press("Start")
		local mine = crewDesk:mine(1)
		if not mine or mine.crew.tag ~= "SDX9" or mine.crew.emblem ~= emu.require(G.data).CLAN_EMBLEMS[3] or mine.crew.motto ~= "We drift at golden hour" then
			table.insert(problems, `starting a crew didn't make Sunset Drifters [SDX9]: {table.concat(calls, ", ")}`)
		else
			-- Mina joins; then the crew takes requests and Kai asks.
			crewDesk:ask(8, { name = "Mina", town = "Mina Falls", level = 9, power = 455, wins = 30, trophies = 9 }, mine.crew.id)
			local look = { emblem = mine.crew.emblem, color = mine.crew.color, motto = mine.crew.motto, minLevel = 1, joinMode = "request" }
			crewDesk:settings(1, look)
			crewDesk:ask(9, { name = "Ivo", town = "Ivoport", level = 4, power = 90, wins = 2, trophies = 1 }, mine.crew.id)
			hud.ctx.close()
			hud.openPanel("friends", "clan")
			Emu.resumeWaits()
			shot("crew-mine", nil)
			local root = hud.gui:FindFirstChild("Root")
			root.Size = roblox.UDim2.fromOffset(1535, 709)
			shot("crew-mine-phone", nil, 1535, 709)
			root.Size = roblox.UDim2.fromOffset(1280, 800)
			local req = hud.gui:FindFirstChild("Request9", true)
			local yes = req and req:FindFirstChild("Yes", true)
			local yesButton = yes and (if yes:IsA("GuiButton") then yes else yes:FindFirstChildWhichIsA("GuiButton", true))
			if yesButton then
				signalFor(yesButton, "Activated"):Fire()
				Emu.resumeWaits()
			end
			if not crewDesk:crew(mine.crew.id).members["9"] then
				table.insert(problems, "accepting Ivo's request didn't let him in")
			end
			-- Make Mina a Co-Leader, then leave: she takes the lead.
			local mina = hud.gui:FindFirstChild("Member8", true)
			local promote = mina and mina:FindFirstChild("Make Co-Leader", true)
			local promoteButton = promote and (if promote:IsA("GuiButton") then promote else promote:FindFirstChildWhichIsA("GuiButton", true))
			if promoteButton then
				signalFor(promoteButton, "Activated"):Fire()
				Emu.resumeWaits()
			end
			if crewDesk:crew(mine.crew.id).members["8"].role ~= "co_leader" then
				table.insert(problems, "Mina wasn't made Co-Leader")
			end
			press("Leave")
			press("Leave")
			if crewDesk:mineId(1) ~= nil or crewDesk:crew(mine.crew.id).members["8"].role ~= "leader" then
				table.insert(problems, "leaving didn't hand the lead to Mina")
			end
		end
		-- Join Rosa's open crew from the browser; her card shows its badge.
		local nite = hud.gui:FindFirstChild("CrewNITE", true)
		local join = nite and nite:FindFirstChild("Join", true)
		local joinButton = join and (if join:IsA("GuiButton") then join else join:FindFirstChildWhichIsA("GuiButton", true))
		if joinButton then
			signalFor(joinButton, "Activated"):Fire()
			Emu.resumeWaits()
		end
		if crewDesk:mineId(1) == nil then
			table.insert(problems, "couldn't join Night Riders")
		end
		shot("crew-joined", nil)
		-- The weekly goal: Rosa and I fill it, and the chest pays out.
		local niteId = crewDesk:mineId(1)
		if niteId then
			goalDesk:add(2, niteId, 2, 240, 0)
			-- Rosa asks for parts.
			partsDesk:ask(2, niteId, "Rosa")
			goalDesk:add(1, niteId, 2, 100, 10)
			local before = towns:save(1).coins or 0
			hud.ctx.close()
			hud.openPanel("friends", "clan")
			Emu.resumeWaits()
			shot("crew-goal", nil)
			if not hud.gui:FindFirstChild("OpenChat", true) then
				table.insert(problems, "no crew chat row for a player who can chat")
			end
			local chest = hud.gui:FindFirstChild("Chest", true)
			local open = chest and chest:FindFirstChild("Open", true)
			local openButton = open and (if open:IsA("GuiButton") then open else open:FindFirstChildWhichIsA("GuiButton", true))
			if openButton then
				signalFor(openButton, "Activated"):Fire()
				Emu.resumeWaits()
			else
				table.insert(problems, "no Open button on the crew chest")
			end
			local pay = emu.require(G.data).payAt(emu.require(G.data).CREW_CHEST, towns:save(1).level or 1)
			if (towns:save(1).crewChests or 0) ~= 1 or (towns:save(1).coins or 0) < before + pay.coins then
				table.insert(problems, `the crew chest didn't pay: {towns:save(1).crewChests} chests, coins {before} -> {towns:save(1).coins}`)
			end
			shot("crew-goal-opened", nil)
			-- Part requests: ask, give Rosa one, and collect what she gives back.
			press("AskParts")
			if #partsDesk:list(niteId, 1) ~= 2 then
				table.insert(problems, "asking for parts didn't add a request")
			end
			local partsBefore = towns:save(1).parts or 0
			local rosa = hud.gui:FindFirstChild("PartAsk2", true)
			local give = rosa and rosa:FindFirstChild("Give", true)
			local giveButton = give and (if give:IsA("GuiButton") then give else give:FindFirstChildWhichIsA("GuiButton", true))
			if giveButton then
				signalFor(giveButton, "Activated"):Fire()
				Emu.resumeWaits()
			end
			if (towns:save(1).parts or 0) ~= partsBefore - 1 then
				table.insert(problems, `giving a part didn't take one: {partsBefore} -> {towns:save(1).parts}`)
			end
			partsDesk:give(2, niteId, 1)
			partsDesk:give(2, niteId, 1)
			hud.ctx.close()
			hud.openPanel("friends", "clan")
			Emu.resumeWaits()
			if (towns:save(1).parts or 0) ~= partsBefore + 1 then
				table.insert(problems, `the parts Rosa gave weren't collected: {partsBefore} -> {towns:save(1).parts}`)
			end
			shot("crew-parts", nil)
			if not hud.gui:FindFirstChild("Rung2", true) or not (hud.gui:FindFirstChild("Rung2", true) :: any):FindFirstChild("Race", true) then
				table.insert(problems, "the crew ladder doesn't list Rosa with a Race button")
			end
			-- Scrolled down to the ladder.
			local scroll = hud.gui:FindFirstChild("Ladder", true)
			local sf = scroll and scroll:FindFirstAncestorWhichIsA("ScrollingFrame")
			if sf then
				sf.CanvasPosition = roblox.Vector2.new(0, 600)
			end
			shot("crew-ladder", nil)
			battles.crew = niteId
		-- This week's crew battle: Rosa and I race; then the week ends and the chests open.
			battles.desk:races(1, niteId, "You", 60, 20)
			battles.desk:races(2, niteId, "Rosa", 12, 3)
			battles.desk:live(1, niteId, "You", 7, "crew2")
			hud.ctx.close()
			hud.openPanel("friends", "clan")
			Emu.resumeWaits()
			local card = hud.gui:FindFirstChild("Battle", true)
			if not card or not card:FindFirstChild("UsScore", true) or (card:FindFirstChild("UsScore", true) :: any).Text ~= tostring(battles.desk:score(niteId, (battles.desk.weeks(battles.now)))) then
				table.insert(problems, "the crew battle card doesn't show our score")
			end
			local sf2 = card and card:FindFirstAncestorWhichIsA("ScrollingFrame")
			if sf2 then
				sf2.CanvasPosition = roblox.Vector2.new(0, 170)
			end
			shot("crew-battle", nil)
			-- The first war chest, this week.
			local warBefore = towns:save(1).crewChests or 0
			press("WarChest1")
			if (towns:save(1).crewChests or 0) ~= warBefore + 1 then
				table.insert(problems, `the first war chest didn't pay: {warBefore} -> {towns:save(1).crewChests}`)
			end
			if sf2 then
				local card2 = hud.gui:FindFirstChild("WarTrack", true)
				local sf3 = card2 and card2:FindFirstAncestorWhichIsA("ScrollingFrame")
				if sf3 then
					sf3.CanvasPosition = roblox.Vector2.new(0, 330)
				end
			end
			shot("crew-war-track", nil)
			local root = hud.gui:FindFirstChild("Root")
			root.Size = roblox.UDim2.fromOffset(1535, 709)
			shot("crew-battle-phone", nil, 1535, 709)
			root.Size = roblox.UDim2.fromOffset(1280, 800)
			battles.now += 7 * 86400
			local chestsBefore = towns:save(1).crewChests or 0
			hud.ctx.close()
			hud.openPanel("friends", "clan")
			Emu.resumeWaits()
			local won = battles.desk:battle(1, niteId, battles.opened()).last
			shot("crew-battle-won", nil)
			if won.result == "win" then
				press("BattleChest")
				press("MvpChest")
				press("LastWarChest2")
				if (towns:save(1).crewChests or 0) ~= chestsBefore + 3 then
					table.insert(problems, `the battle chests didn't pay: {chestsBefore} -> {towns:save(1).crewChests}`)
				end
				if hud.gui:FindFirstChild("BattleChest", true) then
					table.insert(problems, "the victory chest is still there after opening")
				end
			else
				table.insert(problems, `the crew battle wasn't won: {won.us.score} to {won.them.score}`)
			end
			if not hud.gui:FindFirstChild("Battle", true) then
				table.insert(problems, "no crew battle card in the new week")
			end
			if not hud.gui:FindFirstChild("War1", true) or not hud.gui:FindFirstChild("LeagueName", true) then
				table.insert(problems, "no war log or league after a finished war")
			end
			local log = hud.gui:FindFirstChild("War1", true)
			local sf4 = log and log:FindFirstAncestorWhichIsA("ScrollingFrame")
			if sf4 then
				sf4.CanvasPosition = roblox.Vector2.new(0, 360)
			end
			shot("crew-war-log", nil)
		end
		crewDesk:leave(1)
		hud.ctx.close()
		print(`crews: {#problems} problems {table.concat(problems, "; ")}`)
		bad += #problems
	end
	-- Friends' mail: the gift bell's panel, then Collect pays 15 fuel and 5 parts plus the help's 10.
	hud.openPanel("gifts")
	assert(hud.gui:FindFirstChild("Postcard", true), "Kai's postcard isn't in the mail")
	shot("panel-gifts", nil)
	local fuelBefore = store.useGame.getState().fuel
	local collectShadow = hud.gui:FindFirstChild("Collect", true)
	local collectButton = if collectShadow:IsA("GuiButton") then collectShadow else collectShadow:FindFirstChildWhichIsA("GuiButton", true)
	signalFor(collectButton, "Activated"):Fire()
	assert(store.useGame.getState().fuel == fuelBefore + 25, `collecting the mail gave {store.useGame.getState().fuel - fuelBefore} fuel, not 25`)
	assert(#mailDesk:inbox(1).notes == 0, "the notes are still waiting after Collect")
	print("mail: collect")
	hud.ctx.close()
	-- Send Rosa a postcard from the Friends tab.
	hud.openPanel("friends")
	local cardButton
	for _, d in hud.gui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "💌" and d:FindFirstAncestor("Rosa") then
			cardButton = d:FindFirstAncestorWhichIsA("GuiButton")
		end
	end
	assert(cardButton, "no postcard button on Rosa's row")
	signalFor(cardButton, "Activated"):Fire()
	assert(hud.gui:FindFirstChild("PostcardPicker", true), "the postcard picker didn't open")
	shot("panel-postcard", nil)
	local send = hud.gui:FindFirstChild("PostcardPicker", true):FindFirstChild("Send", true)
	signalFor(if send:IsA("GuiButton") then send else send:FindFirstChildWhichIsA("GuiButton", true), "Activated"):Fire()
	assert(#mailDesk:inbox(2).cards == 1, "Rosa didn't get the postcard")
	print("mail: postcard sent")
	hud.ctx.close()
	local info = select(2, socialDesk("visit", 2))
	hud.ctx.setVisit(info)
	local shop = info.asking[1]
	assert(shop, "Rosa's town has no business to help")
	socialDesk("help", shop)
	shot("visit", nil)
	local home
	for _, d in hud.gui:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "🏠 Home" and d.Parent:IsA("GuiButton") then
			home = d.Parent
		end
	end
	assert(home, "no Home button on the visit banner")
	signalFor(home, "Activated"):Fire()
	assert(hud.ctx.visiting == nil, "going home didn't end the visit")
	print("social: friends, visit, help, home")
	-- The Bank, wide and on a phone: an 844 x 390 screen scales the HUD by 0.55, so it lays out at
	-- 1535 x 709 (render at that size, then shrink the picture to 844 x 390).
	local root = hud.gui:FindFirstChild("Root")
	for _, size in { { 1280, 800, "" }, { 1535, 709, "-phone" } } do
		root.Size = roblox.UDim2.fromOffset(size[1], size[2])
		for _, p in { "bank", "carpacks" } do
			hud.ctx.close()
			hud.openPanel(p)
			shot(`panel-{p}{size[3]}`, nil, size[1], size[2])
		end
	end
	root.Size = roblox.UDim2.fromOffset(1280, 800)
	-- Paint: try chrome with white stripes on the first car, look at a locked colour, then buy.
	towns:_with(1, function()
		-- Gems and stock cars again: pressing every Mods button above spent them and fitted parts.
		local cars = {}
		for i, c in store.useGame.getState().cars do
			cars[i] = table.clone(c)
			cars[i].mods = nil
			cars[i].ownedMods = nil
		end
		store.useGame.setState({ coins = 1000000, bucks = 1000, level = 10, cars = cars, selectedCar = cars[1].uid })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("cars", "garage")
	local function tap(name)
		local b = hud.gui:FindFirstChild(name, true)
		assert(b, `no {name} button`)
		signalFor(b, "Activated"):Fire()
	end
	tap("paint")
	shot("paint", nil)
	tap("chrome")
	tap("stripe2")
	shot("paint-try", nil)
	tap("#8c1d40")
	shot("paint-locked", nil)
	tap("#1e88e5")
	local paintShop = hud.gui:FindFirstChild("PaintShop", true)
	local paintBar = paintShop and paintShop.Parent:FindFirstChild("TryBar")
	local paintGo = paintBar and paintBar:FindFirstChild("Go", true)
	assert(paintGo, "no buy button for the paint job")
	signalFor(paintGo, "Activated"):Fire()
	-- The car the garage shows (the top of its list, which earlier presses may have changed): the
	-- one the paint job went on.
	local shownUid = nil
	for _, c in towns:snapshot(1).save.cars do
		if c.finish == "chrome" and c.color == "#1e88e5" then
			shownUid = c.uid
		end
	end
	local function shown(): any
		for _, c in towns:snapshot(1).save.cars do
			if c.uid == shownUid then
				return c
			end
		end
		return {}
	end
	local painted = shown()
	assert(painted.finish == "chrome" and painted.stripe == "#fafafa" and painted.color == "#1e88e5", `paint job didn't stick: {painted.color} {painted.finish} {painted.stripe}`)
	shot("paint-bought", nil)
	-- Skins: try Hexcore (won at level 3) and put it on.
	tap("hexcore")
	shot("skins-try", nil)
	local skins = hud.gui:FindFirstChild("BodySkins", true)
	local putOn = skins and skins:FindFirstChild("Go", true)
	assert(putOn, "no Put on button for the skin")
	signalFor(putOn, "Activated"):Fire()
	assert(shown().skin == "hexcore", "the skin didn't stick")
	shot("skins-on", nil)
	-- Hats: try the cap, make it two colours with a blue brim and wear it; then look at a locked one.
	towns:_with(1, function()
		store.useGame.setState({ hats = { "cap", "tophat" } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("cars", "garage")
	tap("hats")
	shot("hats", nil)
	tap("cap")
	tap("TwoColours")
	tap("Brim#1e88e5")
	shot("hats-try", nil)
	tap("Go")
	local capped = shown().hat
	assert(capped and capped.id == "cap" and capped.colors and capped.colors[2] == "#1e88e5", "the cap didn't stick")
	shot("hats-worn", nil)
	tap("crown")
	shot("hats-locked", nil)
	-- Mods: try the GT Wing and fit it, then try gold rims and a lift kit on top.
	towns:_with(1, function()
		store.useGame.setState({ parts = 500 })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("cars", "garage")
	tap("mods")
	shot("mods", nil)
	tap("gtwing")
	shot("mods-try", nil)
	local wing = hud.gui:FindFirstChild("gtwing", true)
	local buy = wing and wing:FindFirstChild("Go", true)
	assert(buy, "no buy button on the GT Wing")
	signalFor(buy, "Activated"):Fire()
	local modded = shown().mods or {}
	assert(table.find(modded, "gtwing"), "the GT Wing didn't stick")
	shot("mods-fitted", nil)
	-- A mod skin on the wing: Ember (won at level 5).
	tap("ember")
	local modSkins = hud.gui:FindFirstChild("ModSkins", true)
	local skinGo = modSkins and modSkins:FindFirstChild("Go", true)
	assert(skinGo, "no Put on button for the mod skin")
	signalFor(skinGo, "Activated"):Fire()
	local ms = shown().modSkin
	assert(ms and ms.spoiler == "ember", "the mod skin didn't stick")
	shot("mods-skin", nil)
	tap("rims")
	tap("goldmesh")
	shot("mods-rims", nil)
	tap("stance")
	tap("lifted")
	shot("mods-stance", nil)
	-- Custom: a blue hood with camo, carbon on the body and gold rims, then buy it.
	towns:_with(1, function()
		local cars = {}
		for i, c in store.useGame.getState().cars do
			cars[i] = table.clone(c)
			cars[i].mods = nil
			cars[i].panels = nil
		end
		store.useGame.setState({ coins = 1000000, cars = cars })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("cars", "garage")
	tap("custom")
	shot("custom", nil)
	tap("hood")
	tap("#1e88e5")
	tap("camo")
	shot("custom-hood", nil)
	tap("body")
	tap("carbon")
	tap("rims")
	tap("#fafafa")
	shot("custom-try", nil)
	tap("Go")
	local custom = shown().panels
	assert(custom and custom.hood and custom.hood.color == "#1e88e5" and custom.hood.pattern == "camo", "the custom paint didn't stick")
	shot("custom-bought", nil)
	-- Trim: try limo tint, violet headlights and black handles, buy them, then save the look.
	towns:_with(1, function()
		local cars = {}
		for i, c in store.useGame.getState().cars do
			cars[i] = table.clone(c)
			cars[i].trim = nil
		end
		store.useGame.setState({ coins = 1000000, level = 10, cars = cars, presets = {} })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("cars", "garage")
	tap("trim")
	shot("trim", nil)
	tap("tint:smoke")
	tap("lights:violet")
	tap("handles:black")
	shot("trim-try", nil)
	tap("Go")
	local trimmed = shown().trim
	assert(trimmed and trimmed.tint == "smoke" and trimmed.lights == "violet" and trimmed.handles == "black", "the trim didn't stick")
	tap("Save")
	local saved = towns:snapshot(1).save.presets
	assert(saved and saved[1] and saved[1].trim and saved[1].trim.tint == "smoke", "the look didn't save")
	shot("trim-bought", nil)
	-- Call Cards: wearing one you won, then looking at one still locked.
	towns:_with(1, function()
		store.useGame.setState({ callCards = { "neonalley", "plasma", "goldrush" }, callCard = "neonalley" })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("cars", "cards")
	shot("cards", nil)
	local thunder = hud.gui:FindFirstChild("thunderroad", true)
	if thunder then
		signalFor(thunder, "Activated"):Fire()
		shot("cards-locked", nil)
	end
	local gold = hud.gui:FindFirstChild("goldrush", true)
	local go = nil
	if gold then
		signalFor(gold, "Activated"):Fire()
		go = hud.gui:FindFirstChild("Go", true)
	end
	if go then
		signalFor(go, "Activated"):Fire()
		assert(towns:snapshot(1).save.callCard == "goldrush", "equipping a Call Card didn't stick")
		shot("cards-equipped", nil)
	end
	hud.ctx.close()
	hud.openPanel("crates")
	shot("crates", nil)
	-- Open one with coins to spare, let the crate burst, and picture the prize; then ten.
	towns:_with(1, function()
		store.useGame.setState({ coins = 1000000 })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("crates")
	local depot = hud.gui:FindFirstChild("Depot", true)
	local openB = depot and depot:FindFirstChild("Open", true)
	if openB then
		signalFor(openB, "Activated"):Fire()
		-- Once for the server's answer, once for the burst.
		Emu.resumeWaits()
		Emu.resumeWaits()
		shot("crate-prize", nil)
	end
	hud.ctx.close()
	hud.openPanel("crates")
	depot = hud.gui:FindFirstChild("Depot", true)
	local tenB = depot and depot:FindFirstChild("Ten", true)
	if tenB then
		signalFor(tenB, "Activated"):Fire()
		Emu.resumeWaits()
		Emu.resumeWaits()
		shot("crate-ten", nil)
	end
	-- Where paid random items are restricted: no gem crates, a line saying so; coin crates as usual.
	setRules({ ArePaidRandomItemsRestricted = true })
	hud.ctx.close()
	hud.openPanel("crates")
	depot = hud.gui:FindFirstChild("Depot", true)
	local function tabNamed(name)
		for _, d in depot:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == name and d.Parent:IsA("TextButton") then
				return d.Parent
			end
		end
		return nil
	end
	assert(depot and depot:FindFirstChild("NoBuy", true), "no note for a restricted player")
	assert(not tabNamed("Gold") and not tabNamed("Diamond"), "a restricted player sees gem crates")
	assert(tabNamed("Street") and depot:FindFirstChild("Open", true), "coin crates went too")
	shot("crate-restricted", nil)
	-- An arcade prize is a free Gold Crate: it shows, and opens, while it's there.
	towns:_with(1, function()
		store.useGame.setState({ freeCrates = { "arcade:emu" } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("crates")
	depot = hud.gui:FindFirstChild("Depot", true)
	for _, d in depot:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == "Gold" and d.Parent:IsA("TextButton") then
			signalFor(d.Parent, "Activated"):Fire()
			break
		end
	end
	depot = hud.gui:FindFirstChild("Depot", true)
	openB = depot and depot:FindFirstChild("Open", true)
	assert(openB, "a restricted player can't open a free crate")
	shot("crate-restricted-free", nil)
	local gemsBefore = towns:snapshot(1).save.bucks
	signalFor(openB, "Activated"):Fire()
	Emu.resumeWaits()
	Emu.resumeWaits()
	assert(#(towns:snapshot(1).save.freeCrates or {}) == 0, "the free crate wasn't opened")
	assert(towns:snapshot(1).save.bucks >= gemsBefore, "a free crate cost gems")
	print("crates: restricted player sees no gem crates, free gold crate opened")
	setRules({ ArePaidRandomItemsRestricted = false })
	-- The 3D depot on a computer, a phone held sideways and one held upright: the crate waiting,
	-- straining, its prize up, then a ×10 run and its summary (frames stepped by hand).
	if SHOTS then
		local root = hud.gui:FindFirstChild("Root")
		local cam = game.Workspace.CurrentCamera
		local function frames(sec)
			for _ = 1, math.floor(sec * 60) do
				local step = renderSteps.CrateDepot
				if step then
					step(1 / 60)
				end
			end
		end
		towns:_with(1, function()
			store.useGame.setState({ coins = 1000000, bucks = 5000, level = 30 })
		end)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		for _, size in { { 1280, 800, 1280, 800, "wide" }, { 844, 390, 1535, 709, "side" }, { 390, 844, 709, 1535, "tall" } } do
			cam.ViewportSize = roblox.Vector2.new(size[1], size[2])
			root.Size = roblox.UDim2.fromOffset(size[3], size[4])
			hud.ctx.close()
			hud.openPanel("crates")
			local function world()
				return game.Workspace:FindFirstChild("CrateDepot")
			end
			local function pickTab(name)
				local d = hud.gui:FindFirstChild("Depot", true)
				for _, x in d:GetDescendants() do
					if x:IsA("TextLabel") and x.Text == name and x.Parent:IsA("TextButton") then
						signalFor(x.Parent, "Activated"):Fire()
						return
					end
				end
			end
			pickTab("Gold")
			frames(1.2)
			shot(`depot-idle-{size[5]}`, world(), size[3], size[4])
			local d = hud.gui:FindFirstChild("Depot", true)
			signalFor(d:FindFirstChild("Open", true), "Activated"):Fire()
			Emu.resumeWaits()
			frames(0.55 + 0.35 + 0.9)
			shot(`depot-charge-{size[5]}`, world(), size[3], size[4])
			frames(0.45)
			shot(`depot-burst-{size[5]}`, world(), size[3], size[4])
			frames(2.6)
			Emu.resumeWaits()
			frames(0.05)
			shot(`depot-prize-{size[5]}`, world(), size[3], size[4])
			d = hud.gui:FindFirstChild("Depot", true)
			local function done()
				local dd = hud.gui:FindFirstChild("Depot", true)
				for _, x in (dd and dd:GetDescendants() or {}) do
					if x:IsA("TextLabel") and x.Text == "Done" and x.Parent:IsA("TextButton") then
						signalFor(x.Parent, "Activated"):Fire()
						return
					end
				end
			end
			done()
			pickTab("Street")
			d = hud.gui:FindFirstChild("Depot", true)
			signalFor(d:FindFirstChild("Ten", true), "Activated"):Fire()
			Emu.resumeWaits()
			frames(1.2)
			shot(`depot-ten-{size[5]}`, world(), size[3], size[4])
			for _ = 1, 40 do
				frames(0.5)
				Emu.resumeWaits()
				if hud.gui:FindFirstChild("Summary", true) then
					break
				end
			end
			frames(2.6)
			Emu.resumeWaits()
			frames(0.05)
			shot(`depot-summary-{size[5]}`, world(), size[3], size[4])
			done()
		end
		cam.ViewportSize = roblox.Vector2.new(1280, 800)
		root.Size = roblox.UDim2.fromOffset(1280, 800)
		hud.ctx.close()
	end

	-- Rusty's: both tabs, a search part done, the haul towed home, and a finished car's plate.
	towns:run(1, "abandonSearch")
	rustyTown()
	hud.ctx.close()
	hud.openPanel("rescue")
	local function press(name)
		local b = hud.gui:FindFirstChild(name, true)
		if b then
			signalFor(b, "Activated"):Fire()
			Emu.resumeWaits()
		end
		return b ~= nil
	end
	local function tabTo(id)
		local holder = hud.gui:FindFirstChild("Rescue", true)
		local tabs = holder and holder:FindFirstChild("Tabs", true)
		local t = tabs and tabs:FindFirstChild(id, true)
		local face = t and t:FindFirstChild("Face")
		if face then
			signalFor(face, "Activated"):Fire()
		end
	end
	tabTo("storage")
	shot("rescue-lot", nil)
	tabTo("find")
	shot("rescue-find", nil)
	-- A full lot: its count goes red and the lots fade.
	do
		local data = emu.require(RS.Shared.Game.data)
		towns:_with(1, function()
			local junk = {}
			for i = 1, data.STORAGE_MAX do
				table.insert(junk, { uid = `f{i}`, model = if i % 2 == 0 then "woodie" else "pip", rarity = if i == 1 then "rare" else "common" })
			end
			store.useGame.setState({ junkyard = junk })
		end)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		hud.ctx.close()
		hud.openPanel("rescue")
		tabTo("find")
		local holder = hud.gui:FindFirstChild("Rescue", true)
		assert(holder and holder:FindFirstChild("Dim", true), "a full lot doesn't fade the lots")
		shot("rescue-full", nil)
		rustyTown()
		hud.ctx.close()
		hud.openPanel("rescue")
	end
	-- An empty bay brings the picked car's Restore button into view.
	towns:_with(1, function()
		store.useGame.setState({ restoring = nil })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	tabTo("storage")
	do
		local holder = hud.gui:FindFirstChild("Rescue", true)
		assert(holder and holder:FindFirstChild("LotPick", true), "no picked car on the lot")
	end
	shot("rescue-bay-free", nil)
	rustyTown()
	tabTo("find")
	game.Workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(1280, 800)
	press("suburbs")
	-- The search is a 3D lot on its own screen (RescueLot), driven a frame at a time.
	local function sgui()
		return player.PlayerGui:FindFirstChild("RescueSearch")
	end
	local function sfind(name)
		local g = sgui()
		return g and g:FindFirstChild(name, true)
	end
	local function spress(name)
		local b = sfind(name)
		if b then
			signalFor(b, "Activated"):Fire()
			Emu.resumeWaits()
		end
		return b ~= nil
	end
	local function sync()
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	end
	-- Runs the lot for n frames (passing on the server's news); stops early once until() says so.
	local function lotFrames(n, untilFn)
		for f = 1, n do
			local step = renderSteps.RescueLot
			if not step then
				return false
			end
			step(1 / 30)
			if f % 5 == 0 then
				sync()
			end
			if untilFn and untilFn() then
				return true
			end
			Emu.resumeWaits()
		end
		return false
	end
	local RescueLot = emu.require(client.RescueLot)
	local hudGui = if hud.gui:IsA("ScreenGui") then hud.gui else hud.gui:FindFirstAncestorOfClass("ScreenGui")
	assert(sgui() and renderSteps.RescueLot, "the search didn't open the 3D lot")
	assert(not hudGui.Enabled, "the HUD stayed up over the lot")
	assert(game.Workspace:FindFirstChild("RescueLot"), "no lot in the world")
	lotFrames(90)
	assert(sfind("Coach"), "no coach on a fresh search")
	shot("rescue-search-start", game.Workspace:FindFirstChild("RescueLot"))
	-- And on a phone (844 x 390 scales the HUD by 0.55, so it lays out at 1535 x 709).
	do
		local root = hud.gui:FindFirstChild("Root")
		local cam = game.Workspace.CurrentCamera
		root.Size = roblox.UDim2.fromOffset(1535, 709)
		cam.ViewportSize = roblox.Vector2.new(1535, 709)
		lotFrames(2)
		-- (The emulator doesn't fire property changes: follow the HUD's size by hand.)
		sfind("SearchScreen").Size = root.Size
		shot("rescue-search-start-phone", game.Workspace:FindFirstChild("RescueLot"), 1535, 709)
		root.Size = roblox.UDim2.fromOffset(1280, 800)
		sfind("SearchScreen").Size = root.Size
		cam.ViewportSize = roblox.Vector2.new(1280, 800)
		lotFrames(2)
	end
	-- Tapping a spot drives the truck there; the tarp comes off and the find is lifted aboard.
	for i = 1, 3 do
		local q = towns:snapshot(1).search
		if q and not q.flat then
			RescueLot.current():pick(i)
			lotFrames(240)
		end
	end
	assert(towns:snapshot(1).search.revealed[1], "driving to a spot didn't search it")
	shot("rescue-search", game.Workspace:FindFirstChild("RescueLot"))
	-- The next find pops up over the lot.
	do
		local q = towns:snapshot(1).search
		if q and not q.flat then
			for i, r in q.revealed do
				if not r then
					RescueLot.current():pick(i)
					break
				end
			end
			local popped = lotFrames(240, function()
				return sfind("Found") ~= nil
			end)
			if not towns:snapshot(1).search.flat then
				assert(popped, "no find pop-up")
				shot("rescue-found", game.Workspace:FindFirstChild("RescueLot"))
			end
			lotFrames(120)
		end
	end
	-- Leave with a haul aboard asks first; Cancel keeps the search going.
	do
		local q = towns:snapshot(1).search
		if q and q.flat then
			spress("FixTruck")
			sync()
		end
		local leave = sfind("Leave")
		signalFor(leave:FindFirstChild("Face") or leave, "Activated"):Fire()
		local ask = sfind("Confirm")
		assert(ask, "Leave with a haul didn't ask")
		shot("rescue-leave", game.Workspace:FindFirstChild("RescueLot"))
		spress("Cancel")
		assert(towns:snapshot(1).search, "Cancel left the lot")
		assert(not sfind("Confirm"), "Cancel didn't close the question")
	end
	-- Search all turns into Stop while it runs, and the truck carries on by itself.
	do
		local all = sfind("SearchAll")
		if all then
			local before = 0
			for _, r in towns:snapshot(1).search.revealed do
				before += if r then 1 else 0
			end
			signalFor(all, "Activated"):Fire()
			local again = sfind("SearchAll")
			local l = again and again:FindFirstChildWhichIsA("TextLabel", true)
			assert(not again or (l and l.Text:find("Stop")), "Search all didn't turn into Stop")
			lotFrames(150)
			local after = 0
			for _, r in towns:snapshot(1).search.revealed do
				after += if r then 1 else 0
			end
			assert(after > before or towns:snapshot(1).search.flat, "Search all didn't search")
			again = sfind("SearchAll")
			if again then
				signalFor(again, "Activated"):Fire()
			end
			lotFrames(150)
		end
	end
	if towns:snapshot(1).search and towns:snapshot(1).search.flat then
		spress("FixTruck")
		sync()
		lotFrames(30)
	end
	-- A resto-mod piece aboard, so the haul shows its puzzle.
	do
		local resto = emu.require(RS.Shared.Game.resto)
		local car = resto.restoCars()[1]
		towns:_with(1, function(s)
			-- And two cars, so the haul has cars to lay out.
			local q = table.clone(s.search)
			q.pins, q.revealed = table.clone(q.pins), table.clone(q.revealed)
			q.pins[1], q.revealed[1] = { kind = "car", model = "woodie", rarity = "scarce" }, true
			q.pins[2], q.revealed[2] = { kind = "car", model = "miata", rarity = "rare" }, true
			q.piece = { model = car.id, piece = 2 }
			store.useGame.setState({ search = q, restoParts = { `{car.id}:0` } })
		end)
		sync()
	end
	spress("TowHome")
	-- The truck drives off with its haul; then it's home.
	lotFrames(600)
	sync()
	assert(not towns:snapshot(1).search, "Tow home never got home")
	assert(not sgui() and not renderSteps.RescueLot and not game.Workspace:FindFirstChild("RescueLot"), "the lot stayed up after the search")
	assert(hudGui.Enabled, "the HUD didn't come back")
	-- The finds land one at a time and their counts roll up: let them all land.
	require("@lune/task").wait(0.7)
	Emu.resumeWaits()
	Emu.resumeWaits()
	assert(hud.gui:FindFirstChild("BuildArt", true), "no resto-mod puzzle in the haul")
	shot("rescue-haul", nil)
	press("HaulDone")
	towns:_with(1, function(s)
		store.useGame.setState({ restoring = { uid = "r1", model = "bug", rarity = "common", minutes = 5, endsAt = 0 } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("rescue")
	tabTo("storage")
	press("Collect")
	shot("rescue-plate", nil)
	-- Adding it opens the garage on the new car.
	press("AddToGarage")
	do
		local name = emu.require(RS.Shared.Game.data).carDef("bug").name
		local detail = hud.gui:FindFirstChild("Detail", true)
		local shown = false
		for _, d in (detail and detail:GetDescendants() or {}) do
			shown = shown or (d:IsA("TextLabel") and d.Text == name)
		end
		assert(shown, "the garage didn't open on the restored car")
		shot("rescue-garage", nil)
	end
end

-- A whole Quick Race, driven through the race screen's own buttons like a player would.
local function find(root, pred)
	for _, d in root:GetDescendants() do
		if pred(d) then
			return d
		end
	end
	return nil
end
local function label(b)
	local l = b:FindFirstChildWhichIsA("TextLabel", true)
	return l and l.Text or ""
end
-- Drives one Quick Race through the race screen's buttons, taking pictures at the frames listed
-- (tag names them). Returns the frames it ran, the shifts made and the result card, if it came up.
-- start: starts the race (default: the first Quick Race card's button); nil to drive a race
-- already on screen.
-- onFrame(frames, screen): called each frame, after the step (presses a race screen button).
local function runRace(tag, shotAt, start, onFrame)
	if start ~= false then
		renderSteps = {}
	end
	calls = {}
	handlerErrors = {}
	if start ~= false then
		hud.ctx.close()
		if start then
			start()
		else
			hud.openPanel("race", "quick")
			local go = find(hud.gui, function(d)
				return d:IsA("TextButton") and d.Visible and string.find(label(d), "🏁 %$") ~= nil
			end)
			assert(go, "no race button on the Quick Race page")
			signalFor(go, "Activated"):Fire()
		end
	end
	local screen = raceScreen()
	assert(screen, `no race screen ({table.concat(calls, ", ")}) {table.concat(handlerErrors, "; ")}`)
	local shift = find(screen, function(d) return d.Name == "Face" and d.Parent.Name == "Shift" end)
	local boost = find(screen, function(d) return d.Name == "Boost" end)
	local needle = find(screen, function(d) return d.Name == "Needle" end)
	local touch = { UserInputType = roblox.Enum.UserInputType.Touch, KeyCode = roblox.Enum.KeyCode.Unknown }
	local holding, frames, shifts = false, 0, 0
	local result
	while frames < 60 * 90 do
		frames += 1
		raceClock += 1 / 60
		local step = renderSteps.DragStrip
		if not step then
			break
		end
		step(1 / 60)
		Emu.resumeWaits()
		local word = label(shift)
		if word == "HOLD ▶" and not holding and frames > 100 then
			holding = true
			signalFor(shift, "InputBegan"):Fire(touch)
		elseif word == "SHIFT ▲" and holding then
			holding = false
			signalFor(game:GetService("UserInputService"), "InputEnded"):Fire(touch)
		elseif word == "SHIFT ▲" and needle.Rotation >= 6 then
			shifts += 1
			signalFor(shift, "InputBegan"):Fire(touch)
			signalFor(game:GetService("UserInputService"), "InputEnded"):Fire(touch)
			if shifts == 3 then
				signalFor(boost, "InputBegan"):Fire(touch)
			end
		end
		if onFrame then
			onFrame(frames, screen)
		end
		if shotAt[frames] then
			shot(`{tag}-{frames}`, game.Workspace:FindFirstChild("DragStrip"))
		end
		result = find(screen, function(d) return d.Name == "Result" end)
		if result then
			shot(`{tag}-result`, game.Workspace:FindFirstChild("DragStrip"))
			break
		end
	end
	return frames, shifts, result
end

-- SHOTS=1 also races once at every venue, from the line and from halfway down the strip.
if SHOTS then
	local venues = races.mods.venues
	local pick = venues.pickVenue
	for _, v in venues.VENUES do
		venues.pickVenue = function()
			return v
		end
		towns:_with(1, function(s)
			s.fuel = math.max(s.fuel, 50)
		end)
		runRace(`venue-{v.id}`, { [60] = true, [400] = true })
		local screen = raceScreen()
		local collect = screen and find(screen, function(d)
			return d:IsA("TextButton") and (label(d) == "Collect" or label(d) == "Back")
		end)
		assert(collect, `the race at {v.id} has no Collect or Back button`)
		signalFor(collect, "Activated"):Fire()
		Emu.resumeWaits()
		assert(not raceScreen(), `the race at {v.id} didn't close`)
	end
	venues.pickVenue = pick
end

local coinsBefore = towns:snapshot(1).save.coins
local frames, shifts, result = runRace("race", { [60] = true, [150] = true, [330] = true, [480] = true })
local texts = {}
if result then
	for _, d in result:GetDescendants() do
		if d:IsA("TextLabel") and d.Name ~= "Face" and d.Text ~= "" then
			table.insert(texts, d.Text)
		end
	end
end
print(`race: {frames} frames, {shifts} shifts, coins {coinsBefore} -> {towns:snapshot(1).save.coins}`)
print(`race result card: {table.concat(texts, " | ")}`)
print(`race calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)

-- The result card's words, in order.
local function cardText(result)
	local out = {}
	if result then
		for _, d in result:GetDescendants() do
			if d:IsA("TextLabel") and d.Name ~= "Face" and d.Text ~= "" then
				table.insert(out, d.Text)
			end
		end
	end
	return table.concat(out, " | ")
end
local function cardButton(text)
	local screen = raceScreen()
	return screen and find(screen, function(d)
		return d:IsA("TextButton") and string.find(label(d), text, 1, true) ~= nil
	end)
end
-- Closes the race screen left up by the last race (its result card's last button).
local function closeRace()
	local screen = raceScreen()
	if not screen then
		return
	end
	local b = cardButton("Collect") or cardButton("Back") or cardButton("Board")
	if b then
		signalFor(b, "Activated"):Fire()
		Emu.resumeWaits()
	end
	assert(not raceScreen(), "the last race screen didn't close")
end
closeRace()
local function topUp()
	closeRace()
	towns:_with(1, function(s)
		s.fuel = math.max(s.fuel, 50)
	end)
end

-- The 🎥 button: each tap steps to the next view (Wide, Bumper, TV, back to the chase) and flashes
-- its name; SHOTS=1 pictures each view once it has glided in.
do
	topUp()
	local seen = {}
	runRace("view", { [340] = true, [400] = true, [460] = true }, nil, function(frames, screen)
		if frames == 300 or frames == 360 or frames == 420 or frames == 480 then
			local btn = find(screen, function(d)
				return d.Name == "Camera" and d:IsA("TextButton")
			end)
			assert(btn, "no camera button on the race screen")
			signalFor(btn, "Activated"):Fire()
			local name = find(screen, function(d)
				return d.Name == "CameraName"
			end)
			table.insert(seen, if name and name.Visible then label(name) else "(none)")
		end
	end)
	print(`camera views: {table.concat(seen, ", ")}`)
	if table.concat(seen, ",") ~= "🎥 Wide,🎥 Bumper,🎥 TV,🎥 Chase" then
		bad += 1
		print("CAMERA: the views didn't step Wide, Bumper, TV, Chase")
	end
end

-- Live drag races: Rosa challenges you, the 🏁 bell rings, Race! takes you to the strip with her
-- car drawn from where her game says it is; she crosses the line slower, and you win the live prize.
do
	topUp()
	hud.ctx.close()
	local problems = {}
	local id = duels:challenge(2, 1)
	assert(id, "Rosa's challenge didn't go")
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	local bell = hud.gui:FindFirstChild("RaceBell", true)
	if not (bell and bell.Visible) then
		table.insert(problems, "the 🏁 bell didn't show")
	end
	local rosaAt = 0
	local coins = towns:snapshot(1).save.coins
	local frames, _, result = runRace("live", { [200] = true, [420] = true }, function()
		hud.openPanel("invites")
		shot("panel-invites", nil)
		local accept = find(hud.gui, function(d)
			return d:IsA("TextButton") and string.find(label(d), "Race!", 1, true) ~= nil
		end)
		assert(accept, "no Race! button on the challenge")
		signalFor(accept, "Activated"):Fire()
		Emu.resumeWaits()
	end, function(f, screen)
		-- Rosa's game: a slower run, sent every few frames.
		if f > 150 and f % 6 == 0 and duels:racing(2) then
			rosaAt = math.min(402, rosaAt + 2.2)
			signalFor(duelEvent, "OnClientEvent"):Fire("pos", { t = f / 60, dist = rosaAt, speed = 40, burning = false, done = false })
		end
		if f == 400 then
			local title = find(screen, function(d)
				return d:IsA("TextLabel") and string.find(d.Text, "Live race vs Rosa", 1, true) ~= nil
			end)
			if not title then
				table.insert(problems, "no Live race title")
			end
		end
		-- She finishes well behind (her game's finish: the server's replay of her run).
		local race = duels.races[id]
		if race and race.times[2] == nil and f > 300 then
			duels:finish(2, 40)
		end
	end)
	local text = cardText(result)
	print(`live race: {frames} frames; {text}`)
	if not result or not string.find(text, "YOU WIN", 1, true) then
		table.insert(problems, `no win card ({table.concat(calls, ", ")})`)
	end
	if towns:snapshot(1).save.coins <= coins then
		table.insert(problems, "the live prize wasn't paid")
	end
	local sentPos = 0
	for _, m in duelSent do
		if m.to == 2 and m.event == "pos" then
			sentPos += 1
		end
	end
	if sentPos < 10 then
		table.insert(problems, `Rosa only heard where your car was {sentPos} times`)
	end
	closeRace()
	-- The Live page lists Rosa to challenge; the ⚔️ button sends it.
	hud.openPanel("race", "live")
	Emu.resumeWaits()
	local ask = find(hud.gui, function(d)
		return d:IsA("TextButton") and string.find(label(d), "⚔️", 1, true) ~= nil and d:FindFirstAncestor("Driver2") ~= nil
	end)
	shot("race-live", nil)
	if ask then
		signalFor(ask, "Activated"):Fire()
		Emu.resumeWaits()
		local waiting = duels:invitesFor(2)
		if #waiting ~= 1 then
			table.insert(problems, "the ⚔️ button didn't challenge Rosa")
		end
		duels:cancel(1)
	else
		table.insert(problems, "no ⚔️ button for Rosa on the Live page")
	end
	hud.ctx.close()
	print(`live races: {#problems} problems {table.concat(problems, "; ")}`)
	bad += #problems
end

-- Paint rivals: the roster page, a race over a half mile at the beach, and its colour won.
topUp()
local rowStart = function()
	hud.openPanel("race", "rivals")
	local tile = find(hud.gui, function(d)
		return d:IsA("TextButton") and d.Name == "marina"
	end)
	assert(tile, "no Marina tile on the Paint Rivals page")
	signalFor(tile, "Activated"):Fire()
	local go = find(hud.gui, function(d)
		return d:IsA("TextButton") and d.Visible and string.find(label(d), "🏁 %$") ~= nil and d:FindFirstAncestor("Picked") ~= nil
	end)
	assert(go, "no race button for Marina")
	signalFor(go, "Activated"):Fire()
end
local rf, _, rres = runRace("row", { [60] = true, [700] = true, [1100] = true }, rowStart)
print(`paint rival: {rf} frames; card: {cardText(rres)}`)
print(`paint rival calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
local row = towns:snapshot(1).save.rivalRow or {}
if (row.marina or 0) > 0 then
	local paintIt = cardButton("Paint it")
	assert(paintIt, "no Paint it button after winning Marina's colour")
	signalFor(paintIt, "Activated"):Fire()
	Emu.resumeWaits()
	assert(not raceScreen(), "the race screen stayed up")
	local tried = find(hud.gui, function(d)
		return d.Name == "Shop" and d:FindFirstChild("PaintShop", true) ~= nil
	end)
	print(`paint it: garage paint tab open {tried ~= nil}`)
	if SHOTS then
		shot("row-paintit", nil)
	end
else
	local back = cardButton("Back")
	if back then
		signalFor(back, "Activated"):Fire()
		Emu.resumeWaits()
	end
	print("paint rival: lost to Marina")
end

-- A mile race on Main Street at night (Duchess Merlot), for the long strip and its finish line.
if SHOTS then
	topUp()
	local mileStart = function()
		hud.openPanel("race", "rivals")
		local tile = find(hud.gui, function(d)
			return d:IsA("TextButton") and d.Name == "merlot"
		end)
		signalFor(tile, "Activated"):Fire()
		local go = find(hud.gui, function(d)
			return d:IsA("TextButton") and d.Visible and string.find(label(d), "🏁 %$") ~= nil and d:FindFirstAncestor("Picked") ~= nil
		end)
		signalFor(go, "Activated"):Fire()
	end
	local mf, _, mres = runRace("mile", { [60] = true, [1500] = true, [2100] = true }, mileStart)
	print(`mile: {mf} frames; card: {cardText(mres)}`)
	local back = cardButton("Back")
	if back then
		signalFor(back, "Activated"):Fire()
		Emu.resumeWaits()
	end
end

-- The rival in town: race them from the front page (no double or nothing on Roblox).
topUp()
towns:_with(1, function()
	store.useGame.setState({ level = math.max(store.useGame.getState().level, emu.require(G.rivals).RIVAL_LEVEL) })
end)
hud.ctx.close()
local rivalStart = function()
	hud.openPanel("race", "hub")
	local tileFace = find(hud.gui, function(d)
		return d.Name == "Rival" and d:IsA("Frame")
	end)
	assert(tileFace, "no Rival tile")
	local go = find(tileFace, function(d)
		return d:IsA("TextButton") and string.find(label(d), "🏁 %$") ~= nil
	end)
	assert(go, "no race button on the Rival tile")
	signalFor(go, "Activated"):Fire()
end
local tf, _, tres = runRace("rival", { [60] = true }, rivalStart)
print(`town rival: {tf} frames; card: {cardText(tres)}`)
print(`town rival calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
assert(cardButton("Double or nothing") == nil, "double or nothing offered")
print(`rival calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)

-- A war race from the Crew tab's war map: back in Night Riders, race the street crew's first pick.
if battles.crew then
	local warProblems = {}
	crewDesk:ask(1, crewWho(1), battles.crew)
	towns:_with(1, function(s)
		s.fuel = math.max(s.fuel, 50)
	end)
	local wf, _, wres = runRace("war", { [60] = true }, function()
		hud.openPanel("friends", "clan")
		Emu.resumeWaits()
		-- (A prize pop-up left from an earlier race goes first.)
		for _ = 1, 3 do
			local nice = find(hud.gui, function(d)
				return d:IsA("TextButton") and d.Visible and label(d) == "Nice!"
			end)
			if nice then
				signalFor(nice, "Activated"):Fire()
				Emu.resumeWaits()
			end
		end
		local map = hud.gui:FindFirstChild("WarMap", true)
		if not map or not map:FindFirstChild("Them", true) then
			table.insert(warProblems, "no war map with their racers")
		end
		local sf = map and map:FindFirstAncestorWhichIsA("ScrollingFrame")
		if sf then
			sf.CanvasPosition = roblox.Vector2.new(0, 400)
		end
		shot("crew-war-map", nil)
		local b = map and map:FindFirstChild("WarRace", true)
		local face = b and (if b:IsA("GuiButton") then b else b:FindFirstChildWhichIsA("GuiButton", true))
		if face then
			signalFor(face, "Activated"):Fire()
			Emu.resumeWaits()
		else
			table.insert(warProblems, "no Race button on the war map")
		end
	end)
	local x = battles.desk:battleOf(battles.crew)
	local raced = x and battles.desk:attacks(x, battles.crew)
	if not wres or not raced or #raced ~= 1 then
		table.insert(warProblems, `the war race wasn't recorded ({wf} frames): {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
	end
	if not (wres and wres:FindFirstChild("WarStars", true)) then
		table.insert(warProblems, "no stars on the war race's result card")
	end
	local back = cardButton("Crew war")
	if back then
		signalFor(back, "Activated"):Fire()
		Emu.resumeWaits()
	end
	if not hud.gui:FindFirstChild("WarMap", true) or not hud.gui:FindFirstChild("Latest", true) then
		table.insert(warProblems, "the war map doesn't show the race after Crew war")
	end
	local after = hud.gui:FindFirstChild("WarMap", true)
	local sfa = after and after:FindFirstAncestorWhichIsA("ScrollingFrame")
	if sfa then
		sfa.CanvasPosition = roblox.Vector2.new(0, 400)
	end
	shot("crew-war-map-after", nil)
	hud.ctx.close()
	crewDesk:leave(1)
	print(`war races: {#warProblems} problems {table.concat(warProblems, "; ")}`)
	bad += #warProblems
end

-- A race from one of the other modes' pages (client/RacePages): opens the page from the front
-- page's small button, presses the first button whose words match `go`, and races.
local function modeRace(tag, mini, go, shotAt, keep)
	topUp()
	hud.ctx.close()
	local f, _, res = runRace(tag, shotAt or { [60] = true }, function()
		hud.openPanel("race", "hub")
		local m = find(hud.gui, function(d)
			return d:IsA("TextButton") and string.find(label(d), mini, 1, true) ~= nil and d:FindFirstAncestor("Minis") ~= nil
		end)
		assert(m, `no {mini} button on the front page`)
		signalFor(m, "Activated"):Fire()
		if SHOTS then
			shot(`page-{tag}`, nil)
		end
		local b = find(hud.gui, function(d)
			return d:IsA("TextButton") and d.Visible and string.find(label(d), go) ~= nil
		end)
		assert(b, `no race button on the {mini} page`)
		signalFor(b, "Activated"):Fire()
	end)
	print(`{tag}: {f} frames; card: {cardText(res)}`)
	print(`{tag} calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
	if not keep then
		closeRace()
	end
	return res
end

-- The World Tour: Street Racer reputation opens it; race Egypt.
towns:_with(1, function()
	store.useGame.setState({ trophies = math.max(store.useGame.getState().trophies, 400) })
end)
modeRace("world", "World Tour", "🏁 %$")
print(`world tour beaten: {towns:snapshot(1).save.worldTour or 0}`)

-- The Time Trial: the hub's tile opens the board; run against par, then your best.
local function trialRun(tag)
	topUp()
	hud.ctx.close()
	local f, _, res = runRace(tag, { [60] = true }, function()
		hud.openPanel("race", "hub")
		local tile = find(hud.gui, function(d)
			return d:IsA("TextButton") and (d.Name == "Trial" or (d.Parent and d.Parent.Name == "Trial"))
		end)
		assert(tile, "no Time Trial tile")
		signalFor(tile, "Activated"):Fire()
		Emu.resumeWaits()
		if SHOTS then
			shot(`page-{tag}`, nil)
		end
		local run = find(hud.gui, function(d)
			return d:IsA("TextButton") and d.Visible and string.find(label(d), "Run vs") ~= nil
		end)
		assert(run, `no Run button on the Time Trial page ({table.concat(calls, ", ")})`)
		signalFor(run, "Activated"):Fire()
	end)
	print(`{tag}: {f} frames; card: {cardText(res)}`)
	print(`{tag} calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
	closeRace()
end
trialRun("trial")
trialRun("trial2")
-- The Daily Run: the day's loaner against par; the first run of the day pays.
modeRace("daily", "Daily Run", "🏁 %$")
print(`daily run: {(towns:snapshot(1).save.daily or {}).best or "no time"}`)

-- The Pro Tour and the weekly event: each hub tile opens its page; race the tour's first leg boss
-- (Back Streets cleared) and the event's first race from their pages. Their prize cards are with
-- the other pop-ups below.
local function hubPage(tag, tileName)
	topUp()
	hud.ctx.close()
	-- Prize cards earlier races left: closed the way a player would.
	local OK = { ["Nice!"] = true, ["Awesome!"] = true, ["Keep going!"] = true, Continue = true, Later = true }
	for _ = 1, 10 do
		local p = hud.root:FindFirstChild("Popup")
		local b = p and find(p, function(d)
			return d:IsA("TextButton") and d.Name == "Face" and OK[label(d)] == true
		end)
		if not b then
			break
		end
		signalFor(b, "Activated"):Fire()
		Emu.resumeWaits()
	end
	-- Anything opening by itself (the Daily Spin at launch) goes first, then the menu.
	for _ = 1, 3 do
		hud.ctx.close()
		hud.openPanel("race", "hub")
		Emu.resumeWaits()
		if hud.root:FindFirstChild("Panel") then
			break
		end
	end
	local tile = find(hud.gui, function(d)
		return d:IsA("TextButton") and (d.Name == tileName or (d.Parent and d.Parent.Name == tileName))
	end)
	assert(tile, `no {tileName} tile`)
	if SHOTS then
		shot(`page-hub-{tag}`, nil)
	end
	signalFor(tile, "Activated"):Fire()
	Emu.resumeWaits()
	if SHOTS then
		shot(`page-{tag}`, nil)
	end
end
local function pageRace(tag, tileName)
	local f, _, res = runRace(tag, { [60] = true }, function()
		hubPage(tag, tileName)
		local b = find(hud.gui, function(d)
			return d:IsA("TextButton") and d.Visible and string.find(label(d), "🏁 %$") ~= nil and (d:FindFirstAncestor("Races") ~= nil or d:FindFirstAncestor("Versus") ~= nil)
		end)
		assert(b, `no race button on the {tag} page ({table.concat(calls, ", ")})`)
		signalFor(b, "Activated"):Fire()
	end)
	print(`{tag}: {f} frames; card: {cardText(res)}`)
	print(`{tag} calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
	closeRace()
	return res
end
do
	local dataMod = emu.require(G.data)
	local ch = dataMod.CAMPAIGN[1]
	-- Locked first: the page greys the first leg out under the way in.
	local before = towns:snapshot(1).save.campaign
	towns:_with(1, function()
		store.useGame.setState({ campaign = {} })
	end)
	hubPage("tour-locked", "Tour")
	local done = table.clone(before)
	for i = 0, dataMod.CAMPAIGN_RACES - 1 do
		done[dataMod.campaignRaceId(ch, i)] = 3
	end
	towns:_with(1, function()
		store.useGame.setState({ campaign = done, tour = 4 })
	end)
	pageRace("tour", "Tour")
	print(`pro tour: {towns:snapshot(1).save.tour or 0} races won`)
	pageRace("event", "Event")
	print(`weekly event: {store.useGame.getState().event and store.useGame.getState().event.won or 0} won`)
	towns:_with(1, function()
		store.useGame.setState({ campaign = before })
	end)
end
-- Tuner Trials: with the build missing, the race button opens the Garage; then the race car gets
-- Downforce Dash's build (a spoiler, snow studs, tuning) and races it for the Hex pattern.
do
	local tdata = emu.require(G.data)
	local rc = emu.require(G.raceCar)
	local function build(mods, up)
		towns:_with(1, function()
			local s = store.useGame.getState()
			local car = rc.raceCarOf(s.cars, s.raceCar)
			local cars = table.clone(s.cars)
			for i, c in cars do
				if c.uid == car.uid then
					local body = tdata.carDef(c.model).body
					local list = {}
					for _, slot in mods do
						if slot == "snowstuds" then
							table.insert(list, slot)
						else
							for _, m in tdata.MODS do
								if m.slot == slot and tdata.modFits(m, body) and (m.bucks or 0) == 0 then
									table.insert(list, m.id)
									break
								end
							end
						end
					end
					local c2 = table.clone(c)
					c2.mods = list
					c2.upgrades = up
					cars[i] = c2
				end
			end
			store.useGame.setState({ cars = cars, raceCar = car.uid, tuner = { boostbox = 1, pipes = 1 } })
		end)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		Emu.resumeWaits()
	end
	topUp()
	build({}, { engine = 0, turbo = 0, tires = 0, weight = 0 })
	hud.ctx.close()
	hud.openPanel("race", "tuner")
	local fit = find(hud.gui, function(d)
		return d:IsA("TextButton") and d.Visible and string.find(label(d), "Fit parts", 1, true) ~= nil
	end)
	assert(fit, "no Fit parts button on the Tuner Trials page")
	signalFor(fit, "Activated"):Fire()
	local garage = find(hud.gui, function(d)
		return d.Name == "Cars" and d:IsA("Frame")
	end)
	print(`tuner fit parts: {if garage then "garage opened" else "NO GARAGE"}`)
	assert(garage, "Fit parts didn't open the Garage")
	hud.ctx.close()
	build({ "spoiler", "snowstuds" }, { engine = 5, turbo = 5, tires = 5, weight = 5 })
	-- Raced from the page as modeRace does, then the result card's Paint it opens the Custom tab.
	topUp()
	hud.ctx.close()
	local tf, _, tres = runRace("tuner", { [60] = true }, function()
		hud.openPanel("race", "hub")
		local m = find(hud.gui, function(d)
			return d:IsA("TextButton") and string.find(label(d), "Tuner Trials", 1, true) ~= nil and d:FindFirstAncestor("Minis") ~= nil
		end)
		assert(m, "no Tuner Trials button on the front page")
		signalFor(m, "Activated"):Fire()
		if SHOTS then
			shot("page-tuner", nil)
		end
		local b = find(hud.gui, function(d)
			return d:IsA("TextButton") and d.Visible and string.find(label(d), "🏁 %$") ~= nil
		end)
		assert(b, "no race button on the Tuner Trials page")
		signalFor(b, "Activated"):Fire()
	end)
	print(`tuner: {tf} frames; card: {cardText(tres)}`)
	print(`tuner calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
	local tw = (towns:snapshot(1).save.tuner or {}).downforce or 0
	print(`tuner trials won: downforce ×{tw}`)
	if tw > 0 then
		local paintIt = cardButton("Paint it")
		assert(paintIt, "no Paint it button after winning the Hex pattern")
		signalFor(paintIt, "Activated"):Fire()
		Emu.resumeWaits()
		local custom = find(hud.gui, function(d)
			return d.Name == "CustomShop"
		end)
		print(`tuner paint it: garage custom tab open {custom ~= nil}`)
		assert(custom, "Paint it didn't open the Custom tab")
		hud.ctx.close()
	end
	closeRace()
end
-- A page from client/RacePages with no race: opens it from the front page's small button and
-- presses the first button whose words match `press` (a TextButton named `press` when byName),
-- asserting that nothing threw and the server took every call.
local function modePage(tag, mini, press, byName)
	closeRace()
	hud.ctx.close()
	calls = {}
	handlerErrors = {}
	hud.openPanel("race", "hub")
	local m = find(hud.gui, function(d)
		return d:IsA("TextButton") and string.find(label(d), mini, 1, true) ~= nil and d:FindFirstAncestor("Minis") ~= nil
	end)
	assert(m, `no {mini} button on the front page`)
	if SHOTS then
		-- The front page, with the reputation chip in its head.
		shot(`hub-{tag}`, nil)
	end
	signalFor(m, "Activated"):Fire()
	Emu.resumeWaits()
	if SHOTS then
		shot(`page-{tag}`, nil)
	end
	local b = find(hud.gui, function(d)
		return d:IsA("TextButton") and d.Visible and (if byName then d.Name == press else string.find(label(d), press) ~= nil)
	end)
	assert(b, `no {press} button on the {mini} page`)
	signalFor(b, "Activated"):Fire()
	Emu.resumeWaits()
	print(`{tag} calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
	assert(#handlerErrors == 0, `{tag}: {table.concat(handlerErrors, "; ")}`)
	for _, c in calls do
		assert(c:sub(1, 2) == "ok", `{tag}: {c}`)
	end
	if SHOTS then
		shot(`page-{tag}-after`, nil)
	end
	hud.ctx.close()
end

-- Ghost races: the page (players here, friends, a taunt left for you), a run against Mika's
-- best, and a taunt sent back from the result card.
do
	local gres = modeRace("ghost", "Ghosts", "👻 Best", { [60] = true }, true)
	assert(gres, "no ghost race result card")
	local chip = find(gres, function(d)
		return d:IsA("TextButton") and string.sub(d.Name, 1, 5) == "Taunt"
	end)
	assert(chip, "no taunt chips on the ghost result card")
	calls = {}
	signalFor(chip, "Activated"):Fire()
	Emu.resumeWaits()
	print(`ghost taunt calls: {table.concat(calls, ", ")}`)
	if SHOTS then
		shot("ghost-taunted", nil)
	end
	local inbox = races.mods.ghosts:inbox(2)
	assert(#inbox == 1 and inbox[1].from == 1, "the taunt didn't reach Mika")
	closeRace()
end

-- The Trophy Road: claim every stop the trophies reach.
local roadBefore = towns:snapshot(1).save.road or 0
modePage("road", "Trophy Road", "Claim")
local roadSave = towns:snapshot(1).save
print(`trophy road: {roadBefore} -> {roadSave.road} of {math.floor(roadSave.trophies / 25)} stops`)
assert((roadSave.road or 0) > roadBefore, "the Trophy Road claimed nothing")
-- Flair: the trophies opened Frost; pick it (seeing the page clears the new count too).
modePage("flair", "Flair", "frost", true)
local flairSave = towns:snapshot(1).save
print(`flair: trail {flairSave.trail}, seen {flairSave.flairSeen}`)
assert(flairSave.trail == "frost", "Frost wasn't picked")
-- Class Cups: the race car's own class opens first; race its first cup race.
modeRace("cup", "Class Cups", "🏁 %$")
print(`class cups won: {(function()
	local n = 0
	for _, w in towns:snapshot(1).save.cups or {} do
		n += w
	end
	return n
end)()}`)

-- Kart races (client/KartRun): a Grand Prix round from the Grand Prix page, driven on the AI's own
-- line (the web's ?autopilot) until the podium, then Bumper Blast from the front page's button,
-- then a custom race's card.
local KartRun = emu.require(client.KartRun)
-- Parts per circuit (each track both ways round), kept low enough for phones.
do
	local KartWorld = emu.require(client.KartWorld)
	local Kt = emu.require(G.kart)
	local most = 0
	for _, def in Kt.TRACKS do
		for _, rev in { false, true } do
			local m = KartWorld.circuit(Kt.buildTrack(def, rev))
			local n, by = 0, {}
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
					-- Parts of a model (a shop, a tree) count under the model's name.
					local top = d
					while top.Parent ~= m do
						top = top.Parent
					end
					local key = if top:IsA("Model") and top.Name ~= "Gantry" then `{top.Name}*` else d.Name
					by[key] = (by[key] or 0) + 1
				end
			end
			local top = {}
			for k, v in by do
				table.insert(top, { k, v })
			end
			table.sort(top, function(a, b)
				return a[2] > b[2]
			end)
			local parts = {}
			for i = 1, math.min(16, #top) do
				table.insert(parts, `{top[i][1]} {top[i][2]}`)
			end
			print(`kart circuit {def.id}{if rev then " reversed" else ""}: {n} parts ({table.concat(parts, ", ")})`)
			most = math.max(most, n)
		end
	end
	print(`kart circuits: at most {most} parts`)
	assert(most <= 3000, `a kart circuit has {most} parts (phones want 3000 or fewer)`)
end
local kartMost, kartRaceMost, kartPeak = {}, {}, {}
-- The sounds a kart race plays (Sfx.play by name), counted.
local KartSfx = emu.require(client.Sounds.Sfx)
local kartHeard = {}
do
	local play = KartSfx.play
	KartSfx.play = function(name, ...)
		kartHeard[name] = (kartHeard[name] or 0) + 1
		return play(name, ...)
	end
end
local function runKart(tag, shotAt, start)
	topUp()
	hud.ctx.close()
	renderSteps = {}
	calls = {}
	handlerErrors = {}
	table.clear(kartHeard)
	start()
	local screen = raceScreen()
	assert(screen, `{tag}: no kart race screen ({table.concat(calls, ", ")}) {table.concat(handlerErrors, "; ")}`)
	KartRun.autopilot = true
	local frames, podium = 0, nil
	local DT = 1 / 20
	while frames < 200 / DT do
		frames += 1
		raceClock += DT
		local step = renderSteps.KartRun
		if not step then
			break
		end
		step(DT)
		Emu.resumeWaits()
		-- Parts in the circuit as the race goes round (shops and trees fill in near the camera).
		if frames % 40 == 0 then
			local c = game.Workspace:FindFirstChild("KartCircuit")
			local n, race, by = 0, 0, {}
			for _, d in if c then c:GetDescendants() else {} do
				if d:IsA("BasePart") then
					n += 1
					if d:FindFirstAncestor("KartRace") then
						race += 1
					else
						local m = d:FindFirstAncestorWhichIsA("Model")
						local key = if m and m ~= c then `{m.Name}*` else d.Name
						by[key] = (by[key] or 0) + 1
					end
				end
			end
			if n - race > (kartMost[tag] or 0) then
				local top = {}
				for k, v in by do
					table.insert(top, { k, v })
				end
				table.sort(top, function(a, b)
					return a[2] > b[2]
				end)
				local list = {}
				for i = 1, math.min(10, #top) do
					table.insert(list, `{top[i][1]} {top[i][2]}`)
				end
				kartPeak[tag] = `{string.format("%.0f", frames * DT)}s: {table.concat(list, ", ")}`
			end
			kartMost[tag] = math.max(kartMost[tag] or 0, n - race)
			kartRaceMost[tag] = math.max(kartRaceMost[tag] or 0, race)
		end
		if shotAt[frames] then
			shot(`{tag}-{frames}`, game.Workspace:FindFirstChild("KartCircuit"))
		end
		podium = find(screen, function(d)
			return d.Name == "Podium"
		end)
		if podium then
			-- Half a second more, so the podium has the server's answer.
			for _ = 1, 12 do
				raceClock += DT
				renderSteps.KartRun(DT)
				Emu.resumeWaits()
			end
			podium = find(screen, function(d)
				return d.Name == "Podium"
			end)
			shot(`{tag}-result`, game.Workspace:FindFirstChild("KartCircuit"))
			break
		end
	end
	KartRun.autopilot = false
	print(`{tag}: {frames} frames ({string.format("%.1f", frames * DT)}s); podium: {cardText(podium)}`)
	print(`{tag}: at most {kartMost[tag]} circuit parts and {kartRaceMost[tag]} kart and effect parts during the race (most at {kartPeak[tag]})`)
	assert(kartMost[tag] <= 3000, `{tag}: {kartMost[tag]} circuit parts during the race (phones want 3000 or fewer)`)
	print(`{tag} calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
	assert(podium, `{tag}: the race never reached the podium`)
	local heard = {}
	for name, n in kartHeard do
		table.insert(heard, `{name} ×{n}`)
	end
	table.sort(heard)
	print(`{tag} sounds: {table.concat(heard, ", ")}`)
	assert(kartHeard.countdown == 5 and kartHeard["countdown-go"] == 1, `{tag}: the start lights weren't heard`)
	assert((kartHeard.win or 0) + (kartHeard.lose or 0) == 1, `{tag}: no win or lose sound at the line`)
	assert((kartHeard["arcade-ding"] or 0) >= 2, `{tag}: the laps weren't heard`)
	assert(#handlerErrors == 0, `{tag}: {table.concat(handlerErrors, "; ")}`)
	for _, c in calls do
		assert(c:sub(1, 2) == "ok", `{tag}: {c}`)
	end
	return podium
end
-- The Rookie Cup needs level 2 and three cars.
towns:_with(1, function(s)
	local cars = table.clone(s.cars)
	while #cars < 3 do
		table.insert(cars, { uid = `kart{#cars}`, model = "pip", color = "#ff0000", upgrades = { engine = 0, turbo = 0, tires = 0, weight = 0 } })
	end
	store.useGame.setState({ level = math.max(store.useGame.getState().level, 2), cars = cars })
end)
local gpBefore = towns:snapshot(1).save
runKart("kart-gp", { [40] = true, [700] = true }, function()
	hud.openPanel("race", "hub")
	local tile = find(hud.gui, function(d)
		return d:IsA("TextButton") and (d.Name == "GrandPrix" or (d.Parent and d.Parent.Name == "GrandPrix"))
	end)
	assert(tile, "no Grand Prix tile")
	signalFor(tile, "Activated"):Fire()
	Emu.resumeWaits()
	if SHOTS then
		shot("page-gp", nil)
	end
	local go = find(hud.gui, function(d)
		return d:IsA("TextButton") and d.Visible and string.find(label(d), "🏁 %$") ~= nil and d:FindFirstAncestor("rookie") ~= nil
	end)
	assert(go, `no race button for the Rookie Cup ({table.concat(calls, ", ")})`)
	signalFor(go, "Activated"):Fire()
end)
local gpAfter = towns:snapshot(1).save
print(`kart gp: coins {gpBefore.coins} -> {gpAfter.coins}, fuel {gpBefore.fuel} -> {gpAfter.fuel}, rookie round {((gpAfter.gp or {}).rookie or {}).round or 0}`)
assert(gpAfter.coins > gpBefore.coins, "the Grand Prix round paid nothing")
local kartBack = cardButton("Back")
assert(kartBack, "no Back on the podium")
signalFor(kartBack, "Activated"):Fire()
Emu.resumeWaits()
assert(not raceScreen(), "the kart race screen stayed up")
local blastBefore = towns:snapshot(1).save.coins
runKart("kart-blast", { [40] = true }, function()
	hud.openPanel("race", "hub")
	local m = find(hud.gui, function(d)
		return d:IsA("TextButton") and string.find(label(d), "Bumper Blast", 1, true) ~= nil and d:FindFirstAncestor("Minis") ~= nil
	end)
	assert(m, "no Bumper Blast button on the front page")
	signalFor(m, "Activated"):Fire()
end)
print(`kart blast: coins {blastBefore} -> {towns:snapshot(1).save.coins}`)
assert(cardButton("Again"), "no ↻ Again on the Bumper Blast podium")
closeRace()
-- A custom race's card: pick the canyon, reversed, with max boost, and start it.
topUp()
hud.ctx.close()
hud.openPanel("race", "hub")
local customMini = find(hud.gui, function(d)
	return d:IsA("TextButton") and string.find(label(d), "Custom race", 1, true) ~= nil and d:FindFirstAncestor("Minis") ~= nil
end)
assert(customMini, "no Custom race button on the front page")
signalFor(customMini, "Activated"):Fire()
if SHOTS then
	shot("page-custom", nil)
end
renderSteps = {}
calls = {}
for _, pick in { "Canyon", "Reversed", "Max boost" } do
	local customCard = hud.gui:FindFirstChild("CustomRace", true)
	assert(customCard, "no custom race card")
	local b = find(customCard, function(d)
		if not d:IsA("TextButton") then
			return false
		end
		for _, l in d:GetChildren() do
			if l:IsA("TextLabel") and string.find(l.Text, pick, 1, true) then
				return true
			end
		end
		return false
	end)
	assert(b, `no {pick} on the custom race card`)
	signalFor(b, "Activated"):Fire()
end
signalFor(hud.gui:FindFirstChild("CustomRace", true):FindFirstChild("Race", true), "Activated"):Fire()
local customScreen = raceScreen()
local customTitle = customScreen and customScreen:FindFirstChild("Title")
print(`kart custom: {customTitle and customTitle.Text or "no race"} ({table.concat(calls, ", ")})`)
assert(customTitle and customTitle.Text == "🛠️ Custom · 🏜️ Canyon ↺", "the custom race didn't start as picked")
signalFor(customScreen:FindFirstChild("Leave"):FindFirstChild("Face"), "Activated"):Fire()
Emu.resumeWaits()
assert(not raceScreen(), "the custom race didn't close")
-- A kart party: the Live page, start a party, Rosa joins it (from her own game), Go, and the
-- race against her (her kart handed to an AI driver once she goes quiet) to the server's places.
do
	closeRace()
	hud.ctx.close()
	hud.openPanel("race", "hub")
	local liveMini = find(hud.gui, function(d)
		return d:IsA("TextButton") and label(d) == "Live" and d:FindFirstAncestor("Minis") ~= nil
	end)
	assert(liveMini, "no Live button on the front page")
	handlerErrors = {}
	signalFor(liveMini, "Activated"):Fire()
	Emu.resumeWaits()
	local open = find(hud.gui, function(d)
		return d:IsA("TextButton") and string.find(label(d), "Start a kart party", 1, true) ~= nil
	end)
	assert(open, "no Start a kart party on the Live page")
	signalFor(open, "Activated"):Fire()
	Emu.resumeWaits()
	towns:_with(2, function(s)
		s.fuel = math.max(s.fuel, 10)
	end)
	assert(parties:join(2, parties:list(2).open[1].id), "Rosa couldn't join")
	Emu.resumeWaits()
	if SHOTS then
		shot("page-live", nil)
	end
	local roster = {}
	for _, d in (hud.gui:FindFirstChild("Live", true) or Instance.new("Folder")):GetDescendants() do
		if d:IsA("TextLabel") and d.Name ~= "Face" and d.Text ~= "" then
			table.insert(roster, d.Text)
		end
	end
	print(`live page: {table.concat(roster, " | ")} {table.concat(handlerErrors, "; ")}`)
	local before = towns:snapshot(1).save.coins
	runKart("kart-party", { [40] = true }, function()
		-- runKart closed the menu: back to the Live page, where the party still is.
		hud.openPanel("race", "live")
		Emu.resumeWaits()
		local go = find(hud.gui, function(d)
			return d:IsA("TextButton") and string.find(label(d), "Go ×2", 1, true) ~= nil
		end)
		assert(go, "no 🏁 Go ×2 for the host")
		signalFor(go, "Activated"):Fire()
		Emu.resumeWaits()
		-- Rosa's game has the circuit drawn too: the lights go.
		parties:ready(2)
	end)
	-- Rosa never crosses the line: a minute after ours the places are settled.
	raceClock += 61
	for _, tm in table.clone(partyTimers) do
		if tm.at <= raceClock and not tm.ran then
			tm.ran = true
			tm.fn()
		end
	end
	for _ = 1, 12 do
		raceClock += 1 / 20
		if renderSteps.KartRun then
			renderSteps.KartRun(1 / 20)
		end
		Emu.resumeWaits()
	end
	local podium = find(raceScreen(), function(d)
		return d.Name == "Podium"
	end)
	print(`kart party: {cardText(podium)}; coins {before} -> {towns:snapshot(1).save.coins}`)
	assert(find(podium, function(d)
		return d.Name == "Verdict"
	end), "no verdict on the kart party podium")
	assert(towns:snapshot(1).save.coins > before, "the kart party paid nothing")
	if SHOTS then
		shot("kart-party-verdict", game.Workspace:FindFirstChild("KartCircuit"))
	end
	closeRace()
end
-- The Daily Spin: Spin, run the wheel round until it lands, and see the prize was paid once.
do
	closeRace()
	hud.ctx.close()
	unspun()
	local before = towns:snapshot(1).save
	hud.openPanel("daily")
	wheelOpened()
	local spinGui = player.PlayerGui:FindFirstChild("DailySpin")
	assert(spinGui, "the Daily Spin didn't take the screen")
	assert(not hud.gui.Enabled, "the HUD stayed up over the Daily Spin")
	local shopWorld = game.Workspace:FindFirstChild("DailySpinShop")
	assert(shopWorld, "no tyre shop built")
	if SHOTS then
		shot("wheel", shopWorld)
	end
	local spinBtn = find(spinGui, function(d)
		return d:IsA("TextButton") and d.Name == "Face" and d.Parent and d.Parent.Name == "Spin"
	end)
	assert(spinBtn, "no Spin button")
	calls = {}
	handlerErrors = {}
	signalFor(spinBtn, "Activated"):Fire()
	local frames = 0
	while renderSteps.DailySpin and frames < 60 * 12 do
		frames += 1
		renderSteps.DailySpin(1 / 60)
		if frames == 40 and SHOTS then
			shot("wheel-spin", shopWorld)
		end
	end
	local prize = find(spinGui, function(d)
		return d.Name == "PrizeLine"
	end)
	local words = {}
	if prize then
		for _, d in prize:GetDescendants() do
			if d:IsA("TextLabel") and d.Name ~= "Face" then
				table.insert(words, d.Text)
			end
		end
	end
	local after = towns:snapshot(1).save
	print(`daily spin: {frames} frames, wheel at {math.floor(shopWorld:GetAttribute("Angle") or -1)}°, prize "{table.concat(words, " ")}"; coins {before.coins} -> {after.coins}, gems {before.bucks} -> {after.bucks}, spun {after.lastDaily}`)
	print(`daily spin calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)
	if SHOTS then
		-- A moment after it lands, with the confetti in the air.
		for _ = 1, 30 do
			renderSteps.DailySpinScene(1 / 60)
		end
		shot("wheel-won", shopWorld)
	end
	local again = Remote.spin()
	print(`daily spin again the same day: {if again then "SPUN AGAIN" else "refused"}`)
	handlerErrors = {}
	closeWheel()
	if #handlerErrors > 0 then
		print(`daily spin close: {table.concat(handlerErrors, "; ")}`)
	end
	assert(not game.Workspace:FindFirstChild("DailySpinShop") and not player.PlayerGui:FindFirstChild("DailySpin"), "the tyre shop stayed after closing")
	assert(hud.gui.Enabled, "the HUD didn't come back after the Daily Spin")
	if SHOTS then
		-- On a phone: the dock under the wheel, as the web's.
		local cam = game.Workspace.CurrentCamera
		cam.ViewportSize = roblox.Vector2.new(844, 390)
		unspun()
		hud.openPanel("daily")
		wheelOpened()
		shot("wheel-phone", game.Workspace:FindFirstChild("DailySpinShop"), 844, 390)
		closeWheel()
		cam.ViewportSize = roblox.Vector2.new(1280, 800)
	end
end

-- The Star Pass: 45 stars, two tiers already claimed. The street keeps its chips through the
-- town clock's ticks; a chip moves the camera along the road; Collect takes the other three; then
-- Earn goes to Goals.
do
	hud.ctx.close()
	local data = emu.require(RS.Shared.Game.data)
	towns:_with(1, function()
		store.useGame.setState({ season = { n = data.seasonNumber(NOW), stars = 45, claimed = { 0, 1 } } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	-- (A race's prize card left over from earlier would sit on top of the pictures.)
	for _ = 1, 10 do
		local p = hud.root:FindFirstChild("Popup")
		local b = p and find(p, function(d)
			return d:IsA("TextButton") and d.Name == "Face" and (label(d) == "Nice!" or label(d) == "Continue" or label(d) == "Awesome!" or label(d) == "Later")
		end)
		if not b then
			break
		end
		signalFor(b, "Activated"):Fire()
		Emu.resumeWaits()
	end
	hud.openPanel("season")
	local step = renderSteps.StarPass
	assert(step, "the Star Pass isn't stepping its street")
	for _ = 1, 30 do
		step(1 / 30)
	end
	local street = find(hud.gui, function(d)
		return d:IsA("ViewportFrame") and d.Name == "Street"
	end)
	local streetCam = street and street:FindFirstChildOfClass("Camera")
	assert(streetCam, "no street on the Star Pass")
	local signs = 0
	for _, d in hud.gui:GetDescendants() do
		if d.Name:match("^Sign%d+$") and d.Visible then
			signs += 1
		end
	end
	assert(signs >= 3, `only {signs} arch signs in view`)
	local root = hud.gui:FindFirstChild("Root")
	if SHOTS then
		shot("season", nil)
		root.Size = roblox.UDim2.fromOffset(1535, 709)
		step(1)
		shot("season-phone", nil, 1535, 709)
		root.Size = roblox.UDim2.fromOffset(1280, 800)
	end
	-- A tick of the town clock with nothing new for the Star Pass leaves its chips be.
	local chip = hud.gui:FindFirstChild("Tier12", true)
	assert(chip, "no tier 12 chip")
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	assert(hud.gui:FindFirstChild("Tier12", true) == chip, "a clock tick rebuilt the Star Pass chips")
	-- Tapping tier 12's chip looks further up the road.
	local before = streetCam.CFrame.Position.Z
	local face = find(chip, function(d)
		return d:IsA("TextButton")
	end) or chip
	signalFor(face, "Activated"):Fire()
	for _ = 1, 60 do
		step(1 / 30)
	end
	local after = streetCam.CFrame.Position.Z
	assert(after > before + 100, `tier 12's chip didn't move along the road ({before} -> {after})`)
	if SHOTS then
		shot("season-tier12", nil)
	end
	local collect = find(hud.gui, function(d)
		return d:IsA("TextButton") and string.find(label(d), "Collect", 1, true) ~= nil
	end)
	assert(collect, "no Collect on the Star Pass")
	local coins = towns:snapshot(1).save.coins
	calls = {}
	signalFor(collect, "Activated"):Fire()
	local season = towns:snapshot(1).save.season
	print(`star pass: claimed {table.concat(season.claimed, ",")}, coins {coins} -> {towns:snapshot(1).save.coins}; calls {table.concat(calls, ", ")}`)
	assert(#season.claimed == 5, "Collect didn't take every tier reached")
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	step(1 / 30)
	if SHOTS then
		shot("season-collected", nil)
	end
	local earn = find(hud.gui, function(d)
		return d:IsA("TextButton") and string.find(label(d), "Earn", 1, true) ~= nil
	end)
	assert(earn, "no Earn button once everything's collected")
	signalFor(earn, "Activated"):Fire()
	assert(find(hud.gui, function(d)
		return d:IsA("TextLabel") and d.Name == "Title" and d.Text == "Goals"
	end), "Earn didn't open Goals")
	-- (Lune's Destroy doesn't fire Destroying; the street's own step notices the panel's gone.)
	if renderSteps.StarPass then
		renderSteps.StarPass(1 / 30)
	end
	assert(renderSteps.StarPass == nil, "the Star Pass kept stepping after it closed")
	assert(hud.gui:FindFirstChild("Street", true) == nil, "the Star Pass's street stayed")
	print("star pass: chips move the road, collect, earn opens goals")
	hud.ctx.close()
end

-- Daily Deals: buy today's supplies deal.
do
	hud.ctx.close()
	towns:_with(1, function()
		store.useGame.setState({ coins = 1000000, bucks = 1000, fuel = 0, deals = { day = "2000-01-01", used = {} } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.openPanel("deals")
	if SHOTS then
		shot("deals", nil)
	end
	local buy = find(hud.gui, function(d)
		return d:IsA("TextButton") and label(d) == "Buy"
	end)
	local before = towns:snapshot(1).save
	calls = {}
	if buy then
		signalFor(buy, "Activated"):Fire()
	end
	local after = towns:snapshot(1).save
	print(`deals: bought {if buy then "the supplies deal" else "nothing (no Buy)"}; coins {before.coins} -> {after.coins}, gems {before.bucks} -> {after.bucks}, parts {before.parts} -> {after.parts}, fuel {before.fuel} -> {after.fuel}, used {after.deals and table.concat(after.deals.used, ",") or "-"}; calls {table.concat(calls, ", ")}`)
	if SHOTS then
		shot("deals-bought", nil)
	end
	hud.ctx.close()
end

-- Pop-ups (client/Popups): the level-up splash and the prize cards a race leaves, one at a time;
-- the end-of-tutorial goal screen; the welcome back; coins flying to the counters.
do
	closeRace()
	hud.ctx.close()
	Emu.resumeWaits()
	local function popup()
		return hud.root:FindFirstChild("Popup")
	end
	local CLOSE = { Continue = true, ["Nice!"] = true, ["Awesome!"] = true, Later = true, ["Let's go!"] = true, ["Keep going!"] = true }
	local function closer(p)
		return find(p, function(d)
			return d:IsA("TextButton") and d.Name == "Face" and CLOSE[label(d)] == true
		end)
	end
	-- Anything a race earlier left showing: close it the way a player would.
	local leftover = 0
	while popup() and leftover < 10 do
		leftover += 1
		local b = closer(popup())
		assert(b, "a pop-up with no close button")
		signalFor(b, "Activated"):Fire()
		Emu.resumeWaits()
	end
	print(`pop-ups left from races: {leftover}`)
	calls = {}
	handlerErrors = {}
	towns:_with(1, function(s)
		local cars = s.cars
		store.useGame.setState({
			levelUp = { from = s.level, to = s.level + 1, coins = 1200, bucks = 5 },
			campaignPrize = { chapter = "c1", coins = 1000, bucks = 15, trophies = 3, cleared = true, perfect = true },
			paintPrize = "sunny",
			tunerPrize = "downforce",
			masteryPrize = { model = cars[1].model, tier = 1, classes = {}, galaxy = false, first = { "compact" }, xp = 250 },
			cupPrize = "compact-1",
			tourPrize = { leg = 4, coins = 1700 },
			eventPrize = { id = emu.require(G.events).eventFor().id, skin = emu.require(G.events).eventFor().skin, coins = 2300 },
		})
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	local seen = {}
	for _ = 1, 10 do
		local p = popup()
		if not p then
			break
		end
		local title = find(p, function(d)
			return d:IsA("TextLabel") and d.Name == "Title"
		end)
		local name = title and title.Text or "?"
		table.insert(seen, name)
		shot(`popup-{#seen}`, nil)
		-- Every button on it must be wired; then close it.
		for _, d in p:GetDescendants() do
			if d:IsA("GuiButton") and d.Name == "Face" and d.Parent and d.Parent.Name ~= "Item" and d.Parent.Name ~= "Card" and d.Parent.Name ~= "Prize" and next(signalFor(d, "Activated").fns) == nil then
				print(`popup {name}: not wired: {label(d)}`)
				bad += 1
			end
		end
		local b = closer(p)
		assert(b, `pop-up {name} has no close button`)
		signalFor(b, "Activated"):Fire()
		Emu.resumeWaits()
	end
	print(`pop-ups in turn: {table.concat(seen, " | ")}`)
	assert(#seen == 8, `expected 8 pop-ups, saw {#seen}`)
	assert(#handlerErrors == 0, table.concat(handlerErrors, "; "))
	local s = store.useGame.getState()
	assert(s.levelUp == nil and s.paintPrize == nil and s.cupPrize == nil, "a pop-up's news wasn't cleared")

	-- The purchase splash: a gem pack and a car pack just paid.
	towns:_with(1, function(s)
		store.useGame.setState({ bought = { { seq = 1, pack = "bag", bucks = 1200, coins = 5000, parts = 40 }, { seq = 2, pack = "bag", bucks = 6500, coins = 0, parts = 0, car = s.cars[1].model } } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	do
		local p = popup()
		assert(p, "no purchase splash")
		local title = find(p, function(d)
			return d:IsA("TextLabel") and d.Name == "Title"
		end)
		assert(title and title.Text == "Purchase successful!", `the purchase splash says {title and title.Text}`)
		shot("popup-bought", nil)
		local b = closer(p)
		assert(b, "the purchase splash has no Continue")
		signalFor(b, "Activated"):Fire()
		Emu.resumeWaits()
		assert(popup() == nil, "the purchase splash stayed")
		assert(#store.useGame.getState().bought == 0, "the purchase splash's news wasn't cleared")
		print("purchase splash: shown and closed")
	end

	-- A pop-up waits while the race screen hides the HUD.
	local hudGui = hud.gui
	hudGui.Enabled = false
	towns:_with(1, function()
		store.useGame.setState({ cupPrize = "compact-1" })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	local during = popup() ~= nil
	hudGui.Enabled = true
	Emu.resumeWaits()
	print(`cup prize during a race: {during}; after: {popup() ~= nil}`)
	assert(not during and popup(), "the pop-up didn't wait for the race screen")
	local open = find(popup(), function(d)
		return d:IsA("TextButton") and label(d) == "Open it"
	end)
	signalFor(open, "Activated"):Fire()
	Emu.resumeWaits()
	print(`open it: crates menu {hud.root:FindFirstChild("Panel") ~= nil}`)
	hud.ctx.close()

	-- The goal screen after the tutorial's last step; Let's go! finishes the tutorial.
	calls = {}
	-- (Today's spin taken: the tutorial's end would open it, and the welcome back below would wait.)
	towns:_with(1, function()
		store.useGame.setState({ tutorial = 9, lastDaily = store.today() })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	assert(popup(), "no goal screen after the tutorial")
	shot("popup-goal", nil)
	local go = closer(popup())
	signalFor(go, "Activated"):Fire()
	Emu.resumeWaits()
	print(`goal screen: {table.concat(calls, ", ")}; tutorial now {towns:snapshot(1).save.tutorial}`)
	assert(towns:snapshot(1).save.tutorial == 99, "Let's go! didn't finish the tutorial")

	-- The Grand Prix champion's mystery box (Prizes gpPrize): wobbling, then opened to the car.
	towns:_with(1, function()
		store.useGame.setState({ gpPrize = { series = "rookie", model = "miata", color = "#e53935" } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	local box = find(hud.gui, function(d)
		return d.Name == "Mystery"
	end)
	assert(box, "no mystery box for the Grand Prix champion")
	if SHOTS then
		shot("gp-prize-box", nil)
	end
	signalFor(box, "Activated"):Fire()
	Emu.resumeWaits()
	local card = hud.gui:FindFirstChild("Prize", true)
	print(`gp prize: {cardText(card)}`)
	if SHOTS then
		shot("gp-prize-car", nil)
	end
	local nice = find(hud.gui, function(d)
		return d:IsA("TextButton") and label(d) == "Nice!"
	end)
	assert(nice, "no Nice! on the Grand Prix prize")
	signalFor(nice, "Activated"):Fire()
	Emu.resumeWaits()
	assert(store.useGame.getState().gpPrize == nil, "the Grand Prix prize didn't close")

	-- Welcome back: three hours away with jobs finished.
	calls = {}
	local gameData = emu.require(G.data)
	towns:_with(1, function(st)
		local b = {}
		for i, x in st.buildings do
			b[i] = table.clone(x)
			local d = gameData.buildingDef(x.def)
			if d.jobSeconds and d.kind ~= "obstacle" then
				b[i].jobEndsAt = NOW - 60000
			end
		end
		store.useGame.setState({ buildings = b })
	end)
	player:SetAttribute("AwayMs", 3 * 3600000 + 20 * 60000)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	Emu.resumeWaits()
	-- The pop-up queue's half-second heartbeat (Kit.start), in case it waited on a menu dropping away.
	emu.require(client.Popups.Kit).pump()
	Emu.resumeWaits()
	-- (A menu closed just before may still be dropping away under the same name: look in each.)
	local panel, away = nil, nil
	for _, c in hud.root:GetChildren() do
		local a = c.Name == "Panel" and find(c, function(d)
			return d:IsA("TextLabel") and string.find(d.Text, "Away", 1, true) ~= nil
		end)
		if a then
			panel, away = c, a
		end
	end
	if not away then
		local kids = {}
		for _, c in hud.root:GetChildren() do
			table.insert(kids, c.Name)
		end
		local KitM = emu.require(client.Popups.Kit)
		local st = store.useGame.getState()
		local WP = emu.require(client.Panels.Welcome)
		print(`  [diag] root [{table.concat(kids, " ")}] showing {tostring(KitM.showing())} menuOpen {KitM.menuOpen(hud.ctx)} levelUp {tostring(st.levelUp)} editing {emu.require(client.Placement).active()} visiting {tostring(st.visiting)} rusty {store.hasRusty(st)} news {WP.hasNews(st, NOW)} panel {tostring(hud.ctx.panel())}`)
	end
	print(`welcome: {away and away.Text or "not shown"}`)
	assert(away, "no welcome back")
	shot("panel-welcome", nil)
	local before = towns:snapshot(1).save.coins
	local collect = find(panel, function(d)
		return d:IsA("TextButton") and label(d) == "Collect all"
	end)
	local closing = signalFor(panel, "Destroying")
	signalFor(collect, "Activated"):Fire()
	-- The "+N" label shows at once; the coins pop out a moment later.
	Emu.resumeWaits()
	local fly = hud.root:FindFirstChild("Fly")
	-- Lune won't let the Destroy hook above replace the built-in one, so the menu closing never
	-- fired Destroying: fire it as Roblox would, or the pop-up queue waits on the welcome forever.
	closing:Fire()
	print(`welcome collect: {table.concat(calls, ", ")}; coins {before} -> {towns:snapshot(1).save.coins}; flying {fly and #fly:GetChildren() or 0} {table.concat(handlerErrors, "; ")}`)
	assert(towns:snapshot(1).save.coins > before, "Collect all paid nothing")
	assert(fly and #fly:GetChildren() > 0, "no coins flew to the counter")
	shot("fly", nil)
	for _ = 1, 4 do
		Emu.resumeWaits()
	end
	-- Closing the welcome opens the Daily Spin when today's isn't spun (SHOTS' phone wheel picture
	-- unspins it). Lune's Destroy fires no Destroying, so take the shop down as Roblox would, or its
	-- room light (DayNight.raceFog) stays on and the town's weather stands down.
	if player.PlayerGui:FindFirstChild("DailySpin") then
		wheelOpened()
	end
	closeWheel()
	print(`pop-ups: {bad} problems`)
end

-- The tutorial, walked as a brand new player would: a fresh town at step 0, pressing whatever the
-- pointing hand points at (client/Popups/Tutorial), step by step to the goal screen and done (99).
-- Where the hand points is checked against the real layout of the button it names, at the web's
-- 1280 x 800 and on a phone (844 x 390 scales the HUD by 0.55, so it lays out at 1535 x 709).
do
	closeRace()
	hud.ctx.close()
	Emu.resumeWaits()
	local before = bad
	local Tut = emu.require(client.Popups.Tutorial)
	local Rules = emu.require(RS.Shared.Tutorial)
	local Placement = emu.require(client.Placement)
	local TownView = emu.require(SSS.Server.TownView)
	local TownCamera = emu.require(client.TownCamera)
	local UIS = game:GetService("UserInputService")
	local cam = game.Workspace.CurrentCamera
	local V2, V3 = roblox.Vector2, roblox.Vector3

	-- The camera's sums, as Roblox does them: a vertical field of view over the viewport.
	local function toView(p)
		local cf = cam.CFrame
		local d = p - cf.Position
		local W, H = cam.ViewportSize.X, cam.ViewportSize.Y
		local f = 1 / math.tan(math.rad(cam.FieldOfView) / 2)
		local depth = d:Dot(cf.LookVector)
		if depth <= 0 then
			return V3.new(0, 0, depth), false
		end
		local nx, ny = d:Dot(cf.RightVector) * f / (depth * W / H), d:Dot(cf.UpVector) * f / depth
		local x, y = (nx + 1) / 2 * W, (1 - ny) / 2 * H
		return V3.new(x, y, depth), x >= 0 and y >= 0 and x <= W and y <= H
	end
	roblox.implementMethod("Camera", "WorldToViewportPoint", function(_, p)
		return toView(p)
	end)
	roblox.implementMethod("Camera", "ScreenPointToRay", function(_, x, y)
		local W, H = cam.ViewportSize.X, cam.ViewportSize.Y
		local t = math.tan(math.rad(cam.FieldOfView) / 2)
		local nx, ny = x / W * 2 - 1, 1 - y / H * 2
		local cf = cam.CFrame
		local dir = (cf.RightVector * (nx * t * W / H) + cf.UpVector * (ny * t) + cf.LookVector).Unit
		return roblox.Ray.new(cam.CFrame.Position, dir)
	end)
	-- The town view's camera (TownCamera: from (75, 80, 75) at 30°), on the spot it looks at.
	local DIR = V3.new(75, 80, 75).Unit
	local function look(at)
		local zoom = math.clamp(math.sqrt(cam.ViewportSize.X * cam.ViewportSize.Y) / 24, 18, 38)
		local tall = cam.ViewportSize.Y / zoom * 10
		local dist = tall / 2 / math.tan(math.rad(30 / 2))
		local p = V3.new(at.X, 0, at.Z)
		cam.CameraType = roblox.Enum.CameraType.Scriptable
		cam.FieldOfView = 30
		-- (Built from its axes: Lune's CFrame.lookAt turns the wrong way.)
		local back = DIR
		local right = V3.new(0, 1, 0):Cross(back).Unit
		cam.CFrame = roblox.CFrame.fromMatrix(p + DIR * dist, right, back:Cross(right), back)
	end
	local lookAt = TownCamera.lookAt
	local glides = 0
	TownCamera.lookAt = function(p)
		lookAt(p)
		glides += 1
		look(p)
	end
	-- Where each object lands, from the emulator's own layout of the screen.
	local rects = {}
	Gui.onNode = function(g, n)
		rects[idOf(g)] = n
	end
	local function relayout()
		table.clear(rects)
		local race = player.PlayerGui:FindFirstChild("Race")
		-- Lean: Tut.rectOf below finds board rects itself, and laying out every badge and hidden
		-- frame twice a frame made the race after "camp-go" crawl in a full run.
		Gui.dump(hud.gui, cam.ViewportSize.X, cam.ViewportSize.Y, true)
		if race then
			Gui.dump(race, cam.ViewportSize.X, cam.ViewportSize.Y, true)
		end
		local rescue = player.PlayerGui:FindFirstChild("RescueSearch")
		if rescue then
			Gui.dump(rescue, cam.ViewportSize.X, cam.ViewportSize.Y)
		end
	end
	local rectOf = Tut.rectOf
	Tut.rectOf = function(g, layer)
		if g:FindFirstAncestorOfClass("BillboardGui") then
			return rectOf(g, layer)
		end
		local n = rects[idOf(g)]
		if not n then
			return 0, 0, 0, 0
		end
		return n.abs[1], n.abs[2], n.abs[3], n.abs[4]
	end

	-- A fresh town, drawn by the server's TownView so the bubbles have buildings to sit on.
	towns:close(1)
	towns:open(1, nil)
	Emu.resumeWaits()
	local townsFolder = Instance.new("Folder")
	townsFolder.Name = "Towns"
	townsFolder.Parent = game.Workspace
	local view = TownView.new(townsFolder, "Player1", V3.new(0, 0, 0), 1, function(uid)
		towns:run(1, "tapBuilding", uid)
	end)
	local function draw()
		local save = towns:save(1)
		for _, c in save.cars do
			c.mods, c.panels = nil, nil
		end
		view:render(save)
	end
	draw()
	look(V3.new(0, 0, 0))
	-- The badge over Rusty's, as the client's entry point starts it.
	emu.require(client.RescueBadge).start(player.PlayerGui)
	-- A pop-up over everything (a level-up): the hand rests, and the player taps its button.
	local CLOSE = { Continue = true, ["Nice!"] = true, ["Awesome!"] = true, Later = true, ["Keep going!"] = true }
	local function closePopup()
		local p = hud.root:FindFirstChild("Popup")
		local b = p and find(p, function(d)
			return d:IsA("TextButton") and d.Name == "Face" and CLOSE[label(d)] == true
		end)
		if b then
			print(`  (no pointer over the pop-up: tap {label(b)})`)
			signalFor(b, "Activated"):Fire()
			Emu.resumeWaits()
			return true
		end
		return false
	end
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	local s0 = store.useGame.getState()
	print(`tutorial: a new town starts at step {s0.tutorial}`)
	assert(s0.tutorial == 0, "a new town doesn't start the tutorial")

	-- The HUD a new player sees: coins and the level, nothing else yet.
	local function hudShows()
		local out = {}
		local root = hud.root
		for _, name in { "Fuel", "MyCars", "Trophies", "SHOP", "CARS", "EDIT", "Race", "Dock", "Walk", "GoalTracker" } do
			local g = root:FindFirstChild(name, true)
			if g and g.Visible then
				table.insert(out, name)
			end
		end
		return table.concat(out, ",")
	end
	Emu.resumeWaits()
	print(`tutorial: HUD at step 0 shows [{hudShows()}]`)
	assert(hudShows() == "", "the HUD shows buttons before the tutorial unlocks them")

	local function layer()
		local race = player.PlayerGui:FindFirstChild("Race")
		local rescue = player.PlayerGui:FindFirstChild("RescueSearch")
		return (race and race:FindFirstChild("RaceScreen")) or (rescue and rescue:FindFirstChild("SearchScreen")) or hud.root
	end
	local function cardLine()
		local c = hud.root:FindFirstChild("Tutorial")
		local l = c and c:FindFirstChild("Line", true)
		return l and l.Text or "(no card)"
	end
	-- The hand must sit on its target: the ring hugs the box of the very button it names, and the
	-- finger's tip is inside the screen.
	local function checkHand(tag)
		relayout()
		Tut.frame()
		local s = store.useGame.getState()
		local box, el = Tut.box(s, layer())
		local ringG = layer():FindFirstChild("TutRing")
		local handG = layer():FindFirstChild("TutHand")
		if not box then
			return "resting"
		end
		local lw, lh = layer().Size.X.Offset, layer().Size.Y.Offset
		local cx, cy = box.x + box.w / 2, box.y + box.h / 2
		local r = ringG and ringG.Visible and ringG.Position
		local okRing = r and r.X.Offset <= cx and r.Y.Offset <= cy and r.X.Offset + ringG.Size.X.Offset >= cx and r.Y.Offset + ringG.Size.Y.Offset >= cy
		local hx, hy = handG.Position.X.Offset, handG.Position.Y.Offset
		local okHand = handG.Visible and hx >= 0 and hx <= lw and hy >= 0 and hy <= lh and math.abs(hx - cx) < 2
		local okIn = cx >= 0 and cy >= 0 and cx <= lw and cy <= lh
		local what = if el then tostring(el:GetAttribute("Tut")) else "lot"
		if not (okRing and okHand and okIn) then
			bad += 1
			print(`[tutorial {tag}] the hand is off its target {what}: box {math.floor(box.x)},{math.floor(box.y)} {math.floor(box.w)}x{math.floor(box.h)}, hand {hx},{hy}, screen {lw}x{lh}`)
		end
		return `{what} at {math.floor(cx)},{math.floor(cy)}`
	end
	-- The same on a phone: the HUD's 0.55 scale lays it out at 1535 x 709.
	local function onPhone(tag)
		local root = hud.root
		root.Size = roblox.UDim2.fromOffset(1535, 709)
		cam.ViewportSize = V2.new(1535, 709)
		Tut.refresh()
		local where = checkHand(`{tag} phone`)
		shot(`tutorial-{tag}-phone`, view.folder, 1535, 709)
		root.Size = roblox.UDim2.fromOffset(1280, 800)
		cam.ViewportSize = V2.new(1280, 800)
		Tut.refresh()
		return where
	end

	local SHOT_AT = { [0] = "welcome", [1] = "pizza", [3] = "shop", [6] = "paint", [7] = "gas", [8] = "race" }
	local shotTags = {}
	local function picture(tag, phone)
		if shotTags[tag] then
			return
		end
		shotTags[tag] = true
		shot(`tutorial-{tag}`, view.folder)
		if phone then
			print(`  phone: {onPhone(tag)}`)
		end
	end

	local touch = { UserInputType = roblox.Enum.UserInputType.Touch, KeyCode = roblox.Enum.KeyCode.Unknown }
	local holding = false
	local lastStep = -1
	local lastLine = ""
	local pressed = {}
	local waited = 0
	local raceFrames, launches, shiftTaps = 0, 0, 0
	-- A race frame lays the screen out after its step, so the next turn of the loop needn't again.
	local laidOut = false
	for i = 1, 3000 do
		if not laidOut then
			relayout()
		end
		laidOut = false
		Tut.refresh()
		local s = store.useGame.getState()
		if s.tutorial ~= lastStep then
			lastStep = s.tutorial
			if s.tutorial >= Rules.STEPS then
				break
			end
			Tut.frame()
			print(`tutorial step {s.tutorial}: HUD [{hudShows()}]`)
		end
		-- The card's line, each time it changes (it waits behind menus).
		local line = cardLine()
		if line ~= lastLine and line ~= "(no card)" then
			lastLine = line
			print(`  card: "{line}"`)
			if SHOT_AT[s.tutorial] then
				picture(SHOT_AT[s.tutorial], s.tutorial == 1 or s.tutorial == 6)
			end
		end
		local screen = raceScreen()
		if screen then
			-- The race: the hand comes and goes with the pedal and the SHIFT light.
			raceClock += 1 / 60
			raceFrames += 1
			local step = renderSteps.DragStrip
			if step then
				step(1 / 60)
			end
			Emu.resumeWaits()
			relayout()
			laidOut = true
			local b = Tut.press(s, layer())
			local what = b and b:GetAttribute("Tut")
			if what == "launch" and not holding then
				holding = true
				picture("race-launch", false)
				table.insert(pressed, "launch")
				launches += 1
				signalFor(b, "InputBegan"):Fire(touch)
			elseif what ~= "launch" and holding then
				holding = false
				signalFor(UIS, "InputEnded"):Fire(touch)
			end
			if what == "shift-now" then
				table.insert(pressed, "shift")
				shiftTaps += 1
				signalFor(b, "InputBegan"):Fire(touch)
				signalFor(UIS, "InputEnded"):Fire(touch)
			end
			if find(screen, function(d) return d.Name == "Result" end) then
				-- The result card: nothing to point at (as on the web); collect and go back.
				if holding then
					holding = false
					signalFor(UIS, "InputEnded"):Fire(touch)
				end
				picture("race-result", false)
				local res = find(screen, function(d) return d.Name == "Result" end)
				local words = {}
				for _, d in res:GetDescendants() do
					if d:IsA("TextLabel") and d.Text ~= "" and d.Name ~= "Face" and #words < 6 then
						table.insert(words, d.Text)
					end
				end
				print(`  race: {raceFrames} frames, pedal held {launches}x, SHIFT tapped {shiftTaps}x where the hand said; card: {table.concat(words, " | ")}`)
				print("  (no pointer on the result card: collect and go back)")
				closeRace()
				draw()
				laidOut = false
			end
			continue
		end
		Tut.frame()
		local b, pt = Tut.press(s, layer())
		if b or pt then
			local what = if b then tostring(b:GetAttribute("Tut")) else "lot"
			local where = checkHand(`step {s.tutorial}`)
			if what == "start-here" then
				picture("start-here", false)
			elseif what == "lot" then
				picture("lot", true)
			elseif what == "rs-auto" then
				picture("search", false)
			elseif what == "junk-go" then
				picture("restore", false)
			elseif what == "camp-go" then
				picture("race-menu", true)
			end
			if #pressed == 0 or pressed[#pressed] ~= what then
				print(`  press {where}`)
			end
			table.insert(pressed, what)
			calls = {}
			handlerErrors = {}
			if b then
				signalFor(b, "MouseButton1Down"):Fire()
				signalFor(b, "MouseButton1Up"):Fire()
				signalFor(b, "Activated"):Fire()
			else
				local input = { UserInputType = roblox.Enum.UserInputType.MouseButton1, KeyCode = roblox.Enum.KeyCode.Unknown, Position = V3.new(pt.X, pt.Y, 0) }
				signalFor(UIS, "InputBegan"):Fire(input, false)
				signalFor(UIS, "InputEnded"):Fire(input)
			end
			for _, c in calls do
				if c:sub(1, 2) ~= "ok" then
					bad += 1
					print(`[tutorial step {s.tutorial}] pressing {what}: {c}`)
				end
			end
			for _, e in handlerErrors do
				bad += 1
				print(`[tutorial step {s.tutorial}] pressing {what}: ERROR {e}`)
			end
			Emu.resumeWaits()
			if what == "junk-go" and hud.ctx.panel() == "need" then
				-- The find costs more than the town has (some finds do, on the web too): a player
				-- earns it with pizza jobs. The walk hands over what those jobs would pay.
				local short = 0
				towns:_with(1, function(st)
					local g = store.useGame.getState()
					short = 3000
					store.useGame.setState({ coins = g.coins + short })
				end)
				print(`  (the restore costs more than the town has: +{short} coins, as pizza jobs would pay)`)
				hud.ctx.close()
				signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
				Emu.resumeWaits()
			end
			draw()
			Emu.resumeWaits()
			waited = 0
		elseif closePopup() then
			waited = 0
		else
			-- Nothing to tap: a job running, Rusty searching. Time passes.
			waited += 1
			NOW += 5000
			towns:tick(1)
			signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
			Emu.resumeWaits()
			-- Rusty's lot: the truck drives, digs and tows a frame at a time.
			for f = 1, 30 do
				local lotStep = renderSteps.RescueLot
				if not lotStep then
					break
				end
				lotStep(1 / 30)
				if f % 5 == 0 then
					signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
				end
				Emu.resumeWaits()
			end
			if waited > 200 then
				bad += 1
				print(`[tutorial] stuck at step {s.tutorial}: nothing to press for 1000s ({cardLine()}, menu {tostring(hud.ctx.panel())})`)
				local tagged = {}
				for _, d in player.PlayerGui:GetDescendants() do
					if d:GetAttribute("Tut") then
						local n = rects[idOf(d)]
						table.insert(tagged, `{d:GetAttribute("Tut")}@{if n then `{math.floor(n.abs[1])},{math.floor(n.abs[2])}` else "?"}`)
					end
				end
				print(`  marked buttons: {table.concat(tagged, " ")}; the hand wants {tostring(Tut.target(s))}`)
				break
			end
		end
	end
	local s = store.useGame.getState()
	print(`tutorial: reached step {s.tutorial} after {#pressed} presses; the view glided {glides} times`)
	assert(s.tutorial == Rules.STEPS, `the walk stopped at step {s.tutorial}`)
	-- Past the last step: the goal screen waits for the town (the race menu closed, any level-up
	-- splash seen), and Let's go! finishes it.
	Emu.resumeWaits()
	if hud.ctx.panel() then
		local x = find(hud.root, function(d)
			return d:IsA("GuiButton") and d:GetAttribute("Tut") == "close" and d.Visible
		end)
		print(`  (no pointer at step 9: close the {hud.ctx.panel()} menu)`)
		assert(x, "the race menu has no X")
		signalFor(x, "Activated"):Fire()
		Emu.resumeWaits()
	end
	for _ = 1, 6 do
		if not closePopup() then
			break
		end
	end
	Emu.resumeWaits()
	local goal = hud.root:FindFirstChild("Popup")
	if not goal then
		local Kit = emu.require(client.Popups.Kit)
		local kids = {}
		for _, c in hud.root:GetChildren() do
			table.insert(kids, c.Name)
		end
		local st = store.useGame.getState()
		print(`  [diag] showing {tostring(Kit.showing())} hudUp {Kit.hudUp()} gui {hud.gui.Enabled} levelUp {tostring(st.levelUp)} mode {tostring(st.mode)} visiting {tostring(st.visiting)} root [{table.concat(kids, " ")}]`)
	end
	assert(goal, "no goal screen after the last step")
	-- One frame of the hand's own loop, so it's put away for the picture as it would be in game.
	Tut.frame()
	local handShown = false
	for _, d in hud.root:GetDescendants() do
		if d.Name == "TutHand" and d.Visible then
			handShown = true
		end
	end
	print(`tutorial step 9: the goal screen; the hand {if Tut.box(s, hud.root) or handShown then "points" else "rests"}`)
	assert(not handShown, "the hand still shows over the goal screen")
	picture("goal", false)
	local go = find(goal, function(d)
		return d:IsA("TextButton") and d.Name == "Face" and label(d) == "Let's go!"
	end)
	signalFor(go, "Activated"):Fire()
	Emu.resumeWaits()
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	Emu.resumeWaits()
	local done = towns:snapshot(1).save
	print(`tutorial: done at {done.tutorial}; HUD [{hudShows()}]; menu after it {tostring(hud.ctx.panel())}`)
	assert(done.tutorial == 99, "Let's go! didn't finish the tutorial")
	-- The first Daily Spin is the tutorial's reward: it opens once it ends.
	if hud.ctx.panel() ~= "daily" then
		bad += 1
		print("[tutorial] the Daily Spin didn't open after the tutorial")
	end
	-- Lune never fires Destroying on its own: fire it as Roblox would, so the spin's room light
	-- (Panels/Wheel) goes out with it. (Menus closed earlier may still be dropping away under the
	-- same name: fire each.)
	local closing = {}
	for _, c in hud.root:GetChildren() do
		if c.Name == "Panel" then
			table.insert(closing, signalFor(c, "Destroying"))
		end
	end
	hud.ctx.close()
	Emu.resumeWaits()
	for _, sig in closing do
		sig:Fire()
	end
	Emu.resumeWaits()
	Gui.onNode = nil
	TownCamera.lookAt = lookAt
	townsFolder:Destroy()
	print(`tutorial: {bad - before} problems`)
end

-- The town's weather and Rave Mode (client/TownWeather, client/Rave): every kind of weather over
-- a drawn town at noon (lightning mid-flash in the storm, the rainbow after a shower), then a rave
-- through its build-up and drop, with the HUD tag and the club's lights. SHOTS=1 writes
-- build/shot-weather-<kind>.json and shot-rave-*.json with the light, emitters and beams.
do
	hud.ctx.close()
	local TownView = emu.require(SSS.Server.TownView)
	local DayNight = emu.require(client.DayNight)
	local TownWeather = emu.require(client.TownWeather)
	-- A race's or a shop's own sky makes the town's weather stand down.
	assert(DayNight.raceFog == nil, "a race's or shop's sky is still up")
	local Rave = emu.require(client.Rave)
	local W = require("./weatherShot")
	local clock = emu.require(G.clock)
	local techno = emu.require(G.techno)
	towns:_with(1, function()
		store.useGame.setState({ tutorial = 99 })
	end)
	local snap = towns:snapshot(1)
	signalFor(townEvent, "OnClientEvent"):Fire(snap)
	local old = game.Workspace:FindFirstChild("Towns")
	if old then
		old:Destroy()
	end
	local townsFolder = Instance.new("Folder")
	townsFolder.Name = "Towns"
	townsFolder.Parent = game.Workspace
	local view = TownView.new(townsFolder, "Player1", roblox.Vector3.new(0, 0, 0), 1, function() end)
	for _, c in snap.save.cars do
		c.mods, c.panels = nil, nil
	end
	view:render(snap.save)
	-- The town view's camera (TownCamera at zoom 30 on a 1280x800 screen).
	local cam = game.Workspace.CurrentCamera
	cam.FieldOfView = 30
	local dist = 800 / 30 * 10 / 2 / math.tan(math.rad(15))
	do
		-- Lune's CFrame.lookAt faces away from the target; built by hand, as Roblox's.
		local at = roblox.Vector3.new(75, 80, 75).Unit * dist
		local look = (roblox.Vector3.new(0, 0, 0) - at).Unit
		local right = look:Cross(roblox.Vector3.new(0, 1, 0)).Unit
		local up = right:Cross(look)
		cam.CFrame = roblox.CFrame.new(at.X, at.Y, at.Z, right.X, up.X, -look.X, right.Y, up.Y, -look.Y, right.Z, up.Z, -look.Z)
	end
	local noon = clock.nextPhaseAt(0, NOW)
	local function parts()
		local n = 0
		for _, d in game.Workspace:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end
	local before = parts()
	-- DayNight's own noon light, which render.mjs's default lights stand for.
	DayNight.apply(noon)
	local lightBase = W.lighting(game)
	local function weatherShot(name, extraGuis)
		if not SHOTS then
			return
		end
		shot(name, view.folder)
		local scene = serde.decode("json", fs.readFile(`build/shot-{name}.json`))
		scene.lighting = W.lighting(game)
		scene.lightingBase = lightBase
		scene.effects = W.effects(game.Workspace:FindFirstChild("TownWeather"))
		fs.writeFile(`build/shot-{name}.json`, serde.encode("json", scene))
		if extraGuis then
			local nodes = {}
			for _, g in extraGuis do
				for _, n in Gui.dump(g, 1280, 800) do
					table.insert(nodes, n)
				end
			end
			fs.writeFile(`build/shot-{name}-gui.json`, serde.encode("json", { nodes = nodes, bubbles = {} }))
		end
	end
	local problems = 0
	-- The town's own ground pieces, which the weather recolours (and puts back).
	local asphalt, turf
	for _, d in townsFolder:GetDescendants() do
		if d.Name == "Asphalt" and d:IsA("BasePart") then
			asphalt = asphalt or d
		elseif d.Name == "Turf" and d:IsA("BasePart") then
			turf = turf or d
		end
	end
	local asphaltWas, turfWas = asphalt and asphalt.Color, turf and turf.Color
	local function lum(c)
		return c.R * 0.2126 + c.G * 0.7152 + c.B * 0.0722
	end
	for _, kind in { "clear", "rain", "storm", "drizzle", "fog", "wind", "snow", "blizzard", "dust", "mist", "clearing", "heat" } do
		DayNight.apply(noon)
		TownWeather.pin(kind)
		-- The storm's first strike lands 3 to 8 seconds in; 20 s finds it mid-flash.
		local ok, err = pcall(TownWeather.step, noon, if kind == "storm" then 20 else 1)
		if not ok then
			problems += 1
			print(`weather {kind}: ERROR {err}`)
			continue
		end
		local L = game:GetService("Lighting")
		local fx = W.effects(game.Workspace:FindFirstChild("TownWeather"))
		local rates = {}
		for _, e in fx.emitters do
			local k = e.name:gsub("%d", "")
			rates[k] = (rates[k] or 0) + e.rate
		end
		local list = {}
		for k, v in rates do
			table.insert(list, `{k} {math.floor(v)}/s`)
		end
		table.sort(list)
		print(`weather {kind}: brightness {string.format("%.2f", L.Brightness)}, exposure {string.format("%.2f", L.ExposureCompensation)}, air {string.format("%.2f", (L:FindFirstChildWhichIsA("Atmosphere") or { Density = 0 }).Density)}; {table.concat(list, ", ")}; {#fx.beams} beams`)
		if kind == "storm" then
			assert(#fx.beams >= 16, "no lightning in the storm")
		elseif kind == "clearing" then
			assert(#fx.beams == 12 * 16, "no rainbow after the shower")
			for _, b in fx.beams do
				-- About as wide as the screen is tall, standing over the town.
				assert(b.width[1] > 0 and b.width[1] < 20, `a rainbow band {b.width[1]} studs wide`)
			end
		elseif kind == "rain" then
			assert((rates.Rain or 0) > 100 and (rates.Splash or 0) > 50, "no rain")
			if asphalt then
				assert(lum(asphalt.Color) < lum(asphaltWas) * 0.75, "the roads didn't get wet")
				print(`weather rain: roads {asphaltWas:ToHex()} -> {asphalt.Color:ToHex()}`)
			end
		elseif kind == "snow" then
			assert((rates.Snow or 0) > 50, "no snow")
			if turf then
				assert(lum(turf.Color) > 0.85, "no snow on the lawns")
				print(`weather snow: lawn {turfWas:ToHex()} -> {turf.Color:ToHex()}, roads {asphalt and asphalt.Color:ToHex() or "none"}`)
			end
		elseif kind == "clear" then
			assert(#fx.emitters == 0 and #fx.beams == 0, "something falls on a clear day")
		end
		weatherShot(`weather-{kind}`)
	end
	-- The town's light goes back to DayNight's when the weather clears.
	DayNight.apply(noon)
	local bright = game:GetService("Lighting").Brightness
	TownWeather.pin("clear")
	TownWeather.step(noon, 2)
	assert(math.abs(game:GetService("Lighting").Brightness - bright) < 1e-6, "clear weather changed the light")
	assert(not asphalt or asphalt.Color == asphaltWas, "the roads stayed wet")
	assert(not turf or turf.Color == turfWas, "the snow stayed on the lawns")
	print(`weather: {parts() - before} parts added, {problems} problems`)

	-- Rave Mode: the build-up (heads-up, countdown), then the drop (title, tag, lights).
	local changes = {}
	Rave.onChange(function(on)
		table.insert(changes, on)
	end)
	local from = NOW
	Rave.startTest(from, from + 68200)
	local hudGui = player.PlayerGui:FindFirstChild("Cartopia")
	local neon
	for _, d in townsFolder:GetDescendants() do
		if d:IsA("BasePart") and d.Material == roblox.Enum.Material.Neon then
			neon = d
			break
		end
	end
	local neonWas = neon and neon.Color
	for _, step in { { "build", 7500, 7.5 }, { "drop", 10600, 10.6 }, { "groove", 14000, 14 } } do
		local now = from + step[2]
		DayNight.apply(now)
		TownWeather.pin(nil)
		TownWeather.step(now, step[3])
		-- A frame half a second earlier too (the title lands on the first frame after the drop).
		Rave.step(now - 500, step[3] - 0.5)
		Rave.step(now, step[3])
		local rg = player.PlayerGui:FindFirstChild("RaveMode")
		local tagFrame = hudGui and hudGui:FindFirstChild("RaveTag", true)
		print(`rave {step[1]}: on {Rave.isOn(now)}, night {string.format("%.2f", clock.nightAmount(clock.dayPhase(now)))}, to drop {techno.technoToDrop(now)} ms, layer {rg ~= nil}, tag {tagFrame and tagFrame.Tag.Left.Text or "none"}, heads-up {player.PlayerGui:FindFirstChild("RaveHeadsUp") ~= nil}`)
		assert(Rave.isOn(now) and rg and tagFrame, "Rave Mode didn't show")
		local townName = hudGui and hudGui.Root.Center.TownName.Face
		assert(townName.TextColor3 ~= roblox.Color3.new(1, 1, 1), "the town's name didn't take the beat's colour")
		local guis = { rg, hudGui }
		local hu = player.PlayerGui:FindFirstChild("RaveHeadsUp")
		if hu then
			table.insert(guis, hu)
		end
		weatherShot(`rave-{step[1]}`, guis)
		-- The heads-up goes after nine seconds (a timer the emulator doesn't run).
		if hu then
			hu:Destroy()
		end
	end
	assert(player:GetAttribute("RaveOn") == true, "the music hook didn't hear the rave start")
	if neon then
		assert(neon.Color ~= neonWas, "the town's neon didn't take the club's colour")
	end
	-- And off again at its end: lights back, tag gone, the hook told.
	local after = from + 68200 + 500
	Rave.step(after, 70)
	assert(not Rave.isOn(after), "the rave didn't end")
	assert(player:GetAttribute("RaveOn") == false, "the music hook didn't hear the rave stop")
	if neon then
		assert(neon.Color == neonWas, "the town's neon didn't go back")
	end
	assert(not (hudGui and hudGui:FindFirstChild("RaveTag", true)), "the rave tag stayed")
	assert(not (hudGui and hudGui:FindFirstChild("RaveScale", true)), "the HUD kept dancing")
	local townName = hudGui and hudGui.Root.Center.TownName.Face
	assert(townName.TextColor3 == roblox.Color3.new(1, 1, 1), "the town's name kept the rave's colour")
	print(`rave: hook heard {#changes} changes, neon {neon and "back" or "none in town"}`)
	townsFolder:Destroy()
	print("weather and rave: 0 problems")
end

-- Town visitors (client/Visitors, client/VisitorCar, Panels/StreetRace, server/Visitors): a street
-- racer turns up and drives the town's roads with its badge, its card opens from the badge, every
-- button on the card is pressed, then it's raced and beaten for its bonus; tourists and the
-- mystery car are tapped for their prize, and the mystery car once too late. SHOTS=1 writes
-- build/shot-visitor-*.json (the racer in town, the card, the mystery car's countdown).
do
	hud.ctx.close()
	local problems = 0
	local function problem(msg)
		problems += 1
		print(`[visitors] PROBLEM {msg}`)
	end
	local Visitors = emu.require(client.Visitors)
	local VisitorCar = emu.require(client.VisitorCar)
	local TownView = emu.require(SSS.Server.TownView)
	towns:_with(1, function(s)
		store.useGame.setState({ tutorial = 99, fuel = math.max(s.fuel, 50) })
	end)
	local snap = towns:snapshot(1)
	signalFor(townEvent, "OnClientEvent"):Fire(snap)
	local townsFolder = Instance.new("Folder")
	townsFolder.Name = "Towns"
	townsFolder.Parent = game.Workspace
	local view = TownView.new(townsFolder, "Player1", roblox.Vector3.new(0, 0, 0), 1, function() end)
	for _, c in snap.save.cars do
		c.mods, c.panels = nil, nil
	end
	view:render(snap.save)
	-- The toasts shown (the client's own, and the server's in each snapshot), newest last.
	-- A clean noon over the town for the pictures (an earlier screen can leave its own light or
	-- its gui behind).
	local spin = player.PlayerGui:FindFirstChild("DailySpin")
	if spin then
		spin:Destroy()
	end
	do
		local clock = emu.require(G.clock)
		emu.require(client.DayNight).apply(clock.nextPhaseAt(0, NOW))
	end
	-- The town and the visitor's cars, as one picture.
	local function townShot(name)
		local cars = game.Workspace:FindFirstChild("Visitors")
		if cars then
			cars.Parent = view.folder
		end
		shot(name, view.folder)
		if cars then
			cars.Parent = game.Workspace
		end
	end
	local toastsSeen = {}
	local clientToast = hud.ctx.toast
	hud.ctx.toast = function(text)
		table.insert(toastsSeen, text)
		clientToast(text)
	end
	Remote.changed:Connect(function(sn)
		for _, t in sn.toasts or {} do
			table.insert(toastsSeen, t)
		end
	end)
	local function lastToast()
		local out = table.concat(toastsSeen, " / ")
		table.clear(toastsSeen)
		return out
	end

	-- The town's own visitor clock ran through the sections before this one (the tutorial moves time
	-- on while it waits for jobs and Rusty), so a visitor it rolled may already be in town, picked
	-- by the seeded roll rather than the kind asked for below. See it off first, as a player who
	-- let it leave would, so each arrival here is the one asked for.
	if Visitors.visitor and not Visitors.visitor.gone then
		print(`visitors: a {Visitors.visitor.kind} was already in town; seen off`)
		Visitors.leave()
		Emu.resumeWaits()
	end
	local stray = visitorDesk:current(1)
	if stray then
		visitorDesk:leave(1, stray.id)
	end

	-- The next visitor, of `kind`: the server's roll made to pick it, past the gap since the last.
	local function arrive(kind)
		visitorDesk.rollKind = function()
			return kind
		end
		visitClock += 5 * 60000
		calls = {}
		handlerErrors = {}
		Visitors.ask()
		Emu.resumeWaits()
		local v = Visitors.visitor
		if not v or v.kind ~= kind or v.gone then
			problem(`no {kind} came: {table.concat(calls, ", ")}`)
			return nil
		end
		for _, c in calls do
			if c:sub(1, 2) ~= "ok" then
				problem(c)
			end
		end
		return v
	end
	local function drive(frames)
		for _ = 1, frames do
			VisitorCar.step(1 / 30)
		end
	end
	local function badge()
		local holder = player.PlayerGui:FindFirstChild("VisitorBadges")
		local gui = holder and holder:FindFirstChildWhichIsA("BillboardGui")
		local face = gui and find(gui, function(d)
			return d:IsA("TextButton") and d.Name == "Face"
		end)
		local text = gui and find(gui, function(d)
			return d:IsA("TextLabel") and d.Name == "Label"
		end)
		return gui, face, text and text.Text or ""
	end
	local function aim(at)
		local cam = game.Workspace.CurrentCamera
		cam.FieldOfView = 30
		local from = at + roblox.Vector3.new(75, 80, 75).Unit * 260
		local look = (at - from).Unit
		local right = look:Cross(roblox.Vector3.new(0, 1, 0)).Unit
		local up = right:Cross(look)
		cam.CFrame = roblox.CFrame.new(from.X, from.Y, from.Z, right.X, up.X, -look.X, right.Y, up.Y, -look.Y, right.Z, up.Z, -look.Z)
	end

	-- A street racer rolls in and drives round town.
	local v = arrive("racer")
	if v then
		print(`visitor: {v.name} in a {v.model} (PI {v.pi}), toast "{lastToast()}"`)
		drive(150)
		local m = VisitorCar._models[`visitor:{v.id}`]
		local a = VisitorCar._traffic.agents:get(`visitor:{v.id}`)
		if not m or not a then
			problem("the racer's car isn't on the road")
		else
			local p = m:GetPivot().Position
			print(`visitor car: at ({math.floor(p.X)}, {math.floor(p.Z)}), shown {string.format("%.2f", a.show)}, road tile {math.floor(a.x / 2)},{math.floor(a.z / 2)}`)
			aim(p)
		end
		local gui, face, text = badge()
		if not gui or text ~= "🏁 Race me!" then
			problem(`the racer's badge says "{text}"`)
		end
		townShot("visitor-town")
		-- Its badge opens the Street challenge card.
		if face then
			signalFor(face, "Activated"):Fire()
		end
		local panel = hud.root:FindFirstChild("Panel")
		local title = panel and panel:FindFirstChild("Title", true)
		local titleText = if title and title:IsA("TextLabel") and title.Text ~= "" then title.Text elseif title then label(title) else ""
		if not string.find(titleText, "Street challenge", 1, true) then
			problem("tapping the racer didn't open the Street challenge card")
		end
		local card = panel and find(panel, function(d)
			return d:IsA("TextLabel") and d.Name == "Car"
		end)
		print(`street card: {card and card.Text or "?"}`)
		shot("visitor-card", nil)
	end
	-- Every button on the card (Race! starts a street race, which clickAll leaves; No thanks sends
	-- the racer off), a racer brought back for each.
	local before, pressed = bad, total
	clickAll("streetRace", function()
		local here = Visitors.visitor
		if not here or here.gone or here.kind ~= "racer" then
			arrive("racer")
		end
		hud.openPanel("streetRace")
	end)
	print(`street card: {total - pressed} buttons pressed, {bad - before} problems`)
	if bad > before then
		problems += bad - before
	end
	Emu.resumeWaits()

	-- Raced and beaten: the race prize, and the racer's bonus.
	local racer = arrive("racer")
	if racer then
		local before0 = towns:snapshot(1).save
		local coins0 = before0.coins
		local fuel0 = before0.fuel
		-- They've been in town a while before the race (a racer can't be beaten in their first 10 s).
		visitClock += 30000
		local frames, shifts, result = runRace("visitor-race", {}, function()
			hud.openPanel("streetRace")
			local panel = hud.root:FindFirstChild("Panel")
			local go = panel and find(panel, function(d)
				return d:IsA("TextButton") and label(d) == "Race!"
			end)
			assert(go, "no Race! on the Street challenge card")
			signalFor(go, "Activated"):Fire()
		end)
		local after = towns:snapshot(1).save
		print(`street race: {frames} frames, {shifts} shifts; card: {cardText(result)}`)
		print(`street race: coins {coins0} -> {after.coins} (bonus ${racer.coins}), fuel {fuel0} -> {after.fuel}, visits {after.visits}`)
		if not result then
			problem("the street race has no result card")
		end
		if after.fuel ~= fuel0 then
			problem("the street race cost fuel")
		end
		if visitorDesk:current(1) ~= nil then
			problem("the racer is still in town after the race")
		end
		if (after.visits or 0) ~= (before0.visits or 0) + 1 or after.coins < coins0 + racer.coins then
			problem("beating the racer didn't pay their bonus")
		end
		closeRace()
		print(`street race: toast "{lastToast()}", visitor {if Visitors.visitor and not Visitors.visitor.gone then "still here" else "gone"}`)
		if Visitors.visitor and not Visitors.visitor.gone then
			problem("the racer didn't leave after the race")
		end
		for _, c in calls do
			if c:sub(1, 2) ~= "ok" then
				problem(c)
			end
		end
	end

	-- Tourists: tapped for their tip.
	local tourist = arrive("tourist")
	if tourist then
		drive(60)
		local _, face, text = badge()
		print(`tourists: badge "{text}", group {tourist.group or 1}, toast "{lastToast()}"`)
		local coins0 = towns:snapshot(1).save.coins
		calls = {}
		if face then
			signalFor(face, "Activated"):Fire()
		end
		Emu.resumeWaits()
		local coins1 = towns:snapshot(1).save.coins
		print(`tourists: claimed, coins {coins0} -> {coins1} (tip ${tourist.coins}), toast "{lastToast()}" {table.concat(calls, ", ")}`)
		if coins1 ~= coins0 + tourist.coins then
			problem("the tourists' tip wasn't paid")
		end
		drive(60)
		if VisitorCar._models[`visitor:{tourist.id}`] then
			problem("the tourists' camper didn't fade away")
		end
	end

	-- The mystery car: its countdown, tapped in time, then once too late.
	local mystery = arrive("mystery")
	if mystery then
		drive(60)
		local _, face, text = badge()
		print(`mystery car: badge "{text}"`)
		if not string.find(text, "❓", 1, true) or not string.find(text, "s$") then
			problem(`the mystery badge says "{text}"`)
		end
		local m = VisitorCar._models[`visitor:{mystery.id}`]
		if m then
			aim(m:GetPivot().Position)
		end
		townShot("visitor-mystery")
		local parts0 = towns:snapshot(1).save.parts
		if face then
			signalFor(face, "Activated"):Fire()
		end
		Emu.resumeWaits()
		print(`mystery car: caught, parts {parts0} -> {towns:snapshot(1).save.parts}, toast "{lastToast()}"`)
		if towns:snapshot(1).save.parts ~= parts0 + mystery.parts then
			problem("the mystery car's parts weren't paid")
		end
	end
	local late = arrive("mystery")
	if late then
		visitClock += 60000
		local coins0 = towns:snapshot(1).save.coins
		local _, face = badge()
		if face then
			signalFor(face, "Activated"):Fire()
		end
		Emu.resumeWaits()
		print(`mystery car, too late: coins {coins0} -> {towns:snapshot(1).save.coins}, toast "{lastToast()}"`)
		if towns:snapshot(1).save.coins ~= coins0 then
			problem("a mystery car tapped too late still paid")
		end
	end
	-- No thanks: the next one comes a few minutes later, not at once.
	local w = visitorDesk:next(1)
	print(`visitors: next ask says wait {w.wait or "none"}s`)
	Emu.resumeWaits()
	hud.ctx.close()
	townsFolder:Destroy()
	print(`visitors: {problems} problems`)
end

-- Car extras: the dyno pull on the car's page after an upgrade (client/Dyno), the 📸 postcard on a
-- won race (client/Snapshot), and the "🛞 Flat!" bubble over a stalled car in town that opens its
-- fix-it sheet (Popups/FlatBadge). SHOTS=1 writes build/shot-dyno*.json and shot-postcard.json.
do
	hud.ctx.close()
	local problems = 0
	local function problem(msg)
		problems += 1
		print(`[car extras] PROBLEM {msg}`)
	end
	local UIS = game:GetService("UserInputService")
	local touch = { UserInputType = roblox.Enum.UserInputType.Touch, KeyCode = roblox.Enum.KeyCode.Unknown }
	local function textOf(root)
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("TextLabel") and d.Name ~= "Face" and d.Text ~= "" and d.Visible then
				table.insert(out, d.Text)
			end
		end
		return table.concat(out, " | ")
	end

	-- The dyno: an engine upgrade tapped on the car's page.
	calls = {}
	handlerErrors = {}
	local uid
	towns:_with(1, function()
		local cars = {}
		for i, c in store.useGame.getState().cars do
			cars[i] = table.clone(c)
			cars[i].flat, cars[i].lowFuel = nil, nil
		end
		cars[1].upgrades = { engine = 0, turbo = 0, tires = 0, weight = 0 }
		uid = cars[1].uid
		store.useGame.setState({ coins = 1000000, parts = 100000, cars = cars, selectedCar = uid })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.openPanel("cars", { car = uid, tab = "tune" })
	local Dyno = emu.require(client.Dyno)
	local t = 1000
	Dyno.clock = function()
		return t
	end
	signalFor(UIS, "InputBegan"):Fire(touch, true)
	Remote.act("upgradeCar", uid, "engine")
	Emu.resumeWaits()
	local dyno = hud.gui:FindFirstChild("Dyno", true)
	if not dyno then
		problem(`no dyno after an upgrade ({table.concat(calls, ", ")}) {table.concat(handlerErrors, "; ")}`)
	else
		local pi = hud.gui:FindFirstChild("PI", true)
		if pi and pi.Visible then
			problem("the PI badge shows over the dyno")
		end
		print(`dyno: start "{textOf(dyno)}"`)
		shot("dyno", nil)
		-- The pull run to its end: the new time and the gain.
		t += Dyno.PULL + 0.1
		signalFor(game:GetService("RunService"), "RenderStepped"):Fire(1 / 60)
		local done = textOf(dyno)
		print(`dyno: done "{done}"`)
		if not string.find(done, "PI", 1, true) or not (string.find(done, "−", 1, true) or string.find(done, "Same time", 1, true)) then
			problem(`the dyno's result says "{done}"`)
		end
		shot("dyno-done", nil)
		-- Tapped to skip: it goes and the PI badge is back.
		signalFor(dyno, "Activated"):Fire()
		Emu.resumeWaits()
		if hud.gui:FindFirstChild("Dyno", true) then
			problem("the dyno didn't go when tapped")
		end
		local back = hud.gui:FindFirstChild("PI", true)
		if not back or not back.Visible then
			problem("the PI badge didn't come back after the dyno")
		end
	end
	-- A save arriving with no tap on the page (from another device) starts no dyno.
	Dyno.clock = os.clock
	hud.ctx.close()
	hud.openPanel("cars", { car = uid, tab = "tune" })
	towns:_with(1, function()
		local cars = {}
		for i, c in store.useGame.getState().cars do
			cars[i] = table.clone(c)
		end
		cars[1].upgrades = table.clone(cars[1].upgrades)
		cars[1].upgrades.turbo = (cars[1].upgrades.turbo or 0) + 1
		store.useGame.setState({ cars = cars })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	if hud.gui:FindFirstChild("Dyno", true) then
		problem("a dyno ran with no tap")
	end
	hud.ctx.close()

	-- The postcard: the 📸 on a result card, as a won race shows it (no screenshot service here, so
	-- the postcard stays up with its hint, and a tap brings the card back).
	local Snapshot = emu.require(client.Snapshot)
	-- Drawn on the HUD's screen, so the picture has it.
	local screen = Instance.new("Frame")
	screen.Name = "SnapTest"
	screen.BackgroundTransparency = 1
	screen.ZIndex = 50
	screen.Size = roblox.UDim2.fromScale(1, 1)
	screen.Parent = hud.root
	local gui = screen
	local result = Instance.new("Frame")
	result.Name = "Result"
	result.Size = roblox.UDim2.fromScale(1, 1)
	result.Parent = screen
	local card = Instance.new("Frame")
	card.Size = roblox.UDim2.fromOffset(420, 470)
	card.Parent = result
	local snapButton = Snapshot.button(card, result, screen, "🏆 Beat Rosa")
	handlerErrors = {}
	signalFor(snapButton, "Activated"):Fire()
	Emu.resumeWaits()
	local strip = screen:FindFirstChild("Postcard")
	if not strip or result.Visible then
		problem(`no postcard on 📸 {table.concat(handlerErrors, "; ")}`)
	else
		print(`postcard: "{textOf(strip)}"`)
		if textOf(strip) ~= "🏆 Beat Rosa | Cartopia" then
			problem(`the postcard says "{textOf(strip)}"`)
		end
		shot("postcard", nil)
		local back = screen:FindFirstChild("PostcardBack")
		if not back then
			problem("the postcard has no way back")
		else
			signalFor(back, "Activated"):Fire()
			Emu.resumeWaits()
		end
		if screen:FindFirstChild("Postcard") or not result.Visible then
			problem("the result card didn't come back after the postcard")
		end
	end
	gui:Destroy()

	-- The flat-tire bubble: over the stalled car on the road, tapped for its fix-it sheet.
	local FlatBadge = emu.require(client.Popups.FlatBadge)
	local carModel = Instance.new("Model")
	local body = Instance.new("Part")
	body.Size = roblox.Vector3.new(8, 4, 16)
	body.Parent = carModel
	carModel.PrimaryPart = body
	carModel.Parent = game.Workspace
	for _, how in { "flat", "gas" } do
		local stuck
		towns:_with(1, function()
			local cars = {}
			for i, c in store.useGame.getState().cars do
				cars[i] = table.clone(c)
				cars[i].flat = if i == 1 and how == "flat" then true else nil
				cars[i].lowFuel = if i == 1 and how == "gas" then true else nil
			end
			stuck = cars[1].uid
			store.useGame.setState({ cars = cars })
		end)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		FlatBadge.onRoad = function()
			return { [stuck] = carModel }
		end
		FlatBadge.refresh()
		local face = FlatBadge.faces()[stuck]
		if not face then
			problem(`no bubble over the {how} car`)
			continue
		end
		local words = textOf(face)
		print(`flat badge ({how}): "{words}"`)
		if words ~= (if how == "flat" then "🛞 Flat!" else "⛽ No gas!") then
			problem(`the {how} bubble says "{words}"`)
		end
		handlerErrors = {}
		signalFor(face, "Activated"):Fire()
		Emu.resumeWaits()
		local panel = hud.root:FindFirstChild("Panel")
		local sheet = panel and textOf(panel) or ""
		print(`flat badge ({how}): sheet "{string.sub(sheet, 1, 140)}"`)
		if not panel or #handlerErrors > 0 then
			problem(`the {how} bubble didn't open the fix-it sheet {table.concat(handlerErrors, "; ")}`)
		end
		hud.ctx.close()
	end
	-- Fixed: the bubble goes.
	towns:_with(1, function()
		local cars = {}
		for i, c in store.useGame.getState().cars do
			cars[i] = table.clone(c)
			cars[i].flat, cars[i].lowFuel = nil, nil
		end
		store.useGame.setState({ cars = cars })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	FlatBadge.refresh()
	if next(FlatBadge.faces()) then
		problem("the bubble stayed after the car was fixed")
	end
	carModel:Destroy()
	print(`car extras: {problems} problems`)
end

adminCheck()

-- Custom Colour, track skins and the free camera (client/ColourPicker, SkinShop.tracks, the
-- TownCamera's free mode): drag over the picker's square and bar in the Paint and Custom tabs and
-- buy the colour; the locked dot's way to the crates; a Tomahawk's track skin tried on and put on
-- (and the links it recolours); the free camera's button, one-finger drag, pinch, wheel and keys,
-- and back to the bird's-eye view. SHOTS=1 writes build/shot-colour-*.json and shot-tracks-*.json.
do
	hud.ctx.close()
	local problems = 0
	local function problem(msg)
		problems += 1
		print(`[colour/tracks/freecam] PROBLEM {msg}`)
	end
	local function checkCalls(what)
		for _, c in calls do
			if c:sub(1, 2) ~= "ok" then
				problem(`{what}: {c}`)
			end
		end
		for _, e in handlerErrors do
			problem(`{what}: ERROR {e}`)
		end
		calls = {}
		handlerErrors = {}
	end
	local UIS = game:GetService("UserInputService")
	local V3, V2 = roblox.Vector3, roblox.Vector2
	local data = emu.require(RS.Shared.Game.data)
	-- Looked for in the Cars page first when it's open (pop-ups and pages left by the sections
	-- above can hold buttons of the same names).
	local function carsPage()
		-- (The panel is drawn in the HUD's Root: Root/Panel/Cars.)
		for _, p in hud.gui:GetDescendants() do
			if p.Name == "Cars" and p.Parent and p.Parent.Name == "Panel" and p:IsA("Frame") then
				return p
			end
		end
		return nil
	end
	local function find(name)
		local page = carsPage()
		return page and page:FindFirstChild(name, true) or hud.gui:FindFirstChild(name, true)
	end
	local function tap(name)
		local b = find(name)
		if not b then
			problem(`no {name} button`)
			return
		end
		signalFor(b, "Activated"):Fire()
	end
	-- What's on screen, when a check fails: the open panel, the car's name and the shop's lists.
	local function where()
		local page = carsPage()
		local bits = { `panel {tostring(hud.ctx.panel())}` }
		if page then
			for _, d in page:GetDescendants() do
				if d:IsA("TextLabel") and d.TextSize == 22 or d.Name == "ModShop" or d.Name == "CustomShop" or d.Name == "PaintShop" then
					table.insert(bits, if d:IsA("TextLabel") then d.Text else d.Name)
				end
			end
		end
		for _, p in hud.gui:GetChildren() do
			if p:IsA("GuiObject") and p.Visible and p.Name ~= "Root" then
				table.insert(bits, `top {p.Name}`)
			end
		end
		-- Every "mods" and "rims" in the HUD, with where it sits.
		for _, d in hud.gui:GetDescendants() do
			if d.Name == "mods" or d.Name == "rims" then
				table.insert(bits, d:GetFullName())
			end
		end
		return table.concat(bits, ", ")
	end
	-- A picture with the shop's list scrolled down to what's being shown, wide and on a phone.
	local function look(name, list, y)
		local s = list and find(list)
		if s then
			s.CanvasPosition = V2.new(0, y)
		end
		shot(name, nil)
		local root = hud.gui:FindFirstChild("Root")
		root.Size = roblox.UDim2.fromOffset(1535, 709)
		shot(`{name}-phone`, nil, 1535, 709)
		root.Size = roblox.UDim2.fromOffset(1280, 800)
	end
	local function onChart(c)
		for _, p in data.PAINTS do
			if p.color == c then
				return true
			end
		end
		return false
	end
	-- A drag over one of the picker's areas, laid out at a made-up place (nothing is laid out here).
	local function drag(area, from, to)
		area.AbsolutePosition = V2.new(100, 100)
		area.AbsoluteSize = V2.new(300, if area.Name == "SV" then 150 else 26)
		local down = { UserInputType = roblox.Enum.UserInputType.MouseButton1, KeyCode = roblox.Enum.KeyCode.Unknown, Position = V3.new(from[1], from[2], 0) }
		signalFor(area, "InputBegan"):Fire(down)
		signalFor(UIS, "InputChanged"):Fire({ UserInputType = roblox.Enum.UserInputType.MouseMovement, KeyCode = roblox.Enum.KeyCode.Unknown, Position = V3.new(to[1], to[2], 0) }, false)
		signalFor(UIS, "InputEnded"):Fire(down)
	end
	local function carOf(uid)
		for _, c in towns:snapshot(1).save.cars do
			if c.uid == uid then
				return c
			end
		end
		return {}
	end
	calls = {}
	handlerErrors = {}

	-- Paint: Custom Colour won; open its picker, drag the square and the bar, and buy the colour.
	local first
	towns:_with(1, function()
		local s = store.useGame.getState()
		local skins = table.clone(s.skins or {})
		if not table.find(skins, data.CUSTOM_PAINT.id) then
			table.insert(skins, data.CUSTOM_PAINT.id)
		end
		first = s.cars[1].uid
		store.useGame.setState({ coins = 1000000, bucks = 1000, skins = skins, selectedCar = first })
	end)
	local colours0 = {}
	for _, c in towns:snapshot(1).save.cars do
		colours0[c.uid] = c.color
	end
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.openPanel("cars", "garage")
	tap("paint")
	-- The picker starts open when the car's colour is already off the chart.
	if not (find("CustomColourPicker") and find("CustomColourPicker").Visible) then
		tap("CustomColour")
	end
	local fly = find("CustomColourPicker")
	if not fly or not fly.Visible then
		problem("the Custom Colour dot didn't open its picker")
	end
	look("colour-open", "PaintShop", 800)
	local sv = fly and fly:FindFirstChild("SV")
	if sv then
		drag(sv, { 250, 130 }, { 330, 110 })
	else
		problem("no colour square in the picker")
	end
	local hue = find("CustomColourPicker") and find("CustomColourPicker"):FindFirstChild("Hue")
	if hue then
		drag(hue, { 160, 113 }, { 262, 113 })
	else
		problem("no hue bar in the picker")
	end
	look("colour-try", "PaintShop", 800)
	local bar = find("PaintShop") and find("PaintShop").Parent:FindFirstChild("TryBar")
	local label = bar and bar:FindFirstChildWhichIsA("TextLabel")
	if not label or not string.find(label.Text, "Custom colour", 1, true) then
		problem(`the try-on bar doesn't say Custom colour: {label and label.Text or "no bar"}`)
	end
	local go = bar and bar:FindFirstChild("Go", true)
	if go then
		signalFor(go, "Activated"):Fire()
	else
		problem("no buy button for the custom colour")
	end
	-- The garage keeps showing the car it showed before: whichever car the new colour went on.
	local painted = nil
	for _, c in towns:snapshot(1).save.cars do
		if colours0[c.uid] ~= c.color then
			painted, first = c.color, c.uid
		end
	end
	if type(painted) ~= "string" or not painted:match("^#%x%x%x%x%x%x$") or onChart(painted) then
		problem(`the custom colour didn't stick: {tostring(painted)}`)
	end
	print(`custom colour: painted {tostring(painted)}`)
	shot("colour-bought", nil)
	checkCalls("paint custom colour")

	-- Custom: the hood in a custom colour.
	hud.ctx.close()
	hud.openPanel("cars", "garage")
	local hoods0 = {}
	for _, c in towns:snapshot(1).save.cars do
		hoods0[c.uid] = c.panels and c.panels.hood and c.panels.hood.color
	end
	tap("custom")
	tap("hood")
	local cfly = find("CustomColourPicker")
	if cfly and not cfly.Visible then
		tap("CustomColour")
	end
	cfly = find("CustomColourPicker")
	local csv = cfly and cfly:FindFirstChild("SV")
	if csv then
		drag(csv, { 120, 140 }, { 140, 120 })
	else
		problem("no colour square in the Custom tab")
	end
	look("colour-custom", "CustomShop", 600)
	local cbar = find("CustomShop") and find("CustomShop").Parent:FindFirstChild("TryBar")
	local cgo = cbar and cbar:FindFirstChild("Go", true)
	if cgo then
		signalFor(cgo, "Activated"):Fire()
	else
		problem("no buy button for the custom hood")
	end
	-- Whichever car the garage shows gets the hood.
	local hood = nil
	for _, c in towns:snapshot(1).save.cars do
		local h = c.panels and c.panels.hood
		if h and h.color ~= hoods0[c.uid] then
			hood = h
		end
	end
	if not hood or type(hood.color) ~= "string" or onChart(hood.color) then
		problem(`the custom hood colour didn't stick: {hood and tostring(hood.color) or "none"} ({where()})`)
	end
	checkCalls("custom tab custom colour")

	-- Locked: not won yet, the picker points at the crates.
	towns:_with(1, function()
		local s = store.useGame.getState()
		local skins = {}
		for _, id in s.skins or {} do
			if id ~= data.CUSTOM_PAINT.id then
				table.insert(skins, id)
			end
		end
		store.useGame.setState({ skins = skins })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("cars", "garage")
	tap("paint")
	local lfly = find("CustomColourPicker")
	if lfly and not lfly.Visible then
		tap("CustomColour")
	end
	look("colour-locked", "PaintShop", 800)
	tap("Crates")
	if hud.ctx.panel() ~= "crates" then
		problem(`the locked picker's Crates button opened {tostring(hud.ctx.panel())}`)
	end
	checkCalls("locked custom colour")

	-- Track skins: a Tomahawk at level 40 tries Magma (level 44: says where it comes from), then
	-- puts on Hazard.
	towns:_with(1, function()
		local s = store.useGame.getState()
		local cars = table.clone(s.cars)
		local tank = table.clone(cars[1])
		tank.uid, tank.model, tank.color, tank.mods, tank.modSkin, tank.panels = "tank-emu", "tomahawk", "#556b2f", nil, nil, nil
		table.insert(cars, tank)
		store.useGame.setState({ cars = cars, level = 40, selectedCar = "tank-emu" })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("cars", "garage")
	-- The garage keeps the car it showed: pick the tank from its list.
	tap("mods")
	tap("rims")
	local picker = find("TrackSkins")
	if not picker then
		-- Its row in the list; the sections above may have left the list's body filter on
		-- something else (Sports, Trucks...), so step the filter round until the tank's row shows.
		local function tankRow()
			local page = carsPage()
			for _, d in (if page then page else hud.gui):GetDescendants() do
				if d:IsA("TextLabel") and d.Text == data.carDef("tomahawk").name and d.Parent and d.Parent:IsA("GuiButton") then
					return d.Parent
				end
			end
			return nil
		end
		local function filterButton()
			local list = find("List")
			for _, d in (if list then list:GetDescendants() else {}) do
				-- The body filter is the left box (x 0); the sort box sits at x 0.5.
				if d:IsA("TextButton") and d.Position.X.Scale == 0 then
					for _, t in d:GetChildren() do
						if t:IsA("TextLabel") and t.Text == "▾" then
							return d
						end
					end
				end
			end
			return nil
		end
		local row = tankRow()
		for _ = 1, 10 do
			local f = filterButton()
			if row or not f then
				break
			end
			signalFor(f, "Activated"):Fire()
			row = tankRow()
		end
		if row then
			signalFor(row, "Activated"):Fire()
		else
			local saved, rows = {}, {}
			for _, c in towns:snapshot(1).save.cars do
				table.insert(saved, `{c.uid}:{c.model}`)
			end
			local list = find("List")
			for _, d in (if list then list:GetDescendants() else {}) do
				if d:IsA("TextLabel") and d.Parent and d.Parent:IsA("GuiButton") and d.TextSize == 15 then
					table.insert(rows, d.Text)
				end
			end
			problem(`the Tomahawk isn't in the garage's list under any filter: saved [{table.concat(saved, " ")}], level {towns:snapshot(1).save.level}, rows [{table.concat(rows, " / ")}]`)
		end
		tap("mods")
		tap("rims")
		picker = find("TrackSkins")
	end
	if not picker then
		problem(`no track skins under the Tomahawk's tracks ({where()})`)
	else
		tap("magma")
		local mbar = find("TrackSkins") and find("TrackSkins"):FindFirstChild("TryBar")
		local mgo = mbar and mbar:FindFirstChild("Go", true)
		local mtext = mgo and mgo:FindFirstChildWhichIsA("TextLabel", true)
		if not mtext or not string.find(mtext.Text, "Lv 44", 1, true) then
			problem(`a locked track skin's bar says {mtext and mtext.Text or "nothing"}`)
		end
		look("tracks-locked", "ModShop", 700)
		tap("hazard")
		look("tracks-try", "ModShop", 700)
		local hbar = find("TrackSkins") and find("TrackSkins"):FindFirstChild("TryBar")
		local hgo = hbar and hbar:FindFirstChild("Go", true)
		if hgo then
			signalFor(hgo, "Activated"):Fire()
		else
			problem("no Put on button for the track skin")
		end
		local worn = carOf("tank-emu").modSkin
		if not worn or worn.tracks ~= "hazard" then
			problem("the track skin didn't stick")
		end
		shot("tracks-on", nil)
	end
	checkCalls("track skins")
	-- The links it recolours on a built Tomahawk: Hazard's yellow and black, pair by pair.
	local Builder = emu.require(RS.Shared.Models.Builder)
	local Skins = emu.require(RS.Shared.Models.Skins)
	local tank = Builder.build("tomahawk")
	if tank then
		tank.Name = "tomahawk"
		Skins.apply(tank, nil, { tracks = "hazard" })
		local yellow, dark = 0, 0
		for _, p in tank:GetDescendants() do
			if p:IsA("BasePart") then
				local hex = string.lower(p.Color:ToHex())
				if hex == "ffcc00" then
					yellow += 1
				elseif hex == "2a2a2a" then
					dark += 1
				end
			end
		end
		print(`track skin: {yellow} yellow and {dark} black link plates`)
		if yellow == 0 or dark == 0 then
			problem("Hazard didn't paint the Tomahawk's links")
		end
	else
		print("track skin: no Tomahawk model in this build to recolour")
	end

	-- The free camera: on, the swoop, a drag, a pinch, the wheel, keys, and back.
	hud.ctx.close()
	local TownCamera = emu.require(client.TownCamera)
	TownCamera.start()
	local cam = game:GetService("Workspace").CurrentCamera
	local function frames(n)
		for _ = 1, n do
			if renderSteps.TownCamera then
				renderSteps.TownCamera(1 / 30)
			end
		end
	end
	-- A crate scene above may still hold the camera.
	TownCamera.setPaused(false)
	local camButton = find("FreeCamButton")
	local face = camButton and camButton:FindFirstChild("Face")
	if not face then
		problem("no free camera button")
	else
		signalFor(face, "Activated"):Fire()
	end
	if not TownCamera.isFree() then
		problem("the free camera didn't come on")
	end
	frames(70)
	local start = cam.CFrame
	if math.abs(cam.FieldOfView - 42) > 0.01 then
		problem(`the free camera's field of view is {cam.FieldOfView}`)
	end
	look("freecam-on")
	local touch = roblox.Enum.UserInputType.Touch
	local a = { UserInputType = touch, KeyCode = roblox.Enum.KeyCode.Unknown, Position = V3.new(400, 300, 0) }
	signalFor(UIS, "InputBegan"):Fire(a, false)
	a.Position = V3.new(520, 340, 0)
	signalFor(UIS, "InputChanged"):Fire(a, false)
	signalFor(UIS, "InputEnded"):Fire(a)
	frames(20)
	local dragged = cam.CFrame
	if (dragged.Position - start.Position).Magnitude < 1 then
		problem("a one-finger drag didn't move the free camera")
	end
	-- Two fingers spread apart: zooms in.
	local p = { UserInputType = touch, KeyCode = roblox.Enum.KeyCode.Unknown, Position = V3.new(500, 400, 0) }
	local q = { UserInputType = touch, KeyCode = roblox.Enum.KeyCode.Unknown, Position = V3.new(700, 400, 0) }
	signalFor(UIS, "InputBegan"):Fire(p, false)
	signalFor(UIS, "InputBegan"):Fire(q, false)
	local function gap()
		return (cam.CFrame.Position - cam.Focus.Position).Magnitude
	end
	local before = gap()
	for i = 1, 6 do
		q.Position = V3.new(700 + i * 30, 400, 0)
		signalFor(UIS, "InputChanged"):Fire(q, false)
	end
	signalFor(UIS, "InputEnded"):Fire(q)
	signalFor(UIS, "InputEnded"):Fire(p)
	frames(30)
	if gap() >= before then
		problem(`a pinch out didn't zoom in ({before} -> {gap()})`)
	end
	-- The wheel zooms out again.
	local zoomed = gap()
	signalFor(UIS, "InputChanged"):Fire({ UserInputType = roblox.Enum.UserInputType.MouseWheel, KeyCode = roblox.Enum.KeyCode.Unknown, Position = V3.new(0, 0, -3) }, false)
	frames(30)
	if gap() <= zoomed then
		problem("the wheel didn't zoom out")
	end
	-- W flies forward.
	local w = { UserInputType = roblox.Enum.UserInputType.Keyboard, KeyCode = roblox.Enum.KeyCode.W, Position = V3.new(0, 0, 0) }
	local was = cam.Focus.Position
	signalFor(UIS, "InputBegan"):Fire(w, false)
	frames(15)
	signalFor(UIS, "InputEnded"):Fire(w)
	frames(15)
	if (cam.Focus.Position - was).Magnitude < 1 then
		problem("W didn't fly the free camera")
	end
	-- Never under the ground.
	if cam.CFrame.Position.Y < cam.Focus.Position.Y then
		problem("the free camera went under the ground")
	end
	shot("freecam-moved", nil)
	-- Escape goes back to the bird's-eye view; the button brings it back, and takes it away again.
	signalFor(UIS, "InputBegan"):Fire({ UserInputType = roblox.Enum.UserInputType.Keyboard, KeyCode = roblox.Enum.KeyCode.Escape, Position = V3.new(0, 0, 0) }, false)
	if TownCamera.isFree() then
		problem("Escape didn't end the free camera")
	end
	frames(2)
	if math.abs(cam.FieldOfView - 30) > 0.01 then
		problem(`back on the bird's-eye view the field of view is {cam.FieldOfView}`)
	end
	if face then
		signalFor(face, "Activated"):Fire()
		frames(5)
		signalFor(face, "Activated"):Fire()
		if TownCamera.isFree() then
			problem("the button didn't take the free camera away again")
		end
	end
	checkCalls("free camera")
	print(`colour, tracks and free camera: {problems} problems`)
	bad += problems
end

-- Help, settings and town tools: Menu > Settings (graphics, the FPS counter, reduce motion and
-- flashing, the "Are you sure?" questions), Menu > Help's flashing warning, every "How to get"
-- sheet and its Show me, the season recap card, a one-time tip and its pulse, a tap tip, the
-- screenshot mode's two buttons, the edit bar's traffic meter and the Sell car question.
-- SHOTS=1 writes build/shot-tools-*.json, wide and on a phone.
do
	hud.ctx.close()
	local Placement = emu.require(client.Placement)
	Placement.cancel()
	Emu.resumeWaits()
	local problems = 0
	local function problem(msg)
		problems += 1
		print(`[tools] PROBLEM {msg}`)
	end
	local Prefs = emu.require(client.Prefs)
	local Fps = emu.require(client.Fps)
	local TapTip = emu.require(client.TapTip)
	local Jobs = emu.require(client.Jobs)
	local Tips = emu.require(client.Popups.Tips)
	local Confirm = emu.require(client.Confirm)
	local trafficRules = emu.require(G.traffic)
	local lighting = game:GetService("Lighting")
	local uis = game:GetService("UserInputService")
	local root = hud.root
	-- The saved settings travel as JSON (server/Prefs), and changes go back on the Prefs remote.
	pcall(roblox.implementMethod, "HttpService", "JSONDecode", function(_, s)
		return serde.decode("json", s)
	end)
	pcall(roblox.implementMethod, "HttpService", "JSONEncode", function(_, v)
		return serde.encode("json", v)
	end)
	if not remotes:FindFirstChild("Prefs") then
		local p = Instance.new("RemoteEvent")
		p.Name = "Prefs"
		p.Parent = remotes
	end
	local toasts = {}
	local toastWas = hud.ctx.toast
	hud.ctx.toast = function(text)
		table.insert(toasts, text)
		toastWas(text)
	end
	local function lastToast()
		local t = toasts[#toasts] or ""
		table.clear(toasts)
		return t
	end
	local function textIn(r, text)
		return find(r, function(d)
			return (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text == text
		end)
	end
	-- Presses the button showing `text` (or holding a label that does).
	local function press(r, text)
		local l = r and textIn(r, text)
		local b = l and (if l:IsA("GuiButton") then l else l:FindFirstAncestorWhichIsA("GuiButton"))
		if not b then
			problem(`no "{text}" button`)
			return false
		end
		signalFor(b, "Activated"):Fire()
		Emu.resumeWaits()
		return true
	end
	-- The switch on the settings row labelled `text`.
	local function switchOf(r, text)
		local l = textIn(r, text)
		return l and l.Parent and l.Parent:FindFirstChildWhichIsA("TextButton")
	end
	local function flip(r, text)
		local sw = switchOf(r, text)
		if not sw then
			problem(`no switch for "{text}"`)
			return
		end
		signalFor(sw, "Activated"):Fire()
		Emu.resumeWaits()
	end
	local function phone(name)
		root.Size = roblox.UDim2.fromOffset(1535, 709)
		shot(`{name}-phone`, nil, 1535, 709)
		root.Size = roblox.UDim2.fromOffset(1280, 800)
	end
	local function panel()
		return root:FindFirstChild("Panel")
	end
	-- The flashing warning comes up once at launch when the settings arrive, waiting for the town
	-- (not over a menu): Got it.
	local launchSeen = false
	local function closeLaunchWarning()
		local w = root:FindFirstChild("FlashWarning")
		if not w then
			return
		end
		launchSeen = true
		print("flashing warning: up at launch, over the town")
		local ok = find(w, function(d)
			return d.Name == "GotIt" and d:IsA("GuiButton")
		end)
		if ok then
			signalFor(ok, "Activated"):Fire()
			Emu.resumeWaits()
		end
		if w.Parent then
			problem("Got it didn't close the launch flashing warning")
		end
	end

	-- The saved settings arrive (as server/Prefs sets them on the player).
	player:SetAttribute("UiPrefs", serde.encode("json", { graphics = "auto", fps = false, flashHide = false, askLeave = true, askSell = true, tips = {} }))
	Prefs.load()
	if not Prefs.loaded then
		problem("the saved settings didn't load")
	end
	-- The flashing warning may come up once they're in (it waits for them at launch).
	for _ = 1, 3 do
		Emu.resumeWaits()
	end
	closeLaunchWarning()
	local fw
	Fps.start()
	TapTip.start()

	-- (Shared by the parts below, each in its own block: this file is out of local slots.)
	local drainPopups, relRects
	do
		-- Menu > Settings.
		hud.openPanel("menu")
		press(panel(), "⚙️ Settings")
		shot("tools-settings")
		phone("tools-settings")
		local saver = find(panel(), function(d)
			return d:IsA("TextButton") and d.Name == "saver" and d.Parent and d.Parent.Name == "Seg"
		end)
		if saver then
			signalFor(saver, "Activated"):Fire()
			Emu.resumeWaits()
		else
			problem("no Saver choice under Graphics")
		end
		print(`settings: graphics {player:GetAttribute("Graphics")}, shadows {lighting.GlobalShadows}, note "{(function()
			local n = find(panel(), function(d)
				return d:IsA("TextLabel") and d.Name == "Note"
			end)
			return n and n.Text or "?"
		end)()}"`)
		if player:GetAttribute("Graphics") ~= "saver" or lighting.GlobalShadows ~= false then
			problem("Saver didn't turn the shadows off")
		end
		local auto = find(panel(), function(d)
			return d:IsA("TextButton") and d.Name == "auto" and d.Parent and d.Parent.Name == "Seg"
		end)
		if auto then
			signalFor(auto, "Activated"):Fire()
			Emu.resumeWaits()
		end
		if player:GetAttribute("Graphics") ~= "auto" or lighting.GlobalShadows ~= true then
			problem("Auto didn't bring the shadows back")
		end
		flip(panel(), "FPS counter")
		local fpsGui = player.PlayerGui:FindFirstChild("Fps")
		print(`settings: FPS counter {if fpsGui and fpsGui.Enabled then "on" else "off"}`)
		if not (fpsGui and fpsGui.Enabled) then
			problem("the FPS counter didn't show")
		end
		flip(panel(), "FPS counter")
		if fpsGui and fpsGui.Enabled then
			problem("the FPS counter didn't hide")
		end
		flip(panel(), "Reduce motion")
		local motion = player:GetAttribute("ReduceMotion")
		flip(panel(), "Reduce motion")
		flip(panel(), "Reduce flashing")
		local calm = player:GetAttribute("CalmFlashing")
		flip(panel(), "Reduce flashing")
		print(`settings: reduce motion -> {motion}, reduce flashing -> {calm}, back to {player:GetAttribute("ReduceMotion")}/{player:GetAttribute("CalmFlashing")}`)
		if motion ~= true or calm ~= true or player:GetAttribute("CalmFlashing") ~= false then
			problem("the accessibility switches didn't set their attributes")
		end
		flip(panel(), "Selling a car")
		local askSell = Confirm.prefs.askSell
		flip(panel(), "Selling a car")
		if askSell ~= false or Confirm.prefs.askSell ~= true then
			problem("Ask first > Selling a car didn't switch")
		end
		-- The changes go back to be kept with the account, a moment later.
		local sent = prefsSent[#prefsSent]
		print(`settings: {#prefsSent} saves sent, last graphics {sent and sent.ui and sent.ui.graphics}`)
		if not (sent and sent.ui and sent.ui.graphics == "auto" and sent.ui.askSell == true) then
			problem("the settings weren't sent to be kept")
		end
	end

	do
		-- Menu > Help: the flashing warning again.
		press(panel(), "❓ Help")
		shot("tools-help")
		press(panel(), "⚡ Photosensitivity warning")
		fw = root:FindFirstChild("FlashWarning")
		if fw then
			shot("tools-flash")
			phone("tools-flash")
			local ok = find(fw, function(d)
				return d.Name == "GotIt" and d:IsA("GuiButton")
			end)
			if ok then
				signalFor(ok, "Activated"):Fire()
				Emu.resumeWaits()
			end
			if fw.Parent then
				problem("Got it didn't close the flashing warning")
			end
			print("help: the flashing warning opened and closed")
		else
			problem("the photosensitivity link didn't open the warning")
		end
		hud.ctx.close()
		Emu.resumeWaits()
	end

	do
		-- Every "How to get" sheet, row by row as the web's (ui/Need.tsx).
		local WANT = {
			coins = { "Run jobs at your businesses", "Open crates", "Search at Rusty's", "Win drag races", "Finish goals", "Help other towns", "Daily bonus" },
			parts = { "Rusty's Rescue searches", "Tire Shop · 6 parts per job (level 2)", "Lube & Go · 8 parts per job (level 4)", "Parts Depot · 15 parts per job (level 5)", "Tuner Shop · 25 parts per job (level 7)", "Daily bonus day 4" },
			fuel = { "Fill up with gems", "Wait for a refill", "Build a Gas Station", "Level up", "Daily bonus day 3" },
			bucks = { "Level up", "Finish goals", "Spin the daily wheel" },
			level = { "Collect from businesses", "Build and buy", "Race", "Goals" },
		}
		for _, res in { "coins", "parts", "fuel", "bucks", "level" } do
			hud.ctx.close()
			hud.openPanel("need", { res = res, missing = if res == "level" then 8 else 25, what = if res == "level" then "The Speedway" else nil })
			local p = panel()
			local titles = {}
			if p then
				for _, d in p:GetDescendants() do
					if d:IsA("Frame") and d.Name == "Source" then
						for _, c in d:GetChildren() do
							if c:IsA("TextLabel") and c.Position.Y.Offset == 7 then
								table.insert(titles, c.Text)
							end
						end
					end
				end
			end
			print(`need {res}: {table.concat(titles, " / ")}`)
			for _, w in WANT[res] do
				local hit = false
				for _, t in titles do
					if t == w or t:sub(1, #w) == w then
						hit = true
					end
				end
				if not hit then
					problem(`the {res} sheet has no "{w}" row`)
				end
			end
			if res == "coins" or res == "fuel" then
				shot(`tools-need-{res}`)
				phone(`tools-need-{res}`)
			end
		end
		-- Show me: back to the town with the businesses' bubbles flashing.
		hud.ctx.close()
		hud.openPanel("need", { res = "coins", missing = 25 })
		press(panel(), "Show me")
		local flashing = {}
		for _, b in towns:snapshot(1).save.buildings do
			if Jobs.flashing(b.def) and not table.find(flashing, b.def) then
				table.insert(flashing, b.def)
			end
		end
		print(`need: Show me -> panel {if panel() then "still open" else "closed"}, flashing {table.concat(flashing, ", ")}, toast "{lastToast()}"`)
		if panel() then
			problem("Show me didn't go back to the town")
		end

		-- Pop-ups queued by the sections before (a level-up, say): closed the way a player would, once
		-- each one's button is in, until `stop` matches the one up.
		local OK = { Continue = true, ["Nice!"] = true, ["Awesome!"] = true, Later = true, Collect = true }
		function drainPopups(stop)
			for _ = 1, 16 do
				local p = root:FindFirstChild("Popup")
				if not p then
					return nil
				end
				if stop and stop(p) then
					return p
				end
				local b = find(p, function(d)
					return d:IsA("TextButton") and d.Name == "Face" and OK[label(d)] == true
				end)
				if b then
					signalFor(b, "Activated"):Fire()
				end
				Emu.resumeWaits()
			end
			return nil
		end
	end

	do
		-- The season recap card, as a new season starts.
		hud.ctx.close()
		Emu.resumeWaits()
		closeLaunchWarning()
		towns:_with(1, function()
			store.useGame.setState({ recap = { n = 3, name = "Season 3", icon = "🌸", races = 14, wins = 9, trophies = 42, coins = 18250, cars = 2, stars = 31, tiers = 4, repFrom = 1, repTo = 2 } })
		end)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		Emu.resumeWaits()
		local recapPop = drainPopups(function(p)
			return p:FindFirstChild("Recap", true) ~= nil
		end)
		if recapPop then
			local stats = {}
			for _, d in recapPop:GetDescendants() do
				if d:IsA("TextLabel") and d.Name == "Value" then
					table.insert(stats, d.Text)
				end
			end
			print(`recap: "{textIn(recapPop, "🌸 Season 3") and "🌸 Season 3" or "?"}", stats {table.concat(stats, " ")}`)
			shot("tools-recap")
			phone("tools-recap")
			press(recapPop, "📤 Share")
			press(recapPop, "On to the new season!")
			if recapPop.Parent then
				problem("the recap card didn't close")
			end
			if towns:snapshot(1).save.recap ~= nil then
				problem("closing the recap didn't clear it on the town")
			end
		else
			problem("the season recap card didn't come up")
		end
	end

	do
		-- A one-time tip over the plain town, with the pulse on what it points at. (The flashing
		-- warning comes up once at launch when the settings arrive, after the menus above: Got it.)
		hud.ctx.close()
		Emu.resumeWaits()
		closeLaunchWarning()
		drainPopups()
		-- The crate depot hides the HUD's corners while it's up; the sections before close its menu in
		-- ways that can leave the left corner (which the HUD itself never hides) hidden: show it again.
		local leftCorner = root:FindFirstChild("Left")
		if leftCorner and not leftCorner.Visible then
			print("tips: (the HUD's left corner was still hidden by an earlier menu; shown again)")
			leftCorner.Visible = true
		end
		relRects = {}
		Gui.onNode = function(g, n)
			relRects[idOf(g)] = n
		end
		Gui.dump(hud.gui, 1280, 800)
		Gui.onNode = nil
		for _, d in root:GetDescendants() do
			local n = d:IsA("GuiObject") and d:GetAttribute("Tut") and relRects[idOf(d)]
			if n then
				d.AbsoluteSize = roblox.Vector2.new(n.abs[3], n.abs[4])
				d.AbsolutePosition = roblox.Vector2.new(n.abs[1], n.abs[2])
			end
		end
		if not Tips.calm({ level = 5, tutorial = 99 }) then
			local Kit = emu.require(client.Popups.Kit)
			local kids = {}
			for _, n in { "Popup", "FlashWarning", "Tutorial", "Panel" } do
				if root:FindFirstChild(n) then
					table.insert(kids, n)
				end
			end
			problem(`a tip wouldn't show over the plain town: panel {tostring(hud.ctx.panel())}, visit {tostring(hud.ctx.visiting)}, edit {tostring(Placement.active())}, pop-up {tostring(Kit.showing())}, hud {tostring(Kit.hudUp())}, over it [{table.concat(kids, ",")}], NeedsPlot {tostring(player:GetAttribute("NeedsPlot"))}`)
		end
		if Tips.calm({ level = 5, tutorial = 4 }) then
			problem("a tip would show during the tutorial")
		end
		if Tips.pick then
			Tips.pick()
		end
		local tipNow = Tips.current()
		if renderSteps.Tips or Tips.frame then
			(renderSteps.Tips or Tips.frame)()
		end
		local card = root:FindFirstChild("Tip")
		local ring = root:FindFirstChild("TipPulse")
		print(`tips: "{tipNow and tipNow.id or "none"}", card {if card then "up" else "none"}, pulse {if ring and ring.Visible then "on" else "off"}`)
		if not tipNow or not card then
			local st = store.useGame.getState()
			problem(`no tip came up over the plain town (calm {tostring(Tips.calm(st))}: level {tostring(st.level)}, tutorial {tostring(st.tutorial)}, visiting {tostring(st.visiting)})`)
		else
			shot("tools-tip")
			phone("tools-tip")
			if not (ring and ring.Visible) then
				local why = {}
				for _, d in hud.gui:GetDescendants() do
					if d:GetAttribute("Tut") == tipNow.target and d:IsA("GuiObject") then
						local hidden = {}
						local p = d
						while p and p ~= hud.gui do
							if p:IsA("GuiObject") and not p.Visible then
								table.insert(hidden, p.Name)
							end
							p = p.Parent
						end
						table.insert(why, `{d:GetFullName()} size {d.AbsoluteSize.X} hidden [{table.concat(hidden, ",")}]`)
					end
				end
				problem(`the tip's pulse isn't on its button ({table.concat(why, "; ")})`)
			end
			if not press(card, if tipNow.go then "Later" else "Got it") then
				Tips.close()
			end
			if renderSteps.Tips or Tips.frame then
				(renderSteps.Tips or Tips.frame)()
			end
			if root:FindFirstChild("Tip") or not Prefs.seen(tipNow.id) then
				problem("closing the tip didn't mark it seen")
			end
			Tips.pick()
			if Tips.current() then
				problem("a second tip came straight after the first")
			end
		end
	end

	do
		-- A tap tip: the fuel refill rate under the fuel gauge.
		local fuelTap = find(root, function(d)
			return d:IsA("TextButton") and d.Name == "TipTap" and d.Parent and tostring(d.Parent:GetAttribute("Tip") or ""):find("^Fuel refill") ~= nil
		end)
		if fuelTap then
			local n = relRects[idOf(fuelTap.Parent)]
			if n then
				fuelTap.Parent.AbsoluteSize = roblox.Vector2.new(n.abs[3], n.abs[4])
				fuelTap.Parent.AbsolutePosition = roblox.Vector2.new(n.abs[1], n.abs[2])
			end
			-- (Read before the waits run: the bubble goes by itself after a few seconds.)
			signalFor(fuelTap, "Activated"):Fire()
			local b = TapTip.showing()
			if b then
				-- Its picture, drawn with the HUD.
				local layer = b.Parent
				b.Parent = hud.gui
				shot("tools-taptip")
				b.Parent = layer
			end
			local words = {}
			if b then
				for _, d in b:GetDescendants() do
					if d:IsA("TextLabel") then
						table.insert(words, d.Text)
					end
				end
			end
			print(`tap tip: {if b then "showing" else "none"} "{table.concat(words, " ")}"`)
			if not b then
				local okShow, err = pcall(TapTip.show, fuelTap.Parent, TapTip.bodyFor("Fuel refill rate"))
				problem(`tapping the fuel rate didn't explain it (tap tips layer {if player.PlayerGui:FindFirstChild("TapTips") then "up" else "missing"}; shown by hand: {okShow} {tostring(err)}; handler errors {table.concat(handlerErrors, " / ")})`)
			end
			TapTip.hide()
		else
			problem("the fuel rate has no tap tip")
		end
		local sk = TapTip.skillBody("launch")
		local loves = TapTip.lovesBody({ "tires", "gas" }, { tires = "🛞", gas = "⛽" })
		if not sk or not loves then
			problem("the skill and loves tips have nothing to say")
		end
	end

	do
		local shotMode = emu.require(client.ShotMode)
		-- Screenshot mode: the shutter hides every menu, a tap brings them back; Save says why not.
		-- (Its buttons come with the free camera, as on the web: the camera button comes with Social
		-- at a higher level.)
		towns:_with(1, function(s)
			store.useGame.setState({ level = math.max(s.level, 20) })
		end)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		Emu.resumeWaits()
		local dock = root:FindFirstChild("ShotDock", true)
		if dock and dock.Visible then
			problem("the screenshot buttons show without the free camera")
		end
		local freeB = find(root, function(d)
			return d:IsA("GuiButton") and d.Parent and d.Parent.Name == "FreeCamButton"
		end) or root:FindFirstChild("FreeCamButton", true)
		local TownCameraM = emu.require(client.TownCamera)
		-- (A crate scene above may still hold the camera.)
		TownCameraM.setPaused(false)
		if freeB then
			signalFor(freeB, "Activated"):Fire()
			Emu.resumeWaits()
		end
		print(`shot mode: free camera {TownCameraM.isFree()}, level {towns:snapshot(1).save.level}`)
		shot("tools-shotdock")
		phone("tools-shotdock")
		local shutter = dock and find(dock, function(d)
			return d:IsA("GuiButton") and d.Parent and d.Parent.Name == "ShotShutter"
		end)
		local saveB = dock and find(dock, function(d)
			return d:IsA("GuiButton") and d.Parent and d.Parent.Name == "ShotSave"
		end)
		if not (dock and dock.Visible and shutter and saveB) then
			problem(`the screenshot buttons aren't by the camera button: dock {if dock then (if dock.Visible then "shown" else "hidden") else "none"}, shutter {shutter ~= nil}, save {saveB ~= nil}`)
		else
			signalFor(shutter, "Activated"):Fire()
			Emu.resumeWaits()
			print(`shot mode: on {shotMode.active()}, HUD {if hud.gui.Enabled then "showing" else "hidden"}, hint {if player.PlayerGui:FindFirstChild("Shot") then "up" else "none"}`)
			if not shotMode.active() or hud.gui.Enabled then
				problem("the shutter didn't hide the menus")
			end
			local tapIn = { UserInputType = roblox.Enum.UserInputType.Touch, KeyCode = roblox.Enum.KeyCode.Unknown, Position = roblox.Vector3.new(640, 300, 0) }
			signalFor(uis, "InputBegan"):Fire(tapIn, false)
			signalFor(uis, "InputEnded"):Fire(tapIn, false)
			Emu.resumeWaits()
			if shotMode.active() or not hud.gui.Enabled then
				problem("a tap didn't bring the menus back")
				shotMode.exit()
			end
			signalFor(saveB, "Activated"):Fire()
			-- (It waits two frames with the menus off before taking the picture.)
			for _ = 1, 3 do
				Emu.resumeWaits()
			end
			local said = lastToast()
			print(`shot mode: Save -> "{said}", HUD {if hud.gui.Enabled then "showing" else "hidden"}`)
			if said == "" or not hud.gui.Enabled then
				problem("Save said nothing or left the menus hidden")
			end
		end
		if freeB then
			signalFor(freeB, "Activated"):Fire()
			Emu.resumeWaits()
		end
		if dock and dock.Visible then
			problem("the screenshot buttons stayed after the free camera went off")
		end
	end

	do
		-- The traffic meter in the edit bar.
		hud.openPanel("edit")
		Emu.resumeWaits()
		local meter = root:FindFirstChild("Traffic", true)
		local st = store.useGame.getState()
		towns:_with(1, function(s)
			st = s
		end)
		if meter and meter.Visible then
			local share = trafficRules.roadShare(st.roads, st.land)
			local short = trafficRules.roadsShort(st.roads, st.land)
			local want = if short > 0 then `+{short} 🛣️` else `{math.round(share * 100)}%`
			local lvl = find(meter, function(d)
				return d.Name == "Level"
			end)
			local small = find(meter, function(d)
				return d.Name == "Share"
			end)
			print(`traffic: "{lvl and lvl.Text}" "{small and small.Text}" (roads {math.round(share * 100)}%)`)
			if not small or small.Text ~= want or not lvl or lvl.Text ~= trafficRules.TRAFFIC[trafficRules.trafficLevel(share)].name then
				problem(`the traffic meter says "{small and small.Text}", not "{want}"`)
			end
			shot("tools-traffic")
			phone("tools-traffic")
			hud.ctx.close()
			Placement.cancel()
			hud.openPanel("edit", "land")
			Emu.resumeWaits()
			if meter.Parent and meter.Visible then
				problem("the traffic meter shows while buying land")
			end
		else
			problem("no traffic meter in the edit bar")
		end
		hud.ctx.close()
		Placement.cancel()
		Emu.resumeWaits()
	end

	do
		-- Selling a car asks first.
		hud.openPanel("cars", "garage")
		local cp = panel()
		local sellB = cp and find(cp, function(d)
			local l = d:IsA("TextButton") and d:FindFirstChildWhichIsA("TextLabel")
			return l and l.Text:sub(1, 10) == "Sell for $"
		end)
		local carsBefore = #towns:snapshot(1).save.cars
		if sellB then
			signalFor(sellB, "Activated"):Fire()
			Emu.resumeWaits()
			local modal = cp:FindFirstChild("Confirm", true)
			if modal then
				shot("tools-sell")
				phone("tools-sell")
				local no = find(modal, function(d)
					return d.Name == "Cancel" and d:IsA("GuiButton")
				end)
				if no then
					signalFor(no, "Activated"):Fire()
					Emu.resumeWaits()
				end
				if modal.Parent or #towns:snapshot(1).save.cars ~= carsBefore then
					problem("Cancel didn't close the Sell question, or the car went")
				end
				print("sell: asked first, cancelled")
			else
				problem("selling a car didn't ask first")
			end
		else
			print("sell: no car to sell here")
		end
	end

	hud.ctx.close()
	Emu.resumeWaits()
	hud.ctx.toast = toastWas
	print(`help, settings and town tools: {problems} problems`)
	bad += problems
end

-- Live events and the season's look (client/LiveBanner, client/SeasonLook): the owner starts a
-- banner from the admin panel's server side, every player's screen pins it under the top bar and
-- toasts it once; ending it takes it away. Then the town's greenery is shown in each season and
-- back in the real one.
do
	local problems = 0
	local function problem(msg)
		problems += 1
		print("PROBLEM live/season: " .. msg)
	end
	pcall(roblox.implementMethod, "HttpService", "JSONDecode", function(_, s)
		return serde.decode("json", s)
	end)
	local ws = game:GetService("Workspace")
	local LiveBanner = emu.require(client.LiveBanner)
	LiveBanner.start()
	Emu.resumeWaits()
	local ok, id = adminCall("liveStart", "banner", 15, { message = "Grand opening on Main Street tonight!" })
	if not ok then
		problem(`the owner couldn't start a banner ({tostring(id)})`)
	end
	-- Attribute change signals never fire here: hand the change over as Roblox would.
	local hudGui = player.PlayerGui:FindFirstChild("Cartopia")
	local function bannerShown()
		return hudGui and hudGui:FindFirstChild("LiveBanner", true)
	end
	LiveBanner._refresh()
	Emu.resumeWaits()
	local b = bannerShown()
	if not b then
		problem("the banner didn't show")
	else
		local msg = b:FindFirstChild("Message", true)
		if not msg or msg.Text ~= "Grand opening on Main Street tonight!" then
			problem("the banner's message is wrong")
		end
		if b.Size.X.Offset > 560 or b.Size.X.Offset < 100 then
			problem(`the banner is {b.Size.X.Offset} wide`)
		end
		print(`live banner: shown, {b.Size.X.Offset}x{b.Size.Y.Offset}`)
	end
	if SHOTS then
		local fs = require("@lune/fs")
		local Gui = require("./gui")
		fs.writeFile("build/shot-live-banner-gui.json", serde.encode("json", { nodes = Gui.dump(hudGui, 1280, 800), bubbles = {} }))
	end
	-- A long one wraps, still within the web's 560.
	adminCall("liveStart", "banner", 5, { message = string.rep("Big race at the speedway! ", 5) })
	LiveBanner._refresh()
	b = bannerShown()
	if not b or b.Size.X.Offset > 560 or b.Size.Y.Offset < 50 then
		problem("a long banner didn't wrap inside 560")
	end
	-- Someone else can't, and ending it takes it down.
	local Admin = emu.require(SSS.Server.Admin)
	local stranger = { UserId = 999 }
	local refused = Admin.new({ live = {}, now = function()
		return NOW
	end }):run(stranger, "liveStart", "banner", 15, { message = "Hi" })
	if refused then
		problem("someone who isn't the owner started a live event")
	end
	adminCall("liveEnd", nil)
	LiveBanner._refresh()
	Emu.resumeWaits()
	if bannerShown() then
		problem("the banner stayed after it ended")
	end
	-- The weather and night kinds reach the converted game code the town follows.
	adminCall("liveStart", "night", 15, {})
	LiveBanner._refresh()
	local live = emu.require(RS.Shared.Game.liveEvents)
	if not live.activeEvent({ "night" }) then
		problem("a live night didn't reach game/liveEvents")
	end
	adminCall("liveEnd", nil)
	LiveBanner._refresh()

	-- The season's look: every season, then the real one, without errors.
	local SeasonLook = emu.require(client.SeasonLook)
	local ran, err = pcall(function()
		SeasonLook.start()
		Emu.resumeWaits()
		for _, name in { "winter", "spring", "summer", "fall" } do
			SeasonLook.set(name)
		end
		SeasonLook.set(nil)
	end)
	if not ran then
		problem(`the season look failed: {err}`)
	end
	-- What only another season has: snow and bare twigs on the town's oaks in winter (their canopy
	-- hidden), the lawn's wildflowers in spring, and neither in the fall. Stand-in boxes count as
	-- meshes here, as the preview tools draw them.
	local Builder = emu.require(RS.Shared.Models.Builder)
	local preview = Builder.previewMeshes
	Builder.previewMeshes = true
	local function count(): (number, number, number, number, number)
		local trees, dressed, hidden, lawns, blooms = 0, 0, 0, 0, 0
		for _, d in ws:GetDescendants() do
			if d:IsA("Model") and d:GetAttribute("Def") == "tree" and not d:GetAttribute("Merged") then
				trees += 1
				if d:FindFirstChild("Season") then
					dressed += 1
				end
				for _, p in d:GetChildren() do
					if p:IsA("BasePart") and p:GetAttribute("Hide") and p.Transparency >= 1 then
						hidden += 1
					end
				end
			elseif d:IsA("Folder") and d.Name == "Lawn" and (d:GetAttribute("Blooms") or "") ~= "" then
				lawns += 1
				if d:FindFirstChild("Blooms") then
					blooms += 1
				end
			end
		end
		return trees, dressed, hidden, lawns, blooms
	end
	-- An oak and a patch of lawn as server/TownView leaves them, so there is something to check.
	local stage = Instance.new("Folder")
	stage.Name = "SeasonStage"
	stage.Parent = ws
	local oak = Builder.build("tree@1")
	if oak then
		oak:SetAttribute("Def", "tree")
		oak:SetAttribute("Level", 1)
		oak:SetAttribute("Base", roblox.CFrame.new(40, 0, 40))
		oak.Parent = stage
	else
		problem("no tree@1 model")
	end
	local lawn = Instance.new("Folder")
	lawn.Name = "Lawn"
	lawn.Parent = stage
	lawn:SetAttribute("Blooms", "40.00,0.40,44.00,0,0.900,1;42.00,0.40,45.00,3,1.000,3")
	local ran2, err2 = pcall(function()
		SeasonLook._scan(stage)
		SeasonLook.set("winter")
		local trees, dressed, hidden, lawns = count()
		if trees == 0 or lawns == 0 then
			problem(`nothing to check: {trees} oaks, {lawns} lawns`)
		end
		if trees > 0 and (dressed < trees or hidden == 0) then
			problem(`winter: {dressed} of {trees} oaks got snow, {hidden} canopy parts hidden`)
		end
		SeasonLook.set("spring")
		local _, sDressed, sHidden, _, blooms = count()
		if lawns > 0 and blooms < lawns then
			problem(`spring: {blooms} of {lawns} lawns grew wildflowers`)
		end
		-- (Only the fallen leaves stay hidden in spring.)
		if sDressed > 0 or sHidden >= hidden then
			problem(`spring kept the winter oaks ({sDressed} dressed, {sHidden} parts hidden)`)
		end
		SeasonLook.set("fall")
		local _, fDressed, _, _, fBlooms = count()
		if fDressed > 0 or fBlooms > 0 then
			problem("the fall kept another season's pieces")
		end
		print(`season pieces: {dressed}/{trees} oaks dressed in winter ({hidden} parts hidden), {blooms}/{lawns} lawns in bloom in spring`)
		SeasonLook.set(nil)
	end)
	stage.Parent = nil
	Builder.previewMeshes = preview
	if not ran2 then
		problem(`the season pieces failed: {err2}`)
	end
	print(`live events and season look: {problems} problems`)
	bad += problems
end
