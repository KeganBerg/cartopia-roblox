--!strict
-- The Crate Depot, as the web game's CratesPanel (ui/Crates.tsx, crates.css): the picked crate in
-- the middle of a dark depot, and a dock under it with the four crates, their odds and the Open and
-- ×10 buttons. Opening asks the server (server/Crates), which rolls with the web game's own code;
-- the crate shakes and bursts, and the prize card (or, for ×10, all ten prizes) takes the dock's
-- place, edged in the prize's glow.

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
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)

local Crates = {}

-- The reveal's glow by how exciting the prize is (scene/CrateScene.tsx TIER_GLOW).
local TIER_GLOW = { "#4fc3f7", "#b388ff", "#ff4fd8", "#ffb300" }
local DOCK = Color3.fromHex("#18122a")
local DROP_ICON = { coins = "🪙", dupe = "🪙", skindupe = "🪙", piecedupe = "🪙", mod = "⚙️", skin = "🎨", car = "🚗", hat = "🎩", callcard = "🃏", piece = "🧩" }

-- The crate the depot opens on, kept between visits.
local lastPick = "street"
-- What the depot shows (a prize card stays up when a new town redraws the page), whether a crate
-- is mid-burst, and the open depot's redraw, which the burst finishes on.
local shown: { view: string, opens: { any }? } = { view = "idle" }
local busy = false
local live: ((string, { any }?) -> ())? = nil
local shake: (() -> ())? = nil

local function priceText(def: any, level: number, n: number?): string
	local p = crates.crateCost(def, level)
	if p.coins > 0 then
		return `${Ui.compact(p.coins * (n or 1))}`
	end
	return `💎{Ui.compact(p.bucks * (n or 1))}`
end

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

-- A crate drawn like crates.css .crate-ico, at any size: planks, two bands and the glow round it.
local function crateArt(parent: Instance, def: any, size: Vector2, props: { [string]: any }?): Frame
	local f = Ui.new("Frame", { Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = Color3.fromHex(def.look.wood), ZIndex = 4, Parent = parent }, {
		Ui.corner(math.max(4, size.X * 0.06)),
		Ui.stroke(math.max(2, size.X * 0.04), Color3.fromHex(def.look.glow), 0.15),
	})
	for k, v in (props or {}) :: { [string]: any } do
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
		-- Plank seams.
		local seam = Color3.fromHex(if def.id == "gold" then "#b8860b" else "#000000")
		local rows = 5
		for i = 1, rows - 1 do
			Ui.new("Frame", { Position = UDim2.fromScale(0, i / rows), Size = UDim2.new(1, 0, 0, math.max(1, size.Y * 0.03)), BackgroundColor3 = seam, BackgroundTransparency = if def.id == "gold" then 0 else 0.65, BorderSizePixel = 0, ZIndex = 4, Parent = f })
		end
	end
	local band = Color3.fromHex(def.look.band)
	local bh = math.max(3, size.Y * 0.13)
	Ui.new("Frame", { Position = UDim2.new(0, -1, 0.17, 0), Size = UDim2.new(1, 2, 0, bh), BackgroundColor3 = band, BorderSizePixel = 0, ZIndex = 5, Parent = f })
	Ui.new("Frame", { Position = UDim2.new(0, -1, 0.83, -bh), Size = UDim2.new(1, 2, 0, bh), BackgroundColor3 = band, BorderSizePixel = 0, ZIndex = 5, Parent = f })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, bh, 1, 0), BackgroundColor3 = band, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 5, Parent = f })
	return f
end

-- A dark rounded card like the dock's pieces (rgba(24,18,38,.82) with a faint white edge).
local function card(parent: Instance, props: { [string]: any }, edge: Color3?, glow: boolean?): Frame
	local f = Ui.new("Frame", { BackgroundColor3 = DOCK, BackgroundTransparency = 0.12, ZIndex = 4, Parent = parent }, {
		Ui.corner(14),
		Ui.stroke(if glow then 3 else 2, edge or Ui.WHITE, if edge then 0 else 0.75),
	})
	for k, v in props do
		(f :: any)[k] = v
	end
	return f
end

-- A prize's picture: the car itself for car prizes, otherwise its icon.
local function prizeArt(parent: Instance, d: any, size: number, icon: string)
	local model = if d.kind == "car" or d.kind == "dupe" or (d.kind == "piece" and d.uid) then d.model else nil
	if model then
		local color = d.color or data.carDef(model).colors[1]
		local v = Thumb.new("Cars", model, UDim2.fromOffset(size * 1.3, size), Color3.fromHex(color))
		v.AnchorPoint = Vector2.new(0.5, 0.5)
		v.Position = UDim2.fromScale(0.5, 0.5)
		v.ZIndex = 5
		v.Parent = parent
	else
		Ui.text({ Text = icon, TextSize = size * 0.8, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(size, size), ZIndex = 5, Parent = parent })
	end
end

-- Draws the depot into `parent` (the Cars page's content area).
-- Back to the crate on its pedestal, for a fresh visit (a prize already seen isn't shown again).
function Crates.reset()
	if not busy then
		shown = { view = "idle" }
	end
end

function Crates.draw(parent: Instance, ctx: any)
	local root = Ui.new("Frame", { Name = "Depot", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#120c1c"), BorderSizePixel = 0, ZIndex = 3, Parent = parent })

	local function redraw(view: string, opens: { any }?)
		shown = { view = view, opens = opens }
		for _, c in root:GetChildren() do
			c:Destroy()
		end
		local s = store.useGame.getState()
		local level = s.level
		local free = s.freeCrates or {}
		local def = crates.crateDef(lastPick) or crates.CRATES[1]
		local freeHere = {}
		for _, f in free do
			if cups.freeCrateOf(f) == def.id then
				table.insert(freeHere, f)
			end
		end

		-- The wallet along the top.
		local wallet = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, ZIndex = 4, Parent = root }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right }),
		})
		for i, t in { `🪙 {Ui.compact(s.coins)}`, `💎 {Ui.compact(s.bucks)}` } do
			local pill = card(wallet, { LayoutOrder = i, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X })
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = pill })
			Ui.text({ Text = t, TextSize = 16, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5, Parent = pill })
		end

		-- The crate on its stand, glowing in its colour.
		local onStand = if opens and #opens > 0 then crates.crateDef(opens[1].crate) or def else def
		local stage = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 40), Size = UDim2.fromOffset(260, 230), BackgroundTransparency = 1, ZIndex = 3, Parent = root })
		local halo = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(320, 320), BackgroundColor3 = Color3.fromHex(onStand.look.glow), BackgroundTransparency = 0.82, ZIndex = 3, Parent = stage }, { Ui.round() })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(240, 26), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.55, ZIndex = 3, Parent = stage }, { Ui.round() })
		local box = crateArt(stage, onStand, Vector2.new(200, 170), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4) })
		local function burst()
			local t = TweenInfo.new(0.07, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 5, true)
			TweenService:Create(box, t, { Rotation = 6 }):Play()
			TweenService:Create(halo, TweenInfo.new(0.7), { Size = UDim2.fromOffset(420, 420), BackgroundTransparency = 0.6 }):Play()
		end
		shake = burst
		if busy and view == "idle" then
			burst()
		end

		local dock = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -16, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 4, Parent = root }, {
			Ui.new("UISizeConstraint", { MaxSize = Vector2.new(520, math.huge) }),
			Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }),
		})

		local function open(count: number)
			if busy then
				return
			end
			busy = true
			local got = Remote.crate(def.id, if count == 1 then freeHere[1] else nil, count)
			if not got or #got == 0 then
				busy = false
				return
			end
			-- The crate shakes (on the depot as it's drawn now: the new town may have redrawn it),
			-- then bursts into its prize.
			if shake then
				shake()
			end
			task.delay(0.75, function()
				busy = false
				local view, opens = if #got > 1 then "ten" else "prize", if #got > 1 then crates.revealOrder(got) else got
				shown = { view = view, opens = opens }
				if live then
					live(view, opens)
				end
			end)
		end

		if view == "prize" and opens then
			-- One prize: its card, with Again (or Next) and Done.
			box.Visible = false
			local o = opens[1]
			local tier = crates.dropTier(o.drop) + 1
			local glow = Color3.fromHex(TIER_GLOW[tier])
			halo.BackgroundColor3 = glow
			halo.BackgroundTransparency = 0.7
			local title, sub, icon = prizeInfo(o.drop, s.cars)
			local big = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(200, 170), BackgroundTransparency = 1, ZIndex = 4, Parent = stage })
			prizeArt(big, o.drop, 150, icon)
			local prize = card(dock, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 112) }, glow, true)
			local spot = Ui.new("Frame", { Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(52, 52), BackgroundTransparency = 1, ZIndex = 5, Parent = prize })
			prizeArt(spot, o.drop, 44, icon)
			Ui.text({ Text = sub:upper(), TextSize = 13, TextColor3 = glow, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(74, 10), Size = UDim2.new(1, -86, 0, 18), ZIndex = 5, Parent = prize })
			Ui.text({ Text = title, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(74, 28), Size = UDim2.new(1, -86, 0, 30), ZIndex = 5, Parent = prize })
			local rest = { table.unpack(opens, 2) }
			local again = if #rest > 0 then "Next" elseif #freeHere > 0 then `🎁 Free · {#freeHere}` else `Again · {priceText(def, level)}`
			Ui.buy({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -112, 1, -10), Size = UDim2.fromOffset(150, 38), ZIndex = 5, Parent = prize }, again, "green", function()
				if #rest > 0 then
					redraw("prize", rest)
				else
					redraw("idle")
					open(1)
				end
			end, 16)
			Ui.buy({ AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -10, 1, -10), Size = UDim2.fromOffset(94, 38), ZIndex = 5, Parent = prize }, "Done", "garage", function()
				redraw("idle")
			end, 16)
			return
		elseif view == "ten" and opens then
			-- Ten prizes: all of them at once, rarest last, then Again ×10 or Done. The best one
			-- takes the stand.
			box.Visible = false
			local star = opens[#opens]
			local _, _, starIcon = prizeInfo(star.drop, s.cars)
			local big = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(200, 170), BackgroundTransparency = 1, ZIndex = 4, Parent = stage })
			prizeArt(big, star.drop, 150, starIcon)
			local sum = card(dock, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, nil)
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = sum })
			Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = sum })
			local grid = Ui.new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 5, Parent = sum }, {
				Ui.new("UIGridLayout", { CellSize = UDim2.new(0.2, -5, 0, 84), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			local best = 1
			for i, o in opens do
				local tier = crates.dropTier(o.drop) + 1
				best = math.max(best, tier)
				local title, _, icon = prizeInfo(o.drop, s.cars)
				local tile = Ui.new("Frame", { LayoutOrder = i, BackgroundColor3 = Color3.fromHex("#241a3a"), ZIndex = 5, Parent = grid }, {
					Ui.corner(10),
					Ui.stroke(2, Color3.fromHex(TIER_GLOW[tier]), if tier > 1 then 0 else 0.4),
				})
				local art = Ui.new("Frame", { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, ZIndex = 5, Parent = tile })
				prizeArt(art, o.drop, 44, DROP_ICON[o.drop.kind] or icon)
				local coins = o.drop.coins
				Ui.text({ Text = if coins then `🪙{Ui.compact(coins)}` else title, TextSize = 11, TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(3, 56), Size = UDim2.new(1, -6, 0, 26), ZIndex = 5, Parent = tile })
			end
			halo.BackgroundColor3 = Color3.fromHex(TIER_GLOW[best])
			local row = Ui.new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, ZIndex = 5, Parent = sum })
			if level >= def.unlockLevel then
				Ui.buy({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -102, 0, 0), Size = UDim2.fromOffset(190, 38), ZIndex = 5, Parent = row }, `Again ×10 · {priceText(def, level, 10)}`, "green", function()
					redraw("idle")
					open(10)
				end, 16)
			end
			Ui.buy({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(94, 38), ZIndex = 5, Parent = row }, "Done", "garage", function()
				redraw("idle")
			end, 16)
			return
		end

		-- The dock: the four crates.
		local pick = Ui.new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 84), BackgroundTransparency = 1, ZIndex = 4, Parent = dock }, {
			Ui.new("UIGridLayout", { CellSize = UDim2.new(0.25, -5, 1, 0), CellPadding = UDim2.fromOffset(6, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, c in crates.CRATES do
			local sel = c.id == def.id
			local nFree = 0
			for _, f in free do
				if cups.freeCrateOf(f) == c.id then
					nFree += 1
				end
			end
			local locked = level < c.unlockLevel
			local tab = Ui.new("TextButton", { Text = "", AutoButtonColor = false, LayoutOrder = i, BackgroundColor3 = if sel then Color3.fromHex("#3c285a") else DOCK, BackgroundTransparency = 0.12, ZIndex = 4, Parent = pick }, {
				Ui.corner(14),
				Ui.stroke(2, Ui.WHITE, if sel then 0 else 0.75),
			})
			crateArt(tab, c, Vector2.new(34, 30), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, if sel then 4 else 7) })
			Ui.text({ Text = c.name:gsub(" Crate", ""), TextSize = 13, Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 18), ZIndex = 5, Parent = tab })
			local label = if nFree > 0 then `🎁 {nFree}` elseif locked then `🔒 Lv {c.unlockLevel}` else priceText(c, level)
			Ui.text({ Text = label, TextSize = 12, TextColor3 = Color3.fromHex(if c.pay == "bucks" then "#b3e5fc" else "#ffe082"), Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 16), ZIndex = 5, Parent = tab })
			if locked then
				tab.BackgroundTransparency = 0.4
			end
			tab.Activated:Connect(function()
				if not busy and c.id ~= lastPick then
					lastPick = c.id
					redraw("idle")
				end
			end)
		end

		-- The odds: coins, hats, Call Cards, parts, cars, paints and pieces, as the web shows them.
		local owned = {}
		for _, h in s.hats or {} do
			owned[h] = true
		end
		local hatsLeft = false
		for _, h in hats.crateHats(def.id) do
			if not owned[h.id] then
				hatsLeft = true
			end
		end
		local cardsHave = {}
		for _, c in s.callCards or {} do
			cardsHave[c] = true
		end
		local cardsLeft = false
		for _, c in callCards.crateCallCards(def.id) do
			if not cardsHave[c.id] then
				cardsLeft = true
			end
		end
		local o = crates.crateOddsShown(def, level, hatsLeft, cardsLeft)
		local odds = card(dock, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 36) })
		local oddsRow = Ui.new("Frame", { Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1, ZIndex = 5, Parent = odds }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local SLICES: { { any } } = {
			{ "coins", "🪙", o.coins, "#f9a825", "#c17900" },
			{ "hat", "🎩", o.hat, "#c9a98f", "#8d6e63" },
			{ "card", "🃏", o.card, "#26c6da", "#00838f" },
			{ "mod", "⚙️", o.mod, "#9575cd", "#5e35b1" },
			{ "car", "🚗", o.car, "#ff9800", "#e65100" },
			{ "skin", "🎨", o.skin, "#ec407a", "#ad1457" },
			{ "piece", "🧩", o.piece, "#26a69a", "#00695c" },
		}
		for i, sl in SLICES do
			local pct = sl[3] :: number
			if pct > 0 then
				local chip = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.WHITE, ZIndex = 5, Parent = oddsRow }, {
					Ui.corner(9),
					Ui.gradient(sl[4] :: string, sl[5] :: string),
					Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
				})
				Ui.text({ Text = `{sl[2]} {pct}%`, TextSize = 13, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5, Parent = chip })
			end
		end
		local left = crates.pityLeft(def, (s.cratePity or {})[def.id] or 0)
		if left then
			odds.Size = UDim2.new(1, 0, 0, 58)
			oddsRow.Size = UDim2.new(1, -10, 0, 26)
			local what = if def.pity.tier then `{data.SKIN_TIERS[def.pity.tier].name} paint` else "paint"
			Ui.text({ Text = if left <= 1 then `✨ Next open is a {what}!` else `✨ A {what} in {left} opens at most`, TextSize = 13, Position = UDim2.fromOffset(0, 33), Size = UDim2.new(1, 0, 0, 20), ZIndex = 5, Parent = odds })
		end

		-- Open, and ×10 for the price of ten.
		local buttons = Ui.new("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, ZIndex = 4, Parent = dock })
		local gem = def.pay == "bucks"
		local lockedNow = #freeHere == 0 and level < def.unlockLevel
		local label = if #freeHere > 0 then `🎁 Free · {#freeHere}` elseif lockedNow then `🔒 Level {def.unlockLevel}` else `Open · {priceText(def, level)}`
		local canTen = level >= def.unlockLevel
		local _, openFace = Ui.button({ Position = UDim2.fromOffset(0, 0), Size = UDim2.new(1, if canTen then -146 else 0, 1, -4), ZIndex = 4, Parent = buttons }, if gem then "gem" else "green", function()
			open(1)
		end, { radius = 16, stroke = 3, drop = 4, dark = 0.4, strokeColor = Ui.WHITE, text = label, textSize = 22, textShadow = 2 })
		openFace.Name = "Open"
		if canTen then
			Ui.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 140, 1, -4), ZIndex = 4, Parent = buttons }, "ten", function()
				open(10)
			end, { radius = 16, stroke = 3, drop = 4, dark = 0.4, strokeColor = Ui.WHITE, text = `×10 {priceText(def, level, 10)}`, textSize = 18, textShadow = 2 })
		end
	end

	live = redraw
	root.Destroying:Connect(function()
		if live == redraw then
			live = nil
		end
	end)
	redraw(shown.view, shown.opens)
	return root
end

return Crates
