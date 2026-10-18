--!strict
-- Edit mode, as the web game's EditBar (ui/Menus.tsx): a navy hint over a dock of tools (Road,
-- Bulldoze, Move, Land, Merge, Rotate and Upgrade when they apply, Inventory, Shop, Done), and
-- the town under it answering taps and drags for the picked tool. Placing a building from the
-- Shop or the Inventory is the same mode with a see-through copy that follows the pointer.
-- Fit checks use the web game's own rules on the client's copy of the town; the server checks
-- again when it runs the action.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local merge = require(Game.merge) :: any
local placementRules = require(Game.placement) :: any
local lualib = require(Game.lualib_bundle) :: any
local Remote = require(script.Parent.Remote)
local Town = require(script.Parent.Town)
local TownCamera = require(script.Parent.TownCamera)
local Ui = require(script.Parent.Ui)
local Icons = require(script.Parent.Icons)
local Thumb = require(script.Parent.Thumb)
local Sfx = require(script.Parent.Sounds.Sfx)

local Placement = {}

type Mode = "place" | "road" | "bulldoze" | "move" | "land" | "merge"
local mode: Mode? = nil
local placing: string? = nil -- the building being placed
local storedUid: string? = nil -- placing it from the Inventory
local again: string? = nil -- just built: the Again tool builds another
local selected: string? = nil -- Move: the picked building
local rot = 0
-- Until the player turns it, a new building faces the nearest road, as on the web.
local rotated = false
local preview: { x: number, z: number }? = nil -- touch: the first tap previews, a second builds

local ctx: any = nil
local root: GuiObject? = nil
local bar: Frame? = nil
local hint: TextLabel? = nil
local measure: TextLabel? = nil
local dockShadow: Frame? = nil
local tools: Frame? = nil
local toolsKey = ""
local ghost: Model? = nil
local plate: Part? = nil
local marks: Folder? = nil -- For Sale plots and Merge badges
local pick: SelectionBox? = nil
local conns: { RBXScriptConnection } = {}
local onChange: (() -> ())? = nil

-- A drag in progress: laying road / bulldozing tiles, or carrying a building.
local held: InputObject? = nil
local lastTile = ""
local carry: { uid: string, x: number, z: number, block: any? }? = nil

local TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local function state(): any
	return store.useGame.getState()
end

local function findBuilding(uid: string?): any?
	for _, b in state().buildings do
		if b.uid == uid then
			return b
		end
	end
	return nil
end

-- The merged block a building belongs to, if any (game/merge.ts groupOf).
local function blockOf(uid: string?): any?
	if not uid then
		return nil
	end
	return merge.groupOf(state().buildings, uid)
end

local function modelOf(uid: string): Model?
	local f = Town.folder()
	local list = f and f:FindFirstChild("Buildings")
	if not list then
		return nil
	end
	for _, m in list:GetChildren() do
		if m:GetAttribute("Uid") == uid then
			return m :: Model
		end
	end
	return nil
end

local function lot(def: string, r: number?): (number, number)
	local wh = store.lotSize(def, r)
	return wh[1], wh[2]
end

local function chosen(): number?
	return if rotated then rot else nil
end

-- Top-left tile of the lot for a pointer over tile (tx, tz).
local function lotAt(def: string, tx: number, tz: number, r: number?): (number, number, number, number)
	local w, h = lot(def, r)
	return tx - (w - 1) // 2, tz - (h - 1) // 2, w, h
end

local function tileAt(screen: Vector2): (number?, number?)
	local p = Town.groundAt(screen)
	if not p then
		return nil, nil
	end
	return Town.worldToTile(p)
end

local function hintText(): string
	local m = mode
	if m == "land" then
		return "Tap a For Sale sign to buy land"
	elseif m == "merge" then
		local any = #merge.mergeCandidates(state().buildings) > 0
		return if any then "Tap a Merge badge to combine buildings" else "Line up 2 or 4 matching buildings · up to +50% 💰"
	elseif m == "road" then
		return "Drag to lay road · $10 a tile"
	elseif m == "bulldoze" then
		return "Drag to remove · buildings go to Inventory"
	elseif m == "move" and again and selected then
		return "Built! Drag or rotate it"
	elseif m == "move" then
		return if selected then "Drag to move, or rotate it" else "Drag a building, or tap one to pick it"
	end
	local name = if placing then data.buildingDef(placing).name else ""
	return `{if TOUCH then "Tap to preview, tap again to build" else "Click to place"} {name}`
end

-- ── The plate under the pointer, the ghost, the marks ───────────────────────────────────────

local drawMergeBadges: (Instance, any) -> ()

local function clearMarks()
	if marks then
		marks:Destroy()
		marks = nil
	end
	if pick then
		pick:Destroy()
		pick = nil
	end
end

local function makeGhost(def: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local src = lib and (lib :: any).Buildings:FindFirstChild(def)
	if not src then
		return nil
	end
	local m = src:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = math.max(d.Transparency, 0.35)
			d.CanQuery = false
			d.CanCollide = false
			d.CastShadow = false
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	m.Parent = workspace
	return m
end

local function ensurePlate(): Part
	if not plate then
		plate = Ui.new("Part", {
			Name = "EditPlate",
			Anchored = true,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
			Transparency = 0.45,
			Material = Enum.Material.Neon,
			Size = Vector3.new(1, 0.2, 1),
			Parent = workspace,
		})
	end
	return plate :: Part
end

local function showPlate(x: number, z: number, w: number, h: number, color: string, lift: number?)
	local tile = Town.tileSize()
	local c = Town.tileToWorld(x + (w - 1) / 2, z + (h - 1) / 2)
	if not c then
		return
	end
	local p = ensurePlate()
	p.Size = Vector3.new(w * tile, 0.2, h * tile)
	p.CFrame = CFrame.new(c + Vector3.new(0, lift or 0.4, 0))
	p.Color = Color3.fromHex(color)
	p.Transparency = 0.45
end

local function hidePlate()
	if plate then
		plate.Transparency = 1
	end
end

-- The picked building gets a yellow outline.
local function outline()
	if pick then
		pick:Destroy()
		pick = nil
	end
	local m = selected and modelOf(selected)
	if m then
		pick = Ui.new("SelectionBox", { Adornee = m, Color3 = Color3.fromHex("#ffd84a"), LineThickness = 0.4, SurfaceTransparency = 1, Parent = workspace })
	end
end

-- Merge mode's badges (ui/Badges.tsx MergeBadges), over the middle of each block: a purple
-- "🧩 Merge ×n" with the gain it brings on every block that could merge (×2 and ×4 at one corner
-- each get their own), and 🔄, the gain chip and ✂️ Split on every merged one.
local MERGE_PURPLE = Color3.fromHex("#7e57c2")
local PAIR_PURPLE = Color3.fromHex("#9575cd")
local SPLIT_INK = Color3.fromHex("#4527a0")
local SPLIT_EDGE = Color3.fromHex("#b39ddb")
local GAIN_INK = Color3.fromHex("#4e342e")
local GAIN_GOLD = Color3.fromHex("#ffd54f")

-- The merge bonus as a chip (Badges.tsx Gain): 💰+25% for a business, ⛽+25% for houses and gas
-- stations, nothing for decor.
local function gainText(def: string, n: number): string?
	local icon = data.mergeGain(data.buildingDef(def))
	if not icon then
		return nil
	end
	return `{icon}+{math.round(data.mergeBonus(n) * 100)}%`
end

-- Badge height over a block: as tall as its model grows (Badges.tsx lift).
local function lift(g: any): number
	return if g.cols == g.rows then g.cols else math.min(g.cols, g.rows)
end

-- An invisible spot over a block's middle for its badges to hang on.
local function spotOver(folder: Instance, g: any, y: number): BasePart?
	local c = Town.tileToWorld(g.x + (g.w - 1) / 2, g.z + (g.h - 1) / 2)
	if not c then
		return nil
	end
	return Ui.new("Part", { Name = "MergeSpot", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Transparency = 1, Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(c + Vector3.new(0, y, 0)), Parent = folder })
end

-- A small white badge button (.badge-split); returns its width.
local function splitButton(parent: Instance, x: number, text: string, onClick: () -> ()): number
	local w = Ui.textWidth(text, 13) + 18
	local _, face = Ui.shadowed({ Position = UDim2.fromOffset(x, 7), Size = UDim2.fromOffset(w, 30), Parent = parent }, { radius = 15, stroke = 2, drop = 3, dark = 0.3, class = "TextButton", color = Ui.WHITE, strokeColor = SPLIT_EDGE })
	Ui.text({ Text = text, TextSize = 13, TextColor3 = SPLIT_INK, Size = UDim2.fromScale(1, 1), Parent = face })
	face.Activated:Connect(onClick)
	return w
end

-- The yellow gain chip (.merge-gain); returns its width.
local function gainChip(parent: Instance, x: number, y: number, text: string, h: number, edge: Color3?): number
	local w = Ui.textWidth(text, 13) + 12
	local chip = Ui.new("Frame", { Name = "Gain", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h), BackgroundColor3 = GAIN_GOLD, Parent = parent }, {
		Ui.corner(h // 2),
		Ui.text({ Text = text, TextSize = 13, TextColor3 = GAIN_INK, Size = UDim2.fromScale(1, 1) }),
	})
	if edge then
		Ui.stroke(2, edge).Parent = chip
	end
	return w
end

drawMergeBadges = function(folder: Instance, s: any)
	local merges = merge.mergeGroups(s.buildings)
	local n = 0
	for _, c in merge.mergeCandidates(s.buildings, merges) do
		if n >= 16 then
			break
		end
		local spot = spotOver(folder, c, 12 * lift(c) + 4)
		if not spot then
			continue
		end
		n += 1
		local count = #c.members
		local label = `🧩 Merge ×{count}`
		local gain = gainText(c.anchor.def, count)
		local size = if count == 2 then 13 else 15
		local lw = Ui.textWidth(label, size)
		local gw = if gain then Ui.textWidth(gain, 13) + 12 else 0
		local w = lw + 20 + (if gain then gw + 6 else 0)
		local sign = Ui.new("BillboardGui", { Name = "Merge", Adornee = spot, AlwaysOnTop = true, Active = true, Size = UDim2.fromOffset(w, 40), MaxDistance = 2000, Parent = folder })
		local uid, code = c.anchor.uid, c.code
		sign:SetAttribute("Anchor", uid)
		sign:SetAttribute("Code", code)
		local _, face = Ui.shadowed({ Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 4), Parent = sign }, { radius = 16, stroke = 2, drop = 3, dark = 0.3, class = "TextButton", color = if count == 2 then PAIR_PURPLE else MERGE_PURPLE, strokeColor = Ui.WHITE })
		Ui.text({ Text = label, TextSize = size, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, lw, 1, 0), Shadow = 1, ShadowColor = Ui.BLACK, ShadowTransparency = 0.65, Parent = face })
		if gain then
			gainChip(face, lw + 16, 6, gain, 20)
		end
		face.Activated:Connect(function()
			Remote.act("mergeBlock", uid, code)
		end)
	end
	local k = 0
	merges.groups:forEach(function(_, g: any)
		if k >= 16 then
			return
		end
		local spot = spotOver(folder, g, 6 * lift(g) + 4)
		if not spot then
			return
		end
		k += 1
		local uid = g.anchor.uid
		local gain = gainText(g.anchor.def, #g.members)
		local w = Ui.textWidth("🔄", 13) + 18 + 6 + Ui.textWidth("✂️ Split", 13) + 18 + (if gain then Ui.textWidth(gain, 13) + 12 + 6 else 0)
		local sign = Ui.new("BillboardGui", { Name = "Split", Adornee = spot, AlwaysOnTop = true, Active = true, Size = UDim2.fromOffset(w, 40), MaxDistance = 2000, Parent = folder })
		local x = splitButton(sign, 0, "🔄", function()
			Remote.act("rotateBlock", uid)
		end) + 6
		if gain then
			x += gainChip(sign, x, 5, gain, 28, Ui.WHITE) + 6
		end
		splitButton(sign, x, "✂️ Split", function()
			Remote.act("splitBlock", uid)
		end)
	end)
end

-- For Sale signs on the plots next to the town, and Merge badges over buildings that line up.
-- Both lists are short (the plots around the town; a handful of matches), so they stay bounded.
local function drawMarks()
	clearMarks()
	local holder = root and root:FindFirstAncestorOfClass("PlayerGui")
	if not holder or (mode ~= "land" and mode ~= "merge") then
		outline()
		return
	end
	local folder = Ui.new("Folder", { Name = "EditMarks", Parent = holder })
	marks = folder
	local s = state()
	if mode == "land" then
		local tile = Town.tileSize()
		local price = data.plotPrice(#s.land - #data.START_LAND)
		for i, p in store.buyablePlots(s.land) do
			if i > 16 then
				break
			end
			local px, pz = p[1], p[2]
			local c = Town.tileToWorld(px * data.PLOT + (data.PLOT - 1) / 2, pz * data.PLOT + (data.PLOT - 1) / 2)
			if not c then
				continue
			end
			local part = Ui.new("Part", {
				Name = "ForSale",
				Anchored = true,
				CanCollide = false,
				CanQuery = false,
				CastShadow = false,
				Material = Enum.Material.Neon,
				Color = Color3.fromHex("#8ef05c"),
				Transparency = 0.7,
				Size = Vector3.new(data.PLOT * tile - 2, 0.2, data.PLOT * tile - 2),
				CFrame = CFrame.new(c + Vector3.new(0, 0.3, 0)),
				Parent = folder,
			})
			local sign = Ui.new("BillboardGui", { Adornee = part, AlwaysOnTop = true, Active = true, Size = UDim2.fromOffset(120, 46), StudsOffsetWorldSpace = Vector3.new(0, 8, 0), MaxDistance = 2000, Parent = folder })
			local _, face = Ui.buy({ Size = UDim2.new(1, 0, 1, -4), Position = UDim2.fromOffset(0, 3), Parent = sign }, `For sale · ${Ui.compact(price)}`, if s.coins >= price then "green" else "broke", function()
				Remote.act("buyPlot", px, pz)
			end, 14)
			local _ = face
		end
	else
		drawMergeBadges(folder, s)
	end
end

-- ── The bar ─────────────────────────────────────────────────────────────────────────────────

local function setMode(m: Mode?)
	mode = m
	preview = nil
	if m ~= "move" then
		selected = nil
		again = nil
	end
	if m ~= "place" then
		placing = nil
		storedUid = nil
		if ghost then
			ghost:Destroy()
			ghost = nil
		end
	end
	hidePlate()
	-- Laying road and bulldozing take drags; elsewhere a drag pans the town.
	TownCamera.setPanEnabled(m ~= "road" and m ~= "bulldoze")
	Placement.refresh()
end

local function tool(order: number, icon: string, label: string, active: boolean, kind: string?, onClick: () -> (), count: number?)
	local holder = Ui.new("Frame", { Name = label, LayoutOrder = order, Size = UDim2.fromOffset(if kind == "done" then 62 else 58, 54), BackgroundTransparency = 1, Parent = tools })
	local face: GuiButton
	local ink = Color3.fromHex("#4a6283")
	local glyph = Ui.BLUE
	local cut = Ui.SHEET
	if active or kind == "done" then
		local colors = if kind == "done" then "green" else "tab"
		local c = Ui.colors(colors)
		local _, f = Ui.button({ Position = UDim2.fromOffset(if kind == "done" then 4 else 0, 2), Size = UDim2.new(1, if kind == "done" then -4 else 0, 1, -2), Parent = holder }, colors, onClick, {
			radius = 14,
			stroke = 2,
			drop = 2,
			dark = 0.3,
			strokeColor = if kind == "done" then Color3.fromHex("#1d6b22") else Ui.LINE,
			gloss = 0.5,
			shade = 1,
		})
		face = f
		ink = if kind == "done" then Ui.WHITE else Ui.LINE
		glyph = ink
		cut = Color3.fromHex(c[1]):Lerp(Color3.fromHex(c[2]), 0.4)
	else
		face = Ui.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = holder })
		face.Activated:Connect(onClick)
	end
	Icons.draw(icon, face, 24, glyph, cut, UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0))
	Ui.text({ Text = label, TextSize = 11, TextColor3 = ink, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 13), Shadow = if kind == "done" then 1.5 else nil, ShadowColor = Ui.BLACK, ShadowTransparency = 0.7, Parent = face })
	if count and count > 0 then
		Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromHex("#e53935"), ZIndex = 3, Parent = holder }, {
			Ui.round(),
			Ui.stroke(2, Ui.WHITE),
			Ui.text({ Text = tostring(count), TextSize = 11, Size = UDim2.fromScale(1, 1), ZIndex = 3 }),
		})
	end
end

local function rotateCurrent()
	if mode == "place" then
		rot = ((rotated and rot or 0) + 1) % 4
		rotated = true
		preview = nil
	elseif mode == "move" and selected then
		local b = findBuilding(selected)
		if b and blockOf(b.uid) then
			-- A merged block turns as one building (store rotateBlock).
			Remote.act("rotateBlock", b.uid)
		elseif b then
			-- placement.ts rotateSelected: a click when it turns, the error buzz when there's no room.
			local ok, moved = Remote.act("moveBuilding", b.uid, b.x, b.z, ((b.rot or 0) + 1) % 4)
			if ok and moved ~= false then
				Sfx.click()
			else
				Sfx.error()
			end
		end
	end
end

-- Rebuilds the tools only when the set of tools changes, never on a timer.
local function drawTools()
	if not tools then
		return
	end
	local s = state()
	local b = findBuilding(selected)
	local canUp = b ~= nil and data.upgradable(data.buildingDef(b.def))
	local stored = if s.stored then #s.stored else 0
	local key = `{mode}|{selected ~= nil}|{canUp}|{again ~= nil}|{stored}|{placing ~= nil}`
	if key == toolsKey then
		return
	end
	toolsKey = key
	for _, c in (tools :: Frame):GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local n = 0
	local function add(icon: string, label: string, active: boolean, kind: string?, onClick: () -> (), count: number?)
		n += 1
		tool(n, icon, label, active, kind, onClick, count)
	end
	add("road", "Road", mode == "road", nil, function() setMode("road") end)
	add("bulldoze", "Bulldoze", mode == "bulldoze", nil, function() setMode("bulldoze") end)
	add("move", "Move", mode == "move", nil, function() setMode("move") end)
	add("land", "Land", mode == "land", nil, function() setMode("land") end)
	add("merge", "Merge", mode == "merge", nil, function() setMode("merge") end)
	if (mode == "place" and placing) or (mode == "move" and selected) then
		add("rotate", "Rotate", false, nil, rotateCurrent)
	end
	if mode == "move" and selected and canUp then
		add("up", "Upgrade", false, nil, function()
			ctx.open("upgrade", selected)
		end)
	end
	if mode == "move" and again then
		add("plus", "Again", false, nil, function()
			(Placement :: any).place(again, root, ctx)
		end)
	end
	add("box", "Inventory", false, nil, function()
		ctx.open("inventory")
	end, stored)
	add("shop", "Shop", false, nil, function()
		ctx.open("shop")
	end)
	add("check", "Done", false, "done", function()
		Placement.cancel()
	end)
	-- The dock hugs its tools.
	local w = 0
	for _, c in (tools :: Frame):GetChildren() do
		if c:IsA("Frame") then
			w += c.Size.X.Offset + 4
		end
	end
	if dockShadow then
		dockShadow.Size = UDim2.fromOffset(w - 4 + 16, 54 + 16)
	end
end

local function makeBar(gui: GuiObject)
	if bar then
		return
	end
	local b = Ui.new("Frame", { Name = "EditBar", ZIndex = 10, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(700, 120), BackgroundTransparency = 1, Parent = gui })
	bar = b
	-- The hint: a navy pill over the tools (theme.css .edit-hint).
	local pillShadow, pillFace = Ui.pill({ Name = "Hint", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(0, 31), AutomaticSize = Enum.AutomaticSize.X, Parent = b }, 16)
	pillFace.AutomaticSize = Enum.AutomaticSize.X
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = pillShadow })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = pillFace })
	hint = Ui.text({ Text = "", TextSize = 14, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Shadow = 1.5, ShadowColor = Ui.BLACK, ShadowTransparency = 0.6, Parent = pillFace })
	-- Content that sizes the pill: an invisible copy beside the face.
	measure = Ui.text({ Name = "Measure", Text = "", TextSize = 14, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, TextTransparency = 1, ZIndex = 0, Parent = pillShadow })
	local shadow, dock = Ui.shadowed({ Name = "Tools", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(600, 70), Parent = b }, { radius = 20, stroke = 3, drop = 5, dark = 0.3, color = Ui.SHEET })
	dockShadow = shadow
	tools = Ui.new("Frame", { Name = "Row", Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 1, -16), BackgroundTransparency = 1, Parent = dock }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	toolsKey = ""
end

-- Redraws the hint, tools and marks for the current mode (after a mode change or a new town).
function Placement.refresh()
	if not mode then
		return
	end
	if hint and bar then
		local text = hintText()
		Ui.setText(hint, text)
		if measure then
			measure.Text = text
		end
	end
	drawTools()
	drawMarks()
	if onChange then
		onChange()
	end
end

-- ── Pointer ─────────────────────────────────────────────────────────────────────────────────

local function hover(screen: Vector2)
	local tx, tz = tileAt(screen)
	if not tx or not tz then
		return
	end
	local s = state()
	if mode == "place" and placing then
		local px, pz = tx, tz
		if preview then
			px, pz = preview.x, preview.z
		end
		local x, z, w, h = lotAt(placing, px, pz, chosen())
		local ok = store.canPlace(s, placing, x, z, chosen())
		showPlate(x, z, w, h, if ok then "#66bb6a" else "#ef5350", 0.35)
		if ghost then
			local c = Town.tileToWorld(x + (w - 1) / 2, z + (h - 1) / 2)
			if c then
				local roads = lualib.__TS__New(lualib.Set, s.roads)
				local turn = placementRules.turnOf({ def = placing, x = x, z = z, rot = chosen() }, roads)
				ghost:PivotTo(CFrame.new(c) * CFrame.Angles(0, turn * math.pi / 2, 0))
			end
		end
	elseif mode == "move" and carry then
		local b = findBuilding(carry.uid)
		local g = carry.block
		if b and g then
			-- A merged block: the plate covers the whole block (store canPlaceBlock).
			local x, z = tx - (g.w - 1) // 2, tz - (g.h - 1) // 2
			local ok = store.canPlaceBlock(s, g, x, z)
			showPlate(x, z, g.w, g.h, if ok then "#66bb6a" else "#ef5350", 0.5)
			carry.x, carry.z = x, z
		elseif b then
			local x, z, w, h = lotAt(b.def, tx, tz, b.rot)
			local ok = store.canPlace(s, b.def, x, z, b.rot, b.uid)
			showPlate(x, z, w, h, if ok then "#66bb6a" else "#ef5350", 0.5)
			carry.x, carry.z = x, z
		end
	elseif mode == "road" then
		showPlate(tx, tz, 1, 1, "#90caf9", 0.45)
	elseif mode == "bulldoze" then
		showPlate(tx, tz, 1, 1, "#ef5350", 0.45)
	else
		hidePlate()
	end
end

-- Lays road or bulldozes the tile under the pointer, once per tile as a drag crosses it.
local function brush(screen: Vector2)
	local tx, tz = tileAt(screen)
	if not tx or not tz then
		return
	end
	local k = `{tx},{tz}`
	if k == lastTile then
		return
	end
	lastTile = k
	if mode == "road" then
		Remote.act("paintRoad", tx, tz)
	elseif mode == "bulldoze" then
		Remote.act("bulldoze", tx, tz)
	end
end

local function place(screen: Vector2)
	if not placing then
		return
	end
	local tx, tz = tileAt(screen)
	if not tx or not tz then
		return
	end
	-- Touch: the first tap previews the spot, a tap on the same spot builds.
	if TOUCH and not (preview and preview.x == tx and preview.z == tz) then
		preview = { x = tx, z = tz }
		hover(screen)
		return
	end
	local def = placing
	local x, z = lotAt(def, tx, tz, chosen())
	if not store.canPlace(state(), def, x, z, chosen()) then
		ctx.toast("That spot is taken")
		return
	end
	local ok = if storedUid then Remote.act("placeStored", storedUid, x, z, chosen()) else Remote.act("placeBuilding", def, x, z, chosen())
	if ok then
		-- As on the web: straight into Move with the new building picked, and Again to build another.
		local wasStored = storedUid ~= nil
		local built: any = nil
		for _, b in state().buildings do
			if b.def == def and b.x == x and b.z == z then
				built = b
			end
		end
		setMode("move")
		selected = if built then built.uid else nil
		again = if wasStored then nil else def
		Placement.refresh()
	end
end

local function began(input: InputObject, processed: boolean)
	if processed or not mode then
		return
	end
	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
		if input.KeyCode == Enum.KeyCode.R then
			rotateCurrent()
		elseif input.KeyCode == Enum.KeyCode.Escape then
			Placement.cancel()
		end
		return
	end
	local screen = Vector2.new(input.Position.X, input.Position.Y)
	if mode == "road" or mode == "bulldoze" then
		held = input
		lastTile = ""
		brush(screen)
		hover(screen)
	elseif mode == "place" then
		place(screen)
	elseif mode == "move" then
		local tx, tz = tileAt(screen)
		if not tx or not tz then
			return
		end
		local occ = store.occupancy(state())
		local uid = occ:get(`{tx},{tz}`)
		local b = if uid and uid ~= "road" then findBuilding(uid) else nil
		if b and store.movable(b.def) then
			-- Press on a building: pick it, and a drag carries it. A merged block is picked and
			-- carried whole, by its top-left building.
			local g = blockOf(b.uid)
			if g then
				b = g.anchor
			end
			selected = b.uid
			again = nil
			carry = { uid = b.uid, x = if g then g.x else b.x, z = if g then g.z else b.z, block = g }
			held = input
			TownCamera.setPanEnabled(false)
			Placement.refresh()
		end
	end
end

local function changed(input: InputObject)
	if not mode then
		return
	end
	local t = input.UserInputType
	if t ~= Enum.UserInputType.MouseMovement and t ~= Enum.UserInputType.Touch then
		return
	end
	local screen = Vector2.new(input.Position.X, input.Position.Y)
	if held and (mode == "road" or mode == "bulldoze") then
		brush(screen)
	end
	-- Mouse: the plate follows the pointer. Touch: only while a finger drags something.
	if t == Enum.UserInputType.MouseMovement or held then
		hover(screen)
	end
end

-- Drops a carried building: a click when it lands, the error buzz when it snaps back (World.tsx startDrag).
local function move(uid: string, x: number, z: number, r: number?)
	local ok, moved = Remote.act("moveBuilding", uid, x, z, r)
	if ok and moved ~= false then
		Sfx.click()
	else
		Sfx.error()
	end
end

local function ended(input: InputObject)
	if input ~= held and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	held = nil
	lastTile = ""
	if carry then
		local c = carry
		carry = nil
		TownCamera.setPanEnabled(true)
		local b = findBuilding(c.uid)
		if b and c.block then
			if c.x ~= c.block.x or c.z ~= c.block.z then
				-- The anchor is the block's top-left building, so its spot is the block's.
				if store.canPlaceBlock(state(), c.block, c.x, c.z) then
					move(b.uid, c.x, c.z, b.rot)
				else
					Sfx.error()
					ctx.toast("It doesn't fit there")
				end
			end
		elseif b and (c.x ~= b.x or c.z ~= b.z) then
			if store.canPlace(state(), b.def, c.x, c.z, b.rot, b.uid) then
				move(b.uid, c.x, c.z, b.rot)
			else
				Sfx.error()
				ctx.toast("It doesn't fit there")
			end
		end
		hidePlate()
	end
	if TOUCH and (mode == "road" or mode == "bulldoze") then
		hidePlate()
	end
end

-- ── Entering and leaving ────────────────────────────────────────────────────────────────────

local function start(gui: GuiObject, c: any, m: Mode)
	ctx = c
	root = gui
	makeBar(gui)
	if #conns == 0 then
		table.insert(conns, UserInputService.InputBegan:Connect(began))
		table.insert(conns, UserInputService.InputChanged:Connect(changed))
		table.insert(conns, UserInputService.InputEnded:Connect(ended))
	end
	setMode(m)
end

function Placement.active(): boolean
	return mode ~= nil
end

-- Leaves edit mode: back to the town.
function Placement.cancel()
	if not mode then
		return
	end
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	mode, placing, storedUid, selected, again, carry, held, preview = nil, nil, nil, nil, nil, nil, nil, nil
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if plate then
		plate:Destroy()
		plate = nil
	end
	clearMarks()
	if bar then
		bar:Destroy()
		bar, hint, tools, measure, dockShadow = nil, nil, nil, nil, nil
	end
	TownCamera.setPanEnabled(true)
	if onChange then
		onChange()
	end
end

-- The EDIT button: edit mode on the Road tool, as the web opens it.
function Placement.edit(gui: GuiObject, c: any, tool: string?)
	local m: Mode = if tool == "land" then "land" elseif tool == "move" then "move" elseif tool == "bulldoze" then "bulldoze" elseif tool == "merge" then "merge" else "road"
	start(gui, c, m)
end

-- Place a building picked in the Shop.
function Placement.place(def: string, gui: GuiObject, c: any)
	start(gui, c, "place")
	placing = def
	storedUid = nil
	rot, rotated = 0, false
	if ghost then
		ghost:Destroy()
	end
	ghost = makeGhost(def)
	Placement.refresh()
end

-- Place a building back from the Inventory.
function Placement.placeStored(suid: string, def: string, gui: GuiObject, c: any)
	Placement.place(def, gui, c)
	storedUid = suid
end

-- The Inventory: buildings that were bulldozed or picked up, ready to place again.
function Placement.inventory(c: any): Instance
	local overlay, sheet, body = Ui.panel(c.gui, "Inventory", { width = 456, onClose = c.close })
	local limit = (sheet.Parent :: Instance):FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local s = state()
	local groups: { { def: string, uids: { string } } } = {}
	local at: { [string]: number } = {}
	for _, b in (s.stored or {}) do
		local i = at[b.def]
		if not i then
			table.insert(groups, { def = b.def, uids = {} })
			i = #groups
			at[b.def] = i
		end
		table.insert(groups[i].uids, b.uid)
	end
	if #groups == 0 then
		Ui.text({ Text = "Nothing in storage. Bulldozed buildings wait here to be placed again.", Body = true, TextSize = 14, TextColor3 = Color3.fromHex("#546e7a"), TextWrapped = true, Size = UDim2.new(1, 0, 0, 44), Parent = body })
		limit.MaxSize = Vector2.new(456, 61 + 10 + 44 + 24)
		return overlay
	end
	local list = Ui.scroller({ Size = UDim2.fromScale(1, 1), Parent = body })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	for i, g in groups do
		local d = data.buildingDef(g.def)
		local row = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.new(1, -8, 0, 64), BackgroundColor3 = Ui.WHITE, Parent = list }, { Ui.corner(12), Ui.stroke(2, Ui.EDGE) })
		local pic = Ui.new("Frame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(60, 52), BackgroundColor3 = Color3.fromHex("#dcecfb"), Parent = row }, { Ui.corner(10) })
		Thumb.new("Buildings", d.id, UDim2.fromScale(1, 1), nil).Parent = pic
		Ui.text({ Text = d.name, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -170, 1, 0), Parent = row })
		Ui.text({ Text = `×{#g.uids}`, TextSize = 18, TextColor3 = Ui.INK, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.5, 0), Size = UDim2.fromOffset(40, 24), Parent = row })
		Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 1), Size = UDim2.fromOffset(74, 30), Parent = row }, "Place", "green", function()
			c.close()
			Placement.placeStored(g.uids[1], g.def, root or c.gui, c)
		end, 14)
	end
	limit.MaxSize = Vector2.new(456, 61 + 10 + #groups * 72 + 24)
	return overlay
end

function Placement.onChange(fn: () -> ())
	onChange = fn
end

-- Keep the bar, the marks and the picked building right when the town changes under them.
Remote.changed:Connect(function()
	if not mode then
		return
	end
	if selected and not findBuilding(selected) then
		selected = nil
	end
	Placement.refresh()
end)

return Placement
