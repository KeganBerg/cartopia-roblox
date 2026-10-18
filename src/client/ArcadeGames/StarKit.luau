--!strict
-- What Pit Stop and Car Wash Frenzy share, as the web game's StarGame shell (ui/ArcadeMore.tsx)
-- and scene/ArcadeScenery.tsx do: the top bar with the title and the X, the 3-2-1 countdown
-- (ui/ArcadeBits.tsx Countdown), the HUD pills (.arc-hud), the player's car drawn to a set length,
-- crew people, tyres and tool chests, and the camera taken over and given back.
-- Not a game itself: the hub loads the games by name (Pit, Wash, ...), never this one.
--
-- The web's arcade scenes are in world units; here they are 10 studs to the unit (S), built at
-- the hub's ctx.origin.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Ui = require(script.Parent.Parent.Ui)
local Builder = require(ReplicatedStorage.Shared.Models.Builder) :: any
local Catalog = require(ReplicatedStorage.Shared.Models.Catalog) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint) :: any

local Kit = {}

Kit.S = 10 -- studs per web unit

function Kit.hex(h: string): Color3
	return Color3.fromHex(h)
end

-- A plain anchored part that nothing bumps into or clicks.
function Kit.part(props: { [string]: any }, parent: Instance): Part
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

-- Lettering on a part's +Z face (the web's signTexture: words on a colour).
function Kit.sign(p: BasePart, text: string, fg: string, bg: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Kit.hex(bg)
	label.BorderSizePixel = 0
	label.TextColor3 = Kit.hex(fg)
	label.Text = text
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = p
end

-- ── The player's car ───────────────────────────────────────────────────────────────────────────

export type Car = {
	model: Model,
	parts: { BasePart },
	rel: { CFrame }, -- each part from the car's root, after scaling
	len: number, -- studs, nose to tail
	wid: number,
	height: number,
	-- The wheels' corners in the car's own frame (x across, z forward, studs, scaled), each with
	-- the parts that make it up.
	corners: { { x: number, y: number, z: number, parts: { number } } },
}

local function library(id: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local cars = lib and lib:FindFirstChild("Cars")
	local src = cars and cars:FindFirstChild(id)
	return if src then (src:Clone() :: Model) else nil
end

-- Draws a car ({ model, color, finish, ... } as a save's car, or a town car's id and colour)
-- `length` studs long, under `parent`, with the extras the drag race puts on it.
function Kit.car(car: any, length: number, parent: Instance): Car
	local id = car.model or car.id
	local m = library(id) or Builder.build(id, Kit.hex(car.color or "#e53935")) or Instance.new("Model")
	m.Name = "Car"
	pcall(function()
		Paint.apply(m, Paint.jobOf(car), nil)
		local Models = ReplicatedStorage.Shared.Models
		local Panels = require(Models.Panels) :: any
		local Trim = require(Models.Trim) :: any
		local Mods = require(Models.Mods) :: any
		local Skins = require(Models.Skins) :: any
		Panels.apply(m, id, car.panels, car.finish or "gloss", Builder.build)
		Trim.apply(m, id, car.trim, car.color)
		Paint.wearHat(m, id, car.hat, Builder.build)
		Mods.fit(m, id, car.mods, Builder.build)
		Skins.apply(m, car.skin, car.modSkin)
	end)
	m:PivotTo(CFrame.new())
	local parts: { BasePart } = {}
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			table.insert(parts, d)
			if d.Transparency < 0.9 then
				local half = d.Size / 2
				for _, c in { Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, -1) } do
					local w = d.CFrame * (half * c)
					lo = lo:Min(w)
					hi = hi:Max(w)
				end
			end
		end
	end
	if lo.X == math.huge then
		lo, hi = Vector3.new(-4, 0, -8), Vector3.new(4, 6, 8)
	end
	local k = length / math.max(1, hi.Z - lo.Z)
	local rel: { CFrame } = {}
	for i, d in parts do
		local cf = d.CFrame
		d.Size *= k
		rel[i] = cf - cf.Position + cf.Position * k
	end
	-- The wheels: the parts Catalog.WHEELS names, gathered by corner.
	local corners = {}
	local wheelIdx = (Catalog.WHEELS or {})[id]
	if wheelIdx then
		local byKey: { [string]: any } = {}
		for _, n in wheelIdx do
			local w = m:FindFirstChild(tostring(n))
			if w and w:IsA("BasePart") then
				local i = table.find(parts, w)
				local p = rel[i :: number].Position
				local key = `{if p.X > 0.5 then 1 elseif p.X < -0.5 then -1 else 0},{if p.Z > 0 then 1 else -1}`
				local c = byKey[key]
				if not c then
					c = { x = 0, y = 0, z = 0, n = 0, parts = {} }
					byKey[key] = c
					table.insert(corners, c)
				end
				c.x += p.X
				c.y += p.Y
				c.z += p.Z
				c.n += 1
				table.insert(c.parts, i)
			end
		end
		for _, c in corners do
			c.x /= c.n
			c.y /= c.n
			c.z /= c.n
		end
	end
	if #corners < 2 then
		corners = {}
		local wz, wx = (hi.Z - lo.Z) * 0.33 * k, (hi.X - lo.X) * 0.4 * k
		for _, at in { { wx, wz }, { -wx, wz }, { wx, -wz }, { -wx, -wz } } do
			table.insert(corners, { x = at[1], y = 0.3 * length * 0.2, z = at[2], parts = {} })
		end
	end
	m.Parent = parent
	return {
		model = m,
		parts = parts,
		rel = rel,
		len = length,
		wid = (hi.X - lo.X) * k,
		height = (hi.Y - lo.Y) * k,
		corners = corners :: any,
	}
end

-- Moves the car so its root sits at `root`; `extra(i)` may give part i a CFrame of its own (a
-- wheel coming off), relative to where it would be.
function Kit.place(c: Car, root: CFrame, extra: ((number) -> CFrame?)?)
	local cfs = table.create(#c.parts)
	for i, r in c.rel do
		local e = extra and extra(i)
		cfs[i] = if e then e * (root * r) else root * r
	end
	workspace:BulkMoveTo(c.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- How high the car's top is above a spot (car frame, studs): for mud on the bonnet and roof.
function Kit.topAt(c: Car, x: number, z: number): number
	local top = 0
	for i, p in c.parts do
		if p.Transparency < 0.9 then
			local cf = c.rel[i]
			local half = p.Size / 2
			local reach = math.max(half.X, half.Z)
			if math.abs(cf.Position.X - x) <= reach and math.abs(cf.Position.Z - z) <= reach then
				local up = math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.RightVector.Y) * half.X + math.abs(cf.LookVector.Y) * half.Z
				top = math.max(top, cf.Position.Y + up)
			end
		end
	end
	return top
end

-- ── Scenery pieces (ArcadeScenery.tsx) ─────────────────────────────────────────────────────────

local SHIRTS = { "#e53935", "#1e88e5", "#43a047", "#fdd835", "#8e24aa", "#fb8c00", "#00acc1", "#f06292", "#fafafa", "#6d4c41" }
local SKIN = { "#f1c27d", "#e0ac69", "#c68642", "#8d5524", "#ffdbac", "#a1665e" }
local HAIR = { "#2b1b10", "#4e342e", "#212121", "#795548", "#d7a35c", "#9e9e9e" }
local PANTS = { "#263238", "#37474f", "#1a237e", "#3e2723", "#455a64" }

export type Person = { model: Model, parts: { BasePart }, rel: { CFrame }, k: number }

-- One person as the web's Crowd draws them (body, head, hair, legs, arms), `k` web units to the
-- crowd's unit, standing on the ground; `shirt` forces the colour (a pit crew in team kit).
function Kit.person(parent: Instance, i: number, k: number, shirt: string?): Person
	local S = Kit.S
	local m = Instance.new("Model")
	m.Name = "Person"
	local h = (i * 2654435761) % 4294967296
	local function pick(list: { string }, shift: number): Color3
		return Kit.hex(list[(h // (2 ^ shift)) % #list + 1])
	end
	local shirtC = if shirt then Kit.hex(shirt) else pick(SHIRTS, 0)
	local pants = if shirt then Kit.hex("#263238") else pick(PANTS, 3)
	local u = k * S
	local LEG = 0.24
	local parts: { BasePart } = {}
	local rel: { CFrame } = {}
	local function add(shape: Enum.PartType?, size: Vector3, at: Vector3, color: Color3)
		local p = Kit.part({ Size = size * u, Color = color }, m)
		if shape then
			p.Shape = shape
		end
		table.insert(parts, p)
		table.insert(rel, CFrame.new(at * u))
	end
	for _, sd in { -1, 1 } do
		add(nil, Vector3.new(0.06, LEG, 0.07), Vector3.new(sd * 0.045, LEG / 2, 0), pants)
		add(nil, Vector3.new(0.045, 0.17, 0.05), Vector3.new(sd * 0.115, LEG + 0.16, 0), shirtC)
	end
	add(nil, Vector3.new(0.17, 0.3, 0.15), Vector3.new(0, LEG + 0.15, 0), shirtC)
	add(Enum.PartType.Ball, Vector3.new(0.16, 0.16, 0.16), Vector3.new(0, LEG + 0.36, 0), pick(SKIN, 6))
	add(Enum.PartType.Ball, Vector3.new(0.17, 0.12, 0.17), Vector3.new(0, LEG + 0.4, -0.01), pick(HAIR, 9))
	m.Parent = parent
	return { model = m, parts = parts, rel = rel, k = k }
end

function Kit.placePerson(p: Person, at: CFrame)
	local cfs = table.create(#p.parts)
	for i, r in p.rel do
		cfs[i] = at * r
	end
	workspace:BulkMoveTo(p.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- A racing tyre: black rubber, a coloured band and a grey rim, standing up (or
-- lying flat), its axle along x turned by ry. at: its middle on the ground, in studs.
function Kit.tyre(parent: Instance, at: Vector3, r: number, w: number, band: string, flat: boolean?, ry: number?): Model
	local m = Instance.new("Model")
	m.Name = "Tyre"
	local S = Kit.S
	-- Roblox cylinders run along X, as the web's standing tyre does before ry turns it.
	local rot = if flat then CFrame.Angles(0, ry or 0, 0) * CFrame.Angles(0, 0, math.pi / 2) else CFrame.Angles(0, ry or 0, 0)
	local mid = CFrame.new(at + Vector3.new(0, (if flat then w / 2 else r) * S, 0)) * rot
	Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(w, r * 2, r * 2) * S, CFrame = mid, Color = Kit.hex("#1c1c1c") }, m)
	Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(w + 0.01, r * 1.6, r * 1.6) * S, CFrame = mid, Color = Kit.hex(band) }, m)
	Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(w + 0.02, r * 1.44, r * 1.44) * S, CFrame = mid, Color = Kit.hex("#1c1c1c") }, m)
	Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(w + 0.03, r * 1.1, r * 1.1) * S, CFrame = mid, Color = Kit.hex("#9e9e9e"), Material = Enum.Material.Metal }, m)
	m.Parent = parent
	return m
end

function Kit.tyreStack(parent: Instance, origin: Vector3, x: number, z: number, n: number, band: string)
	for i = 0, n - 1 do
		Kit.tyre(parent, origin + Vector3.new(x, i * 0.235, z) * Kit.S, 0.3, 0.22, band, true, i * 0.7)
	end
end

function Kit.toolChest(parent: Instance, origin: Vector3, x: number, z: number, color: string)
	local S = Kit.S
	local at = origin + Vector3.new(x, 0, z) * S
	Kit.part({ Size = Vector3.new(0.9, 0.85, 0.45) * S, CFrame = CFrame.new(at + Vector3.new(0, 0.5, 0) * S), Color = Kit.hex(color), Material = Enum.Material.Metal }, parent)
	for _, y in { 0.25, 0.42, 0.59, 0.76 } do
		Kit.part({ Size = Vector3.new(0.8, 0.02, 0.01) * S, CFrame = CFrame.new(at + Vector3.new(0, y, 0.228) * S), Color = Kit.hex("#cfd8dc") }, parent)
	end
end

-- A street lamp (ArcadeScenery Lamp, scaled by K = 1.15), its arm reaching along +z turned by ry.
function Kit.lamp(parent: Instance, origin: Vector3, x: number, z: number, ry: number, pole: string?)
	local S, K = Kit.S, 1.15
	local base = CFrame.new(origin + Vector3.new(x, 0, z) * S) * CFrame.Angles(0, ry, 0)
	local c = Kit.hex(pole or "#37474f")
	Kit.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.8, 0.1, 0.1) * S * K, CFrame = base * CFrame.new(0, 0.9 * S * K, 0) * CFrame.Angles(0, 0, math.pi / 2), Color = c }, parent)
	Kit.part({ Size = Vector3.new(0.05, 0.04, 0.5) * S * K, CFrame = base * CFrame.new(Vector3.new(0, 1.78, 0.25) * S * K), Color = c }, parent)
	Kit.part({ Size = Vector3.new(0.16, 0.07, 0.22) * S * K, CFrame = base * CFrame.new(Vector3.new(0, 1.72, 0.48) * S * K), Color = Kit.hex("#fff3c4"), Material = Enum.Material.Neon }, parent)
end

-- ── The camera ─────────────────────────────────────────────────────────────────────────────────

-- Takes the camera from the town (as the drag race does); returns a function that gives it back.
function Kit.takeCamera(fov: number): (Camera, () -> ())
	local cam = workspace.CurrentCamera
	local TownCamera: any = nil
	pcall(function()
		TownCamera = require(script.Parent.Parent.TownCamera) :: any
		TownCamera.setPaused(true)
	end)
	local oldType, oldFov, oldCf = cam.CameraType, cam.FieldOfView, cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = fov
	return cam, function()
		cam.FieldOfView = oldFov
		cam.CameraType = oldType
		cam.CFrame = oldCf
		if TownCamera then
			pcall(TownCamera.setPaused, false)
		end
	end
end

-- The race fog for an arcade scene (the web's ArcadeSky fog), in web units; nil clears it.
function Kit.fog(color: string?, near: number?, far: number?)
	pcall(function()
		local DayNight = require(script.Parent.Parent.DayNight) :: any
		DayNight.setRaceFog(if color then { color = Kit.hex(color), near = (near :: number) * Kit.S, far = (far :: number) * Kit.S } else nil)
	end)
end

-- The screen size the game is drawn at (the gui ignores the top inset, so it's the viewport).
function Kit.screen(gui: ScreenGui): Vector2
	local ok, size = pcall(function()
		return gui.AbsoluteSize
	end)
	if not ok or size.X < 10 then
		size = workspace.CurrentCamera.ViewportSize
	end
	return size
end

-- Where a point in the world lands on the screen (pixels), as three's Vector3.project does, from
-- the camera's CFrame and vertical field of view; z > 0 when it's in front of the camera.
function Kit.project(cf: CFrame, fov: number, size: Vector2, p: Vector3): Vector3
	local rel = cf:Inverse() * p
	local depth = -rel.Z
	local t = math.tan(math.rad(fov) / 2)
	local d = math.max(depth, 1e-3)
	local sx = rel.X / d / (t * size.X / size.Y)
	local sy = rel.Y / d / t
	return Vector3.new((sx + 1) / 2 * size.X, (1 - sy) / 2 * size.Y, depth)
end

-- ── The shell: top bar, countdown, HUD pills, tips and pops ───────────────────────────────────

local CHIP = Color3.fromRGB(27, 31, 36)

-- The web's .rf-top: the title on a fade down from navy, and the red X (both inside the bar, so
-- they always draw over its fade).
function Kit.topBar(gui: ScreenGui, title: string, onClose: () -> ())
	local bar = Ui.new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 70), BackgroundColor3 = Color3.fromRGB(10, 30, 60), BackgroundTransparency = 0, BorderSizePixel = 0, ZIndex = 5, Parent = gui })
	Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.45, 1), Parent = bar })
	Ui.text({ Name = "Title", Text = title, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -80, 0, 40), Shadow = 2, ShadowColor = Color3.new(0, 0, 0), ShadowTransparency = 0.65, ZIndex = 6, Parent = bar })
	Ui.closeButton({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.fromOffset(44, 44), ZIndex = 6, Parent = bar }, onClose)
end

export type Pill = { frame: Frame, label: TextLabel }

-- The .arc-hud row: dark pills in a row across the top, middle of the screen.
function Kit.hudRow(gui: ScreenGui): Frame
	local row = Ui.new("Frame", { Name = "ArcHud", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 50), Size = UDim2.new(1, -20, 0, 31), BackgroundTransparency = 1, ZIndex = 4, Parent = gui })
	Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
	return row
end

-- One pill: `min` is its least width (the clock's 4.4em), so it doesn't jump as the digits change.
function Kit.pill(row: Frame, order: number, text: string, min: number?): Pill
	local w = math.max(min or 0, Ui.textWidth(text, 18) + 24)
	local f = Ui.new("Frame", { Name = `Pill{order}`, LayoutOrder = order, Size = UDim2.fromOffset(w, 31), BackgroundColor3 = CHIP, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 4, Parent = row }, { Ui.round() })
	local l = Ui.text({ Text = text, TextSize = 18, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = f })
	return { frame = f, label = l }
end

function Kit.setPill(p: Pill, text: string, min: number?)
	if p.label.Text == text then
		return
	end
	p.label.Text = text
	p.frame.Size = UDim2.fromOffset(math.max(min or 0, Ui.textWidth(text, 18) + 24), 31)
end

-- A line of big outlined words with the web's text-shadow (0 Npx 0 rgba(0,0,0,a)).
function Kit.words(gui: Instance, props: { [string]: any }, size: number, drop: number, dark: number): TextLabel
	props.TextSize = size
	props.Shadow = drop
	props.ShadowColor = Color3.new(0, 0, 0)
	props.ShadowTransparency = 1 - dark
	props.Parent = gui
	return Ui.text(props)
end

-- A pop that comes in big, holds, then floats up and fades (the web's pitPop / chase-pop, 0.9s).
export type Pop = { label: TextLabel, age: number, y: number }
function Kit.pop(gui: Instance, text: string, color: Color3, size: number, y: UDim): Pop
	local l = Kit.words(gui, { Name = "Pop", Text = text, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(UDim.new(0.5, 0), y), Size = UDim2.new(1, -20, 0, size + 10), ZIndex = 8 }, size, 3, 0.45)
	Ui.setColor(l, color)
	return { label = l, age = 0, y = y.Offset }
end

-- Moves a pop on; false once it has gone.
function Kit.stepPop(p: Pop, dt: number, rise: number): boolean
	p.age += dt
	local k = p.age / 0.9
	if k >= 1 then
		p.label:Destroy()
		return false
	end
	local fade = if k < 0.15 then 1 - k / 0.15 elseif k > 0.7 then (k - 0.7) / 0.3 else 0
	local lift = if k > 0.7 then (k - 0.7) / 0.3 * rise else 0
	local pos = p.label.Position
	p.label.Position = UDim2.new(pos.X, UDim.new(pos.Y.Scale, p.y - lift))
	p.label.TextTransparency = 0.55 + 0.45 * fade
	local face = p.label:FindFirstChild("Face") :: TextLabel?
	if face then
		face.TextTransparency = fade
	end
	return true
end

-- The 3-2-1-GO! count over the scene (ArcadeBits Countdown: a number every 0.65s, GO! for 0.6s).
-- step(dt) moves it on and calls onGo once at GO!; returns false once it has gone.
function Kit.countdown(gui: Instance, onGo: () -> ()): (dt: number) -> boolean
	local l = Kit.words(gui, { Name = "Count", Text = "3", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.34, 0), Size = UDim2.new(1, 0, 0, 120), ZIndex = 9 }, 110, 5, 0.35)
	local t, went = 0, false
	return function(dt: number): boolean
		t += dt
		if t >= 0.65 * 3 + 0.6 then
			l:Destroy()
			return false
		end
		local n = 3 - math.floor(t / 0.65)
		if n <= 0 and not went then
			went = true
			onGo()
		end
		Ui.setText(l, if n <= 0 then "GO!" else tostring(n))
		return true
	end
end

return Kit
