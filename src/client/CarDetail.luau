--!strict
-- The townsfolk's and road traffic's cars, up close and far off (client/TownLife, client/WorldLife).
--
-- Each is the game's real car model (Builder), so a car built before its meshes reached this player
-- has stand-in boxes; CarDetail.upgrade swaps it for the real thing once they're all in.
--
-- Level of detail, so a road full of cars stays smooth on a phone: once a car's small pieces
-- (lights, mirrors, badges, hubcaps, handles) would be only a couple of pixels on screen, they're
-- hidden and the car stops casting shadows. Close up, everything shows. It goes by size on screen,
-- not distance, so the town's camera (standing well back, zoomed in) still sees the whole car.
--
-- The wheels roll with the car's speed and the front ones steer (shared/Models/Wheels), but only
-- on cars near enough to show their detail.
--
-- Each car's layout (every piece relative to its pivot) is kept as first seen, and a car whose
-- pieces have come apart from its pivot is put back together before its wheels are placed. The
-- town's cars are the server's models moved here on the client, and an update from the server
-- can land some pieces back where the server has them: before, that left the body somewhere else
-- and the wheels on the road on their own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Models = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models")
local Builder = require(Models:WaitForChild("Builder")) :: any
local Wheels = require(Models:WaitForChild("Wheels"))

local CarDetail = {}

-- Pieces no bigger than this (studs, longest side, as built) count as small.
local SMALL = 1.6
-- Pixels a small piece spans on screen below which the car drops its detail, and above which it
-- gets it back (a gap, so it doesn't flicker at the edge).
local DROP, KEEP = 2.5, 3.2

export type Detail = {
	model: Model,
	small: { BasePart },
	shadows: { BasePart },
	far: boolean,
	boxed: boolean,
	wheels: Wheels.Rig? | false, -- made the first time they turn (false: the car has none)
	parts: { BasePart }, -- every piece, and each relative to the pivot, as first seen
	rest: { CFrame },
	restScale: number,
	anchor: number, -- the biggest piece (the body), checked each frame
	next: number, -- the next few pieces checked (a few each frame, round the car)
}

-- Sorts a freshly built car's pieces for CarDetail.lod. Call it before the car is scaled.
function CarDetail.track(model: Model): Detail
	local small, shadows = {}, {}
	local parts, rest = {}, {}
	local pivot = model:GetPivot()
	local anchor, biggest = 0, -1
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
			table.insert(rest, pivot:ToObjectSpace(d.CFrame))
			if d.Size.Magnitude > biggest then
				anchor, biggest = #parts, d.Size.Magnitude
			end
			local s = d.Size
			if math.max(s.X, s.Y, s.Z) <= SMALL then
				table.insert(small, d)
			end
			if d.CastShadow then
				table.insert(shadows, d)
			end
		end
	end
	return {
		model = model,
		small = small,
		shadows = shadows,
		far = false,
		boxed = Builder.boxed(model),
		wheels = nil,
		parts = parts,
		rest = rest,
		restScale = model:GetScale(),
		anchor = anchor,
		next = 1,
	}
end

local function setFar(d: Detail, far: boolean)
	d.far = far
	for _, p in d.small do
		p.LocalTransparencyModifier = if far then 1 else 0
	end
	for _, p in d.shadows do
		p.CastShadow = not far
	end
end

-- Shows or hides a car's small pieces for how far it is from the camera.
function CarDetail.lod(d: Detail, distance: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	-- Pixels a stud spans at that distance.
	local perStud = cam.ViewportSize.Y / (2 * math.max(distance, 1) * math.tan(math.rad(cam.FieldOfView) / 2))
	local px = SMALL * d.model:GetScale() * perStud
	if d.far and px > KEEP then
		setFar(d, false)
	elseif not d.far and px < DROP then
		setFar(d, true)
	end
end

-- A piece's place for the car standing at `pivot`, from its layout as first seen.
local function placeOf(d: Detail, pivot: CFrame, i: number, k: number): CFrame
	local r = d.rest[i]
	return pivot * (r - r.Position + r.Position * k)
end

-- Pieces checked each frame besides the body.
local CHECKS = 4

-- Puts a car's pieces back together round its pivot if they've come apart (see the top). Checks
-- the body and a few other pieces each frame, so any piece is looked at within a few frames.
local function settle(d: Detail, pivot: CFrame)
	local n = #d.parts
	if n == 0 then
		return
	end
	local k = d.model:GetScale() / d.restScale
	local function off(i: number): boolean
		local p = d.parts[i]
		return p.Parent ~= nil and (p.CFrame.Position - placeOf(d, pivot, i, k).Position).Magnitude > 0.5 * k + 0.05
	end
	local apart = off(d.anchor)
	for _ = 1, math.min(CHECKS, n) do
		if apart then
			break
		end
		local i = d.next
		d.next = i % n + 1
		-- A wheel is turned round its own middle, which doesn't move it, so it's checked too.
		apart = off(i)
	end
	if not apart then
		return
	end
	local list, cfs = {}, {}
	for i, p in d.parts do
		if p.Parent then
			table.insert(list, p)
			table.insert(cfs, placeOf(d, pivot, i, k))
		end
	end
	workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	-- Whatever the wheels had measured is off now too.
	if d.wheels then
		d.wheels = nil
	end
end

-- Rolls and steers a car's wheels for where it is now (call after moving it each frame). Cars too far
-- off to show their detail are left be; a car the player has taken isn't moving, so isn't called.
-- First it makes sure the car is in one piece.
function CarDetail.wheels(d: Detail, pivot: CFrame, dt: number)
	settle(d, pivot)
	if d.far or d.boxed then
		if d.wheels then
			d.wheels.last = nil
		end
		return
	end
	if d.wheels and math.abs(d.model:GetScale() - d.wheels.scale) > 1e-3 then
		-- Grown or shrunk (fading in or out): rigged again at its new size.
		d.wheels = nil
	end
	if d.wheels == nil then
		local id = d.model:GetAttribute("Model")
		-- Rigged from the car's layout as first seen, wheels straight.
		local k = d.model:GetScale() / d.restScale
		d.wheels = (type(id) == "string" and Wheels.rig(d.model, id, pivot, d.parts, function(i: number): CFrame
			return placeOf(d, pivot, i, k)
		end)) or false
	end
	if d.wheels then
		Wheels.follow(d.wheels, d.model, pivot, dt)
	end
end

-- Whether a car with stand-in boxes can now be built for real (all its meshes have arrived).
function CarDetail.ready(d: Detail): boolean
	return d.boxed and Builder.complete(d.model:GetAttribute("Model") :: string)
end

-- Puts `fresh` (a new build of the same car, tracked as `nd`) where the old one is, with its name,
-- attributes, size and place in the world, and drops the old one. Returns the new detail.
function CarDetail.swap(d: Detail, fresh: Model, nd: Detail): Detail
	local old = d.model
	fresh.Name = old.Name
	for k, v in old:GetAttributes() do
		fresh:SetAttribute(k, v)
	end
	if math.abs(fresh:GetScale() - old:GetScale()) > 1e-3 then
		fresh:ScaleTo(old:GetScale())
	end
	fresh:PivotTo(old:GetPivot())
	fresh.Parent = old.Parent
	old:Destroy()
	if d.far then
		setFar(nd, true)
	end
	return nd
end

return CarDetail
