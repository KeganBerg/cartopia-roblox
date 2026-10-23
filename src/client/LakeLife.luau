--!strict
-- Life on the countryside lake, as the web game's scene/LakeLife.tsx draws it (Outskirts.tsx mounts
-- it on the lake in the western clearing, past the last plot): a fisherman rowing his boat out to a
-- spot, casting, waiting on a bite and reeling one in (now and then a trout) before rowing off to
-- another; gulls wheeling overhead that come down to sit on the water or the dock's posts and take
-- off again (and all come down at night or in heavy rain); and a mallard family (Ducks.tsx
-- DuckFamily) paddling about, the ducklings in a line behind their mother, the adults tipping up
-- to dabble. In winter the lake is ice: no boat and no ducks, and the gulls stand on the ice.
--
-- The lake itself is the web game's own scenery (Shared.Models.Scenery "outskirts:forest", drawn by
-- Countryside), so this only runs where Countryside drew the forest: not in the shared world. That
-- scenery was converted with one still frame of this life baked into it (the boat and fisherman
-- where he starts, the gulls in the air, the ducks): those pieces are hidden here while the live
-- ones run (BAKED). tools/models/export.test.tsx now leaves LakeLife out, as it does SpeedwayLife,
-- so the next conversion won't bake them and the list stops matching anything.
--
-- Everyone here is drawn at the townspeople's size (TownLife: a Roblox character's 5.3 studs, FIT of
-- the web's scale), the fisherman with TownLife's own figure; the boat, oars, rod, ducks and gulls
-- shrink with him, and so do their speeds, so nothing races about. The lake keeps its true size.
--
-- The web's water is live (liveWater.ts: a swell, ripples and wakes in the shader). Roblox's lake is
-- a flat mesh, so here the swell only rocks the boat and the ducks (the same three waves, about
-- the laid surface), and ripples and wakes are rings sent out by one particle emitter: where an
-- oar goes in, a bobber lands, a fish bites, a gull comes down and a duck dabbles.
--
-- Like SpeedwayLife it all runs on this player's client and never changes the game. Kept cheap
-- for phones: parts are made once and moved each frame in one BulkMoveTo, nothing moves while the
-- camera is far off, the fisherman's small features (face, collar) only follow him up close, and
-- a phone gets fewer gulls with fewer parts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local clock = require(Game:WaitForChild("clock")) :: any
local weather = require(Game:WaitForChild("weather")) :: any

local LakeLife = {}

local S = Catalog.SCALE -- studs per web unit
-- The townspeople's size (TownLife): studs per figure model unit, and how much smaller than the
-- web's 1.3x people that is. U is studs per web unit for everything on the lake.
local K = 5.3 / 0.69
local FIT = K / (1.3 * S)
local U = S * FIT
local TAU = math.pi * 2

-- Outskirts.tsx LAKE and LAKE_LIFE (web units from the town's middle): its middle, its radii, the
-- water's height and the dock's middle. Scenery's lake (Countryside) is drawn from the same numbers.
local LAKE = { x = -82, z = -14, rx = 17, rz = 11, y = -0.032 }
local DOCK = { x = LAKE.x + LAKE.rx - 2.5, z = LAKE.z + 2 }
-- The lake is ice in the real date's winter (scene/season.ts SEASON, as SeasonLook paints the town).
local FROZEN = (require(Game:WaitForChild("scene_season")) :: any).SEASON == "winter"

-- The still frame's meshes in the current Scenery "outskirts:forest", by mesh key (the forest's
-- meshes are merged by look, so each is one look of one kind of thing): the boat, its tackle and the
-- fisherman; the gulls; the ducks; and their eyes, all one dark look. And the lantern's bulb, a ball
-- (studs from the town's middle).
local BAKED: { [string]: boolean } = {}
for _, key in {
	-- Boat and fisherman.
	"a6aff94f23ab94d6", "d9a050d29acd5f69", "aff443844cab6519", "07b7aa8d74b3b6bc", "3557b0e0657bc225",
	"8625e15e89414e14", "9fb83ef198e9f884", "586bb14f3bb39bb4", "6c766ed8431ccd83", "43729a6ee65ce07e",
	"5492ac326bddb44f", "79d7b520660459fa", "6df5acf412899a09", "28fe79c249a6d5a7", "78f94938deb9a7a3",
	-- Gulls.
	"030cf98fb6512988", "8db79c98d6b45d7e", "803ce800c7de45aa", "f842b073d0e2fdc5", "4fb82399d38a097f",
	"cea0f2084c79b6fa", "683ecbfce1e74089", "a24937bd9f1a35bf",
	-- Ducks.
	"ef22303c10f83ac0", "17b8ddc5c7357daa", "e1580c77a3f8945b", "3381b72b8e9264f6", "e75dada27190bd31",
	"aef665291b9956a1", "5b4791bd7c55b6fd", "e87080aef9e34eab", "f7b16adddc6b7c64", "d6dda270dd20c2ac",
	"e1180f1650046ffe", "0004d5c5efe1a08e", "e694f17140b0c429", "794146f1dfbe73d9", "e8780fc27971e5fe",
	"ee68a37812523ec0", "1331808b67014cad",
	-- Eyes.
	"a52aeb84583dab14",
} do
	BAKED[key] = true
end
local BAKED_BULB = Vector3.new(-753.469, 4.914, -118.422)

-- Nothing moves when the camera is further than this from the lake's middle (studs); the
-- fisherman's face and collar only follow him when it's nearer than NEAR.
local FAR = 1500
local NEAR = 90

local HIDDEN = CFrame.new(0, -10000, 0)
local UPRIGHT = CFrame.Angles(0, 0, math.pi / 2) -- a Roblox cylinder (along x) stood on end
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0) -- a cylinder lying along z

local function smoothstep(a: number, b: number, x: number): number
	local u = math.clamp((x - a) / (b - a), 0, 1)
	return u * u * (3 - 2 * u)
end

-- A heading error wrapped into -pi..pi (the web's ((want - h + 3pi) % 2pi) - pi).
local function wrap(a: number): number
	return ((a + math.pi * 3) % TAU) - math.pi
end

local function part(parent: Instance, shape: Enum.PartType?, size: Vector3, color: string, material: Enum.Material?): Part
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
	p.CFrame = HIDDEN
	p.Color = Color3.fromHex(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function ellipsoid(parent: Instance, size: Vector3, color: string): Part
	local p = part(parent, Enum.PartType.Block, size, color)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

---------------------------------------------------------------------------------------------------
-- The water (liveWater.ts heightAt and floatOn), on the CPU: the swell's three long waves, steeper
-- in the wind, in web units about where the water is laid (the web lifts it so troughs never dip
-- into the banks; Roblox's flat lake isn't lifted, so neither is this).

local SWELL = {
	-- dir x, dir z, wavelength, speed
	{ 0.8, 0.6, 3.1, 0.9 },
	{ -0.35, 0.94, 2.3, 0.75 },
	{ 0.97, -0.24, 1.6, 0.6 },
}
local LIFT = 0.5

local function swell(x: number, z: number, t: number, wind: number): number
	local a = 0.012 + wind * 0.03
	local h = 0
	for _, w in SWELL do
		h += math.sin(((w[1] * x + w[2] * z) / w[3]) * TAU - t * w[4] * 2.4) * a * (w[3] / 3.1)
	end
	return h * LIFT
end

-- Where a floating thing of this length and beam (its drawn size, web units at FIT) sits on the
-- swell at x, z: its rise, pitch (nose up) and roll.
local function floatOn(x: number, z: number, heading: number, len: number, beam: number, t: number, wind: number): (number, number, number)
	local fx, fz = math.sin(heading), math.cos(heading)
	local l, b = len * FIT / 2, beam * FIT / 2
	local bow = swell(x + fx * l, z + fz * l, t, wind)
	local stern = swell(x - fx * l, z - fz * l, t, wind)
	local port = swell(x - fz * b, z + fx * b, t, wind)
	local star = swell(x + fz * b, z - fx * b, t, wind)
	return (bow + stern + port + star) / 4, math.atan2(stern - bow, len), math.atan2(port - star, beam)
end

---------------------------------------------------------------------------------------------------
-- What's drawn. Pieces are { shape, size, offset, colour } in their thing's own frame, web units
-- (scaled by U, or a duckling's smaller size, when built).

type Piece = { shape: string, size: Vector3, at: CFrame, color: string }
local function piece(list: { Piece }, shape: string, w: number, h: number, d: number, at: CFrame, color: string)
	table.insert(list, { shape = shape, size = Vector3.new(w, h, d), at = at, color = color })
end
local function at(x: number, y: number, z: number): CFrame
	return CFrame.new(x, y, z)
end

-- Builds a piece list's parts (its first `n`, or all) at `k` studs per web unit; returns the parts
-- and their offsets.
local function build(parent: Instance, list: { Piece }, k: number, n: number?): ({ BasePart }, { CFrame })
	local parts, offs = {}, {}
	for i, p in list do
		if n and i > n then
			break
		end
		local size = p.size * k
		local x: BasePart
		if p.shape == "egg" then
			x = ellipsoid(parent, size, p.color)
		elseif p.shape == "ball" then
			x = part(parent, Enum.PartType.Ball, size, p.color)
		elseif p.shape == "cyl" then
			x = part(parent, Enum.PartType.Cylinder, size, p.color)
		else
			x = part(parent, nil, size, p.color)
		end
		table.insert(parts, x)
		table.insert(offs, p.at.Rotation + p.at.Position * k)
	end
	return parts, offs
end

-- The rowboat (LakeLife.tsx hullGeo): bow towards +z, waterline at y 0, 1.7 long and 0.64 across.
-- The web lofts a rounded hull; here it's planked: a bottom, flared sides closing to the stem, a
-- transom, gunwale rails, the floor, three thwarts, the tackle box and bait bucket, and the
-- lantern on its post at the stern. The floor sits above the waterline, so the flat lake (which
-- can't be kept out of an open hull, as the web's depth-only lid does) never shows inside.
local BOAT_LEN, BOAT_BEAM = 1.7, 0.64
local HULL_PAINT, HULL_IN, RAIL = "#2e7d6b", "#b08a64", "#6d4c41"
local BOAT: { Piece } = {}
do
	piece(BOAT, "box", 0.56, 0.05, 1.3, at(0, -0.06, -0.15), HULL_PAINT)
	piece(BOAT, "box", 0.56, 0.03, 1.32, at(0, 0.025, -0.18), HULL_IN)
	piece(BOAT, "box", 0.28, 0.03, 0.22, at(0, 0.025, 0.6), HULL_IN)
	for _, sd in { -1, 1 } do
		-- Side planks, flared out a little, and the bow planks closing to the stem.
		piece(BOAT, "box", 0.03, 0.25, 1.3, at(sd * 0.3, 0.04, -0.2) * CFrame.Angles(0, 0, sd * -0.12), HULL_PAINT)
		piece(BOAT, "box", 0.045, 0.03, 1.3, at(sd * 0.315, 0.175, -0.2), RAIL)
		local dx, dz = -sd * 0.3, 0.41
		local len = math.sqrt(dx * dx + dz * dz)
		local yaw = math.atan2(dx, dz)
		piece(BOAT, "box", 0.03, 0.28, len + 0.02, at(sd * 0.15, 0.06, 0.655) * CFrame.Angles(0, yaw, 0), HULL_PAINT)
		piece(BOAT, "box", 0.045, 0.03, len + 0.03, at(sd * 0.15, 0.205, 0.655) * CFrame.Angles(-0.1, yaw, 0), RAIL)
	end
	piece(BOAT, "box", 0.56, 0.24, 0.03, at(0, 0.04, -0.85), HULL_PAINT)
	piece(BOAT, "box", 0.6, 0.03, 0.045, at(0, 0.175, -0.85), RAIL)
	-- Thwarts: stern seat, rower's seat, bow seat.
	for _, zw in { { -0.62, 0.52 }, { 0.06, 0.58 }, { 0.48, 0.5 } } do
		piece(BOAT, "box", zw[2], 0.025, 0.14, at(0, 0.1, zw[1]), "#8d6e63")
	end
	-- Tackle box and bait bucket on the floor.
	piece(BOAT, "box", 0.16, 0.08, 0.1, at(0.12, 0.08, -0.32), "#2e7d32")
	piece(BOAT, "cyl", 0.1, 0.12, 0.12, at(-0.14, 0.09, -0.38) * UPRIGHT, "#eceff1")
	-- The lantern: post, plate and cap (the bulb is its own part: it glows at night).
	piece(BOAT, "cyl", 0.5, 0.018, 0.018, at(0.17, 0.3, -0.72) * UPRIGHT, "#5d4037")
	piece(BOAT, "box", 0.07, 0.012, 0.07, at(0.17, 0.51, -0.72), "#37474f")
	piece(BOAT, "box", 0.06, 0.04, 0.06, at(0.17, 0.6, -0.72) * CFrame.Angles(0, math.pi / 4, 0), "#37474f")
end
local BULB_AT = CFrame.new(0.17 * U, 0.555 * U, -0.72 * U)
local OARLOCK = { 0.31, 0.19, 0.1 }

-- One oar (oarGeo), from the oarlock out along +x: the loom (handle to neck) and the blade.
local OAR_SHAFT = { len = 1.11, mid = 0.215, d = 0.032 }
local OAR_BLADE = { x = 0.86, w = 0.28, h = 0.014, d = 0.1 }

-- The rod (rodGeo) from the grip along +z, the bobber and the trout (fishGeo, nose along +z).
local ROD = 1.25

-- The fisherman: seated on the middle thwart facing the stern, as a rower sits, in TownLife's
-- figure. In figure model units: his hips just above the thwart; the grip (both hands, on the oar
-- handles or the rod) out in front of his chest.
local SEAT_Z = 0.06
local SEAT_HIP = 0.1125 / 1.3 + 0.02
local GRIP = Vector3.new(0, 0.14, 0.19)
-- TownLife's bones: hips, torso, head, then thighs, shins and arms (left, right) from 4 to 9.
local TORSO, HEAD = 2, 3
local THIGH = 0.115
local SHOULDER = Vector3.new(0.105, 0.255, 0)
-- LakeLife.tsx LOOK: red check shirt, orange life vest, old trousers, an olive bucket hat and a
-- grey stubble beard.
local LOOK = { shirt = "#b71c1c", check = "#7f1010", vest = "#ff7043", pants = "#6d5f45", skin = "#e0ac69", hat = "#556b2f", boot = "#3e2723", beard = "#a8a29a" }

-- Gulls (gullBodyGeo, gullWingGeo): body nose along +z, feet at y -0.03; a wing from the shoulder
-- out along +x, grey to a black tip.
local GULL: { Piece } = {}
piece(GULL, "egg", 0.105, 0.095, 0.24, at(0, 0.05, 0), "#fafafa")
piece(GULL, "ball", 0.068, 0.068, 0.068, at(0, 0.095, 0.105), "#ffffff")
piece(GULL, "box", 0.014, 0.014, 0.05, at(0, 0.09, 0.15) * CFrame.Angles(0.15, 0, 0), "#f2c230")
piece(GULL, "box", 0.07, 0.012, 0.07, at(0, 0.06, -0.13) * CFrame.Angles(0.15, 0, 0), "#fafafa")
-- A phone draws the body and head only (and the wings).
local GULL_SMALL = 2
local WING_IN = { len = 0.265, chord = 0.085, z = -0.01, sweep = 0.12, color = "#a9b4bd" }
local WING_TIP = { len = 0.085, chord = 0.045, z = -0.012, sweep = 0.35, color = "#1f1f1f" }
local GULLS, GULLS_SMALL = 7, 4

-- Mallards (Ducks.tsx duckGeo): origin at the waterline, facing +z. A drake (green head, white
-- collar, chestnut breast), a hen (mottled brown) and yellow ducklings at CHICK_SIZE.
type Plumage = { body: string, back: string, breast: string, head: string, bill: string, tail: string, collar: string? }
local DRAKE: Plumage = { body = "#d9d6cf", back = "#8a8170", breast = "#7a3b22", head = "#1f6b3a", bill = "#f2c230", tail = "#222222", collar = "#ffffff" }
local HEN: Plumage = { body = "#9b7451", back = "#6e4f35", breast = "#a57f58", head = "#8a6646", bill = "#d9862b", tail = "#7a5a3e" }
local CHICK: Plumage = { body = "#f7d64a", back = "#c9a43a", breast = "#fae37a", head = "#f5d03c", bill = "#e08a2a", tail = "#f1cc3e" }
local CHICK_SIZE = 0.48
local function duckPieces(p: Plumage, chick: boolean): { Piece }
	local list: { Piece } = {}
	piece(list, "egg", 0.164, 0.124, 0.284, at(0, 0.035, 0), p.body)
	if not chick then
		-- The darker back over the folded wings, the full breast, the tail tipped up.
		piece(list, "egg", 0.15, 0.08, 0.25, at(0, 0.062, -0.015), p.back)
		piece(list, "egg", 0.136, 0.124, 0.122, at(0, 0.05, 0.085), p.breast)
		piece(list, "egg", 0.06, 0.03, 0.1, at(0, 0.075, -0.14) * CFrame.Angles(-0.45, 0, 0), p.tail)
		if p.collar then
			piece(list, "cyl", 0.012, 0.068, 0.068, at(0, 0.088, 0.08) * CFrame.Angles(0.25, 0, 0) * UPRIGHT, p.collar)
		end
	end
	-- Neck, head and bill.
	piece(list, "egg", 0.06, 0.085, 0.06, at(0, 0.105, 0.085) * CFrame.Angles(0.25, 0, 0), p.head)
	piece(list, "egg", 0.081, 0.083, 0.1, at(0, 0.15, 0.1), p.head)
	piece(list, "box", 0.034, 0.016, 0.055, at(0, 0.137, 0.155) * CFrame.Angles(0.15, 0, 0), p.bill)
	if chick then
		piece(list, "egg", 0.084, 0.05, 0.1, at(0, 0.172, 0.094), "#8d6e2f") -- the duckling's dark cap
	end
	return list
end
local DUCK_PIECES = { drake = duckPieces(DRAKE, false), hen = duckPieces(HEN, false), chick = duckPieces(CHICK, true) }
-- The family out on the lake (LakeLife.tsx LAKE_DUCKS), where they wander (DuckFamily's cx, cz,
-- spread) and Ducks.tsx's seed.
local LAKE_DUCKS = { "drake", "hen", "chick", "chick", "chick", "chick" }
local DUCK_AROUND = { x = -LAKE.rx * 0.35, z = LAKE.rz * 0.2, spread = 0.45, seed = 4 }

-- Ripples (liveWater.ts splash): rings spreading on the water, three sizes for a dab, a splash
-- and a big one; a ring reaches about as far as the web's ripple shows.
local TEX_RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local RINGS = {
	{ upto = 0.35, from = 0.12, to = 0.9, life = 1.3, alpha = 0.55 },
	{ upto = 0.75, from = 0.18, to = 1.7, life = 1.7, alpha = 0.45 },
	{ upto = math.huge, from = 0.25, to = 2.6, life = 2.1, alpha = 0.4 },
}

---------------------------------------------------------------------------------------------------
-- The lake's life.

type Fisher = {
	mode: string,
	x: number,
	z: number,
	h: number,
	v: number,
	turn: number,
	tx: number,
	tz: number,
	t0: number,
	casts: number,
	untilT: number,
	stroke: number,
	lean: number,
	bx: number,
	bz: number,
	aimed: boolean,
	hooked: boolean,
	y: number,
	vy: number,
	pitch: number,
	vp: number,
	roll: number,
	vr: number,
	wakeAt: number,
}
type Gull = {
	mode: string,
	r: number,
	alt: number,
	w: number,
	th: number,
	from: Vector3,
	ctrl: Vector3,
	to: Vector3,
	t0: number,
	dur: number,
	untilT: number,
	perch: number,
	heading: number,
	pos: Vector3,
	prev: Vector3,
	flapPh: number,
	parts: { BasePart },
	offs: { CFrame },
}
type Duck = {
	kind: string,
	x: number,
	z: number,
	h: number,
	v: number,
	tx: number,
	tz: number,
	nextT: number,
	dab: number,
	dabAt: number,
	follow: number,
	wakeAt: number,
	parts: { BasePart },
	offs: { CFrame },
}
type Bit = { part: BasePart, bone: number, off: CFrame, near: boolean }

export type Life = {
	folder: Folder,
	origin: Vector3,
	middle: Vector3,
	small: boolean,
	time: number,
	night: number,
	wind: number,
	rain: number,
	lookAt: number,
	splashes: number,
	fisher: Fisher?,
	boat: { BasePart },
	boatOffs: { CFrame },
	bulb: BasePart?,
	bits: { Bit },
	near: boolean,
	oars: { BasePart },
	rod: BasePart?,
	line: { BasePart },
	bobber: BasePart?,
	fish: { BasePart },
	gulls: { Gull },
	ducks: { Duck },
	perches: { Vector3 },
	splashAt: BasePart,
	rings: { ParticleEmitter },
	step: (self: Life, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame }) -> (),
	stepFisher: (self: Life, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame }) -> (),
	stepGulls: (self: Life, dt: number, list: { BasePart }, cfs: { CFrame }) -> (),
	stepDucks: (self: Life, dt: number, list: { BasePart }, cfs: { CFrame }) -> (),
	splash: (self: Life, x: number, z: number, amp: number) -> (),
	water: (self: Life, x: number, z: number) -> number,
	at: (self: Life, x: number, y: number, z: number) -> Vector3,
	destroy: (self: Life) -> (),
}

local Life = {}
Life.__index = Life

-- A point in the lake (e < k of the way to the shore), clear of the dock and of `away`.
local function pick(k: number, ax: number?, az: number?, ad: number?): (number, number)
	for _ = 1, 40 do
		local a, r = math.random() * TAU, math.sqrt(math.random()) * k
		local x, z = LAKE.x + math.cos(a) * LAKE.rx * r, LAKE.z + math.sin(a) * LAKE.rz * r
		if math.sqrt((x - DOCK.x) ^ 2 + (z - DOCK.z) ^ 2) < 4.5 then
			continue
		end
		if ax and az and ad and math.sqrt((x - ax) ^ 2 + (z - az) ^ 2) < ad then
			continue
		end
		return x, z
	end
	return LAKE.x, LAKE.z
end

-- Builds the lake's life for a town whose middle is at `origin`. `small`: a phone.
function LakeLife.new(parent: Instance, origin: Vector3, small: boolean?): Life
	local folder = Instance.new("Folder")
	folder.Name = "LakeLife"
	local phone = small == true

	-- The ripple rings: one emitter of each size on a holder moved to each splash.
	local holder = part(folder, nil, Vector3.one, "#ffffff")
	holder.Name = "Ripples"
	holder.Transparency = 1
	local rings = {}
	for _, r in RINGS do
		local e = Instance.new("ParticleEmitter")
		e.Texture = TEX_RING
		e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
		e.EmissionDirection = Enum.NormalId.Top
		e.Speed = NumberRange.new(0.01)
		e.Rate = 0
		e.Enabled = false
		e.LockedToPart = false
		e.LightInfluence = 0.6
		e.Lifetime = NumberRange.new(r.life * 0.9, r.life * 1.1)
		e.Size = NumberSequence.new(r.from * U, r.to * U)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - r.alpha), NumberSequenceKeypoint.new(1, 1) })
		e.Color = ColorSequence.new(Color3.fromHex("#e3edf7"))
		e.Parent = holder
		table.insert(rings, e)
	end

	local self = {
		folder = folder,
		origin = origin,
		middle = origin + Vector3.new(LAKE.x, LAKE.y, LAKE.z) * S,
		small = phone,
		time = 0,
		night = 0,
		wind = 0,
		rain = 0,
		lookAt = 0,
		splashes = 0,
		fisher = nil :: Fisher?,
		boat = {},
		boatOffs = {},
		bulb = nil :: BasePart?,
		bits = {},
		near = true,
		oars = {},
		rod = nil :: BasePart?,
		line = {},
		bobber = nil :: BasePart?,
		fish = {},
		gulls = {},
		ducks = {},
		perches = {},
		splashAt = holder,
		rings = rings,
	}

	if not FROZEN then
		-- The fisherman, his boat and tackle.
		local tx, tz = pick(0.55)
		self.fisher = {
			mode = "row",
			x = LAKE.x + LAKE.rx * 0.35,
			z = LAKE.z + 2,
			h = -1.4,
			v = 0,
			turn = 0,
			tx = tx,
			tz = tz,
			t0 = 0,
			casts = 0,
			untilT = 0,
			stroke = 0,
			lean = 0,
			bx = 0,
			bz = 0,
			aimed = false,
			hooked = false,
			y = 0,
			vy = 0,
			pitch = 0,
			vp = 0,
			roll = 0,
			vr = 0,
			wakeAt = 0,
		}
		self.boat, self.boatOffs = build(folder, BOAT, U)
		local bulb = part(folder, Enum.PartType.Ball, Vector3.one * 0.056 * U, "#ffe082")
		local light = Instance.new("PointLight")
		light.Color = Color3.fromHex("#ffcc80")
		light.Range = 10
		light.Brightness = 1
		light.Shadows = false
		light.Enabled = false
		light.Parent = bulb
		self.bulb = bulb
		for _ = 1, 2 do
			table.insert(self.oars, part(folder, Enum.PartType.Cylinder, Vector3.new(OAR_SHAFT.len, OAR_SHAFT.d, OAR_SHAFT.d) * U, "#c8a87e"))
			table.insert(self.oars, part(folder, nil, Vector3.new(OAR_BLADE.w, OAR_BLADE.h, OAR_BLADE.d) * U, "#c8a87e"))
		end
		self.rod = part(folder, Enum.PartType.Cylinder, Vector3.new(ROD + 0.1, 0.014, 0.014) * U, "#263238")
		for _ = 1, 2 do
			local l = part(folder, nil, Vector3.new(0.04, 0.04, 1), "#eceff1")
			l.Transparency = 0.2
			table.insert(self.line, l)
		end
		self.bobber = part(folder, Enum.PartType.Ball, Vector3.one * 0.07 * U, "#e53935")
		table.insert(self.fish, ellipsoid(folder, Vector3.new(0.038, 0.062, 0.21) * U, "#9aa77e"))
		table.insert(self.fish, part(folder, nil, Vector3.new(0.012, 0.06, 0.05) * U, "#7d8a63"))

		-- TownLife's townsperson, dressed as LakeLife.tsx dresses him: a red jacket over the check
		-- shirt, a cap under the bucket hat's brim, boots.
		local TownLife = require(script.Parent:WaitForChild("TownLife")) :: any
		local p = TownLife._person("lakefisher", "0", { 0, 0 })
		p.type = "walker"
		p.colors.shirt, p.colors.pants, p.colors.skin, p.colors.hair = LOOK.check, LOOK.pants, LOOK.skin, LOOK.beard
		p.look.top, p.look.coat, p.look.hair, p.look.hat = "jacket", LOOK.shirt, "cap", LOOK.hat
		p.look.shorts, p.look.shoes = false, LOOK.boot
		local fig = TownLife._figure(p, folder)
		local bits: { Bit } = {}
		for _, b in fig.bits do
			table.insert(bits, { part = b.part, bone = b.bone, off = b.off, near = b.near })
		end
		local function add(x: BasePart, bone: number, off: CFrame, near: boolean)
			table.insert(bits, { part = x, bone = bone, off = off, near = near })
		end
		-- The life vest over the jacket, the hat's brim, and the stubble.
		add(part(fig.model, Enum.PartType.Cylinder, Vector3.new(0.13, 0.186, 0.186) * K, LOOK.vest), TORSO, CFrame.new(0, 0.165 * K, 0) * UPRIGHT, false)
		add(part(fig.model, Enum.PartType.Cylinder, Vector3.new(0.01, 0.25, 0.25) * K, LOOK.hat), HEAD, CFrame.new(0, 0.03 * K, -0.005 * K) * UPRIGHT, false)
		add(ellipsoid(fig.model, Vector3.new(0.13, 0.07, 0.08) * K, LOOK.beard), HEAD, CFrame.new(0, -0.04 * K, 0.035 * K), true)
		for _, b in bits do
			b.part.CFrame = HIDDEN
		end
		self.bits = bits
	end

	-- Gulls, wheeling at their own heights and speeds.
	for i = 0, (if phone then GULLS_SMALL else GULLS) - 1 do
		local r = 6 + (i % 4) * 2.2
		local parts, offs = build(folder, GULL, U, if phone then GULL_SMALL else nil)
		for _, w in { WING_IN, WING_IN, WING_TIP, WING_TIP } do
			table.insert(parts, part(folder, nil, Vector3.new(w.len, 0.008, w.chord) * U, w.color))
		end
		local start = Vector3.new(LAKE.x, 5 * FIT, LAKE.z)
		table.insert(self.gulls, {
			mode = "fly",
			r = r,
			alt = (4.5 + (i % 3) * 1.4) * FIT,
			-- Their speed round the circle scaled with their size, like everything else here.
			w = (2.6 / r) * (if i % 2 == 1 then 1 else 1.1) * FIT,
			th = i * 0.9,
			from = start,
			ctrl = start,
			to = start,
			t0 = 0,
			dur = 1,
			untilT = 3 + i * 3.1,
			perch = -1,
			heading = 0,
			pos = start,
			prev = start,
			flapPh = i,
			parts = parts,
			offs = offs,
		})
	end
	-- Dock posts and the end of the deck (their tops, web units), where gulls like to stand.
	for _, p in { { -2, 0.3, -0.5 }, { -2, 0.3, 0.5 }, { -0.6, 0.3, 0.5 }, { -1.5, 0.205, 0.1 } } do
		table.insert(self.perches, Vector3.new(DOCK.x + p[1], p[2], DOCK.z + p[3]))
	end

	-- The mallard family (DuckFamily), placed with Ducks.tsx's seeded random so they start where
	-- the web's do.
	if not FROZEN then
		local s = DUCK_AROUND.seed * 9301 + 49297
		local function r(): number
			s = (s * 9301 + 49297) % 233280
			return s / 233280
		end
		local mom = table.find(LAKE_DUCKS, "hen") or 0
		local prev = mom
		for i, kind in LAKE_DUCKS do
			local a, d = r() * TAU, 0.3 + r() * 0.4
			local follow = if kind == "chick" and mom > 0 then prev else 0
			if kind == "chick" then
				prev = i
			end
			local parts, offs = build(folder, DUCK_PIECES[kind], U * (if kind == "chick" then CHICK_SIZE else 1))
			table.insert(self.ducks, {
				kind = kind,
				x = DUCK_AROUND.x + math.cos(a) * LAKE.rx * d,
				z = DUCK_AROUND.z + math.sin(a) * LAKE.rz * d,
				h = r() * 6.28,
				v = 0,
				tx = DUCK_AROUND.x,
				tz = DUCK_AROUND.z,
				nextT = 0,
				dab = 0,
				dabAt = 4 + r() * 10,
				follow = follow,
				wakeAt = 0,
				parts = parts,
				offs = offs,
			})
		end
	end

	folder.Parent = parent
	return (setmetatable(self :: any, Life) :: any) :: Life
end

-- A ring spreading on the water at x, z (web units from the town's middle); amp 1 is a gull
-- landing, 0.3 a dab (liveWater.ts splash). Nothing on the ice.
function Life.splash(self: Life, x: number, z: number, amp: number)
	if FROZEN then
		return
	end
	self.splashAt.CFrame = CFrame.new(self.origin + Vector3.new(x * S, LAKE.y * S + 0.08, z * S))
	for i, r in RINGS do
		if amp <= r.upto then
			self.rings[i]:Emit(1)
			break
		end
	end
	self.splashes += 1
end

-- The water's height (studs over the town's middle) at x, z: the swell drawn at the things'
-- size, so a duck rides waves its own size.
function Life.water(self: Life, x: number, z: number): number
	return LAKE.y * S + (if FROZEN then 0 else swell(x, z, self.time, self.wind) * U)
end

-- Where a web point (x, y in studs, z) is.
function Life.at(self: Life, x: number, y: number, z: number): Vector3
	return self.origin + Vector3.new(x * S, y, z * S)
end

---------------------------------------------------------------------------------------------------
-- The fisherman (LakeLife.tsx useFrame, "Fisherman").

function Life.stepFisher(self: Life, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	local f = self.fisher :: Fisher
	local t = self.time
	local drive = 0
	-- Cast again, or after a few here row off to another spot.
	local function recast()
		f.casts += 1
		f.t0 = t
		f.aimed = false
		if f.casts < 3 then
			f.mode = "cast"
		else
			f.tx, f.tz = pick(0.6, f.x, f.z, 6)
			f.mode = "row"
		end
	end
	local prevPh = f.stroke
	if f.mode == "row" then
		local dx, dz = f.tx - f.x, f.tz - f.z
		-- Distances the boat covers are in its own lengths: everything here is FIT the web's size.
		local dist = math.sqrt(dx * dx + dz * dz) / FIT
		local err = wrap(math.atan2(dx, dz) - f.h)
		f.turn = math.clamp(err * 0.8, -0.5, 0.5)
		-- Strokes: a drive that pulls the boat on, then the recovery.
		f.stroke = (f.stroke + dt / 1.7) % 1
		local ph = f.stroke
		drive = if ph < 0.45 then math.sin((ph / 0.45) * math.pi) else 0
		if dist < 0.6 or (dist < 2 and math.abs(err) > 1.2) then
			f.mode = "cast"
			f.t0 = t
			f.casts = 0
			f.aimed = false
		end
		f.v += (drive * 0.55 * math.min(1, dist / 1.5) - f.v * 0.6) * dt
	else
		f.v -= f.v * 0.9 * dt
		f.turn *= 1 - dt
		-- Wind drifts him slowly round.
		f.turn += (math.sin(t * 0.13) * 0.04 * (0.3 + self.wind) - f.turn) * dt * 0.5
	end
	f.h += f.turn * dt * (0.4 + f.v * 2)
	f.x += math.sin(f.h) * f.v * FIT * dt
	f.z += math.cos(f.h) * f.v * FIT * dt
	-- Keep off the shore.
	local e = math.sqrt(((f.x - LAKE.x) / LAKE.rx) ^ 2 + ((f.z - LAKE.z) / LAKE.rz) ^ 2)
	if e > 0.8 then
		f.x = LAKE.x + (f.x - LAKE.x) * (0.8 / e)
		f.z = LAKE.z + (f.z - LAKE.z) * (0.8 / e)
	end
	-- Float: spring the hull towards where the water holds it, so it rocks on the swell.
	local rise, fp, fr = floatOn(f.x, f.z, f.h, BOAT_LEN, BOAT_BEAM, t, self.wind)
	local k, damp = 40, 7
	f.vy += ((rise - 0.02) - f.y) * k * dt - f.vy * damp * dt
	f.vp += (fp - drive * 0.035 - f.pitch) * k * 0.6 * dt - f.vp * damp * dt
	f.vr += (fr + f.turn * 0.04 - f.roll) * k * 0.6 * dt - f.vr * damp * dt
	f.y += f.vy * dt
	f.pitch += f.vp * dt
	f.roll += f.vr * dt
	local boat = CFrame.new(self:at(f.x, LAKE.y * S + f.y * U, f.z)) * CFrame.fromEulerAnglesYXZ(f.pitch, f.h, f.roll)
	for i, x in self.boat do
		table.insert(list, x)
		table.insert(cfs, boat * self.boatOffs[i])
	end
	table.insert(list, self.bulb :: BasePart)
	table.insert(cfs, boat * BULB_AT)
	-- A wake: a ring left behind now and then while he's under way.
	if f.v > 0.03 and t > f.wakeAt then
		f.wakeAt = t + 0.8
		self:splash(f.x - math.sin(f.h) * 0.9 * FIT, f.z - math.cos(f.h) * 0.9 * FIT, 0.3)
	end

	-- Oars: sweeping through the stroke, or shipped along the gunwales while he fishes. The blades
	-- drop in square at the catch, pull through under the surface, lift out at the finish and swing
	-- back feathered flat, clear of the water.
	local rowing = f.mode == "row"
	local ph = f.stroke
	local sweep = if rowing then (if ph < 0.45 then -0.55 + (ph / 0.45) * 1.1 else 0.55 - ((ph - 0.45) / 0.55) * 1.1) else 1.35
	local inW = if rowing then smoothstep(0, 0.06, ph) * (1 - smoothstep(0.38, 0.46, ph)) else 0
	local dip = if rowing then 0.1 - inW * 0.42 else 0.04
	local feather = if rowing then smoothstep(0.42, 0.52, ph) * (1 - smoothstep(0.88, 0.98, ph)) else 0
	local square = if rowing then (math.pi / 2) * (1 - feather) else 0
	for i, sd in { 1, -1 } do
		local lock = boat
			* CFrame.new(sd * OARLOCK[1] * U, OARLOCK[2] * U, OARLOCK[3] * U)
			* CFrame.Angles(0, sd * -sweep, 0)
			* CFrame.Angles(0, 0, sd * dip)
			* CFrame.Angles(square, 0, 0)
		local blade = lock * CFrame.new(sd * OAR_BLADE.x * U, 0, 0)
		table.insert(list, self.oars[i * 2 - 1])
		table.insert(cfs, lock * CFrame.new(sd * OAR_SHAFT.mid * U, 0, 0))
		table.insert(list, self.oars[i * 2])
		table.insert(cfs, blade)
		-- A splash where each blade goes in, a smaller one where it comes out.
		local catchIn, out = prevPh < 0.04 and ph >= 0.04, prevPh < 0.42 and ph >= 0.42
		if rowing and (catchIn or out) then
			local p = (blade.Position - self.origin) / S
			self:splash(p.X, p.Z, if catchIn then 0.4 else 0.22)
		end
	end

	-- He leans back on the drive and forward to reach for the next stroke.
	local want = if rowing then (if ph < 0.45 then -0.3 + (ph / 0.45) * 0.6 else 0.3 - ((ph - 0.45) / 0.55) * 0.6) elseif f.mode == "reel" then 0.12 else 0
	f.lean += (want - f.lean) * math.min(1, dt * 8)
	local base = boat * CFrame.new(0, 0, SEAT_Z * U) * CFrame.Angles(0, math.pi, 0)
	local hips = base * CFrame.new(0, SEAT_HIP * K, 0)
	local torso = hips * CFrame.Angles(-f.lean, 0, 0)
	local grip = torso * CFrame.new(GRIP * K)

	-- The rod: up off the water (positive tips it skywards), by what he's doing.
	local rodUp = 0.55
	local since = t - f.t0
	if f.mode == "cast" then
		-- Back over the shoulder, then whip forward; the bobber flies out and lands.
		if since < 0.7 then
			rodUp = 0.55 + (since / 0.7) * 0.9
		elseif since < 1.0 then
			rodUp = 1.45 - ((since - 0.7) / 0.3) * 1.25
		else
			rodUp = 0.2 + math.min(1, (since - 1) / 1.5) * 0.4
		end
		if not f.aimed then
			-- A few lengths out in front of him (he faces the stern), kept on the water.
			f.aimed = true
			local reach = (2.6 + math.random() * 1.6) * FIT
			local side = (math.random() - 0.5) * 1.4 * FIT
			f.bx = f.x - math.sin(f.h) * reach + math.cos(f.h) * side
			f.bz = f.z - math.cos(f.h) * reach - math.sin(f.h) * side
			local be = math.sqrt(((f.bx - LAKE.x) / LAKE.rx) ^ 2 + ((f.bz - LAKE.z) / LAKE.rz) ^ 2)
			if be > 0.9 then
				f.bx = LAKE.x + (f.bx - LAKE.x) * (0.9 / be)
				f.bz = LAKE.z + (f.bz - LAKE.z) * (0.9 / be)
			end
		end
		if since > 1.8 then
			self:splash(f.bx, f.bz, 0.6)
			f.mode = "wait"
			f.untilT = t + 6 + math.random() * 10
		end
	elseif f.mode == "wait" then
		rodUp = 0.6 + math.sin(t * 0.7) * 0.03
		if math.random() < dt * 0.25 then
			self:splash(f.bx, f.bz, 0.12) -- a nibble
		end
		if t > f.untilT then
			f.mode = "bite"
			f.t0 = t
			f.hooked = math.random() < 0.6
			self:splash(f.bx, f.bz, 0.8)
		end
	elseif f.mode == "bite" then
		rodUp = 0.95 + math.sin(since * 30) * 0.04
		if since > 0.6 then
			f.mode = "reel"
			f.t0 = t
		end
	elseif f.mode == "reel" then
		rodUp = 0.85 + (if f.hooked then math.sin(t * 9) * 0.06 else 0)
		-- The line comes in, the bobber skating towards the boat.
		local vx, vz = f.x - math.sin(f.h) * 0.9 * FIT, f.z - math.cos(f.h) * 0.9 * FIT
		local u = math.min(1, dt * 0.9)
		f.bx += (vx - f.bx) * u
		f.bz += (vz - f.bz) * u
		if f.hooked and math.random() < dt * 3 then
			self:splash(f.bx + (math.random() - 0.5) * 0.2 * FIT, f.bz + (math.random() - 0.5) * 0.2 * FIT, 0.5)
		end
		if math.sqrt((f.bx - vx) ^ 2 + (f.bz - vz) ^ 2) < 0.3 * FIT or since > 4 then
			if f.hooked then
				f.mode = "catch"
				f.t0 = t
				self:splash(f.bx, f.bz, 0.9)
			else
				recast()
			end
		end
	elseif f.mode == "catch" then
		rodUp = 1.2
		if since > 2.4 then
			recast()
		end
	end
	-- His mode may have changed: the rod's out whenever he isn't rowing.
	since = t - f.t0
	local rod = grip * CFrame.Angles(-rodUp, 0, 0)
	local tip = (rod * CFrame.new(0, 0, ROD * U)).Position
	table.insert(list, self.rod :: BasePart)
	table.insert(cfs, if f.mode == "row" then HIDDEN else rod * CFrame.new(0, 0, (ROD - 0.1) / 2 * U) * ALONG_Z)

	-- The bobber: flying out on the cast, riding the water, under on the bite, then in on the line.
	local showBob = f.mode ~= "row"
	local bob: Vector3
	if f.mode == "cast" then
		local u = math.clamp((since - 1.0) / 0.8, 0, 1)
		showBob = since >= 1.0
		local land = self:at(f.bx, self:water(f.bx, f.bz), f.bz)
		bob = tip:Lerp(land, u) + Vector3.new(0, math.sin(u * math.pi) * 1.1 * U, 0)
	elseif f.mode == "catch" then
		-- The trout swings up out of the water on the line and into the boat.
		bob = tip - Vector3.new(0, 0.35 * U, 0)
		showBob = since < 1.4
	else
		local under = if f.mode == "bite" then 0.04 * U else 0
		bob = self:at(f.bx, self:water(f.bx, f.bz) + 0.01 * U - under + math.sin(t * 2.2) * 0.004 * U, f.bz)
	end
	table.insert(list, self.bobber :: BasePart)
	table.insert(cfs, if showBob then CFrame.new(bob) else HIDDEN)
	local fishShown = f.mode == "catch" and since < 1.6
	local fish = CFrame.new(bob - Vector3.new(0, 0.08 * U, 0)) * CFrame.Angles(math.pi / 2 + math.sin(t * 18) * 0.5, t * 2, 0)
	table.insert(list, self.fish[1])
	table.insert(cfs, if fishShown then fish else HIDDEN)
	table.insert(list, self.fish[2])
	table.insert(cfs, if fishShown then fish * CFrame.new(0, 0, -0.12 * U) else HIDDEN)
	-- The line: from the rod tip, sagging to the bobber, in two lengths.
	local lineShown = showBob or fishShown
	local tight = f.mode == "bite" or f.mode == "reel" or f.mode == "catch"
	local sag = (if tight then 0.02 else 0.18) * (if f.mode == "cast" then 0.2 else 1) * U
	local mid = tip:Lerp(bob, 0.5) - Vector3.new(0, sag, 0)
	for i, ends in { { tip, mid }, { mid, bob } } do
		local l = self.line[i]
		local a, b = ends[1], ends[2]
		local len = (b - a).Magnitude
		table.insert(list, l)
		if lineShown and len > 0.01 then
			l.Size = Vector3.new(0.04, 0.04, len)
			table.insert(cfs, CFrame.lookAt((a + b) / 2, b))
		else
			table.insert(cfs, HIDDEN)
		end
	end

	-- Him: TownLife's figure, posed seated (thighs forward and a little up, shins down to the
	-- floor), the head steady as he leans, both arms reaching to the grip.
	local nearNow = eye == nil or (eye - base.Position).Magnitude < NEAR
	local head = torso * CFrame.new(0, 0.36 * K, 0) * CFrame.Angles(f.lean * 0.6, 0, 0)
	local bones = { hips, torso, head }
	for i, s in { -1, 1 } do
		local thigh = hips * CFrame.new(s * 0.045 * K, 0, 0) * CFrame.Angles(-math.pi / 2 - 0.25, 0, 0)
		bones[3 + i] = thigh
		bones[5 + i] = thigh * CFrame.new(0, -THIGH * K, 0) * CFrame.Angles(math.pi / 2, 0, 0)
	end
	for i, s in { -1, 1 } do
		-- An arm hangs along its own -y: turn that to point from the shoulder to his hand.
		local shoulder = (torso * CFrame.new(s * SHOULDER.X * K, SHOULDER.Y * K, 0)).Position
		local hand = (torso * CFrame.new(s * 0.055 * K, GRIP.Y * K, GRIP.Z * K)).Position
		local down = (hand - shoulder).Unit
		local right = torso.RightVector
		right = (right - down * right:Dot(down)).Unit
		bones[7 + i] = CFrame.fromMatrix(shoulder, right, -down)
	end
	for _, b in self.bits do
		if b.near and not nearNow then
			if self.near then
				table.insert(list, b.part)
				table.insert(cfs, HIDDEN)
			end
		else
			table.insert(list, b.part)
			table.insert(cfs, bones[b.bone] * b.off)
		end
	end
	self.near = nearNow
end

---------------------------------------------------------------------------------------------------
-- Gulls (LakeLife.tsx useFrame, "Gulls").

local function bez(a: Vector3, b: Vector3, c: Vector3, u: number): Vector3
	return a * ((1 - u) * (1 - u)) + b * (2 * (1 - u) * u) + c * (u * u)
end

function Life.stepGulls(self: Life, dt: number, list: { BasePart }, cfs: { CFrame })
	local t = self.time
	local grounded = self.night > 0.5 or self.rain > 0.6
	local taken: { [number]: boolean } = {}
	for _, gl in self.gulls do
		taken[gl.perch] = true
	end
	-- Water height for a gull, in web units.
	local function water(x: number, z: number): number
		return self:water(x, z) / S
	end
	local function circleAt(gl: Gull, th: number): Vector3
		return Vector3.new(LAKE.x + math.cos(th) * gl.r * 1.3, gl.alt, LAKE.z + math.sin(th) * gl.r)
	end
	for i0, gl in self.gulls do
		local i = i0 - 1
		gl.th += gl.w * dt
		gl.prev = gl.pos
		local flap, fold = 0, 1
		if gl.mode == "fly" then
			gl.pos = circleAt(gl, gl.th) + Vector3.new(0, math.sin(t * 0.6 + i) * 0.6 * FIT, 0)
			if t > gl.untilT or grounded then
				-- Come down: onto the water, or a free spot on the dock.
				gl.mode = "land"
				gl.t0 = t
				gl.dur = (3.2 + math.random()) / FIT
				gl.from = gl.pos
				local free = 0
				for k = 1, #self.perches do
					if not taken[k] then
						free = k
						break
					end
				end
				if free > 0 and math.random() < 0.45 then
					gl.perch = free
					taken[free] = true
					gl.to = self.perches[free] + Vector3.new(0, 0.03 * FIT, 0)
				else
					gl.perch = -1
					local x, z = pick(0.75)
					gl.to = Vector3.new(x, water(x, z), z)
				end
				local c = gl.from:Lerp(gl.to, 0.6)
				gl.ctrl = Vector3.new(c.X, gl.from.Y * 0.55 + 0.6 * FIT, c.Z)
			end
			flap = math.sin(t * 9 + gl.flapPh) * 0.65 * (if math.sin(t * 0.5 + i * 1.3) > 0.1 then 1 else 0.12)
		elseif gl.mode == "land" then
			local u = math.min(1, (t - gl.t0) / gl.dur)
			local eu = 1 - (1 - u) * (1 - u)
			if gl.perch < 0 then
				gl.to = Vector3.new(gl.to.X, water(gl.to.X, gl.to.Z), gl.to.Z)
			end
			gl.pos = bez(gl.from, gl.ctrl, gl.to, eu)
			-- Glide in, then back-pedal hard just before touching down.
			flap = if u > 0.8 then math.sin(t * 16) * 0.8 else 0.1
			if u >= 1 then
				gl.mode = "sit"
				gl.untilT = t + 8 + math.random() * 14
				if gl.perch < 0 then
					self:splash(gl.pos.X, gl.pos.Z, 1)
				end
			end
		elseif gl.mode == "sit" then
			fold = 0.6
			if gl.perch < 0 then
				-- Paddling about a little.
				gl.heading += math.sin(t * 0.3 + i) * dt * 0.3
				local x, z = gl.pos.X, gl.pos.Z
				if not FROZEN then
					x += math.sin(gl.heading) * 0.04 * FIT * dt
					z += math.cos(gl.heading) * 0.04 * FIT * dt
				end
				gl.pos = Vector3.new(x, water(x, z) - 0.015 * FIT, z)
			end
			if t > gl.untilT and not grounded then
				gl.mode = "takeoff"
				gl.t0 = t
				gl.dur = 3.5 / FIT
				gl.from = gl.pos
				gl.ctrl = gl.pos + Vector3.new(math.sin(gl.heading) * 2.5 * FIT, 0.4 * FIT, math.cos(gl.heading) * 2.5 * FIT)
				gl.to = circleAt(gl, gl.th + gl.w * gl.dur)
				gl.perch = -1
			end
		else
			local u = math.min(1, (t - gl.t0) / gl.dur)
			gl.pos = bez(gl.from, gl.ctrl, gl.to, u * u)
			flap = math.sin(t * 14 + gl.flapPh) * 0.85
			-- Running across the water on the way up.
			if u < 0.25 and math.random() < dt * 6 then
				self:splash(gl.pos.X, gl.pos.Z, 0.4)
			end
			if u >= 1 then
				gl.mode = "fly"
				gl.untilT = t + 12 + math.random() * 18
			end
		end
		local dx, dz = gl.pos.X - gl.prev.X, gl.pos.Z - gl.prev.Z
		if gl.mode ~= "sit" and dx * dx + dz * dz > 1e-10 then
			gl.heading = math.atan2(dx, dz)
		end
		local climb = if gl.mode == "sit" then 0 else math.atan2(-(gl.pos.Y - gl.prev.Y), math.max(1e-4, math.sqrt(dx * dx + dz * dz)))
		local bank = if gl.mode == "fly" then -0.35 else 0
		-- gl.pos is in web units (its height over the water at FIT, as everything's is).
		local body = CFrame.new(self.origin + gl.pos * S)
			* CFrame.fromEulerAnglesYXZ(math.clamp(climb, -0.6, 0.6), gl.heading, bank)
		local nBody = #gl.parts - 4
		for j = 1, nBody do
			table.insert(list, gl.parts[j])
			table.insert(cfs, body * gl.offs[j])
		end
		-- Wings: flapping, or folded back along the body when sitting.
		local yaw = if fold < 1 then 1.35 else 0
		local roll = if fold < 1 then 0.12 else flap
		for sd = -1, 1, 2 do
			-- Swept back a little from the shoulder, and more at the black tip (gullWingGeo bends
			-- its trailing edge back towards the tip).
			local shoulder = body * CFrame.new(sd * 0.04 * U, 0.075 * U, 0.01 * U) * CFrame.Angles(0, sd * yaw, 0) * CFrame.Angles(0, 0, sd * roll)
			local inner = shoulder * CFrame.Angles(0, sd * WING_IN.sweep, 0)
			local elbow = inner * CFrame.new(sd * WING_IN.len * fold * U, 0, 0) * CFrame.Angles(0, sd * WING_TIP.sweep, 0)
			local k = if sd > 0 then 1 else 2
			table.insert(list, gl.parts[nBody + k])
			table.insert(cfs, inner * CFrame.new(sd * WING_IN.len / 2 * fold * U, 0, WING_IN.z * U))
			table.insert(list, gl.parts[nBody + 2 + k])
			table.insert(cfs, elbow * CFrame.new(sd * WING_TIP.len / 2 * fold * U, 0, WING_TIP.z * U))
		end
	end
end

---------------------------------------------------------------------------------------------------
-- The mallard family (Ducks.tsx DuckFamily useFrame), in web units about the lake's middle.

function Life.stepDucks(self: Life, dt: number, list: { BasePart }, cfs: { CFrame })
	local t = self.time
	local rx, rz = LAKE.rx, LAKE.rz
	local scale = math.max(rx, rz)
	local boat = self.fisher
	for i, d in self.ducks do
		local lead = if d.follow > 0 then self.ducks[d.follow] else nil
		if lead then
			-- Line astern: aim for a spot just behind the duck ahead.
			d.tx = lead.x - math.sin(lead.h) * 0.2 * FIT
			d.tz = lead.z - math.cos(lead.h) * 0.2 * FIT
		elseif t > d.nextT or math.sqrt((d.tx - d.x) ^ 2 + (d.tz - d.z) ^ 2) < 0.1 * FIT then
			local a, k = math.random() * TAU, math.sqrt(math.random()) * DUCK_AROUND.spread
			d.tx = DUCK_AROUND.x + math.cos(a) * rx * k
			d.tz = DUCK_AROUND.z + math.sin(a) * rz * k
			d.nextT = t + 5 + math.random() * 7
		end
		-- Dabbling: tip up, feed, bob back. Adults only.
		if d.kind ~= "chick" then
			if d.dab > 0 then
				d.dab = math.max(0, d.dab - dt)
			elseif t > d.dabAt then
				d.dab = 2.2
				d.dabAt = t + 9 + math.random() * 14
				self:splash(LAKE.x + d.x + math.sin(d.h) * 0.12 * FIT, LAKE.z + d.z + math.cos(d.h) * 0.12 * FIT, 0.45)
			end
		end
		local dx, dz = d.tx - d.x, d.tz - d.z
		local dist = math.sqrt(dx * dx + dz * dz) / FIT
		local turn = math.clamp(wrap(math.atan2(dx, dz) - d.h), -1.6 * dt, 1.6 * dt)
		d.h += turn
		local cruise = if d.dab > 0 then 0 else (if lead then math.min(0.2, dist * 0.9) else math.min(0.11, dist * 0.4)) * (0.6 + 0.4 * math.min(2.5, scale / 1.5))
		d.v += (cruise - d.v) * math.min(1, dt * 2)
		-- Keep apart: room for a body length between adults, less for a duckling.
		for j, o in self.ducks do
			if j == i then
				continue
			end
			local room = (if d.kind == "chick" or o.kind == "chick" then 0.16 else 0.3) * FIT
			local ox, oz = d.x - o.x, d.z - o.z
			local od = math.sqrt(ox * ox + oz * oz)
			if od < room and od > 1e-4 then
				d.x += (ox / od) * (room - od) * 0.5
				d.z += (oz / od) * (room - od) * 0.5
			end
		end
		d.x += math.sin(d.h) * d.v * FIT * dt
		d.z += math.cos(d.h) * d.v * FIT * dt
		-- Stay on the water, and out from under the boat.
		local e = math.sqrt((d.x / rx) ^ 2 + (d.z / rz) ^ 2)
		if e > 0.86 then
			d.x *= 0.86 / e
			d.z *= 0.86 / e
		end
		if boat then
			local br = 1.4 * FIT
			local bx, bz = LAKE.x + d.x - boat.x, LAKE.z + d.z - boat.z
			local bd = math.sqrt(bx * bx + bz * bz)
			if bd < br and bd > 1e-4 then
				d.x += (bx / bd) * (br - bd) * math.min(1, dt * 4)
				d.z += (bz / bd) * (br - bd) * math.min(1, dt * 4)
				if not lead then
					d.tx = d.x + (bx / bd) * 1.5 * FIT
					d.tz = d.z + (bz / bd) * 1.5 * FIT
				end
			end
		end
		local wx, wz = LAKE.x + d.x, LAKE.z + d.z
		local wy = swell(wx, wz, t, self.wind)
		-- Dabbling pitches the duck nose-down, tail up.
		local tip = if d.dab > 0 then math.sin(math.min(1, (2.2 - d.dab) / 0.35, d.dab / 0.4) * math.pi / 2) * 1.25 else 0
		local y = LAKE.y * S + (wy * 0.8 + math.sin(t * 2.6 + i * 1.7) * 0.003 - tip * 0.03) * U
		local cf = CFrame.new(self:at(wx, y, wz)) * CFrame.fromEulerAnglesYXZ(tip + math.sin(t * 1.9 + i) * 0.04, d.h, math.sin(t * 2.3 + i * 2.1) * 0.05)
		for j, x in d.parts do
			table.insert(list, x)
			table.insert(cfs, cf * d.offs[j])
		end
		-- Its wake: a small ring now and then while it paddles.
		if d.v > 0.02 and t > d.wakeAt then
			d.wakeAt = t + 1.4
			self:splash(wx - math.sin(d.h) * 0.15 * FIT, wz - math.cos(d.h) * 0.15 * FIT, 0.15)
		end
	end
end

---------------------------------------------------------------------------------------------------

-- Moves everything on by dt seconds; adds what moved to BulkMoveTo's lists. `eye`: the camera.
function Life.step(self: Life, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	self.time += dt
	-- The time of day and the weather change slowly: looked up once a second.
	self.lookAt -= dt
	if self.lookAt <= 0 then
		self.lookAt = 1
		local ok, w = pcall(weather.weatherNow)
		if ok and w then
			self.wind, self.rain = w.wind or 0, w.rain or 0
		end
		self.night = clock.nightAmount(clock.dayPhase(DateTime.now().UnixTimestampMillis))
		local bulb = self.bulb
		if bulb then
			local lit = self.night > 0.3
			bulb.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
			local light = bulb:FindFirstChildOfClass("PointLight")
			if light then
				light.Enabled = lit
			end
		end
	end
	if self.fisher then
		self:stepFisher(dt, eye, list, cfs)
	end
	self:stepGulls(dt, list, cfs)
	self:stepDucks(dt, list, cfs)
end

function Life.destroy(self: Life)
	self.folder:Destroy()
end

---------------------------------------------------------------------------------------------------
-- The lake round the player's town.

local function smallScreen(): boolean
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 700
end

-- Countryside's forest (and so the lake), if it drew one: not in the shared world.
local function forestOf(): Model?
	local root = workspace:FindFirstChild("Countryside")
	return root and root:FindFirstChildOfClass("Model")
end

-- Hides the still frame of the lake's life baked into the forest (BAKED); returns how many pieces.
function LakeLife.hideBaked(forest: Model, origin: Vector3): number
	local n = 0
	for _, d in forest:GetChildren() do
		if not d:IsA("BasePart") then
			continue
		end
		local key = d:GetAttribute("Mesh")
		local hit = BAKED[d.Name] or (type(key) == "string" and BAKED[key])
		if not hit and d:IsA("Part") and d.Shape == Enum.PartType.Ball then
			hit = (d.CFrame.Position - (origin + BAKED_BULB)).Magnitude < 0.5
		end
		if hit then
			d.Transparency = 1
			d.CastShadow = false
			n += 1
		end
	end
	return n
end

-- Keeps the lake's life for a town whose middle is at `origin`; returns a function that looks for
-- the lake (drawing the life once it's there, dropping it if it goes), and one that moves it on
-- (each frame).
function LakeLife.attach(origin: Vector3, parent: Instance?): (() -> (), (dt: number) -> ())
	local life: Life? = nil
	local small = smallScreen()
	local hidden: Model? = nil
	local hiddenCount = -1
	local function scan()
		local forest = forestOf()
		if forest and not life then
			life = LakeLife.new(parent or workspace, origin, small)
		elseif not forest and life then
			life:destroy()
			life = nil
		end
		-- Hide the baked frame once the live one is up (again if the forest is redrawn or meshes
		-- arrive late and fill it in).
		if forest and (forest ~= hidden or #forest:GetChildren() ~= hiddenCount) then
			hidden, hiddenCount = forest, #forest:GetChildren()
			LakeLife.hideBaked(forest, origin)
		end
	end
	local function step(dt: number)
		local l = life
		if not l then
			return
		end
		local cam = workspace.CurrentCamera
		local eye = cam and cam.CFrame.Position
		if eye and (eye - l.middle).Magnitude > FAR then
			return
		end
		local list: { BasePart } = {}
		local cfs: { CFrame } = {}
		l:step(dt, eye, list, cfs)
		if #list > 0 then
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	return scan, step
end

function LakeLife.start()
	local Town = require(script.Parent.Town) :: any
	task.spawn(function()
		local folder: Folder? = nil
		while not folder do
			folder = Town.folder()
			if not folder then
				task.wait(0.5)
			end
		end
		local scan, step = LakeLife.attach((folder :: Folder):GetAttribute("Origin") :: any)
		-- Countryside draws the forest after the town: look for it every couple of seconds.
		scan()
		local wait = 0
		RunService.RenderStepped:Connect(function(dt)
			wait -= dt
			if wait <= 0 then
				wait = 2
				scan()
			end
			step(math.min(dt, 0.1))
		end)
	end)
end

LakeLife.LAKE = LAKE
LakeLife.FIT = FIT

return LakeLife
