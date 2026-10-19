--!strict
-- The Pro Tour page (ui/Race.tsx Tour): the endless ladder. A strip of the legs either side of the
-- one being raced (rank badges where a new rank starts), the leg's banner (venue, day or night,
-- the next race's sky, the boss bonus, races won and the rank), and the leg's five races, the
-- next one with its race button. Shut until Back Streets is cleared, its first leg greyed out
-- under the way in. The server (server/Modes/Tour) starts and pays the races.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local tour = require(Game.tour) :: any
local venues = require(Game.scene_venues) :: any
local distance = require(Game.distance) :: any
local weather = require(Game.weather) :: any
local TourRivals = require(Shared:WaitForChild("TourRivals"))
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local DragStrip = require(script.Parent.Parent.DragStrip)

local Tour = {}
Tour.id = "tour"
Tour.title = "Pro Tour"

local SKY_ICON = { clear = "☀️", rain = "🌧️", storm = "⛈️", drizzle = "🌦️", fog = "🌫️", wind = "💨", snow = "🌨️", blizzard = "❄️", dust = "🌪️", mist = "🌁", clearing = "🌈", heat = "🔆" }
local PURPLE = Color3.fromHex("#7c4dff")

local function rules(name: string): any
	return require(Game:FindFirstChild(name) :: ModuleScript) :: any
end

local function legName(leg: any): string
	local v = venues.venue(leg.venue)
	return if leg.night then `{v.name} at Midnight` else `{v.name} {leg.name}`
end

-- The menu head's chip: your rank and races won (Race.tsx).
function Tour.chip(s: any): string
	local won = s.tour or 0
	local r = tour.tourRank(tour.tourLegOf(won))
	return `{r.icon} {r.name} · 🌍 {Ui.commas(won)}`
end

local function opened(s: any): boolean
	return data.campaignCleared(s.campaign or {}, data.CAMPAIGN[1])
end

function Tour.draw(page: Frame, _ctx: any, api: any)
	local s = store.useGame.getState()
	local won = s.tour or 0
	local open = opened(s)
	local cur = tour.tourLegOf(won)
	local leg = tour.tourLeg(cur)
	local v = venues.venue(leg.venue)
	local first = cur * tour.TOUR_RACES
	-- The next race's sky, rolled from its number so it matches the race itself.
	local sky = weather.raceWeather(leg.venue, `tour-{won}`).kind

	-- The legs either side of this one (.rm-nodes).
	local nodes = Ui.new("Frame", { Name = "Legs", Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, Parent = page }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local from = math.max(0, cur - 2)
	for i = 0, 5 do
		local k = from + i
		local l = tour.tourLeg(k)
		local done, here = k < cur, k == cur
		local node = Ui.new("Frame", { Name = `Leg{k + 1}`, LayoutOrder = i, Size = UDim2.new(0, 50, 1, -4), BackgroundColor3 = if here then Color3.fromHex("#ffd54f") elseif l.night then Color3.fromHex("#283593") else Ui.WHITE, BackgroundTransparency = if done or here then 0 else 0.35, Parent = nodes }, {
			Ui.corner(14),
			Ui.stroke(if here then 3 else 2, if here then Color3.fromHex("#ff8f00") else Ui.LINE),
		})
		Ui.text({ Text = if done then "✔" else venues.venue(l.venue).icon, TextSize = 22, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 28), TextColor3 = Color3.fromHex("#2e7d32"), Parent = node })
		Ui.text({ Text = `Leg {k + 1}`, Body = true, Weight = "heavy", TextSize = 12, Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 18), TextColor3 = if l.night and not here then Ui.WHITE else Ui.INK, Parent = node })
		if k % tour.TOUR_RANK_LEGS == tour.TOUR_RANK_LEGS - 1 and tour.tourRankOf(k + 1) > tour.tourRankOf(k) then
			Ui.text({ Text = tour.tourRank(k + 1).icon, TextSize = 18, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 6, 0, -6), Size = UDim2.fromOffset(22, 22), Parent = node })
		end
	end

	-- The leg's banner (.rm-banner).
	local left = Ui.new("Frame", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(0.38, -6, 1, -70), BackgroundTransparency = 1, Parent = page })
	local _, banner = api.tile(left, { Size = UDim2.fromScale(1, 1) }, if leg.night then "#3949ab" else "#9575cd", if leg.night then "#1a1446" else "#5e35b1", true)
	Ui.text({ Text = `Leg {cur + 1} · {if leg.night then "🌙 Under the lights" else "Daytime"} · {SKY_ICON[sky] or ""}`, Body = true, TextSize = 14, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 36), TextYAlignment = Enum.TextYAlignment.Top, Parent = banner })
	Ui.text({ Text = legName(leg), TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 70), TextYAlignment = Enum.TextYAlignment.Top, Stroke = 3, Shadow = 3, Parent = banner })
	Ui.text({ Text = v.icon or "🏁", TextSize = 80, Position = UDim2.fromOffset(0, 116), Size = UDim2.new(1, 0, 0, 96), Parent = banner })
	local chips = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 92), BackgroundTransparency = 1, Parent = banner }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom }),
	})
	local toRank = tour.tourLegsToRank(cur)
	local rank = tour.tourRank(cur)
	for i, text in {
		`👑 Boss bonus {api.money(tour.tourLegBonus(cur))}`,
		`{won - first} of {tour.TOUR_RACES} won`,
		if toRank > 0 then `{rank.icon} {rank.name} · {tour.tourRank(cur + toRank).icon} {toRank}` else `{rank.icon} {rank.name}`,
	} do
		local c = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.new(0, 0, 0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.55, Parent = chips }, {
			Ui.corner(12),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }),
		})
		Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 13, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = c })
	end

	-- The leg's five races (.rm-rows).
	local rows = Ui.new("Frame", { Name = "Races", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 70), Size = UDim2.new(0.62, -6, 1, -70), BackgroundTransparency = 1, Parent = page }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local game = rules
	for i = 0, tour.TOUR_RACES - 1 do
		local race = first + i
		local r = TourRivals.tour(game, race)
		local beat = open and race < won
		local nextOne = open and race == won
		local row = Ui.new("Frame", { Name = `Race{i + 1}`, LayoutOrder = i, Size = UDim2.new(1, 0, if open then 0.2 else 0.17, -7), BackgroundColor3 = if nextOne then Color3.fromHex("#fff8e1") elseif r.boss then Color3.fromHex("#f3e5f5") else Ui.WHITE, BackgroundTransparency = if beat or nextOne then 0 else 0.4, Parent = rows }, {
			Ui.corner(14),
			Ui.stroke(if nextOne then 3 else 2, if nextOne then Color3.fromHex("#ffb300") elseif r.boss then PURPLE else Ui.EDGE),
		})
		Ui.text({ Text = if beat then "✔" elseif r.boss then "👑" else tostring(i + 1), TextSize = 22, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 34, 1, 0), TextColor3 = if beat then Color3.fromHex("#2e7d32") else api.DARK, Parent = row })
		local pic = Thumb.new("Cars", r.model, UDim2.new(0, 70, 1, -6), Color3.fromHex(r.color))
		pic.Position = UDim2.fromOffset(40, 3)
		pic.Parent = row
		Ui.text({ Text = r.name, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 116, 0, 4), Size = UDim2.new(1, -300, 0.5, 0), TextColor3 = Ui.INK, Parent = row })
		local skill = if r.skill and data.SKILLS[r.skill] then ` {data.SKILLS[r.skill].icon}` else ""
		Ui.text({ Text = `{distance.DIST[distance.tourDist(race)].label}   PI {r.pi}{skill}`, Body = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 116, 0.5, -2), Size = UDim2.new(1, -300, 0.5, 0), TextColor3 = Ui.MUTED, Parent = row })
		local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(170, 44) }
		if beat then
			Ui.text({ Text = "✔", TextSize = 26, AnchorPoint = at.AnchorPoint, Position = UDim2.new(1, -20, 0.5, 0), Size = UDim2.fromOffset(40, 40), TextColor3 = Color3.fromHex("#2e7d32"), Parent = row })
		elseif nextOne then
			api.raceButton(row, at, r.prize, function()
				api.start("tour", nil)
			end)
		else
			at.Parent = row
			Ui.buy(at, "🔒", "grey")
		end
	end
	if not open then
		-- The way in, on top of the greyed first leg (.rm-tgate-btn).
		Ui.buy({ Name = "Gate", LayoutOrder = 99, Size = UDim2.new(1, 0, 0, 52), Parent = rows }, `🔒 Clear {data.CAMPAIGN[1].name} to open`, "garage", function()
			api.show("campaign")
		end, 17)
	end
end

-- The race screen: the leg and race in the title, the next race after a win (Race.tsx).
function Tour.extras(_ctx: any, _which: any, started: any, again: (string, any) -> () -> ()): DragStrip.Extras
	local race = tonumber(started.rival.id:match("^tour%-(%d+)$")) or 0
	local leg = tour.tourLeg(tour.tourLegOf(race))
	local step = race % tour.TOUR_RACES
	local dist = distance.DIST[distance.tourDist(race)].label
	return {
		title = `{if leg.night then "🌙" else "🌍"} Pro Tour · Leg {leg.index + 1} · {if tour.tourIsBoss(race) then "Boss race" else `Race {step + 1} of {tour.TOUR_RACES}`} · {dist}`,
		heading = function(res: any): string?
			return if res.legBonus then "LEG CLEARED!" else nil
		end,
		buttons = function(res: any): { DragStrip.Button }?
			local label = if res.won then `▶ Next · ${Ui.commas(TourRivals.tour(rules, res.tour or race + 1).prize)}` else "↻ Retry"
			return { { text = "Back", kind = "garage" }, { text = label, go = again("tour", nil) } }
		end,
	}
end

return Tour
