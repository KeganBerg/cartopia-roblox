--!strict
-- Driving round the shared world in your own race car. The car is the player's avatar in
-- disguise: their race car's model is welded round the (hidden) avatar, which walks fast and
-- can't jump, so Roblox's own controls steer it on every device (thumbstick on phones, WASD or
-- arrows on a computer), its movement reaches every other player like any avatar's, and it
-- bumps into buildings and stays on the ground for free.
--
-- Car models face +Z (the web's yaw convention); an avatar faces -Z, so the car is turned round.

local Drive = {}

Drive.SPEED = 70 -- studs a second until the driver's own client/CarDrive takes the wheel (shared/CarFeel.TOP)
Drive.SCALE = 0.8 -- the town's traffic draws cars at this size

local function hide(character: Model, hidden: boolean)
	local car = character:FindFirstChild("Car")
	for _, d in character:GetDescendants() do
		if car and d:IsDescendantOf(car) then
			continue
		end
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			if hidden then
				if d:GetAttribute("DriveWas") == nil then
					d:SetAttribute("DriveWas", d.Transparency)
				end
				d.Transparency = 1
			else
				local was = d:GetAttribute("DriveWas")
				if type(was) == "number" then
					d.Transparency = was
					d:SetAttribute("DriveWas", nil)
				end
			end
		elseif d:IsA("Decal") then
			d.Transparency = if hidden then 1 else 0
		end
	end
end

function Drive.isDriving(player: Player): boolean
	local character = player.Character
	return character ~= nil and character:FindFirstChild("Car") ~= nil
end

-- Puts the player in their car (model: a built car Model, or nil for a plain stand-in), or takes
-- them out of it (model = false).
function Drive.set(player: Player, model: Model | false | nil)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not humanoid or not root then
		return
	end
	local old = character:FindFirstChild("Car")
	if old then
		old:Destroy()
	end
	if model == false then
		hide(character, false)
		humanoid.WalkSpeed = 16
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 50
		player:SetAttribute("Driving", nil)
		return
	end
	local car: Model = model or (function()
		local m = Instance.new("Model")
		local body = Instance.new("Part")
		body.Size = Vector3.new(16, 6, 34)
		body.Color = Color3.fromHex("#d6283b")
		body.Parent = m
		m.PrimaryPart = body
		return m
	end)()
	car.Name = "Car"
	if math.abs(car:GetScale() - Drive.SCALE) > 1e-3 then
		car:ScaleTo(Drive.SCALE)
	end
	-- Wheels on the ground under the avatar's feet, nose the way it faces.
	local feet = root.CFrame * CFrame.new(0, -(root.Size.Y / 2 + humanoid.HipHeight), 0)
	car:PivotTo(feet * CFrame.Angles(0, math.pi, 0))
	for _, d in car:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
		end
	end
	car.Parent = character
	hide(character, true)
	humanoid.WalkSpeed = Drive.SPEED
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	player:SetAttribute("Driving", true)
end

-- A new avatar (after driving off the world's edge, say) starts on foot at walking pace: the old
-- one's car went with it, so the Driving flag goes too.
local Players = game:GetService("Players")
local function watch(player: Player)
	player.CharacterAdded:Connect(function()
		player:SetAttribute("Driving", nil)
	end)
end
Players.PlayerAdded:Connect(watch)
for _, player in Players:GetPlayers() do
	watch(player)
end

return Drive
