--!strict
-- Car mastery on screen (ui/ClassCups.tsx): a car's top medal (MasteryMedal), its four-step ladder
-- (MasteryLadder), its classes' Gold and Diamond and Galaxy (ClassTiers), and what a finished race
-- unlocked (MasteryPrizePopup), drawn on the race's result card.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local mastery = require(Game.mastery) :: any
local classes = require(Game.classes) :: any
local Ui = require(script.Parent.Ui)

local Mastery = {}

local GOT_EDGE = Color3.fromHex("#8fd694")
local GOT_BG = Color3.fromHex("#f2fff0")
local SMALL = Color3.fromHex("#4a6283")

-- The car's top mastery medal (an emoji), or "" before Bronze.
function Mastery.medal(model: string): string
	local s = store.useGame.getState()
	local b = mastery.masteryBadge(((s.mastery or {})[model] or {}).tier or 0)
	return if b then b.icon else ""
end

-- One cell of a row (.ms-tier / .ms-class): icon, name, and a small line under them.
local function cell(parent: Instance, order: number, icon: string, name: string, small: string, look: string, iconSize: number)
	local dim = look == "dim"
	local f = Ui.new("Frame", { Name = name, LayoutOrder = order, Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = if look == "got" then GOT_BG else Ui.WHITE, BackgroundTransparency = if dim then 0.4 else 0, Parent = parent }, {
		Ui.corner(12),
		Ui.stroke(2.5, if look == "got" then GOT_EDGE elseif look == "next" then Ui.LINE else Ui.EDGE, if dim then 0.4 else 0),
	})
	local t = if dim then 0.45 else 0
	Ui.text({ Text = icon, TextSize = iconSize, TextTransparency = t, Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, iconSize + 2), Parent = f })
	Ui.text({ Text = name, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = Ui.INK, TextTransparency = t, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 2, 0, iconSize + 3), Size = UDim2.new(1, -4, 0, 14), Parent = f })
	Ui.text({ Text = small, Body = true, TextSize = 11, TextColor3 = SMALL, TextTransparency = t, Position = UDim2.new(0, 2, 0, iconSize + 17), Size = UDim2.new(1, -4, 0, 13), Parent = f })
	return f
end

local function row(props: { [string]: any }, n: number): Frame
	local f = Ui.new("Frame", props)
	f.BackgroundTransparency = 1
	Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / n, -6 * (n - 1) / n - 1, 1, 0), CellPadding = UDim2.fromOffset(6, 0), SortOrder = Enum.SortOrder.LayoutOrder, Parent = f })
	return f
end

-- The four mastery steps of one car: each lit once reached, the next one with its count
-- (MasteryLadder). Height 54.
function Mastery.ladder(props: { [string]: any }, model: string): Frame
	local s = store.useGame.getState()
	local m = (s.mastery or {})[model] or mastery.emptyMastery()
	local f = row(props, #mastery.MASTERY_TIERS)
	f.Name = "Ladder"
	for i, t in mastery.MASTERY_TIERS do
		local got = m.tier >= i
		local nextOne = m.tier == i - 1
		local p = mastery.needProgress(m, t)[1]
		cell(f, i, t.icon, t.name, if got then "✔" elseif nextOne then `{p[1]}/{p[2]}` else "🔒", if got then "got" elseif nextOne then "next" else "dim", 22)
	end
	return f
end

-- Class mastery for a car's classes: cars mastered towards Gold and Diamond, then Galaxy
-- (ClassTiers). Height 50.
function Mastery.classes(props: { [string]: any }, model: string): Frame
	local s = store.useGame.getState()
	local all = s.mastery
	local list = classes.classesOf(model)
	local f = row(props, #list + 1)
	f.Name = "Classes"
	local T = mastery.CLASS_TIERS
	for i, c in list do
		local tier = mastery.classTier(all, c.id)
		local need = mastery.classNeed(c.id)
		local goal = if tier >= 1 then need.diamond else need.gold
		local t = T[math.min(tier, 1) + 1]
		cell(f, i, c.icon, c.name, if tier >= 2 then `{T[2].icon} ✔` else `{t.icon} {mastery.masteredIn(all, c.id)}/{goal}`, if tier >= 2 then "got" else "plain", 18)
	end
	local sky = mastery.galaxy(all)
	local diamonds = 0
	for _, c in classes.CAR_CLASSES do
		if mastery.classTier(all, c.id) >= 2 then
			diamonds += 1
		end
	end
	cell(f, #list + 1, T[3].icon, T[3].name, if sky then "✔" else `{diamonds}/{#classes.CAR_CLASSES}`, if sky then "got" else "plain", 18)
	return f
end

-- What a race unlocked in mastery (the server's result.mastery, the store's masteryPrize): a
-- car's step and its gems, a class's Gold or Diamond, Galaxy, or a class colour from a first
-- win. Drawn on the result card from height y; returns the height it reached.
function Mastery.prize(card: Frame, p: any, y: number): number
	local T = mastery.CLASS_TIERS
	local t = if (p.tier or 0) > 0 then mastery.MASTERY_TIERS[math.min(p.tier, #mastery.MASTERY_TIERS)] else nil
	local top: any = nil
	for _, c in p.classes or {} do
		if not top or c.tier > top.tier then
			top = c
		end
	end
	local first = p.first or {}
	local title = if p.galaxy then `{T[3].icon} {T[3].name}!`
		elseif top then `{T[top.tier].icon} {classes.carClass(top.cls).name} {T[top.tier].name}!`
		elseif t then `{t.icon} {t.name} mastery!`
		else "🎨 New colour!"
	-- Each line, and a first win's colour as its swatch.
	local lines: { { any } } = {}
	if t then
		table.insert(lines, { `{data.carDef(p.model).name} · 💎 {t.bucks}{if t.trophies > 0 then ` · 🏆 {t.trophies}` else ""}` })
	end
	if (p.xp or 0) > 0 then
		table.insert(lines, { `⭐ {Ui.commas(p.xp)} XP` })
	end
	for _, c in first do
		table.insert(lines, { `🎨 {classes.carClass(c).name} colour unlocked`, mastery.firstPaint(c) })
	end
	local h = 36 + #lines * 20 + (if t then 58 else 0)
	local box = Ui.new("Frame", { Name = "MasteryPrize", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(360, h), BackgroundColor3 = Color3.fromHex("#fff8e1"), Parent = card }, { Ui.corner(14), Ui.stroke(2, Color3.fromHex("#ffb300")) })
	Ui.text({ Text = title, TextSize = 22, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 26), Parent = box })
	local at = 34
	for _, l in lines do
		Ui.text({ Text = l[1], Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, at), Size = UDim2.new(1, 0, 0, 20), Parent = box })
		if l[2] then
			local w = Ui.textWidth(l[1], 15)
			Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.5, -w / 2 - 6, 0, at + 10), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.fromHex(l[2]), Parent = box }, { Ui.round(), Ui.stroke(1.5, Ui.LINE) })
		end
		at += 20
	end
	if t then
		Mastery.ladder({ Position = UDim2.fromOffset(10, at + 2), Size = UDim2.new(1, -20, 0, 50), Parent = box }, p.model)
	end
	return y + h + 10
end

return Mastery
