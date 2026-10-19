--!strict
-- Townspeople figures standing about and walking on a building's own lot: the schoolkids, runners
-- and students of CampusLife and the funfair's visitors (FairCrowd). The web game draws those with
-- its own instanced figures at its 1.3x people scale; here they're TownLife's townspeople (same
-- look, at a Roblox character's height), so the lots' people match the ones on the pavements.
--
-- The lots' web code says where each person is at a time (a point in the lot's web units); this
-- turns that into a TownLife person: placed through the building's frame, facing the way they're
-- going, legs stepping with the ground they cover (so a slow stroll is a slow stroll, not quick
-- little steps on the spot), jogging when they're going at a run.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local TownLife = require(script.Parent.TownLife) :: any

local LotPeople = {}

local S = Catalog.SCALE -- studs per web unit
local K = TownLife._K :: number -- studs per figure unit, for a grown-up
-- Slower than this (studs a second) and they're standing; faster, and it's a jog.
local STAND = 0.5
local RUN = 3.6

export type Opts = { kids: boolean?, uniform: string?, jog: boolean? }
export type Crowd = { people: { any }, jog: boolean, size: number }

-- `n` people for a lot, ids starting `id` (each id gives a person their own look, the same every
-- time). `kids`: schoolkids (smaller); `uniform`: everyone's shirt (a team's tee); `jog`: always
-- jogging when they move (runners on a track).
function LotPeople.new(parent: Instance, id: string, n: number, opts: Opts?): Crowd
	local o = opts or {}
	local size = if o.kids then 0.72 else 1
	local people = {}
	for i = 1, n do
		-- The number leads, so the hash TownLife picks a look from differs all through (ids that
		-- differ only in their last letter would all get the same hair and trousers).
		local p = TownLife._person(`{i * 7919}:{id}`, "", { 0, 0 })
		-- No dogs on the lot; runners get the jogger's sweatband and a tee.
		p.type = if o.jog then "jogger" else "walker"
		if o.jog or o.uniform then
			p.look.top = "tee"
		end
		if o.uniform then
			p.colors.shirt = o.uniform
		end
		p.size = size
		p.state = "linger"
		p.fig = TownLife._figure(p, parent)
		table.insert(people, p)
	end
	return { people = people, jog = o.jog == true, size = size }
end

local function turnTo(p: any, want: number, dt: number)
	local d = (want - p.heading + math.pi) % (math.pi * 2) - math.pi
	p.heading += d * math.min(1, dt * 10)
end

-- Places person `i` walking: at lot point (x, z) now and (x2, z2) 0.08 s on (where the web reads
-- its heading and speed from), feet at height `y`, all in the lot's web units; `frame` is the
-- building's (its middle on the ground, turned) and `yaw` how far it's turned.
function LotPeople.walk(c: Crowd, i: number, frame: CFrame, yaw: number, y: number, x: number, z: number, x2: number, z2: number, dt: number)
	local p = c.people[i]
	local at = frame * Vector3.new(x * S, y * S, z * S)
	p.pos[1], p.pos[2], p.y = at.X / S, at.Z / S, at.Y
	local dx, dz = x2 - x, z2 - z
	local speed = math.sqrt(dx * dx + dz * dz) / 0.08 * S -- studs a second
	if speed < STAND then
		p.state = "linger"
		return
	end
	p.state = "walk"
	p.waited = 0
	local jog = c.jog or speed > RUN
	if not c.jog then
		p.type = if jog then "jogger" else "walker"
	end
	turnTo(p, math.atan2(dx, dz) + yaw, dt)
	-- About one stride a step's length, as TownLife's townspeople step (shorter legs, more steps).
	p.stride += speed * dt / (K * c.size) * (if jog then 10 else 14)
end

-- Places person `i` standing at lot point (x, z), feet at `y`, facing `face` (0 is the lot's +z).
function LotPeople.stand(c: Crowd, i: number, frame: CFrame, yaw: number, y: number, x: number, z: number, face: number)
	local p = c.people[i]
	local at = frame * Vector3.new(x * S, y * S, z * S)
	p.pos[1], p.pos[2], p.y = at.X / S, at.Z / S, at.Y
	p.state = "linger"
	p.heading = face + yaw
end

-- Takes person `i` off the lot (gone home for the night).
function LotPeople.hide(c: Crowd, i: number)
	c.people[i].state = "inside"
end

-- Adds every person's parts to BulkMoveTo's lists. `eye`: the camera's position (people far from
-- it leave their faces' small features off); `time` keeps the idle ones looking about.
function LotPeople.draw(c: Crowd, time: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	for _, p in c.people do
		TownLife._draw(Vector3.new(0, p.y or 0, 0), p, time, eye, list, cfs)
	end
end

---------------------------------------------------------------------------------------------------

function LotPeople.smallScreen(): boolean
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 700
end

-- Where a building model TownView drew stands: its middle on the ground, turned as it was turned
-- (as SpeedwayLife finds its Speedways), and how far it's turned.
function LotPeople.frameOf(model: Model): (CFrame?, number)
	local hit = model:FindFirstChild("Hit") :: BasePart?
	local turn = model:GetAttribute("Turn")
	if not hit or type(turn) ~= "number" then
		return nil, 0
	end
	local p = hit.CFrame.Position
	local yaw = turn * math.pi / 2
	return CFrame.new(p.X, p.Y - hit.Size.Y / 2, p.Z) * CFrame.Angles(0, yaw, 0), yaw
end

return LotPeople
