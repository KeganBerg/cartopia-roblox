--!strict
-- Little effects, as the web game's ui/Fly.tsx: a reward's coins, gems, parts and XP pop off the
-- button that collected them and fly into their HUD counters; and the soft amber pulse round
-- something ready to collect (the web's chest-glow).

local TweenService = game:GetService("TweenService")

local Ui = require(script.Parent.Ui)
local Icons = require(script.Parent.Icons)

local Fly = {}

local FACE = { coins = "$", parts = "⚙️", xp = "★", bucks = "💎" }
local ORDER = { "coins", "bucks", "parts", "xp" }

-- amounts: { coins, bucks, parts, xp } (what the reward pays). ctx.flyTarget(res) is the HUD
-- counter each lands on; nothing flies where the HUD has none.
function Fly.from(ctx: any, source: GuiObject, amounts: { [string]: any })
	local layer = ctx.gui and (ctx.gui :: Instance).Parent
	if not layer or not ctx.flyTarget then
		return
	end
	-- (Where things are on screen is only known once Roblox has laid them out.)
	local ok, from = pcall(function()
		return source.AbsolutePosition + source.AbsoluteSize / 2
	end)
	if not ok then
		return
	end
	local delay = 0
	for _, res in ORDER do
		local n = amounts[res]
		local target = ctx.flyTarget(res) :: GuiObject?
		if type(n) ~= "number" or n <= 0 or not target then
			continue
		end
		local to = target.AbsolutePosition + target.AbsoluteSize / 2
		-- A few of each, more for a bigger reward (as the web, never a flood).
		local count = math.clamp(math.ceil(math.log10(n + 1)), 1, 5)
		for i = 1, count do
			local bit: GuiObject
			if res == "coins" then
				bit = Ui.new("Frame", { Name = "Fly", BackgroundTransparency = 1, Size = UDim2.fromOffset(22, 22) })
				Icons.draw("coin", bit, 22)
			else
				bit = Ui.text({ Name = "Fly", Text = FACE[res], TextSize = 20, TextColor3 = if res == "xp" then Color3.fromHex("#ffd54f") else Ui.WHITE, Size = UDim2.fromOffset(22, 22) })
			end
			bit.AnchorPoint = Vector2.new(0.5, 0.5)
			bit.Position = UDim2.fromOffset(from.X, from.Y)
			bit.ZIndex = 60
			bit.Parent = layer
			-- Pop out in a little fountain, hang a beat, then whoosh to the counter.
			local a = math.pi * (1.15 + 0.7 * math.random())
			local spread = 30 + math.random() * 34
			local pop = UDim2.fromOffset(from.X + math.cos(a) * spread, from.Y + math.sin(a) * spread * 0.9)
			local start = delay + (i - 1) * 0.045
			task.delay(start, function()
				if not bit.Parent then
					return
				end
				TweenService:Create(bit, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = pop }):Play()
				task.wait(0.4)
				local whoosh = TweenService:Create(bit, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(to.X, to.Y) })
				whoosh:Play()
				whoosh.Completed:Wait()
				bit.Visible = false
			end)
			-- Gone once it has landed (or in any case, should a tween never finish).
			task.delay(start + 1.5, function()
				bit:Destroy()
			end)
		end
		delay += 0.12
	end
end

-- An amber ring that breathes round a frame (radius: its corners) while it's ready to collect.
function Fly.glow(frame: GuiObject, radius: number, color: Color3?): Frame
	local ring = Ui.new("Frame", { Name = "Glow", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = frame }, { Ui.corner(radius) })
	local stroke = Ui.stroke(4, color or Color3.fromHex("#ffb300"), 1)
	stroke.Parent = ring
	TweenService:Create(stroke, TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.7 }):Play()
	return ring
end

return Fly
