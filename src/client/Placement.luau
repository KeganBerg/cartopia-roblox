--!strict
-- Building on the town grid: placing a building from the Shop (a see-through copy follows the
-- pointer, green where it fits, red where it doesn't), painting roads and bulldozing.
-- Fit checks use the web game's own canPlace on the client's copy of the town; the server checks
-- again when it runs the action.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local placementRules = require(Game.placement) :: any
local lualib = require(Game.lualib_bundle) :: any
local Remote = require(script.Parent.Remote)
local Town = require(script.Parent.Town)
local Ui = require(script.Parent.Ui)

local Placement = {}

type Mode = "place" | "road" | "bulldoze"
local mode: Mode? = nil
local placing: string? = nil
local rot = 0
-- Until the player turns it, a new building faces the nearest road, as on the web.
local rotated = false
local ghost: Model? = nil
local plate: Part? = nil
local bar: Frame? = nil
local hoverTile: { x: number, z: number }? = nil
local conns: { RBXScriptConnection } = {}
local onChange: (() -> ())? = nil

local function state(): any
	return store.useGame.getState()
end

local function clear()
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	if plate then
		plate:Destroy()
		plate = nil
	end
	if bar then
		bar:Destroy()
		bar = nil
	end
	mode, placing, hoverTile = nil, nil, nil
	if onChange then
		onChange()
	end
end

function Placement.active(): boolean
	return mode ~= nil
end

function Placement.cancel()
	clear()
end

local function makeGhost(def: string): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local src = lib and lib.Buildings:FindFirstChild(def)
	if not src then
		return nil
	end
	local m = src:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = math.max(d.Transparency, 0.35)
			d.CanQuery = false
			d.CanCollide = false
			d.CastShadow = false
		elseif d:IsA("SurfaceGui") then
			d.Enabled = false
		end
	end
	m.Parent = workspace
	return m
end

-- Top-left tile of the lot for a pointer over tile (tx, tz), and the lot's width and depth.
local function chosen(): number?
	return if rotated then rot else nil
end

local function lotAt(def: string, tx: number, tz: number): (number, number, number, number)
	local w, h = store.lotSize(def, chosen())
	return tx - (w - 1) // 2, tz - (h - 1) // 2, w, h
end

local function update(screen: Vector2)
	local p = Town.groundAt(screen)
	if not p then
		return
	end
	local tx, tz = Town.worldToTile(p)
	if not tx or not tz then
		return
	end
	hoverTile = { x = tx, z = tz }
	local tile = Town.tileSize()
	if mode == "place" and placing then
		local x, z, w, h = lotAt(placing, tx, tz)
		local ok = store.canPlace(state(), placing, x, z, chosen())
		local c = Town.tileToWorld(x + (w - 1) / 2, z + (h - 1) / 2) :: Vector3
		if ghost then
			local roads = lualib.__TS__New(lualib.Set, state().roads)
			local turn = placementRules.turnOf({ def = placing, x = x, z = z, rot = chosen() }, roads)
			ghost:PivotTo(CFrame.new(c) * CFrame.Angles(0, turn * math.pi / 2, 0))
		end
		if plate then
			plate.Size = Vector3.new(w * tile, 0.2, h * tile)
			plate.CFrame = CFrame.new(c + Vector3.new(0, 0.35, 0))
			plate.Color = if ok then Color3.fromHex("#66bb6a") else Color3.fromHex("#ef5350")
		end
	elseif plate then
		local c = Town.tileToWorld(tx, tz) :: Vector3
		plate.Size = Vector3.new(tile, 0.2, tile)
		plate.CFrame = CFrame.new(c + Vector3.new(0, 0.45, 0))
	end
end

local function act()
	if not hoverTile then
		return
	end
	local t = hoverTile
	if mode == "place" and placing then
		local x, z = lotAt(placing, t.x, t.z)
		local def = placing
		local r = chosen()
		if store.canPlace(state(), def, x, z, r) then
			clear()
			Remote.act("placeBuilding", def, x, z, r)
		end
	elseif mode == "road" then
		Remote.act("paintRoad", t.x, t.z)
	elseif mode == "bulldoze" then
		Remote.act("bulldoze", t.x, t.z)
	end
end

local function start(m: Mode, gui: ScreenGui, buttons: { { string } })
	clear()
	mode = m
	plate = Ui.new("Part", {
		Name = "Placement",
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		Transparency = 0.45,
		Material = Enum.Material.Neon,
		Color = if m == "road" then Color3.fromHex("#90caf9") elseif m == "bulldoze" then Color3.fromHex("#ef5350") else Color3.fromHex("#66bb6a"),
		Parent = workspace,
	})
	bar = Ui.new("Frame", {
		Name = "BuildBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(#buttons * 140, 56),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center }) })
	for i, b in buttons do
		Ui.button({ Size = UDim2.fromOffset(130, 52), LayoutOrder = i, Parent = bar }, b[2], b[1], function()
			if b[3] == "rotate" then
				rot = (rot + 1) % 4
				rotated = true
				update(UserInputService:GetMouseLocation())
			elseif b[3] == "road" then
				Placement.road(gui)
			elseif b[3] == "bulldoze" then
				Placement.bulldoze(gui)
			else
				clear()
			end
		end)
	end
	-- Mouse: the ghost follows the pointer. Touch: it follows the finger, and lifting it builds.
	table.insert(conns, RunService.RenderStepped:Connect(function()
		if UserInputService.MouseEnabled then
			update(UserInputService:GetMouseLocation() - Vector2.new(0, 0))
		end
	end))
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			update(Vector2.new(input.Position.X, input.Position.Y))
			act()
		elseif input.KeyCode == Enum.KeyCode.R and mode == "place" then
			rot = (rot + 1) % 4
			rotated = true
		elseif input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Q then
			clear()
		end
	end))
	if onChange then
		onChange()
	end
end

-- Place a building from the Shop.
function Placement.place(def: string, gui: ScreenGui)
	start("place", gui, { { "⟳ Rotate", "white", "rotate" }, { "✕ Cancel", "grey", "cancel" } })
	placing = def
	rot = 0
	rotated = false
	ghost = makeGhost(def)
end

function Placement.road(gui: ScreenGui)
	start("road", gui, { { "🛣 Road", "garage", "road" }, { "🚧 Bulldoze", "showroom", "bulldoze" }, { "✓ Done", "green", "cancel" } })
end

function Placement.bulldoze(gui: ScreenGui)
	start("bulldoze", gui, { { "🛣 Road", "garage", "road" }, { "🚧 Bulldoze", "showroom", "bulldoze" }, { "✓ Done", "green", "cancel" } })
end

function Placement.onChange(fn: () -> ())
	onChange = fn
end

-- Keep the ghost's colour right when the town changes under it.
Remote.changed:Connect(function()
	if mode then
		update(UserInputService:GetMouseLocation())
	end
end)

local _ = data
return Placement
