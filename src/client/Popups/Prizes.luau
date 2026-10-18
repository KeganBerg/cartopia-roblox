--!strict
-- The prize cards a race leaves behind (index.css .prize): a campaign chapter cleared or starred
-- (Race.tsx CampaignPrizePopup), a paint rival beaten (PaintRivals.tsx), a tuner trial won
-- (TunerTrials.tsx), a mastery step (ClassCups.tsx MasteryPrizePopup) and a class cup's free
-- crate (CupPrizePopup). They come in the snapshot's popups and show once the race screen is gone.
-- The Grand Prix, World Tour and event prizes belong to their own race pages.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local paintRivals = require(Game.paintRivals) :: any
local tuner = require(Game.tuner) :: any
local mastery = require(Game.mastery) :: any
local classes = require(Game.classes) :: any
local cups = require(Game.cups) :: any
local crates = require(Game.crates) :: any
local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)
local Kit = require(script.Parent.Kit)

local Prizes = {}

local W = 360
local INK = Ui.INK
local H2 = Color3.fromHex("#e65100")

-- The card: cream, gold-edged (.prize), centred; returns the overlay and the card's face.
local function prizeCard(ctx: any, h: number): (TextButton, any)
	local overlay = Kit.overlay(ctx, false)
	local _, face = Ui.shadowed({ Name = "Prize", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, h), ZIndex = 2, Parent = overlay }, {
		radius = 22,
		stroke = 4,
		drop = 0,
		dark = 0.25,
		color = Kit.PANEL,
		strokeColor = Kit.GOLD,
		class = "TextButton",
	})
	face.Selectable = false
	return overlay, face
end

local function h2(card: Instance, text: string, y: number): number
	local lines = if Ui.textWidth(text, 26) > W - 44 then 2 else 1
	Ui.text({ Name = "Title", Text = text, TextSize = 26, TextColor3 = H2, TextWrapped = true, Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 30 * lines), Parent = card })
	return 30 * lines + 6
end

local function h3(card: Instance, text: string, y: number, swatch: string?): number
	if swatch then
		local w = Ui.textWidth(text, 22) + 34
		local row = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(w, 30), BackgroundTransparency = 1, Parent = card })
		Ui.new("Frame", { Position = UDim2.fromOffset(0, 2), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Color3.fromHex(swatch), Parent = row }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
		Ui.text({ Text = text, TextSize = 22, TextColor3 = INK, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -34, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = row })
		return 34
	end
	Ui.text({ Text = text, TextSize = 22, TextColor3 = INK, TextWrapped = true, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 28), Parent = card })
	return 32
end

local function big(card: Instance, icon: string, y: number): number
	Ui.text({ Name = "Box", Text = icon, TextSize = 90, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 104), Parent = card })
	return 110
end

-- A row of prize words in the display face (.camp-prize), centred.
local function prizeRow(card: Instance, words: { string }, y: number): number
	if #words == 0 then
		return 0
	end
	Ui.text({ Text = table.concat(words, "    "), TextSize = 20, TextColor3 = INK, TextWrapped = true, Position = UDim2.fromOffset(12, y), Size = UDim2.new(1, -24, 0, 26), Parent = card })
	return 30
end

local function car(card: Instance, model: string, color: string, own: any?, look: any?, y: number, tint: string?): number
	local stage = Ui.new("Frame", { Name = "Car", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(198, 140), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, Parent = card }, { Ui.corner(14) })
	if tint then
		-- The rival's colour washed into the backdrop (.pr-prize .thumb3d.lg).
		Ui.new("UIGradient", { Rotation = 90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.fromHex("#e8f1fc"):Lerp(Color3.fromHex(tint), 0.3)) }), Parent = stage })
	else
		stage.BackgroundTransparency = 1
	end
	local v = Kit.carThumb(model, UDim2.fromScale(1, 1), color, own, look)
	v.Parent = stage
	return 146
end

-- The car that raced: the picked race car, else the best one (as Race.tsx does).
local function raced(): any?
	local s = store.useGame.getState()
	return raceCar.raceCarOf(s.cars, s.raceCar)
end

local SHOW: { [string]: (ctx: any, p: any, close: () -> ()) -> () } = {}

SHOW.campaignPrize = function(ctx, prize, close)
	local ch, ci = nil, 0
	for i, c in data.CAMPAIGN do
		if c.id == prize.chapter then
			ch, ci = c, i
		end
	end
	if not ch then
		close()
		return
	end
	local nextCh = data.CAMPAIGN[ci + 1]
	local words = {}
	if (prize.coins or 0) > 0 then
		table.insert(words, `💵 +${Ui.commas(prize.coins)}`)
	end
	if (prize.bucks or 0) > 0 then
		table.insert(words, `💎 +{prize.bucks}`)
	end
	if (prize.trophies or 0) > 0 then
		table.insert(words, `🏆 +{prize.trophies}`)
	end
	local after = {}
	if prize.cleared then
		if prize.perfect then
			table.insert(after, "★★★")
		end
		if nextCh then
			local s = store.useGame.getState()
			-- The data's chapter numbers start at 0, as on the web.
			local open = data.campaignOpen(s.campaign, ci, store.gateLevel(s))
			table.insert(after, `⏭ {nextCh.name}{if open then "" else ` · 🔒 ★{data.campaignStarsNeed(ci)}`}`)
		else
			table.insert(after, "🏆 Campaign done · 🌍 Pro Tour")
		end
	end
	local title = if prize.cleared then `{ch.name} cleared!` else `{ch.name}: all three stars!`
	local th = if Ui.textWidth(title, 26) > W - 44 then 66 else 36
	local h = 18 + th + 110 + (if #words > 0 then 30 else 0) + (if #after > 0 then 30 else 0) + 12 + 44 + 18
	local _, card = prizeCard(ctx, h)
	local y = 18
	y += h2(card, title, y)
	y += big(card, if prize.cleared then "🏁" else "🌟", y)
	y += prizeRow(card, words, y)
	y += prizeRow(card, after, y)
	y += 12
	Kit.buttons(card, y, { { text = "Awesome!", go = close } })
end

SHOW.paintPrize = function(ctx, id, close)
	local r = paintRivals.paintRival(id)
	if not r then
		close()
		return
	end
	local own = raced()
	local d = if own then data.carDef(own.model) else data.CARS[1]
	local name = "Paint"
	for _, p in data.PAINTS do
		if p.color == r.paint then
			name = p.name
			break
		end
	end
	local h = 18 + 36 + 146 + 34 + 12 + 44 + 18
	local _, card = prizeCard(ctx, h)
	local y = 18
	y += h2(card, `{r.icon} {r.name} beaten!`, y)
	y += car(card, d.id, r.paint, own, nil, y, r.paint)
	y += h3(card, `{name} unlocked`, y, r.paint)
	y += 12
	local list = { { text = "Nice!", kind = "garage", go = close } }
	if own then
		table.insert(list, { text = "🎨 Paint it", go = function()
			close()
			ctx.open("garage", { car = own.uid, paint = r.paint })
		end })
	end
	Kit.buttons(card, y, list)
end

SHOW.tunerPrize = function(ctx, id, close)
	local t = tuner.tunerTrial(id)
	local pat = t and t.pattern and data.patternDef(t.pattern)
	if not t or not pat then
		close()
		return
	end
	local own = raced()
	local d = if own then data.carDef(own.model) else data.CARS[1]
	local h = 18 + 36 + 146 + 32 + 12 + 44 + 18
	local _, card = prizeCard(ctx, h)
	local y = 18
	y += h2(card, `{t.icon} {t.name} won!`, y)
	y += car(card, d.id, if own then own.color else t.color, own, { panels = { body = { pattern = pat.id } } }, y, t.color)
	y += h3(card, `🖌️ {pat.name} unlocked`, y)
	y += 12
	local list = { { text = "Nice!", kind = "garage", go = close } }
	if own then
		table.insert(list, { text = "🖌️ Paint it", go = function()
			close()
			ctx.open("garage", { car = own.uid, tab = "custom" })
		end })
	end
	Kit.buttons(card, y, list)
end

SHOW.cupPrize = function(ctx, id, close)
	local r = cups.cupRace(id)
	if not r then
		close()
		return
	end
	local cls = classes.carClass(r.cls)
	local crate = crates.crateDef(cups.CUP_CRATE)
	local title = `{cls.icon} {cls.name} Cup {string.rep("🏆", r.tier)} won!`
	local th = if Ui.textWidth(title, 26) > W - 44 then 66 else 36
	local h = 18 + th + 110 + 32 + 12 + 44 + 18
	local _, card = prizeCard(ctx, h)
	local y = 18
	y += h2(card, title, y)
	y += big(card, "📦", y)
	y += h3(card, `🎁 Free {if crate then crate.name else "crate"}`, y)
	y += 12
	Kit.buttons(card, y, {
		{ text = "Later", kind = "garage", go = close },
		{ text = "Open it", go = function()
			close()
			ctx.open("crates")
		end },
	})
end

-- The four steps of a car's mastery (ClassCups.tsx MasteryLadder), each lit once reached.
local function ladder(card: Instance, model: string, y: number): number
	local m = (store.useGame.getState().mastery or {})[model] or mastery.emptyMastery()
	local n = #mastery.MASTERY_TIERS
	local gap = 6
	local w = (W - 2 * 24 - gap * (n - 1)) / n
	for i, t in mastery.MASTERY_TIERS do
		local got = m.tier > i - 1
		local nxt = m.tier == i - 1
		local need = mastery.needProgress(m, t)[1] or { 0, 0 }
		local cell = Ui.new("Frame", {
			Name = t.id,
			Position = UDim2.fromOffset(24 + (i - 1) * (w + gap), y),
			Size = UDim2.fromOffset(w, 58),
			BackgroundColor3 = Color3.fromHex(if got then "#f2fff0" else "#ffffff"),
			BackgroundTransparency = if got or nxt then 0 else 0.4,
			Parent = card,
		}, { Ui.corner(12), Ui.stroke(2.5, Color3.fromHex(if got then "#8fd694" elseif nxt then "#14213d" else "#c6d7ee")) })
		Ui.text({ Text = t.icon, TextSize = 20, Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, 0, 0, 22), TextTransparency = if got or nxt then 0 else 0.5, Parent = cell })
		Ui.text({ Text = t.name, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = INK, Position = UDim2.fromOffset(0, 25), Size = UDim2.new(1, 0, 0, 14), Parent = cell })
		Ui.text({ Text = if got then "✔" elseif nxt then `{need[1]}/{need[2]}` else "🔒", Body = true, TextSize = 11, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(0, 39), Size = UDim2.new(1, 0, 0, 14), Parent = cell })
	end
	return 64
end

SHOW.masteryPrize = function(ctx, p, close)
	local t = if p.tier > 0 then mastery.MASTERY_TIERS[math.min(p.tier, #mastery.MASTERY_TIERS)] else nil
	local top: any = nil
	for _, c in p.classes or {} do
		if not top or c.tier > top.tier then
			top = c
		end
	end
	local d = data.carDef(p.model)
	local own = nil
	for _, c in store.useGame.getState().cars do
		if c.model == p.model then
			own = c
			break
		end
	end
	local first = p.first or {}
	local color = if #first > 0 then mastery.firstPaint(first[1]) elseif own then own.color else d.colors[1]
	local finish = if p.galaxy then "galaxy" elseif top then (if top.tier >= 2 then "diamond" else "gold") else nil
	local look = if finish then { finish = finish } elseif t and t.id == "signature" then { panels = { body = { pattern = "signature" } } } else nil
	local title = if p.galaxy
		then `{mastery.CLASS_TIERS[3].icon} {mastery.CLASS_TIERS[3].name}!`
		elseif top then `{mastery.CLASS_TIERS[top.tier].icon} {classes.carClass(top.cls).name} {mastery.CLASS_TIERS[top.tier].name}!`
		elseif t then `{t.icon} {t.name} mastery!`
		else "🎨 New colour!"
	local lines: { string } = {}
	if t then
		table.insert(lines, `{d.name} · 💎 {t.bucks}{if (t.trophies or 0) > 0 then ` · 🏆 {t.trophies}` else ""}`)
	end
	if (p.xp or 0) > 0 then
		table.insert(lines, `⭐ {Ui.commas(p.xp)} XP`)
	end
	for _, c in first do
		table.insert(lines, `🎨 {classes.carClass(c).name} colour unlocked`)
	end
	local h = 18 + 36 + 146 + #lines * 32 + (if t then 64 else 0) + 12 + 44 + 18
	local _, card = prizeCard(ctx, h)
	local y = 18
	y += h2(card, title, y)
	y += car(card, d.id, color, own, look, y, nil)
	for _, l in lines do
		y += h3(card, l, y)
	end
	if t then
		y += ladder(card, p.model, y)
	end
	y += 12
	Kit.buttons(card, y, { { text = "Nice!", go = close } })
end

-- The store's close action for each.
local CLOSE = {
	campaignPrize = "closeCampaignPrize",
	paintPrize = "closePaintPrize",
	tunerPrize = "closeTunerPrize",
	masteryPrize = "closeMasteryPrize",
	cupPrize = "closeCupPrize",
}
local ORDER = { "masteryPrize", "campaignPrize", "paintPrize", "tunerPrize", "cupPrize" }

function Prizes.start(ctx: any)
	local function look()
		local s = store.useGame.getState()
		for i, key in ORDER do
			if s[key] ~= nil then
				Kit.push(ctx, key, 1 + i, function(done)
					local p = store.useGame.getState()[key]
					if p == nil then
						done()
						return
					end
					local function close()
						-- A newer prize of the same kind that came while this showed gets its own turn.
						if store.useGame.getState()[key] == p then
							store.useGame.getState()[CLOSE[key]]()
						end
						local o = ctx.gui:FindFirstChild("Popup")
						if o then
							o:Destroy()
						end
						done()
					end
					SHOW[key](ctx, p, close)
				end)
			end
		end
	end
	Remote.changed:Connect(look)
	look()
end

return Prizes
