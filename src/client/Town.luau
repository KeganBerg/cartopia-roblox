--!strict
-- Finds the player's own town in the world (Workspace.Towns, drawn by the server's TownView) and
-- converts between world positions and the web game's tile grid.

local Players = game:GetService("Players")

local Town = {}

function Town.folder(): Folder?
	local towns = workspace:FindFirstChild("Towns")
	if not towns then
		return nil
	end
	for _, f in towns:GetChildren() do
		if f:GetAttribute("Owner") == Players.LocalPlayer.UserId then
			return f :: Folder
		end
	end
	return nil
end

-- The town on screen: the one the player is visiting (their "Visiting" attribute, set by the
-- server), else their own.
function Town.shown(): Folder?
	local host = Players.LocalPlayer:GetAttribute("Visiting")
	local towns = workspace:FindFirstChild("Towns")
	if type(host) == "number" and towns then
		for _, f in towns:GetChildren() do
			if f:GetAttribute("Owner") == host then
				return f :: Folder
			end
		end
	end
	return Town.folder()
end

-- Tile (x, z) to a world position on the ground at its centre (x, z may be fractional).
function Town.tileToWorld(x: number, z: number): Vector3?
	local f = Town.folder()
	if not f then
		return nil
	end
	local origin: Vector3 = f:GetAttribute("Origin") :: any
	local tile: number = f:GetAttribute("TileSize") :: any
	local grid: number = f:GetAttribute("Grid") :: any
	return origin + Vector3.new((x - (grid - 1) / 2) * tile, 0, (z - (grid - 1) / 2) * tile)
end

-- The tile under a world position.
function Town.worldToTile(p: Vector3): (number?, number?)
	local f = Town.folder()
	if not f then
		return nil, nil
	end
	local origin: Vector3 = f:GetAttribute("Origin") :: any
	local tile: number = f:GetAttribute("TileSize") :: any
	local grid: number = f:GetAttribute("Grid") :: any
	local d = p - origin
	return math.round(d.X / tile + (grid - 1) / 2), math.round(d.Z / tile + (grid - 1) / 2)
end

function Town.tileSize(): number
	local f = Town.folder()
	return if f then f:GetAttribute("TileSize") :: any else 20
end

-- Where a screen point (mouse or finger, as InputObject.Position gives it: below Roblox's top
-- bar) meets the ground.
function Town.groundAt(screen: Vector2): Vector3?
	local cam = workspace.CurrentCamera
	local ray = cam:ScreenPointToRay(screen.X, screen.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return nil
	end
	local t = -ray.Origin.Y / ray.Direction.Y
	if t < 0 then
		return nil
	end
	return ray.Origin + ray.Direction * t
end

return Town
