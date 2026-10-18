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
for _, pair in { { "GuiButton", "Activated" }, { "GuiButton", "MouseButton1Down" }, { "GuiButton", "MouseButton1Up" }, { "Instance", "Destroying" }, { "BindableEvent", "Event" }, { "RemoteEvent", "OnClientEvent" }, { "TextBox", "FocusLost" }, { "GuiObject", "InputBegan" }, { "UserInputService", "InputBegan" }, { "UserInputService", "InputEnded" } } do
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

local player = Instance.new("Player")
player.Name = "Player1"
player.UserId = 1
pcall(function() player.DisplayName = "Player1" end)
Instance.new("PlayerGui").Parent = player
local players = game:GetService("Players")
players.LocalPlayer = player
player.Parent = players
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return NOW / 1000
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
local crateDesk = emu.require(SSS.Server.Crates).new(towns, store, emu.require(G.crates))
roblox.implementMethod("RemoteFunction", "InvokeServer", function(remote, name, ...)
	if remote.Name == "Race" then
		return raceDesk(name, ...)
	elseif remote.Name == "Meshes" then
		-- Every mesh is already here in the previews.
		return true
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

local bad, total, silent = 0, 0, 0
local function clickAll(label, open)
	open()
	local n = #buttons(hud.gui)
	for i = 1, n do
		hud.ctx.close()
		open()
		local b = buttons(hud.gui)[i]
		if not b then
			continue
		end
		total += 1
		local where = path(b, hud.gui)
		calls = {}
		handlerErrors = {}
		local wired = next(signalFor(b, "Activated").fns) ~= nil
		local shape = {}
		for _, d in hud.gui:GetDescendants() do
			if d:IsA("GuiObject") and d.Visible then
				shape[d] = true
			end
		end
		local beforeN = #hud.gui:GetDescendants()
		local beforeText = {}
		for _, d in hud.gui:GetDescendants() do
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
		elseif not wired then
			silent += 1
			print(`[{label}] not wired: {where}`)
		end
		if VERBOSE and ok and wired then
			local afterText = {}
			for _, d in hud.gui:GetDescendants() do
				if d:IsA("TextLabel") then
					table.insert(afterText, d.Text)
				end
			end
			local changed = #hud.gui:GetDescendants() ~= beforeN or table.concat(afterText, "|") ~= table.concat(beforeText, "|")
			print(`[{label}] {if changed or #calls > 0 then "does something" else "NO VISIBLE EFFECT"}: {where} {table.concat(calls, ", ")}`)
		end
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
for _, p in { "shop", "cars", "garage", "showroom", "goals", "menu", "inventory", "race", "book", "crates", "rescue" } do
	clickAll(p, function()
		hud.openPanel(p)
	end)
end
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
print(`{total} buttons pressed, {bad} problems, {silent} not wired`)

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Gui = require("./gui")
local function shot(name, world)
	if not SHOTS then
		return
	end
	local parts = {}
	if world then
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, Gui.partOf(d))
			end
		end
	end
	-- Lighting's fog, when a race has set it (Roblox draws it only with no Atmosphere in Lighting).
	local lighting = game:GetService("Lighting")
	local fog = if lighting.FogEnd < 10000 and not lighting:FindFirstChildOfClass("Atmosphere")
		then { color = lighting.FogColor:ToHex(), start = lighting.FogStart, ["end"] = lighting.FogEnd }
		else nil
	fs.writeFile(`build/shot-{name}.json`, serde.encode("json", { parts = parts, fog = fog }))
	local toasts = hud.gui:FindFirstChild("Toasts", true)
	if toasts then
		for _, t in toasts:GetChildren() do
			if t:IsA("GuiObject") then
				t:Destroy()
			end
		end
	end
	local raceGui = player.PlayerGui:FindFirstChild("Race")
	fs.writeFile(`build/shot-{name}-gui.json`, serde.encode("json", { nodes = Gui.dump(raceGui or hud.gui, 1280, 800), bubbles = {} }))
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
	signalFor(walkButton, "Activated"):Fire()
	assert(game.Workspace.CurrentCamera.CameraType == roblox.Enum.CameraType.Custom, "walking didn't hand the camera to the avatar")
	signalFor(walkButton, "Activated"):Fire()
	assert(game.Workspace.CurrentCamera.CameraType == roblox.Enum.CameraType.Scriptable, "the town view didn't come back")
	print("walk: on and off")
end
if SHOTS then
	for _, p in { "shop", "goals", "menu", "cars" } do
		hud.ctx.close()
		hud.openPanel(p)
		shot(`panel-{p}`, nil)
	end
	for _, t in { "hub", "quick", "campaign", "rivals" } do
		hud.ctx.close()
		hud.openPanel("race", t)
		shot(`menu-{t}`, nil)
	end
	hud.ctx.close()
	hud.openPanel("book")
	shot("book", nil)
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
	for _, d in (depot and depot:GetDescendants() or {}) do
		if d:IsA("TextLabel") and d.Text:find("^×10") then
			signalFor(d.Parent, "Activated"):Fire()
			Emu.resumeWaits()
			Emu.resumeWaits()
			shot("crate-ten", nil)
			break
		end
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
	press("suburbs")
	for i = 1, 3 do
		local q = towns:snapshot(1).search
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		if q and not q.flat then
			press(`Tarp{i}`)
		end
	end
	shot("rescue-search", nil)
	if towns:snapshot(1).search and towns:snapshot(1).search.flat then
		press("FixTruck")
	end
	press("TowHome")
	shot("rescue-haul", nil)
	towns:_with(1, function(s)
		store.useGame.setState({ restoring = { uid = "r1", model = "bug", rarity = "common", minutes = 5, endsAt = 0 } })
	end)
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
	hud.ctx.close()
	hud.openPanel("rescue")
	tabTo("storage")
	press("Collect")
	shot("rescue-plate", nil)
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
local function modeRace(tag, mini, go, shotAt)
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
	closeRace()
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
