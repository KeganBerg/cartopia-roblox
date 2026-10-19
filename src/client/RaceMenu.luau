--!strict
-- The Race menu, as the web game's RacePanel (ui/Race.tsx, RaceHub.tsx): a front page with the
-- Campaign tile (its next race one tap away) and Quick Race; Quick Race's three rival cards; the
-- Campaign's chapters, each with its five races and stars; the paint rivals (PaintRivals.tsx),
-- each racing for their colour; and the rival in town on the front page (Rivals.tsx RivalTile),
-- with double or nothing after a win. Along the bottom, the car you race with (tap to change it).
-- The rivals and prizes come from the server (server/Races), which also starts the race and pays
-- it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local venues = require(Game.scene_venues) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Motion = require(script.Parent.Motion)
local Thumb = require(script.Parent.Thumb)
local CallCardArt = require(script.Parent.CallCardArt)
local callCards = require(Game.callCards) :: any
local DragStrip = require(script.Parent.DragStrip)
local KartRun = require(script.Parent.KartRun)
local RepChip = require(script.Parent.RepChip)
local Mastery = require(script.Parent.Mastery)
local tour = require(Game.tour) :: any
local events = require(Game.events) :: any
local trial = require(Game.trial) :: any
local rivals = require(Game.rivals) :: any
local distance = require(Game.distance) :: any
local fairRace = require(Game.fairRace) :: any
local paintRivals = require(Game.paintRivals) :: any

local RaceMenu = {}

-- The other race modes' pages (client/RacePages/*.luau), by tab id. Each page module has:
--   id, title          the tab id (also its Race remote mode) and the menu's title on it
--   mini               { icon, label, go? }: the small button on the front page that opens it
--                      (go(ctx, api): what it does instead, e.g. start a race straight away)
--   chip(s)            the words on the menu head's chip on its page
--   draw(page, ctx, api)  draws the page; api has start(mode, which), show(tab), money(n),
--                      myCar(), raceButton(parent, props, prize, onClick, kind?) and tile(...)
--   extras(ctx, which, started, again)  what the mode adds to the race screen (DragStrip.Extras);
--                      again(mode, which) races again
local PAGES: { [string]: any } = {}
do
	local folder = script.Parent:FindFirstChild("RacePages")
	if folder then
		for _, m in folder:GetChildren() do
			if m:IsA("ModuleScript") then
				local page = (require :: any)(m)
				PAGES[page.id] = page
			end
		end
	end
end

local TITLES = { hub = "Race", quick = "Quick Race", campaign = "Campaign", rivals = "Paint Rivals" }
local DARK = Color3.fromHex("#14213d")
local lastTab = "hub"
local lastChapter: number? = nil
-- The paint rival picked on the Rivals page (nil: the easiest one not beaten yet).
local lastRow: string? = nil

local ZERO = { engine = 0, turbo = 0, tires = 0, weight = 0 }

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

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

-- The town rival a card is for (its id is "rival-<id>").
local function townRival(card: any): any?
	for _, d in rivals.RIVALS do
		if card.id == `rival-{d.id}` then
			return d
		end
	end
	return nil
end

local starting = false
local race: (ctx: any, mode: string, which: any, back: string) -> boolean

-- What each kind of race adds to the race screen: the title, the rival's words, and the result
-- card's buttons (Race.tsx: the paint rival's rematch, the town rival's double or nothing).
local function extrasFor(ctx: any, mode: string, which: any, started: any, back: string): any
	local rv = started.rival
	local function again(m: string, w: any): () -> ()
		return function()
			if not race(ctx, m, w, back) then
				ctx.open("race", back)
			end
		end
	end
	if PAGES[mode] and PAGES[mode].extras then
		return PAGES[mode].extras(ctx, which, started, again)
	end
	if mode == "quick" or mode == "next" then
		-- A win brings a faster challenger straight away, a loss the rematch (Race.tsx).
		local chal = rv.id:match("^chal%-(%d+)$")
		return {
			title = if chal then `⚔️ Challenger {tonumber(chal) + 1}` else nil,
			buttons = function(res: any): { DragStrip.Button }?
				local nx = res.next
				if not nx then
					return nil
				end
				local label = if nx.challenger then `⚔️ Challenger · {money(nx.prize)}` else "↻ Rematch"
				local list: { DragStrip.Button } = { { text = "Back", kind = "garage" }, { text = label, go = again("next", nil) } }
				return list
			end,
		}
	elseif mode == "campaign" then
		local chId, i = rv.id:match("^camp%-(.+)%-(%d+)$")
		local ch: any = nil
		for _, c in data.CAMPAIGN do
			if c.id == chId then
				ch = c
			end
		end
		local n = tonumber(i) or 0
		return {
			title = if ch then `{ch.name} · {if n == data.CAMPAIGN_RACES - 1 then "Boss race" else `Race {n + 1} of {data.CAMPAIGN_RACES}`}` else nil,
			buttons = function(res: any): { DragStrip.Button }?
				local nx = res.next
				if not nx then
					return nil
				end
				local label = if nx.retry then "↻ Retry" else `▶ Next · {money(nx.prize)}`
				local list: { DragStrip.Button } = { { text = "Back", kind = "garage" }, { text = label, go = again("campaign", { chapter = nx.chapter, race = nx.race }) } }
				return list
			end,
		}
	elseif mode == "row" then
		local def = paintRivals.paintRival(which)
		return {
			title = rv.name,
			buttons = function(res: any): { DragStrip.Button }?
				local list: { DragStrip.Button } = {}
				if res.paint then
					local car = myCar()
					if car then
						table.insert(list, { text = "🎨 Paint it", go = function()
							ctx.open("garage", { car = car.uid, paint = res.paint })
						end })
					end
				end
				local beaten = res.won or (rv.wins or 0) > 0
				table.insert(list, { text = if beaten then `↻ Rematch {`${Ui.commas(paintRivals.rowPrize(def, false))}`}` else "↻ Retry", kind = "garage", go = again("row", which) })
				table.insert(list, { text = "Back" })
				return list
			end,
		}
	elseif mode == "rival" or mode == "bet" then
		local def = townRival(rv)
		local bet = mode == "bet"
		return {
			title = if bet then `🎲 Double or nothing · ${Ui.commas(started.stake or rv.prize)}` else `{rv.name} · Round {(rv.visit or 0) + 1} of {rivals.RIVAL_VISITS}`,
			heading = function(res: any): string?
				if res.won then
					return if res.bonus then "RIVAL BEATEN!" else nil
				end
				return if bet then "BUSTED!" else "BEATEN!"
			end,
			quote = function(res: any): string?
				if not def then
					return nil
				end
				local l = def.lines
				local said = if bet then (if res.won then l.betLost else l.betWon) elseif res.won then (if res.bonus then l.quit else l.sore) else l.gloat
				if res.bet then
					said ..= `  “{l.bet}”`
				end
				return said
			end,
			buttons = function(res: any): { DragStrip.Button }?
				if res.bet then
					local offer: { DragStrip.Button } = {
						{ text = `Keep ${Ui.commas(res.bet)}`, kind = "garage", go = function()
							Remote.race("keep", nil, true)
							ctx.open("race", back)
						end },
						{ text = "🎲 Double or nothing", go = again("bet", nil) },
					}
					return offer
				elseif not res.won and not bet then
					local retry: { DragStrip.Button } = { { text = "Back", kind = "garage" }, { text = `↻ Rematch ⛽{data.RACE_FUEL}`, go = again("rival", nil) } }
					return retry
				end
				return nil
			end,
		}
	end
	return nil
end

-- Starts a race and swaps whatever is open for the race screen; `back` is the race menu's page to
-- come back to. False when the server didn't start it (no fuel, nothing to race).
race = function(ctx: any, mode: string, which: any, back: string): boolean
	if starting then
		return false
	end
	local car = myCar()
	if not car then
		ctx.toast("You need a car to race")
		return false
	end
	starting = true
	local ok, res = Remote.race("start", { mode = mode, which = which })
	starting = false
	if not ok then
		return false
	end
	ctx.close()
	-- A loaner (the Daily Run) races instead of the player's own car.
	DragStrip.run(ctx, res, res.car or car, function()
		ctx.open("race", back)
	end, extrasFor(ctx, mode, which, res, back))
	return true
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
	-- A new player's first race is on the front page, where the tutorial points.
	local tab = startTab or (if (store.useGame.getState().tutorial or 99) < 99 then "hub" else lastTab)
	local overlay, _sheet, body, headExtras = Ui.panel(ctx.gui, TITLES[tab] or (PAGES[tab] and PAGES[tab].title) or "Race", { wide = true, height = 640, onClose = ctx.close, bodyTop = 6 })
	local title = (overlay:FindFirstChild("Title", true) :: TextLabel?)
	local content = Ui.new("Frame", { Name = "Content", Size = UDim2.new(1, 0, 1, -86), BackgroundTransparency = 1, Parent = body })
	local barHolder = Ui.new("Frame", { Name = "Bar", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, Parent = body })

	local quick: { any }? = nil
	local campaign: { any }? = nil
	local rows: { any }? = nil
	local show: (string) -> ()

	-- Starts a race and swaps the menu for the race screen; back here after it.
	local function start(mode: string, which: any)
		lastTab = tab
		race(ctx, mode, which, tab)
	end
	-- What a page from client/RacePages gets to draw with.
	local api = {
		start = start,
		show = function(which: string)
			show(which)
		end,
		money = money,
		myCar = myCar,
		raceButton = raceButton,
		tile = tile,
		tag = tag,
		stars = stars,
		DARK = DARK,
		-- The menu itself, for a card over it that closes with it.
		sheet = overlay,
		-- Starts a kart race (client/KartRun): "gp" (which: the series), "blast" or "custom" (the pick).
		kart = function(kind: string, which: any)
			lastTab = tab
			KartRun.start(ctx, kind, which, tab)
		end,
	}

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
		local well = Ui.new("Frame", { Position = UDim2.fromOffset(12, 8), Size = UDim2.new(0, 76, 1, -16), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.05, Parent = face }, { Ui.corner(10), Ui.stroke(2, Ui.LINE) })
		local pic = Thumb.new("Cars", car.model, UDim2.fromScale(1, 1), Color3.fromHex(car.color))
		pic.Parent = well
		Ui.text({ Text = "🏁 RACING WITH", Body = true, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(100, 8), Size = UDim2.fromOffset(300, 16), TextColor3 = Color3.fromHex("#ffd54f"), Parent = face })
		-- The car's top mastery medal after its name (ClassCups.tsx MasteryMedal).
		local medal = Mastery.medal(car.model)
		Ui.text({ Text = if medal ~= "" then `{def.name} {medal}` else def.name, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(100, 24), Size = UDim2.fromOffset(330, 26), Shadow = 2, Parent = face })
		local skill = if def.skill and data.SKILLS[def.skill] then `  {data.SKILLS[def.skill].icon} {data.SKILLS[def.skill].name}` else ""
		local piText = `PI {raceCar.carPi(car)}`
		local piChip = Ui.new("Frame", { Position = UDim2.fromOffset(100, 50), Size = UDim2.fromOffset(math.ceil(Ui.textWidth(piText, 13)) + 14, 18), BackgroundColor3 = Color3.fromHex("#ffd54f"), Parent = face }, { Ui.corner(6), Ui.stroke(1.5, Ui.LINE) })
		Ui.text({ Text = piText, TextSize = 13, TextColor3 = Ui.LINE, Size = UDim2.fromScale(1, 1), Parent = piChip })
		Ui.text({ Text = skill, Body = true, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0, 100 + piChip.Size.X.Offset, 0, 50), Size = UDim2.fromOffset(300, 18), TextColor3 = Color3.fromHex("#cfe0ff"), Parent = face })
		if #s.cars > 1 then
			-- Each tap moves to the next car down by PI, round to the quickest again.
			local function nextCar()
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
				local pick = list[at % #list + 1]
				if Remote.act("setRaceCar", pick.uid) then
					drawBar()
					-- The rivals are matched to the car, and the server deals new ones for it.
					local ok, rivals = Remote.race("rivals", nil, true)
					quick = if ok then rivals else nil
					show(tab)
				end
			end
			-- The yellow Change button (.rm-swap).
			local _, swap = Ui.button({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(86, 36), Parent = face }, "edit", nextCar, { radius = 12, stroke = 2.5, drop = 3, text = "Change", textSize = 17, textColor = Ui.LINE })
			local _ = swap
			face.Activated:Connect(nextCar)
		end
	end

	-- ── Front page ────────────────────────────────────────────────────────────────────────────
	-- As the web's RaceHub: Campaign and Pro Tour as tall tiles, the rival in town, the weekly
	-- event, the Grand Prix and the Time Trial beside them, and the other modes as small buttons
	-- underneath. Modes the Roblox game doesn't run yet say so when tapped.
	local function soon(name: string)
		return function()
			ctx.toast(`{name} is coming to Roblox soon`)
		end
	end
	local function hub(page: Frame)
		local list = campaign
		local s = store.useGame.getState()
		local level = store.gateLevel(s)
		local car = myCar()
		local myPi = if car then raceCar.carPi(car) else 10

		-- The grid: columns 1.25fr 1.25fr 1fr 1fr, gaps of 12, the small buttons in two rows below.
		local GAP = 12
		local MINIS_H = 52 * 2 + 10
		local FR = { 1.25, 1.25, 1, 1 }
		local function cell(c1: number, c2: number, r1: number, r2: number, rows: number): UDim2 & any
			local before, span = 0, 0
			for i = 1, c1 - 1 do
				before += FR[i]
			end
			for i = c1, c2 do
				span += FR[i]
			end
			local gaps = GAP * (#FR - 1)
			local x = UDim.new(before / 4.5, -gaps * before / 4.5 + GAP * (c1 - 1))
			local w = UDim.new(span / 4.5, -gaps * span / 4.5 + GAP * (c2 - c1))
			local hTotal = -(MINIS_H + GAP) - GAP * (rows - 1)
			local y = UDim.new((r1 - 1) / rows, hTotal * (r1 - 1) / rows + GAP * (r1 - 1))
			local h = UDim.new((r2 - r1 + 1) / rows, hTotal * (r2 - r1 + 1) / rows + GAP * (r2 - r1))
			return { pos = UDim2.new(x, y), size = UDim2.new(w, h) }
		end

		-- A tile: navy outline, a gloss along the top, and its picture under the words.
		local function hubTile(at: any, name: string, onClick: (() -> ())?): any
			local shadow, face = Ui.shadowed({ Name = name, Position = at.pos, Size = at.size, Parent = page }, { radius = 18, stroke = 3, drop = 4, dark = 0.35, class = "TextButton", color = Ui.WHITE })
			face.ClipsDescendants = true
			if onClick then
				face.Activated:Connect(onClick)
			end
			local _ = shadow
			return face
		end
		local function gloss(face: GuiObject)
			Ui.new("Frame", { Name = "Gloss", BorderSizePixel = 0, BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.7, Position = UDim2.fromOffset(10, 1), Size = UDim2.new(1, -20, 0, 3), ZIndex = 3, Parent = face }, { Ui.round() })
		end
		-- The mode's name on a coloured tab in the corner (.rm-tag).
		local function hubTag(face: GuiObject, text: string, color: string, inset: boolean?)
			local w = math.ceil(Ui.textWidth(text, 15)) + 22
			local f = Ui.new("Frame", { Name = "Tag", Position = if inset then UDim2.fromOffset(0, 0) else UDim2.fromOffset(-3, -3), Size = UDim2.fromOffset(w, 30), BackgroundColor3 = Color3.fromHex(color), ZIndex = 4, Parent = face }, { Ui.corner(10), Ui.stroke(2.5, Ui.LINE) })
			Ui.text({ Text = text, TextSize = 15, Size = UDim2.fromScale(1, 1), Stroke = 2, Shadow = 2, ZIndex = 4, Parent = f })
		end
		-- A dark chip of small text (.rm-meta).
		local function chip(parent: Instance, text: string, props: { [string]: any })
			local w = math.ceil(Ui.textWidth(text, 13) * 1.02) + 18
			local f = Ui.new("Frame", { Size = UDim2.fromOffset(w, 26), BackgroundColor3 = Color3.fromHex("#14213d"), BackgroundTransparency = 0.25, ZIndex = 4, Parent = parent }, { Ui.corner(9), Ui.stroke(1.5, Color3.fromHex("#6c7fa3"), 0.3) })
			for k, v in props do
				(f :: any)[k] = v
			end
			Ui.text({ Text = text, Body = true, TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = f })
			return f
		end
		local function title(face: GuiObject, text: string, bottom: number, size: number?)
			return Ui.text({ Text = text, TextSize = size or 24, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Bottom, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -bottom), Size = UDim2.new(1, -24, 0, 60), Stroke = 2.5, Shadow = 3, ZIndex = 4, Parent = face })
		end
		-- The tiles' pictures move, as the web's race clips play behind its tiles (TileClip): the
		-- road streams away under the cars, the start lights count down to green and the gantry
		-- falls behind, the finish banner sways, the Grand Prix car weaves through the bends.
		-- Each tile adds a step here, and one loop runs them while the front page shows.
		local steps: { (number, number) -> () } = {}
		local LIGHT_OFF = Color3.fromHex("#3a3a3a")
		local RED, AMBER, GREEN = Color3.fromHex("#e53935"), Color3.fromHex("#ffb300"), Color3.fromHex("#43e047")
		-- The picture: sky, the road and the cars on it, darker toward the bottom for the words.
		-- o.move: "start" (Campaign), "finish" (Pro Tour), "weave" (Grand Prix) or "cruise".
		local function scene(face: GuiObject, o: { [string]: any })
			local night = o.night == true
			local horizon = o.horizon or 0.6
			local sky = Ui.new("Frame", { Name = "Sky", BorderSizePixel = 0, Size = UDim2.fromScale(1, horizon), BackgroundColor3 = Ui.WHITE, Parent = face })
			Ui.gradient(if night then "#121a3a" else (o.skyTop or "#8ec9ff"), if night then "#3b3f7a" else (o.skyBottom or "#e6f4ff")).Parent = sky
			local ground = Ui.new("Frame", { Name = "Ground", BorderSizePixel = 0, Position = UDim2.fromScale(0, horizon), Size = UDim2.fromScale(1, 1 - horizon), BackgroundColor3 = Ui.WHITE, ClipsDescendants = true, Parent = face })
			Ui.gradient(o.groundTop or (if night then "#3a4150" else "#7d8691"), o.groundBottom or (if night then "#20252f" else "#4d5560")).Parent = ground
			local move = o.move or "cruise"
			-- Lane lines running toward you; they stream off toward the horizon as you drive.
			local dashes: { Frame } = {}
			if o.road ~= false then
				for _ = 1, 5 do
					table.insert(dashes, Ui.new("Frame", { BorderSizePixel = 0, BackgroundColor3 = Ui.WHITE, AnchorPoint = Vector2.new(0.5, 0.5), Parent = ground }))
				end
			end
			local function road(u0: number)
				for i, d in dashes do
					-- u: 0 at the horizon, 1 at the bottom edge; nearer lines are longer and wider.
					local u = 1 - ((i - 1) / #dashes + u0) % 1
					local k = u * u
					d.Position = UDim2.fromScale(0.5, 0.02 + k * 1.05)
					d.Size = UDim2.new(0, 2 + u * 6, 0.03 + k * 0.2, 0)
					d.BackgroundTransparency = 0.25 + (1 - u) * 0.5
				end
			end
			road(0.15)
			local lights: { Frame } = {}
			local bar: Frame? = nil
			local banner: Frame? = nil
			if o.banner == "lights" then
				bar = Ui.new("Frame", { Name = "Lights", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(84, 26), BackgroundColor3 = Color3.fromHex("#1a1a1a"), Parent = face }, { Ui.corner(4) })
				for i, c in { "#e53935", "#e53935", "#ffb300" } do
					table.insert(lights, Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new((i - 0.5) / 3, 0, 0.5, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromHex(c), Parent = bar }, { Ui.round() }))
				end
			elseif o.banner == "finish" then
				banner = Ui.new("Frame", { Name = "Finish", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 44), Size = UDim2.new(1.1, 0, 0, 28), BackgroundColor3 = Color3.fromHex("#7a2e2a"), BorderSizePixel = 0, Parent = face })
				Ui.text({ Text = "FINISH", TextSize = 22, Size = UDim2.fromScale(1, 1), TextColor3 = Color3.fromHex("#f5e9d7"), Parent = banner })
				for i = 0, 27 do
					Ui.new("Frame", { BorderSizePixel = 0, BackgroundColor3 = if i % 2 == 0 then Ui.WHITE else Ui.BLACK, Position = UDim2.new(i / 28, 0, 1, 0), Size = UDim2.new(1 / 28, 1, 0, 6), Parent = banner })
				end
			end
			local cars = o.cars or {}
			local pics: { { pic: ViewportFrame, at: UDim2 } } = {}
			for i, c in cars do
				local n = #cars
				local w = if n == 1 then 0.62 else 0.48
				local pic = Thumb.new("Cars", c.model, UDim2.fromScale(w, o.carsH or 0.42), Color3.fromHex(c.color))
				pic.AnchorPoint = Vector2.new(0.5, 1)
				pic.Position = UDim2.fromScale(if n == 1 then 0.5 else (i - 0.5) / n, o.carsAt or 0.8)
				pic.ZIndex = 2
				pic.Parent = face
				table.insert(pics, { pic = pic, at = pic.Position })
			end
			local shade = Ui.new("Frame", { Name = "Shade", BorderSizePixel = 0, BackgroundColor3 = Ui.BLACK, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = face })
			Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 0.35) }), Parent = shade })
			gloss(face)

			-- Each tile starts at its own point in the loop, so they don't all move in step.
			local offset = 1.2 + #steps * 1.3
			local barScale = if bar then Motion.scaleOf(bar) else nil
			local roadAt = 0
			table.insert(steps, function(t: number, dt: number)
				local tt = t + offset
				local speed = 0.55
				if move == "start" then
					-- 5 seconds: red, red, amber, then green; the cars launch and the gantry falls behind.
					local ph = tt % 5
					local go = ph >= 1.5
					local lit = if ph < 0.5 then 1 elseif ph < 1 then 2 elseif ph < 1.5 then 3 else 0
					for i, l in lights do
						l.BackgroundColor3 = if go then GREEN elseif i <= lit then (if i == 3 then AMBER else RED) else LIGHT_OFF
					end
					local g = if go then math.min(1, (ph - 1.5) / 3) else 0
					local e = 1 - (1 - g) ^ 2
					if bar and barScale then
						barScale.Scale = 1 - e * 0.7
						bar.Position = UDim2.new(0.5, 0, horizon * e * 0.92, 52 * (1 - e))
						bar.Visible = g < 1
					end
					speed = if go then 0.25 + e * 0.9 else 0
				elseif move == "finish" and banner then
					-- The banner flaps in the wind.
					banner.Rotation = math.sin(tt * 1.7) * 1.6
					banner.Position = UDim2.new(0.5, 0, 0, 44 + math.sin(tt * 2.3) * 2)
					speed = 0.8
				elseif move == "weave" then
					speed = 0
				end
				roadAt = (roadAt + speed * dt) % 1
				road(roadAt)
				-- The cars: an engine's rumble, a racer edging ahead and back, a weave through bends.
				for i, p in pics do
					local x, y, r = 0, math.sin(tt * 19 + i * 2) * 0.8, 0
					if move == "finish" or (move == "start" and #pics > 1) then
						y += math.sin(tt * 0.9 + i * math.pi) * 3
					elseif move == "weave" then
						x = math.sin(tt * 1.1) * 10
						r = math.cos(tt * 1.1) * 5
					else
						y += math.sin(tt * 1.4 + i) * 1.5
					end
					p.pic.Position = p.at + UDim2.fromOffset(x, y)
					p.pic.Rotation = r
				end
			end)
		end
		local function money2(n: number): string
			return money(n)
		end
		local function goButton(parent: Instance, props: { [string]: any }, text: string, onClick: (() -> ())?, kind: string?)
			props.Parent = parent
			props.ZIndex = 5
			local shadow, face = Ui.buy(props, text, kind or "green", onClick, 16)
			for _, d in shadow:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 5
				end
			end
			local _ = face
			return shadow
		end

		-- Campaign: the chapter to play and its next race, one tap away.
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
		local camp = hubTile(cell(1, 1, 1, 3, 3), "Campaign", function()
			show("campaign")
		end)
		do
			local rv = if list and nextRace then list[ci].races[nextRace].rival else nil
			local mine = if car then { model = car.model, color = car.color } else nil
			local cars = {}
			if mine then
				table.insert(cars, mine)
			end
			if rv then
				table.insert(cars, { model = rv.model, color = rv.color })
			end
			scene(camp, { banner = "lights", move = "start", cars = cars, carsAt = 0.62, carsH = 0.26, horizon = 0.42 })
			hubTag(camp, "CAMPAIGN", "#ffb21a")
		end
		if list then
			local ch = list[ci]
			local foot = if nextRace then 52 else 12
			title(camp, ch.name, foot + 54, 26)
			chip(camp, `Chapter {ci} of {#list} · ⭐ {got}/{total}`, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -(foot + 22)) })
			local barBg = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -(foot + 6)), Size = UDim2.new(1, -24, 0, 9), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.7, ZIndex = 4, Parent = camp }, { Ui.round(), Ui.stroke(1.5, Ui.LINE) })
			local fill = Ui.new("Frame", { Size = UDim2.fromScale(if total > 0 then got / total else 0, 1), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = barBg }, { Ui.round() })
			Ui.gradient("#ffe066", "#ff9f1a").Parent = fill
			if nextRace then
				local rv = ch.races[nextRace].rival
				local cta = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0, 40), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.04, ZIndex = 4, Parent = camp }, { Ui.corner(12), Ui.stroke(2, Ui.LINE) })
				Ui.text({ Text = `{rv.name}{if rv.boss then " 👑" else ""}`, Body = true, TextSize = 13, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(9, 0), Size = UDim2.new(1, -110, 1, 0), ZIndex = 4, Parent = cta })
				local go = goButton(cta, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -3, 0.5, 0), Size = UDim2.fromOffset(96, 32) }, `{money2(rv.prize)} ⛽{data.RACE_FUEL}`, function()
					start("campaign", { chapter = ci - 1, race = nextRace :: number - 1 })
				end)
				-- The tutorial's first race (client/Popups/Tutorial points here, the web's .rm-camp .rm-cta .buy).
				local goFace = go:FindFirstChildWhichIsA("TextButton", true)
				if goFace then
					goFace:SetAttribute("Tut", "camp-go")
				end
			end
		else
			title(camp, "Loading...", 12, 22)
		end

		-- Pro Tour: opens once Back Streets is cleared.
		local won = s.tour or 0
		local leg = tour.tourLeg(tour.tourLegOf(won))
		local tv = venues.venue(leg.venue)
		local tourOpen = list ~= nil and list[1] ~= nil and list[1].cleared == true
		local tourFace = hubTile(cell(2, 2, 1, 3, 3), "Tour", soon("The Pro Tour"))
		scene(tourFace, { banner = "finish", move = "finish", night = leg.night, cars = if car then { { model = car.model, color = car.color }, { model = (if list and list[1] and list[1].races[5] then list[1].races[5].rival.model else car.model), color = "#cfd8dc" } } else {}, carsAt = 0.62, carsH = 0.26, horizon = 0.42 })
		hubTag(tourFace, "PRO TOUR", "#b48cff")
		title(tourFace, if leg.night then `{tv.name} at Midnight` else `{tv.name} {leg.name}`, if tourOpen then 52 else 58, 24)
		if tourOpen then
			chip(tourFace, `Leg {leg.index + 1}{if leg.night then " · 🌙" else ""} · {distance.DIST[distance.tourDist(won)].label}`, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -14) })
		else
			local lock = chip(tourFace, "🔒 Clear Back Streets to open", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12) })
			lock.Size = UDim2.new(1, -24, 0, 40)
			local l = lock:FindFirstChildOfClass("TextLabel") :: TextLabel
			l.TextWrapped = true
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.Position = UDim2.fromOffset(10, 0)
			l.Size = UDim2.new(1, -20, 1, 0)
		end

		-- The rival in town (Rivals.tsx RivalTile).
		local cur = rivals.currentRival(level, s.rivals or {}, now())
		local function openRows()
			show("rivals")
		end
		local rivalFace = hubTile(cell(3, 4, 1, 1, 3), "Rival", openRows)
		do
			local color = if cur then cur.def.color else "#ff7043"
			Ui.gradient(color, color).Parent = rivalFace
			local g = rivalFace:FindFirstChildOfClass("UIGradient") :: UIGradient
			local base = Color3.fromHex(color)
			g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, base:Lerp(Ui.WHITE, 0.35)), ColorSequenceKeypoint.new(0.55, base), ColorSequenceKeypoint.new(1, base:Lerp(Ui.BLACK, 0.2)) })
			g.Rotation = 30
			gloss(rivalFace)
			local idle = cur == nil or cur.locked or (cur.away or 0) > 0
			local face = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(60, 60), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.15, ZIndex = 4, Parent = rivalFace }, { Ui.round(), Ui.stroke(3, Ui.LINE) })
			Ui.text({ Text = if cur == nil then "🏆" elseif cur.locked then "❔" else cur.def.icon, TextSize = 34, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = face })
			local mid = Ui.new("Frame", { Position = UDim2.fromOffset(84, 0), Size = UDim2.new(1, -84 - 112, 1, 0), BackgroundTransparency = 1, ZIndex = 4, Parent = rivalFace })
			local tagText = if cur == nil then "RIVALS" elseif cur.locked then "RIVAL" elseif (cur.away or 0) > 0 then "RIVAL AWAY" else "RIVAL IN TOWN"
			local tw = math.ceil(Ui.textWidth(tagText, 13)) + 18
			local t = Ui.new("Frame", { Position = UDim2.new(0.5, -tw / 2, 0, 8), Size = UDim2.fromOffset(tw, 22), BackgroundColor3 = Color3.fromHex("#c62828"), ZIndex = 4, Parent = mid }, { Ui.corner(8), Ui.stroke(2, Ui.LINE) })
			Ui.text({ Text = tagText, TextSize = 13, Size = UDim2.fromScale(1, 1), Stroke = 1.5, ZIndex = 4, Parent = t })
			local name = if cur == nil then "Town champ!" elseif cur.locked then "???" else cur.def.name
			Ui.text({ Text = name, TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 26), Stroke = 2.5, Shadow = 2, ZIndex = 4, Parent = mid })
			if cur and not cur.locked then
				Ui.text({ Text = string.rep("●", cur.visit) .. string.rep("○", rivals.RIVAL_VISITS - cur.visit), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 12), TextColor3 = Ui.WHITE, ZIndex = 4, Parent = mid })
			end
			local line = if cur == nil then "Every rival beaten." elseif cur.locked then `Rolls into town at level {rivals.RIVAL_LEVEL}.` elseif (cur.away or 0) > 0 then `Tuning up. Back in {math.max(0, math.ceil((cur.away - now()) / 60000))}m.` elseif cur.visit == 0 then cur.def.lines.intro else cur.def.lines.back[cur.visit]
			local bub = Ui.new("Frame", { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = mid }, { Ui.corner(10), Ui.stroke(2, Ui.LINE) })
			Ui.text({ Text = line, Body = true, TextSize = 12, TextColor3 = Ui.INK, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), ZIndex = 4, Parent = bub })
			-- The paint rivals' colours, the ones won so far lit (.rm-paints).
			local strip = Ui.new("Frame", { Name = "Paints", Position = UDim2.fromOffset(0, 100), Size = UDim2.new(1, 0, 0, 10), BackgroundTransparency = 1, ZIndex = 4, Parent = mid }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 2) }),
			})
			for _, r in paintRivals.PAINT_RIVALS do
				local got = ((s.rivalRow or {})[r.id] or 0) > 0
				Ui.new("Frame", { Size = UDim2.fromOffset(6, 10), BackgroundColor3 = Color3.fromHex(r.paint), BackgroundTransparency = if got then 0 else 0.7, ZIndex = 4, Parent = strip }, { Ui.corner(3) })
			end
			local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(96, 52) }
			if cur and cur.locked then
				goButton(rivalFace, at, `🔒 Lv{rivals.RIVAL_LEVEL}`, function()
					ctx.toast(`{cur.def.name} comes to town at level {rivals.RIVAL_LEVEL}`)
				end, "garage")
			elseif cur and (cur.away or 0) > 0 then
				goButton(rivalFace, at, `⏱ {math.max(0, math.ceil((cur.away - now()) / 60000))}m`, nil, "grey")
			elseif cur then
				-- The rival's car is close to your best one (Rivals.tsx rivalMatch).
				local best = 10
				for _, c in s.cars do
					best = math.max(best, raceCar.carPi(c))
				end
				local ladder = rivals.rivalPi(cur.def, cur.visit, best)
				local best, bestD = nil, math.huge
				for _, c in data.CARS do
					local d = math.abs(data.performance(c, ZERO) - ladder)
					if d < bestD then
						best, bestD = c, d
					end
				end
				local idx = table.find(rivals.RIVALS, cur.def) or 1
				local skill = if best and (idx - 1 >= 2 or cur.visit == rivals.RIVAL_VISITS - 1) then best.skill else nil
				local pi = fairRace.fairNow(ladder, rivals.rivalShift(cur.def, cur.visit), skill)
				local go = goButton(rivalFace, at, `🏁 {money(rivals.rivalPrize(pi))}\n⛽{data.RACE_FUEL}`, function()
					start("rival", nil)
				end)
				-- The rival's in town: the race button throbs to be tapped (.rm-go.rm-alert).
				local throb = Motion.scaleOf(go)
				table.insert(steps, function(t: number)
					throb.Scale = 1 + (1 - math.cos(t * math.pi * 2 / 1.6)) * 0.025
				end)
			else
				goButton(rivalFace, at, "🎨", openRows, "garage")
			end
			if idle then
				rivalFace.BackgroundTransparency = 0
			end
		end

		-- The weekly event.
		local ev = events.eventFor()
		local evp = events.eventProgress(s.event)
		local evWon = if evp then evp.won or 0 else 0
		local evBase = if evp and evp.pi then evp.pi else myPi
		local evFace = hubTile(cell(3, 4, 2, 2, 3), "Event", soon("Weekly events"))
		scene(evFace, { night = ev.night, horizon = 0.55, skyTop = "#ffb36b", skyBottom = "#ffe0b2", cars = if car then { { model = car.model, color = car.color } } else {}, carsAt = 0.95 })
		do
			local ring = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(60, 60), BackgroundColor3 = Ui.WHITE, ZIndex = 4, Parent = evFace }, { Ui.round(), Ui.stroke(4, Color3.fromHex(ev.color or "#26a69a")) })
			-- The ring glows in the event's colour (.rm-ev-car's ev-glow).
			local glow = ring:FindFirstChildOfClass("UIStroke") :: UIStroke
			table.insert(steps, function(t: number)
				local k = (1 - math.cos(t * math.pi * 2 / 2.4)) / 2
				glow.Thickness = 4 + k * 2.5
				glow.Transparency = k * 0.35
			end)
			local evCar = if car then Thumb.new("Cars", car.model, UDim2.fromScale(1, 1), Color3.fromHex(car.color)) else nil
			if evCar then
				evCar.ZIndex = 4
				evCar.Parent = ring
			end
			local mid = Ui.new("Frame", { Position = UDim2.fromOffset(84, 0), Size = UDim2.new(1, -84 - 112, 1, 0), BackgroundTransparency = 1, ZIndex = 4, Parent = evFace })
			local tagText = "WEEKLY EVENT"
			local tw = math.ceil(Ui.textWidth(tagText, 13)) + 18
			local t = Ui.new("Frame", { Position = UDim2.new(0.5, -tw / 2, 0, 8), Size = UDim2.fromOffset(tw, 22), BackgroundColor3 = Color3.fromHex("#26a69a"), ZIndex = 4, Parent = mid }, { Ui.corner(8), Ui.stroke(2, Ui.LINE) })
			Ui.text({ Text = tagText, TextSize = 13, Size = UDim2.fromScale(1, 1), Stroke = 1.5, ZIndex = 4, Parent = t })
			Ui.text({ Text = ev.name, TextSize = 21, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 26), Stroke = 2.5, Shadow = 2, ZIndex = 4, Parent = mid })
			chip(mid, `{string.rep("●", evWon)}{string.rep("○", events.EVENT_RACES - evWon)}  ⏳ {trial.shortLeft(data.msToNextWeek())}`, { Position = UDim2.fromOffset(0, 64) })
			local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(96, 52) }
			if evWon < events.EVENT_RACES then
				goButton(evFace, at, `🏁 {money(events.eventPrize(evBase, evWon))}\n⛽{data.RACE_FUEL}`, soon("Weekly events"))
			else
				chip(evFace, "✔ Cleared", { AnchorPoint = at.AnchorPoint, Position = at.Position })
			end
		end

		-- The Grand Prix: a series under way, else the newest open one not won yet.
		local gp = s.gp or {}
		local series, si = nil, 0
		for i, sr in data.GP_SERIES do
			if ((gp[sr.id] and gp[sr.id].round) or 0) > 0 and data.gpOpen(gp, i - 1, level) then
				series, si = sr, i - 1
				break
			end
		end
		if not series then
			for i = #data.GP_SERIES, 1, -1 do
				local sr = data.GP_SERIES[i]
				if data.gpOpen(gp, i - 1, level) and #s.cars >= sr.minCars and not (gp[sr.id] and gp[sr.id].clears) then
					series, si = sr, i - 1
					break
				end
			end
		end
		if not series then
			series, si = data.GP_SERIES[1], 0
			for i = #data.GP_SERIES, 1, -1 do
				if data.gpOpen(gp, i - 1, level) then
					series, si = data.GP_SERIES[i], i - 1
					break
				end
			end
		end
		local round = (gp[series.id] and gp[series.id].round) or 0
		local gpFace = hubTile(cell(3, 3, 3, 3, 3), "GrandPrix", function()
			show("gp")
		end)
		scene(gpFace, { horizon = 0.35, groundTop = "#7cc56a", groundBottom = "#4f9a46", road = false, move = "weave", cars = if car then { { model = car.model, color = car.color } } else {}, carsAt = 0.72 })
		hubTag(gpFace, "GRAND PRIX", "#ffd84a")
		title(gpFace, series.name, 40, 19)
		do
			local pips = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0, 22), BackgroundTransparency = 1, ZIndex = 4, Parent = gpFace }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for i = 1, data.GP_ROUNDS do
				local done = i - 1 < round
				local nxt = i - 1 == round
				local p = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(20, 20), BackgroundColor3 = if done then Color3.fromHex("#43a047") elseif nxt then Ui.WHITE else Color3.fromHex("#dfe7f2"), ZIndex = 4, Parent = pips }, { Ui.round(), Ui.stroke(1.5, Ui.LINE) })
				Ui.text({ Text = if done then "✔" else tostring(i), TextSize = 12, TextColor3 = if done then Ui.WHITE else Ui.INK, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = p })
			end
			if not data.gpOpen(gp, si, level) then
				gpFace.BackgroundTransparency = 0
			end
		end

		-- This week's Time Trial.
		local week = trial.trialWeek()
		local tvn = trial.trialVenue(week)
		local trialFace = hubTile(cell(4, 4, 3, 3, 3), "Trial", function()
			show("trial")
		end)
		scene(trialFace, { horizon = 0.4, cars = if car then { { model = car.model, color = car.color } } else {}, carsAt = 0.7 })
		hubTag(trialFace, "TIME TRIAL", "#5ce0d0")
		title(trialFace, tvn.name, 40, 19)
		local chips = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -10), Size = UDim2.new(1, -20, 0, 26), BackgroundTransparency = 1, ZIndex = 4, Parent = trialFace }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local trialBest = PAGES.trial and PAGES.trial.last and PAGES.trial.last.week == week and PAGES.trial.last.board.me
		chip(chips, if trialBest then string.format("⏱️ %.3fs", trialBest.t) else "⏱️ --", { LayoutOrder = 1 })
		chip(chips, `⏳ {trial.shortLeft(data.msToNextWeek())}`, { LayoutOrder = 2 })

		-- The other modes, as the web's small buttons.
		local minis = Ui.new("Frame", { Name = "Minis", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, MINIS_H), BackgroundTransparency = 1, Parent = page }, {
			Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 6, -9, 0, 52), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local MINIS = {
			{ "🏁", "Quick race", function()
				show("quick")
			end },
			{ "🟢", "Live", soon("Live races") },
			{ "💥", "Bumper Blast", soon("Bumper Blast") },
			{ "🛠️", "Custom race", soon("Custom races") },
			{ "🔧", "Tuner Trials", soon("Tuner Trials") },
			{ "🏆", "Class Cups", soon("Class Cups") },
			{ "🛣️", "Trophy Road", soon("The Trophy Road") },
			{ "📅", "Daily Run", soon("The Daily Run") },
			{ "🌍", "World Tour", soon("The World Tour") },
			{ "🎆", "Flair", soon("Flair") },
			{ "👻", "Ghosts", soon("Ghost races") },
			{ "🏅", "Top racers", soon("Top racers") },
		}
		-- A mode with its own page opens it.
		for _, m in MINIS do
			for id, p in PAGES do
				if p.mini and p.mini.label == m[2] then
					local go = p.mini.go
					m[3] = function()
						if go then
							go(ctx, api)
						else
							show(id)
						end
					end
				end
			end
		end
		for i, m in MINIS do
			local shadow, face = Ui.button({ LayoutOrder = i }, "garage", m[3], { radius = 16, stroke = 2.5, drop = 3 })
			shadow.Parent = minis
			local icon = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromHex("#ffcc80"), Parent = face }, { Ui.round(), Ui.stroke(2, Ui.LINE) })
			Ui.text({ Text = m[1], TextSize = 19, Size = UDim2.fromScale(1, 1), Parent = icon })
			Ui.text({ Text = m[2], TextSize = 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LineHeight = 0.9, Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -52, 1, 0), Stroke = 2, Shadow = 1.5, Parent = face })
		end

		Motion.loop(page, function(t: number, dt: number)
			for _, step in steps do
				step(t, dt)
			end
		end)
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
			-- The rival's car standing on their Call Card (Race.tsx CardArt; rivals without one wear
			-- the Showroom in their car's colour), its ground at 56% (.rm-qc.cc-stage).
			CallCardArt.stage(card, rv.callCard, { car = { model = rv.model, color = rv.color }, g = 0.56, carH = 0.52, aspect = 0.62 })
			CallCardArt.frame(card, rv.callCard, 0, 15)
			local def = rv.callCard and callCards.callCardDef(rv.callCard)
			if def and def.tier then
				-- The tier's gem (.rm-cc-gem).
				local gem = Ui.new("Frame", { Name = "Gem", Position = UDim2.fromOffset(7, 7), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = Color3.fromHex("#080e20"), BackgroundTransparency = 0.45, ZIndex = 2, Parent = card }, { Ui.round(), Ui.stroke(2, CallCardArt.EDGE[def.tier]) })
				Ui.text({ Text = def.icon, TextSize = 15, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = gem })
			end
			-- The name plate fading up from the bottom (.rm-qc-body).
			Ui.new("Frame", { Name = "Body", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 176), BackgroundColor3 = Color3.fromHex("#060a1a"), BorderSizePixel = 0, ZIndex = 1, Parent = card }, {
				Ui.corner(15),
				Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.22), NumberSequenceKeypoint.new(1, 0.1) }) }),
			})
			Ui.text({ Text = rv.name, TextSize = 24, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -118), Size = UDim2.new(1, -20, 0, 30), Stroke = 2.5, Shadow = 2, TextScaled = true, ZIndex = 2, Parent = card })
			Ui.text({ Text = rv.carName, Body = true, TextSize = 15, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -96), Size = UDim2.new(1, -20, 0, 20), TextColor3 = Color3.fromHex("#cfe0ff"), ZIndex = 2, Parent = card })
			local skill = if rv.skill and data.SKILLS[rv.skill] then `  {data.SKILLS[rv.skill].icon}` else ""
			Ui.text({ Text = `PI {rv.pi}{skill}`, TextSize = 18, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 10, 1, -70), Size = UDim2.new(1, -20, 0, 24), TextColor3 = if rv.pi > myPi then Color3.fromHex("#ff8a80") else Color3.fromHex("#ffd54f"), ZIndex = 2, Parent = card })
			local shadow = raceButton(card, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(1, -24, 0, 48) }, rv.prize, function()
				start("quick", i)
			end)
			shadow.ZIndex = 2
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

	-- ── Paint rivals: the picked one on a banner, their colour as the prize, the roster ─────────
	local function rowsPage(page: Frame)
		local list = rows
		if not list then
			Ui.text({ Text = "Loading...", Body = true, TextSize = 20, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.MUTED, Parent = page })
			return
		end
		local byId: { [string]: any } = {}
		local nextUp: string? = nil
		for i, card in list do
			local def = paintRivals.PAINT_RIVALS[i]
			byId[def.id] = card
			if not nextUp and (card.wins or 0) == 0 then
				nextUp = def.id
			end
		end
		local sel = if lastRow and byId[lastRow] then lastRow else (nextUp or paintRivals.PAINT_RIVALS[1].id)
		local def = paintRivals.paintRival(sel)
		local card = byId[sel]
		local beaten = (card.wins or 0) > 0
		local v = venues.venue(def.venue)
		local car = myCar()
		local myPi = if car then raceCar.carPi(car) else 0
		local function flames(t: number): string
			return string.rep("🔥", t)
		end
		local paintName = "Paint"
		for _, p in data.PAINTS do
			if p.color == def.paint then
				paintName = p.name
			end
		end

		-- Left: the banner and the prize.
		local left = Ui.new("Frame", { Name = "Picked", Size = UDim2.new(0.42, -6, 1, 0), BackgroundTransparency = 1, Parent = page })
		local base = Color3.fromHex(def.paint)
		local _, banner = tile(left, { Name = "Banner", Size = UDim2.new(1, 0, 0.62, -6) }, if def.night then "#1b2350" else v.sky, if def.night then "#0b1030" else "#14213d", true)
		banner.ClipsDescendants = true
		local pic = Thumb.new("Cars", card.model, UDim2.new(0.62, 0, 0.5, 0), base)
		pic.AnchorPoint = Vector2.new(1, 1)
		pic.Position = UDim2.new(1, -6, 1, -40)
		pic.Parent = banner
		Ui.text({ Text = `{v.icon} {v.name}{if def.night then " · 🌙" else ""} · {distance.DIST[def.dist].label}`, Body = true, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 12), Size = UDim2.new(1, -28, 0, 18), Parent = banner })
		Ui.text({ Text = card.name, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -28, 0, 36), Stroke = 3, Shadow = 3, Parent = banner })
		local bubble = Ui.new("Frame", { Position = UDim2.fromOffset(14, 74), Size = UDim2.new(0.62, 0, 0, 44), BackgroundColor3 = Ui.WHITE, Parent = banner }, { Ui.corner(12), Ui.stroke(2, Ui.LINE) })
		Ui.text({ Text = def.line, Body = true, TextSize = 13, TextWrapped = true, TextColor3 = Ui.INK, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -16, 1, 0), Parent = bubble })
		local chips = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 26), BackgroundTransparency = 1, Parent = banner }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local skill = if card.skill and data.SKILLS[card.skill] then data.SKILLS[card.skill].icon else nil
		for i, text in { flames(def.tier), `PI {def.pi}`, skill or "", if beaten then `✔ ×{card.wins}` else `🏁 {money(card.prize)}` } do
			if text ~= "" then
				local w = math.ceil(Ui.textWidth(text, 13)) + 18
				local c = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(w, 26), BackgroundColor3 = if i == 4 and beaten then Color3.fromHex("#2e7d32") else DARK, BackgroundTransparency = 0.2, Parent = chips }, { Ui.corner(9) })
				Ui.text({ Text = text, Body = true, TextSize = 13, Size = UDim2.fromScale(1, 1), TextColor3 = if i == 2 and def.pi > myPi then Color3.fromHex("#ff8a80") else Ui.WHITE, Parent = c })
			end
		end

		-- The prize: their colour on your car.
		local prize = Ui.new("Frame", { Name = "Prize", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -62), Size = UDim2.new(1, 0, 0.38, -68), BackgroundColor3 = if beaten then Color3.fromHex("#e8f5e9") else Ui.WHITE, Parent = left }, { Ui.corner(16), Ui.stroke(2.5, if beaten then Color3.fromHex("#43a047") else Ui.EDGE) })
		local mine = if car then Thumb.car(car.model, UDim2.new(0.45, 0, 1, -8), { color = def.paint, finish = car.finish, stripe = car.stripe }, nil, car.mods) else Thumb.new("Cars", card.model, UDim2.new(0.45, 0, 1, -8), base)
		mine.Position = UDim2.fromOffset(6, 4)
		mine.Parent = prize
		Ui.text({ Text = if beaten then "✔" else "🔒", TextSize = 18, Position = UDim2.fromOffset(8, 6), Size = UDim2.fromOffset(24, 24), Parent = prize })
		Ui.text({ Text = paintName, TextSize = 22, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(0.47, 0, 0.5, -30), Size = UDim2.new(0.53, -10, 0, 28), Parent = prize })
		local sw = Ui.new("Frame", { Position = UDim2.new(0.47, 0, 0.5, 4), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = base, Parent = prize }, { Ui.round(), Ui.stroke(2, Ui.LINE) })
		Ui.text({ Text = if beaten then "Yours to paint" else "🎨 Win it", Body = true, TextSize = 14, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(1, 8, 0, 0), Size = UDim2.fromOffset(160, 22), Parent = sw })
		raceButton(left, { Name = "Go", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 52) }, card.prize, function()
			start("row", sel)
		end)

		-- Right: every rival as a tile in their colour, a row per tier.
		local right = Ui.new("Frame", { Name = "Roster", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.58, -6, 1, 0), BackgroundTransparency = 1, Parent = page }, {
			Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for tier = 1, 5 do
			local inTier = {}
			for _, r in paintRivals.PAINT_RIVALS do
				if r.tier == tier then
					table.insert(inTier, r)
				end
			end
			local won = 0
			for _, r in inTier do
				if (byId[r.id].wins or 0) > 0 then
					won += 1
				end
			end
			local rowF = Ui.new("Frame", { Name = `Tier{tier}`, LayoutOrder = tier, Size = UDim2.new(1, 0, 0.2, -5), BackgroundTransparency = 1, Parent = right })
			local head = Ui.new("Frame", { Size = UDim2.new(0, 92, 1, 0), BackgroundColor3 = if won == #inTier then Color3.fromHex("#fff3c4") else Color3.fromHex("#eef3f8"), Parent = rowF }, { Ui.corner(12), Ui.stroke(2, Ui.EDGE) })
			Ui.text({ Text = flames(tier), TextSize = 12, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16), Parent = head })
			Ui.text({ Text = paintRivals.TIERS[tier + 1], TextSize = 17, TextColor3 = Ui.INK, Position = UDim2.new(0, 0, 0.5, -10), Size = UDim2.new(1, 0, 0, 20), Parent = head })
			Ui.text({ Text = if won == #inTier then "👑" else `{won}/{#inTier}`, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -6), Size = UDim2.new(1, 0, 0, 16), Parent = head })
			local tiles = Ui.new("Frame", { Position = UDim2.fromOffset(100, 0), Size = UDim2.new(1, -100, 1, 0), BackgroundTransparency = 1, Parent = rowF }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for i, r in inTier do
				local c = byId[r.id]
				local isSel = r.id == sel
				local done = (c.wins or 0) > 0
				local b = Ui.new("TextButton", { Name = r.id, Text = "", AutoButtonColor = false, LayoutOrder = i, Size = UDim2.new(0.25, -5, 1, 0), BackgroundColor3 = Color3.fromHex(r.paint):Lerp(Ui.WHITE, 0.55), Parent = tiles }, {
					Ui.corner(12),
					Ui.stroke(if isSel then 3.5 else 2, if isSel then Color3.fromHex("#1e88e5") elseif r.id == nextUp then Color3.fromHex("#ffb300") else Ui.LINE),
				})
				local t = Thumb.new("Cars", c.model, UDim2.new(1, -8, 0.62, 0), Color3.fromHex(r.paint))
				t.Position = UDim2.fromOffset(4, 2)
				t.Parent = b
				Ui.text({ Text = r.icon, TextSize = 18, Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(24, 24), Parent = b })
				if done then
					local tick = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromHex("#43a047"), Parent = b }, { Ui.round(), Ui.stroke(1.5, Ui.WHITE) })
					Ui.text({ Text = "✔", TextSize = 12, Size = UDim2.fromScale(1, 1), Parent = tick })
				end
				Ui.text({ Text = `PI {r.pi}`, TextSize = 14, TextColor3 = Ui.INK, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 16), Parent = b })
				b.Activated:Connect(function()
					lastRow = r.id
					show("rivals")
				end)
			end
		end
	end

	-- The page last drawn: a new page pops in, a redraw of the same one (fresh data) doesn't.
	local drawn: string? = nil
	show = function(which: string)
		tab = which
		lastTab = which
		if title then
			Ui.setText(title, TITLES[which] or (PAGES[which] and PAGES[which].title) or "Race")
		end
		-- The head's chip: your reputation title on the front page (Race.tsx RepChip).
		local oldChip = headExtras:FindFirstChild("RepChip")
		if oldChip then
			oldChip:Destroy()
		end
		local oldPage = headExtras:FindFirstChild("PageChip")
		if oldPage then
			oldPage:Destroy()
		end
		local oldCard = headExtras:FindFirstChild("MyCard")
		if oldCard then
			oldCard:Destroy()
		end
		if which == "hub" then
			RepChip.draw(headExtras)
		elseif which == "quick" then
			-- Your own Call Card, what other players see behind your car (Race.tsx MyCardChip):
			-- opens the picker.
			local chip = Ui.new("TextButton", { Name = "MyCard", Text = "", AutoButtonColor = false, LayoutOrder = 1, Size = UDim2.fromOffset(64, 30), BackgroundColor3 = Color3.fromHex("#0a1e46"), BackgroundTransparency = 0.65, Parent = headExtras }, {
				Ui.round(),
				Ui.stroke(2, Ui.LINE, 0.45),
			})
			chip.Activated:Connect(function()
				ctx.open("garage", "cards")
			end)
			local swatch = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(34, 24), BackgroundColor3 = Color3.fromHex("#0b1430"), ClipsDescendants = true, Parent = chip }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
			CallCardArt.scene(swatch, store.useGame.getState().callCard, { still = true, aspect = 34 / 24 })
			Ui.text({ Text = "🃏", TextSize = 15, Position = UDim2.fromOffset(40, 0), Size = UDim2.new(1, -42, 1, 0), Parent = chip })
		elseif PAGES[which] and PAGES[which].chip then
			-- A mode's own chip (.rm-head-chip): its progress in a few words.
			local text = PAGES[which].chip(store.useGame.getState())
			local w = math.ceil(Ui.textWidth(text, 13) * 1.05) + 22
			local pc = Ui.new("Frame", { Name = "PageChip", LayoutOrder = 1, Size = UDim2.fromOffset(w, 26), BackgroundColor3 = Color3.fromHex("#0a1e46"), BackgroundTransparency = 0.65, Parent = headExtras }, { Ui.round(), Ui.stroke(2, Ui.LINE, 0.45) })
			Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 13, Size = UDim2.fromScale(1, 1), Shadow = 1, ShadowTransparency = 0.6, ShadowColor = Ui.BLACK, Parent = pc })
		end
		content:ClearAllChildren()
		-- A page with its own car bar (the Daily Run's loaner) hides the usual one.
		local ownBar = PAGES[which] ~= nil and PAGES[which].hideBar == true
		barHolder.Visible = not ownBar
		content.Size = if ownBar then UDim2.fromScale(1, 1) else UDim2.new(1, 0, 1, -86)
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
		if drawn ~= nil and drawn ~= which then
			Motion.pop(page, 0.22, 0.96)
		end
		drawn = which
		if which == "quick" then
			quickPage(page)
		elseif which == "campaign" then
			campaignPage(page)
		elseif which == "rivals" then
			rowsPage(page)
		elseif PAGES[which] then
			PAGES[which].draw(page, ctx, api)
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
		local ok, list = Remote.race("rows", nil, true)
		if ok and overlay.Parent then
			rows = list
			if tab == "rivals" then
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
		return `{#s.cars}|{if car then car.uid .. raceCar.carPi(car) .. car.color .. Mastery.medal(car.model) else ""}`
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
