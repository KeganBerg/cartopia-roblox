--!strict
-- The Shop, as the web game's ShopPanel (ui/Menus.tsx, shop.css): tabs of buildings and a search
-- box over a grid of cards, each with the building, its name, what one job makes as chips (coins
-- and parts, how long, the fuel it takes) and one price button. Picking one starts placing it.
-- The Upgrades tab lists the town's buildings with their next upgrade, as ShopUpgrades.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local merge = require(Game.merge) :: any
local cityLook = require(Game.cityLook) :: any
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)
local Placement = require(script.Parent.Placement)

local Shop = {}

local LINE = Ui.LINE

-- Tabs and what goes in each, as SHOP_GROUPS in ui/Menus.tsx.
local CAR_CARE = { carwash = true, bodyshop = true }
local GROUPS: { { id: string, label: string, filter: (any) -> boolean } } = {
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

local function capital(s: string): string
	return s:sub(1, 1):upper() .. s:sub(2)
end

-- A chip under the card's name: a little rounded label.
local function chip(parent: Instance, order: number, text: string, bg: string, fg: string)
	local c = Ui.new("Frame", { Size = UDim2.fromOffset(0, 21), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex(bg), LayoutOrder = order, Parent = parent }, {
		Ui.round(),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex(fg), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = c })
end

-- A pill on the card's top edge (START HERE, ★ NEW, DEAL).
local function ribbon(face: Instance, text: string, colors: { string })
	local r = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -12), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = face }, {
		Ui.corner(9),
		Ui.stroke(2),
		Ui.gradient(colors[1], colors[2]),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
	})
	Ui.text({ Text = text, TextSize = 12, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 4, Shadow = 1, ShadowColor = Ui.BLACK, ShadowTransparency = 0.65, Parent = r })
end

-- A white card with a navy outline and a drop shadow, sized by the grid.
local function card(parent: Instance, order: number, dim: boolean): (Frame, TextButton)
	local shadow, face = Ui.shadowed({ LayoutOrder = order, Parent = parent }, { radius = 18, stroke = 3, drop = 4, dark = 0.3, class = "TextButton", color = Ui.WHITE })
	if dim then
		local s = face:FindFirstChildOfClass("UIStroke")
		if s then
			s.Color = Color3.fromHex("#5b6475")
		end
		shadow.BackgroundTransparency = 0.82
	end
	return shadow, face
end

local function thumbBox(face: Instance, def: string, bg: string, height: number, theme: any?)
	local box = Ui.new("Frame", { Name = "Thumb", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, height), BackgroundColor3 = Color3.fromHex(bg), Parent = face }, { Ui.corner(12) })
	local pic = Thumb.new("Buildings", def, UDim2.fromScale(1, 1), nil, theme)
	pic.Parent = box
	return box, pic
end

function Shop.open(ctx: any, focus: string?): Instance
	local s = store.useGame.getState()
	local overlay, _, body = Ui.panel(ctx.gui, "Shop", { wide = true, onClose = ctx.close, bodyTop = 0 })
	local canUpgrade = false
	for _, b in s.buildings do
		if data.upgradable(data.buildingDef(b.def)) then
			canUpgrade = true
		end
	end
	local items = {}
	for _, g in GROUPS do
		table.insert(items, { id = g.id, label = g.label })
	end
	local ev = data.activeEvent()
	if ev then
		table.insert(items, { id = "event", label = "🎃 Spooky" })
	end
	if canUpgrade then
		table.insert(items, { id = "upgrades", label = "⬆️ Upgrades" })
	end
	if focus == "upgrades" then
		lastTab = "upgrades"
	elseif focus then
		local def = data.buildingDef(focus)
		for _, g in GROUPS do
			if def and g.filter(def) then
				lastTab = g.id
			end
		end
	end
	if (lastTab == "upgrades" and not canUpgrade) or (lastTab == "event" and not ev) or not store.hasRusty(s) then
		lastTab = "cars"
	end

	-- The search box: one look through every tab at once.
	local find = Ui.new("Frame", { Name = "Find", Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Ui.WHITE, Parent = body }, {
		Ui.corner(12),
		Ui.stroke(2, LINE, 0.86),
	})
	Ui.text({ Text = "🔍", TextSize = 16, Position = UDim2.fromOffset(12, 0), Size = UDim2.fromOffset(22, 50), Parent = find })
	local box = Ui.new("TextBox", {
		Name = "Input",
		Text = "",
		PlaceholderText = "Find a building",
		PlaceholderColor3 = Color3.fromHex("#6b7a90"),
		ClearTextOnFocus = false,
		FontFace = Ui.BODY,
		TextSize = 16,
		TextColor3 = LINE,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -54, 1, 0),
		Parent = find,
	})

	local grid = Ui.scroller({ Name = "Grid", Position = UDim2.new(0, -6, 0, 116), Size = UDim2.new(1, 12, 1, -116), Parent = body })
	Ui.new("UIPadding", { PaddingTop = UDim.new(0, 18), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12), Parent = grid })
	local gridLayout = Ui.new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, 280), CellPadding = UDim2.fromOffset(10, 16), SortOrder = Enum.SortOrder.LayoutOrder, Parent = grid })
	-- The Upgrades tab stacks sections (its cards, then the maxed ones under a heading).
	local listLayout = Ui.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder })

	local gate = store.gateLevel(s)
	local current = lastTab
	local function clear()
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end

	local function showBuildings(list: { any })
		local rusty = store.hasRusty(s)
		local rows = {}
		for _, b in list do
			local sale = store.buildPrice(s, b.id)
			local locked = gate < b.unlockLevel
			local brokeGems = s.bucks < sale.bucks
			local broke = s.coins < sale.coins or brokeGems
			local owned = false
			if b.unique then
				for _, o in s.buildings do
					if o.def == b.id then
						owned = true
					end
				end
				for _, o in (s.stored or {}) do
					if o.def == b.id then
						owned = true
					end
				end
			end
			local rank = if owned then 3 elseif locked then 2 elseif broke then 1 else 0
			table.insert(rows, { b = b, sale = sale, locked = locked, broke = broke, brokeGems = brokeGems, owned = owned, rank = rank })
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
			local dim = r.locked or r.owned
			local highlight = b.id == "rescue" and not rusty
			local built = false
			for _, o in s.buildings do
				if o.def == b.id then
					built = true
				end
			end
			local feature = not highlight and not r.locked and data.FEATURES[b.id] ~= nil and not built
			local _, face = card(grid, i, dim)
			local _, pic = thumbBox(face, b.id, if dim then "#e6e9ed" elseif r.broke then "#fde3e5" else "#dcecfb", 112)
			if dim then
				pic.ImageTransparency = 0.45
			end
			if highlight then
				ribbon(face, "START HERE", { "#ffb02e", "#ff9f1a" })
				local s2 = face:FindFirstChildOfClass("UIStroke")
				if s2 then
					s2.Color = LINE
				end
			elseif feature then
				ribbon(face, "★ NEW", { "#7c4dff", "#00b0ff" })
			end
			if r.sale.deal and not r.locked then
				ribbon(face, "DEAL", { "#ff5252", "#d50000" })
			end
			Ui.text({ Text = b.name, TextSize = 17, TextColor3 = if dim then Color3.fromHex("#5b6475") else LINE, TextWrapped = true, Position = UDim2.fromOffset(6, 125), Size = UDim2.new(1, -12, 0, 38), Parent = face })
			local chips = Ui.new("Frame", { Position = UDim2.fromOffset(4, 167), Size = UDim2.new(1, -8, 0, 22), BackgroundTransparency = 1, Parent = face }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			local grey = dim
			if b.jobSeconds then
				chip(chips, 1, `${Ui.compact(b.payout or 0)}` .. (if b.partsPayout then ` +{b.partsPayout}⚙` else ""), if grey then "#eef1f4" else "#fff2c2", if grey then "#7d8894" else "#7a5200")
				chip(chips, 2, `⏱{Ui.every(b.jobSeconds)}`, if grey then "#eef1f4" else "#eef3fa", if grey then "#7d8894" else "#14213d")
				chip(chips, 3, `⛽{b.fuelCost or 0}`, if grey then "#eef1f4" else "#ffe5e3", if grey then "#7d8894" else "#b3261e")
			end
			if b.nightOnly then
				chip(chips, 4, "🌙", "#eef3fa", "#14213d")
			end
			if b.fuelCap then
				chip(chips, 5, `⛽+{b.fuelCap}`, "#e3f6e4", "#1d6b22")
			end
			if highlight or feature then
				Ui.text({ Text = `✨ {capital(data.FEATURES[b.id])}`, Body = true, TextSize = 12, TextColor3 = Color3.fromHex("#5e35b1"), TextWrapped = true, Position = UDim2.fromOffset(8, 193), Size = UDim2.new(1, -16, 0, 32), Parent = face })
			end
			local label, kind
			if r.owned then
				label, kind = "✔ Built", "grey"
			elseif r.locked then
				label, kind = `🔒 Lv {b.unlockLevel}`, "grey"
			elseif r.sale.bucks > 0 then
				label, kind = `💎 {Ui.commas(r.sale.bucks)}`, if r.broke then "broke" else "garage"
			elseif r.sale.coins == 0 then
				label, kind = "Free", "green"
			else
				label, kind = `${Ui.commas(r.sale.coins)}`, if r.broke then "broke" else "green"
			end
			local function pick()
				if r.owned then
					return
				elseif r.locked then
					ctx.open("need", { res = "level", missing = b.unlockLevel, what = b.name })
				elseif r.brokeGems then
					ctx.open("need", { res = "bucks", missing = r.sale.bucks - s.bucks, what = b.name })
				elseif r.broke then
					ctx.open("need", { res = "coins", missing = r.sale.coins - s.coins, what = b.name })
				else
					ctx.close()
					Placement.place(b.id, ctx.gui, ctx)
				end
			end
			-- The price button sits on top of the card and takes the taps there, so it runs the
			-- same thing as the rest of the card.
			Ui.buy({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, 32), Parent = face }, label, kind, pick, 17)
			face.Activated:Connect(pick)
		end
	end

	-- Upgrades: a card per building or merged block (🧩×k, its price ×k) with its next upgrade,
	-- cheapest first; identical ones stack on one card (×n), and maxed ones sit together at the
	-- bottom under "⭐ Max · n" (ShopUpgrades in ui/Upgrade.tsx).
	local function section(order: number, count: number, cols: number, cellH: number): Frame
		local rows = math.ceil(count / cols)
		local f = Ui.new("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, rows * cellH + (rows - 1) * 16), Parent = grid })
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / cols, -8, 0, cellH), CellPadding = UDim2.fromOffset(10, 16), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
		return f
	end

	local function showUpgrades(term: string)
		local merges = merge.mergeGroups(s.buildings)
		local function size(b: any): number
			local g = merges.groups:get(b.uid)
			return if g then #g.members else 1
		end
		local rank: { [string]: number } = {}
		for i, d in data.BUILDINGS do
			rank[d.id] = i
		end
		local list = {}
		for _, b in s.buildings do
			local d = data.buildingDef(b.def)
			-- A merged block is one card, on its top-left building.
			if data.upgradable(d) and (not merges.owner:has(b.uid) or merges.groups:has(b.uid)) then
				local lvl = data.buildingLevel(b)
				local name = data.levelName(d, lvl)
				if term == "" or string.find(name:lower(), term, 1, true) then
					local k = size(b)
					local max = lvl >= data.maxLevel(d)
					local one = if max then nil else data.buildingUpgradeCost(d, lvl)
					local cost = if one then { coins = one.coins * k, parts = one.parts * k } else nil
					table.insert(list, { b = b, d = d, lvl = lvl, name = name, max = max, cost = cost, k = k, n = 1 })
				end
			end
		end
		table.sort(list, function(x, y)
			local cx = if x.cost then x.cost.coins else math.huge
			local cy = if y.cost then y.cost.coins else math.huge
			if cx ~= cy then
				return cx < cy
			end
			return (rank[x.d.id] or 0) < (rank[y.d.id] or 0)
		end)
		-- Identical buildings (same kind, level, colours and block size) share a card; a tap opens
		-- the first.
		local open, maxed = {}, {}
		local seen: { [string]: any } = {}
		local maxCount = 0
		for _, u in list do
			local key = `{u.b.def}|{u.lvl}|{u.b.tint or ""}|{u.k}`
			local hit = seen[key]
			if hit then
				hit.n += 1
			else
				seen[key] = u
				table.insert(if u.max then maxed else open, u)
			end
			if u.max then
				maxCount += 1
			end
		end
		if #list == 0 then
			Ui.text({ Text = "🔍 No match", TextSize = 16, TextColor3 = LINE, Size = UDim2.new(1, 0, 0, 30), Parent = grid })
			return
		end
		local function badges(face: Instance, u: any, top: number)
			if u.k > 1 then
				local k = Ui.new("Frame", { Name = "Merged", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#7e57c2"), ZIndex = 3, Parent = face }, {
					Ui.round(),
					Ui.stroke(2),
					Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
				})
				Ui.text({ Text = `🧩×{u.k}`, Body = true, Weight = "heavy", TextSize = 14, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = k })
			end
			if u.n > 1 then
				local n = Ui.new("Frame", { Name = "Count", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, top), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = LINE, ZIndex = 3, Parent = face }, {
					Ui.round(),
					Ui.stroke(2, Ui.WHITE),
					Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
				})
				Ui.text({ Text = `×{u.n}`, TextSize = 16, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = n })
			end
		end
		-- A stack of identical cards shows two more peeking out behind it.
		local function cell(parent: Instance, order: number, u: any): (Frame, TextButton)
			if u.n == 1 then
				return card(parent, order, false)
			end
			local holder = Ui.new("Frame", { LayoutOrder = order, BackgroundTransparency = 1, Parent = parent })
			for i = 2, 1, -1 do
				Ui.new("Frame", { Position = UDim2.fromOffset(i * 5, i * 6), Size = UDim2.new(1, -10, 1, -12), BackgroundColor3 = Ui.WHITE, Parent = holder }, { Ui.corner(18), Ui.stroke(3) })
			end
			local shadow, face = card(holder, 0, false)
			shadow.Size = UDim2.new(1, -10, 1, -12)
			return shadow, face
		end
		local function pick(u: any)
			return function()
				ctx.open("upgrade", u.b.uid)
			end
		end
		if #open > 0 then
			local sec = section(1, #open, 4, 280)
			for i, u in open do
				local afford = s.coins >= u.cost.coins and s.parts >= u.cost.parts
				local _, face = cell(sec, i, u)
				if afford then
					face.BackgroundColor3 = Color3.fromHex("#eaffe4")
					local st = face:FindFirstChildOfClass("UIStroke")
					if st then
						st.Color = Color3.fromHex("#1d6b22")
					end
				end
				thumbBox(face, u.d.id, "#dcecfb", 112, cityLook.themeFor(u.b.tint, s.cityTheme, u.d.kind == "decor"))
				local lv = Ui.new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = face }, { Ui.round(), Ui.stroke(2), Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]) })
				Ui.text({ Text = tostring(u.lvl), TextSize = 15, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = lv })
				badges(face, u, 78)
				Ui.text({ Text = u.name, TextSize = 17, TextColor3 = LINE, TextWrapped = true, Position = UDim2.fromOffset(6, 125), Size = UDim2.new(1, -12, 0, 38), Parent = face })
				local label = `⬆ ${Ui.compact(u.cost.coins)}` .. (if u.cost.parts > 0 then ` ⚙{Ui.compact(u.cost.parts)}` else "")
				Ui.buy({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, 32), Parent = face }, label, if afford then "green" else "broke", pick(u), 17)
				face.Activated:Connect(pick(u))
			end
		end
		if #maxed > 0 then
			Ui.text({ Text = `⭐ Max · {maxCount}`, TextSize = 18, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, -4, 0, 24), Parent = grid })
			local sec = section(3, #maxed, 5, 156)
			for i, u in maxed do
				local _, face = cell(sec, i, u)
				face.BackgroundColor3 = Color3.fromHex("#fff8e1")
				thumbBox(face, u.d.id, "#ffecb3", 72, cityLook.themeFor(u.b.tint, s.cityTheme, u.d.kind == "decor"))
				local lv = Ui.new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = Color3.fromHex("#ffc533"), ZIndex = 3, Parent = face }, { Ui.round(), Ui.stroke(2) })
				Ui.text({ Text = "⭐", TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = lv })
				badges(face, u, 50)
				Ui.text({ Text = u.name, TextSize = 14, TextColor3 = LINE, TextWrapped = true, Position = UDim2.fromOffset(6, 86), Size = UDim2.new(1, -12, 0, 40), Parent = face })
				face.Activated:Connect(pick(u))
			end
		end
	end

	local function show()
		clear()
		grid.CanvasPosition = Vector2.zero
		local term = box.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
		local upgrades = current == "upgrades"
		gridLayout.Parent = if upgrades then nil else grid
		listLayout.Parent = if upgrades then grid else nil
		if upgrades then
			showUpgrades(term)
			return
		end
		local list = {}
		for _, b in data.BUILDINGS do
			if b.unlockLevel < 99 then
				local inTab = false
				for _, g in GROUPS do
					if (term ~= "" or g.id == current) and g.filter(b) then
						inTab = true
					end
				end
				if b.event and ev and b.event == ev.id and (term ~= "" or current == "event") then
					inTab = true
				end
				if inTab and (term == "" or string.find(b.name:lower(), term, 1, true)) then
					table.insert(list, b)
				end
			end
		end
		showBuildings(list)
	end

	Ui.tabs(body, items, current, function(id)
		current = id
		lastTab = id
		box.Text = ""
		show()
	end, { position = UDim2.fromOffset(-14, 0), size = UDim2.new(1, 28, 0, 54) })
	box:GetPropertyChangedSignal("Text"):Connect(show)
	show()
	return overlay
end

return Shop
