--!strict
-- The Social menu's Leaderboards tab, as the web game's LeadersPanel (ui/Social.tsx): Power, Wins,
-- Trophies or Level, all time or gained this week, best first (server/Leaders). Players in this
-- server can be visited from their row; your own row is always shown. The Crews switch ranks crews
-- by their members' numbers added up instead (web scope "clans", the clan_leaderboard view).

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local store = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"):WaitForChild("store")) :: any
local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)
local Crew = require(script.Parent.Crew)

local Leaders = {}

local METRICS = {
	{ id = "power", label = "Power", icon = "⚡" },
	{ id = "race_wins", label = "Wins", icon = "🏁" },
	{ id = "trophies", label = "Trophies", icon = "🏆" },
	{ id = "level", label = "Level", icon = "⭐" },
}
local MEDALS = { "🥇", "🥈", "🥉" }

-- Time to next Monday 00:00 UTC, as the web's weekResetsIn.
local function resetsIn(): string
	local now = os.time()
	local d = os.date("!*t", now) :: any
	local midnight = now - (d.hour * 3600 + d.min * 60 + d.sec)
	local wday = (d.wday + 5) % 7 -- Monday 0
	local nextMonday = midnight + (7 - wday) * 86400
	local h = math.ceil((nextMonday - now) / 3600)
	return if h > 24 then `{math.floor(h / 24)}d {h % 24}h` else `{h}h`
end

local function n(v: number): string
	local s = tostring(math.floor(v))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- The Crews board's rows: crest, name, [TAG] · members, and the crews' numbers added up.
function Leaders._crews(list: Instance, kit: any, board: any, icon: string, plus: string)
	local rows = board.crews or {}
	if #rows == 0 then
		kit.note(list, 4, "No crews yet.")
		if kit.tab then
			Ui.buy({ Name = "StartCrew", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 40), Parent = list }, "Start the first one", "green", function()
				kit.tab("clan")
			end, 15)
		end
		return
	end
	for i, c in rows do
		local mine = c.id == board.myCrew
		local name = c.name .. (if mine then " (yours)" else "")
		local place = MEDALS[i] or ("#" .. i)
		local r = kit.row(list, 4 + i, {
			name = name,
			on = mine,
			line = `{place} · {icon} {plus}{n(c.value)} · [{c.tag}] · {c.members}/{c.cap or 20} members`,
			buttons = {},
		})
		if r then
			-- The crew's crest where a player's picture goes.
			local a = r:FindFirstChild("Avatar")
			if a then
				a:Destroy()
			end
			Crew.crest(r, c, 34, UDim2.new(0, 10, 0.5, -17))
		end
	end
end

-- Draws the tab into list (a scrolling list with a UIListLayout). kit: the Friends panel's row,
-- heading and note, visit(userId) and card(userId, name, town).
function Leaders.draw(list: Instance, kit: any, state: any)
	state.metric = state.metric or "power"
	state.period = state.period or "all"
	state.scope = state.scope or "players"
	local function redraw()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		Leaders.draw(list, kit, state)
	end

	-- The switches: what the board counts, and all time or this week.
	local controls = Ui.new("Frame", { Name = "Controls", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 124), BackgroundTransparency = 1, Parent = list })
	local w = 1 / #METRICS
	for i, m in METRICS do
		local on = m.id == state.metric
		Ui.buy({ Name = m.id, Position = UDim2.new(w * (i - 1), 2, 0, 0), Size = UDim2.new(w, -4, 0, 38), Parent = controls }, `{m.icon} {m.label}`, if on then "green" else "garage", function()
			if state.metric ~= m.id then
				state.metric = m.id
				redraw()
			end
		end, 15)
	end
	for i, p in { { id = "all", label = "All time" }, { id = "week", label = "This week" } } do
		local on = p.id == state.period
		Ui.buy({ Name = p.id, Position = UDim2.new(0.5 * (i - 1), 2, 0, 44), Size = UDim2.new(0.5, -4, 0, 36), Parent = controls }, p.label, if on then "green" else "garage", function()
			if state.period ~= p.id then
				state.period = p.id
				redraw()
			end
		end, 15)
	end
	-- Players or crews (web: "Ranked by members combined").
	for i, p in { { id = "players", label = "Players" }, { id = "crews", label = "Crews" } } do
		local on = p.id == state.scope
		Ui.buy({ Name = p.id, Position = UDim2.new(0.5 * (i - 1), 2, 0, 86), Size = UDim2.new(0.5, -4, 0, 36), Parent = controls }, p.label, if on then "green" else "garage", function()
			if state.scope ~= p.id then
				state.scope = p.id
				redraw()
			end
		end, 15)
	end
	if state.period == "week" then
		kit.note(list, 2, `⏳ Gains since Monday. Resets in {resetsIn()}.`)
	end
	local crewsOn = state.scope == "crews"
	local loading = Ui.text({ Name = "Loading", Text = if crewsOn then "Loading crew rankings…" else "Loading the leaderboard…", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 40), Parent = list })

	local metric, period, scope = state.metric, state.period, state.scope
	task.spawn(function()
		local ok, board = Remote.social("leaders", { metric = metric, period = period, scope = if crewsOn then "crews" else nil }, true)
		if not loading.Parent or state.metric ~= metric or state.period ~= period or state.scope ~= scope then
			return
		end
		loading:Destroy()
		if not ok then
			kit.note(list, 3, "Couldn't reach the leaderboard right now. Try again in a moment.")
			return
		end
		local icon = "⚡"
		for _, m in METRICS do
			if m.id == metric then
				icon = m.icon
			end
		end
		local plus = if period == "week" then "+" else ""
		if crewsOn then
			Leaders._crews(list, kit, board, icon, plus)
			return
		end
		local me = Players.LocalPlayer
		local rows = table.clone(board.rows or {})
		-- You always appear: in your place when the board is short, else after the top 50.
		local below = false
		if board.mine ~= nil then
			local s = store.useGame.getState()
			local mine = { id = me.UserId, name = me.DisplayName, town = s.townName or "My Town", level = s.level or 1, value = board.mine, crew = board.crew }
			if #rows < 50 then
				table.insert(rows, mine)
				table.sort(rows, function(a, b)
					if a.value ~= b.value then
						return a.value > b.value
					end
					return a.id == me.UserId
				end)
			else
				table.insert(rows, mine)
				below = true
			end
		end
		if period == "week" then
			local kept = {}
			for _, r in rows do
				if r.value > 0 or r.id == me.UserId then
					table.insert(kept, r)
				end
			end
			rows = kept
		end
		local order = 4
		if #rows <= 1 and period == "week" then
			kit.note(list, order, "Nobody else has scored this week yet. Be the first!")
		end
		for i, r in rows do
			order += 1
			local mine = r.id == me.UserId
			local buttons = {}
			if r.here then
				table.insert(buttons, { text = "🏠 Visit", kind = "garage", width = 92, onClick = function()
					kit.visit(r.id)
				end })
			end
			local place = if below and i == #rows then "50+" else (MEDALS[i] or `#{i}`)
			local name = `{r.name}{if mine then " (you)" else ""}`
			local rowFrame = kit.row(list, order, {
				name = name,
				userId = r.id,
				on = r.here == true or mine,
				line = `{place} · {icon} {plus}{n(r.value)} · {r.town} · Lvl {r.level}`,
				buttons = buttons,
				onTap = function()
					kit.card(r.id, r.name, r.town)
				end,
			})
			-- Their crew's tag after the name (web ClanTag on leaderboard rows).
			-- (At the row's right, before its buttons; the name gives up the room.)
			if r.crew and rowFrame then
				local right = 10
				for _, b in buttons do
					right += b.width + 6
				end
				local pill = Crew.tag(rowFrame, r.crew, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -right, 0, 8) })
				for _, d in rowFrame:GetChildren() do
					if d:IsA("TextLabel") and d.Text == name then
						d.Size = UDim2.new(1, -54 - right - pill.Size.X.Offset - 8, 0, 20)
					end
				end
			end
		end
	end)
end

return Leaders
