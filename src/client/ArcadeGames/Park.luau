--!strict
-- Parking Pro, as the web game's ParkScene (scene/ParkScene.tsx) and ParkGame (ui/Arcade.tsx): drive
-- your own car into the marked spot of one of eight lots and hold still, without denting anything.
-- The lots, the car's steering (game/arcade.ts drive, parkedIn, lotSolids) and the knocks
-- (game/collide.ts step, carBox) are the converted rules; three knocks end the run. The time,
-- the knocks and whether you parked go to the server, which works out the stars and the pay.
--
-- Everything is worked out in web units on the lot's own ground (the spot towards -z, the way in
-- at +z), and drawn 10 studs to a unit from ctx.origin.

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

local Park = {}
Park.id = "park"

local S = Kit.S
local MAX_FWD = 3.4
local MAX_REV = 2.2
local WALK = 1.4 -- sidewalk round the lot
local BIG = 1.2 -- town buildings drawn this much bigger, to suit the lot's cars (ParkScene S)
local FOV = 40 -- PARK_CAM

-- The shops that line the top of each lot, so every lot is somewhere in town.
local BACKDROPS: { { string } } = {
	{ "coffee", "donut", "icecream", "pizza" },
	{ "pizza", "tacos", "coffee", "burger" },
	{ "diner", "tires", "lube" },
	{ "market", "bowling", "arcade" },
	{ "tuner", "parts", "bodyshop" },
	{ "motel", "club" },
	{ "stadium" },
	{ "cinema", "club", "bowling" },
}

-- The showroom's everyday cars, parked in the other stalls.
local PARKED_BODIES = { sedan = true, compact = true, suv = true, hatch = true, wagon = true, van = true, classic = true, coupe = true, truck = true, ev = true, luxury = true, muscle = true }
local function parkedPool(): { any }
	local out = {}
	for _, c in data.CARS do
		if not c.parked and not data.isBike(c.body) and PARKED_BODIES[c.body] then
			table.insert(out, c)
		end
	end
	return out
end

local function hasBuilding(id: string): boolean
	for _, b in data.BUILDINGS do
		if b.id == id then
			return true
		end
	end
	return false
end

local ASPHALT = Color3.fromHex("#5b6068")
local PAVER = Color3.fromHex("#d9d6cf")
local KERB = Color3.fromHex("#d7dade")
local PAINT = Color3.fromHex("#f5f5f5")

-- Everything that never moves (LotScenery): the lot, its markings, the sidewalk, the shops, the
-- street and the planting.
local function scenery(lot: any, index: number, base: CFrame, parent: Instance)
	local W, L = lot.w, lot.l
	local function box(name: string, x: number, y: number, z: number, w: number, h: number, l: number, color: Color3, ry: number?, mat: Enum.Material?): Part
		return Kit.part({ Name = name, Size = Vector3.new(w * S, math.max(h * S, 0.02), l * S), CFrame = base * CFrame.new(x * S, y * S, z * S) * CFrame.Angles(0, ry or 0, 0), Color = color, Material = mat or Enum.Material.SmoothPlastic }, parent)
	end
	-- A painted line (Line): w across, l along, turned by h; it sits just on the asphalt.
	local function line(x: number, z: number, h: number, w: number, l: number, color: Color3?, lift: number?)
		box("Paint", x, 0.003 + (lift or 0), z, w, 0.002, l, color or PAINT, h)
	end
	-- Grass round everything, then the lot with its sidewalk and kerb.
	box("Grass", 0, -0.06, 0, 70, 0.1, 70, Color3.fromHex("#6fae4f"), 0, Enum.Material.Grass)
	box("Lot", 0, -0.005, 0, W, 0.01, L, ASPHALT)
	for _, r in { { 0, -L / 2 - WALK / 2, W + WALK * 2, WALK }, { 0, L / 2 + WALK / 2, W + WALK * 2, WALK }, { -W / 2 - WALK / 2, 0, WALK, L }, { W / 2 + WALK / 2, 0, WALK, L } } do
		box("Walk", r[1], 0.07, r[2], r[3], 0.14, r[4], PAVER)
	end
	for _, r in { { 0, -L / 2 - 0.05, W + 0.2, 0.1 }, { 0, L / 2 + 0.05, W + 0.2, 0.1 }, { -W / 2 - 0.05, 0, 0.1, L }, { W / 2 + 0.05, 0, 0.1, L } } do
		box("Kerb", r[1], 0.08, r[2], r[3], 0.16, r[4], KERB)
	end
	-- The way in: an arrow painted at the bottom, pointing into the lot.
	local ax, az = lot.start.x, L / 2 - 0.5
	line(ax, az + 0.25, 0, 0.16, 0.7)
	for _, sd in { -1, 1 } do
		line(ax + sd * 0.13, az - 0.2, sd * 0.75, 0.12, 0.42)
	end
	-- Shops along the top.
	local list = {}
	for _, d in BACKDROPS[index + 1] or BACKDROPS[1] do
		if hasBuilding(d) then
			table.insert(list, d)
		end
	end
	local backZ = -L / 2 - WALK - 0.3
	local x = -W / 2 - 6
	local i = 0
	while x < W / 2 + 6 and #list > 0 do
		local def = data.buildingDef(list[i % #list + 1])
		i += 1
		local w, d = def.w * data.TILE * BIG, def.h * data.TILE * BIG
		local cx, cz = x + w / 2, backZ - d / 2
		box("ShopLot", cx, 0.002, cz, w + 0.5, 0.004, d, PAVER)
		local b = Kit.library("Buildings", def.id)
		if b then
			Kit.scale(b, BIG)
			b:PivotTo(base * CFrame.new(cx * S, 0, cz * S))
			b.Parent = parent
		end
		x += w + 0.5
	end
	-- A street along the bottom, with a far sidewalk and a row of trees.
	local roadZ = L / 2 + WALK + 2
	box("Road", 0, -0.005, roadZ, 40, 0.01, 4, Color3.fromHex("#4a4f57"))
	for n = 0, 12 do
		line(-18 + n * 3, roadZ, math.pi / 2, 0.1, 1.4)
	end
	box("FarWalk", 0, 0.07, roadZ + 2.7, 40, 0.14, 1.4, PAVER)
	local function tree(id: string, tx: number, tz: number, k: number)
		local t = Kit.library("Buildings", id)
		if t then
			Kit.scale(t, k)
			t:PivotTo(base * CFrame.new(tx * S, 0, tz * S))
			t.Parent = parent
		else
			Kit.tree(base, tx, tz, false, k, parent)
		end
	end
	for n = 0, 7 do
		tree(if n % 3 == 1 then "pine" else "tree", -14 + n * 4, roadZ + 4.3, BIG * 0.9)
	end
	-- Planting down both sides, and lamps along the kerb.
	for _, sd in { -1, 1 } do
		for n = 0, 4 do
			tree(if n % 2 == 1 then "pine" else "tree", sd * (W / 2 + WALK + 1.1), -L / 2 + 1.5 + n * ((L - 3) / 4), BIG * 0.85)
		end
		for _, z in { -L / 2 + 0.6, 0, L / 2 - 0.6 } do
			Kit.lamp(base, sd * (W / 2 + 0.45), z, if sd > 0 then -math.pi / 2 else math.pi / 2, parent)
		end
	end
	-- A hydrant and two bins on the sidewalk (ArcadeScenery Hydrant, Bin).
	local up = CFrame.Angles(0, 0, math.pi / 2)
	local hx, hz = W / 2 + WALK * 0.6, L / 2 + WALK * 0.5
	Kit.part({ Name = "Hydrant", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.16, 0.16) * S, CFrame = base * CFrame.new(hx * S, 0.29 * S, hz * S) * up, Color = Color3.fromHex("#e53935") }, parent)
	Kit.part({ Name = "Nozzles", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.23, 0.06, 0.06) * S, CFrame = base * CFrame.new(hx * S, 0.33 * S, hz * S), Color = Color3.fromHex("#c62828") }, parent)
	for _, sd in { -1, 1 } do
		local bx, bz = sd * (W / 2 + WALK * 0.6), -L / 2 - WALK * 0.5
		Kit.part({ Name = "Bin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.37, 0.22, 0.22) * S, CFrame = base * CFrame.new(bx * S, 0.33 * S, bz * S) * up, Color = Color3.fromHex("#2e7d32") }, parent)
		Kit.part({ Name = "Lid", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.035, 0.25, 0.25) * S, CFrame = base * CFrame.new(bx * S, 0.53 * S, bz * S) * up, Color = Color3.fromHex("#1b5e20") }, parent)
	end
	-- Stall lines and wheel stops: the other cars' stalls and the spot.
	local stalls = {}
	for _, p in lot.cars do
		table.insert(stalls, { x = p.x, z = p.z, h = p.h, w = arcade.PARKED_W + 0.5, l = arcade.PARK_LEN + 0.6 })
	end
	table.insert(stalls, lot.spot)
	for _, b in stalls do
		local c, s = math.cos(b.h), math.sin(b.h)
		for _, sd in { -1, 1 } do
			line(b.x + sd * b.w / 2 * c, b.z - sd * b.w / 2 * s, b.h, 0.07, b.l)
		end
		-- The wheel stop sits at the stall's far end: the one further from the middle of the lot.
		local ex1, ez1 = b.x + (b.l / 2 - 0.12) * s, b.z + (b.l / 2 - 0.12) * c
		local ex2, ez2 = b.x - (b.l / 2 - 0.12) * s, b.z - (b.l / 2 - 0.12) * c
		local sx, sz = ex1, ez1
		if ex1 * ex1 + ez1 * ez1 < ex2 * ex2 + ez2 * ez2 then
			sx, sz = ex2, ez2
		end
		box("WheelStop", sx, 0.05, sz, 0.62, 0.1, 0.14, Color3.fromHex("#e0dcd5"), b.h)
	end
	-- Brick walls with a stone cap, and cones.
	for _, w in lot.walls do
		box("Wall", w.x, 0.35, w.z, w.w, 0.7, w.l, Color3.fromHex("#c9907a"), w.h, Enum.Material.Brick)
		box("Cap", w.x, 0.72, w.z, w.w + 0.06, 0.06, w.l + 0.06, Color3.fromHex("#cfc6bb"), w.h)
	end
	for _, c in lot.cones do
		box("ConeBase", c.x, 0.02, c.z, 0.4, 0.04, 0.4, Color3.fromHex("#e65100"))
		-- The cone as three bands, narrowing to the top, with a white stripe.
		for n, r in { { 0.34, 0.12, "#ff6d00" }, { 0.24, 0.27, "#ffffff" }, { 0.17, 0.4, "#ff6d00" } } :: { { any } } do
			Kit.part({ Name = `Cone{n}`, Shape = Enum.PartType.Cylinder, Size = Vector3.new(if n == 2 then 0.08 else 0.16, r[1], r[1]) * S, CFrame = base * CFrame.new(c.x * S, r[2] * S, c.z * S) * up, Color = Color3.fromHex(r[3]) }, parent)
		end
	end
end

function Park.play(ctx: any)
	local index = (ctx.lot or 1) - 1
	local lot = arcade.PARK_LOTS[index + 1]
	local origin: Vector3 = ctx.origin
	local base = CFrame.new(origin)
	local world = Instance.new("Folder")
	world.Name = "ArcadePark"
	world.Parent = workspace
	scenery(lot, index, base, world)
	local function at(x: number, z: number, h: number): CFrame
		return base * CFrame.new(x * S, 0, z * S) * CFrame.Angles(0, h, 0)
	end

	-- The spot: a pulsing fill and a yellow outline.
	local spot = lot.spot
	local fill = Kit.part({ Name = "SpotFill", Size = Vector3.new(spot.w * S, 0.02, spot.l * S), CFrame = at(spot.x, spot.z, spot.h) * CFrame.new(0, 0.012, 0), Color = Color3.fromHex("#ffd54f"), Material = Enum.Material.Neon, Transparency = 0.65 }, world)
	do
		local c, s = math.cos(spot.h), math.sin(spot.h)
		local t = 0.09
		for _, side in { { -spot.w / 2, 0, t, spot.l }, { spot.w / 2, 0, t, spot.l }, { 0, -spot.l / 2, spot.w + t, t }, { 0, spot.l / 2, spot.w + t, t } } do
			local lx, lz = side[1], side[2]
			local x, z = spot.x + lx * c + lz * s, spot.z - lx * s + lz * c
			Kit.part({ Name = "SpotLine", Size = Vector3.new(side[3] * S, 0.03, side[4] * S), CFrame = at(x, z, spot.h) * CFrame.new(0, 0.03, 0), Color = Color3.fromHex("#ffd54f") }, world)
		end
	end

	-- The other cars, each fitted to the lot's car size, and what the player can hit.
	local pool = parkedPool()
	local feet = {}
	for i, p in lot.cars do
		local c = pool[((i - 1) * 5 + index * 3) % #pool + 1]
		local m, f = Kit.car({ model = c.id, color = c.colors[((i - 1) + index) % #c.colors + 1] }, arcade.PARK_LEN, arcade.PARKED_W, world)
		Kit.shadow(f.l, f.w, m)
		m:PivotTo(at(p.x, p.z, p.h))
		feet[i] = collide.carBox(p, f)
	end
	local solids = arcade.lotSolids(lot, feet)
	local player, foot = Kit.car(ctx.car, arcade.PARK_LEN, arcade.PARKED_W, world)
	Kit.shadow(foot.l, foot.w, player)
	player:PivotTo(at(lot.start.x, lot.start.z, lot.start.h))

	-- ── The screen ───────────────────────────────────────────────────────────────────────────
	local screen = Kit.screen(ctx.gui)
	local closing = false
	local cleanup: () -> ()
	Kit.topBar(screen, `🅿️ {index + 1}. {lot.name}`, function()
		if closing then
			return
		end
		cleanup()
		ctx.finish(0, { quit = true })
	end)
	local row = Kit.hudRow(screen)
	local timePill = Kit.pill(row, 1, 18, 133)
	timePill.label.RichText = true
	local spotPill = Kit.pill(row, 2, 18, 115)
	local bumpPill = Kit.pill(row, 3, 18)
	local touch = UserInputService.TouchEnabled
	local drive = Kit.drive(screen, touch)
	drive.show(false)
	local input = drive.input

	-- ── The run, as ParkScene's state ────────────────────────────────────────────────────────
	local st = {
		pose = { x = lot.start.x, z = lot.start.z, h = lot.start.h },
		v = 0,
		steer = 0,
		t = 0,
		bumps = 0,
		cool = 0,
		hold = 0,
		done = false,
		inSpot = false,
		jolt = 0,
		pitch = 0,
		roll = 0,
		joltT = 0,
		clock = 0,
	}
	local running = false

	-- The camera: taken over for the run, given back at the end.
	local cam = workspace.CurrentCamera
	local oldType, oldCf, oldFov = cam.CameraType, cam.CFrame, cam.FieldOfView
	TownCamera.setPaused(true)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FOV
	local eyeAt: Vector3? = nil
	local aimAt: Vector3? = nil
	-- The camera frames your car and the spot together, zoomed in as close as that allows (never
	-- past the whole lot); on a wide screen the view turns so the lot's long side runs across it.
	local function frameCam(x: number, z: number, k: number)
		local size = cam.ViewportSize
		local wide = size.X > size.Y
		local ratio = size.X / math.max(1, size.Y)
		local sx, sz = spot.x, spot.z
		local cx, cz = (x + sx) / 2, (z + sz) / 2
		local spanX = math.min(lot.w / 2 + 1.2, math.max(4.2, math.abs(x - sx) / 2 + 2.6))
		local spanZ = math.min(lot.l / 2 + 1.2, math.max(4.2, math.abs(z - sz) / 2 + 2.6))
		local half = math.tan(math.rad(FOV / 2))
		-- Extra height leaves room for the controls over the edges of the view.
		local height = 1.25 * (if wide then math.max(spanX / half, spanZ / (half * ratio)) else math.max(spanZ / half, spanX / (half * ratio)))
		-- Keep the view inside the lot so it doesn't drift off over the kerb.
		local fx = math.clamp(cx, -lot.w / 2 + spanX - 1.2, math.max(-lot.w / 2 + spanX - 1.2, lot.w / 2 - spanX + 1.2))
		local fz = math.clamp(cz, -lot.l / 2 + spanZ - 1.2, math.max(-lot.l / 2 + spanZ - 1.2, lot.l / 2 - spanZ + 1.2))
		local eye = origin + Vector3.new((fx - (if wide then height * 0.28 else 0)) * S, height * S, (fz + (if wide then 0 else height * 0.28)) * S)
		local aim = origin + Vector3.new(fx * S, 0, fz * S)
		local e, a = eyeAt, aimAt
		e = if e then e:Lerp(eye, k) else eye
		a = if a then a:Lerp(aim, k) else aim
		eyeAt, aimAt = e, a
		cam.CFrame = CFrame.lookAt(e :: Vector3, a :: Vector3, if wide then Vector3.new(1, 0, 0) else Vector3.new(0, 0, -1))
	end
	frameCam(lot.start.x, lot.start.z, 1)

	local function frame(dt: number)
		dt = math.min(dt, 1 / 20)
		st.clock += dt
		local live = running and not st.done
		if live then
			st.t += dt
		end
		local pedal = if live then input.gas - input.brake else 0
		if pedal > 0 then
			st.v = math.min(MAX_FWD, st.v + (if st.v < 0 then 9 else 4) * dt)
		elseif pedal < 0 then
			st.v = math.max(-MAX_REV, st.v - (if st.v > 0 then 9 else 4) * dt)
		else
			st.v = math.sign(st.v) * math.max(0, math.abs(st.v) - 6 * dt)
		end
		st.steer += ((if live then input.steer else 0) * 0.62 - st.steer) * math.min(1, dt * 8)
		st.cool = math.max(0, st.cool - dt)

		if st.v ~= 0 then
			-- Scrape along whatever you touch; any real knock is a bump on your record.
			local r = collide.step(st.pose, st.v, arcade.drive(st.pose, st.v, st.steer, dt), foot, solids)
			st.pose = r.pose
			st.v = r.v
			if r.impact > 0.15 and st.cool <= 0 and live then
				st.bumps += 1
				st.cool = 1
				local c, sn = math.cos(st.pose.h), math.sin(st.pose.h)
				st.jolt = math.min(1, 0.4 + r.impact / 3)
				st.pitch = r.nx * sn + r.nz * c
				st.roll = r.nx * c - r.nz * sn
				st.joltT = 0
			end
		end
		st.joltT += dt

		st.inSpot = arcade.parkedIn(collide.carBox(st.pose, foot), spot)
		st.hold = if st.inSpot and math.abs(st.v) < 0.3 and live then st.hold + dt else 0
		local ended: boolean? = nil
		if live and st.hold > 0.6 then
			st.done = true
			ended = true
		elseif live and st.bumps >= arcade.PARK_MAX_BUMPS then
			st.done = true
			ended = false
		end

		frameCam(st.pose.x, st.pose.z, math.min(1, dt * 2.5))
		-- Rock away from a knock and settle.
		local wob = st.jolt * math.exp(-st.joltT * 7) * math.cos(st.joltT * 26)
		player:PivotTo(at(st.pose.x, st.pose.z, st.pose.h) * CFrame.Angles(-st.pitch * wob * 0.14, 0, st.roll * wob * 0.1))
		-- "Hold still" (and the green spot) only once the car is in and slowing down.
		local settling = st.inSpot and math.abs(st.v) < 1.2
		fill.Color = if settling then Color3.fromHex("#00e676") else Color3.fromHex("#ffd54f")
		fill.Transparency = 1 - (0.28 + math.sin(st.clock * 5) * 0.1 + (if settling then 0.2 else 0))

		-- The HUD.
		Ui.setText(timePill.label, string.format('⏱ %.1fs <font size="13" transparency="0.3">/ %gs</font>', st.t, lot.par))
		spotPill.set(if settling then "✅ Hold still" else "🅿️", if settling then Color3.fromHex("#009646") else Color3.fromHex("#1b1f24"))
		spotPill.frame.BackgroundTransparency = if settling then 0.15 else 0.35
		bumpPill.set(`💥 {st.bumps}/{arcade.PARK_MAX_BUMPS}`)

		if ended ~= nil then
			local final = { time = st.t, bumps = st.bumps, parked = ended }
			cleanup()
			ctx.finish(final.time, { bumps = final.bumps, parked = final.parked, lot = ctx.lot })
		end
	end

	cleanup = function()
		if closing then
			return
		end
		closing = true
		RunService:UnbindFromRenderStep("ArcadePark")
		drive.destroy()
		world:Destroy()
		cam.CameraType = oldType
		cam.CFrame = oldCf
		cam.FieldOfView = oldFov
		TownCamera.setPaused(false)
	end

	local count = Kit.countdown(screen, function()
		running = true
		drive.show(true)
	end)
	local function step(dt: number)
		count(dt)
		frame(dt)
	end
	RunService:BindToRenderStep("ArcadePark", Enum.RenderPriority.Camera.Value + 1, step)
	-- For the previews: the state, the controls' input and a step to run frames by hand.
	Park.debug = { state = st, input = input, frame = step }
end

return Park
