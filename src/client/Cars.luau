--!strict
-- The CARS page, as the web game's CarsPage (ui/Menus.tsx, garage-env.css): one full-screen menu
-- standing in the Cartopia Motors showroom, with My Cars, For Sale, Collection, Call Cards and
-- Crates tabs on a dark strip. The car list floats on the left, the picked car turns on the
-- turntable in the middle with its PI, and its details sit on the right: upgrades for your own
-- cars (My Cars), colours and Buy for the dealership (For Sale).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Icons = require(script.Parent.Icons)
local Thumb = require(script.Parent.Thumb)
local Collection = require(script.Parent.Collection)
local CrateDepot = require(script.Parent.Crates)
local CallCards = require(script.Parent.CallCards)
local PaintShop = require(script.Parent.PaintShop)
local HatShop = require(script.Parent.HatShop)
local ModShop = require(script.Parent.ModShop)
local CustomShop = require(script.Parent.CustomShop)
local TrimShop = require(script.Parent.TrimShop)
local SkinShop = require(script.Parent.SkinShop)
local Paint = require(ReplicatedStorage.Shared.Models.Paint)

local Cars = {}

local LINE = Ui.LINE
local GLASS = Color3.fromHex("#f2f6fb")
local NO_UPGRADES = { engine = 0, turbo = 0, tires = 0, weight = 0 }

-- One small icon per business, as ui/buildingIcons.ts, for a car's favourite jobs.
local BUILDING_ICONS: { [string]: string } = {
	academy = "🚦", arcade = "🕹️", bodyshop = "🎨", bowling = "🎳", burger = "🍔", carwash = "🫧", cinema = "🎬", club = "🪩",
	coffee = "☕", diner = "🥞", donut = "🍩", firehouse = "🚒", glasstower = "🏙️", helipad = "🚁", highschool = "🏫", hospital = "🏥",
	hq = "🏢", icecream = "🍦", junkyard = "🧲", lube = "🛢️", market = "🛒", motel = "🛏️", offices = "💼", parkade = "🅿️",
	parts = "⚙️", pizza = "🍕", police = "🚓", school = "🎒", stadium = "🏟️", tacos = "🌮", tires = "🛞", tuner = "🔧", university = "🎓",
	muffler = "💨", brakes = "🛑", wraps = "🎞️", dynolab = "📈", engines = "🔩", racefab = "🏎️",
	laundry = "🧺", vet = "🐾", postoffice = "📮", library = "📚", busdepot = "🚌", cityhall = "🏛️",
	minigolf = "⛳", pool = "🏊", funfair = "🎡", waterpark = "🌊", haunted = "👻",
}
local BODY_LABEL: { [string]: string } = { dogvan = "Dog van", ev = "EV", suv = "SUV", icecream = "Ice cream", parcel = "Parcel van", monster = "Monster truck" }
local function bodyLabel(b: string): string
	return BODY_LABEL[b] or (b:sub(1, 1):upper() .. b:sub(2))
end

-- Reopens on the tab, car and filters it was left on, as the web does.
local lastTab = "garage"
local lastSale: string? = nil
local garageView = { kind = "all", sort = "pi" }
local saleView = { kind = "all", sort = "level" }
local CAR_SORTS = { { id = "pi", label = "Top PI" }, { id = "pi-low", label = "Low PI" }, { id = "name", label = "A–Z" }, { id = "new", label = "Newest" } }
local SALE_SORTS = { { id = "level", label = "Level" }, { id = "cheap", label = "Price ↑" }, { id = "dear", label = "Price ↓" }, { id = "pi", label = "Top PI" }, { id = "name", label = "A–Z" } }

-- The showroom behind the menus: brick wall, the Cartopia Motors sign, the floor and turntable.
local function room(parent: Instance)
	local r = Ui.new("Frame", { Name = "Room", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#0f141d"), BorderSizePixel = 0, ZIndex = 0, Parent = parent })
	-- The showroom wall (garage-env.css): brick down to a dark baseboard, the sign in the middle
	-- with race numbers either side.
	Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 240), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = r }, { Ui.gradient("#8c4f3e", "#6e3a2d") })
	-- Mortar lines, so the wall reads as brick.
	for i = 1, 10 do
		Ui.new("Frame", { Position = UDim2.fromOffset(0, i * 22), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Color3.fromHex("#5a2f25"), BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = r })
	end
	Ui.new("Frame", { Position = UDim2.fromOffset(0, 240), Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Color3.fromHex("#2a2f38"), BorderSizePixel = 0, Parent = r })
	Ui.new("Frame", { Position = UDim2.fromOffset(0, 290), Size = UDim2.new(1, 0, 1, -290), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = r }, { Ui.gradient("#7b8494", "#4b5260") })
	local sign = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, -70, 0, 110), Size = UDim2.fromOffset(336, 86), BackgroundColor3 = Color3.fromHex("#151b2c"), BorderSizePixel = 0, ZIndex = 2, Parent = r }, {
		Ui.corner(4),
		Ui.stroke(4, Color3.fromHex("#e8743b")),
	})
	Ui.text({ Text = "CARTOPIA MOTORS", TextSize = 32, TextColor3 = Color3.fromHex("#ffcf5a"), Size = UDim2.fromScale(1, 1), Parent = sign })
	local function number(x: number, n: string, bg: string, fg: string)
		local card = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, 152), Size = UDim2.fromOffset(60, 86), BackgroundColor3 = Color3.fromHex("#f4f4f4"), BorderSizePixel = 0, Parent = r }, { Ui.corner(3) })
		Ui.new("Frame", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -22), BackgroundColor3 = Color3.fromHex(bg), BorderSizePixel = 0, Parent = card }, {
			Ui.text({ Text = n, TextSize = 44, TextColor3 = Color3.fromHex(fg), Size = UDim2.fromScale(1, 1) }),
		})
		-- The chequered strip along the bottom.
		for i = 0, 5 do
			Ui.new("Frame", { Position = UDim2.new(0, 4 + i * 9, 1, -16), Size = UDim2.fromOffset(9, 6), BackgroundColor3 = Color3.fromHex(if i % 2 == 0 then "#1b1b1b" else "#f4f4f4"), BorderSizePixel = 0, Parent = card })
			Ui.new("Frame", { Position = UDim2.new(0, 4 + i * 9, 1, -10), Size = UDim2.fromOffset(9, 6), BackgroundColor3 = Color3.fromHex(if i % 2 == 0 then "#f4f4f4" else "#1b1b1b"), BorderSizePixel = 0, Parent = card })
		end
	end
	number(-276, "7", "#d32f2f", "#ffffff")
	number(138, "1", "#1e4fbf", "#ffd84a")
	-- The turntable: a pale disc with a darker rim, seen from above at an angle.
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 560), Size = UDim2.fromOffset(980, 340), BackgroundColor3 = Color3.fromHex("#c9d3e0"), BackgroundTransparency = 0.35, BorderSizePixel = 0, Parent = r }, { Ui.round() })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 552), Size = UDim2.fromOffset(820, 280), BackgroundColor3 = Color3.fromHex("#8d97a8"), BorderSizePixel = 0, Parent = r }, { Ui.round(), Ui.stroke(3, Color3.fromHex("#dfe7f1"), 0.3) })
	return r
end

-- A floating glass card (the list and the details), as .garage-list / .garage-detail.
local function glass(parent: Instance, name: string, props: { [string]: any }): Frame
	local shadow = Ui.new("Frame", { Name = name, BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 2, Parent = parent }, { Ui.corner(16) })
	for k, v in props do
		(shadow :: any)[k] = v
	end
	local g = Ui.new("Frame", { Name = "Glass", Position = UDim2.fromOffset(0, -4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = GLASS, BackgroundTransparency = 0.08, ZIndex = 2, Parent = shadow }, { Ui.corner(16) })
	return g
end

-- A chip like the web's .skill-tag / .loves-tag / .body-chip.
local function tag(parent: Instance, order: number, text: string, bg: string, fg: string, edge: string?)
	local f = Ui.new("Frame", { Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex(bg), LayoutOrder = order, ZIndex = 3, Parent = parent }, {
		Ui.round(),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	if edge then
		Ui.stroke(1.5, Color3.fromHex(edge)).Parent = f
	end
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex(fg), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = f })
end

local function traits(parent: Instance, def: any, y: number, body: boolean): Frame
	local row = Ui.new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 3, Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	if body then
		tag(row, 1, bodyLabel(def.body), "#eceff1", "#37474f")
	end
	if def.skill then
		local sk = data.SKILLS[def.skill]
		if sk then
			tag(row, 2, `{sk.icon} {sk.name}`, "#ede7f6", "#4527a0")
		end
	end
	if def.likes and #def.likes > 0 then
		local icons = "❤️"
		for _, id in def.likes do
			icons ..= BUILDING_ICONS[id] or "🏪"
		end
		tag(row, 3, icons, "#fde4ef", "#ad1457")
	end
	return row
end

-- The list's two filter boxes (the web's selects): a tap steps to the next choice.
local function picker(parent: Instance, icon: string, x: number, label: string, onTap: () -> ()): TextLabel
	local b = Ui.new("TextButton", { Text = "", AutoButtonColor = false, Position = UDim2.new(x, if x > 0 then 3 else 0, 0, 0), Size = UDim2.new(0.5, -3, 0, 34), BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = parent }, {
		Ui.corner(10),
		Ui.stroke(1.5, Ui.EDGE),
	})
	Icons.draw(icon, b, 14, Ui.BLUE, Ui.WHITE, UDim2.new(0, 10, 0.5, 0), Vector2.new(0, 0.5)).ZIndex = 3
	local t = Ui.text({ Text = label, TextSize = 13, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(1, -44, 1, 0), ZIndex = 3, Parent = b })
	Ui.text({ Text = "▾", TextSize = 11, TextColor3 = Color3.fromHex("#607d8b"), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(12, 34), ZIndex = 3, Parent = b })
	b.Activated:Connect(onTap)
	return t
end

-- One row in the car list: picture, name, and a line under it.
local function listItem(parent: Instance, order: number, model: string, color: string, name: string, sub: string, right: string?, selected: boolean, dim: boolean, onTap: () -> ())
	local h = 62
	local b = Ui.new("TextButton", {
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
		Size = UDim2.new(1, -4, 0, h),
		BackgroundColor3 = if selected then Color3.fromHex("#eaf3ff") else Ui.WHITE,
		ZIndex = 3,
		Parent = parent,
	}, { Ui.corner(12), Ui.stroke(2, if selected then Color3.fromHex("#2f7ff0") else Ui.EDGE) })
	local box = Ui.new("Frame", { Position = UDim2.fromOffset(6, 5), Size = UDim2.fromOffset(60, 52), BackgroundColor3 = Color3.fromHex("#e9f1fb"), ZIndex = 3, Parent = b }, { Ui.corner(10) })
	local pic = Thumb.new("Cars", model, UDim2.fromScale(1, 1), Color3.fromHex(color))
	pic.ZIndex = 3
	if dim then
		pic.ImageTransparency = 0.45
	end
	pic.Parent = box
	local ink = if dim then Color3.fromHex("#78849a") else LINE
	Ui.text({ Text = name, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = ink, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, TextYAlignment = if sub ~= "" then Enum.TextYAlignment.Bottom else Enum.TextYAlignment.Center, Position = UDim2.fromOffset(74, 4), Size = UDim2.new(1, -80 - (if right then 44 else 0), 0, if sub ~= "" then 34 else h - 8), ZIndex = 3, Parent = b })
	if sub ~= "" then
		Ui.text({ Text = sub, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = if dim then Color3.fromHex("#8c97a8") else Color3.fromHex("#37474f"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(74, 38), Size = UDim2.new(1, -80, 0, 18), ZIndex = 3, Parent = b })
	end
	if right then
		Ui.text({ Text = right, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.fromOffset(44, h), ZIndex = 3, Parent = b })
	end
	b.Activated:Connect(onTap)
end

-- tab: the tab to open on, or { car = uid, paint = colour } for the garage's Paint tab with that
-- colour tried on the car (after winning it from a paint rival), or { car = uid, tab = "mods" |
-- "tune" | "custom" } for that car on one of the garage's tabs (a Tuner Trial's missing part).
function Cars.open(ctx: any, tab: any): Instance
	local s0 = store.useGame.getState()
	local paintPick = if type(tab) == "table" then tab else nil
	local current: string = if paintPick then "garage" else tab or lastTab
	CallCards.reset()
	CrateDepot.reset()
	local overlay = Ui.new("TextButton", { Name = "Panel", Text = "", AutoButtonColor = false, ZIndex = 20, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = ctx.gui })
	local page = Ui.new("Frame", { Name = "Cars", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#0f141d"), BorderSizePixel = 0, Parent = overlay })
	room(page)
	-- The title bar, as every menu's, square-cornered across the top of the screen.
	local head = Ui.new("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 61), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 5, Parent = page }, {
		Ui.gradient(Ui.COLORS.head[1], Ui.COLORS.head[2]),
	})
	Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -3), BorderSizePixel = 0, BackgroundColor3 = LINE, ZIndex = 6, Parent = head })
	Ui.new("Frame", { BorderSizePixel = 0, BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.65, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, 0, 0, 3), ZIndex = 6, Parent = head })
	Ui.text({ Name = "Title", Text = "Cars", TextSize = 32, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18, 6), Size = UDim2.fromOffset(300, 47), Stroke = 3, Shadow = 4, ZIndex = 6, Parent = head })
	Ui.closeButton({ Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(42, 42), ZIndex = 6, Parent = head }, ctx.close)
	local extras = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, -1), Size = UDim2.fromOffset(240, 34), BackgroundTransparency = 1, ZIndex = 6, Parent = head }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local power = Ui.new("Frame", { Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#0a1e46"), BackgroundTransparency = 0.55, LayoutOrder = 1, ZIndex = 6, Parent = extras }, {
		Ui.round(),
		Ui.stroke(2, LINE, 0.45),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	local powerText = Ui.text({ Text = "⚡0", Body = true, Weight = "heavy", TextSize = 15, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 6, Parent = power })
	local hasJobs = false
	for _, b in s0.buildings do
		local d = data.buildingDef(b.def)
		if d.jobSeconds and d.kind ~= "obstacle" then
			hasJobs = true
		end
	end
	if #s0.cars > 0 and hasJobs then
		local auto = Ui.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#effbea"), LayoutOrder = 2, ZIndex = 6, Parent = extras }, {
			Ui.round(),
			Ui.stroke(2, Color3.fromHex("#2e7d32")),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 12) }),
		})
		Ui.text({ Text = "🧑‍✈️ Auto", Body = true, Weight = "heavy", TextSize = 15, TextColor3 = LINE, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 6, Parent = auto })
		auto.Activated:Connect(function()
			-- Auto jobs: the best car on every business, cars that love a place first.
			local ok = Remote.act("autoAssign")
			if ok then
				ctx.toast("🧑‍✈️ Best car on every business")
			end
		end)
	end

	local content = Ui.new("Frame", { Name = "Content", Position = UDim2.fromOffset(0, 113), Size = UDim2.new(1, 0, 1, -113), BackgroundTransparency = 1, ZIndex = 2, Parent = page })
	local spin: RBXScriptConnection? = nil
	local function clear()
		if spin then
			spin:Disconnect()
			spin = nil
		end
		for _, c in content:GetChildren() do
			c:Destroy()
		end
	end

	-- The car on the turntable, turning slowly, framed in the space between the two cards.
	local function stage(model: string, job: Paint.Job, pi: number, owned: number?, hat: any?, mods: { string }?, panels: any?, trim: any?, skin: string?, modSkin: any?)
		local v = Thumb.car(model, UDim2.new(1, -700, 1, -40), job, hat, mods, panels, trim, skin, modSkin)
		v.Position = UDim2.fromOffset(280, 10)
		v.ZIndex = 1
		v.Parent = content
		local m = v:FindFirstChildOfClass("Model")
		local cam = v:FindFirstChildOfClass("Camera")
		if m and cam then
			local cf = m:GetBoundingBox()
			local dist = (cam.CFrame.Position - cf.Position).Magnitude * 0.92
			local a = 0.7
			spin = RunService.RenderStepped:Connect(function(dt: number)
				a += dt * 0.5
				cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(math.cos(a), 0.5, math.sin(a)).Unit * dist, cf.Position)
			end)
		end
		local badge = Ui.new("Frame", { Position = UDim2.fromOffset(286, 14), Size = UDim2.fromOffset(48, 42), BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = content }, {
			Ui.corner(9),
			Ui.stroke(2.5, Ui.WHITE),
			Ui.gradient("#3d8bff", "#1e5fd0"),
		})
		Ui.text({ Text = tostring(pi), TextSize = 22, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 24), ZIndex = 3, Parent = badge })
		Ui.text({ Text = "PI", TextSize = 11, Position = UDim2.fromOffset(0, 25), Size = UDim2.new(1, 0, 0, 14), ZIndex = 3, Parent = badge })
		if owned and owned > 0 then
			local ok = Ui.new("Frame", { Position = UDim2.fromOffset(286, 64), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#2e8b34"), ZIndex = 3, Parent = content }, {
				Ui.round(),
				Ui.stroke(2, Ui.WHITE),
				Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
			})
			Ui.text({ Text = if owned > 1 then `✔ ×{owned}` else "✔", Body = true, Weight = "heavy", TextSize = 13, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = ok })
		end
		local hint = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, -6, 1, -14), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#eceff1"), BackgroundTransparency = 0.1, ZIndex = 3, Parent = content }, {
			Ui.round(),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		})
		Ui.text({ Text = "It turns on its own", Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#37474f"), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = hint })
	end

	local render: () -> ()
	-- Switches the tab strip's highlight (set once the tabs are made below).
	local pickTab: (string) -> () = function() end

	-- ── My Cars ───────────────────────────────────────────────────────────────────────────────
	local selected: string? = s0.selectedCar
	local garageTab = "tune"
	-- A paint job being tried on in the Paint tab (the car's uid and the job).
	local painting: { uid: string, job: Paint.Job }? = nil
	-- A hat being tried on in the Hats tab (false: trying no hat).
	local hatting: { uid: string, hat: any }? = nil
	-- A mod part being tried on in the Mods tab.
	local modding: { uid: string, id: string }? = nil
	-- Custom paint being tried on in the Custom tab.
	local customing: { uid: string, panels: any }? = nil
	-- Trim being tried on in the Trim tab.
	local trimming: { uid: string, trim: any }? = nil
	-- A body skin being tried on in the Paint tab, and a mod skin in the Mods tab (skin false:
	-- trying none).
	local skinning: { uid: string, skin: SkinShop.Trying }? = nil
	local modSkinning: { uid: string, slot: string, skin: SkinShop.Trying }? = nil
	-- Cars whose mod meshes have been asked for (they load the first time a car needs them).
	local asked: { [string]: boolean } = {}
	if paintPick then
		for _, c in s0.cars do
			if c.uid == paintPick.car then
				selected, garageTab = c.uid, paintPick.tab or "paint"
				if paintPick.paint then
					local job = table.clone(Paint.jobOf(c))
					job.color = paintPick.paint
					painting = { uid = c.uid, job = job }
				end
			end
		end
	end
	local function garage()
		local s = store.useGame.getState()
		local rows = {}
		local kinds: { { id: string, label: string } } = { { id = "all", label = `All ({#s.cars})` } }
		local counts: { [string]: number } = {}
		for i, c in s.cars do
			local d = data.carDef(c.model)
			table.insert(rows, { c = c, d = d, i = i, pi = data.performance(d, c.upgrades, c.mods) })
			counts[d.body] = (counts[d.body] or 0) + 1
		end
		local bodies = {}
		for b, n in counts do
			if n > 1 then
				table.insert(bodies, b)
			end
		end
		table.sort(bodies)
		for _, b in bodies do
			table.insert(kinds, { id = b, label = `{bodyLabel(b)} ({counts[b]})` })
		end
		local kind = garageView.kind
		local okKind = false
		for _, k in kinds do
			if k.id == kind then
				okKind = true
			end
		end
		if not okKind then
			kind = "all"
		end
		local list = {}
		for _, r in rows do
			if kind == "all" or r.d.body == kind then
				table.insert(list, r)
			end
		end
		local sort = garageView.sort
		table.sort(list, function(a, b)
			if sort == "pi-low" then
				return if a.pi ~= b.pi then a.pi < b.pi else a.i < b.i
			elseif sort == "name" then
				return a.d.name < b.d.name
			elseif sort == "new" then
				return a.i > b.i
			end
			return if a.pi ~= b.pi then a.pi > b.pi else a.i < b.i
		end)
		local car
		for _, r in rows do
			if r.c.uid == selected then
				car = r
			end
		end
		car = car or list[1] or rows[1]
		if not car then
			local empty = glass(content, "Empty", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(420, 120) })
			Ui.text({ Text = "🚗 No cars yet. Buy one under For Sale.", TextSize = 18, TextColor3 = LINE, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = empty })
			return
		end
		local tryJob = if painting and painting.uid == car.c.uid and garageTab == "paint" then painting.job else nil
		local tryHat = if hatting and hatting.uid == car.c.uid and garageTab == "hats" then hatting.hat else nil
		local tryMod = if modding and modding.uid == car.c.uid and garageTab == "mods" then modding.id else nil
		local mods = ModShop.withMod(car.c.mods, tryMod)
		local tryPanels = if customing and customing.uid == car.c.uid and garageTab == "custom" then customing.panels else nil
		local panels = tryPanels or car.c.panels
		local tryTrim = if trimming and trimming.uid == car.c.uid and garageTab == "trim" then trimming.trim else nil
		local trim = tryTrim or car.c.trim
		local trySkin: SkinShop.Trying = if skinning and skinning.uid == car.c.uid and garageTab == "paint" then skinning.skin else nil
		local skin = if trySkin == nil then car.c.skin elseif trySkin == false then nil else trySkin
		local tryModSkin = if modSkinning and modSkinning.uid == car.c.uid and garageTab == "mods" then modSkinning else nil
		local modSkin = car.c.modSkin
		if tryModSkin then
			modSkin = table.clone(modSkin or {})
			modSkin[tryModSkin.slot] = tryModSkin.skin or nil
		end
		stage(car.c.model, tryJob or Paint.jobOf(car.c), car.pi, nil, if tryHat == nil then car.c.hat elseif tryHat == false then nil else tryHat, mods, panels, trim, skin, modSkin)
		-- The car's mod and custom paint meshes, the first time it shows them or opens the Mods or
		-- Custom tab: drawn again once in.
		if not asked[car.c.model] and (#mods > 0 or panels ~= nil or garageTab == "mods" or garageTab == "custom") then
			asked[car.c.model] = true
			local model = car.c.model
			task.spawn(function()
				Remote.meshesFor(model)
				task.wait(0.5)
				if page.Parent then
					render()
				end
			end)
		end

		local listCard = glass(content, "List", { Position = UDim2.fromOffset(12, 16), Size = UDim2.new(0, 260, 1, -28) })
		local filters = Ui.new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 34), BackgroundTransparency = 1, ZIndex = 3, Parent = listCard })
		local kindLabel = "All"
		for _, k in kinds do
			if k.id == kind then
				kindLabel = k.label
			end
		end
		local sortLabel = "Top PI"
		for _, o in CAR_SORTS do
			if o.id == sort then
				sortLabel = o.label
			end
		end
		picker(filters, "filter", 0, kindLabel, function()
			for i, k in kinds do
				if k.id == kind then
					garageView.kind = kinds[i % #kinds + 1].id
				end
			end
			render()
		end)
		picker(filters, "sort", 0.5, sortLabel, function()
			for i, o in CAR_SORTS do
				if o.id == sort then
					garageView.sort = CAR_SORTS[i % #CAR_SORTS + 1].id
				end
			end
			render()
		end)
		local scroll = Ui.scroller({ Position = UDim2.fromOffset(8, 50), Size = UDim2.new(1, -12, 1, -58), ZIndex = 3, Parent = listCard })
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		Ui.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), Parent = scroll })
		for i, r in list do
			listItem(scroll, i, r.c.model, r.c.color, r.d.name, "", `PI {r.pi}`, r == car, false, function()
				selected = r.c.uid
				render()
			end)
		end

		-- The details: name, traits, the racing and show-off toggles, then the tabs.
		local detail = glass(content, "Detail", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 16), Size = UDim2.new(0, 400, 1, -28) })
		local pad = Ui.new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -24), BackgroundTransparency = 1, ZIndex = 3, Parent = detail })
		Ui.text({ Text = car.d.name, TextSize = 22, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 26), ZIndex = 3, Parent = pad })
		traits(pad, car.d, 34, false)
		local racing = raceCar.raceCarOf(s.cars, s.raceCar)
		local isRace = racing ~= nil and racing.uid == car.c.uid
		local onShow = table.find(s.showcase or {}, car.c.uid) ~= nil
		local _, raceFace = Ui.button({ Position = UDim2.new(0, 0, 0, 74), Size = UDim2.new(0.5, -6, 0, 38), Parent = pad }, if isRace then "green" else "white", function()
			if not isRace then
				Remote.act("setRaceCar", car.c.uid)
				render()
			end
		end, { radius = 10, stroke = 2, drop = 2, dark = 0.25, strokeColor = if isRace then Color3.fromHex("#1d6b22") else Ui.EDGE, flat = not isRace })
		raceFace.ZIndex = 3
		Ui.text({ Text = if isRace then "🏁 Racing" else "🏁 Race with", Body = true, Weight = "heavy", TextSize = 15, TextColor3 = if isRace then Ui.WHITE else LINE, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = raceFace })
		local _, showFace = Ui.button({ Position = UDim2.new(0.5, 6, 0, 74), Size = UDim2.new(0.5, -6, 0, 38), Parent = pad }, if onShow then "edit" else "white", function()
			Remote.act("toggleShowcase", car.c.uid)
			render()
		end, { radius = 10, stroke = 2, drop = 2, dark = 0.25, strokeColor = if onShow then LINE else Ui.EDGE, flat = not onShow })
		Ui.text({ Text = if onShow then "⭐ On show" else "☆ Show off", Body = true, Weight = "heavy", TextSize = 15, TextColor3 = LINE, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = showFace })

		local tabs = Ui.new("Frame", { Position = UDim2.fromOffset(0, 124), Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Ui.SEG, ZIndex = 3, Parent = pad }, {
			Ui.corner(12),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }),
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local GTABS = { { "tune", "🔧", "Upgrades" }, { "mods", "🪽", "Mods" }, { "paint", "🎨", "Paint" }, { "custom", "🖌️", "Custom" }, { "trim", "✨", "Trim" }, { "hats", "🎩", "Hats" } }
		for i, t in GTABS do
			local on = garageTab == t[1]
			local b = Ui.new("TextButton", { Name = t[1], Text = "", AutoButtonColor = false, LayoutOrder = i, Size = UDim2.fromOffset(40, 44), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = if on then 0 else 1, ZIndex = 3, Parent = tabs }, { Ui.corner(9) })
			Ui.text({ Text = t[2], TextSize = 16, Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 20), ZIndex = 3, Parent = b })
			Ui.text({ Text = t[3], TextSize = 12, TextColor3 = if on then Color3.fromHex("#263238") else Color3.fromHex("#546e7a"), Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 16), ZIndex = 3, Parent = b })
			b.Activated:Connect(function()
				if garageTab ~= t[1] then
					HatShop.reset()
					ModShop.reset()
					CustomShop.reset()
					skinning = nil
					modSkinning = nil
				end
				garageTab = t[1]
				render()
			end)
		end
		local y = 190
		if garageTab == "tune" then
			for _, u in data.UPGRADE_SLOTS do
				local lvl = car.c.upgrades[u.id] or 0
				local row = Ui.new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, ZIndex = 3, Parent = pad })
				Ui.new("Frame", { Position = UDim2.new(0, 0, 1, -1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromHex("#e3e9f0"), BorderSizePixel = 0, ZIndex = 3, Parent = row })
				Ui.text({ Text = u.name, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -200, 1, 0), ZIndex = 3, Parent = row })
				local pips = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0), Size = UDim2.fromOffset(5 * 13, 14), BackgroundTransparency = 1, ZIndex = 3, Parent = row }, {
					Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
				})
				for p = 1, data.MAX_UPGRADE do
					Ui.new("Frame", { Size = UDim2.fromOffset(10, 14), BackgroundColor3 = if p <= lvl then Color3.fromHex("#ff9f1a") else Color3.fromHex("#dfe5ea"), LayoutOrder = p, ZIndex = 3, Parent = pips }, { Ui.corner(3) })
				end
				if lvl < data.MAX_UPGRADE then
					local cost = data.upgradeCost(car.d, lvl)
					local broke = s.coins < cost.coins or s.parts < cost.parts
					local _, f = Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 1), Size = UDim2.fromOffset(84, 30), Parent = row }, `${Ui.commas(cost.coins)} + {cost.parts}⚙`, "green", function()
						if broke then
							ctx.open("need", if s.coins < cost.coins then { res = "coins", missing = cost.coins - s.coins, what = "that upgrade" } else { res = "parts", missing = cost.parts - s.parts, what = "that upgrade" })
							return
						end
						Remote.act("upgradeCar", car.c.uid, u.id)
						render()
					end, 13)
					f.ZIndex = 3
				else
					Ui.text({ Text = "MAX", TextSize = 14, TextColor3 = Color3.fromHex("#2e7d32"), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 0), Size = UDim2.fromOffset(60, 46), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = row })
				end
				y += 46
			end
		elseif garageTab == "mods" then
			local space = Ui.new("Frame", { Name = "Shop", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 4, 1, -y), BackgroundTransparency = 1, ZIndex = 3, Parent = pad })
			ModShop.draw(space, ctx, car.c, tryMod, function(id: string?)
				modding = if id then { uid = car.c.uid, id = id } else nil
				render()
			end, tryModSkin, function(t: { slot: string, skin: SkinShop.Trying }?)
				modSkinning = if t then { uid = car.c.uid, slot = t.slot, skin = t.skin } else nil
				render()
			end)
			return
		elseif garageTab == "custom" then
			local space = Ui.new("Frame", { Name = "Shop", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 4, 1, -y), BackgroundTransparency = 1, ZIndex = 3, Parent = pad })
			CustomShop.draw(space, ctx, car.c, panels, function(p: any)
				customing = if p then { uid = car.c.uid, panels = p } else nil
				render()
			end)
			return
		elseif garageTab == "trim" then
			local space = Ui.new("Frame", { Name = "Shop", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 4, 1, -y), BackgroundTransparency = 1, ZIndex = 3, Parent = pad })
			TrimShop.draw(space, ctx, car.c, trim, function(t: any)
				trimming = if t then { uid = car.c.uid, trim = t } else nil
				render()
			end)
			return
		elseif garageTab == "hats" then
			local space = Ui.new("Frame", { Name = "Shop", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 4, 1, -y), BackgroundTransparency = 1, ZIndex = 3, Parent = pad })
			HatShop.draw(space, ctx, car.c, tryHat, function(h: any)
				hatting = if h == nil then nil else { uid = car.c.uid, hat = h }
				render()
			end)
			return
		elseif garageTab == "paint" then
			local space = Ui.new("Frame", { Name = "Shop", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 4, 1, -y), BackgroundTransparency = 1, ZIndex = 3, Parent = pad })
			PaintShop.draw(space, ctx, car.c, tryJob or Paint.jobOf(car.c), function(job: Paint.Job?)
				painting = if job then { uid = car.c.uid, job = job } else nil
				render()
			end, function(list: Instance)
				SkinShop.body(list, 0, car.c, (tryJob or Paint.jobOf(car.c)).color, trySkin, function(t: SkinShop.Trying)
					skinning = if t == nil then nil else { uid = car.c.uid, skin = t }
					render()
				end)
			end)
			return
		else
			Ui.text({ Text = "🛠 This shop is coming to Roblox soon.", Body = true, TextSize = 14, TextColor3 = Color3.fromHex("#546e7a"), TextWrapped = true, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 40), ZIndex = 3, Parent = pad })
			y += 46
		end
		if not car.d.bucks then
			local value = math.floor(car.d.price * 0.5)
			local sell = Ui.new("TextButton", { Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, y + 14), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 3, Parent = pad })
			Ui.text({ Text = `Sell for ${Ui.commas(value)}`, TextSize = 13, TextColor3 = Color3.fromHex("#c62828"), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = sell })
			Ui.new("Frame", { Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 1.5), BackgroundColor3 = Color3.fromHex("#c62828"), BorderSizePixel = 0, ZIndex = 3, Parent = sell })
			-- A second tap sells, as the web's "Sell this car?" check.
			local armed = false
			sell.Activated:Connect(function()
				if not armed then
					armed = true
					local label = sell:FindFirstChildOfClass("TextLabel")
					if label then
						label.Text = `Tap again to sell · ${Ui.commas(value)}`
					end
					return
				end
				Remote.act("sellCar", car.c.uid)
				selected = nil
				render()
			end)
		end
	end

	-- ── For Sale ──────────────────────────────────────────────────────────────────────────────
	local colorFor: { [string]: string } = {}
	local function sale()
		local s = store.useGame.getState()
		local gate = store.gateLevel(s)
		local rusty = store.hasRusty(s)
		local owned: { [string]: number } = {}
		for _, c in s.cars do
			owned[c.model] = (owned[c.model] or 0) + 1
		end
		local forSale = {}
		for i, c in data.CARS do
			if not c.rescueOnly and not c.season and not c.secret and not c.pack then
				table.insert(forSale, c)
			end
		end
		local function afford(c: any): boolean
			return s.coins >= c.price and s.bucks >= (c.bucks or 0)
		end
		local function canBuy(c: any): boolean
			return rusty and gate >= c.unlockLevel and afford(c)
		end
		local counts: { [string]: number } = {}
		local nBuy, nNew = 0, 0
		for _, c in forSale do
			counts[c.body] = (counts[c.body] or 0) + 1
			if canBuy(c) then
				nBuy += 1
			end
			if not owned[c.id] then
				nNew += 1
			end
		end
		local kinds = { { id = "all", label = `All ({#forSale})` }, { id = "buy", label = `Can buy ({nBuy})` }, { id = "new", label = `Not owned ({nNew})` } }
		local bodies = {}
		for b, n in counts do
			if n > 1 then
				table.insert(bodies, b)
			end
		end
		table.sort(bodies)
		for _, b in bodies do
			table.insert(kinds, { id = b, label = `{bodyLabel(b)} ({counts[b]})` })
		end
		local kind = saleView.kind
		local list = {}
		for i, c in forSale do
			local keep = kind == "all" or (if kind == "buy" then canBuy(c) elseif kind == "new" then not owned[c.id] else c.body == kind)
			if keep then
				table.insert(list, { c = c, i = i, gate = if gate < c.unlockLevel then c.unlockLevel else 0, pi = data.performance(c, NO_UPGRADES), cost = c.price + (c.bucks or 0) * (data.GEM_BUILD_COINS or 100) })
			end
		end
		local sort = saleView.sort
		table.sort(list, function(a, b)
			if sort == "cheap" then
				return a.cost < b.cost
			elseif sort == "dear" then
				return a.cost > b.cost
			elseif sort == "pi" then
				return a.pi > b.pi
			elseif sort == "name" then
				return a.c.name < b.c.name
			end
			return if a.gate ~= b.gate then a.gate < b.gate else a.i < b.i
		end)
		local row = list[1]
		for _, r in list do
			if r.c.id == lastSale then
				row = r
			end
		end
		if not row then
			return
		end
		local c = row.c
		lastSale = c.id
		local color = colorFor[c.id] or c.colors[1]
		local locked = gate < c.unlockLevel
		stage(c.id, { color = color }, row.pi, owned[c.id])

		local listCard = glass(content, "List", { Position = UDim2.fromOffset(12, 16), Size = UDim2.new(0, 260, 1, -28) })
		local filters = Ui.new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 34), BackgroundTransparency = 1, ZIndex = 3, Parent = listCard })
		local kindLabel, sortLabel = "All", "Level"
		for _, k in kinds do
			if k.id == kind then
				kindLabel = k.label
			end
		end
		for _, o in SALE_SORTS do
			if o.id == sort then
				sortLabel = o.label
			end
		end
		picker(filters, "filter", 0, kindLabel, function()
			local at = 1
			for i, k in kinds do
				if k.id == kind then
					at = i
				end
			end
			saleView.kind = kinds[at % #kinds + 1].id
			render()
		end)
		picker(filters, "sort", 0.5, sortLabel, function()
			for i, o in SALE_SORTS do
				if o.id == sort then
					saleView.sort = SALE_SORTS[i % #SALE_SORTS + 1].id
				end
			end
			render()
		end)
		local scroll = Ui.scroller({ Position = UDim2.fromOffset(8, 50), Size = UDim2.new(1, -12, 1, -58), ZIndex = 3, Parent = listCard })
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		Ui.new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), Parent = scroll })
		for i, r in list do
			local x = r.c
			local lock = gate < x.unlockLevel
			local n = owned[x.id] or 0
			local price = if (x.bucks or 0) > 0 then `💎 {Ui.commas(x.bucks)}` else `${Ui.commas(x.price)}`
			listItem(scroll, i, x.id, colorFor[x.id] or x.colors[1], x.name .. (if n > 0 then " ✔" else ""), if lock then `🔒 Lv {x.unlockLevel}` else `PI {r.pi} · {price}`, nil, r == row, lock, function()
				lastSale = x.id
				render()
			end)
		end

		local detail = glass(content, "Detail", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 16), Size = UDim2.fromOffset(400, if rusty then 196 else 214) })
		local pad = Ui.new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -24), BackgroundTransparency = 1, ZIndex = 3, Parent = detail })
		Ui.text({ Text = c.name, TextSize = 22, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 26), ZIndex = 3, Parent = pad })
		traits(pad, c, 34, true)
		local dots = Ui.new("Frame", { Position = UDim2.fromOffset(2, 76), Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 3, Parent = pad }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
		})
		for i, hex in c.colors do
			local sel = hex == color
			local d = Ui.new("TextButton", { Text = "", AutoButtonColor = false, LayoutOrder = i, Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromHex(hex), ZIndex = 3, Parent = dots }, {
				Ui.round(),
				Ui.stroke(if sel then 3 else 1, if sel then Color3.fromHex("#ff9f1a") else Color3.fromHex("#90a4ae")),
			})
			-- The white ring inside the outline, as the web's swatches.
			Ui.new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 3, Parent = d }, { Ui.round(), Ui.stroke(2.5, Ui.WHITE) })
			d.Activated:Connect(function()
				colorFor[c.id] = hex
				render()
			end)
		end
		if not rusty then
			local box = Ui.new("Frame", { Position = UDim2.fromOffset(0, 128), Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = Color3.fromHex("#fff3e0"), ZIndex = 3, Parent = pad }, {
				Ui.corner(14),
				Ui.stroke(2.5, Color3.fromHex("#ff9f1a")),
			})
			Ui.text({ Text = "🔧", TextSize = 26, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(40, 62), ZIndex = 3, Parent = box })
			Ui.text({ Text = "Build Rusty's Rescue first", Body = true, Weight = "heavy", TextSize = 15, TextColor3 = LINE, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -200, 1, 0), ZIndex = 3, Parent = box })
			local _, b = Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 1), Size = UDim2.fromOffset(124, 32), Parent = box }, `Build · ${Ui.commas(data.buildingDef("rescue").price)}`, "green", function()
				ctx.open("shop", "rescue")
			end, 15)
			b.ZIndex = 3
		else
			local label, kindName
			if locked then
				label, kindName = `🔒 Level {c.unlockLevel}`, "grey"
			else
				label = "Buy " .. (if (c.bucks or 0) > 0 then `💎 {Ui.commas(c.bucks)}` else `${Ui.commas(c.price)}`)
				kindName = if afford(c) then "green" else "broke"
			end
			Ui.buy({ Position = UDim2.fromOffset(0, 124), Size = UDim2.new(1, 0, 0, 50), Parent = pad }, label, kindName, function()
				if locked then
					ctx.open("need", { res = "level", missing = c.unlockLevel, what = c.name })
				elseif not afford(c) then
					ctx.open("need", if s.bucks < (c.bucks or 0) then { res = "bucks", missing = (c.bucks or 0) - s.bucks, what = c.name } else { res = "coins", missing = c.price - s.coins, what = c.name })
				else
					local ok = Remote.act("buyCar", c.id, color)
					if ok then
						ctx.toast("New car! It's parked by your garage.")
						render()
					end
				end
			end, 22)
		end
	end

	local TABS = {
		{ id = "garage", label = "🔧 My Cars" },
		{ id = "shop", label = "🚘 For Sale" },
		{ id = "book", label = "📖 Collection" },
		{ id = "cards", label = "🃏 Call Cards" },
		{ id = "crates", label = "📦 Crates" },
	}
	render = function()
		clear()
		local s = store.useGame.getState()
		Ui.setText(powerText, `⚡{Ui.compact(data.garagePower(s.cars))}`)
		if current == "shop" then
			sale()
		elseif current == "book" then
			-- A missing car: its card in For Sale when the dealer sells it.
			Collection.draw(content, ctx, function(model: string)
				local def = data.carDef(model)
				if def.secret then
					pickTab("crates")
					current = "crates"
					render()
				elseif not def.rescueOnly and not def.season and not def.pack then
					lastSale = model
					pickTab("shop")
					current = "shop"
					render()
				elseif def.rescueOnly and store.hasRusty(store.useGame.getState()) then
					ctx.open("rescue")
				else
					ctx.toast(`{def.name}: {data.carSource(def).text}`)
				end
			end)
		elseif current == "crates" then
			CrateDepot.draw(content, ctx)
		elseif current == "cards" then
			-- Your race car turns on the stage; its card is picked on the right.
			local car = raceCar.raceCarOf(s.cars, s.raceCar)
			if car then
				local d = data.carDef(car.model)
				stage(car.model, Paint.jobOf(car), data.performance(d, car.upgrades, car.mods), nil, car.hat)
			end
			CallCards.draw(content, ctx, function()
				CrateDepot.reset()
				pickTab("crates")
				current = "crates"
				lastTab = "crates"
				render()
			end, render)
		else
			garage()
		end
	end
	local READY = { garage = true, shop = true, book = true, cards = true, crates = true }
	local _tabs
	_tabs, pickTab = Ui.tabs(page, TABS, current, function(id)
		if READY[id] then
			if current ~= id then
				CrateDepot.reset()
				CallCards.reset()
			end
			current = id
			lastTab = id
			render()
		end
	end, { dark = true, position = UDim2.fromOffset(0, 61), size = UDim2.new(1, 0, 0, 52) })
	-- The tabs the Roblox game doesn't have yet say so and stay on the page you're on.
	for _, t in TABS do
		if not READY[t.id] then
			local face = (_tabs :: any)[t.id].Face :: TextButton
			face.Activated:Connect(function()
				ctx.toast(`{t.label:sub(((t.label:find(" ")) or 0) + 1)} is coming to Roblox soon`)
				pickTab(current)
			end)
		end
	end
	-- Buying, upgrading or selling comes back as a new town: redraw with it.
	local conn = Remote.changed:Connect(function()
		if overlay.Parent then
			render()
		end
	end)
	overlay.Destroying:Connect(function()
		conn:Disconnect()
		if spin then
			spin:Disconnect()
		end
	end)
	render()
	return overlay
end

return Cars
