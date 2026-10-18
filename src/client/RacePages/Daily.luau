--!strict
-- The Daily Run page (ui/DailyRun.tsx DailyRunTab): today's start line with the loaner car beside
-- its par ghost, chips over it (the venue and the time to the next run), today's best on the
-- timing tower, and the medal times along the bottom (green once beaten). Under it, as the web's
-- bottom bar, the loaner's name and the Run button (the day's pay until the first run, then just
-- Run). The server (server/Modes/Daily) starts the run and pays it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local daily = require(Game.daily) :: any
local trial = require(Game.trial) :: any
local Js = require(Game.__js) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local DragStrip = require(script.Parent.Parent.DragStrip)

local Daily = {}
Daily.id = "daily"
Daily.title = "Daily Run"
Daily.mini = { icon = "📅", label = "Daily Run" }

local GREEN = Color3.fromHex("#45b649")

-- Milliseconds to the next day's run (UTC midnight).
local function msToTomorrow(): number
	return 86400000 - (Js.JsDate:now() % 86400000)
end

-- Today's best as saved, or nil before the first run (DailyRun.tsx dailyBest).
local function dailyBest(d: any, day: string): number?
	return if d and d.day == day then d.best else nil
end

local function fmt3(t: number): string
	return string.format("%.3fs", t)
end

-- A dark rounded chip (.dr-chip).
local function chip(parent: Instance, text: string, color: string, order: number)
	local w = math.ceil(Ui.textWidth(text, 15)) + 26
	local f = Ui.new("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(w, 28), BackgroundColor3 = Color3.fromHex(color), Parent = parent }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 15, Size = UDim2.fromScale(1, 1), Parent = f })
end

function Daily.draw(page: Frame, ctx: any, api: any)
	local run = daily.dailyRun()
	local s = store.useGame.getState()
	local best = dailyBest(s.daily, run.day)
	local medal = if best then daily.dailyMedal(run, best) else nil
	local paid = s.daily ~= nil and s.daily.day == run.day and s.daily.paid
	local v = run.venue
	local BAR = 76

	-- ── The start line (.dr) ──────────────────────────────────────────────────────────────────
	local scene = Ui.new("Frame", { Name = "DailyRun", Size = UDim2.new(1, 0, 1, -(BAR + 10)), BackgroundColor3 = Color3.fromHex("#9cc7e8"), ClipsDescendants = true, Parent = page }, {
		Ui.corner(18),
		Ui.stroke(3, Ui.LINE),
	})
	-- The sky over the whole card (its rounded top), the ground over its lower part (its rounded
	-- bottom, squared off at the horizon).
	local sky = Ui.new("Frame", { Name = "Sky", BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, Parent = scene }, { Ui.corner(16) })
	local top, haze = Color3.fromHex(v.sky or "#3d9bff"), Color3.fromHex(v.fog or "#d9f2ff")
	Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, top), ColorSequenceKeypoint.new(0.55, haze), ColorSequenceKeypoint.new(1, haze) }), Parent = sky })
	local groundColor = Color3.fromHex(v.ground or "#7d8691")
	local ground = Ui.new("Frame", { Name = "Ground", BorderSizePixel = 0, Position = UDim2.fromScale(0, 0.55), Size = UDim2.fromScale(1, 0.45), BackgroundColor3 = groundColor, Parent = scene }, { Ui.corner(16) })
	Ui.new("Frame", { Name = "Horizon", BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 20), BackgroundColor3 = groundColor, Parent = ground })
	local road = Ui.new("Frame", { Name = "Road", BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromScale(0.62, 1), BackgroundColor3 = Color3.fromHex(v.road or "#4d5560"), Parent = ground })
	if not v.road then
		Ui.gradient("#7d8691", "#4d5560").Parent = road
	end
	-- The start line across the road.
	Ui.new("Frame", { BorderSizePixel = 0, Position = UDim2.fromScale(0, 0.62), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = Ui.WHITE, Parent = road })
	-- The loaner, and its par ghost beside it, see-through.
	local ghost = Thumb.new("Cars", run.car.id, UDim2.fromScale(0.3, 0.62), Color3.fromHex("#eceff1"))
	ghost.AnchorPoint = Vector2.new(0.5, 1)
	ghost.Position = UDim2.fromScale(0.62, 0.86)
	ghost.ImageTransparency = 0.55
	ghost.ZIndex = 2
	ghost.Parent = scene
	Ui.text({ Text = "👻 Par", Body = true, Weight = "heavy", TextSize = 14, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.02), Size = UDim2.fromOffset(80, 18), Stroke = 2, ZIndex = 3, Parent = ghost })
	local car = Thumb.new("Cars", run.car.id, UDim2.fromScale(0.34, 0.7), Color3.fromHex(run.color))
	car.AnchorPoint = Vector2.new(0.5, 1)
	car.Position = UDim2.fromScale(0.4, 0.9)
	car.ZIndex = 3
	car.Parent = scene

	-- The timing tower: day number and today's best.
	local tower = Ui.new("Frame", { Name = "Tower", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 48), Size = UDim2.fromOffset(150, 74), BackgroundColor3 = Color3.fromHex("#14213d"), ZIndex = 4, Parent = scene }, {
		Ui.corner(12),
		Ui.stroke(2.5, Ui.WHITE),
	})
	local n = daily.dailyNumber(run.day)
	Ui.text({ Text = if n >= 1 then `📅 DAILY #{n}` else "📅 DAILY RUN", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex("#ffd54f"), Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 16), ZIndex = 4, Parent = tower })
	Ui.text({ Text = if best then fmt3(best) else "--", TextSize = 28, TextColor3 = if medal and medal < #daily.DAILY_MEDALS then Color3.fromHex("#7ee787") else Ui.WHITE, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 30), ZIndex = 4, Parent = tower })
	Ui.text({ Text = "Today's best", Body = true, TextSize = 12, TextColor3 = Color3.fromHex("#cfe0ff"), Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 14), ZIndex = 4, Parent = tower })

	-- Chips over it (.dr-top): the venue and the time to the next run.
	local top = Ui.new("Frame", { Name = "Top", Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 0, 28), BackgroundTransparency = 1, ZIndex = 4, Parent = scene }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	chip(top, `{v.icon} {v.name}`, "#14213d", 1)
	chip(top, `⏳ {trial.shortLeft(msToTomorrow())}`, "#311b92", 2)

	-- The medal times (.dr-medals), green once beaten.
	local medals = Ui.new("Frame", { Name = "Medals", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -12), Size = UDim2.new(1, -20, 0, 46), BackgroundTransparency = 1, ZIndex = 4, Parent = scene }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -6, 1, 0), CellPadding = UDim2.fromOffset(8, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, m in daily.DAILY_MEDALS do
		local got = medal ~= nil and medal <= i - 1
		local f = Ui.new("Frame", { Name = `Medal{i}`, LayoutOrder = i, BackgroundColor3 = if got then GREEN else Ui.WHITE, ZIndex = 4, Parent = medals }, { Ui.corner(14), Ui.stroke(3, Ui.LINE) })
		Ui.text({ Text = `{m.icon}  {string.format("%.2fs", run.medals[i])}`, TextSize = 20, TextColor3 = if got then Ui.WHITE else Ui.INK, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = f })
	end

	-- ── The bar: the loaner and the Run button ────────────────────────────────────────────────
	local _, bar = Ui.shadowed({ Name = "Loaner", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, BAR - 4), Parent = page }, { radius = 16, stroke = 2.5, drop = 3, colors = "navy" })
	local well = Ui.new("Frame", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(0, 76, 1, -16), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.05, Parent = bar }, { Ui.corner(10), Ui.stroke(2, Ui.LINE) })
	Thumb.new("Cars", run.car.id, UDim2.fromScale(1, 1), Color3.fromHex(run.color)).Parent = well
	Ui.text({ Text = "📅 TODAY'S LOANER · STOCK", Body = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(100, 8), Size = UDim2.fromOffset(300, 16), TextColor3 = Color3.fromHex("#ffd54f"), Parent = bar })
	Ui.text({ Text = run.car.name, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(100, 24), Size = UDim2.new(1, -330, 0, 26), Shadow = 2, Parent = bar })
	local piText = `PI {run.pi}`
	local piChip = Ui.new("Frame", { Position = UDim2.fromOffset(100, 50), Size = UDim2.fromOffset(math.ceil(Ui.textWidth(piText, 13)) + 14, 18), BackgroundColor3 = Color3.fromHex("#ffd54f"), Parent = bar }, { Ui.corner(6), Ui.stroke(1.5, Ui.LINE) })
	Ui.text({ Text = piText, TextSize = 13, TextColor3 = Ui.LINE, Size = UDim2.fromScale(1, 1), Parent = piChip })
	local skill = if run.car.skill and data.SKILLS[run.car.skill] then `{data.SKILLS[run.car.skill].icon} {data.SKILLS[run.car.skill].name}` else ""
	Ui.text({ Text = skill, Body = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 108 + piChip.Size.X.Offset, 0, 50), Size = UDim2.fromOffset(200, 18), TextColor3 = Color3.fromHex("#cfe0ff"), Parent = bar })
	local label = if paid then "🏁 Run" else `🏁 {api.money(daily.DAILY_PAY[1])}`
	Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(190, 48), Parent = bar }, `{label}  ⛽{trial.TRIAL_FUEL}`, "green", function()
		api.start("daily", nil)
	end, 18)
end

-- The race screen: the venue in the title, and the result card as the web's DailyResult: the
-- medal and time beside the par (the card's two times), today's best, and what the run paid.
function Daily.extras(_ctx: any, _which: any, started: any, again: (string, any) -> () -> ()): DragStrip.Extras
	local venue = started.venue or {}
	return {
		title = `📅 Daily Run · {venue.name or ""}`,
		heading = function(res: any): string?
			local m = daily.DAILY_MEDALS[(res.medal or #daily.DAILY_MEDALS) + 1]
			return `{if m then m.icon else "📅"} {fmt3(res.myTime)}`
		end,
		view = function(card: Frame, res: any, y: number): number
			local best = res.best or res.myTime
			local line = if res.myTime <= best then "Today's best!" else `Best today: {fmt3(best)}`
			Ui.text({ Text = line, TextSize = 20, TextColor3 = Ui.INK, Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 24), Parent = card })
			y += 28
			local paidLine = if res.paidNow then "The day's first run pays" else "Today's pay is taken: chase a better time"
			Ui.text({ Text = paidLine, Body = true, TextSize = 14, TextColor3 = if res.paidNow then Color3.fromHex("#2e7d32") else Ui.MUTED, Position = UDim2.fromOffset(20, y), Size = UDim2.new(1, -40, 0, 20), Parent = card })
			return y + 28
		end,
		buttons = function(_res: any): { DragStrip.Button }?
			return {
				{ text = "Back", kind = "garage" },
				{ text = "↻ Again", go = again("daily", nil) },
			}
		end,
	}
end

return Daily
