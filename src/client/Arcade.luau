--!strict
-- The Arcade, as the web game's ArcadePanel (ui/Arcade.tsx, ArcadeMore.tsx, ArcadeBoards.tsx,
-- ArcadeBits.tsx): a tile for each of the six games with its best (or stars) and what a run costs
-- (a free play or the fuel), the car you play with, Parking Pro's lots, the weekly boards with their
-- Gold crate prizes, and the result card after a round.
--
-- Each game is a module in client/ArcadeGames (by name: Chase, Park, Pit, Wash, Delivery, Stunt)
-- returning { id, play = function(ctx) }; a game whose module isn't there yet shows as coming soon.
-- A run is started and finished on the server (server/Arcade, the Cartopia.Arcade remote), which
-- spends the fuel, checks the result and works out the pay. The hub hides the town's HUD while a
-- game runs and shows the result card when it's done; the game draws its own screen, title bar and
-- countdown on ctx.gui and takes the camera itself.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local arcade = require(Game.arcade) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)

local Arcade = {}

-- The tiles, in the web's order (Arcade.tsx, then ArcadeMore.tsx STAR_GAMES), with each tile's
-- colours (index.css .arc-tile.<id>: a 160° gradient) and its game module's name.
export type GameInfo = { id: string, name: string, art: string, tip: string, colors: { string }, module: string, icon: string }
Arcade.GAMES = {
	{ id = "chase", name = "Getaway Chase", art = "🚓💨🚗", tip = "Near misses, nitro, lose the cop", colors = { "#3949ab", "#c62828" }, module = "Chase", icon = "🚓" },
	{ id = "park", name = "Parking Pro", art = "🅿️🚙", tip = "Steer into the spot", colors = { "#00897b", "#1e5fbf" }, module = "Park", icon = "🅿️" },
	{ id = "pit", name = "Pit Stop", art = "🔧🏎️", tip = "Brake, remember, go", colors = { "#c62828", "#37474f" }, module = "Pit", icon = "🔧" },
	{ id = "wash", name = "Car Wash", art = "🧽🫧", tip = "Wash the whole line", colors = { "#29b6f6", "#3949ab" }, module = "Wash", icon = "🧽" },
	{ id = "delivery", name = "Delivery Dash", art = "🍕🚗", tip = "Hot pizza, dodge traffic", colors = { "#fb8c00", "#c62828" }, module = "Delivery", icon = "🍕" },
	{ id = "stunt", name = "Stunt Ramp", art = "🔥🚙", tip = "Flip, roll, hit the target", colors = { "#6a1b9a", "#ef6c00" }, module = "Stunt", icon = "🔥" },
} :: { GameInfo }
local BY_ID: { [string]: GameInfo } = {}
for _, g in Arcade.GAMES do
	BY_ID[g.id] = g
end
-- The weekly boards' tabs (lib/arcadeBoard.ts BOARD_GAMES, ArcadeBoards.tsx ICON).
local BOARD_GAMES = { "chase", "stunt", "delivery", "wash", "pit" }

-- Where each game builds its world: far from every town and the drag strip (x = -30000).
local ORIGINS: { [string]: Vector3 } = {
	chase = Vector3.new(30000, 0, -30000),
	park = Vector3.new(30000, 0, -24000),
	pit = Vector3.new(30000, 0, -18000),
	wash = Vector3.new(30000, 0, -12000),
	delivery = Vector3.new(30000, 0, -6000),
	stunt = Vector3.new(30000, 0, 0),
}
Arcade.ORIGINS = ORIGINS

local GOLD = Color3.fromHex("#ffd54f")

-- ── The server ──────────────────────────────────────────────────────────────────────────────
local remote: RemoteFunction? = nil
local WHY: { [string]: string } = {
	["slow down"] = "Slow down a little",
	["no car"] = "You need a car to play",
	["lot locked"] = "Park in the lot before first",
	["bad result"] = "That run didn't count",
	["no run to finish"] = "That run didn't count",
	["town not loaded"] = "Your town is still loading",
	["already claimed"] = "Already claimed",
}
-- Asks the server's arcade (server/Arcade). Returns ok and the answer or why.
function Arcade.call(op: string, ...: any): (boolean, any)
	if not remote then
		local folder = ReplicatedStorage:FindFirstChild("Cartopia")
		remote = folder and folder:FindFirstChild("Arcade") :: RemoteFunction?
	end
	if not remote then
		return false, "no answer"
	end
	local r = remote :: RemoteFunction
	local sent, ok, result = pcall(r.InvokeServer, r, op, ...)
	if not sent then
		warn(`[Cartopia] arcade {op}: {ok}`)
		return false, "no answer"
	end
	return ok, result
end

-- ── Little pieces ───────────────────────────────────────────────────────────────────────────
local function stars(n: number): string
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end

-- What the next run costs, for the play buttons (ArcadeBits Cost): free plays left, or the fuel.
local function cost(state: any, id: string): string
	local free = state and state.free and state.free[id] or 0
	return if free > 0 then `Free ×{free}` else `⛽{arcade.ARCADE_FUEL}`
end

-- A game's best, as the tiles show it (Arcade.tsx: 🏆 score; ★ lots; stars and the best).
local function bestText(state: any, id: string): string
	if not state then
		return ""
	end
	if id == "chase" then
		return `🏆 {Ui.commas(state.chase or 0)}`
	elseif id == "park" then
		local total = 0
		for _, n in state.park or {} do
			total += n
		end
		return `★ {total}/{#arcade.PARK_LOTS * 3}`
	end
	local b = state.stars and state.stars[id] or { stars = 0, best = 0 }
	local best = ""
	if b.best and b.best > 0 then
		best = if id == "pit"
			then ` ⏱ {b.best}s`
			elseif id == "delivery" then ` 🍕 {b.best}`
			elseif id == "stunt" then ` 🔥 {Ui.commas(b.best)}`
			else ` 🚗 {b.best}`
	end
	return stars(b.stars or 0) .. best
end

-- A board value (ArcadeBoards.tsx value).
local function boardValue(g: string, v: number): string
	if g == "pit" then
		return string.format("%.1fs", v)
	elseif g == "wash" then
		return `🚗 {v}`
	elseif g == "delivery" then
		return `🍕 {v}`
	end
	return Ui.commas(v)
end

-- A game's module, or nil while it isn't in the game yet.
function Arcade.module(id: string): any?
	local info = BY_ID[id]
	local folder = script.Parent:FindFirstChild("ArcadeGames")
	local m = info and folder and folder:FindFirstChild(info.module)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, mod = pcall(require, m)
	if not ok or type(mod) ~= "table" or type((mod :: any).play) ~= "function" then
		warn(`[Cartopia] arcade game {id}: {mod}`)
		return nil
	end
	return mod
end

local function carPi(c: any): number
	local def = data.carDef(c.model)
	return if def then data.performance(def, c.upgrades, c.mods) else 0
end

-- ── The hub ─────────────────────────────────────────────────────────────────────────────────
-- The car picked for this visit (Arcade.tsx: starts on the race car).
local pickedCar: string? = nil

local function myCar(): any?
	local s = store.useGame.getState()
	local cars = s.cars or {}
	if pickedCar then
		for _, c in cars do
			if c.uid == pickedCar then
				return c
			end
		end
	end
	return raceCar.raceCarOf(cars, s.raceCar)
end

-- A pill button (the web's .arc-weekly / .arc-claim).
local function pillButton(parent: Instance, text: string, bg: Color3, fg: Color3, size: number, props: { [string]: any }, onClick: () -> ()): TextButton
	local w = Ui.textWidth(text, size) + size * 1.8
	local shadow = Ui.new("Frame", { Size = UDim2.fromOffset(w, size * 2.2), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.8, BorderSizePixel = 0, Parent = parent }, { Ui.round() })
	for k, v in props do
		(shadow :: any)[k] = v
	end
	local face = Ui.new("TextButton", { Name = "Face", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, -3), BackgroundColor3 = bg, BorderSizePixel = 0, Parent = shadow }, { Ui.round() })
	Ui.text({ Text = text, TextSize = size, TextColor3 = fg, Size = UDim2.fromScale(1, 1), Parent = face })
	face.Activated:Connect(onClick)
	return face
end

-- Opens the Arcade panel (the 'arcade' panel). arg: { view = "lots" | "boards" } to open on a page.
function Arcade.open(ctx: any, arg: any?): Instance
	local view = if type(arg) == "table" and arg.view then arg.view else "games"
	local state: any = nil
	local prizes: { any } = {}
	local board: { [string]: any } = {}
	local boardGame = "chase"
	local overlay, sheet, body = Ui.panel(ctx.gui, "🕹️ Arcade", { wide = true, onClose = ctx.close })
	overlay.Name = "Arcade"
	local _ = sheet
	local content: Instance? = nil
	local draw: () -> ()

	local function bodyWidth(): number
		local w = body.AbsoluteSize.X
		if w > 10 then
			return w
		end
		-- Before the first layout (and in the previews): the sheet's own sizing.
		local root = ctx.gui :: Frame
		local rw = root.Size.X.Offset
		if rw <= 0 then
			rw = 1280
		end
		return math.min(860, rw - 40) - 28
	end
	-- Phone screens draw the hub bigger, as the web's phone layout does (its text keeps its size
	-- while the HUD's whole screen shrinks to fit).
	-- K undoes the HUD's shrink, so text and tiles come out at the web's CSS sizes; the web's
	-- breakpoints (.arc-games 2 columns at 560 px and under, .arc-lots 2 at 420) go by the screen's
	-- real width.
	local hudScale = (ctx.gui :: Frame):FindFirstChildOfClass("UIScale")
	local K = math.clamp(1 / (if hudScale then hudScale.Scale else 1), 1, 1.8)
	local cssWidth = (ctx.gui :: Frame).Size.X.Offset / K
	local narrow = cssWidth <= 560 or bodyWidth() < 600
	local lotsNarrow = cssWidth <= 420
	local function px(n: number): number
		return math.round(n * K)
	end

	local function refreshState()
		local ok, s = Arcade.call("state")
		if ok then
			state = s
		end
	end
	local function refreshPrizes()
		local ok, p = Arcade.call("prizes")
		prizes = {}
		if ok and type(p) == "table" then
			for _, x in p do
				if not x.claimed then
					table.insert(prizes, x)
				end
			end
		end
	end

	-- Starts a run on the server, then hands over to the game.
	local function play(id: string, lot: number?)
		Arcade.play(ctx, id, lot)
	end

	-- The car row (arc-cars): the top 12 by PI, when there's more than one.
	local function carRow(parent: Instance, y: number): number
		local s = store.useGame.getState()
		local cars = table.clone(s.cars or {})
		if #cars < 2 then
			return y
		end
		table.sort(cars, function(a, b)
			return carPi(a) > carPi(b)
		end)
		local me = myCar()
		local size = px(64)
		local row = Ui.new("ScrollingFrame", {
			Name = "Cars",
			Position = UDim2.fromOffset(0, y),
			Size = UDim2.new(1, 0, 0, size + 10),
			CanvasSize = UDim2.fromOffset(math.min(12, #cars) * (size + 10), 0),
			ScrollingDirection = Enum.ScrollingDirection.X,
			ScrollBarThickness = 0,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = parent,
		})
		for i = 1, math.min(12, #cars) do
			local c = cars[i]
			local sel = me ~= nil and c.uid == me.uid
			local b = Ui.new("TextButton", {
				Name = `Car{i}`,
				Text = "",
				AutoButtonColor = false,
				Position = UDim2.fromOffset((i - 1) * (size + 10) + 2, 2),
				Size = UDim2.fromOffset(size, size),
				BackgroundColor3 = Ui.WHITE,
				Parent = row,
			}, { Ui.corner(12), Ui.stroke(2, if sel then Color3.fromHex("#2e7d32") else Color3.fromHex("#dfe5ea")) })
			local thumb = Thumb.car(c.model, UDim2.fromScale(1, 1), Paint.jobOf(c), c.hat, c.mods, c.panels, c.trim, c.skin, c.modSkin)
			thumb.Parent = b
			b.Activated:Connect(function()
				pickedCar = c.uid
				draw()
			end)
		end
		return y + size + 14
	end

	-- A game tile (arc-tile): its colours, art, name, tip, best and play button.
	local function tile(parent: Instance, g: GameInfo, x: number, y: number, w: number, h: number)
		local shadow = Ui.new("Frame", { Name = g.id, Position = UDim2.fromOffset(x, y + 4), Size = UDim2.fromOffset(w, h), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.8, BorderSizePixel = 0, Parent = parent }, { Ui.corner(18) })
		local face = Ui.new("Frame", { Name = "Face", Position = UDim2.fromOffset(0, -4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = shadow }, {
			Ui.corner(18),
			Ui.stroke(3, Ui.WHITE),
			Ui.new("UIGradient", { Rotation = 70, Color = Ui.seq(g.colors[1], g.colors[2]) }),
		})
		local yy = px(10)
		Ui.text({ Name = "Art", Text = g.art, TextSize = px(38), Position = UDim2.fromOffset(0, yy), Size = UDim2.new(1, 0, 0, px(44)), Parent = face })
		yy += px(48)
		Ui.text({ Name = "Name", Text = g.name, TextSize = px(20), Position = UDim2.fromOffset(4, yy), Size = UDim2.new(1, -8, 0, px(24)), TextScaled = false, Shadow = 2, ShadowTransparency = 0.6, Parent = face })
		yy += px(26)
		Ui.text({ Name = "Tip", Text = g.tip, Body = true, TextSize = px(13), TextWrapped = true, TextTransparency = 0.1, Position = UDim2.fromOffset(6, yy), Size = UDim2.new(1, -12, 0, px(34)), TextYAlignment = Enum.TextYAlignment.Top, Parent = face })
		yy += px(36)
		local best = bestText(state, g.id)
		local bw = Ui.textWidth(best, px(16)) + px(24)
		local pill = Ui.new("Frame", { Name = "Best", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, yy), Size = UDim2.fromOffset(math.min(w - 12, bw), px(24)), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.75, BorderSizePixel = 0, Parent = face }, { Ui.round() })
		Ui.text({ Text = best, TextSize = px(16), Size = UDim2.fromScale(1, 1), Parent = pill })
		local mod = Arcade.module(g.id)
		local label = if not mod then "Coming soon" elseif g.id == "park" then "Pick a lot ›" else `Play · {cost(state, g.id)}`
		local bh = px(36)
		local bWidth = math.min(w - px(20), Ui.textWidth(label, px(16)) + px(30))
		local _, button = Ui.buy({ Name = "Play", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -px(12)), Size = UDim2.fromOffset(bWidth, bh), Parent = face }, label, if mod then "green" else "grey", function()
			if not mod then
				ctx.toast("Coming to Roblox soon")
				return
			end
			if g.id == "park" then
				view = "lots"
				draw()
			else
				play(g.id)
			end
		end, px(16))
		button.Name = "PlayButton"
	end

	local function gamesView(parent: Instance)
		local y = carRow(parent, 0)
		-- The weekly boards and any prizes waiting (arc-top-row).
		local top = Ui.new("Frame", { Name = "TopRow", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, px(36)), BackgroundTransparency = 1, Parent = parent }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		if #prizes > 0 then
			pillButton(top, `🎁 {#prizes} × Gold crate`, Color3.fromHex("#43a047"), Ui.WHITE, px(16), { Name = "Claim", LayoutOrder = 1 }, function()
				for _, p in prizes do
					Arcade.call("claim", p.week, p.game)
				end
				ctx.open("crates")
			end)
		end
		pillButton(top, "🏆 Weekly", GOLD, Color3.fromHex("#3e2723"), px(16), { Name = "Weekly", LayoutOrder = 2 }, function()
			view = "boards"
			draw()
		end)
		y += px(46)
		local W = bodyWidth()
		local cols = if narrow then 2 else 3
		local gap = 10
		local w = math.floor((W - gap * (cols - 1)) / cols)
		local h = px(228)
		for i, g in Arcade.GAMES do
			local c = (i - 1) % cols
			local r = (i - 1) // cols
			tile(parent, g, c * (w + gap), y + r * (h + gap), w, h)
		end
		return y + math.ceil(#Arcade.GAMES / cols) * (h + gap)
	end

	local function backButton(parent: Instance, onClick: () -> ()): number
		local b = Ui.new("TextButton", { Name = "Back", Text = "‹ Back", TextSize = px(15), FontFace = Ui.DISPLAY, TextColor3 = Color3.fromHex("#1e5fbf"), TextXAlignment = Enum.TextXAlignment.Left, BackgroundTransparency = 1, Size = UDim2.fromOffset(px(90), px(26)), Parent = parent })
		b.Activated:Connect(onClick)
		return px(32)
	end

	-- Parking Pro's lots (arc-lots): each lot opens once the one before has a star.
	local function lotsView(parent: Instance): number
		local y = backButton(parent, function()
			view = "games"
			draw()
		end)
		local W = bodyWidth()
		local cols = if lotsNarrow then 2 else 4
		local gap = 8
		local w = math.floor((W - gap * (cols - 1)) / cols)
		local h = px(86)
		local starsOf = if state then state.park or {} else {}
		for i, l in arcade.PARK_LOTS do
			local open = arcade.lotOpen(starsOf, i - 1)
			local c, r = (i - 1) % cols, (i - 1) // cols
			local b = Ui.new("TextButton", {
				Name = `Lot{i}`,
				Text = "",
				AutoButtonColor = false,
				Position = UDim2.fromOffset(c * (w + gap), y + r * (h + gap)),
				Size = UDim2.fromOffset(w, h),
				BackgroundColor3 = Ui.WHITE,
				BackgroundTransparency = if open then 0 else 0.5,
				Parent = parent,
			}, { Ui.corner(14), Ui.stroke(2, Color3.fromHex("#b2dfdb"), if open then 0 else 0.5) })
			local fade = if open then 0 else 0.5
			Ui.text({ Text = if open then tostring(i) else "🔒", TextSize = px(22), TextColor3 = Color3.fromHex("#00897b"), TextTransparency = fade, Position = UDim2.fromOffset(0, px(6)), Size = UDim2.new(1, 0, 0, px(26)), Parent = b })
			Ui.text({ Text = l.name, Body = true, Weight = "heavy", TextSize = px(12), TextColor3 = Ui.INK, TextTransparency = fade, Position = UDim2.fromOffset(2, px(34)), Size = UDim2.new(1, -4, 0, px(16)), Parent = b })
			Ui.text({ Text = stars(starsOf[i] or 0), TextSize = px(15), TextColor3 = Color3.fromHex("#f9a825"), TextTransparency = fade, Position = UDim2.fromOffset(0, px(54)), Size = UDim2.new(1, 0, 0, px(20)), Parent = b })
			b.Activated:Connect(function()
				if not open then
					return
				end
				play("park", i)
			end)
		end
		local rows = math.ceil(#arcade.PARK_LOTS / cols)
		y += rows * (h + gap) + 4
		Ui.text({ Name = "Cost", Text = `Each run {cost(state, "park")}`, TextSize = px(14), TextColor3 = Color3.fromHex("#607d8b"), Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, px(20)), Parent = parent })
		return y + px(24)
	end

	-- The weekly boards (ArcadeBoards.tsx WeeklyBoards): a tab per game, the top 20 and my place.
	local function boardsView(parent: Instance): number
		local y = backButton(parent, function()
			view = "games"
			draw()
		end)
		local W = bodyWidth()
		local tw = math.floor((W - 8 * (#BOARD_GAMES - 1)) / #BOARD_GAMES)
		for i, g in BOARD_GAMES do
			local sel = g == boardGame
			local b = Ui.new("TextButton", {
				Name = `Tab_{g}`,
				Text = BY_ID[g].icon,
				TextSize = px(24),
				FontFace = Ui.DISPLAY,
				AutoButtonColor = false,
				Position = UDim2.fromOffset((i - 1) * (tw + 8), y),
				Size = UDim2.fromOffset(tw, px(42)),
				BackgroundColor3 = if sel then Color3.fromHex("#e3f2fd") else Ui.WHITE,
				Parent = parent,
			}, { Ui.corner(12), Ui.stroke(2, if sel then Color3.fromHex("#1e88e5") else Color3.fromHex("#e0e0e0")) })
			b.Activated:Connect(function()
				boardGame = g
				draw()
			end)
		end
		y += px(52)
		local b = board[boardGame]
		if b == nil then
			local ok, got = Arcade.call("board", boardGame)
			b = if ok then got else false
			board[boardGame] = b
		end
		if not b then
			Ui.text({ Text = "Couldn't load the scores", Body = true, TextSize = px(15), TextColor3 = Color3.fromHex("#546e7a"), Position = UDim2.fromOffset(0, y + 10), Size = UDim2.new(1, 0, 0, px(24)), Parent = parent })
			return y + px(40)
		end
		if #b.top == 0 then
			Ui.text({ Name = "Empty", Text = "🏁 Be the first this week", TextSize = px(16), TextColor3 = Color3.fromHex("#546e7a"), Position = UDim2.fromOffset(0, y + 14), Size = UDim2.new(1, 0, 0, px(24)), Parent = parent })
			return y + px(52)
		end
		local me = Players.LocalPlayer and Players.LocalPlayer.UserId
		local rows: { any } = table.clone(b.top)
		local shown = false
		for _, r in rows do
			if r.owner == me then
				shown = true
			end
		end
		if b.me and not shown then
			table.insert(rows, { owner = me, town = store.useGame.getState().townName, best = b.me.best, place = b.me.place })
		end
		local rh = px(44)
		for i, r in rows do
			local mine = r.owner == me
			local row = Ui.new("Frame", {
				Name = `Row{i}`,
				Position = UDim2.fromOffset(0, y),
				Size = UDim2.new(1, 0, 0, rh),
				BackgroundColor3 = if mine then Color3.fromHex("#fff3e0") else Ui.WHITE,
				Parent = parent,
			}, { Ui.corner(12), Ui.stroke(2, if mine then Color3.fromHex("#ff9800") else Color3.fromHex("#e0e0e0")) })
			local rank = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, px(8), 0.5, 0), Size = UDim2.fromOffset(px(30), px(30)), BackgroundColor3 = if r.place == 1 then GOLD elseif r.place == 2 then Color3.fromHex("#e0e0e0") elseif r.place == 3 then Color3.fromHex("#ffab91") else Color3.fromHex("#eceff1"), Parent = row }, { Ui.round() })
			Ui.text({ Text = tostring(r.place), TextSize = px(15), TextColor3 = Ui.INK, Size = UDim2.fromScale(1, 1), Parent = rank })
			Ui.text({ Text = (r.town or "Town") .. (if mine then " (you)" else ""), Body = true, Weight = "heavy", TextSize = px(15), TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(px(48), 0), Size = UDim2.new(1, -px(48) - px(110), 1, 0), Parent = row })
			Ui.text({ Text = boardValue(boardGame, r.best), TextSize = px(17), TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -px(10), 0, 0), Size = UDim2.new(0, px(100), 1, 0), Parent = row })
			y += rh + 6
		end
		return y
	end

	draw = function()
		if content then
			content:Destroy()
		end
		local scroll = Ui.scroller({ Name = "Content", Size = UDim2.fromScale(1, 1), Parent = body })
		content = scroll
		local h = if view == "lots" then lotsView(scroll) elseif view == "boards" then boardsView(scroll) else gamesView(scroll)
		scroll.CanvasSize = UDim2.fromOffset(0, h + 10)
	end

	refreshState()
	refreshPrizes()
	draw()
	return overlay
end

-- ── A run ───────────────────────────────────────────────────────────────────────────────────
-- Starts a run of game `id` (lot: Parking Pro's 1-based lot): asks the server, hides the town's
-- HUD, runs the game module, sends its result and shows the result card.
function Arcade.play(ctx: any, id: string, lot: number?)
	local mod = Arcade.module(id)
	if not mod then
		ctx.toast("Coming to Roblox soon")
		return
	end
	local car = myCar()
	if not car then
		ctx.toast("You need a car to play")
		return
	end
	local ok, started = Arcade.call("start", id, lot)
	if not ok then
		-- Out of fuel opens the "you need" menu (it comes with the town's snapshot).
		if started ~= "need fuel" then
			ctx.toast(WHY[started] or "That didn't work. Try again.")
		end
		return
	end
	ctx.close()
	local root: Frame = ctx.gui
	local hudGui = root:FindFirstAncestorOfClass("ScreenGui") :: ScreenGui
	local playerGui = hudGui.Parent
	hudGui.Enabled = false
	local gui = Ui.new("ScreenGui", { Name = "ArcadeGame", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = playerGui })
	local hudScale = root:FindFirstChildOfClass("UIScale")
	local done = false
	local level = store.useGame.getState().level
	local run: any = {
		gui = gui,
		origin = ORIGINS[id],
		seed = started.seed,
		level = level,
		car = car,
		lot = lot,
		-- Extras beyond the contract: the HUD's scale (the web's 1280x800 fitted to the screen)
		-- and its toasts.
		scale = if hudScale then hudScale.Scale else 1,
		toast = ctx.toast,
		-- The town's buildings, for the shops along Getaway Chase's street (ArcadeScenery useTownPool).
		buildings = store.useGame.getState().buildings,
	}
	run.finish = function(result: number, detail: { [string]: any }?)
		if done then
			return
		end
		done = true
		task.spawn(function()
			local d: { [string]: any } = detail or {}
			local sentOk, res = Arcade.call("submit", id, result, d)
			if d.quit then
				gui:Destroy()
				hudGui.Enabled = true
				ctx.open("arcade", if id == "park" then { view = "lots" } else nil)
				return
			end
			Arcade.result(ctx, gui, hudGui, id, lot, result, d, if sentOk then res else nil, level)
		end)
	end
	task.spawn(function()
		local ran, err = pcall(mod.play, run)
		if not ran then
			warn(`[Cartopia] arcade {id}: {err}`)
			if not done then
				run.finish(0, { quit = true })
			end
		end
	end)
end

-- The result card (ArcadeBits Result inside Arcade.tsx ChaseGame / ParkGame and ArcadeMore.tsx
-- StarGame): the title, the score or stars, the pay and this week's place, and Back / Again.
-- res: what the server paid (nil when the run didn't count).
function Arcade.result(ctx: any, gui: ScreenGui, hudGui: ScreenGui, id: string, lot: number?, result: number, detail: any, res: any?, level: number)
	local info = BY_ID[id]
	-- The game's screen is in the web's CSS pixels, so the card is drawn at the web's sizes: at
	-- least 250 wide, as wide as its pay and buttons need, never wider than the screen allows.
	local view = workspace.CurrentCamera.ViewportSize
	local maxW = math.min(340, (if view.X > 2 then view.X else 1280) - 32)
	local screen = Ui.new("Frame", { Name = "ResultScreen", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	local inner = Ui.new("Frame", { Name = "Result", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 300), BackgroundTransparency = 1, Parent = screen })
	local stars: number = if res and res.stars then res.stars else 0
	local win: boolean
	local title: string
	if id == "chase" then
		win = res ~= nil and res.record == true
		title = if win then "🏆 New best!" else "🚨 Busted!"
	elseif id == "park" then
		win = res ~= nil and res.parked == true
		title = if win then "🅿️ Parked!" else "💥 Too many dents"
	else
		win = stars > 0
		title = if stars == 0 then "😬 So close" elseif res and res.record then "🏆 New best!" elseif stars == 3 then "🌟 Perfect!" else "👏 Nice!"
	end
	if res == nil then
		win = false
		title = "😬 Didn't count"
	end
	-- The backdrop: a gold glow for a win (.rr.win), a dark wash otherwise.
	local back = Ui.new("Frame", { Name = "Backdrop", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#0a1428"), BackgroundTransparency = if win then 0.35 else 0.45, BorderSizePixel = 0, ZIndex = 0, Parent = screen })
	if win then
		Ui.new("UIGradient", {
			Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromHex("#ffd54f")), ColorSequenceKeypoint.new(1, Color3.fromHex("#0a1428")) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
			Rotation = 90,
			Parent = back,
		})
	end
	local card = Ui.new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(300, 260), BackgroundColor3 = Ui.SHEET, ZIndex = 2, Parent = inner }, {
		Ui.corner(20),
		Ui.stroke(3, Ui.WHITE),
	})
	Ui.new("Frame", { Name = "Drop", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 6), Size = UDim2.fromOffset(306, 266), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.75, ZIndex = 1, Parent = inner }, { Ui.corner(22) })
	local y = 14
	local payWidth = 0
	local function line(text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
		local p: { [string]: any } = { Text = text, TextSize = size, TextColor3 = color, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, size + 6), ZIndex = 3, Parent = card }
		for key, v in (props or {}) :: { [string]: any } do
			p[key] = v
		end
		local l = Ui.text(p)
		y += size + 8
		return l
	end
	line(title, 26, Ui.INK, { Name = "Title" })
	if id == "chase" then
		line(Ui.commas(math.floor(result)), 48, Color3.fromHex("#1e5fbf"), { Name = "Big" })
	else
		if (id ~= "park" or win) and res then
			local row = Ui.new("Frame", { Name = "Stars", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, ZIndex = 3, Parent = card }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 4) }),
			})
			for n = 1, 3 do
				Ui.text({ Text = "★", TextSize = 46, TextColor3 = if n <= stars then Color3.fromHex("#ffc107") else Color3.fromHex("#cfd8dc"), Size = UDim2.fromOffset(48, 52), Shadow = if n <= stars then 3 else nil, ShadowColor = Color3.fromHex("#e65100"), ZIndex = 3, Parent = row })
			end
			y += 56
		end
		local sub = if id == "park"
			then string.format("⏱ %.1fs · 💥 %d", result, detail.bumps or 0)
			else (detail.line or (if id == "pit" then string.format("⏱ %.1fs", result) else tostring(result)))
		line(sub, 16, Color3.fromHex("#607d8b"), { Name = "Sub" })
	end
	if res and (res.coins or 0) + (res.xp or 0) > 0 then
		local pay = Ui.new("Frame", { Name = "Pay", Position = UDim2.fromOffset(0, y + 2), Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, ZIndex = 3, Parent = card }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10) }),
		})
		for _, t in { `🪙 +{Ui.commas(res.coins or 0)}`, `⭐ +{res.xpGain or 0} XP` } do
			local w = Ui.textWidth(t, 18) + 28
			payWidth += w + (if payWidth > 0 then 10 else 0)
			local chip = Ui.new("Frame", { Size = UDim2.fromOffset(w, 28), BackgroundColor3 = Color3.fromHex("#fff3c4"), ZIndex = 3, Parent = pay }, { Ui.round() })
			Ui.text({ Text = t, TextSize = 18, TextColor3 = Ui.INK, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = chip })
		end
		y += 36
	end
	if res and res.place then
		line(`🏅 #{res.place} this week`, 20, GOLD, { Name = "Week", Stroke = 1.5, StrokeColor = Color3.fromHex("#8d5a00") })
	end
	-- What the next run costs.
	local _, state = Arcade.call("state")
	local nextCost = cost(state, id)
	local function leave(go: (() -> ())?)
		gui:Destroy()
		hudGui.Enabled = true
		if go then
			go()
		else
			ctx.open("arcade", if id == "park" then { view = "lots" } else nil)
		end
	end
	local buttons: { { text: string, kind: string, go: (() -> ())? } } = { { text = "Back", kind = "sell" } }
	if id == "park" then
		local n = lot or 1
		table.insert(buttons, { text = `Retry · {nextCost}`, kind = "garage", go = function()
			Arcade.play(ctx, id, n)
		end })
		if win and n < #arcade.PARK_LOTS then
			table.insert(buttons, { text = `Next · {nextCost}`, kind = "green", go = function()
				Arcade.play(ctx, id, n + 1)
			end })
		end
	else
		table.insert(buttons, { text = `Again · {nextCost}`, kind = "green", go = function()
			Arcade.play(ctx, id, nil)
		end })
	end
	-- The buttons (.arc-actions): centred, wrapping onto a second row when they don't fit.
	local widths = {}
	local all = 0
	for i, b in buttons do
		widths[i] = Ui.textWidth(b.text, 16) + 32
		all += widths[i] + (if i > 1 then 8 else 0)
	end
	local CW = math.min(maxW, math.max(250, payWidth + 44, all + 44))
	local rows: { { number } } = { {} }
	local used = 0
	for i, w in widths do
		local row = rows[#rows]
		if #row > 0 and used + 8 + w > CW - 32 then
			table.insert(rows, { i })
			used = w
		else
			used += (if #row > 0 then 8 else 0) + w
			table.insert(row, i)
		end
	end
	y += 6
	for _, row in rows do
		local rowW = 0
		for n, i in row do
			rowW += widths[i] + (if n > 1 then 8 else 0)
		end
		local x = (CW - rowW) / 2
		for _, i in row do
			local b = buttons[i]
			local props = { Name = `Button{i}`, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(widths[i], 40), ZIndex = 3, Parent = card }
			if b.kind == "sell" then
				-- The web's white .sell button with a red outline.
				local face = Ui.new("TextButton", { Name = `Button{i}`, Text = b.text, FontFace = Ui.DISPLAY, TextSize = 16, TextColor3 = Color3.fromHex("#c62828"), AutoButtonColor = false, Position = props.Position, Size = props.Size, BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = card }, {
					Ui.corner(12),
					Ui.stroke(2, Color3.fromHex("#c62828")),
				})
				face.Activated:Connect(function()
					leave(nil)
				end)
			else
				local _, face = Ui.buy(props, b.text, b.kind, function()
					leave(b.go)
				end, 16)
				face.Name = `Button{i}`
			end
			x += widths[i] + 8
		end
		y += 48
	end
	y += 8
	card.Size = UDim2.fromOffset(CW, y)
	inner.Size = UDim2.fromOffset(CW, y)
	local drop = inner:FindFirstChild("Drop") :: Frame
	drop.Size = UDim2.fromOffset(CW + 6, y + 6)
	local _ = info
end

return Arcade
