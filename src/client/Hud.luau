--!strict
-- The heads-up display, laid out like the web game's Hud and BottomBar (ui/Hud.tsx, Menus.tsx):
-- the speedometer level gauge (it's also the Menu button) and the coin, gem and parts pills top
-- left; the town name, MY CARS and the goal tracker top middle; fuel, trophies and sound top
-- right; SHOP, CARS, SOCIAL, CHAT and EDIT bottom left, RACE bottom right, with Goals and Collect
-- All docked above it. While visiting someone's town the bottom bar steps aside for the visit
-- banner (Popups/Visit), as on the web. Also shows toasts and the menus (one at a time), including the ones the server opens.
--
-- Built once. The refresh only changes text, sizes and colours that changed; it never makes
-- instances.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Motion = require(script.Parent.Motion)
local Icons = require(script.Parent.Icons)
local Shop = require(script.Parent.Shop)
local Cars = require(script.Parent.Cars)
local Goals = require(script.Parent.Goals)
local Fly = require(script.Parent.Fly)
local Rescue = require(script.Parent.Rescue)
local Menu = require(script.Parent.Menu)
local Upgrade = require(script.Parent.Upgrade)
local Placement = require(script.Parent.Placement)
local TownCamera = require(script.Parent.TownCamera)
local Jobs = require(script.Parent.Jobs)
local RaceMenu = require(script.Parent.RaceMenu)
local Bank = require(script.Parent.Bank)
local Tutorial = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tutorial")) :: any

local Hud = {}

-- More menus (client/Panels/*.luau), by the web game's panel name: each module has `id` and
-- `open(ctx, arg)` returning the menu's overlay. And pop-ups (client/Popups/*.luau): each
-- module's `start(ctx)` runs once the HUD is up, to watch for what it shows.
local PANELS: { [string]: any } = {}
local POPUPS: { any } = {}
for _, pair in { { "Panels", PANELS }, { "Popups", POPUPS } } do
	local folder = script.Parent:FindFirstChild(pair[1])
	if folder then
		local kids = folder:GetChildren()
		table.sort(kids, function(a, b)
			return a.Name < b.Name
		end)
		for _, m in kids do
			if m:IsA("ModuleScript") then
				local mod = (require :: any)(m)
				if pair[1] == "Panels" then
					PANELS[mod.id] = mod
				else
					table.insert(POPUPS, mod)
				end
			end
		end
	end
end

local LINE = Ui.LINE
local REF_W, REF_H = 1280, 800

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

function Hud.start()
	local gui: ScreenGui = Ui.new("ScreenGui", {
		Name = "Cartopia",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	-- Everything sits in one frame laid out at the web's 1280x800 and scaled to fit the screen:
	-- phones see the same screen, smaller (never bigger than on the web).
	-- Every button on the screen presses, hovers and taps, as on the web (UIMotion).
	Motion.bindAll(gui)
	local root = Ui.new("Frame", { Name = "Root", BackgroundTransparency = 1, Size = UDim2.fromOffset(REF_W, REF_H), Parent = gui })
	local scale = Ui.new("UIScale", { Scale = 1, Parent = root })
	local left = Ui.new("Frame", { Name = "Left", Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(250, 120), BackgroundTransparency = 1, Parent = root })
	local function fit()
		-- The screen the GUI is drawn on, which can be smaller than the camera's view (safe
		-- areas, window edges): sized from the camera alone, wide menus ran off the right edge.
		local cam = workspace.CurrentCamera
		local view = gui.AbsoluteSize
		if (view.X < 2 or view.Y < 2) and cam then
			view = cam.ViewportSize
		end
		if view.X < 2 or view.Y < 2 then
			view = Vector2.new(REF_W, REF_H)
		end
		local s = math.clamp(math.min(view.X / REF_W, view.Y / REF_H), 0.55, 1)
		scale.Scale = s
		root.Size = UDim2.fromOffset(view.X / s, view.Y / s)
		-- Roblox's own buttons (menu, chat) sit in the top bar's left end: start below them there.
		local ok, inset = pcall(function()
			return GuiService.TopbarInset
		end)
		local top = if ok and inset then inset.Height else 0
		left.Position = UDim2.fromOffset(10, 10 + (if top > 0 then top / s - 4 else 0))
	end
	fit()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	end
	GuiService:GetPropertyChangedSignal("TopbarInset"):Connect(fit)

	-- Toasts, under the town name (the web's .toasts at top: 120px).
	local toasts = Ui.new("Frame", { Name = "Toasts", ZIndex = 30, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(700, 200), BackgroundTransparency = 1, Parent = root }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local toastN = 0
	local function toast(text: string)
		toastN += 1
		local t = Ui.toast(toasts, text, toastN)
		task.delay(3.5, function()
			t:Destroy()
		end)
	end

	-- One menu at a time. Closing drops the menu away (Motion.panelOut); opening another in its
	-- place swaps them at once.
	local open: Instance? = nil
	local current: string? = nil -- its name (the web's s.panel), for the tutorial
	local function close(instant: boolean?)
		current = nil
		if open then
			local o = open
			open = nil
			Motion.panelOut(o, instant)
		end
	end

	local openPanel: (string, any?) -> ()
	local ctx = {
		-- The town being visited (Popups/Visit sets it): { townName, ... }, or nil at home.
		visiting = nil :: any,
		gui = root,
		close = function()
			close()
		end,
		toast = toast,
		open = function(name: string, arg: any?)
			openPanel(name, arg)
		end,
		-- The HUD counter a collected reward flies into (set once the counters are made).
		flyTarget = (nil :: any) :: (string) -> GuiObject?,
		-- The menu open now, by the web's panel name (nil over the plain town).
		panel = function(): string?
			return if open and open.Parent then current else nil
		end,
	}

	-- ── Top left: the speedometer (Menu button) and the counters ──────────────────────────────
	local speedo = Ui.new("TextButton", { Name = "Speedo", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromOffset(88, 100), Parent = left })
	Ui.new("Frame", { Name = "Dial", Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(82, 82), BackgroundColor3 = Color3.fromHex("#1b1f24"), Parent = speedo }, { Ui.round(), Ui.stroke(3) })
	-- The arc: dots along it, green up to the needle.
	local dots: { { f: Frame, a: number } } = {}
	local N_DOTS = 34
	for i = 0, N_DOTS - 1 do
		local a = -210 + 240 * i / (N_DOTS - 1)
		local x = 44 + 34 * math.cos(math.rad(a))
		local y = 44 + 34 * math.sin(math.rad(a))
		local f = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = Color3.fromHex("#37474f"), BorderSizePixel = 0, Parent = speedo }, { Ui.round() })
		table.insert(dots, { f = f, a = a })
	end
	local needle = Ui.new("Frame", { Name = "Needle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(44, 44), Size = UDim2.fromOffset(56, 3), BackgroundTransparency = 1, Rotation = -210, Parent = speedo })
	Ui.new("Frame", { Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = Color3.fromHex("#ff1744"), BorderSizePixel = 0, Parent = needle }, { Ui.round() })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(44, 44), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.fromHex("#eceff1"), BorderSizePixel = 0, Parent = speedo }, { Ui.round() })
	local levelText = Ui.text({ Name = "Level", Text = "1", TextSize = 20, Position = UDim2.fromOffset(0, 59), Size = UDim2.fromOffset(88, 20), Parent = speedo })
	local xpBox = Ui.new("Frame", { Name = "Xp", Position = UDim2.fromOffset(6, 86), Size = UDim2.fromOffset(76, 15), BackgroundColor3 = Ui.WHITE, Parent = speedo }, {
		Ui.corner(5),
		Ui.stroke(2),
		Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]),
	})
	local xpText = Ui.text({ Text = "0 XP", TextSize = 12, Size = UDim2.fromScale(1, 1), Parent = xpBox })
	local _, menuFace = Ui.shadowed({ Name = "MenuBadge", Position = UDim2.fromOffset(82, -4), Size = UDim2.fromOffset(19, 19), Parent = speedo }, { radius = 10, stroke = 2.5, drop = 2, colors = "menu" })
	Icons.draw("menu", menuFace, 13, LINE, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	speedo.Activated:Connect(function()
		openPanel("account")
	end)

	local pills = Ui.new("Frame", { Name = "Pills", Position = UDim2.fromOffset(116, 4), Size = UDim2.fromOffset(150, 120), BackgroundTransparency = 1, Parent = left }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	-- A counter pill: icon, the number, and the green + (all of it opens "how to get more").
	local function counter(order: number, icon: string, onClick: () -> ()): TextLabel
		local shadow, face = Ui.pill({ Size = UDim2.fromOffset(115, 28), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = pills })
		local row = Ui.new("TextButton", {
			Name = "Row",
			Text = "",
			AutoButtonColor = false,
			ZIndex = 2,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(0, -3),
			Size = UDim2.fromOffset(0, 28),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = shadow,
		}, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 10) }),
		})
		local _ = face
		Icons.picture(icon, row, 24).LayoutOrder = 1
		local value = Ui.text({ Name = "Value", Text = "0", TextSize = 17, Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Shadow = 2, ShadowColor = Ui.BLACK, ShadowTransparency = 0.55, Parent = row })
		local plusSlot = Ui.new("Frame", { Size = UDim2.fromOffset(22, 20), BackgroundTransparency = 1, LayoutOrder = 3, Parent = row })
		local plus = Ui.new("Frame", { Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Ui.WHITE, Parent = plusSlot }, {
			Ui.corner(6),
			Ui.stroke(1.5, Color3.fromHex("#1d5a20"), 0.15),
			Ui.gradient(Ui.COLORS.plus[1], Ui.COLORS.plus[2]),
		})
		-- The web's inset highlight along the top (theme.css .plus box-shadow).
		Ui.new("Frame", { Position = UDim2.fromOffset(3, 1), Size = UDim2.new(1, -6, 0, 1.5), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.55, BorderSizePixel = 0, Parent = plus }, { Ui.round() })
		Icons.draw("plus", plus, 12, Ui.WHITE, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		row.Activated:Connect(onClick)
		return value
	end
	local coins = counter(1, "coin", function()
		openPanel("need", { res = "coins", missing = 0 })
	end)
	-- Gems open the Bank once it's unlocked (web Hud.tsx openGems), else how to earn them.
	local gems = counter(2, "bucks", function()
		if Bank.unlocked(store.useGame.getState()) then
			openPanel("bank")
		else
			openPanel("need", { res = "bucks", missing = 0 })
		end
	end)
	local parts = counter(3, "parts", function()
		openPanel("need", { res = "parts", missing = 0 })
	end)
	-- Where collected rewards fly to (Fly.from): the counters, and the XP box for XP.
	local flyTo: { [string]: GuiObject } = { coins = coins.Parent :: GuiObject, bucks = gems.Parent :: GuiObject, parts = parts.Parent :: GuiObject, xp = xpBox }
	ctx.flyTarget = function(res: string): GuiObject?
		return flyTo[res]
	end

	-- ── Top middle: town name, MY CARS, the goal tracker ──────────────────────────────────────
	local center = Ui.new("Frame", { Name = "Center", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(420, 120), BackgroundTransparency = 1, Parent = root }, {
		Ui.new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }),
	})
	local townName = Ui.text({ Name = "TownName", Text = "My Town", TextSize = 28, Size = UDim2.fromOffset(420, 34), Stroke = 1.5, Shadow = 4, LayoutOrder = 1, Parent = center })
	Ui.new("Frame", { Size = UDim2.fromOffset(1, 4), BackgroundTransparency = 1, LayoutOrder = 2, Parent = center })
	local carsShadow = Ui.pill({ Name = "MyCars", Size = UDim2.fromOffset(0, 29), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3, Parent = center })
	local carsRow = Ui.new("TextButton", { Name = "Row", Text = "", AutoButtonColor = false, ZIndex = 2, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, -3), Size = UDim2.fromOffset(0, 29), AutomaticSize = Enum.AutomaticSize.X, Parent = carsShadow }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
	})
	Icons.draw("car", carsRow, 18, Ui.WHITE, Color3.fromHex("#2a4370")).LayoutOrder = 1
	local carsText = Ui.text({ Text = "MY CARS: 0", TextSize = 16, Size = UDim2.fromOffset(0, 29), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Shadow = 2, ShadowColor = Ui.BLACK, ShadowTransparency = 0.55, Parent = carsRow })
	carsRow.Activated:Connect(function()
		openPanel("garage")
	end)
	Ui.new("Frame", { Size = UDim2.fromOffset(1, 6), BackgroundTransparency = 1, LayoutOrder = 4, Parent = center })
	local goalShadow, goalFace = Ui.shadowed({ Name = "GoalTracker", Size = UDim2.fromOffset(0, 25), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 5, Parent = center }, { radius = 14, stroke = 2.5, drop = 3, colors = "navy" })
	local goalRow = Ui.new("TextButton", { Name = "Row", Text = "", AutoButtonColor = false, ZIndex = 2, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, -3), Size = UDim2.fromOffset(0, 25), AutomaticSize = Enum.AutomaticSize.X, Parent = goalShadow }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8) }),
	})
	local gtIcon = Ui.new("Frame", { Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.85, LayoutOrder = 1, Parent = goalRow }, { Ui.round() })
	local gtEmoji = Ui.text({ Text = "", TextSize = 13, Size = UDim2.fromScale(1, 1), Parent = gtIcon })
	local gtText = Ui.text({ Text = "", TextSize = 13, Size = UDim2.fromOffset(0, 25), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Shadow = 1.5, ShadowColor = Ui.BLACK, ShadowTransparency = 0.55, Parent = goalRow })
	local gtBar = Ui.new("Frame", { Size = UDim2.fromOffset(44, 6), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.75, LayoutOrder = 3, Parent = goalRow }, { Ui.corner(3) })
	local gtFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromHex("#76ff03"), BorderSizePixel = 0, Parent = gtBar }, { Ui.corner(3) })
	-- Pulses amber while there's something to collect (the web's chest-glow).
	local gtGlow = Fly.glow(goalFace, 14)
	gtGlow.Visible = false
	-- Tapping it collects (opens Goals) when it's done, else takes you where it gets done.
	local tracked: any = nil
	goalRow.Activated:Connect(function()
		if tracked and tracked.have < tracked.target then
			tracked.go(ctx)
		else
			openPanel("goals")
		end
	end)

	-- ── Top right: fuel, trophies, sound ──────────────────────────────────────────────────────
	local right = Ui.new("Frame", { Name = "Right", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(260, 110), BackgroundTransparency = 1, Parent = root })
	local fuelButton = Ui.new("TextButton", { Name = "Fuel", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(200, 24), Parent = right })
	local fuelShadow, fuelBar = Ui.shadowed({ Position = UDim2.fromOffset(2.5, 2.5), Size = UDim2.fromOffset(165, 19), Parent = fuelButton }, { radius = 12, stroke = 2.5, drop = 0, color = Color3.fromHex("#1f3358") })
	fuelShadow.Position = UDim2.fromOffset(2.5, 5.5)
	fuelBar.Position = UDim2.fromOffset(0, -3)
	fuelBar.ClipsDescendants = true
	local fuelFill = Ui.new("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = fuelBar }, {
		Ui.gradient("#ffe066", "#ffb703", 0.5),
		Ui.corner(10),
	})
	local fuelText = Ui.text({ Text = "0/0", TextSize = 15, Size = UDim2.fromScale(1, 1), ZIndex = 2, Shadow = 2, Parent = fuelBar })
	Icons.draw("fuel", fuelButton, 24, nil, nil, UDim2.new(1, 0, 0, 0), Vector2.new(1, 0))
	fuelButton.Activated:Connect(function()
		openPanel("need", { res = "fuel", missing = 0 })
	end)
	local fuelSub = Ui.text({ Name = "FuelSub", Text = "", TextSize = 13, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 28), Size = UDim2.fromOffset(260, 16), TextXAlignment = Enum.TextXAlignment.Right, Shadow = 2, Parent = right })
	local rightRow = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 50), Size = UDim2.fromOffset(300, 43), BackgroundTransparency = 1, Parent = right }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local trophyShadow = Ui.pill({ Name = "Trophies", Size = UDim2.fromOffset(0, 23), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = rightRow })
	local trophyRow = Ui.new("TextButton", { Name = "Row", Text = "", AutoButtonColor = false, ZIndex = 2, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, -3), Size = UDim2.fromOffset(0, 23), AutomaticSize = Enum.AutomaticSize.X, Parent = trophyShadow }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 10) }),
	})
	Icons.draw("trophy", trophyRow, 16, Ui.WHITE).LayoutOrder = 1
	local trophyText = Ui.text({ Text = "0", TextSize = 17, Size = UDim2.fromOffset(0, 23), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Shadow = 2, ShadowColor = Ui.BLACK, ShadowTransparency = 0.55, Parent = trophyRow })
	trophyRow.Activated:Connect(function()
		openPanel("friends", "leaders")
	end)
	-- Sound on/off: mutes the game's sounds (they play through the Cartopia sound group).
	local soundGroup = SoundService:FindFirstChild("Cartopia") or Ui.new("SoundGroup", { Name = "Cartopia", Volume = 1, Parent = SoundService })
	local soundSlot = Ui.new("Frame", { Size = UDim2.fromOffset(40, 43), BackgroundTransparency = 1, LayoutOrder = 10, Parent = rightRow })
	local _, soundFace = Ui.button({ Name = "Sound", Position = UDim2.fromOffset(2.5, 5.5), Size = UDim2.fromOffset(35, 35), Parent = soundSlot }, "white", nil, { radius = 12, stroke = 2.5, drop = 3, split = 0.5, flat = true })
	local soundOn = Icons.draw("soundOn", soundFace, 21, Ui.BLUE, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	local soundOff = Icons.draw("soundOff", soundFace, 21, Ui.BLUE, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	soundOff.Visible = false
	soundFace.Activated:Connect(function()
		local muted = not soundOff.Visible
		soundOff.Visible = muted
		soundOn.Visible = not muted
		;(soundGroup :: SoundGroup).Volume = if muted then 0 else 1
	end)

	-- Menus with a button of their own in this row (client/Panels with `hudButton`, by `hudOrder`:
	-- the Star Pass and Daily Deals). Each returns the refresh to run with the town's state.
	local panelButtons: { (any) -> () } = {}
	for _, mod in PANELS do
		if mod.hudButton then
			table.insert(panelButtons, mod.hudButton(rightRow, ctx))
		end
	end

	-- ── Bottom: SHOP, CARS, SOCIAL, CHAT, EDIT and RACE; Goals and Collect All on the right ───
	local bar = Ui.new("Frame", { Name = "BottomBar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.fromOffset(5 * 66 + 4 * 8, 80), BackgroundTransparency = 1, Parent = root }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function iconButton(order: number, colors: string, icon: string, label: string, onClick: () -> ()): Frame
		local holder = Ui.new("Frame", { Name = label, Size = UDim2.fromOffset(66, 80), BackgroundTransparency = 1, LayoutOrder = order, Parent = bar })
		local c = Ui.colors(colors)
		local _, face = Ui.button({ Position = UDim2.fromOffset(9, 15), Size = UDim2.fromOffset(48, 48), Parent = holder }, colors, onClick, { radius = 16, stroke = 3, drop = 4, dark = 0.35, gloss = 0.6, shade = 0.82 })
		local mid = Color3.fromHex(c[1]):Lerp(Color3.fromHex(c[2]), 0.5)
		Icons.draw(icon, face, 31, Ui.WHITE, mid, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		Ui.text({ Text = label, TextSize = 14, Position = UDim2.fromOffset(-10, 64), Size = UDim2.new(1, 20, 0, 16), Shadow = 2, Stroke = 0.6, Parent = holder })
		-- Where the tutorial's hand points (client/Popups/Tutorial): "shop", "cars", "edit".
		face:SetAttribute("Tut", string.lower(label))
		return holder
	end
	local shopButton = iconButton(1, "shop", "shop", "SHOP", function()
		openPanel("shop")
	end)
	local carsButton = iconButton(2, "showroom", "car", "CARS", function()
		openPanel("cars")
	end)
	-- Friends, visiting towns and joining friends (Panels/Friends).
	local socialButton = iconButton(3, "friends", "friends", "SOCIAL", function()
		openPanel("friends")
	end)
	-- Roblox's own chat (TextChatService), only for players Roblox lets chat.
	local chatButton = iconButton(4, "chat", "chat", "CHAT", function()
		close()
		pcall(function()
			StarterGui:SetCore("ChatActive", not StarterGui:GetCore("ChatActive"))
		end)
	end)
	local editButton = iconButton(5, "edit", "cone", "EDIT", function()
		close()
		TownCamera.setWalking(false)
		-- During the tutorial edit mode opens on Move (roads and the rest come after), as the web.
		local s = store.useGame.getState()
		Placement.edit(root, ctx, if (s.tutorial or 99) >= 99 then nil else "move")
	end)
	local race = Ui.new("Frame", { Name = "Race", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), Size = UDim2.fromOffset(84, 66 + 5), BackgroundTransparency = 1, Parent = root })
	local _, raceFace = Ui.button({ Position = UDim2.fromOffset(3, 8), Size = UDim2.fromOffset(84, 61), Parent = race }, "green", function()
		openPanel("race")
	end, { radius = 18, stroke = 3, drop = 5, dark = 0.35, gloss = 0.55, shade = 0.82 })
	raceFace:SetAttribute("Tut", "race")
	Icons.draw("flag", raceFace, 30, Ui.WHITE, Color3.fromHex("#5cce47"), UDim2.new(0.5, 0, 0, 6), Vector2.new(0.5, 0))
	Ui.text({ Text = "RACE", TextSize = 20, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 22), Shadow = 2, Stroke = 0.6, Parent = raceFace })

	-- Drive: hops in your race car to drive round the shared world (server/Drive), with the camera
	-- behind it; My Town always brings you back to the view over your own town, wherever you were.
	local walk = Ui.new("Frame", { Name = "Walk", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -26, 1, -250), Size = UDim2.fromOffset(60, 78), BackgroundTransparency = 1, Parent = root })
	local walkLabel: TextLabel
	local walkIcon: GuiObject? = nil
	local _, walkFace = Ui.button({ Name = "WalkButton", Position = UDim2.fromOffset(2.5, 5.5), Size = UDim2.fromOffset(55, 55), Parent = walk }, "white", function()
		TownCamera.setWalking(not TownCamera.isWalking())
	end, { radius = 16, stroke = 2.5, drop = 3, split = 0.5, flat = true })
	-- The car (or the town), centred in the tile: a baked picture, as emoji sit high and to one side.
	local function setWalkIcon(kind: string)
		if walkIcon then
			walkIcon:Destroy()
		end
		walkIcon = Icons.picture(kind, walkFace, 38)
		walkIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		walkIcon.Position = UDim2.fromScale(0.5, 0.5)
	end
	setWalkIcon("car")
	walkLabel = Ui.text({ Text = "DRIVE", TextSize = 13, Position = UDim2.fromOffset(-10, 62), Size = UDim2.new(1, 20, 0, 16), Shadow = 2, Stroke = 0.6, Parent = walk })
	TownCamera.onWalking(function(on: boolean)
		setWalkIcon(if on then "town" else "car")
		walkLabel.Text = if on then "MY TOWN" else "DRIVE"
		-- The server puts them in their car, or takes them out and back home.
		if not on or Players.LocalPlayer:GetAttribute("Driving") ~= true then
			task.spawn(Remote.social, if on then "drive" else "home", nil, true)
		end
	end)
	-- The server can start a drive too (Visit in the Social menu drives you over). Getting out of
	-- the car (client/GetIn) leaves them on foot, still out in the world; Town goes back.
	Players.LocalPlayer:GetAttributeChangedSignal("Driving"):Connect(function()
		local driving = Players.LocalPlayer:GetAttribute("Driving") == true
		if driving and not TownCamera.isWalking() then
			TownCamera.setWalking(true)
		end
	end)
	-- On phones Roblox's jump button sits in the bottom right corner, under Race and the buttons
	-- above it: keep it just left of Race instead.
	local function placeJump(button: GuiObject)
		local s = scale.Scale
		local want = UDim2.new(1, -math.floor((10 + 87 + 14) * s), 1, -math.floor(10 * s))
		if button.AnchorPoint ~= Vector2.new(1, 1) or button.Position ~= want then
			button.AnchorPoint = Vector2.new(1, 1)
			button.Position = want
		end
	end
	local function watchJump(touch: Instance)
		task.spawn(function()
			local frame = touch:WaitForChild("TouchControlFrame", 30)
			local button = frame and frame:WaitForChild("JumpButton", 30)
			if button and button:IsA("GuiObject") then
				placeJump(button)
				button:GetPropertyChangedSignal("Position"):Connect(function()
					placeJump(button)
				end)
				scale:GetPropertyChangedSignal("Scale"):Connect(function()
					placeJump(button)
				end)
			end
		end)
	end
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local touch = playerGui:FindFirstChild("TouchGui")
	if touch then
		watchJump(touch)
	end
	playerGui.ChildAdded:Connect(function(c)
		if c.Name == "TouchGui" then
			watchJump(c)
		end
	end)

	local dock = Ui.new("Frame", { Name = "Dock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -26, 1, -104), Size = UDim2.fromOffset(60, 136), BackgroundTransparency = 1, Parent = root })
	local _, goalsFace = Ui.button({ Name = "Goals", Position = UDim2.fromOffset(2.5, 2.5 + 3), Size = UDim2.fromOffset(55, 55), Parent = dock }, "white", function()
		openPanel("goals")
	end, { radius = 16, stroke = 2.5, drop = 3, split = 0.5, flat = true })
	Icons.draw("goals", goalsFace, 34, Ui.BLUE, Color3.fromHex("#f3f7fc"), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	local goalBadge = Ui.new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 8, 0, -8), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromHex("#ff5252"), Visible = false, ZIndex = 3, Parent = goalsFace }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
	local goalBadgeText = Ui.text({ Text = "", TextSize = 12, Size = UDim2.fromScale(1, 1), Parent = goalBadge })
	local collectShadow, collect = Ui.shadowed({ Name = "CollectAll", Position = UDim2.fromOffset(3, 76 + 4), Size = UDim2.fromOffset(54, 54), Parent = dock }, { radius = 27, stroke = 3, drop = 4, dark = 0.3, class = "TextButton", color = Color3.fromHex("#ffca28") })
	local _ = collectShadow
	local inner = Ui.new("Frame", { Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundColor3 = Ui.WHITE, ZIndex = 0, Parent = collect }, {
		Ui.round(),
		Ui.new("UIGradient", { Rotation = 70, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromHex("#fff3b0")), ColorSequenceKeypoint.new(0.6, Color3.fromHex("#ffc21a")), ColorSequenceKeypoint.new(1, Color3.fromHex("#f39b00")) }) }),
	})
	local bolt = Icons.draw("bolt", collect, 30, Color3.fromHex("#7a4a00"), nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	local readyBadge = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 7, 0, -7), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.fromHex("#e53935"), Visible = false, ZIndex = 3, Parent = collect }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
	local readyText = Ui.text({ Text = "", TextSize = 12, Size = UDim2.fromScale(1, 1), Parent = readyBadge })
	local coolChip = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -5), Size = UDim2.fromOffset(34, 16), BackgroundColor3 = Color3.fromHex("#263238"), Visible = false, ZIndex = 3, Parent = collect }, { Ui.corner(8) })
	local coolText = Ui.text({ Text = "", TextSize = 12, Size = UDim2.fromScale(1, 1), Parent = coolChip })
	-- The server keeps Collect All to once a minute; the ring greys while it recharges.
	local lastCollect = -math.huge
	collect.Activated:Connect(function()
		if now() - lastCollect < store.COLLECT_ALL_MS then
			toast(`Ready again in {math.ceil((store.COLLECT_ALL_MS - (now() - lastCollect)) / 1000)}s`)
			return
		end
		local ok = Remote.act("collectAll")
		if ok then
			lastCollect = now()
		end
	end)

	-- ── Menus ─────────────────────────────────────────────────────────────────────────────────
	openPanel = function(panel: string, arg: any?)
		-- Menus opened from the edit bar (Shop, Inventory, a building's Upgrade) keep edit mode
		-- under them, as on the web; the rest go back to the town first.
		if panel ~= "shop" and panel ~= "inventory" and panel ~= "upgrade" and panel ~= "need" then
			Placement.cancel()
		end
		Motion.swapping = open ~= nil
		close(true)
		current = panel
		if panel == "edit" then
			Placement.edit(root, ctx, arg)
		elseif panel == "inventory" then
			open = Placement.inventory(ctx)
		elseif panel == "shop" then
			open = Shop.open(ctx, arg)
		elseif panel == "cars" or panel == "garage" or panel == "showroom" or panel == "crates" or panel == "book" then
			open = Cars.open(ctx, if panel == "cars" then arg elseif panel == "garage" then (arg or "garage") elseif panel == "showroom" then "shop" else panel)
		elseif panel == "upgrade" then
			open = Upgrade.open(ctx, arg)
		elseif panel == "goals" then
			open = Goals.open(ctx)
		elseif panel == "rescue" then
			open = Rescue.open(ctx)
		elseif panel == "account" or panel == "menu" then
			open = Menu.open(ctx)
		elseif panel == "race" then
			open = RaceMenu.open(ctx, arg)
		elseif panel == "need" then
			open = Menu.need(ctx, arg or store.useGame.getState().need)
		elseif PANELS[panel] then
			open = PANELS[panel].open(ctx, arg)
		else
			toast("That screen is coming to Roblox soon")
		end
		Motion.swapping = false
	end

	-- ── Refresh ───────────────────────────────────────────────────────────────────────────────
	local lastXp, lastLevel = -1, -1
	local lastCollectState = ""
	local function refresh()
		local s = store.useGame.getState()
		if s.level == nil then
			return
		end
		if s.xp ~= lastXp or s.level ~= lastLevel then
			lastXp, lastLevel = s.xp, s.level
			local need = data.xpToNext(s.level)
			local pct = math.min(1, s.xp / need)
			local angle = -210 + pct * 240
			needle.Rotation = angle
			for _, d in dots do
				d.f.BackgroundColor3 = if pct > 0.01 and d.a <= angle then Color3.fromHex("#76ff03") else Color3.fromHex("#37474f")
			end
			Ui.setText(levelText, tostring(s.level))
			Ui.setText(xpText, `{Ui.commas(s.xp)} XP`)
		end
		Ui.setText(coins, Ui.compact(s.coins))
		Ui.setText(gems, Ui.compact(s.bucks))
		Ui.setText(parts, Ui.compact(s.parts))
		local visiting = ctx.visiting
		Ui.setText(townName, if visiting then visiting.townName else s.townName)
		carsShadow.Visible = not visiting
		Ui.setText(carsText, `MY CARS: {#s.cars}`)
		local g = Goals.tracked(s)
		tracked = g
		-- Hidden while visiting, editing, or while the tutorial runs (web Goals.tsx GoalTracker).
		local inTutorial = (s.tutorial or 99) < 99
		goalShadow.Visible = g ~= nil and not Placement.active() and not s.visiting and not inTutorial
		-- New players get the buttons and counters one at a time (shared/Tutorial UNLOCKS, the
		-- web's game/unlocks.ts): coins and the level first, the rest as each is needed.
		local function on(id: string): boolean
			return Tutorial.unlocked(s, id)
		end
		;(gems.Parent :: any).Parent.Visible = on("gems")
		;(parts.Parent :: any).Parent.Visible = on("parts")
		fuelButton.Visible = on("fuel")
		fuelSub.Visible = on("fuel")
		carsShadow.Visible = not visiting and on("cars")
		trophyShadow.Visible = on("trophies")
		shopButton.Visible = on("shop")
		carsButton.Visible = on("cars")
		editButton.Visible = on("edit")
		if g then
			local have = math.min(g.target, g.have)
			local done = have >= g.target
			gtGlow.Visible = done
			Ui.setText(gtEmoji, if done then "✔" else g.icon)
			Ui.setText(gtText, g.text)
			gtFill.Size = UDim2.fromScale(have / math.max(1, g.target), 1)
			local grad = goalFace:FindFirstChildOfClass("UIGradient")
			if grad then
				local c = if done then { "#43a047", "#2e7d32" } else Ui.COLORS.navy
				grad.Color = Ui.seq(c[1], c[2])
			end
		end
		local cap = store.fuelCap(s)
		fuelFill.Size = UDim2.fromScale(math.clamp(s.fuel / math.max(cap, 1), 0, 1), 1)
		fuelFill.Visible = s.fuel > 0
		Ui.setText(fuelText, `{Ui.compact(s.fuel)}/{Ui.compact(cap)}`)
		if s.fuel >= cap then
			Ui.setText(fuelSub, `Fuel full · {data.fuelPerMin(s.level)}/min`)
		else
			local wait = math.max(0, data.fuelRegenSeconds(s.level) - math.floor((now() - s.fuelUpdatedAt) / 1000))
			Ui.setText(fuelSub, `+1 fuel in {math.ceil(wait)}s · {data.fuelPerMin(s.level)}/min`)
		end
		Ui.setText(trophyText, Ui.compact(s.trophies or 0))
		for _, f in panelButtons do
			f(s)
		end
		-- The Menu's Sound switch mutes the same group; keep the button's icon in step.
		local muted = (soundGroup :: SoundGroup).Volume == 0
		if soundOff.Visible ~= muted then
			soundOff.Visible = muted
			soundOn.Visible = not muted
		end
		local claim = store.claimable(s)
		goalBadge.Visible = claim > 0
		Ui.setText(goalBadgeText, tostring(claim))
		-- Collect All: the ring and bolt grey while it recharges, else a count of jobs ready.
		local left = store.COLLECT_ALL_MS - (now() - lastCollect)
		local ready = Jobs.ready()
		local state = if left > 0 then `cool{math.ceil(left / 1000)}` else `ready{ready}`
		if state ~= lastCollectState then
			lastCollectState = state
			local cooling = left > 0
			collect.BackgroundColor3 = if cooling then Color3.fromHex("#90a4ae") else Color3.fromHex("#ffca28")
			local ig = inner:FindFirstChildOfClass("UIGradient")
			if ig then
				ig.Color = if cooling
					then Ui.seq("#eceff1", "#b0bec5")
					else ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromHex("#fff3b0")), ColorSequenceKeypoint.new(0.6, Color3.fromHex("#ffc21a")), ColorSequenceKeypoint.new(1, Color3.fromHex("#f39b00")) })
			end
			for _, p in bolt:GetDescendants() do
				if p:IsA("Frame") then
					p.BackgroundTransparency = if cooling then 0.55 else 0
				end
			end
			coolChip.Visible = cooling
			Ui.setText(coolText, `{math.ceil(left / 1000)}s`)
			readyBadge.Visible = not cooling and ready > 0
			Ui.setText(readyText, tostring(ready))
		end
		local editing = Placement.active()
		-- Before they've picked a plot (Popups/Claim) there's no town to play yet.
		local picking = Players.LocalPlayer:GetAttribute("NeedsPlot") == true
		bar.Visible = not editing and not visiting and not picking
		race.Visible = not editing and not visiting and not picking and on("race")
		dock.Visible = not editing and not visiting and not picking and on("gems")
		walk.Visible = not editing and not picking and on("social")
		socialButton.Visible = on("social")
		chatButton.Visible = on("social") and Players.LocalPlayer:GetAttribute("CanChat") == true
	end

	Remote.changed:Connect(function(snap)
		refresh()
		for _, text in snap.toasts do
			toast(text)
		end
		if snap.need and ((snap.need.missing or 0) > 0 or snap.need.res == "level") then
			openPanel("need", snap.need)
		end
		if snap.panel and snap.panel ~= "need" then
			openPanel(snap.panel, snap.upgrading)
		end
	end)
	Remote.failed:Connect(toast)
	Placement.onChange(function()
		refresh()
		Jobs.refresh()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			refresh()
		end
	end)
	if Remote.last then
		refresh()
	end
	Jobs.start(gui)
	for _, p in POPUPS do
		task.spawn(p.start, ctx)
	end
	return { gui = gui, root = root, openPanel = openPanel, toast = toast, ctx = ctx }
end

return Hud
