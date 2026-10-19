--!strict
-- The Big Bison travel stop: a merged gas station at level 7-10, as the web game's
-- scene/TravelCenter.tsx draws it for the whole block (laid out by src/shared/CentreLayout, the
-- web's game/travelCenter.ts), with its life.
--
-- The server draws a merged gas station as the one station grown to fill the block (TownView), so
-- the travel stop itself is drawn here, on each player's own screen, where CentreLife hides the
-- grown station: the store with its porch and doors, the long canopies over rows of pump islands,
-- the parking, lamps, the roadside sign and the bison statue. Drawn once; nothing of it moves.
--
-- Its life, which the web game draws standing still (a car at two pumps in three, cars in the
-- bays): here cars come and go at the pumps, rolling up to an island, stopping while the driver
-- stands at the pump, and rolling on out, and shoppers walk from their parked cars and in off the
-- street to the doors and back. A car pulls in and drives off growing and shrinking where it starts
-- and ends, as the town's traffic does at its ends (TownLife), rather than threading the lot.

local CentreLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CentreLayout")) :: any
local Kit = require(script.Parent:WaitForChild("Kit"))

local TravelStop = {}

local NAME = "BIG BISON"
local RED = "#c62828"
local YELLOW = "#ffca28"
local BROWN = "#5d4037"
local TAN = "#d9b98c"
local GOLD = "#ffc107"
local WHITE = "#fafafa"
-- A shop window or doorway lit from inside.
local LIT = "#fff3c4"
local GLASS = "#9cc9dd"
local ASPHALT = "#4b4f55"
local CONCRETE = "#cfd2d4"

-- How far before its pump a car shows up and how far past it it goes (web units), and how long that
-- roll takes (seconds). The growing or shrinking takes the first or last GROW seconds of it.
local ROLL = 0.75
local ROLL_TIME = 2.2
local GROW = 0.6
-- At most this many cars at the pumps at once (fewer on a phone).
local CARS, CARS_PHONE = 8, 5
local PUMPERS, PUMPERS_PHONE = 3, 2

type Slot = {
	x: number, -- the car's middle at the pump
	z: number,
	pump: number, -- z of the island it fills from
	side: number, -- which side of the island it's on (1: road side)
	left: Slot?, -- the next pump back along the same lane, and the next on
	right: Slot?,
	phase: string, -- "empty", "in", "fuel", "out"
	t: number, -- seconds into the phase, or left to wait while empty
	wait: number,
	car: Kit.Car?,
	pumper: Kit.Person?,
}

type Walker = {
	who: Kit.Person,
	path: { { number } }, -- from where they start (by their car, or the street) to inside the doors
	s: number, -- web units along the path
	dir: number, -- 1 going in, -1 coming back
	t: number, -- seconds left inside, or away
	len: number,
}

export type Stop = {
	folder: Folder,
	frame: CFrame,
	slots: { Slot },
	free: { Kit.Car },
	cars: { Kit.Car },
	pumpers: { Kit.Person },
	walkers: { Walker },
	step: (self: Stop, time: number, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame }) -> (),
	refresh: (self: Stop, eye: Vector3?) -> (),
}

---------------------------------------------------------------------------------------------------
-- The still parts.

-- The bison's head (TravelCenter.tsx BisonHead), about `r` across, facing +z at (x, y, z).
local function bisonHead(b: Kit.Builder, x: number, y: number, z: number, r: number)
	b:egg(x, y + 0.02 * r, z, 0.72 * r, 0.65 * r, 0.5 * r, "#6d4c41")
	b:egg(x, y + 0.26 * r, z - 0.02 * r, 0.67 * r, 0.39 * r, 0.45 * r, "#3e2723")
	b:egg(x, y - 0.1 * r, z + 0.22 * r, 0.37 * r, 0.26 * r, 0.24 * r, "#a1887f")
	for _, sd in { -1, 1 } do
		b:ball(x + sd * 0.13 * r, y + 0.08 * r, z + 0.24 * r, 0.075 * r, "#ffffff")
		b:ball(x + sd * 0.13 * r, y + 0.08 * r, z + 0.3 * r, 0.035 * r, "#212121")
		-- Horns, curling up from the sides.
		b:egg(x + sd * 0.4 * r, y + 0.24 * r, z, 0.09 * r, 0.26 * r, 0.09 * r, "#fff8e1")
	end
end

-- The brand: the bison's head on a yellow disc with a red rim, facing +z.
local function logo(b: Kit.Builder, x: number, y: number, z: number, r: number)
	local face = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder's x along z
	Kit.part(b.folder, Enum.PartType.Cylinder, Vector3.new(0.05, r * 2, r * 2) * Kit.S, b:at(x, y, z) * face, RED)
	Kit.part(b.folder, Enum.PartType.Cylinder, Vector3.new(0.05, r * 1.72, r * 1.72) * Kit.S, b:at(x, y, z + 0.012) * face, YELLOW)
	bisonHead(b, x, y, z + 0.05, r * 0.95)
end

local function sign(b: Kit.Builder, text: string, x: number, y: number, z: number, w: number, h: number, bg: string, fg: string, turn: CFrame?)
	local p = Kit.part(b.folder, nil, Vector3.new(w, h, 0.02) * Kit.S, b:at(x, y, z) * (turn or CFrame.new()), bg)
	Kit.sign(p, text, fg, bg)
	return p
end

local function store(b: Kit.Builder, t: any, level: number, small: boolean)
	local s, door = t.store, t.door
	local zf = s.z + s.d / 2
	local ent = math.min(1.5, s.w * 0.36)
	-- Brick walls on a stone base, a white roof deck and a red fascia band.
	Kit.solid(b:box(s.x, s.h / 2, s.z, s.w, s.h, s.d, TAN, Enum.Material.Brick))
	b:box(s.x, 0.17, s.z, s.w + 0.03, 0.3, s.d + 0.03, "#8d6e63")
	Kit.solid(b:box(s.x, s.h + 0.03, s.z, s.w + 0.06, 0.06, s.d + 0.06, "#eceff1"))
	b:box(s.x, s.h - 0.08, zf + 0.04, s.w + 0.08, 0.22, 0.04, RED)
	-- Big shop windows either side of the entrance.
	local x = s.x - s.w / 2 + 0.35
	while x <= s.x + s.w / 2 - 0.3 do
		if math.abs(x - door[1]) > ent / 2 + 0.2 then
			b:box(x, 0.66, zf + 0.01, 0.42, 0.68, 0.02, GLASS)
			b:box(x, 0.34, zf + 0.02, 0.46, 0.04, 0.04, "#eceff1")
		end
		x += 0.5
	end
	-- Stepped false fronts along the roofline, like an old main street.
	x = s.x - s.w / 2 + 0.7
	while x <= s.x + s.w / 2 - 0.6 do
		if math.abs(x - door[1]) > ent / 2 + 0.55 then
			b:box(x, s.h + 0.14, zf - 0.04, 0.9, 0.28, 0.08, TAN, Enum.Material.Brick)
			b:box(x, s.h + 0.3, zf - 0.04, 0.96, 0.05, 0.12, "#8d6e63")
		end
		x += 2.1
	end
	-- The entrance: a tall red gable over the lit glass doors, the name and the bison.
	local dx = door[1]
	b:box(dx, (s.h + 0.6) / 2, zf + 0.12, ent, s.h + 0.6, 0.24, RED)
	b:box(dx, s.h + 0.62, zf + 0.12, ent + 0.08, 0.06, 0.3, WHITE)
	b:box(dx, 0.5, zf + 0.245, ent * 0.66, 0.92, 0.01, "#37474f")
	b:box(dx, 0.43, zf + 0.252, ent * 0.62, 0.76, 0.01, LIT)
	b:box(dx, 0.84, zf + 0.258, ent * 0.62, 0.025, 0.01, "#cfd8dc")
	local signW = math.min(ent * 1.6, 2.6)
	sign(b, NAME, dx, s.h - 0.1, zf + 0.262, signW, signW / 4, RED, "#fffde7")
	logo(b, dx, s.h + 0.12 + ent * 0.32, zf + 0.27, ent * 0.32)
	-- The porch along the front: red roof on white posts.
	b:box(s.x, 1.16, zf + 0.17, s.w + 0.1, 0.06, 0.36, RED)
	local posts = math.max(2, math.round(s.w / 1.1) + 1)
	for i = 0, posts - 1 do
		local px = -s.w / 2 + 0.05 + i * (s.w - 0.1) / (posts - 1)
		if math.abs(s.x + px - dx) >= ent / 2 + 0.1 then
			Kit.solid(b:cyl(s.x + px, 0.6, zf + 0.32, 0.035, 1.08, WHITE))
		end
	end
	-- Ice chests, planters and rocking chairs along the porch.
	local z = zf + 0.16
	local i = 0
	x = s.x - s.w / 2 + 0.3
	while x <= s.x + s.w / 2 - 0.25 do
		if math.abs(x - dx) > ent / 2 + 0.25 then
			local k = i % 4
			if k == 0 then
				b:box(x, 0.09 + 0.17, z, 0.34, 0.34, 0.2, "#eceff1")
				b:box(x, 0.09 + 0.35, z, 0.36, 0.03, 0.22, "#0277bd")
			elseif k == 2 then
				b:box(x, 0.09 + 0.09, z, 0.24, 0.18, 0.18, "#8d6e63")
				b:ball(x, 0.09 + 0.27, z, 0.13, "#43a047")
			elseif not small then
				for _, cx in { -0.09, 0.09 } do
					b:box(x + cx, 0.09 + 0.13, z, 0.13, 0.025, 0.13, BROWN)
					b:box(x + cx, 0.09 + 0.24, z - 0.06, 0.13, 0.22, 0.02, BROWN)
				end
			end
			i += 1
		end
		x += 0.42
	end
	-- Air handlers on the roof, and a flag from level 8.
	i = 0
	x = s.x - s.w / 2 + 0.5
	while x <= s.x + s.w / 2 - 0.5 do
		b:box(x, s.h + 0.06 + 0.13, s.z - s.d * 0.15 + (i % 2) * 0.25, 0.42, 0.26, 0.32, "#b0bec5")
		i += 1
		x += 1.2
	end
	if level >= 8 then
		local fx, fy, fz = s.x + s.w / 2 - 0.2, s.h + 0.06, s.z - s.d / 2 + 0.2
		b:cyl(fx, fy + 0.45, fz, 0.022, 0.9, "#eceff1")
		b:box(fx + 0.17, fy + 0.75, fz, 0.32, 0.2, 0.015, RED)
		b:ball(fx, fy + 0.92, fz, 0.04, GOLD)
	end
	-- The name down the side too, for the cars coming the other way.
	local sw = math.min(s.d * 0.85, 1.8)
	sign(b, NAME, s.x + s.w / 2 + 0.012, s.h * 0.62, s.z, sw, sw / 4, RED, "#fffde7", CFrame.Angles(0, math.pi / 2, 0))
end

-- The zebra walk from the street to the front doors, and the sidewalk under the porch.
local function walk(b: Kit.Builder, t: any)
	local s, door, D = t.store, t.door, t.D
	local z0 = s.z + s.d / 2
	b:box(s.x, 0.06, z0 + 0.253, s.w + 0.2, 0.06, 0.494, CONCRETE, Enum.Material.Concrete)
	local n = math.max(0, math.floor((D / 2 - 0.1 - (z0 + 0.5)) / 0.18))
	for i = 0, n - 1 do
		b:box(door[1], 0.065, z0 + 0.6 + i * 0.18, 0.5, 0.03, 0.09, WHITE)
	end
end

-- A pump island: two pumps either side of the canopy post, bollards at the ends, a bin.
local function island(b: Kit.Builder, x: number, z: number, h: number)
	local ISLAND = CentreLayout.ISLAND
	b:box(x, 0.08, z, ISLAND, 0.1, 0.32, "#cfd8dc", Enum.Material.Concrete)
	b:box(x, 0.145, z, ISLAND - 0.04, 0.03, 0.3, YELLOW)
	Kit.solid(b:box(x, (h + 0.14) / 2, z, 0.1, h - 0.14, 0.1, WHITE))
	for _, px in { -0.36, 0.36 } do
		Kit.solid(b:box(x + px, 0.44, z, 0.3, 0.6, 0.22, WHITE))
		-- The pump's red face and its little screen, both sides.
		b:box(x + px, 0.38, z, 0.31, 0.2, 0.23, RED)
		b:box(x + px, 0.62, z, 0.16, 0.08, 0.23, "#263238")
		b:box(x + px, 0.76, z, 0.32, 0.05, 0.24, RED)
	end
	for _, bx in { -ISLAND / 2 + 0.04, ISLAND / 2 - 0.04 } do
		b:cyl(x + bx, 0.29, z, 0.035, 0.3, YELLOW)
	end
	b:cyl(x, 0.27, z + 0.13, 0.06, 0.26, "#455a64")
end

-- The pump canopies: one long white roof per row of islands, red-banded, the name along the front.
local function canopy(b: Kit.Builder, t: any, level: number, rows: { number })
	local c = t.canopy
	local y = 1.55
	local strips = {}
	if #rows > 1 then
		for _, z in rows do
			table.insert(strips, { z = z, d = 0.56 })
		end
	else
		table.insert(strips, { z = c.z, d = c.d })
	end
	local n = math.max(1, math.floor(c.w / 3.2))
	local vents = math.max(1, math.floor(c.w / 2.4))
	local panels = math.max(1, math.floor(c.w / 0.6))
	for i, st in strips do
		local zf = st.z + st.d / 2
		b:box(c.x, y, st.z, c.w, 0.16, st.d, WHITE)
		b:box(c.x, y, zf + 0.01, c.w + 0.04, 0.2, 0.03, RED)
		b:box(c.x, y, st.z - st.d / 2 - 0.01, c.w + 0.04, 0.2, 0.03, RED)
		for _, sd in { -1, 1 } do
			b:box(c.x + sd * (c.w / 2 + 0.01), y, st.z, 0.03, 0.2, st.d, RED)
		end
		b:box(c.x, y + 0.115, zf + 0.01, c.w + 0.05, 0.03, 0.04, YELLOW)
		if i == #strips then
			for j = 0, n - 1 do
				sign(b, NAME, c.x + (j - (n - 1) / 2) * 3.2, y, zf + 0.04, 1.2, 0.3, RED, "#fffde7")
			end
		end
		for j = 0, vents - 1 do
			b:box(c.x + (j - (vents - 1) / 2) * 2.4, y + 0.11, st.z, 0.24, 0.06, 0.18, "#cfd8dc")
		end
		if level >= 10 then
			for j = 0, panels - 1 do
				local px = c.x - c.w / 2 + 0.3 + j * (c.w - 0.6) / math.max(1, panels - 1)
				Kit.part(b.folder, nil, Vector3.new(0.5, 0.02, st.d * 0.75) * Kit.S, b:at(px, y + 0.1, st.z) * CFrame.Angles(-0.2, 0, 0), "#1a237e")
			end
		end
	end
	for _, p in t.islands do
		island(b, p.x, p.z, y - 0.08)
	end
end

-- Parking beside the store: striped bays, some taken, and lamps at the lot's corners.
local function parking(b: Kit.Builder, t: any, cars: { Kit.Car }, folder: Instance, seed: number)
	local L, D, s = t.L, t.D, t.store
	local zb = s.z + s.d / 2 - 0.1
	for i, bay in t.bays do
		b:box(bay.x - 0.275, 0.065, s.z, 0.03, 0.03, math.min(s.d, 1.1), WHITE)
		if (i - 1) % 3 ~= 2 then
			local car = Kit.car(folder, seed + (i - 1) * 3 + 2)
			if car then
				-- Nose in, to the store.
				Kit.park(car, b:at(bay.x, 0.05, zb - 0.45) * CFrame.Angles(0, math.pi, 0))
				table.insert(cars, car)
			end
		end
	end
	for _, xz in { { -L / 2 + 0.2, -D / 2 + 0.2 }, { L / 2 - 0.2, D / 2 - 0.2 }, { -L / 2 + 0.2, D / 2 - 0.2 } } do
		local x, z = xz[1], xz[2]
		Kit.solid(b:cyl(x, 0.9, z, 0.03, 1.8, "#607d8b"))
		b:box(x, 1.8, z, 0.24, 0.05, 0.12, "#455a64")
		b:box(x, 1.765, z, 0.2, 0.02, 0.09, LIT)
	end
end

-- The tall sign by the road: the bison on top, the name and the price below.
local function pylon(b: Kit.Builder, t: any, level: number)
	local x, z = t.pylon[1], t.pylon[2]
	local h = math.min(1.3 + t.L * 0.06, 2.4) + (level - 7) * 0.03
	local w = 1.1
	for _, sd in { -1, 1 } do
		Kit.solid(b:box(x + sd * w / 3, (h - 0.01) / 2, z, 0.08, h - 0.01, 0.08, "#90a4ae"))
	end
	b:box(x, 0.15, z, w * 0.9, 0.3, 0.24, "#8d6e63")
	b:box(x, h - 0.2, z, w + 0.1, 0.4, 0.1, RED)
	sign(b, NAME, x, h - 0.2, z + 0.06, w, 0.3, RED, "#fffde7")
	b:box(x, h - 0.72, z, w * 0.8, 0.5, 0.09, "#263238")
	-- The web shows today's Los Angeles pump price (useGasPrice); the town's own gas station shows
	-- its board's price, so this does too.
	sign(b, "GAS 1.99", x, h - 0.72, z + 0.055, w * 0.72, 0.42, "#263238", YELLOW)
	logo(b, x, h + w * 0.42, z, w * 0.45)
end

-- The bison out front on its plinth (gold at level 10), for the photos.
local function statue(b: Kit.Builder, at: { number }, gold: boolean)
	local x, z = at[1], at[3]
	b:box(x, 0.1, z, 0.7, 0.2, 0.42, if gold then GOLD else "#8d6e63")
	b:egg(x + 0.1, 0.2 + 0.42, z, 0.52, 0.49, 0.39, BROWN)
	b:egg(x - 0.18, 0.2 + 0.36, z, 0.4, 0.32, 0.28, "#6d4c41")
	for _, lx in { { 0.18, 0.1 }, { 0.18, -0.1 }, { -0.22, 0.09 }, { -0.22, -0.09 } } do
		b:cyl(x + lx[1], 0.2 + 0.12, z + lx[2], 0.045, 0.24, "#4e342e")
	end
	-- The head looks along +x (the web turns it to face its way).
	local head = Kit.builder(b.folder, b:at(x + 0.38, 0.6, z) * CFrame.Angles(0, math.pi / 2, 0))
	bisonHead(head, 0, 0, 0, 0.5)
end

-- EV chargers at the far end of the parking row (level 9 and up).
local function chargers(b: Kit.Builder, t: any)
	local s, L = t.store, t.L
	for _, dz in { -0.25, 0.2 } do
		local x, z = -L / 2 + 0.16, s.z + dz
		Kit.solid(b:box(x, 0.28, z, 0.1, 0.56, 0.16, "#eceff1"))
		b:box(x + 0.054, 0.4, z, 0.01, 0.08, 0.08, LIT)
		b:box(x, 0.58, z, 0.12, 0.04, 0.18, "#43a047")
	end
end

---------------------------------------------------------------------------------------------------
-- The life.

local function ease(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

-- Builds the travel stop for one block (or one half of a 2x4) at `frame`, the block's middle on
-- the ground facing its road, grown `sx` x `sz` from the station's own lot. `seed` varies the cars.
function TravelStop.new(parent: Instance, frame: CFrame, sx: number, sz: number, level: number, small: boolean, seed: number): Stop
	local folder = Instance.new("Folder")
	folder.Name = "TravelStop"
	local t = CentreLayout.travel(sx, sz)
	local b = Kit.builder(folder, frame)
	-- Asphalt over the whole block.
	b:box(0, 0.03, 0, t.L - 0.12, 0.04, t.D - 0.12, ASPHALT, Enum.Material.Asphalt)
	walk(b, t)
	store(b, t, level, small)
	local rowSet, rows = {}, {}
	for _, p in t.islands do
		if not rowSet[p.z] then
			rowSet[p.z] = true
			table.insert(rows, p.z)
		end
	end
	table.sort(rows)
	canopy(b, t, level, rows)
	local parked: { Kit.Car } = {}
	parking(b, t, parked, folder, seed)
	pylon(b, t, level)
	if t.statue then
		statue(b, t.statue, level >= 10)
	end
	if level >= 9 then
		chargers(b, t)
	end

	-- The pumps cars stop at: the road side of the front row and the store side of the back row (one
	-- row: its road side), each car just off the middle of its island, as the web parks them.
	local slots: { Slot } = {}
	for i, p in t.islands do
		local n = i - 1
		local side = if p.z == rows[#rows] then 1 elseif p.z == rows[1] then -1 else 0
		if side ~= 0 then
			table.insert(slots, {
				x = p.x + (if n % 2 == 1 then -0.15 else 0.15),
				z = p.z + side * 0.46,
				pump = p.z,
				side = side,
				phase = "empty",
				t = 0,
				-- Two pumps in three busy to begin with, as the web draws it; the rest come soon.
				wait = if n % 3 ~= 2 then 0 else 2 + (n % 5) * 1.3,
			} :: any)
		end
	end
	-- Each pump's neighbours along its lane (cars roll along +x), so two never meet.
	for _, a in slots do
		for _, o in slots do
			if o ~= a and o.z == a.z then
				if o.x > a.x and (not a.right or o.x < (a.right :: Slot).x) then
					a.right = o
				end
				if o.x < a.x and (not a.left or o.x > (a.left :: Slot).x) then
					a.left = o
				end
			end
		end
	end
	-- Start part way through: cars already filling up at two pumps in three.
	for i, sl in slots do
		if sl.wait == 0 then
			sl.phase = "fuel"
			sl.t = (i * 3.7) % 9
			sl.wait = 7 + (i * 2.3) % 7
		end
	end

	local cars: { Kit.Car } = {}
	for i = 1, math.min(#slots, if small then CARS_PHONE else CARS) do
		local car = Kit.car(folder, seed + 40 + i)
		if car then
			table.insert(cars, car)
		end
	end
	local free = table.clone(cars)
	for _, sl in slots do
		if sl.phase == "fuel" then
			sl.car = table.remove(free)
			if not sl.car then
				sl.phase, sl.wait = "empty", 3
			end
		end
	end
	local pumpers = {}
	for i = 1, if small then PUMPERS_PHONE else PUMPERS do
		table.insert(pumpers, Kit.person(folder, `bison-pump-{seed}-{i}`))
	end

	-- Shoppers: one from a parked car by the store (when there are bays), one in off the street up
	-- the zebra walk (two of each on a big screen, when there's room).
	local walkers: { Walker } = {}
	local s, door = t.store, t.door
	local zf = s.z + s.d / 2
	local function addWalker(path: { { number } }, i: number)
		local len = 0
		for j = 2, #path do
			len += math.sqrt((path[j][1] - path[j - 1][1]) ^ 2 + (path[j][2] - path[j - 1][2]) ^ 2)
		end
		table.insert(walkers, {
			who = Kit.person(folder, `bison-shop-{seed}-{i}`),
			path = path,
			-- Spread out: some on their way in, some out, some inside.
			s = (i * 0.37 % 1) * len,
			dir = if i % 2 == 0 then 1 else -1,
			t = 0,
			len = len,
		})
	end
	local bayCars = {}
	for i, bay in t.bays do
		if (i - 1) % 3 ~= 2 then
			table.insert(bayCars, bay)
		end
	end
	local porchZ = zf + 0.45
	local n = 0
	for i = 1, math.min(#bayCars, if small then 1 else 2) do
		local bay = bayCars[if i == 1 then #bayCars else 1]
		n += 1
		addWalker({ { bay.x, zf }, { bay.x, porchZ }, { door[1] - 0.12, porchZ }, { door[1] - 0.12, zf + 0.05 } }, n)
	end
	for i = 1, if small then 1 else 2 do
		local dx = door[1] + (if i == 1 then 0.12 else -0.12)
		n += 1
		addWalker({ { dx, t.D / 2 - 0.1 }, { dx, porchZ }, { dx, zf + 0.05 } }, n)
	end

	folder.Parent = parent
	local self = {
		folder = folder,
		frame = frame,
		slots = slots,
		free = free,
		cars = cars,
		parked = parked,
		pumpers = pumpers,
		walkers = walkers,
	}
	return (setmetatable(self, { __index = TravelStop }) :: any) :: Stop
end

-- Where a car is along its lane, `u` (0 to 1) of the way from showing up to its pump (phase "in")
-- or from its pump to where it goes (phase "out"), and how big it's drawn.
local function carAt(self: Stop, sl: Slot): (CFrame, number)
	local x, show = sl.x, 1
	if sl.phase == "in" then
		local u = sl.t / ROLL_TIME
		x = sl.x - ROLL * (1 - (1 - (1 - u) ^ 2)) -- slowing to a stop
		show = math.min(1, sl.t / GROW)
	elseif sl.phase == "out" then
		local u = sl.t / ROLL_TIME
		x = sl.x + ROLL * u * u -- pulling away
		show = math.min(1, (ROLL_TIME - sl.t) / GROW)
	end
	-- Nose along +x, as the web parks them at the pumps.
	return self.frame * CFrame.new(x * Kit.S, 0.05 * Kit.S, sl.z * Kit.S) * CFrame.Angles(0, math.pi / 2, 0), show
end

local function busy(sl: Slot?, phase: string): boolean
	return sl ~= nil and sl.phase == phase
end

function TravelStop.step(self: Stop, time: number, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	for _, sl in self.slots do
		sl.t += dt
		if sl.phase == "empty" then
			-- A car pulls in once the pump's free, a car's free to come, and the car before along the
			-- lane isn't driving off into where this one shows up.
			if sl.t >= sl.wait and #self.free > 0 and not busy(sl.left, "out") then
				local pick = math.random(1, #self.free)
				sl.car = table.remove(self.free, pick)
				sl.phase, sl.t = "in", 0
			end
		elseif sl.phase == "in" then
			if sl.t >= ROLL_TIME then
				sl.phase, sl.t, sl.wait = "fuel", 0, math.random() * 9 + 6
			end
		elseif sl.phase == "fuel" then
			-- Filled up: off it goes, once the next car along has stopped at its own pump.
			if sl.t >= sl.wait and not busy(sl.right, "in") then
				sl.phase, sl.t = "out", 0
			end
		elseif sl.phase == "out" then
			if sl.t >= ROLL_TIME then
				local car = sl.car :: Kit.Car
				Kit.hide(car, list, cfs)
				table.insert(self.free, car)
				sl.car = nil
				sl.phase, sl.t, sl.wait = "empty", 0, math.random() * 9 + 3
			end
		end
		local car = sl.car
		if car then
			local cf, show = carAt(self, sl)
			Kit.place(car, cf, show, list, cfs)
		end
		-- The driver at the pump while it fills: out of the car, by the pump, facing the island.
		if sl.phase == "fuel" and sl.t > 0.6 and sl.t < sl.wait - 0.6 then
			if not sl.pumper then
				for _, who in self.pumpers do
					if not who.taken then
						who.taken = true
						sl.pumper = who
						break
					end
				end
			end
		elseif sl.pumper then
			local who = sl.pumper :: any
			Kit.drawPerson(who, self.frame, 0, 0, 0, "inside", 0, time, eye, list, cfs)
			who.taken = false
			sl.pumper = nil
		end
		if sl.pumper then
			local face = if sl.side > 0 then math.pi else 0
			Kit.drawPerson(sl.pumper, self.frame, sl.x - 0.32, sl.z - sl.side * 0.22, face, "linger", 0, time, eye, list, cfs)
		end
	end
	for _, w in self.walkers do
		local state, moved = "walk", 0
		if w.t > 0 then
			-- Inside the store (at the far end), or gone off in their car or up the street.
			w.t -= dt
			state = "inside"
			if w.t <= 0 then
				w.dir = -w.dir
			end
		else
			local step = Kit.WALK * dt
			w.s += step * w.dir
			moved = step
			if w.s >= w.len then
				w.s, w.t = w.len, 6 + math.random() * 10
			elseif w.s <= 0 then
				w.s, w.t = 0, 4 + math.random() * 8
			end
		end
		-- Where along the path, and which way they face.
		local left = w.s
		local x, z, heading = w.path[1][1], w.path[1][2], 0
		for j = 2, #w.path do
			local a, c = w.path[j - 1], w.path[j]
			local seg = math.sqrt((c[1] - a[1]) ^ 2 + (c[2] - a[2]) ^ 2)
			local u = if seg > 0 then math.min(1, left / seg) else 1
			x, z = a[1] + (c[1] - a[1]) * u, a[2] + (c[2] - a[2]) * u
			heading = math.atan2((c[1] - a[1]) * w.dir, (c[2] - a[2]) * w.dir)
			if left <= seg then
				break
			end
			left -= seg
		end
		Kit.drawPerson(w.who, self.frame, x, z, heading, state, moved, time, eye, list, cfs)
	end
end

-- Once a second: the cars' detail for how far off they are, and any drawn before their meshes
-- arrived built again for real.
function TravelStop.refresh(self: Stop, eye: Vector3?)
	for _, car in self.cars do
		Kit.refresh(car, eye)
	end
	for _, car in (self :: any).parked do
		Kit.refresh(car, eye)
	end
end

return TravelStop
