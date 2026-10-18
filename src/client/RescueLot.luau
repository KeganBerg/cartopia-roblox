--!strict
-- Rusty's search in 3D, as the web game's RescueScene (scene/RescueScene.tsx): a dirt loop with
-- the search spots round it, each a tarp-covered heap under a glowing beacon. Tap one and the tow
-- truck drives there, the tarp flies off and the find rises into view; the crane swings out and
-- lifts a small find into the bed or hitches a car behind. The lot, its yard and the spot's
-- scenery are the web game's own ("rescue:<spot>:<n>", from tools/models), and so are the tarps,
-- the truck and the small finds. The rolls stay on the server: the scene only says when the truck
-- has parked at a spot (onArrive, which asks for revealPin) and draws what the search then says.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local Builder = require(ReplicatedStorage.Shared.Models.Builder) :: any
local DayNight = require(script.Parent.DayNight)

local RescueLot = {}

local S = 10 -- studs per web unit
local ORIGIN = Vector3.new(-30000, 0, 30000) -- far from every town, race and arcade

-- Each spot's look (RescueScene THEMES): the ground past the lot, the sky, and its tarps' colours
-- (the tarps themselves come from tools/models in those colours).
local SKY = { suburbs = "#d9f2ff", farm = "#e2f4ff", downtown = "#d0dce5", desert = "#f2dcc2", track = "#d9f2ff" }
local PAD = { suburbs = "#a58b70", farm = "#ad8e68", downtown = "#9aa0a5", desert = "#c99566", track = "#9a9fa4" }
local RARITY_GLOW = { common = "#cfd8dc", scarce = "#42a5f5", rare = "#ffb300" }

-- How long a find takes to show (BUILD), the beacon's colours as it builds up (LADDER), and the
-- camera's shake and punch-in when the tarp comes off, by what turned up.
local BUILD = { nothing = 0.3, small = 0.3, common = 0.5, scarce = 0.85, rare = 1.15 }
local LADDER = {
	nothing = { "#ffd54f" },
	small = { "#ffd54f" },
	common = { "#ffd54f", "#ffffff" },
	scarce = { "#ffd54f", "#42a5f5" },
	rare = { "#ffd54f", "#42a5f5", "#ff6d00" },
}
local SHAKE = { nothing = 0.02, small = 0.04, common = 0.08, scarce = 0.14, rare = 0.24 }
local PUNCH = { nothing = 0.02, small = 0.04, common = 0.07, scarce = 0.1, rare = 0.14 }

-- The truck and its crane (RescueScene's constants, in web units).
local PIVOT_Y = 1.05
local PIVOT_Z = -0.62
local TILT = 0.22 -- boom rise per unit of reach
local STEP = 0.05 -- trail sample spacing
local TOW_GAP = 1.5
local BED_SCALE = 0.5
local TS = 1.2
local TOW_FIRST = TOW_GAP + 0.15

-- ── The layout: an oval dirt loop with the spots spaced round it (RescueScene makeLayout) ──────

local N = 240

export type Spot = { x: number, z: number, s: number, rx: number, rz: number, yaw: number }
type Layout = { rx: number, rz: number, pts: { { number } }, cum: { number }, len: number, spots: { Spot } }

local function at(L: Layout, s: number): (number, number, number, number)
	s = ((s % L.len) + L.len) % L.len
	local lo, hi = 0, N
	while hi - lo > 1 do
		local m = (lo + hi) // 2
		if L.cum[m + 1] <= s then
			lo = m
		else
			hi = m
		end
	end
	local a, b = L.pts[lo + 1], L.pts[lo + 2]
	local seg = L.cum[lo + 2] - L.cum[lo + 1]
	if seg == 0 then
		seg = 1
	end
	local f = (s - L.cum[lo + 1]) / seg
	return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, (b[1] - a[1]) / seg, (b[2] - a[2]) / seg
end

-- The wide screen's layout (a phone plays Roblox sideways, so it's always the wide one).
function RescueLot.layout(count: number): Layout
	local rx, rz = 8.2, 5.2
	local pts, cum = {}, { 0 }
	for i = 0, N do
		local t = (i / N) * math.pi * 2
		table.insert(pts, { rx * math.sin(t), rz * math.cos(t) })
		if i > 0 then
			table.insert(cum, cum[i] + math.sqrt((pts[i + 1][1] - pts[i][1]) ^ 2 + (pts[i + 1][2] - pts[i][2]) ^ 2))
		end
	end
	local L: Layout = { rx = rx, rz = rz, pts = pts, cum = cum, len = cum[N + 1], spots = {} }
	for k = 0, count - 1 do
		local s = (L.len * (k + 1)) / (count + 1)
		local px, pz, tx, tz = at(L, s)
		-- Alternate outside and inside the loop.
		local side = if k % 2 == 1 then -1 else 1
		local off = if side > 0 then 2.1 else 1.9
		local x = px - tz * off * side
		local z = pz + tx * off * side
		table.insert(L.spots, { x = x, z = z, s = s, rx = px, rz = pz, yaw = math.atan2(px - x, pz - z) })
	end
	return L
end

-- ── Helpers ─────────────────────────────────────────────────────────────────────────────────

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function w(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z) * S
end

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

local function clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

local function backOut(t: number): number
	return 1 + 2.4 * (t - 1) ^ 3 + 1.4 * (t - 1) ^ 2
end

local function ease(v: number): number
	return v * v * (3 - 2 * v)
end

local function lerpAngle(a: number, b: number, t: number): number
	return a + math.atan2(math.sin(b - a), math.cos(b - a)) * t
end

local function tierOf(l: any): string
	return if l.kind == "car" then l.rarity elseif l.kind == "nothing" then "nothing" else "small"
end

-- A model's parts, scaled about its pivot (a copy's own sizes kept in `base`).
local function scaleTo(m: Model, k: number, base: { [BasePart]: { size: Vector3, rel: CFrame } })
	local pivot = m:GetPivot()
	for p, b in base do
		p.Size = b.size * k
		p.CFrame = pivot * (b.rel - b.rel.Position + b.rel.Position * k)
	end
end

local function baseOf(m: Model): { [BasePart]: { size: Vector3, rel: CFrame } }
	local pivot = m:GetPivot()
	local base = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			base[d] = { size = d.Size, rel = pivot:ToObjectSpace(d.CFrame) }
		end
	end
	return base
end

local function fade(m: Instance, t: number)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = t
		end
	end
end

-- A rusty find: its body paint pulled most of the way to rust, as CarModel's `rusty` does.
local function rusty(model: string): Model?
	local d = data.carDef(model)
	local c = hex(d.colors[1])
	local m = Builder.build(model, c:Lerp(hex("#8a5a3c"), 0.72))
	return m
end

local function lootModel(l: any): Model?
	if l.kind == "car" then
		return rusty(l.model)
	end
	return Builder.build(`rescue:loot:{l.kind}`)
end

-- A glowing ring on the ground, as segments (a part can't be a ring).
local function ring(parent: Instance, x: number, z: number, r0: number, r1: number, color: Color3, y: number?): { BasePart }
	local segs = {}
	local n = 24
	local r = (r0 + r1) / 2
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		table.insert(segs, part({
			Name = "Ring",
			-- (Turned by a, a part's own z runs outwards from the centre.)
			Size = Vector3.new(2 * math.pi * r / n * S * 1.08, 0.2, (r1 - r0) * S),
			CFrame = CFrame.new(w(x + math.sin(a) * r, y or 0.05, z + math.cos(a) * r)) * CFrame.Angles(0, a, 0),
			Color = color,
			Material = Enum.Material.Neon,
		}, parent))
	end
	return segs
end

-- A light beam (the web's additive cone): a camera-facing Beam from the ground up.
local function beam(parent: BasePart, height: number, w0: number, w1: number, color: Color3): Beam
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.zero
	a0.Parent = parent
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, height * S, 0)
	a1.Parent = parent
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.Width0 = w0 * S
	b.Width1 = w1 * S
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Segments = 1
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	b.Parent = parent
	return b
end

-- ── One search spot (RescueScene SearchSpot) ─────────────────────────────────────────────────

type SpotView = {
	i: number,
	at: Spot,
	folder: Folder,
	tarp: Model?,
	tarpBase: { [BasePart]: { size: Vector3, rel: CFrame } }?,
	ring: { BasePart },
	anchor: Part,
	column: Beam,
	arrow: Model,
	stage: string, -- "shut", "opening", "open"
	t0: number,
	hit: boolean,
	told: boolean,
	item: Model?,
	itemBase: { [BasePart]: { size: Vector3, rel: CFrame } }?,
	flash: Part?,
	shine: Beam?,
	shock: { BasePart }?,
	carRing: { BasePart }?,
}

-- ── The scene ───────────────────────────────────────────────────────────────────────────────

export type Callbacks = {
	onArrive: (i: number) -> (), -- 1-based spot the truck parked at
	onFound: (i: number, at: Vector2) -> (), -- a find has come into view (where, 0..1 of the screen)
	onLeft: () -> (), -- the truck has driven off home
	onBusy: (busy: boolean) -> (),
}

export type Lot = {
	update: (self: Lot, q: any, opts: { auto: boolean, leaving: boolean, magnet: boolean }) -> (),
	pick: (self: Lot, i: number) -> (),
	close: (self: Lot) -> (),
	spotAt: (self: Lot, i: number) -> Vector3,
}

local current: any = nil

function RescueLot.open(q: any, magnet: boolean, cb: Callbacks): Lot
	if current then
		current:close()
	end
	local L = RescueLot.layout(#q.pins)
	local world = Instance.new("Model")
	world.Name = "RescueLot"
	world.Parent = workspace
	local lot = Builder.build(`rescue:{q.spot}:{#q.pins}`) or Builder.build(`rescue:suburbs:{#q.pins}`) or Builder.build("rescue:suburbs:8")
	if lot then
		lot:PivotTo(CFrame.new(ORIGIN))
		lot.Parent = world
	else
		-- No lot converted yet: plain dirt, so the rest still has somewhere to stand.
		part({ Name = "Dirt", Size = Vector3.new(40 * S, 1, 30 * S), CFrame = CFrame.new(w(0, -0.05, 0)), Color = hex("#bba68c") }, world)
	end
	local sky = hex(SKY[q.spot] or SKY.suburbs)
	DayNight.setRaceFog({ color = sky, near = 38 * S, far = 120 * S })

	local self: any = {
		q = q,
		L = L,
		world = world,
		cb = cb,
		opts = { auto = false, leaving = false, magnet = magnet },
		spots = {} :: { SpotView },
		clock = 0,
		st = { mode = "intro", s = 0, v = 0, trip = 9, spur = 9, yaw = math.pi, goal = nil :: number?, busyUntil = 0, focus = -1, focusAt = -99, parked = -1 },
		taken = {} :: { number },
		grab = nil :: any,
		holding = nil :: number?,
		trail = {} :: { { x: number, z: number, yaw: number } },
		view = { x = 0, z = 0, d = 0 },
		punch = nil :: any,
		busyShown = false,
		towed = {} :: { [number]: Model },
		bed = {} :: { [number]: Model },
		closed = false,
	}
	-- Anything found before the scene came up starts aboard.
	for i, l in q.pins do
		if q.revealed[i] and l.kind ~= "nothing" then
			table.insert(self.taken, i)
		end
	end

	-- The spots: a tarp over who-knows-what under a beacon.
	for i, sp in L.spots do
		local folder = Instance.new("Folder")
		folder.Name = `Spot{i}`
		folder.Parent = world
		local open = q.revealed[i]
		local view: SpotView = {
			i = i,
			at = sp,
			folder = folder,
			ring = {},
			anchor = part({ Name = "Beacon", Size = Vector3.new(1, 1, 1), Transparency = 1, CFrame = CFrame.new(w(sp.x, 0, sp.z)) }, folder),
			column = nil :: any,
			arrow = Instance.new("Model"),
			stage = if open then "open" else "shut",
			t0 = -1,
			hit = open,
			told = open,
		}
		view.column = beam(view.anchor, 3, 1.9, 1.0, hex("#ffe082"))
		if not open then
			local tarp = Builder.build(`rescue:tarp:{q.spot}:{(i - 1) % 3}`) or Builder.build(`rescue:tarp:suburbs:{(i - 1) % 3}`)
			if tarp then
				tarp:PivotTo(CFrame.new(w(sp.x, 0, sp.z)) * CFrame.Angles(0, sp.yaw, 0))
				tarp.Parent = folder
				view.tarp = tarp
				view.tarpBase = baseOf(tarp)
			end
			view.ring = ring(folder, sp.x, sp.z, 1.0, 1.22, hex("#ffd54f"))
			-- The arrow over it, pointing down: a gold four-sided cone (four wedges round its
			-- point) and its shaft.
			local arrow = view.arrow
			arrow.Name = "Arrow"
			for k = 0, 3 do
				part({ Name = "Head", Shape = Enum.PartType.Wedge, Size = Vector3.new(0.05, 0.38, 0.22) * S, Color = hex("#ffca28"), Material = Enum.Material.Neon, CFrame = CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(0, 0, 0.11 * S) * CFrame.Angles(math.pi, 0, 0) }, arrow)
			end
			part({ Name = "Shaft", Size = Vector3.new(0.13, 0.26, 0.13) * S, Color = hex("#ffca28"), Material = Enum.Material.Neon, CFrame = CFrame.new(0, 0.3 * S, 0) }, arrow)
			arrow.WorldPivot = CFrame.new()
			arrow.Parent = folder
		else
			view.column.Enabled = false
		end
		self.spots[i] = view
	end

	-- The truck, its crane boom, cable and hook.
	local truck = Builder.build("rescue:truck") or Instance.new("Model")
	truck.Name = "Truck"
	truck.Parent = world
	local boom = part({ Name = "Boom", Size = Vector3.new(0.13 * S, 0.13 * S, 1), Color = hex("#ffb300") }, world)
	local ext = part({ Name = "BoomExt", Size = Vector3.new(0.085 * S, 0.085 * S, 1), Color = hex("#ffd54f"), Material = Enum.Material.Metal }, world)
	local cable = part({ Name = "Cable", Size = Vector3.new(0.02 * S, 1, 0.02 * S), Color = hex("#212121") }, world)
	local hook = Instance.new("Model")
	hook.Name = "Hook"
	part({ Size = Vector3.new(0.12, 0.1, 0.07) * S, Color = hex("#ffb300"), CFrame = CFrame.new(0, 0.02 * S, 0) }, hook)
	part({ Size = Vector3.new(0.1, 0.03, 0.06) * S, Color = hex("#263238"), CFrame = CFrame.new(0, -0.04 * S, 0) }, hook)
	part({ Size = Vector3.new(0.05, 0.16, 0.16) * S, Color = hex("#cfd8dc"), Material = Enum.Material.Metal, CFrame = CFrame.new(0, -0.12 * S, 0) }, hook)
	hook.WorldPivot = CFrame.new()
	hook.Parent = world
	-- The truck's amber beacons, flashing while it works.
	local lamps = {}
	for _, d in truck:GetDescendants() do
		if d:IsA("BasePart") and d.Color:ToHex():lower() == "ffb300" and d.Size.X < 0.15 * S * TS + 0.01 then
			table.insert(lamps, d)
		end
	end

	-- The camera: backed off until the whole loop and every spot fits (RescueScene fitD).
	local cam = workspace.CurrentCamera
	local tilt = 0.92
	local fov = 42
	local function fitD(): number
		local vp = cam.ViewportSize
		local aspect = if vp.Y > 0 then vp.X / vp.Y else 1.6
		local corners = {}
		for i = 1, N, 8 do
			table.insert(corners, Vector3.new(L.pts[i][1], 0, L.pts[i][2]))
		end
		for _, p in L.spots do
			for _, o in { { 1.4, 0 }, { -1.4, 0 }, { 0, 1.4 }, { 0, -1.4 } } do
				for _, y in { 0, 1.2 } do
					table.insert(corners, Vector3.new(p.x + o[1], y, p.z + o[2]))
				end
			end
		end
		local th = math.tan(math.rad(fov) / 2)
		for d = 8, 90, 0.5 do
			local pos = Vector3.new(0, math.sin(tilt) * d, math.cos(tilt) * d)
			local f = (-pos).Unit
			local r = f:Cross(Vector3.yAxis).Unit
			local u = r:Cross(f)
			local ok = true
			for _, c in corners do
				local v = c - pos
				local z = v:Dot(f)
				local nx, ny = v:Dot(r) / (z * th * aspect), v:Dot(u) / (z * th)
				if math.abs(nx) >= 0.94 or ny >= 0.74 or ny <= -0.66 then
					ok = false
					break
				end
			end
			if ok then
				return d
			end
		end
		return 90
	end
	local fit = fitD()
	self.vp = cam.ViewportSize
	cam.CameraType = Enum.CameraType.Scriptable
	local oldFov = cam.FieldOfView
	cam.FieldOfView = fov

	local function screenOf(x: number, y: number, z: number): Vector2
		local ok, v = pcall(function()
			return cam:WorldToViewportPoint(w(x, y, z))
		end)
		local vp = cam.ViewportSize
		if ok and v and vp.X > 0 then
			return Vector2.new(v.X / vp.X, v.Y / vp.Y)
		end
		return Vector2.new(0.5, 0.45)
	end

	local function pending(): boolean
		local s = self.st
		local sq = self.q
		return s.parked >= 1 and sq.revealed[s.parked] and sq.pins[s.parked].kind ~= "nothing" and not table.find(self.taken, s.parked)
	end
	self.pending = pending

	-- Where a finished find rides: small ones in the bed, cars towed in a line.
	local function bedSlot(n: number): Vector3
		return Vector3.new(if n % 2 == 1 then 0.17 else -0.17, 0.66 + (n // 4) * 0.2, -0.28 - ((n // 2) % 2) * 0.26)
	end

	-- The find at spot i comes into view: the tarp flies off, the find rises.
	local function openSpot(v: SpotView)
		if v.stage ~= "shut" then
			return
		end
		v.stage = "opening"
		v.t0 = self.clock
		local l = self.q.pins[v.i]
		local car = l.kind == "car"
		local glow = hex(if car then RARITY_GLOW[l.rarity] else "#ffe082")
		v.flash = part({ Name = "Flash", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, (if car then 3 else 1.8) * S, (if car then 3 else 1.8) * S), CFrame = CFrame.new(w(v.at.x, 0.06, v.at.z)) * CFrame.Angles(0, 0, math.pi / 2), Color = glow, Material = Enum.Material.Neon, Transparency = 1 }, v.folder)
		v.shine = beam(v.anchor, 4.8, 1.2, 0.64, glow)
		v.shine.Enabled = false
		v.shock = ring(v.folder, v.at.x, v.at.z, 0.9, 1.15, glow, 0.08)
		for _, p in v.shock :: { BasePart } do
			p.Transparency = 1
		end
		local item = lootModel(l)
		if item then
			item.Parent = v.folder
			v.item = item
			v.itemBase = baseOf(item)
			fade(item, 1)
		end
	end

	-- Everything aboard, as it should be drawn: small finds in the bed, cars on the tow line.
	local function syncAboard()
		local smalls, cars = 0, 0
		for _, i in self.taken do
			local l = self.q.pins[i]
			if l.kind == "car" then
				cars += 1
				if not self.towed[i] then
					local m = lootModel(l)
					if m then
						m.Parent = world
						self.towed[i] = m
					end
				end
			else
				smalls += 1
				if not self.bed[i] then
					local m = lootModel(l)
					if m then
						scaleTo(m, BED_SCALE * TS, baseOf(m))
						m.Parent = world
						self.bed[i] = { model = m, n = smalls - 1, base = baseOf(m) } :: any
					end
				end
			end
		end
	end
	syncAboard()

	function self.update(_, nq: any, opts: { auto: boolean, leaving: boolean, magnet: boolean })
		self.q = nq
		self.opts = opts
		for i, v in self.spots do
			if nq.revealed[i] and v.stage == "shut" then
				openSpot(v)
			end
		end
	end

	function self.pick(_, i: number)
		local s = self.st
		local sq = self.q
		if sq.flat or sq.revealed[i] or s.goal ~= nil or s.mode == "leave" or s.mode == "gone" or s.mode == "drive" then
			return
		end
		if self.clock < s.busyUntil or self.grab or pending() then
			return
		end
		s.goal = i
		if s.mode == "idle" then
			s.mode = "drive"
		end
	end

	function self.spotAt(_, i: number): Vector3
		local sp = L.spots[i]
		return w(sp.x, 0, sp.z)
	end

	-- Taps on the lot: the nearest spot to where the finger lands, within a thumb's reach.
	local function tapAt(pos: Vector2)
		local ok, ray = pcall(function()
			return cam:ViewportPointToRay(pos.X, pos.Y)
		end)
		if not ok or not ray then
			return
		end
		local o, d = ray.Origin, ray.Direction
		local best, bestD = nil, 1.6 * S
		for _, y in { 0.9, 0 } do
			if math.abs(d.Y) > 1e-6 then
				local t = (ORIGIN.Y + y * S - o.Y) / d.Y
				local hitAt = o + d * t
				for i, sp in L.spots do
					local dd = (Vector2.new(hitAt.X, hitAt.Z) - Vector2.new(w(sp.x, 0, sp.z).X, w(sp.x, 0, sp.z).Z)).Magnitude
					if dd < bestD then
						best, bestD = i, dd
					end
				end
			end
		end
		if best then
			self:pick(best)
		end
	end
	local conns = {}
	table.insert(conns, UserInputService.InputBegan:Connect(function(input: InputObject, gp: boolean)
		if gp then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			tapAt(Vector2.new(input.Position.X, input.Position.Y))
		end
	end))

	local function step(rawDt: number)
		if self.closed then
			return
		end
		local dt = math.min(rawDt, 0.1)
		self.clock += dt
		local now = self.clock
		-- The window changed (a phone turned, a window resized): fit the lot again.
		if cam.ViewportSize ~= self.vp then
			self.vp = cam.ViewportSize
			fit = fitD()
		end
		local s = self.st
		local o = self.opts
		local sq = self.q
		local k = if o.auto then 2.6 else 1
		local speed = if o.auto then 2.4 else 1

		local function driveTo(target: number): boolean
			local remaining = (((target - s.s) % L.len) + L.len) % L.len
			if remaining < 0.01 or remaining > L.len - 0.01 then
				s.s = target
				s.v = 0
				return true
			end
			if s.v == 0 then
				s.trip = math.max(11, remaining / 1.5) * k
			end
			local acc = s.trip * 1.3
			s.v = math.min(s.trip, s.v + acc * dt, math.sqrt(2 * acc * remaining) + 0.4)
			s.s += math.min(remaining, s.v * dt)
			return false
		end

		local cars, smalls = {}, {}
		for _, i in self.taken do
			table.insert(if sq.pins[i].kind == "car" then cars else smalls, i)
		end

		if o.leaving and s.mode ~= "leave" and s.mode ~= "gone" and not sq.flat and not self.grab and not pending() then
			s.mode = "leave"
			s.goal = nil
		end
		if s.mode == "intro" then
			s.v = 7 * k
			s.spur -= s.v * dt
			if s.spur <= 0 then
				s.spur = 0
				s.v = 0
				s.mode = if s.goal ~= nil then "drive" else "idle"
			end
		elseif s.mode == "idle" then
			-- A fresh find: once it has risen into view, swing the hook out for it.
			if not self.grab and pending() then
				local v = self.spots[s.parked]
				if v.stage ~= "shut" and (now - v.t0) * k > BUILD[tierOf(sq.pins[s.parked])] + 0.85 then
					self.grab = { i = s.parked, t0 = now, held = false }
				end
			end
			if o.auto and not sq.flat and now >= s.busyUntil and not self.grab and not pending() then
				-- The next unchecked spot ahead.
				local best, bestD = nil, math.huge
				for i, r in sq.revealed do
					if not r then
						local d = (((L.spots[i].s - s.s) % L.len) + L.len) % L.len
						if d < bestD then
							best, bestD = i, d
						end
					end
				end
				if best then
					s.goal = best
					s.mode = "drive"
				end
			end
		elseif s.mode == "drive" and s.goal ~= nil then
			s.parked = -1
			if driveTo(L.spots[s.goal].s) then
				local i = s.goal
				s.goal = nil
				s.mode = "idle"
				s.parked = i
				s.focus = i
				s.focusAt = now
				-- Busy until the find has come up (the search says what it is once revealPin returns).
				s.busyUntil = now + (BUILD.rare + 0.9) / k
				cb.onArrive(i)
			end
		elseif s.mode == "leave" then
			s.parked = -1
			if s.spur > 0 or driveTo(math.ceil(s.s / L.len - 0.001) * L.len) then
				s.v = math.min(9 * k, s.v + 8 * k * dt)
				s.spur += s.v * dt
				if s.spur > 10 + #cars * 1.7 then
					s.mode = "gone"
					cb.onLeft()
				end
			end
		end
		-- Arrived and the search has answered: busy only as long as this find takes to show.
		if s.parked >= 1 and sq.revealed[s.parked] and self.spots[s.parked].stage ~= "shut" then
			s.busyUntil = math.min(s.busyUntil, self.spots[s.parked].t0 + (BUILD[tierOf(sq.pins[s.parked])] + 0.9) / k)
		end
		local busy = s.mode == "drive" or s.mode == "intro" or now < s.busyUntil or self.grab ~= nil or pending()
		if busy ~= self.busyShown then
			self.busyShown = busy
			cb.onBusy(busy)
		end
		-- (What the callbacks set off can end the search, and the lot with it.)
		if self.closed then
			return
		end

		-- Place the truck.
		local x, z, yaw
		if s.spur > 0 then
			x, z = 0, L.rz + s.spur
			yaw = if s.mode == "intro" then math.pi else 0
		else
			local px, pz, tx, tz = at(L, s.s)
			x, z = px, pz
			yaw = math.atan2(tx, tz)
		end
		local dy = math.atan2(math.sin(yaw - s.yaw), math.cos(yaw - s.yaw))
		s.yaw += dy * math.min(1, dt * (if s.v > 0.1 then 14 else 6))
		truck:PivotTo(CFrame.new(w(x, if sq.flat then -0.04 else 0, z)) * CFrame.Angles(0, s.yaw, if sq.flat then 0.09 else 0))
		fade(truck, if s.mode == "gone" then 1 else 0)

		-- The trail behind it, so towed cars follow its exact path.
		local tr = self.trail
		if #tr == 0 then
			for j = 160, 1, -1 do
				table.insert(tr, { x = x, z = z + j * STEP, yaw = s.yaw })
			end
		end
		local last = tr[#tr]
		local gap = math.sqrt((x - last.x) ^ 2 + (z - last.z) ^ 2)
		if gap >= STEP then
			local n = math.floor(gap / STEP)
			for j = 1, n do
				local f = (j * STEP) / gap
				table.insert(tr, { x = last.x + (x - last.x) * f, z = last.z + (z - last.z) * f, yaw = lerpAngle(last.yaw, s.yaw, f) })
			end
			if #tr > 1200 then
				for _ = 1, #tr - 1200 do
					table.remove(tr, 1)
				end
			end
		end
		local function behind(d: number)
			return tr[math.max(1, #tr - math.floor(d / STEP + 0.5))]
		end
		local cs, sn = math.cos(s.yaw), math.sin(s.yaw)
		local function localPt(lx: number, ly: number, lz: number): Vector3
			return Vector3.new(x + (lx * cs + lz * sn) * TS, ly * TS, z + (-lx * sn + lz * cs) * TS)
		end

		-- The crane: a post at the back of the bed, a boom that swings round, lowers the hook onto a
		-- find and lifts it aboard.
		local pv = localPt(0, PIVOT_Y, PIVOT_Z)
		local rest = if #cars > 0 then { a = s.yaw + math.pi, len = 0.75 * TS, drop = 0.5 } else { a = s.yaw + math.pi, len = 0.5 * TS, drop = 0.22 }
		local function mix(p: any, q2: any, t: number)
			return { a = lerpAngle(p.a, q2.a, t), len = p.len + (q2.len - p.len) * t, drop = p.drop + (q2.drop - p.drop) * t }
		end
		local function tipOf(p: any): Vector3
			return Vector3.new(pv.X + math.sin(p.a) * p.len, pv.Y + p.len * TILT, pv.Z + math.cos(p.a) * p.len)
		end
		local pose = rest
		local g = self.grab
		if g then
			local sp = L.spots[g.i]
			local loot = sq.pins[g.i]
			local isCar = loot.kind == "car"
			local u = (now - g.t0) * k * 1.3
			local reach = math.sqrt((sp.x - pv.X) ^ 2 + (sp.z - pv.Z) ^ 2)
			local ta = math.atan2(sp.x - pv.X, sp.z - pv.Z)
			local hang = if isCar then 0.7 else 0.3
			local itemTop = if isCar then 0.72 else 0.9
			local tipY = pv.Y + reach * TILT
			local over = { a = ta, len = reach, drop = 0.3 }
			local down = { a = ta, len = reach, drop = tipY - itemTop }
			local lifted = { a = ta, len = reach, drop = math.max(0.3, tipY - itemTop - 0.6) }
			local slot = bedSlot(#smalls)
			local bedReach = (slot.Z - PIVOT_Z) * TS
			local dest = if isCar
				then { a = s.yaw + math.pi, len = 0.75 * TS, drop = 0.5 }
				else { a = s.yaw, len = bedReach, drop = PIVOT_Y * TS + bedReach * TILT - slot.Y * TS - hang * BED_SCALE * TS }
			if u < 0.45 then
				pose = mix(rest, over, ease(u / 0.45))
			elseif u < 0.7 then
				pose = mix(over, down, ease((u - 0.45) / 0.25))
			elseif u < 1.15 then
				pose = mix(down, lifted, ease((u - 0.7) / 0.45))
			else
				pose = mix(lifted, dest, ease(clamp01((u - 1.15) / 0.5)))
			end
			if u >= 0.7 and not g.held then
				g.held = true
				self.holding = g.i
			end
			local v = self.spots[g.i]
			local item = v.item
			if g.held and item then
				local tip = tipOf(pose)
				local pos = Vector3.new(tip.X, tip.Y - pose.drop - hang, tip.Z)
				local back = clamp01((u - 1.15) / 0.5)
				local iy = sp.yaw
				local scale = 1
				if isCar then
					local b = behind(TOW_FIRST + #cars * TOW_GAP)
					local e = ease(back)
					pos = Vector3.new(pos.X + (b.x - pos.X) * e, pos.Y + (0.1 - pos.Y) * e, pos.Z + (b.z - pos.Z) * e)
					iy = lerpAngle(sp.yaw, b.yaw, e)
				else
					local e = ease(back)
					local bp = localPt(slot.X, slot.Y, slot.Z)
					pos = pos + (bp - pos) * e * e
					scale = 1.4 + (BED_SCALE * TS - 1.4) * e
					iy = lerpAngle(sp.yaw, s.yaw, e)
				end
				item:PivotTo(CFrame.new(w(pos.X, pos.Y, pos.Z)) * CFrame.Angles(0, iy, 0))
				if v.itemBase then
					scaleTo(item, scale, v.itemBase)
				end
			end
			if u >= 1.7 then
				self.grab = nil
				self.holding = nil
				if item then
					item:Destroy()
					v.item = nil
				end
				table.insert(self.taken, g.i)
				syncAboard()
			end
		end
		local tip = tipOf(pose)
		local hx, hy, hz = tip.X, tip.Y - pose.drop, tip.Z
		local gone = s.mode == "gone"
		do
			local len = math.sqrt(math.max(0.05, pose.len) ^ 2 + (pose.len * TILT) ^ 2)
			local frame = CFrame.new(w(pv.X, pv.Y, pv.Z)) * CFrame.fromEulerAnglesYXZ(-math.atan(TILT), pose.a + math.pi, 0)
			local base = math.min(len, 0.55 * TS)
			boom.Size = Vector3.new(0.13 * S, 0.13 * S, (base + 0.12) * S)
			boom.CFrame = frame * CFrame.new(0, 0, -(base / 2 - 0.06) * S)
			local e2 = math.max(0.01, len - base * 0.8)
			ext.Size = Vector3.new(0.085 * S, 0.085 * S, e2 * S)
			ext.CFrame = frame * CFrame.new(0, 0, -(base * 0.8 + e2 / 2) * S)
			cable.Size = Vector3.new(0.02 * S, math.max(0.01, tip.Y - hy) * S, 0.02 * S)
			cable.CFrame = CFrame.new(w(tip.X, (tip.Y + hy) / 2, tip.Z))
			hook:PivotTo(CFrame.new(w(hx, hy, hz)) * CFrame.Angles(0, pose.a, 0))
			boom.LocalTransparencyModifier = if gone then 1 else 0
			ext.LocalTransparencyModifier = if gone then 1 else 0
			cable.LocalTransparencyModifier = if gone then 1 else 0
			fade(hook, if gone then 1 else 0)
		end
		-- Finds aboard: small ones in the bed, cars towed along the trail.
		for _, b in self.bed :: any do
			local sl = bedSlot(b.n)
			local bp = localPt(sl.X, sl.Y, sl.Z)
			b.model:PivotTo(CFrame.new(w(bp.X, bp.Y, bp.Z)) * CFrame.Angles(0, s.yaw, 0))
			fade(b.model, if gone then 1 else 0)
		end
		for n, i in cars do
			local m = self.towed[i]
			if m then
				local b = behind(TOW_FIRST + (n - 1) * TOW_GAP)
				m:PivotTo(CFrame.new(w(b.x, if n == 1 then 0.1 else 0, b.z)) * CFrame.fromEulerAnglesYXZ(if n == 1 then -0.12 else 0, b.yaw, 0))
				fade(m, if gone and s.spur > 10 then 1 else 0)
			end
		end
		-- The beacons on the cab roof flash while the truck works.
		local flashOn = busy or s.v > 0.1
		for j, l in lamps do
			l.Material = if flashOn and math.sin(now * 12 + j * math.pi) > 0 then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end

		-- The spots.
		for i, v in self.spots do
			local l = sq.pins[i]
			local tier = tierOf(l)
			local pre = BUILD[tier]
			local raw = if v.stage == "opening" then (now - v.t0) * speed elseif v.stage == "open" then 99 else -1
			local t = if raw < 0 then -1 else raw - pre
			local build = if raw < 0 then 0 else clamp01(raw / pre)
			if v.stage == "opening" and t >= 0.12 and not v.hit then
				v.hit = true
				self.punch = { at = now, tier = tier }
			end
			local fadeK = if raw < 0 then 1 else clamp01(1 - t / 0.3)
			local rate = 3.2 + build * build * 22
			local pulse = 0.5 + math.sin(now * rate + i) * 0.5
			local lad = LADDER[tier]
			local col = if raw < 0
				then hex(if o.magnet and l.kind == "car" then "#4fc3f7" else "#ffd54f")
				else hex(lad[math.min(#lad, math.floor(build * #lad * 0.999) + 1)])
			for _, seg in v.ring do
				seg.Color = col
				seg.Transparency = 1 - fadeK * math.min(1, 0.45 + pulse * 0.45 + build * 0.3)
			end
			v.column.Color = ColorSequence.new(col)
			local op = fadeK * math.min(1, 0.3 + pulse * 0.2 + build * 0.35)
			v.column.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - op * 0.8), NumberSequenceKeypoint.new(1, 1) })
			v.column.Enabled = fadeK > 0.01 and v.stage ~= "open"
			local arrowY = 1.75 + math.abs(math.sin(now * 2.4 + i)) * 0.3 + build * 0.5
			v.arrow:PivotTo(CFrame.new(w(v.at.x, arrowY + 0.1, v.at.z)) * CFrame.Angles(0, now * (1.6 + build * 14), 0))
			fade(v.arrow, if fadeK > 0.01 and v.stage ~= "open" then 1 - fadeK else 1)
			-- The tarp shakes as the find builds up, then flies off and away from the road.
			local tarp = v.tarp
			if tarp and v.tarpBase then
				local home = CFrame.new(w(v.at.x, 0, v.at.z))
				if raw >= 0 and t < 0 then
					local a = 0.02 + build * build * 0.1
					tarp:PivotTo(home * CFrame.new(0, math.abs(math.sin(now * 23)) * a * 0.9 * S, 0) * CFrame.fromEulerAnglesYXZ(math.sin(now * 71) * a, v.at.yaw + math.sin(now * 37) * a * 0.5, math.cos(now * 59) * a))
				elseif t >= 0 then
					local dx, dz = v.at.x - v.at.rx, v.at.z - v.at.rz
					local ln = math.sqrt(dx * dx + dz * dz)
					if ln == 0 then
						ln = 1
					end
					dx, dz = dx / ln, dz / ln
					local kk = clamp01((t - 0.12) / 0.55)
					local e = 1 - (1 - kk) ^ 3
					tarp:PivotTo(home * CFrame.new(dx * e * 2.6 * S, (math.sin(kk * math.pi) * 1.6 + e * 0.4) * S, dz * e * 2.6 * S) * CFrame.fromEulerAnglesYXZ(e * 2.6 * dz, v.at.yaw + e * 1.4, -e * 2.6 * dx))
					scaleTo(tarp, math.max(0.001, 1 - clamp01((kk - 0.6) / 0.4)), v.tarpBase)
					if t >= 0.9 then
						tarp:Destroy()
						v.tarp = nil
					end
				end
			end
			if v.stage ~= "shut" then
				local car = l.kind == "car"
				local takenHere = table.find(self.taken, i) ~= nil or self.holding == i
				-- A shockwave ring, the glow on the ground and a beam of light, fading.
				if v.shock then
					local sk = if t < 0.12 then 1 else clamp01((t - 0.12) / 0.6)
					local grow = 1 + sk * (if tier == "rare" then 4 elseif tier == "scarce" then 3 else 2)
					for j, seg in v.shock :: { BasePart } do
						local a = (j - 0.5) / #(v.shock :: any) * math.pi * 2
						local r = 1.025 * grow
						seg.CFrame = CFrame.new(w(v.at.x + math.sin(a) * r, 0.08, v.at.z + math.cos(a) * r)) * CFrame.Angles(0, a, 0)
						seg.Transparency = if t < 0.12 or sk >= 1 then 1 else 1 - (1 - sk) ^ 2 * (if car then 0.9 else 0.5)
					end
				end
				if v.flash then
					local f = if t < 0.25 or takenHere then 0 elseif car then 0.25 + 0.6 * clamp01(1 - (t - 0.25) / 1.2) else 0.35 * clamp01(1 - (t - 0.25) / 1.2)
					v.flash.Transparency = 1 - f * 0.7
				end
				if v.shine then
					local b = if t < 0.2 or takenHere then 0 else clamp01(1 - (t - 0.2) / 1.1)
					local op2 = b * (if car then (if l.rarity == "rare" then 0.75 elseif l.rarity == "scarce" then 0.5 else 0.28) else 0.18)
					v.shine.Enabled = op2 > 0.01
					v.shine.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - op2), NumberSequenceKeypoint.new(1, 1) })
				end
				if car and not v.carRing and t >= 0.25 then
					v.carRing = ring(v.folder, v.at.x, v.at.z, 1.12, 1.3, hex(RARITY_GLOW[l.rarity]), 0.07)
				end
				if v.carRing and takenHere then
					for _, seg in v.carRing :: { BasePart } do
						seg:Destroy()
					end
					v.carRing = nil
				end
				-- The find rises out of the ground (a car) or pops up and spins (a small find).
				local item = v.item
				if item and v.itemBase and self.holding ~= i then
					local kk = if t < 0 then 0 else clamp01((t - 0.25) / 0.55)
					local e = backOut(kk)
					fade(item, if kk > 0 then 0 else 1)
					if car then
						item:PivotTo(CFrame.new(w(v.at.x, -0.5 + e * 0.5, v.at.z)) * CFrame.Angles(0, v.at.yaw, 0))
						scaleTo(item, math.max(0.001, 0.6 + e * 0.4), v.itemBase)
					else
						local bob = if kk >= 1 then math.sin(now * 2 + i) * 0.06 else 0
						item:PivotTo(CFrame.new(w(v.at.x, e * 0.62 + bob, v.at.z)) * CFrame.Angles(0, now * 1.4 + i, 0))
						scaleTo(item, math.max(0.001, e * 1.4), v.itemBase)
					end
				end
				if v.stage == "opening" and t > 0.6 and not v.told then
					v.told = true
					cb.onFound(i, screenOf(v.at.x, 0.6, v.at.z))
					if self.closed then
						return
					end
				end
				if v.stage == "opening" and t > 1.6 then
					v.stage = "open"
				end
			end
		end

		-- The camera: the whole lot, leaning towards the truck; closer in on a find as it shows.
		local reveal = s.focus >= 1 and ((now - s.focusAt) * k < 1.8 + BUILD[tierOf(sq.pins[s.focus])] or sq.flat or self.grab ~= nil)
		local f = if reveal then L.spots[s.focus] else nil
		local lean = if s.spur > 0 then 0 else 0.18
		local gx = if f then (f.x + x) * 0.32 else x * lean
		local gz = if f then (f.z + z) * 0.32 else z * lean
		local gd = fit * (if f then 0.6 else 1)
		local vw = self.view
		if vw.d == 0 then
			vw.x, vw.z, vw.d = gx, gz, gd
		end
		local ez = 1 - math.exp(-dt * 2.6)
		vw.x += (gx - vw.x) * ez
		vw.z += (gz - vw.z) * ez
		vw.d += (gd - vw.d) * ez
		local pu = self.punch
		local since = if pu then now - pu.at else 9
		local amp = if pu then SHAKE[pu.tier] else 0
		local kick = if since < 0.6 then amp * (1 - since / 0.6) ^ 2 else 0
		local jx = if kick > 0 then math.sin(now * 61) * kick else 0
		local jz = if kick > 0 then math.cos(now * 53) * kick else 0
		local dip = if since < 0.07 then since / 0.07 else math.exp(-(since - 0.07) * 4)
		local d = vw.d * (1 - (if pu then PUNCH[pu.tier] else 0) * dip)
		cam.CFrame = CFrame.lookAt(w(vw.x + jx, math.sin(tilt) * d, vw.z + math.cos(tilt) * d + jz), w(vw.x + jx, 0, vw.z + jz))
	end
	RunService:BindToRenderStep("RescueLot", Enum.RenderPriority.Camera.Value + 1, step)
	self.step = step

	function self.close(_)
		if self.closed then
			return
		end
		self.closed = true
		RunService:UnbindFromRenderStep("RescueLot")
		for _, c in conns do
			c:Disconnect()
		end
		world:Destroy()
		DayNight.setRaceFog(nil)
		cam.FieldOfView = oldFov
		if current == self then
			current = nil
		end
	end
	current = self
	return self :: Lot
end

-- The scene up now, if any.
function RescueLot.current(): Lot?
	return current
end

return RescueLot
