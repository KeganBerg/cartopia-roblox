--!nocheck
-- Plays Delivery Dash and Stunt Ramp (src/client/ArcadeGames/Delivery.luau, Stunt.luau) on their
-- own in the emulator, as the arcade hub would start them: a fake ctx (its own ScreenGui, origin,
-- seed, level, car and finish callback), frames stepped by hand at 60 a second, and input
-- simulated until each round finishes. Writes pictures of the round for render.mjs.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/arcade-delstunt.luau build/place.rbxl [delivery|stunt] [WxH]
--   node tools/emulate/render.mjs <web repo> build/shot-delivery-mid.json out.png build/shot-delivery-mid-gui.json "$(cat build/shot-delivery-mid-cam.json)"
--
-- Shots: build/shot-{delivery,stunt}-{start,mid,...,end}.json (+ -gui.json, -cam.json).

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

-- Signals that fire (taps on the X, input), one per instance and event, as clicks.luau has them.
local nextId = 0
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
		for _, fn in table.clone(fns) do
			local ok, err = pcall(fn, ...)
			if not ok then
				print("handler error:", name, err)
			end
		end
	end
	signals[key] = s
	return s
end
for _, pair in { { "GuiButton", "Activated" }, { "GuiButton", "MouseButton1Down" }, { "GuiButton", "MouseButton1Up" }, { "GuiObject", "InputBegan" }, { "GuiObject", "InputEnded" }, { "UserInputService", "InputBegan" }, { "UserInputService", "InputChanged" }, { "UserInputService", "InputEnded" } } do
	roblox.implementProperty(pair[1], pair[2], function(inst)
		return signalFor(inst, pair[2])
	end)
end

local Emu = require("./roblox")
local Gui = require("./gui")
local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
local only = if process.args[2] == "" or process.args[2] == "all" then nil else process.args[2]
local W, H = 390, 844
if process.args[3] then
	local w, h = string.match(process.args[3], "(%d+)x(%d+)")
	W, H = tonumber(w), tonumber(h)
end
local cam = game.Workspace.CurrentCamera
cam.ViewportSize = roblox.Vector2.new(W, H)
-- A phone (any size but the desktop's 1280x800): touch controls.
local uis = game:GetService("UserInputService")
local phone = not (W == 1280 and H == 800)
uis.TouchEnabled = phone
uis.MouseEnabled = not phone
local TAG = if W < H then "" else `-{W}x{H}`

-- Render steps, run by hand.
local renderSteps = {}
roblox.implementMethod("RunService", "BindToRenderStep", function(_, name, _, fn)
	renderSteps[name] = fn
end)
roblox.implementMethod("RunService", "UnbindFromRenderStep", function(_, name)
	renderSteps[name] = nil
end)

local player = Instance.new("Player")
player.Name = "Player1"
player.UserId = 1
Instance.new("PlayerGui").Parent = player
local players = game:GetService("Players")
players.LocalPlayer = player
player.Parent = players

-- The real models (stand-in boxes for meshes, as render.mjs draws them from build/meshes.json).
local Builder = emu.require(RS.Shared.Models.Builder)
Builder.previewMeshes = true

local client = game:GetService("StarterPlayer").StarterPlayerScripts.Client

local function shot(name, worldName, gui)
	local parts = {}
	local world = game.Workspace:FindFirstChild(worldName)
	if world then
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, Gui.partOf(d))
			end
		end
	end
	name ..= TAG
	fs.writeFile(`build/shot-{name}.json`, serde.encode("json", { parts = parts }))
	fs.writeFile(`build/shot-{name}-gui.json`, serde.encode("json", { nodes = Gui.dump(gui, W, H), bubbles = {} }))
	local cf = cam.CFrame
	local at = cf.Position + cf.LookVector * 50
	fs.writeFile(`build/shot-{name}-cam.json`, serde.encode("json", { from = { cf.Position.X, cf.Position.Y, cf.Position.Z }, at = { at.X, at.Y, at.Z }, fov = cam.FieldOfView }))
	print(`wrote build/shot-{name}.json ({#parts} parts)`)
end

local CAR = { uid = "c1", model = "pip", color = "#e53935", finish = "gloss" }

-- Starts a game with a fake ctx; returns the ctx (with what finish got, once it's called).
local function start(id, origin)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Arcade"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.Parent = player.PlayerGui
	local ctx = {
		gui = gui,
		origin = origin,
		seed = 12345,
		level = 12,
		car = CAR,
	}
	ctx.finish = function(result, detail)
		assert(ctx.result == nil, "finish called twice")
		ctx.result = result
		ctx.detail = detail
		print(`{id}: finish({result}, {serde.encode("json", detail or {})})`)
	end
	local mod = emu.require(client.ArcadeGames:FindFirstChild(id == "delivery" and "Delivery" or "Stunt"))
	assert(mod.id == id, "wrong id")
	mod.play(ctx)
	return ctx
end

local DT = 1 / 60
local function step(name)
	local fn = renderSteps[name]
	if fn then
		fn(DT)
	end
	return fn ~= nil
end

-- ── Delivery Dash ──
if only == nil or only == "delivery" then
	local M = emu.require(RS.Shared.Game.arcadeMore)
	local ctx = start("delivery", roblox.Vector3.new(30000, 0, -30000))
	local s, input = ctx.state, ctx.input
	shot("delivery-start", "DeliveryDash", ctx.gui)
	local frames = 0
	local lastAssist = 0
	local shots = { [60 * 9] = "delivery-mid" }
	local carryAt = nil
	while step("ArcadeDelivery") do
		frames += 1
		if s.running and not s.done then
			-- Drive towards the target: steer by the heading error; every few seconds put the car
			-- on the road a little short of it (a stand-in for a player who knows the town).
			local dx, dz = s.target.x - s.pose.x, s.target.z - s.pose.z
			local want = math.atan2(dx, dz)
			local err = math.atan2(math.sin(want - s.pose.h), math.cos(want - s.pose.h))
			input.left = err > 0.1
			input.right = err < -0.1
			if frames - lastAssist > 60 * 4 and math.sqrt(dx * dx + dz * dz) > 2.5 then
				lastAssist = frames
				local d = math.sqrt(dx * dx + dz * dz)
				-- Along the target's street, 2 units back.
				local horiz = math.abs(s.target.z - M.roadLine(math.floor((s.target.z + M.TOWN / 2) / M.CELL + 0.5))) < 0.01
				local px, pz, h
				if horiz then
					px, pz, h = s.target.x - 2.2, s.target.z, math.pi / 2
				else
					px, pz, h = s.target.x, s.target.z - 2.2, 0
				end
				s.pose = { x = px, z = pz, h = h }
				s.v = 3
			end
			if s.left < 2.5 and not shots.endShot then
				shots.endShot = true
				shot("delivery-end", "DeliveryDash", ctx.gui)
			end
		end
		-- An order on board: the hot-pizza timer, the box on the roof, the green beacon.
		if s.carrying and not carryAt and s.drops >= 1 then
			carryAt = frames
		end
		if carryAt and frames == carryAt + 40 then
			shot("delivery-carry", "DeliveryDash", ctx.gui)
		end
		if shots[frames] then
			shot(shots[frames], "DeliveryDash", ctx.gui)
		end
		if frames > 60 * 200 then
			error("Delivery Dash didn't finish")
		end
	end
	assert(ctx.result ~= nil, "Delivery Dash never called finish")
	assert(game.Workspace:FindFirstChild("DeliveryDash") == nil, "Delivery Dash left its world behind")
	print(`delivery: {frames} frames, {ctx.result} drops, stars {M.dashStars(ctx.result)}`)
	-- The X quits: finish(0, { quit = true }).
	local q = start("delivery", roblox.Vector3.new(30000, 0, -30000))
	for _ = 1, 10 do
		step("ArcadeDelivery")
	end
	-- Touch: hold BRAKE, slide the steer stick right, let go.
	if phone then
		local finger = { UserInputType = roblox.Enum.UserInputType.Touch, Position = roblox.Vector2.new(60, 700), KeyCode = roblox.Enum.KeyCode.Unknown }
		signalFor(q.gui:FindFirstChild("Brake", true), "InputBegan"):Fire(finger)
		assert(q.input.touchBrake, "BRAKE didn't brake")
		signalFor(q.gui:FindFirstChild("Brake", true), "InputEnded"):Fire(finger)
		assert(not q.input.touchBrake, "BRAKE stuck on")
		local thumb = { UserInputType = roblox.Enum.UserInputType.Touch, Position = roblox.Vector2.new(200, 760), KeyCode = roblox.Enum.KeyCode.Unknown }
		signalFor(q.gui:FindFirstChild("Steer", true), "InputBegan"):Fire(thumb)
		thumb.Position = roblox.Vector2.new(228, 760)
		signalFor(uis, "InputChanged"):Fire(thumb, true)
		step("ArcadeDelivery")
		assert(math.abs(q.input.steer + 0.5) < 1e-6, `half a slide right should steer -0.5, got {q.input.steer}`)
		signalFor(uis, "InputEnded"):Fire(thumb, true)
		step("ArcadeDelivery")
		assert(q.input.steer == 0, "letting go didn't centre the steering")
	end
	local close = q.gui:FindFirstChild("Close", true)
	local face = close and close:FindFirstChild("Face")
	signalFor(face, "Activated"):Fire()
	assert(q.result == 0 and q.detail.quit, "the X didn't quit")
	assert(renderSteps.ArcadeDelivery == nil, "quitting left the frame loop running")
end

-- ── Stunt Ramp ──
if only == nil or only == "stunt" then
	local M = emu.require(RS.Shared.Game.arcadeMore)
	local ctx = start("stunt", roblox.Vector3.new(-30000, 0, 30000))
	local s, input = ctx.state, ctx.input
	shot("stunt-start", "StuntRamp", ctx.gui)
	local frames = 0
	local done = {}
	-- Each jump: lock the needle near full, then a different trick in the air (the last one wipes out).
	local plans = { { flip = 0.75 }, { roll = 0.65 }, { flip = 0.75, roll = 0.65 }, { flip = 0.3 } }
	local holdFor = 0
	local airT = 0
	local prev = nil
	while step("ArcadeStunt") do
		frames += 1
		if prev == "air" and s.phase ~= "air" then
			print(`  landed at x {string.format("%.2f", s.x)}, spin {string.format("%.2f", s.spin)}, roll {string.format("%.2f", s.roll)}, power {string.format("%.2f", s.power)}`)
		end
		prev = s.phase
		local jump = s.jump + 1
		local plan = plans[jump] or {}
		if s.phase == "aim" and s.running and s.wait <= 0 and s.power > 0.9 and not input.down then
			input.down = true
			holdFor = 2
		elseif s.phase == "air" then
			airT += DT * (if s.slow then 0.4 else 1)
			input.down = plan.flip ~= nil and airT < plan.flip
			input.roll = plan.roll ~= nil and airT < plan.roll
		else
			airT = 0
			if holdFor > 0 then
				holdFor -= 1
			else
				input.down = false
				input.roll = false
			end
		end
		local key = `{s.phase}{s.jump}`
		if s.phase == "aim" and s.running and not done[key] and s.power > 0.5 then
			done[key] = true
			shot(`stunt-aim{s.jump + 1}`, "StuntRamp", ctx.gui)
		elseif s.phase == "air" and s.vy < 0 and not done[key] then
			done[key] = true
			shot(`stunt-air{s.jump + 1}`, "StuntRamp", ctx.gui)
		elseif s.phase == "roll" or s.phase == "crash" then
			if not done[key] and s.wait < 1.2 then
				print(`  jump {s.jump}: x {string.format("%.2f", s.x)}, {serde.encode("json", s.last)}`)
				done[key] = true
				shot(`stunt-land{s.jump}`, "StuntRamp", ctx.gui)
			end
		end
		if frames > 60 * 120 then
			error("Stunt Ramp didn't finish")
		end
	end
	assert(ctx.result ~= nil, "Stunt Ramp never called finish")
	assert(game.Workspace:FindFirstChild("StuntRamp") == nil, "Stunt Ramp left its world behind")
	print(`stunt: {frames} frames, score {ctx.result}, stars {M.stuntStars(ctx.result)}`)
	local q = start("stunt", roblox.Vector3.new(-30000, 0, 30000))
	for _ = 1, 10 do
		step("ArcadeStunt")
	end
	-- A finger on the left half flips, on the right half rolls; lifting it lets go of both.
	local press = q.gui:FindFirstChild("Press", true)
	local left = { UserInputType = roblox.Enum.UserInputType.Touch, Position = roblox.Vector2.new(W * 0.25, H * 0.6), KeyCode = roblox.Enum.KeyCode.Unknown }
	signalFor(press, "InputBegan"):Fire(left)
	assert(q.input.down and not q.input.roll, "the left half didn't flip")
	signalFor(uis, "InputEnded"):Fire(left, true)
	local right = { UserInputType = roblox.Enum.UserInputType.Touch, Position = roblox.Vector2.new(W * 0.75, H * 0.6), KeyCode = roblox.Enum.KeyCode.Unknown }
	signalFor(press, "InputBegan"):Fire(right)
	assert(q.input.roll and not q.input.down, "the right half didn't roll")
	signalFor(uis, "InputEnded"):Fire(right, true)
	assert(not q.input.roll, "lifting the finger didn't let go")
	local close = q.gui:FindFirstChild("Close", true)
	signalFor(close:FindFirstChild("Face"), "Activated"):Fire()
	assert(q.result == 0 and q.detail.quit, "the X didn't quit")
end
print("ok")
