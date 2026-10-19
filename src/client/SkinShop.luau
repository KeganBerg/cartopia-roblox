--!strict
-- Skin pickers (the web's Skins.tsx): body skins in the garage's Paint tab, mod skins for the part
-- in a slot in the Mods tab. Tapping a skin tries it on the car on the turntable; owned skins go on
-- free from the bar, gem skins are bought there, and the rest say where they come from.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Skins = require(ReplicatedStorage.Shared.Models.Skins)
local Pictures = require(ReplicatedStorage.Shared.Pictures)
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)

local SkinShop = {}

local LINE = Ui.LINE
local SOFT = Color3.fromHex("#607d8b")

-- Where a locked skin comes from, as a short tag.
local function source(d: any): string
	local u = d.unlock
	if u.level then
		return `🔒 Lv {u.level}`
	elseif u.set then
		for _, s in data.CAR_SETS do
			if s.id == u.set then
				return `📘 {s.name}`
			end
		end
		return "📘 Set"
	elseif u.season then
		return `🏁 Tier {u.season}`
	elseif u.bucks then
		return `💎 {u.bucks}`
	elseif u.event then
		return "📅 Event"
	end
	return "🎁 Crates"
end

-- Paints skin `id`'s swatch (the web's SkinDef.swatch, drawn by tools/models/skins.mjs) into the
-- round frame `c`, with the light sweeping across it every 2.6 seconds (.skin-chip::after). Without
-- a drawn swatch in the build, the swatch's colours as a gradient.
function SkinShop.swatch(c: GuiObject, id: string, swatch: string?)
	local pic = Skins.swatch(id)
	if pic and pic.image ~= 0 then
		local img = Ui.new("ImageLabel", { Name = "Swatch", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, ZIndex = c.ZIndex, Parent = c }, { Ui.round() })
		Pictures.set(img, "Image", pic.image)
	else
		local keys = {}
		for hex in string.gmatch(swatch or "", "#%x%x%x%x?%x?%x?") do
			local ok, col = pcall(Color3.fromHex, hex)
			if ok then
				table.insert(keys, col)
			end
		end
		if #keys > 0 then
			c.BackgroundColor3 = keys[1]
		end
		if #keys > 1 then
			local seq = {}
			for i, col in keys do
				table.insert(seq, ColorSequenceKeypoint.new((i - 1) / (#keys - 1), col))
			end
			Ui.new("UIGradient", { Color = ColorSequence.new(seq), Rotation = 45, Parent = c })
		end
	end
	-- The shine: a soft white band at 115deg, held at one side, sweeping over, held at the other.
	local shine = Ui.new("Frame", { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, ZIndex = c.ZIndex, Parent = c }, { Ui.round() })
	local band = Ui.new("UIGradient", {
		Rotation = 25,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 1), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1) }),
		Offset = Vector2.new(-1, 0),
		Parent = shine,
	})
	TweenService:Create(band, TweenInfo.new(1.04, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 1.56), { Offset = Vector2.new(1, 0) }):Play()
end

-- Puts the drawn swatch of the skin whose CSS swatch is `css` into the round frame `c` (for prize
-- lists that only know the CSS). False when no skin has it or the build has no picture for it.
function SkinShop.picture(c: GuiObject, css: string?): boolean
	if not css then
		return false
	end
	for _, list in { data.SKINS, data.MOD_SKINS, { data.CUSTOM_PAINT } } do
		for _, d in list do
			if d and d.swatch == css then
				local pic = Skins.swatch(d.id)
				if pic and pic.image ~= 0 then
					SkinShop.swatch(c, d.id, css)
					return true
				end
				return false
			end
		end
	end
	return false
end

-- A skin drawn small (.skin-chip): its swatch in a white ring edged in its tier's colour, or the
-- grey "none" chip for no skin. Locked skins are greyed and dimmed.
local function chip(parent: Instance, d: any?, tier: Color3?, locked: boolean)
	local c = Ui.new("Frame", { Name = "Chip", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = Color3.fromHex("#eceff1"), ZIndex = 3, Parent = parent }, {
		Ui.round(),
		Ui.stroke(2, Ui.WHITE),
	})
	if tier then
		-- The tier's ring just outside the white one.
		Ui.new("Frame", { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 7, 1, 7), BackgroundTransparency = 1, ZIndex = 3, Parent = c }, {
			Ui.round(),
			Ui.stroke(1.5, tier),
		})
	end
	if d then
		SkinShop.swatch(c, d.id, d.swatch)
		if locked then
			-- saturate(.35) brightness(.8): a grey wash over it.
			Ui.new("Frame", { Name = "Dim", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#6d7378"), BackgroundTransparency = 0.45, ZIndex = 3, Parent = c }, { Ui.round() })
		end
	end
	return c
end

export type Trying = string | false | nil

-- One picker into the list `parent` at `order`. `trying`: the skin being tried (false: none; nil:
-- not trying). `apply(id)` puts it on (nil takes it off).
local function chooser(parent: Instance, order: number, opts: {
	name: string,
	title: string,
	defs: { any },
	owned: { string },
	now: string?,
	color: string,
	trying: Trying,
	setTrying: (Trying) -> (),
	apply: (string?) -> boolean,
})
	local has: { [string]: boolean } = {}
	for _, id in opts.owned do
		has[id] = true
	end
	local pick = if opts.trying == nil then opts.now elseif opts.trying == false then nil else opts.trying
	local d = nil
	for _, x in opts.defs do
		if x.id == opts.trying then
			d = x
		end
	end
	local changed = opts.trying ~= nil and (opts.trying or nil) ~= opts.now
	local box = Ui.new("Frame", { Name = opts.name, LayoutOrder = order, Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3, Parent = parent }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local head = Ui.new("Frame", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, ZIndex = 3, Parent = box }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.text({ Text = opts.title, TextSize = 16, TextColor3 = LINE, LayoutOrder = 1, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = head })
	Ui.text({ Text = `{#opts.owned}/{#opts.defs}`, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = SOFT, LayoutOrder = 2, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 3, Parent = head })

	if changed then
		local bar = Ui.new("Frame", { Name = "TryBar", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 46), BackgroundColor3 = Color3.fromHex("#fff8e1"), ZIndex = 3, Parent = box }, {
			Ui.corner(12),
			Ui.stroke(1.5, Color3.fromHex("#ffcc80")),
		})
		local tier = d and data.SKIN_TIERS[d.tier]
		local what = Ui.text({ Text = if d and tier then `<b>{d.name}</b> <font color="{tier.color}">{tier.name}</font>` else "Back to plain", Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#37474f"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -230, 1, 0), ZIndex = 3, Parent = bar })
		what.RichText = true
		local undo = Ui.new("TextButton", { Name = "Undo", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -140, 0.5, 0), Size = UDim2.fromOffset(52, 30), BackgroundTransparency = 1, ZIndex = 3, Parent = bar })
		Ui.text({ Text = "<u>Undo</u>", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = SOFT, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = undo }).RichText = true
		undo.Activated:Connect(function()
			opts.setTrying(nil)
		end)
		local function go()
			if opts.apply(if d then d.id else nil) then
				opts.setTrying(nil)
			end
		end
		local at = { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(126, 32), Parent = bar }
		local button
		if not d or has[d.id] then
			local _s, b = Ui.buy(at, if d then "Put on" else "Take off", "green", go, 14)
			button = b
		elseif d.unlock.bucks then
			local _s, b = Ui.button(at, "ten", go, { radius = 12, stroke = 2, drop = 2, dark = 0.2, strokeColor = Color3.fromHex("#4a148c"), text = `💎 {d.unlock.bucks}`, textSize = 14, textShadow = 1.5 })
			button = b
		else
			local _s, b = Ui.buy(at, source(d), "grey", nil, 13)
			button = b
		end
		button.Name = "Go"
		button.ZIndex = 3
	end

	local grid = Ui.new("Frame", { Name = "Skins", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 3, Parent = box }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(62, 66), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 3), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3) }),
	})
	local function option(order2: number, d: any?, name: string, sel: boolean, tier: Color3?, locked: boolean, onTap: () -> ())
		local id = d and d.id
		local b = Ui.new("TextButton", { Name = id or "none", Text = "", AutoButtonColor = false, LayoutOrder = order2, BackgroundColor3 = Ui.WHITE, ZIndex = 3, Parent = grid }, {
			Ui.corner(12),
			Ui.stroke(if sel then 2.5 else 1.5, if sel then Color3.fromHex("#1e88e5") else Color3.fromHex("#dfe5ea")),
		})
		if tier then
			Ui.new("Frame", { Name = "Tier", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -1), Size = UDim2.new(1, -12, 0, 3), BackgroundColor3 = tier, BorderSizePixel = 0, ZIndex = 3, Parent = b }, { Ui.corner(2) })
		end
		local c = chip(b, d, tier, locked)
		if not d then
			Ui.text({ Text = "∅", TextSize = 16, TextColor3 = Color3.fromHex("#90a4ae"), Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = c })
		end
		if locked then
			Ui.text({ Name = "Lock", Text = "🔒", TextSize = 12, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 4), Size = UDim2.fromOffset(14, 14), ZIndex = 4, Parent = b })
		end
		Ui.text({ Text = name, TextSize = 11, TextColor3 = Color3.fromHex("#37474f"), TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(2, 45), Size = UDim2.new(1, -4, 0, 14), ZIndex = 3, Parent = b })
		b.Activated:Connect(onTap)
	end
	option(0, nil, "None", pick == nil, nil, false, function()
		opts.setTrying(if opts.now == nil then nil else false)
	end)
	for i, s in opts.defs do
		local tier = Color3.fromHex(data.SKIN_TIERS[s.tier].color)
		option(i, s, s.name, pick == s.id, tier, not has[s.id], function()
			opts.setTrying(if s.id == opts.now then nil else s.id)
		end)
	end
end

-- Body skins, at the top of the Paint tab (`parent` is its list, `order` the place in it).
function SkinShop.body(parent: Instance, order: number, car: any, color: string, trying: Trying, setTrying: (Trying) -> ())
	local s = store.useGame.getState()
	chooser(parent, order, {
		name = "BodySkins",
		title = "Skins",
		defs = data.SKINS,
		owned = data.ownedSkins({ level = s.level, claimedSets = s.claimedSets, skins = s.skins }),
		now = car.skin,
		color = color,
		trying = trying,
		setTrying = setTrying,
		apply = function(id: string?): boolean
			local ok, done = Remote.act("skinCar", car.uid, id)
			return ok and done == true
		end,
	})
end

-- Mod skins for the part fitted in `slot`, in the Mods tab.
function SkinShop.mod(parent: Instance, order: number, car: any, slot: string, trying: Trying, setTrying: (Trying) -> ())
	local s = store.useGame.getState()
	chooser(parent, order, {
		name = "ModSkins",
		title = "Mod skin",
		defs = data.MOD_SKINS,
		owned = data.ownedModSkins({ level = s.level, claimedSets = s.claimedSets, modSkins = s.modSkins }),
		now = car.modSkin and car.modSkin[slot],
		color = car.color,
		trying = trying,
		setTrying = setTrying,
		apply = function(id: string?): boolean
			local ok, done = Remote.act("skinMod", car.uid, slot, id)
			return ok and done == true
		end,
	})
end

return SkinShop
