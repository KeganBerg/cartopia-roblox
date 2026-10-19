--!nocheck
-- Lays out a ScreenGui the way Roblox does (sizes and positions from UDim2 and AnchorPoint, list
-- and grid layouts, padding, size limits, automatic sizes) and returns plain tables for render.mjs
-- to draw. Covers what Cartopia's screens use, not all of Roblox's layout rules. Text widths for
-- AutomaticSize are estimated from the font, since there's no text engine here.

local Gui = {}

local function rect(x, y, w, h)
	return { x = x, y = y, w = w, h = h }
end

local function udim2(u, r)
	return u.X.Scale * r.w + u.X.Offset, u.Y.Scale * r.h + u.Y.Offset
end

local function child(inst, cls)
	return inst:FindFirstChildOfClass(cls)
end

local function hex(c)
	return c:ToHex()
end

local function enumName(e)
	return tostring(e):match("%.(%w+)$")
end

local function isText(g)
	return g:IsA("TextLabel") or g:IsA("TextButton") or g:IsA("TextBox")
end

local function fontOf(g)
	local ok, f = pcall(function()
		return g.FontFace
	end)
	if not ok or not f then
		return "FredokaOne", 400
	end
	local family = f.Family:match("families/(%w+)%.json") or "FredokaOne"
	local weights = { Thin = 100, ExtraLight = 200, Light = 300, Regular = 400, Medium = 500, SemiBold = 600, Bold = 700, ExtraBold = 800, Heavy = 900 }
	return family, weights[enumName(f.Weight)] or 400
end

-- Rough advance widths, as a share of the text size, for Fredoka One and Nunito ExtraBold.
local function charWidth(ch, family)
	local b = string.byte(ch)
	if b and b >= 0xF0 then
		return 1.15 -- emoji
	elseif b and b >= 0xE2 and b < 0xF0 then
		return 1.0 -- symbols (arrows, stars, gears)
	elseif ch == " " then
		return 0.26
	elseif ch:match("[il%.,:;!|'1]") then
		return 0.3
	elseif ch:match("%d") then
		return 0.58
	elseif ch:match("[MWmw]") then
		return 0.86
	elseif ch:match("%u") then
		return if family == "Nunito" then 0.66 else 0.64
	end
	return if family == "Nunito" then 0.54 else 0.55
end

local function textWidth(text, size, family)
	local w = 0
	for _, cp in utf8.codes(text) do
		w += charWidth(utf8.char(cp), family) * size
	end
	return w
end

Gui.textWidth = textWidth

local function guiKids(inst)
	local out = {}
	for _, c in inst:GetChildren() do
		if c:IsA("GuiObject") then
			table.insert(out, c)
		end
	end
	table.sort(out, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return out
end

local function padOf(g)
	local pad = child(g, "UIPadding")
	if not pad then
		return 0, 0, 0, 0
	end
	return pad.PaddingLeft.Offset, pad.PaddingRight.Offset, pad.PaddingTop.Offset, pad.PaddingBottom.Offset
end

-- A part as render.mjs draws it: shape, place (CFrame components), size and look.
function Gui.partOf(d)
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = d.CFrame:GetComponents()
	local shape = if d:IsA("MeshPart") then "mesh" elseif d:FindFirstChildOfClass("SpecialMesh") then "ellipsoid" else enumName(d.Shape)
	local surface = d:FindFirstChildOfClass("SurfaceGui")
	local label = surface and surface:FindFirstChildOfClass("TextLabel")
	return {
		shape = shape,
		mesh = d:GetAttribute("Mesh"),
		imported = if d:IsA("MeshPart") then d:GetAttribute("Imported") == true else nil,
		texture = (function()
			for _, t in d:GetChildren() do
				if t:IsA("Texture") and t:GetAttribute("Image") then
					return { image = t:GetAttribute("Image"), span = { t.StudsPerTileU, t.StudsPerTileV }, offset = { t.OffsetStudsU, t.OffsetStudsV }, transparency = t.Transparency, color = t.Color3:ToHex() }
				end
			end
			return nil
		end)(),
		-- Custom paint patterns (Models/Panels) and skins (Models/Skins): a tile on each of some
		-- faces, tinted and stacked by ZIndex.
		patterns = (function()
			local list = {}
			for _, t in d:GetChildren() do
				if t:IsA("Texture") and t:GetAttribute("Pattern") then
					table.insert(list, { image = t:GetAttribute("Pattern"), span = t.StudsPerTileU, face = enumName(t.Face), color = t.Color3:ToHex(), z = t.ZIndex, offset = { t.OffsetStudsU, t.OffsetStudsV }, transparency = t.Transparency })
				end
			end
			return if #list > 0 then list else nil
		end)(),
		cf = { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 },
		size = { d.Size.X, d.Size.Y, d.Size.Z },
		color = d.Color:ToHex(),
		transparency = d.Transparency,
		material = enumName(d.Material),
		-- A strip: labels or plain frames side by side across the face (kart sponsor boards, crowds).
		text = if surface and surface:GetAttribute("Strip") ~= nil then (function()
				local list = {}
				for _, c in surface:GetChildren() do
					if c:IsA("GuiObject") then
						table.insert(list, { x = c.Position.X.Scale, w = c.Size.X.Scale, bg = c.BackgroundColor3:ToHex(), text = if c:IsA("TextLabel") then c.Text else nil, fg = if c:IsA("TextLabel") then c.TextColor3:ToHex() else nil })
					end
				end
				return { strip = list, face = enumName(surface.Face) }
			end)()
			elseif label then {
				text = label.Text,
				fg = label.TextColor3:ToHex(),
				bg = label.BackgroundColor3:ToHex(),
				clear = label.BackgroundTransparency >= 1 or nil,
				stroke = if label.TextStrokeTransparency < 1 then label.TextStrokeColor3:ToHex() else nil,
			}
			elseif surface and surface:GetAttribute("Checker") then (function()
				local back = surface:FindFirstChildOfClass("Frame")
				local cell = back and back:FindFirstChildOfClass("Frame")
				return { checker = surface:GetAttribute("Checker"), fg = cell and cell.BackgroundColor3:ToHex() or "111111", bg = back and back.BackgroundColor3:ToHex() or "ffffff" }
			end)()
			else nil,
	}
end

local sizeOf

-- What a label shows: rich text's tags aren't drawn.
local function shownText(g): string
	if g.RichText then
		return (g.Text:gsub("<[^>]->", ""))
	end
	return g.Text
end

-- The size an AutomaticSize object grows to hold its text or its laid-out children. ownW/ownH:
-- its size before growing; children sized by scale follow it along an axis that doesn't grow.
local function contentSize(g, ownW, ownH)
	local l, r, t, b = padOf(g)
	-- A text object sizes to its text; a TextButton with no text (a tappable row) to its children.
	if isText(g) and g.Text ~= "" then
		local family = fontOf(g)
		local lines, widest = 0, 0
		for line in (shownText(g) .. "\n"):gmatch("(.-)\n") do
			lines += 1
			widest = math.max(widest, textWidth(line, g.TextSize, family))
		end
		return widest + l + r, lines * g.TextSize * 1.2 + t + b
	end
	local list = child(g, "UIListLayout")
	local kids = guiKids(g)
	local w, h = 0, 0
	-- As in Roblox, children sized by scale don't push an automatic size out (they'd follow it):
	-- only their offsets and their own automatic sizes count.
	local auto = enumName(g.AutomaticSize)
	local area = rect(0, 0, if auto == "Y" then math.max(0, ownW - l - r) else 0, if auto == "X" then math.max(0, ownH - t - b) else 0)
	local grid = child(g, "UIGridLayout")
	if grid then
		local cw = grid.CellSize.X.Offset + grid.CellSize.X.Scale * area.w
		local ch = grid.CellSize.Y.Offset + grid.CellSize.Y.Scale * area.h
		local px, py = grid.CellPadding.X.Offset, grid.CellPadding.Y.Offset
		local n = 0
		for _, k in kids do
			if k.Visible then
				n += 1
			end
		end
		local per = math.max(1, math.floor((area.w + px) / (cw + px)))
		local rows = math.ceil(n / per)
		return math.min(n, per) * (cw + px) - px + l + r, math.max(0, rows * (ch + py) - py) + t + b
	end
	if list then
		local horizontal = enumName(list.FillDirection) == "Horizontal"
		local gap = list.Padding.Offset
		for i, k in kids do
			if k.Visible then
				local kw, kh = sizeOf(k, area)
				if horizontal then
					w += kw + (if i > 1 then gap else 0)
					h = math.max(h, kh)
				else
					h += kh + (if i > 1 then gap else 0)
					w = math.max(w, kw)
				end
			end
		end
	else
		for _, k in kids do
			local kw, kh = sizeOf(k, area)
			local x, y = udim2(k.Position, area)
			w = math.max(w, x + kw)
			h = math.max(h, y + kh)
		end
	end
	return w + l + r, h + t + b
end

sizeOf = function(g, parent)
	local w, h = udim2(g.Size, parent)
	local auto = enumName(g.AutomaticSize)
	if auto and auto ~= "None" then
		local cw, ch = contentSize(g, w, h)
		if auto == "X" or auto == "XY" then
			w = math.max(w, cw)
		end
		if auto == "Y" or auto == "XY" then
			h = math.max(h, ch)
		end
	end
	local lim = child(g, "UISizeConstraint")
	if lim then
		w = math.clamp(w, lim.MinSize.X, lim.MaxSize.X)
		h = math.clamp(h, lim.MinSize.Y, lim.MaxSize.Y)
	end
	local ratio = child(g, "UIAspectRatioConstraint")
	if ratio then
		h = w / ratio.AspectRatio
	end
	return w, h
end

local function inner(g, r)
	local pad = child(g, "UIPadding")
	if not pad then
		return r
	end
	local l = pad.PaddingLeft.Scale * r.w + pad.PaddingLeft.Offset
	local rr = pad.PaddingRight.Scale * r.w + pad.PaddingRight.Offset
	local t = pad.PaddingTop.Scale * r.h + pad.PaddingTop.Offset
	local b = pad.PaddingBottom.Scale * r.h + pad.PaddingBottom.Offset
	return rect(r.x + l, r.y + t, r.w - l - rr, r.h - t - b)
end

local function node(g, r)
	local n = { abs = { r.x, r.y, r.w, r.h }, visible = g.Visible, children = {}, z = g.ZIndex, rot = g.Rotation }
	-- A harness can ask where each object ends up (the tutorial's pointing hand, in clicks.luau).
	if Gui.onNode then
		Gui.onNode(g, n)
	end
	n.bg = hex(g.BackgroundColor3)
	n.bgT = g.BackgroundTransparency
	local corner = child(g, "UICorner")
	if corner then
		n.corner = corner.CornerRadius.Offset + corner.CornerRadius.Scale * math.min(r.w, r.h)
	end
	local grad = child(g, "UIGradient")
	if grad and grad.Enabled then
		local stops = {}
		for _, k in grad.Color.Keypoints do
			table.insert(stops, { k.Time, hex(k.Value) })
		end
		local tk = grad.Transparency.Keypoints
		n.grad = { stops = stops, rot = grad.Rotation, t0 = tk[1].Value, t1 = tk[#tk].Value }
	end
	for _, s in g:GetChildren() do
		if s:IsA("UIStroke") and s.Enabled then
			local info = { s.Thickness, hex(s.Color), s.Transparency }
			if enumName(s.ApplyStrokeMode) == "Border" then
				n.stroke = info
			else
				n.textStroke = info
			end
		end
	end
	if isText(g) then
		n.text = shownText(g)
		n.textColor = hex(g.TextColor3)
		n.textT = g.TextTransparency
		n.textSize = g.TextSize
		n.xAlign = enumName(g.TextXAlignment)
		n.yAlign = enumName(g.TextYAlignment)
		n.wrapped = g.TextWrapped
		n.font, n.weight = fontOf(g)
		if g:IsA("TextBox") and g.Text == "" then
			n.text = g.PlaceholderText
			n.textColor = hex(g.PlaceholderColor3)
		end
	end
	if (g:IsA("ImageLabel") or g:IsA("ImageButton")) and g:GetAttribute("Key") then
		-- Which picture (render.mjs finds it in build/splash), its tint and how it's fitted.
		n.image = { key = g:GetAttribute("Key"), color = hex(g.ImageColor3), t = g.ImageTransparency, scale = enumName(g.ScaleType) }
		-- A piece of a sheet (ImageRectOffset/Size), as the Call Cards use.
		if g.ImageRectSize.X > 0 then
			n.image.rect = { g.ImageRectOffset.X, g.ImageRectOffset.Y, g.ImageRectSize.X, g.ImageRectSize.Y }
		end
	end
	if g:IsA("ViewportFrame") then
		-- What it shows: its parts and camera, which render.mjs draws as a little picture.
		local parts = {}
		for _, d in g:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(parts, Gui.partOf(d))
			end
		end
		local cam = g:FindFirstChildOfClass("Camera")
		-- (An empty one would encode as an object, not a list.)
		n.viewport = if #parts == 0 then nil else {
			parts = parts,
			cam = cam and { cf = { cam.CFrame:GetComponents() }, fov = cam.FieldOfView } or nil,
			ambient = hex(g.Ambient),
		}
	end
	if g.ClipsDescendants or g:IsA("ScrollingFrame") or g:IsA("CanvasGroup") then
		n.clip = true
	end
	return n
end

-- Set while Gui.dump runs for rects only (noBoards): hidden branches are skipped, not laid out.
local lean = false

local function layout(g, r)
	local n = node(g, r)
	if lean and not g.Visible then
		return n
	end
	local area = inner(g, r)
	local kids = guiKids(g)
	local list = child(g, "UIListLayout")
	local grid = child(g, "UIGridLayout")
	if list then
		local horizontal = enumName(list.FillDirection) == "Horizontal"
		local gap = list.Padding.Offset + list.Padding.Scale * (if horizontal then area.w else area.h)
		local sizes, total, shown = {}, 0, 0
		for i, k in kids do
			local w, h = sizeOf(k, area)
			sizes[i] = { w, h }
			if k.Visible then
				total += (if horizontal then w else h) + (if shown > 0 then gap else 0)
				shown += 1
			end
		end
		-- Flex fill: what's left of the row is shared out, so the items stretch to its ends.
		if horizontal and enumName(list.HorizontalFlex) == "Fill" and shown > 0 and total < area.w then
			local extra = (area.w - total) / shown
			for i, k in kids do
				if k.Visible then
					sizes[i][1] += extra
				end
			end
			total = area.w
		end
		local ha = enumName(list.HorizontalAlignment)
		local va = enumName(list.VerticalAlignment)
		local start = 0
		if horizontal and ha == "Center" then
			start = (area.w - total) / 2
		elseif horizontal and ha == "Right" then
			start = area.w - total
		elseif not horizontal and va == "Center" then
			start = (area.h - total) / 2
		elseif not horizontal and va == "Bottom" then
			start = area.h - total
		end
		local at = start
		for i, k in kids do
			local w, h = sizes[i][1], sizes[i][2]
			local x, y
			if horizontal then
				x = area.x + at
				y = area.y + (if va == "Center" then (area.h - h) / 2 elseif va == "Bottom" then area.h - h else 0)
				if k.Visible then
					at += w + gap
				end
			else
				x = area.x + (if ha == "Center" then (area.w - w) / 2 elseif ha == "Right" then area.w - w else 0)
				y = area.y + at
				if k.Visible then
					at += h + gap
				end
			end
			table.insert(n.children, layout(k, rect(x, y, w, h)))
		end
	elseif grid then
		local cw, ch = udim2(grid.CellSize, area)
		local px, py = udim2(grid.CellPadding, area)
		local per = math.max(1, math.floor((area.w + px) / (cw + px)))
		local i = 0
		for _, k in kids do
			if k.Visible then
				local col, row = i % per, i // per
				table.insert(n.children, layout(k, rect(area.x + col * (cw + px), area.y + row * (ch + py), cw, ch)))
				i += 1
			end
		end
	else
		for _, k in kids do
			local w, h = sizeOf(k, area)
			local x, y = udim2(k.Position, area)
			x -= k.AnchorPoint.X * w
			y -= k.AnchorPoint.Y * h
			table.insert(n.children, layout(k, rect(area.x + x, area.y + y, w, h)))
		end
	end
	-- A scrolled list shows from where it's scrolled to.
	if g:IsA("ScrollingFrame") then
		local dx, dy = g.CanvasPosition.X, g.CanvasPosition.Y
		if dx ~= 0 or dy ~= 0 then
			local function shift(c)
				c.abs[1] -= dx
				c.abs[2] -= dy
				for _, cc in c.children do
					shift(cc)
				end
			end
			for _, c in n.children do
				shift(c)
			end
		end
	end
	-- A UIScale grows or shrinks the object and everything in it about its anchor point (the HUD's
	-- root on a phone).
	local scale = child(g, "UIScale")
	if scale and scale.Scale ~= 1 then
		local s = scale.Scale
		local ax, ay = r.x + g.AnchorPoint.X * r.w, r.y + g.AnchorPoint.Y * r.h
		local function shrink(c)
			c.abs = { ax + (c.abs[1] - ax) * s, ay + (c.abs[2] - ay) * s, c.abs[3] * s, c.abs[4] * s }
			c.textSize = c.textSize and c.textSize * s
			c.corner = c.corner and c.corner * s
			c.stroke = c.stroke and { c.stroke[1] * s, c.stroke[2], c.stroke[3] }
			c.textStroke = c.textStroke and { c.textStroke[1] * s, c.textStroke[2], c.textStroke[3] }
			for _, cc in c.children do
				shrink(cc)
			end
		end
		shrink(n)
	end
	return n
end

-- screen: { w, h }. Returns a list of top-level nodes (one per ScreenGui child), then one node per
-- BillboardGui beside the ScreenGui (job bubbles) with `at`, its spot in the world.
-- lean: only where things sit on screen (the tutorial walk calls this twice a frame): no boards and
-- nothing under a hidden frame. Laying all of those out made the tutorial's race take hours.
function Gui.dump(screenGui, w: number, h: number, leanDump: boolean?)
	lean = leanDump == true
	local out = {}
	local screen = rect(0, 0, w, h)
	for _, k in guiKids(screenGui) do
		local kw, kh = sizeOf(k, screen)
		local x, y = udim2(k.Position, screen)
		table.insert(out, layout(k, rect(x - k.AnchorPoint.X * kw, y - k.AnchorPoint.Y * kh, kw, kh)))
	end
	if screenGui.Parent and not lean then
		for _, b in screenGui.Parent:GetDescendants() do
			if b:IsA("BillboardGui") and b.Adornee then
				local bw, bh = b.Size.X.Offset, b.Size.Y.Offset
				local a = b.Adornee
				local at = (if a:IsA("Model") then a:GetPivot() else a.CFrame).Position + b.StudsOffsetWorldSpace
				local box = rect(0, 0, bw, bh)
				local kids = {}
				for _, k in guiKids(b) do
					local kw, kh = sizeOf(k, box)
					local x, y = udim2(k.Position, box)
					table.insert(kids, layout(k, rect(x - k.AnchorPoint.X * kw, y - k.AnchorPoint.Y * kh, kw, kh)))
				end
				-- A switched-off board (badges hidden in edit mode) is kept, hidden.
				table.insert(out, { billboard = true, visible = b.Enabled, at = { at.X, at.Y, at.Z }, abs = { 0, 0, bw, bh }, bgT = 1, children = kids, z = 0, rot = 0 })
			end
		end
	end
	lean = false
	return out
end

return Gui
