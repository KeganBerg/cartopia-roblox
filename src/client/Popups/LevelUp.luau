--!strict
-- The level-up splash (ui/LevelUp.tsx): the badge rolling over to the new level, what the level
-- paid, and what it opened in the shop (or, on a quiet level, what's coming next).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local Remote = require(script.Parent.Parent.Remote)
local Sfx = require(script.Parent.Parent.Sounds.Sfx)
local Motion = require(script.Parent.Parent.Motion)
local Kit = require(script.Parent.Kit)

local LevelUp = {}

type Unlock = { key: string, name: string, level: number, tag: string, price: string, art: (size: UDim2) -> GuiObject, go: () -> () }

-- The picture's backdrop (.thumb3d, .lvl-emoji): white low in the middle, pale blue round it.
local function backdrop(size: UDim2): Frame
	local f = Ui.new("Frame", { Name = "Art", Size = size, BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ClipsDescendants = true }, { Ui.corner(10) })
	Ui.new("UIGradient", { Rotation = 90, Color = Ui.seq("#e3f2fd", "#ffffff") }).Parent = f
	return f
end

local function emoji(icon: string): (UDim2) -> GuiObject
	return function(size: UDim2): GuiObject
		local f = backdrop(size)
		Ui.text({ Text = icon, TextSize = 48, Size = UDim2.fromScale(1, 1), Parent = f })
		return f
	end
end

-- A 3D picture (Thumb) on the backdrop. It fills in when the server's model library reaches this
-- player; until then the item's first letter stands in, so the card is never blank.
local function model(name: string, pic: (UDim2) -> ViewportFrame): (UDim2) -> GuiObject
	return function(size: UDim2): GuiObject
		local f = backdrop(size)
		local vp = pic(UDim2.fromScale(1, 1))
		vp.Parent = f
		if not vp:FindFirstChildOfClass("Model") then
			local wait = Ui.text({ Name = "Waiting", Text = string.upper(string.sub(name, 1, 1)), TextSize = 44, TextColor3 = Color3.fromHex("#90caf9"), Size = UDim2.fromScale(1, 1), Parent = f })
			vp.ChildAdded:Connect(function(c)
				if c:IsA("Model") then
					wait:Destroy()
				end
			end)
		end
		return f
	end
end

local function unlocksBetween(from: number, to: number, rusty: boolean, open: (string, any?) -> ()): { Unlock }
	local function inRange(l: number): boolean
		return l > from and l <= to
	end
	local items: { Unlock } = {}
	for _, b in data.BUILDINGS do
		if b.unlockLevel < 99 and not b.event and inRange(b.unlockLevel) then
			table.insert(items, {
				key = `b-{b.id}`,
				name = b.name,
				level = b.unlockLevel,
				tag = if b.kind == "decor" or b.kind == "house" then "Decor" else "Building",
				price = if b.bucks and b.bucks > 0 then `💎 {b.bucks}` else `$ {Ui.commas(b.price)}`,
				art = model(b.name, function(size: UDim2): ViewportFrame
					return Thumb.new("Buildings", b.id, size)
				end),
				go = function()
					open("shop", b.id)
				end,
			})
		end
	end
	for _, c in data.CARS do
		if not c.rescueOnly and not c.season and not c.secret and not c.pack and inRange(c.unlockLevel) then
			table.insert(items, {
				key = `c-{c.id}`,
				name = c.name,
				level = c.unlockLevel,
				tag = "Car",
				price = if c.bucks and c.bucks > 0 then `💎 {Ui.commas(c.bucks)}` else `$ {Ui.commas(c.price)}`,
				art = model(c.name, function(size: UDim2): ViewportFrame
					return Thumb.car(c.id, size, { color = c.colors[1] })
				end),
				go = function()
					open("showroom", c.id)
				end,
			})
		end
	end
	for _, r in data.RESCUE_SPOTS do
		if inRange(r.unlockLevel) then
			table.insert(items, {
				key = `r-{r.id}`,
				name = r.name,
				level = r.unlockLevel,
				tag = "Rusty's search",
				price = `$ {Ui.commas(r.cost)}`,
				art = emoji(r.icon),
				go = function()
					if rusty then
						open("rescue")
					else
						open("shop", "rescue")
					end
				end,
			})
		end
	end
	for _, g in data.GP_SERIES do
		if inRange(g.unlockLevel) then
			table.insert(items, {
				key = `g-{g.id}`,
				name = g.name,
				level = g.unlockLevel,
				tag = "Grand Prix",
				price = `{g.minCars} cars`,
				art = emoji("🏆"),
				go = function()
					open("race")
				end,
			})
		end
	end
	return items
end

-- The next level that unlocks anything, so a quiet level-up still has something to aim for.
local function nextUnlock(level: number): number?
	local best: number? = nil
	local function see(l: number)
		if l > level and (best == nil or l < best) then
			best = l
		end
	end
	for _, b in data.BUILDINGS do
		if b.unlockLevel < 99 and not b.event then
			see(b.unlockLevel)
		end
	end
	for _, c in data.CARS do
		if not c.rescueOnly and not c.season and not c.secret and not c.pack then
			see(c.unlockLevel)
		end
	end
	for _, r in data.RESCUE_SPOTS do
		see(r.unlockLevel)
	end
	for _, g in data.GP_SERIES do
		see(g.unlockLevel)
	end
	return best
end

local TAG_GO = { Car = "Showroom", ["Grand Prix"] = "Race", ["Rusty's search"] = "Rusty's" }

local function show(ctx: any, lu: any, done: () -> ())
	local s = store.useGame.getState()
	local overlay: Instance
	local function close()
		if overlay.Parent == nil then
			return
		end
		overlay:Destroy()
		-- A second level-up that came while this one showed stays for its own turn.
		if store.useGame.getState().levelUp == lu then
			store.useGame.getState().closeLevelUp()
		end
		done()
	end
	local function go(panel: string, arg: any?)
		close()
		ctx.open(panel, arg)
	end
	local from, to = lu.from, lu.to
	local items = unlocksBetween(from, to, store.hasRusty(s), go)
	local teaser: { at: number, items: { Unlock } }? = nil
	if #items == 0 then
		local at = nextUnlock(to)
		if at then
			teaser = { at = at, items = unlocksBetween(at - 1, at, store.hasRusty(s), go) }
		end
	end
	local fuel = data.baseFuelCap(to) - data.baseFuelCap(from)
	local rate = data.fuelPerMin(to)
	local rateUp = rate > data.fuelPerMin(from)

	overlay = Kit.overlay(ctx, true, close)
	-- A short fanfare as the card comes up.
	task.delay(0.25, function()
		if overlay.Parent ~= nil then
			Sfx.levelUp()
		end
	end)
	local shown = if #items > 0 then items elseif teaser then teaser.items else {}
	local W = 600
	local CW, CH, GAP = 176, 186, 10
	local rows = math.ceil(#shown / 3)
	local fixed = 58 + 46 + 26 + 36 + (if #shown > 0 then 36 else 0) + 12 + 46 + 16
	-- The card fits the screen (.lvl max-height: 100dvh - 74px): on a short one the items scroll,
	-- with at least one whole row showing.
	local viewH = (ctx.gui :: GuiObject).AbsoluteSize.Y
	local sc = (ctx.gui :: GuiObject):FindFirstChildOfClass("UIScale")
	if sc and sc.Scale > 0 then
		viewH /= sc.Scale
	end
	if viewH < 2 then
		viewH = 800
	end
	local room = math.max(CH + 8, viewH - 74 - 16 - fixed)
	local gridH = if #shown > 0 then math.min(rows * (CH + GAP) - GAP + 8, room) else 0
	local h = fixed + gridH
	local shadow, card = Kit.card(overlay, W, h, 28)

	-- The web splash's motion (index.css lvl-*): the card springs up, the badge spins in and rolls
	-- over to the new level with a burst of sparks, then the words and the cards pop in in turn.
	local live = Motion.live()
	local function later(t: number, f: () -> ())
		if not live then
			return
		end
		task.delay(t, function()
			if overlay.Parent ~= nil then
				f()
			end
		end)
	end
	-- Hidden until its moment, then it pops from `from` (scale) and rises `rise` px into place.
	local function popIn(g: GuiObject, at: number, from: number, rise: number, time: number?, style: string?)
		if not live then
			return
		end
		local s = Motion.scaleOf(g)
		local home = g.Position
		s.Scale = 0
		later(at, function()
			s.Scale = from
			g.Position = home + UDim2.fromOffset(0, rise)
			Motion.tween(s, time or 0.45, { Scale = 1 }, style or "Back")
			Motion.tween(g, time or 0.45, { Position = home }, "Quad")
		end)
	end
	if live then
		local s = Motion.scaleOf(shadow)
		s.Scale = 0.85
		local home = shadow.Position
		shadow.Position = home + UDim2.fromOffset(0, 40)
		later(0.1, function()
			Motion.tween(s, 0.55, { Scale = 1 }, "Back")
			Motion.tween(shadow, 0.55, { Position = home }, "Quad")
		end)
	end

	-- The badge: blue, gold-ringed, half above the card.
	local badge = Ui.new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(112, 112), BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = card }, {
		Ui.round(),
		Ui.stroke(5, Kit.GOLD),
		Ui.new("UIGradient", { Rotation = 60, Color = Ui.seq("#6fb1ff", "#1e5fbf") }),
	})
	local ring = Ui.new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -16, 1, -16), BackgroundTransparency = 1, ZIndex = 3, Parent = badge }, {
		Ui.round(),
		Ui.stroke(3, Ui.WHITE, 0.55),
	})
	-- The number rolls: the old one slides up out of a window, the new one springs up into it.
	local window = Ui.new("Frame", { Name = "Number", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -20, 1, -20), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 4, Parent = badge })
	local old = Ui.text({ Name = "Level", Text = tostring(if live then from else to), TextSize = 54, Size = UDim2.fromScale(1, 1), ZIndex = 4, Shadow = 3, ShadowColor = Ui.BLACK, ShadowTransparency = 0.7, Parent = window })
	if live then
		local new = Ui.text({ Name = "New", Text = tostring(to), TextSize = 54, Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 1), ZIndex = 4, Shadow = 3, ShadowColor = Ui.BLACK, ShadowTransparency = 0.7, Parent = window })
		local bs = Motion.scaleOf(badge)
		bs.Scale = 0
		badge.Rotation = -120
		later(0.25, function()
			Motion.tween(bs, 0.7, { Scale = 1 }, "Back")
			Motion.tween(badge, 0.7, { Rotation = 0 }, "Back")
		end)
		later(0.8, function()
			Motion.tween(old, 0.45, { Position = UDim2.fromScale(0, -1) }, "Cubic", "InOut")
			Motion.tween(new, 0.55, { Position = UDim2.fromScale(0, 0) }, "Back")
		end)
		-- The dashed ring turns slowly (lvl-badge-ring).
		Motion.loop(overlay, function(_, dt: number)
			ring.Rotation = (ring.Rotation + dt * 36) % 360
		end)
		-- Eight sparks burst out from behind the number.
		for i = 0, 7 do
			local a = math.rad(i * 45)
			local spark = Ui.new("Frame", { Name = "Spark", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(10, 10), BackgroundColor3 = Color3.fromHex("#ffe082"), BackgroundTransparency = 1, ZIndex = 2, Parent = badge }, {
				Ui.round(),
				Ui.stroke(2, Kit.GOLD, 0.4),
			})
			later(1, function()
				spark.BackgroundTransparency = 0
				local to2 = UDim2.new(0.5, math.sin(a) * 90, 0.5, -math.cos(a) * 90)
				Motion.tween(spark, 0.8, { Position = to2, Size = UDim2.fromOffset(3, 3), BackgroundTransparency = 1 }, "Quad")
				local st = spark:FindFirstChildOfClass("UIStroke")
				if st then
					Motion.tween(st, 0.8, { Transparency = 1 }, "Quad")
				end
			end)
		end
	end

	local y = 58
	popIn(Kit.title(card, "Level up!", y), 0.9, 0.4, 0, 0.5)
	y += 46
	popIn(Kit.line(card, `You're now level {to}`, y), 1, 1, 10, 0.4, "Quad")
	y += 26
	local chips: { Kit.Chip } = {}
	if (lu.coins or 0) > 0 then
		table.insert(chips, { text = `+{Ui.commas(lu.coins)}`, coin = true })
	end
	if (lu.bucks or 0) > 0 then
		table.insert(chips, { text = `💎 +{lu.bucks}` })
	end
	table.insert(chips, { text = if fuel > 0 then `⛽ Full · +{fuel}` else "⛽ Full" })
	if rateUp then
		table.insert(chips, { text = `⏱ {rate}⛽/min ⬆`, color = "#2e9e4f" })
	end
	Kit.chips(card, y, chips)
	local chipRow = card:FindFirstChild("Chips")
	if chipRow then
		popIn(chipRow :: GuiObject, 1.1, 1, 10, 0.4, "Quad")
	end
	y += 36
	if #shown > 0 then
		popIn(Kit.line(card, if teaser then `Coming at level {teaser.at}` else "New in the shop", y, 20, Ui.INK, true), 1.2, 1, 10, 0.4, "Quad")
		y += 36
		local grid = Ui.new("ScrollingFrame", {
			Name = "Items",
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, gridH),
			CanvasSize = UDim2.fromOffset(0, rows * (CH + GAP) + 4),
			ScrollBarThickness = if rows * (CH + GAP) - GAP + 8 > gridH then 6 else 0,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = card,
		})
		for i, it in shown do
			local c = (i - 1) % 3
			local r = (i - 1) // 3
			local inRow = math.min(3, #shown - r * 3)
			local rowLeft = (W - (inRow * CW + (inRow - 1) * GAP)) / 2
			local locked = teaser ~= nil
			local item, face = Kit.itemCard(grid, rowLeft + c * (CW + GAP), 2 + r * (CH + GAP), CW, CH, not locked)
			popIn(item, 1.3 + (i - 1) * 0.09, 0.8, 18)
			local art = it.art(UDim2.new(1, -16, 0, 96))
			art.Position = UDim2.fromOffset(8, 22)
			art.Parent = face
			if locked then
				-- Not yet theirs: the picture in grey (.locked).
				for _, d in art:GetDescendants() do
					if d:IsA("ViewportFrame") then
						d.ImageColor3 = Color3.fromRGB(150, 150, 150)
					end
				end
			end
			local tag = Ui.new("Frame", { Name = "Tag", Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(Ui.textWidth(string.upper(it.tag), 11) + 14, 16), BackgroundColor3 = Ui.BLUE, ZIndex = 2, Parent = face }, { Ui.corner(6) })
			Ui.text({ Text = string.upper(it.tag), TextSize = 11, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = tag })
			Ui.text({ Text = it.name, TextSize = 15, TextColor3 = Ui.INK, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(6, 120), Size = UDim2.new(1, -12, 0, 18), Parent = face })
			Ui.text({ Text = if locked then `🔒 Level {it.level}` else it.price, TextSize = 15, TextColor3 = Color3.fromHex(if string.find(it.price, "💎") and not locked then "#0277bd" else "#8d5a00"), Position = UDim2.fromOffset(6, 139), Size = UDim2.new(1, -12, 0, 18), Parent = face })
			if not locked then
				local label = `{TAG_GO[it.tag] or "Shop"} ›`
				local gw = Ui.textWidth(label, 13) + 22
				Ui.new("Frame", { Name = "Go", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 160), Size = UDim2.fromOffset(gw, 20), BackgroundColor3 = Ui.WHITE, Parent = face }, {
					Ui.corner(10),
					Ui.gradient("#66bb6a", "#2e7d32"),
					Ui.text({ Text = label, TextSize = 13, Size = UDim2.fromScale(1, 1) }),
				})
				face.Activated:Connect(it.go)
			end
		end
		y += gridH
	end
	y += 12
	popIn(Kit.button(card, "Continue", 0, y, 180, 44, "green", close), 1.5, 1, 10, 0.4, "Quad")
end

function LevelUp.start(ctx: any)
	local function look()
		local lu = store.useGame.getState().levelUp
		if lu then
			Kit.push(ctx, "levelUp", 1, function(done)
				local now = store.useGame.getState().levelUp
				if not now then
					done()
					return
				end
				show(ctx, now, done)
			end)
		end
	end
	Remote.changed:Connect(look)
	look()
end

return LevelUp
