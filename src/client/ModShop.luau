--!strict
-- The garage's Mods tab (the web's ModShop): pick a slot, tap a part to try it on the car on the
-- turntable, then fit it. A part bought once for a car goes back on for free.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)

local ModShop = {}

local LINE = Ui.LINE
local SOFT = Color3.fromHex("#607d8b")
local GREEN = Color3.fromHex("#2e7d32")

local STAT_NAME = { power = "Power", grip = "Grip", weight = "Weight" }
local TREAD_NAME = { wet = "🌧️ Rain", snow = "❄️ Snow", dust = "🏜️ Sand" }

-- The slot the tab is on (kept while the garage stays open).
local slot = "spoiler"

-- The car's mods with `tryId` swapped into its slot, for previewing before buying.
function ModShop.withMod(mods: { string }?, tryId: string?): { string }
	local m = tryId and data.modDef(tryId)
	if not m then
		return mods or {}
	end
	local out = {}
	local have: { string } = mods or {}
	for _, id in have do
		local d = data.modDef(id)
		if not d or d.slot ~= m.slot then
			table.insert(out, id)
		end
	end
	table.insert(out, m.id)
	return out
end

-- Back to the first slot, for a fresh visit.
function ModShop.reset()
	slot = "spoiler"
end

local function statLine(m: any): string
	local bits = {}
	if m.tread then
		-- Tires add no PI; they hold the strip in bad weather.
		for _, k in { "wet", "snow", "dust" } do
			local v = m.tread[k]
			if v then
				table.insert(bits, if v < 1 then `{TREAD_NAME[k]} {math.round(v * 100)}%` else TREAD_NAME[k])
			end
		end
	else
		for _, k in { "power", "grip", "weight" } do
			local v = m[k]
			if v and v ~= 0 then
				table.insert(bits, `{if v > 0 then "+" else ""}{v} {STAT_NAME[k]}`)
			end
		end
	end
	return table.concat(bits, " · ")
end

-- Cheapest first, coin parts before gem parts, so each card down the list is a step up.
local function byPrice(a: any, b: any): boolean
	local ga, gb = math.sign(a.bucks), math.sign(b.bucks)
	if ga ~= gb then
		return ga < gb
	end
	if a.bucks ~= b.bucks then
		return a.bucks < b.bucks
	end
	return a.coins < b.coins
end

-- `parent` is the detail card's space under the tabs. `trying`: the part being tried on, or nil.
function ModShop.draw(parent: Instance, ctx: any, car: any, trying: string?, setTrying: (string?) -> ())
	local s = store.useGame.getState()
	local gate = store.gateLevel(s)
	local def = data.carDef(car.model)
	local slots = data.modSlotsFor(def.body)
	local here = false
	for _, x in slots do
		if x.id == slot then
			here = true
		end
	end
	if not here then
		slot = if #slots > 0 then slots[1].id else "spoiler"
	end
	local fit = data.fittedMods(car.mods, def.body)
	local owned: { [string]: boolean } = {}
	for _, id in data.ownedMods(car) do
		owned[id] = true
	end
	local basePi = data.performance(def, car.upgrades, car.mods)
	local info = data.slotInfo(slot, def.body)

	local body = Ui.scroller({ Name = "ModShop", Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = parent })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = body })

	local tabs = Ui.new("Frame", { Name = "Slots", LayoutOrder = 1, Size = UDim2.new(1, -8, 0, 48), BackgroundTransparency = 1, ZIndex = 3, Parent = body }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, x in slots do
		local si = data.slotInfo(x.id, def.body)
		local on = x.id == slot
		local t = Ui.new("TextButton", { Name = x.id, Text = "", AutoButtonColor = false, LayoutOrder = i, Size = UDim2.fromOffset(30, 48), BackgroundColor3 = if on then Color3.fromHex("#fff8e1") else Color3.fromHex("#fafafa"), ZIndex = 3, Parent = tabs }, {
			Ui.corner(10),
			Ui.stroke(2, if on then Color3.fromHex("#ff9f1a") else Color3.fromHex("#e0e0e0")),
		})
		Ui.text({ Text = si.icon, TextSize = 18, Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 20), ZIndex = 3, Parent = t })
		Ui.text({ Text = si.name, Body = true, Weight = "heavy", TextSize = 9, TextColor3 = if on then Color3.fromHex("#263238") else Color3.fromHex("#455a64"), TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(1, 28), Size = UDim2.new(1, -2, 0, 14), ZIndex = 3, Parent = t })
		if fit[x.id] then
			Ui.new("Frame", { Name = "Dot", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.fromHex("#43a047"), ZIndex = 3, Parent = t }, { Ui.round() })
		end
		t.Activated:Connect(function()
			slot = x.id
			setTrying(nil)
		end)
	end
	Ui.text({ Text = info.stat, Body = true, TextSize = 13, TextColor3 = SOFT, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Size = UDim2.new(1, -8, 0, 20), ZIndex = 3, Parent = body })

	local list = {}
	for _, m in data.MODS do
		if m.slot == slot and data.modFits(m, def.body) then
			table.insert(list, m)
		end
	end
	table.sort(list, byPrice)
	for i, m in list do
		local fitted = fit[slot] == m.id
		local have = owned[m.id] == true
		local locked = not have and gate < m.unlockLevel
		local pi = data.performance(def, car.upgrades, ModShop.withMod(car.mods, m.id))
		local gain = pi - basePi
		local deal = store.modPrice(s, m.id)
		local isTrying = trying == m.id
		local card = Ui.new("TextButton", {
			Name = m.id,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = 10 + i,
			Size = UDim2.new(1, -8, 0, 70),
			BackgroundColor3 = if fitted then Color3.fromHex("#f1f8e9") elseif isTrying then Color3.fromHex("#e3f2fd") else Ui.WHITE,
			ZIndex = 3,
			Parent = body,
		}, {
			Ui.corner(12),
			Ui.stroke(2, if fitted then Color3.fromHex("#66bb6a") elseif isTrying then Color3.fromHex("#42a5f5") else Color3.fromHex("#e0e0e0")),
		})
		local fade = if locked then 0.25 else 0
		Ui.text({ Text = data.modName(m, def.body), TextSize = 15, TextColor3 = Color3.fromHex("#263238"), TextTransparency = fade, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(10, 6), Size = UDim2.new(1, -130, 0, 20), ZIndex = 3, Parent = card })
		Ui.text({ Text = statLine(m), Body = true, Weight = "heavy", TextSize = 12, TextColor3 = GREEN, TextTransparency = fade, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(10, 27), Size = UDim2.new(1, -130, 0, 16), ZIndex = 3, Parent = card })
		local piText = if fitted then `PI {basePi}` else `PI {basePi} → {pi}`
		if not fitted and gain > 0 then
			piText ..= ` <font color="#2e7d32"><b>+{gain}</b></font>`
		end
		local piLabel = Ui.text({ Text = piText, Body = true, TextSize = 12, TextColor3 = SOFT, TextTransparency = fade, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 45), Size = UDim2.new(1, -130, 0, 16), ZIndex = 3, Parent = card })
		piLabel.RichText = true
		card.Activated:Connect(function()
			setTrying(if isTrying or fitted then nil else m.id)
		end)

		local go = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 40), Parent = card }
		local function fitIt()
			local ok, done = Remote.act("modCar", car.uid, m.id)
			if ok and done then
				setTrying(nil)
			end
		end
		local button: TextButton
		if fitted then
			button = Ui.new("TextButton", { Text = "", AutoButtonColor = false, AnchorPoint = go.AnchorPoint, Position = go.Position, Size = UDim2.fromOffset(110, 36), BackgroundColor3 = Color3.fromHex("#c5e1a5"), ZIndex = 3, Parent = card }, { Ui.corner(9) })
			Ui.text({ Text = "✔ Fitted · Take off", Body = true, Weight = "heavy", TextSize = 11, TextColor3 = Color3.fromHex("#33691e"), Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = button })
			button.Activated:Connect(function()
				Remote.act("modCar", car.uid, m.id, true)
				setTrying(nil)
			end)
		elseif have then
			local _shadow, b = Ui.buy(go, "Equip", "green", fitIt, 14)
			button = b
		elseif locked then
			local _shadow, b = Ui.buy(go, `🔒 Level {m.unlockLevel}`, "grey", function()
				Remote.act("modCar", car.uid, m.id)
			end, 13)
			button = b
		elseif m.bucks > 0 then
			local _shadow, b = Ui.button(go, "ten", fitIt, { radius = 12, stroke = 2, drop = 2, dark = 0.2, strokeColor = Color3.fromHex("#4a148c"), text = `💎 {deal.bucks}`, textSize = 14, textShadow = 1.5 })
			button = b
		else
			local price = `${Ui.commas(deal.coins)}`
			if m.parts > 0 then
				price ..= `\n+ {deal.parts}⚙`
			end
			local _shadow, b = Ui.buy(go, price, "green", fitIt, if m.parts > 0 then 12 else 14)
			button = b
		end
		button.Name = "Go"
		button.ZIndex = 3
		if deal.deal and not fitted and not have then
			local tag = Ui.new("Frame", { Name = "Deal", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -86, 0, 2), Size = UDim2.fromOffset(38, 16), BackgroundColor3 = Color3.fromHex("#e53935"), ZIndex = 4, Parent = card }, { Ui.corner(5) })
			Ui.text({ Text = "DEAL", TextSize = 10, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = tag })
		end
	end
	Ui.new("Frame", { LayoutOrder = 999, Size = UDim2.new(1, 0, 0, 6), BackgroundTransparency = 1, Parent = body })
end

return ModShop
