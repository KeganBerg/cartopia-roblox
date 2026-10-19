--!strict
-- The bubble over a broken-down car on the town's roads, as the web game's badge-flat
-- (ui/Badges.tsx): "🛞 Flat!" for a flat tire, "⛽ No gas!" when it ran dry. Tapping it picks the
-- car and opens its fix-it sheet (Panels/Flat: your Tire Shop or Gas Station, a gas can, Rusty's
-- tow, a mechanic). It follows the stalled car wherever TownLife has it, and isn't shown while the
-- town is being edited or visited, or while the car is off the road.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local Ui = require(script.Parent.Parent.Ui)
local Placement = require(script.Parent.Parent.Placement)
local TownLife = require(script.Parent.Parent.TownLife)

local FlatBadge = {}

local MAX_DISTANCE = 900
local H = 26
local LIFT = 3 -- studs over the car's roof (the web's anchor sits at 1.1 units)

type Badge = { gui: BillboardGui, shadow: Frame, label: TextLabel, model: Model }
local badges: { [string]: Badge } = {}

-- The cars on the town's roads now, uid -> model (swapped in the emulator, which runs no traffic).
FlatBadge.onRoad = function(): { [string]: Model }
	return TownLife.cars()
end

-- The badge's words for a stuck car (nil: it runs fine).
function FlatBadge.text(c: any): string?
	if c.flat then
		return "🛞 Flat!"
	elseif c.lowFuel then
		return "⛽ No gas!"
	end
	return nil
end

local function make(uid: string, model: Model, parent: Instance, open: (string) -> ()): Badge
	local gui = Ui.new("BillboardGui", {
		Name = `Flat:{uid}`,
		Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true),
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(130, 40),
		MaxDistance = MAX_DISTANCE,
		ResetOnSpawn = false,
		Parent = parent,
	})
	-- .badge.badge-flat: pale red with red letters, a white border and the white tail under it.
	local shadow, face = Ui.shadowed({ Name = "Badge", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(90, H), Parent = gui }, {
		radius = 16,
		stroke = 3,
		drop = 3,
		dark = 0.35,
		color = Color3.fromHex("#ffebee"),
		strokeColor = Ui.WHITE,
		class = "TextButton",
	})
	Ui.new("Frame", { Name = "Tail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromOffset(10, 10), Rotation = 45, BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 0, Parent = shadow })
	local label = Ui.text({ Name = "Label", Text = "", TextSize = 14, TextColor3 = Color3.fromHex("#c62828"), Size = UDim2.fromScale(1, 1), Parent = face })
	;(face :: TextButton).Activated:Connect(function()
		open(uid)
	end)
	return { gui = gui, shadow = shadow, label = label, model = model }
end

local function update(holder: Instance, ctx: any, open: (string) -> ())
	local s = store.useGame.getState()
	local seen: { [string]: boolean } = {}
	local shown = not Placement.active() and not ctx.visiting
	if shown and s.cars then
		local onRoad = FlatBadge.onRoad()
		for _, c in s.cars do
			local text = FlatBadge.text(c)
			local m = text and onRoad[c.uid]
			if not text or not m then
				continue
			end
			seen[c.uid] = true
			local badge: Badge? = badges[c.uid]
			if badge and badge.model ~= m then
				badge.gui:Destroy()
				badge = nil
			end
			local b = badge or make(c.uid, m, holder, open)
			badges[c.uid] = b
			-- Over the roof, whatever size the town draws the car at.
			local adornee = b.gui.Adornee :: BasePart?
			if adornee then
				local cf, size = m:GetBoundingBox()
				local lift = cf.Position.Y + size.Y / 2 + LIFT - adornee.CFrame.Position.Y
				if math.abs(b.gui.StudsOffsetWorldSpace.Y - lift) > 0.2 then
					b.gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
				end
			end
			if b.label.Text ~= text then
				Ui.setText(b.label, text :: string)
				b.shadow.Size = UDim2.fromOffset(math.ceil(Ui.textWidth(text :: string, 14)) + 22, H)
			end
		end
	end
	for uid, badge in badges do
		if not seen[uid] then
			badge.gui:Destroy()
			badges[uid] = nil
		end
	end
end

-- The badges now (for the emulator): uid -> the badge's face button.
function FlatBadge.faces(): { [string]: TextButton }
	local out = {}
	for uid, b in badges do
		out[uid] = b.shadow:FindFirstChild("Face") :: TextButton
	end
	return out
end

local refresh: (() -> ())? = nil

-- Brings the badges up to date now rather than on the next tick.
function FlatBadge.refresh()
	if refresh then
		refresh()
	end
end

function FlatBadge.start(ctx: any)
	local root: Frame = ctx.gui
	local holder = Ui.new("Folder", { Name = "FlatBadges", Parent = (root:FindFirstAncestorOfClass("ScreenGui") :: ScreenGui).Parent })
	-- As the web's selectCar then openPanel('flat'): the sheet is for this car.
	local function open(uid: string)
		ctx.open("flat", uid)
	end
	refresh = function()
		update(holder, ctx, open)
	end
	update(holder, ctx, open)
	while true do
		task.wait(0.25)
		update(holder, ctx, open)
	end
end

return FlatBadge
