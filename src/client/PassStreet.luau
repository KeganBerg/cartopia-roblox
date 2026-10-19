--!strict
-- The Star Pass's street, as the web game's SeasonScene (scene/SeasonScene.tsx): Main Street at
-- midnight with an arch over the road for every tier, its prize on a lit sign and a star on top,
-- your race car at your tier and the season's own car parked at the finish under the last arch.
-- Drawn in a ViewportFrame inside the panel. The signs and stars are drawn over it, placed where
-- the camera sees each arch (a ViewportFrame doesn't draw lettering on parts), nearer ones in front.
-- The camera follows look(z) as PassCam does: high, behind and off to the right, looking up the
-- road, further back on narrow screens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local Builder = require(ReplicatedStorage.Shared.Models.Builder) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint) :: any
local Ui = require(script.Parent.Ui)
local Icons = require(script.Parent.Icons)
local DragStrip = require(script.Parent.DragStrip) :: any

local PassStreet = {}

local S = 10 -- studs per web unit
local GAP, FIRST = 6, 6 -- PASS_GAP, PASS_FIRST
local ROAD = 1.6 -- half the street (RaceVenues ROAD)
local LANE = 0.75 -- each racer's lane, either side of the middle
local FOV = 55
local NEAR, FAR = 10, 50 -- what's kept in the picture around the looked-at point, in web units

PassStreet.GAP, PassStreet.FIRST = GAP, FIRST

local BG = { got = "#45b649", ready = "#ffc533", locked = "#e3e9f1" }
local INK = { got = "#ffffff", ready = "#14213d", locked = "#4a6283" }
local STAR = { got = "#ffd54f", ready = "#ffb300", locked = "#78909c" }
local POST = { got = "#2e7d32", ready = "#ff8f00", locked = "#546e7a" }
local NAVY = Color3.fromHex("#14213d")
-- The web draws the signs through #c8c8c8, a little under full brightness.
local DIM = 200 / 255

export type Tier = { n: number, coins: number, parts: number, gems: number, skin: string?, car: string?, state: string }
export type Street = {
	look: (z: number) -> (),
	step: (dt: number) -> (),
	setTiers: (tiers: { Tier }) -> (),
	setCars: (mine: any?, carZ: number, prize: any?) -> (),
	destroy: () -> (),
	camera: Camera,
	frame: ViewportFrame,
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function dim(c: Color3): Color3
	return Color3.new(c.R * DIM, c.G * DIM, c.B * DIM)
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

-- Prize amounts on the signs: 1.5K, 2K, 750.
local function short(n: number): string
	if n >= 1000 then
		return if n % 1000 ~= 0 then string.format("%.1fK", n / 1000) else `{n // 1000}K`
	end
	return tostring(n)
end

-- A part of the street, kept in the picture only near where the camera looks.
local function chunk(into: Instance, name: string, z: number): Model
	local m = Instance.new("Model")
	m.Name = name
	m:SetAttribute("Z", z)
	m.Parent = into
	return m
end

-- The skyline's towers at night: lit windows up the side that faces the road, as Skyline.tsx
-- lights them after dark (not every one: a few hundred parts in all, for phones). Which windows
-- are lit is the same every time.
local function windows(tower: BasePart, into: Instance)
	local cf, size = tower.CFrame, tower.Size
	local side = if cf.Position.X > 0 then -1 else 1
	local seed = math.floor(math.abs(cf.Position.Z) + math.abs(cf.Position.X) * 7)
	local warm = { hex("#ffe08a"), hex("#ffd166"), hex("#fff1c1") }
	local cols = math.max(1, math.floor((size.Z - 4) / 6))
	local rows = math.max(1, math.floor((size.Y - 8) / 8))
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			if (seed * 73856093 + i * 19349663 + j * 83492791) % 1000 < 420 then
				local z = -size.Z / 2 + 2 + (i + 0.5) * ((size.Z - 4) / cols)
				local y = -size.Y / 2 + 5 + (j + 0.5) * ((size.Y - 8) / rows)
				part({ Name = "Window", Size = Vector3.new(0.3, 3.4, 3), CFrame = cf * CFrame.new(side * (size.X / 2 + 0.1), y, z), Color = warm[(i + j) % 3 + 1], Material = Enum.Material.Neon }, into)
			end
		end
	end
end

-- Main Street itself: the venue's road, kerbs, banners and skyline (the drag race's own scenery),
-- the shops down both sides, lamps pooling light on the pavement, and lit windows up the towers.
local function buildStreet(world: Model, last: number)
	local scene = Builder.build("race:main")
	if scene then
		scene.Name = "Venue"
		scene:PivotTo(CFrame.new())
		for _, d in scene:GetDescendants() do
			if d:IsA("BasePart") then
				local p = d.CFrame.Position
				if math.abs(p.X) > 90 and d.Size.Y > 40 then
					-- A skyline tower: kept in its own piece with its windows, near the view only.
					if p.Z / S > -20 and p.Z / S < last + FAR then
						local c = chunk(world, "Tower", p.Z / S)
						d.Parent = c
						windows(d, c)
					else
						d:Destroy()
					end
				elseif math.abs(p.Z - 1000) < 1 and math.abs(p.X) < 19 and d.Size.Z < 5 then
					-- The quarter mile's finish (its banner, posts and line) moves to the last
					-- arch, where the Star Pass's road ends.
					d.CFrame += Vector3.new(0, 0, last * S - 1000)
				elseif d.Material == Enum.Material.Neon then
					-- The lamps' bulbs, lit.
					d.Color = hex("#ffe2a0")
				end
			end
		end
		scene.Parent = world
	end
	-- The shops, then a lamp on the kerb after every other one with its pool of light on the road.
	local shops = Instance.new("Model")
	DragStrip.mainStreet(shops, math.max(0, last + 40 - 180), Vector3.zero)
	for _, slot in shops:GetChildren() do
		slot.Parent = world
	end
	shops:Destroy()
	for i, sl in DragStrip.streetSlots(last + 40) do
		if (i - 1) % 2 == 0 then
			local z = sl.z + data.buildingDef(sl.def).w + 0.7
			local c = chunk(world, "Lamp", z)
			part({ Name = "Pool", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 2.2, 2.2) * S, CFrame = CFrame.new(sl.side * (ROAD + 0.15 - 0.6) * S, 0.5, z * S) * CFrame.Angles(0, 0, math.pi / 2), Color = hex("#ffd98a"), Material = Enum.Material.Neon, Transparency = 0.86 }, c)
		end
	end
end

-- One arch's posts and bar (Arch in SeasonScene.tsx), in its state's colour.
local function archParts(t: Tier, z: number, into: Instance)
	local big = t.car ~= nil
	local half = ROAD + (if big then 0.45 else 0.25)
	local tall = if big then 3.4 else 2.7
	local post = hex(POST[t.state])
	local thick = if big then 0.22 else 0.14
	for _, sd in { -1, 1 } do
		part({ Name = "Post", Size = Vector3.new(thick, tall, thick) * S, CFrame = CFrame.new(sd * half * S, tall / 2 * S, z * S), Color = post }, into)
	end
	part({ Name = "Bar", Size = Vector3.new(half * 2 + 0.2, if big then 0.2 else 0.12, 0.12) * S, CFrame = CFrame.new(0, (tall - 0.08) * S, z * S), Color = post }, into)
end

-- The lit sign as the web's signTex draws it: a navy edge, the tier's colour, the tier number big,
-- the prize under it (a skin swatch, then coins, parts or gems, or the season car's name), and a
-- tick or lock in the corner; the star above it. 128x76 at the size of a small sign.
local function signFrame(t: Tier, parent: Instance): (Frame, UIScale)
	local holder = Ui.new("Frame", { Name = `Sign{t.n}`, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(128, 76), BackgroundColor3 = NAVY, Visible = false, Parent = parent }, { Ui.corner(10) })
	local scale = Ui.new("UIScale", { Parent = holder }) :: UIScale
	local face = Ui.new("Frame", { Name = "Face", Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundColor3 = dim(hex(BG[t.state])), Parent = holder }, { Ui.corner(7) })
	local ink = dim(hex(INK[t.state]))
	Ui.text({ Name = "Number", Text = tostring(t.n), TextSize = 32, TextColor3 = ink, Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 36), Parent = face })
	local line = Ui.new("Frame", { Name = "Prize", Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = face }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	if t.car then
		Ui.text({ Text = t.car, TextSize = 13, TextColor3 = ink, Size = UDim2.new(1, -8, 1, 0), LayoutOrder = 1, Parent = line })
	else
		if t.skin then
			local cols = {}
			for h in string.gmatch(t.skin, "#%x%x%x%x?%x?%x?") do
				local ok, c = pcall(Color3.fromHex, h)
				if ok then
					table.insert(cols, c)
				end
			end
			local sw = Ui.new("Frame", { Size = UDim2.fromOffset(16, 16), BackgroundColor3 = cols[1] or hex("#ff4081"), LayoutOrder = 1, Parent = line }, { Ui.round(), Ui.stroke(2, NAVY) })
			if #cols > 1 then
				local keys = {}
				for i, c in cols do
					table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#cols - 1), c))
				end
				Ui.new("UIGradient", { Color = ColorSequence.new(keys), Rotation = 45, Parent = sw })
			end
		end
		local text = if t.coins > 0 then short(t.coins) elseif t.parts > 0 then tostring(t.parts) else tostring(t.gems)
		if t.coins > 0 then
			local c = Icons.draw("coin", line, 18)
			c.LayoutOrder = 2
		else
			Ui.text({ Text = if t.parts > 0 then "⚙️" else "💎", TextSize = 15, Size = UDim2.fromOffset(18, 20), LayoutOrder = 2, Parent = line })
		end
		Ui.text({ Text = text, TextSize = 18, TextColor3 = ink, Size = UDim2.fromOffset(Ui.textWidth(text, 18) + 2, 22), LayoutOrder = 3, Parent = line })
	end
	if t.state ~= "ready" then
		local corner = Ui.new("Frame", { Name = "Corner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = if t.state == "got" then hex("#45b649") else Ui.WHITE, ZIndex = 2, Parent = holder }, { Ui.round(), Ui.stroke(2, NAVY) })
		if t.state == "got" then
			Icons.draw("check", corner, 12, Ui.WHITE, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		else
			Ui.text({ Text = "🔒", TextSize = 10, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = corner })
		end
	end
	-- The star on top: 1.11 sign heights' worth above the middle, as the web stacks them.
	local big = t.car ~= nil
	local up = if big then 1.25 / 1.66 * 76 else 1.11 / 1.19 * 76
	local starSize = if big then 0.72 * 1.5 / 1.66 * 76 else 0.72 / 1.19 * 76
	Ui.text({ Name = "Star", Text = "★", Body = true, Weight = "heavy", TextSize = starSize * 1.25, TextColor3 = hex(STAR[t.state]), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -up), Size = UDim2.fromOffset(starSize * 1.3, starSize * 1.3), Parent = holder })
	return holder, scale
end

-- The street in `scene` (a frame `height` tall before the HUD's scaling) for `count` tiers.
function PassStreet.new(scene: Frame, height: number, count: number): Street
	local last = FIRST + (count - 1) * GAP
	local vf = Ui.new("ViewportFrame", {
		Name = "Street",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = hex("#0b1230"),
		BorderSizePixel = 0,
		-- Midnight: a cool, dim moonlight over everything, the lamps and windows glowing.
		Ambient = Color3.fromRGB(78, 88, 130),
		LightColor = Color3.fromRGB(120, 132, 190),
		LightDirection = Vector3.new(-0.5, -1, 0.7),
		Parent = scene,
	}) :: ViewportFrame
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.Parent = vf
	vf.CurrentCamera = cam
	local world = Instance.new("Model")
	world.Name = "World"
	world.Parent = vf
	buildStreet(world, last)
	-- Pieces of the street shown only near the view, and where they go when they're not.
	local pieces: { { m: Instance, z: number } } = {}
	for _, c in world:GetChildren() do
		local z = c:GetAttribute("Z")
		if type(z) == "number" then
			table.insert(pieces, { m = c, z = z })
		end
	end
	local arches = Instance.new("Model")
	arches.Name = "Arches"
	arches.Parent = world
	local cars = Instance.new("Model")
	cars.Name = "Cars"
	cars.Parent = world
	local overlay = Ui.new("Frame", { Name = "Signs", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2, Parent = scene })
	local signs: { { f: Frame, scale: UIScale, at: Vector3, h: number } } = {}

	local want, at: number? = 0, nil
	local culled = -1e9
	local street = {} :: Street
	street.camera, street.frame = cam, vf

	function street.look(z: number)
		want = z
	end

	function street.setTiers(tiers: { Tier })
		arches:ClearAllChildren()
		for _, s in signs do
			s.f:Destroy()
		end
		table.clear(signs)
		for k, t in tiers do
			local z = FIRST + (k - 1) * GAP
			archParts(t, z, arches)
			local big = t.car ~= nil
			local tall = if big then 3.4 else 2.7
			local f, scale = signFrame(t, overlay)
			table.insert(signs, { f = f, scale = scale, at = Vector3.new(0, tall - 0.75, z - 0.08) * S, h = if big then 1.66 else 1.19 })
		end
	end

	function street.setCars(mine: any?, carZ: number, prize: any?)
		cars:ClearAllChildren()
		if mine then
			local m = DragStrip.carModel(mine.model, Paint.jobOf(mine), mine.hat, mine.mods, mine.panels, mine.trim, mine.skin, mine.modSkin)
			m.Name = "MyCar"
			m:PivotTo(CFrame.new(LANE * S, 0, carZ * S))
			m.Parent = cars
		end
		if prize then
			local m = DragStrip.carModel(prize.id, { color = prize.colors[1] }, nil, nil, nil, nil, nil, nil)
			m.Name = "SeasonCar"
			m:PivotTo(CFrame.new(-LANE * S, 0, last * S))
			m.Parent = cars
		end
	end

	-- Each frame: ease the camera to the looked-at point, keep the street near it in the
	-- picture, and set every sign where its arch is.
	function street.step(dt: number)
		local a = at or want
		a += (want - a) * math.min(1, dt * 8)
		at = a
		local size = vf.AbsoluteSize
		if size.X < 2 or size.Y < 2 then
			-- Not laid out yet: the panel's own size (its sheet less the padding).
			size = Vector2.new(428, height)
		end
		local k = math.min(1.6, math.max(1, 1.25 / (size.X / size.Y)))
		local from = Vector3.new(math.max(4.4, 3.2 * k), 5 * k, a - 4.5 * k) * S
		local cf = CFrame.lookAt(from, Vector3.new(0, 0.6, a + 6) * S)
		cam.CFrame = cf
		if math.abs(a - culled) > 2 then
			culled = a
			for _, p in pieces do
				local keep = p.z > a - NEAR and p.z < a + FAR
				p.m.Parent = if keep then world else nil
			end
		end
		-- The scene before the HUD's scaling: signs are laid out in its units.
		local w = height * size.X / size.Y
		local t = math.tan(math.rad(FOV) / 2)
		for _, s in signs do
			local rel = cf:PointToObjectSpace(s.at)
			local depth = -rel.Z
			if depth < 3 or depth > (FAR + 10) * S then
				s.f.Visible = false
			else
				local px = height / 2 / (t * depth)
				local x = w / 2 + rel.X * px
				local y = height / 2 - rel.Y * px
				local scale = px * s.h * S / 76
				s.f.Visible = x > -200 * scale and x < w + 200 * scale and y > -200 * scale and y < height + 200 * scale
				s.f.Position = UDim2.fromOffset(x, y)
				s.scale.Scale = scale
				s.f.ZIndex = 10000 - math.floor(depth)
			end
		end
	end

	function street.destroy()
		for _, p in pieces do
			p.m:Destroy()
		end
		vf:Destroy()
		overlay:Destroy()
	end

	return street
end

return PassStreet
