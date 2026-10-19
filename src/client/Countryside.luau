--!strict
-- The countryside round the player's town, as the web game's Outskirts.tsx draws it: wild meadow
-- on the plots they haven't bought, a split-rail fence along the town line with lantern posts and
-- a gravel lane wherever a road leaves town, and past the last plot a forest ring with a farm and
-- a lake, out to open country dotted with trees.
--
-- The forest and each plot's meadow are the web game's own scenery, converted by
-- tools/models/build.mjs (Shared.Models.Scenery). It's drawn here on the client, for this
-- player's town only: it never changes the game, and nobody else needs a copy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Builder = require(Shared:WaitForChild("Models"):WaitForChild("Builder")) :: any
local Catalog = require(Shared.Models:WaitForChild("Catalog")) :: any
local data = require(Shared:WaitForChild("Game"):WaitForChild("data")) :: any

local Countryside = {}

local S = Catalog.SCALE -- studs per web unit
local PLOT, PLOT_MIN, PLOT_MAX, TILE, GRID = data.PLOT, data.PLOT_MIN, data.PLOT_MAX, data.TILE, data.GRID
local HALF_TILE = TILE / 2
local PLOT_W = PLOT * TILE
local WOOD = Color3.fromHex(if Catalog.SEASON == "winter" then "#6d5a50" else "#8d6e63")

-- World edge (web units) of plot index p, west or north side, with the grid centred on the origin.
local function edge(p: number): number
	return (p * PLOT - (GRID - 1) / 2) * TILE - HALF_TILE
end

local function block(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = size.Y > 1.5
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- Only roads on a plot's edge tiles can leave town (scene/townExits.ts).
local function exitsOf(roads: { string }): { [string]: boolean }
	local out = {}
	for _, k in roads do
		local x, z = string.match(k, "^(-?%d+),(-?%d+)$")
		if x and z then
			local ix, iz = (tonumber(x) :: number) % PLOT, (tonumber(z) :: number) % PLOT
			if ix == 0 or ix == PLOT - 1 or iz == 0 or iz == PLOT - 1 then
				out[k] = true
			end
		end
	end
	return out
end

-- The split-rail fence round the owned plots (Outskirts.tsx TownLine), in web units from the
-- town's middle, drawn into `into` at origin.
local function townLine(into: Instance, origin: Vector3, land: { string }, roads: { string })
	local owned: { [string]: boolean } = {}
	for _, k in land do
		owned[k] = true
	end
	local road = exitsOf(roads)
	local function at(x: number, y: number, z: number): Vector3
		return origin + Vector3.new(x, y, z) * S
	end
	local post = Vector3.new(0.09, 0.62, 0.09) * S
	local function fenceRun(x0: number, z0: number, alongX: boolean, len: number)
		local t = 0
		while t <= len + 1e-6 do
			local x, z = if alongX then x0 + t else x0, if alongX then z0 else z0 + t
			block(into, post, CFrame.new(at(x, 0.31, z)), WOOD)
			if t + 1.6 <= len + 1e-6 then
				for _, y in { 0.22, 0.46 } do
					local mid = at(if alongX then x + 0.8 else x, y, if alongX then z else z + 0.8)
					local size = if alongX then Vector3.new(1.62, 0.05, 0.04) * S else Vector3.new(0.04, 0.05, 1.62) * S
					block(into, size, CFrame.new(mid), WOOD)
				end
			end
			t += 1.6
		end
	end
	local gates: { { x: number, z: number, along: boolean, out: number } } = {}
	for _, key in land do
		local sx, sz = string.match(key, "^(-?%d+),(-?%d+)$")
		if not sx then
			continue
		end
		local px, pz = tonumber(sx) :: number, tonumber(sz) :: number
		local x0, z0 = edge(px), edge(pz)
		-- Each side: its neighbour plot (dx, dz), whether the fence runs along x, the coordinate it
		-- sits at, and the tile on that edge at step i.
		type Side = { dx: number, dz: number, alongX: boolean, fixed: number, tileAt: (number) -> string }
		local sides: { Side } = {
			{ dx = 0, dz = -1, alongX = true, fixed = z0, tileAt = function(i: number) return `{px * PLOT + i},{pz * PLOT}` end },
			{ dx = 0, dz = 1, alongX = true, fixed = z0 + PLOT_W, tileAt = function(i: number) return `{px * PLOT + i},{pz * PLOT + PLOT - 1}` end },
			{ dx = -1, dz = 0, alongX = false, fixed = x0, tileAt = function(i: number) return `{px * PLOT},{pz * PLOT + i}` end },
			{ dx = 1, dz = 0, alongX = false, fixed = x0 + PLOT_W, tileAt = function(i: number) return `{px * PLOT + PLOT - 1},{pz * PLOT + i}` end },
		}
		for _, side in sides do
			local dx, dz, alongX, fixed, tileAt = side.dx, side.dz, side.alongX, side.fixed, side.tileAt
			if owned[`{px + dx},{pz + dz}`] then
				continue
			end
			-- Walk the edge tile by tile; fence the stretches between road exits.
			local runStart = 0
			for i = 0, PLOT do
				local exit = i < PLOT and road[tileAt(i)] == true
				if i == PLOT or exit then
					local len = (i - runStart) * TILE - (if exit then 0.3 else 0) - (if runStart > 0 then 0.3 else 0)
					local from = (if alongX then x0 else z0) + runStart * TILE + (if runStart > 0 then 0.3 else 0)
					if len > 0.5 then
						fenceRun(if alongX then from else fixed, if alongX then fixed else from, alongX, len)
					end
					if exit then
						local c = (if alongX then x0 else z0) + i * TILE + HALF_TILE
						table.insert(gates, { x = if alongX then c else fixed, z = if alongX then fixed else c, along = alongX, out = if alongX then dz else dx })
					end
					runStart = i + 1
				end
			end
		end
	end
	-- Each road out of town gets a gravel lane running off into the country and two lantern posts.
	for _, g in gates do
		local ux, uz = if g.along then 0 else g.out, if g.along then g.out else 0
		local laneSize = if g.along then Vector3.new(1.6, 0.02, 14) else Vector3.new(14, 0.02, 1.6)
		block(into, laneSize * S, CFrame.new(at(g.x + ux * 7, 0.005, g.z + uz * 7)), Color3.fromHex("#b49a7c"), Enum.Material.Pebble)
		for _, sd in { -1, 1 } do
			local px = if g.along then sd * (HALF_TILE + 0.15) else 0
			local pz = if g.along then 0 else sd * (HALF_TILE + 0.15)
			local x, z = g.x + px, g.z + pz
			local pole = block(into, Vector3.new(1.1, 0.11, 0.11) * S, CFrame.new(at(x, 0.55, z)) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromHex("#5d4037"))
			pole.Shape = Enum.PartType.Cylinder
			local bulb = block(into, Vector3.new(0.16, 0.18, 0.16) * S, CFrame.new(at(x, 1.16, z)), Color3.fromHex("#ffe082"), Enum.Material.Neon)
			local light = Instance.new("PointLight")
			light.Color = Color3.fromHex("#ffcc80")
			light.Range = 12
			light.Brightness = 1.2
			light.Shadows = false
			light.Parent = bulb
			block(into, Vector3.new(0.2, 0.06, 0.2) * S, CFrame.new(at(x, 1.28, z)) * CFrame.Angles(0, math.pi / 4, 0), Color3.fromHex("#263238"))
		end
	end
end

-- Draws the countryside round a town whose middle is at origin, into parent. Returns a function
-- that brings the wild plots and the fence up to date with a save.
function Countryside.draw(origin: Vector3, parent: Instance): (save: any) -> ()
	local root = Instance.new("Folder")
	root.Name = "Countryside"
	root.Parent = parent

	-- The forest ring reaches 2,000 studs out: in the shared world (server/World) it would cover
	-- the neighbours' towns, so there the land between towns is the world's own.
	local forest = if workspace:FindFirstChild("World") then nil else Builder.build("outskirts:forest")
	if forest then
		forest:PivotTo(CFrame.new(origin))
		forest.Parent = root
	end

	local wilds = Instance.new("Folder")
	wilds.Name = "Wilds"
	wilds.Parent = root
	local fence = Instance.new("Folder")
	fence.Name = "TownLine"
	fence.Parent = root
	local plots: { [string]: Model } = {}
	local lastFence = ""

	return function(save: any)
		if not save then
			return
		end
		local land: { string } = save.land or {}
		local owned: { [string]: boolean } = {}
		for _, k in land do
			owned[k] = true
		end
		-- Wild meadow on every plot not bought; buying one clears it.
		for px = PLOT_MIN, PLOT_MAX do
			for pz = PLOT_MIN, PLOT_MAX do
				local k = `{px},{pz}`
				if owned[k] and plots[k] then
					plots[k]:Destroy()
					plots[k] = nil
				elseif not owned[k] and not plots[k] then
					local m = Builder.build(`wilds:{k}`)
					if m then
						-- Its long grass and stones reach down into the ground; like the lawn's
						-- tufts they cast no shadow: thousands of thin blades in the shadow map
						-- drew dark, blocky smears over the meadow that crawled as the camera moved.
						for _, d in m:GetDescendants() do
							if d:IsA("BasePart") and d.CFrame.Y - d.Size.Y / 2 < -0.5 then
								d.CastShadow = false
							end
						end
						m:PivotTo(CFrame.new(origin))
						m.Parent = wilds
						plots[k] = m
					end
					-- A frame between plots, so the loading screen keeps moving smoothly while
					-- the countryside is drawn behind it.
					task.wait()
				end
			end
		end
		-- The fence only moves when the land or a road out of town changes.
		local roads: { string } = save.roads or {}
		local exits = {}
		for k in exitsOf(roads) do
			table.insert(exits, k)
		end
		table.sort(exits)
		local sorted = table.clone(land)
		table.sort(sorted)
		local key = table.concat(sorted, ";") .. "|" .. table.concat(exits, ";")
		if key ~= lastFence then
			lastFence = key
			fence:ClearAllChildren()
			townLine(fence, origin, land, roads)
		end
	end
end

function Countryside.start()
	local Town = require(script.Parent.Town)
	local Remote = require(script.Parent.Remote) :: any
	task.spawn(function()
		local folder: Folder? = nil
		while not folder do
			folder = Town.folder()
			if not folder then
				task.wait(0.5)
			end
		end
		Builder.useLibrary(60)
		local refresh = Countryside.draw((folder :: Folder):GetAttribute("Origin") :: any, workspace)
		-- Marked drawn after its first town, for the loading screen (ReplicatedFirst/Loading).
		local function update(save: any)
			refresh(save)
			local root = workspace:FindFirstChild("Countryside")
			if save and root then
				root:SetAttribute("Drawn", true)
			end
		end
		Remote.changed:Connect(function(snap)
			update(snap.save)
		end)
		if Remote.last then
			update(Remote.last.save)
		end
	end)
end

return Countryside
