--!strict
-- Rusty's Rescue, as the web game's RescuePanel (ui/Rescue.tsx): two tabs, Find cars (the lots to
-- search, Rusty's tow truck and its upgrades) and My lot (the restore bays and the rusty cars
-- waiting for them). A search plays on its own screen: tap the tarps to uncover what's under them,
-- fix a flat or go home, then tow the haul home. A restored car gets its license plate here.
--
-- Every change is the web store's own action, run by the server (Remote.act); the search in
-- progress comes with each new town (Remote.search), since it isn't part of the save.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local resto = require(Game.resto) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)
local Confirm = require(script.Parent.Confirm)
local BuildArt = require(script.Parent.BuildArt)
local RescueLot = require(script.Parent.RescueLot)
local TownCamera = require(script.Parent.TownCamera)
local Sfx = require(script.Parent.Sounds.Sfx)

local Rescue = {}

local LINE = Ui.LINE
local RUST = Color3.fromHex("#9a6a4f")
local BAY_TOP, BAY_BOTTOM = "#41506a", "#2a3550"
local RARITY_ORDER = { common = 0, scarce = 1, rare = 2 }
local RARITY_EDGE = { common = "#90a4ae", scarce = "#1e88e5", rare = "#ff6d00" }
-- Each lot's colours, standing in for the web's postcard renders of its search scene.
local SPOT_LOOK = {
	suburbs = { "#8fc46a", "#4f8a3c" },
	farm = { "#e6c25a", "#a8822c" },
	downtown = { "#7f97b8", "#40536f" },
	desert = { "#f0b46a", "#c0703a" },
	track = { "#9a8f86", "#4e4642" },
}
-- Rusty's top spot, where resto-mod pieces turn up.
local PIECE_SPOT = "track"

-- The panel's tab, the haul just towed home and the bay being named, kept between redraws.
local tab: string? = nil
local recap: { items: { any }, piece: any?, at: number? }? = nil
local naming: number? = nil
-- Scrolls the panel to the picked car's Restore button (set while My lot is open).
local scrollToPick: (() -> ())? = nil

-- The search in progress, kept between redraws: Search all running, the tow home under way, the
-- spots whose find has been shown, the find popped up last and the tray's counts so far.
local auto = false
local leaving = false
local seenPins: { [number]: boolean }? = nil
local found: { i: number, at: number }? = nil
local trayWas: { [string]: number } = {}
local FOUND_SECONDS = 1.9

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

local function hasCar(cars: { any }, model: string): boolean
	for _, c in cars do
		if c.model == model then
			return true
		end
	end
	return false
end

-- Short clock for the bay timers: 3:12, or 1h05 for long restores.
local function clock(ms: number): string
	local sec = math.max(0, math.ceil(ms / 1000))
	local h = sec // 3600
	local m = (sec % 3600) // 60
	if h > 0 then
		return string.format("%dh%02d", h, m)
	end
	return string.format("%d:%02d", m, sec % 60)
end

local function restoreTime(minutes: number): string
	return if minutes >= 60 then `{minutes // 60}h` else `{minutes}m`
end

local function lootLabel(l: any): (string, string)
	if l.kind == "car" then
		return "🚗", data.carDef(l.model).name
	elseif l.kind == "coins" then
		return "💰", `${Ui.commas(l.n)}`
	elseif l.kind == "parts" then
		return "⚙️", `{l.n} parts`
	elseif l.kind == "fuel" then
		return "⛽", `{l.n} fuel`
	elseif l.kind == "trophy" then
		return "🏆", "Trophy"
	end
	return "💨", "Nothing"
end

-- A rusty (or restored) car picture.
local function carPic(parent: Instance, model: string, size: UDim2, rusty: boolean, z: number): ViewportFrame
	local d = data.carDef(model)
	local pic = Thumb.new("Cars", model, size, if rusty then RUST else Color3.fromHex(d.colors[1]))
	pic.ZIndex = z
	pic.Parent = parent
	return pic
end

-- The rarity tag: grey Common, blue Scarce, purple-orange Rare.
local function rarityTag(parent: Instance, r: string, props: { [string]: any }?): Frame
	local tag = Ui.new("Frame", { Size = UDim2.fromOffset(0, 17), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.WHITE, ZIndex = 6, Parent = parent }, {
		Ui.corner(6),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	if r == "rare" then
		Ui.new("UIGradient", { Color = ColorSequence.new(Color3.fromHex("#8e24aa"), Color3.fromHex("#ff6d00")), Parent = tag })
	end
	tag.BackgroundColor3 = if r == "common" then Color3.fromHex("#78909c") elseif r == "scarce" then Color3.fromHex("#1e88e5") else Ui.WHITE
	for k, v in (props or {}) :: { [string]: any } do
		(tag :: any)[k] = v
	end
	Ui.text({ Text = data.RARITY[r].name, TextSize = 11, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = tag.ZIndex, Parent = tag })
	return tag
end

-- A dark rounded strip, like the web's truck row and bays.
local function darkCard(props: { [string]: any }): Frame
	local f = Ui.new("Frame", props, { Ui.corner(16), Ui.stroke(2.5, LINE), Ui.gradient(BAY_TOP, BAY_BOTTOM) })
	return f
end

-- A number rolling up from `from` to `to` over 0.55s, easing out, as the web's Count.
local function rollUp(label: TextLabel, from: number, to: number, show: (number) -> string)
	Ui.setText(label, show(from))
	if from == to then
		return
	end
	task.spawn(function()
		local t0 = os.clock()
		while label.Parent do
			local k = math.min(1, (os.clock() - t0) / 0.55)
			Ui.setText(label, show(math.round(from + (to - from) * (1 - (1 - k) ^ 3))))
			if k >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Pops a hidden piece in: shown at 40% and springing to full size.
local function popIn(g: GuiObject)
	g.Visible = true
	local scale = g:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = g })
	scale.Scale = 0.4
	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- The skill chip (the web's SkillTag), beside a car's rarity tag.
local function skillTag(parent: Instance, model: string, props: { [string]: any }): Frame?
	local sk = data.carDef(model).skill
	local def = sk and data.SKILLS[sk]
	if not def then
		return nil
	end
	local tag = Ui.new("Frame", { Size = UDim2.fromOffset(0, 17), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#ede7f6"), ZIndex = 4, Parent = parent }, {
		Ui.corner(8),
		Ui.stroke(1.5, Color3.fromHex("#b39ddb")),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
	for k, v in props do
		(tag :: any)[k] = v
	end
	Ui.text({ Text = `{def.icon} {def.name}`, TextSize = 11, TextColor3 = Color3.fromHex("#4527a0"), Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = tag.ZIndex, Parent = tag })
	return tag
end

-- ── Restore bays ───────────────────────────────────────────────────────────────────────────────

-- One bay: the car on the lift with its timer and Finish now, or Collect when it's done. compact:
-- the slim row over the lots. Returns its height, and a function that moves its timer on.
local function bayHero(parent: Instance, order: number, s: any, bay: number, compact: boolean, ctx: any, onTab: (string) -> ()): (number, (() -> ())?)
	local r = if bay == 1 then s.restoring2 else s.restoring
	if not r then
		if compact then
			return 0, nil
		end
		local b = Ui.new("TextButton", { LayoutOrder = order, Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 96), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = parent }, {
			Ui.corner(18),
			Ui.stroke(2.5, Color3.fromHex("#9fb6d6")),
		})
		Ui.new("Frame", { Position = UDim2.fromOffset(10, 10), Size = UDim2.new(0.55, -10, 1, -20), BackgroundColor3 = Ui.SHEET, ZIndex = 4, Parent = b }, {
			Ui.corner(12),
			Ui.text({ Text = "🔧", TextSize = 34, Size = UDim2.fromScale(1, 1), ZIndex = 4 }),
		})
		Ui.text({ Text = if bay == 1 then "Bay 2 is free" else "Bay is free", TextSize = 22, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.55, 14, 0, 20), Size = UDim2.new(0.45, -24, 0, 28), ZIndex = 4, Parent = b })
		Ui.text({ Text = "Pick a car from your lot ↓", TextSize = 14, TextColor3 = Color3.fromHex("#607d8b"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.55, 14, 0, 52), Size = UDim2.new(0.45, -24, 0, 20), ZIndex = 4, Parent = b })
		-- Tapping a free bay brings the lot's Restore button into view.
		b.Activated:Connect(function()
			if scrollToPick then
				scrollToPick()
			end
		end)
		return 96, nil
	end
	local d = data.carDef(r.model)
	local h = if compact then 84 else 196
	local card = darkCard({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = parent })
	local grad = card:FindFirstChildOfClass("UIGradient") :: UIGradient
	local stage = Ui.new("Frame", {
		Position = UDim2.fromOffset(if compact then 8 else 12, if compact then 8 else 12),
		Size = if compact then UDim2.fromOffset(92, h - 16) else UDim2.new(0.55, -18, 1, -24),
		BackgroundColor3 = Color3.fromHex("#5b6a86"),
		ClipsDescendants = true,
		ZIndex = 4,
		Parent = card,
	}, { Ui.corner(12) })
	-- The lift's yellow arm and the hazard stripe along the floor.
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, if compact then -12 else -18), Size = UDim2.new(0.72, 0, 0, if compact then 4 else 6), BackgroundColor3 = Color3.fromHex("#ffb300"), ZIndex = 4, Parent = stage }, { Ui.round(), Ui.stroke(2, LINE) })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, if compact then 7 else 10), BackgroundColor3 = Color3.fromHex("#ffca28"), ZIndex = 4, Parent = stage })
	local picBox = Ui.new("Frame", { Size = UDim2.new(1, 0, 1, if compact then -14 else -24), BackgroundTransparency = 1, ZIndex = 5, Parent = stage })
	local pic = carPic(picBox, r.model, UDim2.fromScale(1, 1), true, 5)

	local side = Ui.new("Frame", {
		Position = if compact then UDim2.fromOffset(112, 8) else UDim2.new(0.55, 4, 0, 14),
		Size = if compact then UDim2.new(1, -120, 1, -16) else UDim2.new(0.45, -16, 1, -28),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = card,
	})
	Ui.text({ Text = d.name, TextSize = if compact then 17 else 22, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.new(1, 0, 0, if compact then 22 else 30), Shadow = 2, ZIndex = 5, Parent = side })
	local barBack = Ui.new("Frame", { Position = UDim2.fromOffset(0, if compact then 28 else 44), Size = UDim2.new(if compact then 0.45 else 1, 0, 0, 14), BackgroundColor3 = Color3.fromHex("#1b2438"), ZIndex = 5, Parent = side }, { Ui.round(), Ui.stroke(2, LINE) })
	local bar = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromHex("#ffca28"), ZIndex = 5, Parent = barBack }, { Ui.round() })
	local timeText = Ui.text({ Text = "", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(if compact then 0 else 0, if compact then 46 else 64), Size = UDim2.new(if compact then 0.45 else 1, 0, 0, 20), ZIndex = 5, Parent = side })
	if not compact then
		rarityTag(side, r.rarity, { Position = UDim2.fromOffset(0, 90) })
	end
	local btnHolder = Ui.new("Frame", {
		AnchorPoint = Vector2.new(if compact then 1 else 0, 1),
		Position = if compact then UDim2.fromScale(1, 1) else UDim2.fromScale(0, 1),
		Size = UDim2.fromOffset(if compact then 170 else 210, if compact then 36 else 42),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Parent = side,
	})
	local lastDone: boolean? = nil
	local rushLabel: TextLabel? = nil
	local function update()
		local left = r.endsAt - now()
		local done = left <= 0
		bar.Size = UDim2.fromScale(if done then 1 else math.clamp(1 - left / (r.minutes * 60000), 0, 1), 1)
		Ui.setText(timeText, if done then "✨ Good as new!" else `⏱ {clock(left)}  Rusty's on it`)
		if rushLabel and not done then
			Ui.setText(rushLabel, `Finish now · 💎{data.rushBucks(left)}`)
		end
		if done ~= lastDone then
			lastDone = done
			rushLabel = nil
			for _, c in btnHolder:GetChildren() do
				c:Destroy()
			end
			grad.Color = if done then Ui.seq("#5ccf5c", "#2a9a39") else Ui.seq(BAY_TOP, BAY_BOTTOM)
			stage.BackgroundColor3 = if done then Color3.fromHex("#d9efc6") else Color3.fromHex("#5b6a86")
			pic.Parent = nil
			pic = carPic(picBox, r.model, UDim2.fromScale(1, 1), not done, 5)
			if done then
				local _, face = Ui.button({ Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = btnHolder }, "tab", function()
					naming = bay
					Sfx.rescue.fanfare(r.rarity ~= "common")
					ctx.open("rescue")
				end, { radius = 12, stroke = 2.5, drop = 3, text = "✨ Collect", textSize = if compact then 15 else 18, textColor = LINE })
				face.Name = "Collect"
			else
				local _, rush = Ui.buy({ Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = btnHolder }, `Finish now · 💎{data.rushBucks(left)}`, "garage", function()
					Remote.act("rushRestore", bay)
				end, if compact then 14 else 16)
				rush.Name = "Rush"
				rushLabel = rush:FindFirstChild("Label") :: TextLabel?
			end
		end
	end
	update()
	local _ = onTab
	return h, update
end

-- Both bays; the second opens at BAY2_LEVEL, and before then a lock says when.
local function bays(parent: Instance, order: number, s: any, compact: boolean, ctx: any, onTab: (string) -> (), tickers: { () -> () }): number
	local open2 = store.gateLevel(s) >= data.BAY2_LEVEL
	local total = 0
	local h, t = bayHero(parent, order, s, 0, compact, ctx, onTab)
	total += h
	if t then
		table.insert(tickers, t)
	end
	if open2 then
		if s.restoring or compact then
			local h2, t2 = bayHero(parent, order + 1, s, 1, compact, ctx, onTab)
			total += h2
			if t2 then
				table.insert(tickers, t2)
			end
		end
	elseif not compact then
		local lock = Ui.new("Frame", { LayoutOrder = order + 1, Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromHex("#dfe6ef"), ZIndex = 4, Parent = parent }, { Ui.corner(12) })
		Ui.text({ Text = `🔧🔒 Bay 2  ·  Lv {data.BAY2_LEVEL}`, TextSize = 15, TextColor3 = Color3.fromHex("#546e7a"), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = lock })
		total += 34
	end
	return total
end

-- ── My lot ─────────────────────────────────────────────────────────────────────────────────────

local picked: string? = nil

local function lot(parent: Instance, order: number, s: any, onTab: (string) -> ())
	local junk = s.junkyard or {}
	local busy = not (not s.restoring or (not s.restoring2 and store.gateLevel(s) >= data.BAY2_LEVEL))
	local head = Ui.new("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, ZIndex = 4, Parent = parent })
	Ui.text({ Text = "Your lot", TextSize = 19, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromScale(0.5, 1), ZIndex = 4, Parent = head })
	Ui.text({ Text = if #junk > 0 then "Tap a car to fix it up" else "Rusty tows finds here", TextSize = 13, TextColor3 = Color3.fromHex("#607d8b"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.5, 1), ZIndex = 4, Parent = head })

	local best: any = nil
	for _, c in junk do
		if not best or RARITY_ORDER[c.rarity] > RARITY_ORDER[best.rarity] then
			best = c
		end
	end
	local pick: any = best
	for _, c in junk do
		if c.uid == picked then
			pick = c
		end
	end
	if pick then
		local d = data.carDef(pick.model)
		local cost = data.restoreCost(d)
		local row = Ui.new("Frame", { Name = "LotPick", LayoutOrder = order + 1, Size = UDim2.new(1, 0, 0, 76), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = parent }, {
			Ui.corner(14),
			Ui.stroke(2.5, Color3.fromHex(RARITY_EDGE[pick.rarity])),
		})
		Ui.text({ Text = d.name, TextSize = 19, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -330, 0, 24), ZIndex = 4, Parent = row })
		local tags = Ui.new("Frame", { Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -330, 0, 17), BackgroundTransparency = 1, ZIndex = 4, Parent = row }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		rarityTag(tags, pick.rarity, { LayoutOrder = 1 })
		skillTag(tags, pick.model, { LayoutOrder = 2 })
		if d.rescueOnly then
			local classic = Ui.new("Frame", { LayoutOrder = 3, Size = UDim2.fromOffset(0, 17), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#6d4c41"), ZIndex = 4, Parent = tags }, { Ui.corner(6), Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }) })
			Ui.text({ Text = "Classic", TextSize = 11, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 4, Parent = classic })
		end
		local pi = data.performance(d, { engine = 0, turbo = 0, tires = 0, weight = 0 })
		Ui.text({ Text = `PI {pi}   ⏱ {restoreTime(data.RARITY[pick.rarity].minutes)}`, TextSize = 13, TextColor3 = Color3.fromHex("#546e7a"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 54), Size = UDim2.new(1, -330, 0, 16), ZIndex = 4, Parent = row })
		local scrap = Ui.new("TextButton", { Name = "Scrap", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -184, 0.5, 0), Size = UDim2.fromOffset(96, 40), BackgroundColor3 = Color3.fromHex("#efebe9"), ZIndex = 4, Parent = row }, {
			Ui.corner(10),
			Ui.stroke(2, Color3.fromHex("#d7ccc8")),
		})
		Ui.text({ Text = `♻ +{data.RARITY[pick.rarity].scrapParts} ⚙️`, TextSize = 15, TextColor3 = Color3.fromHex("#6d4c41"), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = scrap })
		scrap.Activated:Connect(function()
			picked = nil
			Remote.act("scrapCar", pick.uid)
		end)
		local label = if busy then "🔧 Bay busy" else `Restore · ${Ui.commas(cost)}`
		local _, go = Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(166, 44), ZIndex = 4, Parent = row }, label, if busy then "grey" elseif s.coins < cost then "broke" else "green", function()
			if busy then
				return
			end
			picked = nil
			Remote.act("restoreCar", pick.uid)
		end, 16)
		go.Name = "Restore"
	end

	-- The parking spots: a car in each, then empty bays to search for more.
	local spots = Ui.new("Frame", { LayoutOrder = order + 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromHex("#444b5a"), ZIndex = 4, Parent = parent }, {
		Ui.corner(16),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 6, -7, 0, 112), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, c in junk do
		local cd = data.carDef(c.model)
		local sel = pick and pick.uid == c.uid
		local b = Ui.new("TextButton", { LayoutOrder = i, Text = "", AutoButtonColor = false, BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = spots }, {
			Ui.corner(12),
			Ui.stroke(if sel then 3.5 else 3, Color3.fromHex(if sel then "#ffca28" else RARITY_EDGE[c.rarity])),
		})
		local box = Ui.new("Frame", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 62), BackgroundColor3 = Color3.fromHex("#f6ebdf"), ZIndex = 4, Parent = b }, { Ui.corner(8) })
		carPic(box, c.model, UDim2.fromScale(1, 1), true, 4)
		Ui.text({ Text = cd.name, TextSize = 12, TextColor3 = LINE, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(3, 68), Size = UDim2.new(1, -6, 0, 15), ZIndex = 4, Parent = b })
		rarityTag(b, c.rarity, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 87), ZIndex = 4 })
		b.Activated:Connect(function()
			picked = c.uid
			onTab("storage")
		end)
	end
	for i = 1, math.max(0, data.STORAGE_MAX - #junk) do
		local e = Ui.new("TextButton", { LayoutOrder = #junk + i, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, ZIndex = 4, Parent = spots }, {
			Ui.corner(12),
			Ui.stroke(3, Color3.fromHex("#b9b4a8"), 0.3),
		})
		Ui.text({ Text = "P", TextSize = 28, TextColor3 = Color3.fromHex("#b9b4a8"), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = e })
		e.Activated:Connect(function()
			onTab("find")
		end)
	end
	if not pick then
		Ui.buy({ LayoutOrder = order + 3, Size = UDim2.fromOffset(260, 42), ZIndex = 4, Parent = parent }, "🔍 Search a lot for cars", "garage", function()
			onTab("find")
		end, 17)
	end
end

-- ── Find cars ──────────────────────────────────────────────────────────────────────────────────

local function truckRow(parent: Instance, order: number, s: any)
	local truck = s.truck or 0
	local t = data.truckOf(truck)
	local nextT = data.TRUCK[truck + 2]
	local row = darkCard({ LayoutOrder = order, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = parent })
	local items = Ui.new("Frame", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), BackgroundTransparency = 1, ZIndex = 4, Parent = row }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.text({ LayoutOrder = 1, Text = "🛻", TextSize = 26, Size = UDim2.fromOffset(32, 40), ZIndex = 4, Parent = items })
	local pips = Ui.new("Frame", { LayoutOrder = 2, Size = UDim2.fromOffset(#data.TRUCK * 18, 14), BackgroundTransparency = 1, ZIndex = 4, Parent = items }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4) }),
	})
	for i = 1, #data.TRUCK do
		local on = i - 1 <= truck
		Ui.new("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = if on then Color3.fromHex("#ffb300") else Color3.fromHex("#55617a"), ZIndex = 4, Parent = pips }, {
			Ui.corner(4),
			Ui.stroke(2, if on then Color3.fromHex("#fff3c4") else Color3.fromHex("#7c879c")),
		})
	end
	Ui.text({ LayoutOrder = 3, Text = `📍{t.pins}{if nextT then ` <font color="#9fe39a" size="14">→{nextT.pins}</font>` else ""}`, RichText = true, TextSize = 18, Size = UDim2.fromOffset(80, 40), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, Parent = items }).RichText = true
	if t.magnet then
		Ui.text({ LayoutOrder = 4, Text = "🧲", TextSize = 18, Size = UDim2.fromOffset(24, 40), ZIndex = 4, Parent = items })
	end
	local holder = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 34), BackgroundTransparency = 1, ZIndex = 4, Parent = row })
	if not nextT then
		Ui.buy({ Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = holder }, "MAX", "grey", nil, 17)
	elseif store.gateLevel(s) < nextT.level then
		Ui.buy({ Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = holder }, `🔒 Lv {nextT.level}`, "grey", nil, 16)
	else
		local _, up = Ui.buy({ Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = holder }, `⬆ ⚙️{nextT.parts}`, if (s.parts or 0) < nextT.parts then "broke" else "green", function()
			Remote.act("upgradeTruck")
		end, 17)
		up.Name = "UpgradeTruck"
	end
end

local function spotCard(parent: Instance, order: number, s: any, sp: any, hot: string)
	local gate = store.gateLevel(s)
	local locked = gate < sp.unlockLevel
	local broke = not locked and s.coins < sp.cost
	local full = #(s.junkyard or {}) >= data.STORAGE_MAX
	local setId = data.rustySetId(sp.id)
	local set: any = nil
	for _, x in data.RUSTY_SETS do
		if x.id == setId then
			set = x
		end
	end
	local n = 0
	for _, m in set.cars do
		if hasCar(s.cars, m) then
			n += 1
		end
	end
	local done = n == #set.cars
	local paid = table.find(s.claimedSets or {}, set.id) ~= nil
	local isHot = hot == sp.id and not locked

	local card = Ui.new("TextButton", { Name = sp.id, LayoutOrder = order, Text = "", AutoButtonColor = false, BackgroundColor3 = Ui.WHITE, ClipsDescendants = true, ZIndex = 4, Parent = parent }, {
		Ui.corner(16),
		Ui.stroke(2.5, LINE),
	})
	card.Activated:Connect(function()
		if full and not locked then
			return
		end
		seenPins, found = nil, nil
		Remote.act("startSearch", sp.id)
	end)
	local look = SPOT_LOOK[sp.id] or SPOT_LOOK.suburbs
	local art = Ui.new("Frame", { Size = UDim2.new(1, 0, 1, -50), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = card }, {
		Ui.corner(14),
		Ui.gradient(look[1], look[2]),
	})
	Ui.text({ Text = sp.icon, TextSize = 64, TextTransparency = 0.55, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = art })
	Ui.text({ Text = `{sp.icon} {sp.name}`, TextSize = 21, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -90, 0, 28), Shadow = 2, ZIndex = 5, Parent = art })
	if not locked then
		if done and not paid then
			local claim = Ui.new("TextButton", { Name = "Claim", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(84, 26), BackgroundColor3 = Ui.WHITE, ZIndex = 5, Parent = art }, {
				Ui.round(),
				Ui.stroke(2, LINE),
				Ui.gradient("#8ef05c", "#2fae35"),
			})
			Ui.text({ Text = `🎁 💎{set.bucks}`, TextSize = 15, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = claim })
			claim.Activated:Connect(function()
				Remote.act("claimSet", set.id)
			end)
		else
			local got = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(70, 24), BackgroundColor3 = if paid then Ui.WHITE else LINE, BackgroundTransparency = if paid then 0 else 0.28, ZIndex = 5, Parent = art }, {
				Ui.round(),
				Ui.stroke(2, if paid then LINE else Ui.WHITE, if paid then 0 else 0.5),
				if paid then Ui.gradient("#ffd54f", "#ff9800") else nil,
			})
			Ui.text({ Text = `{if paid then "👑" else "✔"} {n}/{#set.cars}`, TextSize = 15, TextColor3 = if paid then LINE else Ui.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = got })
		end
	end
	if sp.id == PIECE_SPOT then
		local piece = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, if isHot then -44 else -8), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Ui.WHITE, ZIndex = 5, Parent = art }, {
			Ui.round(),
			Ui.stroke(2, LINE),
			Ui.gradient("#b388ff", "#6a1b9a"),
		})
		Ui.text({ Text = "🧩", TextSize = 19, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = piece })
	end
	if isHot then
		local tip = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.WHITE, ZIndex = 5, Parent = art }, {
			Ui.round(),
			Ui.stroke(2, LINE),
			Ui.gradient("#ff8a50", "#e64a19"),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
		})
		Ui.text({ Text = `🔥 {data.HOT_RARE}× Rare`, TextSize = 15, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 5, Parent = tip })
	end
	local go = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -8), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.WHITE, ZIndex = 5, Parent = art }, {
		Ui.corner(12),
		Ui.stroke(2, LINE),
		Ui.gradient(if locked then "#90a4ae" elseif broke then "#ff9a8a" else "#8ef05c", if locked then "#546e7a" elseif broke then "#d6383b" else "#2fae35"),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
	})
	Ui.text({ Text = if locked then `🔒 Lv {sp.unlockLevel}` else `🪙 {Ui.commas(sp.cost)}`, TextSize = 19, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Shadow = 2, ZIndex = 5, Parent = go })

	-- The cars this lot can turn up: ticked when restored, rusty until then.
	local strip = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Color3.fromHex("#eef2f8"), ZIndex = 4, Parent = card }, {
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }),
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 2.5), BackgroundColor3 = LINE, BorderSizePixel = 0, ZIndex = 4, Position = UDim2.new(0, 0, 1, -50), Parent = card })
	for i, c in sp.cars do
		local own = hasCar(s.cars, c.model)
		local cell = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.new(0, 10, 1, 0), BackgroundColor3 = if c.rarity == "rare" then Color3.fromHex("#fff6e0") else Ui.WHITE, ZIndex = 4, Parent = strip }, {
			Ui.corner(8),
			Ui.stroke(2, Color3.fromHex(if c.rarity == "rare" then "#ffb300" elseif c.rarity == "scarce" then "#64b5f6" else "#cfd8e3")),
		})
		carPic(cell, c.model, UDim2.fromScale(1, 1), not own, 4)
		if own then
			local tick = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 3, 0, -5), Size = UDim2.fromOffset(17, 17), BackgroundColor3 = Color3.fromHex("#2fae3a"), ZIndex = 5, Parent = cell }, { Ui.round(), Ui.stroke(1.5, Ui.WHITE) })
			Ui.text({ Text = "✔", TextSize = 11, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = tick })
		end
	end
	-- A full lot: the open spots fade, as the web's disabled cards.
	if full and not locked then
		Ui.new("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.SHEET, BackgroundTransparency = 0.4, BorderSizePixel = 0, ZIndex = 7, Parent = card }, { Ui.corner(16) })
	end
end

local ALL_FINDS: { string } = {}
do
	local seen = {}
	for _, sp in data.RESCUE_SPOTS do
		for _, c in sp.cars do
			if not seen[c.model] then
				seen[c.model] = true
				table.insert(ALL_FINDS, c.model)
			end
		end
	end
end

local function findTab(parent: Instance, order: number, s: any, onTab: (string) -> ())
	if #(s.junkyard or {}) >= data.STORAGE_MAX then
		local full = Ui.new("TextButton", { LayoutOrder = order, Text = "", AutoButtonColor = false, Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromHex("#ffebee"), ZIndex = 4, Parent = parent }, {
			Ui.corner(12),
			Ui.stroke(2, Color3.fromHex("#ef9a9a")),
		})
		Ui.text({ Text = "🚗 Your lot is full · restore or scrap a car", TextSize = 14, TextColor3 = Color3.fromHex("#b71c1c"), Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = full })
		full.Activated:Connect(function()
			onTab("storage")
		end)
	end
	-- How many of Rusty's cars are in the garage.
	local got = 0
	for _, m in ALL_FINDS do
		if hasCar(s.cars, m) then
			got += 1
		end
	end
	local dex = Ui.new("Frame", { LayoutOrder = order + 1, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, ZIndex = 4, Parent = parent })
	Ui.text({ Text = "🔧", TextSize = 24, Size = UDim2.fromOffset(30, 30), ZIndex = 4, Parent = dex })
	local bar = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 40, 0.5, 0), Size = UDim2.new(1, -110, 0, 16), BackgroundColor3 = Color3.fromHex("#dfe6ef"), ClipsDescendants = true, ZIndex = 4, Parent = dex }, {
		Ui.round(),
		Ui.stroke(2.5, LINE),
	})
	Ui.new("Frame", { Size = UDim2.new(got / #ALL_FINDS, 6, 1, 0), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = bar }, { Ui.round(), Ui.gradient("#ffe082", "#ffa000") })
	Ui.text({ Text = `{got}/{#ALL_FINDS}`, TextSize = 20, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(64, 30), ZIndex = 4, Parent = dex })
	truckRow(parent, order + 2, s)
	local grid = Ui.new("Frame", { LayoutOrder = order + 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 4, Parent = parent }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -10, 0, 168), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingBottom = UDim.new(0, 6) }),
	})
	local hot = data.hotSpot(s.level)
	for i, sp in data.RESCUE_SPOTS do
		spotCard(grid, i, s, sp, hot)
	end
end

-- ── The search ─────────────────────────────────────────────────────────────────────────────────

local SMALLS = { "coins", "parts", "fuel", "trophy" }
local SMALL_ICON = { coins = "🪙", parts = "⚙️", fuel = "⛽", trophy = "🏆" }

-- The small finds added up, one count per kind.
local function sums(items: { any }): { [string]: number }
	local sum = { coins = 0, parts = 0, fuel = 0, trophy = 0 }
	for _, l in items do
		if l.kind == "trophy" then
			sum.trophy += 1
		elseif sum[l.kind] then
			sum[l.kind] += l.n
		end
	end
	return sum
end

local function smallText(k: string, v: number): string
	return if k == "trophy" and v <= 1 then SMALL_ICON[k] else `{SMALL_ICON[k]} {Ui.commas(v)}`
end

-- One small find's chip (the web's .haul-item). Returns it and its count.
local function smallChip(parent: Instance, order: number, k: string, z: number): (Frame, TextLabel)
	local chip = Ui.new("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = parent }, {
		Ui.corner(10),
		Ui.stroke(2, Color3.fromHex("#e0e0e0")),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	local label = Ui.text({ Text = "", Body = true, Weight = "heavy", TextSize = 15, TextColor3 = LINE, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = z, Parent = chip })
	return chip, label
end

-- The haul so far, as the web's Haul: each car with its rarity, then one chip per kind of small
-- find. was: the counts shown last time, which roll up to the new ones (and are updated).
local function haulChips(parent: Instance, items: { any }, z: number, was: { [string]: number }?)
	local order = 0
	for _, l in items do
		if l.kind == "car" then
			order += 1
			local chip = Ui.new("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(110, 32), BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = parent }, {
				Ui.corner(10),
				Ui.stroke(2, Color3.fromHex(RARITY_EDGE[l.rarity])),
			})
			local box = Ui.new("Frame", { Size = UDim2.fromOffset(40, 32), BackgroundTransparency = 1, ZIndex = z, Parent = chip })
			carPic(box, l.model, UDim2.fromScale(1, 1), true, z)
			rarityTag(chip, l.rarity, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 42, 0.5, 0), ZIndex = z })
		end
	end
	local sum = sums(items)
	for _, k in SMALLS do
		local v = sum[k]
		if v > 0 then
			order += 1
			local _, label = smallChip(parent, order, k, z)
			-- A new chip shows its count; one already there rolls up to its new count.
			local from = if was and (was[k] or 0) > 0 then was[k] else v
			rollUp(label, from, v, function(n)
				return smallText(k, n)
			end)
		end
		if was then
			was[k] = v
		end
	end
end

-- The find just uncovered, popped up under the top bar for a moment (the web's .rs-found).
local function foundPop(screen: Instance, l: any, z: number): Frame
	local edge = if l.kind == "car" and l.rarity ~= "common" then RARITY_EDGE[l.rarity] else "#ffca28"
	local pop = Ui.new("Frame", { Name = "Found", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), Size = UDim2.fromOffset(0, 46), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = screen }, {
		Ui.round(),
		Ui.stroke(3, Color3.fromHex(edge)),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, if l.kind == "car" then 4 else 8), PaddingRight = UDim.new(0, 16) }),
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local icon, text = lootLabel(l)
	if l.kind == "car" then
		local box = Ui.new("Frame", { LayoutOrder = 1, Size = UDim2.fromOffset(52, 38), BackgroundTransparency = 1, ZIndex = z, Parent = pop })
		carPic(box, l.model, UDim2.fromScale(1, 1), true, z)
	else
		Ui.text({ LayoutOrder = 1, Text = icon, TextSize = 26, Size = UDim2.fromOffset(32, 38), ZIndex = z, Parent = pop })
	end
	Ui.text({ LayoutOrder = 2, Text = text, TextSize = 18, TextColor3 = if l.kind == "car" and l.rarity == "rare" then Color3.fromHex("#e65100") else LINE, Size = UDim2.fromOffset(0, 38), AutomaticSize = Enum.AutomaticSize.X, ZIndex = z, Parent = pop })
	if l.kind == "car" then
		rarityTag(pop, l.rarity, { LayoutOrder = 3, ZIndex = z })
	end
	popIn(pop)
	return pop
end

-- The search, full screen as the web's SearchScreen: Rusty's tow truck drives a 3D lot
-- (RescueLot) and the controls float over it, like a race. The HUD steps aside for the lot's own
-- screen, laid out the same way (the web's 1280x800, scaled to fit), and the lot takes the camera.
local scene: any = nil
local searchGui: ScreenGui? = nil
local hudGui: ScreenGui? = nil
local busyNow = true
-- Finds that have flown into the tray (the web's `aboard`), and the redraw the lot's news calls.
local aboard: { [number]: boolean } = {}
local redraw: (() -> ())? = nil

-- Back to town: the lot and its screen go, the HUD and the town camera come back.
local function endSearch()
	if scene then
		scene:close()
		scene = nil
	end
	if searchGui then
		searchGui:Destroy()
		searchGui = nil
	end
	if hudGui then
		hudGui.Enabled = true
		hudGui = nil
		TownCamera.setPaused(false)
	end
	redraw = nil
end

-- A button faded as the web's :disabled (opacity .55).
local function dim(g: Instance)
	for _, d in { g, table.unpack(g:GetDescendants()) } do
		if d:IsA("GuiObject") then
			d.BackgroundTransparency = 1 - (1 - d.BackgroundTransparency) * 0.55
			if d:IsA("TextLabel") or d:IsA("TextButton") then
				d.TextTransparency = 1 - (1 - d.TextTransparency) * 0.55
			end
		elseif d:IsA("UIStroke") then
			d.Transparency = 1 - (1 - d.Transparency) * 0.55
		end
	end
end

-- A find flying from where it came up to the end of the tray (the web's rs-fly), then aboard.
local function fly(screen: Instance, l: any, from: Vector2, to: Vector2, landed: () -> ())
	local edge = if l.kind == "car" and l.rarity ~= "common" then RARITY_EDGE[l.rarity] else "#ffca28"
	local car = l.kind == "car"
	local bit = Ui.new("Frame", { Name = "Fly", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(from.X, from.Y), Size = UDim2.fromOffset(if car then 56 else 44, 44), BackgroundColor3 = Ui.WHITE, ZIndex = 30, Parent = screen }, {
		if car then Ui.corner(14) else Ui.round(),
		Ui.stroke(3, Color3.fromHex(edge)),
	})
	if car then
		carPic(bit, l.model, UDim2.fromScale(1, 1), true, 30)
	else
		Ui.text({ Text = (lootLabel(l)), TextSize = 24, Size = UDim2.fromScale(1, 1), ZIndex = 30, Parent = bit })
	end
	local mid = UDim2.fromOffset((from.X + to.X) / 2, math.min(from.Y, to.Y) - 60)
	local up = TweenService:Create(bit, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(from.X, from.Y - 30) })
	up:Play()
	task.delay(0.15, function()
		if not bit.Parent then
			return
		end
		TweenService:Create(bit, TweenInfo.new(0.26, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = mid }):Play()
		task.wait(0.26)
		if not bit.Parent then
			return
		end
		TweenService:Create(bit, TweenInfo.new(0.34, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(if car then 31 else 24, 24) }):Play()
		task.wait(0.34)
		bit:Destroy()
		landed()
	end)
	-- Gone in any case, should a tween never finish.
	task.delay(1.5, function()
		if bit.Parent then
			bit:Destroy()
			landed()
		end
	end)
end

local function searchScreen(ctx: any, q: any, root: Instance, rerender: () -> ())
	local s = store.useGame.getState()
	local spot: any = nil
	for _, sp in data.RESCUE_SPOTS do
		if sp.id == q.spot then
			spot = sp
		end
	end
	local magnet = data.truckOf(s.truck).magnet == true
	if q.flat then
		auto = false
	end
	redraw = rerender

	-- The lot's own screen over the scene (as DragStrip's), made once per search.
	local frame: Frame = ctx.gui
	if not searchGui then
		hudGui = frame:FindFirstAncestorOfClass("ScreenGui")
		local gui = Ui.new("ScreenGui", { Name = "RescueSearch", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = (hudGui :: ScreenGui).Parent })
		local hudScale = frame:FindFirstChildOfClass("UIScale")
		local layer = Ui.new("Frame", { Name = "SearchScreen", Size = frame.Size, BackgroundTransparency = 1, Parent = gui }, {
			Ui.new("UIScale", { Scale = if hudScale then hudScale.Scale else 1 }),
		})
		-- Follow the HUD's fit when the window changes.
		local fitConn = frame:GetPropertyChangedSignal("Size"):Connect(function()
			layer.Size = frame.Size
			local sc = layer:FindFirstChildOfClass("UIScale")
			if sc and hudScale then
				sc.Scale = hudScale.Scale
			end
		end)
		gui.Destroying:Connect(function()
			fitConn:Disconnect()
		end)
		searchGui = gui;
		(hudGui :: ScreenGui).Enabled = false
		TownCamera.setPaused(true)
		busyNow = true
	end
	local holder = (searchGui :: ScreenGui):FindFirstChild("SearchScreen") :: Frame
	for _, c in holder:GetChildren() do
		if not c:IsA("UIScale") and c.Name ~= "Fly" then
			c:Destroy()
		end
	end

	-- What was already uncovered when the lot came up is seen and aboard; anything after waits
	-- for its tarp to come off (onFound), so nothing is spoiled.
	if not seenPins then
		seenPins = {}
		aboard = {}
		local was = {}
		for i, r in q.revealed do
			if r then
				(seenPins :: any)[i] = true
				aboard[i] = true
				table.insert(was, q.pins[i])
			end
		end
		trayWas = sums(was)
	end
	local haul = {}
	for i, l in q.pins do
		if aboard[i] and l.kind ~= "nothing" then
			table.insert(haul, l)
		end
	end
	local left, started = 0, false
	for _, r in q.revealed do
		if r then
			started = true
		else
			left += 1
		end
	end
	if left == 0 then
		auto = false
	end

	local screen = Ui.new("Frame", { Name = "Search", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20, Parent = holder })
	-- The bottom's shade (the web's linear-gradient(transparent, rgba(10,20,40,.5))).
	Ui.new("Frame", { Name = "Shade", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = Color3.fromHex("#0a1428"), BorderSizePixel = 0, ZIndex = 20, Parent = screen }, {
		Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.5) }) }),
	})

	-- The lot itself.
	local function onFound(i: number, at: Vector2)
		(seenPins :: any)[i] = true
		found = { i = i, at = os.clock() }
		local l = (Remote.search or q).pins[i]
		if redraw then
			redraw()
		end
		if l.kind == "nothing" then
			return
		end
		task.delay(0.45, function()
			local gui = searchGui
			local box = gui and gui:FindFirstChild("Tray", true) :: GuiObject?
			if not gui or not box then
				aboard[i] = true
				return
			end
			local layer = gui:FindFirstChild("SearchScreen") :: Frame
			local scale = (layer:FindFirstChildOfClass("UIScale") :: UIScale).Scale
			local vp = workspace.CurrentCamera.ViewportSize
			local from = Vector2.new(at.X * vp.X, at.Y * vp.Y) / scale
			local trayAt = (box.AbsolutePosition - layer.AbsolutePosition) / scale
			local to = Vector2.new(trayAt.X + 22, trayAt.Y + box.AbsoluteSize.Y / scale / 2)
			local last = 0
			for _, c in box:GetChildren() do
				if c:IsA("GuiObject") then
					last = math.max(last, (c.AbsolutePosition.X + c.AbsoluteSize.X - box.AbsolutePosition.X) / scale)
				end
			end
			if last > 0 then
				to = Vector2.new(trayAt.X + math.min(box.AbsoluteSize.X / scale - 20, last + 18), to.Y)
			end
			fly(layer, l, from, to, function()
				if aboard[i] then
					return
				end
				aboard[i] = true
				Sfx.rescue.tick(4)
				if redraw then
					redraw()
				end
			end)
		end)
	end
	if not scene then
		scene = RescueLot.open(q, magnet, {
			onArrive = function(i: number)
				Remote.act("revealPin", i - 1)
			end,
			onFound = onFound,
			onLeft = function()
				local cur = Remote.search or q
				local items = {}
				for i, l in cur.pins do
					if cur.revealed[i] and l.kind ~= "nothing" then
						table.insert(items, l)
					end
				end
				recap = { items = items, piece = cur.piece }
				Remote.act("towHome")
			end,
			onBusy = function(b: boolean)
				busyNow = b
				if redraw then
					redraw()
				end
			end,
		})
	end
	scene:update(q, { auto = auto, leaving = leaving, magnet = magnet })

	-- Along the top: where, and the way out.
	Ui.text({ Name = "Title", Text = `{spot.icon} {spot.name}`, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(400, 38), Stroke = 3, Shadow = 3, ZIndex = 21, Parent = screen })
	Ui.closeButton({ Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(36, 36), ZIndex = 21, Parent = screen }, ctx.close)

	-- One dot per spot: a find's icon once seen, pulsing yellow where the truck has just looked.
	local dots = Ui.new("Frame", { Name = "Dots", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(#q.revealed * 32 - 6, 26), BackgroundTransparency = 1, ZIndex = 21, Parent = screen }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, r in q.revealed do
		local l = q.pins[i]
		local open = (seenPins :: any)[i] == true
		local here = r and not open
		local dot = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(26, 26), BackgroundColor3 = if open then Ui.WHITE elseif here then Color3.fromHex("#ffd54f") else Color3.fromHex("#1b1f24"), BackgroundTransparency = if open then 0 elseif here then 0.15 else 0.55, ZIndex = 21, Parent = dots }, {
			Ui.round(),
			Ui.stroke(2, if open and l.kind == "car" then Color3.fromHex(RARITY_EDGE[l.rarity]) elseif open then Color3.fromHex("#ffca28") else Ui.WHITE, if open then 0 else 0.25),
			Ui.text({ Text = if open then (lootLabel(l)) else "", TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 21 }),
		})
		if not open and not here then
			-- The gold inner ring (box-shadow: inset 0 0 0 3px rgba(255,213,79,.55)).
			Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1, ZIndex = 21, Parent = dot }, {
				Ui.round(),
				Ui.stroke(3, Color3.fromHex("#ffd54f"), 0.45),
			})
		end
	end
	local f = found
	if f and os.clock() - f.at < FOUND_SECONDS then
		local pop = foundPop(screen, q.pins[f.i], 22)
		pop.Position = UDim2.new(0.5, 0, 0, 92)
		task.delay(FOUND_SECONDS - (os.clock() - f.at), function()
			if pop.Parent then
				pop:Destroy()
			end
		end)
	elseif not started and not busyNow and not auto then
		local coach = Ui.new("Frame", { Name = "Coach", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(0, 36), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#1b1f24"), BackgroundTransparency = 0.4, ZIndex = 21, Parent = screen }, {
			Ui.round(),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }),
		})
		Ui.text({ Text = "👆 Tap a glowing spot", TextSize = 18, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 21, Parent = coach })
		-- It bobs, as the web's coach animation.
		TweenService:Create(coach, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.new(0.5, 0, 0, 96) }):Play()
	end

	-- Leaving throws the haul away, so it asks first (unless the player said not to).
	local function leave()
		if leaving then
			return
		end
		if #haul == 0 then
			Remote.act("abandonSearch")
			return
		end
		auto = false
		Confirm.ask(screen, {
			pref = "askLeave",
			icon = "🛻",
			title = "Leave your haul?",
			ok = "Leave",
			body = function(box)
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Wraps = true, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = box })
				haulChips(box, haul, 41)
			end,
			bodyHeight = if #haul > 4 then 96 else 56,
			z = 41,
			onOk = function()
				Remote.act("abandonSearch")
			end,
		})
	end

	-- A flat tire: fix it for gems, or go home with nothing.
	if q.flat then
		local pop = Ui.new("Frame", { Name = "Flat", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -134), Size = UDim2.fromOffset(340, 110), BackgroundColor3 = Ui.WHITE, ZIndex = 23, Parent = screen }, {
			Ui.corner(18),
			Ui.stroke(3, LINE),
		})
		popIn(pop)
		Ui.text({ Text = "🛞 Flat tire!", TextSize = 22, TextColor3 = LINE, Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 30), ZIndex = 23, Parent = pop })
		local short = data.TOW_FIX_BUCKS - (s.bucks or 0)
		local _, fix = Ui.buy({ Position = UDim2.fromOffset(14, 54), Size = UDim2.new(0.5, -20, 0, 42), ZIndex = 23, Parent = pop }, `Fix · 💎 {data.TOW_FIX_BUCKS}{if short > 0 then ` (need {short})` else ""}`, "green", function()
			Remote.act("fixTruck")
		end, 15)
		fix.Name = "FixTruck"
		local _, home = Ui.buy({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 54), Size = UDim2.new(0.5, -20, 0, 42), ZIndex = 23, Parent = pop }, "Go home", "broke", leave, 16)
		home.Name = "GoHome"
	end

	-- Along the bottom: the haul so far over the buttons, centred and no wider than 560 (the web's
	-- .rs-bottom on a wide screen).
	local bottom = Ui.new("Frame", { Name = "Bottom", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.new(1, -24, 0, 92), BackgroundTransparency = 1, ZIndex = 21, Parent = screen }, {
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(560, 92) }),
	})
	local tray = Ui.new("Frame", { Name = "Tray", Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 22, Parent = bottom }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	if #haul > 0 then
		haulChips(tray, haul, 22, trayWas)
	else
		Ui.text({ Name = "Empty", Text = "🛻 Haul is empty", TextSize = 15, Size = UDim2.fromOffset(200, 32), TextXAlignment = Enum.TextXAlignment.Left, Shadow = 2, ZIndex = 22, Parent = tray })
	end
	local acts = Ui.new("Frame", { Name = "Actions", Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 0, 48), BackgroundTransparency = 1, ZIndex = 22, Parent = bottom }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalFlex = Enum.UIFlexAlignment.Fill, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	-- Leave: the web's small white .sell button with its red outline.
	local leaveF, leaveB = Ui.button({ LayoutOrder = 1, Size = UDim2.new(0, 58, 1, 0), ZIndex = 22, Parent = acts }, "white", leave, {
		radius = 12,
		stroke = 2.5,
		drop = 2,
		dark = 0.2,
		strokeColor = Color3.fromHex("#d6283b"),
		text = "Leave",
		textSize = 15,
		textColor = Color3.fromHex("#d6283b"),
	})
	leaveB.Name = "Leave"
	Ui.new("UIFlexItem", { FlexMode = Enum.UIFlexMode.None, Parent = leaveF })
	if leaving then
		dim(leaveF)
	end
	if left > 0 then
		local off = q.flat or leaving
		local allF, all = Ui.buy({ LayoutOrder = 2, Size = UDim2.new(0, 200, 1, 0), ZIndex = 22, Parent = acts }, if auto then "⏸ Stop" else "⏩ Search all", "garage", function()
			if q.flat or leaving then
				return
			end
			auto = not auto
			rerender()
		end, 18)
		all.Name = "SearchAll"
		if off then
			dim(allF)
		end
	end
	local canHome = started and not q.flat and not leaving
	local homeF, home = Ui.buy({ LayoutOrder = 3, Size = UDim2.new(0, 200, 1, 0), ZIndex = 22, Parent = acts }, "🏠 Tow home", "green", function()
		if not canHome then
			return
		end
		auto = false
		leaving = true
		Sfx.rescue.home()
		rerender()
	end, 18)
	home.Name = "TowHome"
	if not canHome then
		dim(homeF)
	elseif left == 0 then
		-- Every spot checked: Tow home bobs (the web's .rs-home.ready).
		TweenService:Create(home, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = home.Position + UDim2.fromOffset(0, 3) }):Play()
	end
end

-- ── Back home: the haul, and a restored car's plate ────────────────────────────────────────────

-- Back from a search: the haul laid out one find at a time, as the web's HaulCard. Cars first,
-- best first, then the small finds summed, each landing on a beat (450ms, then every 260ms) with
-- its count rolling up; the resto-mod piece and the XP last.
local function haulCard(ctx: any, body: Instance, r: { items: { any }, piece: any?, at: number? }, onDone: (string) -> ())
	local s = store.useGame.getState()
	local cars = {}
	for _, l in r.items do
		if l.kind == "car" then
			table.insert(cars, l)
		end
	end
	table.sort(cars, function(a, b)
		return RARITY_ORDER[a.rarity] > RARITY_ORDER[b.rarity]
	end)
	local sum = sums(r.items)
	local smalls = {}
	for _, k in SMALLS do
		if sum[k] > 0 then
			table.insert(smalls, k)
		end
	end
	local total = #cars + #smalls
	-- Redrawn mid-reveal (a new snapshot): what has landed already shows at once.
	if not r.at then Sfx.rescue.fanfare(cars[1] ~= nil and cars[1].rarity == "rare") end
	local t0 = r.at or os.clock()
	r.at = t0
	local function onBeat(n: number, show: (instant: boolean) -> ())
		local wait = 0.45 + n * 0.26 - (os.clock() - t0)
		if wait <= 0 then
			show(true)
		else
			task.delay(wait, function()
				show(false)
			end)
		end
	end

	local list = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 12), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.text({ LayoutOrder = 1, Text = "🛻", TextSize = 44, Size = UDim2.new(1, 0, 0, 50), Parent = list })
	if #cars > 0 then
		local grid = Ui.new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = list }, {
			Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(128, 128), CellPadding = UDim2.fromOffset(10, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i, c in cars do
			-- Each spot in the grid keeps its place while its car is still to land.
			local slot = Ui.new("Frame", { LayoutOrder = i, BackgroundTransparency = 1, Parent = grid })
			local cell = Ui.new("Frame", { Name = "Car", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, Visible = false, Parent = slot }, {
				Ui.corner(14),
				Ui.stroke(3, Color3.fromHex(RARITY_EDGE[c.rarity])),
			})
			local box = Ui.new("Frame", { Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 66), BackgroundTransparency = 1, Parent = cell })
			carPic(box, c.model, UDim2.fromScale(1, 1), true, 1)
			Ui.text({ Text = data.carDef(c.model).name, TextSize = 13, TextColor3 = LINE, TextWrapped = true, Position = UDim2.fromOffset(4, 74), Size = UDim2.new(1, -8, 0, 30), Parent = cell })
			rarityTag(cell, c.rarity, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 104), ZIndex = 1 })
			onBeat(i - 1, function(instant)
				if instant then
					cell.Visible = true
				else
					popIn(cell)
					if cell.Parent then Sfx.rescue.reveal(if c.rarity == "common" then "small" else c.rarity) end
				end
			end)
		end
	end
	local row = Ui.new("Frame", { LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, Parent = list }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for n, k in smalls do
		local chip, label = smallChip(row, n, k, 1)
		chip.Visible = false
		Ui.setText(label, smallText(k, 0))
		onBeat(#cars + n - 1, function(instant)
			if instant then
				chip.Visible = true
				Ui.setText(label, smallText(k, sum[k]))
			else
				popIn(chip)
				if chip.Parent then Sfx.rescue.tick((#cars + n - 1) * 2) end
				rollUp(label, 0, sum[k], function(v)
					return smallText(k, v)
				end)
			end
		end)
	end
	local last: { GuiObject } = {}
	if r.piece then
		-- The resto-mod piece: the car's puzzle with the new piece glowing.
		local have = resto.piecesOf(s.restoParts or {}, r.piece.model)
		local chip = Ui.new("Frame", { Name = "Piece", LayoutOrder = 90, Size = UDim2.fromOffset(0, 54), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.WHITE, Visible = false, Parent = row }, {
			Ui.corner(10),
			Ui.stroke(2, Color3.fromHex("#e0e0e0")),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 8) }),
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		BuildArt.new(chip, r.piece.model, have, UDim2.fromOffset(64, 48), { fresh = r.piece.piece, iconSize = 10, LayoutOrder = 1 })
		Ui.text({ LayoutOrder = 2, Text = "🧩", TextSize = 18, Size = UDim2.fromOffset(22, 48), Parent = chip })
		table.insert(last, chip)
	end
	local xp = data.xpGain(s.level, 10 + #cars * 10)
	local xpChip = Ui.new("Frame", { LayoutOrder = 99, Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex("#fff8e1"), Visible = false, Parent = row }, {
		Ui.corner(10),
		Ui.stroke(2, Color3.fromHex("#ffca28")),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
	})
	Ui.text({ Text = `⭐ +{xp} XP`, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = LINE, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = xpChip })
	table.insert(last, xpChip)
	onBeat(total, function(instant)
		for _, g in last do
			if instant then
				g.Visible = true
			else
				popIn(g)
			end
		end
	end)
	local go = if #cars > 0 then "🔧 Fix one up" else "🔍 Search again"
	local _, b = Ui.buy({ LayoutOrder = 4, Size = UDim2.fromOffset(220, 46), Parent = list }, go, "green", function()
		onDone(if #cars > 0 then "storage" else "find")
	end, 18)
	b.Name = "HaulDone"
	local _ = ctx
end

local function plateScreen(ctx: any, body: Instance, s: any, bay: number)
	local r = if bay == 1 then s.restoring2 else s.restoring
	if not r then
		naming = nil
		return
	end
	local d = data.carDef(r.model)
	local list = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local stage = Ui.new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 200), BackgroundColor3 = Color3.fromHex("#d9efc6"), Parent = list }, { Ui.corner(16) })
	carPic(stage, r.model, UDim2.fromScale(1, 1), false, 1)
	local title = Ui.new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = list }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.text({ LayoutOrder = 1, Text = d.name, TextSize = 24, TextColor3 = LINE, Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Parent = title })
	rarityTag(title, r.rarity, { LayoutOrder = 2, ZIndex = 1 })
	Ui.text({ LayoutOrder = 3, Text = "Name your car on its license plate. You can't change it later.", Body = true, TextSize = 14, TextColor3 = Color3.fromHex("#546e7a"), Size = UDim2.new(1, 0, 0, 20), Parent = list })
	local plate = Ui.new("TextBox", {
		Name = "Plate",
		LayoutOrder = 4,
		Text = "",
		PlaceholderText = "RUSTY1",
		PlaceholderColor3 = Color3.fromHex("#9fa8da"),
		ClearTextOnFocus = false,
		FontFace = Ui.DISPLAY,
		TextSize = 30,
		TextColor3 = Color3.fromHex("#1a237e"),
		Size = UDim2.fromOffset(220, 52),
		BackgroundColor3 = Color3.fromHex("#fffde7"),
		Parent = list,
	}, { Ui.corner(10), Ui.stroke(4, Color3.fromHex("#1a237e")) })
	-- Plates are A-Z, 0-9 and spaces, up to seven, as the web's input.
	plate:GetPropertyChangedSignal("Text"):Connect(function()
		local clean = plate.Text:upper():gsub("[^A-Z0-9 ]", ""):sub(1, 7)
		if clean ~= plate.Text then
			plate.Text = clean
		end
	end)
	local _, add = Ui.buy({ LayoutOrder = 5, Size = UDim2.fromOffset(240, 46), Parent = list }, "Add to my garage", "green", function()
		-- The restored car keeps the bay's uid: the garage opens on it.
		local id = r.uid
		local ok = Remote.act("collectRestored", plate.Text, bay)
		if ok then
			naming = nil
			store.useGame.setState({ selectedCar = id })
			ctx.open("garage")
		end
	end, 18)
	add.Name = "AddToGarage"
end

-- ── The panel ──────────────────────────────────────────────────────────────────────────────────

function Rescue.open(ctx: any): Instance?
	local s = store.useGame.getState()
	if not store.hasRusty(s) then
		ctx.toast("Build Rusty's Rescue first")
		return nil
	end
	local holder = Ui.new("Frame", { Name = "Rescue", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 20, Parent = ctx.gui })
	local alive = true
	local tickers: { () -> () } = {}
	local wasSearching = Remote.search and true or false
	-- Reopened mid-search: what's already uncovered doesn't pop up again.
	seenPins, found = nil, nil

	local function render()
		for _, c in holder:GetChildren() do
			c:Destroy()
		end
		table.clear(tickers)
		local st = store.useGame.getState()
		local q = Remote.search or nil
		-- Back from a search with cars: straight to the lot, so restoring one is right there.
		if wasSearching and not q and #(st.junkyard or {}) > 0 then
			tab = "storage"
		end
		wasSearching = q ~= nil
		scrollToPick = nil
		if q then
			searchScreen(ctx, q, holder, render)
			return
		end
		-- No search: back to town, and the next one starts afresh.
		endSearch()
		auto, leaving, seenPins, found = false, false, nil, nil
		trayWas = {}
		if naming ~= nil then
			local overlay, _, body = Ui.panel(holder, "Restored!", { width = 460, height = 470, onClose = function()
				naming = nil
				ctx.close()
			end })
			overlay.Name = "Plate"
			plateScreen(ctx, body, st, naming)
			return
		end
		if recap then
			local r = recap
			local overlay, _, body = Ui.panel(holder, "Rusty's haul", { width = 520, height = 470, onClose = function()
				recap = nil
				ctx.close()
			end })
			overlay.Name = "Haul"
			haulCard(ctx, body, r, function(nextTab)
				recap = nil
				tab = nextTab
				render()
			end)
			return
		end
		local junk = #(st.junkyard or {})
		local current = tab or (if junk > 0 then "storage" else "find")
		local overlay, _, body = Ui.panel(holder, "Rusty's Rescue", { wide = true, onClose = ctx.close, bodyTop = 0 })
		overlay.Name = "Panel"
		local items = {
			{ id = "find", label = "🔍 Find cars" },
			{ id = "storage", label = `🚗 My lot {junk}/{data.STORAGE_MAX}` },
		}
		local list = Ui.scroller({ Name = "List", Position = UDim2.fromOffset(-6, 64), Size = UDim2.new(1, 12, 1, -64), ZIndex = 4, Parent = body })
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = list })
		Ui.new("UIListLayout", { Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
		local function onTab(id: string)
			tab = id
			render()
		end
		local tabRow = Ui.tabs(body, items, current, onTab, { position = UDim2.fromOffset(-14, 0), size = UDim2.new(1, 28, 0, 54) })
		-- A full lot shows its count in red (the web's .tab-count.full).
		local lotTab = tabRow:FindFirstChild("storage")
		local lotLabel = lotTab and lotTab:FindFirstChild("Label", true) :: TextLabel?
		if lotLabel and junk >= data.STORAGE_MAX then
			lotLabel.RichText = true
			lotLabel.Text = `🚗 My lot <mark color="#e53935"><font color="#ffffff"> {junk}/{data.STORAGE_MAX} </font></mark>`
		end
		scrollToPick = function()
			local pick = list:FindFirstChild("LotPick") :: GuiObject?
			if pick then
				local y = pick.AbsolutePosition.Y - list.AbsolutePosition.Y + list.CanvasPosition.Y
				list.CanvasPosition = Vector2.new(0, math.max(0, y - (list.AbsoluteSize.Y - pick.AbsoluteSize.Y) / 2))
			end
		end
		if current == "find" then
			bays(list, 1, st, true, ctx, onTab, tickers)
			findTab(list, 10, st, onTab)
		else
			bays(list, 1, st, false, ctx, onTab, tickers)
			lot(list, 10, st, onTab)
		end
	end
	render()
	local conn = Remote.changed:Connect(render)
	task.spawn(function()
		while alive do
			task.wait(1)
			if not alive or not holder.Parent then
				break
			end
			for _, t in tickers do
				t()
			end
		end
	end)
	holder.Destroying:Connect(function()
		alive = false
		conn:Disconnect()
		endSearch()
	end)
	return holder
end

return Rescue
