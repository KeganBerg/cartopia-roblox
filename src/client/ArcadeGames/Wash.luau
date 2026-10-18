--!strict
-- Car Wash Frenzy, as the web game's WashScene (scene/WashScene.tsx) and its screen (WashGame in
-- ui/ArcadeMore.tsx). A line of muddy cars rolls into the bay, the player's own first: rub the mud
-- spots off each one before the clock runs out. Every clean car adds time (more for a quick one)
-- and the next rolls in, each muddier than the last. The result is how many cars were washed.
--
-- Every rule and number comes from the converted game/arcadeMore.ts (Shared.Game.arcadeMore).
-- Wash.new(ctx) builds a round that a frame loop steps; Wash.play(ctx) runs it on RenderStepped
-- with touch and mouse input (tools/emulate/arcade-pitwash.luau steps it by hand).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local arcadeMore = require(Game.arcadeMore) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Parent.Ui)
local Kit = require(script.Parent.StarKit)
local Sfx = require(script.Parent.Parent.Sounds.Sfx)

local WASH_QUICK, WASH_SPOTS, WASH_TIME = arcadeMore.WASH_QUICK, arcadeMore.WASH_SPOTS, arcadeMore.WASH_TIME

local Wash = { id = "wash" }

local S = Kit.S
local hex = Kit.hex
local LEN = 2.6 -- each car in the bay, drawn this long
local SLIDE = 0.6 -- seconds for a car to roll out or in
local QUEUE = 8 -- different cars in the line, then it repeats
local CAM_FOV = 45 -- WASH_CAM
local LINE_BODIES = { sedan = true, compact = true, van = true, suv = true, truck = true, hatch = true, wagon = true, classic = true, ev = true, bubble = true }
local MUD = { "#6d4c2f", "#5d4037", "#7b5a3a" }
local BANDS = { "#1e88e5", "#e53935", "#fdd835", "#43a047", "#1e88e5", "#e53935", "#fdd835" }

-- The web's little seeded random (WashScene rng): the mud lands in the same places every time.
local function rng(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

-- Who's in line: your car first, then everyday cars from town (washQueue).
local function washQueue(me: any): { any }
	local pool = {}
	for _, c in data.CARS do
		if not c.parked and not data.isBike(c.body) and LINE_BODIES[c.body] then
			table.insert(pool, c)
		end
	end
	local out = { me }
	for i = 0, QUEUE - 2 do
		local c = pool[(i * 7 + 4) % #pool + 1]
		table.insert(out, { model = c.id, color = c.colors[(i * 3) % #c.colors + 1] })
	end
	return out
end

-- ── Scenery: the wash bay (WashScenery) ────────────────────────────────────────────────────────

local function buildScenery(into: Instance, O: Vector3)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(O + Vector3.new(x, y, z) * S)
	end
	local function box(w: number, h: number, d: number, cf: CFrame, color: string, material: Enum.Material?): Part
		return Kit.part({ Size = Vector3.new(w, h, d) * S, CFrame = cf, Color = hex(color), Material = material or Enum.Material.SmoothPlastic }, into)
	end
	local function signBoard(w: number, h: number, cf: CFrame, text: string, bg: string, fg: string)
		local p = Kit.part({ Size = Vector3.new(w * S, h * S, 0.2), CFrame = cf, Color = hex(bg) }, into)
		Kit.sign(p, text, fg, bg)
	end
	local function disc(r: number, thick: number, cf: CFrame, color: string, transparency: number?)
		Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(thick, r * 2 * S, r * 2 * S), CFrame = cf, Color = hex(color), Transparency = transparency or 0 }, into)
	end
	box(60, 0.1, 40, at(0, -0.05, 0), "#cfd2d6", Enum.Material.Pavement)
	box(12, 0.1, 6, at(0, -0.035, 0), "#b8c4cc", Enum.Material.Concrete)
	-- Guide rails for the wheels and the drain run down the middle.
	for _, z in { -0.75, 0.75 } do
		box(11, 0.1, 0.08, at(0, 0.05, z), "#ffd54f")
	end
	for i = 0, 7 do
		box(0.5, 0.01, 0.9, at(-4.9 + i * 1.4, 0.02, 0), "#546e7a", Enum.Material.DiamondPlate)
	end
	-- Puddles.
	for _, p in { { -2.5, 1.4, 1.2 }, { 2.8, -1.2, 0.9 }, { 0.5, 1.9, 0.7 }, { -4, -1.6, 0.8 } } do
		disc(p[3], 0.05, at(p[1], 0.03, p[2]) * CFrame.Angles(0, 0, math.pi / 2), "#5d7a8a", 0.45)
	end
	-- Back wall, with the sign and a price board.
	box(12, 3.2, 0.2, at(0, 1.6, -3), "#b3e5fc", Enum.Material.CorrodedMetal)
	box(12, 0.9, 0.05, at(0, 0.45, -2.88), "#0277bd")
	signBoard(4.4, 1.1, at(0, 2.55, -2.87), "SUDS & SHINE", "#01579b", "#ffffff")
	for _, b in { { -3.8, "#e53935", "WASH" }, { 3.8, "#43a047", "WAX" } } do
		local x = b[1] :: number
		signBoard(1.6, 0.5, at(x, 1.9, -2.87), b[3] :: string, b[2] :: string, "#ffffff")
		for k = 0, 2 do
			box(1.4, 0.12, 0.02, at(x, 1.9 - 0.45 - k * 0.22, -2.88), "#e1f5fe")
		end
	end
	-- Hoses coiled on the back wall.
	for _, x in { -2.2, 2.2 } do
		disc(0.31, 0.06, at(x, 1.4, -2.86) * CFrame.Angles(0, math.pi / 2, 0), "#fdd835")
		disc(0.19, 0.08, at(x, 1.4, -2.86) * CFrame.Angles(0, math.pi / 2, 0), "#b3e5fc")
		box(0.1, 0.1, 0.12, at(x, 1.75, -2.85), "#455a64")
	end
	-- Tunnel arches at each end, with spray bars and curtain strips.
	for _, x in { -4.6, 4.6 } do
		for _, z in { -2.6, 2.6 } do
			box(0.35, 3.2, 0.35, at(x, 1.6, z), "#0288d1")
		end
		box(0.45, 0.5, 5.6, at(x, 3.25, 0), "#0277bd")
		signBoard(3, 0.38, at(x + 0.24, 3.25, 0) * CFrame.Angles(0, math.pi / 2, 0), if x < 0 then "EXIT" else "ENTER", "#0277bd", "#ffffff")
		Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 0.08, 0.08) * S, CFrame = at(x + 0.3, 2.7, 0) * CFrame.Angles(0, math.pi / 2, 0), Color = hex("#cfd8dc"), Material = Enum.Material.Metal }, into)
		for i = 0, 8 do
			box(0.06, 0.1, 0.06, at(x + 0.3, 2.62, -2 + i * 0.5), "#455a64")
		end
		if x < 0 then
			for i = 0, 15 do
				box(0.02, 1.9, 0.22, at(x + 0.1, 2.05, -2.25 + i * 0.3), if i % 2 == 1 then "#4fc3f7" else "#0288d1")
			end
		end
	end
	-- Roof beams and strip lights.
	for _, x in { -3, -1, 1, 3 } do
		box(0.2, 0.2, 6, at(x, 3.4, 0), "#90a4ae")
		Kit.part({ Size = Vector3.new(0.12, 0.04, 4.4) * S, CFrame = at(x, 3.28, 0), Color = hex("#f5fbff"), Material = Enum.Material.Neon }, into)
	end
	-- Vacuum stands outside the entrance.
	for _, x in { 6.5, 8 } do
		box(0.45, 1.1, 0.45, at(x, 0.55, -1.8), "#ffd54f")
		signBoard(0.35, 0.2, at(x, 0.85, -1.8 + 0.23), "VAC", "#ffd54f", "#1a1a1a")
		box(0.4, 0.06, 0.06, at(x, 1.45, -1.8), "#212121")
	end
	Kit.lamp(into, O, 7.2, 2.2, math.pi)
	Kit.lamp(into, O, -7.2, 2.2, math.pi)
	-- The brushes: two tall ones beside the exit and one across the top, a core in coloured
	-- bristle bands (Brush).
	local function brush(x: number, z: number, flat: boolean)
		local base = if flat then at(x, 2.15, z) * CFrame.Angles(0, 0, math.pi / 2) else at(x, 1.1, z)
		Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 0.1, 0.1) * S, CFrame = base * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#b0bec5"), Material = Enum.Material.Metal }, into)
		for i, c in BANDS do
			Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.28, 0.84, 0.84) * S, CFrame = base * CFrame.new(0, (-0.95 + (i - 1) * 0.32) * S, 0) * CFrame.Angles(0, (i - 1) * 0.6, math.pi / 2), Color = hex(c), Material = Enum.Material.Fabric }, into)
		end
	end
	brush(-3.6, -1.7, false)
	brush(-3.6, 1.95, false)
	brush(-4, 0, true)
end

-- ── The round ──────────────────────────────────────────────────────────────────────────────────

export type Round = {
	step: (dt: number) -> (),
	pointer: (x: number, y: number, down: boolean) -> (),
	start: () -> (),
	quit: () -> (),
	spotsOnScreen: () -> { Vector3 },
	state: any,
	done: boolean,
}

function Wash.new(ctx: any): Round
	local O: Vector3 = ctx.origin
	local gui: ScreenGui = ctx.gui
	local random = Random.new(ctx.seed or os.time())
	local function W(x: number, y: number, z: number): Vector3
		return O + Vector3.new(x, y, z) * S
	end

	local folder = Instance.new("Folder")
	folder.Name = "CarWash"
	folder.Parent = workspace
	buildScenery(folder, O)
	local queue = washQueue(ctx.car or { model = "pip", color = "#e53935" })

	-- The car in the bay (facing -x, out through the brushes) and its mud.
	local cur: Kit.Car? = nil
	local spots: { { p: Vector3, up: boolean, size: number, parts: { BasePart }, rel: { CFrame }, sizes: { Vector3 } } } = {}
	local function mudSpots(c: Kit.Car, seed: number)
		for _, sp in spots do
			for _, p in sp.parts do
				p:Destroy()
			end
		end
		spots = {}
		local r = rng(97 + seed * 31)
		local len = LEN
		local side = c.wid / 2 / S + 0.01
		local wy = 0.2
		for _, w in c.corners do
			wy = math.max(wy, w.y / S)
		end
		local low = wy * 1.05
		-- The car's own frame faces +z; the bay's x runs the other way along it.
		local function top(x: number, z: number): number
			return Kit.topAt(c, z * S, -x * S) / S
		end
		local belt = math.max(low + 0.12, top(0.35 * len, 0) * 0.92)
		for i = 0, WASH_SPOTS - 1 do
			local p: Vector3
			local up, size
			if i >= 4 then
				local x = (if i == 4 then -0.3 else 0.2) * len
				local z = (r() - 0.5) * side * 0.9
				p = Vector3.new(x, top(x, z) + 0.012, z)
				up, size = true, 0.19 + r() * 0.06
			else
				local x = (-0.4 + (i + 0.5) * 0.2 + (r() - 0.5) * 0.08) * len
				local y = low + (belt - low) * (0.2 + r() * 0.6)
				p = Vector3.new(x, y, side)
				up, size = false, 0.18 + r() * 0.06
			end
			-- A splat of five blobs, with drips running down the side ones.
			local parts, rel, sizes = {}, {}, {}
			local frame = (if up then CFrame.new() else CFrame.Angles(math.pi / 2, 0, 0)) * CFrame.Angles(0, i * 1.3, 0)
			local function blob(at: Vector3, sz: Vector3, color: string, spin: boolean)
				local b = Kit.part({ Size = sz * S, Color = hex(color), Material = Enum.Material.Mud }, folder)
				local m = Instance.new("SpecialMesh")
				m.MeshType = Enum.MeshType.Sphere
				m.Parent = b
				table.insert(parts, b)
				table.insert(rel, (if spin then frame else (if up then CFrame.new() else CFrame.Angles(math.pi / 2, 0, 0))) * CFrame.new(at * S))
				table.insert(sizes, sz * S)
			end
			for j, d in { { 0, 0, 1 }, { 0.7, 0.25, 0.55 }, { -0.6, -0.3, 0.65 }, { 0.2, -0.65, 0.4 }, { -0.3, 0.6, 0.35 } } do
				local k = d[3]
				blob(Vector3.new(d[1] * size, 0, d[2] * size), Vector3.new(size * k * 2, size * 0.24, size * k * 0.85 * 2), MUD[(i + j - 1) % 3 + 1], true)
			end
			if not up then
				for j, dx in { -0.3, 0.25 } do
					blob(Vector3.new(dx * size, 0, (1 + (j - 1) * 0.4) * size), Vector3.new(size * 0.28, size * 0.16, size * (0.55 + (j - 1) * 0.3) * 2), MUD[i % 3 + 1], false)
				end
			end
			table.insert(spots, { p = p, up = up, size = size, parts = parts, rel = rel, sizes = sizes })
		end
	end
	local function rollIn(slot: number)
		if cur then
			cur.model:Destroy()
		end
		cur = Kit.car(queue[slot % QUEUE + 1], LEN * S, folder)
		mudSpots(cur :: Kit.Car, slot)
	end
	rollIn(0)

	-- Foam that drifts up and pops, and a glint along the clean car.
	local bubbles = {}
	for i = 1, 48 do
		bubbles[i] = { x = 0, y = -10, z = 0, vy = 0, life = 0, s = 0, part = Kit.part({ Shape = Enum.PartType.Ball, Size = Vector3.one, Color = hex("#ffffff"), Transparency = 1, Material = Enum.Material.Glass }, folder) }
	end
	local sparkle = Kit.part({ Size = Vector3.new(0.6, 0.6, 0.02) * S, Color = hex("#ffffff"), Material = Enum.Material.Neon, Transparency = 1 }, folder)

	local s = {
		t = 0,
		clock = 0,
		left = WASH_TIME,
		cars = 0,
		scrub = table.create(WASH_SPOTS, 0),
		dirty = WASH_SPOTS,
		done = false,
		endAt = 0,
		nextBubble = 0,
		squish = 0,
		shine = 0,
		phase = "wash",
		phaseT = 0,
		carT = 0,
		slot = 0,
		need = arcadeMore.scrubNeed(0),
		rigX = 0,
		running = false,
		-- The pointer (screen pixels) and how far it has moved while pressed.
		x = 0,
		y = 0,
		down = false,
		moved = 0,
	}

	local round: Round
	local cam, giveBack = Kit.takeCamera(CAM_FOV)
	Kit.fog("#d9f2ff", 14, 60)
	local finished = false
	local function close(result: number, detail: any)
		if finished then
			return
		end
		finished = true
		round.done = true
		folder:Destroy()
		Kit.fog(nil)
		giveBack()
		ctx.finish(result, detail)
	end

	-- The camera stands in front of the bay, backed off to fit the car (useFitCamera).
	local function fitCamera()
		local size = Kit.screen(gui)
		local wide = size.X > size.Y
		local halfW, halfH = if wide then 3.4 else 1.75, 2
		local t = math.tan(math.rad(CAM_FOV / 2))
		local dist = math.max(halfH / t, halfW / (t * size.X / math.max(1, size.Y)))
		local target = Vector3.new(0, 0.5, 0.2)
		local from = target + Vector3.new(0, 0.55, 1).Unit * dist
		cam.CFrame = CFrame.lookAt(O + from * S, O + target * S)
	end
	fitCamera()

	-- ── The screen (WashGame) ─────────────────────────────────────────────────────────────────
	local scrubber = Ui.new("TextButton", { Name = "Scrub", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = gui })
	Kit.topBar(gui, "🧽 Car Wash", function()
		close(0, { quit = true })
	end)
	local hudRow = Kit.hudRow(gui)
	local clockPill = Kit.pill(hudRow, 1, `⏱ {WASH_TIME}s`, 79)
	local carsPill = Kit.pill(hudRow, 2, "🚗 0")
	local mudPill = Kit.pill(hudRow, 3, `🟤 {WASH_SPOTS}`)
	local tip = Kit.words(gui, { Name = "Tip", Text = "", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.new(1, -20, 0, 26), ZIndex = 4 }, 20, 2, 0.4)
	local sponge = Ui.text({ Name = "Sponge", Text = "🧽", TextSize = 44, AnchorPoint = Vector2.new(0.5, 0.6), Size = UDim2.fromOffset(56, 56), Rotation = -15, Visible = false, ZIndex = 7, Parent = gui })
	local popNow: Kit.Pop? = nil

	local function screenSpots(): { Vector3 }
		local size = Kit.screen(gui)
		local out = {}
		for i, sp in spots do
			out[i] = Kit.project(cam.CFrame, CAM_FOV, size, W(sp.p.X + s.rigX, sp.p.Y, sp.p.Z))
		end
		return out
	end

	local function step(rawDt: number)
		if finished then
			return
		end
		local dt = math.min(rawDt, 1 / 20)
		s.clock += dt
		local t = s.clock
		local live = s.running and not s.done
		if live then
			s.t += dt
			s.left -= dt
			s.carT += dt
		end
		local moved = s.moved
		s.moved = 0
		if live and s.phase == "wash" and s.down and moved > 0 then
			local size = Kit.screen(gui)
			local reach = math.max(46, size.Y * 0.085)
			local need = s.need
			local on = screenSpots()
			local hit = false
			for i, sp in spots do
				if s.scrub[i] >= need then
					continue
				end
				local p = on[i]
				if math.sqrt((p.X - s.x) ^ 2 + (p.Y - s.y) ^ 2) > reach then
					continue
				end
				hit = true
				s.scrub[i] = math.min(need, s.scrub[i] + moved)
				if s.nextBubble <= 0 then
					for _, b in bubbles do
						if b.life <= 0 then
							b.x = sp.p.X + s.rigX + (random:NextNumber() - 0.5) * 0.3
							b.y = sp.p.Y
							b.z = sp.p.Z + 0.05
							b.vy = 0.3 + random:NextNumber() * 0.4
							b.life = 1
							b.s = 0.04 + random:NextNumber() * 0.05
							break
						end
					end
				end
				if s.scrub[i] >= need then
					s.dirty = math.max(0, s.dirty - 1)
					Sfx.arcade.ding(1 + (WASH_SPOTS - s.dirty) * 0.05)
				end
			end
			s.nextBubble = if s.nextBubble <= 0 then 0.03 else s.nextBubble - dt
			if hit then
				s.squish -= dt
				if s.squish <= 0 then
					Sfx.arcade.scrub()
					s.squish = 0.11
				end
			end
			-- Clean: time back, more for a quick one, and it rolls out through the brushes.
			if s.dirty <= 0 then
				local quick = s.carT <= WASH_QUICK
				local bonus = math.floor(arcadeMore.washBonus(s.cars, quick) * 10 + 0.5) / 10
				s.cars += 1
				s.left += bonus
				s.shine = 0.001
				Sfx.arcade.splash()
				if popNow then
					popNow.label:Destroy()
				end
				local text = if quick then `⚡ Quick! +{bonus}s` else `✨ +{bonus}s`
				popNow = Kit.pop(gui, text, hex(if quick then "#80d8ff" else "#ffd54f"), if quick then 44 else 30, UDim.new(0.26, 0))
				s.phase = "out"
				s.phaseT = 0
			end
		end
		if s.phase ~= "wash" then
			s.phaseT += dt
			local k = math.min(1, s.phaseT / SLIDE)
			s.rigX = if s.phase == "out" then -k * k * 9 else (1 - k) * (1 - k) * 9
			if k >= 1 then
				if s.phase == "out" then
					-- The next car in line, freshly muddy.
					s.phase = "in"
					s.phaseT = 0
					s.slot += 1
					for i = 1, WASH_SPOTS do
						s.scrub[i] = 0
					end
					s.dirty = WASH_SPOTS
					s.need = arcadeMore.scrubNeed(s.cars)
					s.shine = 0
					rollIn(s.slot)
					s.rigX = 9
				else
					s.phase = "wash"
					s.carT = 0
				end
			end
		end
		if live and s.left <= 0 then
			s.left = 0
			s.done = true
			s.endAt = t + 0.6
		end
		if s.done and s.endAt > 0 and t > s.endAt then
			s.endAt = 0
			close(s.cars, { stars = arcadeMore.washStars(s.cars), line = `🚗 {s.cars} washed` })
			return
		end

		-- The car and its mud, where the rig is.
		local c = cur :: Kit.Car
		Kit.place(c, CFrame.new(W(s.rigX, 0, 0)) * CFrame.Angles(0, -math.pi / 2, 0))
		for i, sp in spots do
			local k = 1 - s.scrub[i] / s.need
			local seen = k > 0.02
			local sc = 0.35 + k * 0.65
			local base = CFrame.new(W(sp.p.X + s.rigX, sp.p.Y, sp.p.Z))
			for j, p in sp.parts do
				p.Transparency = if seen then 0 else 1
				p.Size = sp.sizes[j] * sc
				local r = sp.rel[j]
				p.CFrame = base * (r - r.Position + r.Position * sc)
			end
		end
		for i, b in bubbles do
			if b.life > 0 then
				b.life -= dt * 0.9
				b.y += b.vy * dt
				b.x += math.sin(t * 3 + i) * dt * 0.1
			end
			if b.life > 0 then
				b.part.Size = Vector3.one * 2 * b.s * (0.6 + (1 - math.max(0, b.life)) * 0.8) * S
				b.part.CFrame = CFrame.new(W(b.x, b.y, b.z))
				b.part.Transparency = 0.15
			else
				b.part.Transparency = 1
			end
		end
		if s.shine > 0 then
			s.shine += dt
		end
		sparkle.Transparency = if s.shine > 0 and s.shine < 0.9 then 0.1 else 1
		sparkle.CFrame = CFrame.new(W(s.rigX + LEN / 2 - (s.shine / 0.8) * LEN, c.height / S * 0.9, c.wid / S / 2 + 0.08)) * CFrame.Angles(0, 0, t * 4)

		-- The HUD.
		local secs = math.max(0, s.left)
		Kit.setPill(clockPill, `⏱ {math.ceil(secs)}s`, 79)
		clockPill.frame.BackgroundColor3 = if secs < 6 then Color3.fromRGB(198, 40, 40) else Color3.fromRGB(27, 31, 36)
		clockPill.frame.BackgroundTransparency = if secs < 6 then 0.15 else 0.35
		Kit.setPill(carsPill, `🚗 {s.cars}`)
		Kit.setPill(mudPill, `🟤 {s.dirty}`)
		Ui.setText(tip, if s.running and s.cars == 0 and s.dirty == WASH_SPOTS then "Rub the mud off 👆" else "")
		sponge.Visible = s.down
		sponge.Position = UDim2.fromOffset(s.x, s.y)
		if popNow and not Kit.stepPop(popNow, dt, 24) then
			popNow = nil
		end
	end

	local count: ((number) -> boolean)? = nil
	round = {
		state = s,
		done = false,
		start = function()
			count = Kit.countdown(gui, function()
				s.running = true
			end)
		end,
		step = function(dt: number)
			if count and not count(dt) then
				count = nil
			end
			step(dt)
		end,
		-- The pointer moved to x, y (screen pixels) and is pressed or not; travel while pressed
		-- is what scrubs.
		pointer = function(x: number, y: number, down: boolean)
			if down and s.down then
				s.moved += math.sqrt((x - s.x) ^ 2 + (y - s.y) ^ 2)
			end
			s.x, s.y, s.down = x, y, down
		end,
		spotsOnScreen = screenSpots,
		quit = function()
			close(0, { quit = true })
		end,
	}
	-- Touch and mouse: a press on the bay starts scrubbing; the pointer is followed until it lifts.
	local function where(input: InputObject): (number, number)
		local inset = GuiService:GetGuiInset()
		return input.Position.X + inset.X, input.Position.Y + inset.Y
	end
	scrubber.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local x, y = where(input)
			round.pointer(x, y, false)
			round.pointer(x, y, true)
		end
	end)
	round.state.inputs = {
		UserInputService.InputChanged:Connect(function(input: InputObject)
			if s.down and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local x, y = where(input)
				round.pointer(x, y, true)
			end
		end),
		UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				s.down = false
			end
		end),
	}
	step(0)
	return round
end

-- Runs one round on its own frame loop.
function Wash.play(ctx: any)
	local round = Wash.new(ctx)
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt: number)
		round.step(dt)
		if round.done then
			conn:Disconnect()
			for _, c in round.state.inputs do
				c:Disconnect()
			end
		end
	end)
	round.start()
end

return Wash
