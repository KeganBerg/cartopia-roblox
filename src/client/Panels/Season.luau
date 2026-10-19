--!strict
-- Star Pass, as the web game's SeasonPanel (ui/Season.tsx, season.css): stars from daily and
-- weekly tasks unlock a tier every STARS_PER_TIER. The header has your stars, the bar to the next
-- tier and the time left in the season; under it Main Street at night (client/PassStreet, as
-- scene/SeasonScene.tsx) with an arch over the road for every tier, its prize on a lit sign and a
-- star on top, your race car at your tier and the season's own car parked at the finish. Drag the
-- road, or tap a tier chip below it, to look along it. The button collects every tier reached, or
-- goes to Goals to earn stars.
-- Also the HUD's star button with the number of tiers ready (SeasonButton).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local Client = script.Parent.Parent
local Remote = require(Client.Remote)
local Ui = require(Client.Ui)
local SkinShop = require(Client.SkinShop)
local Icons = require(Client.Icons)
local PassStreet = require(Client.PassStreet)

local Season = {}
Season.id = "season"

local LINE = Ui.LINE
local INK = Ui.INK

-- scene/SeasonScene.tsx: world units between tiers, and tier 1 past the start line.
local GAP, FIRST = PassStreet.GAP, PassStreet.FIRST
local SCENE_H = 416 -- min(52vh, 440px) at 800px

local BG = { got = "#45b649", ready = "#ffc533", locked = "#e3e9f1" }
local SIGN_INK = { got = "#ffffff", ready = "#14213d", locked = "#4a6283" }

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
	SkinShop.picture(f, swatch)
	f.Parent = parent
	return f
end

-- The tiers as the scene shows them (Tier in SeasonScene.tsx).
local function tiersOf(p: any, prizeCar: any): { PassStreet.Tier }
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

-- A value written out the same way every time, so a car that changed in any way is told apart.
local function keyOf(v: any): string
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in v do
		table.insert(keys, tostring(k))
	end
	table.sort(keys)
	local out = {}
	for _, k in keys do
		local val = v[k]
		if val == nil then
			val = v[tonumber(k)]
		end
		table.insert(out, `{k}={keyOf(val)}`)
	end
	return `\{{table.concat(out, ",")}\}`
end

-- The open Star Pass's teardown (its street, the frame step), so only one is ever running.
local current: (() -> ())? = nil

function Season.open(ctx: any): Instance
	if current then
		current()
	end
	local overlay, _, body = Ui.panel(ctx.gui, "⭐ Star Pass", { width = 460, height = 61 + 10 + 30 + 8 + SCENE_H + 8 + 56 + 8 + 44 + 16, onClose = ctx.close })
	local count = #data.SEASON_TIERS
	local last = count - 1
	local per = data.STARS_PER_TIER

	-- The season as the save has it now.
	local function season(): (any, any, any)
		local s = store.useGame.getState()
		local n = data.seasonNumber(now())
		local p = store.currentSeason({ season = s.season }, data.seasonEndsAt(n) - 1)
		local def = data.seasonOf(p.n)
		return s, p, if def.car then data.carDef(def.car) else nil
	end

	-- ── The header: stars, the bar, the time left ──────────────────────────────────────────────
	local head = Ui.new("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = body })
	local countLabel = Ui.text({ Name = "Count", Text = "", TextSize = 26, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Parent = head })
	local ends = Ui.new("Frame", { Name = "Ends", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), BackgroundColor3 = Color3.fromHex("#311b92"), Parent = head }, { Ui.round(), Ui.stroke(3, LINE) })
	local endsLabel = Ui.text({ Text = "", Body = true, Weight = "heavy", TextSize = 16, Size = UDim2.fromScale(1, 1), Parent = ends })
	local bar = Ui.new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.fromHex("#dfe7f2"), ClipsDescendants = true, Parent = head }, { Ui.round(), Ui.stroke(3, LINE) })
	local fill = Ui.new("Frame", { Name = "Fill", BackgroundColor3 = Color3.fromHex("#ffb300"), BorderSizePixel = 0, Parent = bar }, { Ui.round() })
	local toGo = Ui.text({ Name = "ToGo", Text = "", Body = true, Weight = "heavy", TextSize = 14, TextColor3 = LINE, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = bar })
	local function drawHead(p: any)
		local reached = math.min(count, p.stars // per)
		local into = if reached >= count then per else p.stars % per
		local countText = `⭐ {p.stars}`
		local countW = Ui.textWidth(countText, 26) + 18
		Ui.setText(countLabel, countText)
		countLabel.Size = UDim2.new(0, countW, 1, 0)
		local endsText = `⏱ {left(data.seasonEndsAt(p.n) - now())}`
		local endsW = Ui.textWidth(endsText, 16) + 30
		Ui.setText(endsLabel, endsText)
		ends.Size = UDim2.fromOffset(endsW, 24)
		bar.Position = UDim2.new(0, countW + 3, 0.5, 0)
		bar.Size = UDim2.new(1, -(countW + endsW + 22), 0, 22)
		fill.Size = UDim2.fromScale(into / per, 1)
		fill.Visible = into > 0
		Ui.setText(toGo, if reached >= count then "Max" else `{per - into} to go`)
	end

	-- ── Main Street at midnight ────────────────────────────────────────────────────────────────
	local scene = Ui.new("Frame", { Name = "Scene", Active = true, Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 0, SCENE_H), BackgroundColor3 = Color3.fromHex("#101a3a"), ClipsDescendants = true, Parent = body }, {
		Ui.corner(16),
		Ui.stroke(3, LINE),
	})
	local street = PassStreet.new(scene, SCENE_H, count)

	-- ── The tier chips: each prize as a picture, its tier in the corner ─────────────────────────
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
	local viewZ = 0
	local function look(z: number)
		viewZ = math.clamp(z, 0, zOf(last))
		street.look(viewZ)
		local i = math.clamp(math.round((viewZ - FIRST) / GAP), 0, last)
		for k, r in rings do
			r.Visible = k - 1 == i
		end
		-- Keeps the tier being looked at in the middle of the chip row.
		-- (The row is the sheet's width less its padding until it's been laid out.)
		local scale = if scene.AbsoluteSize.Y > 0 then scene.AbsoluteSize.Y / SCENE_H else 1
		local w = if chips.AbsoluteSize.X > 0 then chips.AbsoluteSize.X / scale else 432
		local x = 6 + i * 52 - (w - 46) / 2
		chips.CanvasPosition = Vector2.new(math.clamp(x, 0, math.max(0, count * 52 + 8 - w)) * scale, 0)
	end
	local function drawChips(tiers: { PassStreet.Tier })
		chips:ClearAllChildren()
		table.clear(rings)
		for i, t in tiers do
			local colors = if t.car then (if t.state == "got" then BG.got else "#311b92") else BG[t.state]
			local fg = Color3.fromHex(if t.car then "#ffffff" else SIGN_INK[t.state])
			local _, face = Ui.shadowed({ Name = `Tier{t.n}`, Position = UDim2.fromOffset(6 + (i - 1) * 52, 9), Size = UDim2.fromOffset(46, 46), Parent = chips }, { radius = 12, stroke = 3, drop = 3, dark = 0.3, class = "TextButton", color = Color3.fromHex(colors) })
			-- Six pixels apart with thick outlines: no room to grow under the mouse.
			face:SetAttribute("MaxGrow", 0)
			local faded = if t.state == "locked" then 0.45 else 0
			if t.car then
				Ui.text({ Name = "Prize", Text = "🚗", TextSize = 20, TextTransparency = faded, Size = UDim2.fromScale(1, 1), Parent = face })
			elseif t.skin then
				Season.swatch(face, t.skin, 22, { Name = "Prize", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = faded })
			elseif t.gems > 0 or t.parts > 0 then
				Ui.text({ Name = "Prize", Text = if t.gems > 0 then "💎" else "⚙️", TextSize = 20, TextTransparency = faded, Size = UDim2.fromScale(1, 1), Parent = face })
			else
				local coin = Icons.draw("coin", face, 24, nil, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
				coin.Name = "Prize"
			end
			Ui.text({ Name = "N", Text = tostring(t.n), TextSize = 11, TextColor3 = fg, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -2, 1, 0), Size = UDim2.fromOffset(20, 14), TextXAlignment = Enum.TextXAlignment.Right, Parent = face })
			local ring = Ui.new("Frame", { Name = "On", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 10, 1, 10), BackgroundTransparency = 1, Visible = false, Parent = face }, { Ui.corner(16), Ui.stroke(3, Color3.fromHex("#2f7ff0")) })
			table.insert(rings, ring)
			face.Activated:Connect(function()
				look(zOf(i - 1))
			end)
		end
	end

	-- ── The button: collect every tier reached, or go and earn stars ────────────────────────────
	local go: Instance? = nil
	local function drawButton(ready: { number })
		if go then
			go:Destroy()
		end
		local at = { Name = "Go", Position = UDim2.new(0, 0, 0, 38 + SCENE_H + 4 + 66 + 4), Size = UDim2.new(1, 0, 0, 44), Parent = body }
		if #ready > 0 then
			go = Ui.buy(at, `🎁 Collect {#ready}`, "green", function()
				for _, i in ready do
					Remote.act("claimTier", i)
				end
			end, 20)
		else
			go = Ui.buy(at, "📋 Earn ⭐", "garage", function()
				ctx.open("goals")
			end, 20)
		end
	end

	-- Draws what changed in the save. Ticks of the town clock change nothing here, so nothing
	-- under a finger is rebuilt while it's being pressed.
	local tierKey, carKey, readyKey = "", "", ""
	local first = true
	local function refresh()
		local s, p, prizeCar = season()
		drawHead(p)
		local ready = {}
		for i = 0, last do
			if store.tierReady(p, i) then
				table.insert(ready, i)
			end
		end
		local tiers = tiersOf(p, prizeCar)
		local states = {}
		for _, t in tiers do
			table.insert(states, t.state)
		end
		local key = `{p.n}|{table.concat(states, ",")}|{prizeCar and prizeCar.id or ""}`
		if key ~= tierKey then
			tierKey = key
			street.setTiers(tiers)
			drawChips(tiers)
		end
		-- The car sits between the last tier reached and the next, as far as its stars go.
		local carZ = math.max(0.5, math.min(zOf(last), zOf(p.stars / per - 1)))
		local mine = raceCar.raceCarOf(s.cars, s.raceCar)
		local ck = `{carZ}|{keyOf(mine)}|{prizeCar and prizeCar.id or ""}`
		if ck ~= carKey then
			carKey = ck
			street.setCars(mine, carZ, prizeCar)
		end
		local rk = table.concat(ready, ",")
		if rk ~= readyKey or go == nil then
			readyKey = rk
			drawButton(ready)
		end
		if first then
			first = false
			local reached = math.min(count, p.stars // per)
			local firstOpen = ready[1] or math.min(last, reached)
			look(math.max(0, math.min(carZ - GAP, zOf(firstOpen))))
		else
			look(viewZ)
		end
	end
	refresh()

	-- Drag the road (or scroll the wheel) to look along it: up or left goes further along.
	local conns: { RBXScriptConnection } = {}
	local drag: { y: number, x: number, z: number }? = nil
	local function perPixel(): number
		local scale = if scene.AbsoluteSize.Y > 0 then scene.AbsoluteSize.Y / SCENE_H else 1
		return 0.04 / scale
	end
	table.insert(conns, scene.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drag = { x = input.Position.X, y = input.Position.Y, z = viewZ }
		end
	end))
	table.insert(conns, scene.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			look(viewZ - input.Position.Z)
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input: InputObject)
		local d = drag
		if d and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			look(d.z + ((d.y - input.Position.Y) + (d.x - input.Position.X)) * perPixel())
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			drag = nil
		end
	end))
	table.insert(conns, Remote.changed:Connect(refresh))

	local function close()
		current = nil
		RunService:UnbindFromRenderStep("StarPass")
		for _, c in conns do
			c:Disconnect()
		end
		street.destroy()
	end
	current = close
	-- Each frame: the camera along the road, the signs on their arches, and the clock.
	RunService:BindToRenderStep("StarPass", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if overlay.Parent == nil then
			close()
			return
		end
		street.step(dt)
		local _, p = season()
		drawHead(p)
	end)
	overlay.Destroying:Connect(function()
		if current == close then
			close()
		end
	end)
	-- The first picture straight away (the step runs from the next frame).
	street.step(1)
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
		-- The Star Pass and Deals arrive after the tutorial, at level 3 (web game/unlocks.ts "season").
		slot.Visible = require(ReplicatedStorage.Shared.Tutorial).unlocked(s, "season")
		local n = if slot.Visible then store.seasonClaimable(s) else 0
		badge.Visible = n > 0
		Ui.setText(badgeText, tostring(n))
	end
end

return Season
