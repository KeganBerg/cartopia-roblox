--!strict
-- The town view, as on the web: the camera looks down on the town from the same corner and
-- angle as the web game's (an orthographic camera at (75, 80, 75) looking at the middle), drag to
-- pan, scroll or pinch to zoom. Roblox has no orthographic camera, so this one stands back with a
-- narrowish field of view, which looks close to the same and keeps buildings square.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Town = require(script.Parent.Town)

local TownCamera = {}

local DIR = Vector3.new(75, 80, 75).Unit
-- Narrow enough to look close to the web's flat view, wide enough that the camera stays a few
-- hundred studs away: much further and Roblox can't tell the flat road and lawn layers apart.
local FOV = 30
-- The web's zoom is pixels per web unit (18 to 38, more on bigger screens); here it sets how
-- many studs of town fit the screen's height.
local ZOOM_MIN, ZOOM_MAX = 12, 60
local STUDS_PER_UNIT = 10

local view = Vector3.zero -- the point on the ground the camera looks at
local zoom = 30
local placed = false
-- Off while an edit tool uses drags (laying road, moving a building): see setPanEnabled.
local panEnabled = true
-- Off while another screen drives the camera (the drag race): see setPaused.
local paused = false

local function distance(): number
	local cam = workspace.CurrentCamera
	local tall = cam.ViewportSize.Y / zoom * STUDS_PER_UNIT -- studs of ground the screen shows
	return tall / 2 / math.tan(math.rad(FOV / 2))
end

local function update()
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = FOV
	cam.CFrame = CFrame.lookAt(view + DIR * distance(), view)
	cam.Focus = CFrame.new(view)
end

-- Keeps the view over the player's land.
local function clamp()
	local f = Town.folder()
	if not f then
		return
	end
	local origin: Vector3 = f:GetAttribute("Origin") :: any
	local reach = 700
	local d = view - origin
	view = origin + Vector3.new(math.clamp(d.X, -reach, reach), 0, math.clamp(d.Z, -reach, reach))
end

-- Responsive zoom like the web's: bigger screens see a little more.
local function fitZoom()
	local size = workspace.CurrentCamera.ViewportSize
	zoom = math.clamp(math.sqrt(size.X * size.Y) / 24, 18, 38)
end

function TownCamera.start()
	local player = Players.LocalPlayer
	-- The town is played from above, so the avatar stays put instead of walking off.
	task.spawn(function()
		local ok, controls = pcall(function()
			local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
			return module and (require(module :: ModuleScript) :: any):GetControls()
		end)
		if ok and controls then
			controls:Disable()
		end
	end)
	fitZoom()

	local dragging: InputObject? = nil
	local grab: Vector3? = nil
	local touches: { [InputObject]: Vector2 } = {}
	local pinch: number? = nil

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or paused then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if input.UserInputType == Enum.UserInputType.Touch then
				touches[input] = Vector2.new(input.Position.X, input.Position.Y)
			end
			dragging = input
			grab = Town.groundAt(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			zoom = math.clamp(zoom * (1 + input.Position.Z * 0.12), ZOOM_MIN, ZOOM_MAX)
			return
		end
		if input.UserInputType == Enum.UserInputType.Touch and touches[input] then
			touches[input] = Vector2.new(input.Position.X, input.Position.Y)
			local pts = {}
			for _, p in touches do
				table.insert(pts, p)
			end
			if #pts >= 2 then
				-- Two fingers pinch to zoom.
				local d = (pts[1] - pts[2]).Magnitude
				if pinch then
					zoom = math.clamp(zoom * d / pinch, ZOOM_MIN, ZOOM_MAX)
				end
				pinch = d
				grab = nil
				return
			end
		end
		local moving = input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch
		if dragging and grab and moving and panEnabled then
			-- Keep the spot that was grabbed under the pointer.
			local now = Town.groundAt(Vector2.new(input.Position.X, input.Position.Y))
			if now then
				view += Vector3.new(grab.X - now.X, 0, grab.Z - now.Z)
				clamp()
				update()
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = nil
			if next(touches) == nil then
				pinch = nil
			end
		end
		if input == dragging or input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = nil
			grab = nil
		end
	end)

	RunService:BindToRenderStep("TownCamera", Enum.RenderPriority.Camera.Value + 1, function()
		if paused then
			return
		end
		if not placed then
			local f = Town.folder()
			if f then
				view = f:GetAttribute("Origin") :: any
				placed = true
			end
		end
		update()
	end)
end

-- Lets edit tools take drags for themselves (Placement): off, a drag no longer pans the town.
function TownCamera.setPanEnabled(on: boolean)
	panEnabled = on
end

-- Hands the camera to another screen (true) or takes it back (false).
function TownCamera.setPaused(on: boolean)
	paused = on
end

-- Moves the view to look at a world position.
function TownCamera.lookAt(p: Vector3)
	view = Vector3.new(p.X, 0, p.Z)
	clamp()
end

return TownCamera
