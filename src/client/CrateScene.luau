--!strict
-- The Crate Depot in 3D, as the web game's CrateScene (scene/CrateScene.tsx): a warehouse loading
-- bay at night where crates are opened. The crate sits on a hazard-striped lift under a work lamp,
-- racking full of stock either side, a forklift parked up, the roller door half open to the street
-- and the depot's neon sign on the back wall.
--
-- The depot is built once, far above the town, and the camera is taken there while the Crates tab
-- is up (CrateScene.enter / leave). Every crate drops onto the lift, shakes while the server rolls,
-- strains and bursts its own way (Street pops its lid off, Garage's sides roll down like shutters,
-- Gold swings its lid back like a chest and Diamond shatters), throws confetti and a shower of
-- coins or gems, and its prize rises out of it on a beam while the camera pushes in. The numbers
-- (timings, sizes, how each crate bursts) are the web's; one web metre is K studs here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local data = require(Game.data) :: any
local crates = require(Game.crates) :: any
local Skins = require(Shared:WaitForChild("Models"):WaitForChild("Skins"))
local Thumb = require(script.Parent.Thumb)
local TownCamera = require(script.Parent.TownCamera)
local DayNight = require(script.Parent.DayNight)
local Sfx = require(script.Parent.Sounds.Sfx)

local CrateScene = {}

-- Studs per web metre, and where the depot stands: high over the town, so nothing of the town is
-- in view and the town's own lights don't reach it.
local K = 4
local ORIGIN = Vector3.new(0, 2600, 0)
-- Where parts go while they're hidden: under the depot's floor.
local HIDE = CFrame.new(ORIGIN - Vector3.new(0, 60, 0))

-- Crate size (metres) and where its floor sits on the lift.
local S = 1.5
local LIFT = 0.14
-- Opening timeline (seconds from the tap): `drop` is how long the crate takes to land, `charge` how
-- long it strains before it bursts, `rise` when the prize starts up out of it after the burst and
-- `lift` how long it takes to come up, `settle` when the prize is shown (from the tap) and `hops`
-- when it jumps as it strains. A single open takes its time; the ×10 run opens the first nine
-- quickly and the last one in full.
export type Pace = "full" | "quick" | "show"
local PACE = {
	full = { drop = 0.55, charge = 1.15, rise = 0.25, lift = 0.9, settle = 2.35, hops = { 0.35, 0.68, 0.95 } },
	quick = { drop = 0.28, charge = 0.36, rise = 0.04, lift = 0.5, settle = 0.86, hops = {} :: { number } },
}
-- How long the crate's bounce lasts once it lands on the lift.
local BOUNCE = 0.35

-- How exciting a prize is, as a glow colour: coins, a part or jackpot, a gem part, a car.
CrateScene.TIER_GLOW = { "#4fc3f7", "#b388ff", "#ff4fd8", "#ffb300" }

-- How each crate bursts open (see the top), which sides end up lying open on the floor (front,
-- back, left, right: coins land on those) and how big each style's moment is.
local OPEN_STYLE = { street = "pop", garage = "roll", gold = "chest", diamond = "shatter" }
local ALL_FLAPS = { true, true, true, true }
local NO_FLAPS = { false, false, false, false }
local FLAPS = { pop = ALL_FLAPS, roll = NO_FLAPS, chest = { true, false, true, true }, shatter = NO_FLAPS }
local DRAMA = {
	pop = { confetti = 0.45, flash = 35, kick = 0.05, push = 0.25, orbit = 0, beam = 0.85 },
	roll = { confetti = 0.65, flash = 45, kick = 0.06, push = 0.3, orbit = 0, beam = 1 },
	chest = { confetti = 1, flash = 90, kick = 0.08, push = 0.35, orbit = 0, beam = 1.3 },
	shatter = { confetti = 1, flash = 120, kick = 0.15, push = 0.45, orbit = 0.25, beam = 1.4 },
}
-- Each crate's boards wear one of the car skins, livelier the rarer the crate (the web's CRATE_SKIN).
local CRATE_SKIN: { [string]: { any } } = { street = { "hexcore", false }, garage = { "overclock", false }, gold = { "goldleaf", true }, diamond = { "prismatic", false } }

local function hex(c: string): Color3
	return Color3.fromHex(c)
end
local function P(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z) * K
end
local function CF(x: number, y: number, z: number): CFrame
	return CFrame.new(x * K, y * K, z * K)
end
-- Roblox's cylinders lie along X; the web's stand along Y.
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

local function rng(seed: number): () -> number
	local s = seed % 2147483647
	if s == 0 then
		s = 1
	end
	return function()
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

-- ── Parts ────────────────────────────────────────────────────────────────────────────────────────

type Look = { color: string?, material: Enum.Material?, transparency: number?, shadow: boolean?, shape: string?, reflect: number? }

-- A part of size `size` (metres) at `cf` (studs), anchored and out of the way of everything else.
local function part(parent: Instance, size: Vector3, cf: CFrame, look: Look): BasePart
	local p: BasePart
	if look.shape == "Wedge" then
		p = Instance.new("WedgePart")
	else
		local q = Instance.new("Part")
		if look.shape == "Cylinder" then
			q.Shape = Enum.PartType.Cylinder
		elseif look.shape == "Ball" then
			q.Shape = Enum.PartType.Ball
		end
		p = q
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = look.shadow ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(math.max(0.05, size.X * K), math.max(0.05, size.Y * K), math.max(0.05, size.Z * K))
	p.CFrame = cf
	p.Color = hex(look.color or "#ffffff")
	p.Material = look.material or Enum.Material.SmoothPlastic
	p.Transparency = look.transparency or 0
	p.Reflectance = look.reflect or 0
	p.Parent = parent
	return p
end

-- Moves many parts at once (BulkMoveTo where there is one).
local function moveAll(parts: { BasePart }, cfs: { CFrame })
	if #parts == 0 then
		return
	end
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in parts do
			p.CFrame = cfs[i]
		end
	end
end

-- A little scene graph for the parts that move together (the crate, its panels and lid, the
-- prize): each node has a frame (studs, relative to its parent) and a scale its parts grow and
-- shrink by, as the web's three.js groups do.
type Item = { part: BasePart, off: CFrame, size: Vector3, shown: Vector3? }
type Node = { cf: CFrame, scale: Vector3, visible: boolean, items: { Item }, kids: { Node } }

local function node(parent: Node?, cf: CFrame?): Node
	local n: Node = { cf = cf or CFrame.identity, scale = Vector3.one, visible = true, items = {}, kids = {} }
	if parent then
		table.insert(parent.kids, n)
	end
	return n
end

-- Adds a part to a node at `off` (studs, in the node's frame).
local function put(n: Node, p: BasePart, off: CFrame): BasePart
	table.insert(n.items, { part = p, off = off, size = p.Size })
	return p
end

-- A block on a node: size and position in metres, an optional turn about Z (the web's rotation-z).
local function block(folder: Instance, n: Node, w: number, h: number, d: number, x: number, y: number, z: number, look: Look, rot: CFrame?): BasePart
	local off = CF(x, y, z) * (rot or CFrame.identity)
	return put(n, part(folder, Vector3.new(w, h, d), off, look), off)
end

-- An upright cylinder (radius r, height h) on a node.
local function cyl(folder: Instance, n: Node, r: number, h: number, x: number, y: number, z: number, look: Look, rot: CFrame?): BasePart
	local off = CF(x, y, z) * (rot or CFrame.identity) * UPRIGHT
	local l = table.clone(look)
	l.shape = "Cylinder"
	return put(n, part(folder, Vector3.new(h, r * 2, r * 2), off, l), off)
end

-- Where every part of a node (and its children) goes, given the node's parent frame and scale.
local function flush(n: Node, at: CFrame, scale: Vector3, show: boolean, parts: { BasePart }, cfs: { CFrame })
	local here = at * CFrame.new(n.cf.Position * scale) * n.cf.Rotation
	local sc = scale * n.scale
	local vis = show and n.visible
	for _, it in n.items do
		table.insert(parts, it.part)
		if not vis then
			table.insert(cfs, HIDE)
			continue
		end
		local off = CFrame.new(it.off.Position * sc) * it.off.Rotation
		table.insert(cfs, here * off)
		local want = if sc == Vector3.one then it.size else Vector3.new(math.max(0.05, it.size.X * sc.X), math.max(0.05, it.size.Y * sc.Y), math.max(0.05, it.size.Z * sc.Z))
		if it.shown ~= want then
			it.shown = want
			it.part.Size = want
		end
	end
	for _, k in n.kids do
		flush(k, here, sc, vis, parts, cfs)
	end
end

local function place(root: Node, at: CFrame)
	local parts, cfs = {}, {}
	flush(root, at, Vector3.one, true, parts, cfs)
	moveAll(parts, cfs)
end

local function light(class: string, parent: BasePart, props: { [string]: any }): Light
	local l = Instance.new(class) :: Light
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

-- A sign on the front of a part: text in a colour on a background.
local function sign(p: BasePart, text: string, fg: string, bg: string, font: Enum.Font, face: Enum.NormalId?)
	local g = Instance.new("SurfaceGui")
	g.Face = face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.Brightness = 1.4
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = hex(bg)
	t.BackgroundTransparency = 0
	t.BorderSizePixel = 0
	t.Text = text
	t.TextColor3 = hex(fg)
	t.TextScaled = true
	t.Font = font
	t.Parent = g
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = t
	g.Parent = p
end

-- A ring of short blocks lying on the floor (the web's ring and hazard-ring textures):
-- `n` pieces between radii r1 and r2 at height y, alternating colours when two are given.
local function ring(folder: Instance, n: Node, r1: number, r2: number, y: number, count: number, colors: { string }, look: Look?)
	local r = (r1 + r2) / 2
	local seg = 2 * math.pi * r / count
	for i = 0, count - 1 do
		local a = (i + 0.5) / count * math.pi * 2
		local l: Look = table.clone(look or {})
		l.color = colors[(i % #colors) + 1]
		l.shadow = false
		local off = CFrame.new(P(math.cos(a) * r, y, math.sin(a) * r)) * CFrame.Angles(0, -a, 0)
		put(n, part(folder, Vector3.new(r2 - r1, 0.012, seg * 1.04), off, l), off)
	end
end

-- ── The depot ────────────────────────────────────────────────────────────────────────────────────

local function Racking(folder: Instance, x: number, flip: boolean, seed: number)
	local r = rng(seed)
	local at = CFrame.new(ORIGIN)
	local function box(size: Vector3, pos: Vector3, look: Look)
		part(folder, size, at * CFrame.new(pos * K), look)
	end
	-- Orange uprights and blue beams, like real pallet racking.
	for _, z in { -5.8, -3.6, -1.4, 0.8 } do
		for _, dx in { -0.55, 0.55 } do
			box(Vector3.new(0.09, 4.8, 0.09), Vector3.new(x + dx, 2.4, z), { color = "#ff6d00", material = Enum.Material.Metal })
		end
	end
	for _, y in { 0.12, 1.67, 3.22 } do
		for _, dx in { -0.55, 0.55 } do
			box(Vector3.new(0.07, 0.14, 6.7), Vector3.new(x + dx, y, -2.5), { color = "#1565c0", material = Enum.Material.Metal })
		end
		box(Vector3.new(1.1, 0.03, 6.6), Vector3.new(x, y + 0.08, -2.5), { color = "#8d6e63", material = Enum.Material.WoodPlanks })
	end
	for level = 0, 2 do
		for bay = 0, 2 do
			local z = -5.8 + bay * 2.2 + 0.1
			while z < -5.8 + bay * 2.2 + 1.9 do
				local w = 0.5 + r() * 0.5
				local h = 0.4 + r() * 0.55
				local wood = r() > 0.45
				local c = if wood then ({ "#b7844f", "#a1703f", "#c79a64" })[math.floor(r() * 3) + 1] else ({ "#c9a46b", "#b8915a", "#d7b98a", "#2e7d4f" })[math.floor(r() * 4) + 1]
				local px = x + (if flip then -1 else 1) * (0.1 + r() * 0.1)
				box(Vector3.new(0.8 + r() * 0.2, h, w), Vector3.new(px, 0.18 + level * 1.55 + h / 2, z + w / 2), { color = c, material = if wood then Enum.Material.Wood else Enum.Material.Cardboard })
				z += w + 0.06
			end
		end
	end
end

local function Forklift(folder: Instance, x: number, z: number, ry: number)
	local at = CFrame.new(ORIGIN + P(x, 0, z)) * CFrame.Angles(0, ry, 0)
	local function box(w: number, h: number, d: number, px: number, py: number, pz: number, look: Look)
		part(folder, Vector3.new(w, h, d), at * CF(px, py, pz), look)
	end
	local yellow: Look = { color = "#ffb300", material = Enum.Material.SmoothPlastic }
	box(1.1, 0.7, 1.6, 0, 0.55, 0, yellow)
	box(1.05, 0.62, 0.4, 0, 0.62, -0.75, { color = "#37474f" })
	box(0.55, 0.12, 0.5, 0, 1.02, -0.05, { color = "#212121" })
	box(0.55, 0.5, 0.1, 0, 1.3, -0.3, { color = "#212121" })
	-- Overhead guard.
	for _, dx in { -0.48, 0.48 } do
		for _, dz in { -0.55, 0.4 } do
			box(0.06, 1.3, 0.06, dx, 1.55, dz, { color = "#263238" })
		end
	end
	box(1.02, 0.05, 1.05, 0, 2.2, -0.08, { color = "#263238" })
	-- Mast and forks.
	for _, dx in { -0.32, 0.32 } do
		box(0.1, 2.5, 0.1, dx, 1.35, 0.88, { color = "#455a64", material = Enum.Material.Metal })
	end
	box(0.8, 0.4, 0.06, 0, 0.35, 0.95, { color = "#455a64", material = Enum.Material.Metal })
	for _, dx in { -0.25, 0.25 } do
		box(0.12, 0.05, 1.0, dx, 0.17, 1.45, { color = "#546e7a", material = Enum.Material.Metal })
	end
	for _, w in { { -0.5, 0.5 }, { 0.5, 0.5 }, { -0.5, -0.55 }, { 0.5, -0.55 } } do
		part(folder, Vector3.new(0.2, 0.48, 0.48), at * CF(w[1], 0.24, w[2]), { color = "#1c1c1c", shape = "Cylinder" })
	end
	local beacon = part(folder, Vector3.new(0.08, 0.14, 0.14), at * CF(0.3, 2.28, -0.4) * UPRIGHT, { color = "#ff9100", material = Enum.Material.Neon, shape = "Cylinder", shadow = false })
	light("PointLight", beacon, { Color = hex("#ff6d00"), Brightness = 1.5, Range = 6 })
end

local function Drum(folder: Instance, x: number, z: number, color: string)
	local at = CFrame.new(ORIGIN + P(x, 0, z))
	part(folder, Vector3.new(0.9, 0.6, 0.6), at * CF(0, 0.45, 0) * UPRIGHT, { color = color, shape = "Cylinder", material = Enum.Material.Metal })
	for _, y in { 0.15, 0.45, 0.75 } do
		part(folder, Vector3.new(0.03, 0.63, 0.63), at * CF(0, y, 0) * UPRIGHT, { color = color, shape = "Cylinder", material = Enum.Material.Metal })
	end
	part(folder, Vector3.new(0.02, 0.08, 0.08), at * CF(0.12, 0.905, 0.05) * UPRIGHT, { color = "#9e9e9e", shape = "Cylinder", material = Enum.Material.Metal })
end

local function Pallet(folder: Instance, x: number, z: number, ry: number, stack: number)
	local at = CFrame.new(ORIGIN + P(x, 0, z)) * CFrame.Angles(0, ry, 0)
	for k = 0, stack - 1 do
		for _, dz in { -0.45, 0, 0.45 } do
			part(folder, Vector3.new(1.2, 0.09, 0.1), at * CF(0, 0.05 + k * 0.15, dz), { color = "#a1887f", material = Enum.Material.Wood })
		end
		for _, dx in { -0.5, -0.25, 0, 0.25, 0.5 } do
			part(folder, Vector3.new(0.18, 0.025, 1.0), at * CF(dx, 0.12 + k * 0.15, 0), { color = "#bcaaa4", material = Enum.Material.Wood })
		end
	end
end

local function TyreStack(folder: Instance, x: number, z: number, count: number, band: string)
	for i = 0, count - 1 do
		local at = CFrame.new(ORIGIN + P(x, i * 0.235 + 0.11, z))
		part(folder, Vector3.new(0.22, 0.6, 0.6), at * UPRIGHT, { color = "#1c1c1c", shape = "Cylinder" })
		part(folder, Vector3.new(0.23, 0.33, 0.33), at * UPRIGHT, { color = "#9e9e9e", shape = "Cylinder", material = Enum.Material.Metal })
		part(folder, Vector3.new(0.225, 0.47, 0.47), at * UPRIGHT, { color = band, shape = "Cylinder", transparency = 0.6, shadow = false })
	end
end

local function ToolChest(folder: Instance, x: number, z: number, ry: number)
	local at = CFrame.new(ORIGIN + P(x, 0, z)) * CFrame.Angles(0, ry, 0)
	part(folder, Vector3.new(0.9, 0.85, 0.45), at * CF(0, 0.5, 0), { color = "#c62828", material = Enum.Material.Metal })
	for i = 0, 4 do
		part(folder, Vector3.new(0.8, 0.02, 0.02), at * CF(0, 0.2 + i * 0.15, 0.235), { color = "#eceff1", material = Enum.Material.Metal })
	end
	for _, dx in { -0.35, 0.35 } do
		part(folder, Vector3.new(0.06, 0.1, 0.1), at * CF(dx, 0.05, 0.12) * UPRIGHT, { color = "#212121", shape = "Cylinder" })
	end
end

-- An industrial lamp hanging on a chain: a dark shade and a hot bulb, lighting what's under it.
local function HangingLamp(folder: Instance, x: number, z: number, y: number)
	local at = CFrame.new(ORIGIN + P(x, y, z))
	part(folder, Vector3.new(0.024, 2.8, 0.024), at * CF(0, 1.4, 0), { color = "#263238" })
	part(folder, Vector3.new(0.32, 0.84, 0.84), at * UPRIGHT, { color = "#2e3b43", shape = "Cylinder", material = Enum.Material.Metal })
	local bulb = part(folder, Vector3.new(0.2, 0.2, 0.2), at * CF(0, -0.18, 0), { color = "#fff8e1", material = Enum.Material.Neon, shape = "Ball", shadow = false })
	light("SpotLight", bulb, { Face = Enum.NormalId.Bottom, Color = hex("#ffd18a"), Brightness = 0.6, Range = 30, Angle = 70 })
end

-- The building: concrete floor with its walkways, the lift and its hazard ring, the corrugated
-- walls, the roller door, the neon sign and the stock.
local function Depot(folder: Instance)
	local at = CFrame.new(ORIGIN)
	local function box(w: number, h: number, d: number, x: number, y: number, z: number, look: Look): BasePart
		return part(folder, Vector3.new(w, h, d), at * CF(x, y, z), look)
	end
	-- Floor (a thick slab, so nothing under it shows) and the yellow walkway lines.
	box(36, 2, 26, 0, -1, 5.5, { color = "#9aa3a8", material = Enum.Material.Concrete })
	for _, x in { -2.6, 2.6 } do
		box(0.12, 0.01, 22, x, 0.005, 0, { color = "#ffd600", shadow = false })
	end
	local floor = node(nil)
	ring(folder, floor, 1.75, 1.95, 0.007, 48, { "#ffc400", "#1b1b1b" })
	-- The lift the crate stands on.
	cyl(folder, floor, 1.5, LIFT, 0, LIFT / 2, 0, { color = "#455a64", material = Enum.Material.Metal })
	cyl(folder, floor, 1.42, 0.004, 0, LIFT + 0.002, 0, { color = "#5b6a73", material = Enum.Material.DiamondPlate, shadow = false })
	-- Its striped rim: yellow and black round the edge.
	for i = 0, 39 do
		local a = (i + 0.5) / 40 * math.pi * 2
		local off = CFrame.new(P(math.cos(a) * 1.505, LIFT / 2, math.sin(a) * 1.505)) * CFrame.Angles(0, -a, 0)
		put(floor, part(folder, Vector3.new(0.02, LIFT * 0.6, 2 * math.pi * 1.505 / 40 * 1.04), off, { color = if i % 2 == 0 then "#ffc400" else "#1b1b1b", shadow = false }), off)
	end
	place(floor, CFrame.new(ORIGIN))

	-- Back wall (corrugated: ribs every 0.6 m), the baseboard, the roller door and the neon sign.
	box(30, 8, 0.2, 0, 4, -7, { color = "#6f7f8a", material = Enum.Material.Metal })
	for i = 0, 49 do
		box(0.08, 8, 0.06, -14.7 + i * 0.6, 4, -6.88, { color = "#5d6b75", material = Enum.Material.Metal, shadow = false })
	end
	box(30, 0.9, 0.12, 0, 0.45, -6.8, { color = "#37474f" })
	do
		-- The roller door, half up, the street's blue glow under it, hazard posts either side.
		box(3.4, 2.1, 0.08, -6.2, 2.95, -6.76, { color = "#b0bec5", material = Enum.Material.Metal })
		for i = 0, 9 do
			box(3.4, 0.03, 0.02, -6.2, 2.0 + i * 0.2, -6.71, { color = "#8a9aa3", shadow = false })
		end
		box(3.2, 1.9, 0.05, -6.2, 1.0, -7.06, { color = "#1a2a4a", material = Enum.Material.Neon, shadow = false })
		local street = box(3.0, 0.6, 0.02, -6.2, 0.9, -7.0, { color = "#7aa7ff", material = Enum.Material.Neon, transparency = 0.6, shadow = false })
		light("PointLight", street, { Color = hex("#7aa7ff"), Brightness = 1.2, Range = 22 })
		for _, dx in { -1.75, 1.75 } do
			box(0.14, 4, 0.14, -6.2 + dx, 2, -6.82, { color = "#ffc400" })
			for i = 0, 7 do
				box(0.145, 0.12, 0.145, -6.2 + dx, 0.25 + i * 0.5, -6.82, { color = "#1b1b1b", shadow = false })
			end
		end
	end
	do
		-- CRATE DEPOT in pink neon on a dark board, framed in cyan tubes.
		box(5.4, 1.5, 0.12, 0, 3.3, -6.84, { color = "#120a1e" })
		local face = box(5.1, 1.25, 0.02, 0, 3.3, -6.77, { color = "#140c22", shadow = false })
		sign(face, "CRATE DEPOT", "#ff4fd8", "#140c22", Enum.Font.GothamBlack)
		for _, t in { { 0, 0.7, 5.3, 0.05 }, { 0, -0.7, 5.3, 0.05 }, { -2.65, 0, 0.05, 1.4 }, { 2.65, 0, 0.05, 1.4 } } do
			box(t[3], t[4], 0.05, t[1], 3.3 + t[2], -6.74, { color = "#00e5ff", material = Enum.Material.Neon, shadow = false })
		end
		light("PointLight", face, { Color = hex("#ff4fd8"), Brightness = 1, Range = 30 })
		local sub = box(2.2, 0.55, 0.04, 5.9, 3.0, -6.82, { color = "#263238", shadow = false })
		sign(sub, "LOADING BAY 3", "#ffc400", "#263238", Enum.Font.GothamBlack)
	end
	-- Side walls, a front wall behind the camera and the roof, so the depot is closed in.
	for _, x in { -13, 13 } do
		box(0.2, 8, 25, x, 4, 5.5, { color = "#55626b", material = Enum.Material.Metal })
		for i = 0, 40 do
			box(0.06, 8, 0.08, x - math.sign(x) * 0.12, 4, -6.6 + i * 0.6, { color = "#4a565e", material = Enum.Material.Metal, shadow = false })
		end
	end
	box(30, 8, 0.2, 0, 4, 18, { color = "#2d3338", material = Enum.Material.Metal })
	box(30, 0.2, 25, 0, 8.1, 5.5, { color = "#1d2226", material = Enum.Material.Metal })
	-- Roof trusses.
	for _, z in { -4, 0, 4 } do
		box(26, 0.2, 0.2, 0, 7.4, z - 2, { color = "#37474f", material = Enum.Material.Metal })
		for i = 0, 11 do
			part(folder, Vector3.new(0.06, 0.9, 0.06), at * CF(-11 + i * 2, 7.05, z - 2) * CFrame.Angles(0, 0, if i % 2 == 1 then 0.6 else -0.6), { color = "#37474f", shadow = false })
		end
	end
	Racking(folder, -8, false, 7)
	Racking(folder, 8, true, 23)
	Forklift(folder, 4.6, -3.2, -0.7)
	Pallet(folder, -4.4, -4.6, 0.2, 4)
	Pallet(folder, 3.2, 1.8, -0.3, 1)
	Drum(folder, -4.2, -2.2, "#1565c0")
	Drum(folder, -3.6, -2.6, "#c62828")
	Drum(folder, -4.6, -2.9, "#2e7d32")
	TyreStack(folder, 4.2, -5.6, 5, "#ffc400")
	ToolChest(folder, -5.8, -5.9, 0.15)
	-- A traffic cone by the lift.
	box(0.36, 0.04, 0.36, 2.4, 0.02, 1.4, { color = "#212121" })
	part(folder, Vector3.new(0.5, 0.26, 0.26), at * CF(2.4, 0.27, 1.4) * UPRIGHT, { color = "#ff6d00", shape = "Cylinder" })
	part(folder, Vector3.new(0.08, 0.2, 0.2), at * CF(2.4, 0.3, 1.4) * UPRIGHT, { color = "#fafafa", shape = "Cylinder" })
	part(folder, Vector3.new(0.12, 0.12, 0.12), at * CF(2.4, 0.53, 1.4), { color = "#ff6d00", shape = "Ball" })
	HangingLamp(folder, -6, -3, 5.4)
	HangingLamp(folder, 6, -3, 5.4)
	-- The work lamp right over the lift (its shade hangs up in the dark; the light is the scene's key).
	local lamp = part(folder, Vector3.new(0.3, 0.3, 0.3), CFrame.lookAt(ORIGIN + P(0, 7, 1.2), ORIGIN), { color = "#2e3b43", transparency = 1, shadow = false })
	light("SpotLight", lamp, { Face = Enum.NormalId.Front, Color = hex("#ffe8c2"), Brightness = 2.6, Range = 60, Angle = 57, Shadows = true })
	-- Fill: the warm lamps over the racking, the sign's pink and a soft light from the camera's side.
	for _, x in { -6, 6 } do
		local f = part(folder, Vector3.new(0.1, 0.1, 0.1), at * CF(x, 4.6, -3), { transparency = 1, shadow = false })
		light("PointLight", f, { Color = hex("#ffd18a"), Brightness = 0.5, Range = 36 })
	end
	local fill = part(folder, Vector3.new(0.1, 0.1, 0.1), at * CF(0, 4, 7), { transparency = 1, shadow = false })
	light("PointLight", fill, { Color = hex("#6b7cc0"), Brightness = 0.3, Range = 50 })
	-- Specks of dust turning slowly in the work lamp's beam.
	local dust = part(folder, Vector3.new(3.4, 4.6, 3.4), at * CF(0, 2.8, 0), { transparency = 1, shadow = false })
	local e = Instance.new("ParticleEmitter")
	e.Rate = 14
	e.Lifetime = NumberRange.new(5, 8)
	e.Speed = NumberRange.new(0.15, 0.4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.08)
	e.LightEmission = 1
	e.Color = ColorSequence.new(hex("#fff3d6"))
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 1) })
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Parent = dust
end

-- ── The crate ────────────────────────────────────────────────────────────────────────────────────

type CrateParts = {
	root: Node,
	base: Node,
	lid: Node,
	panels: { Node },
	bands: { Node },
	core: BasePart,
	coreLight: PointLight,
	glows: { BasePart },
}

local function CrateModel(folder: Instance, def: any, glow: string): CrateParts
	local crystal = def.id == "diamond"
	local gold = def.id == "gold"
	local woodLook: Look = {
		color = def.look.wood,
		material = if crystal then Enum.Material.Glass elseif gold then Enum.Material.Foil else Enum.Material.WoodPlanks,
		reflect = if crystal then 0.25 elseif gold then 0.15 else 0,
		transparency = if crystal then 0.15 else 0,
	}
	local wood = Color3.fromHex(def.look.wood)
	local frameLook: Look = if crystal
		then { color = "#f5f7fa", material = Enum.Material.SmoothPlastic, reflect = 0.2 }
		else { color = "#" .. Color3.new(wood.R * (if gold then 0.8 else 0.72), wood.G * (if gold then 0.8 else 0.72), wood.B * (if gold then 0.8 else 0.72)):ToHex(), material = if gold then Enum.Material.Foil else Enum.Material.Wood }
	local bandLook: Look = { color = def.look.band, material = Enum.Material.Metal, reflect = if gold or crystal then 0.3 else 0.1 }
	local boltLook: Look = { color = if gold then "#ffe082" else "#b0bec5", material = Enum.Material.Metal, shadow = false }
	local skin = CRATE_SKIN[def.id]
	local skinN = if skin then (if skin[2] then data.modSkinNumber(skin[1]) else data.skinNumber(skin[1])) else 0
	local woods: { BasePart } = {}
	local function board(n: Node, w: number, h: number, d: number, x: number, y: number, z: number, rot: CFrame?)
		local p = block(folder, n, w, h, d, x, y, z, woodLook, rot)
		table.insert(woods, p)
		return p
	end

	local root = node(nil)
	-- Skids and the floor of the crate.
	local base = node(root)
	for _, x in { -0.55, 0, 0.55 } do
		block(folder, base, 0.16, 0.12, S + 0.08, x * S, 0.06, 0, frameLook)
	end
	block(folder, base, S, 0.04, S, 0, 0.13, 0, frameLook)
	-- The glow inside: a bright core that lights up through the gaps, and its light.
	local core = block(folder, root, S * 0.86, S * 0.86, S * 0.86, 0, S / 2 + 0.1, 0, { color = glow, material = Enum.Material.Neon, transparency = 1, shadow = false })
	local coreLight = light("PointLight", core, { Color = hex(glow), Brightness = 0, Range = 7 * K * 0.8, Shadows = false }) :: PointLight
	local glows = { core }

	-- Panels: front (+z), back, left, right; each hinged at its bottom outside edge.
	local sides = { { 0, S / 2, 0 }, { 0, -S / 2, math.pi }, { -S / 2, 0, -math.pi / 2 }, { S / 2, 0, math.pi / 2 } }
	local panels, bands = {}, {}
	local boards = 4
	local bh = (S - 0.04) / boards
	for i, sd in sides do
		local hinge = node(root, CFrame.new(P(sd[1], 0.15, sd[2])) * CFrame.Angles(0, sd[3], 0))
		local panel = node(hinge)
		panels[i] = panel
		-- Four boards with gaps (the glow shows through them), a frame and a diagonal brace.
		for b = 0, boards - 1 do
			board(panel, S - 0.02, bh - 0.035, 0.06, 0, 0.02 + bh * (b + 0.5), 0)
		end
		for _, x in { -(S / 2 - 0.065), 0, S / 2 - 0.065 } do
			block(folder, panel, 0.13, S, 0.05, x, S / 2, 0.05, frameLook)
		end
		if not crystal then
			local len = math.sqrt((S * 0.42) ^ 2 + (S * 0.86) ^ 2)
			block(folder, panel, 0.11, len, 0.04, -S / 4 + 0.02, S / 2, 0.09, frameLook, CFrame.Angles(0, 0, -0.46))
			block(folder, panel, 0.11, len, 0.04, S / 4 - 0.02, S / 2, 0.09, frameLook, CFrame.Angles(0, 0, 0.46))
		end
		-- Steel bands and corner brackets ride on the panels.
		local band = node(panel)
		bands[i] = band
		for _, y in { 0.24, S - 0.3 } do
			block(folder, band, S + 0.02, 0.08, 0.02, 0, y, 0.105, bandLook)
		end
		for _, sx in { -1, 1 } do
			for _, y in { 0.12, S - 0.12 } do
				local bx = sx * (S / 2 - 0.05)
				block(folder, band, 0.16, 0.16, 0.02, bx, y, 0.11, bandLook)
				for _, bo in { -0.04, 0.04 } do
					cyl(folder, band, 0.018, 0.02, bx + bo, y + bo, 0.126, boltLook, CFrame.Angles(math.pi / 2, 0, 0))
				end
			end
		end
		if i == 1 then
			-- A stencilled shipping label: the crate's name over a barcode and a FRAGILE glass.
			local label = block(folder, panel, 0.72, 0.36, 0.01, 0, S * 0.55, 0.125, { color = "#f5eedc", shadow = false })
			local g = Instance.new("SurfaceGui")
			g.Face = Enum.NormalId.Front
			g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			g.PixelsPerStud = 60
			local ink = hex(if def.id == "garage" then "#f5f5f5" else "#3e2723")
			local back = Instance.new("Frame")
			back.Size = UDim2.fromScale(1, 1)
			back.BackgroundColor3 = hex(if def.id == "garage" then "#2e3a2f" else "#f5eedc")
			back.BorderSizePixel = 0
			back.Parent = g
			local edge = Instance.new("UIStroke")
			edge.Thickness = 4
			edge.Color = ink
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.Parent = back
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Position = UDim2.fromScale(0.05, 0.08)
			name.Size = UDim2.fromScale(0.9, 0.36)
			name.Text = string.upper(def.name)
			name.TextColor3 = ink
			name.TextScaled = true
			name.Font = Enum.Font.GothamBlack
			name.Parent = back
			local r = rng(#def.name * 7 + 3)
			for bx = 0, 40 do
				if r() > 0.35 then
					local bar = Instance.new("Frame")
					bar.BorderSizePixel = 0
					bar.BackgroundColor3 = ink
					bar.Position = UDim2.fromScale(0.09 + bx * 0.0118, 0.52)
					bar.Size = UDim2.fromScale(if r() > 0.5 then 0.008 else 0.004, 0.3)
					bar.Parent = back
				end
			end
			local fragile = Instance.new("TextLabel")
			fragile.BackgroundTransparency = 1
			fragile.Position = UDim2.fromScale(0.64, 0.52)
			fragile.Size = UDim2.fromScale(0.3, 0.18)
			fragile.Text = "FRAGILE"
			fragile.TextColor3 = ink
			fragile.TextScaled = true
			fragile.Font = Enum.Font.GothamBold
			fragile.Parent = back
			g.Parent = label
			if gold or crystal then
				local gem = block(folder, panel, 0.14, 0.14, 0.14, 0, S * 0.86, 0.17, { color = glow, material = Enum.Material.Neon, shadow = false }, CFrame.Angles(0, 0, math.pi / 4))
				table.insert(glows, gem)
			end
		end
		-- Rope handles on the left and right sides.
		if i >= 3 then
			block(folder, panel, 0.3, 0.05, 0.05, 0, S * 0.62 + 0.1, 0.13, { color = "#c8a165", material = Enum.Material.Fabric })
			block(folder, panel, 0.05, 0.12, 0.05, -0.13, S * 0.62 + 0.04, 0.13, { color = "#c8a165", material = Enum.Material.Fabric })
			block(folder, panel, 0.05, 0.12, 0.05, 0.13, S * 0.62 + 0.04, 0.13, { color = "#c8a165", material = Enum.Material.Fabric })
		end
	end
	-- The lid: boards across, two battens, a band and corner caps.
	local lid = node(root, CFrame.new(P(0, S + 0.15, 0)))
	for i = 0, 4 do
		board(lid, S + 0.08, 0.06, (S + 0.08) / 5 - 0.03, 0, 0.03, -S / 2 - 0.04 + ((S + 0.08) / 5) * (i + 0.5))
	end
	for _, x in { -0.32, 0.32 } do
		block(folder, lid, 0.14, 0.05, S + 0.08, x * S, 0.085, 0, frameLook)
	end
	block(folder, lid, 0.08, 0.012, S + 0.1, 0, 0.115, 0, bandLook)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			block(folder, lid, 0.14, 0.09, 0.14, sx * (S / 2 - 0.02), 0.03, sz * (S / 2 - 0.02), bandLook)
		end
	end
	if skinN > 0 then
		for _, w in woods do
			Skins.lay(w, skinN)
		end
	end
	return { root = root, base = base, lid = lid, panels = panels, bands = bands, core = core, coreLight = coreLight, glows = glows }
end

-- ── Showers: coins, confetti and shards ──────────────────────────────────────────────────────────

-- Coins, or for a rare or legendary pull cut gems, thrown out of the crate: each one tumbles through
-- the air, bounces once or twice, then slides to a stop lying flat on the floor.
local COINS = 110
local SHAPES = { coin = { r = 0.11, h = 0.025 }, gem = { r = 0.1, h = 0.07 } }
type Launch = { vx: number, vy: number, vz: number, delay: number }
local BURSTS: { [string]: { n: number, launch: (number, number, () -> number) -> Launch } } = {
	-- Up and out in a loose spray, tipped toward the camera.
	fountain = { n = 70, launch = function(i, n, r)
		local a, sp = r() * math.pi * 2, 1.2 + r() * 2.6
		return { vx = math.cos(a) * sp, vy = 4.5 + r() * 3.5, vz = math.sin(a) * sp * 0.7 + 0.6, delay = (i / n) * 0.5 }
	end },
	-- One after another round a turning arm that reaches further each time.
	spiral = { n = 70, launch = function(i, n, r)
		local k = i / n
		local a, sp = k * math.pi * 3.2, 0.9 + k * 2.8
		return { vx = math.cos(a) * sp, vy = 5.2 + r() * 0.6, vz = math.sin(a) * sp * 0.8 + 0.2, delay = k * 0.9 }
	end },
	-- All at once, evenly round two rings, so they land as a splash of two circles.
	ring = { n = 72, launch = function(i, n)
		local inner = i % 2 == 0
		local a, sp = (i / n) * math.pi * 2 + (if inner then 0.09 else 0), if inner then 1.65 else 2.6
		return { vx = math.cos(a) * sp, vy = 5, vz = math.sin(a) * sp * 0.85 + 0.15, delay = if inner then 0.07 else 0 }
	end },
	-- Shot high out of sight, then raining down scattered over a second and a bit.
	rain = { n = 70, launch = function(i, n, r)
		local a, sp = r() * math.pi * 2, 0.4 + r() * 1.9
		return { vx = math.cos(a) * sp, vy = 10 + r() * 1.5, vz = math.sin(a) * sp * 0.75 + 0.35, delay = (i / n) * 1.2 + r() * 0.1 }
	end },
	-- A big win: a heavy, low heave in two waves that heaps up round the crate.
	pile = { n = 110, launch = function(i, n, r)
		local a, sp = r() * math.pi * 2, 0.2 + r() * r() * 2.4
		return { vx = math.cos(a) * sp, vy = 3.4 + r() * 2.4, vz = math.sin(a) * sp * 0.8 + 0.25, delay = (i % 2) * 0.35 + (i / n) * 0.35 }
	end },
}
local BURST_PATTERNS = { "fountain", "spiral", "ring", "rain" }
-- Snap an angle to the nearest face-up/face-down orientation.
local function flatOf(a: number): number
	return math.round(a / math.pi) * math.pi
end
-- What a thrown coin lands on at (x, z): the crate's floor, one of the four sides lying open around
-- it (hinged 0.15 up, tipped just short of flat), the lift or the depot floor.
local CRATE_FLOOR = LIFT + 0.15
local function groundAt(x: number, z: number, flaps: { boolean }): number
	local ax, az = math.abs(x), math.abs(z)
	local h = S / 2
	if ax < h and az < h then
		return CRATE_FLOOR
	end
	local side = if ax >= h and az < h then (if x < 0 then 3 else 4) elseif az >= h and ax < h then (if z > 0 then 1 else 2) else -1
	local out = if side >= 3 then ax - h else az - h
	if side >= 1 and flaps[side] and out < S then
		return CRATE_FLOOR + 0.08 + out * 0.07
	end
	return if math.sqrt(x * x + z * z) < 1.5 then LIFT else 0
end

type Coin = {
	vx: number, vy: number, vz: number, delay: number, flip: number, wob: number, yaw: number,
	x: number, y: number, z: number, sx: number, sy: number, sz: number, rx: number, rz: number,
	wx: number, wz: number, bounces: number, rest: boolean, fl: number, live: boolean, lift: number, settled: number,
}
type Shower = { parts: { BasePart }, step: (t: number, dt: number) -> () }

local function CoinBurst(folder: Instance, gems: boolean, big: boolean, style: string): Shower
	local flaps = FLAPS[style]
	local shape = if gems then SHAPES.gem else SHAPES.coin
	local R, H = shape.r, shape.h
	local r = rng(41)
	local coins: { Coin } = {}
	local parts: { BasePart } = {}
	for i = 1, COINS do
		coins[i] = {
			vx = 0, vy = 0, vz = 0, delay = 0,
			-- Flip rate (end over end) and a slower wobble, both in radians/second.
			flip = (8 + r() * 10) * (if r() < 0.5 then -1 else 1), wob = (r() - 0.5) * 6, yaw = r() * math.pi * 2,
			x = 0, y = 0, z = 0, sx = 0, sy = 0, sz = 0, rx = r() * 6, rz = 0, wx = 0, wz = 0, bounces = 0, rest = false, fl = 0, live = false,
			lift = 0, settled = -1,
		}
		parts[i] = part(folder, Vector3.new(H, R * 2, R * 2), HIDE, if gems
			then { shape = "Cylinder", color = "#35a8ff", material = Enum.Material.Glass, reflect = 0.3 }
			else { shape = "Cylinder", color = "#ffc107", material = Enum.Material.Foil, reflect = 0.2 })
	end
	-- A big win always heaps up a pile; otherwise the shower's pattern is picked at random.
	local pattern = if big then "pile" else BURST_PATTERNS[math.random(1, #BURST_PATTERNS)]
	local b = BURSTS[pattern]
	local lr = rng(math.random(1, 1e6))
	local shown = b.n
	for i, c in coins do
		if i <= shown then
			local l = b.launch(i - 1, shown, lr)
			c.vx, c.vy, c.vz, c.delay = l.vx, l.vy, l.vz, l.delay
		end
	end
	local function reach(c: Coin): number
		return R * math.min(1, math.sqrt(math.sin(c.rx) ^ 2 + math.sin(c.rz) ^ 2)) + H / 2
	end
	local function step(t: number, dt: number)
		local cfs = {}
		for i, c in coins do
			if i > shown or t < c.delay then
				cfs[i] = HIDE
				continue
			end
			if not c.live then
				c.live = true
				c.x, c.y, c.z, c.sx, c.sy, c.sz, c.wx, c.wz, c.bounces, c.rest = 0, S * 0.8, 0, c.vx, c.vy, c.vz, c.flip, c.wob, 0, false
			end
			local floor = groundAt(c.x, c.z, flaps)
			if not c.rest then
				c.sy -= 14 * dt
				c.x += c.sx * dt
				c.y += c.sy * dt
				c.z += c.sz * dt
				c.rx += c.wx * dt
				c.rz += c.wz * dt
				-- A chest's back stays standing: a piece thrown at it from inside bounces back off it.
				local wall = -S / 2 + R
				if style == "chest" and c.z < wall and c.z - c.sz * dt >= wall and c.y < S + 0.15 + LIFT then
					c.z = wall
					c.sz = math.abs(c.sz) * 0.35
				end
				local rch = reach(c)
				if c.y < floor + rch and c.sy < 0 then
					c.y = floor + rch
					c.bounces += 1
					-- Each hit loses most of the spin and height; after a couple it lies down.
					c.sy = math.abs(c.sy) * (if c.bounces == 1 then 0.38 else 0.22)
					c.sx *= 0.55
					c.sz *= 0.55
					c.wx *= 0.4
					c.wz *= 0.3
					if c.bounces >= 3 or c.sy < 0.8 then
						c.rest, c.fl, c.settled = true, floor, t
					end
				end
			else
				-- Slide to a stop and settle flat: no more spinning on the floor.
				local k = 1 - math.exp(-12 * dt)
				c.sx *= 1 - math.min(1, 6 * dt)
				c.sz *= 1 - math.min(1, 6 * dt)
				local nx, nz = c.x + c.sx * dt, c.z + c.sz * dt
				local under = groundAt(nx, nz, flaps)
				-- It follows a gentle slope, stops against a step up and drops off an edge again.
				if under > c.fl + 0.04 then
					c.sx, c.sz = 0, 0
				else
					c.x, c.z = nx, nz
					if under < c.fl - 0.04 then
						c.rest, c.sy, c.bounces, c.lift, c.settled = false, 0, 2, 0, -1
					else
						c.fl = under
					end
				end
				c.rx += (flatOf(c.rx) - c.rx) * k
				c.rz += (flatOf(c.rz) - c.rz) * k
				-- Lie on top of any piece that settled here first, so a heap stacks up.
				if math.abs(c.sx) + math.abs(c.sz) > 0.02 or t - c.settled < 0.3 then
					local top = 0
					for j = 1, shown do
						local o = coins[j]
						if o == c or not o.rest or o.settled < 0 or o.settled > c.settled or (o.settled == c.settled and j > i) then
							continue
						end
						if math.abs(o.fl - c.fl) < 0.04 and math.sqrt((o.x - c.x) ^ 2 + (o.z - c.z) ^ 2) < R * 1.5 then
							top = math.max(top, o.lift + H * 0.95)
						end
					end
					c.lift += (top - c.lift) * math.min(1, 20 * dt)
				end
				if c.rest then
					c.y = c.fl + c.lift + reach(c)
				end
			end
			cfs[i] = CFrame.new(ORIGIN + P(c.x, c.y, c.z)) * CFrame.fromEulerAnglesYXZ(c.rx, c.yaw, c.rz) * UPRIGHT
		end
		moveAll(parts, cfs)
	end
	return { parts = parts, step = step }
end

-- Confetti and sparks thrown up when the lid blows.
local BITS = 140
local function Burst(folder: Instance, glow: string, amount: number): Shower
	local r = rng(77)
	local palette = { glow, "#ffffff", "#ffd54f", glow, "#ff4081", "#69f0ae" }
	local count = math.round(BITS * amount)
	local bits, parts = {}, {}
	for i = 1, count do
		local a, sp = r() * math.pi * 2, 0.8 + r() * 3
		bits[i] = { vx = math.cos(a) * sp, vy = 5 + r() * 6, vz = math.sin(a) * sp, rx = r() * 6, ry = r() * 6, w = 0.5 + r() }
		parts[i] = part(folder, Vector3.new(0.09, 0.05, 0.012), HIDE, { color = palette[(i - 1) % #palette + 1], material = Enum.Material.Neon, shadow = false })
	end
	local function step(t: number)
		local cfs = {}
		for i, b in bits do
			if t < 0 or t >= 4 then
				cfs[i] = HIDE
				continue
			end
			-- Fall slows like paper once it's past the top of its throw.
			local drag = math.min(t, 0.6) + math.max(0, t - 0.6) * 0.25
			local y = S + b.vy * drag - 9 * drag * drag
			local fade = math.max(0.05, 1 - t / 4)
			cfs[i] = CFrame.new(ORIGIN + P(b.vx * drag * 1.2, math.max(0.03, y), b.vz * drag * 1.2)) * CFrame.Angles(b.rx + t * 7 * b.w, b.ry + t * 5, t * 3)
			-- Shrinks away: put it through the floor's surface once it's tiny.
			if fade < 0.15 then
				cfs[i] = HIDE
			end
		end
		moveAll(parts, cfs)
	end
	return { parts = parts, step = function(t, _)
		step(t)
	end }
end

-- Diamond's crystal shards: the sides and lid break into pieces that fly out, spin, land on the
-- floor, lie there glinting and then shrink away.
local SHARDS = 72
local function Shards(folder: Instance, glow: string): Shower
	local r = rng(29)
	local h = S / 2
	local palette = { "#e1f5fe", glow, "#b3e5fc", "#ffffff", "#e1bee7" }
	local list, parts = {}, {}
	for i = 0, SHARDS - 1 do
		-- Where on the crate it breaks from: one of the four sides, or the lid.
		local side = i % 5
		local u, v = (r() - 0.5) * S, 0.15 + r() * S
		local x, y, z, nx, nz
		if side == 0 then
			x, y, z, nx, nz = u, v, h, 0, 1
		elseif side == 1 then
			x, y, z, nx, nz = u, v, -h, 0, -1
		elseif side == 2 then
			x, y, z, nx, nz = -h, v, u, -1, 0
		elseif side == 3 then
			x, y, z, nx, nz = h, v, u, 1, 0
		else
			x, y, z, nx, nz = u, S + 0.15, (r() - 0.5) * S, u, 0
		end
		local out = 1.6 + r() * 3
		local size = Vector3.new(0.07 + r() * 0.12, 0.025 + r() * 0.03, 0.05 + r() * 0.1) * 2
		list[i + 1] = {
			x = x, y = y + LIFT, z = z,
			vx = nx * out + (r() - 0.5) * 1.5, vy = 2 + r() * 4 + (if side == 4 then 2 else 0), vz = nz * out * 0.9 + (r() - 0.5) * 1.5 + 0.3,
			w = { (r() - 0.5) * 16, (r() - 0.5) * 10, (r() - 0.5) * 16 },
			rx = r() * 6, ry = r() * 6, rz = r() * 6, rest = false, bounces = 0, hy = size.Y / 2,
		}
		parts[i + 1] = part(folder, size, HIDE, { color = palette[i % #palette + 1], material = Enum.Material.Glass, reflect = 0.3, transparency = 0.1, shape = "Wedge" })
	end
	local age = 0
	local function step(_t: number, dt: number)
		age += dt
		local cfs = {}
		-- They lie there glinting for a moment, then go.
		local gone = age > 4.2
		for i, c in list do
			if gone then
				cfs[i] = HIDE
				continue
			end
			local floor = groundAt(c.x, c.z, NO_FLAPS) + c.hy
			if not c.rest then
				c.vy -= 13 * dt
				c.x += c.vx * dt
				c.y += c.vy * dt
				c.z += c.vz * dt
				c.rx += c.w[1] * dt
				c.ry += c.w[2] * dt
				c.rz += c.w[3] * dt
				if c.y < floor and c.vy < 0 then
					c.y = floor
					c.bounces += 1
					c.vy = math.abs(c.vy) * 0.25
					c.vx *= 0.5
					c.vz *= 0.5
					if c.bounces >= 2 or c.vy < 0.6 then
						c.rest = true
					end
				end
			else
				local k = 1 - math.exp(-10 * dt)
				c.vx *= 1 - math.min(1, 5 * dt)
				c.vz *= 1 - math.min(1, 5 * dt)
				c.x += c.vx * dt
				c.z += c.vz * dt
				c.rx += (flatOf(c.rx) - c.rx) * k
				c.rz += (flatOf(c.rz) - c.rz) * k
				c.y = groundAt(c.x, c.z, NO_FLAPS) + c.hy
			end
			cfs[i] = CFrame.new(ORIGIN + P(c.x, c.y, c.z)) * CFrame.Angles(c.rx, c.ry, c.rz)
		end
		moveAll(parts, cfs)
	end
	return { parts = parts, step = step }
end

-- A stack of gold coins with a big coin standing on top (a coin prize).
local function CoinPile(folder: Instance, n: Node)
	local coin: Look = { color = "#ffc107", material = Enum.Material.Foil, reflect = 0.25 }
	for k = 0, 3 do
		for i = 0, 5 - k do
			local a = (i / (6 - k)) * math.pi * 2 + k
			local rr = 0.42 - k * 0.1
			cyl(folder, n, 0.16, 0.05, math.cos(a) * rr, 0.03 + k * 0.05, math.sin(a) * rr, coin, CFrame.Angles(0.1 * math.sin(i), a, 0.1))
		end
	end
	-- The big coin stands on top facing the camera, a $ stamped on it.
	local face = cyl(folder, n, 0.42, 0.08, 0, 0.62, 0, { color = "#ffca28", material = Enum.Material.Foil, reflect = 0.3 }, CFrame.Angles(math.pi / 2, 0, 0))
	for _, f in { Enum.NormalId.Left, Enum.NormalId.Right } do
		local g = Instance.new("SurfaceGui")
		g.Face = f
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 50
		g.LightInfluence = 0.4
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Text = "$"
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = hex("#e65100")
		t.Parent = g
		g.Parent = face
	end
end

-- ── The prize ────────────────────────────────────────────────────────────────────────────────────

-- How a car prize looks: its model and whole paint job, parts, skins and hat.
export type CarLook = { model: string, color: string, finish: string?, stripe: any?, mods: { string }?, skin: string?, modSkin: any?, hat: any? }

local function fitted(mods: { string }, body: string): { string }
	local out = {}
	for _, id in data.fittedMods(mods, body) do
		table.insert(out, id)
	end
	table.sort(out)
	return out
end

-- The showiest part for a slot on this body: the dearest one that fits.
local function bestPart(slot: string, body: string): string?
	local best, worth = nil, -1
	for _, m in data.MODS do
		if m.slot == slot and data.modFits(m, body) then
			local w = m.coins + (m.bucks or 0) * data.GEM_BUILD_COINS
			if w > worth then
				best, worth = m.id, w
			end
		end
	end
	return best
end

local function ownedCars(cars: { any }): { any }
	local out = {}
	for _, c in cars do
		if not data.carDef(c.model).parked then
			table.insert(out, c)
		end
	end
	return out
end

local function mineOf(cars: { any }, mine: string?): any
	local owned = ownedCars(cars)
	for _, c in owned do
		if c.uid == mine then
			return c
		end
	end
	return owned[1] or { model = "civic", color = "#eceff1" }
end

-- A skin prize, on one of the player's cars (the web's skinLook): a car paint covers the bare body
-- with no parts on; a mod paint goes on a fully kitted car and only those parts change.
local function skinLook(id: string, isPart: boolean, cars: { any }, mine: string?): CarLook
	local car = mineOf(cars, mine)
	local d = data.carDef(car.model)
	local look: CarLook = { model = car.model, color = car.color, finish = car.finish, stripe = car.stripe }
	if not isPart and id == data.CUSTOM_PAINT.id then
		look.mods, look.color = {}, data.CUSTOM_PAINT_SHOW
		return look
	end
	if not isPart then
		look.mods, look.skin = {}, id
		return look
	end
	local have = data.fittedMods(car.mods or {}, d.body)
	local kit = {}
	for _, sl in data.SKINNED_SLOTS do
		local m = have[sl] or bestPart(sl, d.body)
		if m then
			table.insert(kit, m)
		end
	end
	local fit = data.fittedMods(kit, d.body)
	local modSkin = {}
	for _, sl in data.SKINNED_SLOTS do
		if fit[sl] then
			modSkin[sl] = id
		end
	end
	look.mods, look.modSkin = fitted(kit, d.body), modSkin
	return look
end

-- The car a prize shows (the web's prizeLook): a new car in its colour, your car wearing the part,
-- paint or hat it won. `mine` is the car to show a paint on: the selected one, or your race car.
function CrateScene.prizeLook(drop: any, cars: { any }, mine: string?): CarLook?
	if not drop then
		return nil
	end
	local k = drop.kind
	if k == "skin" or k == "skindupe" then
		return skinLook(drop.skin, drop.part == true, cars, mine)
	elseif k == "car" then
		return { model = drop.model, color = drop.color }
	elseif k == "piece" then
		-- A resto-mod piece shows its secret car as a dark shadow; the fourth piece shows it built.
		return { model = drop.model, color = if drop.uid and drop.color then drop.color else "#263238" }
	elseif k == "hat" then
		local car = mineOf(cars, mine)
		return { model = car.model, color = car.color, finish = car.finish, skin = car.skin, modSkin = car.modSkin, stripe = car.stripe, mods = car.mods, hat = { id = drop.hat } }
	elseif k == "dupe" then
		local d = data.carDef(drop.model)
		return { model = d.id, color = d.colors[1] }
	elseif k == "mod" then
		local car = nil
		for _, c in cars do
			if c.uid == drop.car then
				car = c
			end
		end
		if not car then
			return nil
		end
		local d = data.carDef(car.model)
		-- The new part goes first so it wins its slot; the rest of the car's fitted parts stay on.
		local mods = { drop.mod }
		for _, m in car.mods or {} do
			table.insert(mods, m)
		end
		return { model = car.model, color = car.color, finish = car.finish, skin = car.skin, modSkin = car.modSkin, stripe = car.stripe, mods = fitted(mods, d.body) }
	end
	return nil
end

-- ── The scene ────────────────────────────────────────────────────────────────────────────────────

export type Phase = "idle" | "wait" | "open"

type Stage = {
	def: any,
	phase: Phase,
	drop: any?,
	look: CarLook?,
	onReveal: (() -> ())?,
	pace: Pace,
	folder: Folder,
	crate: CrateParts,
	glow: string,
	st: any,
	prize: Model?,
	prizeNode: Node,
	prizeSize: number,
	beam: BasePart,
	floorGlow: BasePart,
	flash: PointLight,
	key: PointLight,
	rim: PointLight,
	lamps: BasePart,
	showers: { Shower },
	burstAt: number?,
	coinAt: number?,
}

local depot: Folder? = nil
local stage: Stage? = nil
local active = false
local clock = 0
-- The camera's resting place (fitted to the screen), and what it looked at.
local base = CFrame.new()
-- The fitted view before it's moved over (metres from the depot's middle), and how far over to
-- move whatever the camera looks at, in screen pixels (the web's view offset), on a screen
-- `viewH` pixels tall.
local raw = { pos = Vector3.new(0, 5, 8), aim = Vector3.new(0, 1.5, -0.6), cx = 0, cy = 0, viewH = 800 }
local hidden: { [GuiObject]: boolean } = {}
local hudRoot: Instance? = nil
local hudKeep: Instance? = nil
local oldFov = 70
local frame: { x: number, y: number, w: number, h: number } = { x = 0, y = 0, w = 1, h = 1 }

local function tierOf(drop: any): number
	return crates.dropTier(drop) + 1
end

local function isCoins(drop: any): boolean
	local k = drop and drop.kind
	return k == "coins" or k == "dupe" or k == "skindupe" or k == "piecedupe"
end

-- Where the camera rests: the web's useFitCamera([0, 0.42, 1], [0, 1.5, -0.6], ...) fitted to the
-- depot's part of the screen (under the Cars page's header), then moved so the crate sits left of
-- centre on a wide screen (the picker docks on the right) and high on a tall one (it docks along
-- the bottom), as the web's view offset does.
local function fit()
	local cam = workspace.CurrentCamera
	local view = cam.ViewportSize
	if view.X < 2 or view.Y < 2 then
		view = Vector2.new(1280, 800)
	end
	local fw, fh = frame.w * view.X, frame.h * view.Y
	local wide = CrateScene.wide()
	local halfW, halfH = if wide then 5 else 2.5, if wide then 3 else 2.9
	-- The web's camera sees 42 degrees top to bottom of the scene's own area (under the menu's
	-- header); Roblox's covers the whole screen, so open it up to match.
	cam.FieldOfView = 2 * math.deg(math.atan(math.tan(math.rad(21)) * view.Y / fh))
	local t = math.tan(math.rad(cam.FieldOfView / 2))
	-- The half-height (metres) the whole screen shows at that distance has to cover the frame's part.
	local dist = math.max(halfH * view.Y / (t * fh), halfW * view.Y / (t * fw))
	local target = Vector3.new(0, 1.5, -0.6)
	local dir = Vector3.new(0, 0.42, 1).Unit
	-- Where on screen the target should be: the frame's middle, then the web's 13% offset.
	raw = {
		pos = target + dir * dist,
		aim = target,
		cx = (frame.x + frame.w / 2) * view.X - view.X / 2 - (if wide then 0.13 * fw else 0),
		cy = (frame.y + frame.h / 2) * view.Y - view.Y / 2 - (if wide then 0 else 0.13 * fh),
		viewH = view.Y,
	}
	base = CrateScene.shoot(raw.pos, raw.aim)
end

-- The camera at `pos` looking at `aim` (metres from the depot's middle), turned a little so what
-- it looks at lands where the fitted view puts it on screen (the web shifts its picture with a
-- view offset; Roblox has none, and turning keeps near and far things in step where sliding the
-- camera over wouldn't).
function CrateScene.shoot(pos: Vector3, aim: Vector3): CFrame
	local cam = workspace.CurrentCamera
	local look = CFrame.lookAt(pos, aim)
	local f = (raw.viewH / 2) / math.tan(math.rad(cam.FieldOfView / 2))
	local turn = CFrame.Angles(0, math.atan(raw.cx / f), 0) * CFrame.Angles(math.atan(raw.cy / f), 0, 0)
	return CFrame.new(ORIGIN + pos * K) * look.Rotation * turn
end

-- Whether the depot is laid out wide (picker on the right): a screen at least 900 wide and wider
-- than 5:4, in the HUD's own units (the web's 1280x800 layout).
function CrateScene.wide(): boolean
	local cam = workspace.CurrentCamera
	local view = cam.ViewportSize
	if view.X < 2 or view.Y < 2 then
		view = Vector2.new(1280, 800)
	end
	local s = math.clamp(math.min(view.X / 1280, view.Y / 800), 0.55, 1)
	local w, h = view.X / s * frame.w, view.Y / s * frame.h
	return w >= 900 and w > h * 1.25
end

local function clearStage()
	local s = stage
	if s then
		stage = nil
		s.folder:Destroy()
	end
end

-- One crate on the lift, from dropping in to its prize: made fresh for every crate.
function CrateScene.run(def: any, pace: Pace?)
	clearStage()
	if not depot then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "Stage"
	folder.Parent = depot
	local glow = def.look.glow
	local crate = CrateModel(folder, def, glow)
	local prizeNode = node(nil)
	-- A slowly turning ring of light under the prize.
	ring(folder, prizeNode, 1.05, 1.2, 0.02, 40, { glow }, { material = Enum.Material.Neon })
	local beam = part(folder, Vector3.new(8, 1.45, 1.45), HIDE, { shape = "Cylinder", color = glow, material = Enum.Material.Neon, transparency = 1, shadow = false })
	local floorGlow = part(folder, Vector3.new(0.02, 3.2, 3.2), CFrame.new(ORIGIN + P(0, LIFT + 0.012, 0)) * UPRIGHT, { shape = "Cylinder", color = glow, material = Enum.Material.Neon, transparency = 0.82, shadow = false })
	local flashPart = part(folder, Vector3.new(0.1, 0.1, 0.1), CFrame.new(ORIGIN + P(0, 2.2, 0.6)), { transparency = 1, shadow = false })
	local lamps = part(folder, Vector3.new(0.1, 0.1, 0.1), HIDE, { transparency = 1, shadow = false })
	local keyPart = part(folder, Vector3.new(0.1, 0.1, 0.1), HIDE, { transparency = 1, shadow = false })
	local rimPart = part(folder, Vector3.new(0.1, 0.1, 0.1), HIDE, { transparency = 1, shadow = false })
	local s: Stage = {
		def = def,
		phase = "idle",
		drop = nil,
		look = nil,
		onReveal = nil,
		pace = pace or "full",
		folder = folder,
		crate = crate,
		glow = glow,
		st = {
			born = -1, openAt = -1, charged = false, lid = { y = 0, vy = 0, x = 0, vx = 0, rx = 0, landed = false }, revealed = false, hops = 0,
			vary = { dir = 0, spin = 1, lag = { 0, 0, 0, 0 }, wob = 11, side = 1 }, skip = false,
		},
		prize = nil,
		prizeNode = prizeNode,
		prizeSize = 1,
		beam = beam,
		floorGlow = floorGlow,
		flash = light("PointLight", flashPart, { Color = hex(glow), Brightness = 0, Range = 48 }) :: PointLight,
		key = light("PointLight", keyPart, { Color = hex("#fff4e0"), Brightness = 0, Range = 36 }) :: PointLight,
		rim = light("PointLight", rimPart, { Color = hex(glow), Brightness = 0, Range = 28 }) :: PointLight,
		lamps = lamps,
		showers = {},
		burstAt = nil,
		coinAt = nil,
	}
	;(s :: any).keyPart, (s :: any).rimPart = keyPart, rimPart
	stage = s
end

-- The prize to show (once the roll is back) in the crate's glow: its car (or coin pile).
local function dressPrize(s: Stage)
	local drop = s.drop
	if not drop then
		return
	end
	local glow = CrateScene.TIER_GLOW[tierOf(drop)]
	if glow ~= s.glow then
		s.glow = glow
		for _, g in s.crate.glows do
			g.Color = hex(glow)
		end
		s.crate.coreLight.Color = hex(glow)
		s.beam.Color = hex(glow)
		s.floorGlow.Color = hex(glow)
		s.flash.Color = hex(glow)
		s.rim.Color = hex(glow)
		for _, it in s.prizeNode.items do
			it.part.Color = hex(glow)
		end
	end
	local showCar = (drop.kind == "car" or drop.kind == "dupe" or drop.kind == "skin" or drop.kind == "skindupe" or drop.kind == "hat" or drop.kind == "piece" or drop.kind == "mod") and s.look ~= nil
	if showCar and s.look and not s.prize then
		local l = s.look
		local m = Thumb.carModel(l.model, { color = l.color, finish = l.finish, stripe = l.stripe }, l.hat, l.mods, l.skin, l.modSkin)
		if m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			local _, size = m:GetBoundingBox()
			-- 2.3 m long, as the web's prizeScale.
			s.prizeSize = 2.3 * K / math.max(size.X, size.Z, 0.1)
			m:PivotTo(HIDE)
			m.Parent = s.folder
			s.prize = m
		end
	elseif isCoins(drop) and not showCar and #s.prizeNode.kids == 0 then
		CoinPile(s.folder, node(s.prizeNode))
	end
end

-- What the crate on the lift is doing: idle, waiting on the roll (it shakes) or opening, with the
-- prize it holds (and the car to show it on), and what to do once it's shown.
function CrateScene.update(phase: Phase, drop: any?, look: CarLook?, onReveal: (() -> ())?)
	local s = stage
	if not s then
		return
	end
	s.phase = phase
	if drop ~= s.drop then
		s.drop = drop
		s.look = look
		dressPrize(s)
	end
	s.onReveal = onReveal
end

-- A tap to skip: lands the crate at once and jumps to the burst.
function CrateScene.skip()
	local s = stage
	if s then
		s.st.skip = true
	end
end

local PIVOT = Vector3.new(0, 1, 0)
local LOOK_AT = Vector3.new(0, 1.5, -0.6)
local PRIZE_AT = Vector3.new(0, 1.45, 0)

local function rotateAbout(v: Vector3, pivot: Vector3, a: number): Vector3
	return pivot + CFrame.Angles(0, a, 0):VectorToWorldSpace(v - pivot)
end

local function tick(dt: number)
	local s = stage
	local cam = workspace.CurrentCamera
	if not s then
		cam.CFrame = base
		return
	end
	clock += dt
	local now = clock
	local st = s.st
	local show = s.pace == "show"
	local Pc = if s.pace == "quick" then PACE.quick else PACE.full
	local style = OPEN_STYLE[s.def.id] or "pop"
	local drama = DRAMA[style]
	local drop = s.drop
	local coins = isCoins(drop)
	local tier = if drop then tierOf(drop) else 1
	local gems = drop ~= nil and not coins and tier >= 3
	local big = drop ~= nil and ((drop.kind == "coins" and drop.jackpot == true) or tier >= 4)
	if st.born < 0 then
		st.born = now
		-- A prize already won goes straight back on the lift: no crate.
		if show then
			st.openAt = now - 10
			s.burstAt = now - 10
			st.revealed = true
			st.charged = true
		end
	end
	-- A quick open bursts as its landing bounce ends; a full one starts straining once it has
	-- landed and bounced.
	if s.phase == "open" and st.openAt < 0 then
		st.openAt = math.max(now, st.born + Pc.drop + (if s.pace == "quick" then 0 else BOUNCE))
	end
	if st.skip then
		st.skip = false
		st.born = math.min(st.born, now - Pc.drop - BOUNCE)
		if st.openAt > 0 then
			st.openAt = math.min(st.openAt, now - Pc.settle)
		end
	end
	-- Drop in from above on arrival, with a little bounce.
	local age = now - st.born
	local fall = math.min(1, age / Pc.drop)
	local y = LIFT + (1 - fall * fall) * 5
	if fall >= 1 then
		y = LIFT + math.abs(math.sin(math.min(1, (age - Pc.drop) / BOUNCE) * math.pi)) * 0.12 * math.max(0, 1 - (age - Pc.drop) / BOUNCE)
	end
	local shake, charge = 0, 0
	local t = if st.openAt > 0 then now - st.openAt else -1
	if s.phase == "wait" then
		shake = 0.012
	end
	local ry = st.ry or 0
	if s.phase == "idle" then
		ry = math.sin(now * 0.6) * 0.18
	end
	if t >= 0 then
		if not st.charged then
			st.charged = true
			Sfx.crate.charge(Pc.charge)
		end
		charge = math.min(1, t / Pc.charge)
		shake = if t < Pc.charge then 0.01 + charge * charge * 0.06 else 0
		-- Hops as it strains.
		for i, h in ipairs(Pc.hops) do
			if t >= h and t < h + 0.16 then
				y += math.sin(((t - h) / 0.16) * math.pi) * (0.06 + (i - 1) * 0.04)
			end
		end
		if t >= Pc.charge and s.burstAt == nil then
			s.burstAt = now
			Sfx.crate.open(s.def.id)
			if s.def.id ~= "street" then
				Sfx.boost()
			end
			if drop then
				Sfx.crate.reveal(tier - 1, coins)
			end
			if coins or gems then
				s.coinAt = now + 0.15
			end
		end
	end
	if s.burstAt and not st.burst and not show then
		st.burst = true
		-- Street's lid pops off and tumbles aside; Garage's floats up and away on the beam.
		st.lid = if style == "roll" then { y = 0, vy = 1.5, x = 0, vx = 0, rx = 0, landed = false } else { y = 0, vy = 4.4 + math.random() * 1.4, x = 0, vx = 1 + math.random() * 0.5, rx = 0, landed = false }
		-- A little chance in every opening so no two look the same.
		local side = if math.random() < 0.5 then -1 else 1
		st.vary = {
			dir = -math.pi / 2 + side * (0.4 + math.random() * 0.7),
			spin = side * (0.7 + math.random() * 0.6),
			lag = { math.random() * 0.14, math.random() * 0.14, math.random() * 0.14, math.random() * 0.14 },
			wob = 9 + math.random() * 5,
			side = side,
		}
		table.insert(s.showers, Burst(s.folder, s.glow, drama.confetti))
		if style == "shatter" then
			table.insert(s.showers, Shards(s.folder, s.glow))
		end
	end
	if s.coinAt and not st.coins and not show then
		st.coins = true
		local c = CoinBurst(s.folder, gems, big, style)
		;(c :: any).coin = true
		table.insert(s.showers, c)
	end
	if t < 0 and s.phase ~= "idle" then
		ry *= 0.9
	end
	st.ry = ry
	local root = s.crate.root
	root.cf = CFrame.new(P((math.random() - 0.5) * shake, y, (math.random() - 0.5) * shake)) * CFrame.Angles(0, ry, 0)
	root.visible = not show

	-- The glow building inside.
	local after = if s.burstAt then now - s.burstAt else -1
	local core = s.crate.core
	core.Transparency = 1 - (if after >= 0 then math.max(0, 1 - after * 1.5) else charge * 0.95) * 0.85
	s.crate.coreLight.Brightness = (if after >= 0 then 6 + math.max(0, 30 * (1 - after * 2)) else charge * 14) / 9
	s.flash.Brightness = if after >= 0 then math.max(0, drama.flash * (1 - after * 3)) / 12 else 0

	-- Burst: the crate opens its own way and the bands snap away.
	if after >= 0 then
		local L = st.lid
		if style == "roll" then
			-- Lifted straight up the beam, speeding up and turning, until it's gone.
			L.vy += 9 * dt
			L.y += L.vy * dt
			L.rx += dt * 2.5 * st.vary.spin
		elseif style == "pop" and not L.landed then
			L.vy -= 16 * dt
			L.y += L.vy * dt
			L.x += L.vx * dt
			L.rx += dt * 5 * st.vary.spin
			local floor = -(S + 0.15) - y + 0.04
			if L.y < floor then
				L.y = floor
				L.landed = true
			end
		end
		local lid = s.crate.lid
		lid.visible = style ~= "shatter" and L.y < 7
		if style == "pop" then
			lid.cf = CFrame.new(P(math.cos(st.vary.dir) * L.x, S + 0.15 + L.y, math.sin(st.vary.dir) * L.x)) * CFrame.Angles(if L.landed then 0 else -L.rx, L.rx * 0.3, if L.landed then 0.05 else L.rx * 0.2)
		elseif style == "roll" then
			lid.cf = CFrame.new(P(0, S + 0.15 + L.y, 0)) * CFrame.Angles(0, L.rx, 0)
		elseif style == "chest" then
			-- Swung back on its hinge along the back edge, past upright, with a heavy wobble.
			local a = 2.35 * (1 - math.exp(-after * 6) * math.cos(after * st.vary.wob))
			lid.cf = CFrame.new(P(0, S + 0.15 + (S / 2) * math.sin(a), -S / 2 + (S / 2) * math.cos(a))) * CFrame.Angles(-a, 0, 0)
		end
		for i, g in s.crate.panels do
			-- Each side goes a moment after the last, in a different order every time.
			local at = math.max(0, after - st.vary.lag[i])
			local k = math.min(1, at / 0.42)
			local open = if k < 1 then 1 - (1 - k) * (1 - k) else 1
			local bounce = if at > 0.42 and at < 0.7 then math.sin(((at - 0.42) / 0.28) * math.pi) * 0.12 else 0
			-- Shutters roll down into the base, a beat after the lid lifts.
			local roll = math.min(1, math.max(0, (at - 0.08) / 0.55))
			if style == "shatter" then
				g.visible = false
				s.crate.base.visible = false
			elseif style == "roll" then
				g.scale = Vector3.new(1, math.max(0.001, 1 - roll * roll * (3 - 2 * roll)), 1)
			elseif not (style == "chest" and i == 2) then
				-- A chest keeps its back standing, with the lid hinged on it.
				g.cf = CFrame.Angles(open * 1.5 - bounce, 0, 0)
			end
		end
		for i, g in s.crate.bands do
			if not (style == "chest" and i == 2) then
				local sc = math.max(0.001, 1 - after * 6)
				g.scale = Vector3.new(sc, sc, sc)
				g.visible = sc > 0.01
			end
		end
		-- The beam up out of the crate: it fades once the prize is up, so it doesn't wash it out.
		local bk = math.min(1, after * 4)
		s.beam.Size = Vector3.new(8 * K * bk, 1.45 * K * drama.beam, 1.45 * K * drama.beam)
		s.beam.CFrame = CFrame.new(ORIGIN + P(0, LIFT + 4 * bk, 0)) * UPRIGHT
		s.beam.Transparency = 1 - math.max(0.04, 0.7 * math.exp(-after * 1.1)) * 0.55
		-- The prize rises out of the box and turns slowly; a coin prize spins as it rises, then
		-- stops facing the camera.
		local r = math.min(1, math.max(0, (after - Pc.rise) / Pc.lift))
		local ease = if r < 1 then 1 - (1 - r) ^ 3 + math.sin(r * math.pi) * 0.12 else 1
		local turn = if coins and not s.prize then (1 - r) ^ 3 * math.pi * 4 else -0.6 + after * 0.55
		local py = LIFT + 0.2 + ease * 0.5
		local at = CFrame.new(ORIGIN + P(0, py, 0)) * CFrame.Angles(0, turn, 0)
		local pn = s.prizeNode
		pn.visible = r > 0
		pn.scale = Vector3.one * math.max(0.01, ease)
		place(pn, at)
		local m = s.prize
		if m then
			if r > 0 then
				local want = s.prizeSize * math.max(0.05, ease)
				pcall(function()
					if math.abs(m:GetScale() - want) > 0.001 then
						m:ScaleTo(want)
					end
				end)
				-- The car stands on the prize's floor (the model's pivot is at its middle).
				local _, size = m:GetBoundingBox()
				m:PivotTo(at * CFrame.new(0, size.Y / 2, 0))
			else
				m:PivotTo(HIDE)
			end
		end
		-- The prize's own lights: a soft white key from the camera's side and a rim in its tier's colour.
		local keyPart, rimPart = (s :: any).keyPart :: BasePart, (s :: any).rimPart :: BasePart
		keyPart.CFrame = at * CF(0.8, 2.6, 3.2)
		rimPart.CFrame = at * CF(0, 2.4, -2.4)
		s.key.Brightness = ease * 1
		s.rim.Brightness = ease * 1.4
		if not st.revealed and after > Pc.settle - Pc.charge then
			st.revealed = true
			if s.onReveal then
				task.spawn(s.onReveal)
			end
		end
		-- Camera kick at the burst, then a slow push in, then down and in to a showroom view of the
		-- prize. Diamond also swings the camera part way round the crate.
		local kick = if show then 0 else math.max(0, 1 - after * 4) * drama.kick
		local b = raw.pos
		local push = math.min(after, 2) * drama.push
		local pos = Vector3.new(b.X + (math.random() - 0.5) * kick, b.Y + (math.random() - 0.5) * kick - push * 0.34, b.Z - push)
		local hk = math.min(1, math.max(0, (after - (Pc.settle - Pc.charge) + 0.35) / 1.1))
		local h = hk * hk * (3 - 2 * hk)
		local hero = Vector3.new(PRIZE_AT.X + (b.X - PRIZE_AT.X) * 0.8, PRIZE_AT.Y + (b.Y - PRIZE_AT.Y) * 0.45, PRIZE_AT.Z + (b.Z - PRIZE_AT.Z) * 0.8)
		pos = pos:Lerp(hero, h)
		local aim = LOOK_AT:Lerp(PRIZE_AT, h)
		if drama.orbit > 0 then
			local o = math.min(1, after / 1.8)
			local a = drama.orbit * st.vary.side * o * o * (3 - 2 * o)
			pos = rotateAbout(pos, PIVOT, a)
			aim = rotateAbout(aim, PIVOT, a)
		end
		cam.CFrame = CrateScene.shoot(pos, aim)
	else
		cam.CFrame = base
		s.beam.CFrame = HIDE
		s.prizeNode.visible = false
		place(s.prizeNode, HIDE)
		if s.prize then
			s.prize:PivotTo(HIDE)
		end
		s.key.Brightness = 0
		s.rim.Brightness = 0
	end
	place(root, CFrame.new(ORIGIN))
	for _, sh in s.showers do
		local t0 = if (sh :: any).coin then s.coinAt else s.burstAt
		if t0 then
			sh.step(now - t0, math.min(dt, 1 / 30))
		end
	end
end

-- Hides the HUD's buttons around the menu (the HUD shows its own again as it updates, so this
-- runs every frame while the depot is up).
local function hideHud()
	local hud, keep = hudRoot, hudKeep
	if not hud then
		return
	end
	if keep and not keep.Parent then
		keep = nil
	end
	for _, c in hud:GetChildren() do
		if c:IsA("GuiObject") and c ~= keep and c.Visible and not (keep and keep:IsDescendantOf(c)) then
			c.Visible = false
			hidden[c] = true
		end
	end
end

-- Takes the camera to the depot (built the first time). `area` is the part of the screen the depot
-- shows in, as fractions of the screen; `hud` is the HUD's root, whose other screens step aside
-- while the depot is up (`keep` stays: the menu the depot is drawn in).
function CrateScene.enter(area: { x: number, y: number, w: number, h: number }, hud: Instance?, keep: Instance?)
	frame = area
	if not depot then
		local f = Instance.new("Folder")
		f.Name = "CrateDepot"
		Depot(f)
		depot = f
	end
	(depot :: Folder).Parent = workspace
	hudRoot, hudKeep = hud, keep
	if active then
		fit()
		return
	end
	active = true
	hidden = {}
	hideHud()
	TownCamera.setPaused(true)
	DayNight.setIndoor({
		ambient = hex("#3d4060"),
		brightness = 0,
		exposure = 0.25,
		bloom = 0.9,
		threshold = 0.9,
		saturation = 0.1,
		contrast = 0.08,
		fog = hex("#120c1c"),
		fogStart = 12 * K,
		fogEnd = 30 * K,
	})
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	oldFov = cam.FieldOfView
	fit()
	cam.CFrame = base
	RunService:BindToRenderStep("CrateDepot", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		hideHud()
		tick(math.min(dt, 1 / 20))
	end)
end

-- The depot's part of the screen changed (the window was resized).
function CrateScene.refit(area: { x: number, y: number, w: number, h: number })
	frame = area
	if active then
		fit()
	end
end

-- Gives the camera back to the town.
function CrateScene.leave()
	if not active then
		return
	end
	active = false
	RunService:UnbindFromRenderStep("CrateDepot")
	clearStage()
	if depot then
		depot.Parent = nil
	end
	for g in hidden do
		g.Visible = true
	end
	hidden = {}
	hudRoot, hudKeep = nil, nil
	DayNight.setIndoor(nil)
	local cam = workspace.CurrentCamera
	cam.FieldOfView = oldFov
	TownCamera.setPaused(false)
end

-- Moves the scene on by `dt` seconds (the previews step it by hand).
CrateScene.step = tick

function CrateScene.active(): boolean
	return active
end

return CrateScene
