--!strict
-- Pit Stop, as the web game's PitScene (scene/PitScene.tsx) and its screen (PitGame in
-- ui/ArcadeMore.tsx). The car comes down the pit lane at the limiter and the player brakes it onto
-- the box. The crew jacks it up and the crew chief calls the order the wheels come off. Every
-- corner's ring fills; a tap on green undoes the nut, the crew swaps the wheel, and a second green
-- tap does the new one up. Then the lollipop man holds the car (the clock stops) until the lane is
-- clear, and the player goes on green. The result is the time in seconds (lower is better).
--
-- Every rule and number comes from the converted game/arcadeMore.ts (Shared.Game.arcadeMore).
-- Pit.new(ctx) builds a round that a frame loop steps; Pit.play(ctx) runs it on RenderStepped
-- with touch and keyboard input (tools/emulate/arcade-pitwash.luau steps it by hand).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local arcadeMore = require(Game.arcadeMore) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Parent.Ui)
local Kit = require(script.Parent.StarKit)

local CALL_MISS, CALL_SHOW, GUN_SLIP, PIT_BRAKE, PIT_COAST, PIT_JUMP, PIT_SPEED, PIT_START =
	arcadeMore.CALL_MISS, arcadeMore.CALL_SHOW, arcadeMore.GUN_SLIP, arcadeMore.PIT_BRAKE, arcadeMore.PIT_COAST, arcadeMore.PIT_JUMP, arcadeMore.PIT_SPEED, arcadeMore.PIT_START

local Pit = { id = "pit" }

local S = Kit.S
local hex = Kit.hex
local LEN = 3.4 -- the player's car, drawn this long: true to the crew beside it
local TEAM = "#e53935"
local TEAMS = {
	{ "BOLT MOTORSPORT", "#1e88e5", "#ffffff" },
	{ "APEX GP", "#2e7d32", "#ffffff" },
	{ "CARTOPIA RACING", TEAM, "#ffffff" },
	{ "NOVA RACING", "#fb8c00", "#1a1a1a" },
	{ "ZEPHYR TEAM", "#6a1b9a", "#ffffff" },
}
local BAY = 7 -- garage bay width
local BOX_W = 6 -- the painted pit box
local BOX_D = 4.6
local WALL = 6 -- the pit wall, past the fast lane
local FAST = 4.3 -- middle of the fast lane, where other cars pass
local RIG = { -2.3, -3.55 } -- the fuel rig on the garage apron
local CREW_K = 1.45 -- crew size: about 1.8 m beside a 4.5 m car
local FAN = 1.3 -- ArcadeScenery's crowd unit
local CAM_FOV = 45 -- PIT_CAM
local CHIP_DARK = Color3.fromRGB(27, 31, 36) -- the web's rgba(27,31,36,a) chips
local RACERS ={ formula = true, super = true, sports = true, muscle = true, coupe = true }

local function ease(k: number): number
	return k * k * (3 - 2 * k)
end

-- JavaScript's %, which keeps the sign of the left side.
local function jsmod(a: number, b: number): number
	return math.fmod(a, b)
end

local function round1(x: number): number
	return math.floor(x * 10 + 0.5) / 10
end

-- The result card's line (pitLine in ArcadeMore.tsx).
local function pitLine(e: { time: number, grade: string, react: number, slips: number }): string
	local emoji = if e.grade == "perfect" then "🎯" elseif e.grade == "good" then "👍" else "😬"
	local words = if e.grade == "perfect" then "Perfect stop" elseif e.grade == "good" then "Good stop" else "Pushed"
	local slips = if e.slips > 0 then ` · {e.slips} slip{if e.slips > 1 then "s" else ""}` else ""
	return `⏱ {string.format("%.1f", e.time)}s · {emoji} {words} · ⚡ {string.format("%.2f", e.react)}s{slips}`
end
Pit.line = pitLine

-- ── Scenery: everything that never moves (PitScenery) ──────────────────────────────────────────

local function buildScenery(into: Instance, O: Vector3, rand: () -> number)
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(O + Vector3.new(x, y, z) * S)
	end
	local function box(w: number, h: number, d: number, x: number, y: number, z: number, color: string, material: Enum.Material?): Part
		return Kit.part({ Size = Vector3.new(w, h, d) * S, CFrame = at(x, y, z), Color = hex(color), Material = material or Enum.Material.SmoothPlastic }, into)
	end
	-- Paint on the lane (the web's Paint): a flat strip `w` along x, `l` along z.
	local function paint(x: number, z: number, w: number, l: number, color: string?, ry: number?)
		Kit.part({ Size = Vector3.new(w * S, 0.1, l * S), CFrame = at(x, 0, z) * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, ry or 0, 0), Color = hex(color or "#ffd54f") }, into)
	end
	local function signBoard(w: number, h: number, cf: CFrame, text: string, bg: string, fg: string)
		local p = Kit.part({ Size = Vector3.new(w * S, h * S, 0.2), CFrame = cf, Color = hex(bg) }, into)
		Kit.sign(p, text, fg, bg)
	end
	local function pitBox(x: number, mark: boolean)
		paint(x, -BOX_D / 2, BOX_W, 0.12)
		paint(x, BOX_D / 2, BOX_W, 0.12)
		paint(x - BOX_W / 2, 0, 0.12, BOX_D)
		paint(x + BOX_W / 2, 0, 0.12, BOX_D)
		if mark then
			-- Where the front wheels stop, and a chevron pointing the way in.
			paint(x + LEN * 0.33, 0, 0.24, BOX_D - 0.4, "#fafafa")
			for _, sd in { -1, 1 } do
				paint(x - BOX_W / 2 - 0.9, sd * 0.38, 0.9, 0.16, "#fafafa", sd * 0.7)
			end
		end
	end

	-- Grass all round, the pit lane from the garage apron to the wall, the apron.
	box(120, 0.1, 80, 0, -0.05, 4, "#7cb85a", Enum.Material.Grass)
	box(80, 0.1, WALL + 4.7, 0, -0.035, (WALL - 4.7) / 2, "#55595f", Enum.Material.Asphalt)
	box(80, 0.1, 1.4, 0, -0.02, -4.7, "#cfd8dc", Enum.Material.Concrete)
	paint(0, 2.75, 80, 0.12, "#fafafa")
	for i = 0, 25 do
		paint(-39 + i * 3, WALL - 0.35, 1.4, 0.1, "#fafafa")
	end
	pitBox(0, true)
	for _, k in { -2, -1, 1, 2 } do
		pitBox(k * BAY, false)
	end

	-- Garage block: bays, a hospitality floor above, roof and flags.
	for i = -5, 5 do
		local team = TEAMS[(jsmod(i, #TEAMS) + #TEAMS + 2) % #TEAMS + 1]
		local name, bg, fg = team[1], team[2], team[3]
		local x, open = i * BAY, i == 0
		local z0 = -5.4
		box(BAY - 0.5, 0.1, 5, x, -0.01, z0 - 2.6, "#5f6368")
		box(BAY - 0.5, 3.4, 0.1, x, 1.7, z0 - 5, bg)
		signBoard(BAY * 0.5, BAY * 0.1, at(x, 2.3, z0 - 4.92), name, bg, fg)
		if open then
			Kit.toolChest(into, O, x - 2.4, z0 - 4.5, bg)
			Kit.toolChest(into, O, x - 1.4, z0 - 4.5, bg)
			Kit.tyreStack(into, O, x + 1.6, z0 - 4.4, 5, TEAM)
			Kit.tyreStack(into, O, x + 2.2, z0 - 4.4, 4, "#ffd54f")
			Kit.tyreStack(into, O, x + 1.9, z0 - 3.8, 3, "#fafafa")
			-- Spare nose cone on a stand, and the timing screens over the chests.
			box(0.2, 1, 0.2, x - 2.6, 0.5, z0 - 2.6, "#455a64")
			Kit.part({ Size = Vector3.new(1, 0.5, 0.5) * S, CFrame = at(x - 2.6, 1.05, z0 - 2.6) * CFrame.Angles(0, math.pi / 2, 0), Color = hex(bg), Shape = Enum.PartType.Cylinder }, into)
			for _, dx in { -2.4, -1.4 } do
				Kit.part({ Size = Vector3.new(0.8 * S, 0.5 * S, 0.1), CFrame = at(x + dx, 1.9, z0 - 4.93), Color = hex("#4fc3f7"), Material = Enum.Material.Neon }, into)
			end
		end
		-- The shutter: rolled up when open, else down to just above head height.
		box(BAY - 0.5, if open then 0.4 else 1.9, 0.08, x, if open then 3.2 else 2.25, z0 - 0.05, "#d0d4d8", Enum.Material.DiamondPlate)
		box(0.5, 3.4, 5.2, x - BAY / 2, 1.7, z0 - 2.5, "#eceff1", Enum.Material.Concrete)
		box(BAY, 0.7, 0.3, x, 3.75, z0 - 0.1, bg)
		signBoard(BAY * 0.6, BAY * 0.12, at(x, 3.75, z0 + 0.06), name, bg, fg)
	end
	box(11 * BAY, 2.6, 5.4, 0, 5.4, -8, "#b0bec5", Enum.Material.Concrete)
	box(11 * BAY, 1.1, 0.1, 0, 5.5, -5.27, "#4f6d84", Enum.Material.Glass)
	box(11 * BAY, 0.2, 0.9, 0, 4.15, -5.2, "#eceff1")
	box(11 * BAY, 0.05, 0.05, 0, 5.2, -5.5, "#90a4ae")
	for i = 0, 29 do
		box(0.05, 1, 0.05, -37.7 + i * 2.6, 4.75, -5.5, "#90a4ae")
	end
	box(11 * BAY + 0.6, 0.25, 6, 0, 6.8, -8, "#eceff1")
	for i = 0, 11 do
		box(0.06, 1.8, 0.06, -33 + i * 6, 6.9 + 0.9, -5.6, "#cfd8dc")
		box(0.7, 0.42, 0.02, -33 + i * 6 + 0.35, 6.9 + 1.55, -5.6, TEAMS[i % #TEAMS + 1][2])
	end

	-- Pit wall with team panels and the catch fence.
	box(80, 0.9, 0.4, 0, 0.45, WALL, "#eceff1", Enum.Material.Concrete)
	for i = 0, 15 do
		local t = TEAMS[i % #TEAMS + 1]
		signBoard(4.2, 0.55, at(-37.5 + i * 5, 0.45, WALL - 0.21) * CFrame.Angles(0, math.pi, 0), t[1], t[2], t[3])
	end
	for i = 0, 26 do
		Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 0.1, 0.1) * S, CFrame = at(-39 + i * 3, 2, WALL + 0.1) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#78909c") }, into)
	end
	for _, y in { 1.3, 2, 2.7 } do
		box(80, 0.02, 0.02, 0, y, WALL + 0.1, "#90a4ae")
	end

	-- The track beyond the wall, kerbs, a tyre wall, and the grandstand.
	local T = WALL - 4.7
	box(80, 0.1, 8, 0, -0.035, 9.2 + T, "#55595f", Enum.Material.Asphalt)
	paint(0, 5.6 + T, 80, 0.14, "#fafafa")
	paint(0, 12.8 + T, 80, 0.14, "#fafafa")
	for i = 0, 39 do
		paint(-39 + i * 2, 13.4 + T, 1, 0.7, if i % 2 == 1 then "#fafafa" else "#e53935")
	end
	for i = 0, 59 do
		for r = 0, 1 do
			local c = if (i + r) % 3 == 0 then "#e53935" elseif (i + r) % 3 == 1 then "#fafafa" else "#1e88e5"
			Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 0.64, 0.64) * S, CFrame = at(-39.5 + i * 1.33 + r * 0.66, 0.3 + r * 0.02, 14.2 + T + r * 0.55) * CFrame.Angles(0, 0, math.pi / 2), Color = hex(c) }, into)
		end
	end
	-- The grandstand (ArcadeScenery Grandstand), facing the track, with its fans.
	local gz, width, rows = 17.5 + T, 34, 5
	for r = 0, rows - 1 do
		box(width, 0.35 + r * 0.4, 0.7, 0, 0.17 + r * 0.2, gz + r * 0.7, if r % 2 == 1 then "#cfd8dc" else "#b0bec5", Enum.Material.Concrete)
	end
	for _, sd in { -1, 1 } do
		box(0.12, 3.2 + rows * 0.4, 0.12, sd * (width / 2 - 0.1), 1.6 + rows * 0.2, gz + rows * 0.7 - 0.3, "#455a64")
	end
	Kit.part({ Size = Vector3.new(width + 0.4, 0.1, rows * 0.7 + 0.6) * S, CFrame = at(0, 3.2 + rows * 0.4, gz + rows * 0.35) * CFrame.Angles(0.12, 0, 0), Color = hex(TEAM) }, into)
	local fans = Instance.new("Folder")
	fans.Name = "Fans"
	fans.Parent = into
	local u = FAN * S
	local SHIRTS = { "#e53935", "#1e88e5", "#43a047", "#fdd835", "#8e24aa", "#fb8c00", "#00acc1", "#f06292", "#fafafa" }
	for r = 0, rows - 1 do
		for i = 0, math.floor(width / 0.55) - 1 do
			if (i * 7 + r * 3) % 5 ~= 0 then
				local x = -(-width / 2 + 0.3 + i * 0.55 + (r % 2) * 0.2)
				local z = gz + r * 0.7
				local y = 0.35 + r * 0.4
				local hop = if (i + r) % 3 ~= 0 then rand() * 0.08 else 0
				Kit.part({ Size = Vector3.new(0.17, 0.3, 0.15) * u, CFrame = at(x, y + (0.39 + hop) * FAN, z), Color = hex(SHIRTS[(i * 3 + r) % #SHIRTS + 1]) }, fans)
				Kit.part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.16, 0.16, 0.16) * u, CFrame = at(x, y + (0.6 + hop) * FAN, z), Color = hex(if (i + r) % 2 == 0 then "#f1c27d" else "#c68642") }, fans)
			end
		end
	end

	-- Pit entry gantry with the speed limit lights and a sign.
	do
		local gx = -12
		for _, z in { -4.6, WALL - 0.4 } do
			box(0.3, 4.6, 0.3, gx, 2.3, z, "#455a64")
		end
		box(0.4, 0.6, WALL + 4.6, gx, 4.5, (WALL - 5) / 2, "#263238")
		signBoard(5, 0.5, at(gx + 0.21, 4.5, (WALL - 5) / 2) * CFrame.Angles(0, math.pi / 2, 0), "PIT LANE 80", "#263238", "#ffd54f")
		for _, z in { -3.4, 4.4 } do
			for k = 0, 1 do
				Kit.part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.24, 0.24, 0.24) * S, CFrame = at(gx + 0.22, 4.4, z + (if k == 1 then 0.3 else -0.3)), Color = hex(if k == 1 then "#00e676" else "#263238"), Material = if k == 1 then Enum.Material.Neon else Enum.Material.SmoothPlastic }, into)
			end
		end
	end
	-- Spare sets and kit on the apron round the box.
	Kit.tyreStack(into, O, -BOX_W / 2 - 0.5, -3.9, 4, "#ffd54f")
	Kit.tyreStack(into, O, -BOX_W / 2 - 1.1, -3.9, 3, "#ffd54f")
	Kit.tyreStack(into, O, BOX_W / 2 + 0.6, -3.9, 4, TEAM)
	Kit.toolChest(into, O, BOX_W / 2 + 1.8, -3.9, TEAM)
	-- The fuel rig: a tall tank on the apron, about head height on the crew.
	box(0.55, 1.44, 0.45, RIG[1], 0.72, RIG[2], "#eceff1")
	signBoard(0.4, 0.4, at(RIG[1], 0.95, RIG[2] + 0.23), "FUEL", TEAM, "#ffffff")
	box(0.62, 0.12, 0.52, RIG[1], 1.5, RIG[2], TEAM)
	Kit.part({ Size = Vector3.new(0.1, 0.18, 0.04) * S, CFrame = at(RIG[1] + 0.2, 0.55, RIG[2] + 0.24), Color = hex("#00e676"), Material = Enum.Material.Neon }, into)
	for _, sd in { -1, 1 } do
		for _, x in { -14, -4, 6, 16 } do
			Kit.lamp(into, O, x, if sd > 0 then WALL - 0.35 else -4.3, if sd > 0 then math.pi else 0, "#455a64")
		end
	end
end

-- ── The round ──────────────────────────────────────────────────────────────────────────────────

export type Round = {
	step: (dt: number) -> (),
	setPedal: (on: boolean) -> (),
	tap: (i: number) -> (),
	start: () -> (),
	quit: () -> (),
	state: any,
	wheels: { any },
	pads: { Frame },
	done: boolean,
}

function Pit.new(ctx: any): Round
	local O: Vector3 = ctx.origin
	local gui: ScreenGui = ctx.gui
	local random = Random.new(ctx.seed or os.time())
	local function rand(): number
		return random:NextNumber()
	end
	local function W(x: number, y: number, z: number): Vector3
		return O + Vector3.new(x, y, z) * S
	end

	local folder = Instance.new("Folder")
	folder.Name = "PitStop"
	folder.Parent = workspace
	buildScenery(folder, O, rand)

	-- The player's car, facing +x down the lane, and its wheels in the world (x along the lane,
	-- z towards the camera, web units), in the order the web builds them.
	local me = Kit.car(ctx.car or {}, LEN * S, folder)
	local bike = data.isBike(ctx.car and ctx.car.body or "") or #me.corners == 2
	local corners = table.clone(me.corners)
	-- Front then rear; on each axle the camera's side (+z, the car's left in its own frame) first.
	table.sort(corners, function(a, b)
		if math.abs(a.z - b.z) > 1 then
			return a.z > b.z
		end
		return a.x < b.x
	end)
	local wheels = {}
	for _, c in corners do
		local wx, wz = c.z / S, -c.x / S
		if bike then
			wz = 0
		end
		table.insert(wheels, { x = wx, z = wz, out = if bike then 1 else (if wz >= 0 then 1 else -1), corner = c })
	end
	local wr = 0.3
	for _, c in corners do
		wr = math.max(wr, c.y / S)
	end
	local times = arcadeMore.gunTimes(rand, #wheels)
	-- Which car part belongs to which wheel.
	local wheelOf: { [number]: number } = {}
	for i, w in wheels do
		for _, p in w.corner.parts do
			wheelOf[p] = i
		end
	end

	-- Other cars: three going round the track, one coming down the fast lane.
	local pool = {}
	for _, c in data.CARS do
		if not c.parked and not data.isBike(c.body) and RACERS[c.body] then
			table.insert(pool, c)
		end
	end
	if #pool == 0 then
		for _, c in data.CARS do
			if not c.parked and not data.isBike(c.body) then
				table.insert(pool, c)
			end
		end
	end
	local function townCar(c: any): any
		return Kit.car({ model = c.id, color = c.colors[1] }, LEN * S, folder)
	end
	local laneCar = townCar(pool[math.floor(rand() * #pool) + 1])
	local laneAt = { x = -40 }
	local track = {}
	for i = 0, 2 do
		table.insert(track, { car = townCar(pool[i % #pool + 1]), x = -45 - i * 30, i = i, z = (if i % 2 == 1 then 8 else 10.4) + WALL - 4.7 })
	end

	-- The crew: a gunner and a tyre man per corner, the two jack men, the lollipop man and the
	-- fuel man. Each has a waiting spot outside the box and a working spot.
	local crew = {}
	do
		local side = BOX_D / 2 + 0.45
		local n = 0
		local function add(h: number, shirt: string, wait: { number }, work: { number })
			n += 1
			table.insert(crew, { p = Kit.person(folder, n, FAN * CREW_K, shirt), h = h, wait = wait, work = work, x = wait[1], z = wait[2] })
		end
		for _, w in wheels do
			local z = w.out * (math.abs(w.z) + 0.62 * CREW_K / 1.45)
			local face = if w.out > 0 then math.pi else 0
			add(face, TEAM, { w.x, w.out * side }, { w.x, z })
			local sx = if w.x >= 0 then 1 else -1
			add(face, TEAM, { w.x + 0.75 * sx, w.out * (side + 0.2) }, { w.x + 0.7 * sx, z + w.out * 0.35 })
		end
		add(-math.pi / 2, TEAM, { LEN / 2 + 1.5, -side }, { LEN / 2 + 1.35, 0 }) -- front jack
		add(math.pi / 2, TEAM, { -LEN / 2 - 1.5, -side }, { -LEN / 2 - 1.35, 0 }) -- rear jack
		add(-math.pi / 2, "#263238", { LEN / 2 + 1.2, -1.6 }, { LEN / 2 + 1.2, -1.6 }) -- lollipop
		add(0, TEAM, { RIG[1] + 0.7, RIG[2] + 0.5 }, { RIG[1] + 1.2, -1.6 }) -- fuel
	end

	-- At each corner: the new tyre waiting, the old one once it's off, and the wheel gun.
	local fresh, used, guns = {}, {}, {}
	for i, w in wheels do
		local sx = if w.x >= 0 then 1 else -1
		fresh[i] = Kit.tyre(folder, W(w.x + 0.42 * sx, 0, w.z + w.out * 0.85), wr, wr * 0.75, TEAM, false, math.pi / 2)
		used[i] = Kit.tyre(folder, W(w.x - 0.6 * sx, 0, w.z + w.out * 1.2), wr, wr * 0.75, "#757575", true, i - 1)
		local g = Instance.new("Model")
		g.Name = "Gun"
		Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.32, 0.11, 0.11) * S, CFrame = CFrame.Angles(0, math.pi / 2, 0), Color = hex("#fdd835") }, g)
		Kit.part({ Size = Vector3.new(0.06, 0.18, 0.08) * S, CFrame = CFrame.new(Vector3.new(0, -0.12, w.out * 0.08) * S), Color = hex("#212121") }, g)
		g.WorldPivot = CFrame.new()
		g.Parent = folder
		guns[i] = g
	end
	local function show(m: Instance, on: boolean)
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				local was = d:GetAttribute("T")
				if was == nil then
					was = d.Transparency
					d:SetAttribute("T", was)
				end
				d.Transparency = if on then was else 1
			end
		end
	end
	for i in wheels do
		show(used[i], false)
		show(guns[i], false)
	end
	-- The trolley jacks, front and back: a saddle under the car and a long handle.
	local jacks = {}
	for k = 0, 1 do
		local dir = if k == 1 then -1 else 1
		local j = Instance.new("Model")
		j.Name = "Jack"
		Kit.part({ Size = Vector3.new(0.36, 0.08, 0.36) * S, CFrame = CFrame.new(Vector3.new(-dir * 0.25, 0.1, 0) * S), Color = hex("#37474f") }, j)
		Kit.part({ Size = Vector3.new(0.5, 0.06, 0.26) * S, CFrame = CFrame.new(Vector3.new(-dir * 0.1, 0.06, 0) * S), Color = hex("#455a64") }, j)
		Kit.part({ Size = Vector3.new(1.1, 0.06, 0.06) * S, CFrame = CFrame.new(Vector3.new(dir * 0.5, 0.25, 0) * S) * CFrame.Angles(0, 0, dir * 0.3), Color = hex("#ffd54f") }, j)
		Kit.part({ Size = Vector3.new(0.06, 0.06, 0.42) * S, CFrame = CFrame.new(Vector3.new(dir * 1.03, 0.41, 0) * S), Color = hex("#212121") }, j)
		j.WorldPivot = CFrame.new()
		j.Parent = folder
		show(j, false)
		jacks[k + 1] = j
	end
	-- Lollipop board on its pole, held out over the nose.
	Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.3, 0.05, 0.05) * S, CFrame = CFrame.new(W(LEN / 2 + 0.95, 0.85, -1.25)) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#212121") }, folder)
	local lolly = Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, 0.6, 0.6) * S, CFrame = CFrame.new(W(LEN / 2 + 0.95, 1.6, -1.25)), Color = hex("#e53935"), Material = Enum.Material.Neon }, folder)
	-- The fuel hose from the rig to the car, in a few straight runs.
	local hose = Instance.new("Model")
	hose.Name = "Hose"
	do
		local pts = { W(RIG[1], 1.42, RIG[2] + 0.2), W(RIG[1] + 0.4, 0.3, RIG[2] + 0.9), W(-0.6, 0.25, -me.wid / S / 2 - 0.5), W(-0.3, 0.55, -me.wid / S / 2 + 0.05) }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new((b - a).Magnitude, 0.9, 0.9), CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.pi / 2, 0), Color = hex("#212121") }, hose)
		end
	end
	hose.Parent = folder
	show(hose, false)
	-- Tyre smoke when the car launches out of the box.
	local puffs = {}
	for i = 1, 10 do
		puffs[i] = { age = 9, x = 0, z = 0, part = Kit.part({ Shape = Enum.PartType.Ball, Size = Vector3.one * S, Color = hex("#e0e0e0"), Transparency = 1 }, folder) }
	end

	-- ── The screen (PitGame) ──────────────────────────────────────────────────────────────────
	local s = {
		t = 0,
		clock = 0,
		x = PIT_START,
		v = PIT_SPEED,
		phase = "in",
		pushFrom = 0,
		pushT = 0,
		pushK = 0,
		grade = "good",
		lift = 0,
		pen = 0,
		slips = 0,
		wait = 0,
		laneGo = false,
		greenAt = 0,
		react = 0,
		go = 0,
		done = false,
		shake = 0,
		camX = 1.6,
		crewK = 0,
		glug = 0,
		call = arcadeMore.pitCall(rand, #wheels),
		callIdx = 0,
		callT = 0,
		corners = {},
		running = false,
		pedal = false,
		presses = 0,
		taps = {},
	}
	for i in wheels do
		s.corners[i] = { stage = 0, fill = 0, swap = 0, green = -1, slip = 0, gun = 0, cls = "" }
	end

	local round: Round
	local cam, giveBack = Kit.takeCamera(CAM_FOV)
	Kit.fog("#d9f2ff", 30, 110)
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

	Kit.topBar(gui, "🔧 Pit Stop", function()
		close(0, { quit = true })
	end)
	local hudRow = Kit.hudRow(gui)
	local clockPill = Kit.pill(hudRow, 1, "⏱ 0.0s", 79)
	local leftPill = Kit.pill(hudRow, 2, "🛞 4")
	leftPill.frame.Visible = false
	local tip = Kit.words(gui, { Name = "Tip", Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 100), Size = UDim2.new(1, -20, 0, 24), ZIndex = 4 }, 18, 2, 0.4)

	-- Brake and go: hold or tap anywhere (the big button is the picture of it).
	local pedal = Ui.new("TextButton", { Name = "Pedal", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Visible = false, Parent = gui })
	local big = Ui.new("Frame", { Name = "Big", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -26), Size = UDim2.fromOffset(112, 112), BackgroundTransparency = 1, ZIndex = 3, Visible = false, Parent = gui })
	Ui.new("Frame", { Name = "Shadow", Position = UDim2.fromOffset(0, 6), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.7, ZIndex = 3, Parent = big }, { Ui.round() })
	local bigFace = Ui.new("Frame", { Name = "Face", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(198, 40, 40), BackgroundTransparency = 0.12, ZIndex = 4, Parent = big }, { Ui.round(), Ui.stroke(4, Ui.WHITE) })
	local bigIcon = Ui.text({ Name = "Icon", Text = "🛑", TextSize = 40, Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 44), ZIndex = 5, Parent = bigFace })
	local bigSmall = Ui.text({ Name = "Small", Text = "Hold to brake", TextSize = 13, Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 16), ZIndex = 5, Parent = bigFace })

	-- The wheel rings (.pit-pad): a ring of segments filling clockwise from the top, a white
	-- edge, and a little label under it.
	local SEGS = 24
	local pads: { Frame } = {}
	local padBits = {}
	for i in wheels do
		local pad = Ui.new("TextButton", { Name = `Pad{i}`, Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(74, 74), BackgroundTransparency = 1, ZIndex = 6, Visible = false, Parent = gui })
		local segs = {}
		for j = 0, SEGS - 1 do
			local a = (j + 0.5) / SEGS * math.pi * 2
			segs[j + 1] = Ui.new("Frame", { Name = `S{j}`, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.sin(a) * 28.5, 0.5, -math.cos(a) * 28.5), Size = UDim2.fromOffset(8, 16), Rotation = math.deg(a), BorderSizePixel = 0, BackgroundColor3 = CHIP_DARK, BackgroundTransparency = 0.45, ZIndex = 6, Parent = pad })
		end
		local edge = Ui.new("Frame", { Name = "Edge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(77, 77), BackgroundTransparency = 1, ZIndex = 7, Parent = pad }, { Ui.round(), Ui.stroke(3, Ui.WHITE) })
		local tag = Ui.new("Frame", { Name = "Tag", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 14), Size = UDim2.fromOffset(34, 19), BackgroundColor3 = CHIP_DARK, BackgroundTransparency = 0.2, ZIndex = 8, Parent = pad }, { Ui.round() })
		local tagText = Ui.text({ Text = "🔧", TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 9, Parent = tag })
		pads[i] = pad
		padBits[i] = { segs = segs, edge = edge, tag = tag, text = tagText }
		pad.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				table.insert(s.taps, i)
			end
		end)
	end
	local popNow: Kit.Pop? = nil
	local function pop(text: string, kind: string)
		if popNow then
			popNow.label:Destroy()
		end
		popNow = Kit.pop(gui, text, hex(if kind == "bad" then "#ff8a80" else "#b9f6ca"), 30, UDim.new(0, 104))
	end

	-- Paints one ring for its class (the web's pit-pad classes).
	local function paintPad(i: number, cls: string, fill: number, n: number?)
		local bits = padBits[i]
		local lit = cls == "call lit"
		local col, solid = CHIP_DARK, false
		if cls == "ready" then
			col, solid = hex("#00e676"), true
		elseif cls == "slip" then
			col, solid = hex("#ff1744"), true
		elseif lit then
			col, solid = hex("#40c4ff"), true
		elseif cls == "call" then
			col, solid = CHIP_DARK, true
		end
		for j, seg in bits.segs do
			local on = solid or (j - 0.5) / SEGS < fill
			seg.BackgroundColor3 = if solid then col elseif on then hex("#ffd54f") else CHIP_DARK
			seg.BackgroundTransparency = if (solid and cls ~= "call") or (not solid and on) then 0 else 0.45
		end
		bits.edge.Size = UDim2.fromOffset(if lit then 88 else 77, if lit then 88 else 77)
		local word = if cls == "ready" then "TAP!" elseif cls == "slip" then "Slip" elseif cls == "swap" then "🛞" elseif lit then tostring(n) elseif cls == "call" then "?" else "🔧"
		bits.text.Text = word
		bits.text.TextSize = if lit then 18 else 13
		bits.tag.Size = UDim2.fromOffset(math.max(34, Ui.textWidth(word, bits.text.TextSize) + 16), if lit then 24 else 19)
		bits.tag.BackgroundColor3 = if cls == "ready" then hex("#00c853") elseif cls == "slip" then hex("#d50000") elseif lit then hex("#0091ea") else CHIP_DARK
		bits.tag.BackgroundTransparency = if cls == "ready" or cls == "slip" or lit then 0 else 0.2
		local fade = if cls == "swap" then 0.4 else 0
		bits.text.TextTransparency = fade
	end

	-- The camera: rides down the lane with the car, closes in for the stop, follows it out.
	local function camWant(tight: boolean): (Vector3, Vector3)
		local size = Kit.screen(gui)
		local tan = math.tan(math.rad(CAM_FOV / 2))
		local aspect = size.X / math.max(1, size.Y)
		local halfW = if aspect > 1 then (if tight then 5.4 else 6.5) else (if tight then 3.5 else 3.9)
		local halfH = if tight then 4.2 else 4.8
		local dist = math.max(halfH / tan, halfW / (tan * aspect))
		local dir = Vector3.new(1, 0.85, 0.35).Unit
		return Vector3.new(s.camX - 0.6 + dir.X * dist, dir.Y * dist, 0.4 + dir.Z * dist), Vector3.new(s.camX - 0.6, 0, 0.4)
	end
	local camPos, camAt = camWant(false)
	cam.CFrame = CFrame.lookAt(O + camPos * S, O + camAt * S)

	local hudPhase = ""
	local function step(rawDt: number)
		if finished then
			return
		end
		local dt = math.min(rawDt, 1 / 20)
		s.clock += dt
		local t = s.clock
		local running = s.running
		-- Presses are counted, so a tap shorter than a frame still counts.
		local press = s.presses > 0
		s.presses = 0
		local taps = s.taps
		s.taps = {}
		if running and s.phase ~= "hold" and s.phase ~= "go" then
			s.t += dt
		end

		if s.phase == "in" and running then
			-- At the limiter until the brake goes on; the crew grab the car if it sails past.
			local brake = s.pedal or s.x > 2.6
			s.v = math.max(0, s.v - (if brake then PIT_BRAKE * (if s.x > 2.6 then 2 else 1) else PIT_COAST) * dt)
			s.x += s.v * dt
			if s.v <= 0 then
				s.grade = arcadeMore.stopGrade(s.x)
				s.pushT = arcadeMore.stopPenalty(s.x)
				pop(if s.grade == "perfect" then "🎯 Perfect stop" elseif s.grade == "good" then "👍 Good stop" elseif s.grade == "short" then "😬 Short! Push" else "😬 Long! Push", if s.pushT > 0 then "bad" else "good")
				if s.pushT > 0 then
					s.phase = "push"
					s.pushFrom = s.x
					s.pushK = 0
				else
					s.phase = "wheels"
				end
			end
		elseif s.phase == "push" then
			-- The crew shove the car onto the marks, which costs real time.
			s.pushK = math.min(1, s.pushK + dt / s.pushT)
			s.x = s.pushFrom * (1 - ease(s.pushK))
			if s.pushK >= 1 then
				s.phase = "wheels"
			end
		elseif s.phase == "wheels" then
			s.lift = math.min(1, s.lift + dt * 6)
			if s.callT < CALL_SHOW * #s.call then
				s.callT += dt
			end
			local calling = s.callT < CALL_SHOW * #s.call
			for _, i in taps do
				local c = s.corners[i]
				if not c or c.stage == 1 or c.stage == 3 or s.lift < 1 or calling then
					continue
				end
				-- pitCall's order is 0-based wheel numbers.
				if c.stage == 0 and c.fill >= 1 and s.call[s.callIdx + 1] ~= i - 1 then
					-- Off in the called order only: the wrong wheel costs time and doesn't count.
					s.pen += CALL_MISS
					c.slip = 0.4
					s.slips += 1
					s.shake = 0.12
					pop(`Wrong wheel! +{CALL_MISS}s`, "bad")
					continue
				end
				if c.fill >= 1 then
					if c.stage == 0 then
						s.callIdx += 1
					end
					local quick = t - c.green < 0.25
					if c.stage == 0 then
						c.stage = 1
						c.swap = 0
					else
						c.stage = 3
					end
					c.gun = 0.3
					s.shake = math.max(s.shake, 0.05)
					if quick then
						pop("⚡ Quick", "good")
					end
				else
					c.fill = math.max(0, c.fill - GUN_SLIP)
					c.slip = 0.4
					s.slips += 1
					s.shake = 0.12
					pop("Slipped!", "bad")
				end
			end
			for i, c in s.corners do
				if s.lift < 1 or calling then
					break
				end
				if c.stage == 0 or c.stage == 2 then
					local was = c.fill
					c.fill = math.min(1, c.fill + dt / times[i][if c.stage == 0 then 1 else 2])
					if was < 1 and c.fill >= 1 then
						c.green = t
					end
				elseif c.stage == 1 then
					-- The old wheel comes off, the new one goes on.
					c.swap += dt / 0.4
					if c.swap >= 1 then
						c.stage = 2
						c.fill = 0
					end
				end
			end
			local all = true
			for _, c in s.corners do
				if c.stage ~= 3 then
					all = false
				end
			end
			if all then
				s.phase = "hold"
				-- Hold for a moment; sometimes a car is coming down the lane and you wait for it.
				s.wait = 0.35 + rand() * 0.6
				s.laneGo = rand() < 0.4
				if s.laneGo then
					laneAt.x = -26
				end
			end
		elseif s.phase == "hold" then
			s.lift = math.max(0, s.lift - dt * 7)
			s.wait -= dt
			if press then
				s.pen += PIT_JUMP
				s.shake = 0.12
				pop(`Wait for green! +{PIT_JUMP}s`, "bad")
			end
			local clear = not s.laneGo or laneAt.x > 3.5
			if s.wait <= 0 and clear then
				s.phase = "green"
				s.greenAt = s.t
			end
		elseif s.phase == "green" then
			if press then
				s.react = s.t - s.greenAt
				s.phase = "go"
				s.v = 0
				pop(`⚡ {string.format("%.2f", s.react)}s`, if s.react < 0.4 then "good" else "bad")
			end
		elseif s.phase == "go" then
			s.go += dt
			s.v += 14 * dt
			s.x += s.v * dt
			if s.go > 1.3 and not s.done then
				s.done = true
				local e = { time = s.t + s.pen, slips = s.slips, grade = s.grade, react = s.react }
				local result = round1(e.time)
				close(result, { stars = arcadeMore.pitStars(e.time), line = pitLine(e), grade = e.grade, react = e.react, slips = e.slips })
				return
			end
		end
		if s.laneGo and s.phase ~= "in" then
			laneAt.x += PIT_SPEED * dt
		end
		-- Tyre smoke off the rear wheels as it launches.
		if s.phase == "go" and s.go < 0.7 then
			s.glug -= dt
			if s.glug <= 0 then
				s.glug = 0.07
				local p = puffs[1]
				local pi = 1
				for k, q in puffs do
					if q.age > p.age then
						p, pi = q, k
					end
				end
				local rw = wheels[#wheels]
				p.age = 0
				p.x = s.x + rw.x - 0.2
				p.z = (if pi % 2 == 0 then 1 else -1) * math.max(0.4, math.abs(rw.z))
			end
		end
		for _, p in puffs do
			p.age += dt
			if p.age < 1.1 then
				local k = p.age / 1.1
				p.part.Size = Vector3.one * (0.25 + k * 0.9) * S
				p.part.CFrame = CFrame.new(W(p.x - k * 0.8, 0.2 + k * 0.6, p.z * (1 + k * 0.4)))
				p.part.Transparency = 1 - 0.55 * (1 - k)
			else
				p.part.Transparency = 1
			end
		end

		-- The car: on the jacks, the wheels coming off and going back on.
		local liftY = ease(s.lift) * 0.16
		local root = CFrame.new(W(s.x, liftY, 0)) * CFrame.Angles(0, math.pi / 2, 0)
		local offs = {}
		for i, c in s.corners do
			c.gun = math.max(0, c.gun - dt)
			c.slip = math.max(0, c.slip - dt)
			local out = if c.stage == 1 then (if c.swap < 0.5 then ease(c.swap * 2) else ease((1 - c.swap) * 2)) else 0
			offs[i] = if out > 0 then CFrame.new(if bike then Vector3.new(0, out * 0.3, 0) * S else Vector3.new(0, 0, wheels[i].out * out * 0.55) * S) else nil
			show(fresh[i], c.stage < 1 or (c.stage == 1 and c.swap < 0.5))
			show(used[i], c.stage >= 2 or (c.stage == 1 and c.swap >= 0.5))
			local w = wheels[i]
			show(guns[i], s.phase == "wheels" and s.lift > 0.3)
			local jig = if c.gun > 0 then (rand() - 0.5) * 0.02 else 0
			guns[i]:PivotTo(CFrame.new(W(s.x + w.x, wr + s.lift * 0.16 + jig, w.z + w.out * 0.42)))
		end
		Kit.place(me, root, function(i: number): CFrame?
			local wi = wheelOf[i]
			return if wi then offs[wi] else nil
		end)
		for k, j in jacks do
			show(j, s.phase == "wheels" or s.phase == "hold")
			j:PivotTo(CFrame.new(W((if k == 2 then -1 else 1) * (LEN / 2 + 0.15) + s.x, 0, 0)))
		end
		-- Other cars.
		Kit.place(laneCar, CFrame.new(W(laneAt.x, 0, FAST)) * CFrame.Angles(0, math.pi / 2, 0))
		for _, tc in track do
			tc.x += dt * (26 + tc.i * 3)
			if tc.x > 45 then
				tc.x = -45 - rand() * 30
			end
			Kit.place(tc.car, CFrame.new(W(tc.x, 0, tc.z)) * CFrame.Angles(0, math.pi / 2, 0))
		end

		-- Crew rush in once the car stops and step back as it leaves.
		local atBox = s.phase == "push" or s.phase == "wheels" or s.phase == "hold" or s.phase == "green"
		s.crewK += ((if atBox then 1 else 0) - s.crewK) * math.min(1, dt * 9)
		for i, c in crew do
			local k = s.crewK
			local x = c.wait[1] + (c.work[1] - c.wait[1]) * k + (if i <= #wheels * 2 and s.phase == "push" then s.x else 0)
			local z = c.wait[2] + (c.work[2] - c.wait[2]) * k
			local hop = if s.phase == "go" then math.max(0, math.sin(t * 6 + i * 1.7)) * 0.09 * FAN * CREW_K else 0
			Kit.placePerson(c.p, CFrame.new(W(x, hop, z)) * CFrame.Angles(0, c.h, 0))
		end
		lolly.Color = hex(if s.phase == "green" or s.phase == "go" then "#00e676" else "#e53935")
		show(hose, s.phase == "wheels" or s.phase == "hold")

		-- Camera.
		local want, look = camWant(s.phase == "wheels" or s.phase == "push")
		local wantX = if s.phase == "in" then 1.6 elseif s.phase == "go" then math.min(14, s.x * 0.5) else 0
		s.camX += (wantX - s.camX) * math.min(1, dt * 3)
		s.shake = math.max(0, s.shake - dt * 0.6)
		local k = math.min(1, dt * 4)
		camPos = camPos + (want - camPos) * k + Vector3.new((rand() - 0.5) * s.shake, (rand() - 0.5) * s.shake, 0)
		cam.CFrame = CFrame.lookAt(O + camPos * S, O + look * S)

		-- Wheel rings: pinned on screen beside each wheel, filling as the gun works.
		local size = Kit.screen(gui)
		for i, pad in pads do
			local c = s.corners[i]
			local w = wheels[i]
			local showPad = s.phase == "wheels" and c.stage ~= 3 and s.lift >= 1
			local callAt = math.floor(s.callT / CALL_SHOW)
			local lit = callAt < #s.call and s.call[callAt + 1] == i - 1
			local cls = if not showPad then "off" elseif callAt < #s.call then (if lit then "call lit" else "call") elseif c.slip > 0 then "slip" elseif c.stage == 1 then "swap" elseif c.fill >= 1 then "ready" else ""
			pad.Visible = showPad
			if showPad then
				paintPad(i, cls, c.fill, callAt + 1)
				local p = Kit.project(cam.CFrame, CAM_FOV, size, W(w.x + s.x, wr + ease(s.lift) * 0.16, w.z + w.out * 0.15))
				local sx = math.min(size.X - 40, math.max(40, p.X))
				local sy = math.min(size.Y - 40, math.max(90, p.Y))
				pad.Position = UDim2.fromOffset(sx, sy)
			end
		end

		-- The HUD.
		local pedalOn = running and (s.phase == "in" or s.phase == "hold" or s.phase == "green")
		pedal.Visible = pedalOn
		big.Visible = pedalOn
		if pedalOn and hudPhase ~= s.phase then
			hudPhase = s.phase
			bigFace.BackgroundColor3 = if s.phase == "in" then Color3.fromRGB(198, 40, 40) elseif s.phase == "hold" then Color3.fromRGB(27, 31, 36) else hex("#00c853")
			bigFace.BackgroundTransparency = if s.phase == "in" then 0.12 elseif s.phase == "hold" then 0.22 else 0
			Ui.setText(bigIcon, if s.phase == "in" then "🛑" elseif s.phase == "hold" then "✋" else "GO!")
			Ui.setText(bigSmall, if s.phase == "in" then "Hold to brake" elseif s.phase == "hold" then "Wait" else "Tap")
		end
		if s.phase == "green" then
			local pulse = 1 + 0.04 * (1 + math.sin(t * math.pi / 0.3))
			big.Size = UDim2.fromOffset(112 * pulse, 112 * pulse)
		else
			big.Size = UDim2.fromOffset(112, 112)
		end
		Kit.setPill(clockPill, `⏱ {string.format("%.1f", s.t + s.pen)}s`, 79)
		local left = 0
		for _, c in s.corners do
			if c.stage ~= 3 then
				left += 1
			end
		end
		leftPill.frame.Visible = s.phase == "wheels"
		Kit.setPill(leftPill, `🛞 {left}`)
		local calling = s.phase == "wheels" and s.callT < CALL_SHOW * #s.call
		Ui.setText(tip, if running and s.phase == "in" then "Stop on the white line" elseif running and s.phase == "wheels" then (if calling then "🧠 Remember the order!" else "Wheels off in that order, on green") else "")
		if popNow and not Kit.stepPop(popNow, dt, 28) then
			popNow = nil
		end
	end

	local count: ((number) -> boolean)? = nil
	round = {
		state = s,
		wheels = wheels,
		pads = pads,
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
		setPedal = function(on: boolean)
			if on then
				s.presses += 1
			end
			s.pedal = on
		end,
		tap = function(i: number)
			table.insert(s.taps, i)
		end,
		quit = function()
			close(0, { quit = true })
		end,
	}
	pedal.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			round.setPedal(true)
		end
	end)
	pedal.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			s.pedal = false
		end
	end)
	step(0)
	return round
end

-- Runs one round on its own frame loop: space brakes and goes on a keyboard, as on the web.
function Pit.play(ctx: any)
	local round = Pit.new(ctx)
	local conns: { RBXScriptConnection } = {}
	local function stop()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
	end
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, typing: boolean)
		if input.KeyCode == Enum.KeyCode.Space and not typing then
			round.setPedal(true)
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Space then
			round.state.pedal = false
		end
	end))
	table.insert(conns, RunService.RenderStepped:Connect(function(dt: number)
		round.step(dt)
		if round.done then
			stop()
		end
	end))
	round.start()
end

return Pit
