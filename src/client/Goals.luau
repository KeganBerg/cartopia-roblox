--!strict
-- Goals, as the web game's GoalsPanel (ui/Goals.tsx): tabs for the story goals (then endless
-- ones), daily and weekly tasks with their chest, and the running event's goals. Each row has its
-- icon, the goal, a progress bar with n/m, what it pays, and Go › (takes you there) or Collect.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local endless = require(Game.endless) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Icons = require(script.Parent.Icons)

local Goals = {}

local GREEN = Color3.fromHex("#43a047")
local PURPLE = Color3.fromHex("#7e57c2")
local ROW_H, GAP = 70, 8
local lastTab: string? = nil

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

-- Countdowns as the web's left(): 45m, 3h 20m, 2d 4h.
local function left(ms: number): string
	local m = math.max(1, math.ceil(ms / 60000))
	if m >= 1440 then
		return `{m // 1440}d {(m % 1440) // 60}h`
	elseif m >= 60 then
		return `{m // 60}h {m % 60}m`
	end
	return `{m}m`
end

local function has(list: { any }?, v: any): boolean
	return list ~= nil and table.find(list, v) ~= nil
end

-- Where a goal gets done, as goTo in ui/Goals.tsx; screens the port doesn't have yet say so.
local function goTo(ctx: any, stat: string, def: string?)
	local s = store.useGame.getState()
	local function firstOf(pred: (any) -> boolean): any?
		for _, b in s.buildings do
			if pred(b) then
				return b
			end
		end
		return nil
	end
	local function shopFor(id: string)
		local d = data.buildingDef(id)
		if d and s.coins < d.price then
			ctx.open("need", { res = "coins", missing = d.price - s.coins, what = d.name })
		else
			ctx.open("shop", id)
		end
	end
	if stat == "rusty" or stat == "searches" or stat == "rescued" then
		if firstOf(function(b) return b.def == "rescue" end) then
			ctx.open("rescue")
		else
			shopFor("rescue")
		end
	elseif stat == "spooky" then
		ctx.open("shop", "pumpkins")
	elseif stat == "owns" then
		shopFor(def or "")
	elseif stat == "built" then
		ctx.open("shop")
	elseif stat == "jobs" or stat == "coinsEarned" or stat == "level" then
		ctx.close()
		ctx.toast("Tap the bubbles over your businesses to run jobs and collect coins.")
	elseif stat == "roads" then
		ctx.open("edit", "road")
		ctx.toast("Drag on empty grass to lay road")
	elseif stat == "plots" then
		ctx.open("edit", "land")
		ctx.toast("Tap a plot next to your town to buy it")
	elseif stat == "carsBought" or stat == "carsOwned" then
		ctx.open("showroom")
	elseif stat == "painted" or stat == "modsBought" or stat == "power" then
		ctx.open("garage")
	elseif stat == "upgrades" or stat == "bldgLevel" then
		local b = firstOf(function(o)
			local d = data.buildingDef(o.def)
			return data.upgradable(d) and data.buildingLevel(o) < data.maxLevel(d)
		end)
		ctx.open(if b then "shop" else "garage", if b then "upgrades" else nil)
	elseif stat == "drivers" then
		local b = firstOf(function(o)
			if not data.takesDriver(data.buildingDef(o.def)) then
				return false
			end
			for _, c in s.cars do
				if c.uid == o.car then
					return false
				end
			end
			return true
		end)
		if b then
			ctx.open("upgrade", b.uid)
		else
			ctx.open("shop")
		end
	elseif stat == "arcadePlays" then
		local b = firstOf(function(o) return o.def == "arcade" end)
		if b then
			ctx.open("upgrade", b.uid)
		else
			ctx.open("shop", "arcade")
		end
	elseif stat == "serviced" or stat == "flatsFixed" then
		ctx.close()
		ctx.toast("Cars sometimes get flats or run dry on jobs. Run a few and watch for the 🛞 and ⛽ bubbles.")
	elseif stat == "cratesOpened" then
		ctx.open("crates")
	else
		-- Races, the campaign, Grand Prix, daily runs: the race hub.
		ctx.open("race")
	end
end

-- Endless goals go where the same story stat goes, as goToEndless.
local ENDLESS_GO = {
	jobs = "jobs", coins = "coinsEarned", races = "races", wins = "racesWon", campaign = "campaignWins", search = "searches", service = "serviced",
	upgrades = "upgrades", mods = "modsBought", paint = "painted", gp = "gpWins", stars = "stars", build = "owns", cars = "carsOwned", land = "plots",
	drivers = "drivers", level = "level", restore = "rescued", flats = "flatsFixed", power = "power", arcade = "arcadePlays", crates = "cratesOpened",
}
local function goToEndless(ctx: any, g: any)
	local s = store.useGame.getState()
	if g.kind == "bldgUp" then
		local best: any = nil
		for _, b in s.buildings do
			if b.def == g.def and (best == nil or data.buildingLevel(b) < data.buildingLevel(best)) then
				best = b
			end
		end
		if best then
			ctx.open("upgrade", best.uid)
		else
			ctx.open("shop", g.def)
		end
	elseif g.kind == "carUp" then
		ctx.open("garage")
	else
		goTo(ctx, ENDLESS_GO[g.kind] or "races", g.def)
	end
end

-- A row of rewards: coin and count, gems, parts, then XP and stars in purple (Reward).
local function reward(parent: Instance, pos: UDim2, r: { coins: number, xp: number?, bucks: number?, parts: number?, stars: number? })
	local line = Ui.new("Frame", { Name = "Pay", BackgroundTransparency = 1, Position = pos, Size = UDim2.new(1, 0, 0, 20), Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local n = 0
	local function word(text: string, color: Color3, gap: number?)
		n += 1
		local l = Ui.text({ Text = text, TextSize = 15, TextColor3 = color, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = n, Parent = line })
		if gap then
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, gap), Parent = l })
		end
	end
	local function icon(text: string)
		n += 1
		Ui.text({ Text = text, TextSize = 14, Size = UDim2.fromOffset(20, 20), LayoutOrder = n, Parent = line })
	end
	n += 1
	local coin = Ui.new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(20, 20), LayoutOrder = n, Parent = line })
	Icons.draw("coin", coin, 20)
	word(Ui.commas(r.coins), Color3.fromHex("#455a64"))
	if (r.bucks or 0) > 0 then
		icon("💎")
		word(tostring(r.bucks), Color3.fromHex("#455a64"))
	end
	if (r.parts or 0) > 0 then
		icon("⚙")
		word(tostring(r.parts), Color3.fromHex("#455a64"))
	end
	if (r.xp or 0) > 0 then
		word(`+{Ui.commas(r.xp :: number)} XP`, PURPLE, 4)
	end
	if (r.stars or 0) > 0 then
		word(`+{r.stars} ⭐`, PURPLE, 4)
	end
end

-- A thin rounded bar with a green fill.
local function bar(parent: Instance, props: { [string]: any }, pct: number, back: string)
	local b = Ui.new("Frame", { Name = "Bar", BackgroundColor3 = Color3.fromHex(back), BorderSizePixel = 0, ClipsDescendants = true, Parent = parent }, { Ui.round() })
	for k, v in props do
		(b :: any)[k] = v
	end
	Ui.new("Frame", { Size = UDim2.fromScale(math.clamp(pct, 0, 1), 1), BackgroundColor3 = GREEN, BorderSizePixel = 0, Visible = pct > 0, Parent = b }, { Ui.round() })
	return b
end

type RowOpts = { icon: string, text: string, have: number, target: number, done: boolean, claimed: boolean?, wait: string?, onGo: () -> (), onClaim: () -> (), pay: any }
local function row(list: Instance, order: number, o: RowOpts)
	-- The card sits on the web's 0 2px 0 edge.
	local edge = if o.done and not o.claimed then GREEN else Ui.EDGE
	local shadow, r = Ui.shadowed({ Name = "Goal", LayoutOrder = order, Size = UDim2.new(1, 0, 0, ROW_H + 2), Parent = list }, {
		radius = 12,
		stroke = 1.5,
		drop = 0,
		color = if o.done and not o.claimed then Color3.fromHex("#f1f8e9") else Ui.WHITE,
		strokeColor = edge,
	})
	shadow.BackgroundColor3 = edge
	shadow.BackgroundTransparency = if o.claimed then 0.45 else 0
	local ss = shadow:FindFirstChildOfClass("UIStroke")
	if ss then
		ss.Color = edge
		ss.Transparency = shadow.BackgroundTransparency
	end
	r.Size = UDim2.new(1, 0, 1, -2)
	r.BackgroundTransparency = if o.claimed then 0.45 else 0
	Ui.new("Frame", { Name = "Icon", Position = UDim2.new(0, 6, 0.5, -20), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = if o.done then Color3.fromHex("#dcedc8") else Ui.SHEET, Parent = r }, {
		Ui.corner(10),
		Ui.text({ Text = o.icon, TextSize = 22, Size = UDim2.fromScale(1, 1) }),
	})
	local main = Ui.new("TextButton", { Name = "Main", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Position = UDim2.fromOffset(56, 8), Size = UDim2.new(1, -56 - 84, 1, -16), Parent = r })
	main.Activated:Connect(function()
		if not o.done then
			o.onGo()
		end
	end)
	Ui.text({ Text = o.text, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, 18), Parent = main })
	local have = math.min(o.have, o.target)
	bar(main, { Position = UDim2.fromOffset(0, 25), Size = UDim2.new(1, -46, 0, 8) }, have / math.max(1, o.target), "#e0e6ea")
	Ui.text({ Text = `{Ui.commas(have)}/{Ui.commas(o.target)}`, TextSize = 12, TextColor3 = Color3.fromHex("#78909c"), TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(1, -40, 0, 21), Size = UDim2.fromOffset(40, 16), Parent = main })
	reward(main, UDim2.fromOffset(0, 37), o.pay)
	local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 1), Size = UDim2.fromOffset(if o.wait then 70 else 50, 28), Parent = r }
	if o.claimed then
		Ui.text({ Text = "✔", TextSize = 20, TextColor3 = GREEN, AnchorPoint = at.AnchorPoint, Position = at.Position, Size = UDim2.fromOffset(36, 28), Parent = r })
	elseif o.done and o.wait then
		Ui.buy(at, `🔒 {o.wait}`, "grey", nil, 14)
	elseif o.done then
		at.Size = UDim2.fromOffset(66, 28)
		Ui.buy(at, "Collect", "green", o.onClaim, 14)
	else
		Ui.buy(at, "Go ›", "garage", o.onGo, 14)
	end
end

-- "Story 3/59" (or a task timer) with its bar, over the rows.
local function head(list: Instance, order: number, text: string, pct: number?)
	local h = Ui.new("Frame", { Name = "Head", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, Parent = list })
	local l = Ui.text({ Text = text, TextSize = 14, TextColor3 = Color3.fromHex("#546e7a"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Parent = h })
	if pct then
		-- The bar fills the rest of the line, as the web's flex: 1.
		local w = math.max(70, math.ceil(Ui.textWidth(text, 14)) + 16)
		bar(h, { Position = UDim2.new(0, w, 0.5, -4), Size = UDim2.new(1, -w - 2, 0, 8) }, pct, "#dfe5ea")
	end
	return l
end

-- ♾ n and pips toward the next parts (5th) and gems (10th) bonus.
local function endlessHead(list: Instance, order: number, s: any)
	local done = if s.endless then s.endless.n or 0 else 0
	local pay = endless.ENDLESS_PAY
	local at = done % pay.bucksEvery
	local h = Ui.new("Frame", { Name = "Endless", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = list })
	Ui.text({ Text = `♾ {Ui.commas(done)}`, TextSize = 15, TextColor3 = Color3.fromHex("#5e35b1"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(2, 0), Size = UDim2.fromOffset(60, 26), Parent = h })
	local pips = Ui.new("Frame", { Position = UDim2.fromOffset(66, 0), Size = UDim2.new(1, -68, 1, 0), BackgroundTransparency = 1, Parent = h }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i = 1, pay.bucksEvery do
		local mark = if i % pay.bucksEvery == 0 then "💎" elseif i % pay.partsEvery == 0 then "⚙" else nil
		local on = i <= at
		local p = Ui.new("Frame", {
			LayoutOrder = i,
			Size = UDim2.fromOffset(if mark then 24 else 10, if mark then 24 else 10),
			BackgroundColor3 = Color3.fromHex(if on then (if mark then "#d1c4e9" else "#7e57c2") else "#e0e6ea"),
			Parent = pips,
		}, { Ui.round() })
		if mark then
			Ui.new("UIFlexItem", { FlexMode = Enum.UIFlexMode.None, Parent = p })
			Ui.text({ Text = mark, TextSize = 13, Size = UDim2.fromScale(1, 1), Parent = p })
		end
	end
end

local function storyTab(ctx: any, list: Instance, s: any): number
	local story = {}
	for _, g in data.GOALS do
		if not g.event then
			table.insert(story, g)
		end
	end
	local claimed = 0
	for _, g in story do
		if has(s.claimedGoals, g.id) then
			claimed += 1
		end
	end
	local total = #story
	local h = 0
	local order = 0
	local function add(height: number)
		order += 1
		h += height + GAP
	end
	if claimed >= total then
		add(26)
		endlessHead(list, order, s)
	else
		add(20)
		head(list, order, `Story {claimed}/{total}`, claimed / math.max(1, total))
	end
	for _, g in store.activeGoals(s) do
		add(ROW_H + 2)
		row(list, order, {
			icon = g.icon,
			text = g.text,
			have = store.statValue(s, g.stat, g.def),
			target = g.target,
			done = store.goalDone(s, g),
			onGo = function()
				goTo(ctx, g.stat, g.def)
			end,
			onClaim = function()
				Remote.act("claimGoal", g.id)
			end,
			pay = { coins = g.coins, xp = data.xpGain(s.level, g.xp or 0), bucks = g.bucks },
		})
	end
	local active = store.activeEndless(s)
	if claimed < total and #active > 0 then
		add(26)
		endlessHead(list, order, s)
	end
	local t = now()
	local capped = endless.endlessCapped(s.endless, t)
	local pay = endless.endlessPay((if s.endless then s.endless.n or 0 else 0) + 1, s.level)
	local xp = endless.endlessXp(s.level)
	for _, g in active do
		local kind = endless.KINDS[g.kind]
		add(ROW_H + 2)
		row(list, order, {
			icon = if kind then kind.icon else "♾",
			text = endless.endlessText(g, s.cars),
			have = endless.endlessHave(store.endlessTown(s), g),
			target = g.n,
			done = store.endlessReady(s, g),
			wait = if capped then left(data.msToNextDay(t)) else nil,
			onGo = function()
				goToEndless(ctx, g)
			end,
			onClaim = function()
				Remote.act("claimEndless", g.k)
			end,
			pay = { coins = pay.coins, xp = xp, parts = pay.parts, bucks = pay.bucks },
		})
	end
	return h
end

local function tasksTab(ctx: any, list: Instance, s: any, period: string): number
	local t = now()
	local slots = store.periodSlots(s.quests, period)
	local done = store.periodDone(s.quests, period)
	local qp = data.QUEST_PAY[period]
	local pay = data.payAt(qp.task, s.level)
	local chestPay = data.payAt(qp.chest, s.level)
	local opened = store.chestOpened(s.quests, period)
	local ready = #done >= data.TASKS_PER_PERIOD and not opened
	local daily = period == "daily"
	local h = 0
	local order = 1
	head(list, order, `{if daily then "New tasks" else "New week"} in {left(if daily then data.msToNextDay(t) else data.msToNextWeek(t))}`)
	h += 20 + GAP
	for _, slot in slots do
		local d = store.taskDef(period, slot.id)
		if not d then
			continue
		end
		local have = store.taskProgress(s, period, slot)
		order += 1
		h += ROW_H + 2 + GAP
		row(list, order, {
			icon = d.icon,
			text = store.taskText(period, slot),
			have = have,
			target = slot.n,
			done = have >= slot.n,
			claimed = has(done, slot.id),
			onGo = function()
				goTo(ctx, d.stat)
			end,
			onClaim = function()
				Remote.act("claimTask", period, slot.id)
			end,
			pay = { coins = pay.coins, xp = data.xpGain(s.level, pay.xp), stars = if daily then data.SEASON_STARS.dailyTask else data.SEASON_STARS.weeklyTask },
		})
	end
	-- The chest: opens once every task in the period is done.
	order += 1
	h += 2 + ROW_H + GAP
	local c = Ui.new("Frame", {
		Name = "Chest",
		LayoutOrder = order,
		Size = UDim2.new(1, 0, 0, ROW_H),
		BackgroundColor3 = Color3.fromHex(if ready then "#fff8e1" else "#ffffff"),
		BackgroundTransparency = if opened then 0.45 else 0,
		Parent = list,
	}, { Ui.corner(12), Ui.stroke(if ready then 2 else 1.5, Color3.fromHex(if ready then "#ffb300" else "#b0bec5")) })
	Ui.text({ Text = if opened then "📭" elseif daily then "🎁" else "💎", TextSize = 26, Position = UDim2.new(0, 6, 0.5, -20), Size = UDim2.fromOffset(40, 40), Parent = c })
	Ui.text({ Text = if daily then "Daily chest" else "Weekly chest", Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 8), Size = UDim2.new(1, -140, 0, 18), Parent = c })
	local pips = Ui.new("Frame", { Position = UDim2.fromOffset(56, 29), Size = UDim2.fromOffset(200, 6), BackgroundTransparency = 1, Parent = c }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }),
	})
	for i = 1, data.TASKS_PER_PERIOD do
		Ui.new("Frame", { Size = UDim2.fromOffset(22, 6), BackgroundColor3 = Color3.fromHex(if i <= #done then "#ffb300" else "#cfd8dc"), Parent = pips }, { Ui.corner(3) })
	end
	reward(c, UDim2.fromOffset(56, 41), {
		coins = chestPay.coins,
		xp = data.chestXp(period, s.level),
		bucks = qp.chest.bucks,
		parts = qp.chest.parts,
		stars = if daily then data.SEASON_STARS.dailyChest else data.SEASON_STARS.weeklyChest,
	})
	local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 1), Size = UDim2.fromOffset(56, 28), Parent = c }
	if opened then
		Ui.text({ Text = "✔", TextSize = 20, TextColor3 = GREEN, AnchorPoint = at.AnchorPoint, Position = at.Position, Size = UDim2.fromOffset(36, 28), Parent = c })
	elseif ready then
		Ui.buy(at, "Open", "green", function()
			Remote.act("claimChest", period)
		end, 14)
	else
		Ui.buy(at, "🔒", "grey", nil, 14)
	end
	return h
end

local function eventTab(ctx: any, list: Instance, s: any): number
	local t = now()
	local e = data.activeEvent(t)
	if not e then
		head(list, 1, "No event is running right now.")
		return 28
	end
	head(list, 1, `{e.icon} {e.name} ends in {left(data.eventEndsAt(e, t) - t)}`)
	local h = 20 + GAP
	for i, g in store.eventGoals(t) do
		local locked = s.level < (g.level or 1)
		h += ROW_H + 2 + GAP
		row(list, i + 1, {
			icon = g.icon,
			text = if locked then `{g.text} (level {g.level})` else g.text,
			have = store.statValue(s, g.stat, g.def),
			target = g.target,
			done = not locked and store.goalDone(s, g),
			claimed = has(s.claimedGoals, g.id),
			onGo = function()
				goTo(ctx, g.stat, g.def)
			end,
			onClaim = function()
				Remote.act("claimGoal", g.id)
			end,
			pay = { coins = g.coins, xp = data.xpGain(s.level, g.xp or 0), bucks = g.bucks },
		})
	end
	return h
end

-- Red counts on the tabs: things ready to collect there.
local function dots(s: any): { [string]: number }
	local out = {}
	local story = 0
	for _, g in store.activeGoals(s) do
		if store.goalDone(s, g) then
			story += 1
		end
	end
	if not endless.endlessCapped(s.endless, now()) then
		for _, g in store.activeEndless(s) do
			if store.endlessReady(s, g) then
				story += 1
			end
		end
	end
	out.story = story
	for _, p in { "daily", "weekly" } do
		local done = store.periodDone(s.quests, p)
		local c = 0
		for _, t in store.periodSlots(s.quests, p) do
			if not has(done, t.id) and store.taskProgress(s, p, t) >= t.n then
				c += 1
			end
		end
		if #done >= data.TASKS_PER_PERIOD and not store.chestOpened(s.quests, p) then
			c += 1
		end
		out[p] = c
	end
	local ev = 0
	for _, g in store.eventGoals(now()) do
		if store.goalOpen(s, g) and store.goalDone(s, g) then
			ev += 1
		end
	end
	out.event = ev
	return out
end

function Goals.open(ctx: any): Instance
	local overlay, sheet, body = Ui.panel(ctx.gui, "Goals", { width = 456, onClose = ctx.close, bodyTop = 0 })
	local limit = (sheet.Parent :: Instance):FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local s = store.useGame.getState()
	local ev = data.activeEvent(now())
	local items = { { id = "story", label = "📋 Goals" }, { id = "daily", label = "☀️ Daily" }, { id = "weekly", label = "📅 Weekly" } }
	if ev then
		table.insert(items, { id = "event", label = `{ev.icon} Event` })
	end
	-- Opens on the first tab with something to collect, else where it was left.
	local d = dots(s)
	local tab = if d.story > 0 then "story" elseif d.event > 0 and ev then "event" elseif d.daily > 0 then "daily" elseif d.weekly > 0 then "weekly" else (lastTab or "story")
	if tab == "event" and not ev then
		tab = "story"
	end

	local list = Ui.scroller({ Name = "List", Position = UDim2.fromOffset(-6, 64), Size = UDim2.new(1, 12, 1, -64), Parent = body })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local row: ScrollingFrame
	local function badges(st: any)
		local counts = dots(st)
		for _, it in items do
			local face = (row :: any)[it.id].Face :: Frame
			local dot = face:FindFirstChild("Dot") :: Frame?
			local c = counts[it.id] or 0
			if c > 0 and not dot then
				dot = Ui.new("Frame", { Name = "Dot", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -7), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromHex("#e53935"), ZIndex = 3, Parent = face }, {
					Ui.round(),
					Ui.text({ Name = "N", Text = "", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 3 }),
				})
			end
			if dot then
				dot.Visible = c > 0
				Ui.setText(dot:FindFirstChild("N") :: TextLabel, tostring(c))
			end
		end
	end
	local function show()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local st = store.useGame.getState()
		local h = if tab == "story" then storyTab(ctx, list, st) elseif tab == "event" then eventTab(ctx, list, st) else tasksTab(ctx, list, st, tab)
		-- The sheet hugs its rows, as the web's panel, up to the screen's height.
		limit.MaxSize = Vector2.new(456, 61 + 64 + h + 18)
		badges(st)
	end
	row = Ui.tabs(body, items, tab, function(id)
		tab = id
		lastTab = id
		show()
	end, { position = UDim2.fromOffset(-14, 0), size = UDim2.new(1, 28, 0, 54) })
	show()
	local conn = Remote.changed:Connect(show)
	overlay.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return overlay
end

return Goals
