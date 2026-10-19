--!strict
-- Where everything stands in the two merged-block forms of the gas station and the car wash (level
-- 7-10): the Big Bison travel stop and the Bubble Car Spa. A hand copy of the web game's
-- src/game/travelCenter.ts and src/game/washCenter.ts (and WashCenter.tsx's doorAt), which the
-- converter (tools/transpile) doesn't take yet; tests/centres.luau checks it against numbers the
-- web code gives (tools/gen-centres-golden.mjs).
--
-- Everything is in true web units on the block's own frame: x along its front, +z out of the front
-- towards the road. `sx`, `sz` are how much the block grows the station's own 2x1 lot along its x
-- and z (merge.ts groupScale: 2, 2 for a 2x2 block; 2, 1 or 1, 2 for a pair; 4, 4 for a 4x4).
-- Plain Luau with no Roblox in it, so the tests can run it.

local CentreLayout = {}

local TILE = 2

export type Rect = { x: number, z: number, w: number, d: number }
export type Travel = {
	L: number,
	D: number,
	store: { x: number, z: number, w: number, d: number, h: number },
	-- Where people step in: just in front of the doors, under the porch.
	door: { number },
	canopy: Rect,
	-- Pump islands, each running along x.
	islands: { { x: number, z: number } },
	-- Parking bays beside the store, each facing the store.
	bays: { { x: number, z: number } },
	-- The tall sign out front, and the bison statue people pose with.
	pylon: { number },
	statue: { number }?,
}

CentreLayout.ISLAND = 1.3
local ROW = 0.8
local GAP = 0.55
-- Half the width of the walk kept clear from the street to the doors.
local AISLE = 0.3

-- travelCenter.ts travelLayout.
function CentreLayout.travel(sx: number, sz: number): Travel
	local ISLAND = CentreLayout.ISLAND
	local L = 2 * TILE * sx
	local D = TILE * sz
	local front = D / 2
	local back = -D / 2
	-- A shallow pair (two lots side by side) has the store at one end; a deep block has it across
	-- the back, with the pumps out front. A narrow block centres its store; a wide one keeps the
	-- left for parking.
	local deep = D >= 3.5
	local wide = L >= 6
	local sw = if not deep then 2.7 elseif wide then math.min(L * 0.58, 7.2) else L - 0.6
	local sd = if deep then math.min(math.max(D * 0.3, 1.35), 2.4) else 1.35
	local sh = if deep then math.min(1.5 + sd * 0.25, 2.1) else 1.55
	local store = { x = if deep and not wide then 0 else L / 2 - sw / 2 - 0.25, z = back + 0.2 + sd / 2, w = sw, d = sd, h = sh }
	local porch = store.z + sd / 2 + 0.42
	local door = { store.x, porch - 0.12 }
	local canopy: Rect
	if deep then
		canopy = { x = if wide then 0.5 else 0, z = (porch + 0.45 + front - 0.3) / 2, w = if wide then L - 1.6 else L - 0.6, d = front - 0.3 - (porch + 0.45) }
	else
		local right = store.x - sw / 2 - 0.45
		local left = -L / 2 + 0.35
		canopy = { x = (left + right) / 2, z = -0.15, w = right - left, d = 1.5 }
	end
	local islands = {}
	local rows = math.max(1, math.floor((canopy.d + 0.45) / ROW))
	-- Columns of islands either side of the walk to the doors.
	local segs: { { number } } = { { canopy.x - canopy.w / 2, canopy.x + canopy.w / 2 } }
	if deep then
		segs = { { canopy.x - canopy.w / 2, door[1] - AISLE }, { door[1] + AISLE, canopy.x + canopy.w / 2 } }
	end
	for _, seg in segs do
		local lo, hi = seg[1], seg[2]
		local cols = math.floor((hi - lo + GAP) / (ISLAND + GAP))
		for c = 0, cols - 1 do
			local x = (lo + hi) / 2 + (c - (cols - 1) / 2) * (ISLAND + GAP)
			for r = 0, rows - 1 do
				table.insert(islands, { x = x, z = canopy.z + (r - (rows - 1) / 2) * ROW })
			end
		end
	end
	local bays = {}
	if deep then
		local left = -L / 2 + 0.35
		local right = store.x - sw / 2 - 0.3
		local x = left + 0.3
		while x + 0.3 <= right do
			table.insert(bays, { x = x, z = store.z })
			x += 0.55
		end
	end
	-- Both stand on the strip by the road left of the canopy (a shallow pair's bison stands by the
	-- store's side wall; a narrow block has no room for one).
	local pylon = if not deep then { -L / 2 + 0.3, front - 0.25 } elseif wide then { -L / 2 + 0.5, front - 0.35 } else { L / 2 - 0.15, back + 0.2 }
	local statue = if not deep then { store.x - sw / 2 - 0.05, 0.05, store.z } elseif wide then { -L / 2 + 0.5, 0.05, porch + 0.75 } else nil
	return { L = L, D = D, store = store, door = door, canopy = canopy, islands = islands, bays = bays, pylon = pylon, statue = statue }
end

export type Wash = {
	L: number,
	D: number,
	-- Tunnels run along x: cars go in at x0 and come out at x1.
	tunnels: { { x0: number, x1: number, z: number } },
	-- Vacuum bays: each a car's space with a post beside it. Nose to the back on a deep block;
	-- parked along the front on a shallow pair (`along`).
	vacs: { { x: number, z: number } },
	along: boolean,
	pylon: { number },
}

CentreLayout.TUNNEL_D = 0.95
local BAY = 0.9
local VAC_ROW = 1.25

-- washCenter.ts washLayout.
function CentreLayout.wash(sx: number, sz: number): Wash
	local TUNNEL_D = CentreLayout.TUNNEL_D
	local L = 2 * TILE * sx
	local D = TILE * sz
	local back = -D / 2
	local front = D / 2
	-- One tunnel, or two side by side on a big block; the kiosks and the queue take the left end,
	-- the exit apron the right.
	local n = if D >= 7 then 2 else 1
	local x0 = -L / 2 + math.min(1.4, L * 0.22)
	local x1 = L / 2 - math.min(0.8, L * 0.12)
	local tunnels = {}
	for i = 0, n - 1 do
		table.insert(tunnels, { x0 = x0, x1 = x1, z = back + 0.2 + TUNNEL_D / 2 + i * (TUNNEL_D + 0.55) })
	end
	local behind = tunnels[n].z + TUNNEL_D / 2 + 0.2
	local vacs = {}
	local along = front - behind < 1.3
	if along then
		local x = -L / 2 + 1.1
		while x + 0.6 <= L / 2 - 0.2 do
			table.insert(vacs, { x = x, z = (behind + front) / 2 })
			x += 1.3
		end
	else
		local rows = math.max(1, math.floor((front - 0.05 - behind) / VAC_ROW))
		for r = 0, rows - 1 do
			local z = behind + 0.6 + r * VAC_ROW
			local x = -L / 2 + 1.0
			while x + 0.45 <= L / 2 - 0.2 do
				table.insert(vacs, { x = x, z = z })
				x += BAY
			end
		end
	end
	return { L = L, D = D, tunnels = tunnels, vacs = vacs, along = along, pylon = { -L / 2 + 0.3, front - 0.3 } }
end

-- WashCenter.tsx doorAt: where the front tunnel's glass doors go, past the brushes and in line with
-- a column of vacuum bays without cars, so the walk out to the street is clear.
function CentreLayout.washDoor(t: Wash): number
	local u = t.tunnels[#t.tunnels]
	local lo = u.x0 + 1.95
	local hi = u.x1 - 0.35
	local cols, seen = {}, {}
	for _, v in t.vacs do
		if not seen[v.x] and v.x >= lo and v.x <= hi then
			seen[v.x] = true
			table.insert(cols, v.x)
		end
	end
	local empty = {}
	for _, x in cols do
		local clear = true
		for i, v in t.vacs do
			-- (The web's index i is from 0: even bays have a car.)
			if v.x == x and (i - 1) % 2 ~= 1 then
				clear = false
				break
			end
		end
		if clear then
			table.insert(empty, x)
		end
	end
	local function pick(xs: { number }): number
		local best = xs[1]
		for _, b in xs do
			if math.abs(b - (lo + hi) / 2) < math.abs(best - (lo + hi) / 2) then
				best = b
			end
		end
		return best
	end
	return if #empty > 0 then pick(empty) elseif #cols > 0 then pick(cols) else (lo + hi) / 2
end

return CentreLayout
