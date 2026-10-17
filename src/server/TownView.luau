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
local Builder = require(Shared.Models.Builder)
local Catalog = require(Shared.Models.Catalog)

local SCALE = Catalog.SCALE
local TILE = data.TILE * SCALE -- studs per tile
local GRID = data.GRID
local PLOT = data.PLOT

local ROAD = Color3.fromHex("#8a9097")
local LINE = Color3.fromHex("#f5f5f5")
local KERB = Color3.fromHex("#cfd8dc")
local GRASS = Color3.fromHex("#7cb342")
local MEADOW = Color3.fromHex("#8bc34a")

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
		buildings: { [string]: { model: Model, key: string } },
		cars: { [string]: { model: Model, key: string } },
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
	for _, sub in { "Land", "Roads", "Buildings", "Cars" } do
		local f = Instance.new("Folder")
		f.Name = sub
		f.Parent = folder
	end
	-- Meadow under the whole lot, so land not yet bought still looks like countryside.
	local meadow = Instance.new("Part")
	meadow.Name = "Meadow"
	meadow.Anchored = true
	meadow.Size = Vector3.new(1400, 4, 1400)
	meadow.CFrame = CFrame.new(origin + Vector3.new(0, -2.05, 0))
	meadow.Color = MEADOW
	meadow.Material = Enum.Material.Grass
	meadow.TopSurface = Enum.SurfaceType.Smooth
	meadow.Parent = folder
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

-- Land plots: bright grass on every plot the town owns.
function TownView._renderLand(self: TownView, land: { string })
	local seen = {}
	for _, k in land do
		seen[k] = true
		if not self.land[k] then
			local px, pz = splitKey(k)
			local c = self:tileToWorld(px * PLOT + (PLOT - 1) / 2, pz * PLOT + (PLOT - 1) / 2)
			local p = part({
				Name = k,
				Size = Vector3.new(PLOT * TILE, 1, PLOT * TILE),
				CFrame = CFrame.new(c + Vector3.new(0, -0.5, 0)),
				Color = GRASS,
				Material = Enum.Material.Grass,
				Parent = (self.folder :: any).Land,
			})
			self.land[k] = p
		end
	end
	for k, p in self.land do
		if not seen[k] then
			p:Destroy()
			self.land[k] = nil
		end
	end
end

-- A road tile: asphalt, kerbs on the sides with no road next door, and a dashed centre line
-- toward each neighbour.
function TownView._roadModel(self: TownView, x: number, z: number, has: (number, number) -> boolean): Model
	local m = Instance.new("Model")
	m.Name = `{x},{z}`
	local c = self:tileToWorld(x, z)
	part({ Name = "Asphalt", Size = Vector3.new(TILE, 0.3, TILE), CFrame = CFrame.new(c + Vector3.new(0, 0.1, 0)), Color = ROAD, Material = Enum.Material.Asphalt, Parent = m })
	local kerb = 1.2
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local dx, dz = d[1], d[2]
		local edge = c + Vector3.new(dx, 0, dz) * (TILE / 2)
		if has(x + dx, z + dz) then
			-- Dashes from the middle toward this neighbour.
			for i = 1, 2 do
				local at = c + Vector3.new(dx, 0, dz) * (TILE * (i - 0.5) / 4.5)
				part({
					Name = "Line",
					Size = if dx ~= 0 then Vector3.new(TILE / 7, 0.05, 0.5) else Vector3.new(0.5, 0.05, TILE / 7),
					CFrame = CFrame.new(at + Vector3.new(0, 0.28, 0)),
					Color = LINE,
					Material = Enum.Material.SmoothPlastic,
					CanCollide = false,
					Parent = m,
				})
			end
		else
			part({
				Name = "Kerb",
				Size = if dx ~= 0 then Vector3.new(kerb, 0.7, TILE) else Vector3.new(TILE, 0.7, kerb),
				CFrame = CFrame.new(edge - Vector3.new(dx, 0, dz) * (kerb / 2) + Vector3.new(0, 0.35, 0)),
				Color = KERB,
				Material = Enum.Material.Concrete,
				Parent = m,
			})
		end
	end
	return m
end

function TownView._renderRoads(self: TownView, roads: { string })
	local set: { [string]: boolean } = {}
	for _, k in roads do
		set[k] = true
	end
	local function has(x: number, z: number): boolean
		return set[`{x},{z}`] == true
	end
	-- A tile's look depends on its neighbours, so key it by them too.
	local seen = {}
	for _, k in roads do
		local x, z = splitKey(k)
		local key = `{k}|{has(x + 1, z)}{has(x - 1, z)}{has(x, z + 1)}{has(x, z - 1)}`
		seen[key] = true
		if not self.roads[key] then
			local m = self:_roadModel(x, z, has)
			m.Parent = (self.folder :: any).Roads
			self.roads[key] = m
		end
	end
	for k, m in self.roads do
		if not seen[k] then
			m:Destroy()
			self.roads[k] = nil
		end
	end
	return set
end

-- A building's centre, as World.tsx's centerOf: the middle of its lot.
local function lotSize(def: any, rot: number?): (number, number)
	if (rot or 0) % 2 == 1 then
		return def.h, def.w
	end
	return def.w, def.h
end

function TownView._buildingModel(self: TownView, b: any, turn: number): Model?
	local def = data.buildingDef(b.def)
	local level = data.buildingLevel(b)
	local name = Builder.buildingName(b.def, level) or Builder.buildingName("parked", 1)
	local model = if name then Builder.build(name) else nil
	if not model then
		return nil
	end
	local w, h = lotSize(def, b.rot)
	local c = self:tileToWorld(b.x + (w - 1) / 2, b.z + (h - 1) / 2)
	model:PivotTo(CFrame.new(c) * CFrame.Angles(0, turn * math.pi / 2, 0))
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
	if def.kind ~= "decor" and def.kind ~= "house" then
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
	model:SetAttribute("Uid", b.uid)
	model:SetAttribute("Def", b.def)
	model:SetAttribute("Name", def.name)
	model:SetAttribute("Level", level)
	model:SetAttribute("Owner", self.userId)
	model:SetAttribute("Height", size.Y)
	return model
end

function TownView._renderBuildings(self: TownView, buildings: { any }, roadSet: any)
	local seen = {}
	for _, b in buildings do
		if b.stored then
			continue
		end
		local turn = placement.turnOf(b, roadSet)
		local key = `{b.def}|{b.x}|{b.z}|{b.rot}|{turn}|{data.buildingLevel(b)}`
		seen[b.uid] = true
		local have: { model: Model, key: string }? = self.buildings[b.uid]
		if have and have.key ~= key then
			have.model:Destroy()
			have = nil
		end
		if not have then
			local m = self:_buildingModel(b, turn)
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
function TownView._renderCars(self: TownView, cars: { any }, buildings: { any }, roadSet: any)
	local workAt: { [string]: any } = {}
	local garage
	for _, b in buildings do
		if b.car then
			workAt[b.car] = b
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
		if at then
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
		local key = `{car.model}|{car.color}`
		local have: { model: Model, key: string }? = self.cars[car.uid]
		if have and have.key ~= key then
			have.model:Destroy()
			have = nil
		end
		if not have then
			local m = Builder.build(car.model, Color3.fromHex(car.color))
			if m then
				m.Name = car.uid
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
	self.folder:SetAttribute("TownName", save.townName)
	self:_renderLand(save.land or {})
	local list = save.roads or {}
	self:_renderRoads(list)
	local roadSet = lualib.__TS__New(lualib.Set, list)
	self:_renderBuildings(save.buildings or {}, roadSet)
	self:_renderCars(save.cars or {}, save.buildings or {}, roadSet)
end

return TownView
