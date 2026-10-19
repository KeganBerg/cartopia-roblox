--!strict
-- The first ten minutes, as the web game's Tutorial and TutHand (ui/Tutorial.tsx, ui/TutHand.tsx):
-- a navy card over the bottom bar with the step's one line (and Next or Skip), and a big pointing
-- finger with a gold ring on whatever to tap next: a pizza bubble, a HUD button, a card in a menu,
-- the glowing lot for Rusty's, a menu's X when a new player wanders off, the race pedal. Left
-- alone for a while, the screen dims around that tap. Taps go straight through.
--
-- The rules (steps, what each waits for, the unlocks) are in shared/Tutorial. The step moves on
-- with setTutorial, which the server only accepts once the step is done. Buttons the hand can
-- point at carry a `Tut` attribute naming them (set where each button is made).
--
-- Each step's spoken line plays through Sounds/Voice (Voice.forStep picks it, as the web's
-- voiceLine does), and a step that moves on by itself gives the little step sound (Sfx.step).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local Rules = require(Shared:WaitForChild("Tutorial")) :: any
local Client = script.Parent.Parent
local Remote = require(Client.Remote)
local Ui = require(Client.Ui)
local Placement = require(Client.Placement)
local TownCamera = require(Client.TownCamera)
local Kit = require(script.Parent.Kit)
local Voice = require(Client.Sounds.Voice)
local Sfx = require(Client.Sounds.Sfx)

local Tutorial = {}

local IDLE = 6 -- seconds left alone before the screen dims around the next tap
local CARD_W = 440
local PAD = 6 -- the ring's gap round its target

local TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

local lineNow: string? = nil -- the spoken line playing now (Sounds/Voice)

-- ── Where things are on screen (the emulator swaps these for its own layout) ───────────────────

-- A world point to viewport pixels (the whole screen, top bar included), and whether it's in front.
function Tutorial.project(p: Vector3): (Vector2, boolean)
	local cam = workspace.CurrentCamera
	local v, onScreen = cam:WorldToViewportPoint(p)
	return Vector2.new(v.X, v.Y), onScreen and v.Z > 0
end

local function scaleOf(layer: GuiObject): number
	local s = layer:FindFirstChildOfClass("UIScale")
	return if s then s.Scale else 1
end

-- A button's box in the layer's own units (the HUD's 1280x800 frame, scaled to the screen):
-- x, y, w, h. Buttons in a BillboardGui (job bubbles) are placed from their spot in the world.
function Tutorial.rectOf(g: GuiObject, layer: GuiObject): (number, number, number, number)
	local s = scaleOf(layer)
	local board = g:FindFirstAncestorOfClass("BillboardGui")
	if board then
		local a = board.Adornee
		local at = if a and a:IsA("BasePart") then a.CFrame.Position elseif a and a:IsA("Model") then a:GetPivot().Position else Vector3.zero
		local v = Tutorial.project(at + board.StudsOffsetWorldSpace)
		-- The bubble's own width (the first size along the way with one), the board's height.
		local w = 0
		local p: Instance? = g
		while p and p ~= board do
			if p:IsA("GuiObject") and p.Size.X.Offset > 0 then
				w = p.Size.X.Offset
				break
			end
			p = p.Parent
		end
		local bh = board.Size.Y.Offset
		w = if w > 0 then w else board.Size.X.Offset
		return v.X / s - w / 2, v.Y / s - bh / 2, w, bh
	end
	local o = layer.AbsolutePosition
	return (g.AbsolutePosition.X - o.X) / s, (g.AbsolutePosition.Y - o.Y) / s, g.AbsoluteSize.X / s, g.AbsoluteSize.Y / s
end

-- Shown: itself and everything it sits in visible, its ScreenGui or BillboardGui on.
local function shown(g: Instance): boolean
	local p: Instance? = g
	while p do
		if p:IsA("GuiObject") and not p.Visible then
			return false
		end
		if p:IsA("LayerCollector") then
			return (p :: any).Enabled
		end
		p = p.Parent
	end
	return false
end

-- ── What to point at (TutHand's handTarget) ────────────────────────────────────────────────────
local ctxRef: any = nil
local paint: string? = nil
local rim: string? = nil

local function raceScreen(): Frame?
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local g = pg and pg:FindFirstChild("Race")
	return g and g:FindFirstChild("RaceScreen") :: Frame?
end

-- The menu up now, by the web's panel name (the race screen counts as the race menu).
local function panelNow(): string?
	if raceScreen() then
		return "race"
	end
	return if ctxRef then ctxRef.panel() else nil
end

local function editing(): boolean
	return Placement.active()
end

local function popupUp(): boolean
	return ctxRef ~= nil and ctxRef.gui:FindFirstChild("Popup") ~= nil
end

-- The names to look for, first found wins; "lot" for the see-through Rusty's; nil to rest.
function Tutorial.target(s: any): { string } | string | nil
	local st = Rules.step(s)
	if not st or s.visiting or s.levelUp or popupUp() then
		return nil
	end
	local step = s.tutorial
	local panel = panelNow()
	if panel then
		if not Rules.inStepPanel(panel, step) then
			return { "close" }
		end
		if panel == "shop" then
			return { "start-here" }
		end
		-- The race menu: the first campaign race. In the race: the pedal on the line, then SHIFT
		-- each time its light says now (the hand comes and goes with it).
		if panel == "race" then
			return { "camp-go", "launch", "shift-now" }
		end
		-- At a lot: Search all finds the car for sure, then tow it home.
		if Remote.search then
			return { "rs-auto", "rs-home-ready" }
		end
		if step == 4 then
			-- (Rusty's remembers its last tab: from My lot, the Find cars tab first.)
			return { "rsc-spot", "find-tab" }
		end
		-- Fix up the find: the lot's Restore, a car on the lot, the haul's button, the lot's tab.
		return { "junk-go", "lot-spot", "haul-fix", "lot-tab" }
	end
	local mode, placing = Placement.mode()
	if mode == "place" then
		return if step == 3 and placing == "rescue" then "lot" else { "edit-done" }
	elseif mode then
		return { "edit-done" }
	end
	local t = st.target and st.target(s, false)
	if t == "pizza" then
		return { if step == 1 then "pizza-idle" else "pizza-ready" }
	elseif t == "shop" or t == "race" or t == "rescue" then
		return { t }
	elseif t == "done" then
		return { "edit-done" }
	end
	-- The paint pick: a colour in each row still unpicked, then Done. Other steps: Next.
	if st.pick and raceCar.raceCarOf(s.cars, s.raceCar) then
		if not paint then
			return { "tut-paint" }
		elseif not rim then
			return { "tut-rim" }
		end
		return { "tut-done" }
	end
	return if st.done then nil else { "tut-next" }
end

-- The button for a name: the one on screen nearest the middle (pizza bubbles), as the web's find.
-- Also says where in the world the nearest bubble is when none is on screen, so the view can go there.
local function find(names: { string }, layer: GuiObject): (GuiObject?, Vector3?)
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return nil, nil
	end
	-- The layer is sized in its own units (the HUD's fit sets it), so its size is its offsets.
	local lw, lh = layer.Size.X.Offset, layer.Size.Y.Offset
	local offAt: Vector3? = nil
	for _, name in names do
		local best: GuiObject? = nil
		local bestD = math.huge
		for _, d in pg:GetDescendants() do
			if d:GetAttribute("Tut") ~= name or not d:IsA("GuiObject") or not shown(d) then
				continue
			end
			local x, y, w, h = Tutorial.rectOf(d, layer)
			if w <= 0 or h <= 0 then
				continue
			end
			local cx, cy = x + w / 2, y + h / 2
			local dist = (cx - lw / 2) ^ 2 + (cy - lh / 2) ^ 2
			local inView = x + w > 0 and y + h > 0 and x < lw and y < lh
			if not inView then
				local board = d:FindFirstAncestorOfClass("BillboardGui")
				local a = board and board.Adornee
				if a and not offAt then
					offAt = if a:IsA("BasePart") then a.CFrame.Position elseif a:IsA("Model") then a:GetPivot().Position else nil
				end
				continue
			end
			if dist < bestD then
				best, bestD = d, dist
			end
		end
		if best then
			return best, nil
		end
	end
	return nil, offAt
end

-- The target's box in the layer, or nil (with a world spot to bring into view, if off screen).
function Tutorial.box(s: any, layer: GuiObject): ({ x: number, y: number, w: number, h: number }?, GuiObject?, Vector3?)
	local t = Tutorial.target(s)
	if t == nil then
		return nil, nil, nil
	end
	if t == "lot" then
		local p = Placement.tutorialLot()
		if not p then
			return nil, nil, nil
		end
		local v, front = Tutorial.project(p)
		if not front then
			return nil, nil, p
		end
		local sc = scaleOf(layer)
		return { x = v.X / sc - 36, y = v.Y / sc - 28, w = 72, h = 56 }, nil, p
	end
	local el, off = find(t :: { string }, layer)
	if not el then
		return nil, nil, off
	end
	local x, y, w, h = Tutorial.rectOf(el, layer)
	return { x = x, y = y, w = w, h = h }, el, nil
end

-- The button to press for the target (the emulator walks the tutorial with it): the GuiButton
-- itself or the first one in it; for the lot, the screen point to tap.
function Tutorial.press(s: any, layer: GuiObject): (GuiButton?, Vector2?)
	local box, el = Tutorial.box(s, layer)
	if not box then
		return nil, nil
	end
	if not el then
		local sc = scaleOf(layer)
		return nil, Vector2.new((box.x + box.w / 2) * sc, (box.y + box.h / 2) * sc)
	end
	if el:IsA("GuiButton") then
		return el, nil
	end
	return el:FindFirstChildWhichIsA("GuiButton", true), nil
end

-- The line to say now: the step's, while the town or the step's own menu shows; none in any other
-- menu, on a visit or over a level-up.
local function voiceLine(s: any): string?
	local st = Rules.step(s)
	if not st or s.visiting or s.levelUp then
		return nil
	end
	local panel = panelNow()
	if panel and not Rules.inStepPanel(panel, s.tutorial) then
		return nil
	end
	local mode = Placement.mode()
	return Voice.forStep(s.tutorial + 1, { placing = mode == "place", touch = TOUCH, editing = editing() })
end

-- ── The card ───────────────────────────────────────────────────────────────────────────────────

local NAVY = { "#2a4370", "#1c2e52" }

local function chip(parent: Instance, order: number, text: string)
	local w = math.ceil(Ui.textWidth(text, 13)) + 14
	local f = Ui.new("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(w, 20), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.88, Parent = parent }, { Ui.corner(8) })
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 13, Size = UDim2.fromScale(1, 1), Parent = f })
end

-- Builds the card for the step; returns it (or nil when nothing shows).
local function drawCard(root: GuiObject, s: any, redraw: () -> ()): Frame?
	local st = Rules.step(s)
	if not st then
		return nil
	end
	local step = s.tutorial
	local car = if st.pick then raceCar.raceCarOf(s.cars, s.raceCar) else nil
	local pick = st.pick and car ~= nil
	local text = st.text(s, editing(), TOUCH)
	-- Sizes, worked out rather than left to AutomaticSize (see Ui's note on flex rows).
	local leftW = if pick then 104 else 40
	local actW = 74
	local textW = CARD_W - 20 - 6 - leftW - actW - 20
	local lines = math.max(1, math.ceil(Ui.textWidth(text, 16) / textW))
	local textH = lines * 21
	local bodyH = textH + 5 + (if st.gas then 25 else 0) + (if pick then 2 * 29 else 0) + 6
	local h = math.max(if pick then 76 else 40, bodyH) + 16 + 6
	local bottom = if editing() then 150 else 96

	local shadow, face = Ui.shadowed({ Name = "Tutorial", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -bottom), Size = UDim2.fromOffset(CARD_W, h), ZIndex = 15, Parent = root }, {
		radius = 16,
		stroke = 3,
		drop = 5,
		dark = 0.3,
		colors = "navy",
	})
	for _, d in shadow:GetDescendants() do
		if d:IsA("UIGradient") then
			d.Color = Ui.seq(NAVY[1], NAVY[2])
		end
	end
	local zi = 15
	local function z(g: Instance)
		for _, d in g:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = zi
			end
		end
		if g:IsA("GuiObject") then
			g.ZIndex = zi
		end
	end
	local inner = h - 6
	if pick and car then
		local well = Ui.new("Frame", { Name = "Car", Position = UDim2.fromOffset(10, (inner - 76) / 2), Size = UDim2.fromOffset(104, 76), BackgroundColor3 = Color3.fromHex("#eef2f4"), Parent = face }, { Ui.corner(10) })
		local panels = if rim then { rims = { color = rim } } else nil
		local thumb = Kit.carThumb(car.model, UDim2.fromScale(1, 1), paint or car.color, car, { panels = panels })
		thumb.Parent = well
	else
		local icon = Ui.new("Frame", { Name = "Icon", Position = UDim2.fromOffset(10, (inner - 40) / 2), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Ui.WHITE, Parent = face }, {
			Ui.round(),
			Ui.gradient("#ffe082", "#ffb300"),
			Ui.stroke(2, Ui.LINE, 0.6),
		})
		Ui.text({ Text = st.icon, TextSize = 22, Size = UDim2.fromScale(1, 1), Parent = icon })
	end
	local x0 = 10 + leftW + 10
	local body = Ui.new("Frame", { Name = "Body", Position = UDim2.fromOffset(x0, (inner - bodyH) / 2), Size = UDim2.fromOffset(textW, bodyH), BackgroundTransparency = 1, Parent = face })
	Ui.text({ Name = "Line", Text = text, Body = true, Weight = "heavy", TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Size = UDim2.fromOffset(textW, textH), Parent = body })
	local y = textH + 5
	if st.gas then
		local row = Ui.new("Frame", { Name = "Gas", Position = UDim2.fromOffset(0, y), Size = UDim2.fromOffset(textW, 20), BackgroundTransparency = 1, Parent = body }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local cap = store.fuelCap(s)
		chip(row, 1, `🏁 −{data.RACE_FUEL}⛽`)
		chip(row, 2, `⏱ +{data.fuelPerMin(s.level)}⛽/m`)
		chip(row, 3, `⛽ {math.floor(s.fuel)}/{cap}`)
		chip(row, 4, `⛽🏪 +{data.upgradeFuelCap(data.buildingDef("gas"), 1)}`)
		y += 25
	end
	if pick then
		for i, row in { { icon = "🎨", name = "Paint", tut = "tut-paint", get = function() return paint end, set = function(c) paint = c end }, { icon = "🛞", name = "Rims", tut = "tut-rim", get = function() return rim end, set = function(c) rim = c end } } do
			local r = Ui.new("Frame", { Name = row.name, Position = UDim2.fromOffset(0, y + (i - 1) * 29), Size = UDim2.fromOffset(textW, 24), BackgroundTransparency = 1, Parent = body }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			Ui.text({ Text = row.icon, TextSize = 16, Size = UDim2.fromOffset(20, 24), LayoutOrder = 0, Parent = r })
			for j, c in Rules.STARTER_PAINTS do
				local sel = row.get() == c
				local dot = Ui.new("TextButton", { Name = c, Text = "", AutoButtonColor = false, LayoutOrder = j, Size = UDim2.fromOffset(24, 24), BackgroundColor3 = Color3.fromHex(c), Parent = r }, {
					Ui.round(),
					Ui.stroke(if sel then 3 else 2, if sel then Color3.fromHex("#ffca28") else Ui.WHITE),
				})
				-- The hand points at the third dot of a row still to pick, as the web.
				if j == 3 and row.get() == nil then
					dot:SetAttribute("Tut", row.tut)
				end
				dot.Activated:Connect(function()
					row.set(c)
					redraw()
				end)
			end
		end
	end
	-- The step dots: done ones gold, this one a long gold dash.
	local dots = Ui.new("Frame", { Name = "Dots", Position = UDim2.fromOffset(0, bodyH - 6), Size = UDim2.fromOffset(textW, 6), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i = 0, Rules.STEPS - 1 do
		Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(if i == step then 16 else 6, 6), BackgroundColor3 = if i <= step then Color3.fromHex("#ffca28") else Ui.WHITE, BackgroundTransparency = if i <= step then 0 else 0.7, BorderSizePixel = 0, Parent = dots }, { Ui.corner(3) })
	end
	-- Next (or Done for the pick), and Skip under it.
	local acts = Ui.new("Frame", { Name = "Actions", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0, inner / 2), Size = UDim2.fromOffset(actW, 54), BackgroundTransparency = 1, Parent = face })
	local function act(name: string, ...: any): boolean
		local ok = Remote.act(name, ...)
		return ok
	end
	if pick and car then
		local ready = paint ~= nil and rim ~= nil
		local _, done = Ui.buy({ Name = "Done", Size = UDim2.fromOffset(actW, 30), Parent = acts }, "Done", if ready then "green" else "grey", function()
			if paint and rim and act("tutorialStyle", car.uid, paint, rim) then
				act("setTutorial", step + 1)
			end
		end, 15)
		if ready then
			done:SetAttribute("Tut", "tut-done")
		end
	elseif not st.done then
		local _, nextB = Ui.buy({ Name = "Next", Size = UDim2.fromOffset(actW, 30), Parent = acts }, "Next", "green", function()
			act("setTutorial", step + 1)
		end, 15)
		nextB:SetAttribute("Tut", "tut-next")
	end
	local skip = Ui.new("TextButton", { Name = "Skip", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(actW, 20), Parent = acts })
	Ui.text({ Text = "Skip", Body = true, Weight = "heavy", TextSize = 12, TextColor3 = Color3.fromHex("#b0bec5"), Size = UDim2.fromScale(1, 1), Parent = skip })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromOffset(26, 1), BackgroundColor3 = Color3.fromHex("#b0bec5"), BorderSizePixel = 0, Parent = skip })
	skip.Activated:Connect(function()
		act("skipTutorial", Rules.PICK_STEP)
	end)
	z(shadow)
	return shadow
end

-- ── The hand and ring ──────────────────────────────────────────────────────────────────────────

local function makeHand(): (Frame, Frame, TextLabel, { Frame })
	local ring = Ui.new("Frame", { Name = "TutRing", BackgroundTransparency = 1, Visible = false, ZIndex = 60 }, {
		Ui.corner(16),
		Ui.new("UIStroke", { Thickness = 4, Color = Color3.fromHex("#ffca28") }),
	})
	-- The dim round the target: four panes, so the ring's middle stays clear.
	local panes = {}
	for i = 1, 4 do
		panes[i] = Ui.new("Frame", { Name = `Dim{i}`, BackgroundColor3 = Color3.fromHex("#081020"), BackgroundTransparency = 0.45, BorderSizePixel = 0, Visible = false, ZIndex = 59 })
	end
	local hand = Ui.new("Frame", { Name = "TutHand", BackgroundTransparency = 1, Size = UDim2.fromOffset(56, 56), Visible = false, ZIndex = 61 })
	local finger = Ui.text({ Text = "👆", TextSize = 46, Size = UDim2.fromScale(1, 1), ZIndex = 61, Parent = hand })
	return ring, hand, finger, panes
end

-- ── Running it ─────────────────────────────────────────────────────────────────────────────────

-- The layer the hand draws in: the race screen while a race is on, else the HUD's frame.
-- Rusty's 3D search has its own screen over the lot (the HUD is off while it's up).
local function rescueScreen(): Frame?
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local g = pg and pg:FindFirstChild("RescueSearch")
	return g and g:FindFirstChild("SearchScreen") :: Frame?
end

local function layerNow(): GuiObject?
	return raceScreen() or rescueScreen() or (if ctxRef then ctxRef.gui else nil)
end

local card: Frame? = nil
local cardKey = ""
local lastSent = -1
local glided = ""
local lastInput = os.clock()
local targetKey = ""

function Tutorial.start(ctx: any)
	ctxRef = ctx
	local root: GuiObject = ctx.gui
	local ring, hand, finger, panes = makeHand()

	local function redraw()
		cardKey = ""
		Tutorial.refresh()
	end

	-- Steps that wait on an action move on as soon as it's done (the server checks it again).
	local function advance()
		local s = store.useGame.getState()
		local st = Rules.step(s)
		if not st or not st.done or lastSent == s.tutorial then
			return
		end
		if st.done(s, Remote.search) then
			lastSent = s.tutorial
			task.spawn(function()
				local ok = Remote.act("setTutorial", s.tutorial + 1)
				if not ok then
					lastSent = -1
				else
					-- A little nod once the action's own sound has played.
					task.delay(0.25, Sfx.step)
				end
			end)
		end
	end

	function Tutorial.refresh()
		local s = store.useGame.getState()
		if s.level == nil then
			return
		end
		-- The card: hidden behind menus (they carry their own pointers) and on visits.
		local st = Rules.step(s)
		local hidden = st == nil or ctx.panel() ~= nil or raceScreen() ~= nil or s.visiting
		if st == nil or not st.pick then
			paint, rim = nil, nil
		end
		local key = if hidden then "" else table.concat({ tostring(s.tutorial), st.text(s, editing(), TOUCH), tostring(paint), tostring(rim), tostring(editing()), if st.gas then `{math.floor(s.fuel)}` else "", tostring(raceCar.raceCarOf(s.cars, s.raceCar) ~= nil) }, "|")
		if key ~= cardKey then
			cardKey = key
			if card then
				card:Destroy()
				card = nil
			end
			if not hidden then
				card = drawCard(root, s, redraw)
			end
		end
		-- The line to say.
		local l = voiceLine(s)
		if l ~= lineNow then
			lineNow = l
			if l then
				Voice.say(l)
			else
				Voice.stop()
			end
		end
		advance()
	end

	-- Every frame: the hand follows its target (bubbles move with the camera).
	local function frame()
		local s = store.useGame.getState()
		local layer = layerNow()
		if s.level == nil or (s.tutorial or 99) >= 99 or s.visiting or not layer then
			ring.Visible, hand.Visible = false, false
			for _, p in panes do
				p.Visible = false
			end
			return
		end
		for _, g in { ring, hand, panes[1], panes[2], panes[3], panes[4] } do
			if g.Parent ~= layer then
				g.Parent = layer
			end
		end
		local t = Tutorial.target(s)
		local k = if t == nil then "" elseif type(t) == "string" then t else table.concat(t :: { string }, "|")
		-- A new step (or menu) restarts the idle clock, so the dim never lands the moment it appears.
		if k ~= targetKey then
			targetKey = k
			lastInput = os.clock()
		end
		local box, el, off = Tutorial.box(s, layer)
		-- Each step that points into the town brings its spot on screen (scene/TutorialCamera.tsx).
		local glideKey = `{s.tutorial}:{k}`
		if off and glided ~= glideKey and not ctx.panel() then
			glided = glideKey
			TownCamera.lookAt(off)
		end
		if not box then
			ring.Visible, hand.Visible = false, false
			for _, p in panes do
				p.Visible = false
			end
			return
		end
		local lw, lh = layer.Size.X.Offset, layer.Size.Y.Offset
		-- Point up from below, or down from above when the target sits low on the screen. On the
		-- card's own Next the hand comes from above: from below it sat right on Skip.
		local onCard = el ~= nil and card ~= nil and el:IsDescendantOf(card)
		local below = not onCard and box.y + box.h + 80 < lh
		local cx = box.x + box.w / 2
		local bob = math.abs(math.sin(os.clock() * math.pi)) * 10
		if below then
			local tip = box.y + box.h * 0.6
			hand.AnchorPoint = Vector2.new(0.4, 0)
			hand.Position = UDim2.fromOffset(math.round(cx), math.round(tip + 4 + bob))
			finger.Rotation = 0
		else
			local tip = box.y + box.h * 0.4
			hand.AnchorPoint = Vector2.new(0.6, 1)
			hand.Position = UDim2.fromOffset(math.round(cx), math.round(tip - 4 - bob))
			finger.Rotation = 180
		end
		ring.Position = UDim2.fromOffset(math.round(box.x - PAD), math.round(box.y - PAD))
		ring.Size = UDim2.fromOffset(math.round(box.w + PAD * 2), math.round(box.h + PAD * 2))
		local stroke = ring:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = Color3.fromHex("#ffca28"):Lerp(Color3.fromHex("#fff8e1"), (math.sin(os.clock() * math.pi * 2) + 1) / 2)
		end
		ring.Visible, hand.Visible = true, true
		-- Left alone, the rest of the screen dims around the next tap.
		local dim = os.clock() - lastInput > IDLE
		local x0, y0 = box.x - PAD, box.y - PAD
		local x1, y1 = box.x + box.w + PAD, box.y + box.h + PAD
		local rects = { { 0, 0, lw, y0 }, { 0, y1, lw, lh - y1 }, { 0, y0, x0, y1 - y0 }, { x1, y0, lw - x1, y1 - y0 } }
		for i, p in panes do
			local r = rects[i]
			p.Visible = dim and r[3] > 0 and r[4] > 0
			p.Position = UDim2.fromOffset(r[1], r[2])
			p.Size = UDim2.fromOffset(math.max(0, r[3]), math.max(0, r[4]))
		end
	end
	Tutorial.frame = frame

	UserInputService.InputBegan:Connect(function()
		lastInput = os.clock()
	end)
	Remote.changed:Connect(function()
		Tutorial.refresh()
	end)
	-- (Placement keeps a single change listener, the HUD's: the poll below picks edit mode up.)
	RunService:BindToRenderStep("Tutorial", Enum.RenderPriority.Last.Value, frame)
	Tutorial.refresh()
	task.spawn(function()
		while true do
			task.wait(0.25)
			Tutorial.refresh()
		end
	end)
end

return Tutorial
