--!strict
-- How this game's menus use UIMotion (the web game's menu and button motion, client/UIMotion):
-- every menu Ui.panel makes rises in and drops away (a sheet from the bottom on phones) with the
-- menu sounds, one menu taking another's place swaps at once with the tab tick, and every button
-- presses, hovers and taps. On top of UIMotion: the dimmed town fades with the menu, the title pops
-- in like a game banner (theme.css head-in), toasts pop, and pictures that keep moving run on one
-- loop each that stops when its screen closes. Reduced Motion (Roblox's settings) keeps it all still.

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local UIMotion = require(script.Parent.UIMotion)
local Sfx = require(script.Parent.Sounds.Sfx)

local Motion = {}

-- UIMotion's sounds, by their web names, through this game's Sfx (and its throttles).
local NAMED: { [string]: () -> () } = {
	["menu-open"] = Sfx.menuOpen,
	["menu-close"] = Sfx.menuClose,
	tab = Sfx.tab,
	click = Sfx.click,
}
UIMotion.useSounds(function(name: string)
	local f = NAMED[name] or (Sfx :: any)[name]
	if type(f) == "function" then
		f()
	else
		Sfx.play(name)
	end
end, function(): number
	return Sfx.lastAt
end)

function Motion.reduced(): boolean
	-- Settings > Reduce motion (client/Prefs), else Roblox's own setting.
	local me = game:GetService("Players").LocalPlayer
	if me and me:GetAttribute("ReduceMotion") == true then
		return true
	end
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

-- Whether frames run (not in the test emulator, where nothing waits on them) and motion is on.
local function live(): boolean
	return RunService:IsRunning() and not Motion.reduced()
end

-- Plays a tween and returns it. style/dir: Enum names ("Quint", "Out").
function Motion.tween(inst: Instance, time: number, goal: { [string]: any }, style: string?, dir: string?): Tween
	local info = TweenInfo.new(time, (Enum.EasingStyle :: any)[style or "Quad"], (Enum.EasingDirection :: any)[dir or "Out"])
	local t = TweenService:Create(inst, info, goal)
	t:Play()
	return t
end

-- The object's own UIScale, shared with UIMotion's.
function Motion.scaleOf(g: GuiObject): UIScale
	local s = g:FindFirstChild("UIMotionScale")
	if s and s:IsA("UIScale") then
		return s
	end
	local n = Instance.new("UIScale")
	n.Name = "UIMotionScale"
	n.Parent = g
	return n
end

-- Set by the HUD while one menu takes another's place: the new one is just there, with the tab tick.
Motion.swapping = false

local function sheetOf(overlay: Instance): (GuiObject?, GuiObject?)
	for _, c in overlay:GetChildren() do
		if c:GetAttribute("MotionSheet") then
			return c :: GuiObject, nil
		end
		if c.Name == "MotionGroup" then
			local s = c:FindFirstChildWhichIsA("GuiObject")
			if s and s:GetAttribute("MotionSheet") then
				return s, c :: GuiObject
			end
		end
	end
	return nil, nil
end

-- While it moves, the sheet rides in a screen-sized CanvasGroup so it fades as a whole, as the web
-- menu does; it comes back out once still, so its words stay sharp.
local function wrap(overlay: GuiObject, sheet: GuiObject): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Name = "MotionGroup"
	g.BackgroundTransparency = 1
	g.AnchorPoint = Vector2.new(0.5, 0.5)
	g.Position = UDim2.fromScale(0.5, 0.5)
	g.Size = UDim2.fromScale(1, 1)
	g.ZIndex = sheet.ZIndex
	g.Parent = overlay
	sheet.Parent = g
	return g
end

-- A menu opening (Ui.panel): the town dims in, the sheet rises in (UIMotion.open) and the title
-- pops in from 55% with a little tilt.
function Motion.panelIn(overlay: GuiObject, sheet: GuiObject, title: GuiObject?)
	local swap = Motion.swapping
	if swap then
		UIMotion.playSfx("tab")
	end
	-- A menu that goes some other way than the HUD's close still counts as closed.
	overlay.Destroying:Connect(function()
		local s, g = sheetOf(overlay)
		local open = g or s
		if open and open:GetAttribute("UIMotionOpen") then
			UIMotion.close(open, nil, { still = true, sound = false })
		end
	end)
	if not live() then
		UIMotion.open(sheet, { still = true, sound = not swap })
		return
	end
	local g = wrap(overlay, sheet)
	UIMotion.open(g, { still = swap or nil, sound = not swap })
	local moving = g.Position ~= UDim2.fromScale(0.5, 0.5)
	if moving then
		local dim = overlay.BackgroundTransparency
		overlay.BackgroundTransparency = 1
		Motion.tween(overlay, UIMotion.Timing.overlayIn, { BackgroundTransparency = dim })
		if title then
			local ts = Motion.scaleOf(title)
			ts.Scale = 0.55
			title.Rotation = -4
			Motion.tween(ts, 0.38, { Scale = 1 }, "Back")
			Motion.tween(title, 0.38, { Rotation = 0 }, "Back")
		end
	end
	task.delay(if moving then UIMotion.Timing.sheetIn + 0.05 else 0, function()
		if g.Parent and sheet.Parent == g and g:GetAttribute("UIMotionOpen") then
			sheet.Parent = overlay
			sheet:SetAttribute("UIMotionOpen", true)
			g:SetAttribute("UIMotionOpen", false)
			g:Destroy()
		end
	end)
end

-- A menu closing: it drops away as the dim fades (UIMotion.close), then it's destroyed. instant:
-- another menu is taking its place, so it goes at once without a sound. Anything that isn't a
-- menu sheet goes at once.
function Motion.panelOut(overlay: Instance, instant: boolean?)
	local sheet, g = sheetOf(overlay)
	if not sheet or not overlay:IsA("GuiObject") then
		overlay:Destroy()
		return
	end
	local function gone()
		overlay:Destroy()
	end
	if instant or not live() then
		UIMotion.close(g or sheet, gone, { still = true, sound = not instant })
		return
	end
	-- No more taps while it goes.
	pcall(function()
		(overlay :: any).Interactable = false
	end)
	local group = g
	if not group then
		local w = wrap(overlay, sheet)
		w:SetAttribute("UIMotionOpen", sheet:GetAttribute("UIMotionOpen"))
		sheet:SetAttribute("UIMotionOpen", false)
		group = w
	end
	Motion.tween(overlay, UIMotion.Timing.overlayOut, { BackgroundTransparency = 1 }, "Quad", "In")
	UIMotion.close(group :: GuiObject, gone)
end

-- Every button under root, now and later, presses, hovers and taps (UIMotion.bindButton). Not
-- the dimmed backdrop or a menu's sheet, invisible tap areas, buttons another UIScale already
-- sizes, or ones marked NoMotion (a button whose position something else moves).
function Motion.bindAll(root: Instance)
	local function try(d: Instance)
		if not d:IsA("GuiButton") or d:GetAttribute("NoMotion") or d:GetAttribute("SinkTaps") or d:GetAttribute("UIMotionBound") then
			return
		end
		if d.BackgroundTransparency >= 1 and #d:GetChildren() == 0 and (not d:IsA("TextButton") or d.Text == "") then
			return
		end
		local other = d:FindFirstChildOfClass("UIScale")
		if other and other.Name ~= "UIMotionScale" then
			return
		end
		UIMotion.bindButton(d)
	end
	for _, d in root:GetDescendants() do
		try(d)
	end
	return root.DescendantAdded:Connect(function(d)
		if d:IsA("GuiButton") then
			-- Once its maker has finished it (attributes are set after it's parented).
			task.defer(try, d)
		end
	end)
end

-- A button made by Ui: bound straight away.
Motion.bindButton = UIMotion.bindButton

-- Something appearing, as the web's toasts do (pop: from 70%, .25s).
function Motion.pop(g: GuiObject, time: number?, from: number?)
	if Motion.reduced() then
		return
	end
	local s = Motion.scaleOf(g)
	s.Scale = from or 0.7
	Motion.tween(s, time or 0.25, { Scale = 1 }, "Back")
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
