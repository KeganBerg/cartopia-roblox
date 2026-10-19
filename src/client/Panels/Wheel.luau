--!strict
-- The Daily Spin, as the web game's WheelPanel (ui/Wheel.tsx, wheel.css): one free spin a day on
-- a giant show wheel in a tyre shop at night (client/WheelShop, the web's scene/WheelScene.tsx).
-- The shop takes the whole screen and the camera; the odds and the Spin button sit in the dock,
-- right of the wheel on a wide screen and under it on a phone, as on the web.
--
-- The spin is rolled on the server (server/Crates spin, the web store's own spinWheel with the
-- web's odds); the wheel spins up straight away and then slows onto the slice it gave, as on the
-- web. The prize card shows what was won, on your own car for a part or a paint.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local wheel = require(Game.wheel) :: any
local crates = require(Game.crates) :: any
local raceCar = require(Game.raceCar) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint) :: any
local Client = script.Parent.Parent
local Remote = require(Client.Remote)
local Ui = require(Client.Ui)
local SkinShop = require(Client.SkinShop)
local Icons = require(Client.Icons)
local Thumb = require(Client.Thumb)
local Sfx = require(Client.Sounds.Sfx)
local WheelShop = require(Client.WheelShop)
local DayNight = require(Client.DayNight)
local Kit = require(Client.ArcadeGames.StarKit)

local Wheel = {}
Wheel.id = "daily"

local WHEEL = wheel.WHEEL
local N = #WHEEL
local STEP = 360 / N
local FULL_SPEED = 720 -- degrees a second
local STEP_NAME = "DailySpin"
local SCENE_STEP = "DailySpinScene"

local BG = Color3.fromHex("#120c1c")
local DOCK = Color3.fromHex("#181226")

local function mix(a: Color3, b: Color3, t: number): Color3
	return b:Lerp(a, t)
end

local function tierColor(tier: string): Color3
	return Color3.fromHex(wheel.TIER_COLOR[tier])
end

local function pct(p: number): string
	return if p < 1 then string.format("%.1f%%", p) else `{math.round(p)}%`
end

-- What a slice pays, for the odds: coins at your level, or the gems.
local function amount(s: any, level: number): string
	if s.kind == "coins" then
		return Ui.commas(wheel.wheelCoins(s.mult, level))
	elseif s.kind == "gems" or s.kind == "jackpot" then
		return tostring(s.gems)
	end
	return ""
end

local SKIN_SWATCH = (function()
	for _, s in data.SKINS do
		if s.id == "prismatic" then
			return s.swatch
		end
	end
	return data.SKINS[1] and data.SKINS[1].swatch
end)()

-- A skin's swatch (a CSS colour or gradient) as a round chip.
local function swatch(parent: Instance, css: string?, size: number, props: { [string]: any }?): Frame
	local cols = {}
	for hex in string.gmatch(css or "", "#%x%x%x%x?%x?%x?") do
		local ok, c = pcall(Color3.fromHex, hex)
		if ok then
			table.insert(cols, c)
		end
	end
	if #cols == 0 then
		table.insert(cols, Color3.fromHex("#ff4081"))
	end
	local f = Ui.new("Frame", { Name = "Swatch", Size = UDim2.fromOffset(size, size), BackgroundColor3 = cols[1], BorderSizePixel = 0 }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
	if #cols > 1 then
		local keys = {}
		for i, c in cols do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#cols - 1), c))
		end
		Ui.new("UIGradient", { Color = ColorSequence.new(keys), Rotation = 45, Parent = f })
	end
	for k, v in (props or {}) :: { [string]: any } do
		(f :: any)[k] = v
	end
	SkinShop.picture(f, css)
	f.Parent = parent
	return f
end

-- A stack of n currency icons, a little offset, so a bigger prize looks bigger (Stack).
local function stack(parent: Instance, n: number, gem: boolean, size: number, z: number): Frame
	local f = Ui.new("Frame", { Name = "Stack", Size = UDim2.fromOffset(size + (n - 1) * size * 0.32, size + (n - 1) * size * 0.12), BackgroundTransparency = 1, ZIndex = z, Parent = parent })
	for i = 0, n - 1 do
		local pos = UDim2.fromOffset(i * size * 0.32, (n - 1 - i) * size * 0.12)
		if gem then
			Ui.text({ Text = "💎", TextSize = size * 0.9, Position = pos, Size = UDim2.fromOffset(size, size), ZIndex = z + i, Parent = f })
		else
			local c = Icons.draw("coin", f, size, nil, nil, pos)
			c.ZIndex = z + i
		end
	end
	return f
end

-- A slice's prize as icons (SliceIcon): coins, gems, the crowned jackpot, a part or a paint.
local function sliceIcon(parent: Instance, s: any, size: number, z: number): Frame
	if s.kind == "coins" then
		return stack(parent, if s.mult < 0.5 then 1 elseif s.mult < 1 then 2 else 3, false, size, z)
	elseif s.kind == "gems" then
		return stack(parent, wheel.gemPile(s.gems), true, size, z)
	elseif s.kind == "jackpot" then
		local st = stack(parent, 3, true, size, z)
		local w, h = st.Size.X.Offset, st.Size.Y.Offset
		local f = Ui.new("Frame", { Name = "Jackpot", Size = UDim2.fromOffset(w, h + 13), BackgroundTransparency = 1, ZIndex = z, Parent = parent })
		Ui.text({ Text = "👑", TextSize = 13, Size = UDim2.new(1, 0, 0, 15), ZIndex = z + 4, Parent = f })
		st.Position = UDim2.fromOffset(0, 11)
		st.Parent = f
		return f
	elseif s.kind == "part" then
		local f = Ui.new("Frame", { Name = "Part", Size = UDim2.fromOffset(size + 2, size + 2), BackgroundTransparency = 1, ZIndex = z, Parent = parent })
		Ui.text({ Text = "⚙️", TextSize = size, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = f })
		return f
	end
	return swatch(parent, SKIN_SWATCH, size, { ZIndex = z })
end

-- One line of what was won (Prize): gems, coins, the part's name or the paint.
local function prizeLine(parent: Instance, spin: any): Frame
	local line = Ui.new("Frame", { Name = "PrizeLine", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 2, Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local d = spin.open.drop
	local gems = wheel.spinGems(spin.open)
	local function words(text: string)
		Ui.text({ Text = text, TextSize = 28, Size = UDim2.fromOffset(math.min(300, Ui.textWidth(text, 28) + 4), 36), TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 3, Parent = line })
	end
	if gems > 0 then
		Ui.text({ Text = "💎", TextSize = 26, Size = UDim2.fromOffset(30, 30), LayoutOrder = 2, Parent = line })
		words(`+{gems}`)
	elseif d.kind == "coins" or d.kind == "skindupe" then
		if d.kind == "skindupe" then
			local def = crates.skinOf(d.skin, d.part)
			swatch(line, def and def.swatch, 28, { LayoutOrder = 1 })
		end
		Icons.draw("coin", line, 28).LayoutOrder = 2
		words(`+{Ui.commas(d.coins)}`)
	elseif d.kind == "mod" then
		Ui.text({ Text = "⚙️", TextSize = 24, Size = UDim2.fromOffset(28, 30), LayoutOrder = 2, Parent = line })
		local m = data.modDef(d.mod)
		words(if m then m.name else "New part")
	elseif d.kind == "skin" then
		local def = crates.skinOf(d.skin, d.part)
		swatch(line, def and def.swatch, 28, { LayoutOrder = 1 })
		words(if def then def.name else "New paint")
	end
	return line
end

-- The prize on your own car (prizeLook): the part fitted, or the paint on it. Nil for the rest.
local function prizeCar(parent: Instance, spin: any, carsAt: { any }, paintUid: string?): GuiObject?
	local d = spin.open.drop
	local car: any = nil
	local mods: { string }? = nil
	local skin: string? = nil
	if d.kind == "mod" then
		for _, c in carsAt do
			if c.uid == d.car then
				car = c
			end
		end
		if car then
			mods = { d.mod }
			for _, m in car.mods or {} do
				table.insert(mods :: { string }, m)
			end
		end
	elseif (d.kind == "skin" or d.kind == "skindupe") and not d.part then
		for _, c in carsAt do
			if c.uid == paintUid then
				car = c
			end
		end
		skin = d.skin
	end
	if not car then
		return nil
	end
	local function draw(): ViewportFrame
		local v = Thumb.car(car.model, UDim2.fromOffset(200, 130), Paint.jobOf(car), car.hat, mods or car.mods, car.panels, car.trim, skin or car.skin, car.modSkin)
		v.Name = "PrizeCar"
		v.LayoutOrder = 1
		v.Parent = parent
		return v
	end
	local v = draw()
	if mods then
		-- The part's meshes load the first time a car needs them: draw it again once they're in.
		task.spawn(function()
			Remote.meshesFor(car.model)
			if v.Parent then
				v:Destroy()
				draw()
			end
		end)
	end
	return v
end

-- The open shop's way out: only one Daily Spin at a time, so a new one first takes down any shop
-- whose panel went without saying so.
local current: (() -> ())? = nil

function Wheel.open(ctx: any): Instance
	if current then
		current()
	end
	local s0 = store.useGame.getState()
	-- Already spun today: nothing to show (the web closes the panel).
	if s0.lastDaily == store.today() then
		ctx.toast("Spun today. Back tomorrow!")
		return Ui.new("Frame", { Name = "Panel", Visible = false, Parent = ctx.gui })
	end
	local level = s0.level
	-- The HUD keeps a stand-in so it knows the panel is open; closing it closes the shop.
	local overlay = Ui.new("Frame", { Name = "Panel", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = ctx.gui })

	-- ── The shop takes the screen and the camera ────────────────────────────────────────────────
	local shop = WheelShop.build(level)
	local hudGui = (ctx.gui :: Instance):FindFirstAncestorOfClass("ScreenGui")
	-- The screen is laid out in the web's CSS pixels, one to a Roblox pixel (the web's own sizes).
	local gui = Ui.new("ScreenGui", { Name = "DailySpin", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = if hudGui then hudGui.Parent else ctx.gui })
	local page = Ui.new("Frame", { Name = "Screen", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	if hudGui then
		hudGui.Enabled = false
	end
	local cam, giveBack = Kit.takeCamera(WheelShop.FOV)
	-- The shop's dark air (WheelScene's fog, 13 to 30 m) and its own light, not the town's sun.
	DayNight.setRaceFog({ color = WheelShop.BG, near = 130, far = 300, room = { ambient = Color3.fromHex("#3c3a58") } })

	-- ── The top bar: title, wallet, close ───────────────────────────────────────────────────────
	local top = Ui.new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = Color3.fromHex("#0a1e3c"), BorderSizePixel = 0, ZIndex = 20, Parent = page }, {
		Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	local title = Ui.text({ Name = "Title", Text = "🎡 Daily Spin", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -300, 0, 42), Shadow = 2, ShadowColor = Ui.BLACK, ShadowTransparency = 0.65, ZIndex = 21, Parent = top })
	local wallet = Ui.new("Frame", { Name = "Wallet", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -66, 0, 16), Size = UDim2.fromOffset(240, 28), BackgroundTransparency = 1, ZIndex = 21, Parent = top }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local function walletPill(order: number, gem: boolean): (Frame, TextLabel)
		local pill = Ui.new("Frame", { Size = UDim2.fromOffset(80, 26), BackgroundColor3 = Color3.fromHex("#120c1c"), BackgroundTransparency = 0.3, LayoutOrder = order, ZIndex = 21, Parent = wallet }, { Ui.corner(13), Ui.stroke(2, Ui.WHITE, 0.4) })
		if gem then
			Ui.text({ Text = "💎", TextSize = 14, Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(18, 20), ZIndex = 21, Parent = pill })
		else
			Icons.draw("coin", pill, 18, nil, nil, UDim2.fromOffset(4, 4)).ZIndex = 21
		end
		local t = Ui.text({ Text = "", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(26, 0), Size = UDim2.new(1, -30, 1, 0), ZIndex = 21, Parent = pill })
		return pill, t
	end
	local coinPill, coinText = walletPill(1, false)
	local gemPill, gemText = walletPill(2, true)
	local function refreshWallet()
		local s = store.useGame.getState()
		local c, g = Ui.compact(s.coins), Ui.compact(s.bucks)
		Ui.setText(coinText, c)
		Ui.setText(gemText, g)
		coinPill.Size = UDim2.fromOffset(Ui.textWidth(c, 15) + 38, 26)
		gemPill.Size = UDim2.fromOffset(Ui.textWidth(g, 15) + 38, 26)
	end
	refreshWallet()
	Ui.closeButton({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 9), Size = UDim2.fromOffset(42, 42), ZIndex = 21, Parent = top }, ctx.close)

	-- ── The dock: the odds and Spin ─────────────────────────────────────────────────────────────
	local phase = "idle"
	local wide = true
	local dock: Frame? = nil
	local go: TextButton? = nil
	local goText = "Spin"
	local function setGo(text: string, on: boolean)
		goText = text
		local b = go
		if not b then
			return
		end
		Ui.setText(b:FindFirstChild("Label") :: TextLabel, text)
		local grad = b:FindFirstChildOfClass("UIGradient")
		if grad then
			grad.Color = if on then Ui.seq("#66bb6a", "#2e7d32") else Ui.seq("#6c9a6e", "#33573a")
		end
	end
	local spin: () -> ()

	-- Wide: two columns of rows (icon, amount, odds at the end), right of the wheel. Tall: four
	-- columns of tiles (icon over amount over odds) along the bottom.
	local function buildDock(vp: Vector2)
		if dock then
			dock:Destroy()
		end
		local rowH = if wide then 34 else 64
		local cols = if wide then 2 else 4
		local oddsH = (N / cols) * rowH + (N / cols - 1) * 5 + 10
		local w = if wide then 384 else math.min(520, vp.X - 16)
		local f = Ui.new("Frame", {
			Name = "Dock",
			AnchorPoint = if wide then Vector2.new(1, 0.5) else Vector2.new(0.5, 1),
			Position = if wide then UDim2.new(1, -16, 0.5, 0) else UDim2.new(0.5, 0, 1, -10),
			Size = UDim2.fromOffset(w, oddsH + 8 + 60),
			BackgroundTransparency = 1,
			ZIndex = 10,
			Parent = page,
		})
		local odds = Ui.new("Frame", { Name = "Odds", Size = UDim2.new(1, 0, 0, oddsH), BackgroundColor3 = DOCK, BackgroundTransparency = 0.18, ZIndex = 10, Parent = f }, {
			Ui.corner(14),
			Ui.stroke(2, Ui.WHITE, 0.75),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }),
			Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / cols, -5 * (cols - 1) / cols - 1, 0, rowH), CellPadding = UDim2.fromOffset(5, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, s in WHEEL do
			local c = tierColor(s.tier)
			local row = Ui.new("Frame", { Name = s.id, LayoutOrder = i, BackgroundColor3 = Ui.WHITE, ZIndex = 10, Parent = odds }, {
				Ui.corner(10),
				Ui.stroke(2, c),
				Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(mix(c, Color3.fromHex("#1a1428"), 0.55), mix(c, Color3.fromHex("#120c1c"), 0.25)) }),
			})
			local text = amount(s, level)
			if text == "" then
				text = if s.kind == "part" then "Part" else "Paint"
			end
			local icon = sliceIcon(row, s, 18, 11)
			if wide then
				icon.AnchorPoint = Vector2.new(0, 0.5)
				icon.Position = UDim2.new(0, 10, 0.5, 0)
				Ui.text({ Text = text, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(18 + icon.Size.X.Offset, 0), Size = UDim2.new(1, -70, 1, 0), Shadow = 1, ShadowColor = Ui.BLACK, ShadowTransparency = 0.5, ZIndex = 11, Parent = row })
				Ui.text({ Text = pct(wheel.wheelPct(s)), TextSize = 12, TextTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 0), Size = UDim2.new(0, 50, 1, 0), ZIndex = 11, Parent = row })
			else
				local ih = icon.Size.Y.Offset
				local top0 = (rowH - (ih + 2 + 15 + 3 + 12)) / 2
				icon.AnchorPoint = Vector2.new(0.5, 0)
				icon.Position = UDim2.new(0.5, 0, 0, top0)
				Ui.text({ Text = text, TextSize = 15, Position = UDim2.fromOffset(0, top0 + ih + 2), Size = UDim2.new(1, 0, 0, 15), Shadow = 1, ShadowColor = Ui.BLACK, ShadowTransparency = 0.5, ZIndex = 11, Parent = row })
				Ui.text({ Text = pct(wheel.wheelPct(s)), TextSize = 12, TextTransparency = 0.2, Position = UDim2.fromOffset(0, top0 + ih + 20), Size = UDim2.new(1, 0, 0, 12), ZIndex = 11, Parent = row })
			end
		end
		-- Spin: the depot's big green open button (.crate-open.wh-go).
		local _, b = Ui.button({ Name = "Spin", Position = UDim2.fromOffset(0, oddsH + 8), Size = UDim2.new(1, 0, 0, 56), Parent = f }, "green", nil, { radius = 16, stroke = 3, strokeColor = Ui.WHITE, drop = 4, dark = 0.4, text = "Spin", textSize = 26, textShadow = 2 })
		b.Activated:Connect(function()
			spin()
		end)
		dock, go = f, b
		setGo(goText, phase == "idle")
	end

	-- ── The prize card ─────────────────────────────────────────────────────────────────────────
	local prizeCard: Frame? = nil
	local function placePrize(slide: boolean)
		local glow = prizeCard
		if not glow then
			return
		end
		local vp = cam.ViewportSize
		local h = glow.Size.Y.Offset
		local w = if wide then 370 else math.min(530, vp.X - 6)
		glow.Size = UDim2.fromOffset(w, h)
		glow.AnchorPoint = if wide then Vector2.new(1, 0.5) else Vector2.new(0.5, 1)
		local home = if wide then UDim2.new(1, -11, 0.5, 0) else UDim2.new(0.5, 0, 1, -7)
		if slide then
			-- Slides in from the side on a wide screen and up from the bottom on a phone (prize-in).
			glow.Position = if wide then UDim2.new(1, w, 0.5, 0) else UDim2.new(0.5, 0, 1, h + 20)
			TweenService:Create(glow, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = home }):Play()
		else
			glow.Position = home
		end
	end

	-- ── Fitting the screen ─────────────────────────────────────────────────────────────────────
	local function layout()
		local vp = cam.ViewportSize
		local cf, isWide = shop.camera(vp)
		cam.CFrame = cf
		local changed = isWide ~= wide or dock == nil
		wide = isWide
		shop.setWide(wide)
		title.TextSize = if vp.Y < 500 then 16 elseif vp.X >= 900 then 24 else 20
		if phase ~= "won" and changed then
			buildDock(vp)
		elseif dock then
			local w = if wide then 384 else math.min(520, vp.X - 16)
			dock.Size = UDim2.fromOffset(w, dock.Size.Y.Offset)
		end
		placePrize(false)
	end
	layout()
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout))
	-- The shop lives each frame: chase lights, the flapper, the winner's glow and the confetti; the
	-- camera stays put (the town camera is paused, and nothing else may move it).
	RunService:BindToRenderStep(SCENE_STEP, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		shop.step(math.min(dt, 0.05))
		cam.CFrame = (shop.camera(cam.ViewportSize))
	end)

	-- ── The spin ────────────────────────────────────────────────────────────────────────────────
	local angle = 0
	local clock = 0
	local spinning = false
	local carsAt = s0.cars

	local function setAngle(a: number)
		angle = a
		shop.setAngle(a)
	end
	local function stop()
		if spinning then
			spinning = false
			RunService:UnbindFromRenderStep(STEP_NAME)
		end
	end

	local function win(spin: any)
		phase = "won"
		local slice = wheel.wheelSlice(spin.slice)
		local color = if slice then tierColor(slice.tier) else Color3.fromHex("#ffd54f")
		shop.won(if slice then table.find(WHEEL, slice) else nil, color)
		Sfx.wheel.win(slice and slice.tier)
		if dock then
			dock.Visible = false
		end
		local s = store.useGame.getState()
		local paintUid = s.selectedCar
		local has = false
		for _, c in carsAt do
			has = has or c.uid == paintUid
		end
		if not has then
			local rc = raceCar.raceCarOf(carsAt, s.raceCar)
			paintUid = rc and rc.uid
		end
		-- The prize card: the render, one line, Collect, edged and glowing in the tier's colour.
		local glow = Ui.new("Frame", { Name = "Prize", Size = UDim2.fromOffset(370, 10), BackgroundColor3 = color, BackgroundTransparency = 0.75, ZIndex = 12, Parent = page }, { Ui.corner(24) })
		local card = Ui.new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -10, 1, -10), BackgroundColor3 = Color3.fromHex("#140e20"), BackgroundTransparency = 0.08, ZIndex = 12, Parent = glow }, {
			Ui.corner(18),
			Ui.stroke(3, color),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }),
			Ui.new("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local h = 24
		local pic = prizeCar(card, spin, carsAt, paintUid)
		if pic then
			h += 130 + 8
		elseif slice then
			local box = Ui.new("Frame", { Name = "PrizeIcon", LayoutOrder = 1, Size = UDim2.fromOffset(160, 64), BackgroundTransparency = 1, ZIndex = 13, Parent = card })
			-- The icon's glow (drop-shadow 0 0 10px in the tier's colour).
			Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(72, 60), BackgroundColor3 = color, BackgroundTransparency = 0.8, ZIndex = 12, Parent = box }, { Ui.round() })
			local icon = sliceIcon(box, slice, 48, 13)
			icon.AnchorPoint = Vector2.new(0.5, 0.5)
			icon.Position = UDim2.fromScale(0.5, 0.5)
			h += 64 + 8
		end
		prizeLine(card, spin)
		h += 36 + 8
		local collectHolder = Ui.new("Frame", { Name = "CollectRow", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = card })
		local _, collect = Ui.button({ Name = "Collect", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 46), Parent = collectHolder }, "green", function()
			ctx.close()
		end, { radius = 16, stroke = 3, strokeColor = Ui.WHITE, drop = 4, dark = 0.4, text = "Collect", textSize = 22, textShadow = 2 })
		local cg = collect:FindFirstChildOfClass("UIGradient")
		if cg then
			cg.Color = Ui.seq("#66bb6a", "#2e7d32")
		end
		h += 50
		glow.Size = UDim2.fromOffset(370, h + 10)
		prizeCard = glow
		placePrize(true)
	end

	spin = function()
		if phase ~= "idle" then
			return
		end
		phase = "spin"
		setGo("Spinning…", false)
		carsAt = store.useGame.getState().cars
		-- Spin up while the server rolls.
		local got: any = nil
		task.spawn(function()
			local r = Remote.spin()
			got = if r then r else false
		end)
		local v = 0
		local started = clock
		local peg = math.floor(angle / STEP)
		local decel: { from: number, to: number, t0: number, dur: number }? = nil
		spinning = true
		RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Last.Value, function(step: number)
			local dt = math.min(0.05, step)
			clock += dt
			local a: number
			local d = decel
			if not d then
				v = math.min(FULL_SPEED, FULL_SPEED * (clock - started) / 0.3)
				a = angle + v * dt
				if got == false then
					-- Couldn't spin (the toast says why): stop where it is.
					setAngle(a)
					stop()
					phase = "idle"
					setGo("Spin", true)
					return
				end
				if got and clock - started > 0.7 then
					local slice = 0
					for i, s in WHEEL do
						if s.id == got.slice then
							slice = i - 1
						end
					end
					local jitter = (math.random() - 0.5) * STEP * 0.6
					-- A clockwise turn that puts the slice's middle under the flapper at the top.
					local land = ((-(slice + 0.5) * STEP + jitter - a) % 360 + 360) % 360
					local dist = 360 * 3 + land
					-- Slows at the speed it had (ease-out cubic starts at 3 x dist / time), kept to a few seconds.
					decel = { from = a, to = a + dist, t0 = clock, dur = math.min(6, math.max(3.5, 3 * dist / math.max(v, 1))) }
				end
			else
				local t = math.min(1, (clock - d.t0) / d.dur)
				a = d.from + (d.to - d.from) * (1 - (1 - t) ^ 3)
				v = 3 * (d.to - d.from) / d.dur * (1 - t) ^ 2
				if t >= 1 then
					setAngle(d.to)
					stop()
					win(got)
					return
				end
			end
			setAngle(a)
			-- The flapper knocks as each peg passes.
			local p = math.floor(a / STEP)
			if p ~= peg then
				peg = p
				Sfx.wheel.tick(math.min(1, v / FULL_SPEED))
				shop.kick()
			end
		end)
	end

	-- A save that says today's spin is taken (spun elsewhere) while nothing is spinning: close.
	table.insert(conns, Remote.changed:Connect(function()
		refreshWallet()
		if phase == "idle" and store.useGame.getState().lastDaily == store.today() then
			ctx.close()
		end
	end))
	local closed = false
	local function closeShop()
		if closed then
			return
		end
		closed = true
		if current == closeShop then
			current = nil
		end
		for _, c in conns do
			c:Disconnect()
		end
		stop()
		RunService:UnbindFromRenderStep(SCENE_STEP)
		gui:Destroy()
		shop.destroy()
		DayNight.setRaceFog(nil)
		giveBack()
		if hudGui then
			hudGui.Enabled = true
		end
	end
	current = closeShop
	overlay.Destroying:Connect(closeShop)
	return overlay
end

return Wheel
