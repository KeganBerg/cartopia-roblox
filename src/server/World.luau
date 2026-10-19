--!strict
-- The shared world every player in a server plays in: a hub in the middle with plots round it,
-- one town to a plot, and roads between them to drive along. A player claims a free plot when they
-- join, and their town is built on it (server/TownView at the plot's origin).
--
-- Plots sit PITCH studs apart on a square grid round the hub: the 8 next to it first, then the 16
-- round those. A town's land reaches at most ~560 studs from its middle (land plots -2..4 of the
-- web game's grid), so neighbouring towns never touch, and the gaps between them carry the roads.
-- Each plot has a marker (Workspace.World.Plots.Plot<i>) with Index, Free and Owner attributes,
-- which the clients read for the claim screen.

local World = {}

World.PITCH = 1400
World.ROAD_W = 44
local GROUND_TOP = -0.9 -- the towns' meadow level (TownView MEADOW_TOP)
local RINGS = 2
local HUB = 520 -- the hub's square, across
local LOT = 480 -- a new town's land, across (START_LAND: 3 by 3 plots of 160 studs)
local KERB = 3
local TOWN = 560 -- how far a town's land reaches from its middle (land plots -2..4)
local BASE_TOP = -1.4 -- the plain ground under everything, well under the meadow's level

-- Grid cells (gx, gz) of the plots in claim order: nearest the hub first, then round each ring.
local CELLS: { { number } } = {}
for ring = 1, RINGS do
	local list = {}
	for gx = -ring, ring do
		for gz = -ring, ring do
			if math.max(math.abs(gx), math.abs(gz)) == ring then
				table.insert(list, { gx, gz })
			end
		end
	end
	-- Sides before corners, then by angle, so the first plots sit closest to the hub.
	table.sort(list, function(a, b)
		local da, db = math.abs(a[1]) + math.abs(a[2]), math.abs(b[1]) + math.abs(b[2])
		if da ~= db then
			return da < db
		end
		return math.atan2(a[2], a[1]) < math.atan2(b[2], b[1])
	end)
	for _, c in list do
		table.insert(CELLS, c)
	end
end
World.COUNT = #CELLS

-- The middle of plot i (0-based): its x and z.
function World.originXZ(i: number): (number, number)
	local c = CELLS[i + 1]
	assert(c, `no plot {i}`)
	return c[1] * World.PITCH, c[2] * World.PITCH
end

-- The middle of plot i (0-based), on the ground.
function World.origin(i: number): Vector3
	local x, z = World.originXZ(i)
	return Vector3.new(x, 0, z)
end

-- The plot the world position (x, z) is on, or nil (the hub, or past the last ring).
function World.plotAtXZ(x: number, z: number): number?
	for i, c in CELLS do
		local dx, dz = x - c[1] * World.PITCH, z - c[2] * World.PITCH
		if math.abs(dx) < World.PITCH / 2 and math.abs(dz) < World.PITCH / 2 then
			return i - 1
		end
	end
	return nil
end

function World.plotAt(p: Vector3): number?
	return World.plotAtXZ(p.X, p.Z)
end

-- Where a player arrives when they drive over to plot i: on the road just outside the town,
-- on the side facing the hub.
function World.gate(i: number): CFrame
	local o = World.origin(i)
	local toHub = if o.Magnitude > 0 then -o.Unit else Vector3.new(0, 0, 1)
	-- Along the grid: the road runs in the gap between plots.
	local dir = if math.abs(toHub.X) >= math.abs(toHub.Z) then Vector3.new(math.sign(toHub.X), 0, 0) else Vector3.new(0, 0, math.sign(toHub.Z))
	local at = o + dir * (World.PITCH / 2)
	return CFrame.lookAt(at, o)
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- Builds the shared ground, roads, hub and plot markers into Workspace.World. meadow: the
-- ground's colour (the towns' own meadow colour, so the land between them matches); texture lays
-- the meadow's picture over a ground part (TownView.groundTexture); grass: the towns' lawn colour,
-- for the free plots and the hub's lawn.
function World.build(parent: Instance, meadow: Color3, texture: ((BasePart) -> ())?, grass: Color3?): Folder
	local lawnColor = grass or Color3.fromHex("#a9b552")
	local ROAD = Color3.fromHex("#8a9097") -- TownView's asphalt, a shade darker for the long roads
	local KERB_COLOR = Color3.fromHex("#d6d2c8")
	local EDGE = Color3.fromHex("#f5f5f0")
	local LINE = Color3.fromHex("#f2c94c")
	local PAVING = Color3.fromHex("#eadfc8") -- TownView's paving
	local PAVING_DARK = Color3.fromHex("#d2c3a3")
	local WOOD = Color3.fromHex("#8d6e63") -- Countryside's fence wood
	local root = Instance.new("Folder")
	root.Name = "World"
	-- The road grid, for the clients' traffic and roadside (client/WorldLife).
	root:SetAttribute("Pitch", World.PITCH)
	root:SetAttribute("RoadWidth", World.ROAD_W)
	root:SetAttribute("Rings", RINGS)
	root:SetAttribute("RoadTop", GROUND_TOP + 0.4)
	-- Ground and roads are kept on every client (they're few, flat parts): far towns stream in
	-- and out, the land between them never does.
	local ground = Instance.new("Model")
	ground.Name = "Ground"
	ground.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	ground.Parent = root
	-- Plain ground everywhere, sunk well under everything that lies on it, and the meadow's picture
	-- only where nothing does: a Texture must never lie under a road, lot, lawn or town, however
	-- far down, because from afar Roblox draws it through them (see TownView's ground layers). So
	-- the textured pieces fill the land between the roads, the hub's square and the towns: round
	-- each plot outside its town's land (+-560), round the hub's square and its spokes, and past
	-- the last ring. A free plot's town land gets its own pieces round its lawn, taken away when
	-- it's claimed (setOwner), when the town draws meadow on its own unbought land (TownView).
	local reach = (RINGS + 0.5) * World.PITCH + 600
	local TILE = 2000 -- a part is at most 2,048 studs
	local n = math.ceil(reach * 2 / TILE)
	local size = reach * 2 / n
	for ix = 0, n - 1 do
		for iz = 0, n - 1 do
			part(ground, "Base", Vector3.new(size, 4, size), CFrame.new(-reach + (ix + 0.5) * size, BASE_TOP - 2, -reach + (iz + 0.5) * size), meadow)
		end
	end
	-- A textured piece over x0..x1, z0..z1 (in pieces of at most TILE), top at the towns' meadow.
	local function fill(into: Instance, x0: number, x1: number, z0: number, z1: number)
		if x1 - x0 < 1 or z1 - z0 < 1 then
			return
		end
		local nx, nz = math.ceil((x1 - x0) / TILE), math.ceil((z1 - z0) / TILE)
		local sx, sz = (x1 - x0) / nx, (z1 - z0) / nz
		for a = 0, nx - 1 do
			for b = 0, nz - 1 do
				local p = part(into, "Meadow", Vector3.new(sx, 1, sz), CFrame.new(x0 + (a + 0.5) * sx, GROUND_TOP - 0.5, z0 + (b + 0.5) * sz), meadow)
				if texture then
					texture(p)
				end
			end
		end
	end
	-- A square frame: inside +-outer of (cx, cz) but outside +-inner.
	local function frame(into: Instance, cx: number, cz: number, inner: number, outer: number)
		fill(into, cx - outer, cx + outer, cz + inner, cz + outer)
		fill(into, cx - outer, cx + outer, cz - outer, cz - inner)
		fill(into, cx + inner, cx + outer, cz - inner, cz + inner)
		fill(into, cx - outer, cx - inner, cz - inner, cz + inner)
	end
	local verge = World.PITCH / 2 - (World.ROAD_W / 2 + KERB) -- from a plot's middle to its roads' kerbs
	for i = 0, World.COUNT - 1 do
		local cx, cz = World.originXZ(i)
		frame(ground, cx, cz, TOWN, verge)
		local own = Instance.new("Model")
		own.Name = `Plot{i}`
		own.Parent = ground
		frame(own, cx, cz, LOT / 2, TOWN)
	end
	-- Round the hub's square, between its four spokes.
	local spokeEdge = World.ROAD_W / 2 + KERB
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local function quad(a0: number, a1: number, b0: number, b1: number)
				fill(ground, math.min(sx * a0, sx * a1), math.max(sx * a0, sx * a1), math.min(sz * b0, sz * b1), math.max(sz * b0, sz * b1))
			end
			quad(HUB / 2, verge, spokeEdge, verge)
			quad(spokeEdge, HUB / 2, HUB / 2, verge)
		end
	end
	-- Past the last ring road.
	local last = (RINGS + 0.5) * World.PITCH + World.ROAD_W / 2 + KERB
	frame(ground, 0, 0, last, reach)

	-- Roads along every gap between plots, out to the last ring, and round the hub: the town's
	-- asphalt (TownView ASPHALT) between pale kerbs, white edge lines and a yellow middle line.
	-- (Matt paint, not Neon: from the zoomed-out view Neon glows into a smear.)
	local roads = Instance.new("Model")
	roads.Name = "Roads"
	roads.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	roads.Parent = root
	-- One straight piece of road from a to b (on the ground, along x or z).
	local function road(mid: Vector3, length: number, alongX: boolean)
		local function strip(name: string, across: number, offset: number, y: number, h: number, color: Color3)
			local sz = if alongX then Vector3.new(length, h, across) else Vector3.new(across, h, length)
			local at = mid + (if alongX then Vector3.new(0, y, offset) else Vector3.new(offset, y, 0))
			local p = part(roads, name, sz, CFrame.new(at), color)
			if name ~= "Road" then
				p.CanCollide = false
			end
		end
		strip("Road", World.ROAD_W, 0, GROUND_TOP + 0.2, 0.4, ROAD)
		for _, side in { -1, 1 } do
			strip("Kerb", KERB, side * (World.ROAD_W + KERB) / 2, GROUND_TOP + 0.15, 0.3, KERB_COLOR)
			strip("Edge", 1, side * (World.ROAD_W / 2 - 2.5), GROUND_TOP + 0.6, 0.2, EDGE)
		end
		strip("Line", 1.2, 0, GROUND_TOP + 0.6, 0.2, LINE)
	end
	local length = (2 * RINGS + 1) * World.PITCH
	for k = -RINGS, RINGS + 1 do
		local at = (k - 0.5) * World.PITCH
		for _, along in { "x", "z" } do
			-- Each road in pieces of at most 2,000 studs.
			local pieces = math.ceil(length / TILE)
			local each = length / pieces
			for j = 0, pieces - 1 do
				local mid = -length / 2 + (j + 0.5) * each
				road(if along == "x" then Vector3.new(mid, 0, at) else Vector3.new(at, 0, mid), each, along == "x")
			end
		end
	end

	-- Four roads out of the hub's square to the ring road round it.
	local spoke = World.PITCH / 2 - HUB / 2
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		road(d * (HUB / 2 + spoke / 2), spoke, d.X ~= 0)
	end

	-- The hub: a paved square where everyone arrives and picks a plot, with a round lawn and a
	-- fountain in the middle. The clients dress it with the web game's own fountain, benches,
	-- lamps, flowers and trees (client/WorldLife), which needs their meshes.
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	hub.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	hub.Parent = root
	local flat = CFrame.Angles(0, 0, math.pi / 2) -- a cylinder standing up
	part(hub, "Square", Vector3.new(HUB, 0.6, HUB), CFrame.new(0, GROUND_TOP + 0.3, 0), PAVING)
	-- A darker band of paving round the edge, and a round path round the lawn.
	for _, side in { -1, 1 } do
		part(hub, "Border", Vector3.new(HUB, 0.9, 14), CFrame.new(0, GROUND_TOP + 0.45, side * (HUB / 2 - 7)), PAVING_DARK)
		part(hub, "Border", Vector3.new(14, 0.9, HUB), CFrame.new(side * (HUB / 2 - 7), GROUND_TOP + 0.45, 0), PAVING_DARK)
	end
	local circle = part(hub, "Path", Vector3.new(1, 300, 300), CFrame.new(0, GROUND_TOP + 0.5, 0) * flat, PAVING_DARK)
	circle.Shape = Enum.PartType.Cylinder
	local lawn = part(hub, "Lawn", Vector3.new(1.4, 270, 270), CFrame.new(0, GROUND_TOP + 0.7, 0) * flat, lawnColor)
	lawn.Shape = Enum.PartType.Cylinder
	-- Paths across the lawn from each road to the fountain.
	part(hub, "Path", Vector3.new(270, 1.8, 22), CFrame.new(0, GROUND_TOP + 0.9, 0), PAVING)
	part(hub, "Path", Vector3.new(22, 1.8, 270), CFrame.new(0, GROUND_TOP + 0.9, 0), PAVING)
	-- The fountain's pool (the web fountain stands in it on the clients).
	local rim = part(hub, "Rim", Vector3.new(4, 110, 110), CFrame.new(0, GROUND_TOP + 2, 0) * flat, Color3.fromHex("#b9b2a6"))
	rim.Shape = Enum.PartType.Cylinder
	local water = part(hub, "Water", Vector3.new(0.4, 102, 102), CFrame.new(0, GROUND_TOP + 4.1, 0) * flat, Color3.fromHex("#4fb3e8"))
	water.Shape = Enum.PartType.Cylinder
	water.CanCollide = false
	local sign = part(hub, "Sign", Vector3.new(80, 24, 2), CFrame.new(0, GROUND_TOP + 30, -200), Color3.fromHex("#2263d6"))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(400, 120)
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "CARTOPIA"
	text.TextScaled = true
	text.Font = Enum.Font.FredokaOne
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Parent = gui
	part(hub, "Post", Vector3.new(3, 30, 3), CFrame.new(-30, GROUND_TOP + 15, -200), WOOD)
	part(hub, "Post", Vector3.new(3, 30, 3), CFrame.new(30, GROUND_TOP + 15, -200), WOOD)

	-- Every plot: while it's free, a mown lawn the size of a new town's land (the web game's
	-- START_LAND, 3 by 3 plots), fenced, with a sign at the corner facing the camera. The lawn is
	-- kept on every client for the claim screen; the fence streams in as players come near.
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = root
	for i = 0, World.COUNT - 1 do
		local o = World.origin(i)
		local m = Instance.new("Model")
		m.Name = `Plot{i}`
		m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		m:SetAttribute("Index", i)
		m:SetAttribute("Free", true)
		m:SetAttribute("Origin", o)
		local pad = part(m, "Pad", Vector3.new(LOT, 0.3, LOT), CFrame.new(o + Vector3.new(0, GROUND_TOP + 0.15, 0)), lawnColor)
		pad.CanCollide = false
		m.PrimaryPart = pad
		local fence = Instance.new("Model")
		fence.Name = "Fence"
		fence.Parent = m
		local half = LOT / 2
		for _, side in { -1, 1 } do
			for _, alongX in { true, false } do
				-- Posts every 60 studs and two rails, as Countryside's split-rail town line.
				local t = -half
				while t <= half + 0.01 do
					local at = if alongX then Vector3.new(t, 0, side * half) else Vector3.new(side * half, 0, t)
					part(fence, "Post", Vector3.new(1.6, 9, 1.6), CFrame.new(o + at + Vector3.new(0, GROUND_TOP + 4.5, 0)), WOOD)
					t += 60
				end
				for _, y in { 3.5, 7 } do
					local at = if alongX then Vector3.new(0, 0, side * half) else Vector3.new(side * half, 0, 0)
					local sz = if alongX then Vector3.new(LOT, 0.9, 0.7) else Vector3.new(0.7, 0.9, LOT)
					part(fence, "Rail", sz, CFrame.new(o + at + Vector3.new(0, GROUND_TOP + y, 0)), WOOD)
				end
			end
		end
		-- The sign at the lawn's corner nearest the town camera (which looks from +x, +z).
		local corner = o + Vector3.new(half - 40, 0, half - 40)
		local face = CFrame.lookAt(corner, corner + Vector3.new(1, 0, 1))
		local board = part(m, "Board", Vector3.new(60, 24, 1.5), face * CFrame.new(0, GROUND_TOP + 26, 0), Color3.fromHex("#fff8e1"))
		for _, x in { -24, 24 } do
			part(m, "Post", Vector3.new(2, 26, 2), face * CFrame.new(x, GROUND_TOP + 13, 0.8), WOOD)
		end
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Front
		surface.CanvasSize = Vector2.new(300, 120)
		surface.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "FREE PLOT"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromHex("#2e7d32")
		label.Parent = surface
		m.Parent = plots
	end
	root.Parent = parent
	return root
end

-- Each claimed plot's meadow pieces, while they're out of the world.
local taken: { [number]: Instance } = {}

-- Marks plot i taken by a player (or free again with nil): the sign and pad step aside for the town.
function World.setOwner(root: Instance, i: number, userId: number?, name: string?)
	local m = root:FindFirstChild("Plots") and (root :: any).Plots:FindFirstChild(`Plot{i}`)
	if not m then
		return
	end
	m:SetAttribute("Free", userId == nil)
	-- The meadow over the town's land steps aside for the town's own ground.
	local ground = root:FindFirstChild("Ground")
	local fills = (ground and ground:FindFirstChild(`Plot{i}`)) or taken[i]
	if fills and ground then
		taken[i] = fills
		fills.Parent = if userId then nil else ground
	end
	m:SetAttribute("Owner", userId)
	m:SetAttribute("OwnerName", name)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = if userId then 1 else 0
			p.CanCollide = userId == nil and p.Name ~= "Pad"
		end
	end
end

return World
