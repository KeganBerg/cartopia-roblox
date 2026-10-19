--!strict
-- What the travel stop and the car spa (client/Centres/TravelStop, CarSpa) are built from: plain
-- parts placed in web units on a block's own frame, signs, the townsfolk's cars and the townspeople.
--
-- Every part is anchored and casts no shadow. The ones that move are moved by CentreLife's one
-- BulkMoveTo a frame; most never move at all. Only the big still pieces a player could walk into
-- (walls, pumps, posts) collide, as TownView's buildings do (its `solidify`).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Models = Shared:WaitForChild("Models")
local Catalog = require(Models:WaitForChild("Catalog")) :: any
local Builder = require(Models:WaitForChild("Builder")) :: any
local Paint = require(Models:WaitForChild("Paint")) :: any
local data = require(Shared:WaitForChild("Game"):WaitForChild("data")) :: any
local CarDetail = require(script.Parent.Parent:WaitForChild("CarDetail"))
local TownLife = require(script.Parent.Parent:WaitForChild("TownLife")) :: any

local Kit = {}

local S = Catalog.SCALE -- studs per web unit
Kit.S = S
Kit.HIDDEN = CFrame.new(0, -10000, 0)
-- Roblox's cylinders run along their own x; the web's stand up along y.
Kit.UPRIGHT = CFrame.Angles(0, 0, math.pi / 2)

-- A plain part: anchored, no collisions, no shadow.
function Kit.part(parent: Instance, shape: Enum.PartType?, size: Vector3, cf: CFrame, color: string, material: Enum.Material?): Part
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
	p.CFrame = cf
	p.Color = Color3.fromHex(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Something a player bumps into and can stand on.
function Kit.solid(p: BasePart): BasePart
	p.CanCollide = true
	return p
end

-- The pieces of one block, in web units on its frame (x along the front, +z to the road, y up).
export type Builder = {
	folder: Instance,
	frame: CFrame,
	at: (self: Builder, x: number, y: number, z: number) -> CFrame,
	box: (self: Builder, x: number, y: number, z: number, w: number, h: number, d: number, color: string, material: Enum.Material?) -> Part,
	cyl: (self: Builder, x: number, y: number, z: number, r: number, h: number, color: string) -> Part,
	ball: (self: Builder, x: number, y: number, z: number, r: number, color: string) -> Part,
	egg: (self: Builder, x: number, y: number, z: number, w: number, h: number, d: number, color: string) -> Part,
}

local B = {}
B.__index = B

function B.at(self: Builder, x: number, y: number, z: number): CFrame
	return self.frame * CFrame.new(x * S, y * S, z * S)
end

-- A box `w` x `h` x `d` with its middle at (x, y, z).
function B.box(self: Builder, x: number, y: number, z: number, w: number, h: number, d: number, color: string, material: Enum.Material?): Part
	return Kit.part(self.folder, nil, Vector3.new(w, h, d) * S, self:at(x, y, z), color, material)
end

-- An upright cylinder of radius `r`, `h` tall, its middle at (x, y, z).
function B.cyl(self: Builder, x: number, y: number, z: number, r: number, h: number, color: string): Part
	return Kit.part(self.folder, Enum.PartType.Cylinder, Vector3.new(h, r * 2, r * 2) * S, self:at(x, y, z) * Kit.UPRIGHT, color)
end

function B.ball(self: Builder, x: number, y: number, z: number, r: number, color: string): Part
	return Kit.part(self.folder, Enum.PartType.Ball, Vector3.one * r * 2 * S, self:at(x, y, z), color)
end

-- A squashed sphere `w` x `h` x `d` across.
function B.egg(self: Builder, x: number, y: number, z: number, w: number, h: number, d: number, color: string): Part
	local p = Kit.part(self.folder, nil, Vector3.new(w, h, d) * S, self:at(x, y, z), color)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

function Kit.builder(folder: Instance, frame: CFrame): Builder
	return (setmetatable({ folder = folder, frame = frame }, B) :: any) :: Builder
end

-- Letters on a part's +z face (the web's sign planes face +z), as Builder's own signs are drawn.
function Kit.sign(p: BasePart, text: string, fg: string, bg: string)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromHex(bg)
	label.BorderSizePixel = 0
	label.TextColor3 = Color3.fromHex(fg)
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

---------------------------------------------------------------------------------------------------
-- Cars: the townsfolk's everyday cars (TownLife's), built from the shared meshes, at the size cars
-- drive round town (Catalog.TOWN_SIZE, the web's townCarSize.ts). A car is moved as a list of parts
-- with their places on the car, so it goes into the one BulkMoveTo.

local pool: { any }? = nil
local function everyday(): { any }
	if pool then
		return pool
	end
	local list = {}
	for _, c in data.CARS do
		if not c.bucks and (c.price or 0) > 0 and c.price <= 22000 and c.colors and #c.colors > 0 and (Catalog.TOWN_SIZE or {})[c.id] then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		return a.price < b.price
	end)
	pool = list
	return list
end

export type Car = {
	model: Model,
	detail: CarDetail.Detail,
	id: string,
	color: string,
	k: number, -- its town size (the model's scale)
	parts: { BasePart },
	offs: { CFrame },
	-- Its roof, in studs above the ground, and its length (web units).
	top: number,
	len: number,
	-- How big it's drawn now (1 full size; less while it pulls in or drives off), whether it stands
	-- anywhere, and where (its middle on the ground).
	show: number,
	shown: boolean,
	at: CFrame,
}

-- (A built model has no PrimaryPart, so its pivot stays where it was last put when BulkMoveTo moves
-- its pieces: anything that goes by the pivot, like ScaleTo, is told where the car really is.)
local function sync(car: Car)
	car.model.WorldPivot = car.at
end

local function capture(car: Car)
	local pivot = car.model:GetPivot()
	table.clear(car.parts)
	table.clear(car.offs)
	for _, d in car.model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(car.parts, d)
			table.insert(car.offs, pivot:ToObjectSpace(d.CFrame))
		end
	end
	local _, size = car.model:GetBoundingBox()
	car.top = size.Y
end

local function prepare(m: Model)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
end

-- Car `i` of a block (the same car and colour each time for the same i), hidden until placed.
function Kit.car(parent: Instance, i: number): Car?
	local list = everyday()
	if #list == 0 then
		return nil
	end
	local c = list[(i * 7) % #list + 1]
	local color = c.colors[(i * 3) % #c.colors + 1]
	local m = Builder.build(c.id)
	if not m then
		return nil
	end
	Paint.apply(m, Paint.jobOf({ color = color }))
	prepare(m)
	m:SetAttribute("Model", c.id)
	local detail = CarDetail.track(m)
	local size = (Catalog.TOWN_SIZE or {})[c.id] or { 0.8, 0.45, 0.8 }
	local k = size[3]
	if math.abs(m:GetScale() - k) > 1e-3 then
		m:ScaleTo(k)
	end
	m:PivotTo(Kit.HIDDEN)
	m.Parent = parent
	local car: Car = { model = m, detail = detail, id = c.id, color = color, k = k, parts = {}, offs = {}, top = 0, len = size[1], show = 1, shown = false, at = Kit.HIDDEN }
	capture(car)
	return car
end

-- Parks a car at `cf` for good (it's never moved again).
function Kit.park(car: Car, cf: CFrame)
	car.model:PivotTo(cf)
	car.at = cf
	car.shown = true
end

-- Puts a car at `cf` (its middle on the ground, nose along the model's own +z there), `show` of its
-- full size. At full size its pieces go into the BulkMoveTo lists; growing or shrinking (only for
-- the moment it pulls in or drives off) scales the model there and then.
function Kit.place(car: Car, cf: CFrame, show: number, list: { BasePart }, cfs: { CFrame })
	show = math.clamp(show, 0, 1)
	if show <= 0.02 then
		Kit.hide(car, list, cfs)
		return
	end
	if show >= 1 and car.show >= 1 and car.shown and cf == car.at then
		-- Standing where it stood (at a pump, say): nothing to move.
		return
	end
	car.shown = true
	if show < 1 or car.show < 1 then
		sync(car)
		car.show = show
		car.model:ScaleTo(car.k * show)
		car.model:PivotTo(cf)
		car.at = cf
		if show >= 1 then
			-- Back at full size: its pieces sit as they were built.
			car.model:ScaleTo(car.k)
		end
		return
	end
	car.at = cf
	for i, p in car.parts do
		table.insert(list, p)
		table.insert(cfs, cf * car.offs[i])
	end
end

-- Out of sight (its pieces kept together, for the next time it grows into view).
function Kit.hide(car: Car, list: { BasePart }, cfs: { CFrame })
	if not car.shown then
		return
	end
	car.shown = false
	if car.show < 1 then
		sync(car)
		car.show = 1
		car.model:ScaleTo(car.k)
	end
	car.at = Kit.HIDDEN
	for i, p in car.parts do
		table.insert(list, p)
		table.insert(cfs, Kit.HIDDEN * car.offs[i])
	end
end

-- Once a second: a car built before its meshes arrived has stand-in boxes, and once they're all
-- in it's built again for real (as TownLife does with CarDetail); and its small pieces show only
-- when they'd be more than a pixel or two on screen (CarDetail.lod), seen from `eye`.
function Kit.refresh(car: Car, eye: Vector3?)
	if car.shown and eye then
		CarDetail.lod(car.detail, (car.at.Position - eye).Magnitude)
	end
	if not CarDetail.ready(car.detail) then
		return
	end
	local fresh = Builder.build(car.id)
	if not fresh then
		return
	end
	Paint.apply(fresh, Paint.jobOf({ color = car.color }))
	prepare(fresh)
	local nd = CarDetail.track(fresh)
	sync(car)
	car.detail = CarDetail.swap(car.detail, fresh, nd)
	car.model = fresh
	car.show = 1
	fresh:ScaleTo(car.k)
	fresh:PivotTo(CFrame.new())
	capture(car)
	fresh:PivotTo(car.at)
end

-- Runs `step` (time, dt, list, cfs) on for `seconds` at once and puts everything where it ends up,
-- so a centre starts out busy (cars already part way through) rather than empty.
function Kit.settle(seconds: number, step: (number, number, { BasePart }, { CFrame }) -> ())
	local last: { [BasePart]: CFrame } = {}
	local dt = 0.1
	for i = 1, math.floor(seconds / dt) do
		local list, cfs = {}, {}
		step(i * dt, dt, list, cfs)
		for j, p in list do
			last[p] = cfs[j]
		end
	end
	local list, cfs = {}, {}
	for p, cf in last do
		table.insert(list, p)
		table.insert(cfs, cf)
	end
	if #list > 0 then
		workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

---------------------------------------------------------------------------------------------------
-- People: the townspeople's own figures (TownLife's figure and draw, 5.3 studs tall), walking at an
-- easy pace, standing about, or indoors (hidden).

-- Web units a second: a stroll for a 5.3-stud figure (about 4 studs a second).
Kit.WALK = 0.4

export type Person = { p: any, shown: boolean, taken: boolean? }

function Kit.person(parent: Instance, id: string): Person
	local p = TownLife._person(id, "centre", { 0, 0 })
	-- Customers, not joggers or dog walkers.
	p.type = "walker"
	p.state = "inside"
	p.fig = TownLife._figure(p, parent)
	return { p = p, shown = true, taken = false }
end

-- Draws a person at (x, z) on a block's frame, facing `heading` (radians, 0 is +z) there:
-- `state` is "walk", "linger" or "inside" (hidden). `moved`: web units walked since last frame.
function Kit.drawPerson(who: Person, frame: CFrame, x: number, z: number, heading: number, state: string, moved: number, time: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	local p = who.p
	if state == "inside" and p.state == "inside" and not who.shown then
		return
	end
	who.shown = state ~= "inside"
	local w = frame * Vector3.new(x * S, 0, z * S)
	local _, yaw = frame:ToEulerAnglesYXZ()
	p.state = state
	p.waited = 0
	p.pos[1], p.pos[2] = w.X / S, w.Z / S
	p.heading = heading + yaw
	-- TownLife's stride for a walker: a step's swing per stud walked.
	p.stride += moved * S / (5.3 / 0.69) * 14
	TownLife._draw(Vector3.new(0, w.Y, 0), p, time, eye, list, cfs)
end

return Kit
