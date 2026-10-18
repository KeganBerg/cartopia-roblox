--!strict
-- A car stuck on a job, as the web game's FlatPanel (ui/Goals.tsx): out of gas (fill up at your
-- Gas Station, or a gas can) or a flat tire (your Tire Shop, Rusty's tow, or a mechanic). Opened
-- as the "flat" panel with the car's uid; closes itself once the car is running again.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint)
local Remote = require(script.Parent.Parent.Remote)
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)

local Flat = {}
Flat.id = "flat"

local W = 456
local CAR_H, ROW_H, GAP = 56, 58, 8
local MUTED = Color3.fromHex("#546e7a")

type Source = { icon: string, title: string, detail: string, label: string?, kind: string?, run: (() -> ())? }

-- The stuck car: the one asked for, else the picked one, else any.
local function stuckCar(s: any, uid: string?): any?
	local function stuck(c: any): boolean
		return c.flat == true or c.lowFuel == true
	end
	for _, want in { uid, s.selectedCar } do
		for _, c in s.cars do
			if want ~= nil and c.uid == want and stuck(c) then
				return c
			end
		end
	end
	for _, c in s.cars do
		if stuck(c) then
			return c
		end
	end
	return nil
end

local function sources(ctx: any, s: any, car: any): { Source }
	local function owns(def: string): boolean
		for _, b in s.buildings do
			if b.def == def then
				return true
			end
		end
		return false
	end
	local function act(name: string, ...: any): () -> ()
		local args = table.pack(...)
		return function()
			Remote.act(name, car.uid, table.unpack(args, 1, args.n))
		end
	end
	local function build(def: string): () -> ()
		return function()
			ctx.open("shop", def)
		end
	end
	local function earns(kind: string): string
		return `+${Ui.commas(data.servicePay(s.level, kind))} · ⭐ {Ui.commas(data.xpGain(s.level, data.serviceXp(kind, s.level)))} XP`
	end
	if not car.flat then
		local gas = owns("gas")
		local pay = data.servicePay(s.level, "gas")
		return {
			{
				icon = "⛽",
				title = "Fill up at your Gas Station",
				detail = if gas then earns("gas") else "Earns on every fill-up",
				label = if gas then `Fill up · +${Ui.commas(pay)}` else "Build",
				run = if gas then act("serviceCar", "gas") else build("gas"),
			},
			{ icon = "🛢️", title = "Bring a gas can", detail = "Quick, but it costs you.", label = `Gas can · ${Ui.commas(data.gasCanCost(s.level))}`, kind = "garage", run = act("serviceCar", "can") },
		}
	end
	local tires = owns("tires")
	local rusty = owns("rescue")
	return {
		{
			icon = "🛞",
			title = "Send it to your Tire Shop",
			detail = if tires then earns("tires") elseif s.level < 2 then "🔒 Level 2" else "Earns on every flat",
			label = if tires then `Fix · +${Ui.commas(data.servicePay(s.level, "tires"))}` elseif s.level >= 2 then "Build" else nil,
			run = if tires then act("serviceCar", "tires") else build("tires"),
		},
		{
			icon = "🔧",
			title = "Call Rusty's tow",
			detail = if rusty then `Free · ⭐ {Ui.commas(data.xpGain(s.level, data.serviceXp("tow", s.level)))} XP` else "🔒 Needs Rusty's Rescue",
			label = "Tow · free",
			kind = if rusty then "garage" else "grey",
			run = if rusty then act("fixFlat", true) else nil,
		},
		{ icon = "💵", title = "Pay a mechanic", detail = "Fixed on the spot.", label = `Fix · ${Ui.commas(data.flatFixCost(s.level))}`, kind = "garage", run = act("fixFlat", false) },
	}
end

function Flat.open(ctx: any, uid: string?): Instance?
	local s0 = store.useGame.getState()
	local car0 = stuckCar(s0, uid)
	if not car0 then
		return nil
	end
	local carUid = car0.uid
	local overlay, sheet, body = Ui.panel(ctx.gui, if car0.flat then "Flat Tire!" else "Out of Gas!", { width = W, onClose = ctx.close })
	local limit = (sheet.Parent :: Instance):FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
	local title = sheet:FindFirstChild("Title", true) :: TextLabel?

	local conn: RBXScriptConnection
	local function draw()
		if not overlay.Parent then
			-- Closed (or another menu took its place).
			if conn then
				conn:Disconnect()
			end
			return
		end
		local s = store.useGame.getState()
		local car = stuckCar(s, carUid)
		if not car or car.uid ~= carUid then
			-- Running again: nothing left to fix here.
			if conn then
				conn:Disconnect()
			end
			ctx.close()
			return
		end
		for _, c in body:GetChildren() do
			c:Destroy()
		end
		if title then
			Ui.setText(title, if car.flat then "Flat Tire!" else "Out of Gas!")
		end
		-- The car: its picture and name (.need-car).
		local def = data.carDef(car.model)
		local head = Ui.new("Frame", { Name = "NeedCar", Size = UDim2.new(1, 0, 0, CAR_H), BackgroundTransparency = 1, Parent = body })
		local well = Ui.new("Frame", { Size = UDim2.fromOffset(64, 52), Position = UDim2.new(0, 0, 0.5, -26), BackgroundColor3 = Ui.WHITE, ClipsDescendants = true, Parent = head }, { Ui.corner(10) })
		Thumb.car(car.model, UDim2.fromScale(1, 1), Paint.jobOf(car), nil, nil, nil, nil, car.skin).Parent = well
		Ui.text({ Text = def.name, TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(76, 0), Size = UDim2.new(1, -76, 1, 0), Parent = head })
		local y = CAR_H + GAP
		for i, src in sources(ctx, s, car) do
			local r = Ui.new("Frame", { Name = "Source", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = Ui.WHITE, Parent = body }, {
				Ui.corner(12),
				Ui.stroke(2, Ui.EDGE),
			})
			r.LayoutOrder = i
			Ui.text({ Text = src.icon, TextSize = 24, Position = UDim2.new(0, 10, 0.5, -16), Size = UDim2.fromOffset(32, 32), Parent = r })
			local bw = if src.label then math.ceil(Ui.textWidth(src.label, 14)) + 26 else 0
			Ui.text({ Text = src.title, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(52, 9), Size = UDim2.new(1, -52 - bw - 16, 0, 20), Parent = r })
			Ui.text({ Text = src.detail, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(52, 30), Size = UDim2.new(1, -52 - bw - 16, 0, 16), Parent = r })
			if src.label then
				local kind = src.kind or "green"
				Ui.buy({ Name = "Act", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 1), Size = UDim2.fromOffset(bw, 30), Parent = r }, src.label, kind, if kind == "grey" then nil else src.run, 14)
			end
			y += ROW_H + GAP
		end
		-- The sheet hugs its rows, as the web's panel.
		limit.MaxSize = Vector2.new(W, 61 + 10 + y - GAP + 18)
	end
	draw()
	conn = Remote.changed:Connect(draw)
	overlay.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return overlay
end

return Flat
