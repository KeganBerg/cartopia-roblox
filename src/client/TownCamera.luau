--!strict
-- The town view, as on the web: the camera looks down on the town from the same corner and
-- angle as the web game's (an orthographic camera at (75, 80, 75) looking at the middle), drag to
-- pan, scroll or pinch to zoom. Roblox has no orthographic camera, so this one stands back with a
-- narrowish field of view, which looks close to the same and keeps buildings square. The HUD's
-- camera button swaps in the free camera (setFree), as the web's.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Town = require(script.Parent.Town)
local Mixer = require(script.Parent.Sounds.Mixer)

local TownCamera = {}

local DIR = Vector3.new(75, 80, 75).Unit
-- Narrow enough to look close to the web's flat view, wide enough that the camera stays a few
-- hundred studs away: much further and Roblox can't tell the flat road and lawn layers apart.
local FOV = 30
-- The web's zoom is pixels per web unit (18 to 38, more on bigger screens); here it sets how
-- many studs of town fit the screen's height.
local ZOOM_MIN, ZOOM_MAX = 12, 90
local STUDS_PER_UNIT = 10

local view = Vector3.zero -- the point on the ground the camera looks at
local zoom = 30
local placed = false
-- Off while an edit tool uses drags (laying road, moving a building): see setPanEnabled.
local panEnabled = true
-- Off while another screen drives the camera (the drag race): see setPaused.
local paused = false
-- On while the player walks their town on foot (see setWalking): Roblox's own camera follows them.
local walking = false
-- Told whenever walking starts or stops (the HUD's Walk button).
local walkListeners: { (boolean) -> () } = {}
-- The avatar's controls (PlayerModule), found once the module loads.
local controls: any = nil

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


-- ── Free camera (the web's scene/FreeCam.tsx) ───────────────────────────────────────────────
-- The HUD's camera button swaps the fixed bird's-eye view for one you can zoom, pan, turn and
-- tilt, down to street level, so the fronts of buildings that face away from the usual view come
-- round into sight. One finger (or the left mouse button) drags the ground and a flick glides on;
-- two fingers pinch to zoom, twist to turn, and drag together to tilt and turn; the right mouse
-- button turns and tilts, the wheel zooms; WASD or the arrows fly, Space rises, Shift sinks and
-- Ctrl goes three times as fast. Escape goes back to the bird's-eye view.

-- The web's FREE limits (web units, here times STUDS_PER_UNIT): field of view wide and tall, how
-- close and far it may get, and how low it may tilt (polar angle: 0 straight down).
local FREE = { fovWide = 42, fovTall = 52, minDist = 5 * STUDS_PER_UNIT, maxDist = 170 * STUDS_PER_UNIT, minPolar = 0.12, maxPolar = 1.45 }
-- The opening swoop: down from the bird's-eye angle to one that shows the skyline, swinging half
-- way round, over SWOOP seconds, ending at polar angle SWOOP_TILT and SWOOP_IN as far back.
local SWOOP, SWOOP_TILT, SWOOP_IN = 1.9, 1.26, 0.72
-- How quickly the camera catches up with the gestures, and how quickly a flick coasts to a stop
-- (both per second).
local FOLLOW, COAST = 16, 3.2
-- How high over the ground (and over a building's roof) the camera stays.
local GROUND_GAP = 1.2 * STUDS_PER_UNIT

type Pose = { x: number, z: number, yaw: number, pitch: number, dist: number }
type Rig = {
	cur: Pose,
	goal: Pose,
	vel: { x: number, z: number, yaw: number },
	held: boolean,
	lift: number,
	swoop: { t: number, from: Pose, to: Pose }?,
}
local rig: Rig? = nil
local freeListeners: { (boolean) -> () } = {}
-- Whether the keys may fly the camera (false while a menu is open): see setFreeKeys.
local keysOk: () -> boolean = function()
	return true
end

local function ease(t: number): number
	return if t < 0.5 then 4 * t * t * t else 1 - (-2 * t + 2) ^ 3 / 2
end

local function freeFov(): number
	local size = workspace.CurrentCamera.ViewportSize
	return if size.X < size.Y then FREE.fovTall else FREE.fovWide
end

local function groundY(): number
	local f = Town.folder()
	local origin = f and f:GetAttribute("Origin")
	return if typeof(origin) == "Vector3" then origin.Y else 0
end

-- The spot in view stays over the town and the fields just past it.
local function keepIn(p: Pose)
	local f = Town.folder()
	local origin = f and f:GetAttribute("Origin")
	if typeof(origin) == "Vector3" then
		local reach = 700
		p.x = math.clamp(p.x, origin.X - reach, origin.X + reach)
		p.z = math.clamp(p.z, origin.Z - reach, origin.Z + reach)
	end
	p.pitch = math.clamp(p.pitch, FREE.minPolar, FREE.maxPolar)
	p.dist = math.clamp(p.dist, FREE.minDist, FREE.maxDist)
end

-- The camera's offset from the spot it looks at (three.js's Spherical: phi from straight up,
-- theta round from +Z).
local function offsetOf(p: Pose): Vector3
	local sp = math.sin(p.pitch)
	return Vector3.new(p.dist * sp * math.sin(p.yaw), p.dist * math.cos(p.pitch), p.dist * sp * math.cos(p.yaw))
end

-- The highest roof (a building's Hit box) right over a point, or nil.
local roofParams: RaycastParams? = nil
local function roofAt(x: number, z: number, low: number): number?
	local f = Town.folder()
	local b = f and f:FindFirstChild("Buildings")
	if not b then
		return nil
	end
	local ok, y = pcall(function(): number?
		local params = roofParams or RaycastParams.new()
		roofParams = params
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { b }
		local top = low + 400
		local hit = workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -(top - low), 0), params)
		return if hit then hit.Position.Y else nil
	end)
	return if ok then y else nil
end

-- Whether the player is typing (chat, a name), when the keys aren't for flying.
local function typing(): boolean
	local ok, box = pcall(function()
		return UserInputService:GetFocusedTextBox()
	end)
	return ok and box ~= nil
end

local function keyDown(k: Enum.KeyCode): boolean
	local ok, down = pcall(function()
		return UserInputService:IsKeyDown(k)
	end)
	return ok and down == true
end

-- Puts the camera at a pose: never under the ground, and lifted over a building it would be inside
-- (eased from frame to frame by the rig's lift, as the web's cameraSpot carries it).
local function placeFree(p: Pose, dt: number)
	local cam = workspace.CurrentCamera
	local ground = groundY()
	local at = Vector3.new(p.x, ground, p.z)
	local pos = at + offsetOf(p)
	local want = 0
	local roof = roofAt(pos.X, pos.Z, ground)
	if roof and roof + GROUND_GAP > pos.Y then
		want = roof + GROUND_GAP - pos.Y
	end
	if rig then
		rig.lift += (want - rig.lift) * (1 - math.exp(-8 * dt))
		pos += Vector3.new(0, rig.lift, 0)
	end
	pos = Vector3.new(pos.X, math.max(pos.Y, ground + GROUND_GAP), pos.Z)
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = freeFov()
	cam.CFrame = CFrame.lookAt(pos, at)
	cam.Focus = CFrame.new(at)
	view = Vector3.new(p.x, 0, p.z)
end

-- Keys held down for flying, by name (the emulator's Enum items don't work as table keys).
local FLY_KEYS: { [string]: boolean } = {
	W = true,
	A = true,
	S = true,
	D = true,
	Up = true,
	Down = true,
	Left = true,
	Right = true,
	Space = true,
	LeftShift = true,
	RightShift = true,
	LeftControl = true,
	RightControl = true,
}
local held: { [string]: boolean } = {}

local function stepFree(delta: number)
	local r = rig
	if not r then
		return
	end
	local dt = math.min(delta, 0.1)
	local goal, cur, vel = r.goal, r.cur, r.vel
	-- Opening swoop: anything the player does ends it and takes over from where it got to.
	local w = r.swoop
	if w then
		w.t = math.min(1, w.t + math.min(delta, 0.25) / SWOOP)
		local e = ease(w.t)
		goal.yaw = w.from.yaw + (w.to.yaw - w.from.yaw) * e
		goal.pitch = w.from.pitch + (w.to.pitch - w.from.pitch) * e
		goal.dist = w.from.dist + (w.to.dist - w.from.dist) * e
		cur.x, cur.z, cur.yaw, cur.pitch, cur.dist = goal.x, goal.z, goal.yaw, goal.pitch, goal.dist
		if w.t >= 1 then
			r.swoop = nil
		end
	end
	-- A flick keeps gliding after the finger lifts, slowing to a stop.
	if not r.held and (vel.x ~= 0 or vel.z ~= 0 or vel.yaw ~= 0) then
		goal.x += vel.x * dt
		goal.z += vel.z * dt
		goal.yaw += vel.yaw * dt
		local k = math.exp(-COAST * dt)
		vel.x *= k
		vel.z *= k
		vel.yaw *= k
		if math.sqrt(vel.x * vel.x + vel.z * vel.z) < 0.05 * STUDS_PER_UNIT and math.abs(vel.yaw) < 0.002 then
			vel.x, vel.z, vel.yaw = 0, 0, 0
		end
	end
	-- Keyboard flying: over the ground the way the camera faces, faster the further out it is.
	if next(held) ~= nil then
		if not keysOk() or typing() then
			table.clear(held)
		else
			r.swoop = nil
			local boost = if held.LeftControl or held.RightControl then 3 else 1
			local speed = (12 * STUDS_PER_UNIT + goal.dist * 0.9) * dt * boost
			local fwd = Vector3.new(-math.sin(goal.yaw), 0, -math.cos(goal.yaw))
			local right = fwd:Cross(Vector3.yAxis)
			local move = Vector3.zero
			if held.W or held.Up then
				move += fwd
			end
			if held.S or held.Down then
				move -= fwd
			end
			if held.D or held.Right then
				move += right
			end
			if held.A or held.Left then
				move -= right
			end
			if move.Magnitude > 0 then
				move = move.Unit * speed
				goal.x += move.X
				goal.z += move.Z
			end
			local lift = (if held.Space then 1 else 0) - (if held.LeftShift or held.RightShift then 1 else 0)
			if lift ~= 0 then
				-- Straight up or down over the same spot, so the camera tips to keep it in view.
				local flat = goal.dist * math.sin(goal.pitch)
				local y = math.max(STUDS_PER_UNIT, goal.dist * math.cos(goal.pitch) + lift * speed * 0.7)
				goal.dist = math.sqrt(flat * flat + y * y)
				goal.pitch = math.atan2(flat, y)
			end
		end
	end
	keepIn(goal)
	local f = 1 - math.exp(-FOLLOW * dt)
	cur.x += (goal.x - cur.x) * f
	cur.z += (goal.z - cur.z) * f
	cur.yaw += (goal.yaw - cur.yaw) * f
	cur.pitch += (goal.pitch - cur.pitch) * f
	cur.dist *= (goal.dist / cur.dist) ^ f
	placeFree(cur, dt)
end

-- Free-camera gestures, fed from the town's input handlers. Each pointer down (a finger, or a
-- mouse button) and where it last was.
type Pt = { x: number, y: number, button: Enum.UserInputType }
local pts: { [InputObject]: Pt } = {}
local npts = 0
type Two = { cx: number, cy: number, d: number, a: number, kind: string }
local two: Two? = nil
local last = 0

local function pair(): Two
	local list = {}
	for _, p in pts do
		table.insert(list, p)
	end
	local p, q = list[1], list[2]
	return { cx = (p.x + q.x) / 2, cy = (p.y + q.y) / 2, d = math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2), a = math.atan2(q.y - p.y, q.x - p.x), kind = "pending" }
end

-- Studs per screen pixel at the spot the camera looks at.
local function unit(r: Rig): number
	local h = math.max(1, workspace.CurrentCamera.ViewportSize.Y)
	return 2 * r.cur.dist * math.tan(math.rad(freeFov() / 2)) / h
end

local function pan(r: Rig, dx: number, dy: number, dt: number)
	local u = unit(r)
	-- Up and down the screen covers more ground the lower the camera is tipped.
	local v = u / math.max(0.35, math.cos(r.cur.pitch))
	local sin, cos = math.sin(r.goal.yaw), math.cos(r.goal.yaw)
	-- The ground follows the finger: drag right and the spot in view moves left.
	local mx = -dx * u * cos - dy * v * sin
	local mz = dx * u * sin - dy * v * cos
	r.goal.x += mx
	r.goal.z += mz
	if dt > 0 then
		local k = math.min(1, dt / 0.06)
		r.vel.x += (mx / dt - r.vel.x) * k
		r.vel.z += (mz / dt - r.vel.z) * k
	end
end

local function turn(r: Rig, dyaw: number, dpitch: number, dt: number)
	r.goal.yaw += dyaw
	r.goal.pitch += dpitch
	if dt > 0 then
		r.vel.yaw += (dyaw / dt - r.vel.yaw) * math.min(1, dt / 0.06)
	end
end

local function resetGesture()
	local r = rig
	if r then
		r.vel.x, r.vel.z, r.vel.yaw = 0, 0, 0
	end
	two = if npts == 2 then pair() else nil
	last = os.clock()
end

local function freeBegan(input: InputObject)
	local r = rig
	local kind = input.UserInputType
	if not r or npts >= 2 then
		return
	end
	if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.MouseButton2 then
		return
	end
	pts[input] = { x = input.Position.X, y = input.Position.Y, button = kind }
	npts += 1
	r.swoop = nil
	r.held = true
	resetGesture()
end

local function freeChanged(input: InputObject)
	local r = rig
	if not r then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseWheel then
		r.swoop = nil
		-- A notch of the wheel stands for about a hundred pixels of the web's wheel.
		r.goal.dist *= math.exp(math.clamp(-input.Position.Z * 100, -200, 200) * 0.0015)
		return
	end
	local p = pts[input]
	if kind == Enum.UserInputType.MouseMovement then
		-- The mouse's moves come as their own input: they move the held button's pointer.
		for _, q in pts do
			if q.button ~= Enum.UserInputType.Touch then
				p = q
			end
		end
	end
	if not p then
		return
	end
	local now = os.clock()
	local dt = math.max(0.001, now - last)
	local h = math.max(1, workspace.CurrentCamera.ViewportSize.Y)
	if npts == 1 then
		local dx, dy = input.Position.X - p.x, input.Position.Y - p.y
		p.x, p.y = input.Position.X, input.Position.Y
		last = now
		-- The right button (or Ctrl or Shift with the left) turns and tilts; otherwise drag the ground.
		local mods = keyDown(Enum.KeyCode.LeftControl) or keyDown(Enum.KeyCode.LeftShift)
		if p.button == Enum.UserInputType.MouseButton2 or (p.button == Enum.UserInputType.MouseButton1 and mods) then
			turn(r, -dx * 2 * math.pi / h, -dy * math.pi / h, 0)
		else
			pan(r, dx, dy, dt)
		end
		return
	end
	p.x, p.y = input.Position.X, input.Position.Y
	local t = two
	if not t then
		return
	end
	local n = pair()
	local dcx, dcy = n.cx - t.cx, n.cy - t.cy
	local da = n.a - t.a
	if da > math.pi then
		da -= math.pi * 2
	elseif da < -math.pi then
		da += math.pi * 2
	end
	local ratio = t.d / math.max(1, n.d)
	if t.kind == "pending" then
		-- Until it's clear, measured from where the fingers started: moving together tilts;
		-- moving apart, together or round each other pinches and twists.
		local shift = math.sqrt(dcx * dcx + dcy * dcy)
		local spread = math.abs(n.d - t.d) + math.abs(da) * n.d * 0.5
		if shift > 14 and shift > spread * 1.5 then
			t.kind = "tilt"
		elseif spread > 14 then
			t.kind = "pinch"
		else
			return
		end
	end
	if t.kind == "tilt" then
		turn(r, -dcx * 2 * math.pi / h, -dcy * math.pi / h, dt)
	else
		r.goal.dist *= ratio
		-- Twisting the fingers clockwise turns the town clockwise on screen.
		turn(r, da, 0, dt)
		pan(r, dcx, dcy, dt)
	end
	t.cx, t.cy, t.d, t.a = n.cx, n.cy, n.d, n.a
	last = now
end

local function freeEnded(input: InputObject)
	if not pts[input] then
		return
	end
	pts[input] = nil
	npts -= 1
	local r = rig
	if not r then
		return
	end
	-- Lifting one of two fingers carries on as a one-finger drag from where it is, without a jump.
	if npts == 1 then
		resetGesture()
	elseif npts == 0 then
		r.held = false
		two = nil
		-- A finger that stopped before lifting shouldn't fling.
		if os.clock() - last > 0.08 then
			r.vel.x, r.vel.z, r.vel.yaw = 0, 0, 0
		end
	end
end

function TownCamera.start()
	local player = Players.LocalPlayer
	-- The town is played from above, so the avatar stays put instead of walking off.
	task.spawn(function()
		local ok, found = pcall(function()
			local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
			return module and (require(module :: ModuleScript) :: any):GetControls()
		end)
		if ok and found then
			controls = found
			if not walking then
				controls:Disable()
			end
		end
	end)
	fitZoom()
	-- A new avatar (after a fall off the map, say) keeps the camera on it while walking.
	player.CharacterAdded:Connect(function()
		if walking then
			task.defer(function()
				TownCamera.setPaused(paused)
			end)
		end
	end)

	local dragging: InputObject? = nil
	local grab: Vector3? = nil
	local touches: { [InputObject]: Vector2 } = {}
	local pinch: number? = nil

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if rig and input.UserInputType == Enum.UserInputType.Keyboard then
			if typing() or paused or not keysOk() then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				TownCamera.setFree(false)
			elseif FLY_KEYS[input.KeyCode.Name] then
				held[input.KeyCode.Name] = true
			end
			return
		end
		if processed or paused or walking then
			return
		end
		if rig then
			freeBegan(input)
			return
		end
		-- Left drag (or one finger) pans unless an edit tool wants drags; right drag always pans.
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.MouseButton2 or input.UserInputType == Enum.UserInputType.Touch then
			if input.UserInputType == Enum.UserInputType.Touch then
				touches[input] = Vector2.new(input.Position.X, input.Position.Y)
			end
			dragging = input
			grab = Town.groundAt(Vector2.new(input.Position.X, input.Position.Y))
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if walking then
			return
		end
		if rig then
			if not paused and (input.UserInputType ~= Enum.UserInputType.MouseWheel or not processed) then
				freeChanged(input)
			end
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			zoom = math.clamp(zoom * (1 + input.Position.Z * 0.12), if overview then 1.2 else ZOOM_MIN, ZOOM_MAX)
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
		if dragging and grab and moving and (panEnabled or dragging.UserInputType == Enum.UserInputType.MouseButton2) then
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
		if input.UserInputType == Enum.UserInputType.Keyboard then
			held[input.KeyCode.Name] = nil
		end
		freeEnded(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			touches[input] = nil
			if next(touches) == nil then
				pinch = nil
			end
		end
		if input == dragging or (dragging and input.UserInputType == dragging.UserInputType) then
			dragging = nil
			grab = nil
		end
	end)

	RunService:BindToRenderStep("TownCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if paused or walking then
			return
		end
		if rig then
			stepFree(dt)
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

-- The camera that follows the avatar, for walking.
local function follow()
	local cam = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	if humanoid then
		cam.CameraSubject = humanoid
	end
end

-- Hands the camera to another screen (true) or takes it back (false).
function TownCamera.setPaused(on: boolean)
	paused = on
	-- Another screen (a race, an arcade game) has the camera: the town's music and sounds hush.
	Mixer.hold("camera", on)
	if not on and walking then
		follow()
	end
end

function TownCamera.isWalking(): boolean
	return walking
end

function TownCamera.isPaused(): boolean
	return paused
end

-- Roblox's camera on the avatar again (client/CarDrive hands it back after a drive).
function TownCamera.follow()
	if walking and not paused then
		follow()
	end
end

-- The avatar's controls (PlayerModule's ControlModule), or nil until it has loaded.
function TownCamera.controls(): any
	return controls
end

function TownCamera.onWalking(fn: (boolean) -> ())
	table.insert(walkListeners, fn)
end

-- Walking (true): the avatar walks and jumps around the town with Roblox's usual controls and
-- camera. Back to the town view (false): the view comes back over the middle of their own town.
function TownCamera.setWalking(on: boolean)
	if walking == on then
		return
	end
	-- Walking or driving takes the camera from the free view (the web's FreeCam is town-only too).
	if on then
		TownCamera.setFree(false)
	end
	walking = on
	for _, fn in walkListeners do
		fn(on)
	end
	if controls then
		if on then
			controls:Enable()
		else
			controls:Disable()
		end
	end
	if on then
		follow()
	else
		-- Back over their own town, centred and at the usual zoom, wherever they drove or walked to
		-- (the server takes the avatar home too).
		fitZoom()
		placed = false
		local f = Town.folder()
		if f then
			view = f:GetAttribute("Origin") :: any
			placed = true
		end
		update()
	end
end

-- The view over the whole shared world, zoomed out, for picking a plot (true); back over the
-- player's own town (false).
local overview = false
function TownCamera.setOverview(on: boolean)
	if on then
		TownCamera.setFree(false)
	end
	overview = on
	if on then
		view = Vector3.zero
		zoom = 2.2
	else
		fitZoom()
		placed = false
	end
end

-- Moves the view to look at a world position.
function TownCamera.lookAt(p: Vector3)
	view = Vector3.new(p.X, 0, p.Z)
	clamp()
end

function TownCamera.isFree(): boolean
	return rig ~= nil
end

-- Told whenever the free camera goes on or off (the HUD's camera button).
function TownCamera.onFree(fn: (boolean) -> ())
	table.insert(freeListeners, fn)
end

-- Whether the keys may fly the free camera just now (the HUD says no while a menu is open).
function TownCamera.setFreeKeys(fn: () -> boolean)
	keysOk = fn
end

-- The free camera on (true): it starts where the bird's-eye view was, same angle and framing the
-- same slice of town, then swoops down and half way round. Off (false): back to the bird's-eye
-- view over the spot the free view ended up on.
function TownCamera.setFree(on: boolean)
	if (rig ~= nil) == on or (on and walking) then
		return
	end
	table.clear(held)
	table.clear(pts)
	npts, two = 0, nil
	if on then
		local fov = freeFov()
		local tall = workspace.CurrentCamera.ViewportSize.Y / zoom * STUDS_PER_UNIT
		local dist = math.min(FREE.maxDist, tall / 2 / math.tan(math.rad(fov / 2)))
		local from: Pose = { x = view.X, z = view.Z, yaw = math.atan2(DIR.X, DIR.Z), pitch = math.acos(DIR.Y), dist = dist }
		local to: Pose = { x = from.x, z = from.z, yaw = from.yaw + math.pi, pitch = SWOOP_TILT, dist = dist * SWOOP_IN }
		keepIn(to)
		rig = { cur = table.clone(from), goal = table.clone(from), vel = { x = 0, z = 0, yaw = 0 }, held = false, lift = 0, swoop = { t = 0, from = from, to = to } }
		if not paused then
			placeFree(from, 0)
		end
	else
		local r = rig :: Rig
		rig = nil
		view = Vector3.new(r.cur.x, 0, r.cur.z)
		clamp()
		if not paused and not walking then
			update()
		end
	end
	for _, fn in freeListeners do
		fn(on)
	end
end

return TownCamera
