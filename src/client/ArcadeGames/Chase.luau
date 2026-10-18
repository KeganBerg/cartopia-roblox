--!strict
-- Getaway Chase, as the web game's ChaseScene (scene/ChaseScene.tsx) and ChaseGame (ui/Arcade.tsx):
-- dodge traffic in three lanes with a cop on your tail. Rows of traffic, coins and nitro cans come
-- from the converted rules (game/arcade.ts chaseRow, chaseSpeed, copGap, ...) with the web's seeded
-- rand; crashes are the web's box tests (game/collide.ts boxPush, circlePush, carBox). Three hearts;
-- near misses build a combo, nitro smashes through traffic, and after 20 seconds the cop lunges
-- for your lane now and then. The score (distance + coins + bonus) goes to the server, which pays it.
--
-- Everything is worked out in web units with the player at z = 0 driving towards -z, as the web
-- scene does, and drawn 10 studs to a unit from ctx.origin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local arcade = require(Game.arcade) :: any
local collide = require(Game.collide) :: any
local data = require(Game.data) :: any
local Kit = require(script.Parent.Parent.ArcadeKit)
local Ui = require(script.Parent.Parent.Ui)
local TownCamera = require(script.Parent.Parent.TownCamera)
local Sfx = require(script.Parent.Parent.Sounds.Sfx)

local Chase = {}
Chase.id = "chase"

local S = Kit.S
local LEN = 1.6 -- every car is drawn at this length
local SPAWN_Z = -80
local HALF = 3.2 -- half the road's width
local WALK = 1.6
local STRETCH = 44 -- one repeating stretch of street
local STRETCHES = 3
local COINS = 24
local COIN_R = 0.3
local CANS = 3
local STREAKS = 28
local PUFFS = 14
local LANES = arcade.CHASE_LANES -- { -1.7, 0, 1.7 }
local K = 1.15 -- town pieces drawn this much bigger (ArcadeScenery K)

-- Everyday cars from the showroom for the traffic, never the exotic ones (ChaseScene pickTraffic).
local TRAFFIC_BODIES = { sedan = true, compact = true, van = true, suv = true, truck = true, hatch = true, wagon = true, classic = true, ev = true, luxury = true, bubble = true, dogvan = true }
local function pickTraffic(n: number): { { model: string, color: string } }
	local pool = {}
	for _, c in data.CARS do
		if not c.parked and not data.isBike(c.body) and TRAFFIC_BODIES[c.body] then
			table.insert(pool, c)
		end
	end
	local out = {}
	for i = 0, n - 1 do
		local c = pool[(i * 7 + 3) % #pool + 1]
		table.insert(out, { model = c.id, color = c.colors[i % #c.colors + 1] })
	end
	return out
end

-- The pop colours (.chase-pop and its kinds) and sizes.
local POP = {
	near = { Color3.fromHex("#ffd54f"), 28 },
	smash = { Color3.fromHex("#ff9e40"), 32 },
	nitro = { Color3.fromHex("#80d8ff"), 40 },
	cop = { Color3.fromHex("#b9f6ca"), 28 },
	warn = { Color3.fromHex("#ff8a80"), 28 },
}

-- One stretch of street (ArcadeScenery StreetStretch): road, kerbs, sidewalks, lane dashes, a
-- side street at its near end, the player's shops either side with trees and lamps, and taller
-- blocks behind. Built facing -z from its pivot.
local function stretch(seed: number, pool: { string }, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = `Stretch{seed}`
	local at = CFrame.new()
	local r = Kit.rand(seed * 7919 + 13)
	local cross = 4.2
	local asphalt = Color3.fromHex("#4a4f57")
	local function box(name: string, x: number, y: number, z: number, w: number, h: number, l: number, color: Color3, mat: Enum.Material?)
		Kit.part({ Name = name, Size = Vector3.new(w * S, h * S, l * S), CFrame = CFrame.new(x * S, y * S, z * S), Color = color, Material = mat or Enum.Material.SmoothPlastic }, m)
	end
	box("Road", 0, -0.05, -STRETCH / 2, HALF * 2, 0.1, STRETCH, asphalt)
	for _, sd in { -1, 1 } do
		box("Walk", sd * (HALF + WALK / 2), 0.06, -STRETCH / 2 - cross / 2, WALK, 0.12, STRETCH - cross, Color3.fromHex("#d9d4ca"))
		box("Kerb", sd * (HALF + 0.04), 0.065, -STRETCH / 2 - cross / 2, 0.08, 0.13, STRETCH - cross, Color3.fromHex("#cfd2d6"))
		box("SideStreet", sd * (HALF + 6), -0.05, -cross / 2, 12, 0.1, cross, asphalt)
		box("Grass", sd * (HALF + WALK + 16), -0.08, -STRETCH / 2 - cross / 2, 32, 0.1, STRETCH - cross, Color3.fromHex("#6fae4f"))
		box("Edge", sd * (HALF - 0.18), 0.005, -STRETCH / 2 - cross / 2, 0.1, 0.01, STRETCH - cross, Color3.fromHex("#ffd54f"))
	end
	-- Zebra crossing at the side street.
	local stripes = math.floor((HALF * 2 - 0.4) / 0.6)
	for i = 0, stripes - 1 do
		box("Zebra", -HALF + 0.5 + i * 0.6, 0.005, -cross / 2, 0.32, 0.01, cross - 1.4, Color3.fromHex("#f5f5f5"))
	end
	-- Lane dashes between the lanes.
	for _, x in { (LANES[1] + LANES[2]) / 2, (LANES[2] + LANES[3]) / 2 } do
		for i = 0, math.floor((STRETCH - cross) / 3) - 1 do
			box("Dash", x, 0.005, -cross - 1 - i * 3, 0.12, 0.01, 1.5, Color3.fromHex("#fafafa"))
		end
	end
	-- Shops, with a tree and sometimes a lamp in each gap.
	local n = 0
	for _, sd in { -1, 1 } do
		local z = -cross - 0.6 - (if sd > 0 then 1.2 else 0)
		local i = math.floor(r() * #pool)
		while z > -STRETCH + 2 do
			local def = data.buildingDef(pool[i % #pool + 1])
			i += 1
			local w, d = def.w * data.TILE * K, def.h * data.TILE * K
			if z - w < -STRETCH + 0.4 then
				break
			end
			local x = sd * (HALF + WALK + d / 2 + 0.15)
			local turn = if sd < 0 then math.pi / 2 else -math.pi / 2
			local place = at * CFrame.new(x * S, 0, (z - w / 2) * S) * CFrame.Angles(0, turn, 0)
			box("Lot", x, 0.01, z - w / 2, d, 0.02, w, Color3.fromHex("#e6dccb"))
			local b = Kit.library("Buildings", def.id)
			if b then
				Kit.scale(b, K)
				b:PivotTo(place)
				b.Parent = m
			end
			z -= w
			Kit.tree(at, sd * (HALF + WALK - 0.45), z - 0.8, r() < 0.25, K, m)
			if n % 2 == 0 then
				Kit.lamp(at, sd * (HALF + 0.25), z - 0.8, if sd > 0 then -math.pi / 2 else math.pi / 2, m)
			end
			n += 1
			z -= 1.6
		end
	end
	-- Taller blocks behind the shops so the skyline is never empty.
	local tints = { "#b0bec5", "#cfd8dc", "#90a4ae", "#d7ccc8", "#bcaaa4", "#9fa8da", "#a5d6a7" }
	for _, sd in { -1, 1 } do
		local z = -cross - 1
		while z > -STRETCH + 3 do
			local w = 3 + r() * 3
			local x = sd * (HALF + WALK + 6.5 + r() * 3)
			local dd = 3 + r() * 2
			local h = 4 + r() * 7
			local c = tints[math.floor(r() * #tints) + 1]
			box("Tower", x, h / 2, z - w / 2, dd, h, w, Color3.fromHex(c), Enum.Material.Concrete)
			z -= w + 0.6 + r() * 1.5
		end
	end
	m.WorldPivot = CFrame.new()
	m.Parent = parent
	return m
end

-- The cruiser: the town's sedan in white, with a push bar and a red and blue light bar on the roof
-- (ChaseScene Cruiser). Returns the model, its footprint and the two lamps.
local function cruiser(parent: Instance): (Model, any, BasePart, BasePart, BasePart)
	local m, foot = Kit.car({ model = "civic", color = "#f5f5f5" }, LEN, nil, parent)
	local _, size = m:GetBoundingBox()
	local top = size.Y
	if m:FindFirstChild("Body") == nil and top < 0.5 then
		top = 0.6 * S
	end
	-- Black doors either side.
	for _, sd in { -1, 1 } do
		Kit.part({ Name = "Door", Size = Vector3.new(0.02 * S, 0.2 * S, 0.72 * S), CFrame = CFrame.new(sd * (foot.w / 2 + 0.006) * S, 0.36 * S, -0.05 * S), Color = Color3.fromHex("#1b1f24") }, m)
	end
	Kit.part({ Name = "PushBar", Size = Vector3.new(0.6, 0.16, 0.06) * S, CFrame = CFrame.new(0, 0.22 * S, (foot.l / 2 + 0.06) * S), Color = Color3.fromHex("#212121") }, m)
	Kit.part({ Name = "Bar", Size = Vector3.new(0.62, 0.04, 0.16) * S, CFrame = CFrame.new(0, top + 0.02 * S, 0), Color = Color3.fromHex("#cfd8dc") }, m)
	local red = Kit.part({ Name = "Red", Size = Vector3.new(0.28, 0.07, 0.13) * S, CFrame = CFrame.new(-0.16 * S, top + 0.07 * S, 0), Color = Color3.fromHex("#ff1744"), Material = Enum.Material.Neon }, m)
	local blue = Kit.part({ Name = "Blue", Size = Vector3.new(0.28, 0.07, 0.13) * S, CFrame = CFrame.new(0.16 * S, top + 0.07 * S, 0), Color = Color3.fromHex("#2979ff"), Material = Enum.Material.Neon }, m)
	-- The light bar's glow on the road.
	local glow = Kit.part({ Name = "Glow", Size = Vector3.new(2.2 * S, 0.02, 2.8 * S), CFrame = CFrame.new(0, 0.05 * S, 0), Color = Color3.fromHex("#ff1744"), Material = Enum.Material.Neon, Transparency = 0.8 }, m)
	return m, foot, red, blue, glow
end

function Chase.play(ctx: any)
	local origin: Vector3 = ctx.origin
	local base = CFrame.new(origin)
	local world = Instance.new("Folder")
	world.Name = "ArcadeChase"
	world.Parent = workspace

	-- ── The scene ────────────────────────────────────────────────────────────────────────────
	Kit.part({ Name = "Grass", Size = Vector3.new(160 * S, 1, 200 * S), CFrame = base * CFrame.new(0, -0.6 - 0.5, -40 * S), Color = Color3.fromHex("#6fae4f") }, world)
	local pool = Kit.townPool(ctx.buildings)
	local stretches: { Model } = {}
	for i = 1, STRETCHES do
		stretches[i] = stretch(i, pool, world)
	end
	local traffic = pickTraffic(10)
	local trafficModels: { Model } = {}
	local feet: { any } = {}
	for i, t in traffic do
		local m, f = Kit.car(t, LEN, nil, world)
		Kit.shadow(f.l, f.w, m)
		m:PivotTo(base * CFrame.new(0, -100 * S, 0))
		trafficModels[i] = m
		feet[i] = f
	end
	local player, foot = Kit.car(ctx.car, LEN, nil, world)
	Kit.shadow(foot.l, foot.w, player)
	local cop, copFoot, red, blue, glow = cruiser(world)
	-- Coins (gold discs with a rim), nitro cans (blue bottles with a white band), smoke and sparkle
	-- puffs and wind streaks, each a pool parked out of sight when unused.
	local coinParts: { BasePart } = {}
	for i = 1, COINS do
		coinParts[i] = Kit.part({ Name = "Coin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.09, 0.52, 0.52) * S, Color = Color3.fromHex("#ffd54f"), Material = Enum.Material.Neon, CFrame = base * CFrame.new(0, -100 * S, 0) }, world)
	end
	local canParts: { Model } = {}
	for i = 1, CANS do
		local can = Instance.new("Model")
		can.Name = "Nitro"
		Kit.part({ Name = "Bottle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 0.32, 0.32) * S, CFrame = CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromHex("#1e88e5"), Material = Enum.Material.Metal }, can)
		Kit.part({ Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.33, 0.33) * S, CFrame = CFrame.Angles(0, 0, math.pi / 2), Color = Color3.fromHex("#fafafa") }, can)
		Kit.part({ Name = "Valve", Size = Vector3.new(0.12, 0.12, 0.12) * S, CFrame = CFrame.new(0, 0.3 * S, 0), Color = Color3.fromHex("#e53935") }, can)
		Kit.part({ Name = "Glow", Size = Vector3.new(1.2 * S, 0.02, 1.2 * S), CFrame = CFrame.new(0, -0.5 * S, 0), Color = Color3.fromHex("#40c4ff"), Material = Enum.Material.Neon, Transparency = 0.6 }, can)
		can.WorldPivot = CFrame.new()
		can:PivotTo(base * CFrame.new(0, -100 * S, 0))
		can.Parent = world
		canParts[i] = can
	end
	local streakParts: { BasePart } = {}
	local puffParts: { BasePart } = {}
	for i = 1, STREAKS do
		streakParts[i] = Kit.part({ Name = "Streak", Size = Vector3.new(0.05, 0.05, 1.6) * S, Color = Color3.new(1, 1, 1), Material = Enum.Material.Neon, Transparency = 0.45, CFrame = base * CFrame.new(0, -100 * S, 0) }, world)
	end
	for i = 1, PUFFS do
		puffParts[i] = Kit.part({ Name = "Puff", Shape = Enum.PartType.Ball, Size = Vector3.new(1, 1, 1), Color = Color3.fromHex("#eceff1"), Transparency = 0.2, CFrame = base * CFrame.new(0, -100 * S, 0) }, world)
	end

	-- ── The screen ───────────────────────────────────────────────────────────────────────────
	local screen = Kit.screen(ctx.gui)
	local closing = false
	local cleanup: () -> ()
	Kit.topBar(screen, "🚓 Getaway Chase", function()
		if closing then
			return
		end
		cleanup()
		ctx.finish(0, { quit = true })
	end)
	local row = Kit.hudRow(screen)
	local heartsPill = Kit.pill(row, 1, 16)
	local scorePill = Kit.pill(row, 2, 20, 70)
	local coinPill = Kit.pill(row, 3, 16)
	local nitroBar = Ui.new("Frame", { Name = "Nitro", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 94), Size = UDim2.fromOffset(200, 12), BackgroundColor3 = Color3.fromHex("#1b1f24"), BackgroundTransparency = 0.5, Visible = false, ZIndex = 20, Parent = screen }, {
		Ui.round(),
		Ui.stroke(2, Ui.WHITE),
	})
	local nitroFill = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 21, Parent = nitroBar }, {
		Ui.round(),
		Ui.new("UIGradient", { Color = Ui.seq("#00b0ff", "#80d8ff") }),
	})
	-- The cop's warning: a red glow round the screen's edges (.chase-warn).
	local warn = Ui.new("Frame", { Name = "Warn", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 15, Parent = screen })
	for i, e in { { UDim2.new(1, 0, 0, 70), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, 0, 70), UDim2.new(0, 0, 1, -70), -90 }, { UDim2.new(0, 70, 1, 0), UDim2.fromScale(0, 0), 0 }, { UDim2.new(0, 70, 1, 0), UDim2.new(1, -70, 0, 0), 180 } } do
		Ui.new("Frame", { Name = `Edge{i}`, Size = e[1], Position = e[2], BackgroundColor3 = Color3.fromHex("#ff1744"), BorderSizePixel = 0, ZIndex = 15, Parent = warn }, {
			Ui.new("UIGradient", { Rotation = e[3], Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }) }),
		})
	end
	local touch = UserInputService.TouchEnabled
	local tip = Kit.tip(screen, if touch then "👈 Swipe or tap to dodge 👉" else "👈 A / D or arrows to dodge 👉")
	tip.Visible = false

	-- ── The run, as ChaseScene's state ───────────────────────────────────────────────────────
	type Slot = { on: boolean, lane: number, z: number, hit: number, mine: boolean, x: number, y: number, spin: number, roll: number }
	local st = {
		t = 0,
		dist = 0,
		got = 0,
		hearts = arcade.CHASE_HEARTS,
		lane = 1, -- 0-based, as the web
		x = 0,
		safe = 0,
		rowIn = 0.8,
		shake = 0,
		over = false,
		overAt = 0,
		copZ = 6,
		copX = 0,
		road = 0,
		bonus = 0,
		streak = 0,
		comboLeft = 0,
		nitro = 0,
		clock = 0,
		cop = { phase = "idle", at = 0, lane = 1, next = arcade.COP_FROM },
	}
	local cars: { Slot } = {}
	for i = 1, #traffic do
		cars[i] = { on = false, lane = 0, z = 0, hit = 0, mine = false, x = 0, y = 0, spin = 0, roll = 0 }
	end
	local cans = {}
	for i = 1, CANS do
		cans[i] = { on = false, lane = 0, z = 0 }
	end
	local bags = {}
	for i = 1, COINS do
		bags[i] = { on = false, lane = 0, z = 0 }
	end
	local streaks = {}
	for i = 0, STREAKS - 1 do
		streaks[i + 1] = { x = (if i % 2 == 1 then 1 else -1) * (HALF + 0.2 + (i % 5) * 0.5), y = 0.4 + (i % 7) * 0.35, z = -60 + i * 2.3 }
	end
	local puffs = {}
	for i = 1, PUFFS do
		puffs[i] = { x = 0, y = 0, z = 0, vx = 0, vy = 0, age = 1, life = 1, gold = false }
	end
	local rand = Kit.rand(ctx.seed or 1)
	local moves: { number } = {}
	local running = false
	local busted = false

	local function puff(x: number, z: number, n: number, gold: boolean)
		for _ = 1, n do
			local p = nil
			for _, o in puffs do
				if o.age >= o.life then
					p = o
					break
				end
			end
			if not p then
				return
			end
			p.x, p.y, p.z = x + (rand() - 0.5) * 0.6, 0.3 + rand() * 0.3, z + (rand() - 0.5) * 0.6
			p.vx, p.vy = (rand() - 0.5) * 2.5, 1 + rand() * 1.5
			p.age, p.life, p.gold = 0, 0.5 + rand() * 0.4, gold
		end
	end
	local function say(text: string, kind: string)
		local look = POP[kind]
		Kit.pop(screen, text, look[1], look[2])
	end
	local function score(pts: number): number
		local m = arcade.comboMult(st.streak)
		st.bonus += pts * m
		return pts * m
	end
	local function loseHeart()
		st.hearts -= 1
		st.safe = 1.4
		st.shake = 0.5
		st.streak = 0
		st.comboLeft = 0
		Sfx.arcade.crash()
		puff(st.x, -0.6, 8, false)
		if st.hearts <= 0 then
			st.over = true
			st.overAt = st.clock
		end
		Sfx.arcade.siren()
	end

	-- The camera: taken over for the run, given back at the end.
	local cam = workspace.CurrentCamera
	local oldType, oldCf, oldFov = cam.CameraType, cam.CFrame, cam.FieldOfView
	TownCamera.setPaused(true)
	cam.CameraType = Enum.CameraType.Scriptable
	local function baseFov(): number
		local v = cam.ViewportSize
		return if v.X < v.Y then 70 else 50
	end
	cam.FieldOfView = baseFov()

	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * S, y * S, z * S)
	end
	local BACK = CFrame.Angles(0, math.pi, 0)

	local function frame(dt: number)
		dt = math.min(dt, 1 / 20)
		st.clock += dt
		local t = st.clock
		local go = running and not st.over
		st.nitro = math.max(0, st.nitro - (if go then dt else 0))
		local boost = if st.nitro > 0 then arcade.NITRO_SPEED else 1
		local v = if go then arcade.chaseSpeed(st.t) * boost elseif st.over then math.max(0, arcade.chaseSpeed(st.t) * (1 - (t - st.overAt) * 1.5)) else 0
		if go then
			st.t += dt
		end
		local move = v * dt
		if go then
			st.dist += move
		end
		if go and st.streak > 0 then
			st.comboLeft -= dt
			if st.comboLeft <= 0 then
				st.streak = 0
			end
		end
		-- Lane moves.
		while #moves > 0 do
			local m = table.remove(moves, 1) :: number
			if go then
				st.lane = math.clamp(st.lane + m, 0, 2)
			end
		end
		local tx = LANES[st.lane + 1]
		local prevX = st.x
		st.x += (tx - st.x) * math.min(1, dt * 12)
		local lean = (st.x - prevX) / math.max(dt, 1e-3)

		-- A new row of traffic every so often, more often as the run goes on.
		if go then
			st.rowIn -= dt * boost
			if st.rowIn <= 0 then
				st.rowIn = math.max(0.55, 1.25 - st.t * 0.008)
				local row = arcade.chaseRow(rand, st.t)
				for _, lane in row.cars do
					local free = {}
					for _, c in cars do
						if not c.on then
							table.insert(free, c)
						end
					end
					local slot = free[math.floor(rand() * #free) + 1]
					if slot then
						slot.on, slot.lane, slot.z, slot.hit, slot.mine = true, lane, SPAWN_Z + (rand() - 0.5) * 2, 0, false
					end
				end
				if row.coins ~= nil then
					for k = 0, 3 do
						for _, c in bags do
							if not c.on then
								c.on, c.lane, c.z = true, row.coins, SPAWN_Z + 5 + k * 1.4
								break
							end
						end
					end
				end
				if row.nitro ~= nil then
					for _, c in cans do
						if not c.on then
							c.on, c.lane, c.z = true, row.nitro, SPAWN_Z + 4
							break
						end
					end
				end
			end
		end

		-- Traffic drives the same way, slower than you, so it closes in at 70% of your speed.
		local close = move * 0.7
		local mine = collide.carBox({ x = st.x, z = 0, h = math.pi - lean * 0.03 }, foot)
		for i, c in cars do
			local g = trafficModels[i]
			if not c.on then
				continue
			end
			c.z += close
			local laneX = LANES[c.lane + 1]
			if go and c.hit == 0 and c.lane == st.lane and c.z > -arcade.NEAR_ZONE and c.z < -0.8 then
				c.mine = true
			end
			if c.hit > 0 then
				-- Knocked aside after a crash: spin off the road (and up from a nitro smash).
				c.hit += dt
				c.x += (if laneX >= 0 then 1 else -1) * dt * 6
				c.spin += dt * 7
				if c.hit > 0.01 and c.y > 0 then
					c.y = math.max(0, c.y + (6 - c.hit * 18) * dt)
					c.roll += dt * 9
				end
			end
			-- Passed it clean after it bore down on you in your lane: a near miss.
			if go and c.hit == 0 and c.mine and c.z > 1.6 then
				c.mine = false
				st.streak += 1
				st.comboLeft = arcade.COMBO_TIME
				local pts = score(arcade.NEAR_POINTS)
				local mult = arcade.comboMult(st.streak)
				Sfx.arcade.ding(1 + math.min(4, st.streak) * 0.12)
				say(if mult > 1 then `Near miss +{pts}  ×{mult}` else `Near miss +{pts}`, "near")
			end
			if c.z > 12 then
				c.on = false
			end
			if go and c.hit == 0 and collide.boxPush(mine, collide.carBox({ x = laneX, z = c.z, h = math.pi }, feet[i])) ~= nil then
				c.hit = 0.001
				c.mine = false
				c.x, c.y, c.spin, c.roll = laneX, 0, 0, 0
				if st.nitro > 0 then
					-- On nitro you plough straight through and send them flying.
					c.hit = 0.02
					c.y = 0.01
					st.shake = 0.25
					Sfx.arcade.crash()
					puff(laneX, c.z, 6, false)
					say(`Smash +{score(arcade.SMASH_POINTS)}`, "smash")
				elseif st.safe <= 0 then
					loseHeart()
				end
			end
			if c.on then
				if c.hit == 0 then
					g:PivotTo(at(laneX, 0, c.z) * BACK)
				else
					g:PivotTo(at(c.x, c.y, c.z) * BACK * CFrame.Angles(0, c.spin, 0) * CFrame.Angles(0, 0, c.roll))
				end
			else
				g:PivotTo(at(0, -100, 0))
			end
		end

		-- Coins bob and spin above the road.
		local collected = false
		for i, c in bags do
			if c.on then
				c.z += close
				if c.z > 8 then
					c.on = false
				end
				if go and c.on and collide.circlePush(mine, { x = LANES[c.lane + 1], z = c.z, r = COIN_R }) ~= nil then
					c.on = false
					st.got += 1
					-- The combo multiplies coins too: the coin counts once in the score, the rest is bonus.
					st.bonus += arcade.CHASE_COIN_POINTS * (arcade.comboMult(st.streak) - 1)
					collected = true
					puff(LANES[c.lane + 1], c.z, 3, true)
				end
			end
			coinParts[i].CFrame = if c.on then at(LANES[c.lane + 1], 0.5 + math.sin(t * 3 + i) * 0.06, c.z) * CFrame.Angles(0, t * 4 + i, 0) else at(0, -100, 0)
		end
		if collected then
			Sfx.coin()
		end

		-- Nitro cans spin above the road; grab one to boost.
		for i, c in cans do
			if c.on then
				c.z += close
				if c.z > 8 then
					c.on = false
				end
				if go and c.on and collide.circlePush(mine, { x = LANES[c.lane + 1], z = c.z, r = 0.35 }) ~= nil then
					c.on = false
					st.nitro = arcade.NITRO_TIME
					Sfx.arcade.rev(0.9)
					Sfx.arcade.air()
					puff(LANES[c.lane + 1], c.z, 4, true)
					say("NITRO!", "nitro")
				end
			end
			canParts[i]:PivotTo(if c.on then at(LANES[c.lane + 1], 0.55 + math.sin(t * 4 + i) * 0.08, c.z) * CFrame.Angles(0, t * 3, 0) else at(0, -100, 0))
		end

		-- Puffs drift up: smoke swells, sparkles shrink away.
		for i, p in puffs do
			p.age += dt
			local live = p.age < p.life
			if live then
				p.x += p.vx * dt
				p.y += p.vy * dt
				p.z += close
			end
			local k = if live then p.age / p.life else 1
			local size = if live then (if p.gold then 0.18 * (1 - k) else 0.25 + k * 0.5) else 0.01
			local part = puffParts[i]
			part.Size = Vector3.new(size, size, size) * S * 2
			part.Color = if p.gold then Color3.fromHex("#ffe082") else Color3.fromHex("#eceff1")
			part.Material = if p.gold then Enum.Material.Neon else Enum.Material.SmoothPlastic
			part.CFrame = if live then at(p.x, p.y, p.z) else at(0, -100, 0)
		end

		-- Wind streaks down both sides, long and bright on nitro.
		local fast = if st.nitro > 0 then 1 else math.max(0, (v - 20) / 10)
		for i, k in streaks do
			k.z += move * 1.6
			if k.z > 8 then
				k.z -= 66
			end
			local part = streakParts[i]
			if fast > 0 then
				part.Size = Vector3.new(0.05 * S, 0.05 * S, 1.6 * (0.5 + fast * 2.5) * S)
				part.CFrame = at(k.x, k.y, k.z)
			elseif part.CFrame.Position.Y > origin.Y - 50 * S then
				part.CFrame = at(0, -100, 0)
			end
		end

		-- The street stretches leapfrog past at your full speed.
		st.road += move
		local span = STRETCH * STRETCHES
		for i, g in stretches do
			local z = (((i - 1) * STRETCH + st.road) % span + span) % span - span + STRETCH + 14
			g:PivotTo(at(0, 0, z))
		end

		-- You: lean into lane changes, blink while you're safe after a crash.
		st.safe = math.max(0, st.safe - dt)
		local blink = st.safe <= 0 or math.floor(st.safe * 10) % 2 == 0
		player:PivotTo((if blink then at(st.x, 0, 0) else at(st.x, -100, 0)) * CFrame.Angles(0, math.pi - lean * 0.03, 0) * CFrame.Angles(0, 0, -lean * 0.012))

		-- The cop sits further back with every heart you have left and pulls alongside when you're
		-- caught; now and then it lines up behind your lane, flashes and lunges.
		local cp = st.cop
		if go and cp.phase == "idle" and st.t > cp.next and st.nitro <= 0 then
			cp.phase = "warn"
			cp.at = st.t
			cp.lane = st.lane
			Sfx.arcade.siren()
			say("⚠️ Cop!", "warn")
		end
		local copTarget = if st.over then 0 else 2 + st.hearts * 0.8
		local copX = st.copX + (st.x - st.copX) * math.min(1, dt * 3)
		if cp.phase ~= "idle" and not st.over then
			local since = st.t - cp.at
			copX = st.copX + (LANES[cp.lane + 1] - st.copX) * math.min(1, dt * 6)
			if cp.phase == "warn" then
				copTarget = 2 + st.hearts * 0.8 + 0.6
				if since > arcade.COP_WARN then
					cp.phase = "go"
					cp.at = st.t
					Sfx.arcade.rev(0.5)
				end
			elseif cp.phase == "go" then
				copTarget = 0.2
				st.copZ += (copTarget - st.copZ) * math.min(1, dt * 9)
				local caught = collide.boxPush(mine, collide.carBox({ x = st.copX, z = st.copZ, h = math.pi }, copFoot)) ~= nil
				if caught and st.safe <= 0 and st.nitro <= 0 then
					loseHeart()
					cp.phase = "back"
					cp.at = st.t
				elseif since > 0.5 then
					cp.phase = "back"
					cp.at = st.t
					if not caught then
						st.streak += 1
						st.comboLeft = arcade.COMBO_TIME
						say(`Dodged! +{score(arcade.COP_DODGE_POINTS)}`, "cop")
						Sfx.arcade.ding(1.5)
					end
				end
			elseif since > 0.8 then
				cp.phase = "idle"
				cp.next = st.t + arcade.copGap(rand, st.t)
			end
		end
		if cp.phase ~= "go" then
			st.copZ += (copTarget - st.copZ) * math.min(1, dt * 2)
		end
		st.copX = if st.over then st.x + (if st.lane == 2 then -1.5 else 1.5) else copX
		cop:PivotTo(at(st.copX, 0, st.copZ) * BACK)
		local flash = math.floor(t * (if cp.phase == "warn" then 14 else 6)) % 2 == 0
		red.Transparency = if flash then 0 else 0.75
		blue.Transparency = if flash then 0.75 else 0
		glow.Color = if flash then Color3.fromHex("#ff1744") else Color3.fromHex("#2979ff")

		-- The chase camera, with a little shake on a crash; it drops back and widens on nitro.
		st.shake = math.max(0, st.shake - dt)
		local j = st.shake * 0.4 + (if st.nitro > 0 then 0.05 else 0)
		local kick = math.min(1, st.nitro * 2)
		local eye = origin + Vector3.new((st.x * 0.5 + (math.random() - 0.5) * j) * S, (5.2 - kick * 0.5 + (math.random() - 0.5) * j) * S, (10 + kick * 0.8) * S)
		cam.CFrame = CFrame.lookAt(eye, origin + Vector3.new(st.x * 0.3 * S, 0, -7 * S))
		local fov = baseFov() + kick * 10
		if math.abs(cam.FieldOfView - fov) > 0.05 then
			cam.FieldOfView += (fov - cam.FieldOfView) * math.min(1, dt * 6)
		end

		-- The HUD.
		local hearts = ""
		for i = 1, arcade.CHASE_HEARTS do
			hearts ..= if i <= st.hearts then "❤️" else "🖤"
		end
		heartsPill.set(hearts)
		scorePill.set(Ui.commas(arcade.chaseScore(st.dist, st.got, st.bonus)))
		local mult = arcade.comboMult(st.streak)
		if mult > 1 then
			coinPill.set(`×{mult}`, Color3.fromHex("#ff6d00"))
		else
			coinPill.set(`🪙 {st.got}`, Color3.fromHex("#1b1f24"))
		end
		nitroBar.Visible = st.nitro > 0
		nitroFill.Size = UDim2.fromScale(st.nitro / arcade.NITRO_TIME, 1)
		warn.Visible = cp.phase == "warn"
		tip.Visible = running and st.dist < 40
		Kit.agePops(screen)

		if st.over and t - st.overAt > 1.6 and not busted then
			busted = true
			local final = arcade.chaseScore(st.dist, st.got, st.bonus)
			cleanup()
			ctx.finish(final, { dist = st.dist, coins = st.got, bonus = st.bonus })
		end
	end

	-- ── Input: a key press, a tap on either half or a swipe moves one lane ───────────────────
	local conns: { RBXScriptConnection } = {}
	local down: { x: number, done: boolean }? = nil
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.A or k == Enum.KeyCode.Left then
			table.insert(moves, -1)
		elseif k == Enum.KeyCode.D or k == Enum.KeyCode.Right then
			table.insert(moves, 1)
		elseif input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			down = { x = input.Position.X, done = false }
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = down
		if not d or d.done then
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
			if math.abs(input.Position.X - d.x) >= 30 then
				d.done = true
				table.insert(moves, if input.Position.X > d.x then 1 else -1)
			end
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		local d = down
		if not d or (input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1) then
			return
		end
		down = nil
		if not d.done and not busted then
			table.insert(moves, if input.Position.X > cam.ViewportSize.X / 2 then 1 else -1)
		end
	end))

	cleanup = function()
		if closing then
			return
		end
		closing = true
		RunService:UnbindFromRenderStep("ArcadeChase")
		for _, c in conns do
			c:Disconnect()
		end
		world:Destroy()
		cam.CameraType = oldType
		cam.CFrame = oldCf
		cam.FieldOfView = oldFov
		TownCamera.setPaused(false)
	end

	local count = Kit.countdown(screen, function()
		running = true
		Sfx.arcade.siren()
	end)
	RunService:BindToRenderStep("ArcadeChase", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		count(dt)
		frame(dt)
	end)
	-- For the previews: the state, and a step to run frames by hand.
	Chase.debug = { state = st, frame = function(dt: number)
		count(dt)
		frame(dt)
	end, moves = moves }
end

return Chase
