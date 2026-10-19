--!strict
-- The Cars page's Call Cards tab (the web's CallCardPicker): your race car standing on the card
-- you picked, big, then every card as a small swatch. Owned cards equip with one tap; the rest
-- show a lock and send you to the crates they drop from.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local callCards = require(Game.callCards) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local CallCardArt = require(script.Parent.CallCardArt)

local CallCards = {}

local LINE = Ui.LINE
local CHIP = { rare = "#e1f5fe", epic = "#ede7f6", legendary = "#fff8e1" }

-- The card you're looking at stays picked while the page redraws; opening the tab starts on
-- the one you wear.
local pick: string? = nil
function CallCards.reset()
	pick = nil
end

local function worn(s: any): string
	return callCards.callCardOr(s.callCard)
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

	-- The big card with your race car standing on it (CallCardShowcase).
	local hero = Ui.new("Frame", { Name = "Hero", Size = UDim2.new(1, 0, 0, 210), BackgroundColor3 = Color3.fromHex("#0b1430"), ZIndex = 3, Parent = pad }, {
		Ui.corner(16),
		Ui.stroke(3, LINE),
	})
	CallCardArt.showcase(hero, chosen, { aspect = 376 / 210 })

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
		-- (A card you don't have yet is greyed, as the web's saturate(.35) brightness(.6).)
		CallCardArt.scene(b, c.id, { still = true, locked = not have, aspect = 80 / 96 })
		CallCardArt.frame(b, c.id, 0, 10)
		local foot = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 4, Parent = b }, {
			Ui.new("UIGradient", { Rotation = 90, Color = Ui.seq("#060a1a", "#060a1a"), Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.15), NumberSequenceKeypoint.new(1, 0.15) }) }),
		})
		Ui.text({ Text = c.name, TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(3, 8), Size = UDim2.new(1, -6, 0, 16), ZIndex = 4, Parent = foot })
		local mark = if c.id == on then "✔" elseif have then "" else "🔒"
		if mark ~= "" then
			Ui.text({ Name = "Mark", Text = mark, TextSize = 14, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(20, 20), ZIndex = 6, Parent = b })
		end
		b.Activated:Connect(function()
			pick = c.id
			redraw()
		end)
	end
end

return CallCards
