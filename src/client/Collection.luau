--!strict
-- The collection book, as the web game's CollectionBook (ui/Collection.tsx): every car grouped
-- into sets. Owned cars show in their colours, missing ones as dark silhouettes with where to find
-- them. A full set pays a one-time reward, claimed here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local resto = require(Game.resto) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)
local BuildArt = require(script.Parent.BuildArt)

local Collection = {}

local LINE = Ui.LINE
local GREY = Color3.fromHex("#90a4ae")

local function car(parent: Instance, order: number, model: string, mine: any, restoParts: { string }, onFind: (string) -> ())
	local def = data.carDef(model)
	local b = Ui.new(if mine then "Frame" else "TextButton", {
		LayoutOrder = order,
		BackgroundColor3 = Color3.fromHex("#f7f9fb"),
		ZIndex = 3,
		Parent = parent,
	}, { Ui.corner(10), Ui.stroke(1, Color3.fromHex("#eceff1")) })
	if not mine then
		(b :: TextButton).Text = "";
		(b :: TextButton).AutoButtonColor = false;
		(b :: TextButton).Activated:Connect(function()
			onFind(model)
		end)
	end
	local box = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(80, 62), BackgroundColor3 = if mine then Color3.fromHex("#e9f1fb") else Color3.fromHex("#eceff1"), ZIndex = 3, Parent = b }, { Ui.corner(8) })
	if not mine and def.secret then
		-- A resto-mod still to build: its puzzle, with the pieces held in colour.
		BuildArt.new(box, model, resto.piecesOf(restoParts, model), UDim2.fromScale(1, 1), { z = 3 })
	else
		local pic = Thumb.new("Cars", model, UDim2.fromScale(1, 1), Color3.fromHex(if mine then mine.color else "#37474f"))
		pic.ZIndex = 3
		if not mine then
			-- A silhouette: the car drawn black and faint.
			pic.ImageColor3 = Ui.BLACK
			pic.ImageTransparency = 0.72
		end
		pic.Parent = box
	end
	Ui.text({ Text = def.name, TextSize = 12, TextColor3 = if mine then LINE else GREY, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, 68), Size = UDim2.new(1, -4, 0, 15), ZIndex = 3, Parent = b })
	if not mine then
		local src = if def.secret then { icon = "🧩", text = `{#resto.piecesOf(restoParts, model)}/{resto.PIECE_COUNT}` } else data.carSource(def)
		Ui.text({ Text = `{src.icon} {src.text}`, Body = true, Weight = "heavy", TextSize = 10, TextColor3 = if def.secret then Color3.fromHex("#00838f") else Ui.BLUE, TextWrapped = true, Position = UDim2.fromOffset(2, 84), Size = UDim2.new(1, -4, 0, 26), ZIndex = 3, Parent = b })
	end
end

-- Draws the book into `parent` (the Cars page's content area). onFind: a missing car was tapped.
function Collection.draw(parent: Instance, ctx: any, onFind: (string) -> ())
	local s = store.useGame.getState()
	local owned: { [string]: any } = {}
	for _, c in s.cars do
		owned[c.model] = owned[c.model] or c
	end
	local claimed: { [string]: boolean } = {}
	for _, id in s.claimedSets or {} do
		claimed[id] = true
	end
	local total = 0
	for _, def in data.CARS do
		if owned[def.id] then
			total += 1
		end
	end
	local doneSets = 0
	for _, set in data.CAR_SETS do
		if claimed[set.id] then
			doneSets += 1
		end
	end

	-- A light sheet over the showroom, like the web's book page.
	local shadow = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.new(1, -24, 1, -20), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.75, ZIndex = 2, Parent = parent }, {
		Ui.corner(16),
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(900, math.huge) }),
	})
	local sheet = Ui.new("Frame", { Position = UDim2.fromOffset(0, -4), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#f2f6fb"), ZIndex = 2, Parent = shadow }, { Ui.corner(16) })
	-- Progress: cars found and sets claimed.
	local head = Ui.new("Frame", { Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -28, 0, 26), BackgroundTransparency = 1, ZIndex = 3, Parent = sheet })
	Ui.text({ Text = `📖 {total} / {#data.CARS}`, TextSize = 16, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0, 110, 1, 0), ZIndex = 3, Parent = head })
	local bar = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 116, 0.5, 0), Size = UDim2.new(1, -216, 0, 10), BackgroundColor3 = Ui.SEG, ZIndex = 3, Parent = head }, { Ui.round() })
	Ui.new("Frame", { Size = UDim2.fromScale(total / math.max(1, #data.CARS), 1), BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = bar }, {
		Ui.round(),
		Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromHex("#ffb300"), Color3.fromHex("#ff7043")) }),
	})
	Ui.text({ Text = `{doneSets} / {#data.CAR_SETS} sets`, TextSize = 13, TextColor3 = Color3.fromHex("#607d8b"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 92, 1, 0), ZIndex = 3, Parent = head })

	local list = Ui.scroller({ Position = UDim2.fromOffset(10, 44), Size = UDim2.new(1, -20, 1, -54), ZIndex = 3, Parent = sheet })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	Ui.new("UIPadding", { PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), Parent = list })

	for i, set in data.CAR_SETS do
		local have = data.setOwned(set, s.cars)
		local done = claimed[set.id] == true
		local ready = not done and have == #set.cars
		local box = Ui.new("Frame", {
			LayoutOrder = i,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = if done then Color3.fromHex("#f1f8e9") else Ui.WHITE,
			ZIndex = 3,
			Parent = list,
		}, {
			Ui.corner(12),
			Ui.stroke(if ready then 3 else 1.5, Color3.fromHex(if ready then "#ffb300" elseif done then "#c5e1a5" else "#dfe5ea")),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }),
			Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local header = Ui.new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, ZIndex = 3, Parent = box })
		Ui.text({ Text = set.icon, TextSize = 20, Size = UDim2.fromOffset(28, 30), ZIndex = 3, Parent = header })
		local name = Ui.text({ Text = `{set.name} <font size="13" color="#78909c">{have}/{#set.cars}</font>`, RichText = true, TextSize = 16, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -330, 1, 0), ZIndex = 3, Parent = header })
		name.RichText = true
		local reward = Ui.text({
			Text = `💰{Ui.commas(set.coins)}  <font color="#2e7d32">💎{set.bucks}</font>  🏆{set.trophies}`,
			RichText = true,
			TextSize = 13,
			TextColor3 = Color3.fromHex("#546e7a"),
			TextTransparency = if done then 0.5 else 0,
			TextXAlignment = Enum.TextXAlignment.Right,
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -86, 0, 0),
			Size = UDim2.fromOffset(200, 30),
			ZIndex = 3,
			Parent = header,
		})
		reward.RichText = true
		if done then
			Ui.text({ Text = "✔", TextSize = 18, TextColor3 = Color3.fromHex("#2e7d32"), AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(80, 30), ZIndex = 3, Parent = header })
		elseif ready then
			Ui.buy({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(80, 30), ZIndex = 3, Parent = header }, "Claim!", "green", function()
				local ok = Remote.act("claimSet", set.id)
				if ok then
					ctx.toast(`{set.icon} {set.name} complete!`)
				end
			end, 15)
		end
		local grid = Ui.new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3, Parent = box }, {
			Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(96, 112), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for j, model in set.cars do
			car(grid, j, model, owned[model], s.restoParts or {}, onFind)
		end
	end
end

return Collection
