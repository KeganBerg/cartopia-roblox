--!strict
-- Getting in any car on foot, and out again (server/GetIn). Out in the world and not in a car, a
-- "Drive" prompt (E, or a tap on phones) shows over the nearest car, in town (TownLife), on the
-- roads between the plots (WorldLife) or parked; the
-- car then drives like the DRIVE button's (server/Drive). E or the EXIT button gets out on foot,
-- and the car stays parked there until the player walks well away, then rejoins the traffic.
--
-- Also Shift: a sprint on foot and a boost in a car, held (and the drag race's boost, DragStrip).
-- Phones get a SPRINT/BOOST button for it: tap to sprint on foot, hold to boost. Shift lock is off
-- (default.project.json EnableMouseLockOption) so Shift is free for this.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local data = require(Game:WaitForChild("data")) :: any
local Ui = require(script.Parent.Ui) :: any
local TownCamera = require(script.Parent.TownCamera) :: any
local TownLife = require(script.Parent.TownLife) :: any
local WorldLife = require(script.Parent.WorldLife) :: any

-- Where the cars come from: the town's traffic, and the roads between the plots. Road cars'
-- uids start "visitor:road:".
local function source(uid: string): any
	return if string.find(uid, "^visitor:road:") then WorldLife else TownLife
end

local GetIn = {}

local player = Players.LocalPlayer

local WALK = 16
local SPRINT = 26
local DRIVE = 110 -- server/Drive.SPEED
local BOOST = 1.5 -- times the car's speed
local REACH = 14 -- how close to a car the prompt shows
local GIVE_BACK = 160 -- walk this far from a car you left and it rejoins the traffic

local shiftHeld = false
local buttonOn = false
-- The uid of the town car the player is in (nil on foot, or in their race car from DRIVE).
local riding: string? = nil
-- The car last got out of, left parked.
local left: { uid: string, at: Vector3 }? = nil
local busy = false

local function boosting(): boolean
	return shiftHeld or buttonOn
end

local function driving(): boolean
	return player:GetAttribute("Driving") == true
end

local function rootPart(): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function remote(): RemoteFunction?
	local folder = ReplicatedStorage:FindFirstChild("Cartopia")
	return folder and folder:FindFirstChild("GetIn") :: RemoteFunction?
end

-- Walking pace or driving speed, sped up while Shift or the button is down.
local function applySpeed()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if driving() then
		humanoid.WalkSpeed = DRIVE * (if boosting() then BOOST else 1)
	elseif TownCamera.isWalking() then
		humanoid.WalkSpeed = if boosting() then SPRINT else WALK
	end
end

local function giveBack()
	if left then
		source(left.uid).give(left.uid)
		left = nil
	end
end

-- Leaves town car `uid` parked at `at` (nose along +Z) until the player walks away from it.
local function park(uid: string, at: CFrame)
	local m = source(uid).take(uid)
	if m then
		m:PivotTo(at)
	end
	left = { uid = uid, at = at.Position }
end

function GetIn.enter(uid: string, model: Model)
	local rem = remote()
	if busy or driving() or not rem then
		return
	end
	busy = true
	if left and left.uid ~= uid then
		giveBack()
	end
	local cf = model:GetPivot()
	source(uid).take(uid)
	local ok, good = pcall(function()
		return rem:InvokeServer("enter", { uid = uid, model = model:GetAttribute("Model"), color = model:GetAttribute("Color"), cf = cf })
	end)
	busy = false
	if not (ok and good == true) then
		if not (left and left.uid == uid) then
			source(uid).give(uid)
		end
		return
	end
	if left and left.uid == uid then
		left = nil
	end
	-- The town's copy hides while the player drives the real one.
	model:PivotTo(CFrame.new(0, -10000, 0))
	riding = uid
	applySpeed()
end

-- Out of the car, on foot beside it (only out in the world: TOWN goes home instead).
function GetIn.exit()
	local rem = remote()
	if busy or not driving() or not rem then
		return
	end
	busy = true
	local ok, good, at, uid = pcall(function()
		return rem:InvokeServer("exit")
	end)
	busy = false
	local was = riding
	riding = nil
	if ok and good == true and typeof(at) == "CFrame" and type(uid) == "string" and uid == was then
		park(uid, at)
	elseif was then
		source(was).give(was)
	end
	applySpeed()
end

---------------------------------------------------------------------------------------------------
-- The prompt: one, moved over whichever car is nearest.

local promptPart: Part
local prompt: ProximityPrompt
local promptUid: string? = nil
local promptModel: Model? = nil

local function makePrompt()
	promptPart = Instance.new("Part")
	promptPart.Name = "GetInPrompt"
	promptPart.Anchored = true
	promptPart.CanCollide = false
	promptPart.CanQuery = false
	promptPart.CanTouch = false
	promptPart.Transparency = 1
	promptPart.Size = Vector3.new(1, 1, 1)
	promptPart.CFrame = CFrame.new(0, -10000, 0)
	promptPart.Parent = workspace
	prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Drive"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = REACH
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = promptPart
	prompt.Triggered:Connect(function()
		local uid, m = promptUid, promptModel
		if uid and m then
			prompt.Enabled = false
			GetIn.enter(uid, m)
		end
	end)
end

local function stepPrompt()
	local root = rootPart()
	if busy or driving() or not TownCamera.isWalking() or not root then
		prompt.Enabled = false
		return
	end
	local best, bestUid, bestModel = REACH, nil, nil
	local function consider(uid: string, m: Model)
		local d = (m:GetPivot().Position - root.Position).Magnitude
		if d < best then
			best, bestUid, bestModel = d, uid, m
		end
	end
	for uid, m in TownLife.cars() do
		consider(uid, m)
	end
	for uid, m in WorldLife.cars() do
		consider(uid, m)
	end
	if left then
		local m = source(left.uid).modelOf(left.uid)
		if m then
			consider(left.uid, m)
		end
	end
	promptUid, promptModel = bestUid, bestModel
	if not (bestUid and bestModel) then
		prompt.Enabled = false
		return
	end
	local id = bestModel:GetAttribute("Model")
	local def = if type(id) == "string" then data.carDef(id) else nil
	prompt.ObjectText = if def then def.name else ""
	promptPart.CFrame = bestModel:GetPivot() + Vector3.new(0, 3, 0)
	prompt.Enabled = true
end

---------------------------------------------------------------------------------------------------
-- The buttons: phones get SPRINT/BOOST; everyone gets EXIT while in a car out in the world.

local exitButton: GuiObject? = nil
local boostButton: GuiObject? = nil
local boostLabel: TextLabel? = nil

local function paintButtons()
	if boostButton then
		boostButton.Visible = UserInputService.TouchEnabled and TownCamera.isWalking()
		;(boostButton :: any).BackgroundColor3 = if buttonOn then Color3.fromHex("#ff9100") else Color3.fromHex("#1b1f24")
	end
	if boostLabel then
		boostLabel.Text = if driving() then "BOOST" else "SPRINT"
	end
	if exitButton then
		exitButton.Visible = driving() and TownCamera.isWalking()
	end
end

local function makeButtons()
	local gui = Ui.new("ScreenGui", {
		Name = "GetIn",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local touch = UserInputService.TouchEnabled
	local boost = Ui.new("TextButton", {
		Name = "Boost",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -200, 1, -110),
		Size = UDim2.fromOffset(72, 72),
		BackgroundColor3 = Color3.fromHex("#1b1f24"),
		BackgroundTransparency = 0.25,
		Visible = false,
		Parent = gui,
	}, { Ui.round(), Ui.stroke(3, Color3.fromHex("#ff9100")) })
	Ui.text({ Text = "⚡", TextSize = 26, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 32), Parent = boost })
	boostLabel = Ui.text({ Text = "SPRINT", TextSize = 12, Position = UDim2.new(0, 0, 1, -26), Size = UDim2.new(1, 0, 0, 16), Parent = boost })
	boostButton = boost
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
	end
	boost.InputBegan:Connect(function(input: InputObject)
		if isPress(input) then
			-- In a car: held for boost. On foot: tap to sprint, tap again to walk.
			buttonOn = if driving() then true else not buttonOn
			applySpeed()
			paintButtons()
		end
	end)
	boost.InputEnded:Connect(function(input: InputObject)
		if isPress(input) and driving() then
			buttonOn = false
			applySpeed()
			paintButtons()
		end
	end)
	local shadow = Ui.button({
		Name = "Exit",
		AnchorPoint = Vector2.new(1, 1),
		Position = if touch then UDim2.new(1, -200, 1, -196) else UDim2.new(1, -120, 1, -24),
		Size = UDim2.fromOffset(92, 48),
		Parent = gui,
	}, "red", function()
		task.spawn(GetIn.exit)
	end, { text = "EXIT", textSize = 18, textStroke = 0.6 })
	shadow.Visible = false
	exitButton = shadow
end

---------------------------------------------------------------------------------------------------

function GetIn.start()
	makePrompt()
	makeButtons()
	TownCamera.onWalking(function(on: boolean)
		if not on then
			-- Back to the town view: the town car goes back to the traffic, the sprint stops.
			if riding then
				source(riding).give(riding)
				riding = nil
			end
			giveBack()
			buttonOn = false
		end
		paintButtons()
	end)
	player:GetAttributeChangedSignal("Driving"):Connect(function()
		if not driving() then
			buttonOn = false
		end
		applySpeed()
		paintButtons()
	end)
	player.CharacterAdded:Connect(function(character: Model)
		character:WaitForChild("Humanoid", 10)
		if riding then
			source(riding).give(riding)
			riding = nil
		end
		applySpeed()
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = true
			applySpeed()
		elseif input.KeyCode == Enum.KeyCode.E and not processed and driving() and TownCamera.isWalking() then
			task.spawn(GetIn.exit)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			shiftHeld = false
			applySpeed()
		end
	end)
	RunService.RenderStepped:Connect(function()
		stepPrompt()
		local root = rootPart()
		if left and not driving() and root and (root.Position - left.at).Magnitude > GIVE_BACK then
			giveBack()
		end
	end)
	paintButtons()
end

return GetIn
