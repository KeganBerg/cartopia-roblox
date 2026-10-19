--!strict
-- The purchase splash (ui/PurchaseSplash.tsx, purchase.css): once Roblox's prompt is paid and the
-- server has added the pack, "Purchase successful!" over a green check badge, the pack's name, then
-- each pack bought (the last three) as a card with what it paid, gems, coins and parts the same
-- size, and the gems flying out of it. It reuses the level-up splash with a check badge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local packs = require(Game.bucksPacks) :: any
local Ui = require(script.Parent.Parent.Ui)
local Icons = require(script.Parent.Parent.Icons)
local Remote = require(script.Parent.Parent.Remote)
local Sfx = require(script.Parent.Parent.Sounds.Sfx)
local Kit = require(script.Parent.Kit)

local Bought = {}

local GREEN = Color3.fromHex("#2e7d32")

local function tween(inst: Instance, t: number, props: { [string]: any }, delay: number?, style: Enum.EasingStyle?)
	pcall(function()
		TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, delay or 0), props):Play()
	end)
end

local function packName(id: string): string?
	for _, p in packs.ALL_PACKS do
		if p.id == id then
			return p.name
		end
	end
	return nil
end

-- One thing a pack paid (.buy-item): its icon in a circle and the amount under it.
local function item(parent: Instance, order: number, icon: (Frame) -> (), amount: string, bg: string)
	local f = Ui.new("Frame", { Name = "Item", Size = UDim2.fromOffset(80, 96), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	local disc = Ui.new("Frame", { Name = "Icon", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(56, 56), BackgroundColor3 = Color3.fromHex(bg), Parent = f }, { Ui.round(), Ui.stroke(3, Ui.LINE) })
	icon(disc)
	Ui.text({ Name = "Amount", Text = amount, TextSize = 26, TextColor3 = Color3.fromHex("#263238"), Position = UDim2.fromOffset(-6, 62), Size = UDim2.new(1, 12, 0, 32), Parent = f })
end

local function emoji(text: string): (Frame) -> ()
	return function(disc: Frame)
		Ui.text({ Text = text, TextSize = 30, Size = UDim2.fromScale(1, 1), Parent = disc })
	end
end

local function show(ctx: any, rows: { any }, done: () -> ())
	local overlay: Instance
	local function close()
		if overlay.Parent == nil then
			return
		end
		overlay:Destroy()
		-- Packs paid while this showed get their own turn.
		local now = store.useGame.getState().bought
		if now == rows then
			store.useGame.setState({ bought = {} })
		end
		done()
	end
	overlay = Kit.overlay(ctx, true, close)
	task.delay(0.25, function()
		if overlay.Parent ~= nil then
			Sfx.rescue.fanfare(true)
		end
	end)
	local shown = {}
	for i = math.max(1, #rows - 2), #rows do
		table.insert(shown, rows[i])
	end
	local anyCar = false
	for _, r in shown do
		if r.car then
			anyCar = true
		end
	end
	local title = if #rows > 1 then `{#rows} packs` else (packName(rows[1].pack) or "Gem pack")
	local packH = 128 + (if anyCar then 112 else 0)
	local W = math.max(460, #shown * 276 + 40)
	local h = 66 + 50 + 32 + 10 + packH + 18 + 46 + 18
	local _, card = Kit.card(overlay, W, h, 24)

	-- The badge: green, gold-ringed, half above the card, the tick drawing in.
	local badge = Ui.new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, -4), Size = UDim2.fromOffset(112, 112), BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = card }, {
		Ui.round(),
		Ui.stroke(5, Kit.GOLD),
		Ui.new("UIGradient", { Rotation = 60, Color = Ui.seq("#81e27f", "#2e7d32") }),
	})
	Ui.new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -16, 1, -16), BackgroundTransparency = 1, ZIndex = 3, Parent = badge }, {
		Ui.round(),
		Ui.stroke(3, Ui.WHITE, 0.55),
	})
	local check = Icons.draw("check", badge, 64, Ui.WHITE, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	check.Name = "Check"
	check.ZIndex = 4
	local checkScale = Ui.new("UIScale", { Scale = 0, Parent = check })
	tween(checkScale, 0.45, { Scale = 1 }, 0.75, Enum.EasingStyle.Back)

	local y = 66
	Kit.title(card, "Purchase successful!", y, 36, GREEN)
	y += 50
	Kit.line(card, title, y, 22, Color3.fromHex("#37474f"), true)
	y += 42

	-- The packs, side by side, popping in one after another.
	local row = Ui.new("Frame", { Name = "Packs", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, packH), BackgroundTransparency = 1, Parent = card }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, r in shown do
		local slot = Ui.new("Frame", { Name = `Pack{i}`, Size = UDim2.fromOffset(264, packH), BackgroundTransparency = 1, LayoutOrder = i, Parent = row })
		local packCard = Ui.new("Frame", { Name = "Card", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, Parent = slot }, {
			Ui.corner(18),
			Ui.stroke(4, Kit.GOLD),
			Ui.new("UIGradient", { Rotation = 70, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromHex("#fffde7")), ColorSequenceKeypoint.new(0.45, Color3.fromHex("#ffffff")), ColorSequenceKeypoint.new(1, Color3.fromHex("#e1f5fe")) }) }),
		})
		local pop = Ui.new("UIScale", { Scale = 0.6, Parent = packCard })
		packCard.Rotation = -6
		packCard.Position = UDim2.new(0.5, 0, 0.5, 30)
		local delay = 1.25 + (i - 1) * 0.15
		tween(pop, 0.6, { Scale = 1 }, delay, Enum.EasingStyle.Back)
		tween(packCard, 0.6, { Rotation = 0, Position = UDim2.fromScale(0.5, 0.5) }, delay, Enum.EasingStyle.Back)
		local top = 14
		if r.car then
			local def = data.carDef(r.car)
			local pic = Kit.carThumb(r.car, UDim2.fromOffset(150, 80), def.colors[1])
			pic.Name = "Car"
			pic.AnchorPoint = Vector2.new(0.5, 0)
			pic.Position = UDim2.new(0.5, 0, 0, 8)
			pic.Parent = packCard
			Ui.text({ Name = "CarName", Text = def.name, TextSize = 19, TextColor3 = Color3.fromHex("#263238"), Position = UDim2.fromOffset(0, 88), Size = UDim2.new(1, 0, 0, 22), Parent = packCard })
			top += 112
		end
		local items = Ui.new("Frame", { Name = "Items", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 0, 96), BackgroundTransparency = 1, Parent = packCard }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		item(items, 1, emoji("💎"), Ui.commas(r.bucks), "#e1f5fe")
		if (r.coins or 0) > 0 then
			item(items, 2, function(disc)
				Icons.draw("coin", disc, 40, nil, nil, UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
			end, Ui.commas(r.coins), "#fff8e1")
		end
		if (r.parts or 0) > 0 then
			item(items, 3, emoji("⚙️"), Ui.commas(r.parts), "#eceff1")
		end
		-- The gems flying up out of the card.
		for k = 0, 6 do
			local gem = Ui.text({ Name = "Fly", Text = "💎", TextSize = 22, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(28, 28), TextTransparency = 1, ZIndex = 5, Parent = slot })
			task.delay(delay + 0.5 + k * 0.06, function()
				if gem.Parent == nil then
					return
				end
				gem.TextTransparency = 0
				tween(gem, 1, { Position = UDim2.new(0.5, (k - 3) * 30, 0.3, -110), Rotation = (k - 3) * 20, TextTransparency = 1 })
			end)
		end
	end
	y += packH + 18
	Kit.button(card, "Continue", 0, y, 180, 44, "green", close)
end

function Bought.start(ctx: any)
	local function look()
		local rows = store.useGame.getState().bought
		if type(rows) == "table" and #rows > 0 then
			Kit.push(ctx, "bought", 0, function(done)
				local now = store.useGame.getState().bought
				if type(now) ~= "table" or #now == 0 then
					done()
					return
				end
				show(ctx, now, done)
			end)
		end
	end
	Remote.changed:Connect(look)
	look()
end

return Bought
