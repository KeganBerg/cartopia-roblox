--!strict
-- The schools' and the driving academy's life, as the web game's scene/CampusLife.tsx draws it
-- inside their buildings (scene/CampusBuildings.tsx): kids at recess on the Elementary School's
-- playground, the High School's runners lapping the track (in the team's green) and a few
-- students crossing its car park, students crossing the University's quad and two people chatting
-- by the Driving Academy's office while the learner cars lap the cone course, each stopping at the
-- stop line, waiting, and pulling away again with the others queued behind.
--
-- Where everyone goes is CampusBuildings.tsx's own numbers, and how they move scene/campusPaths.ts
-- (routes round a loop or a track, kids' loose loops, the academy's smoothed drive), ported by
-- hand below: campusPaths isn't one of the modules the converter turns into Luau (it's ~150
-- lines, and adding it means re-running the converter over the whole web game). The people are
-- TownLife's townspeople (LotPeople), at a Roblox character's height; kids smaller.
--
-- It all runs on this player's client, like SpeedwayLife: it never changes the game. Kept cheap for
-- phones: fewer people, parts made once and moved in one BulkMoveTo, nothing moved for a campus
-- further than FAR studs from the camera.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Models = Shared:WaitForChild("Models")
local Catalog = require(Models:WaitForChild("Catalog")) :: any
local Builder = require(Models:WaitForChild("Builder")) :: any
local Paint = require(Models:WaitForChild("Paint")) :: any
local clock = require(Game:WaitForChild("clock")) :: any
local LotPeople = require(script.Parent.LotPeople)

local CampusLife = {}

local S = Catalog.SCALE -- studs per web unit
local FAR = 1600
local HIDDEN = CFrame.new(0, -10000, 0)

---------------------------------------------------------------------------------------------------
-- campusPaths.ts. Points are { x, z } in the lot's web units.

type XZ = { number }
type Route = (f: number) -> (number, number)
type Mover = (i: number, t: number) -> (number, number)

-- A closed route through `pts`, walked at constant speed: the point a fraction `f` (wraps) round.
local function loop(pts: { XZ }): Route
	local segs = {}
	local total = 0
	for i, p in pts do
		local q = pts[i % #pts + 1]
		local len = math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
		table.insert(segs, { p = p, q = q, len = len })
		total += len
	end
	return function(f: number): (number, number)
		local d = (f % 1) * total
		for _, s in segs do
			if d <= s.len then
				local k = if s.len > 0 then d / s.len else 0
				return s.p[1] + (s.q[1] - s.p[1]) * k, s.p[2] + (s.q[2] - s.p[2]) * k
			end
			d -= s.len
		end
		return pts[1][1], pts[1][2]
	end
end

-- A running track: two straights joined by half circles, centred on (cx, cz), long along z.
local function track(cx: number, cz: number, straight: number, r: number): Route
	local len = 2 * straight + 2 * math.pi * r
	return function(f: number): (number, number)
		local d = (f % 1) * len
		if d < straight then
			return cx + r, cz + straight / 2 - d
		end
		d -= straight
		if d < math.pi * r then
			local a = d / r
			return cx + math.cos(a) * r, cz - straight / 2 - math.sin(a) * r
		end
		d -= math.pi * r
		if d < straight then
			return cx - r, cz - straight / 2 + d
		end
		d -= straight
		local a = d / r
		return cx - math.cos(a) * r, cz + straight / 2 + math.sin(a) * r
	end
end

-- Kids running about a rectangle (cx, cz, half-width, half-depth), each on their own loose loop.
-- `i` counts from 0, as the web's does.
local function playMove(cx: number, cz: number, hw: number, hd: number): Mover
	return function(i: number, t: number): (number, number)
		local a, b = 0.35 + (i % 5) * 0.09, 0.27 + (i % 7) * 0.07
		return cx + math.sin(t * a + i * 2.1) * hw * (0.55 + (i % 3) * 0.2), cz + math.sin(t * b + i * 1.3) * hd * (0.5 + (i % 4) * 0.15)
	end
end

-- People spread round a route, each at their own pace, every other one the other way round.
local function routeMove(route: Route, lap: number, spread: number?): Mover
	local sp = spread or 0.02
	return function(i: number, t: number): (number, number)
		local pace = 1 + ((i * 37) % 10) / 40
		local dir = if i % 2 == 1 then 1 else -1
		local x, z = route(dir * t / (lap * pace) + i * 0.137)
		return x + math.sin(i * 4.7) * sp, z + math.cos(i * 3.1) * sp
	end
end

-- A closed drive through `pts`, rounded into a smooth curve (centripetal Catmull-Rom) and sampled
-- into an arc-length table: at(d) is the point `d` along it (wraps), its heading and how sharply it
-- bends there (radians a unit); bend(d0, d1) the sharpest bend between. Arrays count from 0 here,
-- as the web's do.
type Pose = { x: number, z: number, yaw: number, curv: number }
type Drive = { len: number, at: (d: number, out: Pose) -> Pose, bend: (d0: number, d1: number) -> number }

local function smoothLoop(pts: { XZ }, per: number?): Drive
	local per_ = per or 20
	local n = #pts
	local function P(i: number): XZ
		return pts[i % n + 1]
	end
	local xs: { [number]: number }, zs: { [number]: number } = {}, {}
	local m = 0
	for i = 0, n - 1 do
		local p0, p1, p2, p3 = P(i - 1), P(i), P(i + 1), P(i + 2)
		local function t(a: XZ, b: XZ): number
			local v = math.sqrt(math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2))
			return if v == 0 then 1e-4 else v
		end
		local t1 = t(p0, p1)
		local t2 = t1 + t(p1, p2)
		local t3 = t2 + t(p2, p3)
		for s = 0, per_ - 1 do
			local u = t1 + ((t2 - t1) * s) / per_
			local function lerp(a: XZ, b: XZ, ta: number, tb: number): XZ
				local k = (u - ta) / (tb - ta)
				return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k }
			end
			local a1, a2, a3 = lerp(p0, p1, 0, t1), lerp(p1, p2, t1, t2), lerp(p2, p3, t2, t3)
			local b1, b2 = lerp(a1, a2, 0, t2), lerp(a2, a3, t1, t3)
			local c = lerp(b1, b2, t1, t2)
			xs[m], zs[m] = c[1], c[2]
			m += 1
		end
	end
	local cum: { [number]: number } = { [0] = 0 }
	local yaw: { [number]: number }, curv: { [number]: number } = {}, {}
	for i = 0, m - 1 do
		local j = (i + 1) % m
		cum[i + 1] = cum[i] + math.sqrt((xs[j] - xs[i]) ^ 2 + (zs[j] - zs[i]) ^ 2)
		yaw[i] = math.atan2(xs[j] - xs[i], zs[j] - zs[i])
	end
	local len = cum[m]
	local function index(d: number): (number, number)
		d %= len
		local lo, hi = 0, m - 1
		while lo < hi do
			local mid = (lo + hi + 1) // 2
			if cum[mid] <= d then
				lo = mid
			else
				hi = mid - 1
			end
		end
		return lo, (d - cum[lo]) / math.max(1e-4, cum[lo + 1] - cum[lo])
	end
	-- Bend measured as the turn in heading across a short stretch, so uneven sample spacing
	-- doesn't spike it.
	local W = 0.12
	for i = 0, m - 1 do
		local a, b = yaw[(index(cum[i] - W / 2))], yaw[(index(cum[i] + W / 2))]
		curv[i] = math.atan2(math.sin(b - a), math.cos(b - a)) / W
	end
	local function at(d: number, out: Pose): Pose
		local i, k = index(d)
		local j = (i + 1) % m
		out.x = xs[i] + (xs[j] - xs[i]) * k
		out.z = zs[i] + (zs[j] - zs[i]) * k
		-- Heading eased between samples so it turns continuously.
		local dy = math.atan2(math.sin(yaw[j] - yaw[i]), math.cos(yaw[j] - yaw[i]))
		out.yaw = yaw[i] + dy * k
		out.curv = curv[i] + (curv[j] - curv[i]) * k
		return out
	end
	local function bend(d0: number, d1: number): number
		local most = 0
		local d = d0
		while d <= d1 do
			most = math.max(most, math.abs(curv[(index(d))]))
			d += 0.05
		end
		return most
	end
	return { len = len, at = at, bend = bend }
end

-- How far along `drive` its nearest point to (x, z) is.
local function nearestD(drive: Drive, x: number, z: number): number
	local p = { x = 0, z = 0, yaw = 0, curv = 0 }
	local best, gap = 0, math.huge
	local d = 0
	while d < drive.len do
		drive.at(d, p)
		local g = math.sqrt((p.x - x) ^ 2 + (p.z - z) ^ 2)
		if g < gap then
			gap, best = g, d
		end
		d += 0.005
	end
	return best
end

---------------------------------------------------------------------------------------------------
-- The lots (CampusBuildings.tsx).

-- The academy's cone course: a kerbed island the learners lap, the near straight (z = 0.38) going
-- +x past the stop line at STOP_X, the far one back.
local STOP_X = -0.1
local COURSE = (function()
	local near, far, half = 0.38, 1.3, 0.95
	local mid, r = (near + far) / 2, (far - near) / 2
	local pts: { XZ } = {}
	local x = -half
	while x < half do
		table.insert(pts, { x, near })
		x += 0.38
	end
	for a = 0, 5 do
		table.insert(pts, { half + math.sin((a * math.pi) / 6) * r, mid - math.cos((a * math.pi) / 6) * r })
	end
	x = half
	while x > -half do
		table.insert(pts, { x, far })
		x -= 0.38
	end
	for a = 0, 5 do
		table.insert(pts, { -half - math.sin((a * math.pi) / 6) * r, mid + math.cos((a * math.pi) / 6) * r })
	end
	local drive = smoothLoop(pts)
	return { drive = drive, stop = nearestD(drive, STOP_X, near) }
end)()

-- When people are about: `school` only in daylight (kids go home at dusk), `campus` all day with a
-- few night owls, `always` round the clock.
type Hours = "school" | "campus" | "always"
-- A group of people on a lot: how many, how they move, when they're out, and the height of the
-- ground they walk on (the web stands them at 0, a little into the lot's paving; here their feet
-- are on it).
type Group = { n: number, move: Mover, hours: Hours, ground: number, kids: boolean?, uniform: string?, jog: boolean? }

local function groupsOf(def: string, lvl: number): { Group }
	if def == "school" then
		return { { n = 6 + lvl // 2, kids = true, move = playMove(1.05, 0.45, 0.7, 0.42), hours = "school", ground = 0.08 } }
	elseif def == "highschool" then
		local cx, straight, r = 1.85, 1.6, 0.82
		return {
			{ n = 4 + lvl // 3, move = routeMove(track(cx, 0, straight, r + 0.14), 16, 0.03), hours = "school", uniform = "#2e7d32", jog = true, ground = 0.072 },
			{ n = 4, move = routeMove(loop({ { -1.4, 0.2 }, { -0.2, 0.3 }, { -0.2, 1.95 }, { -2.8, 1.95 }, { -2.8, 0.3 } }), 40), hours = "campus", ground = 0.07 },
		}
	elseif def == "university" then
		local quad = loop({ { 0, 2.75 }, { 0, 0.6 }, { 1.25, 0.6 }, { 1.25, -0.9 }, { 0, -1.0 }, { -1.25, -0.9 }, { -1.25, 0.6 }, { 0, 0.6 } })
		return { { n = 8 + lvl, move = routeMove(quad, 70, 0.12), hours = "campus", ground = 0.08 } }
	elseif def == "academy" then
		local function chat(i: number, t: number): (number, number)
			return -0.6 + i * 0.3 + math.sin(t * 0.3 + i) * 0.1, -0.15 + math.cos(t * 0.25 + i) * 0.05
		end
		return { { n = 2, move = chat, hours = "campus", ground = 0.06 } }
	end
	return {}
end

-- How many of a group are out now (CampusLife.tsx Crowd).
local function shownOf(g: Group, n: number, night: number, isNight: boolean): number
	if g.hours == "always" then
		return n
	elseif g.hours == "school" then
		return if isNight then 0 else n
	end
	return math.max(math.min(2, n), math.round(n * (1 - night * 0.8)))
end

---------------------------------------------------------------------------------------------------
-- Learner cars (CampusLife.tsx StudentCars): the academy's own cars in school colours, each with a
-- STUDENT DRIVER topper on its hard roof, at town traffic size. The web's little one is its plain
-- compact, which isn't one of the game's cars here; the Kitsune coupe (also a hard roof the topper
-- can stand on) takes its place. Their wheels don't steer or spin, as town traffic's don't here.

local CAR_COLORS = { "#e53935", "#1e88e5", "#fdd835", "#43a047" }
local LEARNERS = { "kitsune", "hotshot", "civic" }

-- How the class drives. Speeds in lot units a second; the pedals are gentle.
local CRUISE = 0.42
local BRAKE_FOR = 0.3 -- how much a bend ahead slows them
local LOOK = 0.6 -- how far ahead a learner looks for the next bend
local ACCEL = 0.22 -- pulling away
local DECEL = 0.45 -- braking
local GAP = 0.22 -- space kept to the car in front, bumper to bumper
local WAIT = 1.6 -- seconds stopped at the stop line, give or take

type Learner = {
	parts: { BasePart },
	offs: { CFrame },
	half: number,
	d: number,
	v: number,
	lean: number,
	pitch: number,
	wait: number,
	stopped: boolean,
	go: boolean,
}

local function quiet(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
end

local function topperPart(parent: Instance, size: Vector3, color: string): Part
	local p = Instance.new("Part")
	quiet(p)
	p.Size = size
	p.Color = Color3.fromHex(color)
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Learner `i` (from 0): the car model at town size and its topper, all parked out of sight.
-- Returns nil if the car can't be built; `boxed` when some of its meshes hadn't arrived yet.
local function learner(parent: Instance, i: number, n: number, len: number): (Learner?, boolean)
	local id = LEARNERS[i % #LEARNERS + 1]
	local m = Builder.build(id)
	if not m then
		return nil, false
	end
	local boxed = Builder.boxed(m)
	Paint.apply(m, Paint.jobOf({ color = CAR_COLORS[i % #CAR_COLORS + 1] }))
	local size = (Catalog.TOWN_SIZE or {})[id] or { 0.8, 0.45, 0.8 }
	local k = size[3]
	m:ScaleTo(k)
	m.Name = `learner{i + 1}`
	local pivot = m:GetPivot()
	local parts, offs = {}, {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			quiet(d)
			table.insert(parts, d)
			table.insert(offs, pivot:ToObjectSpace(d.CFrame))
		end
	end
	-- The topper on the roof (where the car would wear a hat): two little magnetic feet, the sign
	-- board and STUDENT on both faces. In the car's own units, at its town size.
	local spot = (Catalog.HAT_SPOTS or {})[id] or { 0, 5.5, -1 }
	local roof = CFrame.new(0, spot[2] * k, spot[3] * k)
	local u = S * k
	for _, x in { -0.09, 0.09 } do
		table.insert(parts, topperPart(m, Vector3.new(0.05, 0.024, 0.05) * u, "#263238"))
		table.insert(offs, roof * CFrame.new(x * u, 0.012 * u, 0))
	end
	local board = topperPart(m, Vector3.new(0.28, 0.09, 0.06) * u, "#ffeb3b")
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.TextColor3 = Color3.fromHex("#212121")
		label.Text = "STUDENT"
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Parent = gui
		gui.Parent = board
	end
	table.insert(parts, board)
	table.insert(offs, roof * CFrame.new(0, 0.07 * u, 0))
	for _, p in parts do
		p.CFrame = HIDDEN
	end
	m.Parent = parent
	return {
		parts = parts,
		offs = offs,
		half = size[1] / 2,
		d = len * i / n,
		v = 0,
		lean = 0,
		pitch = 0,
		wait = 0,
		stopped = false,
		go = false,
	},
		boxed
end

-- The class on the course for one step of `dt` seconds (StudentCars' useFrame): each eases off for
-- bends, keeps its gap to the one ahead, stops with its nose on the stop line, waits and pulls
-- away; the body leans a touch out of bends and pitches with the pedals.
local POSE: Pose = { x = 0, z = 0, yaw = 0, curv = 0 }
local function drive(cars: { Learner }, frame: CFrame, dt: number, list: { BasePart }, cfs: { CFrame })
	local course = COURSE.drive
	local len = course.len
	local stop = COURSE.stop
	local n = #cars
	for i, st in cars do
		local half = st.half
		-- The speed this stretch allows: slower into bends.
		local want = CRUISE / (1 + BRAKE_FOR * course.bend(st.d, st.d + LOOK))
		-- Keep a gap to whoever is next ahead: room to stop from this speed.
		local room = math.huge
		for j = 1, n do
			if j ~= i then
				local ahead = (cars[j].d - st.d) % len
				room = math.min(room, ahead - half - cars[j].half - GAP)
			end
		end
		want = math.min(want, math.sqrt(2 * DECEL * math.max(0, room)))
		-- Stop with the nose on the line, wait, then pull away (`go` until it's over the line).
		-- Signed, so a car that's just reached the line reads 0, not a whole lap to go.
		local toLine = ((stop - half - st.d) % len + len * 1.5) % len - len / 2
		if st.go and toLine > 0.3 then
			st.go = false
		end
		local coming = not st.go and toLine > -0.05 and toLine < len / 2
		if st.stopped then
			want = 0
			st.wait -= dt
			if st.wait <= 0 then
				st.stopped, st.go = false, true
			end
		elseif coming then
			if toLine < 0.004 and st.v < 0.03 then
				st.stopped = true
				st.wait = WAIT + ((i - 1) * 0.37) % 0.6
				want = 0
			else
				want = math.min(want, math.sqrt(2 * DECEL * 0.8 * math.max(0, toLine)))
			end
		end
		local was = st.v
		st.v = if want > st.v then math.min(want, st.v + ACCEL * dt) else math.max(want, st.v - DECEL * 1.6 * dt)
		-- Never roll over the line on the way in.
		if not st.go and toLine > -0.05 and toLine < len / 2 then
			st.v = math.min(st.v, math.max(0, toLine) / math.max(dt, 1e-3))
		end
		st.d = (st.d + st.v * dt) % len
		course.at(st.d, POSE)
		st.lean += (-POSE.curv * st.v * st.v * 0.35 - st.lean) * math.min(1, dt * 4)
		local accel = (st.v - was) / math.max(dt, 1e-3)
		st.pitch += (math.clamp(-accel * 0.06, -0.02, 0.025) - st.pitch) * math.min(1, dt * 5)
		local cf = frame
			* CFrame.new(POSE.x * S, 0.06 * S, POSE.z * S)
			* CFrame.Angles(0, POSE.yaw, 0)
			* CFrame.fromEulerAnglesYXZ(st.pitch, 0, math.clamp(st.lean, -0.05, 0.05))
		for p, part in st.parts do
			table.insert(list, part)
			table.insert(cfs, cf * st.offs[p])
		end
	end
end

---------------------------------------------------------------------------------------------------
-- One campus's life.

export type Life = {
	folder: Folder,
	frame: CFrame,
	yaw: number,
	groups: { Group },
	crowds: { LotPeople.Crowd },
	cars: { Learner },
	boxed: boolean,
	step: (self: Life, time: number, dt: number, night: number, isNight: boolean, eye: Vector3?, list: { BasePart }, cfs: { CFrame }) -> (),
	destroy: (self: Life) -> (),
}

local Life = {}
Life.__index = Life

-- The people (and, at the academy, learner cars) for a `def` lot at `lvl` whose model sits at
-- `frame`, turned `yaw`. `small`: a phone, where the crowds are thinner.
function CampusLife.new(parent: Instance, uid: string, def: string, frame: CFrame, yaw: number, lvl: number, small: boolean?): Life
	local folder = Instance.new("Folder")
	folder.Name = `CampusLife:{uid}`
	local groups = groupsOf(def, lvl)
	local crowds = {}
	for gi, g in groups do
		if small then
			g.n = math.max(math.min(2, g.n), math.ceil(g.n * 0.6))
		end
		table.insert(crowds, LotPeople.new(folder, `{def}:{uid}:{gi}`, g.n, { kids = g.kids, uniform = g.uniform, jog = g.jog }))
	end
	local cars = {}
	local boxed = false
	if def == "academy" then
		local n = if lvl >= 7 then 3 else 2
		for i = 0, n - 1 do
			local car, b = learner(folder, i, n, COURSE.drive.len)
			if car then
				table.insert(cars, car)
			end
			boxed = boxed or b
		end
	end
	folder.Parent = parent
	local self = setmetatable({ folder = folder, frame = frame, yaw = yaw, groups = groups, crowds = crowds, cars = cars, boxed = boxed }, Life)
	return (self :: any) :: Life
end

-- Moves everyone on to `time` seconds, adding what moved to BulkMoveTo's lists.
function Life.step(self: Life, time: number, dt: number, night: number, isNight: boolean, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	for gi, g in self.groups do
		local c = self.crowds[gi]
		local shown = shownOf(g, g.n, night, isNight)
		for i = 1, g.n do
			if i > shown then
				LotPeople.hide(c, i)
				continue
			end
			local x, z = g.move(i - 1, time)
			local x2, z2 = g.move(i - 1, time + 0.08)
			LotPeople.walk(c, i, self.frame, self.yaw, g.ground, x, z, x2, z2, dt)
		end
		LotPeople.draw(c, time, eye, list, cfs)
	end
	if #self.cars > 0 then
		drive(self.cars, self.frame, dt, list, cfs)
	end
end

function Life.destroy(self: Life)
	self.folder:Destroy()
end

---------------------------------------------------------------------------------------------------
-- Every campus in the player's town.

local CAMPUS = { academy = true, school = true, highschool = true, university = true }

-- Keeps a Life for every school, university and driving academy in `town` (its Buildings folder);
-- returns a function that looks for new, moved or upgraded ones, and one that moves them all on.
function CampusLife.attach(town: Folder, parent: Instance?): (() -> (), (dt: number) -> ())
	local buildings = town:WaitForChild("Buildings")
	local holder = Instance.new("Folder")
	holder.Name = "Campuses"
	holder.Parent = parent or workspace
	local lives: { [string]: { life: Life, key: string } } = {}
	local small = LotPeople.smallScreen()

	local function scan()
		local seen = {}
		for _, m in buildings:GetChildren() do
			local def = m:GetAttribute("Def")
			if not m:IsA("Model") or type(def) ~= "string" or not CAMPUS[def] then
				continue
			end
			local frame, yaw = LotPeople.frameOf(m)
			if not frame then
				continue
			end
			local lvl = math.clamp(math.floor((m:GetAttribute("Level") :: number?) or 1), 1, 10)
			local key = `{def}|{lvl}|{frame}`
			seen[m.Name] = true
			local have = lives[m.Name]
			-- Learner cars built before their meshes arrived are rebuilt once they're all in.
			local stale = have and have.life.boxed and Builder.complete(LEARNERS[1]) and Builder.complete(LEARNERS[2]) and Builder.complete(LEARNERS[3])
			if have and (have.key ~= key or stale) then
				have.life:destroy()
				have = nil
			end
			if not have then
				lives[m.Name] = { life = CampusLife.new(holder, m.Name, def, frame, yaw, lvl, small), key = key }
			end
		end
		for uid, have in lives do
			if not seen[uid] then
				have.life:destroy()
				lives[uid] = nil
			end
		end
	end

	-- Seconds since the town was first drawn (the web's clock.elapsedTime), and the time of day,
	-- read twice a second.
	local time = 0
	local light = 0
	local night, isNight = 0, false
	local function step(dt: number)
		time += dt
		light -= dt
		if light <= 0 then
			light = 0.5
			night = clock.nightAmount(clock.dayPhase())
			isNight = clock.isNight()
		end
		local list: { BasePart } = {}
		local cfs: { CFrame } = {}
		local cam = workspace.CurrentCamera
		local eye = cam and cam.CFrame.Position
		for _, have in lives do
			local life = have.life
			if eye and (eye - life.frame.Position).Magnitude > FAR then
				continue
			end
			life:step(time, dt, night, isNight, eye, list, cfs)
		end
		if #list > 0 then
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	return scan, step
end

function CampusLife.start()
	local Town = require(script.Parent.Town) :: any
	local Remote = require(script.Parent.Remote) :: any
	task.spawn(function()
		local folder: Folder? = nil
		while not folder do
			folder = Town.folder()
			if not folder then
				task.wait(0.5)
			end
		end
		local scan, step = CampusLife.attach(folder :: Folder)
		-- The server redraws a building when it's built, moved or upgraded; buildings also stream in
		-- and out, so look again every second as well as on every change.
		Remote.changed:Connect(function()
			task.defer(scan)
		end)
		scan()
		local wait = 0
		RunService.RenderStepped:Connect(function(dt)
			wait -= dt
			if wait <= 0 then
				wait = 1
				scan()
			end
			step(math.min(dt, 0.1))
		end)
	end)
end

return CampusLife
