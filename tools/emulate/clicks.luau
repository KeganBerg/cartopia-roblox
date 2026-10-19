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
for _, pair in { { "GuiButton", "Activated" }, { "RunService", "RenderStepped" }, { "GuiButton", "MouseButton1Down" }, { "GuiButton", "MouseButton1Up" }, { "Instance", "Destroying" }, { "Instance", "ChildAdded" }, { "BindableEvent", "Event" }, { "RemoteEvent", "OnClientEvent" }, { "TextBox", "FocusLost" }, { "GuiObject", "InputBegan" }, { "GuiObject", "InputChanged" }, { "UserInputService", "InputBegan" }, { "UserInputService", "InputChanged" }, { "UserInputService", "InputEnded" } } do
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
roblox.implementMethod("RemoteEvent", "FireServer", function(remote, event, payload)
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
	local ran, result, why = pcall(function()
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
		elseif op == "keep" then
			races:keep(1)
			return true, nil
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
	leaders:record(d[1], d[2], d[3], { power = d[4], race_wins = d[5], trophies = d[6], level = d[7] })
	local _ = i
end
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
			return { rows = rows, mine = mine }, nil
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
roblox.implementMethod("RemoteFunction", "InvokeServer", function(remote, name, ...)
	if remote.Name == "Social" then
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
local function shot(name, world, w, h)
	if not SHOTS then
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
	fs.writeFile(`build/shot-{name}.json`, serde.encode("json", { parts = parts, fog = fog, lights = lights, room = room }))
	local toasts = hud.gui:FindFirstChild("Toasts", true)
	if toasts then
		for _, t in toasts:GetChildren() do
			if t:IsA("GuiObject") then
				t:Destroy()
			end
		end
	end
	local raceGui = player.PlayerGui:FindFirstChild("Race") or player.PlayerGui:FindFirstChild("DailySpin")
	if name:find("^depot%-") or name:find("^page%-") or name:find("^panel%-") then
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
	-- The Leaderboards tab (the trophy pill and Top racers open it).
	hud.openPanel("friends", "leaders")
	local boardRows = 0
	for _, d in hud.gui:GetDescendants() do
		if d:IsA("TextLabel") and string.find(d.Text, "Kai", 1, true) then
			boardRows += 1
		end
	end
	assert(boardRows > 0, "the leaderboard shows no rows")
	shot("panel-leaders", nil)
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
	local paintBar = paintShop and paintShop:FindFirstChild("TryBar")
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
	press("suburbs")
	assert(hud.gui:FindFirstChild("Coach", true), "no coach on a fresh search")
	shot("rescue-search-start", nil)
	for i = 1, 3 do
		local q = towns:snapshot(1).search
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		if q and not q.flat then
			press(`Tarp{i}`)
		end
	end
	shot("rescue-search", nil)
	-- The next find pops up over the lot (before time moves on and it fades).
	do
		local q = towns:snapshot(1).search
		if q and not q.flat then
			for i, r in q.revealed do
				if not r then
					local t = hud.gui:FindFirstChild(`Tarp{i}`, true)
					signalFor(t, "Activated"):Fire()
					break
				end
			end
			if not towns:snapshot(1).search.flat then
				assert(hud.gui:FindFirstChild("Found", true), "no find pop-up")
				shot("rescue-found", nil)
			end
		end
	end
	-- Leave with a haul aboard asks first; Cancel keeps the search going.
	do
		local q = towns:snapshot(1).search
		if q and q.flat then
			press("FixTruck")
		end
		local leave = hud.gui:FindFirstChild("Leave", true)
		signalFor(leave:FindFirstChild("Face") or leave, "Activated"):Fire()
		local ask = hud.gui:FindFirstChild("Confirm", true)
		assert(ask, "Leave with a haul didn't ask")
		shot("rescue-leave", nil)
		press("Cancel")
		assert(towns:snapshot(1).search, "Cancel left the lot")
		assert(not hud.gui:FindFirstChild("Confirm", true), "Cancel didn't close the question")
	end
	-- Search all turns into Stop while it runs.
	do
		local all = hud.gui:FindFirstChild("SearchAll", true)
		if all then
			signalFor(all, "Activated"):Fire()
			local again = hud.gui:FindFirstChild("SearchAll", true)
			local l = again and again:FindFirstChildWhichIsA("TextLabel", true)
			assert(not again or (l and l.Text:find("Stop")), "Search all didn't turn into Stop")
			if again then
				signalFor(again, "Activated"):Fire()
			end
		end
	end
	if towns:snapshot(1).search and towns:snapshot(1).search.flat then
		press("FixTruck")
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
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	end
	press("TowHome")
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
local function runRace(tag, shotAt, start)
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

-- The rival in town: race them from the front page, then double or nothing.
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
local double = cardButton("Double or nothing")
if double then
	local coins = towns:snapshot(1).save.coins
	signalFor(double, "Activated"):Fire()
	Emu.resumeWaits()
	local bf, _, bres = runRace("bet", { [60] = true }, false)
	print(`double or nothing: {bf} frames, coins {coins} -> {towns:snapshot(1).save.coins}; card: {cardText(bres)}`)
	local done = cardButton("Collect") or cardButton("Back")
	if done then
		signalFor(done, "Activated"):Fire()
		Emu.resumeWaits()
	end
else
	print("town rival: no double or nothing offered")
end
print(`rival calls: {table.concat(calls, ", ")} {table.concat(handlerErrors, "; ")}`)

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
	local CLOSE = { Continue = true, ["Nice!"] = true, ["Awesome!"] = true, Later = true, ["Let's go!"] = true }
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
		})
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	Emu.resumeWaits()
	local seen = {}
	for _ = 1, 8 do
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
	assert(#seen == 6, `expected 6 pop-ups, saw {#seen}`)
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
		Gui.dump(hud.gui, cam.ViewportSize.X, cam.ViewportSize.Y)
		if race then
			Gui.dump(race, cam.ViewportSize.X, cam.ViewportSize.Y)
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
	local CLOSE = { Continue = true, ["Nice!"] = true, ["Awesome!"] = true, Later = true }
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
		return (race and race:FindFirstChild("RaceScreen")) or hud.root
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
	for i = 1, 3000 do
		relayout()
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
			assert(#fx.beams == 12, "no rainbow after the shower")
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
