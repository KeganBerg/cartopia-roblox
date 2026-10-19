--!strict
-- The Social menu's Crew tab, as the web game's crew screens (ui/Social.tsx): without a crew, the
-- crews to join (search by name or tag) and "Start a crew" ($2,000 and a Crew House); in one, the
-- crew's banner, its drivers by rank, join requests and settings for its Leader and Co-Leaders,
-- and Leave (server/Crews).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local store = require(Game.store) :: any
local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)

local Crew = {}

local RANKS = {
	leader = { icon = "👑", label = "Leader", order = 0 },
	co_leader = { icon = "🎖️", label = "Co-Leader", order = 1 },
	member = { icon = "🛡️", label = "Member", order = 2 },
}
local MODES = {
	{ id = "open", icon = "🔓", label = "Open" },
	{ id = "request", icon = "✋", label = "Request" },
	{ id = "closed", icon = "🔒", label = "Closed" },
}
local MODE_ICON = { open = "🔓", request = "✋", closed = "🔒" }

local function hex(h: string): Color3
	local ok, c = pcall(Color3.fromHex, h)
	return if ok then c else Color3.fromHex("#ff7043")
end

local function money(n: number): string
	return `${Ui.commas(n)}`
end

-- The crew's badge: its emblem on a circle of its colour.
function Crew.crest(parent: Instance, c: any, size: number, pos: UDim2?): Frame
	local f = Ui.new("Frame", { Name = "Crest", Position = pos or UDim2.new(), Size = UDim2.fromOffset(size, size), BackgroundColor3 = hex(c.color or "#ff7043"), Parent = parent }, {
		Ui.round(),
		Ui.stroke(2, Ui.WHITE),
	})
	Ui.text({ Text = c.emblem or "🏁", TextSize = math.floor(size * 0.55), Size = UDim2.fromScale(1, 1), Parent = f })
	return f
end

-- The emblem and tag on a pill of the crew's colour (web ClanTag), for names elsewhere.
function Crew.tag(parent: Instance, c: any, props: { [string]: any }?): Frame
	local text = `{c.emblem or "🏁"} {c.tag or "??"}`
	local p: { [string]: any } = { Name = "CrewTag", Size = UDim2.fromOffset(math.ceil(Ui.textWidth(text, 13)) + 14, 20), BackgroundColor3 = hex(c.color or "#ff7043"), Parent = parent }
	for k, v in props or {} do
		p[k] = v
	end
	local pill = Ui.new("Frame", p, { Ui.corner(10) })
	Ui.text({ Text = text, TextSize = 13, Size = UDim2.fromScale(1, 1), Stroke = 1.5, Parent = pill })
	return pill
end

local function box(parent: Instance, order: number, h: number, name: string?): Frame
	return Ui.new("Frame", { Name = name or "Box", LayoutOrder = order, Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Ui.WHITE, Parent = parent }, {
		Ui.corner(12),
		Ui.stroke(2, Color3.fromHex("#e0e0e0")),
	})
end

-- "3d 4h", "5h": how long until the week ends (web CrewGoal's left()).
local function left(seconds: number): string
	local h = math.max(1, math.ceil(seconds / 3600))
	if h > 24 then
		return if h % 24 > 0 then `{h // 24}d {h % 24}h` else `{h // 24}d`
	end
	return `{h}h`
end

-- What a crew chest pays at the player's level (data.CREW_CHEST).
local function chestPay(): string
	local level = store.useGame.getState().level or 1
	local pay = data.payAt(data.CREW_CHEST, level)
	return `{money(pay.coins)} · 💎 {data.CREW_CHEST.bucks} · ⚙ {data.CREW_CHEST.parts}`
end

-- A chest row: its icon, name, what it pays (or what's missing) and its button.
local function chestRow(parent: Instance, order: number, name: string, title: string, sub: string, button: string, kind: string, onOpen: (() -> ())?): Frame
	local row = box(parent, order, 58, name)
	Ui.text({ Text = if button == "✔" then "📭" else "🧰", TextSize = 28, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(44, 58), Parent = row })
	Ui.text({ Text = title, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 9), Size = UDim2.new(1, -160, 0, 20), Parent = row })
	Ui.text({ Name = "Pay", Text = sub, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(56, 30), Size = UDim2.new(1, -160, 0, 17), Parent = row })
	if button == "✔" then
		Ui.text({ Text = "✔", TextSize = 22, TextColor3 = Color3.fromHex("#43a047"), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(84, 36), Parent = row })
	else
		Ui.buy({ Name = "Open", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(88, 36), Parent = row }, button, kind, onOpen, 16)
	end
	return row
end

-- The crew's weekly goal (web CrewGoalCard): the shared bar, how points are made, and the chest at
-- the end; last week's chest above it while it still waits. open(week) opens a chest.
function Crew.goal(parent: Instance, nextOrder: () -> number, goal: any, open: (string) -> ())
	if not goal then
		return
	end
	local min = goal.rules and goal.rules.minPoints or 30
	if goal.last then
		chestRow(parent, nextOrder(), "LastChest", "Last week's chest", chestPay(), "Open", "green", function()
			open(goal.last.week)
		end)
	end
	local w = goal.current
	if not w then
		return
	end
	local card = box(parent, nextOrder(), 84, "CrewGoal")
	Ui.text({ Text = "🧰 Crew goal", Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(0.6, 0, 0, 20), Parent = card })
	Ui.text({ Name = "Left", Text = `⏱ {left(goal.left or 0)}`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 9), Size = UDim2.new(0.4, -12, 0, 18), Parent = card })
	local bar = Ui.new("Frame", { Name = "Bar", Position = UDim2.fromOffset(12, 34), Size = UDim2.new(1, -24, 0, 16), BackgroundColor3 = Color3.fromHex("#e3e8ef"), Parent = card }, { Ui.corner(8) })
	local pct = math.clamp(w.points / math.max(1, w.target), 0, 1)
	Ui.new("Frame", { Name = "Fill", Size = UDim2.fromScale(pct, 1), Visible = pct > 0, BackgroundColor3 = if w.reached then Color3.fromHex("#43a047") else Color3.fromHex("#ffa726"), Parent = bar }, { Ui.corner(8) })
	Ui.text({ Name = "Points", Text = `{Ui.commas(w.points)} / {Ui.commas(w.target)}`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 56), Size = UDim2.new(0.5, -12, 0, 18), Parent = card })
	Ui.text({ Text = `🍕 +{data.CREW_POINTS.job} a job · 🏁 +{data.CREW_POINTS.race} a race`, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 57), Size = UDim2.new(0.5, 0, 0, 17), Parent = card })
	local ready = w.reached and not w.opened and w.mine >= min
	local sub = if w.mine < min and not w.opened then `Add {min - w.mine} more points to earn yours` else chestPay()
	local button = if w.opened then "✔" elseif ready then "Open" else "🔒"
	chestRow(parent, nextOrder(), "Chest", "Crew chest", sub, button, if ready then "green" else "broke", function()
		if ready then
			open(w.week)
		end
	end)
end

local function label(parent: Instance, text: string, y: number)
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 18), Parent = parent })
end

local function field(parent: Instance, y: number, text: string, placeholder: string, maxLen: number, upper: boolean?, name: string?): TextBox
	local f = Ui.new("Frame", { Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 40), BackgroundColor3 = Color3.fromHex("#f7f9fc"), Parent = parent }, {
		Ui.corner(10),
		Ui.stroke(2, Color3.fromHex("#cfd8dc")),
	})
	local tb = Ui.new("TextBox", {
		Name = name or "Field",
		Text = text,
		PlaceholderText = placeholder,
		ClearTextOnFocus = false,
		FontFace = Ui.BODY,
		TextSize = 17,
		TextColor3 = Ui.INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -20, 1, 0),
		Parent = f,
	}) :: TextBox
	tb:GetPropertyChangedSignal("Text"):Connect(function()
		local t = tb.Text
		if upper then
			t = t:upper():gsub("[^A-Z0-9]", "")
		end
		if utf8.len(t) and (utf8.len(t) :: number) > maxLen then
			t = t:sub(1, (utf8.offset(t, maxLen + 1) or (#t + 1)) - 1)
		end
		if t ~= tb.Text then
			tb.Text = t
		end
	end)
	return tb
end

-- The look a crew picks: emblem, colour, motto, level needed, who may join. Draws into a box
-- from height y and returns the look being edited and the height reached.
local function lookEditor(parent: Frame, y: number, start: any): (any, number)
	local look = { emblem = start.emblem, color = start.color, motto = start.motto or "", minLevel = start.minLevel or 1, joinMode = start.joinMode or "open" }
	label(parent, "Emblem", y)
	local emblems = Ui.new("Frame", { Name = "Emblems", Position = UDim2.fromOffset(12, y + 22), Size = UDim2.new(1, -24, 0, 84), BackgroundTransparency = 1, Parent = parent }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(38, 38), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local emblemButtons: { [string]: TextButton } = {}
	local function paintEmblems()
		for e, b in emblemButtons do
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = if e == look.emblem then Color3.fromHex("#1e88e5") else Color3.fromHex("#cfd8dc")
				st.Thickness = if e == look.emblem then 3 else 2
			end
		end
	end
	for i, e in data.CLAN_EMBLEMS do
		local b = Ui.new("TextButton", { Name = `Emblem{i}`, LayoutOrder = i, Text = e, TextSize = 20, AutoButtonColor = true, BackgroundColor3 = Ui.WHITE, Parent = emblems }, { Ui.corner(10), Ui.stroke(2, Color3.fromHex("#cfd8dc")) }) :: TextButton
		emblemButtons[e] = b
		b.Activated:Connect(function()
			look.emblem = e
			paintEmblems()
		end)
	end
	paintEmblems()
	y += 112
	label(parent, "Colour", y)
	local colors = Ui.new("Frame", { Name = "Colors", Position = UDim2.fromOffset(12, y + 22), Size = UDim2.new(1, -24, 0, 36), BackgroundTransparency = 1, Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local colorButtons: { [string]: TextButton } = {}
	local function paintColors()
		for c, b in colorButtons do
			local st = b:FindFirstChildOfClass("UIStroke")
			if st then
				st.Color = if c == look.color then Ui.INK else Ui.WHITE
				st.Thickness = if c == look.color then 3 else 2
			end
		end
	end
	for i, c in data.CLAN_COLORS do
		local b = Ui.new("TextButton", { Name = c, LayoutOrder = i, Text = "", AutoButtonColor = true, BackgroundColor3 = hex(c), Size = UDim2.fromOffset(32, 32), Parent = colors }, { Ui.round(), Ui.stroke(2, Ui.WHITE) }) :: TextButton
		colorButtons[c] = b
		b.Activated:Connect(function()
			look.color = c
			paintColors()
		end)
	end
	paintColors()
	y += 64
	label(parent, "Motto", y)
	local motto = field(parent, y + 22, look.motto, "What your crew is about", 140, nil, "Motto")
	motto:GetPropertyChangedSignal("Text"):Connect(function()
		look.motto = motto.Text
	end)
	y += 70
	label(parent, "Level needed", y)
	local lvl = Ui.new("Frame", { Name = "Level", Position = UDim2.fromOffset(12, y + 22), Size = UDim2.fromOffset(150, 36), BackgroundTransparency = 1, Parent = parent })
	local lvlText = Ui.text({ Text = `Lvl {look.minLevel}+`, TextSize = 17, TextColor3 = Ui.INK, Position = UDim2.fromOffset(40, 0), Size = UDim2.fromOffset(70, 36), Parent = lvl })
	local function step(d: number)
		look.minLevel = math.clamp(look.minLevel + d, 1, 99)
		Ui.setText(lvlText, `Lvl {look.minLevel}+`)
	end
	Ui.buy({ Name = "Less", Size = UDim2.fromOffset(36, 36), Parent = lvl }, "−", "garage", function()
		step(-1)
	end, 18)
	Ui.buy({ Name = "More", Position = UDim2.fromOffset(114, 0), Size = UDim2.fromOffset(36, 36), Parent = lvl }, "+", "garage", function()
		step(1)
	end, 18)
	y += 66
	label(parent, "Who can join", y)
	local modes = Ui.new("Frame", { Name = "Modes", Position = UDim2.fromOffset(12, y + 22), Size = UDim2.new(1, -24, 0, 36), BackgroundTransparency = 1, Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local modeFaces: { [string]: Frame } = {}
	local function paintModes()
		for id, f in modeFaces do
			f.BackgroundTransparency = if id == look.joinMode then 0 else 0.6
		end
	end
	for i, m in MODES do
		local _, face = Ui.buy({ Name = m.id, LayoutOrder = i, Size = UDim2.fromOffset(112, 34), Parent = modes }, `{m.icon} {m.label}`, "garage", function()
			look.joinMode = m.id
			paintModes()
		end, 15)
		modeFaces[m.id] = face :: any
	end
	paintModes()
	y += 66
	-- (The motto box too: its text is read again when sent, in case a change wasn't heard.)
	return look, y, motto
end

-- Draws the tab into list. kit: the Friends panel's heading and note, card(userId, name, town),
-- toast and ctx. state keeps the search and whether the start form is open between redraws.
function Crew.draw(list: Instance, kit: any, state: any)
	-- Marks the list as the Crew tab's: when another tab clears it, late answers draw nothing.
	local mark = Ui.new("Frame", { Name = "CrewTab", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Parent = list })
	local function clear()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
	end
	local function redraw()
		if not mark.Parent then
			return
		end
		clear()
		Crew.draw(list, kit, state)
	end
	local loading = Ui.text({ Name = "Loading", Text = "Finding crews…", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 40), Parent = list })
	local busy = false
	-- Runs a crew op, then draws the tab again.
	local function call(op: string, arg: any?, after: ((any) -> ())?)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			local ok, r = Remote.social(op, arg)
			busy = false
			if ok and after then
				after(r)
			end
			redraw()
		end)
	end

	task.spawn(function()
		local ok, res = Remote.social("crew", state.q, true)
		if not mark.Parent or not loading.Parent then
			return
		end
		loading:Destroy()
		if not ok then
			kit.note(list, 1, "Couldn't load crews right now. Try again in a moment.")
			return
		end
		local order = 1
		local function nextOrder(): number
			order += 1
			return order
		end
		local me = Players.LocalPlayer and Players.LocalPlayer.UserId or 0
		local function openChest(week: string)
			call("crewChest", week)
		end

		-- ── In a crew ─────────────────────────────────────────────────────────────────────────
		if res.crew then
			local c, role = res.crew, res.role
			local sum = res.summary or {}
			local officer = role == "leader" or role == "co_leader"
			local hero = box(list, nextOrder(), 96, "Hero")
			hero.BackgroundColor3 = hex(c.color)
			Crew.crest(hero, c, 64, UDim2.fromOffset(14, 16))
			Ui.text({ Name = "CrewName", Text = c.name, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Stroke = 2, Position = UDim2.fromOffset(90, 12), Size = UDim2.new(1, -190, 0, 28), Parent = hero })
			Crew.tag(hero, c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 16) })
			Ui.text({ Text = `{RANKS[role].icon} {RANKS[role].label} · 👥 {sum.members or 0}/{c.cap} · ⚡ {Ui.commas(sum.power or 0)} · {MODE_ICON[c.joinMode] or ""}`, Body = true, Weight = "heavy", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Stroke = 1.5, Position = UDim2.fromOffset(90, 42), Size = UDim2.new(1, -100, 0, 18), Parent = hero })
			if c.motto ~= "" then
				Ui.text({ Text = c.motto, Body = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Stroke = 1.5, Position = UDim2.fromOffset(90, 64), Size = UDim2.new(1, -100, 0, 18), Parent = hero })
			end
			Crew.goal(list, nextOrder, res.goal, openChest)
			-- Each driver's points towards the goal this week.
			local goalPts: { [number]: number } = {}
			for _, g in (res.goal and res.goal.current and res.goal.current.members) or {} do
				goalPts[g.id] = g.points
			end

			-- Join requests, for the Leader and Co-Leaders.
			local requests = {}
			for uid, r in c.requests or {} do
				table.insert(requests, { id = tonumber(uid), name = r.name, level = r.level, power = r.power, at = r.at })
			end
			table.sort(requests, function(a, b)
				return a.at < b.at
			end)
			if officer and #requests > 0 then
				kit.heading(list, nextOrder(), `✋ Requests ({#requests})`)
				for _, r in requests do
					local row = box(list, nextOrder(), 50, `Request{r.id}`)
					Ui.text({ Text = r.name, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -150, 0, 20), Parent = row })
					Ui.text({ Text = `Lvl {r.level} · ⚡ {Ui.commas(r.power or 0)}`, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -150, 0, 17), Parent = row })
					Ui.buy({ Name = "Yes", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -62, 0.5, 0), Size = UDim2.fromOffset(54, 34), Parent = row }, "✔", "green", function()
						call("crewRespond", { id = r.id, yes = true })
					end, 16)
					Ui.buy({ Name = "No", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(48, 34), Parent = row }, "✖", "grey", function()
						call("crewRespond", { id = r.id, yes = false })
					end, 16)
				end
			end

			-- The drivers: Leader, Co-Leaders, Members; strongest garage first in each.
			local members = {}
			for uid, m in c.members do
				local row = table.clone(m)
				row.id = tonumber(uid)
				table.insert(members, row)
			end
			table.sort(members, function(a, b)
				local ra, rb = RANKS[a.role].order, RANKS[b.role].order
				if ra ~= rb then
					return ra < rb
				end
				return (a.power or 0) > (b.power or 0)
			end)
			kit.heading(list, nextOrder(), "👥 Drivers", `{#members}/{c.cap}`)
			for _, m in members do
				local row = box(list, nextOrder(), 56, `Member{m.id}`)
				Ui.new("TextButton", { Name = "Open", Text = "", BackgroundTransparency = 1, ZIndex = 0, Size = UDim2.fromScale(1, 1), Parent = row }).Activated:Connect(function()
					kit.card(m.id, m.name, m.town)
				end)
				local mine = m.id == me
				Ui.text({ Text = RANKS[m.role].icon, TextSize = 22, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(34, 56), Parent = row })
				local buttons = {}
				if not mine and role == "leader" then
					if m.role == "member" then
						table.insert(buttons, { "🎖️", "Make Co-Leader", function()
							call("crewRank", { id = m.id, rank = "co_leader" })
						end })
					else
						table.insert(buttons, { "🛡️", "Make Member", function()
							call("crewRank", { id = m.id, rank = "member" })
						end })
					end
					table.insert(buttons, { "👑", "Make Leader", function()
						if state.confirm == `lead{m.id}` then
							state.confirm = nil
							call("crewRank", { id = m.id, rank = "leader" })
						else
							state.confirm = `lead{m.id}`
							kit.toast(`Tap 👑 again to make {m.name} the Leader`)
						end
					end })
				end
				if not mine and (role == "leader" or (role == "co_leader" and m.role == "member")) then
					table.insert(buttons, { "✖", "Remove", function()
						if state.confirm == `kick{m.id}` then
							state.confirm = nil
							call("crewKick", m.id)
						else
							state.confirm = `kick{m.id}`
							kit.toast(`Tap ✖ again to remove {m.name}`)
						end
					end })
				end
				local right = 8
				for i = #buttons, 1, -1 do
					local b = buttons[i]
					local _, face = Ui.buy({ Name = b[2], AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -right, 0.5, 0), Size = UDim2.fromOffset(42, 34), Parent = row }, b[1], if b[1] == "✖" then "grey" else "garage", b[3], 16)
					face.Name = b[2]
					right += 48
				end
				Ui.text({ Text = if mine then `{m.name} (you)` else m.name, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(46, 8), Size = UDim2.new(1, -54 - right, 0, 20), Parent = row })
				Ui.text({ Text = `Lvl {m.level or 1} · ⚡ {Ui.commas(m.power or 0)} · 🏁 {Ui.commas(m.wins or 0)} · 🏆 {Ui.commas(m.trophies or 0)} · 🧰 {Ui.commas(goalPts[m.id] or 0)}`, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(46, 29), Size = UDim2.new(1, -54 - right, 0, 17), Parent = row })
			end

			-- Settings, for the Leader and Co-Leaders.
			if officer then
				kit.heading(list, nextOrder(), "⚙️ Crew settings")
				local panel = box(list, nextOrder(), 10, "Settings")
				local look, y, motto = lookEditor(panel, 10, c)
				Ui.buy({ Name = "Save", Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 44), Parent = panel }, "Save settings", "green", function()
					look.motto = motto.Text
					call("crewSettings", look, function()
						kit.toast("Crew settings saved")
					end)
				end, 18)
				panel.Size = UDim2.new(1, 0, 0, y + 56)
			end

			-- Leave.
			local leaveRow = Ui.new("Frame", { Name = "LeaveRow", LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = list })
			local heirNote = ""
			if role == "leader" and #members > 1 then
				local h = nil
				for _, m in members do
					if m.id ~= me and (not h or RANKS[m.role].order < RANKS[h.role].order or (m.role == h.role and m.at < h.at)) then
						h = m
					end
				end
				heirNote = if h then ` ({h.name} will lead)` else ""
			end
			Ui.buy({ Name = "Leave", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(260, 42), Parent = leaveRow }, if state.confirm == "leave" then "Tap again to leave" else "Leave crew", "grey", function()
				if state.confirm == "leave" then
					state.confirm = nil
					call("crewLeave", nil, function()
						kit.toast(`You left {c.name}{heirNote}`)
					end)
				else
					state.confirm = "leave"
					kit.toast(if #members <= 1 then "You're the last one: leaving closes the crew. Tap again to leave." else `Tap Leave again to leave{heirNote}`)
					redraw()
				end
			end, 17)
			return
		end

		-- ── Not in a crew ─────────────────────────────────────────────────────────────────────
		-- (Last week's chest still opens after leaving the crew that earned it.)
		Crew.goal(list, nextOrder, res.goal, openChest)
		if not res.house then
			local lock = box(list, nextOrder(), 120, "Locked")
			Ui.text({ Text = "🔒 Crews open with a Crew House", TextSize = 19, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 26), Parent = lock })
			Ui.text({ Text = "Build one in your town to start or join a crew of up to 20 drivers.", Body = true, TextSize = 14, TextColor3 = Ui.MUTED, TextWrapped = true, Position = UDim2.fromOffset(16, 42), Size = UDim2.new(1, -32, 0, 22), Parent = lock })
			Ui.buy({ Name = "Build", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 70), Size = UDim2.fromOffset(220, 40), Parent = lock }, "🏗️ Build a Crew House", "green", function()
				kit.ctx.open("shop", "crew")
			end, 16)
			return
		end

		if state.creating then
			kit.heading(list, nextOrder(), "🛡️ Start a crew")
			local form = box(list, nextOrder(), 10, "Create")
			label(form, "Name", 10)
			local name = field(form, 32, state.name or "", "Crew name (3-24 letters)", 24, nil, "Name")
			label(form, "Tag", 80)
			local tag = field(form, 102, state.tag or "", "2-4 letters or numbers", 4, true, "Tag")
			local look, y, motto = lookEditor(form, 150, { emblem = data.CLAN_EMBLEMS[1], color = data.CLAN_COLORS[1], motto = "", minLevel = 1, joinMode = "open" })
			local coins = store.useGame.getState().coins or 0
			local afford = coins >= data.CLAN_COST
			Ui.buy({ Name = "Start", Position = UDim2.fromOffset(12, y), Size = UDim2.new(0.62, -18, 0, 44), Parent = form }, `Start crew · {money(data.CLAN_COST)}`, if afford then "green" else "broke", function()
				if not afford then
					kit.toast(`You need {money(data.CLAN_COST)} to start a crew`)
					return
				end
				local spec = table.clone(look)
				spec.motto = motto.Text
				spec.name, spec.tag = name.Text, (tag.Text:upper():gsub("[^A-Z0-9]", ""))
				state.name, state.tag = name.Text, tag.Text
				call("crewCreate", spec, function()
					state.creating, state.name, state.tag = nil, nil, nil
					kit.toast("🛡️ Your crew is ready!")
				end)
			end, 17)
			Ui.buy({ Name = "Cancel", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, y), Size = UDim2.new(0.38, -12, 0, 44), Parent = form }, "Cancel", "grey", function()
				state.creating = nil
				redraw()
			end, 17)
			form.Size = UDim2.new(1, 0, 0, y + 56)
			return
		end

		-- Search and Start.
		local bar = Ui.new("Frame", { Name = "Search", LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = list })
		local searchHolder = Ui.new("Frame", { Size = UDim2.new(1, -170, 1, 0), BackgroundTransparency = 1, Parent = bar })
		local q = field(searchHolder, 2, state.q or "", "🔎 Search by name or tag", 24)
		q.Parent.Position = UDim2.fromOffset(0, 2)
		q.Parent.Size = UDim2.new(1, -60, 0, 40)
		Ui.buy({ Name = "Find", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 3), Size = UDim2.fromOffset(54, 38), Parent = searchHolder }, "Go", "garage", function()
			state.q = q.Text
			redraw()
		end, 15)
		Ui.buy({ Name = "StartCrew", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 3), Size = UDim2.fromOffset(160, 38), Parent = bar }, "+ Start a crew", "green", function()
			state.creating = true
			redraw()
		end, 15)

		local rows = res.browse or {}
		if #rows == 0 then
			kit.note(list, nextOrder(), if state.q and state.q ~= "" then "No crews match that search." else "No crews yet. Start the first one and invite your friends!")
		end
		local level = res.level or 1
		for _, c in rows do
			local row = box(list, nextOrder(), 72, `Crew{c.tag}`)
			Crew.crest(row, c, 48, UDim2.fromOffset(10, 12))
			Ui.text({ Text = c.name, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(68, 6), Size = UDim2.new(1, -250, 0, 20), Parent = row })
			Crew.tag(row, c, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -132, 0, 8) })
			Ui.text({ Text = `{MODE_ICON[c.joinMode] or ""} 👥 {c.members}/{c.cap} · ⚡ {Ui.commas(c.power or 0)} · Lvl {c.minLevel}+`, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(68, 27), Size = UDim2.new(1, -200, 0, 17), Parent = row })
			if c.motto and c.motto ~= "" then
				Ui.text({ Text = c.motto, Body = true, TextSize = 12, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(68, 46), Size = UDim2.new(1, -200, 0, 16), Parent = row })
			end
			local asked = table.find(res.asked or {}, c.id) ~= nil
			local text, kind, go = "Join", "green", function()
				call("crewAsk", c.id, function(r)
					kit.toast(if r == "joined" then `🛡️ You joined {c.name}!` else `✋ Asked to join {c.name}`)
				end)
			end
			if asked then
				text, kind, go = "⏳ Sent", "garage", function()
					call("crewCancel", c.id)
				end
			elseif c.joinMode == "closed" then
				text, kind, go = "🔒", "grey", function()
					kit.toast("That crew isn't taking new drivers")
				end
			elseif c.members >= c.cap then
				text, kind, go = "Full", "grey", function()
					kit.toast("That crew is full")
				end
			elseif level < c.minLevel then
				text, kind, go = `🔒 Lvl {c.minLevel}`, "grey", function()
					kit.toast(`Reach level {c.minLevel} to join`)
				end
			elseif c.joinMode == "request" then
				text = "✋ Ask"
			end
			Ui.buy({ Name = "Join", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(112, 40), Parent = row }, text, kind, go, 16)
		end
	end)
end

return Crew
