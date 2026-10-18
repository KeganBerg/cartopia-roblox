--!strict
-- Rewards flying to the counters (ui/Fly.tsx), a light version: when jobs are collected, coins
-- (and gems, parts and XP stars) pop out of the buildings that paid, hang for a beat, then whoosh
-- into their HUD counters, and a "+120" floats up from the first building.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local Ui = require(script.Parent.Parent.Ui)
local Icons = require(script.Parent.Parent.Icons)
local Remote = require(script.Parent.Parent.Remote)
local Kit = require(script.Parent.Kit)

local Fly = {}

local FLIGHT = 0.9
local FACE = { coins = "$", parts = "⚙", xp = "★", bucks = "💎" }

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

-- Where a building is on screen, in the HUD's own (scaled) coordinates.
local function source(root: GuiObject, scale: number, uid: string): Vector2?
	local towns = workspace:FindFirstChild("Towns")
	local mine = towns and towns:FindFirstChild(Players.LocalPlayer.Name)
	local cam = workspace.CurrentCamera
	if not mine or not cam then
		return nil
	end
	for _, d in mine:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("Uid") == uid then
			local p, on = cam:WorldToViewportPoint(d:GetPivot().Position + Vector3.new(0, 6, 0))
			if not on then
				return nil
			end
			local size = root.AbsoluteSize
			local m = 30
			return Vector2.new(math.clamp(p.X / scale, m, size.X / scale - m), math.clamp(p.Y / scale, m, size.Y / scale - m))
		end
	end
	return nil
end

-- The middle of a HUD counter, in the HUD's coordinates.
local function target(root: GuiObject, scale: number, res: string): Vector2?
	local el: GuiObject? = nil
	local left = root:FindFirstChild("Left")
	if res == "xp" then
		el = left and left:FindFirstChild("Speedo") :: GuiObject?
	else
		local pills = left and left:FindFirstChild("Pills")
		local order = if res == "coins" then 1 elseif res == "bucks" then 2 else 3
		if pills then
			for _, c in pills:GetChildren() do
				if c:IsA("GuiObject") and c.LayoutOrder == order then
					el = c
				end
			end
		end
	end
	if not el then
		return nil
	end
	local at = (el.AbsolutePosition - root.AbsolutePosition) / scale
	-- The speedometer's middle, or the icon at a pill's left end.
	return at + (if res == "xp" then el.AbsoluteSize / scale / 2 else Vector2.new(14, 12))
end

local function piece(layer: Instance, res: string): GuiObject
	if res == "coins" then
		local f = Ui.new("Frame", { Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 46, Parent = layer })
		Icons.draw("coin", f, 24)
		return f
	end
	return Ui.text({ Text = FACE[res], TextSize = 22, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(26, 26), ZIndex = 46, TextColor3 = if res == "xp" then Color3.fromHex("#ffd54f") else Ui.WHITE, Stroke = 1.5, Parent = layer })
end

local function launch(layer: Instance, from: Vector2, to: Vector2, res: string, n: number, delay: number)
	for i = 1, n do
		task.delay(delay + (i - 1) * 0.045, function()
			if layer.Parent == nil then
				return
			end
			local el = piece(layer, res)
			el.Position = UDim2.fromOffset(from.X, from.Y)
			local a = math.pi * (0.15 + 0.7 * math.random()) + math.pi
			local spread = 30 + math.random() * 34
			local b = from + Vector2.new(math.cos(a) * spread, math.sin(a) * spread * 0.9)
			-- Pop out in a little fountain, then whoosh to the counter.
			TweenService:Create(el, TweenInfo.new(FLIGHT * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(b.X, b.Y) }):Play()
			task.delay(FLIGHT * 0.45, function()
				if el.Parent then
					TweenService:Create(el, TweenInfo.new(FLIGHT * 0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(to.X, to.Y) }):Play()
				end
			end)
			task.delay(FLIGHT, function()
				el:Destroy()
			end)
		end)
	end
end

-- "+120" floating up from the building.
local function label(layer: Instance, from: Vector2, text: string)
	local l = Ui.text({ Name = "FlyLabel", Text = text, TextSize = 22, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(from.X, from.Y), Size = UDim2.fromOffset(Ui.textWidth(text, 22) + 10, 26), ZIndex = 47, Stroke = 2, Shadow = 3, Parent = layer })
	TweenService:Create(l, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(from.X, from.Y - 60) }):Play()
	task.delay(1.3, function()
		l:Destroy()
	end)
end

-- Bursts rewards from points (HUD coordinates) to the counters.
function Fly.burst(ctx: any, froms: { Vector2 }, e: { coins: number?, bucks: number?, parts: number?, xp: number? })
	local root = ctx.gui :: GuiObject
	local s = root:FindFirstChildOfClass("UIScale")
	local scale = if s then s.Scale else 1
	local layer = root:FindFirstChild("Fly") or Ui.new("Frame", { Name = "Fly", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 45, Parent = root })
	if #froms == 0 then
		table.insert(froms, root.AbsoluteSize / scale / 2)
	end
	-- Fewer coins each when many buildings pay out at once.
	local each = math.max(2, math.floor(8 / math.sqrt(#froms) + 0.5))
	for i, p in froms do
		local d = (i - 1) * 0.07
		for _, r in { { "coins", each, 0 }, { "bucks", math.max(1, each // 2), 0.08 }, { "parts", math.max(1, each // 3), 0.12 }, { "xp", math.max(1, each // 3), 0.2 } } do
			local res = r[1] :: string
			if ((e :: any)[res] or 0) > 0 then
				local to = target(root, scale, res)
				if to then
					launch(layer, p, to, res, r[2] :: number, d + (r[3] :: number))
				end
			end
		end
	end
	local bits = {}
	if (e.coins or 0) > 0 then
		table.insert(bits, `+{Ui.commas(e.coins :: number)}`)
	end
	if (e.bucks or 0) > 0 then
		table.insert(bits, `+{e.bucks}💎`)
	end
	if (e.parts or 0) > 0 then
		table.insert(bits, `+{e.parts}⚙`)
	end
	if (e.xp or 0) > 0 then
		table.insert(bits, `+{e.xp} XP`)
	end
	if #bits > 0 then
		label(layer, froms[1], table.concat(bits, "  "))
	end
end

function Fly.start(ctx: any)
	local last: any = nil
	local function look()
		local s = store.useGame.getState()
		if s.level == nil then
			return
		end
		local prev = last
		local ends: { [string]: number? } = {}
		for _, b in s.buildings do
			ends[b.uid] = b.jobEndsAt
		end
		last = { coins = s.coins, bucks = s.bucks, parts = s.parts, xp = s.xp, level = s.level, ends = ends }
		if not prev or not Kit.hudUp() then
			return
		end
		-- The buildings whose finished job was just collected.
		local t = now()
		local paid = {}
		for uid, was in prev.ends do
			if was ~= nil and was <= t + 1000 and ends[uid] ~= was then
				table.insert(paid, uid)
			end
		end
		if #paid == 0 then
			return
		end
		local gain = {
			coins = math.max(0, s.coins - prev.coins),
			bucks = math.max(0, s.bucks - prev.bucks),
			parts = math.max(0, s.parts - prev.parts),
			xp = if s.level == prev.level then math.max(0, s.xp - prev.xp) else 0,
		}
		if gain.coins + gain.bucks + gain.parts + gain.xp == 0 then
			return
		end
		local root = ctx.gui :: GuiObject
		local sc = root:FindFirstChildOfClass("UIScale")
		local froms = {}
		for _, uid in paid do
			local p = source(root, if sc then sc.Scale else 1, uid)
			if p and #froms < 6 then
				table.insert(froms, p)
			end
		end
		Fly.burst(ctx, froms, gain)
	end
	Remote.changed:Connect(look)
	look()
end

return Fly
