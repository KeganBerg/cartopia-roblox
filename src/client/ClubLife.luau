--!strict
-- The nightclub's life, as the web game's scene/ClubLife.tsx draws it, shown only while the club
-- is open (at night): people dancing on the rooftop floor (5 at level 1, more as it levels up, up
-- to 15), the bouncer by his podium at the velvet rope, and two searchlights sweeping the sky.
--
-- The dancers and the bouncer are townspeople (client/TownLife's figures, faces and all). The
-- dancers bob on the beat, turn about and throw their arms up, some waving, some pumping low, some
-- clapping on the backbeat. The bouncer watches the line TownLife's townspeople form along the
-- rope (TownLife.clubDoor), squares up to whoever's at the front and waves them in with his right
-- arm when it's their turn; with no one waiting he keeps an eye up and down the street.
--
-- Like SpeedwayLife it runs on this player's client only: parts are made once and moved each frame
-- with one BulkMoveTo, and not at all from further off than FAR studs or in the daytime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local data = require(Game:WaitForChild("data")) :: any
local clock = require(Game:WaitForChild("clock")) :: any
local TownLife = require(script.Parent:WaitForChild("TownLife")) :: any

local ClubLife = {}

local S = Catalog.SCALE -- studs per web unit
local FAR = 1600
local HIDDEN = CFrame.new(0, -10000, 0)

-- ClubLife.tsx: the dancers' neon shirts and dark trousers.
local SHIRTS = { "#ff2bd6", "#00e5ff", "#ffea00", "#76ff03", "#ff6d00", "#fafafa", "#7c4dff", "#ff1744", "#18ffff", "#f50057" }
local PANTS = { "#212121", "#263238", "#3949ab", "#1a237e", "#4e342e", "#37474f" }
-- The club's shape (NewBuildings.tsx 'club'): 3.4 by 1.3 web units, its front at z0 + d/2, and the
-- rooftop dance floor over it.
local W, D, Z0 = 3.4, 1.3, -0.29
-- The bouncer: by his podium on the near side of the red carpet (lot units, clubLayout.ts),
-- across from the head of the line, a size bigger than everyone else.
local BOUNCER = { x = -1.44, z = 0.74, scale = 1.15 }
local QUEUE = { x = -0.5, z = 0.82 } -- the head of the line
local LAMP = { x = 1.45, z = -0.43 } -- the searchlights, on the roof's back corners
-- Where he faces: down the street toward the line, square on to whoever's at the front of the
-- rope, and his head turned to the door as he waves them in.
local FACE = { idle = 0.75, line = math.atan2(QUEUE.x - BOUNCER.x, QUEUE.z - BOUNCER.z), door = 0.65 }
-- Seconds his "go on in" wave takes: arm out, hold, back to his hands.
local WAVE = { up = 0.35, hold = 1.4, down = 0.5 }
-- The dance's tempo. The web follows the club track's own beat grid; here a steady house tempo.
local BPM = 122

local function smooth(t: number): number
	return if t <= 0 then 0 elseif t >= 1 then 1 else t * t * (3 - 2 * t)
end

-- An arm's turn at the shoulder that points its hand along (x, y, z) in the figure's own frame
-- (facing +z): ClubLife.tsx aim(), as roll (out to the side) then pitch (forward is negative).
local function aim(x: number, y: number, z: number): (number, number)
	local l = math.sqrt(x * x + y * y + z * z)
	return math.asin(x / l), math.atan2(-z / l, -y / l)
end
local CLASP_R, CLASP_P = aim(-0.11, -0.18, 0.14)
local POINT_R, POINT_P = aim(0.7, 0.1, 0.7)
local function arm(roll: number, pitch: number): CFrame
	return CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, roll)
end

-- Knees bent so the hips sit `dip` (figure units) lower: thighs forward, shins back.
local function bend(dip: number): { { number } }
	local reach = TownLife.THIGH + TownLife.SHIN
	local a = math.acos(math.clamp(1 - dip / reach, -1, 1))
	return { { -a, 2 * a }, { -a, 2 * a } }
end

local function part(parent: Instance, size: Vector3, color: Color3, transparency: number?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = HIDDEN
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Transparency = transparency or 0
	p.Parent = parent
	return p
end

type Figure = any
type Life = {
	model: Model,
	frame: CFrame,
	floor: { y: number, z: number, w: number, d: number },
	roofY: number,
	dancers: { Figure },
	spots: { { number } },
	bouncer: Figure,
	beams: { { holder: Part, beam: Beam } },
	shown: boolean,
	heading: number,
	look: number,
	waved: number,
	wave: number,
}

local function newLife(m: Model, frame: CFrame, lvl: number, parent: Instance): Life
	local folder = Instance.new("Model")
	folder.Name = m.Name
	folder.Parent = parent
	local h = 1.3 + data.levelLift(lvl)
	local floor = { y = h + 0.15, z = Z0 + 0.06, w = W - 0.5, d = D - 0.36 }
	-- More dancers as the club levels up: 5 at level 1, 10 at level 10.
	local n = math.min(5 + math.floor(lvl / 2), 15)
	local dancers = {}
	local spots = {}
	-- Spots spread over the floor in a loose grid, the same every load.
	local cols = math.ceil(math.sqrt(n * (floor.w / floor.d)))
	local rows = math.ceil(n / cols)
	for i = 1, n do
		local c, r = (i - 1) % cols, (i - 1) // cols
		local jx, jz = math.sin((i - 1) * 12.9898) * 0.12, math.cos((i - 1) * 78.233) * 0.08
		spots[i] = { ((c + 0.5) / cols - 0.5) * floor.w * 0.8 + jx, floor.z + ((r + 0.5) / rows - 0.5) * floor.d * 0.6 + jz }
		local p = TownLife.person(`{m.Name}:dancer{i}`, "", { 0, 0 })
		p.type = "walker"
		p.colors.shirt = SHIRTS[(i - 1) % #SHIRTS + 1]
		p.colors.pants = PANTS[(i - 1) % #PANTS + 1]
		p.look.top = if p.look.top == "jacket" or p.look.top == "hoodie" then "tee" else p.look.top
		p.look.shorts = false
		dancers[i] = TownLife.figure(p, folder)
	end
	local b = TownLife.person(`{m.Name}:bouncer`, "", { 0, 0 })
	b.type = "walker"
	b.colors.shirt = "#4a4f5e"
	b.colors.pants = "#2e3039"
	b.look.top, b.look.hair, b.look.shorts, b.look.coat, b.look.shoes = "jacket", "buzz", false, "#212121", "#111111"
	local bouncer = TownLife.figure(b, folder, BOUNCER.scale)
	-- The searchlights: a cone of light from each lamp up into the sky (a Beam, widening from the
	-- lamp and fading out at the top), on a hidden part that turns to sweep it.
	local beams = {}
	for k = 1, 2 do
		local holder = part(folder, Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), 1)
		local a0 = Instance.new("Attachment")
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, 7 * S, 0)
		a1.Parent = holder
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 0.1 * S
		beam.Width1 = 1 * S
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(Color3.fromHex("#d9c8ff"))
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) })
		beam.Segments = 1
		beam.Enabled = false
		beam.Parent = holder
		beams[k] = { holder = holder, beam = beam }
	end
	return {
		model = folder,
		frame = frame,
		floor = floor,
		roofY = h + 0.135,
		dancers = dancers,
		spots = spots,
		bouncer = bouncer,
		beams = beams,
		shown = true,
		heading = FACE.idle,
		look = 0,
		waved = 0,
		wave = -99,
	}
end

-- The dancers' beat count, and a clap on every backbeat (two and four).
local phase, clap = 0, 0

local function stepLife(L: Life, time: number, dt: number, eye: Vector3?, night: number, open: boolean, list: { BasePart }, cfs: { CFrame })
	-- Searchlights sweep up and away from the club (out to the side and back), never across the roof.
	for k, b in L.beams do
		local on = night > 0.05
		if b.beam.Enabled ~= on then
			b.beam.Enabled = on
		end
		if on then
			local sd = if k == 1 then -1 else 1
			local rz = -sd * (0.3 + math.sin(time * 0.5 + (k - 1) * 2.2) * 0.25)
			local rx = -0.1 + math.cos(time * 0.37 + (k - 1)) * 0.15
			local at = L.frame * CFrame.new(sd * LAMP.x * S, (L.roofY + 0.24) * S, (Z0 + LAMP.z) * S)
			table.insert(list, b.holder)
			table.insert(cfs, at * CFrame.Angles(rx, 0, rz))
		end
	end
	if not open then
		if L.shown then
			L.shown = false
			for _, f in L.dancers do
				TownLife.hideFigure(f, list, cfs)
			end
			TownLife.hideFigure(L.bouncer, list, cfs)
		end
		return
	end
	L.shown = true
	-- The bouncer hears from the line at his rope (TownLife's bouncers()).
	local wall = os.clock()
	local door = TownLife.clubDoor(L.frame.Position)
	if door and door.admitted ~= L.waved then
		L.waved = door.admitted
		L.wave = wall
	end
	local since = wall - L.wave
	local waving = since < WAVE.up + WAVE.hold + WAVE.down
	local raise = smooth(since / WAVE.up) * (1 - smooth((since - WAVE.up - WAVE.hold) / WAVE.down))
	local waiting = door ~= nil and door.waiting
	local faceTo = if waving or waiting then FACE.line else FACE.idle
	local lookTo = if waving then FACE.door * raise
		elseif waiting then math.sin(time * 0.35) * 0.15
		else math.sin(time * 0.3) * 0.7 + math.sin(time * 0.71) * 0.2
	L.heading += (faceTo - L.heading) * math.min(1, dt * 3)
	L.look += (lookTo - L.look) * math.min(1, dt * 4)
	-- Left hand stays at the belt; the right sweeps out toward the door and back.
	local base = L.frame * CFrame.new(BOUNCER.x * S, 0, BOUNCER.z * S) * CFrame.Angles(0, L.heading, 0)
	TownLife.pose(L.bouncer, base, {
		hip = TownLife.LEG,
		lean = 0,
		twist = 0,
		nod = 0,
		look = L.look,
		legs = { { 0, 0 }, { 0, 0 } },
		arms = { arm(-CLASP_R, CLASP_P), arm(CLASP_R + (POINT_R - CLASP_R) * raise, CLASP_P + (POINT_P - CLASP_P) * raise) },
	}, eye, list, cfs)
	-- The dancers: knees bend on the beat; some wave their arms in the air, some keep them low and
	-- pump, and some throw their hands up on the claps.
	local beat = phase * math.pi
	local floorY = L.floor.y * S
	for i, f in L.dancers do
		local spot = L.spots[i]
		local x = spot[1] + math.sin(time * 0.7 + i) * 0.05
		local z = spot[2] + math.cos(time * 0.6 + i * 2) * 0.04
		local heading = i * 1.3 + math.sin(time * 1.4 + i) * 0.9
		local dip = (1 - math.sin((phase - math.floor(phase)) * math.pi)) * 0.03
		local lift = if i % 3 == 0 then 2.6 - clap * 0.5 elseif i % 3 == 1 then 2.2 + math.sin(beat) * 0.5 else 1.1 + math.sin(beat * 2) * 0.4 + clap * 1.2
		local wave = math.sin(beat * 0.5 + i * 1.7) * 0.25
		local pump = if i % 3 == 2 then -0.5 - math.sin(beat * 2) * 0.3 else -0.15
		local at = L.frame * CFrame.new(x * S, floorY, z * S) * CFrame.Angles(0, heading, 0)
		TownLife.pose(f, at, {
			hip = TownLife.LEG - dip,
			lean = 0,
			twist = 0,
			nod = 0,
			look = math.sin(time * 0.9 + i * 2.1) * 0.35,
			legs = bend(dip),
			arms = { arm(-(lift - wave), pump), arm(lift + wave, pump) },
		}, eye, list, cfs)
	end
end

---------------------------------------------------------------------------------------------------

-- Where a building model TownView drew stands: its middle on the ground, turned as it was turned.
local function frameOf(model: Model): CFrame?
	local hit = model:FindFirstChild("Hit") :: BasePart?
	local turn = model:GetAttribute("Turn")
	if not hit or type(turn) ~= "number" then
		return nil
	end
	local p = hit.CFrame.Position
	return CFrame.new(p.X, p.Y - hit.Size.Y / 2, p.Z) * CFrame.Angles(0, turn * math.pi / 2, 0)
end

-- Keeps a Life for every club in `town` (its Buildings folder); returns a function that looks for
-- new, moved or upgraded ones, and one that moves them all on (each frame).
function ClubLife.attach(town: Folder, parent: Instance?): (() -> (), (dt: number) -> ())
	local buildings = town:WaitForChild("Buildings")
	local holder = Instance.new("Folder")
	holder.Name = "Clubs"
	holder.Parent = parent or workspace
	local lives: { [string]: { life: Life, key: string } } = {}

	local function scan()
		local seen = {}
		for _, m in buildings:GetChildren() do
			if not m:IsA("Model") or m:GetAttribute("Def") ~= "club" then
				continue
			end
			local frame = frameOf(m)
			if not frame then
				continue
			end
			local lvl = (m:GetAttribute("Level") :: number?) or 1
			local key = `{lvl}|{frame}`
			seen[m.Name] = true
			local have = lives[m.Name]
			if have and have.key ~= key then
				have.life.model:Destroy()
				have = nil
			end
			if not have then
				lives[m.Name] = { life = newLife(m, frame, lvl, holder), key = key }
			end
		end
		for uid, have in lives do
			if not seen[uid] then
				have.life.model:Destroy()
				lives[uid] = nil
			end
		end
	end

	local time = 0
	local clapAt = 0
	local function step(dt: number)
		time += dt
		-- The beat, and a clap that comes in fast on two and four but not all in one frame.
		phase += dt * BPM / 60
		local into = (phase - 1) % 2
		clapAt = if into < 0.25 then 1 - into * 4 else 0
		clap += (clapAt - clap) * math.min(1, dt * 16)
		local open = clock.isNight()
		local night = clock.nightAmount(clock.dayPhase())
		local cam = workspace.CurrentCamera
		local eye = if cam then cam.CFrame.Position else nil
		local list: { BasePart } = {}
		local cfs: { CFrame } = {}
		for _, have in lives do
			local life = have.life
			if eye and (eye - life.frame.Position).Magnitude > FAR and not life.shown then
				continue
			end
			stepLife(life, time, dt, eye, night, open and (not eye or (eye - life.frame.Position).Magnitude <= FAR), list, cfs)
		end
		if #list > 0 then
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	return scan, step
end

function ClubLife.start()
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
		local scan, step = ClubLife.attach(folder :: Folder)
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

return ClubLife
