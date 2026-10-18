--!strict
-- A kart circuit in the world, as the web game's scene/KartScene.tsx draws it: the tarmac ribbon
-- with its kerbs, white lines, verges and sponsor-board barriers, the chequered line with its grid
-- boxes and the gantry of five start lights, the boost pads and jumps, the theme's ground and
-- scenery round it (the town's shops, trees and towers; the harbour's water, quay, containers,
-- cranes and lighthouse; the canyon's sand, mesas and saguaros), grandstands, tyre walls on the
-- bends and the far hills (KartHorizon.tsx). Built from the converted track (Shared.Game.kart's
-- buildTrack), 10 studs to the web's unit, far from every town; kept between races on the same
-- circuit.
--
-- Also the karts themselves (the racers' own cars at kart size, KART_LEN long) and what a race
-- puts on the road: prize crates, obstacles, dropped hazards and the effects on each kart.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local K = require(Game.kart) :: any
local obstacles = require(Game.obstacles) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint)
local Builder = require(ReplicatedStorage.Shared.Models.Builder) :: any
local Mods = require(ReplicatedStorage.Shared.Models.Mods)
local Panels = require(ReplicatedStorage.Shared.Models.Panels)
local Trim = require(ReplicatedStorage.Shared.Models.Trim)
local Skins = require(ReplicatedStorage.Shared.Models.Skins)

local KartWorld = {}

KartWorld.S = 10 -- studs per web unit
local S = KartWorld.S
KartWorld.ORIGIN = Vector3.new(-60000, 0, 0) -- far from every town and the drag strip
local ORIGIN = KartWorld.ORIGIN

local Y_ROAD, Y_KERB, Y_PAINT = 0.02, 0.035, 0.04

-- Each theme's ground, verge, kerbs, barrier and its cap (KartScene THEMES).
local THEMES = {
	town = { ground = "#86d05a", verge = "#86d05a", kerb = { "#e53935", "#fafafa" }, barrier = "#eceff1", cap = "#c62828" },
	docks = { ground = "#9aa3a9", verge = "#b0b6ba", kerb = { "#fbc02d", "#212121" }, barrier = "#cfd8dc", cap = "#fbc02d" },
	desert = { ground = "#d9a46c", verge = "#c9925a", kerb = { "#e53935", "#fafafa" }, barrier = "#d7ccc8", cap = "#1565c0" },
}
-- The sponsor boards along the barrier, in invented names (KartScene ADS).
local ADS = { "CARTOPIA", "RUSTY'S", "BIG BISON", "TURBO TONIC", "GEARBOX", "NITRO NUTS", "SKYHOPPER", "LUGNUT CO" }
local AD_COLORS = { { "#1565c0", "#ffffff" }, { "#c62828", "#ffeb3b" }, { "#2e7d32", "#ffffff" }, { "#212121", "#ff9100" }, { "#6a1b9a", "#ffffff" }, { "#ffeb3b", "#c62828" }, { "#00838f", "#ffffff" }, { "#ef6c00", "#212121" } }
-- Main Street's shops when the town has none of its own to lend (as the drag strip's).
local FALLBACK = { "pizza", "donut", "burger", "diner", "motel", "carwash", "tires", "gas", "bowling", "icecream", "coffee", "tacos" }
-- The far ridges round each theme (KartHorizon RIDGES).
local RIDGES = {
	town = {
		{ r = 150, depth = 26, lo = 5, hi = 16, seed = 3, base = "#6fa548", top = "#4c8a3a", haze = 0.25 },
		{ r = 182, depth = 30, lo = 22, hi = 50, seed = 7, base = "#5b7f6e", top = "#7e93a8", snow = 40, haze = 0.45 },
	},
	docks = {
		{ r = 166, depth = 22, lo = 6, hi = 20, seed = 11, base = "#6f9c4f", top = "#4f7f3d", haze = 0.3 },
		{ r = 196, depth = 30, lo = 24, hi = 52, seed = 13, base = "#62806f", top = "#8b9bb0", snow = 44, haze = 0.5 },
	},
	desert = {
		{ r = 150, depth = 24, lo = 6, hi = 22, seed = 17, base = "#c8693a", top = "#a84a2a", steps = 4, haze = 0.22 },
		{ r = 185, depth = 30, lo = 20, hi = 46, seed = 19, base = "#b06a4d", top = "#8a6a7c", haze = 0.45 },
	},
}
KartWorld.FOG = "#d9f2ff"

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- A world point from the web's (x, y, z).
local function W(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x * S, y * S, z * S)
end
KartWorld.W = W

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end
KartWorld.part = part

-- A seeded random 0..1 (RaceVenues rand).
local function rand(seed: number): () -> number
	local s = seed * 9301 + 49297
	return function(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

local function library(kind: string, id: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local folder = lib and lib:FindFirstChild(kind)
	local src = folder and folder:FindFirstChild(id)
	if not src then
		return nil
	end
	local m = src:Clone() :: Model
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	return m
end

-- Lettering on one face of a part (render.mjs draws it too).
local function sign(p: BasePart, text: string, fg: string, bg: string, face: Enum.NormalId?)
	local g = Instance.new("SurfaceGui")
	g.Face = face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 20
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = hex(bg)
	l.TextColor3 = hex(fg)
	l.Text = text
	l.TextScaled = true
	l.Font = Enum.Font.FredokaOne
	l.Parent = g
	g.Parent = p
end

-- ── Track geometry ─────────────────────────────────────────────────────────────────────────────

-- A strip following the centre line between two offsets across it (+ is left), its top at `top`
-- (web units), each piece coloured by color(i, s) where s is how far round the lap it starts.
local function ribbon(into: Instance, t: any, a: number, b: number, top: number, thick: number, color: (number, number) -> Color3, name: string, material: Enum.Material?)
	local n = t.n
	local m = (a + b) / 2
	local w = math.abs(b - a)
	local reach = math.max(math.abs(a), math.abs(b))
	local s = 0
	for i = 0, n - 1 do
		local j = (i + 1) % n
		local x0, z0 = t.x[i] + t.nx[i] * m, t.z[i] + t.nz[i] * m
		local x1, z1 = t.x[j] + t.nx[j] * m, t.z[j] + t.nz[j] * m
		local dx, dz = x1 - x0, z1 - z0
		local len = math.sqrt(dx * dx + dz * dz)
		-- Long enough to close the gap round the outside of a bend.
		local extra = math.abs(t.curve[i]) * (reach + w / 2) + 0.06
		part({
			Name = name,
			Size = Vector3.new(w * S, thick * S, (len + extra) * S),
			CFrame = CFrame.new(W((x0 + x1) / 2, top - thick / 2, (z0 + z1) / 2)) * CFrame.Angles(0, math.atan2(dx, dz), 0),
			Color = color(i, s),
			Material = material or Enum.Material.SmoothPlastic,
		}, into)
		s += math.sqrt((t.x[j] - t.x[i]) ^ 2 + (t.z[j] - t.z[i]) ^ 2)
	end
end

-- Sponsor boards along a barrier at offset o (each 2 units of the lap, as the web's texture),
-- lettered on the side that faces the track.
local function boards(into: Instance, t: any, o: number)
	local n = t.n
	local sg = if o > 0 then 1 else -1
	-- Points round the lap every 2 units.
	local s, at = 0, {}
	table.insert(at, 0)
	for i = 1, n do
		local j = i % n
		s += math.sqrt((t.x[j] - t.x[i - 1]) ^ 2 + (t.z[j] - t.z[i - 1]) ^ 2)
		if s >= 2 then
			table.insert(at, j)
			s = 0
		end
	end
	for k = 1, #at do
		local i, j = at[k], at[k % #at + 1]
		local x0, z0 = t.x[i] + t.nx[i] * o, t.z[i] + t.nz[i] * o
		local x1, z1 = t.x[j] + t.nx[j] * o, t.z[j] + t.nz[j] * o
		local dx, dz = x1 - x0, z1 - z0
		local len = math.sqrt(dx * dx + dz * dz)
		if len < 0.1 then
			continue
		end
		local ad = (k - 1) % #ADS + 1
		-- The lettering faces the track: the part's -X side on the left barrier, +X on the right.
		local p = part({
			Name = "Board",
			Size = Vector3.new(0.06 * S, 0.62 * S, len * S),
			CFrame = CFrame.new(W((x0 + x1) / 2, 0.31, (z0 + z1) / 2)) * CFrame.Angles(0, math.atan2(dx, dz), 0),
			Color = hex(AD_COLORS[ad][1]),
		}, into)
		sign(p, ADS[ad], AD_COLORS[ad][2], AD_COLORS[ad][1], if sg > 0 then Enum.NormalId.Left else Enum.NormalId.Right)
	end
end

-- Spots beside the track (kartSpots.ts useSpots): clear of it by a margin, along either side,
-- and which side is the outside of a bend.
local function spots(t: any)
	local cell = 8
	local grid: { [string]: { number } } = {}
	for i = 0, t.n - 1 do
		local k = `{math.floor(t.x[i] / cell)},{math.floor(t.z[i] / cell)}`
		local l = grid[k] or {}
		table.insert(l, i)
		grid[k] = l
	end
	local function clearOf(x: number, z: number, d: number): boolean
		local r = math.ceil(d / cell)
		local cx, cz = math.floor(x / cell), math.floor(z / cell)
		for a = -r, r do
			for b = -r, r do
				for _, i in grid[`{cx + a},{cz + b}`] or {} do
					if (t.x[i] - x) ^ 2 + (t.z[i] - z) ^ 2 < d * d then
						return false
					end
				end
			end
		end
		return true
	end
	local function along(step: number, off: number, side: number, clear: number, seed: number, jitter: number?): { any }
		local r = rand(seed)
		local out = {}
		local s = r() * step
		while s < t.n do
			local i = math.floor(s)
			local o = side * (t.wall + off + r() * (jitter or 0))
			local x, z = t.x[i] + t.nx[i] * o, t.z[i] + t.nz[i] * o
			if clearOf(x, z, t.wall + clear) then
				table.insert(out, { x = x, z = z, ry = math.atan2(-t.nx[i] * side, -t.nz[i] * side), i = i, r = r })
			end
			s += step * (0.75 + r() * 0.5)
		end
		return out
	end
	local function outside(i: number): number
		return if t.curve[i] < 0 then 1 else -1
	end
	return { clearOf = clearOf, along = along, outside = outside }
end

-- A box in a spot's own frame: (lx, ly, lz) from its middle, turned ry.
local function boxAt(into: Instance, x: number, z: number, ry: number, lx: number, ly: number, lz: number, sx: number, sy: number, sz: number, color: string, extra: { [string]: any }?): Part
	local cf = CFrame.new(W(x, 0, z)) * CFrame.Angles(0, ry, 0) * CFrame.new(lx * S, ly * S, lz * S)
	local props: { [string]: any } = { Size = Vector3.new(sx * S, sy * S, sz * S), CFrame = cf, Color = hex(color) }
	for k, v in extra or {} do
		props[k] = v
	end
	return part(props, into)
end

local function cylinderUp(into: Instance, x: number, y: number, z: number, r: number, h: number, color: string): Part
	return part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(h * S, r * 2 * S, r * 2 * S), CFrame = CFrame.new(W(x, y, z)) * CFrame.Angles(0, 0, math.pi / 2), Color = hex(color) }, into)
end

-- The tarmac and everything painted on it or lining it.
local function surface(into: Instance, t: any, th: any)
	local kw = 0.55
	ribbon(into, t, -t.half, t.half, Y_ROAD, 0.3, function()
		return hex("#868c93")
	end, "Road")
	local kerb = function(_i: number, s: number): Color3
		return hex(th.kerb[math.floor(s) % 2 + 1])
	end
	ribbon(into, t, t.half, t.half + kw, Y_KERB, 0.3, kerb, "Kerb")
	ribbon(into, t, -t.half - kw, -t.half, Y_KERB, 0.3, kerb, "Kerb")
	local verge = function(): Color3
		return hex(th.verge)
	end
	ribbon(into, t, t.half + kw, t.wall + 0.3, 0.012, 0.3, verge, "Verge", if t.def.theme == "town" then Enum.Material.Grass else nil)
	ribbon(into, t, -t.wall - 0.3, -t.half - kw, 0.012, 0.3, verge, "Verge", if t.def.theme == "town" then Enum.Material.Grass else nil)
	local white = function(): Color3
		return hex("#f5f5f5")
	end
	ribbon(into, t, t.half - 0.32, t.half - 0.2, Y_PAINT, 0.3, white, "Line")
	ribbon(into, t, -t.half + 0.2, -t.half + 0.32, Y_PAINT, 0.3, white, "Line")
	-- The barrier: a wall with the boards on its face, its back, and the coloured cap.
	local barrier = function(): Color3
		return hex(th.barrier)
	end
	ribbon(into, t, t.wall + 0.03, t.wall + 0.22, 0.64, 0.64, barrier, "Barrier")
	ribbon(into, t, -t.wall - 0.22, -t.wall - 0.03, 0.64, 0.64, barrier, "Barrier")
	local cap = function(): Color3
		return hex(th.cap)
	end
	ribbon(into, t, t.wall - 0.06, t.wall + 0.22, 0.68, 0.04, cap, "Cap")
	ribbon(into, t, -t.wall - 0.22, -t.wall + 0.06, 0.68, 0.04, cap, "Cap")
	boards(into, t, t.wall)
	boards(into, t, -t.wall)
end

-- The chequered line, the six painted grid boxes, and the gantry with its sign and five lights.
-- Returns the lights, left to right.
local function startLine(into: Instance, t: any): { BasePart }
	local h = math.atan2(t.tx[0], t.tz[0])
	local w = t.wall * 2 + 0.6
	local base = CFrame.new(W(t.x[0], 0, t.z[0])) * CFrame.Angles(0, h, 0)
	-- Two rows of squares across the road.
	local cells = math.max(2, math.floor(t.half * 2 / 0.5))
	local cw = t.half * 2 / cells
	for row = 0, 1 do
		for c = 0, cells - 1 do
			part({ Name = "Checker", Size = Vector3.new(cw * S, 0.3, 0.5 * S), CFrame = base * CFrame.new((-t.half + (c + 0.5) * cw) * S, Y_PAINT * S + 0.05 - 0.15, (row - 0.5) * 0.5 * S), Color = if (row + c) % 2 == 0 then hex("#ffffff") else hex("#111111") }, into)
		end
	end
	for k = 0, 5 do
		local row, col = k // 2, if k % 2 == 1 then -1 else 1
		local i = (t.n - 6 - row * 4 + t.n) % t.n
		local off = col * t.half * 0.45 + (if row % 2 == 1 then 0.4 else -0.4)
		local bx, bz, bh = t.x[i] + t.nx[i] * off, t.z[i] + t.nz[i] * off, math.atan2(t.tx[i], t.tz[i])
		for _, l in { { -0.55, 0, 0.08, 1.6 }, { 0.55, 0, 0.08, 1.6 }, { 0, 0.78, 1.18, 0.08 } } do
			part({ Name = "GridBox", Size = Vector3.new(l[3] * S, 0.3, l[4] * S), CFrame = CFrame.new(W(bx, Y_PAINT, bz) - Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, bh, 0) * CFrame.new(l[1] * S, 0, l[2] * S), Color = hex("#fafafa") }, into)
		end
	end
	local gantry = Instance.new("Model")
	gantry.Name = "Gantry"
	gantry.Parent = into
	for _, sd in { -1, 1 } do
		part({ Name = "Post", Size = Vector3.new(0.4, 4.6, 0.4) * S, CFrame = base * CFrame.new(sd * w / 2 * S, 2.3 * S, 0), Color = hex("#37474f") }, gantry)
	end
	part({ Name = "Beam", Size = Vector3.new(w + 0.4, 0.9, 0.5) * S, CFrame = base * CFrame.new(0, 4.4 * S, 0), Color = hex("#263238") }, gantry)
	for _, f in { 1, -1 } do
		local p = part({ Name = "Sign", Size = Vector3.new(w * 0.62, 0.7, 0.02) * S, CFrame = base * CFrame.new(0, 4.4 * S, f * 0.26 * S) * CFrame.Angles(0, if f > 0 then math.pi else 0, 0), Color = hex("#c62828") }, gantry)
		sign(p, "CARTOPIA GRAND PRIX", "#ffffff", "#c62828")
	end
	-- Chequered flags either side of the sign, on the side the karts come from.
	for _, sd in { -1, 1 } do
		for cx = 0, 3 do
			for cy = 0, 1 do
				part({ Name = "Flag", Size = Vector3.new(0.35, 0.35, 0.02) * S, CFrame = base * CFrame.new((sd * (w * 0.31 + 0.9) + (cx - 1.5) * 0.35) * S, (4.4 + (cy - 0.5) * 0.35) * S, -0.27 * S), Color = if (cx + cy) % 2 == 0 then hex("#ffffff") else hex("#111111") }, gantry)
			end
		end
	end
	part({ Name = "LightBox", Size = Vector3.new(3.4, 0.6, 0.3) * S, CFrame = base * CFrame.new(0, 3.6 * S, -0.3 * S), Color = hex("#111111") }, gantry)
	part({ Name = "Hanger", Size = Vector3.new(0.1, 0.5, 0.1) * S, CFrame = base * CFrame.new(w * 0.12 * S, 4.15 * S, -0.3 * S), Color = hex("#111111") }, gantry)
	local lamps = {}
	for i = 0, 4 do
		lamps[i + 1] = part({ Name = `Lamp{i + 1}`, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 0.4, 0.4) * S, CFrame = base * CFrame.new((-1.3 + i * 0.65) * S, 3.6 * S, -0.47 * S) * CFrame.Angles(0, math.pi / 2, 0), Color = hex("#3a1010") }, gantry)
	end
	return lamps
end

-- Boost pads (glowing chevrons) and the jumps.
local function pads(into: Instance, t: any)
	for _, p in t.boosts do
		local cf = CFrame.new(W(p.x, Y_PAINT, p.z)) * CFrame.Angles(0, p.h, 0)
		part({ Name = "BoostPad", Size = Vector3.new(p.w * S, 0.3, p.l * S), CFrame = cf * CFrame.new(0, -0.1, 0), Color = hex("#ff6d00"), Material = Enum.Material.Neon }, into)
		-- Three chevrons pointing the way to go.
		for c = 0, 2 do
			local z = (-p.l / 2 + 0.9 + c * 1.2)
			for _, sd in { -1, 1 } do
				part({ Name = "Chevron", Size = Vector3.new(0.18 * S, 0.3, p.w * 0.55 * S), CFrame = cf * CFrame.new(sd * p.w * 0.2 * S, -0.05, z * S) * CFrame.Angles(0, sd * math.rad(55), 0), Color = hex(if c % 2 == 1 then "#ffe082" else "#fff8e1"), Material = Enum.Material.Neon }, into)
			end
		end
	end
	for _, p in t.ramps do
		local cf = CFrame.new(W(p.x, 0, p.z)) * CFrame.Angles(0, p.h, 0)
		local h = 0.5
		for _, sd in { -1, 1 } do
			local kick = part({ Name = "Ramp", Size = Vector3.new(p.w, 0.06, p.l * 0.4) * S, CFrame = cf * CFrame.new(0, h / 2 * S, sd * p.l * 0.33 * S) * CFrame.Angles(sd * 0.42, 0, 0), Color = hex("#ffd600") }, into)
			-- Black hazard stripes over the yellow.
			for k = 0, math.floor(p.w / 0.8) - 1 do
				part({ Name = "Stripe", Size = Vector3.new(0.3, 0.07, p.l * 0.4) * S, CFrame = kick.CFrame * CFrame.new((-p.w / 2 + 0.4 + k * 0.8) * S, 0.02, 0), Color = hex("#212121") }, into)
			end
		end
		part({ Name = "RampTop", Size = Vector3.new(p.w - 0.02, h - 0.04, p.l * 0.5) * S, CFrame = cf * CFrame.new(0, (h / 2 - 0.02) * S, 0), Color = hex("#455a64") }, into)
		for _, sd in { -1, 1 } do
			part({ Name = "RampRail", Size = Vector3.new(0.12, h + 0.1, p.l * 0.9) * S, CFrame = cf * CFrame.new(sd * (p.w / 2 + 0.06) * S, h / 2 * S, 0), Color = hex("#ffd600") }, into)
		end
	end
end

-- Large flat plates (Roblox parts stop at 2048 studs) covering `size` web units round the middle.
local function plates(into: Instance, size: number, y: number, thick: number, color: string, name: string, material: Enum.Material?)
	local n = math.ceil(size * S / 2000)
	local each = size / n
	for a = 0, n - 1 do
		for b = 0, n - 1 do
			part({ Name = name, Size = Vector3.new(each * S, thick * S, each * S), CFrame = CFrame.new(W(-size / 2 + (a + 0.5) * each, y - thick / 2, -size / 2 + (b + 0.5) * each)), Color = hex(color), Material = material or Enum.Material.SmoothPlastic }, into)
		end
	end
end

-- Grandstands along the start straight and tyre walls on the outside of tight bends (Trackside).
local function trackside(into: Instance, t: any, sp: any)
	for k, pick in { { (t.n - 22) % t.n, 1 }, { 8, -1 }, { (t.n - 40) % t.n, -1 } } do
		local i0, side = pick[1], pick[2]
		local o = side * (t.wall + 2.6)
		local x, z = t.x[i0] + t.nx[i0] * o, t.z[i0] + t.nz[i0] * o
		if not sp.clearOf(x, z, t.wall + 2) then
			continue
		end
		local h = math.atan2(-t.nx[i0] * side, -t.nz[i0] * side)
		local width, rows = 14, 5
		for r = 0, rows - 1 do
			boxAt(into, x, z, h, 0, 0.17 + r * 0.2, -r * 0.7, width, 0.35 + r * 0.4, 0.7, if r % 2 == 1 then "#cfd8dc" else "#b0bec5", { Name = "Stand" })
		end
		local roof = if k % 2 == 0 then "#1565c0" else "#c62828"
		for _, sd in { -1, 1 } do
			boxAt(into, x, z, h, sd * (width / 2 - 0.1), 1.6 + rows * 0.2, -rows * 0.7 + 0.3, 0.12, 3.2 + rows * 0.4, 0.12, "#455a64", { Name = "Post" })
		end
		boxAt(into, x, z, h, 0, 3.3 + rows * 0.4, -rows * 0.35 + 0.2, width + 0.4, 0.15, rows * 0.7 + 0.6, roof, { Name = "Roof" })
		-- The crowd: a fan in a bright top every half a unit or so along each row.
		local rr = rand(41 + k)
		local tops = { "#e53935", "#1e88e5", "#fdd835", "#43a047", "#8e24aa", "#fb8c00", "#ffffff", "#00acc1" }
		for r = 0, rows - 1 do
			for c = 0, math.floor(width / 0.55) - 1 do
				if (c * 7 + r * 3) % 5 == 0 then
					continue
				end
				local lx = -width / 2 + 0.3 + c * 0.55 + (r % 2) * 0.2
				boxAt(into, x, z, h, lx, 0.35 + r * 0.4 + 0.2 + 0.18, -r * 0.7, 0.3, 0.36, 0.22, tops[math.floor(rr() * #tops) + 1], { Name = "Fan" })
			end
		end
	end
	local i = 0
	while i < t.n do
		if math.abs(t.curve[i]) >= 0.07 then
			local sd = sp.outside(i)
			for k, extra in { 0.55, 1.05 } do
				local o = sd * (t.wall + extra)
				local x, z = t.x[i] + t.nx[i] * o, t.z[i] + t.nz[i] * o
				if sp.clearOf(x, z, t.wall + 0.2) then
					cylinderUp(into, x, 0.35, z, 0.3, 0.7, "#1c1c1c").Name = "Tyres"
					cylinderUp(into, x, 0.47, z, 0.31, 0.06, if (i // 3 + k) % 2 == 1 then "#e53935" else "#fafafa").Name = "TyreBand"
				end
			end
		end
		i += 3
	end
end

-- The player's own town round the outside, a park inside, office towers beyond (TownScenery).
local function townScenery(into: Instance, t: any, sp: any, pool: { string })
	local r = rand(17)
	local shops = {}
	local k = 0
	for _, side in { 1, -1 } do
		for _, p in sp.along(6.5, 4.6, side, 4.2, 5 + side) do
			local def = pool[k % #pool + 1]
			k += 1
			local d = data.buildingDef(def)
			if not d or d.w * data.TILE > 6 or d.h * data.TILE > 6 then
				continue
			end
			table.insert(shops, p)
			local b = library("Buildings", def)
			if b then
				b:PivotTo(CFrame.new(W(p.x, 0, p.z)) * CFrame.Angles(0, p.ry, 0))
				b.Parent = into
			end
		end
	end
	local trees = 0
	for _ = 1, 900 do
		if trees >= 150 then
			break
		end
		local x, z = (r() - 0.5) * 160, (r() - 0.5) * 150
		if not sp.clearOf(x, z, t.wall + 2.5) then
			continue
		end
		local near = false
		for _, s in shops do
			if (s.x - x) ^ 2 + (s.z - z) ^ 2 < 20 then
				near = true
				break
			end
		end
		if near then
			continue
		end
		local roll = r()
		local def = if roll < 0.3 then "pine" elseif r() < 0.15 then "bush" else "tree"
		local scale = 0.9 + r() * 0.5
		local tree = library("Buildings", def)
		if tree then
			tree:ScaleTo(scale)
			tree:PivotTo(CFrame.new(W(x, 0, z)) * CFrame.Angles(0, trees, 0))
			tree.Parent = into
		end
		trees += 1
	end
	for i = 0, 27 do
		local a, d = (i / 28) * math.pi * 2 + r() * 0.1, 105 + r() * 25
		local w, h = 6 + r() * 6, 10 + r() * 26
		part({ Name = "Tower", Size = Vector3.new(w, h, w) * S, CFrame = CFrame.new(W(math.cos(a) * d * 1.1, h / 2, math.sin(a) * d)), Color = hex(if i % 3 ~= 0 then "#cfd8dc" else "#b0bec5") }, into)
	end
end

-- A harbour: water inside and out, a concrete quay under the circuit, container stacks, cranes
-- and a lighthouse (DocksScenery).
local function docksScenery(into: Instance, t: any, sp: any)
	plates(into, 500, -0.33, 0.2, "#8fd0f5", "Water", Enum.Material.Glass)
	-- The quay: concrete out past the barriers all the way round.
	ribbon(into, t, -t.wall - 3.5, t.wall + 3.5, 0.0, 0.44, function()
		return hex("#b0b6ba")
	end, "Quay")
	local colors = { "#c62828", "#1565c0", "#2e7d32", "#ef6c00", "#00838f", "#6d4c41" }
	for _, side in { 1, -1 } do
		for _, p in sp.along(4.2, 2.6, side, 2.2, 31 + side, 0.8) do
			if p.r() < 0.25 then
				continue
			end
			local n = 1 + math.floor(p.r() * 3)
			local c = colors[math.floor(p.r() * #colors) + 1]
			for k = 0, n - 1 do
				boxAt(into, p.x, p.z, p.ry + math.pi / 2, 0, 0.6 + k * 1.2, 0, 1.15, 1.2, 2.8, c, { Name = "Container" })
			end
			-- The ground under the stack is quay too.
			boxAt(into, p.x, p.z, p.ry, 0, -0.22, 0, 3.2, 0.44, 3.2, "#b0b6ba", { Name = "Quay" })
		end
	end
	local cranes = sp.along(70, 7, 1, 6, 37)
	for _, c in sp.along(80, 7, -1, 6, 39) do
		table.insert(cranes, c)
	end
	for _, c in cranes do
		boxAt(into, c.x, c.z, c.ry, 0, -0.22, 0.6, 4.6, 0.44, 6.4, "#b0b6ba", { Name = "Pier" })
		for _, dx in { -1.6, 1.6 } do
			for _, dz in { -1.6, 1.6 } do
				boxAt(into, c.x, c.z, c.ry, dx, 4.5, dz, 0.35, 9, 0.35, "#fbc02d", { Name = "Crane" })
			end
		end
		boxAt(into, c.x, c.z, c.ry, 0, 9, 0, 3.6, 0.5, 3.6, "#fbc02d", { Name = "Crane" })
		boxAt(into, c.x, c.z, c.ry, 0, 9.8, 4, 0.7, 0.6, 16, "#fbc02d", { Name = "Crane" })
		boxAt(into, c.x, c.z, c.ry, 0, 10.4, -1, 2, 1.4, 2.4, "#c62828", { Name = "Cab" })
		boxAt(into, c.x, c.z, c.ry, 0, 7.4, 8, 0.05, 4.2, 0.05, "#263238", { Name = "Cable" })
		boxAt(into, c.x, c.z, c.ry, 0, 5.3, 8, 1.3, 0.3, 2.8, "#455a64", { Name = "Spreader" })
	end
	-- The lighthouse on the infield.
	local lx, lz = -20, 10
	cylinderUp(into, lx, 0.5, lz, 2.6, 1, "#9aa3a9").Name = "Lighthouse"
	for i = 0, 4 do
		cylinderUp(into, lx, 1.9 + i * 1.8, lz, 1.15 - i * 0.12, 1.8, if i % 2 == 1 then "#ffffff" else "#c62828").Name = "Lighthouse"
	end
	cylinderUp(into, lx, 10.1, lz, 0.9, 0.2, "#263238").Name = "Lighthouse"
	local lamp = cylinderUp(into, lx, 10.6, lz, 0.55, 0.8, "#fff59d")
	lamp.Material = Enum.Material.Neon
	cylinderUp(into, lx, 11.2, lz, 0.6, 0.4, "#263238").Name = "Lighthouse"
	-- Small boats in the basin.
	for i, b in { { -8, 22, "#c62828" }, { 14, 30, "#1565c0" }, { -30, 18, "#fafafa" }, { 2, 12, "#fbc02d" } } do
		local ry = (i - 1) * 1.7
		boxAt(into, b[1], b[2], ry, 0, 0.2 - 0.3, 0, 1.3, 0.5, 3.4, b[3], { Name = "Boat" })
		boxAt(into, b[1], b[2], ry, 0, 0.48 - 0.3, 0.2, 1.1, 0.06, 2.6, "#d7ccc8", { Name = "Boat" })
		boxAt(into, b[1], b[2], ry, 0, 0.85 - 0.3, -0.3, 0.9, 0.7, 1.1, "#eceff1", { Name = "Boat" })
	end
end

-- Red rock canyon: banded mesas and spires, saguaros and an old water tower (DesertScenery).
local function desertScenery(into: Instance, t: any, sp: any)
	local r = rand(53)
	local strata = { "#b5532f", "#c8693a", "#a84a2a", "#d4844e" }
	local mesas = {}
	for _ = 1, 700 do
		if #mesas >= 60 then
			break
		end
		local x, z = (r() - 0.5) * 220, (r() - 0.5) * 200
		local w = 5 + r() * 9
		if not sp.clearOf(x, z, t.wall + w * 0.8 + 3) then
			continue
		end
		local close = false
		for _, m in mesas do
			if (m.x - x) ^ 2 + (m.z - z) ^ 2 < (w + m.w) ^ 2 * 0.35 then
				close = true
				break
			end
		end
		if close then
			continue
		end
		local m = { x = x, z = z, w = w, d = 4 + r() * 8, h = 3 + r() * 10, ry = r() * 3, spire = r() < 0.25 }
		table.insert(mesas, m)
		if m.spire then
			boxAt(into, x, z, m.ry, 0, m.h * 0.35, 0, m.w * 0.35, m.h * 0.7, m.d * 0.35, strata[1], { Name = "Mesa" })
			boxAt(into, x, z, m.ry, 0, m.h * 0.85, 0, m.w * 0.24, m.h * 0.3, m.d * 0.24, strata[2], { Name = "Mesa" })
			boxAt(into, x, z, m.ry, 0, m.h + 0.12, 0, m.w * 0.3, 0.25, m.d * 0.3, strata[4], { Name = "Mesa" })
		else
			boxAt(into, x, z, m.ry, 0, m.h * 0.2, 0, m.w * 1.08, m.h * 0.4, m.d * 1.08, strata[1], { Name = "Mesa" })
			boxAt(into, x, z, m.ry, 0, m.h * 0.52, 0, m.w, m.h * 0.26, m.d, strata[2], { Name = "Mesa" })
			boxAt(into, x, z, m.ry, 0, m.h * 0.78, 0, m.w * 0.94, m.h * 0.28, m.d * 0.94, strata[3], { Name = "Mesa" })
			boxAt(into, x, z, m.ry, 0, m.h + 0.15, 0, m.w * 0.98, 0.3, m.d * 0.98, strata[4], { Name = "Mesa" })
		end
	end
	for _, side in { 1, -1 } do
		for _, p in sp.along(5, 1.2, side, 1, if side > 0 then 71 else 73, 5) do
			local h, arm = 1.4 + p.r() * 1.2, p.r()
			cylinderUp(into, p.x, h / 2, p.z, 0.14, h, "#4f8a3a").Name = "Saguaro"
			for _, sd in { 1, -1 } do
				if (sd > 0 and arm > 0.25) or (sd < 0 and arm > 0.6) then
					local ax, az = p.x + math.cos(p.ry) * sd * 0.34, p.z - math.sin(p.ry) * sd * 0.34
					cylinderUp(into, ax, h * 0.6, az, 0.085, h * 0.32, "#4f8a3a").Name = "Saguaro"
					boxAt(into, p.x, p.z, p.ry, sd * 0.22, h * 0.45, 0, 0.26, 0.15, 0.15, "#4f8a3a", { Name = "Saguaro" })
				end
			end
		end
	end
	for _, dx in { -0.9, 0.9 } do
		for _, dz in { -0.9, 0.9 } do
			boxAt(into, 2, 2, 0, dx, 2.2, dz, 0.14, 4.4, 0.14, "#6d4c41", { Name = "WaterTower" })
		end
	end
	cylinderUp(into, 2, 5.2, 2, 1.5, 1.8, "#8d6e63").Name = "WaterTower"
	cylinderUp(into, 2, 6.3, 2, 1.2, 0.5, "#6d4c41").Name = "WaterTower"
end

-- The far ridges all the way round (KartHorizon): columns of hill, foot to crest, hazed toward
-- the sky's colour.
local function horizon(into: Instance, theme: string)
	local haze = hex(KartWorld.FOG)
	for _, g in RIDGES[theme] do
		local r = rand(g.seed)
		local waves = {}
		local sum = 0
		for _, f in { 1, 2, 3, 5, 8, 13 } do
			local w = { f = f, p = r() * math.pi * 2, a = 1 / math.sqrt(f) }
			table.insert(waves, w)
			sum += w.a
		end
		local base, top = hex(g.base):Lerp(haze, g.haze), hex(g.top):Lerp(haze, g.haze)
		local snow = hex("#f4f7fb"):Lerp(haze, g.haze * 0.8)
		local N = 90
		for i = 0, N - 1 do
			local a = (i + 0.5) / N * math.pi * 2
			local v = 0
			for _, w in waves do
				v += math.sin(a * w.f + w.p) * w.a
			end
			local h = g.lo + (g.hi - g.lo) * (0.5 + (v / sum) * 0.9)
			if g.steps then
				h = math.floor(h / g.steps + 0.5) * g.steps
			end
			local d = g.r + g.depth / 2
			local wid = 2 * math.pi * (g.r + g.depth) / N * 1.08
			local cf = CFrame.new(W(math.cos(a) * d, 0, math.sin(a) * d)) * CFrame.Angles(0, -a + math.pi / 2, 0)
			part({ Name = "Ridge", Size = Vector3.new(wid * S, (h * 0.6) * S, g.depth * S), CFrame = cf * CFrame.new(0, h * 0.3 * S - S, 0), Color = base }, into)
			part({ Name = "Ridge", Size = Vector3.new(wid * S, (h * 0.42) * S, g.depth * 0.6 * S), CFrame = cf * CFrame.new(0, h * 0.79 * S - S, g.depth * 0.15 * S), Color = if g.snow and h > g.snow then snow else top }, into)
		end
	end
end

-- ── The circuit, built once per track and kept ─────────────────────────────────────────────────
local built: Model? = nil
local builtKey = ""
local builtLamps: { BasePart } = {}

-- The circuit for a track (from K.buildTrack); pool: the shop ids to line a town circuit with.
-- Returns the model and its five start lamps.
function KartWorld.circuit(t: any, pool: { string }?): (Model, { BasePart })
	local key = `{t.def.id}:{t.reverse}`
	if built and builtKey == key and built.Parent then
		return built, builtLamps
	end
	if built then
		built:Destroy()
	end
	local th = THEMES[t.def.theme] or THEMES.town
	local m = Instance.new("Model")
	m.Name = "KartCircuit"
	local sp = spots(t)
	if t.def.theme ~= "docks" then
		plates(m, 460, -0.01, 0.2, th.ground, "Ground", if t.def.theme == "town" then Enum.Material.Grass elseif t.def.theme == "desert" then Enum.Material.Sand else nil)
	end
	surface(m, t, th)
	local lamps = startLine(m, t)
	pads(m, t)
	trackside(m, t, sp)
	if t.def.theme == "town" then
		townScenery(m, t, sp, if pool and #pool > 0 then pool else FALLBACK)
	elseif t.def.theme == "docks" then
		docksScenery(m, t, sp)
	else
		desertScenery(m, t, sp)
	end
	horizon(m, t.def.theme)
	m.Parent = workspace
	built, builtKey, builtLamps = m, key, lamps
	return m, lamps
end

-- ── Karts ──────────────────────────────────────────────────────────────────────────────────────

export type KartView = {
	model: Model,
	-- The car's own pivot, relative to the kart's centre on the road.
	offset: CFrame,
	parts: { BasePart },
	fx: { [string]: BasePart },
	ghosted: boolean,
}

-- A racer's car at kart size (KART_LEN long), dressed as on the web (KartView: CarModel with its
-- paint, panels, trim, hat, mods and skin), with its effects: the boost flame, drift sparks, the
-- bubble shield, the static cage, the phantom shroud and the rocket.
function KartWorld.kart(look: any, parent: Instance): KartView
	local m = library("Cars", look.model) or Instance.new("Model")
	Paint.apply(m, Paint.jobOf(look), library("Stripes", look.model))
	pcall(function()
		Panels.apply(m, look.model, look.panels, look.finish, Builder.build)
		Trim.apply(m, look.model, look.trim, look.color)
		Paint.wearHat(m, look.model, look.hat, Builder.build)
		Mods.fit(m, look.model, look.mods, Builder.build)
		Skins.apply(m, look.skin, look.modSkin)
	end)
	-- Scaled about its own pivot so it's a kart's length nose to tail.
	local pivot = m:GetPivot()
	local cf, size = m:GetBoundingBox()
	local long = math.max(size.Z, 1)
	local k = K.KART_LEN * S / long
	local parts = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d.Size *= k
			d.CFrame = pivot * (rel - rel.Position + rel.Position * k)
			d.CastShadow = false
			table.insert(parts, d)
		end
	end
	-- Centred on the road under the middle of the car.
	local mid = pivot:ToObjectSpace(cf).Position * k
	local bottom = (pivot:ToObjectSpace(cf).Position.Y - size.Y / 2) * k
	local offset = CFrame.new(-mid.X, -bottom, -mid.Z)
	m.Parent = parent
	local fx: { [string]: BasePart } = {}
	local function fxPart(name: string, props: { [string]: any }): BasePart
		props.Name = name
		props.Transparency = 1
		local p = part(props, parent)
		fx[name] = p
		return p
	end
	fxPart("flame", { Shape = Enum.PartType.Ball, Size = Vector3.new(0.36, 0.36, 0.36) * S, Color = hex("#ffab40"), Material = Enum.Material.Neon })
	fxPart("sparkL", { Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3) * S, Color = hex("#40c4ff"), Material = Enum.Material.Neon })
	fxPart("sparkR", { Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3) * S, Color = hex("#40c4ff"), Material = Enum.Material.Neon })
	fxPart("shield", { Shape = Enum.PartType.Ball, Size = Vector3.new(2.5, 2.5, 2.5) * S, Color = hex("#80d8ff"), Material = Enum.Material.Glass })
	fxPart("zap", { Shape = Enum.PartType.Ball, Size = Vector3.new(2.3, 2.3, 2.3) * S, Color = hex("#b388ff"), Material = Enum.Material.ForceField })
	fxPart("ghost", { Shape = Enum.PartType.Ball, Size = Vector3.new(2.5, 1.9, 3.4) * S, Color = hex("#b388ff"), Material = Enum.Material.Neon })
	fxPart("rocket", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.5, 0.52, 0.52) * S, Color = hex("#e53935") })
	fxPart("rocketFlame", { Shape = Enum.PartType.Ball, Size = Vector3.new(0.42, 0.42, 0.42) * S, Color = hex("#ffca28"), Material = Enum.Material.Neon })
	fxPart("magnet", { Size = Vector3.new(0.6, 0.25, 0.3) * S, Color = hex("#e53935") })
	fxPart("splat", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, 0.9, 0.9) * S, Color = hex("#ff4081") })
	return { model = m, offset = offset, parts = parts, fx = fx, ghosted = false }
end

-- ── What a race puts on the road ──────────────────────────────────────────────────────────────

-- The prize crates: glowing boxes that bob and turn, gone for three seconds after a pick-up.
function KartWorld.crates(t: any, parent: Instance): { BasePart }
	local out = {}
	for i, c in t.crates do
		out[i] = part({ Name = "Crate", Size = Vector3.new(0.62, 0.62, 0.62) * S, CFrame = CFrame.new(W(c.x, 0.75, c.z)), Color = hex("#9c4dff"), Material = Enum.Material.Neon, Transparency = 0.08 }, parent)
	end
	return out
end

-- The road's obstacles (game/obstacles.ts): a pile of boxes, a pothole, an ice patch, and two
-- workers carrying a pane of glass across the road. Returns each glass crossing's moving parts.
function KartWorld.obstacles(race: any, parent: Instance): { any }
	local t = race.track
	local glass = {}
	for oi, o in race.obstacles do
		local cf = CFrame.new(W(o.x, 0, o.z)) * CFrame.Angles(0, o.h, 0)
		if o.kind == "boxes" then
			for j, b in { { -0.82, 0.35, 0, 0.7 }, { -0.45, 0.35, 0.15, 0.7 }, { -0.1, 0.32, -0.1, 0.62 }, { 0.25, 0.35, 0.05, 0.7 }, { 0.6, 0.32, -0.05, 0.62 }, { 0.88, 0.3, 0.1, 0.58 }, { -0.62, 0.95, 0.05, 0.55 }, { 0.05, 0.92, 0, 0.5 }, { 0.42, 0.95, 0.02, 0.55 }, { -0.2, 1.42, 0, 0.42 } } do
				part({ Name = "Box", Size = Vector3.new(b[4], b[4], b[4]) * S, CFrame = cf * CFrame.new(b[1] * o.w / 2 * S, b[2] * S, b[3] * S) * CFrame.Angles(0, (j - 1) * 0.4, 0), Color = hex(if j % 2 == 0 then "#c8a165" else "#b98b4e") }, parent)
			end
		elseif o.kind == "pothole" then
			part({ Name = "Pothole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, o.w * S, o.w * S), CFrame = CFrame.new(W(o.x, Y_PAINT, o.z) - Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#26221f") }, parent)
		elseif o.kind == "ice" then
			part({ Name = "Ice", Size = Vector3.new(o.w * S, 0.3, o.l * S), CFrame = cf * CFrame.new(0, Y_PAINT * S - 0.08, 0), Color = hex("#cdeffd"), Transparency = 0.25, Material = Enum.Material.Ice }, parent)
		else
			-- The workers walk across the road, so the crossing faces across it.
			local across = math.atan2(t.nx[o.i], t.nz[o.i])
			local bits = {}
			for _, z in { -1.1, 1.1 } do
				table.insert(bits, { p = part({ Name = "Worker", Size = Vector3.new(0.36, 0.96, 0.36) * S, Color = hex("#ff9800") }, parent), at = CFrame.new(0, 0.55 * S, z * S) })
				table.insert(bits, { p = part({ Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.new(0.32, 0.32, 0.32) * S, Color = hex("#f1c27d") }, parent), at = CFrame.new(0, 1.1 * S, z * S) })
				table.insert(bits, { p = part({ Name = "Hat", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.4, 0.4) * S, Color = hex("#fdd835") }, parent), at = CFrame.new(0, 1.27 * S, z * S) * CFrame.Angles(0, 0, math.pi / 2) })
			end
			local pane = part({ Name = "Pane", Size = Vector3.new(0.04, 1.2, obstacles.GLASS_W) * S, Color = hex("#b3e5fc"), Transparency = 0.55, Material = Enum.Material.Glass }, parent)
			local shards = {}
			for j = 1, 9 do
				shards[j] = part({ Name = "Shard", Size = Vector3.new(0.22, 0.04, 0.16) * S, Color = hex("#e1f5fe"), Transparency = 1 }, parent)
			end
			glass[oi] = { o = o, across = across, bits = bits, pane = pane, shards = shards }
		end
	end
	return glass
end

-- Moves each glass crossing to where its workers are now (obstacles.glassAt), the pane shattered
-- if a kart has hit it this crossing.
function KartWorld.moveGlass(race: any, glass: { any })
	local t = race.track
	for oi, g in glass do
		local at = obstacles.glassAt(g.o, race.t)
		local shown = at ~= nil
		local broke = shown and race.glassBroke[oi] == at.cycle
		local cf = if at then CFrame.new(W(g.o.x + t.nx[g.o.i] * at.across, 0, g.o.z + t.nz[g.o.i] * at.across)) * CFrame.Angles(0, g.across, 0) else CFrame.new(0, -1e4, 0)
		for _, b in g.bits do
			b.p.CFrame = cf * b.at
			b.p.Transparency = if shown then 0 else 1
		end
		g.pane.CFrame = cf * CFrame.new(0, 0.85 * S, 0)
		g.pane.Transparency = if shown and not broke then 0.55 else 1
		for j, sh in g.shards do
			sh.Transparency = if broke then 0.3 else 1
			if broke then
				sh.CFrame = cf * CFrame.new(math.sin(j * 2.1) * 0.8 * S, 0.06 * S, math.cos(j * 1.3) * 0.4 * S) * CFrame.Angles(j * 0.7, j, 0)
			end
		end
	end
end

-- A pool of hazard parts made as needed: oil slicks, tack strips, smoke puffs, hornets, bombs
-- and their blasts, tow beams and traffic cones.
function KartWorld.pool(parent: Instance, make: () -> BasePart): (number) -> BasePart
	local list: { BasePart } = {}
	return function(i: number): BasePart
		local p = list[i]
		if not p then
			p = make()
			p.Parent = parent
			list[i] = p
		end
		return p
	end
end

return KartWorld
