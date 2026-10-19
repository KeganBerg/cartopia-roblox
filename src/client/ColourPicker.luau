--!strict
-- Custom Colour (the web's ColourPicker.tsx): a rainbow dot at the end of a paint row that flies
-- out a colour picker. Locked until won (a legendary Diamond Crate prize); then any colour goes:
-- drag over the square for how bright and how strong, along the bar for the hue. The colour is
-- tried on the car when the finger lifts (the web tries it on as it moves; here the car on the
-- turntable is built again for each try-on). Used by the garage's Paint and Custom tabs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Ui)

local ColourPicker = {}

local GOLD = Color3.fromHex("#ffc94d")
local ACCENT = Color3.fromHex("#ff9f1a")
local INK = Color3.fromHex("#37474f")

export type Hsv = { number }

-- Hue (0-360), saturation and value (0-1) to and from #rrggbb (the web's lib/hsv.ts).
local function hex2(n: number): string
	return string.format("%02x", math.clamp(math.round(n * 255), 0, 255))
end
function ColourPicker.hsvToHex(hsv: Hsv): string
	local h, s, v = hsv[1], hsv[2], hsv[3]
	local function f(n: number): number
		local k = (n + h / 60) % 6
		return v - v * s * math.max(0, math.min(k, 4 - k, 1))
	end
	return `#{hex2(f(5))}{hex2(f(3))}{hex2(f(1))}`
end
function ColourPicker.hexToHsv(hex: string): Hsv
	local n = tonumber(hex:sub(2), 16) or 0
	local r, g, b = bit32.band(bit32.rshift(n, 16), 255) / 255, bit32.band(bit32.rshift(n, 8), 255) / 255, bit32.band(n, 255) / 255
	local max = math.max(r, g, b)
	local d = max - math.min(r, g, b)
	local h = 0
	if d > 0 then
		if max == r then
			h = math.fmod((g - b) / d, 6)
		elseif max == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
	end
	return { (h * 60 + 360) % 360, if max > 0 then d / max else 0, max }
end

local function isHex(c: any): boolean
	return type(c) == "string" and c:match("^#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$") ~= nil
end

-- The swatch (CUSTOM_PAINT.swatch, a white glow over a colour wheel): a rainbow sweep here.
local RAINBOW = { "#ff2d2d", "#ffd400", "#3cff3c", "#00e5ff", "#2d5bff", "#ff2dd2", "#ff2d2d" }
local HUES = { { 0, "#ff0000" }, { 0.17, "#ffff00" }, { 0.33, "#00ff00" }, { 0.5, "#00ffff" }, { 0.67, "#0000ff" }, { 0.83, "#ff00ff" }, { 1, "#ff0000" } }

local function rainbow(parent: GuiObject, glow: boolean)
	local keys = {}
	for i, c in RAINBOW do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#RAINBOW - 1), Color3.fromHex(c)))
	end
	parent.BackgroundColor3 = Ui.WHITE
	Ui.new("UIGradient", { Rotation = 45, Color = ColorSequence.new(keys), Parent = parent })
	if glow then
		Ui.new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.25, ZIndex = parent.ZIndex, Parent = parent }, { Ui.round() })
	end
end

-- A knob for the square and the bar: a ring of white with a dark edge, filled with the colour.
local function knob(parent: Instance, color: Color3): Frame
	local k = Ui.new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = 6, Parent = parent }, { Ui.round() })
	Ui.new("Frame", { Name = "Fill", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -3, 1, -3), BackgroundColor3 = color, ZIndex = 6, Parent = k }, {
		Ui.round(),
		Ui.stroke(3, Ui.WHITE),
	})
	return k
end

-- Kept while the game runs, as the web's component state: whether each picker is open (nil:
-- open when a custom colour is on) and where its pointer is.
local opened: { [string]: boolean } = {}
local hsvOf: { [string]: Hsv } = {}

-- The dot into the paint row `dots` (at `order`), and its picker into the list `list` at
-- `flyOrder`, under the row. `color` is the colour on try-on; `custom` says it's off the chart,
-- so the dot shows it picked. `onPick(hex)` tries a colour on.
function ColourPicker.draw(dots: Instance, order: number, list: Instance, flyOrder: number, opts: { key: string, color: string, custom: boolean, onPick: (string) -> (), ctx: any })
	local s = store.useGame.getState()
	local owned = data.hasCustomPaint(s) == true
	local key = opts.key
	local open = opened[key]
	if open == nil then
		open = owned and opts.custom
	end
	local hsv: Hsv = hsvOf[key] or ColourPicker.hexToHsv(if isHex(opts.color) then opts.color else data.CUSTOM_PAINT_SHOW)
	-- Follow a colour picked elsewhere (a chart dot), keeping the hue when it's a grey.
	if isHex(opts.color) and ColourPicker.hsvToHex(hsv) ~= opts.color then
		local nxt = ColourPicker.hexToHsv(opts.color)
		hsv = if nxt[2] > 0 then nxt else { hsv[1], nxt[2], nxt[3] }
	end
	hsvOf[key] = hsv
	local picked = owned and opts.custom

	local dot = Ui.new("TextButton", { Name = "CustomColour", Text = "", AutoButtonColor = false, LayoutOrder = order, ZIndex = 3, Parent = dots }, { Ui.round() })
	rainbow(dot, not picked)
	local ring = Ui.stroke(2, GOLD)
	ring.Parent = dot
	if picked then
		Ui.new("Frame", { Name = "Now", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.84, 0.84), BackgroundColor3 = Color3.fromHex(opts.color), ZIndex = 3, Parent = dot }, { Ui.round() })
	end
	if not owned then
		dot.BackgroundTransparency = 0.15
		Ui.text({ Name = "Lock", Text = "🔒", TextSize = 11, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 6, 1, 6), Size = UDim2.fromOffset(14, 14), ZIndex = 4, Parent = dot })
	end
	local function ringFor(isOpen: boolean)
		ring.Thickness = if picked or isOpen then 3 else 2
		ring.Color = if picked or isOpen then ACCENT else GOLD
	end
	ringFor(open)

	local fly = Ui.new("Frame", { Name = "CustomColourPicker", LayoutOrder = flyOrder, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Ui.WHITE, Visible = open, ZIndex = 3, Parent = list }, {
		Ui.corner(14),
		Ui.stroke(2.5, GOLD),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }),
	})
	dot.Activated:Connect(function()
		local now = not fly.Visible
		opened[key] = now
		fly.Visible = now
		ringFor(now)
		if now and owned and not opts.custom then
			opts.onPick(ColourPicker.hsvToHex(hsv))
		end
	end)

	if not owned then
		-- Locked: what it is and where it comes from, and the way to the crates.
		local big = Ui.new("Frame", { Name = "Big", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(44, 44), ZIndex = 3, Parent = fly }, { Ui.round(), Ui.stroke(2, GOLD) })
		rainbow(big, true)
		Ui.text({ Text = "🔒", TextSize = 18, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = big })
		Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = fly })
		Ui.text({ Text = data.CUSTOM_PAINT.name, TextSize = 16, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(54, 3), Size = UDim2.new(1, -170, 0, 20), ZIndex = 3, Parent = fly })
		Ui.text({ Text = "★ Legendary · 💎 Diamond", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex("#b7791f"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(54, 23), Size = UDim2.new(1, -170, 0, 18), ZIndex = 3, Parent = fly })
		local _, go = Ui.button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 2), Size = UDim2.fromOffset(104, 34), Parent = fly }, "ten", function()
			opts.ctx.open("crates")
		end, { radius = 12, stroke = 2, drop = 2, dark = 0.2, strokeColor = Color3.fromHex("#4a148c"), text = "📦 Crates", textSize = 14, textShadow = 1.5 })
		go.Name = "Crates"
		go.ZIndex = 3
		return
	end

	Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = fly })
	local hex = ColourPicker.hsvToHex(hsv)
	-- The square: across from white to the hue, down from bright to black.
	local sv = Ui.new("TextButton", { Name = "SV", Text = "", AutoButtonColor = false, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = Color3.fromHex(ColourPicker.hsvToHex({ hsv[1], 1, 1 })), ZIndex = 3, Parent = fly }, { Ui.corner(10) })
	Ui.new("Frame", { Name = "White", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = sv }, {
		Ui.corner(10),
		Ui.new("UIGradient", { Transparency = NumberSequence.new(0, 1) }),
	})
	Ui.new("Frame", { Name = "Black", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 5, Parent = sv }, {
		Ui.corner(10),
		Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(0, 0, 0)), Transparency = NumberSequence.new(1, 0) }),
	})
	local svKnob = knob(sv, Color3.fromHex(hex))
	-- The bar: every hue.
	local hue = Ui.new("TextButton", { Name = "Hue", Text = "", AutoButtonColor = false, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = fly }, { Ui.corner(13) })
	local hk = {}
	for _, h in HUES do
		table.insert(hk, ColorSequenceKeypoint.new(h[1], Color3.fromHex(h[2])))
	end
	Ui.new("UIGradient", { Color = ColorSequence.new(hk), Parent = hue })
	local hueKnob = knob(hue, Color3.fromHex(hex))
	-- What it is now: a dot of it and its code.
	local nowRow = Ui.new("Frame", { Name = "Now", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, ZIndex = 3, Parent = fly })
	local nowDot = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 1, 0.5, 0), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromHex(hex), ZIndex = 3, Parent = nowRow }, {
		Ui.round(),
		Ui.stroke(2, Ui.WHITE),
	})
	Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(32, 32), BackgroundTransparency = 1, ZIndex = 3, Parent = nowRow }, { Ui.round(), Ui.stroke(1, Color3.fromHex("#90a4ae")) })
	local nowText = Ui.text({ Name = "Hex", Text = string.upper(hex), TextSize = 16, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -40, 1, 0), ZIndex = 3, Parent = nowRow })

	local function show()
		local h = ColourPicker.hsvToHex(hsv)
		local c = Color3.fromHex(h)
		sv.BackgroundColor3 = Color3.fromHex(ColourPicker.hsvToHex({ hsv[1], 1, 1 }))
		svKnob.Position = UDim2.fromScale(hsv[2], 1 - hsv[3])
		hueKnob.Position = UDim2.fromScale(hsv[1] / 360, 0.5)
		for _, k in { svKnob, hueKnob } do
			(k:FindFirstChild("Fill") :: Frame).BackgroundColor3 = c
		end
		nowDot.BackgroundColor3 = c
		nowText.Text = string.upper(h)
	end
	show()

	-- A drag over the square or the bar: the knob follows the finger (or the mouse) and the colour
	-- goes on the car when it lifts. The list doesn't scroll meanwhile.
	local function drag(area: GuiObject, at: (number, number) -> ())
		area.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
				return
			end
			local scroller = area:FindFirstAncestorWhichIsA("ScrollingFrame")
			local could = scroller and scroller.ScrollingEnabled
			if scroller then
				scroller.ScrollingEnabled = false
			end
			local function move(p: Vector3)
				local x = math.clamp((p.X - area.AbsolutePosition.X) / math.max(1, area.AbsoluteSize.X), 0, 1)
				local y = math.clamp((p.Y - area.AbsolutePosition.Y) / math.max(1, area.AbsoluteSize.Y), 0, 1)
				at(x, y)
				hsvOf[key] = hsv
				show()
			end
			move(input.Position)
			local moved, ended
			moved = UserInputService.InputChanged:Connect(function(i: InputObject)
				if i == input or (kind == Enum.UserInputType.MouseButton1 and i.UserInputType == Enum.UserInputType.MouseMovement) then
					move(i.Position)
				end
			end)
			ended = UserInputService.InputEnded:Connect(function(i: InputObject)
				if i == input or (kind == Enum.UserInputType.MouseButton1 and i.UserInputType == kind) then
					moved:Disconnect()
					ended:Disconnect()
					if scroller and could then
						scroller.ScrollingEnabled = true
					end
					local h = ColourPicker.hsvToHex(hsv)
					if h ~= opts.color then
						opts.onPick(h)
					end
				end
			end)
		end)
	end
	drag(sv, function(x: number, y: number)
		hsv = { hsv[1], x, 1 - y }
	end)
	drag(hue, function(x: number)
		hsv = { x * 359.9, if hsv[2] > 0 then hsv[2] else 0.85, if hsv[3] > 0 then hsv[3] else 0.9 }
	end)
end

return ColourPicker
