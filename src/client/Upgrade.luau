--!strict
-- A building's own sheet, as the web game's UpgradePanel (ui/Upgrade.tsx): its next level's look,
-- the level pips, a Now / Level n+1 table, the green Upgrade button, its colour themes and, for
-- businesses that take one, who drives for it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local merge = require(Game.merge) :: any
local cityLook = require(Game.cityLook) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)

local Upgrade = {}

local W = 456
local GAP = 10

local function time(sec: number): string
	if sec >= 60 then
		local s = sec % 60
		return `{sec // 60}m` .. (if s > 0 then ` {s}s` else "")
	end
	return `{sec}s`
end

local function carDefOf(c: any): any
	return data.carDef(c.model)
end

-- The level pips: gold up to the building's level, grey after.
local function pips(parent: Instance, order: number, level: number, max: number)
	local row = Ui.new("Frame", { Name = "Pips", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 8), BackgroundTransparency = 1, Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4) }),
	})
	for i = 1, max do
		local p = Ui.new("Frame", { Size = UDim2.fromOffset(18, 8), BackgroundColor3 = if i <= level then Ui.WHITE else Color3.fromHex("#cfd8dc"), BorderSizePixel = 0, LayoutOrder = i, Parent = row }, { Ui.corner(4) })
		if i <= level then
			Ui.gradient("#ffd54f", "#ff8f00").Parent = p
		end
	end
end

-- The Driver box: the car on the job, or the player's cars to pick from (favourites first).
local function driverBox(parent: Instance, order: number, s: any, b: any, d: any, picking: boolean, repick: (boolean) -> ()): number
	local lvl = data.buildingLevel(b)
	local car: any = nil
	for _, c in s.cars do
		if c.uid == b.car then
			car = c
		end
	end
	local box = Ui.new("Frame", { Name = "Driver", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 100), BackgroundColor3 = Ui.WHITE, Parent = parent }, {
		Ui.corner(12),
		Ui.stroke(2, Color3.fromHex("#f8bbd0")),
	})
	local pink = Color3.fromHex("#ad1457")
	if car and not picking then
		local cd = carDefOf(car)
		local broken = car.flat or car.lowFuel
		Ui.text({ Text = "Driver", TextSize = 15, TextColor3 = pink, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 20), Parent = box })
		local pic = Ui.new("Frame", { Position = UDim2.fromOffset(10, 34), Size = UDim2.fromOffset(52, 40), BackgroundColor3 = Color3.fromHex("#eef3fa"), Parent = box }, { Ui.corner(8) })
		Thumb.new("Cars", cd.id, UDim2.fromScale(1, 1), Color3.fromHex(car.color or "#ffffff")).Parent = pic
		Ui.text({ Text = cd.name, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Color3.fromHex("#263238"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(72, 36), Size = UDim2.new(1, -170, 0, 18), Parent = box })
		local bonus = if broken
			then "No bonus until it is fixed"
			else `{if data.loves(cd, d.id) then "❤️ Loves it · +25%" else "+10%"} · ${Ui.commas(data.driverPayout(d, lvl, store.workingDriver(s, b)))} a job`
		Ui.text({ Text = bonus, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex(if broken then "#e65100" else "#2e7d32"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(72, 55), Size = UDim2.new(1, -170, 0, 16), Parent = box })
		Ui.buy({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 40), Size = UDim2.fromOffset(78, 30), Parent = box }, "Change", "garage", function()
			repick(true)
		end, 14)
		box.Size = UDim2.new(1, 0, 0, 86)
		return 86
	end
	Ui.text({ Text = if car then "🚗 New driver" else "🚗 Driver", TextSize = 15, TextColor3 = pink, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -20, 0, 20), Parent = box })
	if picking then
		local cancel = Ui.new("TextButton", { Text = "Cancel", FontFace = Ui.DISPLAY, TextSize = 13, TextColor3 = Color3.fromHex("#607d8b"), BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(60, 20), Parent = box })
		cancel.Activated:Connect(function()
			repick(false)
		end)
	end
	local base = data.upgradePayout(d, lvl)
	Ui.text({ Text = `+10% ${Ui.commas(math.floor(base * 1.1 + 0.5))} · ❤️ +25% ${Ui.commas(math.floor(base * 1.25 + 0.5))}`, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex("#455a64"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 30), Size = UDim2.new(1, -20, 0, 18), Parent = box })
	local cars = table.clone(s.cars)
	table.sort(cars, function(x, y)
		local fx = if data.loves(carDefOf(x), d.id) then 1 else 0
		local fy = if data.loves(carDefOf(y), d.id) then 1 else 0
		return fx > fy
	end)
	local y = 54
	for _, c in cars do
		local cd = carDefOf(c)
		local fan = data.loves(cd, d.id)
		local at: any = nil
		for _, o in s.buildings do
			if o.car == c.uid and o.uid ~= b.uid then
				at = o
			end
		end
		local pick = Ui.new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Position = UDim2.fromOffset(10, y),
			Size = UDim2.new(1, -20, 0, 46),
			BackgroundColor3 = Color3.fromHex(if fan then "#fff5f8" else "#fafafa"),
			Parent = box,
		}, { Ui.corner(10), Ui.stroke(2, Color3.fromHex(if c.uid == b.car then "#66bb6a" elseif fan then "#f48fb1" else "#e0e0e0")) })
		local pic = Ui.new("Frame", { Position = UDim2.fromOffset(8, 5), Size = UDim2.fromOffset(44, 36), BackgroundTransparency = 1, Parent = pick })
		Thumb.new("Cars", cd.id, UDim2.fromScale(1, 1), Color3.fromHex(c.color or "#ffffff")).Parent = pic
		local notes = {}
		if at then
			table.insert(notes, `at {data.buildingDef(at.def).name}`)
		end
		if c.flat then
			table.insert(notes, "🛞 flat tire")
		end
		if c.lowFuel then
			table.insert(notes, "⛽ out of gas")
		end
		Ui.text({ Text = cd.name, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex("#263238"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(60, if #notes > 0 then 6 else 0), Size = UDim2.new(1, -140, if #notes > 0 then 0 else 1, if #notes > 0 then 18 else 0), Parent = pick })
		if #notes > 0 then
			Ui.text({ Text = table.concat(notes, " · "), Body = true, TextSize = 11, TextColor3 = Color3.fromHex("#78909c"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(60, 24), Size = UDim2.new(1, -140, 0, 14), Parent = pick })
		end
		Ui.text({ Text = if fan then "❤️ +25%" else "+10%", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex(if fan then "#ad1457" else "#546e7a"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0, 70, 1, 0), Parent = pick })
		pick.Activated:Connect(function()
			Remote.act("assignCar", b.uid, c.uid)
			repick(false)
		end)
		y += 52
	end
	if car then
		local off = Ui.new("TextButton", { Text = `Take {carDefOf(car).name} off this job`, FontFace = Ui.BODY, TextSize = 13, TextColor3 = Color3.fromHex("#c62828"), BackgroundTransparency = 1, Position = UDim2.fromOffset(10, y), Size = UDim2.new(1, -20, 0, 22), Parent = box })
		off.Activated:Connect(function()
			Remote.act("assignCar", b.uid, nil)
			repick(false)
		end)
		y += 26
	end
	if #cars == 0 then
		Ui.text({ Text = "No cars yet: buy one in CARS.", Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#78909c"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, y), Size = UDim2.new(1, -20, 0, 20), Parent = box })
		y += 24
	end
	box.Size = UDim2.new(1, 0, 0, y + 4)
	return y + 4
end

function Upgrade.open(ctx: any, uid: string?): Instance?
	local s0 = store.useGame.getState()
	local b0: any = nil
	for _, o in s0.buildings do
		if o.uid == uid then
			b0 = o
		end
	end
	if not b0 or not data.themable(data.buildingDef(b0.def)) then
		ctx.toast("That building has nothing to upgrade")
		return nil
	end
	local d = data.buildingDef(b0.def)
	local overlay, sheet, body = Ui.panel(ctx.gui, d.name, { width = W, onClose = ctx.close })
	local title = (sheet :: any).Head.Title :: TextLabel
	local limit = (sheet.Parent :: Instance):FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local list = Ui.scroller({ Name = "List", Position = UDim2.fromOffset(-6, 0), Size = UDim2.new(1, 12, 1, 0), Parent = body })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 4), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = list })
	local picking = false

	local show: () -> ()
	local function draw()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local s = store.useGame.getState()
		local b: any = nil
		for _, o in s.buildings do
			if o.uid == uid then
				b = o
			end
		end
		if not b then
			ctx.close()
			return
		end
		local canUp = data.upgradable(d)
		local lvl = data.buildingLevel(b)
		local maxL = data.maxLevel(d)
		local max = lvl >= maxL
		local nextL = if max then lvl else lvl + 1
		-- A merged block shows and upgrades all its buildings at once.
		local block = merge.groupOf(s.buildings, b.uid)
		local members = if block then block.members else { b }
		local k = #members
		local boost = if k > 1 then data.mergeBonus(k) else 0
		local one = data.buildingUpgradeCost(d, lvl)
		local cost = { coins = one.coins * k, parts = one.parts * k }
		local function sum(f: (any) -> number): number
			local t = 0
			for _, o in members do
				t += f(o)
			end
			return t
		end
		local rows: { { string } } = {}
		if d.jobSeconds then
			local driver = false
			for _, o in members do
				if store.workingDriver(s, o) then
					driver = true
				end
			end
			table.insert(rows, {
				if driver then "Coins per job (with driver)" else "Coins per job",
				`${Ui.commas(sum(function(o) return data.driverPayout(d, lvl, store.workingDriver(s, o), boost) end))}`,
				`${Ui.commas(sum(function(o) return data.driverPayout(d, nextL, store.workingDriver(s, o), boost) end))}`,
			})
			if d.partsPayout then
				table.insert(rows, { "Parts per job", `⚙ {data.mergedParts(d, lvl, boost) * k}`, `⚙ {data.mergedParts(d, nextL, boost) * k}` })
			end
			table.insert(rows, { "Job time", time(data.upgradeJobSeconds(d, lvl)), time(data.upgradeJobSeconds(d, nextL)) })
			table.insert(rows, { "XP per job", tostring(data.xpGain(s.level, data.jobXp(d, lvl, s.level) * k)), tostring(data.xpGain(s.level, data.jobXp(d, nextL, s.level) * k)) })
		end
		if data.decorGrows(d) then
			local function tour(l: number): number
				return math.floor(((l - 1) * data.TOURIST_PER_LEVEL * 100) / data.VISITORS.tourist.weight + 0.5)
			end
			table.insert(rows, { "📸 Tourists", `+{tour(lvl) * k}%`, `+{tour(nextL) * k}%` })
		end
		local function fuel(l: number): number
			return data.upgradeFuelCap(d, l) * k + (if k > 1 then data.mergedFuelExtra(d, l, k) else 0)
		end
		if data.upgradeFuelCap(d, nextL) > 0 then
			table.insert(rows, { "Max fuel", `+{fuel(lvl)}`, `+{fuel(nextL)}` })
		end
		if d.kind ~= "house" and data.levelName(d, nextL) ~= data.levelName(d, lvl) then
			table.insert(rows, { "Building", data.levelName(d, lvl), data.levelName(d, nextL) })
		end
		local landmark = if block and merge.isLandmark(block) then merge.landmarkName(block) else nil
		if d.kind == "house" then
			table.insert(rows, { "Building", landmark or data.levelName(d, lvl), data.levelName(d, nextL) })
			table.insert(rows, { "Residents", tostring(data.houseResidents(lvl) * k), tostring(data.houseResidents(nextL) * k) })
			table.insert(rows, { "Upgrade XP", "", `+{data.xpGain(s.level, data.buildingUpgradeXp(lvl) * k)}` })
		end
		local name = landmark or (data.levelName(d, lvl) .. (if k > 1 then ` ×{k}` else ""))
		Ui.setText(title, if canUp then `{name} · Level {lvl}` else name)

		local h = 0
		local order = 0
		local function add(height: number)
			order += 1
			h += height + GAP
		end
		-- The next level's look, with its tag.
		add(190)
		local preview = Ui.new("Frame", { Name = "Preview", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 190), BackgroundColor3 = Ui.WHITE, ClipsDescendants = true, Parent = list }, {
			Ui.corner(12),
			Ui.gradient("#e3f2fd", "#ffffff"),
		})
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.72, 0), Size = UDim2.fromOffset(176, 96), BackgroundColor3 = Color3.fromHex("#cfd8dc"), Parent = preview }, { Ui.round() })
		Thumb.new("Buildings", d.id, UDim2.new(1, 0, 1, -10), nil).Parent = preview
		local shown = if canUp then nextL else lvl
		local tag = Ui.new("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#263238"), ZIndex = 2, Parent = preview }, {
			Ui.corner(8),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
		})
		Ui.text({ Text = `Level {shown}{if shown > 1 then " look" else ""}`, TextSize = 13, TextColor3 = Color3.fromHex("#ffca28"), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 2, Parent = tag })
		if canUp then
			add(8)
			pips(list, order, lvl, maxL)
		end
		if k > 1 and boost > 0 then
			add(20)
			Ui.text({ Text = `🧩 ×{k} · {data.mergeGain(d)} +{math.floor(boost * 100 + 0.5)}%`, TextSize = 15, TextColor3 = Color3.fromHex("#7e57c2"), Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order, Parent = list })
		end
		if canUp and max then
			add(24)
			Ui.text({ Text = "⭐ Max level", TextSize = 17, TextColor3 = Color3.fromHex("#ef6c00"), Size = UDim2.new(1, 0, 0, 24), LayoutOrder = order, Parent = list })
		elseif canUp then
			-- Now / Level n+1.
			local th = 24 + #rows * 30 + 2
			add(th)
			local tbl = Ui.new("Frame", { Name = "Stats", LayoutOrder = order, Size = UDim2.new(1, 0, 0, th), BackgroundColor3 = Ui.WHITE, Parent = list }, {
				Ui.corner(12),
				Ui.stroke(2, Color3.fromHex("#e0e0e0")),
			})
			local nowX = 0.7
			local grey = Color3.fromHex("#607d8b")
			Ui.text({ Text = "Now", TextSize = 13, TextColor3 = grey, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(nowX, -10, 0, 16), Parent = tbl })
			Ui.text({ Text = `Level {nextL}`, TextSize = 13, TextColor3 = grey, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(nowX, 0, 0, 6), Size = UDim2.new(1 - nowX, -10, 0, 16), Parent = tbl })
			for i, r in rows do
				local y = 24 + (i - 1) * 30
				Ui.new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromHex("#eceff1"), BorderSizePixel = 0, Parent = tbl })
				type Cell = { text: string, x: number, sx: number, w: number, align: Enum.TextXAlignment, color: string }
				local cells: { Cell } = {
					{ text = r[1], x = 10, sx = 0, w = 0.5, align = Enum.TextXAlignment.Left, color = "#263238" },
					{ text = r[2], x = 0, sx = 0, w = nowX, align = Enum.TextXAlignment.Right, color = "#455a64" },
					{ text = r[3], x = 0, sx = nowX, w = 1 - nowX, align = Enum.TextXAlignment.Right, color = "#2e7d32" },
				}
				for _, c in cells do
					Ui.text({
						Text = c.text,
						Body = true,
						Weight = "heavy",
						TextSize = 14,
						TextColor3 = Color3.fromHex(c.color),
						TextXAlignment = c.align,
						Position = UDim2.new(c.sx, c.x, 0, y + 1),
						Size = UDim2.new(c.w, -10, 0, 29),
						Parent = tbl,
					})
				end
			end
			local shortCoins = math.max(0, cost.coins - s.coins)
			local shortParts = math.max(0, cost.parts - s.parts)
			add(42)
			local label = `⬆ Upgrade · ${Ui.commas(cost.coins)}` .. (if cost.parts > 0 then ` · ⚙ {cost.parts}` else "")
			local shadow = Ui.buy({ Name = "UpgradeBuy", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 42), Parent = list }, label, "green", function()
				local ok = Remote.act("upgradeBuilding", b.uid)
				if not ok and (shortCoins > 0 or shortParts > 0) then
					ctx.open("need", if shortCoins > 0 then { res = "coins", missing = shortCoins, what = `upgrading your {name}` } else { res = "parts", missing = shortParts, what = `upgrading your {name}` })
				end
			end, 19)
			if shortCoins > 0 or shortParts > 0 then
				-- The web greys it a little (saturate .55) and adds a Need line under it.
				local g = (shadow :: any).Face:FindFirstChildOfClass("UIGradient")
				if g then
					g.Color = Ui.seq("#9fcf86", "#5f9a5f")
				end
				local parts = {}
				if shortCoins > 0 then
					table.insert(parts, `${Ui.commas(shortCoins)}`)
				end
				if shortParts > 0 then
					table.insert(parts, `⚙ {shortParts}`)
				end
				add(38)
				local need = Ui.new("TextButton", { Name = "Short", Text = "", AutoButtonColor = false, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Color3.fromHex("#fff8e1"), Parent = list }, {
					Ui.corner(12),
					Ui.stroke(2, Color3.fromHex("#ffca28")),
				})
				Ui.text({ Text = `Need {table.concat(parts, " · ")} ➜`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Color3.fromHex("#6d4c41"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -20, 1, 0), Parent = need })
				need.Activated:Connect(function()
					ctx.open("need", if shortCoins > 0 then { res = "coins", missing = shortCoins, what = `upgrading your {name}` } else { res = "parts", missing = shortParts, what = `upgrading your {name}` })
				end)
			end
		end
		-- Colour themes: its own colours, then a swatch per theme.
		add(40)
		local strip = Ui.new("Frame", { Name = "Themes", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = list }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local function dot(i: number, id: string?, color: string, icon: string?)
			local sel = b.tint == id
			local btn = Ui.new("TextButton", {
				Text = icon or "",
				TextSize = 16,
				LayoutOrder = i,
				AutoButtonColor = false,
				Size = UDim2.fromOffset(34, 34),
				BackgroundColor3 = Color3.fromHex(color),
				Parent = strip,
			}, { Ui.round(), Ui.stroke(2, if sel then Color3.fromHex("#ff8f00") else Ui.BLACK, if sel then 0 else 0.82) })
			if sel then
				Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 10, 1, 10), BackgroundTransparency = 1, ZIndex = 0, Parent = btn }, {
					Ui.round(),
					Ui.stroke(3, Color3.fromHex("#ff8f00"), 0.65),
				})
			end
			btn.Activated:Connect(function()
				Remote.act("setBuildingTint", b.uid, id)
			end)
		end
		dot(0, nil, "#ffffff", "🎨")
		for i, t in cityLook.COLOR_THEMES do
			dot(i, t.id, t.c)
		end
		if data.takesDriver(d) then
			order += 1
			h += driverBox(list, order, s, b, d, picking, function(on: boolean)
				picking = on
				show()
			end) + GAP
		end
		-- The sheet hugs what's in it, as the web's panel, up to the screen's height.
		limit.MaxSize = Vector2.new(W, 61 + 10 + h + 14)
	end
	show = draw
	draw()
	local conn = Remote.changed:Connect(draw)
	overlay.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return overlay
end

return Upgrade
