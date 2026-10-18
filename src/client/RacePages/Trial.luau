--!strict
-- The weekly Time Trial page (ui/TimeTrial.tsx): this week's venue with the top three on a
-- podium, the prizes for the week's best, last weeks' prizes to claim, and the board of the top
-- ten times (yours too, if you're further down). Run races a ghost: your best this week, or par
-- for your car until you have one. The board is the server's (server/Modes/Trial, server/Boards).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local venues = require(Game.scene_venues) :: any
local trial = require(Game.trial) :: any
local raceCar = require(Game.raceCar) :: any
local Remote = require(script.Parent.Parent.Remote)
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local DragStrip = require(script.Parent.Parent.DragStrip)
local Sfx = require(script.Parent.Parent.Sounds.Sfx)

local Trial = {}
Trial.id = "trial"
Trial.title = "Time Trial"

local MEDAL = { "🥇", "🥈", "🥉" }
local PODIUM_H = { 0.22, 0.16, 0.11 }
local function place(n: number): string
	return MEDAL[n] or `#{n}`
end
local function money(n: number): string
	return if n >= 1000 then `${n / 1000}k` else `${n}`
end
local function weekOf(week: string): string
	local m, d = string.match(week, "%d+-(%d+)-(%d+)")
	local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
	return `{months[tonumber(m) or 1]} {tonumber(d)}`
end

-- The last board read, so the front page's tile can show your best.
Trial.last = nil :: any

-- A car picture from a board row's look (its paint and parts).
local function rowCar(look: any, size: UDim2): GuiObject?
	if type(look) ~= "table" or not look.model then
		return nil
	end
	local ok, pic = pcall(Thumb.car, look.model, size, { color = look.color or "#cfd8dc", finish = look.finish, stripe = look.stripe }, look.hat, look.mods, look.panels, look.trim, look.skin, look.modSkin)
	return if ok then pic else nil
end

local function draw(page: Frame, ctx: any, api: any, info: any)
	local me = Players.LocalPlayer and Players.LocalPlayer.UserId or 0
	local week = info.week
	local v = venues.venue(info.venue)
	local b = info.board

	-- Left: the stage (venue, podium, prizes).
	local _, stage = api.tile(page, { Name = "Stage", Size = UDim2.new(0.5, -6, 1, -60) }, v.sky or "#8ec9ff", "#14213d", true)
	stage.ClipsDescendants = true
	local ground = Ui.new("Frame", { BorderSizePixel = 0, Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.38), BackgroundColor3 = Ui.WHITE, Parent = stage }, { Ui.corner(18) })
	Ui.gradient("#7d8691", "#4d5560").Parent = ground
	Ui.text({ Text = v.icon or "🏁", TextSize = 70, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(100, 80), TextTransparency = 0.5, Parent = stage })
	local function chip(text: string, props: { [string]: any })
		local w = math.ceil(Ui.textWidth(text, 14)) + 22
		local f = Ui.new("Frame", { Size = UDim2.fromOffset(w, 28), BackgroundColor3 = Color3.fromHex("#14213d"), BackgroundTransparency = 0.2, ZIndex = 3, Parent = stage }, { Ui.corner(10) })
		for k, val in props do
			(f :: any)[k] = val
		end
		Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 14, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = f })
	end
	chip(`{v.icon} {v.name}`, { Position = UDim2.fromOffset(10, 10) })
	chip(`⏳ {trial.shortLeft(info.leftMs)}`, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10) })
	-- The podium: second, first, third.
	for i, at in { 2, 1, 3 } do
		local r = b.top[at]
		local x = (i - 0.5) / 3
		local step = Ui.new("Frame", { Name = `Step{at}`, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(x, 0, 1, -44), Size = UDim2.new(0.28, 0, PODIUM_H[at], 0), BackgroundColor3 = if at == 1 then Color3.fromHex("#ffd54f") elseif at == 2 then Color3.fromHex("#cfd8dc") else Color3.fromHex("#ffab91"), ZIndex = 2, Parent = stage }, {
			Ui.corner(8),
			Ui.stroke(2.5, Ui.LINE),
		})
		Ui.text({ Text = MEDAL[at], TextSize = 22, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 26), ZIndex = 2, Parent = step })
		if r then
			local pic = rowCar(r.look, UDim2.new(1.3, 0, 0, 70))
			if pic then
				pic.AnchorPoint = Vector2.new(0.5, 1)
				pic.Position = UDim2.new(0.5, 0, 0, 4)
				pic.ZIndex = 3
				pic.Parent = step
			end
			Ui.text({ Text = string.format("%.3f", r.t), TextSize = 14, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 16), ZIndex = 3, Parent = step })
		end
	end
	-- The week's prizes: 1st, 2nd, 3rd and top ten.
	local prizes = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -20, 0, 30), BackgroundTransparency = 1, ZIndex = 3, Parent = stage }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i = 1, 4 do
		local p = trial.TRIAL_PRIZES[i]
		local text = `{if i <= 3 then MEDAL[i] else "🔟"} 💎{p.bucks}`
		local f = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(math.ceil(Ui.textWidth(text, 14)) + 18, 28), BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = prizes }, { Ui.corner(10), Ui.stroke(2, Ui.LINE) })
		Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.INK, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = f })
	end

	-- The Run button, under the stage: your best to chase, or par.
	local car = api.myCar()
	Ui.buy({ Name = "Run", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(0.5, -6, 0, 52), Parent = page }, `⏱️ Run vs {info.ghost} {string.format("%.2f", info.target)}s  ⛽{trial.TRIAL_FUEL}`, if car then "green" else "grey", if car then function()
		api.start("trial", nil)
	end else nil, 16)

	-- Right: prizes to claim, then the board.
	local side = Ui.scroller({ Name = "Board", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.5, -6, 1, 0), Parent = page })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = side })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 6), Parent = side })
	for i, p in info.prizes do
		local row = Ui.new("Frame", { Name = "Claim", LayoutOrder = i, Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Color3.fromHex("#fff8e1"), Parent = side }, { Ui.corner(12), Ui.stroke(2, Color3.fromHex("#ffb300")) })
		Ui.text({ Text = place(p.place), TextSize = 24, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 40, 1, 0), Parent = row })
		Ui.text({ Text = weekOf(p.week), TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(52, 6), Size = UDim2.fromOffset(110, 20), Parent = row })
		Ui.text({ Text = string.format("%.3fs", p.t), Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(52, 26), Size = UDim2.fromOffset(110, 18), Parent = row })
		local label = `🎁 {if p.bucks > 0 then `💎{p.bucks} ` else ""}{money(p.coins)} 🏆{p.trophies}`
		Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(math.max(120, math.ceil(Ui.textWidth(label, 14)) + 24), 36), Parent = row }, label, "green", function()
			Sfx.reward()
			local ok = Remote.race("act", { mode = "trial", which = { claim = p.week } })
			if ok then
				api.show("trial")
			end
		end, 14)
	end
	local leader = if b.top[1] then b.top[1].t else nil
	local shownMe = false
	local function boardRow(order: number, r: any, mine: boolean)
		local row = Ui.new("Frame", { Name = "Row", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = if mine then Color3.fromHex("#e3f2fd") else Ui.WHITE, Parent = side }, {
			Ui.corner(12),
			Ui.stroke(if mine then 2.5 else 2, if mine then Color3.fromHex("#1e88e5") else Ui.EDGE),
		})
		Ui.text({ Text = if r.place <= 3 then MEDAL[r.place] else tostring(r.place), TextSize = if r.place <= 3 then 20 else 16, TextColor3 = Ui.INK, Position = UDim2.fromOffset(4, 0), Size = UDim2.new(0, 34, 1, 0), Parent = row })
		local pic = rowCar(r.look, UDim2.fromOffset(56, 40))
		if pic then
			pic.Position = UDim2.fromOffset(38, 3)
			pic.Parent = row
		end
		Ui.text({ Text = r.town or "Racer", Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(100, 4), Size = UDim2.new(1, -190, 0, 20), Parent = row })
		Ui.text({ Text = `{r.car or ""}  PI {r.pi or "?"}`, Body = true, TextSize = 12, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(100, 24), Size = UDim2.new(1, -190, 0, 16), Parent = row })
		Ui.text({ Text = string.format("%.3f", r.t), TextSize = 17, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 4), Size = UDim2.fromOffset(80, 22), Parent = row })
		if leader and r.place > 1 then
			Ui.text({ Text = string.format("+%.3f", r.t - leader), Body = true, TextSize = 12, TextColor3 = Color3.fromHex("#c62828"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 25), Size = UDim2.fromOffset(80, 16), Parent = row })
		end
	end
	for i, r in b.top do
		local mine = r.owner == me
		shownMe = shownMe or mine
		boardRow(100 + i, r, mine)
	end
	if #b.top == 0 then
		Ui.text({ Text = "🏁 No times yet this week. Be 1st!", Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.MUTED, LayoutOrder = 100, Size = UDim2.new(1, 0, 0, 60), Parent = side })
	end
	if b.me and not shownMe then
		local s = require(Game.store).useGame.getState()
		local mycar = raceCar.raceCarOf(s.cars, s.raceCar)
		boardRow(200, { place = b.me.place, t = b.me.t, town = s.townName, car = if mycar then data.carDef(mycar.model).name else nil, pi = if mycar then raceCar.carPi(mycar) else nil, look = mycar }, true)
	end
	if b.total > 0 then
		Ui.text({ Text = `{b.total} racer{if b.total == 1 then "" else "s"} this week`, Body = true, TextSize = 12, TextColor3 = Ui.MUTED, LayoutOrder = 300, Size = UDim2.new(1, 0, 0, 18), Parent = side })
	end
	local _ = ctx
end

function Trial.draw(page: Frame, ctx: any, api: any)
	Sfx.start()
	Ui.text({ Text = "Loading lap times...", Body = true, TextSize = 20, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.MUTED, Parent = page })
	task.spawn(function()
		local ok, info = Remote.race("list", { mode = "trial" }, true)
		if not page.Parent then
			return
		end
		page:ClearAllChildren()
		if not ok or not info then
			Ui.text({ Text = "📡 Couldn't load the board", Body = true, TextSize = 20, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.MUTED, Parent = page })
			return
		end
		Trial.last = info
		draw(page, ctx, api, info)
	end)
end

-- The end-of-run card (TrialResult): the time, a new best or not, and where it put you.
function Trial.extras(_ctx: any, _which: any, started: any, again: (string, any) -> () -> ()): DragStrip.Extras
	local v = started.venue or {}
	return {
		title = `⏱️ Time trial · {v.name or "Drag strip"}`,
		icon = "⏱️",
		heading = function(res: any): string?
			local t = res.trial
			if not t or not t.t then
				return "NO TIME"
			end
			if t.before == nil or math.round(t.t * 1000) < math.round(t.before * 1000) then
				return "NEW BEST!"
			end
			return if t.t < t.target then `You beat {string.lower(t.ghost)}!` else string.format("%.3fs", t.t)
		end,
		view = function(card: Frame, res: any, y: number): number
			local t = res.trial
			if not t or not t.place then
				return y
			end
			Ui.text({ Text = `{place(t.place)} of {t.total} this week · best {string.format("%.3fs", t.kept)}`, TextSize = 18, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 24), Parent = card })
			return y + 32
		end,
		buttons = function(_res: any): { DragStrip.Button }?
			return { { text = "Board", kind = "garage" }, { text = `↻ Again · ⛽{trial.TRIAL_FUEL}`, go = again("trial", nil) } }
		end,
	}
end

return Trial
