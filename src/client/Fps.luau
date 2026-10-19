--!strict
-- Settings > Graphics > FPS counter, as the web game's FpsMeter (ui/FpsMeter.tsx): how many frames
-- a second the game really draws, so a player can tell us a number instead of "laggy", and next to
-- it the slowest frame of the last half second, which is what a stutter feels like. Green at 50
-- and up, yellow from 30, red under. Bottom left, over everything, never in the way of a tap.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Ui = require(script.Parent.Ui)
local Prefs = require(script.Parent.Prefs)

local Fps = {}

-- A frame that waited (the app in the background) isn't one slow frame.
local IDLE = 0.5

-- The readout's words, as the web's.
function Fps.text(fps: number, worst: number): string
	return if worst > 0 then `{fps} fps · {worst} ms` else `{fps} fps`
end

function Fps.color(fps: number): Color3
	return Color3.fromHex(if fps >= 50 then "#9cff57" elseif fps >= 30 then "#ffd54f" else "#ff5252")
end

function Fps.start()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local gui = Ui.new("ScreenGui", { Name = "Fps", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000, Enabled = false, Parent = pg })
	local label = Ui.text({
		Name = "Meter",
		Text = "",
		Body = true,
		Weight = "heavy",
		TextSize = 12,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 8, 1, -100),
		Size = UDim2.fromOffset(110, 18),
		BackgroundColor3 = Ui.BLACK,
		BackgroundTransparency = 0.4,
		Parent = gui,
	})
	Ui.corner(6).Parent = label
	local n, worst, last, t0 = 0, 0, os.clock(), os.clock()
	local conn: RBXScriptConnection? = nil
	local function turn(on: boolean)
		gui.Enabled = on
		if on and not conn then
			n, worst, last, t0 = 0, 0, os.clock(), os.clock()
			label.Text = ""
			conn = RunService.RenderStepped:Connect(function()
				local t = os.clock()
				local gap = t - last
				if gap < IDLE then
					worst = math.max(worst, gap)
				end
				n += 1
				last = t
				if t - t0 >= 0.5 then
					local fps = math.round(n / (t - t0))
					local ms = math.round(worst * 1000)
					label.Text = Fps.text(fps, ms)
					label.TextColor3 = Fps.color(fps)
					label.Size = UDim2.fromOffset(Ui.textWidth(label.Text, 12) + 14, 18)
					n, worst, t0 = 0, 0, t
				end
			end)
		elseif not on and conn then
			conn:Disconnect()
			conn = nil
		end
	end
	turn(Prefs.get().fps)
	Prefs.changed:Connect(function()
		turn(Prefs.get().fps)
	end)
end

return Fps
