--!strict
-- Your reputation title for the Race menu's header (ui/Reputation.tsx RepChip): its icon and
-- name, and a little bar to the next title, in the menu's head chip (.rm-head-chip, .rep-chip).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local reputation = require(Game.reputation) :: any
local Ui = require(script.Parent.Ui)

local RepChip = {}

-- Your reputation as it stands now (Reputation.tsx useRep).
function RepChip.rep(): any
	local s = store.useGame.getState()
	return reputation.reputation({ trophies = s.trophies, stats = s.stats, cups = s.cups, mastery = s.mastery })
end

function RepChip.draw(parent: Instance): Frame
	local r = RepChip.rep()
	local text = `{r.title.icon} {r.title.name}`
	local tw = math.ceil(Ui.textWidth(text, 13) * 1.05)
	local chip = Ui.new("Frame", { Name = "RepChip", LayoutOrder = 1, Size = UDim2.fromOffset(tw + 44 + 6 + 22, 26), BackgroundColor3 = Color3.fromHex("#0a1e46"), BackgroundTransparency = 0.65, Parent = parent }, {
		Ui.round(),
		Ui.stroke(2, Ui.LINE, 0.45),
	})
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(11, 0), Size = UDim2.new(0, tw, 1, 0), Shadow = 1, ShadowTransparency = 0.6, ShadowColor = Ui.BLACK, Parent = chip })
	local bar = Ui.new("Frame", { Name = "RepBar", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 11 + tw + 6, 0.5, 0), Size = UDim2.fromOffset(44, 6), BackgroundColor3 = Ui.LINE, BackgroundTransparency = 0.82, ClipsDescendants = true, Parent = chip }, { Ui.corner(3) })
	Ui.new("Frame", { Size = UDim2.fromScale(math.clamp(r.frac, 0, 1), 1), BackgroundColor3 = Color3.fromHex("#ffb300"), BorderSizePixel = 0, Parent = bar }, { Ui.corner(3) })
	return chip
end

return RepChip
