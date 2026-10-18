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
-- the meadow's picture over a ground part (TownView.groundTexture).
function World.build(parent: Instance, meadow: Color3, texture: ((BasePart) -> ())?): Folder
	local root = Instance.new("Folder")
	root.Name = "World"
	-- Ground and roads are kept on every client (they're few, flat parts): far towns stream in
	-- and out, the land between them never does.
	local ground = Instance.new("Model")
	ground.Name = "Ground"
	ground.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	ground.Parent = root
	local reach = (RINGS + 0.5) * World.PITCH + 600
	local TILE = 2000 -- a part is at most 2,048 studs
	local n = math.ceil(reach * 2 / TILE)
	local size = reach * 2 / n
	for ix = 0, n - 1 do
		for iz = 0, n - 1 do
			local p = part(ground, "Meadow", Vector3.new(size, 4, size), CFrame.new(-reach + (ix + 0.5) * size, GROUND_TOP - 2.05, -reach + (iz + 0.5) * size), meadow)
			if texture then
				texture(p)
			end
		end
	end
	-- Roads along every gap between plots, out to the last ring, and round the hub.
	local asphalt = Color3.fromHex("#4a4f57")
	local line = Color3.fromHex("#f2d24b")
	local roads = Instance.new("Model")
	roads.Name = "Roads"
	roads.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	roads.Parent = root
	local length = (2 * RINGS + 1) * World.PITCH
	for k = -RINGS, RINGS + 1 do
		local at = (k - 0.5) * World.PITCH
		for _, along in { "x", "z" } do
			-- Each road in pieces of at most 2,000 studs.
			local pieces = math.ceil(length / TILE)
			local each = length / pieces
			for j = 0, pieces - 1 do
				local mid = -length / 2 + (j + 0.5) * each
				local pos = if along == "x" then Vector3.new(mid, GROUND_TOP + 0.2, at) else Vector3.new(at, GROUND_TOP + 0.2, mid)
				local sz = if along == "x" then Vector3.new(each, 0.4, World.ROAD_W) else Vector3.new(World.ROAD_W, 0.4, each)
				part(roads, "Road", sz, CFrame.new(pos), asphalt)
				local lsz = if along == "x" then Vector3.new(each, 0.1, 1.2) else Vector3.new(1.2, 0.1, each)
				part(roads, "Line", lsz, CFrame.new(pos + Vector3.new(0, 0.25, 0)), line, Enum.Material.Neon).CanCollide = false
			end
		end
	end

	-- Four roads out of the hub's square to the ring road round it.
	local spoke = World.PITCH / 2 - 260
	for _, d in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local pos = d * (260 + spoke / 2) + Vector3.new(0, GROUND_TOP + 0.2, 0)
		local sz = if d.X ~= 0 then Vector3.new(spoke, 0.4, World.ROAD_W) else Vector3.new(World.ROAD_W, 0.4, spoke)
		part(roads, "Road", sz, CFrame.new(pos), asphalt)
		local lsz = if d.X ~= 0 then Vector3.new(spoke, 0.1, 1.2) else Vector3.new(1.2, 0.1, spoke)
		part(roads, "Line", lsz, CFrame.new(pos + Vector3.new(0, 0.25, 0)), line, Enum.Material.Neon).CanCollide = false
	end

	-- The hub: a paved square with the spawn, where everyone arrives and picks a plot.
	local hub = Instance.new("Model")
	hub.Name = "Hub"
	hub.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	hub.Parent = root
	part(hub, "Square", Vector3.new(520, 0.6, 520), CFrame.new(0, GROUND_TOP + 0.3, 0), Color3.fromHex("#d9cbb0"))
	part(hub, "Ring", Vector3.new(160, 1.2, 160), CFrame.new(0, GROUND_TOP + 0.6, 0), Color3.fromHex("#7cb342"), Enum.Material.Grass)
	part(hub, "Fountain", Vector3.new(60, 6, 60), CFrame.new(0, GROUND_TOP + 3, 0) * CFrame.Angles(0, math.rad(45), 0), Color3.fromHex("#90caf9"), Enum.Material.Glass)
	local sign = part(hub, "Sign", Vector3.new(80, 24, 2), CFrame.new(0, GROUND_TOP + 30, -110), Color3.fromHex("#2263d6"))
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
	part(hub, "Post", Vector3.new(3, 30, 3), CFrame.new(-30, GROUND_TOP + 15, -110), Color3.fromHex("#5d4037"))
	part(hub, "Post", Vector3.new(3, 30, 3), CFrame.new(30, GROUND_TOP + 15, -110), Color3.fromHex("#5d4037"))

	-- A marker on every plot: a sign while it's free, the town's name once claimed.
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
		local pad = part(m, "Pad", Vector3.new(460, 0.3, 460), CFrame.new(o + Vector3.new(0, GROUND_TOP + 0.15, 0)), Color3.fromHex("#a5d6a7"))
		pad.CanCollide = false
		pad.Transparency = 0.3
		m.PrimaryPart = pad
		local board = part(m, "Board", Vector3.new(40, 16, 1.5), CFrame.new(o + Vector3.new(0, GROUND_TOP + 22, 0)), Color3.fromHex("#fff8e1"))
		local post = part(m, "Post", Vector3.new(2, 22, 2), CFrame.new(o + Vector3.new(0, GROUND_TOP + 11, 0)), Color3.fromHex("#6d4c41"))
		local _ = post
		local face = Instance.new("SurfaceGui")
		face.Face = Enum.NormalId.Front
		face.CanvasSize = Vector2.new(300, 120)
		face.Parent = board
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "FREE PLOT"
		label.TextScaled = true
		label.Font = Enum.Font.FredokaOne
		label.TextColor3 = Color3.fromHex("#2e7d32")
		label.Parent = face
		m.Parent = plots
	end
	root.Parent = parent
	return root
end

-- Marks plot i taken by a player (or free again with nil): the sign and pad step aside for the town.
function World.setOwner(root: Instance, i: number, userId: number?, name: string?)
	local m = root:FindFirstChild("Plots") and (root :: any).Plots:FindFirstChild(`Plot{i}`)
	if not m then
		return
	end
	m:SetAttribute("Free", userId == nil)
	m:SetAttribute("Owner", userId)
	m:SetAttribute("OwnerName", name)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Transparency = if userId then 1 else (if p.Name == "Pad" then 0.3 else 0)
			p.CanCollide = userId == nil and p.Name ~= "Pad"
		end
	end
end

return World
