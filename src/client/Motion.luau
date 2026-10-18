--!strict
-- Menu motion, as the web game's CSS animations: menus rise in and drop away (index.css panel-in
-- and panel-out), their titles pop in like a game banner (theme.css head-in), buttons press down
-- and bounce back up, toasts pop, and pictures that keep moving run on one loop each that stops
-- when its screen closes. Players who turn on Reduced Motion in Roblox's settings get the still
-- screens, as prefers-reduced-motion does on the web.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Motion = {}

function Motion.reduced(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

-- Plays a tween and returns it. style/dir: Enum names ("Quint", "Out").
function Motion.tween(inst: Instance, time: number, goal: { [string]: any }, style: string?, dir: string?): Tween
	local info = TweenInfo.new(time, (Enum.EasingStyle :: any)[style or "Quad"], (Enum.EasingDirection :: any)[dir or "Out"])
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

local function scaleOf(g: GuiObject): UIScale
	local s = g:FindFirstChild("MotionScale")
	if s and s:IsA("UIScale") then
		return s
	end
	local n = Instance.new("UIScale")
	n.Name = "MotionScale"
	n.Parent = g
	return n
end
Motion.scaleOf = scaleOf

-- A menu opening: the town dims in, the sheet rises 24px while growing from 94%, and the title
-- pops in from 55% with a little tilt.
function Motion.panelIn(overlay: GuiObject, sheet: GuiObject, title: GuiObject?)
	if Motion.reduced() then
		return
	end
	local dim = (overlay :: any).BackgroundTransparency
	;(overlay :: any).BackgroundTransparency = 1
	Motion.tween(overlay, 0.2, { BackgroundTransparency = dim })
	local at = sheet.Position
	sheet.Position = at + UDim2.fromOffset(0, 24)
	local s = scaleOf(sheet)
	s.Scale = 0.94
	Motion.tween(sheet, 0.26, { Position = at }, "Quint")
	Motion.tween(s, 0.26, { Scale = 1 }, "Quint")
	if title then
		local ts = scaleOf(title)
		ts.Scale = 0.55
		title.Rotation = -4
		Motion.tween(ts, 0.38, { Scale = 1 }, "Back")
		Motion.tween(title, 0.38, { Rotation = 0 }, "Back")
	end
end

-- A menu closing: the sheet drops 18px and shrinks to 95% as the dim fades, then it's destroyed.
-- Anything that isn't a menu sheet (or with Reduced Motion on) goes at once.
function Motion.panelOut(overlay: Instance)
	local sheet: GuiObject? = nil
	for _, c in overlay:GetChildren() do
		if c:IsA("GuiObject") and c:GetAttribute("MotionSheet") then
			sheet = c
		end
	end
	-- (No frames run outside a live game, as in the test emulator: there it goes at once too.)
	if not sheet or not overlay:IsA("GuiObject") or Motion.reduced() or not RunService:IsRunning() then
		overlay:Destroy()
		return
	end
	-- No more taps while it goes.
	pcall(function()
		(overlay :: any).Interactable = false
	end)
	Motion.tween(overlay, 0.17, { BackgroundTransparency = 1 }, "Quad", "In")
	Motion.tween(sheet, 0.17, { Position = sheet.Position + UDim2.fromOffset(0, 18) }, "Quad", "In")
	Motion.tween(scaleOf(sheet), 0.17, { Scale = 0.95 }, "Quad", "In")
	task.delay(0.18, function()
		overlay:Destroy()
	end)
end

-- Something appearing: pops from `from` (70%) to full size.
function Motion.pop(g: GuiObject, time: number?, from: number?)
	if Motion.reduced() then
		return
	end
	local s = scaleOf(g)
	s.Scale = from or 0.7
	Motion.tween(s, time or 0.25, { Scale = 1 }, "Back")
end

-- A button with a drop shadow: its face goes down onto the shadow while held and bounces back up.
function Motion.pressFace(face: GuiButton, drop: number)
	face:SetAttribute("Pressy", true)
	local down = UDim2.fromOffset(0, -math.max(0, drop - 2))
	local up = UDim2.fromOffset(0, -drop)
	local function release()
		if face.Position ~= up then
			Motion.tween(face, 0.22, { Position = up }, "Back")
		end
	end
	face.MouseButton1Down:Connect(function()
		Motion.tween(face, 0.06, { Position = down })
	end)
	face.MouseButton1Up:Connect(release)
	face.MouseLeave:Connect(release)
end

-- Any other button: squeezes to 95% while held and springs back.
function Motion.pressScale(b: GuiButton)
	b:SetAttribute("Pressy", true)
	local function release()
		local s = b:FindFirstChild("MotionScale") :: UIScale?
		if s and s.Scale ~= 1 then
			Motion.tween(s, 0.25, { Scale = 1 }, "Back")
		end
	end
	b.MouseButton1Down:Connect(function()
		Motion.tween(scaleOf(b), 0.06, { Scale = 0.95 })
	end)
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
end

-- Gives a button in a menu its press, once: shadowed faces press down, other buttons squeeze.
-- Skips buttons that already have one, the dimmed backdrop and sheet, and invisible tap areas.
function Motion.pressable(d: Instance)
	if not d:IsA("GuiButton") or d:GetAttribute("Pressy") or d:GetAttribute("SinkTaps") or d:GetAttribute("NoPress") then
		return
	end
	if d.BackgroundTransparency >= 1 and #d:GetChildren() == 0 and (not d:IsA("TextButton") or d.Text == "") then
		return
	end
	local parent = d.Parent
	if d.Name == "Face" and parent and parent:IsA("Frame") and d.Position.Y.Scale == 0 and d.Position.Y.Offset < 0 then
		Motion.pressFace(d, -d.Position.Y.Offset)
	elseif not d:FindFirstChildOfClass("UIScale") then
		Motion.pressScale(d)
	end
end

-- Runs fn(t, dt) every frame while `owner` is on screen, t in seconds since it started; stops for
-- good once owner leaves the screen. With Reduced Motion on, fn runs once at t = 0.
function Motion.loop(owner: Instance, fn: (number, number) -> ())
	fn(0, 0)
	if Motion.reduced() then
		return
	end
	local t = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		if not owner.Parent then
			conn:Disconnect()
			return
		end
		t += dt
		fn(t, dt)
	end)
	owner.Destroying:Connect(function()
		conn:Disconnect()
	end)
end

return Motion
