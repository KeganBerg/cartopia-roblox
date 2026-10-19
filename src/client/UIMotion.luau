-- UIMotion: Cartopia's menu and button motion, ported from the web game (src/index.css,
-- src/theme.css, src/ui/Menus.tsx, src/game/store.ts, src/lib/sound.ts). Client-only
-- (a LocalScript or a ModuleScript required by one). Copied into the kit by scripts/roblox/export.mjs.
--
--   local UIMotion = require(ReplicatedStorage.CartopiaData.UIMotion)
--   UIMotion.init(require(ReplicatedStorage.CartopiaData.Audio))  -- once, for the sounds
--   UIMotion.open(shopPanel)            -- rise in (a sheet from the bottom on phones) + menu sound
--   UIMotion.close(shopPanel)           -- drop away + menu sound, then Visible = false
--   UIMotion.swap(shopPanel, carsPanel) -- one menu taking another's place: instant + tab tick
--   UIMotion.bindAll(playerGui)         -- every button presses, hovers and taps, now and later
--   UIMotion.pop(rewardIcon)            -- a reward or unlock popping in
--   UIMotion.bump(coinLabel)            -- a number that just changed
--   UIMotion.shake(buyButton)           -- "can't do that" (plays the error sound)
--
-- A panel fades as a whole when it is a CanvasGroup (recommended for every menu); any other
-- GuiObject still slides and scales. Give a panel a dim Frame behind it named "Overlay"
-- (a sibling, same parent) and it fades in and out with the panel, the way the web overlay does.
--
-- In this game (the only changes from the kit's copy): sounds go through client/Sounds/Sfx rather
-- than the kit's Audio map, set with UIMotion.useSounds(play, lastPlayed) (client/Motion does), and
-- a button's tap sound is looked up as it's tapped, as the tap may close its menu.

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")

local UIMotion = {}

-- Timings and easing from the web game's CSS. The web's panel curve, cubic-bezier(.2,1,.3,1),
-- is a fast start with a long soft landing: Quint Out is the closest Roblox easing.
UIMotion.Timing = {
	overlayIn = 0.2, -- .overlay: ov-in .2s ease-out
	overlayOut = 0.17, -- ov-out .17s ease-in
	panelIn = 0.26, -- panel-in .26s cubic-bezier(.2,1,.3,1): from 24px lower, 94% size, transparent
	panelOut = 0.17, -- panel-out .17s ease-in: to 18px lower, 95% size, transparent
	sheetIn = 0.3, -- phones, sheet-in .3s: slides up from below the screen
	sheetOut = 0.17, -- sheet-out .17s ease-in
	stillWindow = 0.25, -- a menu opening within this of another closing is just there (Menus.tsx `still`)
	press = 0.06, -- .big-btn:active: pushed 2px down while held
	release = 0.12,
	pop = 0.35, -- unlockPop: 0 -> 115% -> 100%
	bump = 0.25, -- count-bump: from 135% back to 100%
	shake = 0.3, -- pitShake: 5px left and right
}
UIMotion.Panel = { rise = 24, drop = 18, scaleIn = 0.94, scaleOut = 0.95 }
UIMotion.Button = { pressDown = 2, pressScale = 0.96, hoverScale = 1.04 }
-- Phones get the bottom sheet: narrow screens, or touch screens short enough to be a phone.
UIMotion.SheetWidth = 700
UIMotion.SheetHeight = 500

local QUINT_OUT = Enum.EasingStyle.Quint
local OUT, IN = Enum.EasingDirection.Out, Enum.EasingDirection.In

local audio = nil
local lastClosedAt = -math.huge
local openCount = 0
local playedAt = -math.huge
-- This game's own sound player (useSounds), and when it last played anything.
local soundPlay: ((string) -> ())? = nil
local soundLast: (() -> number)? = nil

local function reducedMotion()
	-- Settings > Reduce motion (client/Prefs), else Roblox's own setting.
	local me = game:GetService("Players").LocalPlayer
	if me and me:GetAttribute("ReduceMotion") == true then
		return true
	end
	local ok, on = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)
	return ok and on == true
end

local function isPhone()
	local cam = workspace.CurrentCamera
	if not cam then
		return false
	end
	local size = cam.ViewportSize
	return size.X < UIMotion.SheetWidth or (UserInputService.TouchEnabled and size.Y < UIMotion.SheetHeight)
end

local function tween(inst, time, style, dir, goal)
	local t = TweenService:Create(inst, TweenInfo.new(time, style, dir), goal)
	t:Play()
	return t
end

-- Every animated object gets its own UIScale, so scaling never fights a layout's own UIScale.
local function scaleOf(gui)
	local s = gui:FindFirstChild("UIMotionScale")
	if not s then
		s = Instance.new("UIScale")
		s.Name = "UIMotionScale"
		s.Parent = gui
	end
	return s
end

-- Where the object sits at rest: remembered the first time, so repeated animations never drift.
local function homeOf(gui)
	local home = gui:GetAttribute("UIMotionHome")
	if typeof(home) ~= "UDim2" then
		home = gui.Position
		gui:SetAttribute("UIMotionHome", home)
	end
	return home
end

local function overlayOf(panel)
	local parent = panel.Parent
	local o = parent and parent:FindFirstChild("Overlay")
	if o and o ~= panel and o:IsA("GuiObject") then
		return o
	end
	return nil
end

local function setFade(gui, amount)
	if gui:IsA("CanvasGroup") then
		gui.GroupTransparency = amount
	end
end

local function fadeTo(gui, time, dir, amount)
	if gui:IsA("CanvasGroup") then
		tween(gui, time, Enum.EasingStyle.Quad, dir, { GroupTransparency = amount })
	end
end

-- Sounds ------------------------------------------------------------------------------------

-- `audioMap` is Data/Audio.luau. Effects play as regions of the uploaded sound sprite; until its
-- assetId is filled in, nothing plays and nothing errors.
function UIMotion.init(audioMap)
	audio = audioMap
end

-- This game: play(name) plays a sound by its Audio.Sfx name, lastPlayed() says when (os.clock)
-- any sound last played, so a button whose own handler made a sound doesn't click as well.
function UIMotion.useSounds(play: (string) -> (), lastPlayed: () -> number)
	soundPlay = play
	soundLast = lastPlayed
end

local function lastPlayed(): number
	return if soundLast then math.max(playedAt, soundLast()) else playedAt
end

function UIMotion.playSfx(name)
	if soundPlay then
		playedAt = os.clock()
		soundPlay(name)
		return
	end
	if not audio or not audio.Sfx or not audio.SfxSprite then
		return
	end
	local fx = audio.Sfx[name]
	local id = audio.SfxSprite.assetId
	if not fx or not fx.sprite or id == nil or id == "" then
		return
	end
	playedAt = os.clock()
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. tostring(id)
	s.Volume = (audio.Volume and audio.Volume.sfx) or 0.7
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(fx.sprite.start, fx.sprite.stop)
	s.Parent = SoundService
	s.Ended:Once(function()
		s:Destroy()
	end)
	s:Play()
	task.delay(fx.sprite.stop - fx.sprite.start + 1, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

-- Panels ------------------------------------------------------------------------------------

-- Rise in, or slide up as a sheet on phones. A menu opening right after another closed (or
-- while another is up) is just there, so moving between menus never stutters.
function UIMotion.open(panel, opts)
	opts = opts or {}
	local home = homeOf(panel)
	local overlay = overlayOf(panel)
	local still = opts.still or openCount > 0 or os.clock() - lastClosedAt < UIMotion.Timing.stillWindow
	openCount += 1
	panel:SetAttribute("UIMotionOpen", true)
	panel.Visible = true
	if overlay then
		overlay.Visible = true
	end
	if opts.sound ~= false then
		UIMotion.playSfx("menu-open")
	end
	local scale = scaleOf(panel)
	if still or reducedMotion() then
		panel.Position = home
		scale.Scale = 1
		setFade(panel, 0)
		if overlay then
			overlay.BackgroundTransparency = overlay:GetAttribute("UIMotionDim") or overlay.BackgroundTransparency
		end
		return
	end
	local T = UIMotion.Timing
	if overlay then
		local dim = overlay:GetAttribute("UIMotionDim")
		if typeof(dim) ~= "number" then
			dim = overlay.BackgroundTransparency
			overlay:SetAttribute("UIMotionDim", dim)
		end
		overlay.BackgroundTransparency = 1
		tween(overlay, T.overlayIn, Enum.EasingStyle.Quad, OUT, { BackgroundTransparency = dim })
	end
	if isPhone() then
		-- From just below the bottom of the screen.
		panel.Position = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale + 1, home.Y.Offset)
		scale.Scale = 1
		setFade(panel, 0)
		tween(panel, T.sheetIn, QUINT_OUT, OUT, { Position = home })
	else
		local P = UIMotion.Panel
		panel.Position = home + UDim2.fromOffset(0, P.rise)
		scale.Scale = P.scaleIn
		setFade(panel, 1)
		tween(panel, T.panelIn, QUINT_OUT, OUT, { Position = home })
		tween(scale, T.panelIn, QUINT_OUT, OUT, { Scale = 1 })
		fadeTo(panel, T.panelIn * 0.6, OUT, 0)
	end
end

-- Drop away, then hide. `onDone` runs once it is hidden.
function UIMotion.close(panel, onDone, opts)
	opts = opts or {}
	if panel:GetAttribute("UIMotionOpen") then
		openCount = math.max(0, openCount - 1)
	end
	panel:SetAttribute("UIMotionOpen", false)
	lastClosedAt = os.clock()
	if opts.sound ~= false then
		UIMotion.playSfx("menu-close")
	end
	local home = homeOf(panel)
	local overlay = overlayOf(panel)
	local T = UIMotion.Timing
	local function finish()
		panel.Visible = false
		panel.Position = home
		scaleOf(panel).Scale = 1
		setFade(panel, 0)
		if overlay then
			overlay.Visible = false
		end
		if onDone then
			onDone()
		end
	end
	if reducedMotion() or opts.still then
		finish()
		return
	end
	if overlay then
		tween(overlay, T.overlayOut, Enum.EasingStyle.Quad, IN, { BackgroundTransparency = 1 })
	end
	local t
	if isPhone() then
		t = tween(panel, T.sheetOut, Enum.EasingStyle.Quad, IN, { Position = UDim2.new(home.X.Scale, home.X.Offset, home.Y.Scale + 1, home.Y.Offset) })
	else
		local P = UIMotion.Panel
		t = tween(panel, T.panelOut, Enum.EasingStyle.Quad, IN, { Position = home + UDim2.fromOffset(0, P.drop) })
		tween(scaleOf(panel), T.panelOut, Enum.EasingStyle.Quad, IN, { Scale = P.scaleOut })
		fadeTo(panel, T.panelOut, IN, 1)
	end
	t.Completed:Once(finish)
end

-- One menu taking another's place (store.ts swapPanel): no slide, just the tab tick.
function UIMotion.swap(from, to)
	if from then
		UIMotion.close(from, nil, { sound = false, still = true })
	end
	UIMotion.playSfx("tab")
	UIMotion.open(to, { sound = false, still = true })
end

-- Buttons -----------------------------------------------------------------------------------

-- Pushed down while held, springs back on release, grows a touch under a mouse, and taps.
-- `sfxName` overrides the tap sound; a button whose own handler plays a sound within a
-- moment of the press stays with that one (sound.ts: "no press feels dead").
function UIMotion.bindButton(button, sfxName)
	if not button:IsA("GuiButton") or button:GetAttribute("UIMotionBound") then
		return
	end
	button:SetAttribute("UIMotionBound", true)
	local B, T = UIMotion.Button, UIMotion.Timing
	local scale = scaleOf(button)
	local hovering = false
	local function rest()
		return hovering and B.hoverScale or 1
	end
	button.MouseButton1Down:Connect(function()
		if not button.Active or reducedMotion() then
			return
		end
		local home = homeOf(button)
		tween(button, T.press, Enum.EasingStyle.Quad, OUT, { Position = home + UDim2.fromOffset(0, B.pressDown) })
		tween(scale, T.press, Enum.EasingStyle.Quad, OUT, { Scale = B.pressScale })
	end)
	local function release()
		local home = homeOf(button)
		tween(button, T.release, Enum.EasingStyle.Back, OUT, { Position = home })
		tween(scale, T.release, Enum.EasingStyle.Back, OUT, { Scale = rest() })
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(function()
		hovering = false
		release()
	end)
	button.MouseEnter:Connect(function()
		if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
			return
		end
		hovering = true
		if not reducedMotion() then
			tween(scale, T.release, Enum.EasingStyle.Quad, OUT, { Scale = B.hoverScale })
		end
	end)
	button.Activated:Connect(function()
		local at = os.clock()
		-- Read now: the tap may close the menu the button is on.
		local name = sfxName or button:GetAttribute("Sfx") or "click"
		task.delay(0.04, function()
			if lastPlayed() < at - 0.25 then
				UIMotion.playSfx(name)
			end
		end)
	end)
end

-- Every button under `root`, and every one added later. A button can name its own tap sound
-- with a string attribute "Sfx" (an Audio.Sfx name such as "buy" or "equip"), or opt out of
-- motion with the attribute "NoMotion" = true.
function UIMotion.bindAll(root)
	local function try(d)
		if d:IsA("GuiButton") and not d:GetAttribute("NoMotion") then
			UIMotion.bindButton(d)
		end
	end
	for _, d in root:GetDescendants() do
		try(d)
	end
	return root.DescendantAdded:Connect(try)
end

-- Little moments --------------------------------------------------------------------------

-- A reward, badge or unlock popping in: from nothing, overshoot, settle (unlockPop).
function UIMotion.pop(gui, sfxName)
	local s = scaleOf(gui)
	gui.Visible = true
	if sfxName then
		UIMotion.playSfx(sfxName)
	end
	if reducedMotion() then
		s.Scale = 1
		return
	end
	s.Scale = 0
	tween(s, UIMotion.Timing.pop, Enum.EasingStyle.Back, OUT, { Scale = 1 })
end

-- A number that just changed (coins, gems, fuel): a quick swell back to size (count-bump).
function UIMotion.bump(gui)
	if reducedMotion() then
		return
	end
	local s = scaleOf(gui)
	s.Scale = 1.35
	tween(s, UIMotion.Timing.bump, Enum.EasingStyle.Quad, OUT, { Scale = 1 })
end

-- "Can't do that": a short side-to-side shake with the error sound (pitShake).
function UIMotion.shake(gui)
	UIMotion.playSfx("error")
	if reducedMotion() then
		return
	end
	local home = homeOf(gui)
	local step = UIMotion.Timing.shake / 4
	task.spawn(function()
		for _, dx in { -5, 5, -3, 0 } do
			local t = tween(gui, step, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, { Position = home + UDim2.fromOffset(dx, 0) })
			t.Completed:Wait()
		end
		gui.Position = home
	end)
end

return UIMotion
