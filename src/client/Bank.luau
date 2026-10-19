--!strict
-- The Bank, as the web game's BankPanel and CarPacksPanel (ui/Bank.tsx, ui/CarPacks.tsx): two tabs
-- of one menu. Gems: the gem packs as cards, each with its art, the gems it gives (bonus included),
-- the bonus, the coins and parts for the player's level, and one Robux price button. Car Packs: the
-- pack-only cars on coloured stages, the super and hyper cars taking turns on a big stage first, one
-- of each per account.
--
-- Prices come from the server (server/Purchases): Roblox Developer Products, in Robux. A pack whose
-- product isn't made yet shows "Soon". Paying happens in Roblox's own prompt; the server adds the
-- pack, the menu redraws with the new gems and the purchase splash shows (client/Popups/Bought).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local packs = require(Game.bucksPacks) :: any
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)
local Remote = require(script.Parent.Remote)

local Bank = {}

local LINE = Ui.LINE
local ZERO = { engine = 0, turbo = 0, tires = 0, weight = 0 }

-- Real-money buys wait for the town's Crew House, built or packed away (web game/payGate.ts), and
-- the end of the tutorial (web game/unlocks.ts "bank").
function Bank.hasCrewHouse(s: any): boolean
	if s.admin then
		return true
	end
	for _, list in { s.buildings or {}, s.stored or {} } do
		for _, b in list do
			if type(b) == "table" and b.def == "crew" then
				return true
			end
		end
	end
	return false
end

function Bank.unlocked(s: any): boolean
	return (s.tutorial or 0) >= 99 and Bank.hasCrewHouse(s)
end

-- Each car pack's stage colours (CarPacks.tsx THEME): the backdrop's two ends and the glow.
local THEME: { [string]: { string } } = {
	scatto = { "#2a0606", "#b71c1c", "#ff8a80" },
	stinger = { "#3e2a00", "#c88a00", "#ffd54f" },
	thunderjet = { "#0d2410", "#2e7d32", "#ffb74d" },
	sora = { "#2a0a12", "#8e1b2c", "#ef9a9a" },
	hayate = { "#1c0b2e", "#6a1b9a", "#ce93d8" },
	kestrel = { "#04221f", "#00796b", "#64ffda" },
	firebolt = { "#3a0d05", "#b4300c", "#ff7043" },
	kaze = { "#061a3a", "#1565c0", "#4fc3f7" },
	sturm = { "#14260f", "#4e6b1e", "#c5e1a5" },
	vanta = { "#4527a0", "#00acc1", "#00e5ff" },
}

local function tierOf(pi: number): string
	return if pi >= 115 then "Hyper" elseif pi >= 100 then "Super" else "New"
end

local WHY = {
	soon = "Packs aren't on sale yet. You weren't charged.",
	crew = "Build a Crew House to open the Bank.",
	owned = "Already yours. Check your garage.",
	["slow down"] = "Slow down a little",
}

local function priceText(robux: number?): string
	return if robux then `R$ {Ui.commas(robux)}` else "Soon"
end

-- A ribbon on a card's top edge (the web's .ribbon), in the featured gold.
local function ribbon(face: Instance, text: string, colors: { string })
	local r = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -11), Size = UDim2.fromOffset(Ui.textWidth(text, 12) + 20, 20), BackgroundColor3 = Ui.WHITE, ZIndex = 6, Parent = face }, {
		Ui.corner(9),
		Ui.stroke(2),
		Ui.gradient(colors[1], colors[2]),
	})
	Ui.text({ Text = text, TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 6, Shadow = 1, ShadowColor = Ui.BLACK, ShadowTransparency = 0.65, Parent = r })
end

-- A grid of `cols` columns with cards `h` tall. (The HUD is laid out at the web's 1280x800 and
-- scaled down to fit a phone, so the sheet is never narrow enough to need fewer.)
local function grid(parent: Instance, order: number, cols: number, h: number): Frame
	local g = Ui.new("Frame", { Name = "Grid", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	Ui.new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 4), Parent = g })
	-- (A pixel to spare, so rounding never pushes the last card of a row onto the next.)
	Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / cols, -10 * (cols - 1) / cols - 1, 0, h), CellPadding = UDim2.fromOffset(10, 18), SortOrder = Enum.SortOrder.LayoutOrder, Parent = g })
	return g
end

local function heading(parent: Instance, order: number, text: string, color: string)
	Ui.text({ Text = text, TextSize = 20, TextColor3 = Color3.fromHex(color), TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order, Parent = parent })
end

local function buyButton(parent: Instance, props: { [string]: any }, p: any, info: any, buy: (any) -> ())
	local owned = info and info.owned
	local robux = info and info.robux
	local label = if owned then "✓ Owned" else priceText(robux)
	local kind = if owned or not robux then "grey" else "green"
	props.Parent = parent
	Ui.buy(props, label, kind, function()
		if not owned then
			buy(p)
		end
	end, 18)
end

-- The Gems tab.
local function gemsTab(list: Instance, s: any, shop: any, buy: (any) -> ())
	local head = Ui.new("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 64), BackgroundColor3 = Color3.fromHex("#e3f2fd"), LayoutOrder = 1, Parent = list }, {
		Ui.corner(14),
		Ui.stroke(2, Color3.fromHex("#90caf9")),
	})
	local ico = Ui.new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Ui.WHITE, Parent = head }, {
		Ui.round(),
		Ui.stroke(2),
		Ui.gradient("#81d4fa", "#0277bd"),
	})
	Ui.text({ Text = "💎", TextSize = 22, Size = UDim2.fromScale(1, 1), Parent = ico })
	Ui.text({ Text = `You have {Ui.commas(s.bucks)} gems`, TextSize = 18, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(64, 10), Size = UDim2.new(1, -76, 0, 24), Parent = head })
	Ui.text({ Text = "🔧 ⛽ 🚚 🚗 🎨", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(64, 34), Size = UDim2.new(1, -76, 0, 20), Parent = head })

	local g = grid(list, 2, 3, 236)
	for i, p in packs.BUCKS_PACKS do
		local grant = packs.packGrant(p, s.level)
		local featured = p.tag ~= nil
		local _, face = Ui.shadowed({ LayoutOrder = i, Parent = g }, { radius = 16, stroke = 3, drop = 4, dark = 0.25, color = if featured then Color3.fromHex("#fffde7") else Ui.WHITE, strokeColor = Color3.fromHex(if featured then "#ffca28" else "#e0e0e0") })
		if p.tag then
			ribbon(face, p.tag, { "#ffb02e", "#ff8f00" })
		end
		Ui.text({ Text = p.art, TextSize = 34, Position = UDim2.fromOffset(0, 12), Size = UDim2.new(1, 0, 0, 40), Parent = face })
		Ui.text({ Text = p.name, TextSize = 15, TextColor3 = LINE, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(6, 54), Size = UDim2.new(1, -12, 0, 20), Parent = face })
		Ui.text({ Text = `💎 {Ui.commas(grant.bucks)}`, TextSize = 25, TextColor3 = Color3.fromHex("#1e5fbf"), Position = UDim2.fromOffset(0, 76), Size = UDim2.new(1, 0, 0, 32), Parent = face })
		local bonus = if p.bonus > 0 then `+{math.floor(p.bonus / p.bucks * 100 + 0.5)}% bonus` else `{Ui.commas(p.bucks)} gems`
		Ui.text({ Text = bonus, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex(if p.bonus > 0 then "#2e7d32" else "#78909c"), Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 0, 18), Parent = face })
		local extras = Ui.new("Frame", { Position = UDim2.fromOffset(4, 130), Size = UDim2.new(1, -8, 0, 20), BackgroundTransparency = 1, Parent = face }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for j, t in { if grant.coins > 0 then `+ ${Ui.commas(grant.coins)}` else "", if grant.parts > 0 then `+ {grant.parts}⚙` else "" } do
			if t ~= "" then
				local w = Ui.textWidth(t, 13) + 12
				local chip = Ui.new("Frame", { Size = UDim2.fromOffset(w, 20), BackgroundColor3 = Color3.fromHex("#fff3e0"), LayoutOrder = j, Parent = extras }, { Ui.corner(8) })
				Ui.text({ Text = t, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex("#6d4c41"), Size = UDim2.fromScale(1, 1), Parent = chip })
			end
		end
		buyButton(face, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 42) }, p, shop and shop.packs[p.id], buy)
	end

	-- Free gems: where they come from without paying.
	local free = Ui.new("Frame", { Name = "Free", Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Ui.WHITE, LayoutOrder = 3, Parent = list }, {
		Ui.corner(14),
		Ui.stroke(2, LINE, 0.86),
	})
	Ui.text({ Text = "⭐", TextSize = 24, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(32, 58), Parent = free })
	Ui.text({ Text = "Free gems", TextSize = 17, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(50, 8), Size = UDim2.new(1, -60, 0, 22), Parent = free })
	Ui.text({ Text = "⬆ Levels · 🎯 Goals · 🔥 Streaks", Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(50, 30), Size = UDim2.new(1, -60, 0, 18), Parent = free })
end

-- A car on its coloured stage, with the PI and gems badges along the top.
local function stage(parent: Instance, car: any, props: { [string]: any }, big: boolean?): Frame
	local t = THEME[car.id] or THEME.vanta
	props.BackgroundColor3 = Ui.WHITE
	props.ClipsDescendants = true
	props.Parent = parent
	local st = Ui.new("Frame", props, { Ui.corner(12), Ui.gradient(t[1], t[2]) })
	local lift = if big then 34 else 0
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4 - lift), Size = UDim2.new(if big then 0.36 else 0.8, 0, 0, if big then 18 else 14), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.6, Parent = st }, { Ui.round() })
	local pic = Thumb.new("Cars", car.id, UDim2.new(1, 0, if big then 1 else 0.86, -lift), Color3.fromHex(car.colors[1]))
	pic.AnchorPoint = Vector2.new(0.5, 1)
	pic.Position = UDim2.new(0.5, 0, 1, -lift)
	pic.BackgroundTransparency = 1
	pic.Parent = st
	return st
end

local function badge(parent: Instance, text: string, props: { [string]: any })
	props.Size = UDim2.fromOffset(Ui.textWidth(text, 13) + 14, 22)
	props.BackgroundColor3 = Ui.BLACK
	props.BackgroundTransparency = 0.45
	props.ZIndex = 4
	props.Parent = parent
	local b = Ui.new("Frame", props, { Ui.corner(9) })
	Ui.text({ Text = text, TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = b })
end

-- The Car Packs tab: the showcase, then the super and hyper cards, then the street ones.
local function carsTab(list: Instance, shop: any, buy: (any) -> (), alive: () -> boolean)
	local top, street = {}, {}
	for _, p in packs.CAR_PACKS do
		table.insert(if p.tier == "super" then top else street, p)
	end

	-- The showcase: the super and hyper cars take turns, or the one the player taps.
	local hero = Ui.new("Frame", { Name = "Showcase", Size = UDim2.new(1, 0, 0, 250), BackgroundColor3 = Color3.fromHex("#14213d"), LayoutOrder = 1, Parent = list }, {
		Ui.corner(16),
		Ui.stroke(3),
	})
	local at, held = #top, false
	local function show()
		for _, c in hero:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local p = top[at]
		local car = data.carDef(p.car)
		local pi = data.performance(car, ZERO)
		stage(hero, car, { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -12) }, true)
		local tier = tierOf(pi)
		badge(hero, tier:upper(), { Position = UDim2.fromOffset(16, 16) })
		Ui.text({ Text = car.name, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 42), Size = UDim2.new(0.6, 0, 0, 32), ZIndex = 4, Stroke = 2.5, Shadow = 3, Parent = hero })
		Ui.text({ Text = `{pi} PI   + {Ui.commas(p.bucks)} 💎`, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 76), Size = UDim2.new(0.6, 0, 0, 24), ZIndex = 4, Stroke = 2, Parent = hero })
		buyButton(hero, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -36), Size = UDim2.fromOffset(150, 44), ZIndex = 5 }, p, shop and shop.packs[p.id], buy)
		local dots = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(#top * 26, 16), BackgroundTransparency = 1, ZIndex = 5, Parent = hero }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i = 1, #top do
			local d = Ui.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(16, 16), BackgroundColor3 = if i == at then Ui.WHITE else Color3.fromHex("#90a4ae"), LayoutOrder = i, ZIndex = 5, Parent = dots }, { Ui.round(), Ui.stroke(2) })
			d.Activated:Connect(function()
				held = true
				at = i
				show()
			end)
		end
	end
	show()
	task.spawn(function()
		while true do
			task.wait(4.5)
			if not alive() or not hero.Parent then
				return
			end
			if not held then
				at = at % #top + 1
				show()
			end
		end
	end)

	local function cards(packList: { any }, order: number, cols: number)
		local g = grid(list, order, cols, 230)
		for i, p in packList do
			local car = data.carDef(p.car)
			local pi = data.performance(car, ZERO)
			local tier = tierOf(pi)
			local info = shop and shop.packs[p.id]
			local owned = info and info.owned
			local _, face = Ui.shadowed({ LayoutOrder = i, Parent = g }, { radius = 16, stroke = 3, drop = 4, dark = 0.3, color = Color3.fromHex(if owned then "#eceff1" else "#ffffff"), strokeColor = Color3.fromHex(if p.tag then "#ffca28" else "#14213d") })
			local st = stage(face, car, { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 120) })
			badge(st, `{pi} PI`, { Position = UDim2.fromOffset(6, 6) })
			badge(st, `+ {Ui.compact(p.bucks)} 💎`, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6) })
			Ui.text({ Text = car.name, TextSize = 17, TextColor3 = LINE, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(6, 130), Size = UDim2.new(1, -12, 0, 24), Parent = face })
			local tag = p.tag or (if tier == "New" then "Pack only" else tier)
			Ui.text({ Text = tag:upper(), TextSize = 12, TextColor3 = Color3.fromHex(if p.tag then "#e65100" elseif tier == "Hyper" then "#00838f" elseif tier == "Super" then "#c62828" else "#5e35b1"), Position = UDim2.fromOffset(6, 154), Size = UDim2.new(1, -12, 0, 16), Parent = face })
			buyButton(face, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 40) }, p, info, buy)
		end
	end
	heading(list, 2, "🔥 Super & Hyper", "#c62828")
	cards(top, 3, 4)
	heading(list, 4, "🏁 Street", "#14213d")
	cards(street, 5, 3)
	Ui.text({ Text = "One of each per account", Body = true, TextSize = 13, TextColor3 = Ui.MUTED, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 6, Parent = list })
end

-- Opens the Bank on a tab ("bank" for gems, "carpacks").
function Bank.open(ctx: any, tab: string?): Instance
	local overlay, _, body = Ui.panel(ctx.gui, if tab == "carpacks" then "Car Packs" else "Bank", { wide = true, onClose = ctx.close, bodyTop = 0 })
	local current = if tab == "carpacks" then "carpacks" else "bank"
	local shop: any = nil
	local list = Ui.scroller({ Name = "List", Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 1, -58), Parent = body })
	Ui.new("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingBottom = UDim.new(0, 12), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local busy = false
	local function buy(p: any)
		if busy then
			return
		end
		busy = true
		local ok, why = Remote.bank("buy", p.id)
		busy = false
		if not ok then
			ctx.toast(WHY[why] or "Couldn't open the purchase. You weren't charged.")
		end
	end

	local drawn = 0
	local function draw()
		drawn += 1
		local me = drawn
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local s = store.useGame.getState()
		if current == "carpacks" then
			carsTab(list, shop, buy, function()
				return me == drawn and overlay.Parent ~= nil
			end)
		else
			gemsTab(list, s, shop, buy)
		end
	end

	Ui.tabs(body, { { id = "bank", label = "💎 Gems" }, { id = "carpacks", label = "🚗 Car Packs" } }, current, function(id)
		current = id
		local title = overlay:FindFirstChild("Title", true)
		if title and title:IsA("TextLabel") then
			Ui.setText(title, if id == "carpacks" then "Car Packs" else "Bank")
		end
		draw()
	end)
	draw()

	-- Prices and what's owned, from the server; again whenever the town changes (a pack just landed).
	local function refresh()
		task.spawn(function()
			local ok, result = Remote.bank("shop")
			if ok and overlay.Parent then
				shop = result
				draw()
			end
		end)
	end
	refresh()
	local conn
	conn = Remote.changed:Connect(function(snap)
		if not overlay.Parent then
			conn:Disconnect()
			return
		end
		if snap.toasts and #snap.toasts > 0 then
			refresh()
		end
	end)
	return overlay
end

return Bank
