--!strict
-- Pieces Getaway Chase and Parking Pro share (client/ArcadeGames/Chase, Park): parts and models
-- for their streets and lots (the web's scene/ArcadeScenery.tsx, drawn 10 studs to a web unit),
-- the player's own car in its whole paint job, and the game screen's top bar, HUD pills, word pops
-- and 3-2-1 countdown (ui/Arcade.tsx, ArcadeBits.tsx Countdown and index.css .rf-top, .arc-hud,
-- .arc-count, .chase-pop, .arc-tip). The screen is drawn at the web's CSS pixels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint)
local Builder = require(ReplicatedStorage.Shared.Models.Builder) :: any
local Mods = require(ReplicatedStorage.Shared.Models.Mods)
local Panels = require(ReplicatedStorage.Shared.Models.Panels)
local Trim = require(ReplicatedStorage.Shared.Models.Trim)
local Skins = require(ReplicatedStorage.Shared.Models.Skins)
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sounds.Sfx)

local Kit = {}

Kit.S = 10 -- studs per web unit

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

-- A copy of a model from the shared library (ReplicatedStorage.ModelLibrary), or nil.
function Kit.library(kind: string, id: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local src = lib and lib:FindFirstChild(kind) and (lib :: any)[kind]:FindFirstChild(id)
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

-- Scales a model evenly about its pivot.
function Kit.scale(m: Model, k: number)
	if math.abs(k - 1) < 1e-4 then
		return
	end
	local pivot = m:GetPivot()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local rel: any = pivot:ToObjectSpace(d.CFrame)
			d.Size *= k
			d.CFrame = pivot * (rel - rel.Position + rel.Position * k)
		end
	end
end

-- A car's length and width on the ground (studs), as it sits at its pivot, and how far the middle
-- of its box is ahead of the pivot.
function Kit.footprint(m: Model): (number, number, number)
	local cf, size = m:GetBoundingBox()
	local rel = m:GetPivot():ToObjectSpace(cf)
	return size.Z, size.X, rel.Position.Z
end

-- A car scaled to fit `len` by `wid` web units (wid optional: length only), facing +z at the
-- origin. car: an owned car ({ model, color, finish, ... }) or { model, color }. Returns the model
-- and its footprint in web units ({ w, l, cz }, as game/collide.ts Footprint).
function Kit.car(car: any, len: number, wid: number?, parent: Instance): (Model, { w: number, l: number, cz: number })
	local m = Kit.library("Cars", car.model) or Instance.new("Model")
	if car.uid then
		Paint.apply(m, Paint.jobOf(car), Kit.library("Stripes", car.model))
		Panels.apply(m, car.model, car.panels, car.finish, Builder.build)
		Trim.apply(m, car.model, car.trim, car.color)
		Paint.wearHat(m, car.model, car.hat, Builder.build)
		Mods.fit(m, car.model, car.mods, Builder.build)
		Skins.apply(m, car.skin, car.modSkin)
	else
		Paint.apply(m, { color = car.color }, Kit.library("Stripes", car.model))
	end
	m:PivotTo(CFrame.new())
	local l, w = Kit.footprint(m)
	local k = 1
	if l > 0.01 then
		k = len * Kit.S / l
		if wid and w > 0.01 then
			k = math.min(k, wid * Kit.S / w)
		end
	end
	Kit.scale(m, k)
	local l2, w2, cz = Kit.footprint(m)
	if l2 <= 0.01 then
		-- No model (a preview without the library): a box the size it would be.
		l2, w2, cz = len * Kit.S, (wid or len * 0.5) * Kit.S, 0
		Kit.part({ Name = "Body", Size = Vector3.new(w2, 0.6 * Kit.S, l2), CFrame = CFrame.new(0, 0.3 * Kit.S, 0), Color = Color3.fromHex(car.color or "#9e9e9e") }, m)
	end
	m.Parent = parent
	return m, { w = w2 / Kit.S, l = l2 / Kit.S, cz = cz / Kit.S }
end

-- A soft dark patch under a car (ArcadeScenery CarShadow).
function Kit.shadow(len: number, wid: number, parent: Instance): Part
	return Kit.part({ Name = "Shadow", Size = Vector3.new(wid * 1.3 * Kit.S, 0.05, len * 1.15 * Kit.S), Color = Color3.new(0, 0, 0), Transparency = 0.6, Material = Enum.Material.SmoothPlastic }, parent)
end

-- A tree (the town's) or a palm, at web units (x, z) from `at`.
function Kit.tree(at: CFrame, x: number, z: number, palm: boolean, scale: number, parent: Instance)
	local t = Kit.library("Buildings", if palm then "palm" else "tree")
	if t then
		Kit.scale(t, scale)
		t:PivotTo(at * CFrame.new(x * Kit.S, 0, z * Kit.S))
		t.Parent = parent
	else
		Kit.part({ Name = "Trunk", Size = Vector3.new(0.2, 1, 0.2) * Kit.S, CFrame = at * CFrame.new(x * Kit.S, 0.5 * Kit.S, z * Kit.S), Color = Color3.fromHex("#6d4c41") }, parent)
		Kit.part({ Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2) * Kit.S, CFrame = at * CFrame.new(x * Kit.S, 1.3 * Kit.S, z * Kit.S), Color = Color3.fromHex("#43a047") }, parent)
	end
end

-- A lamp post leaning over the road (ArcadeScenery Lamp), at web units (x, z), its arm towards -x
-- turned by ry.
function Kit.lamp(at: CFrame, x: number, z: number, ry: number, parent: Instance)
	local base = at * CFrame.new(x * Kit.S, 0, z * Kit.S) * CFrame.Angles(0, ry, 0)
	local pole = Color3.fromHex("#37474f")
	Kit.part({ Name = "Pole", Size = Vector3.new(0.08, 2.2, 0.08) * Kit.S, CFrame = base * CFrame.new(0, 1.1 * Kit.S, 0), Color = pole }, parent)
	Kit.part({ Name = "Arm", Size = Vector3.new(0.06, 0.06, 0.6) * Kit.S, CFrame = base * CFrame.new(0, 2.18 * Kit.S, 0.28 * Kit.S), Color = pole }, parent)
	Kit.part({ Name = "Head", Size = Vector3.new(0.22, 0.08, 0.3) * Kit.S, CFrame = base * CFrame.new(0, 2.14 * Kit.S, 0.55 * Kit.S), Color = Color3.fromHex("#fff8e1"), Material = Enum.Material.Neon }, parent)
end

-- The player's own shop types for the street (ArcadeScenery useTownPool), or a standard high street.
local FALLBACK = { "pizza", "donut", "burger", "diner", "motel", "carwash", "tires", "gas", "bowling", "icecream", "coffee", "tacos" }
local SHOPS = { business = true, gas = true, parts = true }
function Kit.townPool(buildings: { any }?): { string }
	local own, seen = {}, {}
	for _, b in (buildings or {}) :: { any } do
		local d = data.buildingDef(b.def)
		if d and not seen[d.id] and SHOPS[d.kind] and d.w <= 2 and d.h <= 1 then
			seen[d.id] = true
			table.insert(own, d.id)
		end
	end
	if #own >= 4 then
		return own
	end
	local out = {}
	for _, id in FALLBACK do
		if data.buildingDef(id) then
			table.insert(out, id)
		end
	end
	return out
end

-- The web's seeded rand (a Park-Miller generator, as the scenes use): seed -> () -> [0, 1).
function Kit.rand(seed: number): () -> number
	local s = seed % 2147483646 + 1
	return function(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

-- ── The screen ──────────────────────────────────────────────────────────────────────────────

-- The full-screen frame a game draws on (in CSS pixels, like the web).
function Kit.screen(gui: ScreenGui): Frame
	return Ui.new("Frame", { Name = "Screen", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
end

-- The top bar (.rf-top): the title over a dark fade, and the red X.
function Kit.topBar(screen: Frame, title: string, onClose: () -> ()): Frame
	local bar = Ui.new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = Color3.fromHex("#0a1e3c"), BorderSizePixel = 0, ZIndex = 20, Parent = screen }, {
		Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	Ui.text({ Name = "Title", Text = title, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -80, 0, 30), Shadow = 2, ShadowTransparency = 0.65, ShadowColor = Color3.new(0, 0, 0), ZIndex = 21, Parent = bar })
	Ui.closeButton({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(38, 38), ZIndex = 22, Parent = bar }, onClose)
	return bar
end

-- The HUD row under the top bar (.arc-hud): dark pills, centred. Returns the row; add pills with
-- Kit.pill.
function Kit.hudRow(screen: Frame): Frame
	return Ui.new("Frame", { Name = "Hud", Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, ZIndex = 20, Parent = screen }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
end

export type Pill = { frame: Frame, label: TextLabel, set: (text: string, color: Color3?) -> () }
-- One pill (.arc-hud > span): sized to its text, at least minW wide.
function Kit.pill(row: Frame, order: number, size: number, minW: number?): Pill
	local frame = Ui.new("Frame", { Name = `Pill{order}`, LayoutOrder = order, Size = UDim2.fromOffset(minW or 40, size + 12), BackgroundColor3 = Color3.fromHex("#1b1f24"), BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 20, Parent = row }, { Ui.round() })
	local label = Ui.text({ Text = "", TextSize = size, Size = UDim2.fromScale(1, 1), ZIndex = 21, Parent = frame })
	local function set(text: string, color: Color3?)
		Ui.setText(label, text)
		local w = math.max(minW or 0, Ui.textWidth(text, size) + 24)
		if frame.Size.X.Offset ~= w then
			frame.Size = UDim2.fromOffset(w, size + 12)
		end
		if color and frame.BackgroundColor3 ~= color then
			frame.BackgroundColor3 = color
		end
	end
	return { frame = frame, label = label, set = set }
end

-- A word that pops over the road and floats away (.chase-pop), ~0.9 s.
function Kit.pop(screen: Frame, text: string, color: Color3, size: number, y: number?)
	local l = Ui.text({ Name = "Pop", Text = text, TextSize = size, TextColor3 = color, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, y or 0.26, 0), Size = UDim2.new(1, 0, 0, size + 8), Shadow = 3, ShadowColor = Color3.new(0, 0, 0), ShadowTransparency = 0.55, ZIndex = 25, Parent = screen })
	l:SetAttribute("Born", os.clock())
	return l
end

-- Moves the pops on: they rise and fade, then go.
function Kit.agePops(screen: Frame)
	for _, l in screen:GetChildren() do
		if l.Name == "Pop" and l:IsA("TextLabel") then
			local age = os.clock() - ((l:GetAttribute("Born") :: number?) or 0)
			if age > 0.9 then
				l:Destroy()
			else
				local k = math.max(0, (age - 0.6) / 0.3)
				l.Position = UDim2.new(0.5, 0, l.Position.Y.Scale, -age * 26)
				local face = l:FindFirstChild("Face") :: TextLabel?
				if face then
					face.TextTransparency = k
				end
				l.TextTransparency = math.max(k, 0.55)
			end
		end
	end
end

-- A line of help along the bottom (.arc-tip).
function Kit.tip(screen: Frame, text: string): TextLabel
	return Ui.text({ Name = "Tip", Text = text, TextSize = 18, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.new(1, -20, 0, 26), Shadow = 2, ShadowColor = Color3.new(0, 0, 0), ShadowTransparency = 0.6, ZIndex = 20, Parent = screen })
end

-- The 3-2-1-GO (ArcadeBits Countdown): 650 ms a number, GO for 600 ms. onGo runs at GO. Returns a
-- step(dt) to call every frame (true while it's still showing).
function Kit.countdown(screen: Frame, onGo: () -> ()): (dt: number) -> boolean
	local label = Ui.text({ Name = "Count", Text = "3", TextSize = 96, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.34, 0), Size = UDim2.new(1, 0, 0, 110), Shadow = 5, ShadowColor = Color3.new(0, 0, 0), ShadowTransparency = 0.65, ZIndex = 30, Parent = screen })
	local t = 0
	local went = false
	local beeped = 4
	return function(dt: number): boolean
		if not label.Parent then
			return false
		end
		t += dt
		local n = 3 - math.floor(t / 0.65)
		-- A beep for each number, a higher one on GO (ArcadeBits Countdown's sfx.countdown).
		if math.max(0, n) < beeped then
			beeped = math.max(0, n)
			Sfx.countdown(beeped == 0)
		end
		if n <= 0 then
			if not went then
				went = true
				onGo()
			end
			Ui.setText(label, "GO!")
			if t >= 3 * 0.65 + 0.6 then
				label:Destroy()
				return false
			end
		else
			Ui.setText(label, tostring(n))
		end
		return true
	end
end

-- ── Driving controls (ui/DriveControls.tsx, drive.css .dc) ─────────────────────────────────

export type DriveInput = { steer: number, gas: number, brake: number }
export type Drive = { input: DriveInput, show: (on: boolean) -> (), destroy: () -> () }

local RANGE = 56 -- ARCADE_FEEL: px from where the thumb landed to full lock
local EDGE, MIN_SIDE = 14, 20

local function isPress(i: InputObject): boolean
	return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1
end

local function sameFinger(mine: InputObject, i: InputObject): boolean
	return i == mine or (mine.UserInputType == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseButton1)
end

-- A round touch button (.dc-btn): a see-through disc with a white ring and a word.
local function pedal(parent: Instance, name: string, word: string, size: number, color: Color3, alpha: number): TextButton
	local b = Ui.new("TextButton", { Name = name, Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(size, size), BackgroundColor3 = color, BackgroundTransparency = alpha, ZIndex = 26, Parent = parent }, {
		Ui.round(),
		Ui.stroke(3, Ui.WHITE, 0.3),
	})
	Ui.text({ Text = word, TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 27, Parent = b })
	return b
end

-- The shared driving controls with a gas pedal (TouchDrive with autoGas off, as Parking Pro has):
-- on a touch screen, BRAKE and GAS buttons and a slide-to-steer zone (upright: a strip along the
-- bottom with the buttons on its top edge; on its side: steer on the left, pedals bottom right);
-- WASD or arrows on a keyboard, with a line of key hints when there's no touch screen.
-- input.steer: +1 full left, -1 full right; gas and brake 0..1.
function Kit.drive(screen: Frame, touch: boolean): Drive
	local UserInputService = game:GetService("UserInputService")
	local input: DriveInput = { steer = 0, gas = 0, brake = 0 }
	local touchSteer, touchGas, touchBrake = 0, false, false
	local held: { [Enum.KeyCode]: boolean } = {}
	local function has(a: Enum.KeyCode, b: Enum.KeyCode): boolean
		return held[a] == true or held[b] == true
	end
	local function apply()
		local keySteer = (if has(Enum.KeyCode.A, Enum.KeyCode.Left) then 1 else 0) - (if has(Enum.KeyCode.D, Enum.KeyCode.Right) then 1 else 0)
		input.steer = if keySteer ~= 0 then keySteer else touchSteer
		input.brake = if touchBrake or has(Enum.KeyCode.S, Enum.KeyCode.Down) then 1 else 0
		input.gas = if (touchGas or has(Enum.KeyCode.W, Enum.KeyCode.Up)) and input.brake == 0 then 1 else 0
	end
	local box = Ui.new("Frame", { Name = "Drive", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 24, Parent = screen })
	local conns: { RBXScriptConnection } = {}
	local view = workspace.CurrentCamera.ViewportSize
	local tall = view.Y > view.X
	local strip = math.max(150, view.Y * 0.3)

	if touch then
		-- The steering zone (.dc-steer), its hint and the floating stick.
		local zone = Ui.new("Frame", { Name = "Steer", BackgroundTransparency = 1, Active = true, AnchorPoint = Vector2.new(0, 1), ZIndex = 24, Parent = box })
		if tall then
			zone.Position = UDim2.new(0, 8, 1, 0)
			zone.Size = UDim2.new(1, -16, 0, strip)
		else
			zone.Position = UDim2.fromScale(0, 1)
			zone.Size = UDim2.fromScale(0.46, 0.62)
		end
		local hint = Ui.new("Frame", { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = if tall then UDim2.new(0.5, 0, 1, -26) else UDim2.new(0, 110, 1, -40), Size = UDim2.fromOffset(150, 33), BackgroundColor3 = Color3.fromHex("#0a1428"), BackgroundTransparency = 0.58, ZIndex = 25, Parent = zone }, { Ui.round() })
		Ui.text({ Text = "◀ slide to steer ▶", Body = true, TextSize = 13, TextTransparency = 0.1, Size = UDim2.fromScale(1, 1), ZIndex = 26, Parent = hint })
		local stick = Ui.new("Frame", { Name = "Stick", Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Visible = false, ZIndex = 25, Parent = zone })
		Ui.new("Frame", { Name = "Track", Position = UDim2.fromOffset(-RANGE - 20, -12), Size = UDim2.fromOffset((RANGE + 20) * 2, 24), BackgroundColor3 = Color3.fromHex("#0a1428"), BackgroundTransparency = 0.62, ZIndex = 25, Parent = stick }, {
			Ui.corner(12),
			Ui.stroke(2, Ui.WHITE, 0.55),
		})
		local knob = Ui.new("Frame", { Name = "Knob", Position = UDim2.fromOffset(-30, -30), Size = UDim2.fromOffset(60, 60), BackgroundColor3 = Ui.WHITE, ZIndex = 26, Parent = stick }, {
			Ui.round(),
			Ui.new("UIGradient", { Rotation = 60, Color = Ui.seq("#ffffff", "#cfd8dc") }),
		})
		-- The finger that owns the stick; a second finger landing in the zone is ignored.
		local owner: InputObject? = nil
		local x0, left, right = 0, RANGE, RANGE
		table.insert(conns, zone.InputBegan:Connect(function(i: InputObject)
			if owner or not isPress(i) then
				return
			end
			owner = i
			local at = zone.AbsolutePosition
			x0 = i.Position.X - at.X
			-- sideRanges: a thumb near the edge reaches full lock at the edge.
			left = math.max(MIN_SIDE, math.min(RANGE, i.Position.X - EDGE))
			right = math.max(MIN_SIDE, math.min(RANGE, view.X - i.Position.X - EDGE))
			stick.Position = UDim2.fromOffset(x0, i.Position.Y - at.Y)
			knob.Position = UDim2.fromOffset(-30, -30)
			stick.Visible = true
			hint.Visible = false
		end))
		table.insert(conns, UserInputService.InputChanged:Connect(function(i: InputObject)
			local o = owner
			if not o or not (i == o or (o.UserInputType == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseMovement)) then
				return
			end
			local dx = math.clamp(i.Position.X - zone.AbsolutePosition.X - x0, -left, right)
			local side = if dx < 0 then left else right
			-- thumbSteer: +1 is left, so a thumb slid right steers negative.
			touchSteer = -math.sign(dx) * math.min(1, math.abs(dx) / side)
			knob.Position = UDim2.fromOffset(dx - 30, -30)
			apply()
		end))
		table.insert(conns, UserInputService.InputEnded:Connect(function(i: InputObject)
			local o = owner
			if o and sameFinger(o, i) then
				owner = nil
				touchSteer = 0
				stick.Visible = false
				hint.Visible = true
				apply()
			end
		end))

		-- BRAKE and GAS (.dc-brake 80 px, .dc-gas 84 px).
		local brake = pedal(box, "Brake", "BRAKE", 80, Color3.fromHex("#b71c1c"), 0.35)
		local gas = pedal(box, "Gas", "GAS", 84, Color3.fromHex("#2e7d32"), 0.25)
		if tall then
			-- The row sits on the steering strip's top edge, 40 px into it.
			brake.AnchorPoint = Vector2.new(0, 1)
			brake.Position = UDim2.new(0, 16, 1, -(strip - 40))
			gas.AnchorPoint = Vector2.new(1, 1)
			gas.Position = UDim2.new(1, -16, 1, -(strip - 40))
		else
			brake.AnchorPoint = Vector2.new(1, 1)
			brake.Position = UDim2.new(1, -18 - 112, 1, -18)
			gas.AnchorPoint = Vector2.new(1, 1)
			gas.Position = UDim2.new(1, -18, 1, -18)
		end
		local looks = { Brake = { Color3.fromHex("#b71c1c"), 0.35, Color3.fromHex("#d50000") }, Gas = { Color3.fromHex("#2e7d32"), 0.25, Color3.fromHex("#2e7d32") } }
		for _, b in { brake, gas } do
			local mine: InputObject? = nil
			local look = looks[b.Name]
			local function set(on: boolean)
				if b == brake then
					touchBrake = on
				else
					touchGas = on
				end
				b.BackgroundColor3 = if on then look[3] else look[1]
				b.BackgroundTransparency = if on then 0 else look[2]
				apply()
			end
			table.insert(conns, b.InputBegan:Connect(function(i: InputObject)
				if isPress(i) then
					mine = i
					set(true)
				end
			end))
			table.insert(conns, UserInputService.InputEnded:Connect(function(i: InputObject)
				local m = mine
				if m and sameFinger(m, i) then
					mine = nil
					set(false)
				end
			end))
		end
	else
		-- Key hints (KeyHints, .dc-keys).
		local keys = Ui.new("Frame", { Name = "Keys", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(180, 30), BackgroundColor3 = Color3.fromHex("#0a1428"), BackgroundTransparency = 0.55, ZIndex = 25, Parent = box }, {
			Ui.round(),
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for n, k in { "W", "A", "S", "D" } do
			Ui.new("TextLabel", { LayoutOrder = n, Text = k, Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Ui.WHITE, TextColor3 = Color3.fromHex("#263238"), FontFace = Ui.HEAVY, TextSize = 11, ZIndex = 26, Parent = keys }, { Ui.corner(5) })
		end
		Ui.text({ LayoutOrder = 9, Text = "or arrows", Body = true, TextSize = 12, Size = UDim2.fromOffset(70, 20), ZIndex = 26, Parent = keys })
	end

	local KEYS = { [Enum.KeyCode.A] = true, [Enum.KeyCode.D] = true, [Enum.KeyCode.W] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true, [Enum.KeyCode.Up] = true, [Enum.KeyCode.Down] = true }
	table.insert(conns, UserInputService.InputBegan:Connect(function(i: InputObject, processed: boolean)
		if not processed and KEYS[i.KeyCode] then
			held[i.KeyCode] = true
			apply()
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(i: InputObject)
		if held[i.KeyCode] then
			held[i.KeyCode] = nil
			apply()
		end
	end))

	return {
		input = input,
		show = function(on: boolean)
			box.Visible = on
			if not on then
				touchSteer, touchGas, touchBrake = 0, false, false
				table.clear(held)
				apply()
			end
		end,
		destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			box:Destroy()
		end,
	}
end

return Kit
