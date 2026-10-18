--!strict
-- The garage's Hats tab (the web's HatShop): tap a hat to try it on the car on the turntable, pick
-- its colours, then wear it from the bar on top. Hats are never bought: one you don't have shows
-- how it's won (its challenge's progress, or 📦 for crates).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local hats = require(Game.hats) :: any
local classes = require(Game.classes) :: any
local Paint = require(ReplicatedStorage.Shared.Models.Paint)
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)

local HatShop = {}

local LINE = Ui.LINE
local SOFT = Color3.fromHex("#607d8b")

-- Whether the two-colour switch is on for the cap being tried (the web keeps it per visit).
local twoTone: boolean? = nil
local toneFor: string? = nil

-- How a hat you don't have is won: its challenge's icon and progress, or 🔒 📦 for crates only.
local function how(d: any, n: number): string
	local c = d.challenge
	if not c then
		return "🔒 📦"
	end
	local cls = if c.cls then classes.carClass(c.cls).icon else ""
	return `{c.icon}{cls} {math.min(n, c.goal)}/{c.goal}`
end

local function hint(d: any): string
	local bits = { d.name }
	if d.challenge then
		table.insert(bits, `{d.challenge.name}: {d.challenge.text}`)
	end
	if d.crates and #d.crates > 0 then
		table.insert(bits, if d.challenge then "or found in crates" else "Found in crates")
	end
	return table.concat(bits, " · ")
end

local function header(parent: Instance, order: number, text: string, note: string?)
	local row = Ui.new("Frame", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 26), BackgroundTransparency = 1, ZIndex = 3, Parent = parent }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	Ui.text({ Text = text, TextSize = 16, TextColor3 = LINE, LayoutOrder = 1, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = row })
	if note then
		Ui.text({ Text = note, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = SOFT, LayoutOrder = 2, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = row })
	end
end

local function grid(parent: Instance, order: number, cell: UDim2, pad: number): Frame
	return Ui.new("Frame", { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3, Parent = parent }, {
		Ui.new("UIGridLayout", { CellSize = cell, CellPadding = UDim2.fromOffset(pad, pad), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }),
	})
end

local function swatches(parent: Instance, order: number, prefix: string, colors: { string }, on: string, pick: (string) -> ())
	local g = grid(parent, order, UDim2.fromOffset(32, 32), 8)
	for i, c in colors do
		local sel = c == on
		local d = Ui.new("TextButton", { Name = prefix .. c, Text = "", AutoButtonColor = false, LayoutOrder = i, BackgroundColor3 = Color3.fromHex(c), ZIndex = 3, Parent = g }, {
			Ui.round(),
			Ui.stroke(if sel then 3 else 1, if sel then Color3.fromHex("#ff9f1a") else Color3.fromHex("#90a4ae")),
		})
		Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 3, Parent = d }, { Ui.round(), Ui.stroke(2.5, Ui.WHITE) })
		d.Activated:Connect(function()
			pick(c)
		end)
	end
end

-- Back to the hat the car wears, for a fresh visit.
function HatShop.reset()
	twoTone = nil
	toneFor = nil
end

-- `parent` is the detail card's space under the tabs. `trying`: the hat being tried (false: trying
-- no hat; nil: nothing tried). `setTrying(nil)` stops trying.
function HatShop.draw(parent: Instance, ctx: any, car: any, trying: any, setTrying: (any) -> ())
	local s = store.useGame.getState()
	local owned: { [string]: boolean } = {}
	local count = 0
	for _, id in hats.ownedHats(s) do
		if not owned[id] then
			owned[id] = true
			count += 1
		end
	end
	local now = hats.cleanHat(car.hat)
	local pick = if trying == nil then now elseif trying == false then nil else trying
	local d = hats.hatDef(pick and pick.id)
	local changed = trying ~= nil and not hats.sameHat(if trying == false then nil else trying, now)
	local function tryOn(h: any)
		if hats.sameHat(h, now) then
			setTrying(nil)
		else
			setTrying(if h == nil then false else h)
		end
	end
	local function wear()
		local ok = Remote.act("hatCar", car.uid, pick)
		if ok then
			ctx.toast(if pick then `{d.icon} {d.name} on!` else "Hat off")
			setTrying(nil)
		end
	end
	local quest = { stats = s.stats or {}, hatQuest = s.hatQuest }

	local body = Ui.scroller({ Name = "HatShop", Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = parent })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

	if changed then
		local bar = Ui.new("Frame", { Name = "TryBar", LayoutOrder = 1, Size = UDim2.new(1, -8, 0, 46), BackgroundColor3 = Color3.fromHex("#fff8e1"), ZIndex = 3, Parent = body }, {
			Ui.corner(12),
			Ui.stroke(1.5, Color3.fromHex("#ffcc80")),
		})
		local what = Ui.text({ Text = if d then `{d.icon} <b>{d.name}</b>` else "No hat", Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#37474f"), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -230, 1, 0), ZIndex = 3, Parent = bar })
		what.RichText = true
		local undo = Ui.new("TextButton", { Name = "Undo", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -124, 0.5, 0), Size = UDim2.fromOffset(52, 30), BackgroundTransparency = 1, ZIndex = 3, Parent = bar })
		Ui.text({ Text = "<u>Undo</u>", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = undo }).RichText = true
		undo.Activated:Connect(function()
			setTrying(nil)
		end)
		local go = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 32), Parent = bar }
		if not d then
			local _, b = Ui.buy(go, "Take off", "green", wear, 15)
			b.Name = "Go"
			b.ZIndex = 3
		elseif owned[d.id] then
			local _, b = Ui.buy(go, "Wear", "green", wear, 15)
			b.Name = "Go"
			b.ZIndex = 3
		else
			local chip = Ui.new("TextButton", { Name = "How", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 30), BackgroundColor3 = Color3.fromHex("#eceff1"), ZIndex = 3, Parent = bar }, { Ui.corner(10) })
			Ui.text({ Text = how(d, hats.hatProgress(d, quest)), Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex("#37474f"), Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = chip })
			chip.Activated:Connect(function()
				ctx.toast(hint(d))
			end)
		end
	end

	header(body, 2, "Hats", `{count}/{#hats.HATS}`)
	local g = grid(body, 3, UDim2.fromOffset(84, 98), 6)
	local function cell(order: number, name: string, sel: boolean, mine: boolean, label: string, foot: string, thumb: (Instance) -> (), onTap: () -> ())
		local b = Ui.new("TextButton", { Name = name, Text = "", AutoButtonColor = false, LayoutOrder = order, BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = g }, {
			Ui.corner(12),
			Ui.stroke(if sel then 2.5 else 1.5, if sel then Ui.BLUE else Color3.fromHex("#dfe5ea")),
		})
		local art = Ui.new("Frame", { Name = "Art", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(56, 50), BackgroundTransparency = 1, ZIndex = 3, Parent = b })
		thumb(art)
		if not mine then
			for _, c in art:GetDescendants() do
				if c:IsA("ViewportFrame") then
					c.ImageTransparency = 0.45
				elseif c:IsA("TextLabel") then
					c.TextTransparency = 0.45
				end
			end
		end
		Ui.text({ Text = label, TextSize = 12, TextColor3 = Color3.fromHex("#37474f"), TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(3, 56), Size = UDim2.new(1, -6, 0, 18), ZIndex = 3, Parent = b })
		Ui.text({ Text = foot, Body = true, Weight = "heavy", TextSize = 11, TextColor3 = if foot == "✔" then Color3.fromHex("#2e7d32") else SOFT, Position = UDim2.fromOffset(0, 75), Size = UDim2.new(1, 0, 0, 16), ZIndex = 3, Parent = b })
		b.Activated:Connect(onTap)
	end
	cell(0, "nohat", pick == nil, true, "None", "", function(art)
		Ui.text({ Text = "∅", TextSize = 30, TextColor3 = SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = art })
	end, function()
		tryOn(nil)
	end)
	for i, h in hats.HATS do
		local mine = owned[h.id] == true
		local shown = if pick and pick.id == h.id then pick elseif now and now.id == h.id then now else { id = h.id }
		cell(i, h.id, pick ~= nil and pick.id == h.id, mine, h.name, if mine then "✔" else how(h, hats.hatProgress(h, quest)), function(art)
			local t = Thumb.hat(Paint.hatName(shown) :: string, UDim2.fromScale(1, 1), h.icon)
			t.ZIndex = 3
			t.Parent = art
		end, function()
			tryOn(if pick and pick.id == h.id then pick else shown)
		end)
	end

	-- Colours for the hat being tried: swatches, and for caps a one or two colour switch.
	local choices = if d then hats.hatChoices(d) else nil
	if d and pick and choices then
		local paint = hats.hatPaint(pick)
		local a, b = paint[1], paint[2] or paint[1]
		local function set(colors: { string })
			tryOn(hats.cleanHat({ id = d.id, colors = colors }))
		end
		if d.colors ~= "twoTone" then
			header(body, 4, "Colour")
			swatches(body, 5, "Hat", choices, a, function(c)
				set({ c })
			end)
		else
			if twoTone == nil or toneFor ~= d.id then
				twoTone = a ~= b
				toneFor = d.id
			end
			local second = b
			if b == a then
				second = if d.base[2] and d.base[2] ~= a then d.base[2] else (if choices[1] ~= a then choices[1] else choices[2])
			end
			local tone = Ui.new("Frame", { LayoutOrder = 4, Size = UDim2.new(1, -8, 0, 36), BackgroundColor3 = Ui.SEG, ZIndex = 3, Parent = body }, {
				Ui.corner(10),
				Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingRight = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }),
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			local opts: { { name: string, label: string, two: boolean } } = { { name = "OneColour", label = "1 colour", two = false }, { name = "TwoColours", label = "2 colours", two = true } }
			for i, opt in opts do
				local on = twoTone == opt.two
				local t = Ui.new("TextButton", { Name = opt.name, Text = "", AutoButtonColor = false, LayoutOrder = i, Size = UDim2.fromOffset(60, 30), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = if on then 0 else 1, ZIndex = 3, Parent = tone }, { Ui.corner(8) })
				Ui.text({ Text = opt.label, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = if on then LINE else SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = t })
				t.Activated:Connect(function()
					twoTone = opt.two
					set(if twoTone then { a, second } else { a })
				end)
			end
			header(body, 5, if twoTone then "Top" else "Colour")
			swatches(body, 6, "Top", choices, a, function(c)
				set(if twoTone then { c, second } else { c })
			end)
			if twoTone then
				header(body, 7, "Front & brim")
				swatches(body, 8, "Brim", choices, second, function(c)
					set({ a, c })
				end)
			end
		end
	end
	Ui.new("Frame", { LayoutOrder = 9, Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, Parent = body })
end

return HatShop
