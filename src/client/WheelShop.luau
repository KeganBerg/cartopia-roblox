--!strict
-- The Daily Spin's tyre shop at night, as the web game's scene/WheelScene.tsx: a giant show wheel
-- (a tyre round a chrome rim, eight glossy slices between chrome spokes, each with its prize and
-- amount, pegs for the rubber flapper up top, chase lights on the lip and an enamel star cap) on a
-- steel A-frame and hazard-ringed plinth, with tyre racks, tyre stacks, tool chests, hanging lamps,
-- a roller door and the neon DAILY SPIN sign behind, lit by a spot from the front and pink and cyan
-- lamps either side. Confetti flies off the wheel when it lands.
--
-- Built on the client far from every town (10 studs to the web's metre), and only while the Daily
-- Spin is open. The panel (Panels/Wheel) turns the wheel, kicks the flapper and says what won.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local wheel = require(Game.wheel) :: any
local data = require(Game.data) :: any
local Kit = require(script.Parent.ArcadeGames.StarKit)

local WheelShop = {}

local S = 10 -- studs per web metre
local ORIGIN = Vector3.new(-30000, 0, 12000) -- far from every town, the drag strip and the arcade
WheelShop.ORIGIN = ORIGIN

local WHEEL = wheel.WHEEL
local N = #WHEEL
local STEP = math.pi * 2 / N
-- Wheel centre height and sizes (metres), as WheelScene.
local CY = 2.45
local FACE = 1.58
local HUB = 0.42
local TYRE_IN = 1.66
local TYRE_OUT = 2.12
local FOV = 40
WheelShop.FOV = FOV

local hex = Color3.fromHex
local BG = hex("#120c1c")
WheelShop.BG = BG

local function P(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z) * S
end

local function part(props: { [string]: any }, parent: Instance): Part
	return Kit.part(props, parent)
end


-- A Roblox cylinder runs along X; these stand one along Z (facing the camera) or Y (upright).
local ALONG_Z = CFrame.Angles(0, math.pi / 2, 0)
local ALONG_Y = CFrame.Angles(0, 0, math.pi / 2)

-- Words on a part's +Z face: no backing, the web's chunky white numbers with a navy outline.
local function label(p: BasePart, text: string, color: string, stroke: string?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = hex(color)
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	if stroke then
		l.TextStrokeColor3 = hex(stroke)
		l.TextStrokeTransparency = 0
	end
	l.Parent = gui
	gui.Parent = p
end

-- A part that moves with something (the wheel, the flapper), and where it sits on it.
type Piece = { part: BasePart, at: CFrame }

-- ── The wheel ─────────────────────────────────────────────────────────────────────────────────

export type Shop = {
	world: Folder,
	setAngle: (degrees: number) -> (),
	kick: () -> (),
	won: (index: number?, color: Color3?) -> (),
	camera: (viewport: Vector2) -> (CFrame, boolean),
	setWide: (wide: boolean) -> (),
	step: (dt: number) -> (),
	destroy: () -> (),
}

local function amount(s: any, level: number): string?
	if s.kind == "coins" then
		local n = wheel.wheelCoins(s.mult, level)
		local t = tostring(math.floor(n))
		local out = t:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		return (out:gsub("^,", ""))
	elseif s.kind == "gems" or s.kind == "jackpot" then
		return `×{s.gems}`
	end
	return nil
end

local SKIN_COLORS = (function()
	local swatch
	for _, s in data.SKINS do
		if s.id == "prismatic" then
			swatch = s.swatch
		end
	end
	local cols = {}
	for h in string.gmatch(swatch or "", "#%x%x%x%x%x%x") do
		table.insert(cols, hex(h))
	end
	if #cols == 0 then
		cols = { hex("#ff80ab"), hex("#80d8ff"), hex("#ccff90") }
	end
	return cols
end)()

-- A prize as the web's Prize, built round (0, 0) in its slice's frame (+Y towards the rim).
local function prize(s: any, add: (props: { [string]: any }, at: CFrame) -> BasePart)
	local gold = hex("#ffc533")
	local function coin(x: number, y: number, z: number, tilt: number)
		local at = CFrame.new(x * S, y * S, z * S) * CFrame.Angles(0, 0, tilt)
		add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.035, 0.26, 0.26) * S, Color = gold, Material = Enum.Material.Metal, Reflectance = 0.15 }, at * ALONG_Z)
		local face = add({ Size = Vector3.new(0.17, 0.17, 0.01) * S, Transparency = 1 }, at * CFrame.new(0, 0, 0.025 * S))
		label(face, "$", "#9a5800")
		-- A raised ring on the face.
		add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.01, 0.2, 0.2) * S, Color = hex("#e0a020"), Material = Enum.Material.Metal }, at * CFrame.new(0, 0, 0.019 * S) * ALONG_Z)
	end
	local function gem(x: number, y: number, z: number, turn: number)
		local at = CFrame.new(x * S, y * S, (z + 0.06) * S) * CFrame.Angles(0, 0, math.pi / 4 + turn * 0.15)
		add({ Size = Vector3.new(0.16, 0.16, 0.1) * S, Color = hex("#1e88e5"), Reflectance = 0.25 }, at)
		add({ Size = Vector3.new(0.08, 0.08, 0.02) * S, Color = hex("#90caf9"), Material = Enum.Material.Neon, Transparency = 0.2 }, at * CFrame.new(0.02 * S, 0.02 * S, 0.055 * S))
	end
	local function gems(n: number, dy: number)
		local spots = if n == 1 then { { 0, 0, 0 } }
			elseif n == 3 then { { -0.13, -0.05, 0 }, { 0.13, -0.05, 0 }, { 0, 0.09, 0.04 } }
			else { { -0.18, -0.08, 0 }, { 0, -0.1, 0.02 }, { 0.18, -0.08, 0 }, { -0.09, 0.07, 0.05 }, { 0.09, 0.07, 0.05 } }
		for i, p in spots do
			gem(p[1], p[2] + dy, p[3], i)
		end
	end
	if s.kind == "coins" then
		local n = if s.mult < 0.5 then 1 elseif s.mult < 1 then 2 else 3
		local spots = if n == 1 then { { 0, 0, 0, 0 } }
			elseif n == 2 then { { -0.08, -0.03, 0, -0.2 }, { 0.08, 0.03, 0.03, 0.25 } }
			else { { -0.15, -0.06, 0, -0.3 }, { 0.15, -0.06, 0.01, 0.3 }, { 0, 0.07, 0.04, 0 }, { -0.07, -0.12, 0.06, 0.15 }, { 0.08, -0.13, 0.07, -0.1 } }
		for _, p in spots do
			coin(p[1], p[2], p[3], p[4])
		end
	elseif s.kind == "gems" then
		gems(wheel.gemPile(s.gems), 0)
	elseif s.kind == "jackpot" then
		gems(5, -0.08)
		-- The crown on top: a gold band with five points, a gem on each.
		local c = CFrame.new(0, 0.2 * S, 0.08 * S)
		add({ Size = Vector3.new(0.26, 0.07, 0.05) * S, Color = gold, Material = Enum.Material.Metal, Reflectance = 0.2 }, c)
		for i = -2, 2 do
			local at = c * CFrame.new(i * 0.06 * S, 0.06 * S, 0) * CFrame.Angles(0, 0, math.pi / 4)
			add({ Size = Vector3.new(0.05, 0.05, 0.04) * S, Color = gold, Material = Enum.Material.Metal }, at)
			add({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.035, 0.035, 0.035) * S, Color = hex("#4fc3f7"), Material = Enum.Material.Neon }, c * CFrame.new(i * 0.06 * S, 0.1 * S, 0.02 * S))
		end
	elseif s.kind == "part" then
		-- A red GT wing: the blade on two stands, with end plates.
		local red = hex("#e53935")
		local base = CFrame.Angles(0, 0, 0.35) * CFrame.Angles(-0.5, 0, 0)
		add({ Size = Vector3.new(0.44, 0.07, 0.13) * S, Color = red }, base * CFrame.new(0, 0.07 * S, 0))
		for _, sd in { -1, 1 } do
			add({ Size = Vector3.new(0.02, 0.15, 0.16) * S, Color = hex("#b71c1c") }, base * CFrame.new(sd * 0.23 * S, 0.06 * S, 0))
			add({ Size = Vector3.new(0.035, 0.12, 0.035) * S, Color = hex("#263238") }, base * CFrame.new(sd * 0.1 * S, -0.03 * S, 0))
		end
	else
		-- A skin-wrapped orb with a chrome band.
		add({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4) * S, Color = SKIN_COLORS[1], Reflectance = 0.1 }, CFrame.new())
		for i = 2, math.min(3, #SKIN_COLORS) do
			local a = (i - 2) * 2.2 + 0.6
			add({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.22, 0.22, 0.22) * S, Color = SKIN_COLORS[i] }, CFrame.new(math.cos(a) * 0.09 * S, math.sin(a) * 0.09 * S, 0.1 * S))
		end
		add({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02, 0.44, 0.44) * S, Color = hex("#e9eef2"), Material = Enum.Material.Metal, Reflectance = 0.3 }, CFrame.Angles(0.3, 0, 0) * ALONG_Y)
	end
end

local function buildWheel(world: Folder, level: number)
	local model = Instance.new("Model")
	model.Name = "Wheel"
	model.Parent = world
	local centre = CFrame.new(P(0, CY, 0))
	local turning: { Piece } = {}
	local slices: { { part: BasePart, color: Color3 } } = {}
	-- A part that turns with the wheel, placed at `at` in the wheel's frame (studs).
	local function turn(props: { [string]: any }, at: CFrame): BasePart
		props.CFrame = centre * at
		local p = part(props, model)
		table.insert(turning, { part = p, at = at })
		return p
	end
	local function still(props: { [string]: any }, at: CFrame): BasePart
		props.CFrame = centre * at
		return part(props, model)
	end
	-- Clockwise from the top, as the web lays its slices out.
	local function around(theta: number): CFrame
		return CFrame.Angles(0, 0, -theta)
	end

	-- The tyre: a ring of rubber blocks round the rim, the raised sidewall lettering (which turns,
	-- so you see the wheel go) and the dark barrel behind the slices.
	local rubber = hex("#1f2226")
	local BLOCKS = 72
	for i = 0, BLOCKS - 1 do
		local th = i / BLOCKS * math.pi * 2
		local r = (TYRE_IN + TYRE_OUT) / 2
		local len = 2 * math.pi * TYRE_OUT / BLOCKS * 1.04
		still({ Name = "Tyre", Size = Vector3.new(len, TYRE_OUT - TYRE_IN, 0.6) * S, Color = rubber, Material = Enum.Material.SmoothPlastic }, around(th) * CFrame.new(0, r * S, 0))
		-- Tread blocks on the crown, staggered either side.
		local side = if i % 2 == 0 then -1 else 1
		still({ Name = "Tread", Size = Vector3.new(0.07, 0.04, 0.2) * S, Color = hex("#17191c") }, around(th + math.pi / BLOCKS) * CFrame.new(0, (TYRE_OUT + 0.01) * S, side * 0.13 * S) * CFrame.Angles(0, side * 0.35, 0))
	end
	local text = "CARTOPIA  ★  DAILY SPIN  ★  RADIAL T/S  ★  "
	local chars = {}
	for _, c in utf8.codes(text .. text) do
		table.insert(chars, utf8.char(c))
	end
	local rr = (TYRE_IN + TYRE_OUT) / 2
	for i, ch in chars do
		if ch ~= " " then
			local p = turn({ Name = "Letter", Size = Vector3.new(0.17, 0.2, 0.01) * S, Transparency = 1 }, around((i - 1) / #chars * math.pi * 2) * CFrame.new(0, rr * S, 0.305 * S))
			label(p, ch, "#b8c2c9")
		end
	end
	still({ Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, TYRE_IN * 2, TYRE_IN * 2) * S, Color = hex("#5d6a75"), Material = Enum.Material.Metal }, CFrame.new(0, 0, -0.25 * S) * ALONG_Z)

	-- The chrome rim between the slices and the tyre, and its chase lights.
	local chrome = hex("#e9eef2")
	local RIM = 64
	for i = 0, RIM - 1 do
		local th = i / RIM * math.pi * 2
		local r0, r1 = FACE - 0.03, TYRE_IN + 0.02
		still({ Name = "Rim", Size = Vector3.new(2 * math.pi * r1 / RIM * 1.06, r1 - r0, 0.05) * S, Color = chrome, Material = Enum.Material.Metal, Reflectance = 0.35 }, around(th) * CFrame.new(0, (r0 + r1) / 2 * S, 0.12 * S))
	end
	local bulbs: { BasePart } = {}
	for i = 0, 23 do
		local th = i / 24 * math.pi * 2 + math.pi / 24
		table.insert(bulbs, still({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.075, 0.075, 0.075) * S, Color = hex("#fff6c2"), Material = Enum.Material.Neon }, around(th) * CFrame.new(0, 1.625 * S, 0.16 * S)))
	end

	-- The slices: each a fan of three thin triangles from the middle out to the rim (two wedges
	-- each), so the outer edge is near round; the hub hides where they meet.
	local thick = 0.06 * S
	for i, s in WHEEL do
		local base = hex(wheel.TIER_COLOR[s.tier])
		if i % 2 == 0 then
			base = Color3.new(base.R * 0.86, base.G * 0.86, base.B * 0.86)
		end
		local FAN = 3
		local h = STEP / FAN / 2
		for k = 0, FAN - 1 do
			local mid = (i - 1) * STEP + (k + 0.5) * STEP / FAN
			local R = FACE * S
			local la, lb = R * math.cos(h), R * math.sin(h)
			for _, sd in { 1, -1 } do
				local x = Vector3.new(0, 0, -sd)
				local y = Vector3.new(0, -1, 0)
				local z = Vector3.new(-sd, 0, 0)
				local at = around(mid) * CFrame.fromMatrix(Vector3.new(sd * lb / 2, la / 2, 0.04 * S), x, y, z)
				local p = turn({ Name = "Slice", Shape = Enum.PartType.Wedge, Size = Vector3.new(thick, la, lb), Color = base, Reflectance = 0.08 }, at)
				table.insert(slices, { part = p, color = base, index = i } :: any)
			end
		end
		-- The prize and the amount, upright along the slice's middle.
		local mid = (i - 0.5) * STEP
		prize(s, function(props, at)
			return turn(props, around(mid) * CFrame.new(0, 1.13 * S, 0.16 * S) * at)
		end)
		local t = amount(s, level)
		if t then
			local p = turn({ Name = "Amount", Size = Vector3.new(0.62, 0.23, 0.01) * S, Transparency = 1 }, around(mid) * CFrame.new(0, 0.7 * S, 0.1 * S))
			label(p, t, "#ffffff", "#14213d")
		end
	end
	-- Spokes on the slice edges, a peg at each end for the flapper.
	for i = 0, N - 1 do
		local a = around(i * STEP)
		turn({ Name = "Spoke", Size = Vector3.new(0.09, FACE - HUB, 0.08) * S, Color = chrome, Material = Enum.Material.Metal, Reflectance = 0.35 }, a * CFrame.new(0, (HUB + FACE) / 2 * S, 0.17 * S))
		turn({ Name = "Inlay", Size = Vector3.new(0.025, FACE - HUB - 0.1, 0.01) * S, Color = hex("#5d6a75"), Material = Enum.Material.Metal }, a * CFrame.new(0, (HUB + FACE) / 2 * S, 0.212 * S))
		turn({ Name = "Peg", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 0.07, 0.07) * S, Color = chrome, Material = Enum.Material.Metal }, a * CFrame.new(0, (FACE - 0.08) * S, 0.22 * S) * ALONG_Z)
		turn({ Name = "PegTip", Shape = Enum.PartType.Ball, Size = Vector3.new(0.09, 0.09, 0.09) * S, Color = hex("#e53935") }, a * CFrame.new(0, (FACE - 0.08) * S, 0.34 * S))
	end

	-- The hub: chrome, five lug nuts and the red enamel cap with its white star.
	still({ Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, (HUB + 0.06) * 2, (HUB + 0.06) * 2) * S, Color = chrome, Material = Enum.Material.Metal, Reflectance = 0.35 }, CFrame.new(0, 0, 0.15 * S) * ALONG_Z)
	for i = 0, 4 do
		turn({ Name = "Nut", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 0.09, 0.09) * S, Color = hex("#5d6a75"), Material = Enum.Material.Metal }, around(i / 5 * math.pi * 2) * CFrame.new(0, 0.3 * S, 0.26 * S) * ALONG_Z)
	end
	still({ Name = "CapRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.03, 0.48, 0.48) * S, Color = chrome, Material = Enum.Material.Metal, Reflectance = 0.35 }, CFrame.new(0, 0, 0.29 * S) * ALONG_Z)
	turn({ Name = "Cap", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.03, 0.44, 0.44) * S, Color = hex("#e53935"), Reflectance = 0.1 }, CFrame.new(0, 0, 0.3 * S) * ALONG_Z)
	local star = turn({ Name = "Star", Size = Vector3.new(0.3, 0.3, 0.01) * S, Transparency = 1 }, CFrame.new(0, 0, 0.32 * S))
	label(star, "★", "#ffffff")

	return model, centre, turning, slices, bulbs
end

-- The rubber flapper on its bracket over the top of the tyre.
local function buildFlapper(world: Folder): (CFrame, { Piece })
	local pivot = CFrame.new(P(0, CY + TYRE_OUT + 0.14, 0.3))
	local steel = hex("#455a64")
	part({ Name = "Bracket", Size = Vector3.new(0.1, 0.1, 0.75) * S, CFrame = pivot * CFrame.new(0, 0.1 * S, -0.3 * S), Color = steel, Material = Enum.Material.Metal }, world)
	part({ Name = "Hinge", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 0.12, 0.12) * S, CFrame = pivot * ALONG_Z, Color = hex("#e9eef2"), Material = Enum.Material.Metal, Reflectance = 0.3 }, world)
	local pieces: { Piece } = {}
	local yellow = hex("#ffc400")
	for _, d in {
		{ Size = Vector3.new(0.2, 0.26, 0.06), at = CFrame.new(0, -0.15 * S, 0) },
		{ Size = Vector3.new(0.13, 0.13, 0.06), at = CFrame.new(0, -0.3 * S, 0) * CFrame.Angles(0, 0, math.pi / 4) },
		{ Size = Vector3.new(0.08, 0.08, 0.01), at = CFrame.new(0, -0.12 * S, 0.035 * S), color = "#fff3b0" },
	} do
		local p = part({ Name = "Flapper", Size = d.Size * S, CFrame = pivot * d.at, Color = if d.color then hex(d.color) else yellow, Reflectance = 0.1 }, world)
		table.insert(pieces, { part = p, at = d.at })
	end
	return pivot, pieces
end

-- The steel A-frame and the hazard-ringed plinth the wheel stands on.
local function buildStand(world: Folder)
	local steel = hex("#455a64")
	part({ Name = "Plinth", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, 3.1, 3.1) * S, CFrame = CFrame.new(P(0, 0.09, 0)) * ALONG_Y, Color = hex("#37474f"), Material = Enum.Material.Metal }, world)
	part({ Name = "PlinthTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.01, 2.96, 2.96) * S, CFrame = CFrame.new(P(0, 0.182, 0)) * ALONG_Y, Color = hex("#56656e"), Material = Enum.Material.Metal }, world)
	local BANDS = 28
	for i = 0, BANDS - 1 do
		local a = i / BANDS * math.pi * 2
		part({ Name = "Hazard", Size = Vector3.new(2 * math.pi * 1.6 / BANDS * 1.02, 0.1, 0.03) * S, CFrame = CFrame.new(P(0, 0.09, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, 1.6 * S), Color = if i % 2 == 0 then hex("#ffd600") else hex("#212121") }, world)
	end
	for _, sd in { -1, 1 } do
		part({ Name = "Leg", Size = Vector3.new(0.14, 2.5, 0.14) * S, CFrame = CFrame.new(P(sd * 0.62, 1.32, -0.45)) * CFrame.Angles(0, 0, sd * 0.2), Color = steel, Material = Enum.Material.Metal }, world)
		part({ Name = "Foot", Size = Vector3.new(0.4, 0.06, 0.4) * S, CFrame = CFrame.new(P(sd * 0.62, 0.22, -0.45)), Color = steel, Material = Enum.Material.Metal }, world)
	end
	part({ Name = "Axle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 0.2, 0.2) * S, CFrame = CFrame.new(P(0, CY, -0.4)) * ALONG_Z, Color = hex("#e9eef2"), Material = Enum.Material.Metal }, world)
	part({ Name = "Arm", Size = Vector3.new(0.12, 2.3, 0.12) * S, CFrame = CFrame.new(P(0, CY + 1.2, -0.45)), Color = steel, Material = Enum.Material.Metal }, world)
	-- A soft glow pooled on the floor under the wheel.
	part({ Name = "Glow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.01, 4.8, 4.8) * S, CFrame = CFrame.new(P(0, 0.012, 0.6)) * ALONG_Y, Color = hex("#ffd180"), Material = Enum.Material.Neon, Transparency = 0.93 }, world)
end

-- Tyre racks either side: orange uprights, blue beams and rows of tyres standing in them.
local BANDS = { "#e53935", "#ffc400", "#fafafa", "#43a047", "#1e88e5" }
local function tyreRack(world: Instance, x: number, flip: boolean)
	local ry = if flip then -0.35 else 0.35
	local at = CFrame.new(P(x, 0, -3.2)) * CFrame.Angles(0, ry, 0)
	for _, dx in { -1.6, 1.6 } do
		part({ Name = "Upright", Size = Vector3.new(0.1, 4, 0.1) * S, CFrame = at * CFrame.new(dx * S, 2 * S, 0), Color = hex("#ff6d00") }, world)
	end
	for _, y in { 0.1, 1.45, 2.8 } do
		part({ Name = "Beam", Size = Vector3.new(3.3, 0.1, 0.5) * S, CFrame = at * CFrame.new(0, y * S, 0), Color = hex("#1565c0") }, world)
		for i = 0, 5 do
			local spot = (at * CFrame.new((-1.25 + i * 0.5) * S, (y + 0.05) * S, 0)).Position
			Kit.tyre(world, spot, 0.42, 0.26, BANDS[(i + math.round(y)) % #BANDS + 1], false, ry)
		end
	end
end

local function hangingLamp(world: Instance, x: number, z: number): BasePart
	local y = 5.4
	part({ Name = "Cord", Size = Vector3.new(0.03, 2.8, 0.03) * S, CFrame = CFrame.new(P(x, y + 1.4, z)), Color = hex("#263238") }, world)
	part({ Name = "Shade", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.84, 0.84) * S, CFrame = CFrame.new(P(x, y, z)) * ALONG_Y, Color = hex("#2e3b43"), Material = Enum.Material.Metal }, world)
	local bulb = part({ Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.2, 0.2, 0.2) * S, CFrame = CFrame.new(P(x, y - 0.12, z)), Color = hex("#fff8e1"), Material = Enum.Material.Neon }, world)
	local holder = part({ Name = "LampLight", Size = Vector3.new(0.1, 0.1, 0.1) * S, CFrame = CFrame.new(P(x, y - 0.2, z)) * CFrame.Angles(-math.pi / 2, 0, 0), Transparency = 1 }, world)
	local l = Instance.new("SpotLight")
	l.Angle = 70
	l.Range = 50
	l.Brightness = 1.6
	l.Color = hex("#ffe0a3")
	l.Parent = holder
	return bulb
end

local function light(world: Instance, kind: string, at: CFrame, props: { [string]: any })
	local holder = part({ Name = "Light", Size = Vector3.new(0.5, 0.5, 0.5), CFrame = at, Transparency = 1 }, world)
	local l = Instance.new(kind)
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = holder
end

-- The room: floor, walls, signs, door, racks, stacks, chests, a cone, lamps and the lights.
local function buildShop(world: Folder): { BasePart }
	part({ Name = "Floor", Size = Vector3.new(36, 0.2, 26) * S, CFrame = CFrame.new(P(0, -0.1, 0)), Color = hex("#9aa3a8"), Material = Enum.Material.Concrete }, world)
	for _, x in { -2.4, 2.4 } do
		part({ Name = "FloorLine", Size = Vector3.new(0.12, 0.01, 12) * S, CFrame = CFrame.new(P(x, 0.005, 2)), Color = hex("#ffd600") }, world)
	end
	part({ Name = "BackWall", Size = Vector3.new(30, 8, 0.2) * S, CFrame = CFrame.new(P(0, 4, -6)), Color = hex("#5c6b78"), Material = Enum.Material.Metal }, world)
	-- Ribs down the wall, as the web's corrugated texture.
	for i = 0, 59 do
		part({ Name = "Rib", Size = Vector3.new(0.12, 8, 0.04) * S, CFrame = CFrame.new(P(-15 + 0.25 + i * 0.5, 4, -5.88)), Color = hex("#4e5c68") }, world)
	end
	part({ Name = "Skirting", Size = Vector3.new(30, 0.9, 0.12) * S, CFrame = CFrame.new(P(0, 0.45, -5.82)), Color = hex("#37474f") }, world)
	part({ Name = "Ceiling", Size = Vector3.new(30, 0.2, 26) * S, CFrame = CFrame.new(P(0, 8.1, 0)), Color = hex("#1a1426") }, world)
	for _, x in { -13, 13 } do
		part({ Name = "SideWall", Size = Vector3.new(0.2, 8, 26) * S, CFrame = CFrame.new(P(x, 4, 0)), Color = hex("#4d5962"), Material = Enum.Material.Metal }, world)
		for i = 0, 51 do
			part({ Name = "Rib", Size = Vector3.new(0.04, 8, 0.12) * S, CFrame = CFrame.new(P(x - math.sign(x) * 0.12, 4, -13 + 0.25 + i * 0.5)), Color = hex("#404b53") }, world)
		end
	end

	-- The neon sign (wide screens only: on a phone the top bar covers it).
	local sign: { BasePart } = {}
	table.insert(sign, part({ Name = "Sign", Size = Vector3.new(5.8, 1.5, 0.12) * S, CFrame = CFrame.new(P(0, 6.35, -5.78)), Color = hex("#120a1e") }, world))
	local face = part({ Name = "SignFace", Size = Vector3.new(5.5, 1.25, 0.02) * S, CFrame = CFrame.new(P(0, 6.35, -5.71)), Color = hex("#140c22") }, world)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 8
	gui.LightInfluence = 0
	local l = Instance.new("TextLabel")
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundColor3 = hex("#140c22")
	l.BorderSizePixel = 0
	l.Text = "DAILY SPIN"
	l.TextColor3 = hex("#ffc400")
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.Parent = gui
	gui.Parent = face
	table.insert(sign, face)
	for _, b in { { 0, 0.7, 5.7, 0.05 }, { 0, -0.7, 5.7, 0.05 }, { -2.85, 0, 0.05, 1.4 }, { 2.85, 0, 0.05, 1.4 } } do
		table.insert(sign, part({ Name = "SignNeon", Size = Vector3.new(b[3], b[4], 0.05) * S, CFrame = CFrame.new(P(b[1], 6.35 + b[2], -5.68)), Color = hex("#ff4fd8"), Material = Enum.Material.Neon }, world))
	end
	local sub = part({ Name = "SubSign", Size = Vector3.new(2.6, 0.6, 0.04) * S, CFrame = CFrame.new(P(6.4, 4.6, -5.8)), Color = hex("#263238") }, world)
	Kit.sign(sub, "TYRES · RIMS · PRIZES", "#4fc3f7", "#263238")

	-- The roller door, its dark gap and the hazard posts.
	part({ Name = "Shutter", Size = Vector3.new(3.4, 2.6, 0.08) * S, CFrame = CFrame.new(P(-7.4, 2.6, -5.84)), Color = hex("#b0bec5"), Material = Enum.Material.Metal }, world)
	for i = 0, 12 do
		part({ Name = "Slat", Size = Vector3.new(3.4, 0.02, 0.03) * S, CFrame = CFrame.new(P(-7.4, 1.35 + i * 0.2, -5.79)), Color = hex("#8a9aa3") }, world)
	end
	part({ Name = "DoorGap", Size = Vector3.new(3.2, 1.3, 0.02) * S, CFrame = CFrame.new(P(-7.4, 0.65, -5.86)), Color = hex("#1a2a4a") }, world)
	for _, dx in { -1.75, 1.75 } do
		part({ Name = "Post", Size = Vector3.new(0.14, 4, 0.14) * S, CFrame = CFrame.new(P(-7.4 + dx, 2, -5.8)), Color = hex("#ffd600") }, world)
		for k = 0, 7 do
			part({ Name = "PostStripe", Size = Vector3.new(0.15, 0.2, 0.15) * S, CFrame = CFrame.new(P(-7.4 + dx, 0.25 + k * 0.5, -5.8)) * CFrame.Angles(0, 0, 0.5), Color = hex("#212121") }, world)
		end
	end

	tyreRack(world, -5.6, false)
	tyreRack(world, 5.6, true)
	Kit.tyreStack(world, ORIGIN, -3.1, -1.2, 5, "#ffc400")
	Kit.tyreStack(world, ORIGIN, -3.6, -0.4, 3, "#e53935")
	Kit.tyreStack(world, ORIGIN, 3.3, -1.0, 4, "#4fc3f7")
	Kit.toolChest(world, ORIGIN, 3.9, -4.6, "#c62828")
	Kit.toolChest(world, ORIGIN, -3.8, -4.8, "#1565c0")
	-- A tyre leaning on the plinth, and a traffic cone.
	Kit.tyre(world, P(1.95, 0, 0.9), 0.36, 0.24, "#ffc400", false, 0.9)
	part({ Name = "ConeBase", Size = Vector3.new(0.36, 0.04, 0.36) * S, CFrame = CFrame.new(P(-2.1, 0.02, 1.2)), Color = hex("#212121") }, world)
	for k = 0, 4 do
		local r = 0.16 * (1 - k / 5) + 0.02
		part({ Name = "Cone", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, r * 2, r * 2) * S, CFrame = CFrame.new(P(-2.1, 0.09 + k * 0.1, 1.2)) * ALONG_Y, Color = if k == 2 then hex("#fafafa") else hex("#ff6d00") }, world)
	end
	hangingLamp(world, -4.5, -2)
	hangingLamp(world, 4.5, -2)

	-- The lights: the spot on the wheel from the front, pink and cyan either side, gold by the sign.
	local target = P(0, CY, 0)
	local spotAt = P(0, 5.5, 4)
	light(world, "SpotLight", CFrame.lookAt(spotAt, target), { Angle = 55, Range = 60, Brightness = 2.5, Color = hex("#fff1d6"), Shadows = true })
	light(world, "PointLight", CFrame.new(P(-3.5, 3, 2.5)), { Range = 40, Brightness = 3, Color = hex("#ff4fd8") })
	light(world, "PointLight", CFrame.new(P(3.5, 3, 2.5)), { Range = 40, Brightness = 3, Color = hex("#4fc3f7") })
	light(world, "PointLight", CFrame.new(P(0, 6.35, -5)), { Range = 30, Brightness = 2, Color = hex("#ffc400") })
	-- A soft fill so the room isn't black beyond the lamps (the web's hemisphere light).
	light(world, "PointLight", CFrame.new(P(0, 6, 6)), { Range = 60, Brightness = 0.6, Color = hex("#6b7cc0") })
	return sign
end

-- ── Confetti ──────────────────────────────────────────────────────────────────────────────────

type Bit = { part: BasePart, pos: Vector3, vel: Vector3, spin: Vector3, rot: CFrame }

local function confetti(world: Folder, color: Color3): { Bit }
	local bits: { Bit } = {}
	local cols = { color, hex("#ffd54f"), hex("#ffffff") }
	for i = 1, 150 do
		local a = math.random() * math.pi * 2
		local sp = 1.5 + math.random() * 3
		local pos = P(0, CY + 1.4, 0.6)
		local p = part({ Name = "Confetti", Size = Vector3.new(0.6, 0.6, 0.08), CFrame = CFrame.new(pos), Color = cols[i % 3 + 1], Material = Enum.Material.Neon }, world)
		table.insert(bits, {
			part = p,
			pos = pos,
			vel = Vector3.new(math.cos(a) * sp, 2 + math.random() * 4, 1 + math.random() * 2) * S,
			spin = Vector3.new(math.random() * 10 - 5, math.random() * 10 - 5, math.random() * 10 - 5),
			rot = CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
		})
	end
	return bits
end

-- ── The shop ──────────────────────────────────────────────────────────────────────────────────

function WheelShop.build(level: number): Shop
	local world = Instance.new("Folder")
	world.Name = "DailySpinShop"
	local _, centre, turning, slices, bulbs = buildWheel(world, level)
	local pivot, flapper = buildFlapper(world)
	buildStand(world)
	local sign = buildShop(world)
	world.Parent = workspace

	local clock = 0
	local kickAt = -10
	local wonIndex: number? = nil
	local bits: { Bit }? = nil
	local bitsT = 0
	local parts: { BasePart } = {}
	for _, t in turning do
		table.insert(parts, t.part)
	end
	local cfs: { CFrame } = table.create(#parts)

	local shop = {} :: Shop
	shop.world = world

	function shop.setAngle(deg: number)
		local spin = centre * CFrame.Angles(0, 0, -math.rad(deg))
		for i, t in turning do
			cfs[i] = spin * t.at
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		world:SetAttribute("Angle", deg % 360)
	end

	function shop.kick()
		kickAt = clock
	end

	-- The winning slice glows and confetti flies off the wheel (nil puts it back to spinning).
	function shop.won(index: number?, color: Color3?)
		wonIndex = index
		if bits then
			for _, b in bits do
				b.part:Destroy()
			end
			bits = nil
		end
		if index then
			bits = confetti(world, color or hex("#ffd54f"))
			bitsT = 0
		else
			for _, sl in slices :: { any } do
				sl.part.Color = sl.color
			end
		end
	end

	-- Where the camera stands for this screen (the web's useFitCamera and view offset: on a wide
	-- screen the wheel sits left of the dock, on a tall one high above it); and whether it's wide.
	function shop.camera(vp: Vector2): (CFrame, boolean)
		local wide = vp.X >= 900 and vp.X > vp.Y * 1.25
		local aspect = vp.X / math.max(1, vp.Y)
		local t = math.tan(math.rad(FOV / 2))
		local halfW, halfH = if wide then 4.6 else 2.45, if wide then 2.95 else 2.85
		local dist = math.max(halfH / t, halfW / (t * aspect)) * S
		local target = P(0, CY + 0.25, 0)
		local dir = Vector3.new(0, 0.1, 1).Unit
		local from = target + dir * dist
		local look = CFrame.lookAt(from, target)
		-- three's setViewOffset slides the picture; sliding the camera the same way matches it at the wheel.
		local shift = if wide then look.RightVector * (0.32 * dist * t * aspect) else look.UpVector * -(0.34 * dist * t)
		return CFrame.lookAt(from + shift, target + shift), wide
	end

	function shop.setWide(wide: boolean)
		for _, p in sign do
			p.Transparency = if wide then 0 else 1
			local g = p:FindFirstChildOfClass("SurfaceGui")
			if g then
				g.Enabled = wide
			end
		end
	end

	-- Each frame: the chase lights, the flapper's knock and spring, the winner's glow, the confetti.
	function shop.step(dt: number)
		clock += dt
		local on = math.floor(clock * 5) % 2 == 0
		for i, b in bulbs do
			local lit = (i % 2 == 0) == on
			b.Color = if lit then hex("#fff6c2") else hex("#b8862a")
			b.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		local since = clock - kickAt
		local swing = if since >= 0 and since < 0.6 then 0.42 * math.exp(-since * 9) * math.cos(since * 30) else 0
		local turned = pivot * CFrame.Angles(0, 0, swing)
		for _, f in flapper do
			f.part.CFrame = turned * f.at
		end
		if wonIndex then
			local glow = 0.2 + 0.15 * math.sin(clock * 6)
			for _, sl in slices :: { any } do
				if sl.index == wonIndex then
					sl.part.Color = sl.color:Lerp(Color3.new(1, 1, 1), glow)
				end
			end
		end
		local b = bits
		if b then
			bitsT += dt
			local d = math.min(dt, 0.05)
			for _, bit in b do
				bit.vel = Vector3.new(bit.vel.X * 0.985, bit.vel.Y - 6 * S * d, bit.vel.Z)
				local pos = bit.pos + bit.vel * d
				if pos.Y < ORIGIN.Y + 0.2 then
					pos = Vector3.new(pos.X, ORIGIN.Y + 0.2, pos.Z)
					bit.vel = Vector3.zero
					bit.spin = Vector3.zero
				end
				bit.pos = pos
				bit.rot = bit.rot * CFrame.Angles(bit.spin.X * d, bit.spin.Y * d, bit.spin.Z * d)
				bit.part.CFrame = CFrame.new(pos) * bit.rot
			end
			if bitsT > 6 then
				for _, bit in b do
					bit.part:Destroy()
				end
				bits = nil
			end
		end
	end

	function shop.destroy()
		world:Destroy()
	end

	shop.setAngle(0)
	shop.step(0)
	return shop
end

return WheelShop
