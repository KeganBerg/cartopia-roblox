--!strict
-- The Cars page's Call Cards tab (the web's CallCardPicker): your race car standing on the card
-- you picked, big, then every card as a small swatch. Owned cards equip with one tap; the rest
-- show a lock and send you to the crates they drop from.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local callCards = require(Game.callCards) :: any
local raceCar = require(Game.raceCar) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)

local CallCards = {}

local LINE = Ui.LINE
local EDGE = { rare = "#4fc3f7", epic = "#b388ff", legendary = "#ffd54f" }
local CHIP = { rare = "#e1f5fe", epic = "#ede7f6", legendary = "#fff8e1" }

-- Each card's backdrop, top to bottom: the first layer of its scene in call-cards.css.
local ART: { [string]: { { any } } } = {
	showroom = { { 0.000, "#1c2747" }, { 0.600, "#0e1630" }, { 1.000, "#0a1026" } },
	neonalley = { { 0.000, "#12002b" }, { 0.550, "#3a0b5e" }, { 1.000, "#ff2d95" } },
	raincheck = { { 0.000, "#0c1b33" }, { 0.600, "#1d3557" }, { 0.610, "#2b4c7e" }, { 1.000, "#10203a" } },
	sunsetstrip = { { 0.000, "#2b1055" }, { 0.380, "#b4316f" }, { 0.580, "#ff8a3c" }, { 0.585, "#1e1530" }, { 1.000, "#2a1d3d" } },
	checkerrush = { { 0.000, "#16181d" }, { 1.000, "#16181d" } },
	ravelights = { { 0.000, "#07001a" }, { 0.550, "#1a0033" }, { 1.000, "#4a0072" } },
	warpspeed = { { 0.000, "#e3f6ff" }, { 0.180, "#6ec6ff" }, { 0.550, "#0a3d91" }, { 1.000, "#020b2a" } },
	polarglow = { { 0.000, "#020a1a" }, { 0.700, "#0b2e4a" }, { 1.000, "#12405e" } },
	midnightgrid = { { 0.000, "#0d0221" }, { 0.480, "#2a0845" }, { 0.550, "#ff2a6d" }, { 0.555, "#0d0221" }, { 1.000, "#0d0221" } },
	thunderroad = { { 0.000, "#05070d" }, { 0.550, "#1b2233" }, { 1.000, "#2c3850" } },
	inferno = { { 0.000, "#120300" }, { 0.500, "#4a0800" }, { 0.820, "#b32000" }, { 1.000, "#ff6a00" } },
	starwarp = { { 0.000, "#070320" }, { 1.000, "#070320" } },
	goldrush = { { 0.000, "#fff1b8" }, { 0.300, "#ffc93c" }, { 0.650, "#b8860b" }, { 1.000, "#3d2400" } },
	tiresmoke = { { 0.000, "#2a2f3a" }, { 0.560, "#4a5262" }, { 0.565, "#30343d" }, { 1.000, "#1c1f25" } },
	hazard = { { 0.000, "#3a3320" }, { 1.000, "#15130c" } },
	oceandrive = { { 0.000, "#4fc3f7" }, { 0.420, "#b3e5fc" }, { 0.500, "#ffe0b2" }, { 0.505, "#0288d1" }, { 1.000, "#01579b" } },
	snowday = { { 0.000, "#6f86b8" }, { 0.600, "#b9c8e6" }, { 0.610, "#eef3fb" }, { 1.000, "#dfe7f5" } },
	autumnlane = { { 0.000, "#ffb74d" }, { 0.450, "#ff8a50" }, { 0.700, "#8d3b1f" }, { 1.000, "#4e2412" } },
	dragtree = { { 0.000, "#253048" }, { 1.000, "#0c1020" } },
	bubblepop = { { 0.000, "#ffd1f0" }, { 0.500, "#c7b8ff" }, { 1.000, "#8fd3ff" } },
	pixelpark = { { 0.000, "#5c94fc" }, { 0.700, "#5c94fc" }, { 0.701, "#c84c0c" }, { 1.000, "#c84c0c" } },
	plasma = { { 0.000, "#10002b" }, { 1.000, "#10002b" } },
	lasergrid = { { 0.000, "#0a0006" }, { 1.000, "#1c0010" } },
	circuitry = { { 0.000, "#0c3b2a" }, { 1.000, "#04150f" } },
	deepsea = { { 0.000, "#0a6c8f" }, { 0.450, "#063a5e" }, { 1.000, "#021428" } },
	fireworks = { { 0.000, "#050816" }, { 0.700, "#0d1638" }, { 1.000, "#1e1440" } },
	comettrail = { { 0.000, "#2b1d5c" }, { 0.700, "#0b0820" }, { 1.000, "#0b0820" } },
	discoball = { { 0.000, "#3b1060" }, { 0.750, "#10041f" }, { 1.000, "#10041f" } },
	sakura = { { 0.000, "#2a1b3d" }, { 0.550, "#6b3f6b" }, { 1.000, "#f3a5c0" } },
	blackhole = { { 0.000, "#1a0f3a" }, { 0.750, "#020108" }, { 1.000, "#020108" } },
	magmacore = { { 0.000, "#1a0a06" }, { 0.500, "#3b0f05" }, { 1.000, "#160704" } },
	diamondrain = { { 0.000, "#2c5d8f" }, { 0.800, "#0a1830" }, { 1.000, "#0a1830" } },
	championlap = { { 0.000, "#6b4a00" }, { 0.750, "#1a1000" }, { 1.000, "#1a1000" } },
}

-- The card you're looking at stays picked while the page redraws; opening the tab starts on
-- the one you wear.
local pick: string? = nil
function CallCards.reset()
	pick = nil
end

local function worn(s: any): string
	return callCards.callCardOr(s.callCard)
end

-- A card's backdrop filling `parent`, with its icon glowing faintly in it.
-- `corner` puts the icon top left (the big card, where the car stands in the middle).
local function art(parent: GuiObject, id: string, iconSize: number, locked: boolean, corner: boolean?)
	local stops = ART[id] or ART.showroom
	local keys = {}
	for _, st in stops do
		table.insert(keys, ColorSequenceKeypoint.new(st[1], Color3.fromHex(st[2])))
	end
	local bg = Ui.new("Frame", { Name = "Art", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = parent.ZIndex, Parent = parent }, {
		Ui.new("UICorner", { CornerRadius = (parent:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius }),
		Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new(keys) }),
	})
	local def = callCards.callCardDef(id)
	Ui.text({ Text = def.icon, TextSize = iconSize, TextTransparency = if locked then 0.55 else 0.15, AnchorPoint = if corner then Vector2.zero else Vector2.new(0.5, 0.5), Position = if corner then UDim2.fromOffset(12, 10) else UDim2.fromScale(0.5, 0.42), Size = if corner then UDim2.fromOffset(iconSize, iconSize) else UDim2.fromScale(1, 0.8), ZIndex = parent.ZIndex, Parent = parent })
	if locked then
		-- The web dims and desaturates a card you don't have yet.
		Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#2b3140"), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = parent.ZIndex, Parent = parent }, {
			Ui.new("UICorner", { CornerRadius = (parent:FindFirstChildOfClass("UICorner") :: UICorner).CornerRadius }),
		})
	end
	return bg
end

-- The tab: `parent` is the page's content area (the race car turns on the left, Cars draws it),
-- `onCrates` takes you to the crate depot.
function CallCards.draw(parent: Instance, ctx: any, onCrates: () -> (), redraw: () -> ())
	local s = store.useGame.getState()
	local on = worn(s)
	local owned: { [string]: boolean } = {}
	local count = 0
	for _, id in callCards.ownedCallCards(s) do
		if not owned[id] then
			owned[id] = true
			count += 1
		end
	end
	if not pick or not callCards.callCardDef(pick) then
		pick = on
	end
	local chosen = pick :: string
	local d = callCards.callCardDef(chosen)

	local shadow = Ui.new("Frame", { Name = "Detail", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 16), Size = UDim2.new(0, 400, 1, -28), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 2, Parent = parent }, { Ui.corner(16) })
	local sheet = Ui.new("Frame", { Name = "Glass", Position = UDim2.fromOffset(0, -4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#f2f6fb"), BackgroundTransparency = 0.08, ZIndex = 2, Parent = shadow }, { Ui.corner(16) })
	local pad = Ui.new("Frame", { Position = UDim2.fromOffset(12, 12), Size = UDim2.new(1, -24, 1, -24), BackgroundTransparency = 1, ZIndex = 3, Parent = sheet })

	-- The big card with your race car standing on it.
	local hero = Ui.new("Frame", { Name = "Hero", Size = UDim2.new(1, 0, 0, 210), BackgroundColor3 = Color3.fromHex("#0b1430"), ClipsDescendants = true, ZIndex = 3, Parent = pad }, {
		Ui.corner(16),
		Ui.stroke(3, LINE),
	})
	art(hero, chosen, 40, false, true)
	Ui.new("Frame", { Name = "Edge", Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 1, ZIndex = 3, Parent = hero }, {
		Ui.corner(13),
		Ui.stroke(2, if d.tier then Color3.fromHex(EDGE[d.tier]) else Ui.WHITE, if d.tier then 0 else 0.84),
	})
	local car = raceCar.raceCarOf(s.cars, s.raceCar)
	if car then
		-- The pool of the card's light and the car's shadow on its ground.
		Ui.new("Frame", { Name = "Ground", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -34), Size = UDim2.fromOffset(250, 46), BackgroundColor3 = Color3.fromHex(car.color), BackgroundTransparency = 0.78, ZIndex = 3, Parent = hero }, { Ui.round() })
		Ui.new("Frame", { Name = "Shadow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -32), Size = UDim2.fromOffset(170, 22), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.55, ZIndex = 3, Parent = hero }, { Ui.round() })
		local v = Thumb.new("Cars", car.model, UDim2.new(1, -40, 0, 170), Color3.fromHex(car.color))
		v.Name = "Car"
		v.AnchorPoint = Vector2.new(0.5, 1)
		v.Position = UDim2.new(0.5, 0, 1, -10)
		v.ZIndex = 3
		v.Parent = hero
	end

	-- Its name and tier, and the button.
	Ui.text({ Name = "CardName", Text = d.name, TextSize = 20, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, 218), Size = UDim2.new(1, -130, 0, 24), ZIndex = 3, Parent = pad })
	if d.tier then
		local chip = Ui.new("Frame", { Name = "Tier", Position = UDim2.fromOffset(2, 244), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex(CHIP[d.tier]), ZIndex = 3, Parent = pad }, {
			Ui.corner(6),
			Ui.stroke(2, LINE),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }),
		})
		Ui.text({ Text = `{callCards.TIER_ICON[d.tier]} {callCards.TIER_NAME[d.tier]}`, Body = true, Weight = "heavy", TextSize = 11, TextColor3 = LINE, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = chip })
	end
	local go = { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 222), Size = UDim2.fromOffset(118, 40), Parent = pad }
	local _shadow, button
	if chosen == on then
		_shadow, button = Ui.buy(go, "✔ On", "grey", nil, 16)
	elseif owned[chosen] then
		_shadow, button = Ui.buy(go, "Equip", "green", function()
			local ok = Remote.act("equipCallCard", chosen)
			if ok then
				ctx.toast(`🃏 {d.name} on`)
				redraw()
			end
		end, 17)
	else
		_shadow, button = Ui.button(go, "ten", onCrates, { radius = 12, stroke = 2, drop = 2, dark = 0.2, strokeColor = Color3.fromHex("#4a148c"), text = "🔒 📦 Crates", textSize = 15, textShadow = 1.5 })
	end
	button.Name = "Go"
	button.ZIndex = 3

	Ui.text({ Name = "Count", Text = `🃏 {count}/{#callCards.CALL_CARDS}`, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(2, 272), Size = UDim2.new(1, 0, 0, 18), ZIndex = 3, Parent = pad })

	-- Every card, as a still swatch.
	local list = Ui.scroller({ Name = "Cards", Position = UDim2.fromOffset(0, 296), Size = UDim2.new(1, 0, 1, -296), ZIndex = 3, Parent = pad })
	Ui.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = list })
	Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(80, 96), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	for i, c in callCards.CALL_CARDS do
		local have = owned[c.id] == true
		local sel = c.id == chosen
		local b = Ui.new("TextButton", { Name = c.id, Text = "", AutoButtonColor = false, LayoutOrder = i, BackgroundColor3 = Color3.fromHex("#0b1430"), ClipsDescendants = true, ZIndex = 3, Parent = list }, {
			Ui.corner(12),
			Ui.stroke(if sel then 3 else 2.5, if sel then Color3.fromHex("#ffd43b") else LINE),
		})
		art(b, c.id, 34, not have)
		if c.tier then
			Ui.new("Frame", { Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 1, ZIndex = 3, Parent = b }, {
				Ui.corner(10),
				Ui.stroke(2, Color3.fromHex(EDGE[c.tier])),
			})
		end
		local foot = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 3, Parent = b }, {
			Ui.new("UIGradient", { Rotation = 90, Color = Ui.seq("#060a1a", "#060a1a"), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.15), NumberSequenceKeypoint.new(1, 0.15) }) }),
		})
		Ui.text({ Text = c.name, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(3, 8), Size = UDim2.new(1, -6, 0, 16), ZIndex = 3, Parent = foot })
		local mark = if c.id == on then "✔" elseif have then "" else "🔒"
		if mark ~= "" then
			Ui.text({ Name = "Mark", Text = mark, TextSize = 14, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(20, 20), ZIndex = 3, Parent = b })
		end
		b.Activated:Connect(function()
			pick = c.id
			redraw()
		end)
	end
end

return CallCards
