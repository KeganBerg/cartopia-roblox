--!strict
-- Life on the shared world's roads between the plots (server/World): everyday cars driving the
-- road grid, keeping to their lane, following the car in front, turning at the crossroads and
-- stopping for the player, and street lamps, bushes and rocks along the verges.
--
-- It all runs here on the client, like TownLife: each player sees their own traffic. Only what's
-- near the camera is drawn (the verges in stretches, built as they come near and cleared as they
-- go), so phones stay smooth. The cars are the game's real models, with their small pieces hidden
-- far off (client/CarDetail). They can be got in like the town's (client/GetIn).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local data = require(Game:WaitForChild("data")) :: any
local Builder = require(Shared:WaitForChild("Models"):WaitForChild("Builder")) :: any
local Paint = require(Shared.Models:WaitForChild("Paint")) :: any
local Catalog = require(Shared.Models:WaitForChild("Catalog")) :: any
local CarDetail = require(script.Parent:WaitForChild("CarDetail"))

-- Leaves for the season the models were made in (Catalog.SEASON), like the countryside's trees.
local LEAVES: { [string]: { string } } = {
	fall = { "#d84315", "#ef6c00", "#f9a825", "#c62828", "#2e7d32" },
	winter = { "#eceff1", "#cfd8dc", "#2e5d3a" },
	spring = { "#7cb342", "#9ccc65", "#f8bbd0", "#558b2f" },
	summer = { "#558b2f", "#689f38", "#33691e", "#7cb342" },
}

local WorldLife = {}

local CARS = 26
local CARS_PHONE = 14
local SCALE = 0.8 -- the size cars are drawn at (server/Drive.SCALE)
local LANE = 0.25 -- of the road's width, right of the middle
local GAP = 40 -- studs kept behind the car in front
local SHOWN = 1400 -- studs from the camera a car is drawn within; past it, it comes back nearer
local RESPAWN_NEAR, RESPAWN_FAR = 500, 1200 -- how far from the camera it comes back
local VERGE_NEAR = 1100 -- verge stretches within this are built...
local VERGE_FAR = 1500 -- ...and cleared past this
local STRETCH = 700 -- studs of road per verge stretch
local HIDDEN = CFrame.new(0, -10000, 0)

type Car = {
	uid: string,
	model: Model,
	detail: CarDetail.Detail,
	along: "x" | "z", -- the axis it drives along
	line: number, -- the road's other coordinate
	dir: number, -- +1 or -1 along the axis
	s: number, -- where along the axis
	v: number,
	cruise: number,
	shown: CFrame?, -- where it's drawn (eases after the sim through turns)
	taken: boolean,
}

local cars: { Car } = {}
-- The road grid (set by attach).
local theGrid: Grid? = nil
local byUid: { [string]: Car } = {}

local function phone(): boolean
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 700
end

-- The everyday cars (as client/TownLife's townsfolk drive).
local function pool(): { any }
	local out = {}
	for _, c in data.CARS do
		if not c.bucks and (c.price or 0) > 0 and c.price <= 22000 and c.colors and #c.colors > 0 then
			table.insert(out, c)
		end
	end
	table.sort(out, function(a, b)
		return a.price < b.price
	end)
	return out
end

-- The grid: road lines at (k - 0.5) * pitch for k = -rings .. rings + 1, both ways.
type Grid = { pitch: number, width: number, rings: number, top: number, lines: { number }, reach: number }

local function gridOf(world: Instance): Grid
	local pitch = (world:GetAttribute("Pitch") :: number?) or 1400
	local rings = (world:GetAttribute("Rings") :: number?) or 2
	local lines = {}
	for k = -rings, rings + 1 do
		table.insert(lines, (k - 0.5) * pitch)
	end
	return {
		pitch = pitch,
		width = (world:GetAttribute("RoadWidth") :: number?) or 44,
		rings = rings,
		top = (world:GetAttribute("RoadTop") :: number?) or -0.5,
		lines = lines,
		reach = (2 * rings + 1) * pitch / 2,
	}
end

-- Where a car is on the road: its lane, right of the road's middle, facing the way it goes.
local function poseOf(g: Grid, c: Car): CFrame
	local fx, fz = if c.along == "x" then c.dir else 0, if c.along == "z" then c.dir else 0
	-- Right of a car facing (fx, fz) is (-fz, fx).
	local off = g.width * LANE
	local x = if c.along == "x" then c.s else c.line
	local z = if c.along == "z" then c.s else c.line
	local p = Vector3.new(x - fz * off, g.top, z + fx * off)
	-- Car models face +Z.
	return CFrame.new(p) * CFrame.Angles(0, math.atan2(fx, fz), 0)
end

local function nearestLine(g: Grid, v: number): number
	local best, d = g.lines[1], math.huge
	for _, l in g.lines do
		if math.abs(l - v) < d then
			best, d = l, math.abs(l - v)
		end
	end
	return best
end

-- A road car: the real model, painted, at the size cars are driven at. Returns it with its detail.
local function carModel(id: string, color: string): (Model?, CarDetail.Detail?)
	local m = Builder.build(id)
	if not m then
		return nil, nil
	end
	Paint.apply(m, Paint.jobOf({ color = color }))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
		end
	end
	local detail = CarDetail.track(m)
	if math.abs(m:GetScale() - SCALE) > 1e-3 then
		m:ScaleTo(SCALE)
	end
	return m, detail
end

local function spawnCars(g: Grid, folder: Folder)
	local list = pool()
	if #list == 0 then
		return
	end
	local n = if phone() then CARS_PHONE else CARS
	local rng = Random.new(7)
	for i = 1, n do
		local def = list[(i * 5) % #list + 1]
		local color = def.colors[(i * 3) % #def.colors + 1]
		local m, detail = carModel(def.id, color)
		if not m or not detail then
			continue
		end
		local uid = `visitor:road:{i}`
		m.Name = uid
		m:SetAttribute("Uid", uid)
		m:SetAttribute("Model", def.id)
		m:SetAttribute("Color", color)
		m:PivotTo(HIDDEN)
		m.Parent = folder
		local cruise = rng:NextNumber(55, 85)
		local c: Car = {
			uid = uid,
			model = m,
			detail = detail,
			along = if i % 2 == 0 then "x" else "z",
			line = g.lines[rng:NextInteger(1, #g.lines)],
			dir = if rng:NextNumber() < 0.5 then 1 else -1,
			s = rng:NextNumber(-g.reach, g.reach),
			v = cruise,
			cruise = cruise,
			shown = nil,
			taken = false,
		}
		table.insert(cars, c)
		byUid[uid] = c
	end
end

-- Puts a car on a road some way from `eye` (not on top of another).
local function respawn(g: Grid, c: Car, eye: Vector3, rng: Random)
	for _ = 1, 8 do
		local along: "x" | "z" = if rng:NextNumber() < 0.5 then "x" else "z"
		local across = if along == "x" then eye.Z else eye.X
		local alongAt = if along == "x" then eye.X else eye.Z
		local near = {}
		for _, l in g.lines do
			if math.abs(l - across) < RESPAWN_FAR then
				table.insert(near, l)
			end
		end
		if #near == 0 then
			continue
		end
		local line = near[rng:NextInteger(1, #near)]
		local left = math.max(0, RESPAWN_FAR ^ 2 - (line - across) ^ 2) ^ 0.5
		local d = rng:NextNumber(math.max(0, RESPAWN_NEAR ^ 2 - (line - across) ^ 2) ^ 0.5, left)
		local sAt = math.clamp(alongAt + d * (if rng:NextNumber() < 0.5 then 1 else -1), -g.reach + 20, g.reach - 20)
		local clear = true
		for _, o in cars do
			if o ~= c and o.along == along and o.line == line and math.abs(o.s - sAt) < GAP * 2 then
				clear = false
			end
		end
		if clear then
			c.along, c.line, c.s = along, line, sAt
			c.dir = if rng:NextNumber() < 0.5 then 1 else -1
			c.v = c.cruise
			return
		end
	end
end

-- How far ahead the nearest thing in a car's lane is: another car, or the player.
local function clearAhead(g: Grid, c: Car, me: Vector3?): number
	local best = math.huge
	for _, o in cars do
		if o ~= c and not o.taken and o.along == c.along and o.line == c.line and o.dir == c.dir then
			local d = (o.s - c.s) * c.dir
			if d > 0 and d < best then
				best = d
			end
		end
	end
	if me then
		local here = poseOf(g, c).Position
		local fwd = if c.along == "x" then Vector3.new(c.dir, 0, 0) else Vector3.new(0, 0, c.dir)
		local rel = me - here
		local ahead = rel:Dot(fwd)
		local side = (rel - fwd * ahead).Magnitude
		if ahead > 0 and side < g.width * 0.35 and ahead < best then
			best = ahead
		end
	end
	return best
end

local function stepCar(g: Grid, c: Car, dt: number, me: Vector3?, rng: Random)
	local room = clearAhead(g, c, me)
	local want = if room < GAP then 0 elseif room < GAP * 3 then c.cruise * (room - GAP) / (GAP * 2) else c.cruise
	c.v += math.clamp(want - c.v, -90 * dt, 25 * dt)
	local before = c.s
	c.s += c.v * c.dir * dt
	-- The end of the road: turn round.
	if math.abs(c.s) > g.reach - 10 then
		c.s = math.sign(c.s) * (g.reach - 10)
		c.dir = -c.dir
		return
	end
	-- Crossing a road: now and then turn onto it.
	for _, l in g.lines do
		if (before - l) * (c.s - l) < 0 then
			if rng:NextNumber() < 0.35 then
				local dir = if rng:NextNumber() < 0.5 then 1 else -1
				local line = l
				c.s, c.line = c.line, line
				c.along = if c.along == "x" then "z" else "x"
				c.dir = dir
				c.line = nearestLine(g, line)
			end
			break
		end
	end
end

---------------------------------------------------------------------------------------------------
-- The verges: lamps either side, a bush or rock here and there, in stretches near the camera.

-- One of the web game's models, anchored and out of the way of clicks, at p turned `turn` about
-- the vertical and scaled.
local function placeModel(parent: Instance, name: string, p: Vector3, turn: number, scale: number?): Model?
	local piece = Builder.build(name)
	if not piece then
		return nil
	end
	if scale then
		piece:ScaleTo(scale)
	end
	for _, d in piece:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	piece:PivotTo(CFrame.new(p) * CFrame.Angles(0, turn, 0))
	piece.Parent = parent
	return piece
end

-- A low-poly tree like the town's: a short trunk and a round crown of leaves in the season's
-- colours. Two parts.
local function makeTree(parent: Instance, p: Vector3, size: number, rng: Random)
	local leaves = LEAVES[Catalog.SEASON or "summer"] or LEAVES.summer
	local trunk = Instance.new("Part")
	trunk.Shape = Enum.PartType.Cylinder
	trunk.Size = Vector3.new(size * 0.6, size * 0.16, size * 0.16)
	trunk.CFrame = CFrame.new(p + Vector3.new(0, size * 0.3, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	trunk.Color = Color3.fromHex("#6d4c41")
	local crown = Instance.new("Part")
	crown.Shape = Enum.PartType.Ball
	crown.Size = Vector3.new(size * 0.8, size * 0.8, size * 0.8)
	crown.CFrame = CFrame.new(p + Vector3.new(0, size * 0.85, 0))
	crown.Color = Color3.fromHex(leaves[rng:NextInteger(1, #leaves)])
	for _, x in { trunk, crown } do
		x.Anchored = true
		x.CanCollide = x == trunk
		x.CanTouch = false
		x.CanQuery = false
		x.Material = Enum.Material.SmoothPlastic
		x.TopSurface = Enum.SurfaceType.Smooth
		x.BottomSurface = Enum.SurfaceType.Smooth
		x.Parent = parent
	end
end

-- The hub's square (server/World builds its paving, lawn and pool): the web game's fountain in the
-- pool, benches and lamps round the lawn, flower beds, and trees in the square's corners. Drawn
-- once, here, because it needs the meshes the clients share (Builder.useLibrary).
local function dressHub(g: Grid): Model
	local m = Instance.new("Model")
	m.Name = "HubDress"
	local rng = Random.new(7)
	local top = g.top - 0.4 -- the ground the roads lie on
	local fountain = placeModel(m, "fountain@1", Vector3.new(0, top + 3.5, 0), 0, 4.5)
	if fountain then
		for _, d in fountain:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = true
			end
		end
	end
	-- Round the lawn's path: benches facing the fountain, lamps between them.
	for k = 0, 7 do
		local a = (k + 0.5) * math.pi / 4
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = dir * 158 + Vector3.new(0, top + 1, 0)
		local face = CFrame.lookAt(at, Vector3.new(0, at.Y, 0))
		local _, turn, _ = face:ToOrientation()
		placeModel(m, "bench@1", at, turn, 1.6)
		local b = k * math.pi / 4
		placeModel(m, "prop:lamp", Vector3.new(math.cos(b), 0, math.sin(b)) * 158 + Vector3.new(0, top + 1, 0), 0, 2.2)
	end
	-- Flower beds on the lawn between the paths.
	for _, q in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		placeModel(m, "flowers@1", q * 62 + Vector3.new(0, top + 1.4, 0), rng:NextNumber(0, 6.28), 3)
	end
	-- Trees in the square's corners, outside the round path.
	for _, q in { Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) } do
		for _ = 1, 4 do
			local p = q * rng:NextNumber(150, 225) + Vector3.new(q.Z, 0, -q.X) * rng:NextNumber(-60, 60)
			if math.abs(p.X) < 240 and math.abs(p.Z) < 240 and p.Magnitude > 175 then
				makeTree(m, p + Vector3.new(0, top + 0.6, 0), rng:NextNumber(20, 30), rng)
			end
		end
	end
	m.Parent = workspace
	return m
end

-- The web game's wild meadow (Outskirts.tsx, Shared.Models.Scenery "wilds:x,z") on the land plots
-- round every plot that nobody has bought: round free plots all but the new town's land (the fenced
-- lawn), round a neighbour's town all but the plots they own. The player's own town has its own
-- (client/Countryside). Only plots near where the camera looks are drawn, so phones stay smooth.
-- Drawn out to about twice the camera's height (so a zoomed-out view isn't cut short), between
-- these radii; from higher than WILDS_TOP (the claim screen's view of the whole map) none at all.
local WILDS_MIN, WILDS_MAX, WILDS_MAX_PHONE = 900, 1400, 1000
local WILDS_TOP = 2600
local LAND_W = data.PLOT * data.TILE * Catalog.SCALE -- a land plot, across, in studs
local START: { [string]: boolean } = {}
for _, k in data.START_LAND do
	START[k] = true
end

-- The middle of land plot (px, pz), in studs from its town's middle (Countryside's edge()).
local function landMiddle(px: number, pz: number): (number, number)
	local function edge(p: number): number
		return ((p * data.PLOT - (data.GRID - 1) / 2) * data.TILE - data.TILE / 2) * Catalog.SCALE
	end
	return edge(px) + LAND_W / 2, edge(pz) + LAND_W / 2
end

-- The land plots a plot's town owns: the starting land while it's free; once claimed, its town's
-- Land parts (server/TownView names them "x,z"), or the starting land until they stream in.
local function ownedLand(plot: Instance, towns: Instance?): { [string]: boolean }
	if plot:GetAttribute("Free") ~= false or not towns then
		return START
	end
	local origin = plot:GetAttribute("Origin")
	for _, t in towns:GetChildren() do
		if t:GetAttribute("Origin") == origin then
			local land = t:FindFirstChild("Land")
			local out = {}
			local any = false
			if land then
				for _, p in land:GetChildren() do
					out[p.Name] = true
					any = true
				end
			end
			return if any then out else START
		end
	end
	return START
end

-- The shared ground's meadow picture: up close it's the web game's meadow, but from far back its
-- little tufts blur into speckle (the zoomed-out claim view looked like noisy carpet), so it gives way
-- to the meadow's own flat colour once the camera is high.
-- (Off, not faded: a part's Texture drawn see-through can show over the roads lying on it.)
local TEXTURE_OFF = 1500 -- camera height, in studs

local function buildStretch(g: Grid, folder: Folder, along: "x" | "z", line: number, from: number): Model
	local m = Instance.new("Model")
	m.Name = `{along}{line}:{from}`
	local rng = Random.new(math.floor(line * 31 + from * 7 + (if along == "x" then 1 else 2)))
	local edge = g.width / 2
	local function at(s: number, side: number, out: number): Vector3
		if along == "x" then
			return Vector3.new(s, g.top - 0.4, line + side * (edge + out))
		end
		return Vector3.new(line + side * (edge + out), g.top - 0.4, s)
	end
	local function near(s: number): boolean
		-- Not in the crossroads or on the hub's square.
		for _, l in g.lines do
			if math.abs(s - l) < edge + 16 then
				return true
			end
		end
		return math.abs(s) < 300 and math.abs(line) < 300
	end
	local function place(name: string, p: Vector3, turn: number, scale: number?)
		placeModel(m, name, p, turn, scale)
	end
	local function tree(p: Vector3, size: number)
		makeTree(m, p, size, rng)
	end
	local s = from + 60
	local side = 1
	while s < from + STRETCH do
		if not near(s) then
			-- A lamp facing the road, sides taking turns.
			local face = if along == "x" then (if side > 0 then math.pi else 0) else (if side > 0 then -math.pi / 2 else math.pi / 2)
			place("prop:lamp", at(s, side, 6), face, 2.2)
			-- Something growing further out: mostly trees in little clumps.
			local other = -side
			for _ = 1, rng:NextInteger(1, 3) do
				local r = rng:NextNumber()
				local out = rng:NextNumber(20, 90)
				local p = at(s + rng:NextNumber(-55, 55), if rng:NextNumber() < 0.7 then other else side, out)
				if r < 0.6 then
					tree(p, rng:NextNumber(14, 22))
				elseif r < 0.8 then
					place("bush", p, rng:NextNumber(0, 6.28), rng:NextNumber(2, 3))
				elseif r < 0.9 then
					place(`rock:{rng:NextInteger(1, 3)}`, p, rng:NextNumber(0, 6.28), rng:NextNumber(0.8, 1.4))
				else
					place(`tuft:{rng:NextInteger(1, 5)}`, p, rng:NextNumber(0, 6.28), 3)
				end
			end
		end
		side = -side
		s += 120
	end
	m.Parent = folder
	return m
end

---------------------------------------------------------------------------------------------------

-- Every road car near enough to get in: uid -> model.
function WorldLife.cars(): { [string]: Model }
	local out = {}
	for _, c in cars do
		if not c.taken and c.shown then
			out[c.uid] = c.model
		end
	end
	return out
end

function WorldLife.modelOf(uid: string): Model?
	local c = byUid[uid]
	return c and c.model
end

-- Takes a road car out of the traffic (the player's getting in); its model stays where it is.
function WorldLife.take(uid: string): Model?
	local c = byUid[uid]
	if not c then
		return nil
	end
	c.taken = true
	return c.model
end

-- Back into the traffic, on the nearest road.
function WorldLife.give(uid: string)
	local c = byUid[uid]
	if not c or not c.taken then
		return
	end
	c.taken = false
	c.shown = nil
	c.v = 0
end

-- A parking spot on the verge of the road nearest world point p, just off the asphalt on p's side,
-- facing along the road with the verge on its right (car models face +Z).
function WorldLife.roadsideNear(p: Vector3): CFrame?
	local g = theGrid
	if not g then
		return nil
	end
	local lx, lz = nearestLine(g, p.X), nearestLine(g, p.Z)
	local off = g.width / 2 + 9
	if math.abs(p.X - lx) <= math.abs(p.Z - lz) then
		-- A road running along z at x = lx.
		local side = if p.X >= lx then 1 else -1
		local z = math.clamp(p.Z, -g.reach, g.reach)
		-- Right of a car facing (0, fz) is (-fz, 0): the verge on the right means fz = -side.
		return CFrame.new(lx + side * off, g.top, z) * CFrame.Angles(0, math.atan2(0, -side), 0)
	end
	local side = if p.Z >= lz then 1 else -1
	local x = math.clamp(p.X, -g.reach, g.reach)
	-- Right of a car facing (fx, 0) is (0, fx): fx = side.
	return CFrame.new(x, g.top, lz + side * off) * CFrame.Angles(0, math.atan2(side, 0), 0)
end

-- Brings the world's roads to life: returns a function that moves everything on by dt seconds,
-- for a camera at `eye` and the player at `me`.
function WorldLife.attach(world: Instance): (rawDt: number, eye: Vector3, me: Vector3?) -> ()
	local g = gridOf(world)
	theGrid = g
	local folder = Instance.new("Folder")
	folder.Name = "RoadTraffic"
	folder.Parent = workspace
	local verges = Instance.new("Folder")
	verges.Name = "Verges"
	verges.Parent = workspace
	spawnCars(g, folder)
	dressHub(g)
	-- (A free plot's meadow comes back when its town leaves: it takes the setting as it arrives.)
	local ground = world:FindFirstChild("Ground")
	local textureFade = 0
	if ground then
		ground.DescendantAdded:Connect(function(d)
			if d:IsA("Texture") then
				d.Transparency = textureFade
			end
		end)
	end
	local wildsFolder = Instance.new("Folder")
	wildsFolder.Name = "WorldWilds"
	wildsFolder.Parent = workspace
	local wilds: { [string]: Model } = {}
	local rng = Random.new()
	local stretches: { [string]: Model } = {}
	local nextVerge = 0
	local nextUpgrade = 0
	return function(rawDt: number, eye: Vector3, me: Vector3?)
		local dt = math.min(rawDt, 0.1)
		-- Cars built before their meshes reached this player are built again once they have.
		nextUpgrade -= rawDt
		if nextUpgrade <= 0 then
			nextUpgrade = 1
			for _, c in cars do
				if not c.taken and CarDetail.ready(c.detail) then
					local fresh, detail = carModel(c.model:GetAttribute("Model") :: string, c.model:GetAttribute("Color") :: string)
					if fresh and detail then
						c.detail = CarDetail.swap(c.detail, fresh, detail)
						c.model = fresh
					end
				end
			end
		end
		for _, c in cars do
			if c.taken then
				continue
			end
			stepCar(g, c, dt, me, rng)
			local pose = poseOf(g, c)
			if (pose.Position - eye).Magnitude > SHOWN then
				-- Too far to see: it turns up again on a road a little way from the camera, so the
				-- roads round the player always have traffic.
				c.shown = nil
				c.model:PivotTo(HIDDEN)
				respawn(g, c, eye, rng)
				continue
			end
			-- Eases through turns rather than snapping round.
			local shown = if c.shown then c.shown:Lerp(pose, math.min(1, dt * 6)) else pose
			c.shown = shown
			c.model:PivotTo(shown)
			CarDetail.lod(c.detail, (shown.Position - eye).Magnitude)
		end
		-- The verges near the camera, a couple of times a second.
		nextVerge -= rawDt
		if nextVerge > 0 then
			return
		end
		nextVerge = 0.5
		local hide = if eye.Y > TEXTURE_OFF then 1 else 0
		if hide ~= textureFade then
			textureFade = hide
			for _, t in (if ground then ground:GetDescendants() else {}) :: { Instance } do
				if t:IsA("Texture") then
					t.Transparency = hide
				end
			end
		end
		-- Where the camera looks on the ground.
		local cam = workspace.CurrentCamera
		local look = if cam then cam.CFrame.LookVector else Vector3.new(0, -1, 0)
		local focus = if look.Y < -0.05 then eye + look * ((eye.Y - g.top) / -look.Y) else eye
		local near = if eye.Y > WILDS_TOP then -1 else math.clamp(eye.Y * 2, WILDS_MIN, if phone() then WILDS_MAX_PHONE else WILDS_MAX)
		local far = near + 250
		local me = if Players.LocalPlayer then Players.LocalPlayer.UserId else nil
		local towns = workspace:FindFirstChild("Towns")
		local plots = world:FindFirstChild("Plots")
		local keepWilds: { [string]: boolean } = {}
		for _, plot in (if plots then plots:GetChildren() else {}) :: { Instance } do
			local origin = plot:GetAttribute("Origin")
			if typeof(origin) ~= "Vector3" or (me ~= nil and plot:GetAttribute("Owner") == me) then
				continue
			end
			local owned: { [string]: boolean }? = nil
			for px = data.PLOT_MIN, data.PLOT_MAX do
				for pz = data.PLOT_MIN, data.PLOT_MAX do
					local mx, mz = landMiddle(px, pz)
					local d = Vector2.new(origin.X + mx - focus.X, origin.Z + mz - focus.Z).Magnitude
					local key = `{plot.Name}:{px},{pz}`
					if d > (if wilds[key] then far else near) then
						continue
					end
					owned = owned or ownedLand(plot, towns)
					if (owned :: any)[`{px},{pz}`] then
						continue
					end
					keepWilds[key] = true
					if not wilds[key] then
						local m = Builder.build(`wilds:{px},{pz}`)
						if m then
							for _, x in m:GetDescendants() do
								if x:IsA("BasePart") then
									x.CanTouch = false
									x.CanQuery = false
								end
							end
							m:PivotTo(CFrame.new(origin))
							m.Parent = wildsFolder
							wilds[key] = m
						end
					end
				end
			end
		end
		for key, m in wilds do
			if not keepWilds[key] then
				m:Destroy()
				wilds[key] = nil
			end
		end
		local keep: { [string]: boolean } = {}
		for _, line in g.lines do
			for _, along in { "x", "z" } do
				local from = -g.reach
				while from < g.reach do
					local mid = from + STRETCH / 2
					local p = if along == "x" then Vector3.new(mid, 0, line) else Vector3.new(line, 0, mid)
					local d = (Vector3.new(eye.X, 0, eye.Z) - p).Magnitude
					local key = `{along}{line}:{from}`
					if stretches[key] and d < VERGE_FAR then
						keep[key] = true
					elseif not stretches[key] and d < VERGE_NEAR then
						stretches[key] = buildStretch(g, verges, along :: any, line, from)
						keep[key] = true
					end
					from += STRETCH
				end
			end
		end
		for key, m in stretches do
			if not keep[key] then
				m:Destroy()
				stretches[key] = nil
			end
		end
	end
end

function WorldLife.start()
	task.spawn(function()
		local world = workspace:WaitForChild("World", 120)
		if not world then
			return
		end
		Builder.useLibrary(60)
		local step = WorldLife.attach(world)
		RunService.RenderStepped:Connect(function(rawDt: number)
			local cam = workspace.CurrentCamera
			local character = Players.LocalPlayer.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			step(rawDt, if cam then cam.CFrame.Position else Vector3.zero, if root then root.Position else nil)
		end)
	end)
end

return WorldLife
