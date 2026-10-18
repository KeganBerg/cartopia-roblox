--!strict
-- The garage's Paint tab (the web's PaintShop): tap a finish, colour or stripe to try it on the
-- car on the turntable, then buy the lot from the bar on top. Locked colours can be tried on too;
-- the bar then names the paint rival who has it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local mastery = require(Game.mastery) :: any
local paintRivals = require(Game.paintRivals) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint)
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)

local PaintShop = {}

local LINE = Ui.LINE
local SOFT = Color3.fromHex("#607d8b")

-- How a swatch shows each finish (the web's SHEEN): light and dark bands over the colour, top
-- left to bottom right.
local SHEEN: { [string]: { { number } } } = {
	gloss = { { 0, 0.4 }, { 0.32, 1 }, { 1, 1 } },
	matte = {},
	chrome = { { 0, 0.35 }, { 0.38, 1 }, { 0.55, 0.6 }, { 0.78, 1 }, { 1, 0.45 } },
	gold = { { 0, 0.45 }, { 0.45, 1 }, { 0.7, 0.65 }, { 1, 1 } },
	diamond = { { 0, 0.3 }, { 0.35, 0.85 }, { 0.5, 0.45 }, { 0.7, 0.85 }, { 1, 0.35 } },
	galaxy = { { 0, 1 }, { 0.5, 0.75 }, { 1, 1 } },
}

local function sheen(parent: GuiObject, finish: string)
	local bands: { { number } } = SHEEN[finish] or {}
	if #bands == 0 then
		return
	end
	local glow = Ui.new("Frame", { Name = "Sheen", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = parent.ZIndex, Parent = parent })
	local corner = parent:FindFirstChildOfClass("UICorner")
	if corner then
		Ui.new("UICorner", { CornerRadius = corner.CornerRadius, Parent = glow })
	end
	local keys = {}
	for _, b in bands do
		table.insert(keys, NumberSequenceKeypoint.new(b[1], b[2]))
	end
	Ui.new("UIGradient", { Rotation = 45, Transparency = NumberSequence.new(keys), Parent = glow })
	if finish == "galaxy" then
		-- A few stars.
		for _, at in { { 0.3, 0.3 }, { 0.7, 0.6 }, { 0.55, 0.2 } } do
			Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(at[1], at[2]), Size = UDim2.fromOffset(3, 3), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = parent.ZIndex, Parent = parent }, { Ui.round() })
		end
	end
end

local function header(parent: Instance, order: number, text: string, note: string?)
	local row = Ui.new("Frame", { Name = "H" .. order, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 26), BackgroundTransparency = 1, ZIndex = 3, Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	Ui.text({ Text = text, TextSize = 16, TextColor3 = LINE, LayoutOrder = 1, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = row })
	if note then
		Ui.text({ Text = note, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = SOFT, LayoutOrder = 2, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = row })
	end
end

local function grid(parent: Instance, order: number, cell: UDim2, pad: number): Frame
	return Ui.new("Frame", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3, Parent = parent }, {
		Ui.new("UIGridLayout", { CellSize = cell, CellPadding = UDim2.fromOffset(pad, pad), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }),
	})
end

-- A round colour swatch (.dot.big) with the white ring and grey edge, an orange ring when picked.
local function dot(parent: Instance, order: number, name: string, color: Color3, sel: boolean, premium: boolean, onTap: () -> ()): TextButton
	local d = Ui.new("TextButton", { Name = name, Text = "", AutoButtonColor = false, LayoutOrder = order, BackgroundColor3 = color, ZIndex = 3, Parent = parent }, {
		Ui.round(),
		Ui.stroke(if sel then 3 else if premium then 2 else 1, if sel then Color3.fromHex("#ff9f1a") elseif premium then Color3.fromHex("#ffd54f") else Color3.fromHex("#90a4ae")),
	})
	Ui.new("Frame", { Name = "Ring", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = d }, { Ui.round(), Ui.stroke(2.5, Ui.WHITE) })
	d.Activated:Connect(onTap)
	return d
end

-- `parent` is the detail card's space under the tabs; `job` is the paint job being tried (the
-- car's own when nothing is); `setJob(nil)` stops trying. `redraw` draws the page again.
function PaintShop.draw(parent: Instance, ctx: any, car: any, job: Paint.Job, setJob: (Paint.Job?) -> ())
	local s = store.useGame.getState()
	local gate = store.gateLevel(s)
	local tier = mastery.carClassTier(s.mastery, car.model)
	local now = Paint.jobOf(car)
	local function open(color: string): boolean
		return color == now.color or paintRivals.paintOpen(s, color)
	end
	local function pick(p: { [string]: any })
		local next: Paint.Job = { color = p.color or job.color, finish = p.finish or job.finish, stripe = if p.stripe ~= nil then p.stripe else job.stripe }
		setJob(if Paint.same(next, now) then nil else next)
	end
	local paintBy: { [string]: any } = {}
	for _, p in data.PAINTS do
		paintBy[p.color] = p
	end

	local body = Ui.scroller({ Name = "PaintShop", Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = parent })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

	-- The bar: what's being tried, Undo, and the price (or the rival who has a locked colour).
	if not Paint.same(job, now) then
		local bits = {}
		if job.finish ~= now.finish then
			table.insert(bits, data.finishDef(job.finish).name)
		end
		if job.color ~= now.color then
			table.insert(bits, if paintBy[job.color] then paintBy[job.color].name else "Custom colour")
		end
		if job.stripe ~= now.stripe then
			table.insert(bits, if job.stripe then "stripes" else "no stripes")
		end
		local bar = Ui.new("Frame", { Name = "TryBar", LayoutOrder = 1, Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = Color3.fromHex("#fff8e1"), ZIndex = 3, Parent = body }, {
			Ui.corner(12),
			Ui.stroke(1.5, Color3.fromHex("#ffcc80")),
		})
		local what = Ui.text({ Text = `Trying <b>{table.concat(bits, " · ")}</b>`, Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#37474f"), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -230, 1, 0), ZIndex = 3, Parent = bar })
		what.RichText = true
		local undo = Ui.new("TextButton", { Name = "Undo", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -140, 0.5, 0), Size = UDim2.fromOffset(52, 30), BackgroundTransparency = 1, ZIndex = 3, Parent = bar })
		Ui.text({ Text = "<u>Undo</u>", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = undo }).RichText = true
		undo.Activated:Connect(function()
			setJob(nil)
		end)
		local go = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(126, 32), Parent = bar }
		local lockedBy = if open(job.color) then nil else paintRivals.rivalForPaint(job.color)
		local _shadow, button
		if lockedBy then
			local first = string.split(lockedBy.name, " ")[1]
			_shadow, button = Ui.buy(go, `🏁 {lockedBy.icon} {first}`, "green", function()
				ctx.toast(`Beat {lockedBy.name} in the Race menu to win {paintBy[job.color].name}`)
				ctx.open("race")
			end, 14)
		elseif not open(job.color) then
			local p = paintBy[job.color]
			_shadow, button = Ui.buy(go, "🔒 Locked", "grey", function()
				ctx.toast(if p and p.earn then `{p.name}: {paintRivals.earnHint(job.color)}` else "That colour is locked")
			end, 14)
		else
			local cost = store.paintPrice(s, car, job)
			local parts = {}
			if cost.coins and cost.coins > 0 then
				table.insert(parts, `${Ui.commas(cost.coins)}`)
			end
			if cost.bucks and cost.bucks > 0 then
				table.insert(parts, `💎 {cost.bucks}`)
			end
			local price = if #parts > 0 then table.concat(parts, " + ") else "Free"
			if cost.free then
				price = "🎁 " .. price
			elseif cost.deal then
				price = "DEAL " .. price
			end
			local function buy()
				local ok = Remote.act("paintCar", car.uid, { color = job.color, finish = job.finish or "gloss", stripe = job.stripe or false })
				if ok then
					ctx.toast("Fresh paint! 🎨")
					setJob(nil)
				end
			end
			if cost.bucks and cost.bucks > 0 then
				_shadow, button = Ui.button(go, "ten", buy, { radius = 12, stroke = 2, drop = 2, dark = 0.2, strokeColor = Color3.fromHex("#4a148c"), text = price, textSize = 14, textShadow = 1.5 })
			else
				_shadow, button = Ui.buy(go, price, "green", buy, 14)
			end
		end
		button.Name = "Go"
		button.ZIndex = 3
	end

	-- Finishes: a chip of the colour in each one, its name, and its price or lock.
	header(body, 2, "Finish")
	local fins = grid(body, 3, UDim2.fromOffset(112, 74), 6)
	for i, f in data.FINISHES do
		local earn = if f.mastery then mastery.CLASS_TIERS[f.mastery] else nil
		local shut = earn ~= nil and tier < f.mastery and now.finish ~= f.id
		local locked = (gate < f.unlockLevel and now.finish ~= f.id) or shut
		local sel = job.finish == f.id
		local b = Ui.new("TextButton", { Name = f.id, Text = "", AutoButtonColor = false, LayoutOrder = i, BackgroundColor3 = Ui.WHITE, BackgroundTransparency = if locked then 0.45 else 0, ZIndex = 3, Parent = fins }, {
			Ui.corner(12),
			Ui.stroke(if sel then 2.5 else 1.5, if sel then Ui.BLUE else Color3.fromHex("#dfe5ea")),
		})
		local chip = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 7), Size = UDim2.fromOffset(34, 22), BackgroundColor3 = Paint.color(job.color, f.id), ZIndex = 3, Parent = b }, {
			Ui.corner(8),
			Ui.stroke(2, Ui.WHITE),
		})
		sheen(chip, f.id)
		Ui.text({ Text = f.name, TextSize = 14, TextColor3 = Color3.fromHex("#37474f"), TextTransparency = if locked then 0.45 else 0, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 18), ZIndex = 3, Parent = b })
		local note
		if shut then
			note = `🔒 {earn.icon}`
		elseif locked then
			note = `🔒 Level {f.unlockLevel}`
		elseif now.finish == f.id then
			note = "Yours"
		elseif earn then
			note = `{earn.icon} Free`
		else
			local deal = store.liveDeal(s, "paint", f.id)
			note = if deal then `<s>${Ui.commas(f.coins)}</s> <b>${Ui.commas(data.dealOffer(deal).now.coins)}</b>` else `${Ui.commas(f.coins)}`
		end
		local n = Ui.text({ Text = note, Body = true, TextSize = 12, TextColor3 = SOFT, TextTransparency = if locked then 0.3 else 0, Position = UDim2.fromOffset(0, 51), Size = UDim2.new(1, 0, 0, 16), ZIndex = 3, Parent = b })
		n.RichText = true
		b.Activated:Connect(function()
			if locked then
				ctx.toast(if shut then f.blurb else `{f.name} unlocks at level {f.unlockLevel}`)
				return
			end
			pick({ finish = f.id })
		end)
	end

	-- Colours: the chart, locked ones dimmed with a lock (won from paint rivals and prizes).
	header(body, 4, "Colour", `🎨 {paintRivals.paintsOpen(s)}/{paintRivals.PAINTS_TO_COLLECT}`)
	local dots = grid(body, 5, UDim2.fromOffset(32, 32), 8)
	for i, p in data.PAINTS do
		local locked = not open(p.color)
		local d = dot(dots, i, p.color, Paint.color(p.color, job.finish), p.color == job.color, (p.bucks or 0) > 0, function()
			pick({ color = p.color })
		end)
		sheen(d, job.finish or "gloss")
		if locked and p.color ~= job.color then
			d.BackgroundTransparency = 0.35
		end
		if locked then
			Ui.text({ Name = "Lock", Text = "🔒", TextSize = 11, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 6, 1, 6), Size = UDim2.fromOffset(14, 14), ZIndex = 3, Parent = d })
		end
	end

	-- Stripes: none, then each stripe colour shown as two bars down the car's colour.
	header(body, 6, "Racing stripes", `${data.STRIPE_COST}`)
	local stripes = grid(body, 7, UDim2.fromOffset(32, 32), 8)
	for i, st in data.STRIPES do
		local d = dot(stripes, i, if st then `stripe{i}` else "nostripe", Color3.fromHex(job.color), job.stripe == st, false, function()
			pick({ stripe = st })
		end)
		d.ClipsDescendants = true
		if st then
			for _, x in { 0.35, 0.55 } do
				Ui.new("Frame", { Position = UDim2.fromScale(x, 0), Size = UDim2.fromScale(0.1, 1), BackgroundColor3 = Color3.fromHex(st), BorderSizePixel = 0, ZIndex = 3, Parent = d })
			end
		else
			Ui.text({ Text = "∅", TextSize = 14, TextColor3 = SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = d })
		end
	end
	Ui.new("Frame", { LayoutOrder = 8, Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, Parent = body })
end

return PaintShop
