--!nocheck
-- Pictures the Arcade on a phone (390x844, touch) in the emulator: the hub, Parking Pro's lots,
-- the weekly boards, a Getaway Chase round, a Parking Pro round and their result cards, each run
-- against the real server (server/Arcade). Writes build/shot-arcade-<name>.json, -gui.json and
-- -cam.json for render.mjs.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/arcade.luau build/place.rbxl
--   CHROMIUM=... SIZE=390x844 node tools/emulate/render.mjs <web repo> build/shot-arcade-hub.json \
--     out.png build/shot-arcade-hub-gui.json "$(cat build/shot-arcade-hub-cam.json)"

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance, Vector2 = roblox.Instance, roblox.Vector2

-- Real signals, one per instance and event, so presses can be fired.
local nextId = 0
local signals = {}
local errors = {}
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
		for _, fn in table.clone(fns) do
			local ok, err = pcall(fn, ...)
			if not ok then
				table.insert(errors, `{name}: {err}`)
			end
		end
	end
	signals[key] = s
	return s
end
for _, pair in { { "GuiButton", "Activated" }, { "GuiButton", "MouseButton1Down" }, { "GuiButton", "MouseButton1Up" }, { "BindableEvent", "Event" }, { "RemoteEvent", "OnClientEvent" }, { "GuiObject", "InputBegan" }, { "GuiObject", "InputEnded" }, { "UserInputService", "InputBegan" }, { "UserInputService", "InputChanged" }, { "UserInputService", "InputEnded" } } do
	roblox.implementProperty(pair[1], pair[2], function(inst)
		return signalFor(inst, pair[2])
	end)
end

roblox.implementMethod("BindableEvent", "Fire", function(inst, ...)
	signalFor(inst, "Event"):Fire(...)
end)

local Emu = require("./roblox")
local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
-- Wednesday 2026-10-14 12:00 UTC: mid-week, so the weekly board has a few days on it.
local NOW = 1791979200000
local Js = emu.require(RS.Shared.Game.__js)
Js.setClock(function()
	return NOW
end)
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return NOW / 1000
end)
local G = RS.Shared.Game
local store = emu.require(G.store)
local Towns = emu.require(SSS.Server.Towns)
local towns = Towns.new(store, function()
	return NOW
end)

-- The server's clock (start gaps, run times), moved on by hand.
local t = 1000
local Arcade = emu.require(SSS.Server.Arcade)
local Boards = emu.require(SSS.Server.Boards)
local boards = {}
for _, g in Arcade.BOARD_GAMES do
	boards[g] = Boards.new(`Arcade_{g}`, nil, function()
		return t
	end)
end
local rolls = 0
local arcade = Arcade.new(towns, {
	store = store,
	data = emu.require(G.data),
	arcade = emu.require(G.arcade),
	arcadeMore = emu.require(G.arcadeMore),
	trial = emu.require(G.trial),
	boards = boards,
	clock = function()
		return t
	end,
	now = function()
		return NOW
	end,
	random = function()
		rolls += 1
		return (rolls * 0.618034) % 1
	end,
})

-- The player's town: level 12 with fuel, a Pixel Palace and two cars. Some neighbours have played
-- this week, so the board has rows on it.
local function setUp(id, level)
	towns:open(id, nil)
	towns:_with(id, function()
		store.useGame.setState({ level = level, fuel = 100, coins = 500000 })
	end)
end
setUp(1, 12)
pcall(towns.run, towns, 1, "placeBuilding", "arcade", 14, 12)
towns:run(1, "buyCar", "pip", "#1e5fbf")
pcall(towns.run, towns, 1, "buyCar", "hotshot", "#c62828")
for id = 2, 6 do
	setUp(id, 8 + id)
	towns:run(id, "buyCar", "pip", "#c62828")
	local ok = arcade:start(id, "chase")
	if ok then
		t += 90
		local score = 900 + id * 430
		local okSubmit, why = arcade:submit(id, "chase", score, { dist = score * 0.6, coins = 10, bonus = 0 })
		if not okSubmit then
			print(`neighbour {id}: {why}`)
		end
	end
	t += 5
end

-- The client.
local player = Instance.new("Player")
player.Name = "Player1"
player.UserId = 1
pcall(function()
	player.DisplayName = "Player1"
end)
Instance.new("PlayerGui").Parent = player
local players = game:GetService("Players")
players.LocalPlayer = player
player.Parent = players
local remotes = Instance.new("Folder")
remotes.Name = "Cartopia"
local function make(class, name)
	local i = Instance.new(class)
	i.Name = name
	i.Parent = remotes
	return i
end
make("RemoteFunction", "Act")
local townEvent = make("RemoteEvent", "Town")
make("RemoteFunction", "Race")
make("RemoteFunction", "Crate")
make("RemoteFunction", "Arcade")
make("RemoteFunction", "Meshes")
make("RemoteFunction", "Social")
make("RemoteFunction", "WebLink")
make("RemoteEvent", "Kart")
remotes.Parent = RS
local calls = {}
roblox.implementMethod("RemoteFunction", "InvokeServer", function(remote, op, a, b, c)
	if remote.Name == "Arcade" then
		local ran, result, why = pcall(function()
			if op == "state" then
				return arcade:state(1), nil
			elseif op == "start" then
				return arcade:start(1, a, b)
			elseif op == "submit" then
				return arcade:submit(1, a, b, c)
			elseif op == "board" then
				return arcade:board(1, a)
			elseif op == "prizes" then
				return arcade:prizes(1), nil
			elseif op == "claim" then
				return arcade:claim(1, a, b)
			end
			return nil, "not an arcade call"
		end)
		if not ran then
			table.insert(calls, `SERVER ERROR arcade {op}: {result}`)
			return false, "error"
		end
		if op == "start" or op == "submit" or op == "claim" then
			signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		end
		table.insert(calls, `arcade {op}: {if result == nil then "refused " .. tostring(why) else "ok"}`)
		if result == nil then
			return false, why
		end
		return true, result
	elseif remote.Name == "Act" then
		local ran, result = pcall(towns.run, towns, 1, op, a, b, c)
		signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
		return ran, result
	end
	return false, "not here"
end)

-- Render steps, run by hand.
local renderSteps = {}
roblox.implementMethod("RunService", "BindToRenderStep", function(_, name, _, fn)
	renderSteps[name] = fn
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_, name)
	renderSteps[name] = nil
end)
local function run(seconds)
	for _ = 1, math.floor(seconds * 30 + 0.5) do
		t += 1 / 30
		for _, fn in table.clone(renderSteps) do
			fn(1 / 30)
		end
	end
	Emu.resumeWaits()
end

-- The model library, as the server builds it, with the real meshes.
local Builder = emu.require(RS.Shared.Models.Builder)
Builder.previewMeshes = true
local data = emu.require(G.data)
local lib = Instance.new("Folder")
lib.Name = "ModelLibrary"
lib:SetAttribute("Ready", true)
for _, kind in { "Cars", "Buildings", "Stripes" } do
	local f = Instance.new("Folder")
	f.Name = kind
	f.Parent = lib
end
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
lib.Parent = RS

-- A phone held upright, with a touch screen.
local W, H = 390, 844
local cam = game.Workspace.CurrentCamera
cam.ViewportSize = Vector2.new(W, H)
game:GetService("UserInputService").TouchEnabled = true

local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
emu.require(client.Remote)
signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
local hud = emu.require(client.Hud).start()
Emu.resumeWaits()

local Gui = require("./gui")
local function shot(name, world, screenGui)
	local parts = {}
	if world then
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, Gui.partOf(d))
			end
		end
	end
	fs.writeFile(`build/shot-arcade-{name}.json`, serde.encode("json", { parts = parts }))
	fs.writeFile(`build/shot-arcade-{name}-gui.json`, serde.encode("json", { nodes = Gui.dump(screenGui or hud.gui, W, H), bubbles = {} }))
	local cf = cam.CFrame
	local at = cf.Position + cf.LookVector * 50
	fs.writeFile(`build/shot-arcade-{name}-cam.json`, serde.encode("json", { from = { cf.Position.X, cf.Position.Y, cf.Position.Z }, at = { at.X, at.Y, at.Z }, fov = cam.FieldOfView }))
	print(`shot {name}: {#parts} parts`)
end

-- The button whose label reads `text` (a plain find), under root.
local function button(root, text)
	for _, d in root:GetDescendants() do
		if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Name ~= "Face" and string.find(d.Text, text, 1, true) then
			local p = d
			while p and p ~= root do
				if p:IsA("GuiButton") then
					return p
				end
				p = p.Parent
			end
		end
	end
	error(`no button "{text}"`)
end
local function press(b)
	signalFor(b, "Activated"):Fire()
	Emu.resumeWaits()
end
local function arcadeGui()
	return player.PlayerGui:FindFirstChild("ArcadeGame")
end

-- The hub, Parking Pro's lots and the weekly boards.
hud.openPanel("arcade")
Emu.resumeWaits()
shot("hub", nil)
press(button(hud.gui, "Pick a lot"))
shot("lots", nil)
press(button(hud.gui, "Back"))
press(button(hud.gui, "Weekly"))
shot("boards", nil)
hud.ctx.close()

-- A Getaway Chase round, a few seconds in, dodging now and then; then busted.
hud.openPanel("arcade")
Emu.resumeWaits()
press(button(hud.gui:FindFirstChild("chase", true), "Play"))
local Chase = emu.require(client.ArcadeGames.Chase)
assert(arcadeGui() and Chase.debug, "Getaway Chase didn't start")
run(1.2)
shot("chase-count", game.Workspace:FindFirstChild("ArcadeChase"), arcadeGui())
run(1.6)
for i = 1, 8 do
	table.insert(Chase.debug.moves, if i % 3 == 0 then -1 else 1)
	run(0.9)
end
shot("chase", game.Workspace:FindFirstChild("ArcadeChase"), arcadeGui())
local st = Chase.debug.state
print(`chase: {math.floor(st.dist)} m, {st.got} coins, {st.hearts} hearts, bonus {st.bonus}`)
st.over = true
st.overAt = st.clock
run(2)
shot("chase-result", nil, arcadeGui())
press(button(arcadeGui(), "Back"))

-- A Parking Pro round on Easy Street: drive up to the spot, then brake into it.
hud.openPanel("arcade", { view = "lots" })
Emu.resumeWaits()
press(button(hud.gui, "Easy Street"))
local Park = emu.require(client.ArcadeGames.Park)
assert(arcadeGui() and Park.debug, "Parking Pro didn't start")
run(2.7)
local pst, input = Park.debug.state, Park.debug.input
-- Straight up the lot towards the spot (its middle at z = -4), braking to a stop in it.
local function drive()
	if pst.pose.z > -3.75 then
		input.gas, input.brake = 1, 0
	elseif pst.v > 0.05 then
		input.gas, input.brake = 0, 1
	else
		input.gas, input.brake = 0, 0
	end
end
for _ = 1, 30 do
	drive()
	run(1 / 30)
end
shot("park", game.Workspace:FindFirstChild("ArcadePark"), arcadeGui())
for _ = 1, 300 do
	if pst.done then
		break
	end
	drive()
	run(1 / 30)
end
print(`park: {string.format("%.2f", pst.t)} s, {pst.bumps} bumps, parked {pst.inSpot}`)
run(0.5)
shot("park-result", nil, arcadeGui())

-- The other four games start from their tiles, a few seconds in, then the X quits them.
for _, id in { "pit", "wash", "delivery", "stunt" } do
	-- Leave the last result card the way a player does (its Back button), so the next game's
	-- screen is the only one.
	while arcadeGui() do
		local back = button(arcadeGui(), "Back")
		press(back)
	end
	hud.ctx.close()
	hud.openPanel("arcade")
	Emu.resumeWaits()
	press(button(hud.gui:FindFirstChild(id, true), "Play"))
	local g = arcadeGui()
	assert(g, `{id} didn't start`)
	run(4)
	shot(`{id}-round`, game.Workspace, arcadeGui())
	local close = arcadeGui() and arcadeGui():FindFirstChild("Close", true)
	assert(close, `{id} has no X`)
	press(if close:IsA("GuiButton") then close else close:FindFirstChildWhichIsA("GuiButton", true))
	run(1)
	Emu.resumeWaits()
	print(`{id}: started, quit {arcadeGui() == nil}`)
	assert(arcadeGui() == nil, `{id}'s X didn't quit`)
end

for _, c in calls do
	print(c)
end
for _, e in errors do
	print("ERROR", string.sub(e, 1, 400))
end
