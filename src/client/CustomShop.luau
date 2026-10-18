--!strict
-- The garage's Custom tab (the web's CustomShop): custom paint part by part. Pick a part (the body,
-- hood, doors, roof or wheels), then a pattern and a colour to try on the car on the turntable,
-- then buy the lot from the bar on top. Locked colours can be tried on too; the bar then names the
-- paint rival who has it (or the Tuner Trial that wins a pattern).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local Pictures = require(ReplicatedStorage.Shared.Pictures)
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local mastery = require(Game.mastery) :: any
local paintRivals = require(Game.paintRivals) :: any
local trophyRoad = require(Game.trophyRoad) :: any
local tuner = require(Game.tuner) :: any
local Models = ReplicatedStorage.Shared.Models
local Catalog = require(Models.Catalog)
local Panels = require(Models.Panels)
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)

local CustomShop = {}

local LINE = Ui.LINE
local SOFT = Color3.fromHex("#607d8b")
local TEXTURES: { [string]: { image: number } } = (Catalog :: any).TEXTURES or {}

-- The part the tab is on (kept while the garage stays open).
local part = "hood"

function CustomShop.reset()
	part = "hood"
end

-- Whether two custom paint jobs are the same once tidied.
function CustomShop.same(a: any, b: any): boolean
	return Panels.key(data.tidyPanels(a)) == Panels.key(data.tidyPanels(b))
end

local function header(parent: Instance, order: number, text: string)
	Ui.text({ Name = "H" .. order, Text = text, TextSize = 16, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 24), ZIndex = 3, Parent = parent })
end

local function grid(parent: Instance, order: number, cell: UDim2, pad: number): Frame
	return Ui.new("Frame", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3, Parent = parent }, {
		Ui.new("UIGridLayout", { CellSize = cell, CellPadding = UDim2.fromOffset(pad, pad), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }),
	})
end

-- A pattern drawn small in a colour: its tile over the colour.
local function swatch(parent: Instance, pattern: string?, color: string)
	local back = Ui.new("Frame", { Name = "Swatch", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(56, 32), BackgroundColor3 = Color3.fromHex(color), ClipsDescendants = true, ZIndex = 3, Parent = parent }, {
		Ui.corner(6),
		Ui.stroke(1, Color3.fromHex("#b0bec5")),
	})
	local t = pattern and TEXTURES[`pattern_{pattern}`]
	if t and t.image ~= 0 then
		Ui.new("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Pictures.content(t.image), ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(56, 56), ZIndex = 3, Parent = back })
	end
end

-- `parent` is the detail card's space under the tabs. `panels`: the custom paint being tried (the
-- car's own when nothing is); `setPanels(nil)` stops trying.
function CustomShop.draw(parent: Instance, ctx: any, car: any, panels: any, setPanels: (any) -> ())
	local s = store.useGame.getState()
	local gate = store.gateLevel(s)
	local bike = data.isBike(data.carDef(car.model).body)
	local parts = {}
	for _, p in data.PANELS do
		if not bike or not p.car then
			table.insert(parts, p)
		end
	end
	local info = parts[1]
	for _, p in parts do
		if p.id == part then
			info = p
		end
	end
	local now = data.tidyPanels(car.panels)
	local changed = not CustomShop.same(panels, now)
	local cost = data.panelJobCost(now, data.tidyPanels(panels))
	local mine = panels and panels[info.id]
	local function colour(id: string): string
		local p = panels and panels[id]
		return p and p.color or car.color
	end
	-- Sets the part's colour or pattern (a field of false clears it).
	local function pick(p: { color: (string | boolean)?, pattern: (string | boolean)? })
		local one = table.clone(mine or {})
		if p.color ~= nil then
			one.color = if p.color == false then nil else p.color
		end
		if p.pattern ~= nil then
			one.pattern = if p.pattern == false then nil else p.pattern
		end
		local next = table.clone(panels or {})
		next[info.id] = one
		local tidy = data.tidyPanels(next)
		setPanels(if CustomShop.same(tidy, now) then nil else (tidy or {}))
	end
	local tier = mastery.masteryTier(s.mastery, car.model)
	local function open(id: string, c: string): boolean
		return (now and now[id] and now[id].color == c) or paintRivals.paintOpen(s, c)
	end
	-- A mastery pattern needs that step in this car; a Trophy Road one, won at a mystery stop.
	local function earned(id: string, pt: any): boolean
		if now and now[id] and now[id].pattern == pt.id then
			return true
		end
		if pt.mastery then
			return tier >= pt.mastery
		end
		if pt.road then
			return trophyRoad.roadOpen(s.roadItems, pt.id)
		end
		return true
	end
	-- A pattern won in a Tuner Trial stays shut until that trial is won.
	local function shut(id: string, pattern: string): any
		local pt = data.patternDef(pattern)
		local t = tuner.tunerTrial(pt and pt.trial or "")
		if t and not (((s.tuner or {})[t.id] or 0) > 0) and not (now and now[id] and now[id].pattern == pattern) then
			return t
		end
		return nil
	end
	local trialFor, lockedBy = nil, nil
	for _, p in data.PANELS do
		local v = panels and panels[p.id]
		if v and v.pattern and not trialFor then
			trialFor = shut(p.id, v.pattern)
		end
		if v and v.color and not lockedBy and not open(p.id, v.color) then
			lockedBy = paintRivals.rivalForPaint(v.color)
		end
	end

	local body = Ui.scroller({ Name = "CustomShop", Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = parent })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

	if changed then
		local bar = Ui.new("Frame", { Name = "TryBar", LayoutOrder = 1, Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = Color3.fromHex("#fff8e1"), ZIndex = 3, Parent = body }, {
			Ui.corner(12),
			Ui.stroke(1.5, Color3.fromHex("#ffcc80")),
		})
		local what = Ui.text({ Text = "Trying <b>custom paint</b>", Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#37474f"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -230, 1, 0), ZIndex = 3, Parent = bar })
		what.RichText = true
		local undo = Ui.new("TextButton", { Name = "Undo", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -140, 0.5, 0), Size = UDim2.fromOffset(52, 30), BackgroundTransparency = 1, ZIndex = 3, Parent = bar })
		Ui.text({ Text = "<u>Undo</u>", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = undo }).RichText = true
		undo.Activated:Connect(function()
			setPanels(nil)
		end)
		local go = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(126, 32), Parent = bar }
		local _shadow, button
		if trialFor then
			_shadow, button = Ui.buy(go, `🏁 {trialFor.icon} {trialFor.name}`, "green", function()
				ctx.toast(`Win {trialFor.name} to unlock that pattern`)
				ctx.open("race")
			end, 13)
		elseif lockedBy then
			local first = string.split(lockedBy.name, " ")[1]
			_shadow, button = Ui.buy(go, `🏁 {lockedBy.icon} {first}`, "green", function()
				ctx.toast(`Beat {lockedBy.name} in the Race menu to win that colour`)
				ctx.open("race")
			end, 14)
		else
			local bits = {}
			if cost.coins > 0 then
				table.insert(bits, `${Ui.commas(cost.coins)}`)
			end
			if cost.bucks > 0 then
				table.insert(bits, `💎 {cost.bucks}`)
			end
			local price = if #bits > 0 then table.concat(bits, " + ") else "Free"
			local function buy()
				local ok, done = Remote.act("paintPanels", car.uid, panels or {})
				if ok and done then
					ctx.toast("Fresh paint! 🎨")
					setPanels(nil)
				end
			end
			if cost.bucks > 0 then
				_shadow, button = Ui.button(go, "ten", buy, { radius = 12, stroke = 2, drop = 2, dark = 0.2, strokeColor = Color3.fromHex("#4a148c"), text = price, textSize = 14, textShadow = 1.5 })
			else
				_shadow, button = Ui.buy(go, price, "green", buy, 14)
			end
		end
		button.Name = "Go"
		button.ZIndex = 3
	end

	-- The parts, each with a chip in its colour.
	local tabs = Ui.new("Frame", { Name = "Parts", LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 48), BackgroundTransparency = 1, ZIndex = 3, Parent = body }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, p in parts do
		local on = p.id == info.id
		local t = Ui.new("TextButton", { Name = p.id, Text = "", AutoButtonColor = false, LayoutOrder = i, Size = UDim2.fromOffset(40, 48), BackgroundColor3 = if on then Color3.fromHex("#fff8e1") else Color3.fromHex("#fafafa"), ZIndex = 3, Parent = tabs }, {
			Ui.corner(10),
			Ui.stroke(2, if on then Color3.fromHex("#ff9f1a") else Color3.fromHex("#e0e0e0")),
		})
		local chip = if p.id == "rims" and not (panels and panels.rims and panels.rims.color) then "#cfd8dc" else colour(p.id)
		Ui.new("Frame", { Name = "Chip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(28, 16), BackgroundColor3 = Color3.fromHex(chip), ZIndex = 3, Parent = t }, {
			Ui.corner(5),
			Ui.stroke(1, Color3.fromHex("#546e7a")),
		})
		Ui.text({ Text = p.name, Body = true, Weight = "heavy", TextSize = 11, TextColor3 = if on then Color3.fromHex("#263238") else Color3.fromHex("#455a64"), Position = UDim2.fromOffset(0, 27), Size = UDim2.new(1, 0, 0, 14), ZIndex = 3, Parent = t })
		if panels and panels[p.id] then
			Ui.new("Frame", { Name = "Dot", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.fromHex("#43a047"), ZIndex = 3, Parent = t }, { Ui.round() })
		end
		t.Activated:Connect(function()
			part = p.id
			setPanels(panels)
		end)
	end

	if info.pattern then
		header(body, 3, "Pattern")
		local g = grid(body, 4, UDim2.fromOffset(84, 72), 6)
		local list: { any } = { false }
		for _, pt in data.PATTERNS do
			table.insert(list, pt)
		end
		for i, pt in list do
			local id: string? = if pt then pt.id else nil
			local on = (mine and mine.pattern or nil) == id
			local had = now and now[info.id] and now[info.id].pattern == id
			local earn = nil
			if pt and not earned(info.id, pt) then
				earn = if pt.mastery then `🔒 {mastery.MASTERY_TIERS[pt.mastery].icon}` else "🔒 🛣️"
			end
			local locked = (pt and gate < pt.unlockLevel and not had) or earn ~= nil
			local trial = if pt then shut(info.id, pt.id) else nil
			local b = Ui.new("TextButton", { Name = id or "solid", Text = "", AutoButtonColor = false, LayoutOrder = i, BackgroundColor3 = Ui.WHITE, BackgroundTransparency = if locked then 0.4 else 0, ZIndex = 3, Parent = g }, {
				Ui.corner(10),
				Ui.stroke(if on then 2.5 else 1.5, if on then Color3.fromHex("#ff9f1a") else Color3.fromHex("#dfe5ea")),
			})
			swatch(b, id, colour(info.id))
			Ui.text({ Text = if pt then pt.name else "Solid", TextSize = 12, TextColor3 = Color3.fromHex("#37474f"), TextTransparency = if locked then 0.3 else 0, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, 40), Size = UDim2.new(1, -4, 0, 14), ZIndex = 3, Parent = b })
			local foot = earn
				or (if locked and pt then `🔒 Lv {pt.unlockLevel}` else nil)
				or (if trial then `🏁 {trial.icon}` else nil)
				or (if not pt or (pt.coins or 0) == 0 then "Free" elseif had then "✔" else `${Ui.commas(pt.coins)}`)
			Ui.text({ Text = foot, Body = true, Weight = "heavy", TextSize = 11, TextColor3 = SOFT, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 14), ZIndex = 3, Parent = b })
			b.Activated:Connect(function()
				if locked then
					ctx.toast(if earn and pt and pt.mastery then `{pt.name}: reach {mastery.MASTERY_TIERS[pt.mastery].name} with this car` elseif earn then `{pt.name}: win it on the Trophy Road` else `{pt.name} unlocks at level {pt.unlockLevel}`)
					return
				end
				pick({ pattern = id or false })
			end)
		end
	end

	if info.color then
		header(body, 5, "Colour")
		local dots = grid(body, 6, UDim2.fromOffset(32, 32), 8)
		local function dot(order: number, name: string, color: string, sel: boolean, premium: boolean, onTap: () -> ()): TextButton
			local d = Ui.new("TextButton", { Name = name, Text = "", AutoButtonColor = false, LayoutOrder = order, BackgroundColor3 = Color3.fromHex(color), ZIndex = 3, Parent = dots }, {
				Ui.round(),
				Ui.stroke(if sel then 3 else if premium then 2 else 1, if sel then Color3.fromHex("#ff9f1a") elseif premium then Color3.fromHex("#ffd54f") else Color3.fromHex("#90a4ae")),
			})
			Ui.new("Frame", { Name = "Ring", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = d }, { Ui.round(), Ui.stroke(2.5, Ui.WHITE) })
			d.Activated:Connect(onTap)
			return d
		end
		local match = dot(0, "match", if info.id == "rims" then "#cfd8dc" else car.color, not (mine and mine.color), false, function()
			pick({ color = false })
		end)
		Ui.text({ Text = "∅", TextSize = 14, TextColor3 = SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = match })
		for i, p in data.PAINTS do
			local locked = not open(info.id, p.color)
			local d = dot(i, p.color, p.color, mine ~= nil and mine.color == p.color, (p.bucks or 0) > 0, function()
				pick({ color = p.color })
			end)
			if locked then
				d.BackgroundTransparency = 0.35
				Ui.text({ Name = "Lock", Text = "🔒", TextSize = 11, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 6, 1, 6), Size = UDim2.fromOffset(14, 14), ZIndex = 3, Parent = d })
			end
		end
	end
	Ui.new("Frame", { LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, Parent = body })
end

return CustomShop
