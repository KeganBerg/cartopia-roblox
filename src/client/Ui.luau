--!strict
-- Building blocks for Cartopia's screens, in the web game's glossy cartoon style (theme.css):
-- navy pills with dark outlines, bevelled colour buttons and white sheets.

local Ui = {}

Ui.INK = Color3.fromHex("#1b2a4a")
Ui.LINE = Color3.fromHex("#14213d")
Ui.SHEET = Color3.fromHex("#e8f1fc")
Ui.SEG = Color3.fromHex("#d3e2f5")
Ui.BLUE = Color3.fromHex("#2f7ff0")
Ui.FONT = Enum.Font.FredokaOne
Ui.BODY = Enum.Font.GothamBold

-- Button colours from theme.css (top, bottom of the gradient).
Ui.COLORS = {
	shop = { "#ffb547", "#f07b0e" },
	showroom = { "#ff6b6b", "#d6283b" },
	garage = { "#5aa9ff", "#2263d6" },
	edit = { "#ffd84a", "#f0a400" },
	green = { "#8ef05c", "#2fae35" },
	navy = { "#34507f", "#1f3358" },
	white = { "#ffffff", "#e3ecf7" },
	grey = { "#cfd8dc", "#90a4ae" },
}

function Ui.new(class: string, props: { [string]: any }, children: { any }?): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	for _, c in (children or {}) :: { any } do
		c.Parent = inst
	end
	if props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Ui.corner(r: number): any
	return Ui.new("UICorner", { CornerRadius = UDim.new(0, r) })
end

function Ui.stroke(thickness: number, color: Color3?): any
	return Ui.new("UIStroke", { Thickness = thickness, Color = color or Ui.LINE, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

function Ui.gradient(top: string, bottom: string): any
	return Ui.new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromHex(top), Color3.fromHex(bottom)),
	})
end

-- Bold white lettering with the dark outline the web game uses on buttons and the town name.
function Ui.label(props: { [string]: any }): TextLabel
	local l = Ui.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = Ui.FONT,
		TextColor3 = Color3.new(1, 1, 1),
		TextScaled = false,
		TextSize = 18,
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "NoStroke" then
			(l :: any)[k] = v
		end
	end
	if not props.NoStroke then
		Ui.new("UIStroke", { Thickness = 1.5, Color = Ui.LINE, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = l })
	end
	l.Parent = props.Parent
	return l
end

-- A bevelled button. colors: a key of Ui.COLORS. Returns the button; onClick runs on press.
function Ui.button(props: { [string]: any }, colors: string, text: string, onClick: () -> ()): TextButton
	local c = Ui.COLORS[colors] or Ui.COLORS.green
	local dark = colors == "white" or colors == "grey" or colors == "edit"
	local b = Ui.new("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = Color3.new(1, 1, 1),
		Font = Ui.FONT,
		Text = text,
		TextSize = 20,
		TextColor3 = if dark then Ui.LINE else Color3.new(1, 1, 1),
	}, { Ui.corner(14), Ui.stroke(3), Ui.gradient(c[1], c[2]) })
	if not dark then
		Ui.new("UIStroke", { Thickness = 1.5, Color = Ui.LINE, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual, Parent = b })
	end
	for k, v in props do
		if k ~= "Parent" then
			(b :: any)[k] = v
		end
	end
	b.Activated:Connect(onClick)
	b.Parent = props.Parent
	return b
end

-- A navy pill (coins, gems, parts): icon text on the left, value on the right.
function Ui.pill(parent: Instance, icon: string, order: number): TextLabel
	local f = Ui.new("Frame", {
		Size = UDim2.fromOffset(150, 34),
		BackgroundColor3 = Color3.new(1, 1, 1),
		LayoutOrder = order,
		Parent = parent,
	}, { Ui.corner(17), Ui.stroke(2.5), Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]) })
	Ui.label({ Text = icon, Size = UDim2.fromOffset(34, 34), TextSize = 20, NoStroke = true, Parent = f })
	return Ui.label({ Name = "Value", Text = "0", Size = UDim2.new(1, -44, 1, 0), Position = UDim2.fromOffset(36, 0), TextXAlignment = Enum.TextXAlignment.Left, TextSize = 20, Parent = f })
end

-- A sheet (the web game's popup panel): coloured header with a title and a close button, and a
-- body to fill. Returns the outer frame and the body.
function Ui.sheet(parent: Instance, title: string, colors: string, size: UDim2, onClose: () -> ()): (Frame, Frame)
	local c = Ui.COLORS[colors] or Ui.COLORS.shop
	local f = Ui.new("Frame", {
		Name = title,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = size,
		BackgroundColor3 = Ui.SHEET,
		Parent = parent,
	}, { Ui.corner(18), Ui.stroke(3), Ui.new("UISizeConstraint", { MaxSize = Vector2.new(980, 640) }) })
	local head = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Color3.new(1, 1, 1), Parent = f }, { Ui.corner(18), Ui.gradient(c[1], c[2]) })
	-- Square off the header's bottom corners.
	Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -18), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = head }, { Ui.gradient(c[2], c[2]) })
	Ui.label({ Text = title, TextSize = 28, Size = UDim2.new(1, -120, 1, 0), Position = UDim2.fromOffset(18, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = head })
	Ui.button({ Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -48, 0, 6), TextSize = 22 }, "white", "✕", onClose).Parent = head
	local body = Ui.new("Frame", { Name = "Body", BackgroundTransparency = 1, Position = UDim2.fromOffset(14, 62), Size = UDim2.new(1, -28, 1, -74), Parent = f })
	return f, body
end

-- Short counters, as the web game's compact() (ui/format.ts): 9,999 / 52.6K / 1.2M.
local UNITS = { "", "K", "M", "B", "T", "Q" }
function Ui.commas(v: number): string
	local s = tostring(math.floor(math.abs(v)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then
		out = out:sub(2)
	end
	return (if v < 0 then "-" else "") .. out
end

function Ui.compact(v: number): string
	local sign = if v < 0 then "-" else ""
	local a = math.abs(math.floor(v))
	if a < 10000 then
		return sign .. Ui.commas(a)
	end
	local i = 1
	while a >= 1000 and i < #UNITS do
		a /= 1000
		i += 1
	end
	local d = if a < 100 then 1 else 0
	local f = 10 ^ d
	local r = math.floor(a * f) / f
	local text = string.format(`%.{d}f`, r):gsub("%.0$", "")
	return sign .. text .. UNITS[i]
end

-- m:ss or h:mm:ss for job timers.
function Ui.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h, m = s // 3600, (s // 60) % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s % 60)
	end
	return string.format("%d:%02d", m, s % 60)
end

return Ui
