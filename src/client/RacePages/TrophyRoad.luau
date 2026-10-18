--!strict
-- The Trophy Road page (ui/TrophyRoad.tsx): your trophies and how many to the next stop, the next
-- prize, and the road itself, a sign at every ROAD_STEP trophies with its prize (a gift on the
-- mystery ones) and your race car at your trophy count. The web draws it in 3D on the drag strip
-- (scene/TrophyRoadScene.tsx); here it is a flat road seen from the side that scrolls sideways.
-- Green and ticked: claimed. Gold: reached, waiting to be claimed. Grey: locked. Tap a stop in
-- the row under the road to look at it. The Claim button (on the web, the race bar's button)
-- claims every stop reached, through the store's claimRoad on the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local tr = require(Game.trophyRoad) :: any
local Remote = require(script.Parent.Parent.Remote)
local Ui = require(script.Parent.Parent.Ui)
local Icons = require(script.Parent.Parent.Icons)
local Thumb = require(script.Parent.Parent.Thumb)

local TrophyRoad = {}
TrophyRoad.id = "road"
TrophyRoad.title = "Trophy Road"
TrophyRoad.mini = { icon = "🛣️", label = "Trophy Road" }

-- One stop behind the first unclaimed one, then the ones ahead (TrophyRoad.tsx BEHIND, SHOWN).
local BEHIND = 1
local SHOWN = 11
-- The road: pixels from its start to the first stop shown, and between stops.
local FIRST = 110
local GAP = 170
local SIGN_W, SIGN_H = 140, 82

local BG = { got = "#45b649", ready = "#ffc533", locked = "#e3e9f1" }
local INK = { got = "#ffffff", ready = "#14213d", locked = "#4a6283" }
local POST = { got = "#2e7d32", ready = "#ff8f00", locked = "#90a4ae" }

-- Stops reached but not yet claimed (TrophyRoad.tsx roadReady).
local function ready(s: any): number
	return math.max(0, tr.roadReached(s.trophies) - (s.road or 0))
end

-- Coins on a sign: 2,000 / 12.5K (TrophyRoadScene.tsx signTex).
local function short(n: number): string
	if n >= 10000 then
		local k = n / 1000
		return if n % 1000 == 0 then `{k}K` else `{string.format("%.1f", k)}K`
	end
	return Ui.commas(n)
end

function TrophyRoad.draw(page: Frame, ctx: any, api: any)
	local s = store.useGame.getState()
	local trophies: number = s.trophies or 0
	local claimed: number = s.road or 0
	local reached: number = tr.roadReached(trophies)
	local toNext = tr.roadTrophies(reached) - trophies
	local from = math.max(0, math.min(claimed, reached) - BEHIND)
	local function xOf(u: number): number
		return FIRST + (u - from) * GAP
	end
	local finish = xOf(from + SHOWN - 1)
	local carX = math.max(40, math.min(finish, xOf(trophies / tr.ROAD_STEP - 1)))

	-- ── The head: trophies, the bar to the next stop, the next prize, and Claim (.tr-head) ──
	local head = Ui.new("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = page })
	local countText = `🏆 {Ui.commas(trophies)}`
	local cw = math.ceil(Ui.textWidth(countText, 26)) + 10
	Ui.text({ Name = "Count", Text = countText, TextSize = 26, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0, cw, 1, 0), Parent = head })
	local due = ready(s)
	local claimW = if due > 0 then 150 else 0
	local nextPay = tr.roadPay(reached)
	local gift = tr.roadMystery(reached)
	local nextText = if gift then "🎁" else Ui.commas(nextPay.coins)
	local nw = if gift then 50 else math.ceil(Ui.textWidth(nextText, 16)) + 50
	local nextPill = Ui.new("Frame", { Name = "Next", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -(claimW + (if claimW > 0 then 10 else 0)), 0.5, 0), Size = UDim2.fromOffset(nw, 30), BackgroundColor3 = Ui.WHITE, Parent = head }, { Ui.round(), Ui.stroke(3, Ui.LINE) })
	if gift then
		Ui.text({ Text = "🎁", TextSize = 18, Size = UDim2.fromScale(1, 1), Parent = nextPill })
	else
		Icons.draw("coin", nextPill, 20, nil, nil, UDim2.new(0, 10, 0.5, 0), Vector2.new(0, 0.5))
		Ui.text({ Text = nextText, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.LINE, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -38, 1, 0), Parent = nextPill })
	end
	local bar = Ui.new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, cw + 10, 0.5, 0), Size = UDim2.new(1, -(cw + 10) - nw - 10 - claimW - (if claimW > 0 then 10 else 0), 0, 26), BackgroundColor3 = Color3.fromHex("#dfe7f2"), ClipsDescendants = true, Parent = head }, { Ui.round(), Ui.stroke(3, Ui.LINE) })
	Ui.new("Frame", { Name = "Fill", Size = UDim2.fromScale((trophies % tr.ROAD_STEP) / tr.ROAD_STEP, 1), BackgroundColor3 = Color3.fromHex("#ffb300"), BorderSizePixel = 0, Parent = bar }, { Ui.round() })
	Ui.text({ Text = `{toNext} to go`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.LINE, Size = UDim2.fromScale(1, 1), Parent = bar })
	if due > 0 then
		Ui.buy({ Name = "Claim", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(claimW, 36), Parent = head }, `🎁 Claim {due}`, "green", function()
			if Remote.act("claimRoad") then
				api.show("road")
			end
		end, 16)
	end

	-- ── The road (.tr-scene) ──────────────────────────────────────────────────────────────────
	local CHIPS_H = 56
	local frame = Ui.new("Frame", { Name = "Scene", Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44 - CHIPS_H - 6), BackgroundColor3 = Color3.fromHex("#9cc7e8"), ClipsDescendants = true, Parent = page }, { Ui.corner(16), Ui.stroke(3, Ui.LINE) })
	local road = Ui.scroller({ Name = "Road", Size = UDim2.fromScale(1, 1), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.None, CanvasSize = UDim2.fromOffset(finish + FIRST, 0), ScrollBarThickness = 0, Parent = frame })
	local width = finish + FIRST
	-- The scenery runs on past the end, so a wide view never shows the edge.
	local ground = width + 1200
	local sky = Ui.new("Frame", { Name = "Sky", BorderSizePixel = 0, Size = UDim2.new(0, ground, 0.66, 0), BackgroundColor3 = Ui.WHITE, Parent = road })
	Ui.gradient("#8ec9ff", "#e6f4ff").Parent = sky
	-- Grass on the far side, then the strip, its white edges and the dashes down the middle.
	Ui.new("Frame", { Name = "Grass", BorderSizePixel = 0, Position = UDim2.fromScale(0, 0.6), Size = UDim2.new(0, ground, 0.08, 0), BackgroundColor3 = Color3.fromHex("#6fbf5a"), Parent = road })
	local strip = Ui.new("Frame", { Name = "Strip", BorderSizePixel = 0, Position = UDim2.fromScale(0, 0.66), Size = UDim2.new(0, ground, 0.34, 0), BackgroundColor3 = Ui.WHITE, Parent = road })
	Ui.gradient("#6b7480", "#454c57").Parent = strip
	Ui.new("Frame", { BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = Color3.fromHex("#f5f5f5"), Parent = strip })
	Ui.new("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = Color3.fromHex("#f5f5f5"), Parent = strip })
	for x = 20, ground, 60 do
		Ui.new("Frame", { BorderSizePixel = 0, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, x, 0.5, 0), Size = UDim2.fromOffset(30, 4), BackgroundColor3 = Color3.fromHex("#ffd54f"), Parent = strip })
	end
	-- The start line, when the road shown starts at the start.
	for i = 0, if from == 0 then 5 else -1 do
		Ui.new("Frame", { BorderSizePixel = 0, Position = UDim2.new(0, 30 + (i % 2) * 6, i / 6, 0), Size = UDim2.new(0, 6, 1 / 6, 0), BackgroundColor3 = Ui.WHITE, Parent = strip })
		Ui.new("Frame", { BorderSizePixel = 0, Position = UDim2.new(0, 36 - (i % 2) * 6, i / 6, 0), Size = UDim2.new(0, 6, 1 / 6, 0), BackgroundColor3 = Ui.BLACK, Parent = strip })
	end

	-- A sign on a post at each stop: the trophies big, the coins and parts under them, and a tick
	-- or a lock in the corner (TrophyRoadScene.tsx signTex, Gantry).
	type Stop = { trophies: number, coins: number, parts: number, state: string, gift: boolean }
	local stops: { Stop } = {}
	for k = 0, SHOWN - 1 do
		local i = from + k
		local pay = tr.roadPay(i)
		local state = if i < claimed then "got" elseif i < reached then "ready" else "locked"
		local st: Stop = { trophies = tr.roadTrophies(i), coins = pay.coins, parts = pay.parts, state = state, gift = tr.roadMystery(i) and i >= claimed }
		table.insert(stops, st)
		local x = xOf(i)
		local g = Ui.new("Frame", { Name = `Stop{st.trophies}`, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0, x, 0, 0), Size = UDim2.new(0, SIGN_W, 0.7, 0), BackgroundTransparency = 1, Parent = road })
		Ui.new("Frame", { Name = "Post", BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40 + SIGN_H), Size = UDim2.new(0, 8, 1, -(40 + SIGN_H)), BackgroundColor3 = Color3.fromHex(POST[state]), Parent = g }, { Ui.stroke(1.5, Ui.LINE) })
		local sign = Ui.new("Frame", { Name = "Sign", Position = UDim2.fromOffset(0, 40), Size = UDim2.fromOffset(SIGN_W, SIGN_H), BackgroundColor3 = Color3.fromHex(BG[state]), Parent = g }, { Ui.corner(12), Ui.stroke(4, Ui.LINE) })
		local ink = Color3.fromHex(INK[state])
		Ui.text({ Text = tostring(st.trophies), TextSize = 34, TextColor3 = ink, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 40), Parent = sign })
		local line = `{short(st.coins)}  ⚙{st.parts}`
		local lw = math.ceil(Ui.textWidth(line, 17)) + 22
		local row = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), Size = UDim2.fromOffset(lw, 22), BackgroundTransparency = 1, Parent = sign })
		Icons.draw("coin", row, 18, nil, nil, UDim2.new(0, 0, 0.5, 0), Vector2.new(0, 0.5))
		Ui.text({ Text = line, TextSize = 17, TextColor3 = ink, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(22, 0), Size = UDim2.new(1, -22, 1, 0), Parent = row })
		if state ~= "ready" then
			local badge = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = if state == "got" then Color3.fromHex("#45b649") else Ui.WHITE, Parent = sign }, { Ui.round(), Ui.stroke(3, Ui.LINE) })
			Ui.text({ Text = if state == "got" then "✔" else "🔒", TextSize = 14, TextColor3 = if state == "got" then Ui.WHITE else Ui.LINE, Size = UDim2.fromScale(1, 1), Parent = badge })
		end
		if st.gift then
			Ui.text({ Name = "Gift", Text = "🎁", TextSize = 32, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(40, 38), Parent = g })
		end
	end

	-- Your race car on the road at your trophy count.
	local car = api.myCar()
	if car then
		local pic = Thumb.new("Cars", car.model, UDim2.fromOffset(150, 84), Color3.fromHex(car.color))
		pic.Name = "Car"
		pic.AnchorPoint = Vector2.new(0.5, 1)
		pic.Position = UDim2.new(0, carX, 0.97, 0)
		pic.ZIndex = 3
		pic.Parent = road
	end

	-- ── The stops in a row, tap one to look at it (.tr-chips) ─────────────────────────────────
	local chips = Ui.scroller({ Name = "Chips", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, CHIPS_H), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 0, Parent = page })
	Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = chips })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 3), Parent = chips })
	local rings: { UIStroke } = {}
	local function viewWidth(): number
		local w = road.AbsoluteSize.X
		return if w > 0 then w else 800
	end
	local function look(k: number)
		road.CanvasPosition = Vector2.new(math.clamp(xOf(from + k) - viewWidth() / 2, 0, math.max(0, width - viewWidth())), 0)
		for j, ring in rings do
			ring.Color = if j - 1 == k then Color3.fromHex("#2f7ff0") else Ui.LINE
			ring.Thickness = if j - 1 == k then 4 else 3
		end
	end
	for k, st in stops do
		local text = `{if st.gift then "🎁 " else ""}{st.trophies}`
		local w = math.max(58, math.ceil(Ui.textWidth(text, 18)) + 22)
		local ring = Ui.stroke(3, Ui.LINE)
		local b = Ui.new("TextButton", { Name = `Chip{st.trophies}`, Text = "", AutoButtonColor = false, LayoutOrder = k, Size = UDim2.fromOffset(w, 46), BackgroundColor3 = Color3.fromHex(BG[st.state]), Parent = chips }, { Ui.corner(12), ring })
		table.insert(rings, ring)
		Ui.text({ Text = text, TextSize = 18, TextColor3 = Color3.fromHex(if st.state == "got" then "#ffffff" elseif st.state == "ready" then "#14213d" else "#4a6283"), Size = UDim2.fromScale(1, 1), Parent = b })
		b.Activated:Connect(function()
			look(k - 1)
		end)
	end
	-- Start on the car, its nearest stop picked.
	local near = math.clamp(math.floor((carX - FIRST) / GAP + 0.5), 0, SHOWN - 1)
	road.CanvasPosition = Vector2.new(math.clamp(carX - viewWidth() / 2, 0, math.max(0, width - viewWidth())), 0)
	for j, ring in rings do
		if j - 1 == near then
			ring.Color = Color3.fromHex("#2f7ff0")
			ring.Thickness = 4
		end
	end
	local _ = ctx
end

return TrophyRoad
