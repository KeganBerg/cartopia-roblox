--!strict
-- The Menu (the web game's AccountPanel, ui/Account.tsx, with CityLook and the Settings tabs) and
-- the "How to get ..." sheet (NeedPanel, ui/Need.tsx) that opens when the player is short.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local cityLook = require(Game.cityLook) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Icons = require(script.Parent.Icons)
local Bank = require(script.Parent.Bank)
local Mixer = require(script.Parent.Sounds.Mixer)
local Sfx = require(script.Parent.Sounds.Sfx)

local Menu = {}

local W = 456
local GAP = 10
local lastTab = "town"

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

-- A panel whose body is one scrolling column; returns the overlay, the column, and a function
-- that sizes the sheet to its content (as the web's panels hug what's in them).
local function column(parent: Instance, top: number): ScrollingFrame
	local list = Ui.scroller({ Name = "List", Position = UDim2.fromOffset(-6, top), Size = UDim2.new(1, 12, 1, -top), Parent = parent })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 6), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	return list
end

local function clear(list: Instance)
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function h3(list: Instance, order: number, text: string): number
	Ui.text({ Text = text, TextSize = 18, TextColor3 = Ui.LINE, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = order, Parent = list })
	return 26
end

-- ── Town tab ────────────────────────────────────────────────────────────────────────────────

-- The ✔ badge and orange outline on the picked card.
local function picked(card: GuiObject, on: boolean)
	local s = card:FindFirstChildOfClass("UIStroke")
	if s then
		s.Color = if on then Color3.fromHex("#ff8f00") else Ui.LINE
		s.Transparency = if on then 0 else 0.86
	end
	if on then
		Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = Color3.fromHex("#ff8f00"), ZIndex = 3, Parent = card }, {
			Ui.round(),
			Ui.text({ Text = "✔", Body = true, Weight = "heavy", TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 3 }),
		})
	end
end

-- A picture card with a name under it (.cl-card); `art` draws the picture.
local function card(grid: Instance, order: number, name: string, on: boolean, picH: number, art: (Frame) -> (), onClick: () -> ())
	local c = Ui.new("TextButton", { Text = "", AutoButtonColor = false, LayoutOrder = order, BackgroundColor3 = Ui.WHITE, ClipsDescendants = true, Parent = grid }, {
		Ui.corner(14),
		Ui.stroke(3, Ui.LINE, 0.86),
	})
	local pic = Ui.new("Frame", { Name = "Pic", Size = UDim2.new(1, 0, 0, picH), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("#141a33"), Parent = c })
	art(pic)
	local foot = Ui.new("Frame", { Position = UDim2.fromOffset(0, picH), Size = UDim2.new(1, 0, 1, -picH), BorderSizePixel = 0, BackgroundColor3 = if on then Color3.fromHex("#fff3d6") else Ui.WHITE, Parent = c })
	Ui.text({ Text = name, Body = true, TextSize = 15, TextColor3 = Ui.LINE, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.fromScale(1, 1), Parent = foot })
	picked(c, on)
	c.Activated:Connect(onClick)
end

-- A lamp post in the light's colour: the post, its head and a glow on the pavement.
local function lampArt(post: string, tone: string): (Frame) -> ()
	return function(pic: Frame)
		local c = Color3.fromHex(tone)
		Ui.new("Frame", { Position = UDim2.new(0, 0, 0.72, 0), Size = UDim2.fromScale(1, 0.28), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("#3a4258"), Parent = pic })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.fromScale(0.8, 0.16), BackgroundColor3 = c, BackgroundTransparency = 0.55, Parent = pic }, { Ui.round() })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.8), Size = UDim2.new(0, 4, 0.58, 0), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("#2b2f3a"), Parent = pic })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = c, BackgroundTransparency = 0.72, Parent = pic }, { Ui.round() })
		local icon = ({ auto = "🔀", cobra = "🛣️", lantern = "🏮", globe = "🔮" } :: any)[post] or "💡"
		Ui.text({ Text = icon, TextSize = 22, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), Size = UDim2.fromOffset(30, 30), Parent = pic })
	end
end

-- Three little shops in a theme's colour (or their own colours).
local function themeArt(color: string?): (Frame) -> ()
	return function(pic: Frame)
		pic.BackgroundColor3 = Color3.fromHex("#bfe3f7")
		Ui.new("Frame", { Position = UDim2.new(0, 0, 1, -12), Size = UDim2.new(1, 0, 0, 12), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("#f4f1ea"), Parent = pic })
		local own = { "#f4f3ee", "#d6463c", "#5aa96a" }
		local hs = { 0.5, 0.66, 0.56 }
		for i = 1, 3 do
			local base = Color3.fromHex(if color then color else own[i])
			local x = 0.12 + (i - 1) * 0.27
			local house = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(x, 0, 1, -8), Size = UDim2.fromScale(0.24, hs[i]), BorderSizePixel = 0, BackgroundColor3 = base, Parent = pic }, { Ui.corner(2) })
			Ui.new("Frame", { Position = UDim2.fromScale(0, 0), Size = UDim2.new(1, 0, 0, 4), BorderSizePixel = 0, BackgroundColor3 = base:Lerp(Ui.BLACK, 0.25), Parent = house })
			Ui.new("Frame", { Position = UDim2.fromScale(0.2, 0.45), Size = UDim2.fromScale(0.6, 0.22), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("#7fb7e0"), Parent = house })
		end
	end
end

local function townTab(ctx: any, list: Instance, s: any): number
	local h = 0
	local order = 0
	local function add(height: number)
		order += 1
		h += height + GAP
	end
	add(26)
	h3(list, order, "🏙️ Town name")
	add(48)
	local row = Ui.new("Frame", { Name = "TownName", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, Parent = list })
	local field = Ui.new("Frame", { Size = UDim2.new(1, -102, 1, -4), Position = UDim2.fromOffset(0, 2), BackgroundColor3 = Ui.WHITE, Parent = row }, {
		Ui.corner(10),
		Ui.stroke(2, Color3.fromHex("#cfd8dc")),
	})
	local box = Ui.new("TextBox", {
		Text = s.townName,
		PlaceholderText = "Town name",
		ClearTextOnFocus = false,
		FontFace = Ui.BODY,
		TextSize = 18,
		TextColor3 = Ui.INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Parent = field,
	})
	local saveShadow, saveFace = Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 2), Size = UDim2.fromOffset(84, 34), Parent = row }, "Save", "green", function()
		local name = box.Text:sub(1, 24)
		if name:match("%S") and name ~= store.useGame.getState().townName then
			Remote.act("renameTown", name)
		end
	end, 16)
	-- Greyed out until the name changes, as the web's disabled Save.
	local function dim()
		local same = box.Text == store.useGame.getState().townName or not box.Text:match("%S")
		saveShadow.BackgroundTransparency = if same then 0.9 else 0.8
		local g = saveFace:FindFirstChildOfClass("UIGradient")
		if g then
			g.Color = if same then Ui.seq("#b5e3a0", "#86c98a") else Ui.seq(Ui.COLORS.green[1], Ui.COLORS.green[2])
		end
	end
	box:GetPropertyChangedSignal("Text"):Connect(dim)
	dim()

	local lights = s.lights or {}
	local tone = cityLook.lightTone(lights)
	local post = cityLook.lampPost(lights)
	local function saved()
		ctx.toast("Saved to your town. The Roblox town shows it soon.")
	end
	add(26)
	h3(list, order, "💡 Street lights")
	local cardW = (W - 28 - 30) / 4
	add(cardW + 30)
	local lamps = Ui.new("Frame", { Name = "Lamps", LayoutOrder = order, Size = UDim2.new(1, 0, 0, cardW + 30), BackgroundTransparency = 1, Parent = list }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 1, 0), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, p in cityLook.LAMP_POSTS do
		card(lamps, i, p.name, post == p.id, cardW - 6, lampArt(p.id, tone.c), function()
			Remote.act("setLights", { tone = tone.id, post = p.id })
			saved()
		end)
	end
	add(64)
	local bulbs = Ui.new("Frame", { Name = "Bulbs", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Parent = list }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, t in cityLook.LIGHT_TONES do
		local on = tone.id == t.id
		local b = Ui.new("TextButton", { Text = "", AutoButtonColor = false, LayoutOrder = i, Size = UDim2.new(0, 40, 1, 0), BackgroundTransparency = 1, Parent = bulbs })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = Ui.WHITE, Parent = b }, {
			Ui.round(),
			Ui.stroke(if on then 3 else 2, if on then Color3.fromHex("#ff8f00") else Ui.LINE, if on then 0 else 0.82),
			Ui.new("Frame", { Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundColor3 = Color3.fromHex(t.c) }, { Ui.round() }),
		})
		Ui.text({ Text = t.name, Body = true, TextSize = 12, TextColor3 = if on then Ui.LINE else Ui.MUTED, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 16), Parent = b })
		b.Activated:Connect(function()
			Remote.act("setLights", { tone = t.id, post = post })
			saved()
		end)
	end
	add(26)
	h3(list, order, "🎨 Town colours")
	local themes = { { id = "own", name = "Own colours", c = nil :: string? } }
	for _, t in cityLook.COLOR_THEMES do
		table.insert(themes, { id = t.id, name = t.name, c = t.c })
	end
	local picH = math.floor(cardW * 220 / 360)
	local rowsN = math.ceil(#themes / 4)
	local gridH = rowsN * (picH + 30) + (rowsN - 1) * 10
	add(gridH)
	local grid = Ui.new("Frame", { Name = "Themes", LayoutOrder = order, Size = UDim2.new(1, 0, 0, gridH), BackgroundTransparency = 1, Parent = list }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, picH + 30), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, t in themes do
		local on = if t.id == "own" then s.cityTheme == nil else s.cityTheme == t.id
		card(grid, i, t.name, on, picH, themeArt(t.c), function()
			Remote.act("setCityTheme", if t.id == "own" then nil else t.id)
			saved()
		end)
	end
	return h
end

-- ── Settings, Account and Help tabs ─────────────────────────────────────────────────────────

-- A titled white card of rows (.set-group): returns the card and a function adding a row.
local function group(list: Instance, order: number, icon: string, title: string): (Frame, (number) -> Frame)
	local g = Ui.new("Frame", { Name = title, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Ui.WHITE, ClipsDescendants = true, Parent = list }, {
		Ui.corner(16),
		Ui.stroke(2.5, Ui.TAB_EDGE),
	})
	local headBar = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BorderSizePixel = 0, BackgroundColor3 = Ui.WHITE, Parent = g }, {
		Ui.gradient("#f4f8fd", "#e6eef9"),
	})
	Ui.new("Frame", { Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("#d5e2f3"), Parent = headBar })
	Ui.text({ Text = `{icon}  {title}`, TextSize = 16, TextColor3 = Color3.fromHex("#24406b"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, -2), Parent = headBar })
	local y = 36
	return g, function(height: number): Frame
		local r = Ui.new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, Parent = g })
		if y > 36 then
			Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 1.5), BorderSizePixel = 0, BackgroundColor3 = Color3.fromHex("#edf2f8"), Parent = r })
		end
		y += height
		g.Size = UDim2.new(1, 0, 0, y)
		return r
	end
end

local function label(row: Frame, text: string, sub: string?)
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, if sub then 6 else 0), Size = UDim2.new(1, -90, if sub then 0 else 1, if sub then 20 else 0), Parent = row })
	if sub then
		Ui.text({ Text = sub, Body = true, TextSize = 12, TextColor3 = Color3.fromHex("#78909c"), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -90, 0, 16), Parent = row })
	end
end

-- The web's on/off switch: green when on, the knob slides right.
local function switch(row: Frame, on: boolean, onChange: (boolean) -> ())
	local sw = Ui.new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(50, 30), BackgroundColor3 = Ui.WHITE, Parent = row }, {
		Ui.round(),
		Ui.stroke(2.5),
	})
	local grad = Ui.gradient("#cfd8dc", "#cfd8dc")
	grad.Parent = sw
	local knob = Ui.new("Frame", { Size = UDim2.fromOffset(21, 21), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Ui.WHITE, Parent = sw }, {
		Ui.round(),
		Ui.stroke(2),
		Ui.gradient("#ffffff", "#e3ecf7"),
	})
	local state = on
	local function paint()
		knob.Position = UDim2.new(0, if state then 25 else 4, 0.5, 0)
		grad.Color = if state then Ui.seq("#8ef05c", "#2fae35") else Ui.seq("#cfd8dc", "#cfd8dc")
	end
	paint()
	sw.Activated:Connect(function()
		state = not state
		paint()
		onChange(state)
	end)
end

-- The web's volume slider (Menu > Settings > Sound): 0 to 100 in steps of 5, green up to the knob,
-- faded while its sound is off. Drag or tap along it.
local function slider(row: Frame, value: number, enabled: boolean, onChange: (number) -> ())
	local track = Ui.new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 116, 0.5, 0), Size = UDim2.new(1, -116 - 62, 0, 28), BackgroundTransparency = 1, Parent = row })
	local bar = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 8), BackgroundColor3 = Color3.fromHex("#e0e6ee"), BorderSizePixel = 0, Parent = track }, { Ui.round() })
	local fill = Ui.new("Frame", { Size = UDim2.fromScale(value, 1), BackgroundColor3 = Color3.fromHex("#43a047"), BorderSizePixel = 0, Parent = bar }, { Ui.round() })
	local knob = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(value, 0.5), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Ui.WHITE, Parent = bar }, {
		Ui.round(),
		Ui.stroke(2),
	})
	local v = value
	local function paint()
		fill.Size = UDim2.fromScale(v, 1)
		knob.Position = UDim2.fromScale(v, 0.5)
		local fade = if enabled then 0 else 0.6
		fill.BackgroundTransparency = fade
		knob.BackgroundTransparency = fade
		bar.BackgroundTransparency = fade
	end
	paint()
	local function at(x: number)
		local w = math.max(1, bar.AbsoluteSize.X)
		local next = math.clamp(math.round((x - bar.AbsolutePosition.X) / w * 20) / 20, 0, 1)
		if next ~= v then
			v = next
			paint()
			onChange(v)
		end
	end
	local dragging: InputObject? = nil
	track.InputBegan:Connect(function(input)
		if not enabled then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = input
			at(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragging) then
			at(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = nil
		end
	end)
end

-- The web's round on/off button at the end of a sound row (🎵 / 🔕).
local function toggle(row: Frame, on: boolean, glyph: string, onChange: (boolean) -> ())
	local b = Ui.new("TextButton", { Text = if on then glyph else "🔕", TextSize = 17, Font = Enum.Font.GothamBold, AutoButtonColor = true, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(38, 34), BackgroundColor3 = Ui.WHITE, Parent = row }, {
		Ui.corner(10),
		Ui.stroke(2, Color3.fromHex("#e0e0e0")),
	})
	b.Activated:Connect(function()
		on = not on
		b.Text = if on then glyph else "🔕"
		onChange(on)
	end)
end

-- Music, Effects and Town sounds rows (the web's MusicControl, EffectsControl, AmbienceControl).
local lastEffects = 1
local function soundRows(row: (number) -> Frame, redraw: () -> ())
	local set = Mixer.settings()
	local r = row(48)
	label(r, "Music")
	slider(r, set.music.volume, set.music.on, function(v)
		Mixer.set({ music = { volume = v } })
	end)
	toggle(r, set.music.on, "🎵", function(on)
		Mixer.set({ music = { on = on } })
		redraw()
	end)
	r = row(48)
	label(r, "Effects")
	slider(r, set.effects, true, function(v)
		Mixer.set({ effects = v })
		Sfx.click()
	end)
	toggle(r, set.effects > 0, "💥", function(on)
		if on then
			Mixer.set({ effects = lastEffects })
		else
			lastEffects = math.max(0.05, Mixer.settings().effects)
			Mixer.set({ effects = 0 })
		end
		redraw()
	end)
	r = row(48)
	label(r, "Town sounds")
	slider(r, set.town.volume, set.town.on, function(v)
		Mixer.set({ town = { volume = v } })
	end)
	toggle(r, set.town.on, "🌳", function(on)
		Mixer.set({ town = { on = on } })
		redraw()
	end)
end

local function settingsTab(list: Instance, redraw: () -> ()): number
	local sound = SoundService:FindFirstChild("Cartopia") :: SoundGroup?
	local g1, row1 = group(list, 1, "🔊", "Sound")
	local r = row1(48)
	label(r, "Sound")
	switch(r, sound == nil or sound.Volume > 0, function(on)
		local sg = SoundService:FindFirstChild("Cartopia") :: SoundGroup?
		if sg then
			sg.Volume = if on then 1 else 0
		end
	end)
	soundRows(row1, redraw)
	local g2, row2 = group(list, 2, "✨", "Graphics")
	label(row2(52), "Graphics quality", "Roblox sets this: open its menu (Esc) > Settings")
	return g1.Size.Y.Offset + g2.Size.Y.Offset + GAP * 2
end

local function accountTab(list: Instance): number
	local g, row = group(list, 1, "☁️", "Cloud save")
	local me = Players.LocalPlayer
	label(row(52), if me then me.DisplayName else "You", "Your town saves to your Roblox account")
	return g.Size.Y.Offset + GAP
end

local TIPS = {
	{ "⛽", "Tap a business to send a car on a job" },
	{ "💰", "Tap coin bubbles for coins and XP" },
	{ "🚗", "Every car you own drives your roads" },
	{ "🔧", "Rusty's Rescue finds and restores old cars" },
	{ "⚙️", "Upgrade cars in the Garage" },
	{ "➕", "Short on something? Tap its counter" },
	{ "🏁", "Race rivals. Shift in the green zone" },
	{ "⭐", "Level up to unlock businesses and cars" },
}
local function helpTab(list: Instance): number
	local g, row = group(list, 1, "🚗", "How to play")
	local r = row(#TIPS * 26 + 12)
	for i, t in TIPS do
		Ui.text({ Text = t[1], TextSize = 16, Position = UDim2.fromOffset(12, 6 + (i - 1) * 26), Size = UDim2.fromOffset(24, 26), Parent = r })
		Ui.text({ Text = t[2], Body = true, TextSize = 14, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(42, 6 + (i - 1) * 26), Size = UDim2.new(1, -54, 0, 26), Parent = r })
	end
	return g.Size.Y.Offset + GAP
end

local TABS = { { id = "town", label = "🏠 Town" }, { id = "settings", label = "⚙️ Settings" }, { id = "account", label = "👤 Account" }, { id = "help", label = "❓ Help" } }

function Menu.open(ctx: any): Instance
	local overlay, sheet, body = Ui.panel(ctx.gui, "Menu", { width = W, onClose = ctx.close, bodyTop = 0 })
	local limit = (sheet.Parent :: Instance):FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local list = column(body, 64)
	local tab = lastTab
	local function show()
		clear(list)
		local s = store.useGame.getState()
		local h = if tab == "town" then townTab(ctx, list, s) elseif tab == "settings" then settingsTab(list, show) elseif tab == "account" then accountTab(list) else helpTab(list)
		limit.MaxSize = Vector2.new(W, 61 + 64 + h + 22)
	end
	Ui.tabs(body, TABS, tab, function(id)
		tab = id
		lastTab = id
		show()
	end, { position = UDim2.fromOffset(-14, 0), size = UDim2.new(1, 28, 0, 54) })
	show()
	-- Redraw the Town tab when a pick lands, but not while the name is being typed.
	local conn = Remote.changed:Connect(function()
		if tab == "town" then
			show()
		end
	end)
	overlay.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return overlay
end

-- ── How to get ... ──────────────────────────────────────────────────────────────────────────

local LABEL = { coins = "coins", parts = "parts", fuel = "fuel", bucks = "gems", level = "a higher level" }
local ICON = { coins = "$", parts = "⚙", fuel = "⛽", bucks = "💎", level = "⭐" }
local ICON_BG = { coins = { "#ffe082", "#f9a825" }, parts = { "#bcaaa4", "#6d4c41" }, fuel = { "#e53935", "#e53935" }, bucks = { "#81d4fa", "#0277bd" }, level = { "#c5e1a5", "#558b2f" } }

type Source = { icon: string, title: string, detail: string, action: { label: string, run: () -> (), disabled: boolean? }? }

function Menu.need(ctx: any, need: any?): Instance?
	if not need or not LABEL[need.res] then
		return nil
	end
	local s = store.useGame.getState()
	local t = now()
	local function soon(what: string): () -> ()
		return function()
			ctx.close()
			ctx.toast(`{what} is coming to Roblox soon`)
		end
	end
	local function owned(id: string): number
		local n = 0
		for _, b in s.buildings do
			if b.def == id then
				n += 1
			end
		end
		return n
	end
	local function build(id: string): { label: string, run: () -> (), disabled: boolean? }
		local d = data.buildingDef(id)
		if store.gateLevel(s) < d.unlockLevel then
			return { label = `🔒 Level {d.unlockLevel}`, run = function() end, disabled = true }
		end
		if d.unique then
			for _, b in s.buildings do
				if b.def == id then
					return { label = "✔ Built", run = function() end, disabled = true }
				end
			end
			for _, b in (s.stored or {}) do
				if b.def == id then
					return { label = "✔ Built", run = function() end, disabled = true }
				end
			end
		end
		return { label = `Build · ${Ui.commas(d.price)}`, run = function() ctx.open("shop", id) end }
	end
	local function isJob(def: string): boolean
		local d = data.buildingDef(def)
		return d.jobSeconds ~= nil and d.kind ~= "obstacle"
	end
	local idle, ready = 0, 0
	local hasJob = false
	for _, b in s.buildings do
		if isJob(b.def) then
			hasJob = true
			if b.jobEndsAt == nil and data.isOpen(data.buildingDef(b.def), t) then
				idle += 1
			elseif b.jobEndsAt ~= nil and t >= b.jobEndsAt then
				ready += 1
			end
		end
	end
	local function showJobs()
		ctx.close()
		ctx.toast(if ready > 0 then "Tap the $ bubbles to collect." else "Tap a ⛽ bubble to start a job.")
	end
	local function showParts(id: string): () -> ()
		return function()
			ctx.close()
			ctx.toast(`Tap the bubble on your {data.buildingDef(id).name} to start a parts job.`)
		end
	end
	local what = need.what
	local missing = need.missing or 0
	local summary = ""
	local sources: { Source } = {}
	if need.res == "coins" then
		summary = if missing > 0 then `You need {Ui.commas(missing)} more coins{if what then ` for {what}` else ""}.` else `You have {Ui.commas(s.coins)} coins. Here's how to earn more.`
		sources = {
			{ icon = "🏪", title = "Run jobs at your businesses", detail = `Tap the ⛽ bubble to start a job, then the $ bubble to collect. {ready} ready to collect, {idle} idle right now.`, action = { label = "Show me", run = showJobs } },
			{ icon = "🎁", title = "Open crates", detail = "Coin crates can pay big coin prizes.", action = { label = "Crates", run = function() ctx.open("crates") end } },
		}
		if hasJob and not (what and what:sub(1, 9) == "upgrading") then
			table.insert(sources, { icon = "⬆️", title = "Upgrade your businesses", detail = "Upgraded businesses pay more coins per job and finish sooner. Find them under Upgrades in the Shop.", action = { label = "Upgrades", run = function() ctx.open("shop", "upgrades") end } })
		end
		table.insert(sources, { icon = "🔍", title = "Search at Rusty's", detail = "Searches can turn up coin stashes along with cars.", action = if owned("rescue") > 0 then { label = "Rusty's", run = function() ctx.open("rescue") end } else build("rescue") })
		table.insert(sources, { icon = "🏆", title = "Win drag races", detail = `Each race costs {data.RACE_FUEL} fuel and pays a few hundred coins.`, action = { label = "Race", run = function() ctx.open("race") end } })
		table.insert(sources, { icon = "📋", title = "Finish goals", detail = "Goals pay coins, XP and sometimes gems.", action = { label = "Goals", run = function() ctx.open("goals") end } })
		table.insert(sources, { icon = "👫", title = "Help other towns", detail = "Visit a town and tap its shops to help.", action = { label = "Social", run = soon("Visiting towns") } })
	elseif need.res == "parts" then
		summary = (if missing > 0 then `You need {missing} more parts{if what then ` for {what}` else ""}.` else `You have {s.parts} parts.`) .. " Parts (the ⚙ gears) come from these businesses:"
		local function partsRow(icon: string, title: string, id: string, detail: string): Source
			return { icon = icon, title = title, detail = detail, action = if owned(id) > 0 then { label = "Show me", run = showParts(id) } else build(id) }
		end
		sources = {
			{ icon = "🔧", title = "Rusty's Rescue searches", detail = if owned("rescue") > 0 then "Searches turn up parts, and you can scrap cars in storage for 3 to 12 parts." else "Build Rusty's to search for cars and parts.", action = if owned("rescue") > 0 then { label = "Rusty's", run = function() ctx.open("rescue") end } else build("rescue") },
			partsRow("🛞", "Tire Shop · 6 parts per job (level 2)", "tires", `You have {owned("tires")}. Build more for more parts.`),
			partsRow("🛢", "Lube & Go · 8 parts per job (level 4)", "lube", `You have {owned("lube")}.`),
			partsRow("📦", "Parts Depot · 15 parts per job (level 5)", "parts", `You have {owned("parts")}.`),
			partsRow("🏁", "Tuner Shop · 25 parts per job (level 7)", "tuner", `You have {owned("tuner")}.`),
		}
	elseif need.res == "fuel" then
		local cap = store.fuelCap(s)
		local nextIn = if s.fuel >= cap then nil else math.max(0, data.fuelRegenSeconds(s.level) - math.floor((t - s.fuelUpdatedAt) / 1000))
		summary = if missing > 0 then `You need {missing} more fuel{if what then ` for {what}` else ""}. You have {s.fuel}/{cap}.` else `You have {s.fuel}/{cap} fuel.`
		local refill = data.refillBucks(cap - s.fuel)
		local step = data.nextFuelStep(s.level)
		sources = {
			{ icon = "⛽", title = `Fill up with gems · 💎 {refill}`, detail = if s.fuel >= cap then "Your tank is full." else `Fill your tank to {cap} right now. You have {Ui.commas(s.bucks)} gems.`, action = { label = `Fill up · 💎 {refill}`, disabled = s.fuel >= cap, run = function()
				Remote.act("refillFuel")
			end } },
			{ icon = "⏱", title = `Wait for a refill · {data.fuelPerMin(s.level)}⛽/min`, detail = if nextIn == nil then "Your tank is full." else `Next one in {nextIn}s.` },
			{ icon = "⛽", title = "Build a Gas Station", detail = `Each one adds +10 to your max fuel. You have {owned("gas")}.`, action = build("gas") },
		}
		if owned("house") > 0 then
			table.insert(sources, { icon = "🏡", title = "Upgrade your homes", detail = "Every home level adds +1 to your max fuel. Find them under Upgrades in the Shop.", action = { label = "Upgrades", run = function() ctx.open("shop", "upgrades") end } })
		end
		table.insert(sources, { icon = "⭐", title = "Level up", detail = "Refills your tank and raises the max." .. (if step then ` {step.perMin}⛽/min at level {step.level}.` else "") })
	elseif need.res == "bucks" then
		summary = if missing > 0 then `You need {missing} more gems{if what then ` for {what}` else ""}.` else `You have {Ui.commas(s.bucks)} gems.`
		sources = {
			{ icon = "⭐", title = "Level up", detail = `Every new level gives +{data.LEVEL_GEMS} gems.` },
			{ icon = "📋", title = "Finish goals", detail = "Bigger goals pay gems.", action = { label = "Goals", run = function() ctx.open("goals") end } },
		}
		if Bank.unlocked(s) then
			table.insert(sources, { icon = "🏦", title = "Visit the Bank", detail = "Buy gems in packs. Bigger packs come with bonus gems, coins and parts.", action = { label = "Bank", run = function() ctx.open("bank") end } })
		end
	else
		local toGo = data.xpToNext(s.level) - s.xp
		summary = `{what or "This"} unlocks at level {missing}. You're level {s.level}, {Ui.commas(toGo)} XP from level {s.level + 1}.`
		sources = {
			{ icon = "🏪", title = "Collect from businesses", detail = "Every job you collect gives XP.", action = { label = "Show me", run = showJobs } },
			{ icon = "🏗", title = "Build and buy", detail = "New buildings, cars and upgrades all give XP.", action = { label = "Shop", run = function() ctx.open("shop") end } },
			{ icon = "🏆", title = "Race", detail = `Wins give {Ui.commas(data.xpGain(s.level, data.raceXp(true, s.level)))} XP.`, action = { label = "Race", run = function() ctx.open("race") end } },
			{ icon = "📋", title = "Goals", detail = "Goals give big XP rewards.", action = { label = "Goals", run = function() ctx.open("goals") end } },
		}
	end

	local overlay, sheet, body = Ui.panel(ctx.gui, `How to get {LABEL[need.res]}`, { width = W, onClose = ctx.close })
	local limit = (sheet.Parent :: Instance):FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local list = column(body, 0)
	local h = 0
	-- The head: the resource's icon and what's short.
	local headH = 48
	h += headH + GAP
	local head = Ui.new("Frame", { Name = "NeedHead", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, headH), BackgroundTransparency = 1, Parent = list })
	local bg = ICON_BG[need.res]
	local ico = Ui.new("Frame", { Position = UDim2.new(0, 0, 0.5, -22), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = Ui.WHITE, Parent = head }, {
		if need.res == "fuel" then Ui.corner(10) else Ui.round(),
		Ui.gradient(bg[1], bg[2]),
	})
	if need.res == "coins" then
		Icons.draw("coin", ico, 44)
	else
		Ui.text({ Text = ICON[need.res], TextSize = 22, Size = UDim2.fromScale(1, 1), Parent = ico })
	end
	Ui.text({ Text = summary, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -56, 1, 0), Parent = head })
	for i, src in sources do
		-- Two lines of detail fit at this width; long ones get a third.
		local lines = math.ceil((#src.detail * 6.4) / (W - 28 - 32 - 30 - (if src.action then 100 else 0)))
		local rh = 26 + math.max(1, lines) * 16 + 10
		h += rh + 6
		local r = Ui.new("Frame", { Name = "Source", LayoutOrder = i, Size = UDim2.new(1, 0, 0, rh), BackgroundColor3 = Ui.WHITE, Parent = list }, {
			Ui.corner(12),
			Ui.stroke(2, Ui.EDGE),
		})
		Ui.text({ Text = src.icon, TextSize = 24, Position = UDim2.new(0, 10, 0.5, -16), Size = UDim2.fromOffset(32, 32), Parent = r })
		local textW = if src.action then -52 - 110 else -62
		Ui.text({ Text = src.title, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(52, 7), Size = UDim2.new(1, textW, 0, 20), Parent = r })
		Ui.text({ Text = src.detail, Body = true, TextSize = 12, TextColor3 = Color3.fromHex("#546e7a"), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Position = UDim2.fromOffset(52, 28), Size = UDim2.new(1, textW, 1, -32), Parent = r })
		local a = src.action
		if a then
			Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 1), Size = UDim2.fromOffset(math.clamp(#a.label * 8 + 22, 64, 110), 30), Parent = r }, a.label, if a.disabled then "grey" else "green", if a.disabled then nil else a.run, 14)
		end
	end
	(list:FindFirstChildOfClass("UIListLayout") :: UIListLayout).Padding = UDim.new(0, 6)
	limit.MaxSize = Vector2.new(W, 61 + 10 + h + 24)
	return overlay
end

return Menu
