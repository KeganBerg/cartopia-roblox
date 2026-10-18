--!strict
-- The joystick over each Pixel Palace (ui/Badges.tsx ArcadeBadge): the arcade games live there,
-- and tapping it opens the Arcade. A merged block gets one, over its anchor. It sits above the
-- building's job badge (the web's 3.3 units up, the job badge's 2.2), bobbing gently.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local merge = require(Game.merge) :: any
local Town = require(script.Parent.Parent.Town)
local Ui = require(script.Parent.Parent.Ui)
local Placement = require(script.Parent.Parent.Placement)

local ArcadeBadge = {}

local MAX_DISTANCE = 900
local LIFT = 11 -- studs above the job badge (1.1 web units)

type Badge = { gui: BillboardGui, face: Frame }
local badges: { [string]: Badge } = {}

local function make(model: Model, parent: Instance, open: () -> ()): Badge
	local gui = Ui.new("BillboardGui", {
		Name = "Arcade",
		Adornee = model.PrimaryPart or model,
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(46, 44),
		StudsOffsetWorldSpace = Vector3.new(0, ((model:GetAttribute("Height") :: number?) or 10) + 4 + LIFT, 0),
		MaxDistance = MAX_DISTANCE,
		ResetOnSpawn = false,
		Parent = parent,
	})
	-- .badge-arcade: a purple-to-pink pill with a white border and a little tail.
	local face = Ui.new("TextButton", { Name = "Joystick", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(40, 32), BackgroundColor3 = Ui.WHITE, ZIndex = 2, Parent = gui }, {
		Ui.corner(16),
		Ui.stroke(3, Ui.WHITE),
		Ui.new("UIGradient", { Rotation = 70, Color = Ui.seq("#7e57c2", "#ec407a") }),
	})
	Ui.text({ Text = "🕹️", TextSize = 20, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = face })
	Ui.new("Frame", { Name = "Tail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 36), Size = UDim2.fromOffset(9, 9), Rotation = 45, BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 1, Parent = gui })
	face.Activated:Connect(open)
	return { gui = gui, face = face :: any }
end

local function update(holder: Instance, open: () -> ())
	local s = store.useGame.getState()
	local f = Town.folder()
	local list = f and f:FindFirstChild("Buildings")
	local seen: { [string]: boolean } = {}
	if s.buildings and list then
		local merges = merge.mergeGroups(s.buildings)
		local shown = not Placement.active()
		for _, b in s.buildings do
			if b.def ~= "arcade" or (merges.owner:has(b.uid) and not merges.groups:has(b.uid)) then
				continue
			end
			local m = list:FindFirstChild(b.uid)
			if not m or not m:IsA("Model") then
				continue
			end
			seen[b.uid] = true
			local badge: Badge? = badges[b.uid]
			if badge and badge.gui.Adornee ~= (m.PrimaryPart or m) then
				badge.gui:Destroy()
				badge = nil
			end
			local shownBadge = badge or make(m, holder, open)
			badges[b.uid] = shownBadge
			if shownBadge.gui.Enabled ~= shown then
				shownBadge.gui.Enabled = shown
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

function ArcadeBadge.start(ctx: any)
	local root: Frame = ctx.gui
	local holder = Ui.new("Folder", { Name = "ArcadeBadges", Parent = root:FindFirstAncestorOfClass("ScreenGui").Parent })
	local function open()
		ctx.open("arcade")
	end
	update(holder, open)
	-- The bob (arc-bob: 3px up and back every 2.4 s).
	RunService.RenderStepped:Connect(function()
		local y = 2 - 3 * (0.5 - 0.5 * math.cos(os.clock() / 2.4 * math.pi * 2))
		for _, b in badges do
			b.face.Position = UDim2.new(0.5, 0, 0, y)
		end
	end)
	while true do
		task.wait(0.5)
		update(holder, open)
	end
end

return ArcadeBadge
