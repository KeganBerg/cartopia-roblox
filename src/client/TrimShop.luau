--!strict
-- The garage's Trim tab (the web's TrimShop, game/trim.ts): window tint, headlight colour and door
-- handles, tried on the car on the turntable first and bought together from the bar on top; and
-- three saved looks (paint, panels and trim) to put on any car.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local trim = require(Game.trim) :: any
local Remote = require(script.Parent.Remote)
local Thumb = require(script.Parent.Thumb)
local Ui = require(script.Parent.Ui)

local TrimShop = {}

local LINE = Ui.LINE
local SOFT = Color3.fromHex("#607d8b")

-- Whether two trims are the same once tidied.
function TrimShop.same(a: any, b: any): boolean
	return trim.sameTrim(a, b)
end

local function header(parent: Instance, order: number, text: string)
	Ui.text({ Name = "H" .. order, Text = text, TextSize = 16, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 24), ZIndex = 3, Parent = parent })
end

local function grid(parent: Instance, order: number, cell: UDim2, pad: number): Frame
	return Ui.new("Frame", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3, Parent = parent }, {
		Ui.new("UIGridLayout", { CellSize = cell, CellPadding = UDim2.fromOffset(pad, pad), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }),
	})
end

-- `parent` is the detail card's space under the tabs. `want`: the trim being tried (the car's own
-- when nothing is); `setTrim(nil)` stops trying.
function TrimShop.draw(parent: Instance, ctx: any, car: any, want: any, setTrim: (any) -> ())
	local s = store.useGame.getState()
	local level = s.level
	local bike = data.isBike(data.carDef(car.model).body)
	local now = trim.tidyTrim(car.trim)
	local changed = not trim.sameTrim(want, now)
	local cost = trim.trimCost(now, want)
	local lock = trim.trimLocked(level, now, want)
	local function pick(kind: string, id: string)
		local next = table.clone(want or {})
		next[kind] = id
		local tidy = trim.tidyTrim(next)
		setTrim(if trim.sameTrim(tidy, now) then nil else (tidy or {}))
	end

	local body = Ui.scroller({ Name = "TrimShop", Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = parent })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

	if changed then
		local bar = Ui.new("Frame", { Name = "TryBar", LayoutOrder = 1, Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = Color3.fromHex("#fff8e1"), ZIndex = 3, Parent = body }, {
			Ui.corner(12),
			Ui.stroke(1.5, Color3.fromHex("#ffcc80")),
		})
		local what = Ui.text({ Text = "Trying <b>new trim</b>", Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#37474f"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -230, 1, 0), ZIndex = 3, Parent = bar })
		what.RichText = true
		local undo = Ui.new("TextButton", { Name = "Undo", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -140, 0.5, 0), Size = UDim2.fromOffset(52, 30), BackgroundTransparency = 1, ZIndex = 3, Parent = bar })
		Ui.text({ Text = "<u>Undo</u>", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = undo }).RichText = true
		undo.Activated:Connect(function()
			setTrim(nil)
		end)
		local go = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(126, 32), Parent = bar }
		local label = if lock then `🔒 Level {lock.level}` elseif cost > 0 then `${Ui.commas(cost)}` else "Free"
		local _shadow, button = Ui.buy(go, label, if lock then "grey" else "green", function()
			if lock then
				ctx.toast(`{lock.name} unlocks at level {lock.level}`)
				return
			end
			if s.coins < cost then
				ctx.open("need", { res = "coins", missing = cost - s.coins, what = "that trim" })
				return
			end
			local ok, done = Remote.act("setTrim", car.uid, want or {})
			if ok and done then
				ctx.toast("Looking sharp! ✨")
				setTrim(nil)
			end
		end, 14)
		button.Name = "Go"
		button.ZIndex = 3
	end

	-- Bikes have no windows or doors: only the headlight.
	local order = 2
	for _, k in trim.TRIM_KINDS do
		if bike and k.id ~= "lights" then
			continue
		end
		local kind: string = k.id
		header(body, order, k.name)
		local g = grid(body, order + 1, UDim2.fromOffset(74, 74), 6)
		g.Name = k.id
		order += 2
		for i, d in k.list do
			local on = ((want and want[k.id]) or "stock") == d.id
			local had = ((now and now[k.id]) or "stock") == d.id
			local locked = d.level ~= nil and level < d.level and not had
			local b = Ui.new("TextButton", { Name = `{k.id}:{d.id}`, Text = "", AutoButtonColor = false, LayoutOrder = i, BackgroundColor3 = Ui.WHITE, BackgroundTransparency = if locked then 0.4 else 0, ZIndex = 3, Parent = g }, {
				Ui.corner(10),
				Ui.stroke(if on then 2.5 else 1.5, if on then Color3.fromHex("#ff9f1a") else Color3.fromHex("#dfe5ea")),
			})
			-- A chip in the pick's colour: a pane of glass, a lamp, or a handle.
			local chip = Ui.new("Frame", { Name = "Chip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = if kind == "lights" then UDim2.fromOffset(24, 24) elseif kind == "handles" then UDim2.fromOffset(40, 12) else UDim2.fromOffset(44, 24), BackgroundColor3 = Color3.fromHex(if d.color ~= "" then d.color else car.color), BackgroundTransparency = if kind == "tint" then 1 - d.opacity else 0, ZIndex = 3, Parent = b }, {
				if kind == "lights" then Ui.round() else Ui.corner(if kind == "handles" then 6 else 5),
				Ui.stroke(1, Color3.fromHex("#90a4ae")),
			})
			if kind == "lights" then
				Ui.new("UIStroke", { Thickness = 3, Color = Color3.fromHex(d.color), Transparency = 0.6, Parent = chip })
			end
			Ui.text({ Text = d.name, TextSize = 12, TextColor3 = Color3.fromHex("#37474f"), TextTransparency = if locked then 0.3 else 0, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, 38), Size = UDim2.new(1, -4, 0, 14), ZIndex = 3, Parent = b })
			local foot = if locked then `🔒 Lv {d.level}` elseif had then "✔" elseif d.coins > 0 then `${Ui.commas(d.coins)}` else "Free"
			Ui.text({ Text = foot, Body = true, Weight = "heavy", TextSize = 11, TextColor3 = SOFT, Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 14), ZIndex = 3, Parent = b })
			b.Activated:Connect(function()
				if locked then
					ctx.toast(`{d.name} unlocks at level {d.level}`)
					return
				end
				pick(k.id, d.id)
			end)
		end
	end

	-- Saved looks: three slots to save this car's whole look in, or put a saved one on it at the
	-- usual prices.
	header(body, order, "Saved looks")
	local slots = Ui.new("Frame", { Name = "Presets", LayoutOrder = order + 1, Size = UDim2.new(1, -8, 0, 132), BackgroundTransparency = 1, ZIndex = 3, Parent = body }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local presets = s.presets or {}
	for i = 0, trim.PRESET_SLOTS - 1 do
		local p = presets[i + 1]
		local box = Ui.new("Frame", { Name = `Slot{i + 1}`, LayoutOrder = i, Size = UDim2.new(0, 60, 1, 0), BackgroundColor3 = if p then Ui.WHITE else Color3.fromHex("#f5f7f9"), ZIndex = 3, Parent = slots }, {
			Ui.corner(10),
			Ui.stroke(1.5, Color3.fromHex("#dfe5ea")),
		})
		local function act(name: string, ...: any)
			Remote.act(name, ...)
			setTrim(nil)
		end
		if p then
			local look = Thumb.car(car.model, UDim2.new(1, -8, 0, 84), { color = p.color, finish = p.finish, stripe = p.stripe }, nil, nil, p.panels, p.trim)
			look.Position = UDim2.fromOffset(4, 4)
			look.ZIndex = 3
			look.Parent = box
			local row = Ui.new("Frame", { Position = UDim2.new(0, 4, 1, -38), Size = UDim2.new(1, -8, 0, 32), BackgroundTransparency = 1, ZIndex = 3, Parent = box }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			local _a, use = Ui.buy({ Size = UDim2.fromOffset(40, 30), LayoutOrder = 1, Parent = row }, "Use", "green", function()
				act("applyPreset", i, car.uid)
			end, 13)
			use.Name = "Use"
			local _b, save = Ui.buy({ Size = UDim2.fromOffset(30, 30), LayoutOrder = 2, Parent = row }, "💾", "garage", function()
				act("savePreset", i, car.uid)
			end, 13)
			save.Name = "Save"
			local _c, clear = Ui.buy({ Size = UDim2.fromOffset(30, 30), LayoutOrder = 3, Parent = row }, "✕", "grey", function()
				act("clearPreset", i)
			end, 13)
			clear.Name = "Clear"
		else
			local _d, save = Ui.buy({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -12, 0, 34), Parent = box }, "💾 Save look", "garage", function()
				act("savePreset", i, car.uid)
			end, 13)
			save.Name = "Save"
		end
	end
end

return TrimShop
