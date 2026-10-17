--!strict
-- The heads-up display, laid out like the web game's Hud (ui/Hud.tsx): level gauge and coin, gem
-- and parts pills top left, the town name in the middle, fuel top right, and the big buttons
-- (Shop, Showroom, Garage, Build) bottom right. Also shows toasts, "you need more" notes, and the
-- popups the server opens (Showroom, Garage, a building's upgrades).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Shop = require(script.Parent.Shop)
local Showroom = require(script.Parent.Showroom)
local Placement = require(script.Parent.Placement)
local Jobs = require(script.Parent.Jobs)
local Thumb = require(script.Parent.Thumb)

local Hud = {}

local RES_NAMES = { coins = "coins", bucks = "gems", parts = "parts", fuel = "fuel", level = "level" }

function Hud.start()
	local gui: ScreenGui = Ui.new("ScreenGui", {
		Name = "Cartopia",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})

	-- Top left: level gauge and pills.
	local left = Ui.new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(280, 130), BackgroundTransparency = 1, Parent = gui })
	local gauge = Ui.new("Frame", { Size = UDim2.fromOffset(88, 88), BackgroundColor3 = Color3.fromHex("#1b1f24"), Parent = left }, { Ui.corner(44), Ui.stroke(3, Color3.fromHex("#cfd8dc")) })
	local levelText = Ui.label({ Text = "1", TextSize = 34, Size = UDim2.new(1, 0, 1, -10), Parent = gauge })
	local xpBack = Ui.new("Frame", { Position = UDim2.new(0, -4, 1, -14), Size = UDim2.new(1, 8, 0, 22), BackgroundColor3 = Color3.new(1, 1, 1), Parent = gauge }, { Ui.corner(11), Ui.stroke(2.5), Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]) })
	local xpFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromHex("#76ff03"), BorderSizePixel = 0, Parent = xpBack }, { Ui.corner(11) })
	local xpText = Ui.label({ Text = "0 XP", TextSize = 13, Size = UDim2.fromScale(1, 1), Parent = xpBack })
	local pills = Ui.new("Frame", { Position = UDim2.fromOffset(98, 0), Size = UDim2.fromOffset(160, 120), BackgroundTransparency = 1, Parent = left }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local coins = Ui.pill(pills, "🪙", 1)
	local gems = Ui.pill(pills, "💎", 2)
	local parts = Ui.pill(pills, "⚙️", 3)

	-- Top middle: town name and car count.
	local townName = Ui.label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(400, 44), TextSize = 36, Text = "My Town", Parent = gui })
	local myCars = Ui.label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(160, 30), TextSize = 18, Text = "🚗 MY CARS: 0", BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = gui })
	Ui.corner(15).Parent = myCars
	Ui.stroke(2.5).Parent = myCars
	Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]).Parent = myCars

	-- Top right: fuel bar and refill timer.
	local fuelBack = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, 16), Size = UDim2.fromOffset(200, 30), BackgroundColor3 = Color3.fromHex("#1f3358"), Parent = gui }, { Ui.corner(15), Ui.stroke(2.5) })
	local fuelFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = fuelBack }, { Ui.corner(15), Ui.gradient("#ffe066", "#ffb703") })
	local fuelText = Ui.label({ Text = "0/0", TextSize = 18, Size = UDim2.fromScale(1, 1), Parent = fuelBack })
	Ui.label({ Text = "⛽", TextSize = 30, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 12), Size = UDim2.fromOffset(40, 36), NoStroke = true, Parent = gui })
	local fuelSub = Ui.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -60, 0, 50), Size = UDim2.fromOffset(240, 20), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = gui })

	-- Toasts, top centre under the town name.
	local toasts = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(520, 200), BackgroundTransparency = 1, Parent = gui }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local toastN = 0
	local function toast(text: string)
		toastN += 1
		local t = Ui.label({
			Text = text,
			TextSize = 18,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromOffset(500, 36),
			LayoutOrder = toastN,
			BackgroundTransparency = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = toasts,
		})
		Ui.corner(14).Parent = t
		Ui.stroke(2.5).Parent = t
		Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]).Parent = t
		Ui.new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = t })
		task.delay(3.5, function()
			t:Destroy()
		end)
	end

	-- One popup at a time.
	local open: Frame? = nil
	local function close()
		if open then
			open:Destroy()
			open = nil
		end
	end

	local function garage()
		close()
		local s = store.useGame.getState()
		local frame, body = Ui.sheet(gui, "My Garage", "garage", UDim2.new(0.8, 0, 0.75, 0), close)
		local grid = Ui.new("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = body }, {
			Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(180, 150), CellPadding = UDim2.fromOffset(10, 10) }),
		})
		for _, car in s.cars do
			local def = data.carDef(car.model)
			local card = Ui.new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Parent = grid }, { Ui.corner(14), Ui.stroke(2.5) })
			local pic = Thumb.new("Cars", car.model, UDim2.new(1, -10, 0, 100), Color3.fromHex(car.color))
			pic.Position = UDim2.fromOffset(5, 4)
			pic.Parent = card
			Ui.new("TextLabel", { Text = def.name, Font = Ui.FONT, TextSize = 15, TextColor3 = Ui.INK, TextWrapped = true, BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 104), Size = UDim2.new(1, -12, 0, 40), Parent = card })
		end
		open = frame
	end

	local function upgrade(uid: string?)
		close()
		local s = store.useGame.getState()
		local b
		for _, o in s.buildings do
			if o.uid == uid then
				b = o
			end
		end
		if not b then
			return
		end
		local def = data.buildingDef(b.def)
		local lvl = data.buildingLevel(b)
		local frame, body = Ui.sheet(gui, def.name, "edit", UDim2.fromOffset(460, 420), close)
		local pic = Thumb.new("Buildings", def.id, UDim2.new(1, 0, 0, 200), nil)
		pic.Parent = body
		Ui.new("TextLabel", { Text = `Level {lvl}`, Font = Ui.FONT, TextSize = 22, TextColor3 = Ui.INK, BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 206), Size = UDim2.new(1, 0, 0, 30), Parent = body })
		if data.upgradable(def) and lvl < data.maxLevel(def) then
			local cost = data.buildingUpgradeCost(def, lvl)
			local label = `⬆ Level {lvl + 1}   🪙 {Ui.compact(cost.coins)}` .. (if cost.parts > 0 then `  ⚙ {cost.parts}` else "")
			Ui.button({ Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 1, -60), TextSize = 22, Parent = body }, "green", label, function()
				Remote.act("upgradeBuilding", b.uid)
				close()
			end)
		else
			Ui.new("TextLabel", { Text = "Top level", Font = Ui.FONT, TextSize = 20, TextColor3 = Color3.fromHex("#607d8b"), BackgroundTransparency = 1, Position = UDim2.new(0, 0, 1, -50), Size = UDim2.new(1, 0, 0, 40), Parent = body })
		end
		open = frame
	end

	local function openPanel(panel: string, upgrading: string?)
		Placement.cancel()
		if panel == "shop" then
			close()
			open = Shop.open(gui, close, toast)
		elseif panel == "showroom" then
			close()
			open = Showroom.open(gui, close, toast)
		elseif panel == "garage" then
			garage()
		elseif panel == "upgrade" then
			upgrade(upgrading)
		else
			toast("That screen is coming to Roblox soon")
		end
	end

	-- Bottom right: the big buttons, and Collect All when jobs are ready.
	local actions = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(4 * 92, 96), BackgroundTransparency = 1, Parent = gui }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function bigButton(order: number, colors: string, icon: string, text: string, fn: () -> ())
		local holder = Ui.new("Frame", { Size = UDim2.fromOffset(80, 96), BackgroundTransparency = 1, LayoutOrder = order, Parent = actions })
		Ui.button({ Size = UDim2.fromOffset(76, 70), Position = UDim2.fromOffset(2, 0), TextSize = 34, Parent = holder }, colors, icon, fn)
		Ui.label({ Text = text, TextSize = 16, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 72), Parent = holder })
	end
	bigButton(1, "edit", "🛠", "BUILD", function()
		close()
		Placement.road(gui)
	end)
	bigButton(2, "garage", "🚗", "GARAGE", function()
		openPanel("garage")
	end)
	bigButton(3, "showroom", "🏎", "SHOWROOM", function()
		openPanel("showroom")
	end)
	bigButton(4, "shop", "🛒", "SHOP", function()
		openPanel("shop")
	end)
	local collect = Ui.button({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -124), Size = UDim2.fromOffset(200, 50), Visible = false, TextSize = 20, Parent = gui }, "edit", "🪙 Collect all", function()
		Remote.act("collectAll")
	end)

	local function refresh()
		local s = store.useGame.getState()
		if s.level == nil then
			return
		end
		levelText.Text = tostring(s.level)
		local need = data.xpToNext(s.level)
		xpFill.Size = UDim2.fromScale(math.clamp(s.xp / need, 0, 1), 1)
		xpText.Text = `{Ui.commas(s.xp)} XP`
		coins.Text = Ui.compact(s.coins)
		gems.Text = Ui.compact(s.bucks)
		parts.Text = Ui.compact(s.parts)
		townName.Text = s.townName
		myCars.Text = `🚗 MY CARS: {#s.cars}`
		local cap = store.fuelCap(s)
		fuelFill.Size = UDim2.fromScale(math.clamp(s.fuel / math.max(cap, 1), 0, 1), 1)
		fuelText.Text = `{Ui.compact(s.fuel)}/{Ui.compact(cap)}`
		if s.fuel >= cap then
			fuelSub.Text = `Fuel full · {data.fuelPerMin(s.level)}/min`
		else
			local wait = math.max(0, data.fuelRegenSeconds(s.level) - math.floor((workspace:GetServerTimeNow() * 1000 - s.fuelUpdatedAt) / 1000))
			fuelSub.Text = `+1 fuel in {math.ceil(wait)}s · {data.fuelPerMin(s.level)}/min`
		end
		collect.Visible = Jobs.ready() >= 2 and not Placement.active()
		actions.Visible = not Placement.active()
	end

	Remote.changed:Connect(function(snap)
		refresh()
		for _, text in snap.toasts do
			toast(text)
		end
		if snap.need then
			local n = snap.need
			if n.res == "level" then
				toast(`Reach level {n.missing} for {n.what or "that"}`)
			elseif (n.missing or 0) > 0 then
				toast(`You need {Ui.commas(n.missing)} more {RES_NAMES[n.res] or n.res}` .. (if n.what then ` for {n.what}` else ""))
			end
		end
		if snap.panel and snap.panel ~= "need" then
			openPanel(snap.panel, snap.upgrading)
		end
	end)
	Placement.onChange(refresh)
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
	return { gui = gui, openPanel = openPanel, toast = toast }
end

return Hud
