--!strict
-- The Class Cups page (ui/ClassCups.tsx): pick a class, then one of its three races. Only a car of
-- that class can race. The left side shows the race, how far the car you race with is along its
-- mastery ladder and its classes' Gold and Diamond; the right side the classes, the class's three
-- races and the race's first-win prize, a free crate. The server (server/Modes/Cup) starts and
-- pays the races.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local venues = require(Game.scene_venues) :: any
local distance = require(Game.distance) :: any
local cups = require(Game.cups) :: any
local classes = require(Game.classes) :: any
local crates = require(Game.crates) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local Mastery = require(script.Parent.Parent.Mastery)
local DragStrip = require(script.Parent.Parent.DragStrip)

local Cup = {}
Cup.id = "cup"
Cup.title = "Class Cups"
Cup.mini = { icon = "🏆", label = "Class Cups" }

local GREEN = Color3.fromHex("#2fae35")
local GOT_EDGE = Color3.fromHex("#8fd694")
local GOT_BG = Color3.fromHex("#f2fff0")

-- The race picked (nil: the first one for the car you race with).
local sel: string? = nil

local function wins(s: any, id: string): number
	return (s.cups or {})[id] or 0
end

-- What a race pays now: double until it's won (ClassCups.tsx cupPrizeOf).
local function prizeOf(r: any, s: any): number
	return cups.cupPrize(r, wins(s, r.id) == 0)
end

-- The races picked first (firstCupPick): the first one not won in the car's class, else its first.
local function firstPick(s: any, car: any?): string
	if car then
		local mine = classes.classOf(car.model).id
		local any: string? = nil
		for _, r in cups.CUP_RACES do
			if r.cls == mine then
				if wins(s, r.id) == 0 then
					return r.id
				end
				any = any or r.id
			end
		end
		if any then
			return any
		end
	end
	return cups.CUP_RACES[1].id
end

-- The head chip (cupChip): classes whose whole cup is won.
function Cup.chip(s: any): string
	local n = 0
	for _, c in classes.CAR_CLASSES do
		if cups.cupWon(s.cups, c.id) then
			n += 1
		end
	end
	return `🏆 {n}/{#classes.CAR_CLASSES}`
end

local function tick(parent: Instance, x: number, y: number)
	local t = Ui.new("Frame", { Name = "Tick", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, x, 0, y), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = GREEN, ZIndex = 3, Parent = parent }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
	Ui.text({ Text = "✔", Body = true, Weight = "heavy", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = t })
end

function Cup.draw(page: Frame, ctx: any, api: any)
	local s = store.useGame.getState()
	local car = api.myCar()
	if not sel or not cups.cupRace(sel) then
		sel = firstPick(s, car)
	end
	local r = cups.cupRace(sel)
	local cls = classes.carClass(r.cls)
	local v = venues.venue(r.venue)
	local hc = data.carDef(r.car)
	local fits = car ~= nil and cups.cupFits(r, car.model)
	local got = wins(s, r.id) > 0
	local color = Color3.fromHex(r.color)
	local function pick(id: string)
		sel = id
		api.show("cup")
	end

	-- ── Left: the race, the car's mastery, and the race button ────────────────────────────────
	local left = Ui.new("Frame", { Name = "Picked", Size = UDim2.new(0.465, -6, 1, 0), BackgroundTransparency = 1, Parent = page })
	local LADDER, CLASSES, GO, GAP = 54, 50, 52, 8
	local below = (if car then LADDER + CLASSES + 2 * GAP else 0) + GO + GAP
	local _, banner = api.tile(left, { Name = "Banner", Size = UDim2.new(1, 0, 1, -below) }, if r.night then "#1b2350" else v.sky, if r.night then "#0b1030" else "#14213d", true)
	banner.ClipsDescendants = true
	-- The host in the corner (.tt-host).
	local host = Thumb.new("Cars", hc.id, UDim2.fromOffset(150, 96), color)
	host.AnchorPoint = Vector2.new(1, 0)
	host.Position = UDim2.new(1, -6, 0, 6)
	host.Parent = banner
	-- Words at the bottom: where, the cup's name, and its chips.
	Ui.text({ Text = string.upper(`{v.icon} {v.name}{if r.night then " · 🌙" else ""} · {distance.DIST[r.dist].label}`), Body = true, Weight = "heavy", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -84), Size = UDim2.new(1, -28, 0, 16), Parent = banner })
	Ui.text({ Text = `{cls.icon} {cls.name} Cup`, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -46), Size = UDim2.new(1, -28, 0, 34), Stroke = 2, Shadow = 2, Parent = banner })
	local chips = Ui.new("Frame", { Name = "Chips", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 28), BackgroundTransparency = 1, Parent = banner }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local chipList = {
		{ string.rep("🏆", r.tier) },
		{ `PI {r.pi}` },
		{ if got then `✔ ×{wins(s, r.id)}` else `🏁 {api.money(prizeOf(r, s))}`, if got then "got" else nil },
	}
	if car and not fits then
		table.insert(chipList, { `{cls.icon} only`, "need" })
	end
	for i, c in chipList do
		local look = c[2]
		local w = math.ceil(Ui.textWidth(c[1], 15)) + 22
		local f = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(w, 28), BackgroundColor3 = if look == "got" then GREEN elseif look == "need" then Color3.fromHex("#ffd84a") else Color3.fromHex("#0a142d"), BackgroundTransparency = if look then 0.05 else 0.4, Parent = chips }, {
			Ui.round(),
			Ui.stroke(1.5, if look == "need" then Ui.LINE else Ui.WHITE, if look == "need" then 0 else 0.75),
		})
		Ui.text({ Text = c[1], TextSize = 15, TextColor3 = if look == "need" then Ui.LINE else Ui.WHITE, Size = UDim2.fromScale(1, 1), Parent = f })
	end
	if car then
		Mastery.ladder({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(GO + GAP + CLASSES + GAP)), Size = UDim2.new(1, 0, 0, LADDER), Parent = left }, car.model)
		Mastery.classes({ AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -(GO + GAP)), Size = UDim2.new(1, 0, 0, CLASSES), Parent = left }, car.model)
	end
	-- The race button (the web's bar button): the prize, or the class the cup needs.
	local at = { Name = "Go", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, GO) }
	local function go()
		local now = api.myCar()
		if now and not cups.cupFits(r, now.model) then
			ctx.toast(`Race with a {cls.name} car for this cup`)
			return
		end
		api.start("cup", r.id)
	end
	if fits or not car then
		api.raceButton(left, at, prizeOf(r, s), go)
	else
		at.Parent = left
		Ui.buy(at, `{cls.icon} {cls.name} car`, "edit", go, 18)
	end

	-- ── Right: the classes, the class's three races, the first-win crate ──────────────────────
	local right = Ui.new("Frame", { Name = "Cups", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.535, -6, 1, 0), BackgroundTransparency = 1, Parent = page })
	local TABS, GRID = 58, 112
	local tabs = Ui.new("Frame", { Name = "Classes", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, TABS), BackgroundTransparency = 1, Parent = right }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 6, -6, 1, 0), CellPadding = UDim2.fromOffset(6, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, c in classes.CAR_CLASSES do
		local isSel = c.id == r.cls
		local done = cups.cupWon(s.cups, c.id)
		local b = Ui.new("TextButton", { Name = c.id, Text = "", AutoButtonColor = false, LayoutOrder = i, BackgroundColor3 = if isSel then color:Lerp(Ui.WHITE, 0.78) else Ui.WHITE, Parent = tabs }, {
			Ui.corner(12),
			Ui.stroke(2.5, if isSel then Ui.LINE elseif done then GOT_EDGE else Ui.EDGE),
		})
		Ui.text({ Text = c.icon, TextSize = 22, Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 26), Parent = b })
		Ui.text({ Text = c.name, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = Ui.INK, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, 33), Size = UDim2.new(1, -4, 0, 16), Parent = b })
		if done then
			tick(b, 4, -6)
		end
		b.Activated:Connect(function()
			-- A class opens on its first race not won yet.
			local list = cups.cupRacesOf(c.id)
			local to = list[1].id
			for _, x in list do
				if wins(s, x.id) == 0 then
					to = x.id
					break
				end
			end
			pick(to)
		end)
	end
	local grid = Ui.new("Frame", { Name = "Races", Position = UDim2.fromOffset(0, 4 + TABS + 12), Size = UDim2.new(1, 0, 0, GRID), BackgroundTransparency = 1, Parent = right }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -7, 1, 0), CellPadding = UDim2.fromOffset(9, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, x in cups.cupRacesOf(r.cls) do
		local xc = data.carDef(x.car)
		local isSel = x.id == r.id
		local done = wins(s, x.id) > 0
		local xColor = Color3.fromHex(x.color)
		local b = Ui.new("TextButton", { Name = x.id, Text = "", AutoButtonColor = false, LayoutOrder = i, BackgroundColor3 = if isSel then xColor:Lerp(Ui.WHITE, 0.72) elseif done then GOT_BG else Ui.WHITE, Parent = grid }, {
			Ui.corner(14),
			Ui.stroke(if isSel then 3 else 2.5, if isSel then Ui.LINE elseif done then GOT_EDGE else Ui.EDGE),
		})
		-- The colour along the bottom (.pr-tile's border-bottom).
		Ui.new("Frame", { Name = "Edge", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 3, 1, -2), Size = UDim2.new(1, -6, 0, 6), BackgroundColor3 = xColor, BorderSizePixel = 0, Parent = b }, { Ui.corner(3) })
		local t = Thumb.new("Cars", xc.id, UDim2.new(1, -12, 0, 58), xColor)
		t.Position = UDim2.fromOffset(6, 4)
		t.Parent = b
		if done then
			tick(b, 4, -6)
		end
		Ui.text({ Text = string.rep("🏆", x.tier), TextSize = 12, Position = UDim2.fromOffset(0, 62), Size = UDim2.new(1, 0, 0, 16), Parent = b })
		Ui.text({ Text = `PI {x.pi}`, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 18), Parent = b })
		b.Activated:Connect(function()
			pick(x.id)
		end)
	end
	-- The first-win prize: a free crate (.ev-reward.cup-reward).
	local crate = crates.crateDef(cups.CUP_CRATE)
	local top = 4 + TABS + 12 + GRID + 12
	local reward = Ui.new("Frame", { Name = "Reward", Position = UDim2.fromOffset(0, top), Size = UDim2.new(1, 0, 1, -top - 2), BackgroundColor3 = color:Lerp(Ui.SHEET, 0.7), Parent = right }, {
		Ui.corner(18),
		Ui.stroke(3, Ui.LINE),
	})
	local glow = Ui.new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.62, 0.8), BackgroundColor3 = Ui.WHITE, Parent = reward }, { Ui.round() })
	Ui.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.2), NumberSequenceKeypoint.new(1, 1) }), Parent = glow })
	local inner = Ui.new("Frame", { Name = "Ring", Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), BackgroundTransparency = 1, Parent = reward }, {
		Ui.corner(15),
		Ui.stroke(3, if got then GREEN else color:Lerp(Ui.WHITE, 0.45)),
	})
	local _ = inner
	local box = Ui.new("Frame", { Name = "Crate", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -26), Size = UDim2.fromOffset(110, 80), BackgroundTransparency = 1, Parent = reward })
	Ui.text({ Text = "📦", TextSize = 64, Size = UDim2.fromScale(1, 1), Parent = box })
	local state = Ui.new("Frame", { Name = "State", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(1, -14, 0, -6), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = if got then GREEN else Color3.fromHex("#ffd84a"), Parent = box }, { Ui.round(), Ui.stroke(3, Ui.LINE) })
	Ui.text({ Text = if got then "✔" else "🎁", TextSize = 19, TextColor3 = Ui.WHITE, Size = UDim2.fromScale(1, 1), Parent = state })
	Ui.text({ Text = crate.name, TextSize = 28, TextColor3 = Ui.INK, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 20), Size = UDim2.new(1, -20, 0, 30), Parent = reward })
	local em = "🎁 First win"
	local tag = Ui.new("Frame", { Name = "When", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 54), Size = UDim2.fromOffset(math.ceil(Ui.textWidth(em, 15)) + 20, 24), BackgroundTransparency = 1, Parent = reward }, {
		Ui.corner(7),
		Ui.stroke(1.5, Ui.LINE),
	})
	Ui.text({ Text = em, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.LINE, Size = UDim2.fromScale(1, 1), Parent = tag })
end

-- The race screen: the cup in the title, the crate on a first win, and a rematch or a retry.
function Cup.extras(ctx: any, which: any, _started: any, again: (string, any) -> () -> ()): DragStrip.Extras
	local r = cups.cupRace(which)
	local cls = classes.carClass(r.cls)
	return {
		title = `{cls.icon} {cls.name} Cup · {string.rep("🏆", r.tier)}`,
		-- A first win's free crate (CupPrizePopup) and a whole class's cup won.
		view = function(card: Frame, res: any, y: number): number
			local function row(name: string, icon: string, text: string, sub: string?)
				local f = Ui.new("Frame", { Name = name, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(330, 40), BackgroundColor3 = Color3.fromHex("#fff8e1"), Parent = card }, { Ui.corner(12), Ui.stroke(2, Color3.fromHex("#ffb300")) })
				Ui.text({ Text = icon, TextSize = 26, Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(36, 40), Parent = f })
				Ui.text({ Text = text, TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(46, if sub then 2 else 0), Size = UDim2.new(1, -52, 0, if sub then 22 else 40), Parent = f })
				if sub then
					Ui.text({ Text = sub, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(46, 22), Size = UDim2.new(1, -52, 0, 16), Parent = f })
				end
				y += 48
			end
			if res.cupCrate then
				row("CupPrize", "📦", `🎁 Free {crates.crateDef(res.cupCrate).name}`, `{cls.icon} {cls.name} Cup {string.rep("🏆", r.tier)} won!`)
			end
			if res.cupClass then
				local c = classes.carClass(res.cupClass)
				row("CupClass", "🏆", `{c.icon} {c.name} Cup complete!`)
			end
			return y
		end,
		buttons = function(res: any): { DragStrip.Button }?
			-- Once it's been won, it's a rematch for the usual prize.
			local beaten = (res.cupWins or 0) > 0
			local list: { DragStrip.Button } = { { text = "Back", kind = "garage" } }
			if res.cupCrate then
				table.insert(list, { text = "📦 Open it", kind = "crates", go = function()
					ctx.open("crates")
				end })
			end
			table.insert(list, { text = if beaten then `↻ Rematch ${Ui.commas(cups.cupPrize(r, false))}` else "↻ Retry", go = again("cup", r.id) })
			return list
		end,
	}
end

return Cup
