--!strict
-- The World Tour page (ui/WorldTour.tsx): Tour Blue as the prize on your car, the reputation it
-- takes to start, and the nine countries in order, each beaten one ticked and the next one with a
-- race button. The server (server/Modes/World) starts and pays the races.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local venues = require(Game.scene_venues) :: any
local distance = require(Game.distance) :: any
local reputation = require(Game.reputation) :: any
local wt = require(Game.worldTour) :: any
local raceCar = require(Game.raceCar) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local DragStrip = require(script.Parent.Parent.DragStrip)

local World = {}
World.id = "world"
World.title = "World Tour"
World.mini = { icon = "🌍", label = "World Tour" }

local function rep(s: any): any
	return reputation.reputation({ trophies = s.trophies, stats = s.stats, cups = s.cups, mastery = s.mastery })
end

function World.chip(s: any): string
	return `🌍 {math.min(s.worldTour or 0, #wt.WORLD_TOUR)}/{#wt.WORLD_TOUR}`
end

function World.draw(page: Frame, ctx: any, api: any)
	local s = store.useGame.getState()
	local beaten = s.worldTour or 0
	local r = rep(s)
	local open = r.tier >= wt.WORLD_TOUR_REP
	local done = wt.worldDone(beaten)
	local car = api.myCar()
	local list = Ui.scroller({ Name = "WorldTour", Size = UDim2.fromScale(1, 1), Parent = page })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = list })

	-- The prize: Tour Blue on the race car (.ev-reward).
	local reward = Ui.new("Frame", { Name = "Reward", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 104), BackgroundColor3 = if done then Color3.fromHex("#e8f5e9") else Ui.WHITE, Parent = list }, {
		Ui.corner(16),
		Ui.stroke(2.5, if done then Color3.fromHex("#43a047") else Ui.LINE),
	})
	local pic = if car
		then Thumb.car(car.model, UDim2.fromOffset(150, 96), { color = wt.TOUR_BLUE, finish = car.finish, stripe = car.stripe }, nil, car.mods)
		else Thumb.new("Cars", data.CARS[1].id, UDim2.fromOffset(150, 96), Color3.fromHex(wt.TOUR_BLUE))
	pic.Position = UDim2.fromOffset(8, 4)
	pic.Parent = reward
	Ui.text({ Text = if done then "✔" else "🔒", TextSize = 20, Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(26, 26), Parent = reward })
	Ui.text({ Text = "Tour Blue", TextSize = 26, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(172, 14), Size = UDim2.new(1, -180, 0, 30), Parent = reward })
	local sw = Ui.new("Frame", { Position = UDim2.fromOffset(172, 52), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromHex(wt.TOUR_BLUE), Parent = reward }, { Ui.round(), Ui.stroke(2, Ui.LINE) })
	Ui.text({ Text = "🎨 Only from the World Tour", Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(1, 8, 0, 0), Size = UDim2.fromOffset(260, 22), Parent = sw })
	if done and car then
		Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(130, 40), Parent = reward }, "🎨 Paint it", "green", function()
			ctx.open("garage", { car = car.uid, paint = wt.TOUR_BLUE })
		end, 16)
	end

	-- The gate: the reputation title that opens the tour (.wt-gate).
	if not open then
		local need = reputation.REP_TITLES[wt.WORLD_TOUR_REP + 1]
		local gate = Ui.new("Frame", { Name = "Gate", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Color3.fromHex("#fff4d6"), Parent = list }, { Ui.corner(12) })
		Ui.text({ Text = `🔒 {need.icon} {need.name} · {Ui.commas(r.toNext)} rep to go`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), Parent = gate })
	end

	-- The countries, in order (.wt-stop).
	for i, stop in wt.WORLD_TOUR do
		local idx = i - 1
		local won = idx < beaten
		local nextOne = idx == beaten
		local v = venues.venue(stop.venue)
		local row = Ui.new("Frame", { Name = stop.country, LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = if won or nextOne then 0 else 0.45, Parent = list }, {
			Ui.corner(14),
			Ui.stroke(if nextOne then 3 else 2.5, if nextOne then Color3.fromHex("#2b8cff") else Ui.LINE),
		})
		Ui.text({ Text = stop.flag, TextSize = 28, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(0, 38, 1, 0), Parent = row })
		Ui.text({ Text = `{stop.country} · {stop.name}`, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(58, 8), Size = UDim2.new(1, -230, 0, 20), Parent = row })
		Ui.text({ Text = `{v.icon} {v.name}{if stop.night then " 🌙" else ""}     {distance.DIST[stop.dist].label}     PI {stop.pi}`, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = Color3.fromHex("#4a6283"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(58, 30), Size = UDim2.new(1, -230, 0, 18), Parent = row })
		local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(150, 40), Parent = row }
		if won then
			Ui.buy(at, `↻ {api.money(wt.worldPrize(idx, false))}`, if open then "garage" else "grey", if open then function()
				api.start("world", idx)
			end else nil, 15)
		elseif nextOne and open then
			Ui.buy(at, `🏁 {api.money(wt.worldPrize(idx, true))}  ⛽{data.RACE_FUEL}`, "green", function()
				api.start("world", idx)
			end, 15)
		else
			Ui.text({ Text = "🔒", TextSize = 20, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(30, 30), Parent = row })
		end
	end
end

-- The race screen: the country in the title, the racer's words, and the next stop after a win.
function World.extras(ctx: any, which: any, started: any, again: (string, any) -> () -> ()): DragStrip.Extras
	local i: number = which
	local stop = wt.WORLD_TOUR[i + 1]
	return {
		title = `🌍 {stop.flag} {stop.country} · {i + 1} of {#wt.WORLD_TOUR}`,
		heading = function(res: any): string?
			return if res.champion then "WORLD CHAMPION!" else nil
		end,
		quote = function(res: any): string?
			return `“{if res.won then stop.beaten else stop.hello}”`
		end,
		buttons = function(res: any): { DragStrip.Button }?
			local n = if res.won then i + 1 else i
			local list: { DragStrip.Button } = { { text = "Back", kind = "garage" } }
			if res.champion then
				local s = store.useGame.getState()
				local car = raceCar.raceCarOf(s.cars, s.raceCar)
				if car then
					return { { text = "Back", kind = "garage" }, { text = "🎨 Paint it", go = function()
						ctx.open("garage", { car = car.uid, paint = wt.TOUR_BLUE })
					end } }
				end
				return nil
			end
			if wt.WORLD_TOUR[n + 1] then
				table.insert(list, { text = if res.won then `▶ {wt.WORLD_TOUR[n + 1].flag} {wt.WORLD_TOUR[n + 1].country}` else "↻ Retry", go = again("world", n) })
			end
			return list
		end,
	}
end

return World
