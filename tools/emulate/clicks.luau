--!nocheck
-- Presses every button on every screen, in the emulator, and reports the ones that throw an
-- error or reach the server with a request it refuses.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/clicks.luau build/place.rbxl

local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

-- Real signals, one per instance and event, so clicks can be fired.
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
for _, pair in { { "GuiButton", "Activated" }, { "GuiButton", "MouseButton1Down" }, { "GuiButton", "MouseButton1Up" }, { "Instance", "Destroying" }, { "BindableEvent", "Event" }, { "RemoteEvent", "OnClientEvent" }, { "TextBox", "FocusLost" } } do
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
remotes.Parent = RS
local lib = Instance.new("Folder")
lib.Name = "ModelLibrary"
for _, kind in { "Cars", "Buildings" } do
	local f = Instance.new("Folder")
	f.Name = kind
	f.Parent = lib
end
lib.Parent = RS

-- The server end of Cartopia.Act, as init.server.luau runs it.
local calls = {}
roblox.implementMethod("RemoteFunction", "InvokeServer", function(_, name, ...)
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
	signalFor(townEvent, "OnClientEvent"):Fire(towns:snapshot(1))
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
for _, p in { "shop", "cars", "garage", "showroom", "goals", "menu", "inventory" } do
	clickAll(p, function()
		hud.openPanel(p)
	end)
end
print(`{total} buttons pressed, {bad} problems, {silent} not wired`)
