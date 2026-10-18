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
for _, kind in { "Cars", "Buildings" } do
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
		elseif op == "start" and type(arg) == "table" then
			return races:start(1, arg.mode, arg.which)
		elseif op == "finish" then
			return races:finish(1, arg)
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
	fs.writeFile(`build/shot-{name}.json`, serde.encode("json", { parts = parts }))
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
if SHOTS then
	for _, t in { "hub", "quick", "campaign" } do
		hud.ctx.close()
		hud.openPanel("race", t)
		shot(`menu-{t}`, nil)
	end
	hud.ctx.close()
	hud.openPanel("book")
	shot("book", nil)
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
		local t = tabs and tabs:FindFirstChild(id)
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
renderSteps = {}
hud.ctx.close()
local coinsBefore = towns:snapshot(1).save.coins
calls = {}
handlerErrors = {}
hud.openPanel("race", "quick")
local go = find(hud.gui, function(d)
	return d:IsA("TextButton") and d.Visible and string.find(label(d), "🏁 %$") ~= nil
end)
assert(go, "no race button on the Quick Race page")
signalFor(go, "Activated"):Fire()
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
	if frames == 60 or frames == 150 or frames == 330 or frames == 480 then
		shot(`race-{frames}`, game.Workspace:FindFirstChild("DragStrip"))
	end
	result = find(screen, function(d) return d.Name == "Result" end)
	if result then
		shot("race-result", game.Workspace:FindFirstChild("DragStrip"))
		break
	end
end
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
