--!strict
-- The end of the tutorial (ui/GoalSplash.tsx): the dream car at the top of the ladder, what
-- you're playing for, and what there is to do. Shows once, right after the tutorial's last step
-- (tutorial == the number of steps), after any level-up splash; "Let's go!" finishes the tutorial.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local Remote = require(script.Parent.Parent.Remote)
local Kit = require(script.Parent.Kit)

local GoalSplash = {}

-- ui/Tutorial.tsx TUTORIAL_STEPS: the tutorial's steps; past the last one this shows.
GoalSplash.TUTORIAL_STEPS = 9

local function bldg(id: string): any
	for _, b in data.BUILDINGS do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- A race's picture, as a tile in the race menu's colours with its emoji.
local function shot(icon: string, top: string, bottom: string): (UDim2) -> GuiObject
	return function(size: UDim2): GuiObject
		local f = Ui.new("Frame", { Size = size, BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0 }, { Ui.corner(10), Ui.gradient(top, bottom) })
		Ui.text({ Text = icon, TextSize = 46, Size = UDim2.fromScale(1, 1), Parent = f })
		return f
	end
end
local function building(id: string): (UDim2) -> GuiObject
	return function(size: UDim2): GuiObject
		return Thumb.new("Buildings", id, size)
	end
end

local function due(s: any): boolean
	return s.tutorial == GoalSplash.TUTORIAL_STEPS and not s.levelUp and not s.visiting and (s.mode == nil or s.mode == "play")
end

local function show(ctx: any, done: () -> ())
	local s = store.useGame.getState()
	-- The dream car: the Legends Series prize.
	local dream = data.CARS[#data.CARS]
	local collectable = 0
	for _, c in data.CARS do
		if c.id == "lambo" then
			dream = c
		end
		if not c.season then
			collectable += 1
		end
	end
	local owned, seen = 0, {}
	for _, c in s.cars do
		if not seen[c.model] then
			seen[c.model] = true
			owned += 1
		end
	end
	local won = 0
	for _, g in data.GP_SERIES do
		local r = s.gp and s.gp[g.id]
		if r and (r.clears or 0) > 0 then
			won += 1
		end
	end
	local features = {
		{ name = "Find cars", level = 1, art = building("rescue") },
		{ name = "Race", level = 1, art = shot("🏁", "#8ec9ff", "#4d5560") },
		{ name = "Upgrade", level = 1, art = building("garage") },
		{ name = "Grand Prix", level = data.GP_SERIES[1].unlockLevel, art = shot("🏆", "#ffb547", "#f07b0e") },
		{ name = "Crews", level = (bldg("crew") or { unlockLevel = 1 }).unlockLevel, art = building("crew") },
		{ name = "Arcade", level = (bldg("arcade") or { unlockLevel = 1 }).unlockLevel, art = building("arcade") },
	}

	local overlay: Instance
	local function close()
		if overlay.Parent == nil then
			return
		end
		overlay:Destroy()
		store.useGame.setState({ tutorial = 99 })
		Remote.act("setTutorial", 99)
		done()
	end
	overlay = Kit.overlay(ctx, true)
	local W, CW, CH, GAP = 600, 176, 130, 10
	local h = 80 + 46 + 28 + 36 + 10 + 2 * CH + GAP + 12 + 46 + 16
	local _, card = Kit.card(overlay, W, h, 50)
	-- The dream car rides on the card's top edge.
	local hero = Kit.carThumb(dream.id, UDim2.fromOffset(260, 170), dream.colors[1])
	hero.AnchorPoint = Vector2.new(0.5, 0)
	hero.Position = UDim2.new(0.5, 0, 0, -88)
	hero.ZIndex = 3
	hero.Parent = card
	local y = 80
	Kit.title(card, "Chase the dream", y)
	y += 46
	Kit.line(card, "Collect every car. Become a racing Legend.", y, 18, Color3.fromHex("#37474f"))
	y += 28
	Kit.chips(card, y, { { text = `🚗 {owned} / {collectable}` }, { text = `🏆 {won} / {#data.GP_SERIES}` } }, 18)
	y += 36 + 10
	local left = (W - (3 * CW + 2 * GAP)) / 2
	for i, f in features do
		local c = (i - 1) % 3
		local r = (i - 1) // 3
		local _, face = Kit.itemCard(card, left + c * (CW + GAP), y + r * (CH + GAP), CW, CH, false)
		local locked = s.level < f.level
		local art = f.art(UDim2.new(1, -12, 0, 96))
		art.Position = UDim2.fromOffset(6, 6)
		art.Parent = face
		Ui.text({ Text = f.name, TextSize = 17, TextColor3 = Ui.INK, Position = UDim2.fromOffset(6, 104), Size = UDim2.new(1, -12, 0, 20), Parent = face })
		if locked then
			local label = `🔒 {f.level}`
			local lock = Ui.new("Frame", { Name = "Lock", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(Ui.textWidth(label, 13) + 16, 18), BackgroundColor3 = Color3.fromHex("#455a64"), ZIndex = 3, Parent = face }, { Ui.corner(8) })
			Ui.text({ Text = label, TextSize = 13, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = lock })
			if art:IsA("Frame") then
				art.BackgroundColor3 = Color3.fromHex("#9e9e9e")
			end
		end
	end
	y += 2 * CH + GAP + 12
	Kit.button(card, "Let's go!", 0, y, 220, 44, "green", close)
end

function GoalSplash.start(ctx: any)
	local function look()
		if due(store.useGame.getState()) then
			Kit.push(ctx, "goal", 6, function(done)
				show(ctx, done)
			end, function()
				-- Not over a menu, and after the level-up splash.
				local s = store.useGame.getState()
				return due(s) and not Kit.menuOpen(ctx)
			end)
		end
	end
	Remote.changed:Connect(look)
	look()
end

return GoalSplash
