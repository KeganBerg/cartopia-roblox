--!strict
-- Welcome back (ui/WelcomeBack.tsx, panel "welcome"): how long you were away and what finished
-- meanwhile (jobs, obstacles cleared, cars the Gas Station filled, a car Rusty restored), with
-- Collect all. Opened by Popups/Welcome; arg: how long they were away, in ms.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local Remote = require(script.Parent.Parent.Remote)

local Welcome = {}
Welcome.id = "welcome"

local INK = Ui.INK
local MUTED = Color3.fromHex("#546e7a")

function Welcome.awayText(ms: number): string
	local m = math.floor(ms / 60000)
	if m < 60 then
		return `{m}m`
	end
	local h = m // 60
	if h < 24 then
		return if m % 60 > 0 then `{h}h {m % 60}m` else `{h}h`
	end
	local d = h // 24
	return if h % 24 > 0 then `{d}d {h % 24}h` else `{d}d`
end

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

-- Whether a menu "daily" exists on Roblox yet (client/Panels), to hand over to after this.
local function hasPanel(id: string): boolean
	for _, m in script.Parent:GetChildren() do
		if m:IsA("ModuleScript") and m ~= script then
			local ok, mod = pcall(require, m)
			if ok and type(mod) == "table" and (mod :: any).id == id then
				return true
			end
		end
	end
	return false
end

-- Something waiting is what makes a welcome worth showing.
function Welcome.hasNews(s: any, t: number): boolean
	local r = store.readyRewards(s, t)
	return r.collected + r.cleared + r.filled > 0 or (s.restoring ~= nil and t >= s.restoring.endsAt) or (s.restoring2 ~= nil and t >= s.restoring2.endsAt)
end

function Welcome.open(ctx: any, away: any?): Instance?
	local s = store.useGame.getState()
	local t = now()
	local r = store.readyRewards(s, t)
	local restored = if s.restoring and t >= s.restoring.endsAt then data.carDef(s.restoring.model) else nil
	local some = r.collected + r.cleared + r.filled > 0
	-- Closing hands over to the daily bonus if it hasn't been claimed yet.
	local function close()
		if s.lastDaily ~= store.today() and hasPanel("daily") then
			ctx.open("daily")
		else
			ctx.close()
		end
	end
	-- A save can load with nothing waiting: step aside instead of showing an empty welcome.
	if not some and not restored then
		task.defer(close)
		return nil
	end

	local rows: { { thumb: string?, icon: string?, name: string, stat: string, price: string? } } = {}
	for _, j in r.jobs do
		local d = data.buildingDef(j.def)
		table.insert(rows, { thumb = d.id, name = d.name, stat = `{j.n} job{if j.n > 1 then "s" else ""} finished`, price = `$ {Ui.commas(j.coins)}` })
	end
	if r.cleared > 0 then
		table.insert(rows, { icon = "🪓", name = `{r.cleared} obstacle{if r.cleared > 1 then "s" else ""} cleared`, stat = "More room to build" })
	end
	if r.filled > 0 then
		table.insert(rows, { icon = "⛽", name = `{r.filled} car{if r.filled > 1 then "s" else ""} out of gas`, stat = "Your Gas Station fills them up" })
	end
	if restored then
		table.insert(rows, { icon = "🔧", name = `Rusty restored your {restored.name}`, stat = "Give it a plate to drive it" })
	end
	if s.fuel >= store.fuelCap(s) then
		table.insert(rows, { icon = "⛽", name = "Fuel tank refilled", stat = "Ready for more jobs" })
	end
	local chips: { string } = {}
	local welcome = (s.boosts and s.boosts.welcome) or 0
	local coinChip = r.coins > 0
	if r.parts > 0 then
		table.insert(chips, `⚙ +{r.parts}`)
	end
	if r.xp > 0 then
		table.insert(chips, `⭐ +{r.xp} XP`)
	end
	if welcome > 0 then
		table.insert(chips, `🏁 ×2 · {welcome}`)
	end
	local hasChips = coinChip or #chips > 0

	local ROW = 62
	local listH = #rows * (ROW + 8)
	local bodyH = 24 + (if hasChips then 40 else 0) + listH + 64
	local height = 61 + 10 + bodyH + 14
	local overlay, _, body = Ui.panel(ctx.gui, "Welcome back!", { width = 460, height = math.min(640, height), onClose = close })
	local y = 0
	Ui.text({ Text = `⏱ Away {Welcome.awayText(tonumber(away) or 0)}`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = MUTED, Size = UDim2.new(1, 0, 0, 20), Parent = body })
	y += 24
	if hasChips then
		-- The reward chips (.lvl-chip), centred.
		local items: { { text: string, coin: boolean } } = {}
		if coinChip then
			table.insert(items, { text = `+{Ui.commas(r.coins)}`, coin = true })
		end
		for _, c in chips do
			table.insert(items, { text = c, coin = false })
		end
		local widths, total = {}, 0
		for i, it in items do
			widths[i] = Ui.textWidth(it.text, 15) + 20 + (if it.coin then 24 else 0)
			total += widths[i] + (if i > 1 then 6 else 0)
		end
		local row = Ui.new("Frame", { Name = "Chips", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(total, 28), BackgroundTransparency = 1, Parent = body })
		local x = 0
		for i, it in items do
			local chip = Ui.new("Frame", { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(widths[i], 28), BackgroundColor3 = Ui.WHITE, Parent = row }, {
				Ui.round(),
				Ui.stroke(2, Ui.LINE),
				Ui.gradient(Ui.COLORS.navy[1], Ui.COLORS.navy[2]),
			})
			local tx = 10
			if it.coin then
				local Icons = require(script.Parent.Parent.Icons) :: any
				Icons.draw("coin", chip, 22, nil, nil, UDim2.fromOffset(3, 3))
				tx = 28
			end
			Ui.text({ Text = it.text, TextSize = 15, Position = UDim2.fromOffset(tx, 0), Size = UDim2.new(1, -tx - 8, 1, 0), Shadow = 1.5, ShadowColor = Ui.BLACK, ShadowTransparency = 0.6, Parent = chip })
			x += widths[i] + 6
		end
		y += 40
	end
	local list = Ui.scroller({ Name = "List", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 1, -y - 64), CanvasSize = UDim2.fromOffset(0, listH), Parent = body })
	for i, row in rows do
		local shadow, card = Ui.shadowed({ Name = "Row", Position = UDim2.fromOffset(0, (i - 1) * (ROW + 8)), Size = UDim2.new(1, -8, 0, ROW), Parent = list }, {
			radius = 12,
			stroke = 1.5,
			drop = 2,
			dark = 1,
			color = Ui.WHITE,
			strokeColor = Ui.EDGE,
		})
		shadow.BackgroundColor3 = Ui.EDGE
		if row.thumb then
			local v = Thumb.new("Buildings", row.thumb, UDim2.fromOffset(76, ROW - 6))
			v.Position = UDim2.fromOffset(4, 1)
			v.Parent = card
		else
			Ui.text({ Text = row.icon or "", TextSize = 30, Position = UDim2.fromOffset(4, 0), Size = UDim2.fromOffset(76, ROW - 2), Parent = card })
		end
		local priceW = if row.price then Ui.textWidth(row.price, 15) + 16 else 0
		Ui.text({ Text = row.name, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(88, 10), Size = UDim2.new(1, -96 - priceW, 0, 20), Parent = card })
		Ui.text({ Text = row.stat, Body = true, TextSize = 13, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(88, 32), Size = UDim2.new(1, -96 - priceW, 0, 18), Parent = card })
		if row.price then
			Ui.text({ Text = row.price, TextSize = 15, TextColor3 = Color3.fromHex("#8d5a00"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(priceW, 20), Parent = card })
		end
	end
	local label = if some then "Collect all" else "Go to Rusty's"
	Ui.buy({ Name = "Collect", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(math.max(180, Ui.textWidth(label, 20) + 64), 46), Parent = body }, label, "green", function()
		if some then
			Remote.act("collectAll", true)
		end
		-- A car Rusty finished still needs its plate, so go there next.
		if restored then
			ctx.open("rescue")
		else
			close()
		end
	end, 20)
	return overlay
end

return Welcome
