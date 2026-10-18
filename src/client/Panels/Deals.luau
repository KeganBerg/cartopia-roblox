--!strict
-- Daily Deals, as the web game's DealsPanel (ui/Deals.tsx): three discounted items a day, the same
-- for every player, one from each slot (Supplies, Car shop, Town). Each can be used once. Parts
-- and fuel are bought here (buyDeal); a decor deal goes straight to placing it, at its deal price;
-- a mod or paint deal goes to the garage, where that part or finish is on sale.
-- Also the HUD's price-tag button with the number of deals still open today (DealsButton).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint) :: any
local Client = script.Parent.Parent
local Remote = require(Client.Remote)
local Ui = require(Client.Ui)
local Thumb = require(Client.Thumb)
local Placement = require(Client.Placement)

local Deals = {}
Deals.id = "deals"

local LINE = Ui.LINE

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

-- Countdown as the web's left(): 45m, 3h 20m, 5h.
local function left(ms: number): string
	local m = math.max(1, math.ceil(ms / 60000))
	if m >= 60 then
		return `{m // 60}h` .. (if m % 60 > 0 then ` {m % 60}m` else "")
	end
	return `{m}m`
end

-- A price as the web's cost(): $1,200 + 💎 10 + 5⚙, or Free.
local function cost(c: any, parts: number?): string
	local bits = {}
	if (c.coins or 0) > 0 then
		table.insert(bits, `${Ui.commas(c.coins)}`)
	end
	if (c.bucks or 0) > 0 then
		table.insert(bits, `💎 {c.bucks}`)
	end
	if (parts or 0) > 0 then
		table.insert(bits, `{parts}⚙`)
	end
	return if #bits > 0 then table.concat(bits, " + ") else "Free"
end

-- A button in the web's .buy colours: green, purple (.premium, gem prices) or blue (.owned).
local KINDS = {
	green = { colors = "green", edge = "#1d6b22" },
	premium = { colors = "ten", edge = "#4a148c" },
	owned = { colors = "gem", edge = "#0d3c78" },
}
local function button(props: { [string]: any }, text: string, kind: string, onClick: (() -> ())?): Frame
	local k = KINDS[kind] or KINDS.green
	local shadow = Ui.button(props, k.colors, onClick, {
		radius = 12,
		stroke = 2,
		drop = 2,
		dark = 0.2,
		strokeColor = Color3.fromHex(k.edge),
		text = text,
		textSize = 14,
		textShadow = 1.5,
		textStrokeColor = Color3.fromHex("#0f2a12"),
	})
	return shadow
end

-- The deal's picture: the building, your first car with the part or finish, or the icon.
local function art(parent: Instance, deal: any, offer: any)
	local s = store.useGame.getState()
	if deal.kind == "decor" then
		local pic = Thumb.new("Buildings", deal.item or "", UDim2.fromScale(1, 1))
		pic.ZIndex = 3
		pic.Parent = parent
		return
	end
	local car = s.cars[1]
	if (deal.kind == "mod" or deal.kind == "paint") and car then
		local job = table.clone(Paint.jobOf(car))
		if deal.kind == "paint" then
			job.finish = deal.item
		end
		local mods = if deal.kind == "mod" then { deal.item } else car.mods
		local pic = Thumb.car(car.model, UDim2.fromScale(1, 1), job, nil, mods)
		pic.ZIndex = 3
		pic.Parent = parent
		if deal.kind == "mod" then
			-- The part's meshes load the first time a car needs them: draw it again once they're in.
			task.spawn(function()
				Remote.meshesFor(car.model)
				if pic.Parent then
					pic:Destroy()
					local again = Thumb.car(car.model, UDim2.fromScale(1, 1), job, nil, mods)
					again.ZIndex = 3
					again.Parent = parent
				end
			end)
		end
		return
	end
	-- The parts gear as the emoji, which every device draws.
	Ui.text({ Text = if offer.icon == "⚙" then "⚙️" else offer.icon, TextSize = 40, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = parent })
end

-- What a deal's button does, as go() in DealCard.
local function go(ctx: any, deal: any, offer: any)
	local s = store.useGame.getState()
	if deal.kind == "parts" or deal.kind == "fuel" then
		Remote.act("buyDeal", deal.id)
		return
	end
	if deal.kind == "decor" then
		if s.coins < offer.now.coins then
			ctx.open("need", { res = "coins", missing = offer.now.coins - s.coins, what = offer.name })
		elseif s.bucks < offer.now.bucks then
			ctx.open("need", { res = "bucks", missing = offer.now.bucks - s.bucks, what = offer.name })
		else
			ctx.close()
			Placement.place(deal.item or "", ctx.gui, ctx)
		end
		return
	end
	if #s.cars == 0 then
		ctx.toast("Get a car first")
		return
	end
	ctx.open("garage")
	ctx.toast(if deal.kind == "mod" then `Pick a car, then the {offer.name} is on sale in Mods` else `Pick a car, then {offer.name} is on sale in Paint`)
end

local CARD_H = 206

local function card(parent: Instance, ctx: any, order: number, deal: any, slot: string)
	local s = store.useGame.getState()
	local o = data.dealOffer(deal)
	local used = store.dealUsed(s, deal.id)
	local locked = s.level < o.unlockLevel
	local gem = data.GEM_BUILD_COINS
	local pct = math.round((1 - (o.now.coins + o.now.bucks * gem) / math.max(1, o.was.coins + o.was.bucks * gem)) * 100)
	local box = Ui.new("Frame", {
		Name = deal.id,
		LayoutOrder = order,
		BackgroundColor3 = Ui.WHITE,
		ZIndex = 2,
		Parent = parent,
	}, {
		Ui.corner(14),
		Ui.stroke(2, Color3.fromHex(if used then "#e0e0e0" else "#ffcc80")),
	})
	-- Used deals fade (opacity .6), locked ones go grey.
	local fade = if used then 0.4 elseif locked then 0.25 else 0
	Ui.text({ Text = string.upper(slot), TextSize = 12, TextColor3 = Color3.fromHex("#8d6e63"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 15), ZIndex = 3, Parent = box })
	if not used then
		local w = Ui.textWidth(`-{pct}%`, 13) + 14
		local off = Ui.new("Frame", { Name = "Off", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -9), Size = UDim2.fromOffset(w, 20), Rotation = 6, BackgroundColor3 = Color3.fromHex("#e53935"), ZIndex = 5, Parent = box }, {
			Ui.corner(10),
		})
		Ui.new("Frame", { Position = UDim2.fromOffset(0, 2), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.75, ZIndex = 4, Parent = off }, { Ui.corner(10) })
		Ui.text({ Text = `-{pct}%`, TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 6, Parent = off })
	end
	local pic = Ui.new("Frame", { Name = "Art", Position = UDim2.fromOffset(6, 22), Size = UDim2.new(1, -12, 0, 72), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 3, Parent = box })
	art(pic, deal, o)
	Ui.text({ Name = "DealName", Text = o.name, TextSize = 15, TextColor3 = LINE, TextWrapped = true, Position = UDim2.fromOffset(6, 98), Size = UDim2.new(1, -12, 0, 34), ZIndex = 3, Parent = box })
	Ui.text({
		Name = "Cost",
		Text = `<font color="#9e9e9e"><s>{cost(o.was, o.parts)}</s></font> <font color="#2e7d32">{cost(o.now, o.parts)}</font>`,
		RichText = true,
		Body = true,
		Weight = "heavy",
		TextSize = 13,
		TextColor3 = Color3.fromHex("#2e7d32"),
		TextWrapped = true,
		Position = UDim2.fromOffset(4, 134),
		Size = UDim2.new(1, -8, 0, 32),
		ZIndex = 3,
		Parent = box,
	})
	local at = { Name = "Go", Position = UDim2.new(0, 6, 1, -38), Size = UDim2.new(1, -12, 0, 30), ZIndex = 3, Parent = box }
	if used then
		-- Disabled on the web: a plain face, not a button.
		local _, face = Ui.shadowed(at, { radius = 12, stroke = 2, drop = 2, dark = 0.2, colors = KINDS.owned.colors, strokeColor = Color3.fromHex(KINDS.owned.edge) })
		Ui.text({ Text = "✔ Got it", TextSize = 14, Size = UDim2.fromScale(1, 1), Shadow = 1.5, ZIndex = 4, Parent = face })
	elseif locked then
		local b = Ui.new("TextButton", { Name = "Go", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = at.Position, Size = at.Size, ZIndex = 3, Parent = box })
		Ui.text({ Text = `🔒 Level {o.unlockLevel}`, TextSize = 15, TextColor3 = Color3.fromHex("#8d5a00"), Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = b })
		b.Activated:Connect(function()
			ctx.open("need", { res = "level", missing = o.unlockLevel, what = o.name })
		end)
	else
		local label = if deal.kind == "parts" or deal.kind == "fuel" then "Buy" elseif deal.kind == "decor" then "Place" else "Use"
		button(at, label, if o.now.bucks > 0 then "premium" else "green", function()
			go(ctx, deal, o)
		end)
	end
	if fade > 0 then
		-- A veil in the sheet's colour over the card stands in for the web's opacity and grayscale.
		Ui.new("Frame", { Name = "Veil", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 1 - fade, ZIndex = 7, Active = false, Parent = box }, { Ui.corner(14) })
	end
end

function Deals.open(ctx: any): Instance
	local overlay, _, body = Ui.panel(ctx.gui, "🏷️ Daily Deals", { width = 460, height = 61 + 10 + CARD_H + 12 + 26 + 18, onClose = ctx.close })
	local grid = Ui.new("Frame", { Name = "Deals", Position = UDim2.fromOffset(0, 9), Size = UDim2.new(1, 0, 0, CARD_H), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 1, 0), CellPadding = UDim2.fromOffset(8, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local foot = Ui.text({ Name = "Foot", Text = "", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex("#546e7a"), Position = UDim2.fromOffset(0, 9 + CARD_H + 10), Size = UDim2.new(1, 0, 0, 18), Parent = body })
	local function render()
		for _, c in grid:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local slots = data.DEAL_SLOTS
		for i, d in data.dealsFor(store.today()) do
			card(grid, ctx, i, d, slots[i].name)
		end
		Ui.setText(foot, `⏱ New deals in {left(data.msToNextDay(now()))}`)
	end
	render()
	local conn = Remote.changed:Connect(render)
	overlay.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return overlay
end

-- The HUD's Daily Deals button (DealsButton): a price tag, with the number of deals still open.
-- Shown from level 3, as the web's 'season' unlock. Returns the refresh the HUD runs.
Deals.hudOrder = 4
function Deals.hudButton(row: Instance, ctx: any): (any) -> ()
	local slot = Ui.new("Frame", { Name = "Deals", Size = UDim2.fromOffset(40, 43), BackgroundTransparency = 1, LayoutOrder = Deals.hudOrder, Parent = row })
	local _, face = Ui.button({ Name = "DealsButton", Position = UDim2.fromOffset(2.5, 5.5), Size = UDim2.fromOffset(35, 35), Parent = slot }, "white", function()
		ctx.open("deals")
	end, { radius = 12, stroke = 2.5, drop = 3, split = 0.5, flat = true })
	-- The tag: a body with a pointed end and a hole, tilted like the web's icon.
	local tag = Ui.new("Frame", { Name = "Tag", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 13), Rotation = 45, BackgroundTransparency = 1, Parent = face })
	Ui.new("Frame", { Position = UDim2.fromOffset(5, 0), Size = UDim2.fromOffset(15, 13), BackgroundColor3 = Ui.BLUE, BorderSizePixel = 0, Parent = tag }, { Ui.corner(3) })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(6.5, 6.5), Size = UDim2.fromOffset(9.2, 9.2), Rotation = 45, BackgroundColor3 = Ui.BLUE, BorderSizePixel = 0, Parent = tag }, { Ui.corner(2) })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(7, 6.5), Size = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.fromHex("#f3f7fc"), BorderSizePixel = 0, ZIndex = 2, Parent = tag }, { Ui.round() })
	local badge = Ui.new("Frame", { Name = "Badge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromHex("#e53935"), Visible = false, ZIndex = 3, Parent = face }, { Ui.corner(10), Ui.stroke(2, Ui.WHITE) })
	local badgeText = Ui.text({ Text = "", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = badge })
	return function(s: any)
		slot.Visible = s.level >= 3
		local n = if slot.Visible then store.openDeals(s) else 0
		badge.Visible = n > 0
		Ui.setText(badgeText, tostring(n))
	end
end

return Deals
