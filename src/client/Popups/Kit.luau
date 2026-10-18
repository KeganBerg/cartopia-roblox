--!strict
-- What the pop-ups share: the queue that shows them one at a time, and the web's splash pieces
-- (index.css .lvl-overlay, .lvl, .lvl-chip, .prize).
--
-- The queue waits while the race screen is up (it turns the HUD's ScreenGui off) and shows the
-- next pop-up once the town is back. A pop-up is pushed under a key (one of each at a time) with a
-- rank (lower shows first: the level-up splash before prize cards, as the web stacks them) and a
-- show function that builds it and calls done when it closes.

local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Parent.Ui)
local Icons = require(script.Parent.Parent.Icons)
local Remote = require(script.Parent.Parent.Remote)

local Kit = {}

local LINE = Ui.LINE
Kit.PANEL = Color3.fromHex("#fffaf0")
Kit.ORANGE = Color3.fromHex("#ff8a00")
Kit.GOLD = Color3.fromHex("#ffca28")
Kit.SUB = Color3.fromHex("#546e7a")

type Item = { key: string, rank: number, n: number, show: (done: () -> ()) -> (), when: (() -> boolean)? }

local items: { Item } = {}
local showing: string? = nil
local ctxRef: any = nil
local pushes = 0
local watching = false

local function hudGui(): ScreenGui?
	local root = ctxRef and ctxRef.gui
	return root and root:FindFirstAncestorOfClass("ScreenGui")
end

-- The race screen hides the HUD; pop-ups wait for it to come back.
function Kit.hudUp(): boolean
	local g = hudGui()
	return g == nil or g.Enabled
end

local pump: () -> ()
pump = function()
	if showing or #items == 0 or not ctxRef then
		return
	end
	local g = hudGui()
	if g and not g.Enabled then
		if not watching then
			watching = true
			local c: RBXScriptConnection
			c = g:GetPropertyChangedSignal("Enabled"):Connect(function()
				if g.Enabled then
					c:Disconnect()
					watching = false
					pump()
				end
			end)
		end
		return
	end
	table.sort(items, function(a, b)
		if a.rank ~= b.rank then
			return a.rank < b.rank
		end
		return a.n < b.n
	end)
	for i, it in items do
		if it.when == nil or it.when() then
			table.remove(items, i)
			showing = it.key
			local finished = false
			local ok, err = pcall(it.show, function()
				if finished then
					return
				end
				finished = true
				showing = nil
				task.defer(pump)
			end)
			if not ok then
				warn(`[Cartopia] pop-up {it.key}: {err}`)
				showing = nil
			end
			return
		end
	end
end

-- Queues a pop-up. Returns false when one under that key is already queued or showing.
function Kit.push(ctx: any, key: string, rank: number, show: (done: () -> ()) -> (), when: (() -> boolean)?): boolean
	ctxRef = ctxRef or ctx
	if showing == key then
		return false
	end
	for _, it in items do
		if it.key == key then
			return false
		end
	end
	pushes += 1
	table.insert(items, { key = key, rank = rank, n = pushes, show = show, when = when })
	-- A moment later, so everything one snapshot brought is queued and the first in rank shows.
	task.delay(0, pump)
	return true
end

-- The key showing now, or nil.
function Kit.showing(): string?
	return showing
end

-- Try again (a pop-up whose `when` said not yet).
function Kit.pump()
	pump()
end

Remote.changed:Connect(function()
	task.delay(0, pump)
end)

-- Runs once with the HUD: keeps the HUD's ctx so the queue can find its ScreenGui, and looks
-- again every half second (the HUD coming back after a race, a menu closing).
function Kit.start(ctx: any)
	ctxRef = ctx
	pump()
	while true do
		task.wait(0.5)
		pump()
	end
end

-- A menu is open over the town (Ui.panel and the Cars page both name their overlay "Panel").
function Kit.menuOpen(ctx: any): boolean
	return ctx.gui:FindFirstChild("Panel") ~= nil
end

-- ── Pieces ──────────────────────────────────────────────────────────────────────────────────────

-- The dimmed screen behind a splash (.lvl-overlay): it takes taps so they don't reach the town.
-- rays: the slowly turning light rays behind the level-up.
function Kit.overlay(ctx: any, rays: boolean?, onTap: (() -> ())?): TextButton
	local o = Ui.new("TextButton", {
		Name = "Popup",
		Text = "",
		AutoButtonColor = false,
		ZIndex = 40,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromHex("#0a1428"),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Parent = ctx.gui,
	})
	o.Selectable = false
	if onTap then
		o.Activated:Connect(onTap)
	end
	if rays then
		local spin = Ui.new("Frame", { Name = "Rays", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Parent = o })
		for i = 0, 7 do
			Ui.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromOffset(1500, 90),
				Rotation = i * 22.5,
				BackgroundColor3 = Color3.fromHex("#ffecb3"),
				BorderSizePixel = 0,
				Parent = spin,
			}, {
				Ui.new("UIGradient", {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.3, 1),
						NumberSequenceKeypoint.new(0.5, 0.72),
						NumberSequenceKeypoint.new(0.7, 1),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			})
		end
		pcall(function()
			TweenService:Create(spin, TweenInfo.new(24, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 }):Play()
		end)
	end
	return o
end

-- The splash card (.lvl / .prize): the web's cream panel with a navy outline, a gold ring inside
-- it and a drop shadow. Centred in the overlay; size it with the returned shadow.
function Kit.card(overlay: Instance, w: number, h: number, yOffset: number?): (Frame, TextButton)
	local shadow, face = Ui.shadowed({
		Name = "Card",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, yOffset or 0),
		Size = UDim2.fromOffset(w, h),
		ZIndex = 2,
		Parent = overlay,
	}, { radius = 24, stroke = 4, drop = 8, dark = 0.35, color = Kit.PANEL, class = "TextButton" })
	face.Selectable = false
	Ui.new("Frame", {
		Name = "Ring",
		Position = UDim2.fromOffset(2, 2),
		Size = UDim2.new(1, -4, 1, -4),
		BackgroundTransparency = 1,
		Parent = face,
	}, { Ui.corner(22), Ui.stroke(4, Kit.GOLD) })
	return shadow, face
end

-- The big orange title (.lvl-title, .prize h2), centred at y.
function Kit.title(parent: Instance, text: string, y: number, size: number?, color: Color3?): TextLabel
	return Ui.text({
		Name = "Title",
		Text = text,
		TextSize = size or 40,
		TextColor3 = color or Kit.ORANGE,
		Position = UDim2.fromOffset(10, y),
		Size = UDim2.new(1, -20, 0, (size or 40) + 6),
		TextWrapped = true,
		Stroke = 1.5,
		StrokeColor = LINE,
		Shadow = if (size or 40) >= 30 then 4 else 3,
		Parent = parent,
	})
end

-- A line of body text (.lvl-sub), centred at y.
function Kit.line(parent: Instance, text: string, y: number, size: number?, color: Color3?, display: boolean?): TextLabel
	return Ui.text({
		Text = text,
		Body = not display,
		Weight = "heavy",
		TextSize = size or 16,
		TextColor3 = color or Kit.SUB,
		Position = UDim2.fromOffset(10, y),
		Size = UDim2.new(1, -20, 0, (size or 16) + 6),
		TextWrapped = true,
		Parent = parent,
	})
end

export type Chip = { text: string, coin: boolean?, color: string? }

-- A row of navy reward chips (.lvl-chip), centred at y. Returns the row's height.
function Kit.chips(parent: Instance, y: number, chips: { Chip }, size: number?): number
	local ts = size or 15
	local h = ts + 13
	local widths = {}
	local total = 0
	for i, c in chips do
		local w = Ui.textWidth(c.text, ts) + 20 + (if c.coin then h - 4 else 0)
		widths[i] = w
		total += w + (if i > 1 then 6 else 0)
	end
	local row = Ui.new("Frame", { Name = "Chips", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(total, h), BackgroundTransparency = 1, Parent = parent })
	local x = 0
	for i, c in chips do
		local w = widths[i]
		local chip = Ui.new("Frame", { Name = "Chip", Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Ui.WHITE, Parent = row }, {
			Ui.round(),
			Ui.stroke(2, LINE),
			if c.color then Ui.gradient(c.color, c.color) else Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]),
		})
		local tx = 10
		if c.coin then
			Icons.draw("coin", chip, h - 6, nil, nil, UDim2.fromOffset(3, 3))
			tx = h
		end
		Ui.text({ Text = c.text, TextSize = ts, Position = UDim2.fromOffset(tx, 0), Size = UDim2.new(1, -tx - 10, 1, 0), Shadow = 1.5, ShadowColor = Ui.BLACK, ShadowTransparency = 0.6, Parent = chip })
		x += w + 6
	end
	return h
end

-- The web's .buy button, centred at y. kind: "green" or "garage" (the blue .alt).
function Kit.button(parent: Instance, text: string, x: number, y: number, w: number, h: number, kind: string?, onClick: () -> (), size: number?): Frame
	local shadow = Ui.buy({ Name = text, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, y), Size = UDim2.fromOffset(w, h), Parent = parent }, text, kind, onClick, size or 20)
	return shadow
end

-- Buttons side by side, centred at y (.prize .row).
function Kit.buttons(parent: Instance, y: number, list: { { text: string, kind: string?, go: () -> () } }, h: number?)
	local bh = h or 44
	local widths = {}
	local total = 0
	for i, b in list do
		widths[i] = math.max(110, Ui.textWidth(b.text, 19) + 40)
		total += widths[i] + (if i > 1 then 10 else 0)
	end
	local x = -total / 2
	for i, b in list do
		Kit.button(parent, b.text, x + widths[i] / 2, y, widths[i], bh, b.kind, b.go, 19)
		x += widths[i] + 10
	end
end

-- A white card for a shop item (.card.lvl-item) at x, y.
function Kit.itemCard(parent: Instance, x: number, y: number, w: number, h: number, button: boolean): (Frame, any)
	local shadow, face = Ui.shadowed({ Name = "Item", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), Parent = parent }, {
		radius = 12,
		stroke = 1.5,
		drop = 2,
		dark = 1,
		color = Ui.WHITE,
		strokeColor = Ui.EDGE,
		class = if button then "TextButton" else "Frame",
	})
	shadow.BackgroundColor3 = Ui.EDGE
	shadow.BackgroundTransparency = 0
	return shadow, face
end

-- A car picture as the web's CarThumb: the car in a colour (and its look, when it's theirs).
function Kit.carThumb(model: string, size: UDim2, color: string, car: any?, look: any?): GuiObject
	local Thumb = require(script.Parent.Parent.Thumb) :: any
	local l = look or {}
	return Thumb.car(model, size, { color = color, finish = l.finish or (car and car.finish), stripe = car and car.stripe }, nil, car and car.mods, l.panels)
end

return Kit
