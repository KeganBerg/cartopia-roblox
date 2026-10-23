--!strict
-- The town's life, as the web game's TownCars.tsx and Townspeople.tsx draw it: the player's cars
-- driving round their roads (the web's traffic sim, converted: Shared.Game.scene_traffic_sim), the
-- traffic lights and stop signs at junctions, and townspeople who live in the houses and walk the
-- sidewalks (walkGraph) to the shops, parks and showroom and back, crossing at the zebras.
--
-- It all runs here on the client, for this player's town only, like the countryside: it never
-- changes the game. The cars are the server's own car models (TownView), moved and resized here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local CarDetail = require(script.Parent:WaitForChild("CarDetail"))
local lualib = require(Game:WaitForChild("lualib_bundle")) :: any
local data = require(Game:WaitForChild("data")) :: any
local placement = require(Game:WaitForChild("placement")) :: any
local clock = require(Game:WaitForChild("clock")) :: any
-- The real date's season (scene/season.ts SEASON), as SeasonLook paints the town: beanies in winter.
local WINTER = (require(Game:WaitForChild("scene_season")) :: any).SEASON == "winter"
local trafficLevel = require(Game:WaitForChild("traffic")) :: any
local sim = require(Game:WaitForChild("scene_traffic_sim")) :: any
local layout = require(Game:WaitForChild("scene_traffic_layout")) :: any
local grid = require(Game:WaitForChild("scene_grid")) :: any
local walk = require(Game:WaitForChild("walkGraph")) :: any
local Thought = require(script.Parent:WaitForChild("Thought"))
local ClockShift = require(script.Parent.ClockShift)

local TownLife = {}

local S = Catalog.SCALE -- studs per web unit
local TILE = data.TILE

-- Buses run the school routes (TownCars.tsx SCHOOLS); beaters under LOW_PI live at the trailers.
local SCHOOLS = { "school", "highschool", "university" }
local MAX_VISIBLE = 30
local LOW_PI = 40

local function map(t: { [string]: any }): any
	local m = lualib.__TS__New(lualib.Map)
	for k, v in t do
		m:set(k, v)
	end
	return m
end

---------------------------------------------------------------------------------------------------
-- Traffic: one sim for the town, stepped every frame (TownCars.tsx).

local traffic = lualib.__TS__New(sim.Traffic)
-- The middle of the town the traffic drives in (set by attach).
local townOrigin: Vector3? = nil
-- How far the town's land reaches from its middle (server/World TOWN).
local TOWN_REACH = 560
traffic.walkers = walk.pedestrianCrossings

-- The cars it drives, by uid: the scale each is drawn at (townCarSize.ts).
local scaleOf: { [string]: number } = {}

local townKey = ""
local carsKey = ""
local homesKey = ""

-- Cars taken off the road by the player (driving it, or just left where they parked it).
local taken: { [string]: boolean } = {}

-- A visitor's cars (client/VisitorCar), in the same traffic as the town's, ahead of them and on
-- top of the usual cap (TownCars.tsx), so everyone gives way to everyone at the junctions.
local guests: { any } = {}

local function updateTraffic(save: any)
	local roads = save.roads or {}
	local buildings = save.buildings or {}
	local parts = {}
	for _, b in buildings do
		table.insert(parts, `{b.uid}:{b.def}:{b.x}:{b.z}:{b.rot or "-"}`)
	end
	local key = table.concat(roads, ";") .. "|" .. table.concat(parts, ";")
	local moved = key ~= townKey
	if moved then
		townKey = key
		traffic:setTown(roads, buildings, placement.turnOf)
	end
	local cars = save.cars or {}
	local pace = trafficLevel.townTraffic(save).pace
	local pis: { [string]: number } = {}
	local order = {}
	for _, c in cars do
		pis[c.uid] = data.performance(data.carDef(c.model), c.upgrades, c.mods)
		table.insert(order, c)
	end
	table.sort(order, function(a, b)
		return pis[a.uid] < pis[b.uid]
	end)
	local slow: { [string]: boolean } = {}
	for i = 1, math.ceil(#cars / 3) do
		slow[order[i].uid] = true
	end
	local specs = {}
	local sig = {}
	for _, g in guests do
		table.insert(specs, g)
		table.insert(sig, `{g.uid}:{g.cruise}`)
	end
	for _, c in cars do
		if taken[c.uid] then
			continue
		end
		local def = data.carDef(c.model)
		local size = (Catalog.TOWN_SIZE or {})[c.model] or { 0.8, 0.45, 0.8 }
		scaleOf[c.uid] = size[3]
		local stalled = (c.flat or c.lowFuel) and true or false
		table.insert(specs, {
			uid = c.uid,
			len = size[1],
			wid = size[2],
			cruise = (1.1 + pis[c.uid] / 45) * pace,
			stalled = stalled,
			low = pis[c.uid] < LOW_PI or slow[c.uid] == true,
			favors = if def.body == "bus" then SCHOOLS else nil,
		})
		table.insert(sig, `{c.uid}:{c.model}:{pis[c.uid]}:{stalled}`)
	end
	local max = math.min(MAX_VISIBLE, math.max(3, math.floor(#roads * 0.5))) + #guests
	for uid in taken do
		table.insert(sig, `-{uid}`)
	end
	local ck = table.concat(sig, ";") .. `|{pace}|{max}`
	if moved or ck ~= carsKey then
		carsKey = ck
		traffic:setCars(specs, max)
	end
	local homes = {}
	local hk = {}
	for _, b in buildings do
		if b.car then
			homes[b.car] = b.uid
			table.insert(hk, `{b.car}>{b.uid}`)
		end
	end
	local h = table.concat(hk, ",")
	if h ~= homesKey then
		homesKey = h
		traffic.homes = map(homes)
	end
end

-- May people cross on tile `tile` at its edge facing `side` (live.ts crossingSignal)? "walk" while
-- the cars heading into the junction from that road have a red light, "wait" otherwise, nil where
-- there are no lights.
local D = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local function crossingSignal(tile: string, side: number): string?
	local tiles = traffic.net.layout.tiles
	local t = tiles:get(tile)
	if not t then
		return nil
	end
	local j = tiles:get(`{t.x + D[side + 1][1]},{t.z + D[side + 1][2]}`)
	local c = if j and j.cluster >= 0 then traffic.net.layout.clusters[j.cluster + 1] else nil
	if not c or not c.signal then
		return nil
	end
	if traffic:lightOf(c.id, side) == "red" then
		return "walk"
	end
	traffic:wantWalk(c.id, side)
	return "wait"
end

---------------------------------------------------------------------------------------------------
-- Traffic lights and stop signs at the junctions (TownCars.tsx TrafficSignals).

local function part(parent: Instance, shape: Enum.PartType?, size: Vector3, cf: CFrame, color: string, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = Color3.fromHex(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A cylinder standing up (Roblox's run along x), `d` across and `h` tall, its middle at `cf`.
local UP = CFrame.Angles(0, 0, math.pi / 2)
local function post(parent: Instance, d: number, h: number, cf: CFrame, color: string): Part
	return part(parent, Enum.PartType.Cylinder, Vector3.new(h, d, d) * S, cf * UP, color)
end

local LIT = { red = "#f44336", yellow = "#ffb300", green = "#4caf50" }
local ORDER = { "red", "yellow", "green" }
local DARK = Color3.fromHex("#3a3a3a")

type Lamp = { part: Part, cluster: number, heading: number, look: string }
local signalsKey = ""
local signals: Folder? = nil
local lamps: { Lamp } = {}

local function drawSignals(origin: Vector3, roads: { string })
	local key = table.concat(roads, ";")
	if key == signalsKey then
		return
	end
	signalsKey = key
	if signals then
		signals:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "TrafficSignals"
	signals = folder
	table.clear(lamps)
	local lay = layout.layoutRoads(roads)
	for _, c in lay.clusters do
		for _, e in c.entries do
			if not c.signal and not e.stop then
				continue
			end
			local from = lay.tiles:get(e.from)
			local w = grid.toWorld(from.x, from.z)
			local dir = grid.DIRS[e.heading + 1]
			local dx, dz = dir[1], dir[2]
			local rx, rz = -dz, dx
			local along = TILE / 2 - 0.3
			local side = TILE / 2 - 0.16
			local x, z = w[1] + dx * along + rx * side, w[2] + dz * along + rz * side
			local at = CFrame.new(origin + Vector3.new(x, 0, z) * S) * CFrame.Angles(0, math.atan2(-dx, -dz), 0)
			local function local_(lx: number, ly: number, lz: number): CFrame
				return at * CFrame.new(lx * S, ly * S, lz * S)
			end
			if not c.signal then
				-- Stop sign: pole, base, the octagon's white rim and red face, and its white bar.
				post(folder, 0.06, 1.2, local_(0, 0.6, 0), "#9e9e9e")
				post(folder, 0.11, 0.03, local_(0, 0.015, 0), "#9e9e9e")
				local face = local_(0, 1.15, 0) * CFrame.Angles(0, math.pi / 2, 0)
				part(folder, Enum.PartType.Cylinder, Vector3.new(0.02, 0.48, 0.48) * S, face * CFrame.new(-0.03 * S, 0, 0), "#fafafa")
				part(folder, Enum.PartType.Cylinder, Vector3.new(0.01, 0.43, 0.43) * S, face * CFrame.new(-0.042 * S, 0, 0), "#c62828")
				part(folder, nil, Vector3.new(0.24, 0.06, 0.005) * S, local_(0, 1.15, 0.05), "#fafafa")
			else
				-- Light: pole and base, the arm out over the road and the housing hung from it.
				post(folder, 0.07, 1.5, local_(0, 0.75, 0), "#37474f")
				post(folder, 0.13, 0.1, local_(0, 0.05, 0), "#37474f")
				part(folder, nil, Vector3.new(0.5, 0.04, 0.04) * S, local_(-0.25, 1.46, 0), "#37474f")
				part(folder, nil, Vector3.new(0.17, 0.46, 0.12) * S, local_(-0.44, 1.2, 0), "#263238")
				for k = 0, 2 do
					for _, f in { 1, -1 } do
						local lamp = part(folder, Enum.PartType.Ball, Vector3.one * 0.116 * S, local_(-0.44, 1.2 + 0.145 - k * 0.145, f * 0.05), "#3a3a3a")
						lamp.Name = ORDER[k + 1]
						table.insert(lamps, { part = lamp, cluster = c.id, heading = e.heading, look = "" })
					end
				end
			end
		end
	end
	folder.Parent = workspace
end

local function stepSignals()
	for _, l in lamps do
		local now = traffic:lightOf(l.cluster, l.heading)
		if now ~= l.look then
			l.look = now
			local on = l.part.Name == now
			l.part.Color = if on then Color3.fromHex(LIT[now]) else DARK
			l.part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

---------------------------------------------------------------------------------------------------
-- Townspeople (Townspeople.tsx): residents of the houses, a few more as the town levels up.

local PERSON = { scale = 1.3, leg = 0.24 }
local LEG = PERSON.leg
-- Figures are drawn at a Roblox character's height (about 5.3 studs) rather than the web's 1.3x
-- scale, which would make them nearly twice the player's size. A figure is 0.69 model units tall
-- (shoes to hair); FIT is how much smaller than the web's scale that is, for the dogs too.
local K = 5.3 / 0.69 -- studs per model unit of a figure
local FIT = K / (PERSON.scale * S)
local SHIRTS = { "#e53935", "#1e88e5", "#fdd835", "#43a047", "#8e24aa", "#ff7043", "#fafafa", "#26c6da", "#ec407a", "#5c6bc0" }
local PANTS = { "#37474f", "#1565c0", "#5d4037", "#212121", "#78909c", "#283593" }
local SKIN = { "#f5d0b5", "#e0ac8a", "#c68863", "#8d5a3b", "#5c3a24", "#f1c27d" }
local HAIR = { "#3e2723", "#212121", "#6d4c41", "#fbc02d", "#bf360c", "#9e9e9e" }
local BEANIES = { "#d32f2f", "#1976d2", "#388e3c", "#fbc02d", "#7b1fa2" }
-- What they wear (the web draws one shirt over trousers; here there's more to see up close).
local JACKETS = { "#455a64", "#6d4c41", "#1a237e", "#2e7d32", "#c62828", "#37474f", "#f9a825" }
local SHOES = { "#2b2b2b", "#fafafa", "#5d4037", "#c62828", "#1565c0", "#2b2b2b" }
local HATS = { "#d32f2f", "#1976d2", "#212121", "#fbc02d", "#2e7d32", "#fafafa" }
local TOPS = { "tee", "tee", "stripe", "jacket", "hoodie", "polo" }
local HAIRDOS = { "short", "short", "long", "ponytail", "bun", "cap", "curly", "buzz" }
local DOG_COATS = { "#8d6e63", "#f5f5f5", "#5d4037", "#d4a056", "#a1887f", "#3a3a3a" }
local DOG_SIZES = { 0.8, 0.9, 1, 1.1, 1.2 }
local LEASHES = { "#d32f2f", "#1565c0", "#2e7d32", "#212121", "#f9a825", "#6a1b9a" }
local NAMES = { "Alex", "Sam", "Jordan", "Riley", "Casey", "Morgan", "Taylor", "Jamie", "Quinn", "Avery", "Rowan", "Skyler", "Drew", "Kai", "Robin", "Charlie", "Frankie", "Jesse", "Remy", "Sage" }
local DOGS = { "Biscuit", "Rocket", "Pepper", "Daisy", "Turbo", "Maple", "Nugget", "Scout" }

-- Where to stand at each decoration, how long to linger, which make a park, and the seats.
local SPOT: { [string]: number } = {
	bench = 0.06, fountain = 0.98, flowers = 0.86, tree = 0.5, palm = 0.5, statue = 0.78, lamp = 0.45, billboard = 0.7,
	pine = 0.7, picnic = 0.45, busstop = -0.22, hotdog = 0.5, flagpole = 0.6, gazebo = 0.25, clocktower = 0.8,
	pumpkins = 0.6, scarecrow = 0.55, graves = 0.65, deadtree = 0.6, court = 0.6, cauldron = 0.6, jacklamp = 0.5,
}
local LINGER: { [string]: { number } } = {
	bench = { 10, 24 }, fountain = { 5, 12 }, statue = { 4, 9 }, pond = { 6, 14 },
	picnic = { 12, 26 }, busstop = { 8, 18 }, hotdog = { 4, 8 }, gazebo = { 8, 18 }, playground = { 10, 22 }, clocktower = { 4, 9 },
	dogpark = { 10, 22 }, skatepark = { 8, 18 }, koi = { 8, 16 }, garden = { 10, 20 },
	pumpkins = { 5, 12 }, graves = { 4, 9 }, court = { 10, 22 }, tennis = { 10, 22 }, cornmaze = { 8, 18 }, cauldron = { 4, 9 },
}
local function set(list: { string }): { [string]: boolean }
	local s = {}
	for _, k in list do
		s[k] = true
	end
	return s
end
local PARKS = set({ "bench", "fountain", "flowers", "tree", "palm", "statue", "pond", "pine", "picnic", "busstop", "hotdog", "flagpole", "gazebo", "clocktower", "pumpkins", "scarecrow", "graves", "deadtree", "court", "cauldron", "jacklamp" })
local BIG_PARKS = set({ "pond", "playground", "dogpark", "skatepark", "koi", "garden", "tennis", "cornmaze" })
local SEATS: { [string]: string } = { bench = "back", busstop = "out", picnic = "in" }
local FRONT_DOOR = set({ "busstop", "gazebo" })
-- Food is the big draw (Townspeople.tsx ITEMS): those shops go in the list twice.
local FOOD = set({ "pizza", "coffee", "burger", "icecream", "bakery", "donut", "taco", "sushi", "diner", "hotdog", "juice", "bbq", "noodles", "cafe" })

local function seatFacing(seat: string, turn: number): number
	return if seat == "back" then (turn + 2) % 4 else turn
end

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end
local function pick<T>(xs: { T }): T
	return xs[math.random(1, #xs)]
end
local function hash(s: string): number
	local h = 0
	for i = 1, #s do
		h = (h * 31 + string.byte(s, i)) % 4294967296
		if h >= 2147483648 then
			h -= 4294967296
		end
	end
	return math.abs(h)
end

type Pt = { number }
type Dest = { kind: string, key: string, def: string }
type Bit = { part: BasePart, bone: number, off: CFrame, near: boolean }
type Figure = { model: Model, bits: { Bit }, dog: { BasePart }, leash: BasePart, shown: boolean, near: boolean, k: number }
-- How a figure stands (see pose()): hips and head (figure units and radians), each leg's swing
-- and knee bend, and each arm's turn at the shoulder (left, then right).
export type Pose = { hip: number, lean: number, twist: number, nod: number, look: number, legs: { { number } }, arms: { CFrame } }
type Person = {
	id: string,
	type: string,
	name: string,
	dogName: string,
	dogPos: Pt,
	dogHeading: number,
	dogSize: number,
	home: string,
	at: string,
	pos: Pt,
	heading: number,
	face: number?,
	speed: number,
	stride: number,
	state: string,
	sit: boolean,
	timer: number,
	waited: number,
	steps: { any },
	si: number,
	crossing: string?,
	dest: Dest?,
	outings: number,
	colors: { shirt: string, pants: string, skin: string, hair: string, dog: string },
	look: { top: string, hair: string, shorts: boolean, coat: string, trim: string, shoes: string, hat: string },
	queue: string?, -- the club whose line they're standing in
	fig: Figure?,
	-- How big the figure is drawn, 1 for a grown-up (CampusLife's schoolkids are smaller).
	size: number?,
}

local inLine: (p: any, dt: number) -> ()
local followThought: (list: { any }) -> ()

local function nodePos(n: any): Pt
	return if n.kind == "v" then n.pos else n.center
end

local function person(id: string, home: string, pos: Pt): Person
	local h = hash(id)
	local kind = if h % 6 == 0 then "jogger" elseif h % 6 == 1 then "dog" else "walker"
	return {
		id = id,
		type = kind,
		name = NAMES[(h // 16) % #NAMES + 1],
		dogName = DOGS[(h // 128) % #DOGS + 1],
		dogPos = { pos[1], pos[2] },
		dogHeading = 0,
		dogSize = DOG_SIZES[(h // 8192) % #DOG_SIZES + 1],
		home = home,
		at = `b{home}`,
		pos = { pos[1], pos[2] },
		heading = 0,
		face = nil,
		speed = if kind == "jogger" then rand(1.5, 1.8) else rand(0.65, 0.9),
		stride = rand(0, 6),
		state = "inside",
		sit = false,
		timer = rand(0.5, 10),
		waited = 0,
		steps = {},
		si = 1,
		crossing = nil,
		dest = nil,
		outings = 0,
		colors = {
			shirt = SHIRTS[h % #SHIRTS + 1],
			pants = PANTS[(h // 8) % #PANTS + 1],
			skin = SKIN[(h // 64) % #SKIN + 1],
			hair = (if WINTER then BEANIES else HAIR)[(h // 512) % 5 + 1],
			dog = DOG_COATS[(h // 2048) % #DOG_COATS + 1],
		},
		look = {
			top = if kind == "jogger" then "tee" else TOPS[(h // 4096) % #TOPS + 1],
			hair = if WINTER then "beanie" else HAIRDOS[(h // 32768) % #HAIRDOS + 1],
			shorts = not WINTER and (kind == "jogger" or (h // 262144) % 4 == 0),
			coat = JACKETS[(h // 1048576) % #JACKETS + 1],
			trim = if (h // 4194304) % 2 == 0 then "#fafafa" else "#212121",
			shoes = if kind == "jogger" then "#fafafa" else SHOES[(h // 16777216) % #SHOES + 1],
			hat = HATS[(h // 67108864) % #HATS + 1],
		},
		queue = nil,
		fig = nil,
	}
end

type Club = { dest: Dest, center: Pt, turn: number }
type Places = { shops: { Dest }, browse: { Dest }, parks: { Dest }, houses: { Dest }, corners: { Dest }, clubs: { Club } }

-- Places worth walking to, sorted by what kind of outing they make.
local function destinations(g: any): Places
	local p: Places = { shops = {}, browse = {}, parks = {}, houses = {}, corners = {}, clubs = {} }
	g.byKey:forEach(function(_, _i, key)
		if string.sub(key, 1, 1) == "v" then
			table.insert(p.corners, { kind = "jog", key = key, def = "" })
		end
	end)
	for _, n in g.nodes do
		if n.kind == "b" then
			local def = data.buildingDef(n.def)
			local function d(k: string): Dest
				return { kind = k, key = `b{n.uid}`, def = n.def }
			end
			if def.nightOnly then
				table.insert(p.clubs, { dest = d("club"), center = n.center, turn = n.turn })
			elseif def.kind == "business" or def.kind == "gas" or def.kind == "parts" then
				table.insert(p.shops, d("shop"))
				if FOOD[n.def] then
					table.insert(p.shops, d("shop"))
				end
			elseif def.kind == "showroom" or def.kind == "garage" then
				table.insert(p.browse, d("browse"))
			elseif def.kind == "house" then
				table.insert(p.houses, d("friend"))
			elseif BIG_PARKS[n.def] then
				table.insert(p.parks, d("park"))
				table.insert(p.parks, d("park"))
			end
		elseif n.kind == "t" and n.decor and PARKS[n.decor] then
			table.insert(p.parks, { kind = "park", key = `t{n.tile[1]},{n.tile[2]}`, def = n.decor })
		end
	end
	return p
end

local function nearestNode(g: any, at: Pt): number?
	local best, bestD = nil, math.huge
	for i, n in g.nodes do
		if n.kind == "b" then
			continue
		end
		local q = nodePos(n)
		local d = math.sqrt((q[1] - at[1]) ^ 2 + (q[2] - at[2]) ^ 2)
		if d < bestD then
			bestD = d
			best = i - 1
		end
	end
	return best
end

local function nodeAt(g: any, key: string): number?
	return g.byKey:get(key)
end

local function turnTo(p: Person, target: number, dt: number)
	local diff = target - p.heading
	diff = math.atan2(math.sin(diff), math.cos(diff))
	p.heading += diff * math.min(1, dt * 10)
end

local function leaveCrossing(p: Person)
	if not p.crossing then
		return
	end
	local c = walk.pedestrianCrossings
	local n = (c:get(p.crossing) or 1) - 1
	if n > 0 then
		c:set(p.crossing, n)
	else
		c:delete(p.crossing)
	end
	p.crossing = nil
end

local function carNear(at: Pt, r: number): boolean
	local near = false
	traffic.agents:forEach(function(_, a: any)
		if not near and math.sqrt((a.x - at[1]) ^ 2 + (a.z - at[2]) ^ 2) < r then
			near = true
		end
	end)
	return near
end

-- Where a walked dog heads for: behind and beside its walker, or beside them while they stop.
local function dogSpot(p: Person): (number, number)
	local sin, cos = math.sin(p.heading), math.cos(p.heading)
	local still = p.state == "linger"
	local back = (if still then -0.1 else 0.4) * FIT
	local side = (if still then 0.35 else 0.22) * FIT
	return p.pos[1] - sin * back + cos * side, p.pos[2] - cos * back - sin * side
end

-- Closest a dog comes to its walker's middle: any nearer and it would show inside their legs.
local DOG_CLEAR = 0.3 * FIT

local function walkDog(p: Person, dt: number)
	if p.type ~= "dog" then
		return
	end
	local tx, tz = dogSpot(p)
	local dx, dz = tx - p.dogPos[1], tz - p.dogPos[2]
	local k = math.min(1, dt * 6)
	p.dogPos[1] += dx * k
	p.dogPos[2] += dz * k
	-- Catching up round a sharp turn, it goes round its walker rather than through them.
	local ox, oz = p.dogPos[1] - p.pos[1], p.dogPos[2] - p.pos[2]
	local off = math.sqrt(ox * ox + oz * oz)
	if off < DOG_CLEAR then
		if off < 1e-6 then
			ox, oz, off = tx - p.pos[1], tz - p.pos[2], math.sqrt((tx - p.pos[1]) ^ 2 + (tz - p.pos[2]) ^ 2)
		end
		p.dogPos[1] = p.pos[1] + ox / off * DOG_CLEAR
		p.dogPos[2] = p.pos[2] + oz / off * DOG_CLEAR
	end
	local target = if math.sqrt(dx * dx + dz * dz) > 0.03 then math.atan2(dx, dz) else p.heading
	local diff = target - p.dogHeading
	diff = math.atan2(math.sin(diff), math.cos(diff))
	p.dogHeading += diff * math.min(1, dt * 8)
end

-- Somewhere to go on an outing: food most often, then parks, the showroom or a neighbour.
local function outing(g: any, places: Places, p: Person): Dest?
	if p.type == "jogger" and #places.corners > 0 then
		local best, bestD = nil, -1
		for _ = 1, 4 do
			local c = pick(places.corners)
			local q = nodePos(g.nodes[(nodeAt(g, c.key) :: number) + 1])
			local d = math.sqrt((q[1] - p.pos[1]) ^ 2 + (q[2] - p.pos[2]) ^ 2)
			if d > bestD then
				bestD = d
				best = c
			end
		end
		return best
	end
	if p.type == "dog" and #places.parks > 0 and math.random() < 0.7 then
		return pick(places.parks)
	end
	local r = math.random()
	local others = {}
	for _, h in places.houses do
		if h.key ~= `b{p.home}` then
			table.insert(others, h)
		end
	end
	local order: { { Dest } } = if r < 0.45 then { places.shops, places.parks, places.browse }
		elseif r < 0.8 then { places.parks, places.shops, places.browse }
		elseif r < 0.9 then { places.browse, places.shops, places.parks }
		else { others, places.parks, places.shops }
	for _, l in order do
		if #l > 0 then
			return pick(l)
		end
	end
	return nil
end

-- The last few steps from the edge of a decoration to a good spot at it.
local function settle(p: Person, n: any)
	local entry = if #p.steps > 0 then p.steps[#p.steps].p else p.pos
	local c = n.center
	local seat = SEATS[n.decor or ""]
	local bench = seat == "out" or seat == "back"
	local near = walk.sideOf(c, entry)
	local front = FRONT_DOOR[n.decor or ""] == true
	local side = if bench or front then n.turn elseif seat == "in" and (near - n.turn) % 2 ~= 0 then n.turn else near
	local dir = walk.SIDES[side + 1]
	local dx, dz = dir[1], dir[2]
	local r = SPOT[n.decor or ""] or 0.8
	local along = if bench then rand(-0.25, 0.25) else rand(-0.3, 0.3)
	local spot = { c[1] + dx * r + dz * along, c[2] + dz * r - dx * along }
	local to = spot
	if front then
		to = { c[1] + dx * 0.95, c[2] + dz * 0.95 }
	end
	for _, w in walk.transit(n, entry, to) do
		table.insert(p.steps, { p = w })
	end
	table.insert(p.steps, { p = to })
	if front then
		table.insert(p.steps, { p = spot })
	end
end

-- The nightclub's line (Townspeople.tsx): people queue along the velvet rope, and the bouncer
-- (client/ClubLife draws him) lets the front of the line in every few seconds.
-- Where things stand at the club, in its lot's own units (clubLayout.ts CLUB).
local CLUB = { doorX = -1.0, doorZ = 0.36, queueZ = 0.82, queueX = -0.5, gap = 0.3, queueMax = 8, inPath = { { -0.55, 0.98 }, { -1.0, 0.98 } } }
local clubsNow: { Club } = {}
local queues: { [string]: { Person } } = {}
local gates: { [string]: number } = {}
-- What each club's bouncer sees at his rope (clubDoor.ts), by club key: where the club stands in
-- the world (studs), whether someone's waiting at the front, and when he last let someone in.
type Door = { at: Vector3, waiting: boolean, admitted: number }
local doors: { [string]: Door } = {}

local function clubAt(key: string): Club?
	for _, c in clubsNow do
		if c.dest.key == key then
			return c
		end
	end
	return nil
end

-- A point in front of the club, from its own coordinates to the town's.
local function clubPoint(c: Club, lx: number, lz: number): Pt
	local a = c.turn * math.pi / 2
	local cos, sin = math.cos(a), math.sin(a)
	return { c.center[1] + lx * cos + lz * sin, c.center[2] - lx * sin + lz * cos }
end

local function doorOf(key: string, c: Club): Door
	local at = (townOrigin or Vector3.zero) + Vector3.new(c.center[1], 0, c.center[2]) * S
	local d = doors[key]
	if not d then
		d = { at = at, waiting = false, admitted = 0 }
		doors[key] = d
	end
	d.at = at
	return d
end

-- The bouncer's view of the club standing at `at` (studs), if anyone has queued there.
function TownLife.clubDoor(at: Vector3): Door?
	for _, d in doors do
		if (Vector3.new(d.at.X - at.X, 0, d.at.Z - at.Z)).Magnitude < 0.75 * S then
			return d
		end
	end
	return nil
end

-- Each club's bouncer lets the front of the line in every few seconds, and sends everyone home
-- when the club closes at dawn.
local function bouncers(dt: number)
	local open = clock.isNight()
	for key, q in queues do
		local c = clubAt(key)
		if not c or not open then
			for _, p in q do
				p.queue = nil
				p.state = "linger"
				p.face = nil
				p.timer = rand(0.3, 2)
			end
			queues[key] = nil
			if doors[key] then
				doors[key].waiting = false
			end
			continue
		end
		local left = (gates[key] or rand(6, 10)) - dt
		gates[key] = left
		local first = q[1]
		local d = doorOf(key, c)
		-- Only once they've made it to the front of the rope.
		d.waiting = first ~= nil and first.face ~= nil
		if left > 0 or not d.waiting then
			continue
		end
		table.remove(q, 1)
		first.queue = nil
		first.face = nil
		first.dest = { kind = "door", key = key, def = c.dest.def }
		-- Round the end of the rope and in front of the canopy pole, then up the carpet.
		first.steps = {}
		for _, w in CLUB.inPath do
			table.insert(first.steps, { p = clubPoint(c, w[1], w[2]) })
		end
		table.insert(first.steps, { p = clubPoint(c, CLUB.doorX, CLUB.doorZ) })
		first.si = 1
		first.state = "walk"
		d.admitted = os.clock()
		gates[key] = rand(8, 15)
	end
end

-- Shuffle up to your place in line, then wait facing the door.
inLine = function(p: Person, dt: number)
	local c = if p.queue then clubAt(p.queue) else nil
	local q = if p.queue then queues[p.queue] else nil
	local i = if q then table.find(q, p) else nil
	if not c or not i then
		p.queue = nil
		p.state = "linger"
		p.timer = rand(0.3, 1.5)
		return
	end
	local spot = clubPoint(c, CLUB.queueX + (i - 1) * CLUB.gap, CLUB.queueZ)
	local dx, dz = spot[1] - p.pos[1], spot[2] - p.pos[2]
	local len = math.sqrt(dx * dx + dz * dz)
	local move = p.speed * 0.8 * FIT * dt
	if len > 0.02 then
		p.face = nil
		local k = math.min(1, move / len)
		p.pos[1] += dx * k
		p.pos[2] += dz * k
		turnTo(p, math.atan2(dx, dz), dt)
		p.stride += move * S / K * 14
		return
	end
	local a = c.turn * math.pi / 2
	p.face = math.atan2(-math.cos(a), math.sin(a))
	turnTo(p, p.face :: number, dt)
end

-- Done with the current stop (or time to leave home): work out the next one.
local function setOff(g: any, places: Places, p: Person, night: boolean)
	p.sit = false
	p.face = nil
	local atHome = p.at == `b{p.home}`
	-- After dark the nightclub is the place to be (not for joggers or dog walkers).
	local clubs = {}
	if night and p.type == "walker" then
		for _, c in places.clubs do
			if c.dest.key ~= p.at then
				table.insert(clubs, c)
			end
		end
	end
	local club = if #clubs > 0 and math.random() < (if atHome then 0.6 else 0.4) then pick(clubs).dest else nil
	if atHome and night and not club and math.random() < 0.85 then
		p.timer = rand(20, 45) -- most people stay in after dark
		return
	end
	local dest: Dest? = club
	if not dest and not atHome and (p.outings >= 3 or math.random() < 0.4 or night) then
		dest = { kind = "home", key = `b{p.home}`, def = "house" }
	end
	local start = nodeAt(g, p.at) or nearestNode(g, p.pos)
	for _ = 1, 4 do
		local d = dest or outing(g, places, p)
		if not d or d.key == p.at then
			continue
		end
		local goal = nodeAt(g, d.key)
		local route = if start ~= nil and goal ~= nil then walk.findPath(g, start, goal) else nil
		if not route then
			dest = nil
			continue
		end
		p.dest = d
		p.steps = walk.stepsFor(g, route, p.pos)
		p.si = 1
		local last = g.nodes[(goal :: number) + 1]
		if last.kind == "t" then
			settle(p, last)
		end
		if p.state == "inside" then
			-- Step out of the front door.
			local first = p.steps[1]
			if first then
				local from = nodePos(g.nodes[(start :: number) + 1])
				p.pos = { first.p[1], first.p[2] }
				p.heading = math.atan2(first.p[1] - from[1], first.p[2] - from[2])
				p.si = 2
			end
			-- The dog comes out at their heels (walkDog keeps it clear of their legs).
			p.dogPos = { p.pos[1], p.pos[2] }
			p.dogHeading = p.heading
			walkDog(p, 0)
		end
		p.state = "walk"
		p.outings += 1
		return
	end
	p.timer = rand(6, 14) -- nowhere reachable: try again in a bit
end

local function arrive(g: any, p: Person, night: boolean)
	leaveCrossing(p)
	local d = p.dest
	p.steps = {}
	p.si = 1
	if not d then
		p.state = "inside"
		p.timer = 1
		return
	end
	p.at = d.key
	local i = nodeAt(g, d.key)
	local node = if i then g.nodes[i + 1] else nil
	if d.kind == "jog" then
		p.state = "linger"
		p.timer = rand(0.2, 0.8)
		return
	end
	if d.kind == "club" then
		local q = queues[d.key] or {}
		if not clock.isNight() or #q >= CLUB.queueMax or not clubAt(d.key) then
			-- Closed, or the line's too long: hang about a moment, then move on.
			p.state = "linger"
			p.timer = rand(1, 3)
			return
		end
		table.insert(q, p)
		queues[d.key] = q
		p.state = "queue"
		p.queue = d.key
		p.face = nil
		return
	end
	if d.kind == "park" then
		p.state = "linger"
		local span = LINGER[d.def] or { 3, 8 }
		p.timer = rand(span[1], span[2])
		if node and node.kind == "t" then
			local seat = SEATS[d.def]
			p.sit = seat ~= nil
			local fx, fz
			if seat == "out" or seat == "back" then
				local s = walk.SIDES[seatFacing(seat, node.turn) + 1]
				fx, fz = s[1], s[2]
			else
				fx, fz = node.center[1] - p.pos[1], node.center[2] - p.pos[2]
			end
			p.face = math.atan2(fx, fz)
		elseif node and node.kind == "b" then
			p.face = math.atan2(node.center[1] - p.pos[1], node.center[2] - p.pos[2])
		end
		return
	end
	p.state = "inside"
	if d.kind == "home" then
		p.outings = 0
		p.timer = if night then rand(40, 90) else rand(12, 35)
	elseif d.kind == "door" then
		p.timer = rand(35, 80) -- dancing the night away
	else
		p.timer = if d.kind == "shop" then rand(5, 12) else rand(6, 14)
	end
end

local function updatePerson(g: any, places: Places, p: Person, dt: number, night: boolean)
	if p.state == "queue" then
		inLine(p, dt)
		return
	end
	if p.state == "inside" or p.state == "linger" then
		if p.face ~= nil then
			turnTo(p, p.face, dt)
		end
		if p.state == "linger" then
			walkDog(p, dt)
		end
		p.timer -= dt
		if p.timer <= 0 then
			setOff(g, places, p, night)
		end
		return
	end
	local step = p.steps[p.si]
	if not step then
		arrive(g, p, night)
		return
	end
	local cross = step.cross
	if cross and p.crossing ~= cross.id then
		-- At lights, wait for the walk signal; elsewhere look both ways and wait while a car is close.
		local signal = crossingSignal(cross.tile, cross.dir)
		local hold = if signal == "wait" then p.waited < 30 else carNear(cross.mid, if signal == "walk" then 1.1 else 1.7) and p.waited < 8
		if hold then
			p.waited += dt
			turnTo(p, math.atan2(step.p[1] - p.pos[1], step.p[2] - p.pos[2]), dt)
			walkDog(p, dt)
			return
		end
		p.crossing = cross.id
		local c = walk.pedestrianCrossings
		c:set(cross.id, (c:get(cross.id) or 0) + 1)
	end
	p.waited = 0
	local dx, dz = step.p[1] - p.pos[1], step.p[2] - p.pos[2]
	local len = math.sqrt(dx * dx + dz * dz)
	-- The web's speeds suit its figures, which are 1/FIT times the size of ours: scaled the same, a
	-- walk is an easy stroll for a 5.3-stud person (about 4.5 studs a second) and a jog a jog.
	local move = p.speed * FIT * dt
	if len <= move then
		p.pos[1], p.pos[2] = step.p[1], step.p[2]
		if cross then
			leaveCrossing(p)
		end
		p.si += 1
	else
		p.pos[1] += dx / len * move
		p.pos[2] += dz / len * move
		turnTo(p, math.atan2(dx, dz), dt)
	end
	-- Legs keep pace with the ground (about one stride a step's length), so feet don't skate.
	p.stride += move * S / K * (if p.type == "jogger" then 10 else 14)
	walkDog(p, dt)
end

-- A figure (peopleGeo.ts at Townspeople's scale, with more to see up close): legs that bend at the
-- knee, shoes, a rounded torso in the person's top (tee, striped, polo, jacket or hoodie) over
-- trousers or shorts, arms that swing with sleeves and hands, and a head with eyes, brows, nose,
-- smile and ears under one of several hairdos or hats; a walked dog and its leash.
--
-- Each part rides a bone (hips, torso, head, a thigh, a shin or an arm) at a fixed offset, so
-- draw() works out nine bones and places every part from them. Parts marked `near` (the face's
-- small features, collars and trims) only follow people close to the camera; far off they're
-- parked out of sight, which keeps a phone's busy town to about 20 moving parts a person.
local function ellipsoid(parent: Instance, size: Vector3, color: string): Part
	local p = part(parent, Enum.PartType.Block, size, CFrame.new(), color)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- A hex colour `k` of the way to black (k < 0: to white).
local function shade(hex: string, k: number): string
	local out = "#"
	for i = 0, 2 do
		local v = tonumber(string.sub(hex, 2 + i * 2, 3 + i * 2), 16) :: number
		v = if k >= 0 then v * (1 - k) else v + (255 - v) * -k
		out ..= string.format("%02x", math.floor(v + 0.5))
	end
	return out
end

local HIPS, TORSO, HEAD, THIGH_L, THIGH_R, SHIN_L, SHIN_R, ARM_L, ARM_R = 1, 2, 3, 4, 5, 6, 7, 8, 9
local THIGH, SHIN = 0.115, 0.1 -- leg lengths, hip to knee to ankle (LEG less the shoe)
local SHOULDER = Vector3.new(0.105, 0.255, 0) -- from the hips, on the torso
-- Where a seated person's hips go: the web seats its figures at 0.26 of its (1/FIT bigger) scale,
-- which is where the bench's seat is.
local SIT_HIP = 0.26 / FIT

local function figure(p: Person, parent: Instance, scale: number?): Figure
	local K = K * (scale or p.size or 1) -- studs per figure unit, for this figure (a bouncer's bigger)
	local m = Instance.new("Model")
	m.Name = p.id
	local c, look = p.colors, p.look
	local bits: { Bit } = {}
	local function add(x: BasePart, bone: number, off: CFrame, near: boolean?)
		x.CastShadow = false
		table.insert(bits, { part = x, bone = bone, off = off, near = near == true })
	end
	local function ball(bone: number, d: number, at: Vector3, color: string, near: boolean?)
		add(part(m, Enum.PartType.Ball, Vector3.one * d * K, CFrame.new(), color), bone, CFrame.new(at * K), near)
	end
	local function egg(bone: number, size: Vector3, off: CFrame, color: string, near: boolean?)
		add(ellipsoid(m, size * K, color), bone, off, near)
	end
	local function ring(bone: number, d: number, h: number, y: number, color: string, near: boolean?)
		add(part(m, Enum.PartType.Cylinder, Vector3.new(h, d, d) * K, CFrame.new(), color), bone, CFrame.new(0, y * K, 0) * UP, near)
	end
	local function at(x: number, y: number, z: number): CFrame
		return CFrame.new(x * K, y * K, z * K)
	end
	local top = look.top
	local covered = top == "jacket" or top == "hoodie"
	local body = if covered then look.coat else c.shirt
	-- Legs: trouser thighs, shins in trousers or bare under shorts, and shoes, toe forward.
	for _, bone in { THIGH_L, THIGH_R } do
		egg(bone, Vector3.new(0.072, THIGH + 0.05, 0.078), at(0, -THIGH / 2, 0), c.pants)
	end
	for _, bone in { SHIN_L, SHIN_R } do
		egg(bone, Vector3.new(0.06, SHIN + 0.04, 0.066), at(0, -SHIN / 2, 0), if look.shorts then c.skin else c.pants)
	end
	for _, bone in { SHIN_L, SHIN_R } do
		egg(bone, Vector3.new(0.072, 0.05, 0.12), at(0, -SHIN - 0.008, 0.02), look.shoes)
	end
	-- Torso: a capsule (seat in the trousers, middle and shoulders in the top) and a belt.
	ball(TORSO, 0.17, Vector3.new(0, 0.07, 0), c.pants)
	ring(TORSO, 0.17, 0.16, 0.15, body)
	ball(TORSO, 0.17, Vector3.new(0, 0.23, 0), body)
	ring(TORSO, 0.176, 0.024, 0.07, "#3a3a3a")
	-- Arms: a sleeve (short over a bare forearm, or long), and the hand.
	for _, bone in { ARM_L, ARM_R } do
		if covered then
			egg(bone, Vector3.new(0.062, 0.2, 0.062), at(0, -0.09, 0), body)
		else
			egg(bone, Vector3.new(0.066, 0.11, 0.066), at(0, -0.045, 0), body)
			egg(bone, Vector3.new(0.046, 0.13, 0.046), at(0, -0.125, 0), c.skin)
		end
		ball(bone, 0.054, Vector3.new(0, -0.205, 0.004), c.skin)
	end
	-- What sets each top apart, close up.
	if top == "stripe" then
		ring(TORSO, 0.174, 0.034, 0.19, look.trim, true)
		ring(TORSO, 0.174, 0.034, 0.12, look.trim, true)
	elseif top == "polo" then
		ring(TORSO, 0.1, 0.03, 0.305, shade(c.shirt, 0.15), true)
		egg(TORSO, Vector3.new(0.03, 0.06, 0.012), at(0, 0.27, 0.078) * CFrame.Angles(-0.5, 0, 0), shade(c.shirt, 0.25), true)
	elseif top == "jacket" then
		-- Open down the front over the shirt, with a zip each side.
		add(part(m, nil, Vector3.new(0.05, 0.15, 0.012) * K, CFrame.new(), c.shirt), TORSO, at(0, 0.19, 0.081), true)
		ring(TORSO, 0.105, 0.035, 0.31, shade(look.coat, 0.2), true)
	elseif top == "hoodie" then
		egg(TORSO, Vector3.new(0.15, 0.09, 0.09), at(0, 0.3, -0.06), shade(look.coat, 0.12), true)
		add(part(m, nil, Vector3.new(0.1, 0.05, 0.012) * K, CFrame.new(), shade(look.coat, 0.12)), TORSO, at(0, 0.11, 0.083), true)
	else
		ring(TORSO, 0.1, 0.025, 0.305, shade(c.shirt, 0.12), true)
	end
	-- Head and face: eyes (always: they read from afar), then brows, nose, smile, ears and neck.
	ball(HEAD, 0.16, Vector3.zero, c.skin)
	for _, s in { -1, 1 } do
		egg(HEAD, Vector3.new(0.022, 0.03, 0.016), at(s * 0.029, 0.012, 0.072), "#1a1a1a")
	end
	local brow = if look.hair == "beanie" then "#3e2723" else c.hair
	for _, s in { -1, 1 } do
		add(part(m, nil, Vector3.new(0.034, 0.009, 0.012) * K, CFrame.new(), brow), HEAD, at(s * 0.03, 0.036, 0.071) * CFrame.Angles(-0.45, 0, s * -0.12), true)
	end
	ball(HEAD, 0.028, Vector3.new(0, -0.006, 0.08), shade(c.skin, 0.06), true)
	add(part(m, nil, Vector3.new(0.034, 0.008, 0.01) * K, CFrame.new(), "#8a4a4a"), HEAD, at(0, -0.033, 0.072) * CFrame.Angles(0.45, 0, 0), true)
	for _, s in { -1, 1 } do
		egg(HEAD, Vector3.new(0.022, 0.042, 0.032), at(s * 0.079, 0, -0.004), c.skin, true)
	end
	ring(TORSO, 0.066, 0.06, 0.29, c.skin, true)
	-- Hair, or a hat over it.
	local hd = look.hair
	if hd == "cap" then
		egg(HEAD, Vector3.new(0.172, 0.1, 0.172), at(0, 0.052, -0.016), look.hat)
		add(part(m, nil, Vector3.new(0.12, 0.012, 0.075) * K, CFrame.new(), shade(look.hat, 0.15)), HEAD, at(0, 0.05, 0.088) * CFrame.Angles(-0.12, 0, 0))
		egg(HEAD, Vector3.new(0.15, 0.08, 0.12), at(0, -0.01, -0.03), c.hair, true)
	elseif hd == "beanie" then
		egg(HEAD, Vector3.new(0.18, 0.12, 0.18), at(0, 0.062, -0.012), c.hair)
		ball(HEAD, 0.05, Vector3.new(0, 0.125, -0.012), "#fafafa")
		ring(TORSO, 0.11, 0.04, 0.3, shade(c.hair, -0.25), true) -- a scarf
	elseif hd == "curly" then
		ball(HEAD, 0.2, Vector3.new(0, 0.058, -0.034), c.hair)
	elseif hd == "buzz" then
		egg(HEAD, Vector3.new(0.166, 0.1, 0.166), at(0, 0.045, -0.012), c.hair)
	else
		egg(HEAD, Vector3.new(0.174, 0.1, 0.172), at(0, 0.05, -0.02), c.hair)
		if hd == "long" then
			egg(HEAD, Vector3.new(0.17, 0.2, 0.09), at(0, -0.045, -0.048), c.hair)
		elseif hd == "ponytail" then
			egg(HEAD, Vector3.new(0.052, 0.13, 0.052), at(0, -0.02, -0.1) * CFrame.Angles(-0.35, 0, 0), c.hair)
		elseif hd == "bun" then
			ball(HEAD, 0.075, Vector3.new(0, 0.095, -0.04), c.hair)
		end
	end
	if p.type == "jogger" then
		ring(HEAD, 0.168, 0.022, 0.042, look.hat, true) -- a sweatband
	end
	-- The dog (Dog Park proportions, at its own size) and the leash.
	local dog: { BasePart } = {}
	local leash = part(m, nil, Vector3.new(0.009, 0.009, 1) * S, CFrame.new(), LEASHES[(#p.name * 3 + #p.dogName) % #LEASHES + 1])
	if p.type == "dog" then
		local k = p.dogSize * S * FIT
		table.insert(dog, ellipsoid(m, Vector3.new(0.112, 0.104, 0.208) * k, c.dog))
		table.insert(dog, part(m, Enum.PartType.Ball, Vector3.one * 0.11 * k, CFrame.new(), c.dog))
		table.insert(dog, part(m, nil, Vector3.new(0.04, 0.035, 0.05) * k, CFrame.new(), c.dog))
		table.insert(dog, part(m, nil, Vector3.new(0.022, 0.02, 0.01) * k, CFrame.new(), "#151515"))
		for _ = 1, 4 do
			table.insert(dog, part(m, nil, Vector3.new(0.028, 0.1, 0.028) * k, CFrame.new(), c.dog))
		end
		for _ = 1, 2 do
			table.insert(dog, part(m, nil, Vector3.new(0.025, 0.05, 0.02) * k, CFrame.new(), "#9a9a9a"))
		end
		table.insert(dog, part(m, nil, Vector3.new(0.014, 0.085, 0.014) * k, CFrame.new(), c.dog))
		table.insert(dog, part(m, Enum.PartType.Cylinder, Vector3.new(0.016, 0.09, 0.09) * k, CFrame.new(), "#c62828"))
	else
		leash.Transparency = 1
	end
	m.Parent = parent
	return { model = m, bits = bits, dog = dog, leash = leash, shown = true, near = true, k = K }
end

local HIDDEN = CFrame.new(0, -10000, 0)
-- How close (studs) the camera must be for a figure's small features to follow it.
local NEAR = 90

-- Places a figure's parts as `p` (a Pose) has it standing at `base` (its feet, facing +z), into the
-- lists BulkMoveTo takes, and returns its bones. Small parts only follow it within NEAR studs of
-- `eye` (the camera), if given. Also used for the club's dancers and bouncer (client/ClubLife).
local function pose(fig: Figure, base: CFrame, p: Pose, eye: Vector3?, list: { BasePart }, cfs: { CFrame }): { CFrame }
	local K = fig.k
	local near = eye == nil or (eye - base.Position).Magnitude < NEAR
	local hips = base * CFrame.new(0, p.hip * K, 0)
	local torso = hips * CFrame.Angles(p.lean, p.twist, 0)
	local head = torso * CFrame.new(0, 0.36 * K, 0) * CFrame.Angles(p.nod, p.look, 0)
	local bones = { hips, torso, head }
	for i, s in { -1, 1 } do
		local thigh = hips * CFrame.new(s * 0.045 * K, 0, 0) * CFrame.Angles(p.legs[i][1], 0, 0)
		bones[3 + i] = thigh
		bones[5 + i] = thigh * CFrame.new(0, -THIGH * K, 0) * CFrame.Angles(p.legs[i][2], 0, 0)
		bones[7 + i] = torso * CFrame.new(s * SHOULDER.X * K, SHOULDER.Y * K, 0) * p.arms[i]
	end
	if near then
		for _, b in fig.bits do
			table.insert(list, b.part)
			table.insert(cfs, bones[b.bone] * b.off)
		end
	else
		for _, b in fig.bits do
			if not b.near then
				table.insert(list, b.part)
				table.insert(cfs, bones[b.bone] * b.off)
			elseif fig.near then
				table.insert(list, b.part)
				table.insert(cfs, HIDDEN)
			end
		end
	end
	fig.near = near
	fig.shown = true
	return bones
end

-- Hides a figure (and its dog), once.
local function hide(fig: Figure, list: { BasePart }, cfs: { CFrame })
	if not fig.shown then
		return
	end
	fig.shown = false
	fig.near = false
	for _, b in fig.bits do
		table.insert(list, b.part)
		table.insert(cfs, HIDDEN)
	end
	for _, x in fig.dog do
		table.insert(list, x)
		table.insert(cfs, HIDDEN)
	end
	table.insert(list, fig.leash)
	table.insert(cfs, HIDDEN)
end

-- Places a person's figure (Townspeople.tsx draw()) into the lists BulkMoveTo takes. `eye` is the
-- camera's position, if there is one.
local function draw(origin: Vector3, p: Person, wag: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	local fig = p.fig :: Figure
	if p.state == "inside" then
		hide(fig, list, cfs)
		return
	end
	local moving = (p.state == "walk" and p.waited == 0) or (p.state == "queue" and p.face == nil)
	local jog = p.type == "jogger"
	local swing = if moving then math.sin(p.stride) * (if jog then 0.85 else 0.55) else 0
	local bob = if moving then math.abs(math.cos(p.stride)) * (if jog then 0.05 else 0.025) else 0
	local hip = (if p.sit then SIT_HIP else LEG) + bob
	local base = CFrame.new(origin + Vector3.new(p.pos[1], 0, p.pos[2]) * S) * CFrame.Angles(0, p.heading, 0)
	-- The torso leans into a jog and turns a little against the legs; legs swing from the hips and
	-- bend at the knee as they come through (sitting, thighs forward and shins down); arms swing
	-- against the legs (a dog walker's right one holds the leash out).
	local lean = if moving then (if jog then 0.16 else 0.05) else 0
	local legs, arms = {}, {}
	for i, s in { -1, 1 } do
		if p.sit then
			legs[i] = { -math.pi / 2, math.pi / 2 }
		else
			legs[i] = { swing * s, if moving then math.max(0, math.cos(p.stride) * s) * (if jog then 1.1 else 0.55) else 0 }
		end
		local a = if p.sit then -0.45 else -swing * s * (if jog then 1.1 else 0.8)
		if p.type == "dog" and s == 1 and not p.sit then
			a = -0.4 + a * 0.3
		end
		arms[i] = CFrame.Angles(a, 0, 0) * CFrame.Angles(0, 0, s * 0.1)
	end
	local idle = if p.state == "linger" and not p.sit then math.sin(wag * 0.6 + #p.id) * 0.45 else 0
	local bones = pose(fig, base, {
		hip = hip,
		lean = lean,
		twist = swing * 0.12,
		nod = -lean * 0.6,
		look = idle - swing * 0.1,
		legs = legs,
		arms = arms,
	}, eye, list, cfs)
	if p.type == "dog" then
		local k = p.dogSize * FIT
		local still = p.state == "linger"
		local trot = if moving then math.abs(math.sin(p.stride * 1.6)) * 0.025 * k else 0
		local pitch = if still then -0.32 elseif moving then math.sin(p.stride * 3.2) * 0.07 else 0
		local d = CFrame.new(origin + Vector3.new(p.dogPos[1], trot, p.dogPos[2]) * S) * CFrame.Angles(0, p.dogHeading, 0) * CFrame.Angles(pitch, 0, 0)
		local function dat(x: number, y: number, z: number): CFrame
			return d * CFrame.new(x * k * S, y * k * S, z * k * S)
		end
		local gait = if moving then math.sin(p.stride * 1.6) * 0.55 else 0
		local tail = math.sin(wag * (if moving then 9 else 14)) * (if still then 0.5 else 0.35)
		local dcf = {
			dat(0, 0.13, 0),
			dat(0, 0.2, 0.11),
			dat(0, 0.185, 0.17),
			dat(0, 0.195, 0.197),
		}
		for _, xz in { { -1, 1 }, { 1, 1 }, { -1, -1 }, { 1, -1 } } do
			local pair = if xz[1] * xz[2] > 0 then 1 else -1
			table.insert(dcf, dat(xz[1] * 0.035, 0.1, xz[2] * 0.06) * CFrame.Angles(gait * pair, 0, 0) * CFrame.new(0, -0.05 * k * S, 0))
		end
		for _, s in { -1, 1 } do
			table.insert(dcf, dat(s * 0.04, 0.24, 0.1) * CFrame.Angles(0, 0, s * 0.24))
		end
		table.insert(dcf, dat(0, 0.195, -0.105) * CFrame.Angles(0, tail, 0) * CFrame.Angles(-0.7, 0, 0))
		table.insert(dcf, dat(0, 0.17, 0.075) * CFrame.Angles(-0.9, 0, 0) * UP)
		for j, x in fig.dog do
			table.insert(list, x)
			table.insert(cfs, dcf[j])
		end
		-- The leash, from the right hand to the collar.
		local hand = (bones[ARM_R] * CFrame.new(0, -0.205 * K, 0.004 * K)).Position
		local collar = dat(0, 0.17 + (if still then 0.03 else 0), 0.075).Position
		local span = (collar - hand).Magnitude
		fig.leash.Size = Vector3.new(0.009 * S, 0.009 * S, math.max(0.01, span))
		table.insert(list, fig.leash)
		table.insert(cfs, CFrame.lookAt((hand + collar) / 2, collar))
	end
end
---------------------------------------------------------------------------------------------------

-- Set by attach: the latest save, re-running the traffic's cars, and a car's model by uid.
local lastSave: any = nil
local refresh: () -> () = function() end
local modelOf: (string) -> Model? = function()
	return nil
end

---------------------------------------------------------------------------------------------------
-- Thought bubbles (Townspeople.tsx thought() and where()): tap someone to see what they're up to.

-- The chip for where someone is headed ("☕ Coffee"), and whether they're there yet.
local function whereOf(p: Person): (string, boolean)
	local d = p.dest
	local there = p.state == "linger" or p.state == "queue"
	if not d or d.kind == "jog" then
		return if p.type == "jogger" then "🏃 Around the block" else "🚶 Around town", false
	end
	if d.kind == "home" then
		return "🏠 Home", there
	end
	if d.kind == "friend" then
		return "🏡 A neighbour's", there
	end
	local icon = Thought.SHOP[d.def] or Thought.PARK_GO[d.def]
	return Thought.placeChip(d.def, if icon then icon[1] else nil), there
end

-- One line for the bubble: who it is and what they're up to.
local function thoughtOf(p: Person): string
	local who = if p.type == "dog" then `{p.name} and {p.dogName} are` else `{p.name} is`
	local d = p.dest
	local idea = { "🚶", "out for a walk" }
	if p.type == "jogger" and (not d or d.kind ~= "home") then
		idea = { "🏃", "out for a run" }
	elseif d and d.kind == "home" then
		idea = { "🏠", "heading home" }
	elseif d and d.kind == "shop" then
		idea = Thought.SHOP[d.def] or { "🛍️", "running an errand" }
	elseif d and d.kind == "browse" then
		idea = if d.def == "garage" then { "🔧", "peeking into your garage" } else { "🚗", "looking at cars in the showroom" }
	elseif d and d.kind == "friend" then
		idea = { "👋", "visiting a neighbour" }
	elseif d and d.kind == "club" then
		idea = if p.state == "queue" then { "🎟️", "waiting in line for the club" } else { "🪩", "heading out dancing" }
	elseif d and d.kind == "door" then
		idea = { "🕺", "getting into the club" }
	elseif d and d.kind == "park" then
		idea = (if p.state == "linger" then Thought.PARK_AT else Thought.PARK_GO)[d.def] or { "🌳", "enjoying the park" }
	end
	return `{idea[1]} {who} {idea[2]}`
end

local function headOf(p: Person): BasePart?
	for _, b in if p.fig then p.fig.bits else {} do
		if b.bone == HEAD then
			return b.part
		end
	end
	return nil
end

-- Keeps the bubble over the person it belongs to, up to date, until it runs out or they go in.
followThought = function(list: { Person })
	local id = Thought.current()
	if not id then
		return
	end
	for _, p in list do
		if p.id == id then
			local head = headOf(p)
			if p.state == "inside" or not head then
				break
			end
			local where, there = whereOf(p)
			Thought.show(p.id, head, where, there, thoughtOf(p))
			return
		end
	end
	Thought.hide()
end

-- A tap (or click) on the town, `at` on screen: the townsperson nearest it, if one's close enough.
local function tapped(list: { Person }, at: Vector2): Person?
	local cam = workspace.CurrentCamera
	if not cam or not townOrigin then
		return nil
	end
	local best, bestD = nil, math.huge
	for _, p in list do
		if p.state == "inside" or not p.fig then
			continue
		end
		local world = (townOrigin :: Vector3) + Vector3.new(p.pos[1] * S, 2.7, p.pos[2] * S)
		local v, onScreen = cam:WorldToViewportPoint(world)
		if not onScreen then
			continue
		end
		-- A roomier target than the figure (Townspeople.tsx's invisible hit box), so they're easy
		-- to tap on a phone: about the figure's height on screen, and never under 28 pixels.
		local top = cam:WorldToViewportPoint(world + Vector3.new(0, 2.65, 0))
		local reach = math.max(28, math.abs(v.Y - top.Y) * 1.3)
		local d = (Vector2.new(v.X, v.Y) - at).Magnitude
		if d < reach and d < bestD then
			best, bestD = p, d
		end
	end
	return best
end

local function smallScreen(): boolean
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 700
end

-- Brings a drawn town to life: returns a function that brings it up to date with a save, and one
-- that moves everything on by dt seconds (each frame).
function TownLife.attach(town: Folder): ((save: any) -> (), (rawDt: number) -> ())
	local origin: Vector3 = town:GetAttribute("Origin") :: any
	townOrigin = origin
	local carsFolder = town:WaitForChild("Cars")

	-- The player's cars' pieces, for showing the small ones only up close (client/CarDetail).
	-- By uid (a new model under the same uid, after the server draws it again, is tracked afresh).
	local serverDetails: { [string]: CarDetail.Detail } = {}
	local peopleFolder = Instance.new("Folder")
	peopleFolder.Name = "Townspeople"
	peopleFolder.Parent = workspace
	local maxPeople = if smallScreen() then 20 else 44
	local people: { Person } = {}
	local graph: any = nil
	local places: Places? = nil
	local graphKey = ""
	local peopleKey = ""

	local function updatePeople(save: any)
		local roads = save.roads or {}
		local buildings = save.buildings or {}
		local foot = {}
		for _, b in buildings do
			table.insert(foot, `{b.uid}:{b.def}:{b.x}:{b.z}:{b.rot or 0}`)
		end
		local land = save.land or data.START_LAND
		local gk = table.concat(roads, ";") .. "|" .. table.concat(foot, "|") .. "|" .. table.concat(land, ";")
		if gk ~= graphKey then
			graphKey = gk
			graph = walk.buildWalkGraph(lualib.__TS__New(lualib.Set, roads), buildings, land)
			places = destinations(graph)
			clubsNow = (places :: Places).clubs
			table.clear(queues)
			-- Anyone walking re-plans from where they stand; the simple way: home, indoors.
			for _, p in people do
				p.queue = nil
				if p.state == "walk" or p.state == "linger" or p.state == "queue" then
					leaveCrossing(p)
					p.state = "inside"
					p.at = `b{p.home}`
					p.timer = rand(1, 6)
				end
			end
		end
		-- Two per house (more in upgraded ones), plus a few as the town levels up.
		local homes, sizes = {}, {}
		local fallback = nil
		for _, n in graph.nodes do
			if n.kind == "b" then
				fallback = fallback or n
				if data.buildingDef(n.def).kind == "house" then
					table.insert(homes, n)
				end
			end
		end
		for _, b in buildings do
			if data.buildingDef(b.def).kind == "house" then
				sizes[b.uid] = data.houseResidents(data.buildingLevel(b))
			end
		end
		local wanted = {}
		if #homes > 0 then
			local function size(h: any): number
				return sizes[h.uid] or data.houseResidents(1)
			end
			local most = 0
			for _, h in homes do
				most = math.max(most, size(h))
			end
			for i = 0, most - 1 do
				for _, h in homes do
					if i < size(h) then
						table.insert(wanted, { id = `{h.uid}:{i}`, home = h })
					end
				end
			end
			local count = {}
			for _, h in homes do
				count[h.uid] = size(h)
			end
			for i = 0, math.min(10, math.floor((save.level or 1) / 2)) - 1 do
				local h = homes[i % #homes + 1]
				local n = count[h.uid]
				count[h.uid] = n + 1
				table.insert(wanted, { id = `{h.uid}:{n}`, home = h })
			end
		elseif fallback then
			for i = 0, 3 do
				table.insert(wanted, { id = `{fallback.uid}:{i}`, home = fallback })
			end
		end
		local ids = {}
		for i = 1, math.min(#wanted, maxPeople) do
			table.insert(ids, wanted[i].id)
		end
		local pk = table.concat(ids, ",")
		if pk == peopleKey then
			return
		end
		peopleKey = pk
		local old: { [string]: Person } = {}
		for _, p in people do
			old[p.id] = p
		end
		local next: { Person } = {}
		for i = 1, math.min(#wanted, maxPeople) do
			local w = wanted[i]
			local had: Person? = old[w.id]
			local p: Person
			if had then
				p = had
				old[w.id] = nil
			else
				p = person(w.id, w.home.uid, w.home.center)
				p.fig = figure(p, peopleFolder)
			end
			table.insert(next, p)
		end
		for _, p in old do
			leaveCrossing(p)
			if p.fig then
				p.fig.model:Destroy()
			end
		end
		people = next
	end

	local function update(save: any)
		if not save then
			return
		end
		lastSave = save
		updateTraffic(save)
		drawSignals(origin, save.roads or {})
		updatePeople(save)
	end
	refresh = function()
		if lastSave then
			updateTraffic(lastSave)
		end
	end
	modelOf = function(uid: string): Model?
		return carsFolder:FindFirstChild(uid) :: Model?
	end
	local parked: { [string]: boolean } = {}
	-- If the player's character ever ends up under their town's ground (fallen through before it
	-- streamed in), it's stood back on top.
	local nextCheck = 0
	local function rescueFall()
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not (character and root and humanoid) or root.Anchored then
			return
		end
		local p = root.Position
		local flat = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
		if p.Y > origin.Y - 2.5 or flat.Magnitude > 1900 then
			return
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(Vector3.new(p.X, origin.Y + 3, p.Z), Vector3.new(0, -6, 0), params)
		local top = if hit then hit.Position.Y else origin.Y
		character:PivotTo(CFrame.new(p.X, top + humanoid.HipHeight + root.Size.Y / 2 + 0.1, p.Z) * root.CFrame.Rotation)
		root.AssemblyLinearVelocity = Vector3.zero
	end

	local function step(rawDt: number)
		local dt = math.min(rawDt, 0.1)
		nextCheck -= rawDt
		if nextCheck <= 0 then
			nextCheck = 1
			rescueFall()
		end
		traffic:step(dt)
		stepSignals()
		-- The cars: each server model goes where the sim has it, at its town size.
		-- A car the player has taken stays wherever they left it.
		local cam0 = workspace.CurrentCamera
		local eyeAt = if cam0 then cam0.CFrame.Position else nil
		for _, m in carsFolder:GetChildren() do
			if not m:IsA("Model") or taken[m.Name] then
				continue
			end
			local a = traffic.agents:get(m.Name)
			if not a then
				-- Checked every frame: the server parks its models again whenever the town changes,
				-- which would leave them sitting (and floating) on their lots.
				if not parked[m.Name] or m:GetAttribute("TownLife") == nil or m:GetPivot().Position.Y > HIDDEN.Position.Y + 1 then
					parked[m.Name] = true
					m:SetAttribute("TownLife", true)
					m:PivotTo(HIDDEN)
				end
				continue
			end
			parked[m.Name] = nil
			m:SetAttribute("TownLife", true)
			local k = (scaleOf[m.Name] or 0.8) * math.max(0.01, a.show)
			if math.abs(m:GetScale() - k) > 0.001 then
				m:ScaleTo(k)
			end
			local tilt = if a.stalled and a.tow == 0 then 0.06 else 0
			local at = origin + Vector3.new(a.x * S, 0.02 * S, a.z * S)
			m:PivotTo(CFrame.new(at) * CFrame.Angles(0, a.yaw, 0) * CFrame.Angles(0, 0, tilt))
			-- The player's own cars, from the server: tracked here, for their wheels.
			local d = serverDetails[m.Name]
			if not d or d.model ~= m then
				d = CarDetail.track(m)
				serverDetails[m.Name] = d
			end
			if d and eyeAt then
				CarDetail.lod(d, (at - eyeAt).Magnitude)
				CarDetail.wheels(d, m:GetPivot(), dt)
			end
		end
		-- The townspeople.
		if graph and places then
			local night = clock.nightAmount(clock.dayPhase(ClockShift.now())) > 0.5
			local wag = os.clock()
			local cam = workspace.CurrentCamera
			local eye = if cam then cam.CFrame.Position else nil
			local parts: { BasePart } = {}
			local cfs: { CFrame } = {}
			bouncers(dt)
			for _, p in people do
				updatePerson(graph, places, p, dt, night)
				if p.fig and p.fig.model.Parent then
					draw(origin, p, wag, eye, parts, cfs)
				end
			end
			followThought(people)
			if #parts > 0 then
				workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
	-- Tap someone to see what they're up to; a tap anywhere else (not a drag to pan) closes it.
	local down: { [InputObject]: Vector2 } = {}
	local function isTap(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if isTap(input) and not processed then
			down[input] = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local from = down[input]
		down[input] = nil
		if not from then
			return
		end
		local at = Vector2.new(input.Position.X, input.Position.Y)
		if (at - from).Magnitude > 6 then
			return
		end
		local p = tapped(people, at)
		local head = p and headOf(p)
		if p and head then
			local where, there = whereOf(p)
			Thought.show(p.id, head, where, there, thoughtOf(p), true)
		else
			Thought.hide()
		end
	end)
	return update, step
end

-- Puts a visitor's cars on the town's roads, or takes them off (empty): leaving visitors fade out
-- where they are. Each spec: { uid, len, wid, cruise, stalled }.
function TownLife.setGuests(list: { any })
	guests = list
	refresh()
end

-- For a town nobody has brought to life (attach): keeps the traffic up to date with `save` and
-- moves it on by dt, for the visitor's cars alone.
function TownLife.drive(save: any, dt: number)
	lastSave = save
	updateTraffic(save)
	traffic:step(dt)
end

TownLife.running = false

function TownLife.start()
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
		local update, step = TownLife.attach(folder :: Folder)
		Remote.changed:Connect(function(snap)
			update(snap.save)
		end)
		if Remote.last then
			update(Remote.last.save)
		end
		TownLife.running = true
		RunService.RenderStepped:Connect(step)
	end)
end

-- Every car on the town's roads right now (the player's), for getting in:
-- uid -> model.
function TownLife.cars(): { [string]: Model }
	local out = {}
	traffic.agents:forEach(function(_, a: any, uid: string)
		local m = modelOf(uid)
		if m and a.show > 0.9 and not taken[uid] then
			out[uid] = m
		end
	end)
	return out
end

-- Takes a car off the road (the player is getting in): the sim lets go of it and its model
-- stays put for whoever moves it. Returns the model.
function TownLife.take(uid: string): Model?
	local m = modelOf(uid)
	if not m then
		return nil
	end
	taken[uid] = true
	local a = traffic.agents:get(uid)
	if a then
		traffic:remove(a)
	end
	refresh()
	return m
end

-- A car's model (the player's, from the server) by uid.
function TownLife.modelOf(uid: string): Model?
	return modelOf(uid)
end

-- Gives a taken car back to the town's traffic (it fades in somewhere on the roads).
function TownLife.give(uid: string)
	if not taken[uid] then
		return
	end
	taken[uid] = nil
	local m = modelOf(uid)
	if m then
		m:PivotTo(HIDDEN)
	end
	refresh()
end

-- The middle of the nearest road tile to world point p, on the ground, when p is on this town's
-- land (nil outside it, or before the traffic has roads).
function TownLife.roadNear(p: Vector3): Vector3?
	local o = townOrigin
	if not o or math.abs(p.X - o.X) > TOWN_REACH or math.abs(p.Z - o.Z) > TOWN_REACH then
		return nil
	end
	local best: Vector3?, bestD = nil, math.huge
	local net = traffic.net
	if not net or not net.layout then
		return nil
	end
	net.layout.tiles:forEach(function(_, t: any)
		local w = grid.toWorld(t.x, t.z)
		local at = o + Vector3.new(w[1], 0, w[2]) * S
		local d = (Vector3.new(at.X - p.X, 0, at.Z - p.Z)).Magnitude
		if d < bestD then
			best, bestD = at, d
		end
	end)
	return best
end

TownLife._traffic = traffic
TownLife._crossingSignal = crossingSignal
TownLife._person = person
TownLife._figure = figure
TownLife._draw = draw
TownLife._updatePerson = updatePerson
TownLife._thoughtOf = thoughtOf
TownLife._whereOf = whereOf
TownLife._tapped = tapped
TownLife._queues = queues

-- The townspeople's figures, for other crowds drawn the same way (client/ClubLife): a new
-- person's look (from an id), a figure for it (`scale` for a bigger one), posing it and hiding it.
TownLife.person = person
TownLife.figure = figure
TownLife.pose = pose
TownLife.hideFigure = hide
TownLife.LEG = LEG
TownLife.THIGH = THIGH
TownLife.SHIN = SHIN
-- Studs per model unit of a grown-up's figure (LotPeople steps their legs to match the ground).
TownLife._K = K

return TownLife
