--!strict
-- Getting in any car on foot, and out again (server/GetIn). Out in the world and not in a car, a
-- "Drive" prompt (E, or a tap on phones) shows over the nearest car, in town (TownLife), on the
-- roads between the plots (WorldLife) or parked; the
-- car then drives like the DRIVE button's (server/Drive, with the feel in client/CarDrive). E or
-- the EXIT button gets out on foot, and the car drives itself off slowly: in the player's town to
-- the nearest road and on with the traffic; elsewhere to the verge of the nearest road, where it
-- stays parked until the player walks well away, then rejoins the traffic.
--
-- Also Shift: a sprint on foot and a boost in a car, held (and the drag race's boost, DragStrip).
-- Phones get a SPRINT/BOOST button for it: tap to sprint on foot, hold to boost. Shift lock is off
-- (default.project.json EnableMouseLockOption) so Shift is free for this.

local PathfindingService = game:GetService("PathfindingService")
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
local CarDrive = require(script.Parent.CarDrive) :: any

-- Where the cars come from: the town's traffic, and the roads between the plots. Road cars'
-- uids start "visitor:road:".
local function source(uid: string): any
	return if string.find(uid, "^visitor:road:") then WorldLife else TownLife
end

local GetIn = {}

local player = Players.LocalPlayer

local WALK = 16
local SPRINT = 26
local REACH = 14 -- how close to a car the prompt shows
local GIVE_BACK = 160 -- walk this far from a car you left and it rejoins the traffic
local AWAY = 9 -- a car left out drives itself off this slowly (studs a second)...
local AWAY_TURN = 1.3 -- ...turning at most this fast (radians a second)
local AWAY_GIVE_UP = 45 -- seconds: still not there, it's simply put there

local shiftHeld = false
local buttonOn = false
-- The uid of the town car the player is in (nil on foot, or in their race car from DRIVE).
local riding: string? = nil
-- The car last got out of, left parked.
local left: { uid: string, at: Vector3 }? = nil
-- The car last got out of driving itself off: to the nearest road in town, where it rejoins the
-- traffic, or out in the world to the verge of the nearest road, where it parks.
type Away = {
	uid: string,
	model: Model,
	pos: Vector3,
	yaw: number, -- car models face +Z: the nose points (sin yaw, 0, cos yaw)
	speed: number,
	points: { Vector3 }?, -- the way there, once worked out
	i: number,
	park: CFrame?, -- where it parks (nil: it rejoins the town's traffic at the last point)
	since: number,
}
local away: Away? = nil
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

-- Walking pace, sped up while Shift or the button is down. In a car, client/CarDrive sets the
-- speed every step (and reads boosting()).
local function applySpeed()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or driving() then
		return
	end
	if TownCamera.isWalking() then
		humanoid.WalkSpeed = if boosting() then SPRINT else WALK
	end
end

local function giveBack()
	away = nil
	if left then
		source(left.uid).give(left.uid)
		left = nil
	end
end

-- Leaves car `uid` at `at` (nose along +Z), then sends it off on its own: in the player's town to
-- the nearest road, where it carries on with the traffic; anywhere else to the verge of the
-- nearest road between the plots, where it parks.
local function park(uid: string, at: CFrame)
	local m = source(uid).take(uid)
	if m then
		m:PivotTo(at)
	end
	left = { uid = uid, at = at.Position }
	away = nil
	if not m then
		return
	end
	local road = TownLife.roadNear(at.Position)
	local target: Vector3?, spot: CFrame? = nil, nil
	if road then
		target = road
		-- A road car left in town parks at the roadside there; a town car rejoins its traffic.
		spot = if source(uid) == WorldLife then CFrame.new(road) * at.Rotation else nil
	else
		spot = WorldLife.roadsideNear(at.Position)
		target = spot and spot.Position
	end
	if not target then
		return
	end
	local nose = at.ZVector
	local trip: Away = {
		uid = uid,
		model = m,
		pos = at.Position,
		yaw = math.atan2(nose.X, nose.Z),
		speed = 0,
		points = nil,
		i = 1,
		park = spot,
		since = os.clock(),
	}
	away = trip
	-- The way round fences and buildings, worked out in the background; straight there if none.
	task.spawn(function()
		local points = { target :: Vector3 }
		local ok, path = pcall(function()
			local p = PathfindingService:CreatePath({ AgentRadius = 7, AgentHeight = 6, AgentCanJump = false, AgentCanClimb = false, WaypointSpacing = 14 })
			p:ComputeAsync(at.Position + Vector3.new(0, 2, 0), (target :: Vector3) + Vector3.new(0, 2, 0))
			return p
		end)
		if ok and path and path.Status == Enum.PathStatus.Success then
			local list = {}
			for _, w in path:GetWaypoints() do
				table.insert(list, w.Position)
			end
			if #list > 0 then
				points = list
			end
		end
		if away == trip then
			trip.points = points
		end
	end)
end

local function groundUnder(p: Vector3, skip: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	params.RespectCanCollide = true
	local hit = workspace:Raycast(p + Vector3.new(0, 25, 0), Vector3.new(0, -80, 0), params)
	return hit and hit.Position.Y
end

local function arrive(trip: Away)
	away = nil
	if trip.park then
		trip.model:PivotTo(trip.park)
		if left and left.uid == trip.uid then
			left.at = trip.park.Position
		end
	else
		-- Back on the town's roads: it carries on with the traffic.
		giveBack()
	end
end

-- Moves the car driving itself off on by dt: a slow, car-like drive along the way there.
local function stepAway(dt: number)
	local trip = away
	if not trip or not trip.points then
		return
	end
	if not trip.model.Parent or os.clock() - trip.since > AWAY_GIVE_UP then
		arrive(trip)
		return
	end
	local points = trip.points :: { Vector3 }
	local goal = points[trip.i]
	local to = Vector3.new(goal.X - trip.pos.X, 0, goal.Z - trip.pos.Z)
	local last = trip.i >= #points
	if to.Magnitude < (if last then 3 else 7) then
		trip.i += 1
		if trip.i > #points then
			arrive(trip)
			return
		end
		return
	end
	local want = math.atan2(to.X, to.Z)
	local diff = (want - trip.yaw + math.pi) % (2 * math.pi) - math.pi
	trip.yaw += math.clamp(diff, -AWAY_TURN * dt, AWAY_TURN * dt)
	-- Pull away gently, slow for sharp turns and coming up to the end.
	local cap = AWAY * math.max(0.35, math.cos(diff)) * (if last then math.clamp(to.Magnitude / 15, 0.3, 1) else 1)
	trip.speed = math.min(trip.speed + 6 * dt, cap)
	local nose = Vector3.new(math.sin(trip.yaw), 0, math.cos(trip.yaw))
	local pos = trip.pos + nose * trip.speed * dt
	local skip: { Instance } = { trip.model }
	if player.Character then
		table.insert(skip, player.Character)
	end
	local y = groundUnder(pos, skip)
	trip.pos = Vector3.new(pos.X, y or pos.Y, pos.Z)
	trip.model:PivotTo(CFrame.new(trip.pos) * CFrame.Angles(0, trip.yaw, 0))
	if left and left.uid == trip.uid then
		left.at = trip.pos
	end
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
		away = nil
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
	CarDrive.start(boosting)
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
	RunService.RenderStepped:Connect(function(dt: number)
		stepPrompt()
		stepAway(math.min(dt, 0.1))
		local root = rootPart()
		if left and not away and not driving() and root and (root.Position - left.at).Magnitude > GIVE_BACK then
			giveBack()
		end
	end)
	paintButtons()
end

return GetIn
