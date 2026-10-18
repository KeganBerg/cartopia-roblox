--!strict
-- Draws a player's town in the world from their save: land, roads, buildings and parked cars,
-- with the web game's own models (Shared.Models). Each town sits on its own lot (Towns.slot);
-- re-rendering only rebuilds what changed.
--
-- Positions follow the web game's grid: tile (x, z) is TILE web units wide, centred so the
-- starter town's middle is the lot's origin, and one web unit is Catalog.SCALE studs.
--
-- Buildings carry attributes the client reads for its job timers: Uid, Def, Level, JobEndsAt
-- (ms, or absent), Owner (user id). Clicking a building (its ClickDetector) taps it, as on the web.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local data = require(Game.data) :: any
local placement = require(Game.placement) :: any
local lualib = require(Game.lualib_bundle) :: any
local roadLayout = require(Game.scene_traffic_layout) :: any
local streetFurniture = require(Game.streetFurniture) :: any
local merge = require(Game.merge) :: any
local cityLook = require(Game.cityLook) :: any
local Builder = require(Shared.Models.Builder)
local Pictures = require(Shared.Pictures)
local CityTint = require(Shared.CityTint)
local Catalog = require(Shared.Models.Catalog)
local Paint = require(Shared.Models.Paint)
local Mods = require(Shared.Models.Mods)
local Panels = require(Shared.Models.Panels)
local Trim = require(Shared.Models.Trim)
local Skins = require(Shared.Models.Skins)

local SCALE = Catalog.SCALE
local TILE = data.TILE * SCALE -- studs per tile
local GRID = data.GRID
local PLOT = data.PLOT

-- Asphalt and lawn in the web game's colours (textures.ts asphaltTex; season.ts grass).
local ASPHALT = Color3.fromHex("#9ba1a8")
local GRIME = Color3.fromHex("#5f646b")
local PAVING = Color3.fromHex("#eadfc8")
local GRASS = Color3.fromHex(Catalog.GRASS)
-- Ground layers, in studs. The web game stacks its flat layers a few hundredths of a unit apart,
-- which an orthographic camera tells apart; Roblox's camera stands hundreds of studs back, where
-- surfaces that close blend into one (the roads and lots vanished into the grass). So the lawn
-- sits well under the asphalt (top 0.2), and the meadow well under it.
--
-- A textured surface must never lie under a road or a lot, however far down: from afar Roblox
-- draws a Texture over whatever stands just above it, and the lawn's showed through the roads and
-- lots of every plot bought after the first. So the lawn's turf covers only the free tiles, the
-- meadow only the plots not bought, and under roads and lots lies plain untextured ground (BASE).
local LAND_TOP = -0.4
local MEADOW_TOP = -0.9
local MEADOW = Color3.fromHex(Catalog.MEADOW)
-- The meadow reaches 2,000 studs out from the town's middle; the plots span PLOT_LO to PLOT_HI.
local MEADOW_REACH = 2000
local PLOT_LO = data.PLOT_MIN * PLOT * TILE - (GRID / 2) * TILE
local PLOT_HI = (data.PLOT_MAX + 1) * PLOT * TILE - (GRID / 2) * TILE

-- Lays one of the web game's ground textures (Catalog.TEXTURES: the lawn's or the meadow's) over a
-- part's top face, once its image is uploaded; until then the part's flat colour shows. Images tile
-- from `from` (a world point), so neighbouring parts line up.
local function groundTexture(p: BasePart, key: string, from: Vector3)
	local t = ((Catalog :: any).TEXTURES or {})[key]
	if not t or t.image == 0 then
		return
	end
	local tex = Instance.new("Texture")
	tex.Name = "Ground"
	tex.Face = Enum.NormalId.Top
	Pictures.set(tex, "Texture", t.image)
	tex.StudsPerTileU = t.span
	tex.StudsPerTileV = t.span
	local corner = p.CFrame.Position - p.Size / 2
	tex.OffsetStudsU = (corner.X - from.X) % t.span
	tex.OffsetStudsV = (corner.Z - from.Z) % t.span
	-- Which image it is, for the preview tools (tools/emulate/render.mjs).
	tex:SetAttribute("Image", t.name)
	tex.Parent = p
end

-- A piece of meadow, its top at MEADOW_TOP, centred `at` (studs from the town's middle) and `size`
-- across.
local function meadowPart(parent: Instance, origin: Vector3, at: Vector3, size: Vector3): Part
	local meadow = Instance.new("Part")
	meadow.Name = "Meadow"
	meadow.Anchored = true
	meadow.Size = Vector3.new(size.X, 4, size.Z)
	meadow.CFrame = CFrame.new(origin + Vector3.new(at.X, MEADOW_TOP - 2, at.Z))
	meadow.Color = MEADOW
	-- Flat colour like the web's ground: Roblox's Grass material reads far brighter and greener.
	meadow.Material = Enum.Material.SmoothPlastic
	meadow.TopSurface = Enum.SurfaceType.Smooth
	meadow.CastShadow = false
	-- The web lines its meadow images up 8 units off the town's middle (World.tsx OUTER).
	groundTexture(meadow, "meadow", origin + Vector3.new(8, 0, 8) * SCALE)
	meadow.Parent = parent
	return meadow
end

local TownView = {}
TownView.__index = TownView

export type TownView = typeof(setmetatable(
	{} :: {
		folder: Folder,
		origin: Vector3,
		userId: number,
		onTap: (uid: string) -> (),
		land: { [string]: BasePart },
		roads: { [string]: Model },
		lawnKey: string?,
		buildings: { [string]: { model: Model, key: string } },
		cars: { [string]: { model: Model, key: string } },
		-- The last save drawn, and the cars whose mod meshes are loading.
		last: any,
		waiting: { [string]: boolean },
	},
	TownView
))

-- World position (studs, ground level) of a tile's centre; x and z may be fractional.
function TownView.tileToWorld(self: TownView, x: number, z: number): Vector3
	return self.origin + Vector3.new((x - (GRID - 1) / 2) * TILE, 0, (z - (GRID - 1) / 2) * TILE)
end

-- The tile under a world position.
function TownView.worldToTile(self: TownView, p: Vector3): (number, number)
	local d = p - self.origin
	return math.round(d.X / TILE + (GRID - 1) / 2), math.round(d.Z / TILE + (GRID - 1) / 2)
end

function TownView.new(parent: Instance, name: string, origin: Vector3, userId: number, onTap: (uid: string) -> ()): TownView
	local folder = Instance.new("Folder")
	folder.Name = name
	folder:SetAttribute("Owner", userId)
	folder:SetAttribute("Origin", origin)
	folder:SetAttribute("TileSize", TILE)
	folder:SetAttribute("Grid", GRID)
	for _, sub in { "Land", "Lawn", "Roads", "Buildings", "Cars" } do
		local f = Instance.new("Folder")
		f.Name = sub
		f.Parent = folder
	end
	-- Meadow round the town out to the countryside's edge, 4,000 studs across like the web game's
	-- outer ground (World.tsx OUTER), in eight pieces round the plots (a part is at most 2,048
	-- studs); each plot not bought gets its own piece (_renderLand). The far pieces' middles are
	-- past what instance streaming sends a player, so the model is kept persistent: without it
	-- players saw Workspace.Ground in its place.
	local meadows = Instance.new("Model")
	meadows.Name = "Meadow"
	meadows.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	meadows.Parent = folder
	local cuts = { -MEADOW_REACH, PLOT_LO, PLOT_HI, MEADOW_REACH }
	for i = 1, 3 do
		for j = 1, 3 do
			if i == 2 and j == 2 then
				continue
			end
			local x0, x1, z0, z1 = cuts[i], cuts[i + 1], cuts[j], cuts[j + 1]
			meadowPart(meadows, origin, Vector3.new((x0 + x1) / 2, 0, (z0 + z1) / 2), Vector3.new(x1 - x0, 0, z1 - z0))
		end
	end
	folder.Parent = parent
	return setmetatable({
		folder = folder,
		origin = origin,
		userId = userId,
		onTap = onTap,
		land = {},
		roads = {},
		buildings = {},
		cars = {},
		last = nil,
		waiting = {},
	}, TownView)
end

function TownView.destroy(self: TownView)
	self.folder:Destroy()
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function splitKey(k: string): (number, number)
	local a, b = string.match(k, "^(-?%d+),(-?%d+)$")
	return tonumber(a) :: number, tonumber(b) :: number
end

-- A building's centre, as World.tsx's centerOf: the middle of its lot.
local function lotSize(def: any, rot: number?): (number, number)
	if (rot or 0) % 2 == 1 then
		return def.h, def.w
	end
	return def.w, def.h
end

-- Land plots: on every plot the town owns, plain ground in the lawn's colour, at the meadow's
-- level (the lawn's textured turf lies over its free tiles: _renderLawn); on every other plot, meadow.
function TownView._renderLand(self: TownView, land: { string })
	local owned = {}
	for _, k in land do
		owned[k] = true
	end
	for px = data.PLOT_MIN, data.PLOT_MAX do
		for pz = data.PLOT_MIN, data.PLOT_MAX do
			local k = `{px},{pz}`
			local have = self.land[k]
			if have and (have.Name == k) == (owned[k] == true) then
				continue
			end
			if have then
				have:Destroy()
			end
			local c = self:tileToWorld(px * PLOT + (PLOT - 1) / 2, pz * PLOT + (PLOT - 1) / 2)
			if owned[k] then
				self.land[k] = part({
					Name = k,
					Size = Vector3.new(PLOT * TILE, 4, PLOT * TILE),
					CFrame = CFrame.new(c + Vector3.new(0, MEADOW_TOP - 2, 0)),
					Color = GRASS,
					Material = Enum.Material.SmoothPlastic,
					CastShadow = false,
					Parent = (self.folder :: any).Land,
				})
			else
				self.land[k] = meadowPart((self.folder :: any).Meadow, self.origin, c - self.origin, Vector3.new(PLOT * TILE, 0, PLOT * TILE))
			end
		end
	end
end

-- Tufts.tsx's small deterministic hash, so the lawn stays put between loads: 0 <= h < 1.
local function imul(a: number, b: number): number
	-- 32-bit multiply, low bits only, without losing precision in doubles.
	local lo = (a * (b % 65536)) % 4294967296
	local hi = ((a * (b // 65536)) % 65536) * 65536
	return (lo + hi) % 4294967296
end
local function hash(x: number, z: number, k: number): number
	local h = (x * 374761393 + z * 668265263 + k * 2147483647) % 4294967296
	h = imul(bit32.bxor(h, bit32.rshift(h, 13)), 1274126177)
	return bit32.bxor(h, bit32.rshift(h, 16)) / 4294967296
end

-- A lawn piece, scaled (s across, s * sy tall) and turned ry about its foot.
local function scatter(parent: Instance, name: string, at: Vector3, ry: number, s: number, sy: number)
	local piece = Builder.build(name)
	if not piece then
		return
	end
	for _, p in piece:GetDescendants() do
		if not p:IsA("MeshPart") and p:GetAttribute("Mesh") and not Builder.previewMeshes then
			-- Its shape isn't uploaded yet, and a field of grey boxes is worse than bare lawn.
			piece:Destroy()
			return
		end
	end
	for _, p in piece:GetDescendants() do
		if p:IsA("BasePart") then
			local cf = p.CFrame
			p.Size = p.Size * Vector3.new(s, s * sy, s)
			p.CFrame = CFrame.new(cf.X * s, cf.Y * s * sy, cf.Z * s) * cf.Rotation
			p.CastShadow = false
			p.CanQuery = false
			p.CanTouch = false
		end
	end
	piece:PivotTo(CFrame.new(at) * CFrame.Angles(0, ry, 0))
	piece.Parent = parent
end

-- Lawn detail on the empty tiles of the town's land, as Tufts.tsx: grass clumps in the season's
-- greens, leaf heaps and mushroom rings in the fall, and pebbles, as many as the web draws.
local GREENS = 0
for name in Catalog.MODELS do
	if string.match(name, "^tuft:%d+$") then
		GREENS += 1
	end
end
function TownView._renderLawn(self: TownView, land: { string }, roads: { string }, buildings: { any })
	-- Tiles taken by a road or a building, and those of them that are paved (a road, or a lot).
	local used: { [string]: boolean } = {}
	local paved: { [string]: boolean } = {}
	for _, k in roads do
		used[k] = true
		paved[k] = true
	end
	local lots = {}
	for _, b in buildings do
		if b.stored then
			continue
		end
		local def = data.buildingDef(b.def)
		local w, h = lotSize(def, b.rot)
		local lot = def.kind ~= "decor" and def.kind ~= "obstacle"
		table.insert(lots, `{b.x},{b.z},{w},{h}`)
		for i = 0, w - 1 do
			for j = 0, h - 1 do
				used[`{b.x + i},{b.z + j}`] = true
				if lot then
					paved[`{b.x + i},{b.z + j}`] = true
				end
			end
		end
	end
	local key = table.concat(land, ";") .. "|" .. table.concat(roads, ";") .. "|" .. table.concat(lots, ";")
	if key == self.lawnKey then
		return
	end
	self.lawnKey = key
	local folder = (self.folder :: any).Lawn :: Folder
	folder:ClearAllChildren()
	-- The lawn's turf, textured, over every tile that isn't paved: each plot's free tiles in as few
	-- rectangles as rows allow. Never under a road or lot (see LAND_TOP).
	local corner = self:tileToWorld(-0.5, -0.5)
	for _, k in land do
		local px, pz = splitKey(k)
		local done: { [string]: boolean } = {}
		local function free(x: number, z: number): boolean
			local t = `{x},{z}`
			return not paved[t] and not done[t]
		end
		for z = pz * PLOT, pz * PLOT + PLOT - 1 do
			for x = px * PLOT, px * PLOT + PLOT - 1 do
				if not free(x, z) then
					continue
				end
				local x1 = x
				while x1 + 1 < (px + 1) * PLOT and free(x1 + 1, z) do
					x1 += 1
				end
				local z1 = z
				while z1 + 1 < (pz + 1) * PLOT do
					local row = true
					for i = x, x1 do
						if not free(i, z1 + 1) then
							row = false
							break
						end
					end
					if not row then
						break
					end
					z1 += 1
				end
				for i = x, x1 do
					for j = z, z1 do
						done[`{i},{j}`] = true
					end
				end
				local turf = part({
					Name = "Turf",
					Size = Vector3.new((x1 - x + 1) * TILE, LAND_TOP - MEADOW_TOP, (z1 - z + 1) * TILE),
					CFrame = CFrame.new(self:tileToWorld((x + x1) / 2, (z + z1) / 2) + Vector3.new(0, (LAND_TOP + MEADOW_TOP) / 2, 0)),
					Color = GRASS,
					Material = Enum.Material.SmoothPlastic,
					CastShadow = false,
					Parent = folder,
				})
				groundTexture(turf, "grass", corner)
			end
		end
	end
	local fall = Catalog.SEASON == "fall"
	local winter = Catalog.SEASON == "winter"
	for _, k in land do
		local px, pz = splitKey(k)
		for x = px * PLOT, px * PLOT + PLOT - 1 do
			for z = pz * PLOT, pz * PLOT + PLOT - 1 do
				if used[`{x},{z}`] then
					continue
				end
				local c = self:tileToWorld(x, z) + Vector3.new(0, LAND_TOP, 0)
				local function spot(k2: number, spread: number): Vector3
					return c + Vector3.new((hash(x, z, k2) - 0.5) * TILE * spread, 0, (hash(x, z, k2 + 101) - 0.5) * TILE * spread)
				end
				local tufts = if winter then math.floor(hash(x, z, 0) * 2) else 3 + math.floor(hash(x, z, 0) * 3)
				if GREENS > 0 then
					for t = 0, tufts - 1 do
						local tint = ((x + z + t) % GREENS + GREENS) % GREENS + 1
						scatter(folder, `tuft:{tint}`, spot(t + 1, 0.85), hash(x, z, t + 30) * 6, 1 + hash(x, z, t + 40) * 0.6, 0.7 + hash(x, z, t + 50) * 0.6)
					end
				end
				local roll = hash(x, z, 7)
				if (fall or winter) and roll > 0.86 then
					scatter(folder, "heap", spot(11, 0.6), hash(x, z, 12) * 6, 0.6 + hash(x, z, 13) * 0.5, 1)
				end
				if fall and roll > 0.5 and roll < 0.53 then
					local mid = spot(14, 0.4)
					for i = 0, 5 do
						local a = i / 6 * math.pi * 2
						scatter(folder, "mushroom", mid + Vector3.new(math.cos(a), 0, math.sin(a)) * 0.3 * SCALE, a, 0.7 + hash(x, z, i + 90) * 0.5, 1)
					end
				end
				if hash(x, z, 15) < 0.12 then
					scatter(folder, `rock:{(x + z) % 3 + 1}`, spot(16, 0.85), hash(x, z, 17) * 6, 0.22 + hash(x, z, 18) * 0.2, 1)
				end
			end
		end
	end
end

-- Road tiles, put together the way World.tsx's RoadTile does: asphalt, a sidewalk on every side
-- without road next door (rounding off corners, with ramps where crosswalks land), lane paint,
-- crosswalks and stop lines by intersections, manholes, and the lamps, hydrants and furniture
-- streetFurniture.ts stands on the sidewalks. The pieces themselves are the web game's own models.
local SIDES = { "e", "w", "s", "n" }
local SIDE_INDEX = { e = 1, w = 2, s = 3, n = 4 }
local SIDE_ROT = { s = 0, n = math.pi, e = math.pi / 2, w = -math.pi / 2 }
-- The sides at the -x and +x ends of a side's own frame (Roadside.tsx ENDS).
local ENDS = { s = { "w", "e" }, e = { "s", "n" }, w = { "n", "s" }, n = { "e", "w" } }
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
-- A tile's corners in CornerCurb turn order: east/west arm, south/north arm, diagonal step.
local CORNERS = { { 1, 3, 1, 1 }, { 1, 4, 1, -1 }, { 2, 4, -1, -1 }, { 2, 3, -1, 1 } }
local HALF = data.TILE / 2 -- web units, as the pieces are measured
local WALK = 0.4
-- Lane paint and kerb grime sit clearly above the asphalt, for the same reason as LAND_TOP.
local PAINT_Y = 0.02 * SCALE + 0.25

-- A flat strip of paint lying on the asphalt, at (x, z) web units from the tile's middle.
local function paint(m: Model, c: Vector3, x: number, z: number, w: number, d: number, color: string)
	part({
		Name = "Paint",
		Size = Vector3.new(w * SCALE, 0.1, d * SCALE),
		CFrame = CFrame.new(c + Vector3.new(x * SCALE, PAINT_Y - 0.05, z * SCALE)),
		Color = Color3.fromHex(color),
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = m,
	})
end

local function place(m: Model, name: string, cf: CFrame)
	local piece = Builder.build(name)
	if piece then
		piece:PivotTo(cf)
		for _, d in piece:GetChildren() do
			d.Parent = m
		end
		piece:Destroy()
	end
end

function TownView._roadModel(self: TownView, t: any): Model
	local m = Instance.new("Model")
	m.Name = t.key
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local c = self:tileToWorld(t.x, t.z)
	local here = CFrame.new(c)
	local arms, xing = t.arms, t.xing
	local e, w, s, n = arms[1], arms[2], arms[3], arms[4]
	local straightX = not t.junction and (e or w) and not s and not n
	local straightZ = not t.junction and (s or n) and not e and not w
	local crossing = xing[1] or xing[2] or xing[3] or xing[4]
	local plain = (straightX or straightZ) and not crossing
	local avenue = t.oneWay >= 0
	-- Asphalt, its top just above the grass (LAYER.lot).
	part({
		Name = "Asphalt",
		Size = Vector3.new(TILE, 0.4, TILE),
		CFrame = CFrame.new(c + Vector3.new(0, 0.02 * SCALE - 0.2, 0)),
		Color = ASPHALT,
		Material = Enum.Material.Asphalt,
		CastShadow = false,
		Parent = m,
	})
	for i, sd in SIDES do
		if arms[i] then
			continue
		end
		-- What the sidewalk meets at each end: a corner, a crosswalk ramp, or more sidewalk.
		local ends = {}
		for k, other in ENDS[sd] do
			local j = SIDE_INDEX[other]
			ends[k] = if not arms[j] then "corner" elseif xing[j] then "ramp" else "open"
		end
		local drain = plain and (t.x * 2 + t.z + (i - 1)) % 4 == 0
		place(m, `walk:{sd}:{ends[1]}:{ends[2]}` .. (if drain and ends[1] == "open" and ends[2] == "open" then ":drain" else ""), here)
		-- Grime along the kerb (RoadWear).
		local rot = CFrame.Angles(0, SIDE_ROT[sd], 0)
		part({
			Name = "Grime",
			Size = Vector3.new(TILE, 0.05, 0.32 * SCALE),
			CFrame = here * rot * CFrame.new(0, 0.02 * SCALE + 0.18, (HALF - WALK - 0.16) * SCALE),
			Color = GRIME,
			Transparency = 0.55,
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
			Parent = m,
		})
	end
	for i, corner in t.corners do
		if corner then
			place(m, `{corner}:{i - 1}`, here)
		end
	end
	if plain and (t.x * 3 + t.z * 7) % 5 == 1 then
		place(m, "manhole", here * CFrame.new((if straightX then 0 else 0.45) * SCALE, 0, (if straightX then 0.45 else 0) * SCALE))
	end
	-- Zebra crossings where the road meets an intersection, and stop lines before them.
	for i, sd in SIDES do
		if not xing[i] then
			continue
		end
		local across = sd == "e" or sd == "w"
		local off = (if sd == "e" or sd == "s" then 1 else -1) * (HALF - 0.32)
		for _, o in { -0.45, -0.15, 0.15, 0.45 } do
			if across then
				paint(m, c, off, o, 0.34, 0.16, "#f5f5f5")
			else
				paint(m, c, o, off, 0.16, 0.34, "#f5f5f5")
			end
		end
		if t.oneWay < 0 or t.oneWay == i - 1 then
			local dx, dz = DIRS[i][1], DIRS[i][2]
			local rx, rz = -dz, dx
			local at = HALF - 0.58
			paint(m, c, dx * at + rx * 0.45, dz * at + rz * 0.45, if dx ~= 0 then 0.08 else 0.8, if dx ~= 0 then 0.8 else 0.08, "#fafafa")
		end
	end
	local function dashes(alongX: boolean)
		for _, o in { -0.5, 0.5 } do
			if alongX then
				paint(m, c, o, 0, 0.45, 0.07, "#fafafa")
			else
				paint(m, c, 0, o, 0.07, 0.45, "#fafafa")
			end
		end
	end
	if straightX or straightZ then
		dashes(straightX == true)
	end
	if avenue then
		dashes(t.oneWay < 2)
		if t.mate == 0 or t.mate == 2 then
			-- Double yellow line down the middle of the avenue.
			local alongX = t.mate >= 2
			local edge = HALF
			for _, o in { -0.07, 0.07 } do
				if alongX then
					paint(m, c, 0, edge + o, data.TILE, 0.06, "#ffca28")
				else
					paint(m, c, edge + o, 0, 0.06, data.TILE, "#ffca28")
				end
			end
		end
	end
	-- Lamps, hydrants and sidewalk furniture.
	for _, f in streetFurniture.furnitureOf(t) do
		place(m, `prop:{f.kind}`, here * CFrame.Angles(0, SIDE_ROT[f.side], 0) * CFrame.new(f.x * SCALE, 0, f.z * SCALE))
	end
	return m
end

function TownView._renderRoads(self: TownView, roads: { string })
	local layout = roadLayout.layoutRoads(roads)
	local all = layout.tiles
	local seen = {}
	all:forEach(function(_, t: any)
		-- Zebra crossings where a road meets an intersection.
		local xing = {}
		for i, d in DIRS do
			local nb = all:get(`{t.x + d[1]},{t.z + d[2]}`)
			xing[i] = not t.junction and nb ~= nil and nb.junction == true
		end
		-- Corners (south-east round to south-west): a rounded kerb inside a bend, a rounded
		-- sidewalk on the outside corner of a block where two roads meet.
		local corners = {}
		for i, cn in CORNERS do
			local a, b = t.arms[cn[1]], t.arms[cn[2]]
			corners[i] = if not a and not b then "fillet" elseif a and b and not all:has(`{t.x + cn[3]},{t.z + cn[4]}`) then "curb" else false
		end
		local tile = {
			key = t.key,
			x = t.x,
			z = t.z,
			arms = t.arms,
			junction = t.junction,
			oneWay = t.oneWay,
			mate = t.mate,
			xing = xing,
			corners = corners,
		}
		local key = `{t.key}|{t.junction}|{t.oneWay}|{t.mate}|{tostring(t.arms[1])}{tostring(t.arms[2])}{tostring(t.arms[3])}{tostring(t.arms[4])}|`
			.. `{tostring(xing[1])}{tostring(xing[2])}{tostring(xing[3])}{tostring(xing[4])}|{tostring(corners[1])}{tostring(corners[2])}{tostring(corners[3])}{tostring(corners[4])}`
		seen[key] = true
		if not self.roads[key] then
			local m = self:_roadModel(tile)
			m.Parent = (self.folder :: any).Roads
			self.roads[key] = m
		end
	end)
	for k, m in self.roads do
		if not seen[k] then
			m:Destroy()
			self.roads[k] = nil
		end
	end
end

-- Grows a model built at the origin by s along its own axes (World.tsx groupScale): evenly for a
-- 2x2 or 4x4 block, along one side for a pair. A stretched part grows by how much the stretch
-- lengthens each of its own axes, so turned pieces stay close to the web's shape.
local function stretch(model: Model, s: Vector3)
	if s.X == s.Y and s.Y == s.Z then
		if s.X ~= 1 then
			model:ScaleTo(s.X)
		end
		return
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			local cf = p.CFrame
			local r = cf.Rotation
			p.Size = p.Size * Vector3.new((r.XVector * s).Magnitude, (r.YVector * s).Magnitude, (r.ZVector * s).Magnitude)
			p.CFrame = CFrame.new(cf.Position * s) * r
		end
	end
end

-- The model a building (or a merged block, `g`) draws, built at the origin and turned to face its
-- road. A merged block is the top-left building's model grown to fill it (a 2x4 is two 2x2s side
-- by side); four level 10 houses are the Vanguard Tower, eight the Globe Tower (World.tsx
-- BuildingLot), when the model build has them.
local function blockModel(b: any, g: any, turn: number, level: number): Model?
	local name = Builder.buildingName(b.def, level) or Builder.buildingName("parked", 1)
	local facing = CFrame.Angles(0, turn * math.pi / 2, 0)
	if g and merge.isGlobe(g) and Builder.has("landmark:globe") then
		local m = Builder.build("landmark:globe") :: Model
		m:PivotTo(facing)
		return m
	end
	if g and merge.isLandmark(g) and Builder.has("landmark:vanguard") then
		local m = Builder.build("landmark:vanguard") :: Model
		stretch(m, Vector3.one * (math.min(g.cols, g.rows) / 2))
		m:PivotTo(facing)
		return m
	end
	if not name then
		return nil
	end
	if not g then
		local m = Builder.build(name)
		if m then
			m:PivotTo(facing)
		end
		return m
	end
	local model: Model? = nil
	for _, part in merge.groupParts(g, turn) do
		local m = Builder.build(name)
		if not m then
			return nil
		end
		stretch(m, Vector3.new(part.scale[1], part.scale[2], part.scale[3]))
		m:PivotTo(CFrame.new(part.at[1] * TILE, 0, part.at[2] * TILE) * facing)
		if model then
			for _, d in m:GetChildren() do
				d.Parent = model
			end
			m:Destroy()
		else
			model = m
		end
	end
	return model
end

-- Flat layers closer than this (studs) flicker against each other from Roblox's camera.
local LAYER_GAP = 0.25

-- The web's models stack flat layers (a yard on a slab, a stripe on a yard) a few hundredths of a
-- unit apart, which flicker in Roblox (Rusty's yard did). Raises the top of each thin flat block or
-- disc lying within LAYER_GAP of a lower layer it overlaps, keeping its underside where it was.
-- `floor` is the top of the paved lot under the model, if any.
local function spreadLayers(model: Model, floor: number?)
	type Layer = { top: number, x0: number, x1: number, z0: number, z1: number }
	local layers: { Layer } = {}
	local items = {}
	for _, p in model:GetDescendants() do
		if not p:IsA("Part") then
			continue
		end
		local r = p.CFrame
		-- The part's own axis that stands upright, if any.
		local axis: string? = nil
		if p.Shape == Enum.PartType.Block then
			if math.abs(r.UpVector.Y) > 0.999 then
				axis = "Y"
			elseif math.abs(r.RightVector.Y) > 0.999 then
				axis = "X"
			elseif math.abs(r.LookVector.Y) > 0.999 then
				axis = "Z"
			end
		elseif p.Shape == Enum.PartType.Cylinder and math.abs(r.RightVector.Y) > 0.999 then
			axis = "X"
		end
		if not axis then
			continue
		end
		local h = (p.Size :: any)[axis] :: number
		-- Its footprint on the ground.
		local ex = math.abs(r.RightVector.X) * p.Size.X + math.abs(r.UpVector.X) * p.Size.Y + math.abs(r.LookVector.X) * p.Size.Z
		local ez = math.abs(r.RightVector.Z) * p.Size.X + math.abs(r.UpVector.Z) * p.Size.Y + math.abs(r.LookVector.Z) * p.Size.Z
		local at = r.Position
		table.insert(items, {
			part = p,
			axis = axis,
			h = h,
			-- Thin and wide: a layer that may be raised.
			flat = h <= 1 and math.min(ex, ez) - h >= 1,
			layer = { top = at.Y + h / 2, x0 = at.X - ex / 2, x1 = at.X + ex / 2, z0 = at.Z - ez / 2, z1 = at.Z + ez / 2 },
		})
	end
	table.sort(items, function(a, b)
		return a.layer.top < b.layer.top
	end)
	if floor then
		table.insert(layers, { top = floor, x0 = -math.huge, x1 = math.huge, z0 = -math.huge, z1 = math.huge })
	end
	for _, it in items do
		local l = it.layer
		if it.flat then
			local top = l.top
			local moved = true
			while moved do
				moved = false
				for _, o in layers do
					if math.abs(top - o.top) < LAYER_GAP - 0.001 and o.x0 < l.x1 and l.x0 < o.x1 and o.z0 < l.z1 and l.z0 < o.z1 then
						top = o.top + LAYER_GAP
						moved = true
					end
				end
			end
			local grow = top - l.top
			if grow > 0 then
				local p = it.part
				local cf = p.CFrame
				p.Size += if it.axis == "X" then Vector3.new(grow, 0, 0) elseif it.axis == "Y" then Vector3.new(0, grow, 0) else Vector3.new(0, 0, grow)
				p.CFrame = cf + Vector3.new(0, grow / 2, 0)
				l.top = top
			end
		end
		table.insert(layers, l)
	end
end

function TownView._buildingModel(self: TownView, b: any, turn: number, g: any, cityTheme: string?): Model?
	local def = data.buildingDef(b.def)
	local level = data.buildingLevel(b)
	local model = blockModel(b, g, turn, level)
	if not model then
		return nil
	end
	-- In its colour theme, or the city's (CityTint.tsx); the paved lot keeps its own.
	CityTint.apply(model, cityLook.themeFor(b.tint, cityTheme, def.kind == "decor"))
	local w, h, c
	if g then
		w, h = g.w, g.h
		c = self:tileToWorld(g.x + (w - 1) / 2, g.z + (h - 1) / 2)
	else
		w, h = lotSize(def, b.rot)
		c = self:tileToWorld(b.x + (w - 1) / 2, b.z + (h - 1) / 2)
	end
	model:PivotTo(CFrame.new(c) * model:GetPivot())
	local paved = def.kind ~= "decor" and def.kind ~= "obstacle"
	spreadLayers(model, if paved then c.Y + 0.02 * SCALE else nil)
	if paved then
		-- The paved lot under a business or home (World.tsx BuildingLot), level with the asphalt:
		-- one under the whole of a merged block.
		part({
			Name = "Lot",
			Size = Vector3.new(w * TILE - 0.1 * SCALE, 0.4, h * TILE - 0.1 * SCALE),
			CFrame = CFrame.new(c + Vector3.new(0, 0.02 * SCALE - 0.2, 0)),
			Color = PAVING,
			Material = Enum.Material.Pavement,
			CastShadow = false,
			Parent = model,
		})
	end
	-- One invisible box over the lot: what you bump into and what you click.
	local _, size = model:GetBoundingBox()
	local hit = part({
		Name = "Hit",
		Size = Vector3.new(w * TILE * 0.9, math.max(4, size.Y), h * TILE * 0.9),
		CFrame = CFrame.new(c + Vector3.new(0, math.max(4, size.Y) / 2, 0)),
		Transparency = 1,
		CanCollide = def.kind ~= "decor",
		Parent = model,
	})
	model.PrimaryPart = hit
	-- A tap works a business, and opens a house's or a decoration's upgrades and colours (store
	-- tapBuilding), as on the web; a decoration with neither takes no taps.
	if (def.kind ~= "decor" and def.kind ~= "house") or data.themable(def) then
		local click = Instance.new("ClickDetector")
		click.MaxActivationDistance = 400
		click.MouseClick:Connect(function(player)
			if player.UserId == self.userId then
				self.onTap(b.uid)
			end
		end)
		click.Parent = hit
	end
	model.Name = b.uid
	-- Streams to players whole, so a building never shows up half drawn.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Uid", b.uid)
	model:SetAttribute("Def", b.def)
	model:SetAttribute("Name", if g and merge.isLandmark(g) then merge.landmarkName(g) else def.name)
	model:SetAttribute("Level", level)
	-- Quarter turns about its middle (client/SpeedwayLife puts the race and crowd inside it).
	model:SetAttribute("Turn", turn)
	model:SetAttribute("Owner", self.userId)
	model:SetAttribute("Height", size.Y)
	if g then
		model:SetAttribute("Merged", #g.members)
	end
	return model
end

-- The buildings on the map (stored ones wait in the Inventory) and their merged blocks.
local function placed(buildings: { any }): ({ any }, any)
	local list = {}
	for _, b in buildings do
		if not b.stored then
			table.insert(list, b)
		end
	end
	return list, merge.mergeGroups(list)
end

function TownView._renderBuildings(self: TownView, buildings: { any }, roadSet: any, cityTheme: string?)
	local seen = {}
	local list, merges = placed(buildings)
	for _, b in list do
		-- A merged block draws once, from its top-left building; the rest draw nothing.
		local owner = merges.owner:get(b.uid)
		if owner and owner ~= b.uid then
			continue
		end
		local g = merges.groups:get(b.uid)
		local turn = if g then merge.groupTurn(g, roadSet) else placement.turnOf(b, roadSet)
		local look = `{b.tint or ""}|{if data.buildingDef(b.def).kind == "decor" then "" else cityTheme or ""}`
		local block = if g then `{g.code}|{g.x}|{g.z}|{#g.members}` else ""
		local key = `{b.def}|{b.x}|{b.z}|{b.rot}|{turn}|{data.buildingLevel(b)}|{block}|{look}`
		seen[b.uid] = true
		local have: { model: Model, key: string }? = self.buildings[b.uid]
		if have and have.key ~= key then
			have.model:Destroy()
			have = nil
		end
		if not have then
			local m = self:_buildingModel(b, turn, g, cityTheme)
			if m then
				m.Parent = (self.folder :: any).Buildings
				have = { model = m, key = key }
				self.buildings[b.uid] = have
			end
		end
		if have then
			have.model:SetAttribute("JobEndsAt", b.jobEndsAt)
			have.model:SetAttribute("Car", b.car)
		end
	end
	for uid, have in self.buildings do
		if not seen[uid] then
			have.model:Destroy()
			self.buildings[uid] = nil
		end
	end
end

-- Cars: each driver parks in front of the business it works at; the rest line up by the garage.
-- A merged block's drivers park side by side along its front, a row further out when the front is full.
local CAR_GAP = 13

function TownView._renderCars(self: TownView, cars: { any }, buildings: { any }, roadSet: any)
	local workAt: { [string]: any } = {}
	local garage
	local list, merges = placed(buildings)
	-- Each merged block's drivers, in order, for their places along its front.
	local slot: { [string]: number } = {}
	local drivers: { [string]: number } = {}
	for _, b in list do
		if b.car then
			workAt[b.car] = b
			local owner = merges.owner:get(b.uid)
			if owner then
				drivers[owner] = (drivers[owner] or 0) + 1
				slot[b.car] = drivers[owner]
			end
		end
		if b.def == "garage" then
			garage = b
		end
	end
	local seen = {}
	local queue = 0
	for _, car in cars do
		seen[car.uid] = true
		local at = workAt[car.uid]
		local cf: CFrame
		local g = at and merges.groups:get(merges.owner:get(at.uid) or "")
		if g then
			local turn = merge.groupTurn(g, roadSet)
			local c = self:tileToWorld(g.x + (g.w - 1) / 2, g.z + (g.h - 1) / 2)
			local facing = CFrame.Angles(0, turn * math.pi / 2, 0)
			local across = (if turn % 2 == 1 then g.h else g.w) * TILE
			local depth = (if turn % 2 == 1 then g.w else g.h) * TILE / 2
			local per = math.max(1, math.floor(across / CAR_GAP))
			local n = math.min(per, drivers[g.anchor.uid])
			local i = slot[car.uid] - 1
			local row, k = i // per, i % per
			cf = CFrame.new(c) * facing * CFrame.new((k - (n - 1) / 2) * CAR_GAP, 0, depth + TILE * 0.3 + row * 7) * CFrame.Angles(0, math.pi / 2, 0)
		elseif at then
			local def = data.buildingDef(at.def)
			local turn = placement.turnOf(at, roadSet)
			local w, h = lotSize(def, at.rot)
			local c = self:tileToWorld(at.x + (w - 1) / 2, at.z + (h - 1) / 2)
			-- The front of a building faces +Z before it turns; park just past it, sideways.
			local facing = CFrame.Angles(0, turn * math.pi / 2, 0)
			local depth = (if turn % 2 == 1 then w else h) * TILE / 2
			cf = CFrame.new(c) * facing * CFrame.new(0, 0, depth + TILE * 0.3) * CFrame.Angles(0, math.pi / 2, 0)
		elseif garage then
			local c = self:tileToWorld(garage.x + 0.5, garage.z + 0.5)
			local row, colN = queue // 6, queue % 6
			cf = CFrame.new(c + Vector3.new((colN - 2.5) * 7, 0, TILE * 1.4 + row * 14))
			queue += 1
		else
			cf = CFrame.new(self.origin + Vector3.new(queue * 8, 0, 0))
			queue += 1
		end
		local job = Paint.jobOf(car)
		local key = `{car.model}|{Paint.key(job)}|{Paint.hatName(car.hat) or ""}|{Mods.key(car.mods)}|{Panels.key(car.panels)}|{Trim.key(car.trim)}|{Skins.key(car.skin, car.modSkin)}`
		-- A car's mod and custom paint meshes load the first time it needs them; it's drawn again
		-- once they're in.
		if ((car.mods and #car.mods > 0) or Panels.key(car.panels) ~= "") and not Builder.modsReady(car.model) then
			key ..= "|waiting"
			if not self.waiting[car.model] then
				self.waiting[car.model] = true
				task.spawn(function()
					Builder.loadFor(car.model)
					self.waiting[car.model] = nil
					if self.last and self.folder.Parent then
						self:render(self.last)
					end
				end)
			end
		end
		local have: { model: Model, key: string }? = self.cars[car.uid]
		if have and have.key ~= key then
			have.model:Destroy()
			have = nil
		end
		if not have then
			local m = Builder.build(car.model)
			if m then
				Paint.apply(m, job, if type(job.stripe) == "string" then Builder.build(`stripe:{car.model}`) else nil)
				Panels.apply(m, car.model, car.panels, job.finish, Builder.build)
				Trim.apply(m, car.model, car.trim, job.color)
				Paint.wearHat(m, car.model, car.hat, Builder.build)
				Mods.fit(m, car.model, car.mods, Builder.build)
				Skins.apply(m, car.skin, car.modSkin)
				m.Name = car.uid
				m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
				m:SetAttribute("Uid", car.uid)
				m:SetAttribute("Model", car.model)
				m.Parent = (self.folder :: any).Cars
				have = { model = m, key = key }
				self.cars[car.uid] = have
			end
		end
		if have then
			have.model:PivotTo(cf)
		end
	end
	for uid, have in self.cars do
		if not seen[uid] then
			have.model:Destroy()
			self.cars[uid] = nil
		end
	end
end

-- Draws the town as a save describes it.
function TownView.render(self: TownView, save: any)
	self.last = save
	self.folder:SetAttribute("TownName", save.townName)
	self:_renderLand(save.land or {})
	local list = save.roads or {}
	self:_renderRoads(list)
	local roadSet = lualib.__TS__New(lualib.Set, list)
	self:_renderBuildings(save.buildings or {}, roadSet, save.cityTheme)
	self:_renderLawn(save.land or {}, list, save.buildings or {})
	self:_renderCars(save.cars or {}, save.buildings or {}, roadSet)
end

return TownView
