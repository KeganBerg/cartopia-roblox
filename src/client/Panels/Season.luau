--!strict
-- Star Pass, as the web game's SeasonPanel (ui/Season.tsx, season.css): stars from daily and
-- weekly tasks unlock a tier every STARS_PER_TIER. The header has your stars, the bar to the next
-- tier and the time left in the season; under it Main Street at night (scene/SeasonScene.tsx,
-- drawn here from above) with an arch over the road for every tier, its prize on a lit sign and a
-- star on top, your race car at your tier and the season's own car parked at the finish. Drag the
-- road, or tap a tier chip below it, to look along it. The button collects every tier reached, or
-- goes to Goals to earn stars.
-- Also the HUD's star button with the number of tiers ready (SeasonButton).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint) :: any
local Client = script.Parent.Parent
local Remote = require(Client.Remote)
local Ui = require(Client.Ui)
local Icons = require(Client.Icons)
local Thumb = require(Client.Thumb)

local Season = {}
Season.id = "season"

local LINE = Ui.LINE
local INK = Ui.INK

-- scene/SeasonScene.tsx: world units between tiers, and tier 1 past the start line.
local GAP, FIRST = 6, 6
local K = 24 -- pixels per world unit, looking down on the road
local SCENE_H = 416 -- min(52vh, 440px) at 800px
local AT = 0.62 -- how far down the scene the looked-at point sits

local BG = { got = "#45b649", ready = "#ffc533", locked = "#e3e9f1" }
local SIGN_INK = { got = "#ffffff", ready = "#14213d", locked = "#4a6283" }
local STAR = { got = "#ffd54f", ready = "#ffb300", locked = "#78909c" }
local POST = { got = "#2e7d32", ready = "#ff8f00", locked = "#546e7a" }

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

local function zOf(i: number): number
	return FIRST + i * GAP
end

-- Time left as the web's left(): 5h, 3d.
local function left(ms: number): string
	local h = math.max(1, math.ceil(ms / 3600000))
	return if h >= 24 then `{h // 24}d` else `{h}h`
end

-- Prize amounts on the signs: 1.5K, 2K, 750.
local function short(n: number): string
	if n >= 1000 then
		return if n % 1000 ~= 0 then string.format("%.1fK", n / 1000) else `{n // 1000}K`
	end
	return tostring(n)
end

-- A skin's swatch (a CSS colour or gradient) as its colours.
local function swatchColors(swatch: string?): { Color3 }
	local out = {}
	for hex in string.gmatch(swatch or "", "#%x%x%x%x?%x?%x?") do
		local ok, c = pcall(Color3.fromHex, hex)
		if ok then
			table.insert(out, c)
		end
	end
	if #out == 0 then
		table.insert(out, Color3.fromHex("#ff4081"))
	end
	return out
end

function Season.swatch(parent: Instance, swatch: string?, size: number, props: { [string]: any }?): Frame
	local cols = swatchColors(swatch)
	local f = Ui.new("Frame", { Size = UDim2.fromOffset(size, size), BackgroundColor3 = cols[1], BorderSizePixel = 0 }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
	for k, v in (props or {}) :: { [string]: any } do
		(f :: any)[k] = v
	end
	if #cols > 1 then
		local keys = {}
		for i, c in cols do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#cols - 1), c))
		end
		Ui.new("UIGradient", { Color = ColorSequence.new(keys), Rotation = 45, Parent = f })
	end
	f.Parent = parent
	return f
end

-- The tiers as the scene shows them (Tier in SeasonScene.tsx).
local function tiersOf(p: any, prizeCar: any): { any }
	local out = {}
	for i, prize in data.SEASON_TIERS do
		local i0 = i - 1
		local skin = data.seasonSkin(i) or data.seasonModSkin(i)
		local got = table.find(p.claimed, i0) ~= nil
		table.insert(out, {
			n = i,
			coins = prize.coins,
			parts = prize.parts,
			gems = prize.bucks + (if prize.car and not prizeCar then data.SEASON_CAR_BUCKS else 0),
			skin = skin and skin.swatch,
			car = if prize.car and prizeCar then prizeCar.name else nil,
			state = if got then "got" elseif p.stars >= i * data.STARS_PER_TIER then "ready" else "locked",
		})
	end
	return out
end

-- One arch: posts at the road's edges, the bar across, the lit sign with the tier and its prize,
-- the star on top, and a tick or lock in the sign's corner.
local function arch(world: Instance, t: any, y: number, roadW: number)
	local holder = Ui.new("Frame", { Name = `Tier{t.n}`, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(roadW + 40, 120), BackgroundTransparency = 1, ZIndex = 4, Parent = world })
	local post = Color3.fromHex(POST[t.state])
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -24, 0, 8), BackgroundColor3 = post, BorderSizePixel = 0, ZIndex = 4, Parent = holder }, { Ui.corner(4) })
	for _, x in { 0, 1 } do
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(x, if x == 0 then 12 else -12, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = post, ZIndex = 5, Parent = holder }, { Ui.round(), Ui.stroke(2, LINE) })
	end
	-- The sign's glow on the road.
	if t.state ~= "locked" then
		Ui.new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(128 + 30, 76 + 30), BackgroundColor3 = Color3.fromHex(BG[t.state]), BackgroundTransparency = 0.82, ZIndex = 5, Parent = holder }, { Ui.corner(22) })
	end
	local sign = Ui.new("Frame", { Name = "Sign", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(128, 76), BackgroundColor3 = Color3.fromHex(BG[t.state]), ZIndex = 6, Parent = holder }, {
		Ui.corner(10),
		Ui.stroke(4, LINE),
	})
	local ink = Color3.fromHex(SIGN_INK[t.state])
	Ui.text({ Text = tostring(t.n), TextSize = 34, TextColor3 = ink, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 40), ZIndex = 7, Parent = sign })
	local line = Ui.new("Frame", { Name = "Prize", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.fromOffset(120, 24), BackgroundTransparency = 1, ZIndex = 7, Parent = sign }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	if t.car then
		Ui.text({ Text = t.car, TextSize = 14, TextColor3 = ink, Size = UDim2.fromOffset(120, 24), ZIndex = 7, LayoutOrder = 2, Parent = line })
	else
		if t.skin then
			Season.swatch(line, t.skin, 18, { LayoutOrder = 1, ZIndex = 7 })
		end
		local text = if t.coins > 0 then short(t.coins) elseif t.parts > 0 then tostring(t.parts) else tostring(t.gems)
		if t.coins > 0 then
			local c = Icons.draw("coin", line, 20)
			c.LayoutOrder = 2
		else
			Ui.text({ Text = if t.parts > 0 then "⚙️" else "💎", TextSize = 17, Size = UDim2.fromOffset(20, 22), ZIndex = 7, LayoutOrder = 2, Parent = line })
		end
		Ui.text({ Text = text, TextSize = 19, TextColor3 = ink, Size = UDim2.fromOffset(Ui.textWidth(text, 19) + 2, 24), ZIndex = 7, LayoutOrder = 3, Parent = line })
	end
	-- The star on top, and the tick or lock.
	Ui.text({ Text = "★", Body = true, Weight = "heavy", TextSize = 30, TextColor3 = Color3.fromHex(STAR[t.state]), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(34, 30), ZIndex = 8, Stroke = 1.5, StrokeColor = LINE, Parent = sign })
	if t.state ~= "ready" then
		local corner = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = if t.state == "got" then Color3.fromHex("#2e7d32") else Color3.fromHex("#546e7a"), ZIndex = 8, Parent = sign }, { Ui.round(), Ui.stroke(2, LINE) })
		if t.state == "got" then
			Icons.draw("check", corner, 14, Ui.WHITE, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		else
			Ui.text({ Text = "🔒", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 8, Parent = corner })
		end
	end
end

function Season.open(ctx: any): Instance
	local overlay, _, body = Ui.panel(ctx.gui, "⭐ Star Pass", { width = 460, height = 61 + 10 + 30 + 8 + SCENE_H + 8 + 56 + 8 + 44 + 16, onClose = ctx.close })
	-- The drawing's own listeners (the drag), dropped when it's drawn again.
	local drawn: { RBXScriptConnection } = {}
	local viewZ: number? = nil

	local function render()
		for _, c in body:GetChildren() do
			c:Destroy()
		end
		for _, c in drawn do
			c:Disconnect()
		end
		table.clear(drawn)
		local s = store.useGame.getState()
		local n = data.seasonNumber(now())
		local p = store.currentSeason({ season = s.season }, data.seasonEndsAt(n) - 1)
		local def = data.seasonOf(p.n)
		local prizeCar = if def.car then data.carDef(def.car) else nil
		local count = #data.SEASON_TIERS
		local last = count - 1
		local per = data.STARS_PER_TIER
		local reached = math.min(count, p.stars // per)
		local into = if reached >= count then per else p.stars % per
		local ready = {}
		for i = 0, last do
			if store.tierReady(p, i) then
				table.insert(ready, i)
			end
		end
		local tiers = tiersOf(p, prizeCar)
		local carZ = math.max(0.5, math.min(zOf(last), zOf(p.stars / per - 1)))
		local firstOpen = ready[1] or math.min(last, reached)
		if viewZ == nil then
			viewZ = math.max(0, math.min(carZ - GAP, zOf(firstOpen)))
		end

		-- ── The header: stars, the bar, the time left ──────────────────────────────────────────
		local head = Ui.new("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = body })
		local countText = `⭐ {p.stars}`
		local countW = Ui.textWidth(countText, 26) + 18
		Ui.text({ Name = "Count", Text = countText, TextSize = 26, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0, countW, 1, 0), Parent = head })
		local endsText = `⏱ {left(data.seasonEndsAt(p.n) - now())}`
		local endsW = Ui.textWidth(endsText, 16) + 30
		local ends = Ui.new("Frame", { Name = "Ends", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(endsW, 24), BackgroundColor3 = Color3.fromHex("#311b92"), Parent = head }, { Ui.round(), Ui.stroke(3, LINE) })
		Ui.text({ Text = endsText, Body = true, Weight = "heavy", TextSize = 16, Size = UDim2.fromScale(1, 1), Parent = ends })
		local bar = Ui.new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, countW + 3, 0.5, 0), Size = UDim2.new(1, -(countW + endsW + 22), 0, 22), BackgroundColor3 = Color3.fromHex("#dfe7f2"), ClipsDescendants = true, Parent = head }, { Ui.round(), Ui.stroke(3, LINE) })
		Ui.new("Frame", { Size = UDim2.fromScale(into / per, 1), BackgroundColor3 = Color3.fromHex("#ffb300"), BorderSizePixel = 0, Visible = into > 0, Parent = bar }, { Ui.round() })
		Ui.text({ Text = if reached >= count then "Max" else `{per - into} to go`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = LINE, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = bar })

		-- ── The road at night ───────────────────────────────────────────────────────────────────
		local scene = Ui.new("Frame", { Name = "Scene", Active = true, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, SCENE_H), BackgroundColor3 = Color3.fromHex("#101a3a"), ClipsDescendants = true, Parent = body }, {
			Ui.corner(16),
			Ui.stroke(3, LINE),
		})
		local zMax = zOf(last) + GAP * 2
		local zMin = -GAP
		local roadW = 220
		local world = Ui.new("Frame", { Name = "Street", Size = UDim2.new(1, 0, 0, (zMax - zMin) * K), BackgroundTransparency = 1, Parent = scene })
		local function yOf(z: number): number
			return (zMax - z) * K
		end
		-- Pavements, the road, its edge lines and the dashes down the middle.
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, roadW + 70, 1, 0), BackgroundColor3 = Color3.fromHex("#2c3557"), BorderSizePixel = 0, ZIndex = 1, Parent = world })
		local road = Ui.new("Frame", { Name = "Road", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, roadW, 1, 0), BackgroundColor3 = Color3.fromHex("#262a33"), BorderSizePixel = 0, ZIndex = 2, Parent = world })
		for _, x in { 0, 1 } do
			Ui.new("Frame", { AnchorPoint = Vector2.new(x, 0), Position = UDim2.new(x, if x == 0 then 8 else -8, 0, 0), Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = Color3.fromHex("#cfd8dc"), BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 2, Parent = road })
		end
		for z = zMin, zMax, 2 do
			Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, yOf(z)), Size = UDim2.fromOffset(4, K * 0.9), BackgroundColor3 = Color3.fromHex("#ffd54f"), BorderSizePixel = 0, ZIndex = 2, Parent = world })
		end
		-- Street lamps down both sides, pooling light on the pavement.
		for z = 3, zMax, GAP do
			for _, side in { -1, 1 } do
				local x = side * (roadW / 2 + 22)
				Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0, yOf(z)), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = Color3.fromHex("#ffe9a8"), BackgroundTransparency = 0.85, ZIndex = 2, Parent = world }, { Ui.round() })
				Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, x, 0, yOf(z)), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.fromHex("#fff3c4"), ZIndex = 3, Parent = world }, { Ui.round() })
			end
		end
		-- The start line, and the finish under the last arch: chequers across the road.
		for _, z in { 0, zOf(last) + 1.2 } do
			local row = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, yOf(z)), Size = UDim2.fromOffset(roadW - 16, 12), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 3, Parent = world })
			local cells = 17
			for i = 0, cells - 1 do
				for j = 0, 1 do
					if (i + j) % 2 == 1 then
						Ui.new("Frame", { Position = UDim2.new(i / cells, 0, j / 2, 0), Size = UDim2.new(1 / cells, 1, 0.5, 0), BackgroundColor3 = Color3.fromHex("#1b1f24"), BorderSizePixel = 0, ZIndex = 3, Parent = row })
					end
				end
			end
		end
		for i, t in tiers do
			arch(world, t, yOf(zOf(i - 1)), roadW)
		end
		-- Your race car at your tier, and the season's car at the finish.
		local mine = raceCar.raceCarOf(s.cars, s.raceCar)
		if mine then
			local pic = Thumb.car(mine.model, UDim2.fromOffset(110, 74), Paint.jobOf(mine), mine.hat, mine.mods, mine.panels, mine.trim, mine.skin, mine.modSkin)
			pic.Name = "MyCar"
			pic.AnchorPoint = Vector2.new(0.5, 0.5)
			pic.Position = UDim2.new(0.5, -roadW / 4 - 6, 0, yOf(carZ) + 30)
			pic.ZIndex = 9
			pic.Parent = world
		end
		if prizeCar then
			local pic = Thumb.new("Cars", prizeCar.id, UDim2.fromOffset(120, 80), Color3.fromHex(prizeCar.colors[1]))
			pic.Name = "SeasonCar"
			pic.AnchorPoint = Vector2.new(0.5, 0.5)
			pic.Position = UDim2.new(0.5, 0, 0, yOf(zOf(last) + 3.2))
			pic.ZIndex = 9
			pic.Parent = world
		end

		-- ── The tier chips ──────────────────────────────────────────────────────────────────────
		local chips = Ui.new("ScrollingFrame", {
			Name = "Chips",
			Position = UDim2.fromOffset(0, 38 + SCENE_H + 4),
			Size = UDim2.new(1, 0, 0, 66),
			CanvasSize = UDim2.fromOffset(count * 52 + 8, 0),
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 0,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = body,
		})
		local rings: { Frame } = {}
		local function look(z: number)
			viewZ = math.clamp(z, 0, zOf(last))
			local at = viewZ :: number
			world.Position = UDim2.fromOffset(0, SCENE_H * AT - (zMax - at) * K)
			local i = math.clamp(math.round((at - FIRST) / GAP), 0, last)
			for k, r in rings do
				r.Visible = k - 1 == i
			end
			-- Keeps the tier being looked at in the middle of the chip row.
			-- (The row is the sheet's width less its padding until it's been laid out.)
			local w = if chips.AbsoluteSize.X > 0 then chips.AbsoluteSize.X else 432
			local x = 6 + i * 52 - (w - 46) / 2
			chips.CanvasPosition = Vector2.new(math.max(0, x), 0)
		end
		for i, t in tiers do
			local colors = if t.car then (if t.state == "got" then BG.got else "#311b92") else BG[t.state]
			local fg = if t.car then "#ffffff" else SIGN_INK[t.state]
			local shadow, face = Ui.shadowed({ Name = `Tier{t.n}`, Position = UDim2.fromOffset(6 + (i - 1) * 52, 9), Size = UDim2.fromOffset(46, 46), Parent = chips }, { radius = 12, stroke = 3, drop = 3, dark = 0.3, class = "TextButton", color = Color3.fromHex(colors) })
			local _ = shadow
			Ui.text({ Text = if t.car then "🚗" else tostring(t.n), TextSize = if t.car then 20 else 18, TextColor3 = Color3.fromHex(fg), Size = UDim2.fromScale(1, 1), Parent = face })
			local ring = Ui.new("Frame", { Name = "On", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 10, 1, 10), BackgroundTransparency = 1, Visible = false, Parent = face }, { Ui.corner(16), Ui.stroke(3, Color3.fromHex("#2f7ff0")) })
			table.insert(rings, ring)
			face.Activated:Connect(function()
				look(zOf(i - 1))
			end)
		end
		look(viewZ :: number)

		-- Drag the road (or scroll the wheel) to look along it.
		local drag: { y: number, x: number, z: number }? = nil
		scene.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				drag = { x = input.Position.X, y = input.Position.Y, z = viewZ :: number }
			end
		end)
		scene.InputChanged:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseWheel then
				look((viewZ :: number) - input.Position.Z * 2)
			end
		end)
		table.insert(drawn, UserInputService.InputChanged:Connect(function(input: InputObject)
			local d = drag
			if d and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				look(d.z + ((input.Position.Y - d.y) + (d.x - input.Position.X) * 0.3) / K)
			end
		end))
		table.insert(drawn, UserInputService.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				drag = nil
			end
		end))

		-- ── The button ──────────────────────────────────────────────────────────────────────────
		local at = { Name = "Go", Position = UDim2.new(0, 0, 0, 38 + SCENE_H + 4 + 66 + 4), Size = UDim2.new(1, 0, 0, 44), Parent = body }
		if #ready > 0 then
			Ui.buy(at, `🎁 Collect {#ready}`, "green", function()
				for _, i in ready do
					Remote.act("claimTier", i)
				end
			end, 20)
		else
			Ui.buy(at, "📋 Earn ⭐", "garage", function()
				ctx.open("goals")
			end, 20)
		end
	end

	render()
	local changed = Remote.changed:Connect(render)
	overlay.Destroying:Connect(function()
		changed:Disconnect()
		for _, c in drawn do
			c:Disconnect()
		end
	end)
	return overlay
end

-- The HUD's Star Pass button (SeasonButton): a star, with the number of tiers ready to collect.
-- Shown from level 3, as the web's 'season' unlock. Returns the refresh the HUD runs.
Season.hudOrder = 3
function Season.hudButton(row: Instance, ctx: any): (any) -> ()
	local slot = Ui.new("Frame", { Name = "Season", Size = UDim2.fromOffset(40, 43), BackgroundTransparency = 1, LayoutOrder = Season.hudOrder, Parent = row })
	local _, face = Ui.button({ Name = "SeasonButton", Position = UDim2.fromOffset(2.5, 5.5), Size = UDim2.fromOffset(35, 35), Parent = slot }, "white", function()
		ctx.open("season")
	end, { radius = 12, stroke = 2.5, drop = 3, split = 0.5, flat = true })
	Ui.text({ Text = "★", Body = true, Weight = "heavy", TextSize = 26, TextColor3 = Ui.BLUE, Position = UDim2.fromOffset(0, -1), Size = UDim2.fromScale(1, 1), Parent = face })
	local badge = Ui.new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromHex("#ff5252"), Visible = false, ZIndex = 3, Parent = face }, { Ui.corner(10), Ui.stroke(2, Ui.WHITE) })
	local badgeText = Ui.text({ Text = "", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = badge })
	return function(s: any)
		slot.Visible = s.level >= 3
		local n = if slot.Visible then store.seasonClaimable(s) else 0
		badge.Visible = n > 0
		Ui.setText(badgeText, tostring(n))
	end
end

return Season
