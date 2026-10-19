--!strict
-- Driving feel out in the world. The car is still the hidden avatar in disguise (server/Drive), so
-- it bumps into things, stays on the ground and shows to every other player for free, but while
-- the player drives this takes the wheel from Roblox's walking controls:
--   - speed builds, coasts and brakes like a car (shared/CarFeel) instead of jumping to full
--     speed and stopping dead; S brakes, then backs up;
--   - W/S or the stick's up/down is throttle and brake, A/D or left/right steers, and the car
--     turns round its back wheels (no spinning on the spot);
--   - a chase camera sits behind the car and swings round after it smoothly, widening a little
--     with speed; right-drag (or a drag on the right of a phone screen) looks round, the wheel
--     zooms;
--   - the body leans a touch on corners and dips under braking, and the wheels roll with the
--     speed and the front ones steer (shared/Models/Wheels) (this player's view only).
-- Shift / BOOST (client/GetIn) raises the top speed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local CarFeel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CarFeel")) :: any
local Wheels = require(ReplicatedStorage.Shared:WaitForChild("Models"):WaitForChild("Wheels"))
local TownCamera = require(script.Parent.TownCamera) :: any

local CarDrive = {}

local player = Players.LocalPlayer

local CAM_DIST = 30 -- studs behind the car
local CAM_HIGH = 10 -- and above its middle
local CAM_SWING = 4 -- how fast the camera swings round behind the car
local LOOK_AHEAD = 10
local FOV = 70
local MAX_BODY_PARTS = 600
local FLIP = CFrame.Angles(0, math.pi, 0) -- car models face +Z, avatars -Z

local boosting: () -> boolean = function()
	return false
end

local active = false
local state = CarFeel.new()
local yaw = 0 -- the car's heading (radians round Y; 0 faces -Z)

-- Camera.
local camYaw = 0
local camY: number? = nil
local fov = FOV
local zoom = 1
local orbit = 0 -- extra look-round angle from a drag
local orbitHeld = false
local orbitLetGo = 0
local orbitTouch: InputObject? = nil

-- The leaning body: a local copy of the car moved each frame, the real one hidden.
local body: { car: Model, copy: Model, parts: { BasePart }, rel: { CFrame }, hidden: { BasePart }, pivot: Vector3, added: RBXScriptConnection, wheels: Wheels.Rig? }? = nil
-- Set when more of the car arrives after the copy was made (streaming): the copy is made again.
local stale = false
local roll, rollV, pitch, pitchV = 0, 0, 0, 0

local function parts(): (Model?, Humanoid?, BasePart?, Model?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local car = character and character:FindFirstChild("Car") :: Model?
	return character, humanoid, root, car
end

local function shouldDrive(): boolean
	if player:GetAttribute("Driving") ~= true or not TownCamera.isWalking() or TownCamera.isPaused() then
		return false
	end
	local _, humanoid, root, car = parts()
	return humanoid ~= nil and root ~= nil and car ~= nil and humanoid.Health > 0
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function headingOf(cf: CFrame): number
	local look = flat(cf.LookVector)
	if look.Magnitude < 1e-3 then
		return 0
	end
	look = look.Unit
	return math.atan2(-look.X, -look.Z)
end

local function forwardOf(a: number): Vector3
	return Vector3.new(-math.sin(a), 0, -math.cos(a))
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function dropBody()
	if not body then
		return
	end
	for _, p in body.hidden do
		p.LocalTransparencyModifier = 0
	end
	body.added:Disconnect()
	body.copy:Destroy()
	body = nil
end

local function makeBody(root: BasePart, humanoid: Humanoid, car: Model)
	dropBody()
	local originals: { BasePart } = {}
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(originals, d)
		end
	end
	if #originals == 0 or #originals > MAX_BODY_PARTS then
		return
	end
	-- Each original is tagged with its number so its copy can be found in the clone.
	for i, p in originals do
		p:SetAttribute("CarDriveI", i)
	end
	local ok, copy = pcall(function()
		return car:Clone()
	end)
	if not ok or not copy then
		return
	end
	local copies: { BasePart } = {}
	local rel: { CFrame } = {}
	for _, d in copy:GetDescendants() do
		if d:IsA("WeldConstraint") or d:IsA("JointInstance") or d:IsA("Sound") or d:IsA("Light") or d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			local i = d:GetAttribute("CarDriveI")
			local orig = if type(i) == "number" then originals[i] else nil
			if orig then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				table.insert(copies, d)
				table.insert(rel, root.CFrame:ToObjectSpace(orig.CFrame))
			end
		end
	end
	if #copies ~= #originals then
		copy:Destroy()
		return
	end
	copy.Name = "DrivenCar"
	copy.Parent = workspace
	for _, p in originals do
		p.LocalTransparencyModifier = 1
	end
	body = {
		car = car,
		copy = copy,
		parts = copies,
		rel = rel,
		hidden = originals,
		pivot = Vector3.new(0, -(root.Size.Y / 2 + humanoid.HipHeight), 0),
		added = car.DescendantAdded:Connect(function(d: Instance)
			if d:IsA("BasePart") then
				stale = true
			end
		end),
		-- The copy's wheels, measured from the root turned round (the car faces the avatar's -Z).
		wheels = Wheels.rig(copy, car:GetAttribute("Model") :: string?, root.CFrame * FLIP, copies),
	}
	stale = false
	roll, rollV, pitch, pitchV = 0, 0, 0, 0
end

local function begin()
	local _, humanoid, root, car = parts()
	if not (humanoid and root and car) then
		return
	end
	active = true
	humanoid.AutoRotate = false
	yaw = headingOf(root.CFrame)
	state = CarFeel.new()
	state.speed = flat(root.AssemblyLinearVelocity):Dot(forwardOf(yaw))
	camYaw = yaw
	camY = nil
	orbit = 0
	zoom = 1
	fov = workspace.CurrentCamera.FieldOfView
	pcall(makeBody, root, humanoid, car)
end

local function finish()
	active = false
	dropBody()
	orbitTouch = nil
	orbitHeld = false
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCurrentPosition then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	local _, humanoid = parts()
	if humanoid then
		humanoid.AutoRotate = true
		humanoid:Move(Vector3.zero)
	end
	-- Back on foot (or the town view, or another screen has the camera): hand the camera back.
	TownCamera.follow()
end

-- Before each physics step: the car's speed and heading, handed to the avatar. Runs after
-- Roblox's controls have moved the avatar this frame, so this move is the one that counts.
local function physicsStep(dt: number)
	local on = shouldDrive()
	if on ~= active then
		if on then
			begin()
		else
			finish()
		end
	end
	if not active then
		return
	end
	local _, humanoid, root, car = parts()
	if not (humanoid and root) then
		return
	end
	if car and ((body and body.car ~= car) or stale) then
		stale = false
		pcall(makeBody, root, humanoid, car)
	end
	local controls = TownCamera.controls()
	local move: Vector3 = if controls then controls:GetMoveVector() else Vector3.zero
	if UserInputService:GetFocusedTextBox() then
		move = Vector3.zero
	end
	local actual = flat(root.AssemblyLinearVelocity):Dot(forwardOf(yaw))
	CarFeel.blocked(state, actual)
	state = CarFeel.step(state, dt, -move.Z, move.X, boosting())
	yaw = wrap(yaw - state.turn * dt)
	root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	root.AssemblyAngularVelocity = Vector3.zero
	humanoid.WalkSpeed = math.abs(state.speed)
	if math.abs(state.speed) > 0.05 then
		humanoid:Move(forwardOf(yaw) * math.sign(state.speed), false)
	else
		humanoid:Move(Vector3.zero, false)
	end
end

local function spring(x: number, v: number, target: number, dt: number): (number, number)
	v += (target - x) * 140 * dt
	v *= math.exp(-13 * dt)
	return x + v * dt, v
end

-- Each frame before drawing: the leaning body and the chase camera.
local function renderStep(dt: number)
	if not active then
		return
	end
	local character, _, root = parts()
	if not (character and root) then
		return
	end
	dt = math.min(dt, 0.1)
	local here = root.CFrame

	if body then
		-- Lean out of corners, nose up pulling away, nose down braking.
		local lateral = state.speed * state.turn
		roll, rollV = spring(roll, rollV, math.clamp(lateral * 0.0011, -0.06, 0.06), dt)
		pitch, pitchV = spring(pitch, pitchV, math.clamp(state.accel * 0.0009, -0.045, 0.03), dt)
		local p = body.pivot
		local base = here * CFrame.new(p) * CFrame.Angles(pitch, 0, roll) * CFrame.new(-p)
		local cfs = table.create(#body.parts)
		for i, r in body.rel do
			cfs[i] = base * r
		end
		if body.wheels then
			local t = math.clamp(math.abs(state.speed) / CarFeel.TOP, 0, 1)
			local lock = CarFeel.STEER_SLOW + (CarFeel.STEER_FAST - CarFeel.STEER_SLOW) * t
			Wheels.turn(body.wheels, dt, state.speed, state.steer * lock)
			Wheels.into(body.wheels, base * FLIP, cfs)
		end
		workspace:BulkMoveTo(body.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- The camera swings round behind the car (behind its nose even when backing up).
	if not orbitHeld and orbitTouch == nil and os.clock() - orbitLetGo > 1.2 then
		orbit *= math.exp(-3 * dt)
	end
	local swing = CAM_SWING * (0.35 + 0.65 * math.clamp(math.abs(state.speed) / 30, 0, 1))
	camYaw = wrap(camYaw + wrap(yaw + orbit - camYaw) * (1 - math.exp(-swing * dt)))
	local target = here.Position
	-- Smooth only the height, so bumps and kerbs don't shake the view.
	camY = if camY then camY + (target.Y - camY) * (1 - math.exp(-8 * dt)) else target.Y
	local centre = Vector3.new(target.X, camY :: number, target.Z)
	local ahead = forwardOf(camYaw)
	local speedish = math.clamp(math.abs(state.speed) / CarFeel.TOP, 0, 1.5)
	local dist = (CAM_DIST + speedish * 6) * zoom
	local high = CAM_HIGH * zoom + 2
	local look = centre + ahead * LOOK_AHEAD + Vector3.new(0, 3, 0)
	local want = centre - ahead * dist + Vector3.new(0, high, 0)
	-- Don't look through walls: pull in in front of whatever is between the car and the camera.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = if body then { character, body.copy } else { character }
	local from = centre + Vector3.new(0, 4, 0)
	local hit = workspace:Raycast(from, want - from, params)
	if hit then
		want = hit.Position + (from - want).Unit * 1.5
	end
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local wantFov = FOV + 9 * math.min(speedish, 1) + (if boosting() and state.speed > CarFeel.TOP then 6 else 0)
	fov += (wantFov - fov) * (1 - math.exp(-4 * dt))
	cam.FieldOfView = fov
	cam.CFrame = CFrame.lookAt(want, look)
	cam.Focus = CFrame.new(centre)
end

function CarDrive.start(isBoosting: () -> boolean)
	boosting = isBoosting
	RunService.PreSimulation:Connect(physicsStep)
	RunService:BindToRenderStep("CarDrive", Enum.RenderPriority.Camera.Value + 1, renderStep)

	-- Looking round: right-drag with a mouse, a drag on the right of a phone screen; the wheel zooms.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not active or processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			orbitHeld = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
		elseif input.UserInputType == Enum.UserInputType.Touch and orbitTouch == nil then
			local width = workspace.CurrentCamera.ViewportSize.X
			if input.Position.X > width * 0.45 then
				orbitTouch = input
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton2 and orbitHeld then
			orbitHeld = false
			orbitLetGo = os.clock()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		elseif input == orbitTouch then
			orbitTouch = nil
			orbitLetGo = os.clock()
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseMovement and orbitHeld then
			orbit = wrap(orbit - input.Delta.X * 0.008)
		elseif input == orbitTouch then
			orbit = wrap(orbit - input.Delta.X * 0.01)
		elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			zoom = math.clamp(zoom * (1 - input.Position.Z * 0.1), 0.6, 1.8)
		end
	end)
	player.CharacterAdded:Connect(function()
		if active then
			active = false
			dropBody()
		end
	end)
end

return CarDrive
