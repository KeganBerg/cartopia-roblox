--!nocheck
-- Lays out a ScreenGui the way Roblox does (sizes and positions from UDim2 and AnchorPoint, list
-- and grid layouts, padding, size limits) and returns plain tables for render.mjs to draw.
-- Covers what Cartopia's screens use, not all of Roblox's layout rules.

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

local function sizeOf(g, parent)
	local w, h = udim2(g.Size, parent)
	local lim = child(g, "UISizeConstraint")
	if lim then
		w = math.clamp(w, lim.MinSize.X, lim.MaxSize.X)
		h = math.clamp(h, lim.MinSize.Y, lim.MaxSize.Y)
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

local function node(g, r)
	local n = { abs = { r.x, r.y, r.w, r.h }, visible = g.Visible, children = {} }
	if not g:IsA("ScrollingFrame") and not g:IsA("ViewportFrame") or true then
		n.bg = hex(g.BackgroundColor3)
		n.bgT = g.BackgroundTransparency
	end
	local corner = child(g, "UICorner")
	if corner then
		n.corner = corner.CornerRadius.Offset + corner.CornerRadius.Scale * math.min(r.w, r.h)
	end
	local grad = child(g, "UIGradient")
	if grad then
		local k = grad.Color.Keypoints
		n.grad = { hex(k[1].Value), hex(k[#k].Value) }
	end
	for _, s in g:GetChildren() do
		if s:IsA("UIStroke") then
			if enumName(s.ApplyStrokeMode) == "Border" then
				n.stroke = { s.Thickness, hex(s.Color) }
			else
				n.textStroke = true
			end
		end
	end
	if g:IsA("TextLabel") or g:IsA("TextButton") then
		n.text = g.Text
		n.textColor = hex(g.TextColor3)
		n.textSize = g.TextSize
		n.xAlign = enumName(g.TextXAlignment)
	end
	if g:IsA("ViewportFrame") then
		n.viewport = true
	end
	if g.ClipsDescendants or g:IsA("ScrollingFrame") then
		n.clip = true
	end
	return n
end

local function layout(g, r)
	local n = node(g, r)
	local area = inner(g, r)
	local kids = guiKids(g)
	local list = child(g, "UIListLayout")
	local grid = child(g, "UIGridLayout")
	if list then
		local horizontal = enumName(list.FillDirection) == "Horizontal"
		local gap = list.Padding.Offset + list.Padding.Scale * (if horizontal then area.w else area.h)
		local sizes, total = {}, 0
		for i, k in kids do
			local w, h = sizeOf(k, area)
			sizes[i] = { w, h }
			total += (if horizontal then w else h) + (if i > 1 then gap else 0)
		end
		local start = 0
		local ha = enumName(list.HorizontalAlignment)
		if horizontal and ha == "Center" then
			start = (area.w - total) / 2
		elseif horizontal and ha == "Right" then
			start = area.w - total
		end
		local at = start
		for i, k in kids do
			local w, h = sizes[i][1], sizes[i][2]
			local x, y
			if horizontal then
				x, y = area.x + at, area.y
				at += w + gap
			else
				x = area.x + (if ha == "Center" then (area.w - w) / 2 elseif ha == "Right" then area.w - w else 0)
				y = area.y + at
				at += h + gap
			end
			table.insert(n.children, layout(k, rect(x, y, w, h)))
		end
	elseif grid then
		local cw, ch = udim2(grid.CellSize, area)
		local px, py = udim2(grid.CellPadding, area)
		local per = math.max(1, math.floor((area.w + px) / (cw + px)))
		for i, k in kids do
			local col, row = (i - 1) % per, (i - 1) // per
			table.insert(n.children, layout(k, rect(area.x + col * (cw + px), area.y + row * (ch + py), cw, ch)))
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
	return n
end

-- screen: { w, h }. Returns a list of top-level nodes (one per ScreenGui child).
function Gui.dump(screenGui, w: number, h: number)
	local out = {}
	local screen = rect(0, 0, w, h)
	for _, k in guiKids(screenGui) do
		local kw, kh = sizeOf(k, screen)
		local x, y = udim2(k.Position, screen)
		table.insert(out, layout(k, rect(x - k.AnchorPoint.X * kw, y - k.AnchorPoint.Y * kh, kw, kh)))
	end
	return out
end

return Gui
