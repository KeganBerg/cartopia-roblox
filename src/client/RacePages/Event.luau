--!strict
-- The weekly event page (ui/Race.tsx WeeklyEvent): this week's venue and sky on a banner with next
-- week's event, the five rivals as a ladder of cars (the boss wearing the prize skin), who's next,
-- and the exclusive skin on your own car with the boss bonus (doubled when you already own it).
-- The server (server/Modes/Event) starts and pays the races.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local events = require(Game.events) :: any
local venues = require(Game.scene_venues) :: any
local raceCar = require(Game.raceCar) :: any
local trial = require(Game.trial) :: any
local TourRivals = require(Shared:WaitForChild("TourRivals"))
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local DragStrip = require(script.Parent.Parent.DragStrip)

local Event = {}
Event.id = "event"
Event.title = "Weekly Event"

local SKY_ICON = { clear = "☀️", rain = "🌧️", storm = "⛈️", drizzle = "🌦️", fog = "🌫️", wind = "💨", snow = "🌨️", blizzard = "❄️", dust = "🌪️", mist = "🌁", clearing = "🌈", heat = "🔆" }
local GREEN = Color3.fromHex("#2e7d32")

local function rules(name: string): any
	return require(Game:FindFirstChild(name) :: ModuleScript) :: any
end

-- The PI the event's rivals sit around: the one you entered with, else your best car's (Race.tsx evBase).
function Event.base(s: any): number
	local p = events.eventProgress(s.event)
	if p and p.pi then
		return p.pi
	end
	local best = raceCar.bestCar(s.cars or {})
	return if best then raceCar.carPi(best) else 0
end

-- The menu head's chip: the time left this week.
function Event.chip(_s: any): string
	return `⏳ {trial.shortLeft(data.msToNextWeek())}`
end

local function chipOn(parent: Instance, text: string, props: { [string]: any }): Frame
	local c = Ui.new("Frame", { Size = UDim2.new(0, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.55, Parent = parent }, {
		Ui.corner(12),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
	})
	for k, v in props do
		(c :: any)[k] = v
	end
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 13, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = c })
	return c
end

function Event.draw(page: Frame, _ctx: any, api: any)
	local s = store.useGame.getState()
	local base = Event.base(s)
	local p = events.eventProgress(s.event)
	local e = events.eventFor()
	local won = if p then p.won else 0
	local done = won >= events.EVENT_RACES
	local skin = data.skinDef(e.skin)
	local has = table.find(s.skins or {}, e.skin) ~= nil
	local v = venues.venue(e.venue)
	local nextEv = events.eventFor(events.nextEventWeek())
	local col = Color3.fromHex(e.color)
	local bonus = if has and not done then events.eventBonus(base) * 2 else events.eventBonus(base)
	local car = api.myCar()

	-- The banner (.rm-banner): the venue, its sky, the event's name and next week's.
	local left = Ui.new("Frame", { Size = UDim2.new(0.38, -6, 1, 0), BackgroundTransparency = 1, Parent = page })
	local top = col:Lerp(Ui.WHITE, 0.15)
	local bottom = col:Lerp(Ui.BLACK, if e.night then 0.6 else 0.35)
	local _, banner = api.tile(left, { Size = UDim2.fromScale(1, 1) }, top:ToHex(), bottom:ToHex(), true)
	Ui.text({ Text = `{v.icon} {v.name}{if e.night then " · 🌙" else ""} · {SKY_ICON[e.sky] or ""}`, Body = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 18), Parent = banner })
	Ui.text({ Text = e.name, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(14, 36), Size = UDim2.new(1, -28, 0, 76), TextYAlignment = Enum.TextYAlignment.Top, Stroke = 3, Shadow = 3, Parent = banner })
	Ui.text({ Text = e.blurb, Body = true, TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(14, 116), Size = UDim2.new(1, -28, 0, 60), Parent = banner })
	Ui.text({ Text = v.icon or "🏁", TextSize = 70, Position = UDim2.fromOffset(0, 178), Size = UDim2.new(1, 0, 0, 84), Parent = banner })
	chipOn(banner, `⏭ {nextEv.name}`, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12) })

	local right = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.62, -6, 1, 0), BackgroundTransparency = 1, Parent = page })
	-- The ladder of five cars (.ev-steps), the boss in the prize skin.
	local steps = Ui.new("Frame", { Name = "Ladder", Size = UDim2.new(1, 0, 0, 112), BackgroundColor3 = Ui.WHITE, Parent = right }, {
		Ui.corner(16),
		Ui.stroke(2.5, col),
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }),
	})
	local game = rules
	local rivals = {}
	for i = 0, events.EVENT_RACES - 1 do
		local r = TourRivals.event(game, base, i)
		rivals[i + 1] = r
		local state = if i < won then "done" elseif i == won then "next" else "locked"
		-- Each step a little taller than the last (.ev-step's climb).
		local h = 70 + i * 8
		local step = Ui.new("Frame", { Name = `Step{i + 1}`, LayoutOrder = i, Size = UDim2.new(0, 40, 0, h), BackgroundColor3 = if state == "next" then Color3.fromHex("#fff8e1") else Color3.fromHex("#f4f6fa"), BackgroundTransparency = if state == "locked" then 0.4 else 0, Parent = steps }, {
			Ui.corner(10),
			Ui.stroke(if state == "next" then 3 else 1.5, if state == "next" then Color3.fromHex("#ffb300") elseif r.boss then col else Ui.EDGE),
		})
		local pic = Thumb.car(r.model, UDim2.new(1, 0, 0, 44), { color = r.color }, nil, nil, nil, nil, if r.boss then e.skin else nil)
		pic.Position = UDim2.new(0, 0, 1, -66)
		pic.Parent = step
		local badge = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = if state == "done" then Color3.fromHex("#66bb6a") elseif r.boss then col else Ui.WHITE, Parent = step }, { Ui.round(), Ui.stroke(2, Ui.LINE) })
		Ui.text({ Text = if state == "done" then "✔" elseif r.boss then "👑" else tostring(i + 1), TextSize = 14, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.INK, Parent = badge })
		Ui.text({ Text = `PI {r.pi}`, Body = true, Weight = "heavy", TextSize = 12, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 16), TextColor3 = Ui.INK, Parent = step })
	end

	-- Who's next (.ev-vs), with the race button.
	local vs = Ui.new("Frame", { Name = "Versus", Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 0, 60), BackgroundColor3 = if done then Color3.fromHex("#e8f5e9") else Ui.WHITE, Parent = right }, {
		Ui.corner(14),
		Ui.stroke(2, if done then GREEN else Ui.LINE),
	})
	if done then
		Ui.text({ Text = `🏆 {events.EVENT_RACES}/{events.EVENT_RACES}  ·  Back next week`, TextSize = 20, TextColor3 = Ui.INK, Size = UDim2.fromScale(1, 1), Parent = vs })
	else
		local r = rivals[won + 1]
		local tagF = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.fromOffset(40, 26), BackgroundColor3 = col, Parent = vs }, { Ui.corner(8), Ui.stroke(2, Ui.LINE) })
		Ui.text({ Text = "VS", TextSize = 15, Size = UDim2.fromScale(1, 1), Stroke = 1.5, Parent = tagF })
		local skill = if r.skill and data.SKILLS[r.skill] then ` {data.SKILLS[r.skill].icon}` else ""
		Ui.text({ Text = `{r.name}{skill}`, TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(58, 0), Size = UDim2.new(1, -240, 1, 0), Parent = vs })
		api.raceButton(vs, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(170, 44) }, r.prize, function()
			api.start("event", nil)
		end)
	end

	-- The prize (.ev-reward): the event's skin on your car.
	local got = done or has
	local reward = Ui.new("Frame", { Name = "Reward", Position = UDim2.fromOffset(0, 188), Size = UDim2.new(1, 0, 1, -188), BackgroundColor3 = if done then Color3.fromHex("#e8f5e9") else Ui.WHITE, Parent = right }, {
		Ui.corner(16),
		Ui.stroke(2.5, if done then GREEN else col),
	})
	local d = if car then data.carDef(car.model) else data.CARS[1]
	local pic = Thumb.car(d.id, UDim2.fromOffset(170, 110), { color = if car then car.color else d.colors[1], finish = car and car.finish, stripe = car and car.stripe }, nil, car and car.mods, nil, nil, e.skin)
	pic.AnchorPoint = Vector2.new(0, 0.5)
	pic.Position = UDim2.new(0, 8, 0.5, 0)
	pic.Parent = reward
	Ui.text({ Text = if got then "✔" else "👑", TextSize = 22, Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(28, 28), Parent = reward })
	local info = Ui.new("Frame", { Position = UDim2.fromOffset(188, 0), Size = UDim2.new(1, -198, 1, 0), BackgroundTransparency = 1, Parent = reward }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	Ui.text({ Text = skin and skin.name or e.skin, LayoutOrder = 1, TextSize = 24, TextWrapped = true, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 56), Parent = info })
	if skin then
		local tier = data.SKIN_TIERS[skin.tier]
		local row = Ui.new("Frame", { LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = info }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center }),
		})
		local sw = Ui.new("Frame", { Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Ui.WHITE, Parent = row }, { Ui.round(), Ui.stroke(2, Ui.LINE) })
		-- The skin's swatch is a CSS gradient on the web; its boldest colour stands in, else the event's.
		local pick, most = col, -1
		for hex in string.gmatch(skin.swatch or "", "#%x%x%x%x%x%x") do
			local c = Color3.fromHex(hex)
			local _, sat = c:ToHSV()
			if sat > most then
				pick, most = c, sat
			end
		end
		sw.BackgroundColor3 = pick
		if tier then
			local t = Ui.new("Frame", { Size = UDim2.new(0, 0, 0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromHex(tier.color), Parent = row }, {
				Ui.corner(8),
				Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }),
			})
			Ui.text({ Text = tier.name, TextSize = 13, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Stroke = 1.5, Parent = t })
		end
	end
	Ui.text({ Text = if done then "Yours: put it on any car in the Paint Shop" elseif has then "Already yours: the bonus is doubled" else "Beat the boss to win it", LayoutOrder = 3, Body = true, TextSize = 13, TextWrapped = true, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 34), Parent = info })
	if not done then
		Ui.text({ Text = `👑 +{api.money(bonus)}`, LayoutOrder = 4, TextSize = 20, TextColor3 = Color3.fromHex("#e65100"), TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 24), Parent = info })
	end
end

-- The race screen: the event and race in the title, the next race after a win (Race.tsx).
function Event.extras(_ctx: any, _which: any, started: any, again: (string, any) -> () -> ()): DragStrip.Extras
	local e = events.eventFor(started.extra and started.extra.week)
	local race = started.extra and started.extra.race or 0
	return {
		title = `📅 {e.name} · {if events.eventIsBoss(race) then "Boss race" else `Race {race + 1} of {events.EVENT_RACES}`}`,
		heading = function(res: any): string?
			return if res.eventPrize then "EVENT CLEARED!" else nil
		end,
		buttons = function(res: any): { DragStrip.Button }?
			local ev = res.event
			local wonNow = if ev then ev.won else race
			if wonNow >= events.EVENT_RACES then
				return nil
			end
			local label = if res.won then `▶ Next · ${Ui.commas(events.eventPrize(ev.pi, wonNow))}` else "↻ Retry"
			return { { text = "Back", kind = "garage" }, { text = label, go = again("event", nil) } }
		end,
	}
end

return Event
