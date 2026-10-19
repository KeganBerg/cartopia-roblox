--!strict
-- Turning wheels, as the web game's CarModel turns them: each wheel rolls round its axle with the
-- car's speed, and the front pair swing to the way the car is steering.
--
-- A rig is built once per car from the parts Catalog.WHEELS names, gathered by corner (plus
-- anything sitting inside a wheel, such as a fitted rim mod). Car models face +Z, so the axle is
-- the car's X axis and the front wheels are the ones at +Z.
--
-- Two ways to drive it:
--   - Wheels.follow(rig, pivot, dt) works out the speed and steering from how the car moved since
--     the last frame (traffic, which is moved by its own sim) and puts the wheels in place;
--   - Wheels.turn(rig, dt, speed, steer) and Wheels.into(rig, base, cfs) for a car moved some
--     other way (client/CarDrive's leaning copy of the driven car), filling in its CFrame list.

local Catalog = require(script.Parent.Catalog)

local Wheels = {}

local WHEELS: { [string]: { number } } = (Catalog :: any).WHEELS or {}
-- The furthest the front wheels swing when a car's steering is only guessed from how it moved.
local MAX_STEER = math.rad(32)

type Corner = {
	index: { number }, -- where its parts are in the rig's part list
	rel: { CFrame }, -- each part relative to the rig's frame, as built (unturned)
	centre: Vector3, -- the wheel's middle, in the rig's frame
	front: boolean,
}

export type Rig = {
	parts: { BasePart },
	corners: { Corner },
	radius: number, -- studs, at the car's size when rigged
	base: number, -- wheelbase, studs
	scale: number, -- the model's scale when rigged
	angle: number, -- how far the wheels have rolled (radians)
	steer: number, -- the front wheels' angle, radians, positive to the right
	last: CFrame?, -- where the car was last frame (follow)
}

-- Builds a rig for a car model. `frame` is what part positions are measured from (the model's
-- pivot by default); `list` is the parts the rig indexes into (the model's own by default, or a
-- caller's list whose CFrames it fills in). `restOf(i)`, if given, is where part i sits with the
-- wheels straight (otherwise where it is now), so a car rigged again mid-turn doesn't keep the turn.
-- Returns nil for a car with no wheels in Catalog.
function Wheels.rig(model: Model, carId: string?, frame: CFrame?, list: { BasePart }?, restOf: ((number) -> CFrame)?): Rig?
	local ids = carId and WHEELS[carId]
	if not ids then
		return nil
	end
	local f = frame or model:GetPivot()
	local parts: { BasePart } = list or {}
	if not list then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
	end
	local function cfOf(i: number): CFrame
		return if restOf then restOf(i) else parts[i].CFrame
	end
	-- The named wheel parts, by corner.
	local byKey: { [string]: any } = {}
	local corners: { any } = {}
	-- (Looked up by position in the list, not keyed by instance, so the emulator's instances work.)
	local taken: { [number]: boolean } = {}
	local radius = 0
	for _, n in ids do
		local w = model:FindFirstChild(tostring(n))
		local i = w and w:IsA("BasePart") and table.find(parts, w)
		if not i then
			continue
		end
		local wp = w :: BasePart
		local p = f:PointToObjectSpace(cfOf(i).Position)
		local key = `{if p.X > 0 then 1 else -1},{if p.Z > 0 then 1 else -1}`
		local c = byKey[key]
		if not c then
			c = { index = {}, rel = {}, sum = Vector3.zero, n = 0, front = p.Z > 0, width = 0 }
			byKey[key] = c
			table.insert(corners, c)
		end
		table.insert(c.index, i)
		table.insert(c.rel, f:ToObjectSpace(cfOf(i)))
		c.sum += p
		c.n += 1
		taken[i] = true
		radius = math.max(radius, wp.Size.Y / 2, wp.Size.Z / 2)
	end
	if #corners < 2 then
		return nil
	end
	for _, c in corners do
		c.centre = c.sum / c.n
	end
	-- Anything else sitting inside a wheel turns with it (a rim mod, a hubcap).
	for i, p in parts do
		if taken[i] or math.max(p.Size.X, p.Size.Y, p.Size.Z) > radius * 2.1 then
			continue
		end
		local q = f:PointToObjectSpace(cfOf(i).Position)
		for _, c in corners do
			local d = q - c.centre
			if math.abs(d.X) < 1.5 and Vector2.new(d.Y, d.Z).Magnitude < radius * 0.6 then
				table.insert(c.index, i)
				table.insert(c.rel, f:ToObjectSpace(cfOf(i)))
				break
			end
		end
	end
	local front, back = 0, 0
	for _, c in corners do
		if c.front then
			front = math.max(front, c.centre.Z)
		else
			back = math.min(back, c.centre.Z)
		end
	end
	return {
		parts = parts,
		corners = corners :: any,
		radius = math.max(radius, 0.5),
		base = math.max(front - back, 1),
		scale = model:GetScale(),
		angle = 0,
		steer = 0,
		last = nil,
	}
end

-- Rolls the wheels on by `speed` studs a second (negative backwards) for dt seconds and sets the
-- front wheels' angle (radians, positive to the right).
function Wheels.turn(r: Rig, dt: number, speed: number, steer: number)
	r.angle = (r.angle + speed * dt / r.radius) % (2 * math.pi)
	r.steer = steer
end

-- Each wheel part's CFrame for the car standing at `base`, written into `cfs` at the part's place
-- in the rig's list.
function Wheels.into(r: Rig, base: CFrame, cfs: { CFrame })
	-- Rolling forward (+Z) turns the top of the wheel forward: round +X. Steering right turns the
	-- nose towards -X: round -Y.
	local roll = CFrame.Angles(r.angle, 0, 0)
	local swing = CFrame.Angles(0, -r.steer, 0)
	for _, c in r.corners do
		local spin = CFrame.new(c.centre) * (if c.front then swing * roll else roll) * CFrame.new(-c.centre)
		for k, i in c.index do
			cfs[i] = base * spin * c.rel[k]
		end
	end
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- For a car its own sim moves: from where it is now (`pivot`) and where it was last frame, its
-- speed and steering, then the wheels put in place. Call it after the car is moved each frame.
function Wheels.follow(r: Rig, model: Model, pivot: CFrame, dt: number)
	local last = r.last
	r.last = pivot
	if not last or dt <= 0 then
		return
	end
	if math.abs(model:GetScale() - r.scale) > 1e-3 then
		-- Grown or shrunk since it was rigged (fading in): too fiddly to follow, so it waits.
		return
	end
	local step = pivot.Position - last.Position
	if step.Magnitude > 60 then
		-- Jumped (respawned somewhere else): nothing to follow.
		return
	end
	local fwd = pivot:VectorToWorldSpace(Vector3.zAxis)
	local speed = step:Dot(fwd) / dt
	local lf, nf = last:VectorToWorldSpace(Vector3.zAxis), fwd
	-- Positive when turning right (the nose swinging towards the car's -X).
	local yawRate = -wrap(math.atan2(nf.X, nf.Z) - math.atan2(lf.X, lf.Z)) / dt
	local want = if math.abs(speed) > 1 then math.clamp(math.atan(yawRate * r.base / speed), -MAX_STEER, MAX_STEER) else r.steer
	Wheels.turn(r, dt, speed, r.steer + (want - r.steer) * math.min(1, dt * 8))
	local cfs = table.create(#r.parts)
	local moved: { BasePart } = {}
	local list: { CFrame } = {}
	Wheels.into(r, pivot, cfs)
	for i, cf in cfs do
		local p = r.parts[i]
		if p.Parent then
			table.insert(moved, p)
			table.insert(list, cf)
		end
	end
	workspace:BulkMoveTo(moved, list, Enum.BulkMoveMode.FireCFrameChanged)
end

return Wheels
