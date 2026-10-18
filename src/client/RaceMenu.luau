--!strict
-- The Race menu, as the web game's RacePanel (ui/Race.tsx, RaceHub.tsx): a front page with the
-- Campaign tile (its next race one tap away) and Quick Race; Quick Race's three rival cards; the
-- Campaign's chapters, each with its five races and stars. Along the bottom, the car you race
-- with (tap to change it). The rivals and prizes come from the server (server/Races), which also
-- starts the race and pays it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local venues = require(Game.scene_venues) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)
local DragStrip = require(script.Parent.DragStrip)

local RaceMenu = {}

local TITLES = { hub = "Race", quick = "Quick Race", campaign = "Campaign" }
local DARK = Color3.fromHex("#14213d")
local lastTab = "hub"
local lastChapter: number? = nil

local function money(n: number): string
	return if n >= 10000 then `${math.round(n / 1000)}k` else `${Ui.commas(n)}`
end

local function stars(n: number): string
	return string.rep("★", n) .. string.rep("☆", 3 - n)
end

-- The car picked to race with, else the best one.
local function myCar(): any?
	local s = store.useGame.getState()
	return raceCar.raceCarOf(s.cars, s.raceCar)
end

-- A tile: a dark rounded card with a coloured top, its tag, title and lines.
-- still: a picture, not a button.
local function tile(parent: Instance, props: { [string]: any }, top: string, bottom: string, still: boolean?): (Frame, any)
	local shadow, face = Ui.shadowed(props, { radius = 18, stroke = 3, drop = 5, dark = 0.35, class = if still then "Frame" else "TextButton", color = Ui.WHITE })
	Ui.gradient(top, bottom).Parent = face
	shadow.Parent = parent
	return shadow, face
end

local function tag(parent: Instance, text: string, y: number?)
	local f = Ui.new("Frame", { Position = UDim2.fromOffset(14, y or 12), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.55, Parent = parent }, { Ui.corner(11), Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 9), PaddingRight = UDim.new(0, 9) }) })
	Ui.text({ Text = text, TextSize = 13, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, Parent = f })
end

-- The green race button: the prize and the fuel it costs.
local function raceButton(parent: Instance, props: { [string]: any }, prize: number, onClick: () -> (), kind: string?)
	props.Parent = parent
	return Ui.buy(props, `🏁 {money(prize)}  ⛽{data.RACE_FUEL}`, kind or "green", onClick, 16)
end

function RaceMenu.open(ctx: any, startTab: string?): Instance
	local tab = startTab or lastTab
	local overlay, _sheet, body = Ui.panel(ctx.gui, TITLES[tab] or "Race", { wide = true, height = 640, onClose = ctx.close, bodyTop = 6 })
	local title = (overlay:FindFirstChild("Title", true) :: TextLabel?)
	local content = Ui.new("Frame", { Name = "Content", Size = UDim2.new(1, 0, 1, -86), BackgroundTransparency = 1, Parent = body })
	local barHolder = Ui.new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, Parent = body })

	local quick: { any }? = nil
	local campaign: { any }? = nil
	local show: (string) -> ()

	-- Starts a race and swaps the menu for the race screen; back here after it.
	local busy = false
	local function start(mode: string, which: any)
		if busy then
			return
		end
		local car = myCar()
		if not car then
			ctx.toast("You need a car to race")
			return
		end
		busy = true
		local ok, res = Remote.race("start", { mode = mode, which = which })
		busy = false
		if not ok then
			return
		end
		lastTab = tab
		ctx.close()
		DragStrip.run(ctx, res, { model = car.model, color = car.color }, function()
			ctx.open("race", lastTab)
		end)
	end

	-- ── The bar: the car you race with ────────────────────────────────────────────────────────
	local function drawBar()
		barHolder:ClearAllChildren()
		local s = store.useGame.getState()
		local car = myCar()
		if not car then
			Ui.text({ Text = "Buy a car in the Showroom to race", Body = true, TextSize = 18, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.MUTED, Parent = barHolder })
			return
		end
		local def = data.carDef(car.model)
		local _, face = Ui.shadowed({ Size = UDim2.new(1, 0, 1, -4), Position = UDim2.fromOffset(0, 4), Parent = barHolder }, { radius = 16, stroke = 2.5, drop = 3, colors = "navy", class = "TextButton" })
		local pic = Thumb.new("Cars", car.model, UDim2.fromOffset(84, 64), Color3.fromHex(car.color))
		pic.Position = UDim2.fromOffset(8, 2)
		pic.Parent = face
		Ui.text({ Text = "🏁 Racing with", Body = true, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(100, 8), Size = UDim2.fromOffset(300, 16), TextColor3 = Color3.fromHex("#cfe0ff"), Parent = face })
		Ui.text({ Text = def.name, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(100, 24), Size = UDim2.fromOffset(330, 26), Shadow = 2, Parent = face })
		local skill = if def.skill and data.SKILLS[def.skill] then `  {data.SKILLS[def.skill].icon} {data.SKILLS[def.skill].name}` else ""
		Ui.text({ Text = `PI {raceCar.carPi(car)}{skill}`, Body = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(100, 50), Size = UDim2.fromOffset(330, 16), TextColor3 = Color3.fromHex("#ffd54f"), Parent = face })
		if #s.cars > 1 then
			Ui.text({ Text = "Change ›", Body = true, TextSize = 15, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(100, 24), TextXAlignment = Enum.TextXAlignment.Right, Parent = face })
			-- Each tap moves to the next car down by PI, round to the quickest again.
			face.Activated:Connect(function()
				local list = table.clone(s.cars)
				table.sort(list, function(a, b)
					return raceCar.carPi(a) > raceCar.carPi(b)
				end)
				local at = 1
				for i, c in list do
					if c.uid == car.uid then
						at = i
					end
				end
				local nextCar = list[at % #list + 1]
				if Remote.act("setRaceCar", nextCar.uid) then
					drawBar()
					-- The rivals are matched to the car, and the server deals new ones for it.
					local ok, rivals = Remote.race("rivals", nil, true)
					quick = if ok then rivals else nil
					show(tab)
				end
			end)
		end
	end

	-- ── Front page ────────────────────────────────────────────────────────────────────────────
	local function hub(page: Frame)
		local list = campaign
		local s = store.useGame.getState()
		-- The chapter to show: the first open one not cleared yet, and its next race.
		local ci, nextRace = 1, nil
		local total, got = 0, 0
		if list then
			for i, ch in list do
				for _, r in ch.races do
					total += 3
					got += r.stars
				end
				if ch.open then
					ci = i
				end
			end
			for i, ch in list do
				if ch.open and not ch.cleared then
					ci = i
					break
				end
			end
			for i, r in list[ci].races do
				if r.open and r.stars == 0 then
					nextRace = i
					break
				end
			end
		end
		local _, camp = tile(page, { Size = UDim2.new(0.62, -6, 1, 0) }, "#ff8a3d", "#c2410c")
		camp.Activated:Connect(function()
			show("campaign")
		end)
		tag(camp, "CAMPAIGN")
		if list then
			local ch = list[ci]
			local v = venues.venue(ch.venue)
			Ui.text({ Text = v.icon or "🏁", TextSize = 120, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -20, 0, 10), Size = UDim2.fromOffset(160, 150), TextTransparency = 0.1, Parent = camp })
			Ui.text({ Text = ch.name, TextSize = 36, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 44), Size = UDim2.new(1, -28, 0, 44), Stroke = 3, Shadow = 3, Parent = camp })
			Ui.text({ Text = `Chapter {ci} of {#list} · ⭐ {got}/{total}`, Body = true, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 92), Size = UDim2.new(1, -28, 0, 22), Parent = camp })
			local barBg = Ui.new("Frame", { Position = UDim2.fromOffset(14, 122), Size = UDim2.new(1, -200, 0, 12), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.6, Parent = camp }, { Ui.round() })
			Ui.new("Frame", { Size = UDim2.fromScale(if total > 0 then got / total else 0, 1), BackgroundColor3 = Color3.fromHex("#ffd54f"), Parent = barBg }, { Ui.round() })
			if nextRace then
				local rv = ch.races[nextRace].rival
				-- The next rival's car, big in the middle of the tile.
				local pic = Thumb.new("Cars", rv.model, UDim2.new(1, -28, 1, -240), Color3.fromHex(rv.color))
				pic.Position = UDim2.fromOffset(14, 170)
				pic.Parent = camp
				local foot = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -28, 0, 50), BackgroundTransparency = 1, Parent = camp })
				Ui.text({ Text = `Next: {rv.name}{if rv.boss then " 👑" else ""}`, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -200, 1, 0), Stroke = 2, Shadow = 2, Parent = foot })
				raceButton(foot, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(190, 46) }, rv.prize, function()
					start("campaign", { chapter = ci - 1, race = nextRace :: number - 1 })
				end)
			end
		else
			Ui.text({ Text = "Loading...", Body = true, TextSize = 18, Position = UDim2.fromOffset(14, 50), Size = UDim2.fromOffset(200, 24), TextXAlignment = Enum.TextXAlignment.Left, Parent = camp })
		end

		local right = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.38, -6, 1, 0), BackgroundTransparency = 1, Parent = page }, {
			Ui.new("UIListLayout", { Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local _, q = tile(right, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0.5, -6) }, "#5aa9ff", "#2263d6")
		q.Activated:Connect(function()
			show("quick")
		end)
		tag(q, "QUICK RACE")
		Ui.text({ Text = "🏁", TextSize = 64, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 6), Size = UDim2.fromOffset(80, 80), Parent = q })
		Ui.text({ Text = "Quick race", TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 44), Size = UDim2.new(1, -100, 0, 36), Stroke = 3, Shadow = 3, Parent = q })
		Ui.text({ Text = "Pick a rival", Body = true, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 84), Size = UDim2.new(1, -100, 0, 22), Parent = q })
		local _, tr = tile(right, { LayoutOrder = 2, Size = UDim2.new(1, 0, 0.5, -6) }, "#ffd84a", "#f0a400", true)
		tag(tr, "TROPHIES")
		Ui.text({ Text = "🏆", TextSize = 64, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 6), Size = UDim2.fromOffset(80, 80), Parent = tr })
		Ui.text({ Text = Ui.commas(s.trophies or 0), TextSize = 34, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 44), Size = UDim2.new(1, -100, 0, 40), Stroke = 3, Shadow = 3, Parent = tr })
		Ui.text({ Text = "Win races to earn more", Body = true, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 88), Size = UDim2.new(1, -100, 0, 22), TextColor3 = DARK, Parent = tr })
	end

	-- ── Quick Race: three rivals ──────────────────────────────────────────────────────────────
	local function quickPage(page: Frame)
		if not quick then
			Ui.text({ Text = "Finding rivals...", Body = true, TextSize = 20, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.MUTED, Parent = page })
			return
		end
		local car = myCar()
		local myPi = if car then raceCar.carPi(car) else 0
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 12), HorizontalFlex = Enum.UIFlexAlignment.Fill, Parent = page })
		for i, rv in quick do
			local _, card = tile(page, { LayoutOrder = i, Size = UDim2.new(0, 100, 1, 0) }, "#34507f", "#1f3358", true)
			local pic = Thumb.new("Cars", rv.model, UDim2.new(1, -20, 0, 150), Color3.fromHex(rv.color))
			pic.Position = UDim2.fromOffset(10, 30)
			pic.Parent = card
			Ui.text({ Text = rv.name, TextSize = 24, Position = UDim2.fromOffset(10, 186), Size = UDim2.new(1, -20, 0, 30), Stroke = 2.5, Shadow = 2, TextScaled = true, Parent = card })
			Ui.text({ Text = rv.carName, Body = true, TextSize = 15, Position = UDim2.fromOffset(10, 218), Size = UDim2.new(1, -20, 0, 20), TextColor3 = Color3.fromHex("#cfe0ff"), Parent = card })
			local skill = if rv.skill and data.SKILLS[rv.skill] then `  {data.SKILLS[rv.skill].icon}` else ""
			Ui.text({ Text = `PI {rv.pi}{skill}`, TextSize = 18, Position = UDim2.fromOffset(10, 242), Size = UDim2.new(1, -20, 0, 24), TextColor3 = if rv.pi > myPi then Color3.fromHex("#ff8a80") else Color3.fromHex("#ffd54f"), Parent = card })
			raceButton(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -24, 0, 48) }, rv.prize, function()
				start("quick", i)
			end)
		end
	end

	-- ── Campaign: chapters along the top, the picked one's five races ─────────────────────────
	local function campaignPage(page: Frame)
		local list = campaign
		if not list then
			Ui.text({ Text = "Loading...", Body = true, TextSize = 20, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.MUTED, Parent = page })
			return
		end
		local sel: number = lastChapter or 0
		if not list[sel] then
			sel = 1
			for i, ch in list do
				if ch.open then
					sel = i
				end
			end
			for i, ch in list do
				if ch.open and not ch.cleared then
					sel = i
					break
				end
			end
		end
		local nodes = Ui.scroller({ Size = UDim2.new(1, 0, 0, 66), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), Parent = page })
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = nodes })
		for i, ch in list do
			local n = 0
			for _, r in ch.races do
				n += r.stars
			end
			local v = venues.venue(ch.venue)
			local _, face = Ui.button({ LayoutOrder = i, Size = UDim2.fromOffset(58, 58) }, if i == sel then "tab" elseif ch.open then "white" else "grey", function()
				lastChapter = i
				show("campaign")
			end, { radius = 14, drop = 3, flat = true })
			;(face.Parent :: Instance).Parent = nodes
			Ui.text({ Text = if ch.open then (v.icon or "🏁") else "🔒", TextSize = 24, Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 30), Parent = face })
			Ui.text({ Text = `★{if ch.open then n else ch.starsNeed}`, TextSize = 13, Position = UDim2.fromOffset(0, 34), Size = UDim2.new(1, 0, 0, 16), TextColor3 = DARK, Parent = face })
		end
		local ch = list[sel]
		local v = venues.venue(ch.venue)
		local left = Ui.new("Frame", { Position = UDim2.fromOffset(0, 76), Size = UDim2.new(0.38, -6, 1, -76), BackgroundTransparency = 1, Parent = page })
		local _, banner = tile(left, { Size = UDim2.fromScale(1, 1) }, "#ff8a3d", "#c2410c", true)
		Ui.text({ Text = `Chapter {sel} · {v.name}`, Body = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 18), Parent = banner })
		Ui.text({ Text = ch.name, TextSize = 30, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(14, 34), Size = UDim2.new(1, -28, 0, 72), TextYAlignment = Enum.TextYAlignment.Top, Stroke = 3, Shadow = 3, Parent = banner })
		Ui.text({ Text = v.icon or "🏁", TextSize = 90, Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 110), Parent = banner })
		Ui.text({ Text = `{if ch.cleared then "✔" else "🏁"} {money(ch.coins)}  💎{ch.bucks}  🏆{ch.trophies}`, Body = true, TextSize = 15, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -40), Size = UDim2.new(1, -28, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, Parent = banner })
		Ui.text({ Text = `★★★ every race: 💎{ch.starBucks}`, Body = true, TextSize = 15, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -14), Size = UDim2.new(1, -28, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, Parent = banner })

		local rows = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 76), Size = UDim2.new(0.62, -6, 1, -76), BackgroundTransparency = 1, Parent = page }, {
			Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		if not ch.open then
			Ui.text({ Text = `🔒 Get ★{ch.starsNeed} in the chapters before to open {ch.name}`, Body = true, TextSize = 18, TextWrapped = true, Size = UDim2.new(1, 0, 0, 80), TextColor3 = Ui.MUTED, Parent = rows })
			return
		end
		local car = myCar()
		local myPi = if car then raceCar.carPi(car) else 0
		for i, r in ch.races do
			local rv = r.rival
			local nextOne = r.open and r.stars == 0
			local row = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.new(1, 0, 0.2, -7), BackgroundColor3 = if nextOne then Color3.fromHex("#fff8e1") else Ui.WHITE, BackgroundTransparency = if r.open then 0 else 0.4, Parent = rows }, { Ui.corner(14), Ui.stroke(2, if nextOne then Color3.fromHex("#ffb300") else Ui.EDGE) })
			Ui.text({ Text = if rv.boss then "👑" else tostring(i), TextSize = 22, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 34, 1, 0), TextColor3 = DARK, Parent = row })
			local pic = Thumb.new("Cars", rv.model, UDim2.new(0, 70, 1, -6), Color3.fromHex(rv.color))
			pic.Position = UDim2.fromOffset(40, 3)
			pic.Parent = row
			Ui.text({ Text = rv.name, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 116, 0, 4), Size = UDim2.new(1, -330, 0.5, 0), TextColor3 = Ui.INK, Parent = row })
			local skill = if rv.skill and data.SKILLS[rv.skill] then ` {data.SKILLS[rv.skill].icon}` else ""
			Ui.text({ Text = `{stars(r.stars)}   PI {rv.pi}{skill}`, Body = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 116, 0.5, -2), Size = UDim2.new(1, -330, 0.5, 0), TextColor3 = if rv.pi > myPi then Color3.fromHex("#c62828") else Ui.MUTED, Parent = row })
			if r.open then
				raceButton(row, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(190, 44) }, rv.prize, function()
					start("campaign", { chapter = sel - 1, race = i - 1 })
				end, if r.stars > 0 then "garage" else "green")
			else
				Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(190, 44), Parent = row }, "🔒", "grey")
			end
		end
	end

	show = function(which: string)
		tab = which
		lastTab = which
		if title then
			Ui.setText(title, TITLES[which] or "Race")
		end
		content:ClearAllChildren()
		local page = Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = content })
		if which ~= "hub" then
			-- Back to the front page.
			local back = Ui.buy({ AnchorPoint = Vector2.new(0, 0), Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(96, 34), Parent = content }, "‹ Back", "garage", function()
				show("hub")
			end, 15)
			local _ = back
			page.Position = UDim2.fromOffset(0, 44)
			page.Size = UDim2.new(1, 0, 1, -44)
		end
		if which == "quick" then
			quickPage(page)
		elseif which == "campaign" then
			campaignPage(page)
		else
			hub(page)
		end
	end

	drawBar()
	show(tab)
	-- The rivals and chapters, from the server.
	task.spawn(function()
		local ok, list = Remote.race("campaign", nil, true)
		if ok and overlay.Parent then
			campaign = list
			if tab ~= "quick" then
				show(tab)
			end
		end
	end)
	task.spawn(function()
		local ok, list = Remote.race("rivals", nil, true)
		if ok and overlay.Parent then
			quick = list
			if tab == "quick" then
				show(tab)
			end
		end
	end)
	-- A new car, or another one picked, redraws the bar.
	local function barKey(): string
		local s = store.useGame.getState()
		local car = myCar()
		return `{#s.cars}|{if car then car.uid .. raceCar.carPi(car) .. car.color else ""}`
	end
	local shown = barKey()
	local conn = Remote.changed:Connect(function()
		local key = barKey()
		if overlay.Parent and key ~= shown then
			shown = key
			drawBar()
		end
	end)
	overlay.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return overlay
end

return RaceMenu
