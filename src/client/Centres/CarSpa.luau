--!strict
-- The Bubble Car Spa: a merged car wash at level 7-10, as the web game's scene/WashCenter.tsx draws
-- it for the whole block (laid out by src/shared/CentreLayout, the web's game/washCenter.ts), with
-- its life.
--
-- The server draws a merged car wash as the one wash grown to fill the block (TownView), so the
-- spa itself is drawn here, on each player's own screen, where CentreLife hides the grown wash:
-- express tunnels with glass fronts under arched blue roofs, the pay kiosk and its gate at the way
-- in, blowers at the way out, rows of vacuum bays under bright arches, and the roadside sign.
--
-- Its life, which the web game draws standing still (a car at the kiosk, one inside, one rolling
-- off, cars at two bays in three): here cars pull up to the kiosk and pay, the gate lifts, they
-- crawl through the tunnel past the spinning brushes, foamed up as they go, and stop on the apron
-- to drip before they drive off; the giant soap bubbles on the roof bob; people vacuum out their
-- cars at the bays, and customers walk in off the street to the glass doors to watch. A car shows
-- up at the kiosk and leaves from the apron growing and shrinking, as the town's traffic does at
-- its ends (TownLife), rather than threading the lot.

local CentreLayout = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("CentreLayout")) :: any
local Kit = require(script.Parent:WaitForChild("Kit"))

local CarSpa = {}

local NAME = "BUBBLE SPA"
local BLUE = "#0288d1"
local SKY = "#4fc3f7"
local PINK = "#ec407a"
local WHITE = "#fafafa"
local GOLD = "#ffc107"
local LIT = "#fff3c4"
local ASPHALT = "#4b4f55"
local FOAM = "#f5fbff"
local ARCH = { "#ec407a", "#ffca28", "#29b6f6", "#66bb6a" }

-- The tunnel's height to the eaves (web units).
local H = 0.95
-- Web units a second: rolling up to the kiosk and off the apron, and crawling through the wash.
local ROLL, CRAWL = 0.5, 0.2
-- How long a car takes to pay, drips on the apron, and grows or shrinks (seconds).
local PAY, DRIP, GROW = 2.6, 2.4, 0.6
-- Room kept between cars in a tunnel (web units, middle to middle).
local SPACING = 1.05
-- Brushes spin this fast idling and when a car's at them (radians a second).
local SPIN, SPIN_BUSY = 3, 13
local CARS, CARS_PHONE = 4, 3

type Brush = { x: number, z: number, top: boolean, flaps: { BasePart } }
type Bubble = { part: BasePart, at: CFrame, phase: number }
type WashCar = {
	car: Kit.Car,
	x: number,
	phase: string, -- "pay", "wash", "drip"
	t: number,
	foam: { BasePart },
}
type Tunnel = {
	z: number,
	x0: number,
	x1: number,
	frame: CFrame, -- the tunnel's own: x along it, its middle on z = 0
	kiosk: number, -- x where a car stops to pay
	apron: number, -- x where a car stops to drip
	gate: BasePart,
	gateAt: CFrame, -- the gate arm's hinge, and where the arm hangs off it
	gateArm: CFrame,
	gateUp: number, -- how far up (0 down, 1 up)
	brushes: { Brush },
	queue: { WashCar },
	free: { Kit.Car },
	foams: { { BasePart } },
	wait: number,
}
type Walker = { who: Kit.Person, x: number, z0: number, z1: number, s: number, dir: number, t: number }
type Vacuumer = { who: Kit.Person, x: number, z: number, face: number, phase: number }

export type Spa = {
	folder: Folder,
	frame: CFrame,
	tunnels: { Tunnel },
	bubbles: { Bubble },
	walkers: { Walker },
	vacuumers: { Vacuumer },
	cars: { Kit.Car },
	step: (self: Spa, time: number, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame }) -> (),
	refresh: (self: Spa, eye: Vector3?) -> (),
}

---------------------------------------------------------------------------------------------------
-- The still parts.

local function sign(b: Kit.Builder, text: string, x: number, y: number, z: number, w: number, h: number, bg: string, fg: string, turn: CFrame?)
	local p = Kit.part(b.folder, nil, Vector3.new(w, h, 0.02) * Kit.S, b:at(x, y, z) * (turn or CFrame.new()), bg)
	Kit.sign(p, text, fg, bg)
	return p
end

-- One express tunnel (WashCenter.tsx Tunnel), on its own frame: a long glass-fronted hall under an
-- arched blue roof, the kiosk and gate at the way in, blowers at the way out. `door`: x of the
-- glass doors in its front wall. Returns what moves: the brushes, the gate, the roof's bubbles.
local function tunnel(b: Kit.Builder, x0: number, x1: number, level: number, room: number, door: number?, small: boolean): ({ Brush }, BasePart, CFrame, { Bubble })
	local len = x1 - x0
	local cx = (x0 + x1) / 2
	local d = CentreLayout.TUNNEL_D
	local zf = d / 2
	-- Floor channel, back wall and the end piers.
	b:box(cx, 0.065, 0, len, 0.03, d - 0.01, "#cfd8dc", Enum.Material.Concrete)
	Kit.solid(b:box(cx, (H - 0.01) / 2, -zf + 0.05, len, H - 0.01, 0.1, "#e1f5fe"))
	for _, x in { x0, x1 } do
		for _, sd in { -1, 1 } do
			Kit.solid(b:box(x, H / 2, sd * (zf - 0.058), 0.14, H, 0.124, BLUE))
		end
		b:box(x, H + 0.06, 0, 0.16, 0.12, d, BLUE)
	end
	-- The glass front wall: a low sill (broken for the doors), tall panes, the wash inside.
	local runs = if door == nil then { { x0, x1 } } else { { x0, door - 0.3 }, { door + 0.3, x1 } }
	for _, r in runs do
		Kit.solid(b:box((r[1] + r[2]) / 2, 0.12, zf - 0.04, r[2] - r[1], 0.2, 0.06, BLUE))
		-- Pink neon along the sill.
		b:box((r[1] + r[2]) / 2, 0.24, zf + 0.005, r[2] - r[1], 0.025, 0.025, "#f06292", Enum.Material.Neon)
	end
	if door then
		b:box(door, 0.41, zf - 0.03, 0.6, 0.74, 0.04, WHITE)
		b:box(door, 0.4, zf - 0.005, 0.48, 0.68, 0.01, LIT)
		b:box(door, 0.4, zf + 0.002, 0.02, 0.68, 0.004, "#cfd8dc")
		b:box(door, 0.065, zf + 0.1, 0.6, 0.03, 0.18, "#cfd8dc")
	end
	local x = x0 + 0.45
	while x <= x1 - 0.4 do
		if door == nil or math.abs(x - door) > 0.42 then
			local pane = b:box(x, 0.58, zf - 0.03, 0.38, 0.68, 0.02, "#b3e5fc", Enum.Material.Glass)
			pane.Transparency = 0.65
			b:box(x + 0.21, 0.58, zf - 0.03, 0.03, 0.72, 0.04, WHITE)
		end
		x += 0.42
	end
	b:box(cx, H - 0.02, zf - 0.03, len, 0.05, 0.05, WHITE)
	b:box(cx, H + 0.005, zf - 0.005, len, 0.03, 0.03, "#4dd0e1", Enum.Material.Neon)
	-- The arched roof: a half barrel along the tunnel, drawn as slats round the arch.
	local SLATS = if small then 4 else 6
	local r = d / 2
	for k = 0, SLATS - 1 do
		local a = (k + 0.5) * math.pi / SLATS -- round from the front (+z) over the top to the back
		local chord = 2 * r * math.sin(math.pi / SLATS / 2) + 0.02
		Kit.solid(Kit.part(b.folder, nil, Vector3.new(len, 0.03, chord) * Kit.S, b:at(cx, H + r * math.sin(a), r * math.cos(a)) * CFrame.Angles(-(a - math.pi / 2), 0, 0), SKY))
	end
	-- Its ends closed with half discs (stepped boxes here), as the web's half cylinder is.
	for _, ex in { x0, x1 } do
		for k = 0, 2 do
			local mid = (k + 0.5) * r / 3
			b:box(ex, H + mid, 0, 0.03, r / 3 + 0.005, 2 * math.sqrt(r * r - mid * mid), SKY)
		end
	end
	-- White ribs over it (left off on a phone): the same slats, a little proud of the roof.
	if not small then
		local ribs = math.max(2, math.floor(len / 0.9))
		for i = 0, ribs - 1 do
			local rx = x0 + 0.2 + i * (len - 0.4) / (ribs - 1)
			for k = 0, SLATS - 1 do
				local a = (k + 0.5) * math.pi / SLATS
				local chord = 2 * (r + 0.02) * math.sin(math.pi / SLATS / 2) + 0.02
				Kit.part(b.folder, nil, Vector3.new(0.05, 0.03, chord) * Kit.S, b:at(rx, H + (r + 0.02) * math.sin(a), (r + 0.02) * math.cos(a)) * CFrame.Angles(-(a - math.pi / 2), 0, 0), WHITE)
			end
		end
	end
	-- (A little further forward than the web's, to stand clear of the slatted arch.)
	sign(b, NAME, cx, H + d * 0.36, d * 0.36, math.min(2.2, len * 0.42), math.min(2.2, len * 0.42) / 4, PINK, "#ffffff")
	-- Inside: the brushes (spun by the life, CarSpa.step), a pair at the sides and one over the top,
	-- each a coloured roller with a fringe of flaps round it; and suds heaped along the walls.
	local brushes: { Brush } = {}
	for i, bx in { x0 + 0.7, x0 + 1.2, x0 + 1.7 } do
		if bx >= x1 - 1 then
			continue
		end
		for _, sd in { -1, 1 } do
			local color = ARCH[(i - 1 + (if sd > 0 then 1 else 0)) % #ARCH + 1]
			b:cyl(bx, 0.42, sd * 0.32, 0.075, 0.66, color)
			local flaps = {}
			for _ = 1, 2 do
				table.insert(flaps, Kit.part(b.folder, nil, Vector3.new(0.21, 0.6, 0.015) * Kit.S, b:at(bx, 0.42, sd * 0.32), color))
			end
			table.insert(brushes, { x = bx, z = sd * 0.32, top = false, flaps = flaps })
		end
		local color = ARCH[(i + 1) % #ARCH + 1]
		-- (A cylinder runs along its own x: turned to run across the tunnel.)
		Kit.part(b.folder, Enum.PartType.Cylinder, Vector3.new(0.6, 0.12, 0.12) * Kit.S, b:at(bx, 0.82, 0) * CFrame.Angles(0, math.pi / 2, 0), color)
		local flaps = {}
		for _ = 1, 2 do
			table.insert(flaps, Kit.part(b.folder, nil, Vector3.new(0.015, 0.17, 0.56) * Kit.S, b:at(bx, 0.82, 0), color))
		end
		table.insert(brushes, { x = bx, z = 0, top = true, flaps = flaps })
	end
	for _, f in { { 0.75, -0.3, 0.1 }, { 0.9, -0.33, 0.13 }, { 1.1, -0.31, 0.11 }, { 1.4, 0.32, 0.1 }, { 1.55, 0.3, 0.12 }, { 1.7, 0.33, 0.09 } } do
		b:ball(x0 + f[1], 0.05 + f[3] * 0.6, f[2], f[3], FOAM)
	end
	-- Way in: the curtain of coloured strips, the ENTER sign, and the pay kiosk with its gate arm.
	for i = 0, 6 do
		b:box(x0 + 0.02, 0.52, -0.3 + i * 0.1, 0.012, 0.6, 0.07, ARCH[i % #ARCH + 1])
	end
	sign(b, "ENTER", x0 - 0.09, H - 0.07, 0, 0.5, 0.14, "#2e7d32", "#ffffff", CFrame.Angles(0, -math.pi / 2, 0))
	local kx, kz = x0 - 0.45, 0.32
	b:box(kx, 0.06, kz, 0.5, 0.06, 0.26, "#cfd8dc")
	Kit.solid(b:box(kx, 0.36, kz - 0.02, 0.22, 0.56, 0.16, "#eceff1"))
	b:box(kx, 0.66, kz - 0.02, 0.3, 0.05, 0.22, PINK)
	b:box(kx + 0.114, 0.46, kz - 0.02, 0.01, 0.12, 0.1, LIT)
	b:box(kx + 0.3, 0.235, kz - 0.02, 0.04, 0.37, 0.04, "#455a64")
	-- The arm hinges at the top of its post and reaches across the lane (-z).
	local hinge = b:at(kx + 0.3, 0.4, kz - 0.02)
	local arm = CFrame.new(0, 0, -0.28 * Kit.S)
	local gate = Kit.part(b.folder, nil, Vector3.new(0.025, 0.025, 0.56) * Kit.S, hinge * arm, WHITE)
	-- Painted arrows into the tunnel.
	for _, ax in { -1.25, -0.75 } do
		b:box(x0 + ax + 0.2, 0.065, 0.28, 0.24, 0.03, 0.06, WHITE)
	end
	-- Way out: blowers over the exit and the EXIT sign.
	for _, dz in { -0.25, 0.25 } do
		Kit.part(b.folder, Enum.PartType.Cylinder, Vector3.new(0.16, 0.16, 0.16) * Kit.S, b:at(x1 - 0.12, H - 0.12, dz), "#eceff1")
	end
	sign(b, "EXIT", x1 + 0.09, H - 0.07, 0, 0.44, 0.14, "#c62828", "#ffffff", CFrame.Angles(0, math.pi / 2, 0))
	-- On the roof: a heap of giant soap bubbles (they bob), and a flag from level 8.
	local bubbles: { Bubble } = {}
	for i, bb in { { 0, 0.18, 0.2 }, { 0.22, 0.12, 0.15 }, { -0.2, 0.1, 0.13 }, { 0.06, 0.38, 0.12 } } do
		local at = b:at(x1 - 0.7 + bb[1], H + d / 2 + bb[2], -0.08)
		local p = Kit.part(b.folder, Enum.PartType.Ball, Vector3.one * bb[3] * 2 * Kit.S, at, "#e1f5fe", Enum.Material.Glass)
		p.Transparency = 0.25
		table.insert(bubbles, { part = p, at = at, phase = i * 1.7 })
	end
	if level >= 8 then
		local fx, fy = x0 + 0.3, H + d / 2 - 0.05
		b:cyl(fx, fy + 0.45, 0, 0.022, 0.9, "#eceff1")
		b:box(fx + 0.17, fy + 0.75, 0, 0.32, 0.2, 0.015, PINK)
		b:ball(fx, fy + 0.92, 0, 0.04, GOLD)
	end
	return brushes, gate, hinge, bubbles
end

-- A vacuum bay: a coloured steel arch over the space, a hose drop and the vacuum post.
local function vacBay(b: Kit.Builder, n: number, small: boolean)
	local c = ARCH[n % #ARCH + 1]
	b:box(0.44, 0.065, 0, 0.025, 0.03, 1.05, WHITE)
	Kit.solid(b:box(0.44, 0.7, -0.42, 0.05, 1.3, 0.05, c))
	b:box(0.2, 1.33, -0.42, 0.5, 0.05, 0.05, c)
	b:box(0.2, 1.295, -0.42, 0.2, 0.02, 0.035, LIT)
	if not small then
		b:cyl(-0.04, 1.08, -0.42, 0.014, 0.46, "#37474f")
	end
	b:box(0.44, 0.03, 0.42, 0.16, 0.06, 0.16, "#cfd8dc")
	Kit.solid(b:box(0.44, 0.3, 0.42, 0.11, 0.48, 0.11, "#ffca28"))
	b:box(0.44, 0.56, 0.42, 0.14, 0.04, 0.14, BLUE)
end

-- The roadside sign: the name, a bubble on top and the price board.
local function pylon(b: Kit.Builder, x: number, z: number, level: number)
	local h = 2.6 + (level - 7) * 0.12
	local w = 1.1
	Kit.solid(b:box(x, (h - 0.01) / 2, z, 0.1, h - 0.01, 0.09, "#90a4ae"))
	b:box(x, 0.12, z, 0.5, 0.24, 0.3, BLUE)
	b:box(x, h - 0.2, z, w + 0.1, 0.4, 0.1, PINK)
	sign(b, NAME, x, h - 0.2, z + 0.06, w, 0.3, PINK, "#ffffff")
	b:box(x, h - 0.66, z, w * 0.8, 0.4, 0.08, "#263238")
	sign(b, "WASH $5", x, h - 0.66, z + 0.05, w * 0.72, 0.32, "#263238", "#4fc3f7")
	local bubble = b:ball(x, h + 0.32, z, 0.3, "#b3e5fc")
	bubble.Material = Enum.Material.Glass
	bubble.Transparency = 0.15
	b:cyl(x, h + 0.02, z, 0.12, 0.04, if level >= 10 then GOLD else BLUE)
end

---------------------------------------------------------------------------------------------------
-- The life.

local function stepTunnel(u: Tunnel, time: number, dt: number, list: { BasePart }, cfs: { CFrame })
	-- A new car shows up at the kiosk once the last one's well on its way in.
	u.wait -= dt
	local last = u.queue[#u.queue]
	if u.wait <= 0 and #u.free > 0 and (not last or last.x > u.kiosk + SPACING + 0.5) then
		local car = table.remove(u.free, math.random(1, #u.free)) :: Kit.Car
		table.insert(u.queue, { car = car, x = u.kiosk, phase = "pay", t = 0, foam = table.remove(u.foams) :: { BasePart } })
		u.wait = 1 + math.random() * 5
	end
	local gate = false
	local ahead: number? = nil
	local i = 1
	while i <= #u.queue do
		local c = u.queue[i]
		c.t += dt
		local show = 1
		if c.phase == "pay" then
			show = math.min(1, c.t / GROW)
			-- Paid: the gate lifts, and in it goes.
			if c.t > PAY then
				gate = true
				if u.gateUp > 0.9 then
					c.phase, c.t = "wash", 0
				end
			end
		elseif c.phase == "wash" then
			-- Off the kiosk at a roll, then the conveyor's crawl through the tunnel, then out to the apron.
			local v = if c.x < u.x0 or c.x > u.x1 - 0.35 then ROLL else CRAWL
			c.x = math.min(c.x + v * dt, u.apron)
			if c.x < u.x0 + 0.35 then
				gate = true
			end
			if c.x >= u.apron then
				c.phase, c.t = "drip", 0
			end
		elseif c.phase == "drip" then
			show = math.min(1, (DRIP + GROW - c.t) / GROW)
			if c.t > DRIP + GROW then
				Kit.hide(c.car, list, cfs)
				for _, f in c.foam do
					table.insert(list, f)
					table.insert(cfs, Kit.HIDDEN)
				end
				table.insert(u.free, c.car)
				table.insert(u.foams, c.foam)
				table.remove(u.queue, i)
				continue
			end
		end
		-- Never closer than SPACING to the car ahead.
		if ahead and c.x > ahead - SPACING then
			c.x = math.max(c.x - (c.x - (ahead - SPACING)), u.kiosk)
		end
		ahead = c.x
		-- Nose along +x, through the tunnel.
		local cf = u.frame * CFrame.new(c.x * Kit.S, 0.05 * Kit.S, 0) * CFrame.Angles(0, math.pi / 2, 0)
		Kit.place(c.car, cf, show, list, cfs)
		-- Foamed up from the first brush to a little past the last, then rinsed off.
		local foamy = c.phase == "wash" and c.x > u.x0 + 0.55 and c.x < u.x0 + 2.1
		local roof = c.car.top
		for j, f in c.foam do
			table.insert(list, f)
			if foamy then
				local along = ({ -0.12, 0.08, 0.28 })[j] * Kit.S
				local bob = math.sin(time * 3 + j * 2) * 0.01 * Kit.S
				table.insert(cfs, cf * CFrame.new(0, roof - (j == 3 and 0.12 * Kit.S or 0.02 * Kit.S) + bob, along))
			else
				table.insert(cfs, Kit.HIDDEN)
			end
		end
		i += 1
	end
	-- The gate arm swings up for a paid car and down behind it.
	local target = if gate then 1 else 0
	if u.gateUp ~= target then
		u.gateUp = if target > u.gateUp then math.min(1, u.gateUp + dt * 1.8) else math.max(0, u.gateUp - dt * 1.4)
		table.insert(list, u.gate)
		table.insert(cfs, u.gateAt * CFrame.Angles(u.gateUp * math.pi * 0.45, 0, 0) * u.gateArm)
	end
	-- The brushes: spinning all the while, hard when a car's at them.
	for _, br in u.brushes do
		local busy = false
		for _, c in u.queue do
			if math.abs(c.x - br.x) < 0.55 then
				busy = true
				break
			end
		end
		local speed = if busy then SPIN_BUSY else SPIN
		local a = (br :: any).a or 0
		a = (a + speed * dt) % (math.pi * 2)
		;(br :: any).a = a
		local at = u.frame * CFrame.new(br.x * Kit.S, (if br.top then 0.82 else 0.42) * Kit.S, br.z * Kit.S)
		for k, f in br.flaps do
			table.insert(list, f)
			local turn = a + (k - 1) * math.pi / 2
			table.insert(cfs, at * (if br.top then CFrame.Angles(0, 0, turn) else CFrame.Angles(0, turn, 0)))
		end
	end
end

-- Builds the spa for one block (or one half of a 2x4) at `frame`, the block's middle on the ground
-- facing its road, grown `sx` x `sz` from the wash's own lot. `seed` varies the cars and people.
function CarSpa.new(parent: Instance, frame: CFrame, sx: number, sz: number, level: number, small: boolean, seed: number): Spa
	local folder = Instance.new("Folder")
	folder.Name = "CarSpa"
	local t = CentreLayout.wash(sx, sz)
	local b = Kit.builder(folder, frame)
	b:box(0, 0.03, 0, t.L - 0.12, 0.04, t.D - 0.12, ASPHALT, Enum.Material.Asphalt)
	local dx = CentreLayout.washDoor(t)
	local tunnels: { Tunnel } = {}
	local allBubbles: { Bubble } = {}
	local cars: { Kit.Car } = {}
	for i, u in t.tunnels do
		local tf = frame * CFrame.new(0, 0, u.z * Kit.S)
		local tb = Kit.builder(folder, tf)
		local room = t.L / 2 - u.x1
		local brushes, gate, hinge, bubbles = tunnel(tb, u.x0, u.x1, level, room, if i == #t.tunnels then dx else nil, small)
		for _, bb in bubbles do
			table.insert(allBubbles, bb)
		end
		local free = {}
		for j = 1, if small then CARS_PHONE else CARS do
			local car = Kit.car(folder, seed + i * 10 + j)
			if car then
				table.insert(free, car)
				table.insert(cars, car)
			end
		end
		-- Foam that rides on a car through the brushes: a heap on the roof, one on the bonnet.
		local foams = {}
		for _ = 1, #free do
			local set = {}
			for _, r in { 0.11, 0.09, 0.08 } do
				table.insert(set, Kit.part(folder, Enum.PartType.Ball, Vector3.one * r * 2 * Kit.S, Kit.HIDDEN, FOAM))
			end
			table.insert(foams, set)
		end
		table.insert(tunnels, {
			z = u.z,
			x0 = u.x0,
			x1 = u.x1,
			frame = tf,
			kiosk = u.x0 - 0.95,
			-- Out on the apron if there's room for a car there, else just out of the doors.
			apron = if room >= 0.75 then u.x1 + 0.4 else u.x1 + 0.1,
			gate = gate,
			gateAt = hinge,
			gateArm = CFrame.new(0, 0, -0.28 * Kit.S),
			gateUp = 0,
			brushes = brushes,
			queue = {},
			free = free,
			foams = foams,
			wait = (i - 1) * 3,
		})
	end
	-- Vacuum bays, a car at two in three (none in line with the doors, the walk to the street).
	local vacuumers: { Vacuumer } = {}
	local parked: { Kit.Car } = {}
	local spots = {}
	for i, v in t.vacs do
		local n = i - 1
		local vf = frame * CFrame.new(v.x * Kit.S, 0, v.z * Kit.S) * (if t.along then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new())
		vacBay(Kit.builder(folder, vf), n, small)
		if n % 2 == 0 and v.x ~= dx then
			local car = Kit.car(folder, seed + 100 + n + 3)
			if car then
				Kit.park(car, vf * CFrame.new(0, 0.05 * Kit.S, 0))
				table.insert(parked, car)
				table.insert(spots, { v = v, n = n })
			end
		end
	end
	-- Someone at a car or two, vacuuming it out: standing by its side, by the vacuum post.
	for i = 1, math.min(#spots, if small then 1 else 2) do
		local sp = spots[if i == 1 then math.max(1, #spots // 2) else #spots]
		local v = sp.v
		local x, z, face = v.x + 0.3, v.z + 0.15, -math.pi / 2
		if t.along then
			x, z, face = v.x + 0.15, v.z - 0.3, 0
		end
		table.insert(vacuumers, { who = Kit.person(folder, `spa-vac-{seed}-{i}`), x = x, z = z, face = face, phase = i * 2.1 })
	end
	pylon(b, t.pylon[1], t.pylon[2], level)
	-- Customers walking in off the street up the clear column to the glass doors, to watch.
	local walkers: { Walker } = {}
	local front = t.tunnels[#t.tunnels]
	local zDoor = front.z + CentreLayout.TUNNEL_D / 2 + 0.02
	for i = 1, if small then 1 else 2 do
		local x = dx + (if i == 1 then 0.08 else -0.08)
		local len = t.D / 2 - 0.1 - zDoor
		table.insert(walkers, { who = Kit.person(folder, `spa-walk-{seed}-{i}`), x = x, z0 = t.D / 2 - 0.1, z1 = zDoor, s = len * (if i == 1 then 0.3 else 0.8), dir = if i == 1 then 1 else -1, t = 0 })
	end
	folder.Parent = parent
	-- Open for a while already: cars at the kiosk, in the tunnel and out on the apron.
	Kit.settle(36, function(time, dt, list, cfs)
		for _, u in tunnels do
			stepTunnel(u, time, dt, list, cfs)
		end
	end)
	local self = {
		folder = folder,
		frame = frame,
		tunnels = tunnels,
		bubbles = allBubbles,
		walkers = walkers,
		vacuumers = vacuumers,
		cars = cars,
		parked = parked,
	}
	return (setmetatable(self, { __index = CarSpa }) :: any) :: Spa
end

function CarSpa.step(self: Spa, time: number, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	for _, u in self.tunnels do
		stepTunnel(u, time, dt, list, cfs)
	end
	-- The roof's bubbles bob gently.
	for _, bb in self.bubbles do
		table.insert(list, bb.part)
		table.insert(cfs, bb.at * CFrame.new(0, math.sin(time * 1.3 + bb.phase) * 0.03 * Kit.S, 0))
	end
	for _, v in self.vacuumers do
		-- Leaning in at the car and looking about, now and then.
		Kit.drawPerson(v.who, self.frame, v.x, v.z, v.face, "linger", 0, time + v.phase, eye, list, cfs)
	end
	for _, w in self.walkers do
		local state, moved = "walk", 0
		local len = w.z0 - w.z1
		if w.t > 0 then
			-- Inside watching the wash, or gone off up the street.
			w.t -= dt
			state = "inside"
			if w.t <= 0 then
				w.dir = -w.dir
			end
		else
			local step = Kit.WALK * dt
			w.s += step * w.dir
			moved = step
			if w.s >= len then
				w.s, w.t = len, 8 + math.random() * 8
			elseif w.s <= 0 then
				w.s, w.t = 0, 4 + math.random() * 8
			end
		end
		-- Facing the doors going in (-z), the street coming out.
		Kit.drawPerson(w.who, self.frame, w.x, w.z0 - w.s, if w.dir > 0 then math.pi else 0, state, moved, time, eye, list, cfs)
	end
end

function CarSpa.refresh(self: Spa, eye: Vector3?)
	for _, car in self.cars do
		Kit.refresh(car, eye)
	end
	for _, car in (self :: any).parked do
		Kit.refresh(car, eye)
	end
end

return CarSpa
