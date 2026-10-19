--!strict
-- One dyno run after an upgrade or a new part, as the web game's DynoOverlay (ui/Dyno.tsx): laid
-- over the garage's turntable car, the rev counter's needle sweeps up through the gears while the
-- read-out counts the new time and PI up from the old ones, then shows what the work gained
-- ("−0.12s · +3 PI"). Tap anywhere on it to skip. It goes by itself after the pull and a short hold.
--
--   Dyno.show(parent, run, onDone)  -> the overlay (Frame); run = { before = pi, after = pi, model }

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local race = require(Game.race) :: any
local Ui = require(script.Parent.Ui)
local Sfx = require(script.Parent.Sounds.Sfx)

local Dyno = {}

-- How long the pull takes on screen, and how long the result stays up after it.
Dyno.PULL = 2.4
Dyno.HOLD = 1.8
-- The clock the pull and the garage's tap window run on (the emulator pins it, so a slow run
-- neither misses the window nor has to wait out the pull).
Dyno.clock = os.clock

export type Run = { before: number, after: number, model: string? }
type Frame_ = { rpm: number, gear: number, speed: number }

-- The pull's frames (rpm, gear) and its time, from the same racer the races use.
function Dyno.pull(pi: number): ({ Frame_ }, number)
	local frames: { Frame_ } = {}
	local time = race.dynoPull(pi, function(r: any)
		table.insert(frames, { rpm = r.rpm, gear = r.gear, speed = r.speed })
	end)
	return frames, time
end

local function secs(t: number): string
	return string.format("%.2fs", t)
end

-- The gain line: "−0.12s · +3 PI", or "Same time" when the clock didn't move.
function Dyno.gain(beforeTime: number, afterTime: number, before: number, after: number): string
	local saved = beforeTime - afterTime
	local text = if saved > 0.004 then `−{string.format("%.2f", saved)}s` else "Same time"
	if after > before then
		text ..= ` · +{after - before} PI`
	end
	return text
end

-- The rev counter (dyno-gauge): a dark face, nine ticks round from idle to the red, the gear in
-- yellow, and the orange needle on a pale hub.
local function gauge(parent: Instance): (Frame, TextLabel)
	local face = Ui.new("Frame", { Name = "Gauge", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 6, 1, -6), Size = UDim2.fromOffset(72, 72), BackgroundColor3 = Color3.fromHex("#263238"), ZIndex = 4, Parent = parent }, {
		Ui.round(),
		Ui.stroke(2, Color3.fromHex("#eceff1")),
	})
	for i = 0, 8 do
		local a = -120 + i * 28.5
		-- Each tick sits on a spoke turned to its angle; the last two are in the red.
		local spoke = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(64, 64), Rotation = a, BackgroundTransparency = 1, ZIndex = 4, Parent = face })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 1), Size = UDim2.fromOffset(if i >= 7 then 4 else 3, if i >= 7 then 8 else 6), BackgroundColor3 = Color3.fromHex(if i >= 7 then "#ef5350" else "#eceff1"), BorderSizePixel = 0, ZIndex = 4, Parent = spoke }, { Ui.corner(2) })
	end
	local gear = Ui.text({ Name = "Gear", Text = "1", TextSize = 16, TextColor3 = Color3.fromHex("#ffca28"), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 18), Size = UDim2.fromOffset(24, 18), ZIndex = 5, Parent = face })
	local needle = Ui.new("Frame", { Name = "Needle", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(64, 64), Rotation = -120, BackgroundTransparency = 1, ZIndex = 6, Parent = face })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.5, 4), Size = UDim2.fromOffset(4, 30), BackgroundColor3 = Color3.fromHex("#ff7043"), BorderSizePixel = 0, ZIndex = 6, Parent = needle }, { Ui.corner(2) })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(9, 9), BackgroundColor3 = Color3.fromHex("#eceff1"), BorderSizePixel = 0, ZIndex = 7, Parent = face }, { Ui.round() })
	return needle, gear
end

-- One row of the read-out: BEFORE / NOW, the time, the PI.
local function row(parent: Instance, y: number, word: string, color: string): (TextLabel, TextLabel)
	Ui.text({ Text = word, Body = true, Weight = "heavy", TextSize = 10, TextColor3 = Color3.fromHex("#78909c"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(8, y + 3), Size = UDim2.fromOffset(48, 14), ZIndex = 5, Parent = parent })
	local time = Ui.text({ Text = "", TextSize = 15, TextColor3 = Color3.fromHex(color), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(60, y), Size = UDim2.fromOffset(56, 18), ZIndex = 5, Parent = parent })
	local pi = Ui.text({ Text = "", Body = true, Weight = "heavy", TextSize = 11, TextColor3 = Color3.fromHex("#607d8b"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, y + 2), Size = UDim2.fromOffset(46, 16), ZIndex = 5, Parent = parent })
	return time, pi
end

function Dyno.show(parent: Instance, run: Run, onDone: () -> ()): TextButton
	local frames, time = Dyno.pull(run.after)
	local _, beforeTime = Dyno.pull(run.before)
	-- The whole stage is the skip button (.dyno), darkening a little towards the floor.
	local overlay = Ui.new("TextButton", { Name = "Dyno", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0, ZIndex = 4, Parent = parent }, {
		Ui.new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.fromHex("#263238")),
			Transparency = NumberSequence.new(1, 0.72),
		}),
	})
	local tag = Ui.new("Frame", { Name = "Tag", Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(58, 20), BackgroundColor3 = Color3.fromHex("#263238"), ZIndex = 5, Parent = overlay }, { Ui.corner(6) })
	Ui.text({ Text = "D Y N O", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = tag })
	local skip = Ui.new("Frame", { Name = "Skip", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -6, 1, -6), Size = UDim2.fromOffset(62, 20), BackgroundColor3 = Color3.fromHex("#263238"), BackgroundTransparency = 0.4, ZIndex = 5, Parent = overlay }, { Ui.round() })
	local skipText = Ui.text({ Text = "Skip ✕", Body = true, Weight = "heavy", TextSize = 11, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = skip })
	local needle, gearText = gauge(overlay)
	-- The read-out (.dyno-read), top right.
	local read = Ui.new("Frame", { Name = "Read", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 6), Size = UDim2.fromOffset(176, 72), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.08, ZIndex = 5, Parent = overlay }, { Ui.corner(10) })
	local oldTime, oldPi = row(read, 5, "BEFORE", "#90a4ae")
	local newTime, newPi = row(read, 25, "NOW", "#1b5e20")
	oldTime.Text = secs(beforeTime)
	oldPi.Text = `PI {run.before}`
	local gainPill = Ui.new("Frame", { Name = "Gain", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 47), Size = UDim2.fromOffset(60, 18), BackgroundColor3 = Color3.fromHex("#43a047"), Visible = false, ZIndex = 5, Parent = read }, { Ui.round() })
	local gainText = Ui.text({ Text = "", Body = true, Weight = "heavy", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = gainPill })

	local finished = false
	local conn: RBXScriptConnection? = nil
	local function finish()
		if finished then
			return
		end
		finished = true
		if conn then
			conn:Disconnect()
		end
		onDone()
	end
	local function draw(k: number)
		local fr = frames[math.min(#frames, math.floor(k * (#frames - 1)) + 1)] or { rpm = 0, gear = 0, speed = 0 }
		needle.Rotation = -120 + math.min(1.05, fr.rpm) * 228
		Ui.setText(gearText, tostring(fr.gear + 1))
		local done = k >= 1
		Ui.setText(newTime, secs(time * k))
		Ui.setText(newPi, `PI {if done then run.after else math.round(run.before + (run.after - run.before) * math.min(1, k))}`)
		if done and not gainPill.Visible then
			local text = Dyno.gain(beforeTime, time, run.before, run.after)
			gainText.Text = text
			gainPill.Size = UDim2.fromOffset(math.ceil(Ui.textWidth(text, 12)) + 18, 18)
			gainPill.Visible = true
			skipText.TextTransparency = 0.3
		end
	end
	draw(0)
	overlay.Activated:Connect(finish)
	overlay.Destroying:Connect(function()
		finished = true
		if conn then
			conn:Disconnect()
		end
	end)
	-- The engine winds up through the gears for the length of the pull.
	Sfx.arcade.rev(Dyno.PULL)
	local t0 = Dyno.clock()
	local held = false
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((Dyno.clock() - t0) / Dyno.PULL, 0, 1)
		draw(k)
		if k >= 1 and not held then
			held = true
			if conn then
				conn:Disconnect()
			end
			task.delay(Dyno.HOLD, finish)
		end
	end)
	return overlay
end

return Dyno
