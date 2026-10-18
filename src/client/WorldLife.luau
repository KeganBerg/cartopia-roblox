--!strict
-- Life on the shared world's roads between the plots (server/World): everyday cars driving the
-- road grid, keeping to their lane, following the car in front, turning at the crossroads and
-- stopping for the player, and street lamps, bushes and rocks along the verges.
--
-- It all runs here on the client, like TownLife: each player sees their own traffic. Only what's
-- near the camera is drawn (the verges in stretches, built as they come near and cleared as they
-- go), so phones stay smooth. The cars can be got in like the town's (client/GetIn).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local data = require(Game:WaitForChild("data")) :: any
local Builder = require(Shared:WaitForChild("Models"):WaitForChild("Builder")) :: any
local Paint = require(Shared.Models:WaitForChild("Paint")) :: any

local WorldLife = {}

local CARS = 24
local CARS_PHONE = 12
local SCALE = 0.8 -- the size cars are drawn at (server/Drive.SCALE)
local LANE = 0.25 -- of the road's width, right of the middle
local GAP = 40 -- studs kept behind the car in front
local SHOWN = 1800 -- studs from the camera a car is drawn within
local VERGE_NEAR = 1100 -- verge stretches within this are built...
local VERGE_FAR = 1500 -- ...and cleared past this
local STRETCH = 700 -- studs of road per verge stretch
local HIDDEN = CFrame.new(0, -10000, 0)

type Car = {
	uid: string,
	model: Model,
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

local function spawnCars(g: Grid, folder: Folder)
	local list = pool()
	if #list == 0 then
		return
	end
	local n = if phone() then CARS_PHONE else CARS
	local rng = Random.new(7)
	for i = 1, n do
		local def = list[(i * 5) % #list + 1]
		local m = Builder.build(def.id)
		if not m then
			continue
		end
		local color = def.colors[(i * 3) % #def.colors + 1]
		Paint.apply(m, Paint.jobOf({ color = color }))
		if math.abs(m:GetScale() - SCALE) > 1e-3 then
			m:ScaleTo(SCALE)
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
			end
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
		local piece = Builder.build(name)
		if not piece then
			return
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
		piece.Parent = m
	end
	local s = from + 60
	local side = 1
	while s < from + STRETCH do
		if not near(s) then
			-- A lamp facing the road, sides taking turns.
			local face = if along == "x" then (if side > 0 then math.pi else 0) else (if side > 0 then -math.pi / 2 else math.pi / 2)
			place("prop:lamp", at(s, side, 6), face, 2.2)
			-- Something growing further out.
			local r = rng:NextNumber()
			local out = rng:NextNumber(18, 70)
			local other = -side
			if r < 0.45 then
				place("bush", at(s + rng:NextNumber(-40, 40), other, out), rng:NextNumber(0, 6.28), rng:NextNumber(2, 3.5))
			elseif r < 0.7 then
				place(`rock:{rng:NextInteger(1, 3)}`, at(s + rng:NextNumber(-40, 40), other, out), rng:NextNumber(0, 6.28), rng:NextNumber(2, 4))
			elseif r < 0.85 then
				place(`tuft:{rng:NextInteger(1, 5)}`, at(s + rng:NextNumber(-40, 40), other, out * 0.5), rng:NextNumber(0, 6.28), 3)
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

-- Brings the world's roads to life: returns a function that moves everything on by dt seconds,
-- for a camera at `eye` and the player at `me`.
function WorldLife.attach(world: Instance): (rawDt: number, eye: Vector3, me: Vector3?) -> ()
	local g = gridOf(world)
	local folder = Instance.new("Folder")
	folder.Name = "RoadTraffic"
	folder.Parent = workspace
	local verges = Instance.new("Folder")
	verges.Name = "Verges"
	verges.Parent = workspace
	spawnCars(g, folder)
	local rng = Random.new()
	local stretches: { [string]: Model } = {}
	local nextVerge = 0
	return function(rawDt: number, eye: Vector3, me: Vector3?)
		local dt = math.min(rawDt, 0.1)
		for _, c in cars do
			if c.taken then
				continue
			end
			stepCar(g, c, dt, me, rng)
			local pose = poseOf(g, c)
			if (pose.Position - eye).Magnitude > SHOWN then
				if c.shown then
					c.shown = nil
					c.model:PivotTo(HIDDEN)
				end
				continue
			end
			-- Eases through turns rather than snapping round.
			local shown = if c.shown then c.shown:Lerp(pose, math.min(1, dt * 6)) else pose
			c.shown = shown
			c.model:PivotTo(shown)
		end
		-- The verges near the camera, a couple of times a second.
		nextVerge -= rawDt
		if nextVerge > 0 then
			return
		end
		nextVerge = 0.5
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
