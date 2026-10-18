--!strict
-- The Tuner Trials page (ui/TunerTrials.tsx): the picked trial's banner (venue, distance, name,
-- difficulty) over the parts and tuning it asks for, each checked against your race car (a miss
-- opens the Garage on the Mods or Upgrades tab); every trial as a tile in its colour; and your car
-- against the host's, built for the trial, with the prize and the pattern the first win unlocks.
-- The race button races the picked trial, or opens the Garage when the build isn't ready
-- (Race.tsx startTuner, fixBuild). The server (server/Modes/Tuner) starts and pays the races.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local venues = require(Game.scene_venues) :: any
local distance = require(Game.distance) :: any
local raceCar = require(Game.raceCar) :: any
local tuner = require(Game.tuner) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local DragStrip = require(script.Parent.Parent.DragStrip)
local Paint = require(ReplicatedStorage.Shared.Models.Paint) :: any

local Tuner = {}
Tuner.id = "tuner"
Tuner.title = "Tuner Trials"
Tuner.mini = { icon = "🔧", label = "Tuner Trials" }

local INK = Ui.INK
local GREEN = Color3.fromHex("#2fae35")
local RED = Color3.fromHex("#d32f2f")
local TUNE: { [string]: { icon: string, name: string } } = {
	engine = { icon = "⚡", name = "Speed" },
	turbo = { icon = "🌀", name = "Boost" },
	tires = { icon = "🧲", name = "Grip" },
	weight = { icon = "🪶", name = "Weight" },
}
local TUNE_ORDER = { engine = 1, turbo = 2, tires = 3, weight = 4 }
-- Tyres a trial asks for by name: shown by the surface they grip on.
local TREAD: { [string]: { icon: string, name: string } } = {
	snowstuds = { icon = "❄️", name = "Snow tires" },
	sandtires = { icon = "🏜️", name = "Sand tires" },
	raintires = { icon = "🌧️", name = "Rain tires" },
}
-- How far the race car outclasses a host before the page calls the race an easy win.
local EASY = 1.5

-- The trial picked on the page (nil: the first one not won yet).
local picked: string? = nil

local function flames(t: any): string
	return string.rep("🔥", t.tier)
end

local function wins(t: any): number
	local s = store.useGame.getState()
	return (s.tuner or {})[t.id] or 0
end

local function modSlot(slot: string): any
	for _, m in data.MOD_SLOTS do
		if m.id == slot then
			return m
		end
	end
	return { icon = "🔧", name = slot }
end

-- One line per requirement, met or not (tuner.ts buildChecks), parts first in the Mods tab's
-- order, then tuning.
local function checksFor(t: any, car: any): { any }
	if not car then
		return {}
	end
	local list = table.clone(tuner.buildChecks(t, car))
	local slotAt: { [string]: number } = {}
	for i, m in data.MOD_SLOTS do
		slotAt[m.id] = i
	end
	local function key(c: any): number
		return if c.kind == "mod" then (slotAt[c.slot] or 50) else 100 + (TUNE_ORDER[c.slot] or 50)
	end
	table.sort(list, function(a, b)
		return key(a) < key(b)
	end)
	return list
end

local function ready(checks: { any }): boolean
	for _, c in checks do
		if not c.ok then
			return false
		end
	end
	return true
end

-- Where to fix the first unmet line of a build: the parts shop or the tuning bench.
local function fixBuild(ctx: any, car: any, checks: { any })
	for _, c in checks do
		if not c.ok then
			ctx.open("garage", { car = car.uid, tab = if c.kind == "mod" then "mods" else "tune" })
			return
		end
	end
end

local function patternOf(t: any): any?
	return if t.pattern then data.patternDef(t.pattern) else nil
end

-- A check row (.tt-check): its icon, name, the tuning pips, and a tick or a cross.
local function checkRow(parent: Instance, c: any, order: number, onFix: () -> ())
	local row = Ui.new("TextButton", {
		Name = `{c.kind}-{c.slot}`,
		Text = "",
		AutoButtonColor = false,
		LayoutOrder = order,
		BackgroundColor3 = if c.ok then Color3.fromHex("#f2fff0") else Ui.WHITE,
		Parent = parent,
	}, { Ui.corner(12), Ui.stroke(2.5, if c.ok then Color3.fromHex("#8fd694") else Color3.fromHex("#e57373")) })
	local icon, name
	if c.kind == "mod" then
		local m = modSlot(c.slot)
		local tread = if c.ids then TREAD[c.ids[1]] else nil
		icon = if tread then tread.icon else m.icon
		name = if tread then tread.name else (string.gsub(m.name, "s$", ""))
	else
		local u = TUNE[c.slot] or { icon = "🔧", name = c.slot }
		icon, name = u.icon, u.name
	end
	Ui.text({ Text = icon, TextSize = 18, Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0, 24, 1, 0), Parent = row })
	local pipsW = 0
	if c.kind == "tune" then
		pipsW = data.MAX_UPGRADE * 9
		local pips = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -28, 0.5, 0), Size = UDim2.fromOffset(pipsW, 12), BackgroundTransparency = 1, Parent = row }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		for i = 1, data.MAX_UPGRADE do
			local on = i <= c.have
			local need = not on and i <= c.need
			local pip = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(7, 12), BackgroundColor3 = if on then GREEN elseif need then Ui.WHITE else Color3.fromHex("#dfe7f2"), Parent = pips }, { Ui.corner(2) })
			if need then
				Ui.stroke(2, if c.ok then Color3.fromHex("#8fd694") else Color3.fromHex("#e57373")).Parent = pip
			end
		end
	end
	Ui.text({ Text = name, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(34, 0), Size = UDim2.new(1, -(34 + 28 + pipsW + 4), 1, 0), Parent = row })
	Ui.text({ Text = if c.ok then "✔" else "✗", Body = true, Weight = "heavy", TextSize = 15, TextColor3 = if c.ok then GREEN else RED, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 0), Size = UDim2.new(0, 20, 1, 0), Parent = row })
	if not c.ok then
		row.Activated:Connect(onFix)
	end
	return row
end

-- A PI bar (.tt-pi): filled to this side's share of the higher PI.
local function piBar(parent: Instance, pi: number, top: number, fill: Color3, y: number)
	local bar = Ui.new("Frame", { Name = "PI", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, y), Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = Color3.fromHex("#dfe7f2"), ClipsDescendants = true, Parent = parent }, {
		Ui.round(),
		Ui.stroke(2, Ui.LINE),
	})
	Ui.new("Frame", { Size = UDim2.fromScale(math.clamp(pi / top, 0, 1), 1), BackgroundColor3 = fill, BorderSizePixel = 0, Parent = bar }, { Ui.round() })
	Ui.text({ Text = `PI {pi}`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = INK, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = bar })
end

-- A chip sized to its text (no AutomaticSize inside layouts).
local function chip(parent: Instance, text: string, order: number, size: number, color: Color3, props: { [string]: any }?)
	local w = math.ceil(Ui.textWidth(text, size)) + 22
	local f = Ui.new("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(w, size + 12), BackgroundColor3 = color, Parent = parent }, { Ui.corner(12), Ui.stroke(2.5, Ui.LINE) })
	local p: { [string]: any } = { Text = text, TextSize = size, TextColor3 = INK, Size = UDim2.fromScale(1, 1), Parent = f }
	for k, v in (props or {}) :: { [string]: any } do
		p[k] = v
	end
	Ui.text(p)
	return f
end

function Tuner.draw(page: Frame, ctx: any, api: any)
	local s = store.useGame.getState()
	local won = s.tuner or {}
	local sel = picked
	if not sel or not tuner.tunerTrial(sel) then
		sel = tuner.TUNER_TRIALS[1].id
		for _, x in tuner.TUNER_TRIALS do
			if (won[x.id] or 0) == 0 then
				sel = x.id
				break
			end
		end
	end
	local t = tuner.tunerTrial(sel)
	local beaten = wins(t) > 0
	local v = venues.venue(t.venue)
	local hc = data.carDef(t.car)
	local car = api.myCar()
	local checks = checksFor(t, car)
	local pat = patternOf(t)
	local mine = if car then raceCar.carPi(car) else 0
	local easy = mine >= t.pi * EASY
	local top = math.max(mine, t.pi, 1)
	local prize = tuner.tunerPrize(t, not beaten)
	local skill = if t.tier >= 2 and hc.skill and data.SKILLS[hc.skill] then data.SKILLS[hc.skill] else nil
	local tint = Color3.fromHex(t.color)

	-- ── Left: the banner and the build ────────────────────────────────────────────────────────
	local left = Ui.new("Frame", { Name = "Picked", Size = UDim2.new(0.465, -6, 1, 0), BackgroundTransparency = 1, Parent = page })
	local _, banner = api.tile(left, { Name = "Banner", Size = UDim2.new(1, 0, 0.5, -4) }, if t.night then "#1b2350" else v.sky, if t.night then "#0b1030" else "#14213d", true)
	banner.ClipsDescendants = true
	-- The trial's gimmick (.tt-twist).
	local twist = Ui.new("Frame", { Name = "Twist", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(52, 52), BackgroundColor3 = Ui.WHITE, Parent = banner }, {
		Ui.round(),
		Ui.stroke(3, Ui.LINE),
	})
	Ui.text({ Text = t.icon, TextSize = 28, Size = UDim2.fromScale(1, 1), Parent = twist })
	Ui.text({ Text = t.twist, Body = true, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromHex("#cfe0ff"), Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -90, 0, 36), Parent = banner })
	Ui.text({ Text = string.upper(`{v.icon} {v.name}{if t.night then " · 🌙" else ""} · {distance.DIST[t.dist].label}`), Body = true, Weight = "heavy", TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -74), Size = UDim2.new(1, -28, 0, 16), Parent = banner })
	Ui.text({ Text = t.name, TextSize = 28, TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -42), Size = UDim2.new(1, -28, 0, 32), Stroke = 1, Shadow = 2, Parent = banner })
	local chips = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.new(1, -24, 0, 24), BackgroundTransparency = 1, Parent = banner }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, text in { flames(t), if skill then skill.icon else "", if beaten then `✔ ×{wins(t)}` else "" } do
		if text ~= "" then
			local w = math.ceil(Ui.textWidth(text, 13)) + 20
			local c = Ui.new("Frame", { LayoutOrder = i, Size = UDim2.fromOffset(w, 24), BackgroundColor3 = if i == 3 then Color3.fromRGB(47, 174, 53) else Color3.fromRGB(10, 20, 45), BackgroundTransparency = if i == 3 then 0.1 else 0.4, Parent = chips }, {
				Ui.round(),
				Ui.stroke(1.5, Ui.WHITE, 0.75),
			})
			Ui.text({ Text = text, TextSize = 13, Size = UDim2.fromScale(1, 1), Parent = c })
		end
	end

	-- The build (.tt-build): two columns of checks.
	local build = Ui.new("Frame", { Name = "Build", Position = UDim2.new(0, 0, 0.5, 4), Size = UDim2.new(1, 0, 0.5, -70), BackgroundTransparency = 1, Parent = left }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 38), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	if car then
		for i, c in checks do
			checkRow(build, c, i, function()
				fixBuild(ctx, car, checks)
			end)
		end
	else
		Ui.text({ Text = "Buy a car to race", Body = true, TextSize = 16, TextColor3 = Ui.MUTED, Parent = build })
	end
	-- The race button: the prize, or off to the Garage to fit what's missing.
	local goAt = { Name = "Go", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4), Size = UDim2.new(1, 0, 0, 52) }
	if car and ready(checks) then
		api.raceButton(left, goAt, prize, function()
			picked = t.id
			api.start("tuner", t.id)
		end)
	elseif car then
		local props = table.clone(goAt) :: any
		props.Parent = left
		Ui.buy(props, "🔧 Fit parts", "garage", function()
			picked = t.id
			fixBuild(ctx, car, checks)
		end, 18)
	end

	-- ── Right: every trial, then you against the host ─────────────────────────────────────────
	local right = Ui.new("Frame", { Name = "Trials", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.535, -6, 1, 0), BackgroundTransparency = 1, Parent = page })
	local grid = Ui.new("Frame", { Name = "Grid", Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 2 * 96 + 8), BackgroundTransparency = 1, Parent = right }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0.25, -6, 0, 96), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, x in tuner.TUNER_TRIALS do
		local xc = data.carDef(x.car)
		local isSel = x.id == t.id
		local done = (won[x.id] or 0) > 0
		local xReady = if car then ready(checksFor(x, car)) else false
		local xTint = Color3.fromHex(x.color)
		local b = Ui.new("TextButton", {
			Name = x.id,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
			BackgroundColor3 = if isSel then Ui.WHITE:Lerp(xTint, 0.28) elseif done then Color3.fromHex("#f2fff0") else Ui.WHITE,
			Parent = grid,
		}, {
			Ui.corner(14),
			Ui.stroke(if isSel then 3 else 2.5, if isSel then Ui.LINE elseif done then Color3.fromHex("#8fd694") else Ui.EDGE),
		})
		-- Their colour along the bottom (border-bottom: 6px var(--pr)).
		Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 6), BackgroundColor3 = xTint, BorderSizePixel = 0, Parent = b }, { Ui.corner(4) })
		local pic = Thumb.car(xc.id, UDim2.new(1, -8, 0, 50), { color = x.color }, nil, tuner.hostMods(x))
		pic.Position = UDim2.fromOffset(4, 4)
		pic.Parent = b
		local face = Ui.new("Frame", { Position = UDim2.fromOffset(-4, -6), Size = UDim2.fromOffset(28, 28), BackgroundColor3 = Ui.WHITE, ZIndex = 2, Parent = b }, { Ui.round(), Ui.stroke(2, Ui.LINE) })
		Ui.text({ Text = x.icon, TextSize = 16, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = face })
		if done or not xReady then
			local tick = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 4, 0, -6), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = if done then GREEN else Ui.WHITE, ZIndex = 2, Parent = b }, {
				Ui.round(),
				Ui.stroke(2, if done then Ui.WHITE else Ui.EDGE),
			})
			Ui.text({ Text = if done then "✔" else "🔧", Body = true, Weight = "heavy", TextSize = if done then 13 else 12, Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = tick })
		end
		Ui.text({ Text = `{flames(x)}{if x.pattern then " 🎨" else ""}`, TextSize = 11, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 14), Parent = b })
		Ui.text({ Text = `PI {x.pi}`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = INK, Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 18), Parent = b })
		b.Activated:Connect(function()
			picked = x.id
			api.show("tuner")
		end)
	end

	-- You against the host (.tt-vs).
	local vsTop = 2 * 96 + 8 + 16
	local vs = Ui.new("Frame", { Name = "Versus", Position = UDim2.fromOffset(0, vsTop), Size = UDim2.new(1, 0, 1, -(vsTop + 4)), BackgroundColor3 = Ui.WHITE, Parent = right }, {
		Ui.corner(18),
		Ui.stroke(3, Ui.LINE),
		Ui.new("UIGradient", { Color = ColorSequence.new(Ui.WHITE, Ui.SHEET:Lerp(tint, 0.26)), Rotation = 90 }),
	})
	local prizeH = 46
	local function side(x: number, anchor: number): Frame
		return Ui.new("Frame", { AnchorPoint = Vector2.new(anchor, 0), Position = UDim2.new(x, if anchor == 0 then 10 else -10, 0, 8), Size = UDim2.new(0.5, -40, 1, -(prizeH + 16)), BackgroundTransparency = 1, Parent = vs })
	end
	local me = side(0, 0)
	me.Name = "Me"
	local mePanels = if pat then { body = { pattern = pat.id } } else nil
	local myPic = if car
		then Thumb.car(car.model, UDim2.new(1, 0, 1, -30), Paint.jobOf(car), nil, car.mods, mePanels)
		else Thumb.new("Cars", data.CARS[1].id, UDim2.new(1, 0, 1, -30), tint)
	myPic.Parent = me
	piBar(me, mine, top, GREEN, 0)
	local host = side(1, 1)
	host.Name = "Host"
	local hostPic = Thumb.car(hc.id, UDim2.new(1, 0, 1, -30), { color = t.color }, nil, tuner.hostMods(t))
	hostPic.Parent = host
	-- Facing the other way, as the web's mirrored host thumb.
	local cam = hostPic:FindFirstChildOfClass("Camera")
	local model = hostPic:FindFirstChildOfClass("Model")
	if cam and model then
		local cf = model:GetBoundingBox()
		local off = cam.CFrame.Position - cf.Position
		cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(-off.X, off.Y, off.Z), cf.Position)
	end
	piBar(host, t.pi, top, tint:Lerp(Ui.WHITE, 0.2), 0)
	Ui.text({ Text = "VS", TextSize = 34, Rotation = -8, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -prizeH / 2), Size = UDim2.fromOffset(60, 40), Stroke = 3, Parent = vs })
	if easy then
		local e = chip(vs, "😴 Too easy", 0, 14, Color3.fromHex("#ffd84a"), { Body = true, Weight = "heavy" })
		e.AnchorPoint = Vector2.new(0.5, 0)
		e.Position = UDim2.new(0.5, 0, 0, 8)
	end
	local prizeRow = Ui.new("Frame", { Name = "Prize", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -8), Size = UDim2.new(1, 0, 0, prizeH - 6), BackgroundTransparency = 1, Parent = vs }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	chip(prizeRow, `🏆 {api.money(prize)}`, 1, 24, if beaten then Color3.fromHex("#fff3c4") else Color3.fromHex("#ffd84a"))
	if pat then
		chip(prizeRow, `{if beaten then "✔" else "🎨"} {pat.name}`, 2, 15, Ui.WHITE, { Body = true, Weight = "heavy" })
	end
end

-- The race screen: the trial in the title; after it, the rematch (or retry), and the pattern the
-- first win unlocks with a button to paint it (TunerPrizePopup).
function Tuner.extras(ctx: any, which: any, _started: any, again: (string, any) -> () -> ()): DragStrip.Extras
	local t = tuner.tunerTrial(which)
	return {
		title = `{t.icon} {t.name}`,
		view = function(card: Frame, res: any, y: number): number
			local pat = if res.pattern then data.patternDef(res.pattern) else nil
			if not pat then
				return y
			end
			local row = Ui.new("Frame", { Name = "PatternPrize", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(340, 64), BackgroundColor3 = Color3.fromHex("#fff8e1"), Parent = card }, {
				Ui.corner(12),
				Ui.stroke(2, Color3.fromHex("#ffb300")),
			})
			local s = store.useGame.getState()
			local car = raceCar.raceCarOf(s.cars, s.raceCar)
			local pic = if car
				then Thumb.car(car.model, UDim2.fromOffset(90, 58), Paint.jobOf(car), nil, car.mods, { body = { pattern = pat.id } })
				else Thumb.new("Cars", t.car, UDim2.fromOffset(90, 58), Color3.fromHex(t.color))
			pic.Position = UDim2.fromOffset(6, 3)
			pic.Parent = row
			Ui.text({ Text = `{t.icon} {t.name} won!`, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(104, 8), Size = UDim2.new(1, -112, 0, 18), Parent = row })
			Ui.text({ Text = `🖌️ {pat.name} unlocked`, TextSize = 19, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(104, 28), Size = UDim2.new(1, -112, 0, 26), Parent = row })
			return y + 74
		end,
		buttons = function(res: any): { DragStrip.Button }?
			local list: { DragStrip.Button } = {}
			if res.pattern then
				local s = store.useGame.getState()
				local car = raceCar.raceCarOf(s.cars, s.raceCar)
				if car then
					table.insert(list, { text = "🖌️ Paint it", go = function()
						ctx.open("garage", { car = car.uid, tab = "custom" })
					end })
				end
			end
			local beaten = res.won or (res.wins or 0) > 0
			table.insert(list, { text = if beaten then `↻ Rematch · {`${Ui.commas(tuner.tunerPrize(t, false))}`}` else "↻ Retry", kind = "garage", go = again("tuner", which) })
			table.insert(list, { text = "Back" })
			return list
		end,
	}
end

return Tuner
