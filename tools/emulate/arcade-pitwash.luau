--!nocheck
-- Plays Pit Stop and Car Wash Frenzy (src/client/ArcadeGames/Pit.luau, Wash.luau) on their own,
-- without the arcade hub: each gets a fake ctx (its own ScreenGui, an origin, a seed, a level and
-- a car), is stepped a frame at a time with taps, presses and scrubs played in, and writes
-- pictures for render.mjs at a phone's 390x844, mid-round and near the end. Prints what each
-- passes to ctx.finish.
--
--   rojo build -o build/place.rbxl && lune run tools/emulate/arcade-pitwash.luau build/place.rbxl [pit|wash]
--   SIZE=390x844 node tools/emulate/render.mjs <web repo> build/shot-pit-wheels.json out.png \
--     build/shot-pit-wheels-gui.json "$(cat build/shot-pit-wheels-cam.json)"

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Emu = require("./roblox")
local Gui = require("./gui")

local W, H = 390, 844
local only = process.args[2]
local emu = Emu.load(process.args[1] or "build/place.rbxl")
local game = emu.game
local RS = game:GetService("ReplicatedStorage")
Emu.fakeMeshPacks(emu)
local Builder = emu.require(RS.Shared.Models.Builder)
Builder.previewMeshes = true
Builder.loadMeshes(1)
game.Workspace.CurrentCamera.ViewportSize = roblox.Vector2.new(W, H)
local Client = game:GetService("StarterPlayer").StarterPlayerScripts.Client
local data = emu.require(RS.Shared.Game.data)

-- The player's car: the first car the game sells, in red.
local starter = data.CARS[1]
local CAR = { model = starter.id, body = starter.body, color = "#e53935" }

local function shot(name, folderName, gui)
	local parts = {}
	local world = game.Workspace:FindFirstChild(folderName)
	if world then
		for _, d in world:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, Gui.partOf(d))
			end
		end
	end
	local lighting = game:GetService("Lighting")
	local fog = if lighting.FogEnd < 10000 then { color = lighting.FogColor:ToHex(), start = lighting.FogStart, ["end"] = lighting.FogEnd } else nil
	fs.writeFile(`build/shot-{name}.json`, serde.encode("json", { parts = parts, fog = fog }))
	fs.writeFile(`build/shot-{name}-gui.json`, serde.encode("json", { nodes = Gui.dump(gui, W, H), bubbles = {} }))
	local cam = game.Workspace.CurrentCamera
	local cf = cam.CFrame
	local at = cf.Position + cf.LookVector * 50
	fs.writeFile(`build/shot-{name}-cam.json`, serde.encode("json", { from = { cf.Position.X, cf.Position.Y, cf.Position.Z }, at = { at.X, at.Y, at.Z }, fov = cam.FieldOfView }))
	print(`wrote build/shot-{name}.json ({#parts} parts)`)
end

local function newCtx(seed, origin)
	local gui = roblox.Instance.new("ScreenGui")
	gui.Name = "Arcade"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	local ctx = { gui = gui, origin = origin, seed = seed, level = 8, car = CAR, result = nil }
	ctx.finish = function(result, detail)
		assert(ctx.result == nil, "ctx.finish called twice")
		ctx.result = { result = result, detail = detail }
	end
	return ctx
end

local DT = 1 / 30

-- ── Pit Stop ──────────────────────────────────────────────────────────────────────────────────
if only == nil or only == "pit" then
	local Pit = emu.require(Client.ArcadeGames.Pit)
	local arcadeMore = emu.require(RS.Shared.Game.arcadeMore)
	local ctx = newCtx(12345, roblox.Vector3.new(20000, 0, 20000))
	local round = Pit.new(ctx)
	local s = round.state
	round.start()
	local shots = {}
	local function once(name)
		if not shots[name] then
			shots[name] = true
			shot(`pit-{name}`, "PitStop", ctx.gui)
		end
	end
	local braked = false
	for frame = 1, 30 * 40 do
		if ctx.result then
			break
		end
		-- Brake so the car rolls to a stop on the line (brakeDistance from the limiter).
		if s.running and s.phase == "in" then
			if s.x > -10.5 and s.x < -6 then
				once("in")
			end
			if not braked and s.x >= -arcadeMore.brakeDistance(s.v) - 0.15 then
				braked = true
				round.setPedal(true)
			end
		elseif braked and s.phase ~= "in" then
			s.pedal = false
		end
		if s.phase == "wheels" then
			local calling = s.callT < arcadeMore.CALL_SHOW * #s.call
			if calling and s.callT > arcadeMore.CALL_SHOW * 1.5 then
				once("call")
			end
			if not calling then
				-- The called wheel when ready, then each new nut as it turns green, a little late.
				local want = s.call[s.callIdx + 1]
				for i, c in s.corners do
					if c.fill >= 1 and frame % 3 == 0 and (c.stage == 2 or (c.stage == 0 and want == i - 1)) then
						round.tap(i)
					end
				end
				local stages = {}
				for _, c in s.corners do
					stages[c.stage] = (stages[c.stage] or 0) + 1
				end
				if (stages[1] or 0) + (stages[2] or 0) >= 2 then
					once("wheels")
				end
			end
		end
		if s.phase == "green" then
			once("green")
			round.setPedal(true)
			s.pedal = false
		end
		if s.phase == "go" and s.go > 0.5 then
			once("go")
		end
		round.step(DT)
	end
	assert(ctx.result, "Pit Stop never finished")
	print(`Pit Stop finished: result {ctx.result.result}, stars {ctx.result.detail.stars}, line "{ctx.result.detail.line}"`)
	assert(game.Workspace:FindFirstChild("PitStop") == nil, "Pit Stop left its world behind")
	-- The quit button finishes with 0.
	local q = newCtx(7, roblox.Vector3.new(20000, 0, 20000))
	local r2 = Pit.new(q)
	r2.quit()
	assert(q.result.result == 0 and q.result.detail.quit, "quitting didn't finish with 0")
	print("Pit Stop quit: finish(0, { quit = true })")
end

-- ── Car Wash Frenzy ───────────────────────────────────────────────────────────────────────────
if only == nil or only == "wash" then
	local Wash = emu.require(Client.ArcadeGames.Wash)
	local ctx = newCtx(4242, roblox.Vector3.new(-20000, 0, 20000))
	local round = Wash.new(ctx)
	local s = round.state
	round.start()
	local shots = {}
	local function once(name)
		if not shots[name] then
			shots[name] = true
			shot(`wash-{name}`, "CarWash", ctx.gui)
		end
	end
	local wiggle = 0
	for frame = 1, 30 * 120 do
		if ctx.result then
			break
		end
		if s.running and s.phase == "wash" and not s.done then
			-- Rub the first dirty spot: wiggle the pointer over it.
			local on = round.spotsOnScreen()
			for i, p in on do
				if s.scrub[i] < s.need then
					wiggle += 1
					local dx = if wiggle % 2 == 0 then 6 else -6
					if not s.down then
						round.pointer(p.X, p.Y, true)
					end
					round.pointer(p.X + dx, p.Y + (wiggle % 3) * 4, true)
					break
				end
			end
			if s.cars == 0 and s.dirty <= 3 then
				once("scrub")
			end
		elseif s.down then
			round.pointer(s.x, s.y, false)
		end
		if s.phase == "in" and s.phaseT > 0.25 then
			once("next")
		end
		if s.cars >= 2 and s.left < 3 and s.phase == "wash" then
			once("end")
		end
		round.step(DT)
	end
	assert(ctx.result, "Car Wash never finished")
	print(`Car Wash finished: result {ctx.result.result}, stars {ctx.result.detail.stars}, line "{ctx.result.detail.line}"`)
	assert(game.Workspace:FindFirstChild("CarWash") == nil, "Car Wash left its world behind")
end
