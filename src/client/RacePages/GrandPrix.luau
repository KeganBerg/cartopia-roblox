--!strict
-- The Grand Prix page (ui/Race.tsx GrandPrix): the four series side by side, each with its cup,
-- the six rounds (won ones ticked), how many times it's been won, the next round's circuit and
-- rival, the mystery box's cars turning one at a time, and the button: the race (its prize and
-- fuel), or what's in the way (the level, the final's PI, the cars it needs). Each round is a
-- kart race (client/KartRun); the server (server/Karts) starts and pays it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local K = require(Game.kart) :: any
local gpBeat = require(Game.gpBeat) :: any
local raceCar = require(Game.raceCar) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)

local GrandPrix = {}
GrandPrix.id = "gp"
GrandPrix.title = "Grand Prix"

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local GP_CUP = { "🥉", "🏆", "🏆", "👑" }
-- Each series' colours (.rm-gp-0 … .rm-gp-3).
local GRADS = { { "#7ee05a", "#2f9e35" }, { "#5aa9ff", "#2263d6" }, { "#b48cff", "#6a3fd0" }, { "#ffcf4a", "#e07b00" } }

function GrandPrix.chip(_s: any): string
	return `🏁 ×{data.GP_ROUNDS} → 🎁`
end

-- The round's named rival (Race.tsx gpRival): the car nearest their PI.
local function rivalOf(series: any, r: number, clears: number): any
	return { name = series.rivals[r + 1], pi = data.gpRivalPi(series, r, clears) }
end

-- The PI the final needs (Race.tsx gpFinalNeed; 0 before the final).
local function finalNeed(series: any, clears: number, r: number): number
	if r ~= data.GP_ROUNDS - 1 then
		return 0
	end
	return gpBeat.gpClearPi(data.gpRivalPi(series, data.GP_ROUNDS - 1, clears)) or 0
end

function GrandPrix.draw(page: Frame, ctx: any, api: any)
	local s = store.useGame.getState()
	local level = store.gateLevel(s)
	local gp = s.gp or {}
	local best = raceCar.bestCar(s.cars)
	local myBest = if best then raceCar.carPi(best) else 0
	local grid = Ui.new("Frame", { Name = "GrandPrix", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = page }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0.25, -9, 1, -6), CellPadding = UDim2.fromOffset(12, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, series in data.GP_SERIES do
		local si = i - 1
		local prog = gp[series.id] or { round = 0, clears = 0 }
		local round, clears = prog.round or 0, prog.clears or 0
		local locked = not data.gpOpen(gp, si, level)
		local short = #s.cars < series.minCars
		local rival = rivalOf(series, round, clears)
		local prize = data.gpReward(series, round)
		local need = finalNeed(series, clears, round)
		local cell = Ui.new("Frame", { Name = series.id, LayoutOrder = i, BackgroundTransparency = 1, Parent = grid })
		local shadow, card = Ui.shadowed({ Size = UDim2.new(1, 0, 1, -4), Position = UDim2.fromOffset(0, 4), Parent = cell }, { radius = 18, stroke = 3, drop = 4, dark = 0.3, color = Ui.WHITE })
		local _ = shadow
		card.ClipsDescendants = true
		local g = GRADS[i] or GRADS[1]
		if locked then
			g = { "#b8c0c8", "#7d8791" }
		end

		-- The top: the series' colours, its name, cup, rounds and wins (.rm-gpc-top).
		local topH = if clears > 0 then 100 else 72
		local top = Ui.new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, topH), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = card }, { Ui.corner(16), Ui.new("UIGradient", { Color = Ui.seq(g[1], g[2]), Rotation = 45 }) })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = top }, { Ui.new("UIGradient", { Color = Ui.seq(g[1], g[2]), Rotation = 45 }) })
		Ui.new("Frame", { Name = "Gloss", Position = UDim2.fromOffset(10, 1), Size = UDim2.new(1, -20, 0, 3), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.7, BorderSizePixel = 0, Parent = top }, { Ui.round() })
		Ui.text({ Text = GP_CUP[i] or "🏆", TextSize = 28, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(34, 34), Parent = top })
		Ui.text({ Name = "Title", Text = series.name, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(10, 8), Size = UDim2.new(1, -50, 0, 24), Stroke = 2, Shadow = 2, Parent = top })
		for n = 0, data.GP_ROUNDS - 1 do
			local won, nextOne = n < round, n == round
			local pip = Ui.new("Frame", { Position = UDim2.fromOffset(10 + n * 27, 38), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = if won then hex("#ffd84a") elseif nextOne then Ui.WHITE else Ui.WHITE, BackgroundTransparency = if won or nextOne then 0 else 0.7, Parent = top }, { Ui.round(), Ui.stroke(2, Ui.LINE, if won or nextOne then 0 else 0.45) })
			Ui.text({ Text = if won then "✔" else tostring(n + 1), TextSize = 13, TextColor3 = if won or nextOne then Ui.LINE else Ui.WHITE, Size = UDim2.fromScale(1, 1), Parent = pip })
		end
		if clears > 0 then
			local text = `🏆×{clears}`
			local w = math.ceil(Ui.textWidth(text, 14)) + 22
			local wchip = Ui.new("Frame", { Position = UDim2.fromOffset(10, 68), Size = UDim2.fromOffset(w, 24), BackgroundColor3 = hex("#0a142d"), BackgroundTransparency = 0.55, Parent = top }, { Ui.round() })
			Ui.text({ Text = text, TextSize = 14, Size = UDim2.fromScale(1, 1), Parent = wchip })
		end

		-- The body: the next round, the mystery box and the button (.rm-gpc-body).
		local body = Ui.new("Frame", { Name = "Body", Position = UDim2.fromOffset(10, topH + 8), Size = UDim2.new(1, -20, 1, -(topH + 8) - 10), BackgroundTransparency = 1, Parent = card })
		local tr = K.gpTrack(round)
		local trackText = `{tr.def.short}{if tr.reverse then " ↺" else ""}`
		local tw = math.ceil(Ui.textWidth(trackText, 13)) + 16
		local trackChip = Ui.new("Frame", { Name = "Track", Size = UDim2.fromOffset(tw, 20), BackgroundColor3 = hex("#43a047"), Parent = body }, { Ui.corner(8) })
		Ui.text({ Text = trackText, TextSize = 13, Size = UDim2.fromScale(1, 1), Parent = trackChip })
		Ui.text({ Name = "Next", Text = `Race {round + 1}: <font color="#1b2a4a">{rival.name}</font> · PI {rival.pi}`, RichText = true, Body = true, Weight = "heavy", TextSize = 14, TextWrapped = true, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 36), Parent = body })
		local box = Ui.new("Frame", { Name = "Box", Position = UDim2.fromOffset(0, 64), Size = UDim2.new(1, 0, 1, -64 - 50), BackgroundColor3 = hex("#f2f6fc"), Parent = body }, { Ui.corner(12) })
		local boxName = Ui.text({ Text = "", Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.MUTED, TextWrapped = true, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 4, 1, -18), Size = UDim2.new(1, -8, 0, 34), TextYAlignment = Enum.TextYAlignment.Bottom, Parent = box })
		local dotRow = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(#series.box * 12, 8), BackgroundTransparency = 1, Parent = box })
		local dots = {}
		for n = 1, #series.box do
			dots[n] = Ui.new("Frame", { Position = UDim2.fromOffset((n - 1) * 12 + 2, 0), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Ui.LINE, Parent = dotRow }, { Ui.round() })
		end
		local pic: GuiObject? = nil
		local function showCar(k: number)
			local car = data.carDef(series.box[k])
			if pic then
				pic:Destroy()
			end
			-- A small turning picture in the middle of the box (.rm-box .thumb3d.sm, 120x94).
			local p = Thumb.new("Cars", car.id, UDim2.fromOffset(150, 118), Color3.fromHex(car.colors[1]))
			p.AnchorPoint = Vector2.new(0.5, 0.5)
			p.Position = UDim2.new(0.5, 0, 0.5, -22)
			if locked then
				p.ImageTransparency = 0.4
			end
			p.Parent = box
			pic = p
			Ui.setText(boxName, `🎁 {car.name}`)
			for n, d in dots do
				d.BackgroundTransparency = if n == k then 0 else 0.75
			end
		end
		showCar(1)
		if #series.box > 1 then
			task.spawn(function()
				local k = 1
				while true do
					task.wait(2.8)
					if not box.Parent or not page.Parent then
						return
					end
					k = k % #series.box + 1
					showCar(k)
				end
			end)
		end

		local at = { Name = "Go", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 44) }
		if locked then
			local first = level < data.GP_SERIES[1].unlockLevel or si == 0
			at.Parent = body
			Ui.buy(at, if first then `🔒 Level {series.unlockLevel}` else `🔒 Lv {series.unlockLevel}`, "grey", function()
				ctx.open("need", { res = "level", missing = series.unlockLevel, what = series.name })
			end, 17)
		elseif need > myBest then
			at.Parent = body
			Ui.buy(at, `🔒 Final needs PI {need}`, "grey", function()
				ctx.open("garage")
			end, 15)
		elseif short then
			at.Parent = body
			Ui.buy(at, `🚗 {#s.cars}/{series.minCars} cars`, "garage", function()
				ctx.open("rescue")
			end, 17)
		else
			local _b, face = api.raceButton(body, at, prize, function()
				api.kart("gp", series.id)
			end)
			local _ = face
		end
	end
end

return GrandPrix
