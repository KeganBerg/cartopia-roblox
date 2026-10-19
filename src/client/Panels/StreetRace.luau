--!strict
-- A street racer's challenge, as the web game's StreetRaceCard (ui/Visitors.tsx): who they are,
-- their car, PI and how tough they look against your best car, what beating them pays on top of
-- the race prize, and Race! (free of fuel) or No thanks. Opened by tapping the street racer in
-- town (client/Visitors); closes itself if they leave.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local Visitors = require(script.Parent.Parent.Visitors)

local StreetRace = {}
StreetRace.id = "streetRace"

local W = 460
local CHIP_H = 28
local EDGE = Color3.fromHex("#cfd8dc")

-- The web's odds line: against the town's best car.
function StreetRace.odds(pi: number, cars: { any }): string
	local best = 0
	for _, c in cars do
		best = math.max(best, data.performance(data.carDef(c.model), c.upgrades, c.mods))
	end
	return if pi <= best then "Even match" elseif pi - best < 8 then "Tough" else "Very tough"
end

-- A .chip: white with a grey edge (green for the free race).
local function chip(parent: Instance, text: string, x: number, y: number, free: boolean?): number
	local w = math.ceil(Ui.textWidth(text, 15)) + 20
	local f = Ui.new("Frame", { Name = "Chip", Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, CHIP_H), BackgroundColor3 = if free then Color3.fromHex("#e8f5e9") else Ui.WHITE, Parent = parent }, {
		Ui.corner(14),
		Ui.stroke(2, if free then Color3.fromHex("#a5d6a7") else EDGE),
	})
	Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, Size = UDim2.fromScale(1, 1), Parent = f })
	return w
end

function StreetRace.open(ctx: any): Instance?
	local v = Visitors.visitor
	if not v or v.kind ~= "racer" or v.gone then
		return nil
	end
	local overlay, sheet, body = Ui.panel(ctx.gui, "Street challenge", { width = W, onClose = ctx.close })
	local limit = (sheet.Parent :: Instance):FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local s = store.useGame.getState()
	local def = data.carDef(v.model)

	-- Who: the car and its driver (.street-card).
	local head = Ui.new("Frame", { Name = "StreetCard", Size = UDim2.new(1, 0, 0, 60), BackgroundTransparency = 1, Parent = body })
	local well = Ui.new("Frame", { Size = UDim2.fromOffset(76, 56), Position = UDim2.new(0, 0, 0.5, -28), BackgroundColor3 = Ui.WHITE, ClipsDescendants = true, Parent = head }, { Ui.corner(10) })
	Thumb.car(v.model, UDim2.fromScale(1, 1), { color = v.color, finish = "gloss", stripe = "#fafafa" }).Parent = well
	Ui.text({ Name = "Name", Text = v.name, Body = true, Weight = "heavy", TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(88, 8), Size = UDim2.new(1, -88, 0, 22), Parent = head })
	Ui.text({ Name = "Car", Text = `{def.name} · PI {v.pi} · {StreetRace.odds(v.pi, s.cars or {})}`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(88, 32), Size = UDim2.new(1, -88, 0, 18), Parent = head })

	-- What winning pays on top of the race prize (.street-prize), wrapping like the web's row.
	local prize = Ui.new("Frame", { Name = "StreetPrize", Position = UDim2.fromOffset(0, 72), Size = UDim2.new(1, 0, 0, CHIP_H), BackgroundTransparency = 1, Parent = body })
	local lead = "Win: race prize +"
	local width = W - 28 - 8
	local x, y = 0, 0
	Ui.text({ Text = lead, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(math.ceil(Ui.textWidth(lead, 16)) + 4, CHIP_H), Parent = prize })
	x = math.ceil(Ui.textWidth(lead, 16)) + 10
	local chips: { { any } } = {}
	if v.coins > 0 then
		table.insert(chips, { `${Ui.commas(v.coins)}`, false })
	end
	if v.parts > 0 then
		table.insert(chips, { `⚙ {v.parts}`, false })
	end
	if v.bucks > 0 then
		table.insert(chips, { `💎{v.bucks}`, false })
	end
	table.insert(chips, { "⛽ Free race", true })
	for _, c in chips do
		local w = math.ceil(Ui.textWidth(c[1], 15)) + 20
		if x + w > width then
			x, y = 0, y + CHIP_H + 6
		end
		x += chip(prize, c[1], x, y, c[2]) + 6
	end
	prize.Size = UDim2.new(1, 0, 0, y + CHIP_H)

	-- Race! or No thanks (.street-actions).
	local by = 72 + y + CHIP_H + 14
	local actions = Ui.new("Frame", { Name = "StreetActions", Position = UDim2.fromOffset(0, by), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = body })
	local noText = "No thanks"
	local noW = math.ceil(Ui.textWidth(noText, 16)) + 28
	Ui.buy({ Name = "Race", Size = UDim2.new(1, -(noW + 10), 0, 42), Parent = actions }, "Race!", "green", function()
		Visitors.race(ctx)
	end, 18)
	local no = Ui.new("TextButton", { Name = "NoThanks", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(noW, 42), BackgroundTransparency = 1, Parent = actions }, {
		Ui.corner(12),
		Ui.stroke(2, EDGE),
	})
	Ui.text({ Text = noText, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, Size = UDim2.fromScale(1, 1), Parent = no })
	no.Activated:Connect(function()
		ctx.close()
		Visitors.leave()
	end)
	-- The sheet hugs its rows, as the web's panel.
	limit.MaxSize = Vector2.new(W, 61 + 10 + by + 44 + 18)

	-- They left (their time ran out, or they were sent off): nothing to race.
	local conn = Visitors.changed:Connect(function(now: any)
		if overlay.Parent and (not now or now.gone or now.id ~= v.id) then
			ctx.close()
		end
	end)
	overlay.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return overlay
end

return StreetRace
