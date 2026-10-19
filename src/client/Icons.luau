--!strict
-- The web game's icons (ui/Icon.tsx), drawn with frames on the same 24-unit grid so they read the
-- same at any size: white glyphs on the coloured buttons, the coin and fuel can in full colour.
-- Built once with the screen; nothing here runs per frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Pictures = require(ReplicatedStorage.Shared.Pictures)

local Icons = {}

local LINE = Color3.fromHex("#14213d")

type Ctx = { holder: Frame, size: number, color: Color3, cut: Color3 }

local function part(c: Ctx, x: number, y: number, w: number, h: number, r: number?, rot: number?, color: Color3?, parent: Instance?): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color or c.color
	f.Position = UDim2.fromScale(x / 24, y / 24)
	f.Size = UDim2.fromScale(w / 24, h / 24)
	f.Rotation = rot or 0
	if r and r > 0 then
		local k = Instance.new("UICorner")
		k.CornerRadius = UDim.new(math.min(0.5, r / math.min(w, h)), 0)
		k.Parent = f
	end
	f.Parent = parent or c.holder
	return f
end

-- A bar from (x0, y0) to (x1, y1), thickness t: strokes like the check mark.
local function bar(c: Ctx, x0: number, y0: number, x1: number, y1: number, t: number, color: Color3?, parent: Instance?)
	local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
	local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
	part(c, cx - len / 2, cy - t / 2, len, t, t / 2, math.deg(math.atan2(y1 - y0, x1 - x0)), color, parent)
end

local function circle(c: Ctx, cx: number, cy: number, r: number, color: Color3?, parent: Instance?): Frame
	return part(c, cx - r, cy - r, r * 2, r * 2, r, 0, color, parent)
end

-- A ring (circle outline), thickness t, for the sound waves and the rotate arrow.
local function ring(c: Ctx, cx: number, cy: number, r: number, t: number, parent: Instance?): Frame
	local f = circle(c, cx, cy, r, c.color, parent)
	f.BackgroundTransparency = 1
	local s = Instance.new("UIStroke")
	s.Thickness = t / 24 * c.size
	s.Color = c.color
	s.Parent = f
	return f
end

-- A clipping window: only what's inside it shows (half rings, arrow heads).
local function clip(c: Ctx, x: number, y: number, w: number, h: number): Frame
	local f = part(c, x, y, w, h, 0, 0)
	f.BackgroundTransparency = 1
	f.ClipsDescendants = true
	return f
end

-- Coordinates inside a clip window are still on the icon's grid.
local function inClip(c: Ctx, win: Frame, x0: number, y0: number, w0: number, h0: number): Ctx
	local sub = Instance.new("Frame")
	sub.BackgroundTransparency = 1
	sub.Size = UDim2.fromScale(24 / w0, 24 / h0)
	sub.Position = UDim2.fromScale(-x0 / w0, -y0 / h0)
	sub.Parent = win
	return { holder = sub, size = c.size, color = c.color, cut = c.cut }
end

local DRAW: { [string]: (Ctx) -> () } = {}

DRAW.menu = function(c)
	for _, y in { 5.5, 10.5, 15.5 } do
		part(c, 2.5, y, 19, 3, 1.5)
	end
end

DRAW.plus = function(c)
	part(c, 10.2, 3.5, 3.6, 17, 1.8)
	part(c, 3.5, 10.2, 17, 3.6, 1.8)
end

DRAW.close = function(c)
	bar(c, 5, 5, 19, 19, 3.2)
	bar(c, 19, 5, 5, 19, 3.2)
end

DRAW.check = function(c)
	bar(c, 4, 12.5, 9.2, 17.6, 3.4)
	bar(c, 9.2, 17.6, 20, 6, 3.4)
end

DRAW.back = function(c)
	bar(c, 15, 4.5, 8, 12, 3.4)
	bar(c, 8, 12, 15, 19.5, 3.4)
end

DRAW.shop = function(c)
	part(c, 3, 4, 18, 5, 0.6)
	for _, x in { 4.5, 9.5, 14.5, 19.5 } do
		circle(c, x, 9, 2.6)
	end
	part(c, 3.5, 12.6, 17, 8.4, 1)
	part(c, 6.5, 15, 4, 6, 0, 0, c.cut)
	part(c, 13.5, 15, 4, 3.5, 0, 0, c.cut)
end

DRAW.car = function(c)
	part(c, 6.2, 4, 11.6, 9, 2)
	part(c, 2, 10, 20, 8, 2.5)
	part(c, 7.8, 5.8, 8.4, 4.6, 1, 0, c.cut)
	circle(c, 6, 13.6, 1.5, c.cut)
	circle(c, 18, 13.6, 1.5, c.cut)
	part(c, 4, 16, 3, 5, 1.5)
	part(c, 17, 16, 3, 5, 1.5)
end

DRAW.cone = function(c)
	part(c, 10.3, 3, 3.4, 4, 0.6)
	part(c, 8.7, 9, 6.6, 4, 0.6)
	part(c, 7.1, 15, 9.8, 4.5, 0.6)
	part(c, 2.5, 19.5, 19, 2.5, 1)
	-- The cone's sloped sides.
	bar(c, 10.6, 3.4, 6.6, 19.5, 1.4)
	bar(c, 13.4, 3.4, 17.4, 19.5, 1.4)
end

DRAW.flag = function(c)
	part(c, 3, 2.5, 2, 20, 1)
	part(c, 5, 4, 15, 11, 1)
	for _, sq in { { 5, 6 }, { 8.5, 9 }, { 12, 6 }, { 15.5, 9 } } do
		part(c, sq[1], sq[2], 3.5, 3, 0, 0, c.cut)
	end
end

-- Two people, the bigger in front (the web's friends icon).
DRAW.friends = function(c)
	circle(c, 17, 8.5, 2.8)
	part(c, 14.6, 13.5, 8, 6, 3)
	circle(c, 8.5, 7.5, 3.5)
	part(c, 1.5, 13.5, 14, 7, 3.5)
	part(c, 1.5, 17, 14, 3.5, 1)
end

-- A speech bubble with three dots.
DRAW.chat = function(c)
	part(c, 2, 3, 20, 15, 2.5)
	bar(c, 7, 16, 5.5, 21.3, 2.6)
	for _, x in { 7.5, 12, 16.5 } do
		circle(c, x, 10.7, 1.5, c.cut)
	end
end

DRAW.goals = function(c)
	part(c, 4, 4, 16, 18, 1.5)
	part(c, 8, 2, 8, 3.5, 1)
	part(c, 10, 4, 4, 1.5, 0, 0, c.cut)
	bar(c, 8, 13.5, 11, 16.5, 2.2, c.cut)
	bar(c, 11, 16.5, 16.5, 10, 2.2, c.cut)
end

-- Screenshot mode: a camera body with its lens (ShotMode).
DRAW.shutter = function(c)
	part(c, 8.6, 4, 6.8, 4, 1)
	part(c, 2, 6.5, 20, 14, 2)
	circle(c, 12, 13.2, 4.2, c.cut)
	circle(c, 12, 13.2, 2, c.color)
end

-- Save a picture: an arrow down into a tray.
DRAW.save = function(c)
	part(c, 10.4, 3, 3.2, 8.5, 0)
	part(c, 8.6, 7.6, 6.8, 6.8, 0.8, 45)
	part(c, 3, 14.5, 2.6, 6, 0.8)
	part(c, 18.4, 14.5, 2.6, 6, 0.8)
	part(c, 3, 18.2, 18, 2.8, 1)
end

-- Free camera: a house with an arrow sweeping round it (the web's orbit icon).
DRAW.orbit = function(c)
	part(c, 7.8, 8.8, 8.4, 6.2, 0.4)
	-- The roof: a turned square, only its top half showing.
	local roof = clip(c, 6, 4, 12, 4.9)
	part(inClip(c, roof, 6, 4, 12, 4.9), 9.03, 6.03, 5.94, 5.94, 0.3, 45)
	-- The sweep: the lower half of a flat ring round the house.
	local sweep = clip(c, 0, 10.6, 24, 9)
	local sub = inClip(c, sweep, 0, 10.6, 24, 9)
	local ell = part(sub, 2, 9, 20, 9, 4.5)
	ell.BackgroundTransparency = 1
	local k = ell:FindFirstChildOfClass("UICorner")
	if k then
		k.CornerRadius = UDim.new(0.5, 0)
	end
	local s = Instance.new("UIStroke")
	s.Thickness = 2.2 / 24 * c.size
	s.Color = c.color
	s.Parent = ell
	-- Its arrow head, pointing on round: a turned square, only its right half showing.
	local head = clip(c, 10.6, 14.8, 4.4, 6.4)
	part(inClip(c, head, 10.6, 14.8, 4.4, 6.4), 8.6, 16, 4, 4, 0.2, 45)
end

-- Back to the bird's-eye view: town blocks seen from above (the web's birdseye icon).
DRAW.birdseye = function(c)
	for _, at in { { 12, 7 }, { 6.5, 12.5 }, { 17.5, 12.5 }, { 12, 18 } } do
		part(c, at[1] - 3, at[2] - 3, 6, 6, 0.6, 45)
	end
end

DRAW.bolt = function(c)
	bar(c, 13.5, 2, 5.5, 12.5, 4.2)
	part(c, 5, 10.8, 13, 3.6, 1)
	bar(c, 17, 12.5, 9.5, 22, 4.2)
end

DRAW.soundOn = function(c)
	part(c, 3, 8, 5, 8, 1.5)
	part(c, 6.5, 6.5, 3, 11, 0.5)
	part(c, 9.2, 4.2, 3.8, 15.6, 1)
	local win = clip(c, 14, 0, 10, 24)
	local sub = inClip(c, win, 14, 0, 10, 24)
	ring(sub, 13.4, 12, 3.6, 2.2)
	ring(sub, 13.4, 12, 7.6, 2.2)
end

DRAW.soundOff = function(c)
	part(c, 3, 8, 5, 8, 1.5)
	part(c, 6.5, 6.5, 3, 11, 0.5)
	part(c, 9.2, 4.2, 3.8, 15.6, 1)
	bar(c, 16, 9, 22, 15, 2.2)
	bar(c, 22, 9, 16, 15, 2.2)
end

DRAW.trophy = function(c)
	part(c, 6, 2.5, 12, 6, 0.5)
	part(c, 6, 4, 12, 10.5, 6)
	part(c, 2.5, 4, 4.5, 2.2, 1)
	part(c, 2.5, 4, 2.2, 5.5, 1)
	part(c, 17, 4, 4.5, 2.2, 1)
	part(c, 19.3, 4, 2.2, 5.5, 1)
	part(c, 10.5, 13, 3, 5, 0)
	part(c, 6, 17, 12, 4.5, 1.5)
end

DRAW.road = function(c)
	bar(c, 9, 2.5, 4.5, 21.5, 3.5)
	bar(c, 15, 2.5, 19.5, 21.5, 3.5)
	part(c, 8, 2, 8, 20, 0)
	part(c, 11, 4.5, 2, 3, 0, 0, c.cut)
	part(c, 11, 10, 2, 3.5, 0, 0, c.cut)
	part(c, 11, 16, 2, 4, 0, 0, c.cut)
end

DRAW.bulldoze = function(c)
	part(c, 3, 9.5, 12, 6, 0.5)
	part(c, 10, 5, 5, 5, 0.5)
	part(c, 13.5, 7.5, 3.5, 8, 0.5)
	part(c, 18, 11, 3, 6.5, 0.5, 15)
	part(c, 2, 16, 16, 6, 3)
	for _, x in { 5, 10, 15 } do
		circle(c, x, 19, 1, c.cut)
	end
end

DRAW.move = function(c)
	part(c, 10.8, 4, 2.4, 16, 0.5)
	part(c, 4, 10.8, 16, 2.4, 0.5)
	for _, p in { { 12, 3.4 }, { 12, 20.6 }, { 3.4, 12 }, { 20.6, 12 } } do
		part(c, p[1] - 3, p[2] - 3, 6, 6, 0.5, 45)
	end
end

DRAW.land = function(c)
	part(c, 1.5, 4.8, 6, 15, 0.6, -4)
	part(c, 9, 4, 6, 15.5, 0.6, 4)
	part(c, 16.5, 4.5, 6, 15, 0.6, -4)
end

DRAW.merge = function(c)
	for _, p in { { 3, 3 }, { 13, 3 }, { 3, 13 }, { 13, 13 } } do
		part(c, p[1], p[2], 8, 8, 1)
	end
end

DRAW.rotate = function(c)
	ring(c, 12, 12, 7.5, 3)
	part(c, 14, 3, 7, 6, 0, 0, c.cut)
	local win = clip(c, 14, 2, 9, 9)
	local sub = inClip(c, win, 14, 2, 9, 9)
	part(sub, 15.5, 4.5, 6, 6, 0.4, 45)
end

DRAW.up = function(c)
	part(c, 8.5, 11, 7, 10.5, 0.5)
	local win = clip(c, 0, 0, 24, 12.2)
	local sub = inClip(c, win, 0, 0, 24, 12.2)
	part(sub, 5.6, 5.6, 12.8, 12.8, 0.8, 45)
end

DRAW.box = function(c)
	part(c, 2.5, 3, 19, 5, 1.5)
	part(c, 4, 9.5, 16, 11, 1.5)
	part(c, 9.5, 12, 5, 2, 1, 0, c.cut)
end

DRAW.filter = function(c)
	part(c, 3, 4, 18, 3, 1)
	bar(c, 4.5, 6, 10.8, 13.5, 3)
	bar(c, 19.5, 6, 13.2, 13.5, 3)
	part(c, 10, 12, 4, 9, 1)
end

DRAW.sort = function(c)
	part(c, 5.5, 7, 3, 14, 0.5)
	bar(c, 3, 9, 7, 3.5, 2.4)
	bar(c, 11, 9, 7, 3.5, 2.4)
	part(c, 15.5, 3, 3, 14, 0.5)
	bar(c, 13, 15, 17, 20.5, 2.4)
	bar(c, 21, 15, 17, 20.5, 2.4)
end

-- Full-colour coin: the web's CoinIcon, a gold coin with a $.
DRAW.coin = function(c)
	circle(c, 12, 12.8, 10.5, Color3.fromHex("#b86e00"))
	circle(c, 12, 11.6, 10.5, Color3.fromHex("#ffc533"))
	local face = circle(c, 12, 11.6, 7.6, Color3.fromHex("#ffd95c"))
	local s = Instance.new("UIStroke")
	s.Thickness = math.max(1, 1.4 / 24 * c.size)
	s.Color = Color3.fromHex("#e8a20c")
	s.Parent = face
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.FontFace = Font.fromEnum(Enum.Font.FredokaOne)
	t.Text = "$"
	t.TextColor3 = Color3.fromHex("#a35f00")
	t.TextSize = math.floor(c.size * 0.62)
	t.Parent = face
end

-- Full-colour fuel can: the web's FuelIcon, a red jerrycan with a white drop.
DRAW.fuel = function(c)
	part(c, 4, 3.5, 16, 19.5, 2, 0, Color3.fromHex("#9b1c1c"))
	part(c, 4, 2.5, 16, 19.5, 2, 0, Color3.fromHex("#f04438"))
	part(c, 8.5, 1.5, 4, 3, 0.5, 0, Color3.fromHex("#3a4148"))
	local white = Color3.new(1, 1, 1)
	circle(c, 12, 15.2, 3, white)
	part(c, 9.9, 10.6, 4.2, 4.2, 0.4, 45, white)
end

-- Draws icon `name` in a size-by-size frame. color: the glyph's colour; cut: the colour behind it,
-- for the holes (a door, a window, the checks of the flag).
function Icons.draw(name: string, parent: Instance, size: number, color: Color3?, cut: Color3?, position: UDim2?, anchor: Vector2?): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromOffset(size, size)
	holder.Position = position or UDim2.new()
	holder.AnchorPoint = anchor or Vector2.zero
	local c: Ctx = { holder = holder, size = size, color = color or Color3.new(1, 1, 1), cut = cut or LINE }
	local fn = DRAW[name]
	if fn then
		fn(c)
	end
	holder.Parent = parent
	return holder
end

-- A baked icon ("coin", "bucks", "parts", "fuel", "car" or "town"), size pixels square: vector
-- art baked into one picture by tools/icons/build.mjs, so it stays smooth and centred at any size.
-- Until that picture is uploaded, the coin is drawn with frames and the rest are emoji.
local EMOJI = { bucks = "💎", parts = "⚙️", fuel = "⛽", car = "🚗", town = "🏙️" }
function Icons.picture(kind: string, parent: Instance, size: number): GuiObject
	local IconImages = require(ReplicatedStorage.Shared.IconImages) :: any
	local at = IconImages.at[kind]
	if IconImages.sheet ~= 0 and at then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromOffset(size, size)
		img.ImageRectOffset = at
		img.ImageRectSize = Vector2.new(IconImages.size, IconImages.size)
		img.ResampleMode = Enum.ResamplerMode.Default
		Pictures.set(img, "Image", IconImages.sheet)
		-- For the previews (tools/emulate/render.mjs finds the sheet by this).
		img:SetAttribute("Key", "icons:icons")
		img.Parent = parent
		return img
	end
	if kind == "coin" then
		return Icons.draw("coin", parent, size)
	end
	local t = Instance.new("TextLabel")
	t.Name = "Icon"
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromOffset(size, size)
	t.Text = EMOJI[kind] or ""
	t.TextSize = math.floor(size * 0.8)
	t.Parent = parent
	return t
end

-- Recolours an icon drawn by Icons.draw (a tab turning on, a muted speaker): glyph parts only.
function Icons.tint(holder: Instance, from: Color3, to: Color3)
	for _, d in holder:GetDescendants() do
		if d:IsA("Frame") and d.BackgroundColor3 == from and d.BackgroundTransparency < 1 then
			d.BackgroundColor3 = to
		elseif d:IsA("UIStroke") and d.Color == from then
			d.Color = to
		end
	end
end

return Icons
