--!strict
-- The life at the merged Fresh Mart and the merged motel at their last form (level 7-10): the web
-- game's Fresh Mart Supercenter (scene/MarketCenter.tsx) and Palm Cove Resort
-- (scene/ResortCenter.tsx). Neither model moves anything of its own on the web: what moves there is
-- the townspeople, who walk from the street across the lot to the big store's doors and in
-- (game/storeDoors.ts, Townspeople.tsx doorIn/doorOut), and the glass doors, which slide apart
-- while someone steps through (DoorLeaves.tsx, doors.ts holdOpen/tickDoors). That is what this
-- draws: shoppers and hotel guests coming along the sidewalk, turning in, waiting for the doors to
-- part, going in, and coming back out a while later to walk off along the street.
--
-- What it walks up to is what the server drew (TownView), not the web's centre: the Roblox models
-- are exported at level 1 only (tools/models/export.test.tsx), so a merged level 7-10 market or
-- motel is the level 1 model grown to fill the block, and the supercenter's car park, garden and
-- pylon and the resort's wings and pool aren't drawn at all. So the walk is the web's (sidewalk,
-- straight out in front of the doors, wait just outside, in), to the doors of the model as drawn
-- (DOORS below), the way doors.ts reads every door from the model it shows.
--
-- The web's shoppers are the town's own residents and come and go from their homes; here each
-- centre has a few of its own (TownLife's townspeople look), who fade in and out at the ends of
-- the block along the sidewalk. It all runs on this player's client and never changes
-- the game. Kept cheap for phones: fewer people there, each figure's parts and the three door
-- parts are made once and moved with the rest of the town's centres in one BulkMoveTo, and a centre
-- far from the camera isn't moved at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local Builder = require(Shared.Models:WaitForChild("Builder")) :: any
local data = require(Game:WaitForChild("data")) :: any
local growth = require(Game:WaitForChild("growth")) :: any
local clock = require(Game:WaitForChild("clock")) :: any
local TownLife = require(script.Parent:WaitForChild("TownLife")) :: any

local CenterLife = {}

local S = Catalog.SCALE -- studs per web unit
local TILE = data.TILE

-- The doors of each model the server may draw for these blocks, on the model's own frame at its
-- own size, in studs (read off Catalog's parts: the door panel and the step in front of it):
-- the middle of the doorway along x, its outside face (z), width, height and sill, and the step
-- (its width, front to back, and its top). The model faces +z, its street. A model not listed
-- (a later export with the real centre, say) gets no life here until its doors are added.
type DoorSpec = { x: number, z: number, w: number, h: number, y: number, stepW: number, stepZ0: number, stepZ1: number, stepTop: number }
local DOORS: { [string]: DoorSpec } = {
	-- Fresh Mart's sliding doors (NewBuildings.tsx 'market', door="slide").
	["market@1"] = { x = 0, z = 3.9, w = 3.8, h = 6, y = 0.2, stepW = 6, stepZ0 = 3.6, stepZ1 = 5.8, stepTop = 1 },
	-- The motel's lobby doors.
	["motel@1"] = { x = 0, z = 6.6, w = 4, h = 6, y = 0.2, stepW = 6, stepZ0 = 6.3, stepZ1 = 8.5, stepTop = 1 },
}

-- Who comes and goes at each: how many (on a phone), how long they stay inside (seconds) and
-- how long before someone new comes along once they've gone.
type Kind = { count: number, phone: number, stay: { number }, gone: { number } }
local KINDS: { [string]: Kind } = {
	-- Townspeople.tsx: a shop visit is 5-12 s inside.
	market = { count = 5, phone = 3, stay = { 5, 12 }, gone = { 2, 8 } },
	-- Guests check in and stay a little longer, and come by less often.
	motel = { count = 3, phone = 2, stay = { 8, 20 }, gone = { 4, 12 } },
}

-- Townspeople.tsx: how far inside a door people vanish, and how far out they wait for a sliding
-- door to open; doors.ts: how fast doors open and close (fractions of fully open a second), and
-- how long one stays held open after the last person through.
local INSIDE = 0.25
local WAIT_AT = 0.3
local OPENS, CLOSES, HOLD = 2.6, 1.6, 0.7
-- walkGraph.ts: the middle of the sidewalk, this far into the road from the lot's edge.
local SIDEWALK = 0.2
-- The paved lot's top (TownView's Lot), in web units.
local LOT = 0.02
-- Walking pace, web units a second at the web's figure size (Townspeople.tsx's 0.65-0.9, a
-- touch slower for people with shopping on their mind), scaled to our figures as TownLife does.
local PACE = { 0.6, 0.85 }
-- How close (web units) people let the one in front of them get.
local AHEAD = 0.22
-- How far along the sidewalk (web units) people fade in and out at the ends of the block.
local FADE = 0.35
-- From further than this (studs), nobody can see who's at the doors: the centre isn't moved.
local FAR = 900

local HIDDEN = CFrame.new(0, -10000, 0)
-- DoorLeaves.tsx: the doorway's colour by day and lit up after dark, and the glass panels'.
local DAY_IN = Color3.fromHex("#2b1f17")
local NIGHT_IN = Color3.fromHex("#f2b45a")
local GLASS = "#4f7f8c"

-- TownLife's figure scale: FIT is how much smaller than the web's townspeople ours are (K studs a
-- model unit; Townspeople.tsx scale 1.3).
local K = 5.3 / 0.69
local FIT = K / (1.3 * S)

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function part(parent: Instance, size: Vector3, color: string, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = HIDDEN
	p.Color = Color3.fromHex(color)
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

---------------------------------------------------------------------------------------------------
-- The block and its doors, on the block's own frame in web units (x along its front, +z towards
-- the road, its middle at 0).

-- One way in: the doorway's middle on its outside face, its size, the step in front, and the
-- sidewalk people come along (`edge`, from `x0` to `x1`). `open` and `until` are doors.ts's.
type Door = {
	x: number,
	z: number,
	w: number,
	h: number,
	y: number,
	stepX: number,
	stepW: number,
	stepZ0: number,
	stepZ1: number,
	stepTop: number,
	edge: number,
	x0: number,
	x1: number,
	open: number,
	hold: number,
	parts: { BasePart },
	shown: boolean,
}

-- Where the copies of the model stand in a merged block of `merged` buildings, `w` by `d` tiles
-- on the model's own frame (merge.ts groupScale/groupParts, as TownView draws them): each copy's
-- middle (web units) and how much it grew. A 2x4 is two 2x2s side by side; when they stand one
-- behind the other, the back one's doors open onto the front one's back wall, so only the front
-- one's are kept.
type Copy = { x: number, z: number, sx: number, sy: number, sz: number }
local function copies(merged: number, w: number, d: number): { Copy }
	-- The market's and motel's own lot is 2 tiles wide and 1 deep.
	local sx, sz = w / 2, d
	if merged == 8 then
		if w >= d * 2 then
			return {
				{ x = -w * TILE / 4, z = 0, sx = 2, sy = 2, sz = 2 },
				{ x = w * TILE / 4, z = 0, sx = 2, sy = 2, sz = 2 },
			}
		end
		return { { x = 0, z = d * TILE / 4, sx = 2, sy = 2, sz = 2 } }
	end
	-- Squares grow evenly; a pair grows longer (or deeper) at the same height.
	return { { x = 0, z = 0, sx = sx, sy = if sx == sz then sx else 1, sz = sz } }
end
CenterLife._copies = copies

-- The doors of a `name` model in a block `w` by `d` tiles of `merged` buildings.
local function doorsOf(name: string, merged: number, w: number, d: number): { Door }
	local spec = DOORS[name]
	if not spec then
		return {}
	end
	local out = {}
	local front = d * TILE / 2
	for _, c in copies(merged, w, d) do
		local x = c.x + spec.x * c.sx / S
		table.insert(out, {
			x = x,
			z = c.z + spec.z * c.sz / S,
			w = spec.w * c.sx / S,
			h = spec.h * c.sy / S,
			y = spec.y * c.sy / S,
			stepX = x,
			stepW = spec.stepW * c.sx / S,
			stepZ0 = c.z + spec.stepZ0 * c.sz / S,
			stepZ1 = c.z + spec.stepZ1 * c.sz / S,
			stepTop = spec.stepTop * c.sy / S,
			edge = front + SIDEWALK,
			-- Along the sidewalk to the ends of the block.
			x0 = -w * TILE / 2,
			x1 = w * TILE / 2,
			open = 0,
			hold = 0,
			parts = {},
			shown = false,
		})
	end
	return out
end
CenterLife._doorsOf = doorsOf

-- How high the ground is under (x, z): the lot, or the step up to a door (with a short ramp up
-- its front so nobody pops up it).
local function groundAt(doors: { Door }, x: number, z: number): number
	for _, d in doors do
		if math.abs(x - d.stepX) <= d.stepW / 2 and z >= d.stepZ0 and z <= d.stepZ1 + 0.08 then
			local k = math.clamp((d.stepZ1 + 0.08 - z) / 0.08, 0, 1)
			return LOT + (d.stepTop - LOT) * k
		end
	end
	return LOT
end

---------------------------------------------------------------------------------------------------
-- One centre's comings and goings.

-- A leg of a walk: a point on the block's frame, and the door it goes through, if any.
type Leg = { x: number, z: number, door: Door? }
type Visitor = {
	p: any, -- TownLife's person: its look, figure and stride; pos and heading set when drawn
	x: number,
	z: number,
	heading: number,
	state: string, -- "away", "walk" (in or out), "inside"
	going: string, -- "in" or "out"
	timer: number,
	steps: { Leg },
	si: number,
	door: Door,
	passing: boolean,
	-- Where along the sidewalk they come from or go to, and how faded they are there (0 to 1).
	far: number,
	fade: number,
	-- How long they've been waiting for someone in the way.
	held: number,
}

export type Life = {
	folder: Folder,
	frame: CFrame,
	yaw: number,
	kind: Kind,
	doors: { Door },
	people: { Visitor },
	step: (self: Life, now: number, dt: number, night: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame }) -> (),
	destroy: (self: Life) -> (),
}

local Life = {}
Life.__index = Life

-- Builds the life at a `def` centre ("market" or "motel") drawn as `name`, a block of `merged`
-- buildings `w` by `d` tiles on its own frame, whose middle on the ground is `frame` turned
-- `turn` quarter turns. `small`: a phone, with fewer people about.
function CenterLife.new(parent: Instance, frame: CFrame, turn: number, def: string, name: string, merged: number, w: number, d: number, small: boolean?): Life?
	local kind = KINDS[def]
	local doors = doorsOf(name, merged, w, d)
	if not kind or #doors == 0 then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "CenterLife"
	-- The doorway and two glass panels for each door, out of sight until it opens.
	for _, door in doors do
		door.parts = {
			part(folder, Vector3.new(door.w * 0.98 * S, door.h * 0.98 * S, 0.05), "#2b1f17"),
			part(folder, Vector3.new(door.w / 2 * S, door.h * S, 0.03 * S), GLASS, 0.25),
			part(folder, Vector3.new(door.w / 2 * S, door.h * S, 0.03 * S), GLASS, 0.25),
		}
	end
	local people = {}
	local n = if small then kind.phone else kind.count
	local seed = math.floor(frame.Position.X * 7 + frame.Position.Z * 13)
	for i = 1, n * #doors do
		local door = doors[(i - 1) % #doors + 1]
		local p = TownLife._person(`c{i * 7919 + seed}:{def}`, "center", { 0, 0 })
		-- No joggers or dogs going in to the shops.
		p.type = "walker"
		p.speed = rand(PACE[1], PACE[2])
		p.fig = TownLife._figure(p, folder)
		-- Some already inside, the rest on their way along at staggered times.
		local inside = i % 2 == 0
		table.insert(people, {
			p = p,
			x = 0,
			z = 0,
			heading = 0,
			state = if inside then "inside" else "away",
			going = "in",
			timer = if inside then rand(0.5, kind.stay[2]) else rand(0, kind.gone[2]),
			steps = {},
			si = 1,
			door = door,
			passing = false,
			far = 0,
			fade = 0,
			held = 0,
		})
	end
	folder.Parent = parent
	local self = setmetatable({
		folder = folder,
		frame = frame,
		yaw = turn * math.pi / 2,
		kind = kind,
		doors = doors,
		people = people,
	}, Life)
	return (self :: any) :: Life
end

-- doors.ts holdOpen: keeps a door opening (or open) a little longer; how open it is now.
local function holdOpen(d: Door, now: number): number
	d.hold = now + HOLD
	return d.open
end

-- Sets off along the sidewalk from one end, to straight out in front of the doors, up to them
-- and in (Townspeople.tsx doorIn).
local function comeIn(v: Visitor)
	local d = v.door
	local from = if math.random() < 0.5 then d.x0 else d.x1
	-- In on the right-hand side of the doors (the supercenter's IN door) and out on the left, not
	-- all on one line, and spread across the sidewalk a little.
	local x = d.x + rand(0.05, 0.3) * d.w
	-- Keeping to the lot side of the sidewalk, so people leaving pass on the road side.
	local edge = d.edge - rand(0.09, 0.13)
	v.x, v.z = from, edge
	v.far = from
	v.heading = if from < x then math.pi / 2 else -math.pi / 2
	v.steps = {
		{ x = x, z = edge },
		{ x = x, z = d.z + WAIT_AT },
		{ x = x, z = d.z - INSIDE, door = d },
	}
	v.si = 1
	v.state = "walk"
	v.going = "in"
	v.passing = false
	v.p.stride = rand(0, 6)
end

-- Out through the doors from just inside, back to the sidewalk and off along it either way
-- (Townspeople.tsx doorOut).
local function goOut(v: Visitor)
	local d = v.door
	local x = d.x - rand(0.05, 0.3) * d.w
	local edge = d.edge + rand(0.09, 0.13)
	v.x, v.z = x, d.z - INSIDE
	v.far = if math.random() < 0.5 then d.x0 else d.x1
	v.heading = 0
	v.steps = {
		{ x = x, z = d.z + WAIT_AT, door = d },
		{ x = x, z = edge },
		{ x = v.far, z = edge },
	}
	v.si = 1
	v.state = "walk"
	v.going = "out"
	v.passing = false
end

local function turnTo(v: Visitor, target: number, dt: number)
	local diff = target - v.heading
	diff = math.atan2(math.sin(diff), math.cos(diff))
	v.heading += diff * math.min(1, dt * 10)
end

-- One visitor's next moment (Townspeople.tsx update, for a walk to a door and back).
-- Is someone just ahead of `v` (the `i`th) in the way? Then `v` waits a moment rather than walking
-- into them (the web's townspeople pass through each other; here a few share one short walk, so
-- they'd bunch up in it). Someone going the same way is followed; where two paths cross, the one
-- listed first goes first; people coming the other way keep to their own side of the doors.
local function blocked(v: Visitor, i: number, all: { Visitor }): boolean
	local hx, hz = math.sin(v.heading), math.cos(v.heading)
	for j, o in all do
		if j ~= i and o.state == "walk" then
			local dx, dz = o.x - v.x, o.z - v.z
			if dx * dx + dz * dz < AHEAD * AHEAD and dx * hx + dz * hz > 0 then
				local c = math.cos(o.heading - v.heading)
				if c > 0.5 or (c > -0.5 and j < i) then
					return true
				end
			end
		end
	end
	return false
end

local function move(v: Visitor, i: number, kind: Kind, now: number, dt: number, all: { Visitor })
	if v.state ~= "walk" then
		v.timer -= dt
		if v.timer <= 0 then
			if v.state == "away" then
				comeIn(v)
			else
				goOut(v)
			end
		end
		return
	end
	local leg = v.steps[v.si]
	if not leg then
		if v.going == "in" then
			v.state = "inside"
			v.timer = rand(kind.stay[1], kind.stay[2])
		else
			v.state = "away"
			v.timer = rand(kind.gone[1], kind.gone[2])
		end
		return
	end
	local p = v.p
	p.waited = 0
	if leg.door then
		-- Wait for the doors to part, then keep them open while stepping through.
		local open = holdOpen(leg.door, now)
		if not v.passing and open < 0.8 then
			turnTo(v, math.atan2(leg.x - v.x, leg.z - v.z), dt)
			p.waited = 1
			return
		end
		v.passing = true
	else
		-- Open them as people come up, so nobody stands about.
		local next = v.steps[v.si + 1]
		if next and next.door and math.sqrt((leg.x - v.x) ^ 2 + (leg.z - v.z) ^ 2) < 0.7 then
			holdOpen(next.door, now)
		end
	end
	-- (Not for long: after a couple of seconds they carry on regardless.)
	if not v.passing and v.held < 2 and blocked(v, i, all) then
		v.held += dt
		p.waited = 1
		return
	end
	v.held = 0
	local dx, dz = leg.x - v.x, leg.z - v.z
	local len = math.sqrt(dx * dx + dz * dz)
	-- TownLife's pace: the web's speed at our figures' size, an easy stroll of about 4 studs a second.
	local step = p.speed * FIT * dt
	if len <= step then
		v.x, v.z = leg.x, leg.z
		if leg.door then
			v.passing = false
		end
		v.si += 1
	else
		v.x += dx / len * step
		v.z += dz / len * step
		turnTo(v, math.atan2(dx, dz), dt)
	end
	-- Legs keep pace with the ground (TownLife's stride), so feet don't skate.
	p.stride += step * S / K * 14
end

-- The doorway and its glass panels (DoorLeaves.tsx 'slide'): two panels part from the middle along
-- the outside of the wall, over a doorway dark by day and lit warm after dark.
local function drawDoor(self: Life, d: Door, night: number, list: { BasePart }, cfs: { CFrame })
	if d.open <= 0 then
		if d.shown then
			d.shown = false
			for _, x in d.parts do
				table.insert(list, x)
				table.insert(cfs, HIDDEN)
			end
		end
		return
	end
	d.shown = true
	local e = d.open * d.open * (3 - 2 * d.open)
	local gap = d.parts[1]
	gap.Color = DAY_IN:Lerp(NIGHT_IN, night * 0.75)
	local function at(x: number, y: number, z: number): CFrame
		return self.frame * CFrame.new(x * S, y * S, z * S)
	end
	table.insert(list, gap)
	table.insert(cfs, at(d.x, d.y + d.h / 2, d.z) * CFrame.new(0, 0, 0.05))
	for i, s in { -1, 1 } do
		local along = s * (d.w / 2) * e
		local left = d.x + along + (if s < 0 then -d.w / 2 else 0)
		table.insert(list, d.parts[i + 1])
		table.insert(cfs, at(left + d.w / 4, d.y + d.h / 2, d.z + 0.015) * CFrame.new(0, 0, 0.1))
	end
end

-- Moves everyone on to `now` (seconds), opens and closes the doors, and adds what moved to
-- BulkMoveTo's lists. `night`: how dark it is (0 to 1); `eye`: the camera, for figures' detail.
function Life.step(self: Life, now: number, dt: number, night: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	for i, v in self.people do
		move(v, i, self.kind, now, dt, self.people)
	end
	-- doors.ts tickDoors: open while held, then close.
	for _, d in self.doors do
		if now < d.hold then
			d.open = math.min(1, d.open + dt * OPENS)
		else
			d.open = math.max(0, d.open - dt * CLOSES)
		end
		drawDoor(self, d, night, list, cfs)
	end
	-- The figures, drawn by TownLife on the town's frame: the block's position turned to the world.
	for _, v in self.people do
		local p = v.p
		p.state = if v.state == "walk" then "walk" else "inside"
		local wp = self.frame:PointToWorldSpace(Vector3.new(v.x * S, 0, v.z * S))
		p.pos = { wp.X / S, wp.Z / S }
		p.heading = v.heading + self.yaw
		local y = wp.Y + groundAt(self.doors, v.x, v.z) * S
		-- Faded in (and out) over the last few steps at the end of the sidewalk, in fifths so the
		-- parts' transparency is only set now and then.
		if v.state == "walk" then
			local far = math.abs(v.x - v.far) + math.max(0, math.abs(v.z - v.door.edge) - 0.12)
			local fade = math.floor(math.clamp(1 - far / FADE, 0, 1) * 5 + 0.5) / 5
			if fade ~= v.fade then
				v.fade = fade
				for _, b in p.fig.bits do
					b.part.Transparency = fade
				end
			end
		end
		TownLife._draw(Vector3.new(0, y, 0), p, now, eye, list, cfs)
	end
end

function Life.destroy(self: Life)
	self.folder:Destroy()
end

---------------------------------------------------------------------------------------------------
-- Every centre in the player's town.

local function smallScreen(): boolean
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 700
end

-- Where a building model TownView drew stands: its middle on the ground, turned as it was turned
-- (as SpeedwayLife finds it); and its lot on its own frame, in tiles across and deep.
local function placeOf(model: Model): (CFrame?, number, number, number)
	local hit = model:FindFirstChild("Hit") :: BasePart?
	local turn = model:GetAttribute("Turn")
	if not hit or type(turn) ~= "number" then
		return nil, 0, 0, 0
	end
	local p = hit.CFrame.Position
	-- The Hit box covers 0.9 of the lot each way, along the world's axes.
	local wx, wz = hit.Size.X / (0.9 * TILE * S), hit.Size.Z / (0.9 * TILE * S)
	local w, d = if turn % 2 == 0 then wx else wz, if turn % 2 == 0 then wz else wx
	return CFrame.new(p.X, p.Y - hit.Size.Y / 2, p.Z) * CFrame.Angles(0, turn * math.pi / 2, 0), turn, math.round(w), math.round(d)
end

-- Is this model a merged market or motel at its last form (marketCenter.ts isMarketCenter,
-- resortCenter.ts isResort: any merge at growth stage 3)?
local function isCenter(m: Instance): boolean
	if not m:IsA("Model") or not KINDS[m:GetAttribute("Def") :: string] then
		return false
	end
	local merged = m:GetAttribute("Merged")
	local lvl = m:GetAttribute("Level")
	return type(merged) == "number" and merged > 1 and type(lvl) == "number" and growth.growthStage(lvl) == 3
end

-- Keeps a Life for every centre in `town` (its Buildings folder); returns a function that looks
-- for new, moved or changed ones, and one that moves them all on (each frame).
function CenterLife.attach(town: Folder, parent: Instance?): (() -> (), (dt: number) -> ())
	local buildings = town:WaitForChild("Buildings")
	local holder = Instance.new("Folder")
	holder.Name = "Centers"
	holder.Parent = parent or workspace
	local lives: { [string]: { life: Life?, key: string } } = {}
	local small = smallScreen()

	local function scan()
		local seen = {}
		for _, m in buildings:GetChildren() do
			if not isCenter(m) then
				continue
			end
			local model = m :: Model
			local frame, turn, w, d = placeOf(model)
			if not frame then
				continue
			end
			local def = model:GetAttribute("Def") :: string
			local lvl = model:GetAttribute("Level") :: number
			local merged = model:GetAttribute("Merged") :: number
			local name = Builder.buildingName(def, lvl) or ""
			local key = `{def}|{name}|{merged}|{w}x{d}|{frame}`
			seen[model.Name] = true
			local have: { life: Life?, key: string }? = lives[model.Name]
			if have and have.key ~= key then
				if have.life then
					have.life:destroy()
				end
				have = nil
			end
			if not have then
				lives[model.Name] = { life = CenterLife.new(holder, frame, turn, def, name, merged, w, d, small), key = key }
			end
		end
		for uid, have in lives do
			if not seen[uid] then
				if have.life then
					have.life:destroy()
				end
				lives[uid] = nil
			end
		end
	end

	-- Seconds since the town was first drawn: the doors' clock.
	local now = 0
	local function step(dt: number)
		now += dt
		local list: { BasePart } = {}
		local cfs: { CFrame } = {}
		local cam = workspace.CurrentCamera
		local eye = if cam then cam.CFrame.Position else nil
		local night = clock.nightAmount(clock.dayPhase(DateTime.now().UnixTimestampMillis))
		for _, have in lives do
			local life = have.life
			if not life or (eye and (eye - life.frame.Position).Magnitude > FAR) then
				continue
			end
			life:step(now, dt, night, eye, list, cfs)
		end
		if #list > 0 then
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	return scan, step
end

function CenterLife.start()
	local Town = require(script.Parent.Town) :: any
	local Remote = require(script.Parent.Remote) :: any
	task.spawn(function()
		local folder: Folder? = nil
		while not folder do
			folder = Town.folder()
			if not folder then
				task.wait(0.5)
			end
		end
		local scan, step = CenterLife.attach(folder :: Folder)
		-- The server redraws a building when it's built, moved, merged or upgraded; buildings also
		-- stream in and out, so look again every second as well as on every change.
		Remote.changed:Connect(function()
			task.defer(scan)
		end)
		scan()
		local wait = 0
		RunService.RenderStepped:Connect(function(dt)
			wait -= dt
			if wait <= 0 then
				wait = 1
				scan()
			end
			step(math.min(dt, 0.1))
		end)
	end)
end

return CenterLife
