--!strict
-- The Shop, as the web game's ShopPanel (ui/Menus.tsx): tabs of buildings, each card showing the
-- building, its price and what one job pays. Picking one starts placing it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)
local Placement = require(script.Parent.Placement)

local Shop = {}

-- Tabs and what goes in each, as SHOP_GROUPS in ui/Menus.tsx.
local CAR_CARE = { carwash = true, bodyshop = true }
local TABS: { { id: string, label: string, filter: (any) -> boolean } } = {
	{ id = "cars", label = "🔧 Car shops", filter = function(b) return b.id == "rescue" or b.kind == "parts" or CAR_CARE[b.id] == true end },
	{ id = "business", label = "🍕 Businesses", filter = function(b) return b.kind == "business" and b.id ~= "rescue" and b.id ~= "crew" and not b.service and not b.rec and not b.event and not CAR_CARE[b.id] end },
	{ id = "homes", label = "🏠 Homes", filter = function(b) return b.kind == "house" end },
	{ id = "services", label = "⛽ Services", filter = function(b) return b.kind == "gas" or b.id == "crew" or b.service == true end },
	{ id = "rec", label = "🎡 Recreation", filter = function(b) return (b.kind == "decor" or b.rec == true) and not b.event end },
}
local lastTab = "cars"

local function featureRank(b: any): number
	if b.id == "rescue" then
		return 2
	end
	return if data.FEATURES[b.id] then 1 else 0
end

function Shop.open(gui: ScreenGui, close: () -> (), toast: (string) -> ())
	local s = store.useGame.getState()
	local frame, body = Ui.sheet(gui, "Shop", "shop", UDim2.new(0.9, 0, 0.82, 0), close)
	local tabs = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }),
	})
	local grid = Ui.new("ScrollingFrame", {
		Position = UDim2.fromOffset(0, 50),
		Size = UDim2.new(1, 0, 1, -50),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(170, 214), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }) })

	local gate = store.gateLevel(s)
	local function show(tabId: string)
		lastTab = tabId
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		for _, t in tabs:GetChildren() do
			if t:IsA("TextButton") then
				local g = t:FindFirstChildOfClass("UIGradient")
				local c = if t.Name == tabId then Ui.COLORS.garage else Ui.COLORS.white
				if g then
					g.Color = ColorSequence.new(Color3.fromHex(c[1]), Color3.fromHex(c[2]))
				end
				t.TextColor3 = if t.Name == tabId then Color3.new(1, 1, 1) else Ui.LINE
			end
		end
		local tab
		for _, t in TABS do
			if t.id == tabId then
				tab = t
			end
		end
		local rows = {}
		for _, b in data.BUILDINGS do
			if b.unlockLevel < 99 and tab.filter(b) then
				local sale = store.buildPrice(s, b.id)
				local locked = gate < b.unlockLevel
				local broke = s.coins < sale.coins or s.bucks < sale.bucks
				local owned = false
				if b.unique then
					for _, o in s.buildings do
						if o.def == b.id then
							owned = true
						end
					end
				end
				local rank = if owned then 3 elseif locked then 2 elseif broke then 1 else 0
				table.insert(rows, { b = b, sale = sale, locked = locked, broke = broke, owned = owned, rank = rank })
			end
		end
		table.sort(rows, function(x, y)
			local fx = if x.rank < 2 then featureRank(x.b) else 0
			local fy = if y.rank < 2 then featureRank(y.b) else 0
			if fx ~= fy then
				return fx > fy
			end
			if x.rank ~= y.rank then
				return x.rank < y.rank
			end
			if x.b.unlockLevel ~= y.b.unlockLevel then
				return x.b.unlockLevel < y.b.unlockLevel
			end
			return x.b.price < y.b.price
		end)
		for i, r in rows do
			local b = r.b
			local card = Ui.new("TextButton", {
				Text = "",
				LayoutOrder = i,
				AutoButtonColor = not r.owned,
				BackgroundColor3 = if r.locked then Color3.fromHex("#cfd8dc") else Color3.new(1, 1, 1),
				Parent = grid,
			}, { Ui.corner(14), Ui.stroke(2.5) })
			local pic = Thumb.new("Buildings", b.id, UDim2.new(1, -12, 0, 118), nil)
			pic.Position = UDim2.fromOffset(6, 6)
			pic.Parent = card
			if r.locked then
				pic.ImageTransparency = 0.5
				Ui.label({ Text = `🔒 Lv {b.unlockLevel}`, TextSize = 22, Size = UDim2.new(1, 0, 0, 118), Parent = card })
			end
			Ui.new("TextLabel", {
				Text = b.name,
				Font = Ui.FONT,
				TextSize = 16,
				TextColor3 = Ui.INK,
				TextWrapped = true,
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(6, 124),
				Size = UDim2.new(1, -12, 0, 36),
				Parent = card,
			})
			local chips = {}
			if b.jobSeconds then
				table.insert(chips, `🪙{Ui.compact(b.payout or 0)}` .. (if b.partsPayout then ` +{b.partsPayout}⚙` else ""))
				table.insert(chips, if b.jobSeconds >= 60 then `⏱{b.jobSeconds // 60}m` else `⏱{b.jobSeconds}s`)
			end
			Ui.new("TextLabel", {
				Text = table.concat(chips, "  "),
				Font = Ui.BODY,
				TextSize = 13,
				TextColor3 = Color3.fromHex("#455a64"),
				BackgroundTransparency = 1,
				Position = UDim2.fromOffset(6, 158),
				Size = UDim2.new(1, -12, 0, 18),
				Parent = card,
			})
			local price = if r.owned then "Built" elseif r.sale.bucks > 0 then `💎 {Ui.compact(r.sale.bucks)}` else `🪙 {Ui.compact(r.sale.coins)}`
			if not r.owned and r.sale.coins == 0 and r.sale.bucks == 0 then
				price = "Free"
			end
			local priceTag = Ui.label({
				Text = price,
				TextSize = 18,
				TextColor3 = if r.broke and not r.locked then Color3.fromHex("#ff8a80") else Color3.new(1, 1, 1),
				Size = UDim2.new(1, -16, 0, 28),
				Position = UDim2.new(0, 8, 1, -34),
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.new(1, 1, 1),
				Parent = card,
			})
			Ui.corner(10).Parent = priceTag
			Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]).Parent = priceTag
			card.Activated:Connect(function()
				if r.owned then
					return
				elseif r.locked then
					toast(`Reach level {b.unlockLevel} to build the {b.name}`)
				elseif r.broke then
					if s.bucks < r.sale.bucks then
						toast(`You need {Ui.commas(r.sale.bucks - s.bucks)} more gems for the {b.name}`)
					else
						toast(`You need {Ui.commas(r.sale.coins - s.coins)} more coins for the {b.name}`)
					end
				else
					close()
					Placement.place(b.id, gui)
				end
			end)
		end
	end
	for i, t in TABS do
		Ui.button({ Name = t.id, Size = UDim2.fromOffset(150, 38), TextSize = 16, LayoutOrder = i, Parent = tabs }, "white", t.label, function()
			show(t.id)
		end)
	end
	show(lastTab)
	return frame
end

return Shop
