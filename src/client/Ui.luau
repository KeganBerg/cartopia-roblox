--!strict
-- Building blocks for Cartopia's screens, in the web game's glossy cartoon style (theme.css):
-- navy pills and bevelled colour buttons with dark outlines and a drop shadow under them, white
-- display lettering outlined in navy, and light blue sheets with a blue title bar.
--
-- Sizes are the web game's CSS pixels at 1280x800; the HUD scales the whole screen down on
-- smaller displays (Hud.luau), so these stay as they are on the web.

local Icons = require(script.Parent.Icons)

local Ui = {}

Ui.INK = Color3.fromHex("#1b2a4a")
Ui.LINE = Color3.fromHex("#14213d")
Ui.SHEET = Color3.fromHex("#e8f1fc")
Ui.SEG = Color3.fromHex("#d3e2f5")
Ui.EDGE = Color3.fromHex("#c6d7ee")
Ui.TAB_EDGE = Color3.fromHex("#b9cde8")
Ui.MUTED = Color3.fromHex("#4a6283")
Ui.BLUE = Color3.fromHex("#2f6fd6")
Ui.WHITE = Color3.new(1, 1, 1)
Ui.BLACK = Color3.new(0, 0, 0)

-- The web game's display face is Lilita One, which Roblox doesn't have; Fredoka One is Roblox's
-- closest rounded heavy face. Body text is Nunito, as on the web.
Ui.DISPLAY = Font.fromEnum(Enum.Font.FredokaOne)
Ui.BODY = Font.new(Font.fromEnum(Enum.Font.Nunito).Family, Enum.FontWeight.ExtraBold)
Ui.HEAVY = Font.new(Font.fromEnum(Enum.Font.Nunito).Family, Enum.FontWeight.Heavy)

-- Gradients from theme.css (top, bottom).
Ui.COLORS = {
	shop = { "#ffb547", "#f07b0e" },
	crates = { "#4fd1c5", "#1b8f86" },
	showroom = { "#ff6b6b", "#d6283b" },
	garage = { "#5aa9ff", "#2263d6" },
	edit = { "#ffd84a", "#f0a400" },
	green = { "#8ef05c", "#2fae35" },
	navy = { "#34507f", "#1f3358" },
	head = { "#5aa9ff", "#2263d6" },
	red = { "#ff6b6b", "#d6283b" },
	tab = { "#ffd84a", "#ffa41a" },
	plus = { "#7ee05a", "#2fa52f" },
	menu = { "#ffd43b", "#ff9f1a" },
	broke = { "#ff8a8a", "#d6283b" },
	white = { "#ffffff", "#e3ecf7" },
	grey = { "#eceff1", "#eceff1" },
	gold = { "#ffe066", "#f0a400" },
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

function Ui.round(): any
	return Ui.new("UICorner", { CornerRadius = UDim.new(0.5, 0) })
end

-- An outline round the box (CSS border); Roblox draws it outside the box.
function Ui.stroke(thickness: number, color: Color3?, transparency: number?): any
	return Ui.new("UIStroke", { Thickness = thickness, Color = color or Ui.LINE, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

-- An outline round the letters (-webkit-text-stroke with paint-order: stroke).
function Ui.textStroke(thickness: number, color: Color3?, transparency: number?): any
	return Ui.new("UIStroke", { Thickness = thickness, Color = color or Ui.LINE, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

-- A two-colour sequence from hex strings, with explicit keypoints (the two-argument constructor
-- isn't in every runtime the previews use).
function Ui.seq(top: string, bottom: string): ColorSequence
	return ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromHex(top)), ColorSequenceKeypoint.new(1, Color3.fromHex(bottom)) })
end

-- Top-to-bottom gradient. `at` makes it a hard split there (the fuel bar, the white buttons).
function Ui.gradient(top: string, bottom: string, at: number?): any
	local a, b = Color3.fromHex(top), Color3.fromHex(bottom)
	local seq = if at
		then ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(at, a), ColorSequenceKeypoint.new(at + 0.001, b), ColorSequenceKeypoint.new(1, b) })
		else ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b) })
	return Ui.new("UIGradient", { Rotation = 90, Color = seq })
end

function Ui.colors(name: string): { string }
	return Ui.COLORS[name] or Ui.COLORS.green
end

-- Text. Extra props: Body (Nunito instead of the display face), Weight ("heavy"), Stroke (outline
-- thickness), StrokeColor, StrokeTransparency, Shadow (a drop shadow that many px down, in the
-- outline colour: the web's text-shadow 0 Npx 0). A shadowed label is the shadow, with the letters
-- in a child named Face on top; change its text with Ui.setText.
local OWN = { Body = true, Weight = true, Stroke = true, StrokeColor = true, StrokeTransparency = true, Shadow = true, ShadowColor = true, ShadowTransparency = true, Parent = true }
function Ui.text(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = if props.Body then (if props.Weight == "heavy" then Ui.HEAVY else Ui.BODY) else Ui.DISPLAY
	l.TextColor3 = Ui.WHITE
	l.TextSize = 16
	for k, v in props do
		if not OWN[k] then
			(l :: any)[k] = v
		end
	end
	local face: TextLabel? = nil
	if props.Shadow then
		local f = l:Clone()
		f.Name = "Face"
		f.AnchorPoint = Vector2.zero
		f.Position = UDim2.fromOffset(0, -props.Shadow)
		f.Size = UDim2.fromScale(1, 1)
		f.AutomaticSize = Enum.AutomaticSize.None
		f.LayoutOrder = 0
		f.Parent = l
		face = f
		l.TextColor3 = props.ShadowColor or props.StrokeColor or Ui.LINE
		l.TextTransparency = props.ShadowTransparency or 0
	end
	if props.Stroke then
		Ui.textStroke(props.Stroke, props.StrokeColor, props.StrokeTransparency).Parent = l
		if face then
			Ui.textStroke(props.Stroke, props.StrokeColor, props.StrokeTransparency).Parent = face
		end
	end
	l.Parent = props.Parent
	return l
end

-- Sets a label's text, and its letters' too when it's shadowed. Skips unchanged text so the
-- refresh loop never touches labels that didn't change.
function Ui.setText(l: TextLabel, text: string)
	if l.Text == text then
		return
	end
	l.Text = text
	local face = l:FindFirstChild("Face")
	if face and face:IsA("TextLabel") then
		face.Text = text
	end
end

function Ui.setColor(l: TextLabel, color: Color3)
	local face = l:FindFirstChild("Face")
	if face and face:IsA("TextLabel") then
		face.TextColor3 = color
	else
		l.TextColor3 = color
	end
end

-- A face with the web's drop shadow under it (box-shadow: 0 Npx 0 rgba(0,0,0,a)). The shadow is
-- the frame that's laid out; the face sits on it, `drop` px higher. Returns shadow, face.
-- opts: radius, stroke (outline px), drop, dark (shadow opacity), class ("TextButton" for a
-- button face), colors (a gradient name) or color, strokeColor.
function Ui.shadowed(props: { [string]: any }, opts: { [string]: any }): (Frame, any)
	local r = opts.radius or 12
	local th = opts.stroke or 0
	local drop = opts.drop or 3
	local shadow = Ui.new("Frame", {
		BackgroundColor3 = Ui.BLACK,
		BackgroundTransparency = 1 - (opts.dark or 0.35),
		BorderSizePixel = 0,
	}, { Ui.new("UICorner", { CornerRadius = UDim.new(0, r) }) })
	if th > 0 then
		Ui.stroke(th, Ui.BLACK, 1 - (opts.dark or 0.35)).Parent = shadow
	end
	for k, v in props do
		if k ~= "Parent" then
			(shadow :: any)[k] = v
		end
	end
	local face = Ui.new(opts.class or "Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, -drop),
		BorderSizePixel = 0,
		BackgroundColor3 = if opts.colors then Ui.WHITE else (opts.color or Ui.WHITE),
	}, { Ui.new("UICorner", { CornerRadius = UDim.new(0, r) }) })
	if face:IsA("TextButton") then
		face.Text = ""
		face.AutoButtonColor = false
	end
	if opts.colors then
		local c = Ui.colors(opts.colors)
		Ui.gradient(c[1], c[2], opts.split).Parent = face
	end
	if th > 0 then
		Ui.stroke(th, opts.strokeColor or Ui.LINE).Parent = face
	end
	face.Parent = shadow
	shadow.Parent = props.Parent
	return shadow, face
end

-- The glossy bevel inside a button: a light line along the top and a darker band along the bottom
-- (the web's inset box-shadows).
function Ui.bevel(face: GuiObject, radius: number, top: number?, bottom: number?)
	local t = top or 0.55
	local b = bottom or 0.82
	Ui.new("Frame", {
		Name = "Gloss",
		ZIndex = 0,
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.WHITE,
		BackgroundTransparency = t,
		Position = UDim2.fromOffset(math.floor(radius * 0.6), 1),
		Size = UDim2.new(1, -math.floor(radius * 1.2), 0, 3),
		Parent = face,
	}, { Ui.round() })
	Ui.new("Frame", {
		Name = "Shade",
		ZIndex = 0,
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.BLACK,
		BackgroundTransparency = b,
		Position = UDim2.new(0, math.floor(radius * 0.6), 1, -5),
		Size = UDim2.new(1, -math.floor(radius * 1.2), 0, 4),
		Parent = face,
	}, { Ui.round() })
end

-- Presses a button down onto its shadow while it's held (the web's :active translateY).
local function press(face: GuiButton, drop: number)
	local down = UDim2.fromOffset(0, -math.max(0, drop - 2))
	local up = UDim2.fromOffset(0, -drop)
	face.MouseButton1Down:Connect(function()
		face.Position = down
	end)
	face.MouseButton1Up:Connect(function()
		face.Position = up
	end)
	face.MouseLeave:Connect(function()
		face.Position = up
	end)
end

-- A bevelled colour button. colors: a gradient name. Returns the laid-out frame and the face (a
-- TextButton whose Activated runs onClick); put its icon and words in the face.
function Ui.button(props: { [string]: any }, colors: string, onClick: (() -> ())?, opts: { [string]: any }?): (Frame, TextButton)
	local o: { [string]: any } = opts or {}
	local r = o.radius or 14
	local drop = o.drop or 3
	local shadow, face = Ui.shadowed(props, { radius = r, stroke = o.stroke or 2.5, drop = drop, dark = o.dark or 0.3, class = "TextButton", colors = colors, split = o.split, strokeColor = o.strokeColor })
	if not o.flat then
		Ui.bevel(face, r, o.gloss, o.shade)
	end
	if o.text then
		Ui.text({ Name = "Label", Text = o.text, TextSize = o.textSize or 18, Size = UDim2.fromScale(1, 1), TextColor3 = o.textColor or Ui.WHITE, Stroke = o.textStroke, Shadow = o.textShadow, StrokeColor = o.textStrokeColor, Parent = face })
	end
	press(face, drop)
	if onClick then
		face.Activated:Connect(onClick)
	end
	return shadow, face
end

-- The web's green "buy" button (theme.css .buy): a green bevel with a dark green outline and white
-- lettering. kind: "green", "garage" (the blue .alt), "broke" or "grey" (locked).
local BUY_EDGE = { green = "#1d6b22", garage = "#123d8a", broke = "#8a1020", grey = "#b0bec5" }
function Ui.buy(props: { [string]: any }, text: string, kind: string?, onClick: (() -> ())?, textSize: number?): (Frame, TextButton)
	local k = kind or "green"
	local grey = k == "grey"
	return Ui.button(props, k, onClick, {
		radius = 12,
		stroke = 2,
		drop = 2,
		dark = 0.2,
		strokeColor = Color3.fromHex(BUY_EDGE[k] or BUY_EDGE.green),
		flat = grey,
		text = text,
		textSize = textSize or 17,
		textColor = if grey then Color3.fromHex("#546e7a") else Ui.WHITE,
		textShadow = if grey then nil else 1.5,
		textStrokeColor = Color3.fromHex("#0f2a12"),
	})
end

-- The red close button with a white X (theme.css .close).
function Ui.closeButton(props: { [string]: any }, onClick: () -> ()): Frame
	local shadow, face = Ui.button(props, "red", onClick, { radius = 12, stroke = 3, drop = 3, dark = 0.35 })
	Icons.draw("close", face, 16, Ui.WHITE, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	return shadow
end

-- A navy counter pill (theme.css .pill / .my-cars): navy gradient, outline, drop shadow.
function Ui.pill(props: { [string]: any }, radius: number?): (Frame, Frame)
	local shadow, face = Ui.shadowed(props, { radius = radius or 20, stroke = 2.5, drop = 3, dark = 0.35, colors = "navy" })
	Ui.new("Frame", {
		Name = "Gloss",
		ZIndex = 0,
		BorderSizePixel = 0,
		BackgroundColor3 = Ui.WHITE,
		BackgroundTransparency = 0.78,
		Position = UDim2.fromOffset(10, 1),
		Size = UDim2.new(1, -20, 0, 2),
		Parent = face,
	}, { Ui.round() })
	return shadow, face
end

-- A one-line toast, as the web's .toast: navy with an outline.
function Ui.toast(parent: Instance, text: string, order: number): Frame
	local shadow, face = Ui.shadowed({ Size = UDim2.fromOffset(0, 37), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = order, Parent = parent }, { radius = 14, stroke = 2.5, drop = 3, colors = "navy" })
	face.AutomaticSize = Enum.AutomaticSize.X
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = shadow })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = face })
	Ui.text({ Text = text, TextSize = 16, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Shadow = 2, Parent = face })
	return shadow
end

-- The web's Panel (Menus.tsx): the town dims behind a light blue sheet with a thick outline, a
-- blue title bar with the outlined title, and a red X. A tap beside the sheet closes it too.
-- opts: wide (the 860px sheets), width, height, onClose, bodyPadding. Returns the overlay (destroy
-- it to close), the sheet, the body to fill and the title bar (for extra bits before the X).
function Ui.panel(gui: Instance, title: string, opts: { [string]: any }): (TextButton, Frame, Frame, Frame)
	local overlay = Ui.new("TextButton", {
		Name = "Panel",
		Text = "",
		AutoButtonColor = false,
		ZIndex = 20,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromHex("#0a1630"),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Parent = gui,
	})
	overlay.Activated:Connect(opts.onClose)
	local w = if opts.wide then 860 else (opts.width or 460)
	local h = if opts.wide then 900 else (opts.height or 600)
	local shadow, sheet = Ui.shadowed({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 4),
		Size = UDim2.new(1, -40, 1, -40),
		Parent = overlay,
	}, { radius = 24, stroke = 4, drop = 8, dark = 0.35, color = Ui.SHEET, class = "TextButton" })
	-- The sheet takes taps so they don't fall through to the overlay and close it.
	sheet.Selectable = false
	Ui.new("UISizeConstraint", { MaxSize = Vector2.new(w, h), Parent = shadow })
	-- Keep the sheet clear of Roblox's own buttons in the top bar.
	local function clearTopbar()
		local ok, inset = pcall(function()
			return game:GetService("GuiService").TopbarInset
		end)
		local top = if ok and inset then inset.Height else 0
		shadow.Position = UDim2.new(0.5, 0, 0.5, 4 + top / 2)
		shadow.Size = UDim2.new(1, -40, 1, -40 - top)
	end
	clearTopbar()
	pcall(function()
		game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset"):Connect(clearTopbar)
	end)
	local head = Ui.new("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 61), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = sheet }, {
		Ui.corner(21),
		Ui.gradient(Ui.COLORS.head[1], Ui.COLORS.head[2]),
	})
	-- Square off the bar's bottom corners, then its navy bottom edge.
	Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("#2a6fe0"), ZIndex = 0, Parent = head }, {
		Ui.gradient("#3a86ea", Ui.COLORS.head[2]),
	})
	Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 3), Position = UDim2.new(0, 0, 1, -3), BorderSizePixel = 0, BackgroundColor3 = Ui.LINE, ZIndex = 2, Parent = head })
	Ui.new("Frame", { ZIndex = 0, BorderSizePixel = 0, BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.65, Position = UDim2.fromOffset(16, 1), Size = UDim2.new(1, -32, 0, 3), Parent = head }, { Ui.round() })
	local long = #title > 14
	Ui.text({
		Name = "Title",
		Text = title,
		TextSize = if long then 25 else 32,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 6),
		Size = UDim2.new(1, -170, 1, -12),
		Stroke = if long then 2.5 else 3,
		Shadow = 4,
		Parent = head,
	})
	Ui.closeButton({ Name = "Close", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(42, 42), Parent = head }, opts.onClose)
	local extras = Ui.new("Frame", {
		Name = "Extras",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -62, 0.5, -1),
		Size = UDim2.fromOffset(0, 40),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = head,
	}, { Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local pad = opts.bodyPadding or 14
	local body = Ui.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(pad, 61 + (opts.bodyTop or 10)),
		Size = UDim2.new(1, -pad * 2, 1, -61 - (opts.bodyTop or 10) - 14),
		Parent = sheet,
	})
	return overlay, sheet, body, extras
end

-- The web's SheetTabs: a row of tabs that stretch to fill it; the picked one is yellow with a navy
-- outline, the rest white. items: { id, label }. Returns the row and a function to pick a tab
-- (which recolours them; onChange runs on taps). dark: the Cars page's dark strip.
function Ui.tabs(parent: Instance, items: { { id: string, label: string } }, value: string, onChange: (string) -> (), opts: { [string]: any }?): (Frame, (string) -> ())
	local o: { [string]: any } = opts or {}
	local row = Ui.new("Frame", {
		Name = "Tabs",
		Size = o.size or UDim2.new(1, 0, 0, 52),
		Position = o.position or UDim2.new(),
		BackgroundColor3 = if o.dark then Color3.fromHex("#0f141d") else Ui.SHEET,
		BackgroundTransparency = if o.dark then 0.28 else 0,
		BorderSizePixel = 0,
		Parent = parent,
	}, {
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10) }),
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	-- The line under the tabs sits beside the row, not in it, so the row's list doesn't lay it out.
	if not o.dark then
		local size: UDim2 = row.Size
		local pos: UDim2 = row.Position
		Ui.new("Frame", { Name = "TabsEdge", Size = UDim2.new(size.X.Scale, size.X.Offset, 0, 2), Position = pos + UDim2.new(0, 0, size.Y.Scale, size.Y.Offset - 2), BorderSizePixel = 0, BackgroundColor3 = Ui.EDGE, Parent = parent })
	end
	local faces: { [string]: TextButton } = {}
	local function pick(id: string)
		for tid, face in faces do
			local on = tid == id
			local g = face:FindFirstChildOfClass("UIGradient")
			local c = if on then Ui.COLORS.tab else Ui.COLORS.white
			if g then
				g.Color = Ui.seq(c[1], if on then c[2] else c[1])
			end
			if not on and o.dark then
				face.BackgroundTransparency = 0.12
			else
				face.BackgroundTransparency = 0
			end
			local s = face:FindFirstChildOfClass("UIStroke")
			if s then
				s.Color = if on then Ui.LINE else Ui.TAB_EDGE
			end
			local label = face:FindFirstChild("Label") :: TextLabel?
			if label then
				label.TextColor3 = if on then Ui.LINE else Ui.MUTED
			end
			local shadow = face.Parent :: Frame
			shadow.BackgroundColor3 = if on then Ui.BLACK else Ui.TAB_EDGE
			shadow.BackgroundTransparency = if on then 0.7 else 0
			local ss = shadow:FindFirstChildOfClass("UIStroke")
			if ss then
				ss.Color = shadow.BackgroundColor3
				ss.Transparency = shadow.BackgroundTransparency
			end
			local gloss = face:FindFirstChild("Gloss") :: Frame?
			if gloss then
				gloss.Visible = on
			end
		end
	end
	for i, it in items do
		local shadow, face = Ui.shadowed({ Name = it.id, Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = row }, {
			radius = 12,
			stroke = 2,
			drop = 2,
			class = "TextButton",
			colors = "white",
		})
		local gloss = Ui.new("Frame", { Name = "Gloss", ZIndex = 0, BorderSizePixel = 0, BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.5, Position = UDim2.fromOffset(8, 1), Size = UDim2.new(1, -16, 0, 2), Parent = face }, { Ui.round() })
		gloss.Visible = false
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), Parent = shadow })
		Ui.text({ Name = "Label", Text = it.label, TextSize = o.textSize or 14, Size = UDim2.new(1, 0, 1, 0), TextColor3 = Ui.MUTED, Parent = face })
		-- The label sets the tab's width; the face fills the tab, padding and all.
		local measure = Ui.text({ Name = "Measure", Text = it.label, TextSize = o.textSize or 14, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, TextTransparency = 1, Parent = shadow })
		measure.ZIndex = 0
		face.Size = UDim2.new(1, 24, 1, 0)
		face.Position = UDim2.fromOffset(-12, -2)
		faces[it.id] = face
		face.Activated:Connect(function()
			pick(it.id)
			onChange(it.id)
		end)
	end
	pick(value)
	return row, pick
end

-- A scrolling list or grid, with the web's thin scroll bar.
function Ui.scroller(props: { [string]: any }): ScrollingFrame
	local s = Ui.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Color3.fromHex("#90a4ae"),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
	})
	for k, v in props do
		if k ~= "Parent" then
			(s :: any)[k] = v
		end
	end
	s.Parent = props.Parent
	return s
end

-- Counters as the web game's format.ts: 2,500 / 52.6K / 1.2M.
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

-- Job timers, as the web's badges (Badges.tsx fmt): 45s, 3m 20s, 75m 00s.
function Ui.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	if s >= 60 then
		return string.format("%dm %02ds", s // 60, s % 60)
	end
	return `{s}s`
end

-- Short job times for cards: 30s, 4m, 4.5m, 2h.
function Ui.every(seconds: number): string
	if seconds >= 60 then
		local m = seconds / 60
		return (if m == math.floor(m) then tostring(m) else string.format("%.1f", m)) .. "m"
	end
	return `{seconds}s`
end

return Ui
