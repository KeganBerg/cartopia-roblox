--!strict
-- The town's life, as the web game's TownCars.tsx and Townspeople.tsx draw it: the player's cars
-- driving round their roads (the web's traffic sim, converted: Shared.Game.scene_traffic_sim), the
-- traffic lights and stop signs at junctions, and townspeople who live in the houses and walk the
-- sidewalks (walkGraph) to the shops, parks and showroom and back, crossing at the zebras.
--
-- It all runs here on the client, for this player's town only, like the countryside: it never
-- changes the game. The cars are the server's own car models (TownView), moved and resized here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local lualib = require(Game:WaitForChild("lualib_bundle")) :: any
local data = require(Game:WaitForChild("data")) :: any
local placement = require(Game:WaitForChild("placement")) :: any
local clock = require(Game:WaitForChild("clock")) :: any
local trafficLevel = require(Game:WaitForChild("traffic")) :: any
local sim = require(Game:WaitForChild("scene_traffic_sim")) :: any
local layout = require(Game:WaitForChild("scene_traffic_layout")) :: any
local grid = require(Game:WaitForChild("scene_grid")) :: any
local walk = require(Game:WaitForChild("walkGraph")) :: any

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
traffic.walkers = walk.pedestrianCrossings

-- The cars it drives, by uid: the scale each is drawn at (townCarSize.ts).
local scaleOf: { [string]: number } = {}

local townKey = ""
local carsKey = ""
local homesKey = ""

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
	for _, c in cars do
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
	local max = math.min(MAX_VISIBLE, math.max(3, math.floor(#roads * 0.5)))
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
local K = PERSON.scale * S -- studs per model unit of a figure
local SHIRTS = { "#e53935", "#1e88e5", "#fdd835", "#43a047", "#8e24aa", "#ff7043", "#fafafa", "#26c6da", "#ec407a", "#5c6bc0" }
local PANTS = { "#37474f", "#1565c0", "#5d4037", "#212121", "#78909c", "#283593" }
local SKIN = { "#f5d0b5", "#e0ac8a", "#c68863", "#8d5a3b", "#5c3a24", "#f1c27d" }
local HAIR = { "#3e2723", "#212121", "#6d4c41", "#fbc02d", "#bf360c", "#9e9e9e" }
local BEANIES = { "#d32f2f", "#1976d2", "#388e3c", "#fbc02d", "#7b1fa2" }
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
type Figure = { model: Model, parts: { BasePart }, dog: { BasePart }, leash: BasePart, shown: boolean }
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
	fig: Figure?,
}

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
			hair = (if Catalog.SEASON == "winter" then BEANIES else HAIR)[(h // 512) % 5 + 1],
			dog = DOG_COATS[(h // 2048) % #DOG_COATS + 1],
		},
		fig = nil,
	}
end

type Places = { shops: { Dest }, browse: { Dest }, parks: { Dest }, houses: { Dest }, corners: { Dest } }

-- Places worth walking to, sorted by what kind of outing they make.
local function destinations(g: any): Places
	local p: Places = { shops = {}, browse = {}, parks = {}, houses = {}, corners = {} }
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
				continue -- the nightclub's line and bouncer aren't drawn here yet
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

local function walkDog(p: Person, dt: number)
	if p.type ~= "dog" then
		return
	end
	local sin, cos = math.sin(p.heading), math.cos(p.heading)
	local still = p.state == "linger"
	local back = if still then -0.1 else 0.4
	local side = if still then 0.35 else 0.22
	local tx = p.pos[1] - sin * back + cos * side
	local tz = p.pos[2] - cos * back - sin * side
	local dx, dz = tx - p.dogPos[1], tz - p.dogPos[2]
	local k = math.min(1, dt * 6)
	p.dogPos[1] += dx * k
	p.dogPos[2] += dz * k
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

-- Done with the current stop (or time to leave home): work out the next one.
local function setOff(g: any, places: Places, p: Person, night: boolean)
	p.sit = false
	p.face = nil
	local atHome = p.at == `b{p.home}`
	if atHome and night and math.random() < 0.85 then
		p.timer = rand(20, 45) -- most people stay in after dark
		return
	end
	local dest: Dest? = nil
	if not atHome and (p.outings >= 3 or math.random() < 0.4 or night) then
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
			p.dogPos = { p.pos[1], p.pos[2] }
			p.dogHeading = p.heading
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
	else
		p.timer = if d.kind == "shop" then rand(5, 12) else rand(6, 14)
	end
end

local function updatePerson(g: any, places: Places, p: Person, dt: number, night: boolean)
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
	local move = p.speed * dt
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
	p.stride += dt * p.speed * (if p.type == "jogger" then 10 else 14)
	walkDog(p, dt)
end

-- A figure (peopleGeo.ts at Townspeople's scale): legs and shoes, torso and belt, arms and hands,
-- head with eyes, hair; a walked dog and its leash. Parts in the order draw() places them.
local function ellipsoid(parent: Instance, size: Vector3, color: string): Part
	local p = part(parent, Enum.PartType.Block, size, CFrame.new(), color)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end
local function figure(p: Person, parent: Instance): Figure
	local m = Instance.new("Model")
	m.Name = p.id
	local c = p.colors
	local parts: { BasePart } = {}
	local function add(x: BasePart)
		x.CastShadow = false
		table.insert(parts, x)
	end
	for _ = 1, 2 do
		add(part(m, nil, Vector3.new(0.06, LEG, 0.07) * K, CFrame.new(), c.pants))
	end
	for _ = 1, 2 do
		add(part(m, nil, Vector3.new(0.066, 0.04, 0.105) * K, CFrame.new(), "#2b2b2b"))
	end
	add(ellipsoid(m, Vector3.new(0.17, 0.33, 0.17) * K, c.shirt))
	add(part(m, Enum.PartType.Cylinder, Vector3.new(0.022, 0.176, 0.176) * K, CFrame.new(), "#3a3a3a"))
	for _ = 1, 2 do
		add(ellipsoid(m, Vector3.new(0.056, 0.196, 0.056) * K, c.shirt))
	end
	for _ = 1, 2 do
		add(part(m, Enum.PartType.Ball, Vector3.one * 0.052 * K, CFrame.new(), c.skin))
	end
	add(part(m, Enum.PartType.Ball, Vector3.one * 0.16 * K, CFrame.new(), c.skin))
	for _ = 1, 2 do
		add(part(m, Enum.PartType.Ball, Vector3.one * 0.022 * K, CFrame.new(), "#1a1a1a"))
	end
	add(ellipsoid(m, Vector3.new(0.17, 0.1, 0.17) * K, c.hair))
	-- The dog (Dog Park proportions, at its own size) and the leash.
	local dog: { BasePart } = {}
	local leash = part(m, nil, Vector3.new(0.009, 0.009, 1) * S, CFrame.new(), LEASHES[(#p.name * 3 + #p.dogName) % #LEASHES + 1])
	if p.type == "dog" then
		local k = p.dogSize * S
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
	return { model = m, parts = parts, dog = dog, leash = leash, shown = true }
end

local HIDDEN = CFrame.new(0, -10000, 0)

-- Places a person's figure (Townspeople.tsx draw()) into the lists BulkMoveTo takes.
local function draw(origin: Vector3, p: Person, wag: number, list: { BasePart }, cfs: { CFrame })
	local fig = p.fig :: Figure
	local hide = p.state == "inside"
	if hide then
		if fig.shown then
			fig.shown = false
			for _, x in fig.parts do
				table.insert(list, x)
				table.insert(cfs, HIDDEN)
			end
			for _, x in fig.dog do
				table.insert(list, x)
				table.insert(cfs, HIDDEN)
			end
			table.insert(list, fig.leash)
			table.insert(cfs, HIDDEN)
		end
		return
	end
	fig.shown = true
	local moving = p.state == "walk" and p.waited == 0
	local jog = p.type == "jogger"
	local swing = if moving then math.sin(p.stride) * (if jog then 0.85 else 0.55) else 0
	local bob = if moving then math.abs(math.cos(p.stride)) * (if jog then 0.05 else 0.025) else 0
	local hip = (if p.sit then 0.26 else LEG) + bob
	local base = CFrame.new(origin + Vector3.new(p.pos[1], 0, p.pos[2]) * S) * CFrame.Angles(0, p.heading, 0)
	local function at(x: number, y: number, z: number): CFrame
		return base * CFrame.new(x * K, y * K, z * K)
	end
	local i = 0
	local function put(cf: CFrame)
		i += 1
		table.insert(list, fig.parts[i])
		table.insert(cfs, cf)
	end
	-- Legs swing from the hips (sitting folds them forward), each with its shoe.
	local legs = {}
	for _, side in { -1, 1 } do
		local a = if p.sit then -math.pi / 2 else swing * side
		legs[side] = at(side * 0.045, hip, 0) * CFrame.Angles(a, 0, 0) * CFrame.new(0, -LEG / 2 * K, 0)
	end
	put(legs[-1])
	put(legs[1])
	put(legs[-1] * CFrame.new(0, (-LEG / 2 + 0.01) * K, 0.017 * K))
	put(legs[1] * CFrame.new(0, (-LEG / 2 + 0.01) * K, 0.017 * K))
	-- Body, belt and arms; hands; head, eyes and hair, stacked up from the hips.
	put(at(0, hip + 0.15, 0))
	put(at(0, hip + 0.065, 0) * UP)
	for _, s in { -1, 1 } do
		put(at(s * 0.107, hip + 0.18, 0) * CFrame.Angles(0, 0, s * 0.12))
	end
	for _, s in { -1, 1 } do
		put(at(s * 0.118, hip + 0.075, 0.005))
	end
	put(at(0, hip + 0.36, 0))
	for _, s in { -1, 1 } do
		put(at(s * 0.028, hip + 0.374, 0.07))
	end
	put(at(0, hip + 0.4, -0.015))
	if p.type == "dog" then
		local k = p.dogSize
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
		local hand = (at(0.118, hip + 0.075, 0.005)).Position
		local collar = dat(0, 0.17 + (if still then 0.03 else 0), 0.075).Position
		local span = (collar - hand).Magnitude
		fig.leash.Size = Vector3.new(0.009 * S, 0.009 * S, math.max(0.01, span))
		table.insert(list, fig.leash)
		table.insert(cfs, CFrame.lookAt((hand + collar) / 2, collar))
	end
end

---------------------------------------------------------------------------------------------------

local function smallScreen(): boolean
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 700
end

-- Brings a drawn town to life: returns a function that brings it up to date with a save, and one
-- that moves everything on by dt seconds (each frame).
function TownLife.attach(town: Folder): ((save: any) -> (), (rawDt: number) -> ())
	local origin: Vector3 = town:GetAttribute("Origin") :: any
	local carsFolder = town:WaitForChild("Cars")

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
			-- Anyone walking re-plans from where they stand; the simple way: home, indoors.
			for _, p in people do
				if p.state == "walk" or p.state == "linger" then
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
		updateTraffic(save)
		drawSignals(origin, save.roads or {})
		updatePeople(save)
	end
	local parked: { [string]: boolean } = {}
	local function step(rawDt: number)
		local dt = math.min(rawDt, 0.1)
		traffic:step(dt)
		stepSignals()
		-- The cars: each server model goes where the sim has it, at its town size.
		for _, m in carsFolder:GetChildren() do
			if not m:IsA("Model") then
				continue
			end
			local a = traffic.agents:get(m.Name)
			if not a then
				if not parked[m.Name] or m:GetAttribute("TownLife") == nil then
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
			m:PivotTo(CFrame.new(origin + Vector3.new(a.x * S, 0.02 * S, a.z * S)) * CFrame.Angles(0, a.yaw, 0) * CFrame.Angles(0, 0, tilt))
		end
		-- The townspeople.
		if graph and places then
			local night = clock.nightAmount(clock.dayPhase(DateTime.now().UnixTimestampMillis)) > 0.5
			local wag = os.clock()
			local parts: { BasePart } = {}
			local cfs: { CFrame } = {}
			for _, p in people do
				updatePerson(graph, places, p, dt, night)
				if p.fig and p.fig.model.Parent then
					draw(origin, p, wag, parts, cfs)
				end
			end
			if #parts > 0 then
				workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			end
		end
	end
	return update, step
end

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
		RunService.RenderStepped:Connect(step)
	end)
end

TownLife._traffic = traffic
TownLife._crossingSignal = crossingSignal

return TownLife
