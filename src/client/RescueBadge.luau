--!strict
-- The badge over Rusty's Rescue, as the web game's RescueBadge (ui/Badges.tsx): "🚗 Ready!" on
-- cream when a restored car waits in a bay, "🔧 3m 20s" while Rusty works on one, and "🔍 Find
-- cars" when both bays are empty. With two bays it shows a finished car first, else the one
-- finishing soonest. Tapping it taps the building, which opens Rusty's.
--
-- Built like Jobs' bubbles (a BillboardGui over the building's model, by its Uid attribute), each
-- badge made once and only its text and colours changed by the update loop.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local Remote = require(script.Parent.Remote)
local Town = require(script.Parent.Town)
local Ui = require(script.Parent.Ui)
local Placement = require(script.Parent.Placement)

local RescueBadge = {}

local MAX_DISTANCE = 900
local H = 26

type Badge = {
	gui: BillboardGui,
	shadow: Frame,
	face: Frame,
	tail: Frame,
	label: TextLabel,
	look: string,
}
local badges: { [string]: Badge } = {}

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

-- Timers as the web's fmt: 45s, 3m 20s.
local function fmt(sec: number): string
	if sec >= 60 then
		return string.format("%dm %02ds", sec // 60, sec % 60)
	end
	return `{sec}s`
end

-- The bay to show: a finished car first, else the one finishing soonest (nil: both empty).
function RescueBadge.pick(s: any): any
	local best: any = nil
	for _, r in { s.restoring, s.restoring2 } do
		if r and (not best or r.endsAt < best.endsAt) then
			best = r
		end
	end
	return best
end

-- The badge's look and text: "ready", "working" or "find".
function RescueBadge.look(s: any, t: number): (string, string)
	local r = RescueBadge.pick(s)
	if r and t >= r.endsAt then
		return "ready", "🚗 Ready!"
	elseif r then
		return "working", `🔧 {fmt(math.ceil((r.endsAt - t) / 1000))}`
	end
	return "find", "🔍 Find cars"
end

-- Each look's fill and its text colour (badge-ready, badge-rescue).
local LOOKS = {
	ready = { top = "#fff8e1", bottom = "#ffecb3", text = "#5d4037" },
	working = { top = "#fff3e0", bottom = "#fff3e0", text = "#5d4037" },
	find = { top = "#fff3e0", bottom = "#fff3e0", text = "#5d4037" },
}

local function make(uid: string, model: Model, parent: Instance): Badge
	local gui = Ui.new("BillboardGui", {
		Name = "Rescue",
		Adornee = model.PrimaryPart or model,
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(150, 40),
		StudsOffsetWorldSpace = Vector3.new(0, ((model:GetAttribute("Height") :: number?) or 10) + 4, 0),
		MaxDistance = MAX_DISTANCE,
		ResetOnSpawn = false,
		Parent = parent,
	})
	local shadow, face = Ui.shadowed({ Name = "Badge", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(110, H), Parent = gui }, {
		radius = 16,
		stroke = 2.5,
		drop = 3,
		dark = 0.3,
		color = Ui.WHITE,
		class = "TextButton",
	})
	local grad = Ui.gradient("#fff3e0", "#fff3e0")
	grad.Parent = face
	-- The tail: a turned square, half hidden behind the badge, as the job bubbles'.
	local tail = Ui.new("Frame", { Name = "Tail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromOffset(11, 11), Rotation = 45, BackgroundColor3 = Color3.fromHex("#fff3e0"), BorderSizePixel = 0, ZIndex = 0, Parent = shadow }, {
		Ui.corner(2),
		Ui.stroke(2.5),
	})
	local label = Ui.text({ Name = "Label", Text = "", TextSize = 14, TextColor3 = Color3.fromHex("#5d4037"), Size = UDim2.fromScale(1, 1), Parent = face })
	-- What the tutorial's pointing hand looks for (client/Popups/Tutorial).
	face:SetAttribute("Tut", "rescue")
	;(face :: TextButton).Activated:Connect(function()
		Remote.act("tapBuilding", uid)
	end)
	return { gui = gui, shadow = shadow, face = face, tail = tail, label = label, look = "" }
end

local function setLook(b: Badge, look: string, text: string)
	Ui.setText(b.label, text)
	-- The pill hugs its text.
	local w = math.max(56, math.ceil(Ui.textWidth(text, 14)) + 22)
	if b.shadow.Size.X.Offset ~= w then
		b.shadow.Size = UDim2.fromOffset(w, H)
	end
	if b.look == look then
		return
	end
	b.look = look
	local c = LOOKS[look]
	local g = b.face:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = Ui.seq(c.top, c.bottom)
	end
	b.tail.BackgroundColor3 = Color3.fromHex(c.bottom)
	b.label.TextColor3 = Color3.fromHex(c.text)
end

local function modelsByUid(): { [string]: Model }
	local out = {}
	local f = Town.folder()
	local list = f and f:FindFirstChild("Buildings")
	if list then
		for _, m in list:GetChildren() do
			local uid = m:GetAttribute("Uid")
			if type(uid) == "string" and m:IsA("Model") then
				out[uid] = m
			end
		end
	end
	return out
end

local function update(holder: Instance)
	local s = store.useGame.getState()
	if not s.buildings then
		return
	end
	local models = modelsByUid()
	local seen: { [string]: boolean } = {}
	-- Edit mode clears the town of badges, as on the web.
	local shown = not Placement.active()
	local look, text = RescueBadge.look(s, now())
	for _, b in s.buildings do
		if b.def ~= "rescue" then
			continue
		end
		local m = models[b.uid]
		if not m then
			continue
		end
		seen[b.uid] = true
		local badge = badges[b.uid]
		if not badge then
			badge = make(b.uid, m, holder)
			badges[b.uid] = badge
		end
		if badge.gui.Enabled ~= shown then
			badge.gui.Enabled = shown
		end
		setLook(badge, look, text)
	end
	for uid, badge in badges do
		if not seen[uid] then
			badge.gui:Destroy()
			badges[uid] = nil
		end
	end
end

local holder: Folder? = nil

-- Starts the badges, under the player's PlayerGui beside the job bubbles.
function RescueBadge.start(parent: Instance?)
	if holder then
		return
	end
	local where = parent or Players.LocalPlayer:WaitForChild("PlayerGui")
	holder = Ui.new("Folder", { Name = "RescueBadges", Parent = where })
	update(holder :: Folder)
	task.spawn(function()
		while true do
			task.wait(0.25)
			update(holder :: Folder)
		end
	end)
end

-- Brings the badges up to date now rather than on the next tick.
function RescueBadge.refresh()
	if holder then
		update(holder)
	end
end

return RescueBadge
