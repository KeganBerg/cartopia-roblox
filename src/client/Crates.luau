--!strict
-- The Crate Depot, as the web game's CratesPanel (ui/Crates.tsx, crates.css): the depot in 3D
-- (CrateScene) behind a compact picker docked along the bottom (on a wide screen, standing on the
-- right with the crate on the left): the four crates, their odds (tap a slice for what it holds)
-- and the Open and ×10 buttons. Opening asks the server (server/Crates), which rolls with the web
-- game's own code; the crate shakes on the lift while it waits, then strains, bursts and its prize
-- rises out of it. A single open ends on the prize's card; ×10 opens the first nine quickly, the
-- rarest last, with a strip of the ten along the top, then shows all ten to pick through.
--
-- Where Roblox's rules restrict paid random items (PolicyService, shared/Policy), crates bought
-- with gems are hidden (unless one was won free, which still opens) and a line says why; coin
-- crates are as usual. The odds are always on show. The server checks the same rule
-- (server/Crates), so this is only the menu's side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local crates = require(Game.crates) :: any
local hats = require(Game.hats) :: any
local callCards = require(Game.callCards) :: any
local resto = require(Game.resto) :: any
local cups = require(Game.cups) :: any
local raceCar = require(Game.raceCar) :: any
local Policy = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Policy"))
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Icons = require(script.Parent.Icons)
local Thumb = require(script.Parent.Thumb)
local CallCardArt = require(script.Parent.CallCardArt)
local CrateScene = require(script.Parent.CrateScene)

local Crates = {}

local TIER_GLOW = CrateScene.TIER_GLOW
-- The dock's dark glass (rgba(24,18,38,.82)) and the prize card's (rgba(20,14,32,.9)).
local DOCK = Color3.fromHex("#181226")
local CARD = Color3.fromHex("#140e20")
local DROP_ICON = { coins = "🪙", dupe = "🪙", skindupe = "🪙", piecedupe = "🪙", mod = "⚙️", skin = "🎨", car = "🚗", hat = "🎩", callcard = "🃏", piece = "🧩" }
local HEADER = 113

-- What the depot is doing, kept between redraws (the Cars page redraws on every new town):
-- the crate picked, the phase, opens still to show, whether the one showing is up, a ×10 run
-- (its prizes, how far it's got, the prize picked in its summary and how the crate on the lift
-- opens), the cars as they were before a part prize and which slice of the odds is open.
type State = {
	pick: string,
	phase: CrateScene.Phase,
	queue: { any },
	shown: boolean,
	ten: { any }?,
	tenAt: number,
	summary: number?,
	tenPace: CrateScene.Pace,
	chained: boolean,
	carsAt: { any },
	odds: string?,
}
local state: State = { pick = "street", phase = "idle", queue = {}, shown = false, ten = nil, tenAt = 1, summary = nil, tenPace = "quick", chained = false, carsAt = {}, odds = nil }
-- The open depot's redraw, the draw count (a redraw replaces the last; leaving the tab doesn't),
-- and the ×10 run's next-crate timer.
local live: (() -> ())? = nil
local drawn = 0
local timer = 0

-- This player's Roblox rules (they arrive as Player attributes from the server).
local function rules(): any
	local me = Players.LocalPlayer
	return Policy.fromAttributes(function(name)
		return me:GetAttribute(name)
	end)
end
local NO_BUY = "💎 Gem crates aren't available where you live"

local function redraw()
	if live then
		live()
	end
end

-- ── Little pieces ────────────────────────────────────────────────────────────────────────────────

-- A price: the coin and the amount, or the gem and the amount, side by side.
local function money(parent: Instance, def: any, level: number, n: number, size: number, color: Color3?, props: { [string]: any }?): Frame
	local p = crates.crateCost(def, level)
	local row = Ui.new("Frame", { Size = UDim2.fromOffset(0, size + 2), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 6, Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for k, v in (props or {}) :: { [string]: any } do
		(row :: any)[k] = v
	end
	if p.coins > 0 then
		local ic = Icons.draw("coin", row, size)
		ic.LayoutOrder = 1
		ic.ZIndex = 6
		for _, d in ic:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 6
			end
		end
	else
		Ui.text({ Text = "💎", TextSize = size * 0.9, LayoutOrder = 1, Size = UDim2.fromOffset(size, size), ZIndex = 6, Parent = row })
	end
	local amount = if p.coins > 0 then p.coins * n else p.bucks * n
	local label = Ui.compact(amount)
	Ui.text({ Text = label, TextSize = size, TextColor3 = color or Ui.WHITE, LayoutOrder = 2, Size = UDim2.fromOffset(Ui.textWidth(label, size) + 2, size + 2), ZIndex = 6, Parent = row })
	return row
end

local function moneyWidth(def: any, level: number, n: number, size: number): number
	local p = crates.crateCost(def, level)
	return size + 3 + Ui.textWidth(Ui.compact(if p.coins > 0 then p.coins * n else p.bucks * n), size) + 2
end

-- A crate drawn like crates.css .crate-ico: planks, two bands and the glow round it.
local function crateIcon(parent: Instance, def: any, w: number, h: number, props: { [string]: any }): Frame
	local plank = h / 30 * 7
	local f = Ui.new("Frame", { Size = UDim2.fromOffset(w, h), BackgroundColor3 = Color3.fromHex(def.look.wood), ClipsDescendants = false, ZIndex = 6, Parent = parent }, {
		Ui.corner(4),
		Ui.stroke(2.5, Color3.fromHex(def.look.glow), 0.35),
	})
	for k, v in props do
		(f :: any)[k] = v
	end
	if def.id == "diamond" then
		Ui.new("UIGradient", { Rotation = 45, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("#b3e5fc")),
			ColorSequenceKeypoint.new(0.45, Color3.fromHex("#4fc3f7")),
			ColorSequenceKeypoint.new(0.55, Color3.fromHex("#e1f5fe")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("#29b6f6")),
		}), Parent = f })
	else
		if def.id == "gold" then
			f.BackgroundColor3 = Color3.fromHex("#ffd54f")
		end
		-- Plank seams every 7 of 30 units.
		local y = plank - 1
		while y < h - 1 do
			Ui.new("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = if def.id == "gold" then Color3.fromHex("#b8860b") else Ui.BLACK, BackgroundTransparency = if def.id == "gold" then 0 else 0.65, BorderSizePixel = 0, ZIndex = 6, Parent = f })
			y += plank
		end
	end
	local band = Color3.fromHex(def.look.band)
	local bh = math.max(3, h * 4 / 30)
	Ui.new("Frame", { Position = UDim2.new(0, -1, 0, h * 5 / 30), Size = UDim2.new(1, 2, 0, bh), BackgroundColor3 = band, BorderSizePixel = 0, ZIndex = 7, Parent = f }, { Ui.corner(1) })
	Ui.new("Frame", { Position = UDim2.new(0, -1, 1, -h * 5 / 30 - bh), Size = UDim2.new(1, 2, 0, bh), BackgroundColor3 = band, BorderSizePixel = 0, ZIndex = 7, Parent = f }, { Ui.corner(1) })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, bh, 1, 0), BackgroundColor3 = band, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 7, Parent = f })
	return f
end

-- A dark rounded piece of the dock (rgba(24,18,38,.82), a faint white edge).
local function glass(parent: Instance, props: { [string]: any }, edge: Color3?, edgeAlpha: number?, thick: number?): Frame
	local f = Ui.new("Frame", { BackgroundColor3 = DOCK, BackgroundTransparency = 0.18, ZIndex = 5, Parent = parent }, {
		Ui.corner(14),
		Ui.stroke(thick or 2, edge or Ui.WHITE, edgeAlpha or 0.75),
	})
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

-- The web's white "sell" button: red letters, a red edge (Done).
local function sell(parent: Instance, props: { [string]: any }, text: string, onClick: () -> (), textSize: number?): Frame
	local p = table.clone(props)
	p.Parent = parent
	local shadow = Ui.button(p, "white", onClick, { radius = 12, stroke = 2, drop = 2, dark = 0.2, strokeColor = Color3.fromHex("#d6283b"), text = text, textSize = textSize or 15, textColor = Color3.fromHex("#d6283b") })
	return shadow
end

-- A small green (or blue "alt") button sized to its text.
local function small(parent: Instance, order: number, text: string, kind: string, onClick: () -> (), size: number?, h: number?): Frame
	local ts = size or 15
	local w = Ui.textWidth(text, ts) + 22
	local shadow = Ui.buy({ LayoutOrder = order, Size = UDim2.fromOffset(w, h or 34), ZIndex = 6, Parent = parent }, text, kind, onClick, ts)
	return shadow
end

-- ── What a prize is ──────────────────────────────────────────────────────────────────────────────

-- What a prize is called, the line over it, and its icon (ui/Crates.tsx usePrizeInfo).
local function prizeInfo(d: any, cars: { any }): (string, string, string)
	local k = d.kind
	if k == "coins" then
		return `{Ui.commas(d.coins)} coins`, if d.jackpot then "Jackpot!" else "Coins", "🪙"
	elseif k == "dupe" then
		return `{Ui.commas(d.coins)} coins`, `{data.carDef(d.model).name} · already yours`, "🔁"
	elseif k == "skin" or k == "skindupe" then
		local def = crates.skinOf(d.skin, d.part)
		local kind = if d.part then "Mod Paint" elseif d.skin == data.CUSTOM_PAINT.id then "Unlock" else "Car Paint"
		local name = if def then def.name else ""
		if k == "skindupe" then
			return `{Ui.commas(d.coins)} coins`, `{name} {kind} · already yours`, "🎨"
		end
		local tier = if def then data.SKIN_TIERS[def.tier].name:lower() else ""
		return `{name} {kind}`, `New {tier} {kind:lower()}!`, "🎨"
	elseif k == "car" then
		return data.carDef(d.model).name, "New car!", "🚗"
	elseif k == "piece" or k == "piecedupe" then
		local piece = resto.RESTO_PIECES[d.piece + 1]
		if k == "piecedupe" then
			return `{Ui.commas(d.coins)} coins`, `{piece.name} · already yours`, "🧩"
		elseif d.uid then
			return data.carDef(d.model).name, "Built! Secret car", "🧩"
		end
		local have = #resto.piecesOf(store.useGame.getState().restoParts or {}, d.model)
		return `{piece.icon} {piece.name} piece`, `{data.carDef(d.model).name} · {have}/{resto.PIECE_COUNT}`, "🧩"
	elseif k == "hat" then
		local h = hats.hatDef(d.hat)
		return if h then h.name else "Hat", "New hat!", if h then h.icon else "🎩"
	elseif k == "callcard" then
		local c = callCards.callCardDef(d.card)
		return if c then c.name else "Call Card", `🃏 {if c and c.tier then callCards.TIER_NAME[c.tier] else ""} Call Card`, "🃏"
	end
	local mod = data.modDef(d.mod)
	local mine = nil
	for _, c in cars do
		if c.uid == d.car then
			mine = c
		end
	end
	return if mod then mod.name else "Part", if mine then `For your {data.carDef(mine.model).name}` else "New part", "⚙️"
end

-- A prize's picture: the car itself for car prizes, a paint's swatch, otherwise its icon.
local function prizeArt(parent: Instance, d: any, w: number, h: number, icon: string, look: CrateScene.CarLook?)
	local model = if d.kind == "car" or d.kind == "dupe" or (d.kind == "piece" and d.uid) then d.model else nil
	if look and (d.kind == "skin" or d.kind == "skindupe" or d.kind == "hat" or d.kind == "mod") then
		model = look.model
	end
	if model and Thumb.has("Cars", model) then
		local color = if look then look.color elseif d.color then d.color else data.carDef(model).colors[1]
		local v = if look
			then Thumb.car(model, UDim2.fromOffset(w, h), { color = look.color, finish = look.finish, stripe = look.stripe }, look.hat, look.mods, nil, nil, look.skin, look.modSkin)
			else Thumb.new("Cars", model, UDim2.fromOffset(w, h), Color3.fromHex(color))
		v.AnchorPoint = Vector2.new(0.5, 0.5)
		v.Position = UDim2.fromScale(0.5, 0.5)
		v.ZIndex = 6
		v.Parent = parent
	elseif d.kind == "skin" or d.kind == "skindupe" then
		local def = crates.skinOf(d.skin, d.part)
		local tier = def and data.SKIN_TIERS[def.tier]
		local sw = math.min(w, h) * 0.8
		local f = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(sw, sw), BackgroundColor3 = Color3.fromHex(if tier then tier.color else "#9575cd"), ZIndex = 6, Parent = parent }, {
			if d.part then Ui.round() else Ui.corner(10),
			Ui.stroke(2, Ui.WHITE),
		})
		Ui.text({ Text = if d.part then "⚙️" else "🚗", TextSize = sw * 0.4, AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), Size = UDim2.fromOffset(sw * 0.5, sw * 0.5), ZIndex = 6, Parent = f })
	else
		Ui.text({ Text = icon, TextSize = math.min(w, h) * 0.8, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(w, h), ZIndex = 6, Parent = parent })
	end
end

-- Pops a piece in from a little lower down, as the web's prize-in.
local function popIn(f: GuiObject, dx: number, dy: number)
	local to = f.Position
	f.Position = to + UDim2.fromOffset(dx, dy)
	TweenService:Create(f, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = to }):Play()
end

-- ── The depot ────────────────────────────────────────────────────────────────────────────────────

-- Back to the crate on the lift, for a fresh visit (a prize already seen isn't shown again).
function Crates.reset()
	if state.phase ~= "wait" then
		state.phase = "idle"
		state.queue = {}
		state.shown = false
		state.ten = nil
		state.summary = nil
		state.odds = nil
		timer += 1
		if CrateScene.active() then
			CrateScene.run(crates.crateDef(state.pick) or crates.CRATES[1], "full")
		end
	end
end

-- The opens showing now: the one on the lift.
local function current(): any?
	local ten = state.ten
	if ten then
		return ten[state.summary or state.tenAt]
	end
	return state.queue[1]
end

-- The car a new paint, part or hat is shown on: your selected car, or else the one you race with.
local function paintCar(): string?
	local s = store.useGame.getState()
	local cars = state.carsAt
	for _, c in cars do
		if c.uid == s.selectedCar then
			return c.uid
		end
	end
	local rc = raceCar.raceCarOf(cars, s.raceCar)
	return rc and rc.uid
end

local function lookOf(o: any): CrateScene.CarLook?
	return o and CrateScene.prizeLook(o.drop, state.carsAt, paintCar())
end

local function onReveal()
	state.shown = true
	redraw()
	local ten = state.ten
	if ten and state.summary == nil then
		-- A quick crate's prize stays up a moment, then the next one drops in; the last one stays
		-- up a little longer before the summary comes up under it.
		timer += 1
		local my = timer
		task.delay(if state.tenAt == #ten then 1.6 else 0.48, function()
			if my == timer then
				Crates.tenNext()
			end
		end)
	end
end

-- Puts the open showing now on the lift: a fresh crate drops in (or with `keep`, the one already
-- on the lift opens) and bursts into its prize.
local function showOpen(pace: CrateScene.Pace, keep: boolean?)
	local o = current()
	if not o then
		return
	end
	if not keep then
		CrateScene.run(crates.crateDef(o.crate) or crates.crateDef(state.pick), pace)
	end
	CrateScene.update("open", o.drop, lookOf(o), onReveal)
end

-- ×10: the next crate, or after the last one the summary, with the rarest prize on the lift.
function Crates.tenNext()
	local ten = state.ten
	if not ten or state.summary ~= nil then
		return
	end
	timer += 1
	state.shown = false
	if state.tenAt < #ten then
		state.tenAt += 1
		state.tenPace = if state.tenAt == #ten then "full" else "quick"
		showOpen(state.tenPace)
	else
		state.summary = #ten
	end
	redraw()
end

local function tenSkip()
	local ten = state.ten
	if not ten then
		return
	end
	timer += 1
	state.shown = false
	state.summary = #ten
	state.tenPace = "show"
	showOpen("show")
	redraw()
end

local function inspect(i: number)
	if i == state.summary then
		return
	end
	state.summary = i
	state.tenPace = "show"
	showOpen("show")
	redraw()
end

-- Done with what's shown: the next prize handed over late, or back to the crates.
local function nextOne()
	timer += 1
	state.shown = false
	if #state.queue > 1 then
		table.remove(state.queue, 1)
		state.phase = "open"
		showOpen("full")
		redraw()
		return
	end
	state.queue = {}
	state.ten = nil
	state.summary = nil
	state.phase = "idle"
	CrateScene.run(crates.crateDef(state.pick) or crates.CRATES[1], "full")
	redraw()
end

-- Opens `count` crates. Again chains straight into the next open: the prizes clear, a fresh crate
-- drops on the lift and shakes while the server rolls, and the menu only comes back if it fails.
local function go(count: number, free: string?, chain: boolean?)
	if state.phase ~= (if chain then "open" else "idle") then
		return
	end
	timer += 1
	local def = crates.crateDef(state.pick)
	local before = store.useGame.getState().cars
	if chain then
		state.chained = true
		state.shown = false
		state.queue = {}
		state.ten = nil
		state.summary = nil
		CrateScene.run(def, "full")
	end
	state.phase = "wait"
	CrateScene.update("wait")
	redraw()
	task.spawn(function()
		local got = Remote.crate(def.id, free, count)
		state.chained = false
		if not got or #got == 0 then
			state.phase = "idle"
			CrateScene.update("idle")
			redraw()
			return
		end
		state.shown = false
		if count > 1 and #got > 1 then
			-- The ten were rolled in order; they're shown rarest last, on the cars as they are now.
			state.carsAt = store.useGame.getState().cars
			state.ten = crates.revealOrder(got)
			state.tenAt = 1
			state.summary = nil
			state.tenPace = "quick"
			state.phase = "open"
			showOpen("quick")
		else
			state.carsAt = before
			state.queue = got
			state.phase = "open"
			showOpen("full", true)
		end
		redraw()
	end)
end

-- A tap on the depot moves things along: the crate opening jumps to its prize, and in a ×10 run a
-- prize shown goes on to the next.
local function tap()
	if state.phase ~= "open" then
		return
	end
	if state.ten and state.summary == nil then
		if state.shown then
			Crates.tenNext()
		else
			CrateScene.skip()
		end
	elseif not state.ten and not state.shown then
		CrateScene.skip()
	end
end

-- The odds a crate shows: coins, hats, Call Cards, parts, paints, cars and resto-mod pieces (rarest
-- last), and on a tap what each can hold.
local function odds(dock: Instance, order: number, def: any, s: any, width: number): number
	local level = s.level
	local ownedHats = {}
	for _, h in s.hats or {} do
		ownedHats[h] = true
	end
	local hatList = {}
	for _, h in hats.crateHats(def.id) do
		table.insert(hatList, { h = h, have = ownedHats[h.id] == true })
	end
	local hatsLeft = 0
	for _, x in hatList do
		if not x.have then
			hatsLeft += 1
		end
	end
	local cardsHave = {}
	for _, c in s.callCards or {} do
		cardsHave[c] = true
	end
	local cardList, cardW = {}, 0
	for _, c in callCards.crateCallCards(def.id) do
		table.insert(cardList, { x = c, have = cardsHave[c.id] == true })
		if not cardsHave[c.id] then
			cardW += callCards.CALL_WEIGHT[c.tier]
		end
	end
	local o = crates.crateOddsShown(def, level, hatsLeft > 0, cardW > 0)
	-- Parts that can drop now first, then the crate's own parts that can't (locked, owned or no fit).
	local now, nowList = {}, {}
	for _, x in crates.modChoices(def, level, s.cars) do
		for _, id in x.mods do
			if not now[id] then
				now[id] = true
				table.insert(nowList, id)
			end
		end
	end
	local noParts = #nowList == 0
	local slices = {
		{ "coins", "🪙", o.coins, "#f9a825", "#c17900" },
		{ "hat", "🎩", o.hat, "#c9a98f", "#8d6e63" },
		{ "card", "🃏", o.card, "#b388ff", "#7c4dff" },
		{ "mod", if noParts then "🔧🪙" else "🔧", o.mod, "#9575cd", "#5e35b1" },
		{ "skin", "✨", o.skin, "#ec407a", "#ad1457" },
		{ "car", "🚗", o.car, "#ff9800", "#e65100" },
		{ "piece", "🧩", o.piece, "#26c6da", "#00838f" },
	}
	-- The slices share the row by their odds (each at least wide enough for its label).
	local shown, total = {}, 0
	for _, sl in slices do
		local pct = (sl[3] :: any) :: number
		if pct > 0 or sl[1] == "mod" or sl[1] == "car" then
			local label = `{sl[2]} {pct}%` .. (if sl[1] ~= "coins" then " ▾" else "")
			local need = Ui.textWidth(label, 13) + 10
			local flex = if sl[1] == "coins" then pct else math.max(pct, 14)
			table.insert(shown, { sl = sl, label = label, need = need, flex = flex })
			total += flex
		end
	end
	local inner = width - 14
	local gap = 4
	local free = inner - gap * (#shown - 1)
	-- Too many slices for the row at full size (Gold and Diamond have every kind): smaller text,
	-- and if even that won't fit, every pill gives up the same share.
	local textSize, needAll = 13, 0
	for _, x in shown do
		needAll += x.need
	end
	if needAll > free then
		textSize, needAll = 11, 0
		for _, x in shown do
			x.need = Ui.textWidth(x.label, 11) + 6
			needAll += x.need
		end
		if needAll > free then
			for _, x in shown do
				x.need *= free / needAll
			end
		end
	end
	local fixed, rest = 0, 0
	for _, x in shown do
		x.w = free * x.flex / total
		if x.w < x.need then
			x.w = x.need
			x.fixed = true
			fixed += x.w
		else
			rest += x.flex
		end
	end
	for _, x in shown do
		if not x.fixed then
			x.w = math.max(x.need, (free - fixed) * x.flex / rest)
		end
	end
	local left = crates.pityLeft(def, (s.cratePity or {})[def.id] or 0)
	local open = state.odds
	local listH = if open then 132 else 0
	local h = 10 + 26 + (if left then 22 else 0) + listH
	local box = glass(dock, { Name = "Odds", LayoutOrder = order, Size = UDim2.new(1, 0, 0, h) })
	local x = 7
	for i, it in shown do
		local sl = it.sl
		local pill = Ui.new(if sl[1] == "coins" then "Frame" else "TextButton", { Name = sl[1], LayoutOrder = i, Position = UDim2.fromOffset(x, 5), Size = UDim2.fromOffset(it.w, 26), BackgroundColor3 = Ui.WHITE, ZIndex = 6, Parent = box }, {
			Ui.corner(9),
			Ui.gradient(sl[4] :: string, sl[5] :: string),
		})
		if pill:IsA("TextButton") then
			pill.Text = ""
			pill.AutoButtonColor = false
			pill.Activated:Connect(function()
				state.odds = if state.odds == sl[1] then nil else sl[1]
				redraw()
			end)
		end
		if sl[1] == "mod" and noParts then
			Ui.new("UIStroke", { Thickness = 0, Parent = pill })
			pill.BackgroundTransparency = 0.35
		end
		local label = `{sl[2]} {sl[3]}%` .. (if sl[1] ~= "coins" then (if open == sl[1] then " ▴" else " ▾") else "")
		Ui.text({ Text = label, TextSize = textSize, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = pill })
		x += it.w + gap
	end
	if left then
		local what = if def.pity.tier == "legendary" then "🌟" else "✨"
		Ui.text({ Text = if left <= 1 then `{what} Next one` else `{what} ≤ {left}`, TextSize = 13, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 20), ZIndex = 6, Parent = box })
	end
	if not open then
		return h
	end
	-- What the open slice can hold.
	local list = Ui.scroller({ Position = UDim2.new(0, 6, 1, -listH - 4), Size = UDim2.new(1, -12, 0, listH), ZIndex = 6, Parent = box })
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(52, 54), CellPadding = UDim2.fromOffset(4, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	local n = 0
	local function cell(art: (Frame) -> (), text: string, dim: boolean?, tint: string?): Frame
		n += 1
		local c = Ui.new("Frame", { LayoutOrder = n, BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.92, ZIndex = 6, Parent = list }, { Ui.corner(8) })
		local top = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, ZIndex = 6, Parent = c })
		art(top)
		Ui.text({ Text = text, TextSize = 11, TextColor3 = Color3.fromHex(tint or "#ffe0b2"), TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, 36), Size = UDim2.new(1, -4, 0, 16), ZIndex = 6, Parent = c })
		if dim then
			for _, d in c:GetDescendants() do
				if d:IsA("TextLabel") then
					d.TextTransparency = 0.5
				elseif d:IsA("ViewportFrame") then
					d.ImageTransparency = 0.55
				end
			end
		end
		return c
	end
	local function emoji(t: string): (Frame) -> ()
		return function(f: Frame)
			Ui.text({ Text = t, TextSize = 24, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = f })
		end
	end
	local function pct(p: number): string
		return if p < 0.1 then string.format("%.2f", p) elseif p < 1 then string.format("%.1f", p) else string.format("%d", math.round(p))
	end
	local have = {}
	for _, c in s.cars do
		have[c.model] = true
	end
	local function carArt(model: string): (Frame) -> ()
		return function(f: Frame)
			if Thumb.has("Cars", model) then
				local d = data.carDef(model)
				local v = Thumb.new("Cars", model, UDim2.fromOffset(46, 34), Color3.fromHex(d.colors[1]))
				v.AnchorPoint = Vector2.new(0.5, 0.5)
				v.Position = UDim2.fromScale(0.5, 0.5)
				v.ZIndex = 6
				v.Parent = f
			else
				emoji("🚗")(f)
			end
		end
	end
	if open == "car" then
		local carList = crates.carOdds(def, level)
		table.sort(carList, function(a, b)
			return a.p > b.p
		end)
		for _, c in carList do
			cell(carArt(c.model), if have[c.model] then `🪙 {pct(c.p * o.car)}%` else `{pct(c.p * o.car)}%`, have[c.model])
		end
		local locked = {}
		for _, d in crates.homeCars(def) do
			if d.unlockLevel > level then
				table.insert(locked, d)
			end
		end
		table.sort(locked, function(a, b)
			return a.unlockLevel < b.unlockLevel
		end)
		for _, d in locked do
			cell(carArt(d.id), `🔒{d.unlockLevel}`, true, "#cfd8dc")
		end
		if #carList == 0 and #locked == 0 then
			cell(emoji("🚫"), "None yet", true)
		end
	elseif open == "mod" then
		local slotIcon = {}
		for _, sl in data.MOD_SLOTS do
			slotIcon[sl.id] = sl.icon
		end
		for _, id in nowList do
			local m = data.modDef(id)
			cell(emoji(slotIcon[m.slot] or "🔧"), m.name, false, "#d1c4e9")
		end
		for _, m in crates.homeMods(def) do
			if not now[m.id] then
				cell(emoji(slotIcon[m.slot] or "🔧"), if m.unlockLevel > level then `🔒{m.unlockLevel}` else m.name, true, "#d1c4e9")
			end
		end
	elseif open == "hat" then
		for _, e in hatList do
			cell(emoji(e.h.icon), if e.have then "✔" else `{pct(o.hat / math.max(1, hatsLeft))}%`, e.have)
		end
	elseif open == "card" then
		for _, e in cardList do
			cell(function(f: Frame)
				-- A still swatch of the card's scene, edged in its tier (the web's crate-cc).
				local sw = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(40, 34), BackgroundColor3 = Ui.WHITE, ZIndex = 6, Parent = f }, {
					Ui.corner(6),
					Ui.stroke(2, Ui.WHITE),
				})
				CallCardArt.chip(sw, e.x.id, 40 / 34)
			end, if e.have then "✔" else `{pct(o.card * callCards.CALL_WEIGHT[e.x.tier] / math.max(1, cardW))}%`, e.have)
		end
	elseif open == "skin" then
		local owned = {}
		local st = { level = level, claimedSets = s.claimedSets, skins = s.skins, modSkins = s.modSkins }
		for _, id in crates.crateOwnedSkins(st) do
			owned["b:" .. id] = true
		end
		for _, id in data.ownedModSkins(st) do
			owned["p:" .. id] = true
		end
		local skinList = crates.skinOdds(def)
		table.sort(skinList, function(a, b)
			return a.p > b.p
		end)
		for _, e in skinList do
			local key = (if e.part then "p:" else "b:") .. e.id
			local tier = data.SKIN_TIERS[e.def.tier]
			cell(function(f: Frame)
				Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 30), BackgroundColor3 = Color3.fromHex(tier.color), ZIndex = 6, Parent = f }, {
					if e.part then Ui.round() else Ui.corner(8),
					Ui.stroke(2, Ui.WHITE, 0.3),
				})
			end, `{pct(e.p * o.skin)}%`, owned[key], "#e1bee7")
		end
	elseif open == "piece" then
		for _, d in resto.restoCars() do
			local got = #resto.piecesOf(s.restoParts or {}, d.id)
			local done = have[d.id] == true
			cell(carArt(d.id), if d.unlockLevel > level then `🔒{d.unlockLevel}` elseif done then "✔" else `{got}/{resto.PIECE_COUNT}`, d.unlockLevel > level, "#80deea")
		end
	end
	return h
end

-- The prize's own buttons: they leave the crates for the Garage with the prize on try-on there,
-- on the car it's for; the Garage's own buttons fit it.
local function prizeActions(row: Instance, d: any, ctx: any, sz: number?, h: number?)
	local car = paintCar()
	local function garage(uid: string?, tab: string)
		if uid then
			ctx.open("cars", { car = uid, tab = tab })
		end
	end
	if d.kind == "callcard" then
		local worn = store.useGame.getState().callCard == d.card
		small(row, 1, if worn then "✔" else "Use it", "garage", function()
			if not worn then
				Remote.act("equipCallCard", d.card)
				redraw()
			end
		end, sz, h)
	elseif d.kind == "mod" then
		small(row, 1, "Fit it", "green", function()
			garage(d.car, "mods")
		end, sz, h)
	elseif d.kind == "skin" and car then
		small(row, 1, "Use it", "garage", function()
			garage(car, if d.part then "mods" else "paint")
		end, sz, h)
	elseif d.kind == "hat" and car then
		small(row, 1, "Wear it", "garage", function()
			garage(car, "hats")
		end, sz, h)
	elseif (d.kind == "car" or (d.kind == "piece" and d.uid)) and d.uid then
		small(row, 1, "Garage", "garage", function()
			garage(d.uid, "tune")
		end, sz, h)
	end
end

function Crates.draw(parent: Instance, ctx: any)
	drawn += 1
	local me = drawn
	local root = Ui.new("Frame", { Name = "Depot", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = parent })
	-- The depot shows through the page (under its header and tabs): fit the 3D view to that.
	local hud = ctx.gui :: GuiObject
	local function area(): { x: number, y: number, w: number, h: number }
		local h = if hud and hud.Size.Y.Offset > 0 then hud.Size.Y.Offset else 800
		return { x = 0, y = HEADER / h, w = 1, h = (h - HEADER) / h }
	end
	local panel = parent:FindFirstAncestor("Panel") or parent
	local fresh = not CrateScene.active()
	CrateScene.enter(area(), hud, panel)
	if fresh then
		Crates.reset()
		CrateScene.run(crates.crateDef(state.pick) or crates.CRATES[1], "full")
	end

	local function render()
		for _, c in root:GetChildren() do
			c:Destroy()
		end
		local s = store.useGame.getState()
		local level = s.level
		local free = s.freeCrates or {}
		local function freeOf(id: string): { string }
			local out = {}
			for _, f in free do
				if cups.freeCrateOf(f) == id then
					table.insert(out, f)
				end
			end
			return out
		end
		-- The crates shown: a gem crate that can't be bought here only while one is free.
		local r = rules()
		local restricted = false
		local shownCrates = {}
		for _, c in crates.CRATES do
			if Policy.canBuyCrate(r, c.pay) or #freeOf(c.id) > 0 then
				table.insert(shownCrates, c)
			end
			restricted = restricted or not Policy.canBuyCrate(r, c.pay)
		end
		local def = crates.crateDef(state.pick) or crates.CRATES[1]
		if not table.find(shownCrates, def) then
			def = shownCrates[1]
			if state.phase == "idle" and def.id ~= state.pick then
				state.pick = def.id
				CrateScene.run(def, "full")
			end
		end
		local buyable = Policy.canBuyCrate(r, def.pay)
		local freeHere = freeOf(def.id)
		local wide = CrateScene.wide()
		local W = if hud and hud.Size.X.Offset > 0 then hud.Size.X.Offset else 1280
		local H = (if hud and hud.Size.Y.Offset > 0 then hud.Size.Y.Offset else 800) - HEADER
		local dockW = if wide then 384 else math.min(520, W - 16)
		-- Where things over the crate centre: left of middle on a wide screen.
		local midX = if wide then 0.37 else 0.5

		-- A tap anywhere on the depot moves an opening along.
		if state.phase == "open" then
			local catcher = Ui.new("TextButton", { Name = "Tap", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 4, Parent = root })
			catcher.Activated:Connect(tap)
		end

		-- Coins and gems: along the top, or (on a tall screen, where the top is the depot's sign) on
		-- the dock over the crates.
		local function wallet(parentOf: Instance, props: { [string]: any })
			local w = Ui.new("Frame", { Name = "Wallet", Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 6, Parent = parentOf }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for k, v in props do
				(w :: any)[k] = v
			end
			for i, kind in { "coins", "bucks" } do
				local amount = Ui.compact(if kind == "coins" then s.coins else s.bucks)
				local pill = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(24 + Ui.textWidth(amount, 15) + 12, 26), BackgroundColor3 = Color3.fromHex("#120c1c"), BackgroundTransparency = 0.3, ZIndex = 6, Parent = w }, {
					Ui.round(),
					Ui.stroke(2, Ui.WHITE, 0.4),
				})
				if kind == "coins" then
					local ic = Icons.draw("coin", pill, 16, nil, nil, UDim2.fromOffset(5, 5))
					for _, d in ic:GetDescendants() do
						if d:IsA("GuiObject") then
							d.ZIndex = 6
						end
					end
					ic.ZIndex = 6
				else
					Ui.text({ Text = "💎", TextSize = 14, Position = UDim2.fromOffset(4, 4), Size = UDim2.fromOffset(18, 18), ZIndex = 6, Parent = pill })
				end
				Ui.text({ Text = amount, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 1, 0), ZIndex = 6, Parent = pill })
			end
		end
		if wide then
			wallet(root, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10) })
		end

		local open = current()
		-- A Call Card prize stands over the lift, full size, with your race car's card art.
		if state.phase == "open" and open and open.drop.kind == "callcard" and (state.shown or state.summary ~= nil) then
			local ch = math.min(H * (if wide then 0.52 else 0.4), if wide then 420 else 340)
			if state.summary ~= nil and not wide then
				ch = math.min(H * 0.32, 280)
			end
			local def2 = callCards.callCardDef(open.drop.card)
			local glow = if def2 and def2.tier == "legendary" then "#ffb300" elseif def2 and def2.tier == "epic" then "#b388ff" else "#5aa9ff"
			local cardF = Ui.new("Frame", { Name = "CardOnLift", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(midX, if wide then 0.5 else (if state.summary ~= nil then 0.32 else 0.37)), Size = UDim2.fromOffset(ch * 5 / 6, ch), BackgroundColor3 = Ui.WHITE, ZIndex = 5, Parent = root }, {
				Ui.corner(20),
				Ui.stroke(4, Color3.fromHex(glow)),
			})
			-- The card with your race car standing on its ground (the web's CallCardShowcase).
			CallCardArt.showcase(cardF, open.drop.card, { aspect = 5 / 6 })
			popIn(cardF, 0, 40)
		end

		if state.phase == "open" and not state.shown and not state.ten then
			local skip = Ui.text({ Name = "Skip", Text = "Tap to skip", TextSize = 15, TextTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -22), Size = UDim2.fromOffset(200, 22), Stroke = 1.5, StrokeTransparency = 0.5, ZIndex = 6, Parent = root })
			TweenService:Create(skip, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextTransparency = 0.6 }):Play()
		end

		if state.phase == "open" and state.shown and open and not state.ten then
			-- The prize card under the reveal (beside it on a wide screen), edged in the prize's glow.
			local d = open.drop
			local tier = crates.dropTier(d) + 1
			local glow = Color3.fromHex(TIER_GLOW[tier])
			local title, sub, icon = prizeInfo(d, state.carsAt)
			local cw = if wide then 360 else dockW
			local card = Ui.new("Frame", { Name = "Prize", AnchorPoint = if wide then Vector2.new(1, 0.5) else Vector2.new(0.5, 1), Position = if wide then UDim2.new(1, -16, 0.5, 0) else UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(cw, 108), BackgroundColor3 = CARD, BackgroundTransparency = 0.1, ZIndex = 5, Parent = root }, {
				Ui.corner(18),
				Ui.stroke(3, glow),
			})
			-- Its glow, spilling out round the edge.
			Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 18, 1, 18), BackgroundTransparency = 1, ZIndex = 4, Parent = card }, {
				Ui.corner(24),
				Ui.stroke(8, glow, 0.75),
			})
			local art = Ui.new("Frame", { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(46, 46), BackgroundTransparency = 1, ZIndex = 6, Parent = card })
			prizeArt(art, d, 46, 40, icon, nil)
			Ui.text({ Text = sub:upper(), TextSize = 13, TextColor3 = glow, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(68, 12), Size = UDim2.new(1, -80, 0, 16), ZIndex = 6, Parent = card })
			local t = Ui.text({ Text = title, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(68, 28), Size = UDim2.new(1, -80, 0, 28), ZIndex = 6, Parent = card })
			if tier == 4 then
				Ui.new("UIGradient", { Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Ui.WHITE), ColorSequenceKeypoint.new(0.5, Color3.fromHex("#ffe082")), ColorSequenceKeypoint.new(1, Ui.WHITE) }), Parent = t })
			end
			local row = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -10), Size = UDim2.new(1, -24, 0, 36), BackgroundTransparency = 1, ZIndex = 6, Parent = card }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			prizeActions(row, d, ctx)
			-- (Again only for the crate still picked: a free gem crate, once opened, leaves the dock.)
			local rest = #state.queue > 1
			local againFree = #freeHere > 0
			local againDef = crates.crateDef(open.crate) or def
			if rest or (open.crate == def.id and (againFree or (buyable and level >= def.unlockLevel))) then
				local label = if rest then "Next" elseif againFree then `🎁 Free · {#freeHere}` else "Again · "
				local w = Ui.textWidth(label, 15) + 22 + (if rest or againFree then 0 else moneyWidth(againDef, level, 1, 15))
				local again = Ui.buy({ LayoutOrder = 2, Size = UDim2.fromOffset(w, 34), ZIndex = 6, Parent = row }, if rest or againFree then label else "", "green", function()
					if rest then
						nextOne()
					else
						go(1, freeHere[1], true)
					end
				end, 15)
				if not (rest or againFree) then
					local face = again:FindFirstChildWhichIsA("TextButton", true) :: Instance
					local line = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 6, Parent = face }, {
						Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
					})
					Ui.text({ Text = label, TextSize = 15, LayoutOrder = 1, Size = UDim2.fromOffset(Ui.textWidth(label, 15), 20), Stroke = 1.5, StrokeColor = Color3.fromHex("#0f2a12"), ZIndex = 6, Parent = line })
					money(line, againDef, level, 1, 15, nil, { LayoutOrder = 2 })
				end
			end
			sell(row, { LayoutOrder = 3, Size = UDim2.fromOffset(70, 34), ZIndex = 6 }, "Done", nextOne)
			popIn(card, if wide then 30 else 0, if wide then 0 else 30)
			return
		end

		local ten = state.ten
		if ten and state.summary == nil then
			-- A ×10 run: a slot per crate along the top, lit with each prize's icon once it's out.
			local at = if state.shown then state.tenAt else state.tenAt - 1
			local strip = Ui.new("Frame", { Name = "TenStrip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(midX, 0, 0, 54), Size = UDim2.fromOffset(#ten * 31 + 11, 40), BackgroundColor3 = Color3.fromHex("#120c1c"), BackgroundTransparency = 0.22, ZIndex = 5, Parent = root }, {
				Ui.corner(22),
				Ui.stroke(2, Ui.WHITE, 0.8),
			})
			for i, o in ten do
				local tier = crates.dropTier(o.drop) + 1
				local got = i <= at
				local nowOn = i == at + 1
				local dot = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(8 + (i - 1) * 31 + 15, 20), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.fromHex("#120c1c"), BackgroundTransparency = 0.3, ZIndex = 6, Parent = strip }, {
					Ui.round(),
					Ui.stroke(2, if got then Color3.fromHex(TIER_GLOW[tier]) elseif nowOn then Ui.WHITE else Ui.WHITE, if got or nowOn then 0 else 0.75),
				})
				if got then
					Ui.text({ Text = DROP_ICON[o.drop.kind] or "🪙", TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = dot })
					if i == at and state.shown then
						dot.Size = UDim2.fromOffset(44, 44)
						TweenService:Create(dot, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(26, 26) }):Play()
					end
				end
			end
			if state.shown and open then
				-- The name of the prize just shown, for a moment, under the crate.
				local tier = crates.dropTier(open.drop) + 1
				local glow = Color3.fromHex(TIER_GLOW[tier])
				local title, _, icon = prizeInfo(open.drop, state.carsAt)
				local fw = math.min(Ui.textWidth(title, 19) + 60, W - 96)
				local flash = Ui.new("Frame", { Name = "TenFlash", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(midX, 0, 1, -26), Size = UDim2.fromOffset(fw, 44), BackgroundColor3 = CARD, BackgroundTransparency = 0.1, ZIndex = 5, Parent = root }, {
					Ui.corner(22),
					Ui.stroke(3, glow),
				})
				local ic = Ui.new("Frame", { Position = UDim2.fromOffset(8, 7), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1, ZIndex = 6, Parent = flash })
				prizeArt(ic, open.drop, 30, 30, icon, nil)
				Ui.text({ Text = title, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -56, 1, 0), ZIndex = 6, Parent = flash })
				popIn(flash, 0, 20)
			end
			local _, skipFace = Ui.button({ Name = "TenSkip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -22), Size = UDim2.fromOffset(48, 48), ZIndex = 6, Parent = root }, "navy", tenSkip, { radius = 24, stroke = 3, drop = 3, strokeColor = Ui.WHITE, text = "⏭", textSize = 22, flat = true })
			skipFace.Name = "Skip"
			return
		elseif ten and state.summary ~= nil then
			-- The ×10 summary: all ten prizes as tiles, the one on the lift picked out.
			local sw = if wide then 440 else dockW
			local tileH = if wide then 98 else 90
			local cellW = (sw - 16 - 4 * 5) / 5
			local sum = Ui.new("Frame", { Name = "Summary", AnchorPoint = if wide then Vector2.new(1, 0.5) else Vector2.new(0.5, 1), Position = if wide then UDim2.new(1, -16, 0.5, 0) else UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(sw, 8 + tileH * 2 + 5 + 8 + 36 + 8), BackgroundColor3 = CARD, BackgroundTransparency = 0.1, ZIndex = 5, Parent = root }, {
				Ui.corner(18),
				Ui.stroke(2, Ui.WHITE, 0.7),
			})
			for i, o in ten do
				local d = o.drop
				local tier = crates.dropTier(d) + 1
				local glow = Color3.fromHex(TIER_GLOW[tier])
				local sel = i == state.summary
				local col, rowN = (i - 1) % 5, math.floor((i - 1) / 5)
				local tile = Ui.new("TextButton", { Name = `Tile{i}`, Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(8 + col * (cellW + 5), 8 + rowN * (tileH + 5)), Size = UDim2.fromOffset(cellW, tileH), BackgroundColor3 = if sel then glow:Lerp(CARD, 0.72) else Ui.WHITE, BackgroundTransparency = if sel then 0 else 0.93, ZIndex = 6, Parent = sum }, {
					Ui.corner(12),
					Ui.stroke(2, if sel then Ui.WHITE else glow, if sel then 0 else 0.45),
				})
				tile.Activated:Connect(function()
					inspect(i)
				end)
				local title, _, icon = prizeInfo(d, state.carsAt)
				local look = if d.kind == "skin" or d.kind == "hat" or d.kind == "mod" then CrateScene.prizeLook(d, state.carsAt, paintCar()) else nil
				local art = Ui.new("Frame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, if wide then 52 else 46), BackgroundTransparency = 1, ZIndex = 6, Parent = tile })
				local coinish = d.kind == "coins" or d.kind == "dupe" or d.kind == "skindupe" or d.kind == "piecedupe"
				if coinish and d.kind ~= "dupe" then
					Icons.draw("coin", art, if d.jackpot then 38 else 32, nil, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
					for _, x in art:GetDescendants() do
						if x:IsA("GuiObject") then
							x.ZIndex = 6
						end
					end
				else
					prizeArt(art, d, cellW - 6, if wide then 50 else 44, icon, look)
				end
				local badge = if d.kind == "mod" then "⚙️" elseif d.kind == "skin" or d.kind == "skindupe" then "🎨" elseif d.kind == "hat" then "🎩" elseif d.kind == "callcard" then "🃏" else nil
				if badge then
					Ui.text({ Text = badge, TextSize = 13, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -1, 0, if wide then 56 else 50), Size = UDim2.fromOffset(16, 16), ZIndex = 7, Parent = tile })
				end
				if d.kind == "dupe" or d.kind == "skindupe" then
					Ui.text({ Text = "🔁", TextSize = 13, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 1, 0, if wide then 56 else 50), Size = UDim2.fromOffset(16, 16), ZIndex = 7, Parent = tile })
				end
				local line = if coinish then `🪙{Ui.compact(d.coins)}` elseif d.kind == "skin" then (crates.skinOf(d.skin, d.part) or { name = title }).name else title
				Ui.text({ Text = line, TextSize = 11, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, if wide then 57 else 51), Size = UDim2.new(1, -4, 0, 26), ZIndex = 6, Parent = tile })
				if not coinish then
					local act = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 2), Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, ZIndex = 7, Parent = tile }, {
						Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
					})
					prizeActions(act, d, ctx, 11, 20)
				end
			end
			local row = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -8), Size = UDim2.new(1, -16, 0, 36), BackgroundTransparency = 1, ZIndex = 6, Parent = sum }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			if buyable and level >= def.unlockLevel then
				local label = "Again ×10 · "
				local again = Ui.buy({ LayoutOrder = 1, Size = UDim2.fromOffset(Ui.textWidth(label, 15) + 24 + moneyWidth(def, level, 10, 15), 34), ZIndex = 6, Parent = row }, "", "green", function()
					go(10, nil, true)
				end, 15)
				local face = again:FindFirstChildWhichIsA("TextButton", true) :: Instance
				local line = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 6, Parent = face }, {
					Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
				})
				Ui.text({ Text = label, TextSize = 15, LayoutOrder = 1, Size = UDim2.fromOffset(Ui.textWidth(label, 15), 20), Stroke = 1.5, StrokeColor = Color3.fromHex("#0f2a12"), ZIndex = 6, Parent = line })
				money(line, def, level, 10, 15, nil, { LayoutOrder = 2 })
			end
			sell(row, { LayoutOrder = 2, Size = UDim2.fromOffset(70, 34), ZIndex = 6 }, "Done", nextOne)
			popIn(sum, if wide then 30 else 0, if wide then 0 else 30)
			return
		end
		if state.phase == "open" or state.chained then
			return
		end

		-- ── The dock: the crates, their odds and the buttons ─────────────────────────────────────
		local dock = Ui.new("Frame", { Name = "Dock", AnchorPoint = if wide then Vector2.new(1, 0.5) else Vector2.new(0.5, 1), Position = if wide then UDim2.new(1, -16, 0.5, 0) else UDim2.new(0.5, 0, 1, -10), Size = UDim2.fromOffset(dockW, 0), BackgroundTransparency = 1, ZIndex = 5, Parent = root }, {
			Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local total = 0
		if not wide then
			local holder = Ui.new("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, ZIndex = 5, Parent = dock })
			wallet(holder, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0) })
			total += 26 + 6
		end
		-- The crates (all four, unless gem crates can't be bought here): four across, or two by two
		-- on a wide screen.
		local cols = if wide then math.min(2, #shownCrates) else #shownCrates
		local rows = math.ceil(#shownCrates / cols)
		local tabH = if wide then 84 else 74
		local pickH = rows * tabH + (rows - 1) * 6
		local pick = Ui.new("Frame", { Name = "Pick", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, pickH), BackgroundTransparency = 1, ZIndex = 5, Parent = dock })
		local tw = (dockW - 6 * (cols - 1)) / cols
		for i, c in shownCrates do
			local sel = c.id == def.id
			local nFree = #freeOf(c.id)
			local locked = level < c.unlockLevel
			local col, rowN = (i - 1) % cols, math.floor((i - 1) / cols)
			local tab = Ui.new("TextButton", { Name = c.id, Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(col * (tw + 6), rowN * (tabH + 6) + (if sel then -3 else 0)), Size = UDim2.fromOffset(tw, tabH), BackgroundColor3 = if sel then Color3.fromHex("#3c285a") else DOCK, BackgroundTransparency = if sel then 0.08 else 0.18, ZIndex = 5, Parent = pick }, {
				Ui.corner(14),
				Ui.stroke(2, Ui.WHITE, if sel then 0 else 0.75),
			})
			if sel then
				-- Its drop shadow and soft glow.
				Ui.new("Frame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.65, ZIndex = 4, Parent = tab }, { Ui.corner(14) })
			end
			local icon = crateIcon(tab, c, 34, 30, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, if wide then 8 else 6) })
			if sel then
				TweenService:Create(icon, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.new(0.5, 0, 0, (if wide then 8 else 6) - 2), Rotation = -3 }):Play()
			end
			local nameSize = if wide then 15 else 13
			Ui.text({ Text = (c.name:gsub(" Crate", "")), TextSize = nameSize, Position = UDim2.fromOffset(0, if wide then 42 else 39), Size = UDim2.new(1, 0, 0, nameSize + 2), ZIndex = 6, Parent = tab })
			local priceY = if wide then 61 else 55
			if nFree > 0 or locked then
				Ui.text({ Text = if nFree > 0 then `🎁 {nFree}` else `🔒 Lv {c.unlockLevel}`, TextSize = 12, TextColor3 = Color3.fromHex(if c.pay == "bucks" then "#b3e5fc" else "#ffe082"), Position = UDim2.fromOffset(0, priceY), Size = UDim2.new(1, 0, 0, 14), ZIndex = 6, Parent = tab })
			else
				money(tab, c, level, 1, 12, Color3.fromHex(if c.pay == "bucks" then "#b3e5fc" else "#ffe082"), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, priceY - 1) })
			end
			if locked then
				tab.BackgroundTransparency = 0.45
				for _, d in tab:GetDescendants() do
					if d:IsA("TextLabel") then
						d.TextTransparency = 0.38
					end
				end
			end
			tab.Activated:Connect(function()
				if state.phase == "idle" and c.id ~= state.pick then
					state.pick = c.id
					state.odds = nil
					CrateScene.run(c, "full")
					redraw()
				end
			end)
		end
		total += pickH + 6
		total += odds(dock, 2, def, s, dockW) + 6

		-- Where gem crates can't be bought: one line saying so.
		if restricted then
			local note = glass(dock, { Name = "NoBuy", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 30) })
			Ui.text({ Text = NO_BUY, TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = note })
			total += 30 + 6
		end

		-- Open, and ×10 for the price of ten.
		local buttons = Ui.new("Frame", { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, ZIndex = 5, Parent = dock })
		total += 52
		local gem = def.pay == "bucks"
		local waiting = state.phase ~= "idle"
		local lockedNow = #freeHere == 0 and level < def.unlockLevel
		local canTen = buyable and level >= def.unlockLevel
		local tenW = if canTen then math.max(110, 34 + moneyWidth(def, level, 10, 17) + 24) else 0
		local _, openFace = Ui.button({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, if canTen then -(tenW + 6) else 0, 1, -4), ZIndex = 5, Parent = buttons }, if gem then "gem" else "green", function()
			if not waiting then
				go(1, freeHere[1])
			end
		end, { radius = 16, stroke = 3, drop = 4, dark = 0.4, strokeColor = Ui.WHITE })
		openFace.Name = "Open"
		local line = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 6, Parent = openFace }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local openText = if waiting then "Opening…" elseif #freeHere > 0 then `🎁 Free · {#freeHere}` elseif lockedNow then `🔒 Level {def.unlockLevel}` else "Open ·"
		Ui.text({ Text = openText, TextSize = 22, LayoutOrder = 1, Size = UDim2.fromOffset(Ui.textWidth(openText, 22), 26), Stroke = 2, ZIndex = 6, Parent = line })
		if not waiting and #freeHere == 0 and not lockedNow then
			money(line, def, level, 1, 22, nil, { LayoutOrder = 2 })
		end
		if waiting then
			openFace.AutoButtonColor = false
			for _, d in buttons:GetDescendants() do
				if d:IsA("UIGradient") then
					d.Color = Ui.seq("#9aa7a0", "#5f6e66")
				end
			end
		end
		if canTen then
			local _, tenFace = Ui.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, tenW, 1, -4), ZIndex = 5, Parent = buttons }, "ten", function()
				if not waiting then
					go(10)
				end
			end, { radius = 16, stroke = 3, drop = 4, dark = 0.4, strokeColor = Ui.WHITE })
			if gem then
				for _, d in tenFace:GetDescendants() do
					if d:IsA("UIGradient") then
						d.Color = Ui.seq("#7e57c2", "#311b92")
						break
					end
				end
			end
			local tl = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 6, Parent = tenFace }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			Ui.text({ Text = "×10", TextSize = 22, LayoutOrder = 1, Size = UDim2.fromOffset(Ui.textWidth("×10", 22), 26), Stroke = 2, ZIndex = 6, Parent = tl })
			money(tl, def, level, 10, 17, nil, { LayoutOrder = 2 })
			tenFace.Name = "Ten"
		end
		dock.Size = UDim2.fromOffset(dockW, total)
	end

	live = render
	-- The player's rules can arrive after the depot is drawn.
	local player = Players.LocalPlayer
	for _, name in { Policy.ATTR.ready, Policy.ATTR.paidRandomRestricted } do
		local conn = player:GetAttributeChangedSignal(name):Connect(function()
			if state.phase == "idle" and live == render then
				render()
			end
		end)
		root.Destroying:Connect(function()
			conn:Disconnect()
		end)
	end
	-- The window changed size: fit the 3D view and lay the dock out again.
	local cam = workspace.CurrentCamera
	local resize = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		CrateScene.refit(area())
		if live == render then
			render()
		end
	end)
	root.Destroying:Connect(function()
		resize:Disconnect()
		if live == render then
			live = nil
		end
		-- Leaving the tab (or the Cars page) gives the camera back; a redraw draws a new depot first.
		task.defer(function()
			if drawn == me then
				CrateScene.leave()
			end
		end)
	end)
	render()
	return root
end

return Crates
