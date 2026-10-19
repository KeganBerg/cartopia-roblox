--!strict
-- Screenshot mode, as the web game's ShotMode (ui/ShotMode.tsx, shot.ts): two buttons above the
-- Drive / Town button (.shot-dock). The shutter hides every menu, bubble, pop-up and toast (and
-- Roblox's own buttons) so only the town is left on screen; the camera keeps working underneath.
-- A tap, Esc or H brings them back; "Tap to show menus" says so for a moment. H also goes into it
-- from the plain town on a keyboard. The other button saves a picture of the view without the
-- menus, through Roblox's own capture (saved to the player's captures).

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Ui = require(script.Parent.Ui)
local Icons = require(script.Parent.Icons)

local ShotMode = {}

local TOUCH = UserInputService.TouchEnabled and not UserInputService.MouseEnabled

-- A press that barely moves and lets go quickly. Anything else is the camera being steered.
function ShotMode.isTap(dx: number, dy: number, seconds: number): boolean
	return dx * dx + dy * dy < 100 and seconds < 0.35
end

local on = false
local hidden: { [LayerCollector]: boolean } = {}
local coreWas: boolean? = nil
local layer: ScreenGui? = nil
local conns: { RBXScriptConnection } = {}

function ShotMode.active(): boolean
	return on
end

-- The menus are off right now (screenshot mode, or a picture being taken): job bubbles stay off.
function ShotMode.hiding(): boolean
	return on or next(hidden) ~= nil
end

local function hideAll()
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return
	end
	for _, g in pg:GetDescendants() do
		if g:IsA("LayerCollector") and g ~= layer and g.Enabled then
			hidden[g] = true
			g.Enabled = false
		end
	end
	local ok, was = pcall(function()
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.All)
	end)
	coreWas = if ok then was else nil
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
end

local function showAll()
	for g in hidden do
		if g.Parent then
			g.Enabled = true
		end
	end
	hidden = {}
	if coreWas ~= false then
		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
		end)
	end
	coreWas = nil
end

function ShotMode.exit()
	if not on then
		return
	end
	on = false
	for _, c in conns do
		c:Disconnect()
	end
	conns = {}
	if layer then
		layer:Destroy()
		layer = nil
	end
	showAll()
end

function ShotMode.enter()
	if on then
		return
	end
	on = true
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Ui.new("ScreenGui", { Name = "Shot", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 2000, Parent = pg })
	layer = g
	hideAll()
	-- The hint (.shot-ui), fading after a moment.
	local hint = Ui.text({ Name = "Hint", Text = if TOUCH then "Tap to show menus" else "Esc to show menus", TextSize = 15, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(200, 30), BackgroundColor3 = Ui.BLACK, BackgroundTransparency = 0.55, Parent = g })
	Ui.corner(14).Parent = hint
	hint.Size = UDim2.fromOffset(Ui.textWidth(hint.Text, 15) + 28, 30)
	task.delay(1.4, function()
		if hint.Parent then
			pcall(function()
				TweenService:Create(hint, TweenInfo.new(0.6), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			end)
		end
	end)
	local start: { at: Vector2, t: number, input: InputObject }? = nil
	table.insert(conns, UserInputService.InputBegan:Connect(function(input)
		local k = input.KeyCode
		if k == Enum.KeyCode.Escape or k == Enum.KeyCode.H then
			ShotMode.exit()
			return
		end
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			start = { at = Vector2.new(input.Position.X, input.Position.Y), t = os.clock(), input = input }
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		local st = start
		if not st then
			return
		end
		if input ~= st.input and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		start = nil
		local d = Vector2.new(input.Position.X, input.Position.Y) - st.at
		if ShotMode.isTap(d.X, d.Y, os.clock() - st.t) then
			-- The tap only brings the menus back; it mustn't also press what's under it (the
			-- menus are still off as it lands).
			task.defer(ShotMode.exit)
		end
	end))
end

-- A picture of the view without the menus, saved to the player's captures.
function ShotMode.save(toast: (string) -> ())
	local found, CaptureService = pcall(function()
		return (game :: any):GetService("CaptureService")
	end)
	if not found or not CaptureService then
		toast("Saving pictures isn't available here")
		return
	end
	local was = on
	if not was then
		hideAll()
	end
	task.wait()
	task.wait()
	local ok = pcall(function()
		CaptureService:CaptureScreenshot(function(id: any)
			if not was then
				showAll()
			end
			pcall(function()
				CaptureService:PromptSaveCapturesToGallery({ id }, function(results: any)
					if type(results) == "table" and results[id] then
						toast("📸 Picture saved!")
					end
				end)
			end)
		end)
	end)
	if not ok then
		if not was then
			showAll()
		end
		toast("Saving pictures isn't available here")
	end
end

-- The two buttons (.shot-dock): place them with the returned frame.
function ShotMode.dock(root: Instance, ctx: any): Frame
	local dock = Ui.new("Frame", { Name = "ShotDock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -26, 1, -408), Size = UDim2.fromOffset(60, 60 * 2 + 12), BackgroundTransparency = 1, Parent = root })
	local function button(name: string, icon: string, y: number, onClick: () -> ())
		local _, face = Ui.button({ Name = name, Position = UDim2.fromOffset(2.5, y + 5.5), Size = UDim2.fromOffset(55, 55), Parent = dock }, "white", onClick, { radius = 16, stroke = 2.5, drop = 3, split = 0.5, flat = true })
		Icons.draw(icon, face, 30, Ui.BLUE, Color3.fromHex("#f3f7fc"), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		return face
	end
	-- (column-reverse on the web: the shutter nearest the camera button, Save above it.)
	local shutter = button("ShotShutter", "shutter", 60 + 12, function()
		ctx.close()
		ShotMode.enter()
	end)
	local save = button("ShotSave", "save", 0, function()
		task.spawn(ShotMode.save, ctx.toast)
	end)
	shutter:SetAttribute("Tip", "Screenshot mode: hide menus and bubbles (H)")
	shutter:SetAttribute("TipHold", true)
	save:SetAttribute("Tip", "Save picture of the view")
	save:SetAttribute("TipHold", true)
	-- H on a keyboard, from the plain town.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or on or input.KeyCode ~= Enum.KeyCode.H then
			return
		end
		if UserInputService:GetFocusedTextBox() or not dock.Visible or ctx.panel() ~= nil then
			return
		end
		ShotMode.enter()
	end)
	return dock
end

return ShotMode
