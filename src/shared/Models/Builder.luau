--!strict
-- Builds Roblox models from Catalog: the web game's own buildings and cars, converted part for
-- part by tools/models/build.mjs.
--
-- Blocks, cylinders and balls are plain parts. Meshes are copies of MeshParts the server loads
-- from the uploaded mesh packs (Builder.loadMeshes); a mesh whose pack isn't uploaded or didn't
-- load shows as a box of its size and colour instead.
--
-- Every model is built once as a template and cloned after that.

local Catalog = require(script.Parent.Catalog)
local Meshes = require(script.Parent.Meshes)
local Scenery = require(script.Parent.Scenery)
local RaceScenery = require(script.Parent.RaceScenery)
local Insert = require(script.Parent.Insert)

local Builder = {}

-- Written by the model build (tools/models/build.mjs); empty in a build from before mods.
local MOD_DROPS: { [string]: any } = (Catalog :: any).MOD_DROPS or {}
local WHEELS: { [string]: any } = (Catalog :: any).WHEELS or {}
local PANEL_DROPS: { [string]: any } = (Catalog :: any).PANEL_DROPS or {}
local TRIM: { [string]: any } = (Catalog :: any).TRIM or {}

local templates: { [string]: Model } = {}
local meshParts: { [string]: MeshPart } = {}
-- Templates built while some of their meshes hadn't arrived (stand-in boxes in them): dropped as
-- soon as a mesh arrives, so the next build of that model uses the real shapes.
local boxed: { [string]: boolean } = {}

local function meshArrived()
	for name in boxed do
		templates[name] = nil
	end
	table.clear(boxed)
end

-- How far each mesh pack has got: loading, or done (loaded). A pack that failed is left out, so
-- it can be tried again.
local packState: { [number]: "loading" | "done" } = {}

-- Whether a loaded mesh came in the shape it was made: its own size (MeshSize) in the same
-- proportions as the converter recorded (Meshes.MESHES). A mesh Roblox imported turned on its side
-- or squashed would be stretched by its part's size into long beams across the sky, so one that
-- doesn't fit is treated as not loaded and left out. Only the countryside's meshes are checked,
-- where a missing piece is simply not drawn (a town would show a box).
local sceneryMeshes: { [string]: boolean }? = nil
local function fits(d: MeshPart): boolean
	if not sceneryMeshes then
		local set = {}
		for _, list in { Scenery.MODELS, RaceScenery.MODELS } do
			for _, parts in list do
				for _, p in parts do
					if p[1] == "m" then
						set[p[13]] = true
					end
				end
			end
		end
		sceneryMeshes = set
	end
	if not (sceneryMeshes :: any)[d.Name] then
		return true
	end
	local want = Meshes.MESHES[d.Name]
	local ok, got = pcall(function()
		return d.MeshSize
	end)
	if not want or not ok or typeof(got) ~= "Vector3" or got.Magnitude < 1e-6 then
		return true
	end
	local lo, hi = math.huge, 0
	for _, axis in { "X", "Y", "Z" } do
		local w, g = (want.size :: any)[axis], (got :: any)[axis]
		-- (Very thin sides are left out: the converter rounds them up.)
		if w > 0.2 then
			local r = math.max(g, 1e-6) / w
			lo = math.min(lo, r)
			hi = math.max(hi, r)
		end
	end
	return hi == 0 or hi / lo < 1.5
end

-- Loads mesh packs (server only) and shares a copy of each mesh with the clients through
-- ReplicatedStorage.MeshLibrary once that exists. Calls back after each pack.
local function loadPacks(assets: { number }, each: (() -> ())?, priority: Insert.Priority?)
	for _, asset in assets do
		packState[asset] = "loading"
		task.spawn(function()
			local model, err = Insert.load(asset, priority)
			packState[asset] = if model then "done" else nil
			if model then
				local library = game:GetService("ReplicatedStorage"):FindFirstChild("MeshLibrary")
				for _, d in model:GetDescendants() do
					if d:IsA("MeshPart") and not meshParts[d.Name] and fits(d) then
						meshParts[d.Name] = d
						meshArrived()
						if library then
							local copy = d:Clone()
							copy.Parent = library
						end
					end
				end
			else
				warn(`[Cartopia] mesh pack {asset} didn't load: {err}`)
			end
			if each then
				each()
			end
		end)
	end
end

-- Loads every uploaded mesh pack (server only: InsertService). Waits for all of them, up to
-- timeout seconds, calling progress(done, total) as each one finishes. Safe to call more than once.
function Builder.loadMeshes(timeout: number?, progress: ((done: number, total: number) -> ())?)
	local byAsset: { [number]: boolean } = {}
	for _, m in Meshes.MESHES do
		-- A car's mod pack waits until that car needs it (Builder.loadFor), the far land until the
		-- rest is in (Builder.loadLate).
		if m.asset ~= 0 and not (m :: any).lazy and not (m :: any).late then
			byAsset[m.asset] = true
		end
	end
	local list = {}
	for asset in byAsset do
		table.insert(list, asset)
	end
	local total = #list
	local left = total
	if progress then
		progress(0, total)
	end
	loadPacks(list, function()
		left -= 1
		if progress then
			progress(total - left, total)
		end
	end)
	local start = os.clock()
	while left > 0 and os.clock() - start < (timeout or 60) do
		task.wait(0.1)
	end
	-- Templates built before the meshes arrived used boxes; build them again.
	table.clear(templates)
	-- A copy of every mesh for the clients (they can't load assets themselves), which draw the
	-- countryside locally (Builder.useLibrary).
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	if not ReplicatedStorage:FindFirstChild("MeshLibrary") then
		local library = Instance.new("Folder")
		library.Name = "MeshLibrary"
		for key, part in meshParts do
			local copy = part:Clone()
			copy.Name = key
			copy.Parent = library
		end
		library.Parent = ReplicatedStorage
	end
end

-- On a client: takes the meshes the server shares (see loadMeshes), waiting up to timeout seconds
-- for them. Returns whether they arrived.
-- Loads the far land's mesh packs (server only), after Builder.loadMeshes: the clients draw it
-- (client/Horizon) once every one of its meshes is in the library.
function Builder.loadLate()
	local seen: { [number]: boolean } = {}
	local list = {}
	for _, m in Meshes.MESHES do
		if m.asset ~= 0 and (m :: any).late and not seen[m.asset] then
			seen[m.asset] = true
			table.insert(list, m.asset)
		end
	end
	loadPacks(list, nil, "last")
end

-- Roblox draws a MeshPart in less detail the further its middle is from the camera (Automatic
-- render fidelity). A race venue's meshes are merged over hundreds of studs of roadside, so their
-- middles are far off even where they pass the car: the crowd came out as bare boxes and balls,
-- the trees, fences and lift towers vanished and the mountains went flat. Swaps every race venue
-- mesh for a copy drawn at full detail (server only, after Builder.loadMeshes), a few at a time
-- in the background, and hands each one on to the clients through MeshLibrary as it's made.
-- Call it again for meshes whose packs came in late; each mesh is only asked for once.
local sharpening = false
local sharpened: { [string]: boolean } = {}
function Builder.sharpenRaces()
	if sharpening then
		return
	end
	local keys: { string } = {}
	for _, parts in RaceScenery.MODELS do
		for _, p in parts do
			local key = p[13]
			if p[1] == "m" and not sharpened[key] and meshParts[key] then
				sharpened[key] = true
				table.insert(keys, key)
			end
		end
	end
	if #keys == 0 then
		return
	end
	local found, AssetService = pcall(game.GetService, game, "AssetService")
	if not found then
		return
	end
	sharpening = true
	local library = game:GetService("ReplicatedStorage"):FindFirstChild("MeshLibrary")
	local function sharpen(key: string)
		local old = meshParts[key]
		local ok, made = pcall(function()
			return (AssetService :: any):CreateMeshPartAsync(old.MeshId, {
				RenderFidelity = Enum.RenderFidelity.Precise,
				CollisionFidelity = Enum.CollisionFidelity.Box,
			})
		end)
		if not ok or not made then
			return
		end
		made.Name = key
		made.Anchored = true
		made.CanCollide = false
		meshParts[key] = made
		if library then
			local was = library:FindFirstChild(key)
			made:Clone().Parent = library
			if was then
				was:Destroy()
			end
		end
	end
	local nextKey, running = 0, 6
	for _ = 1, running do
		task.spawn(function()
			while nextKey < #keys do
				nextKey += 1
				sharpen(keys[nextKey])
			end
			running -= 1
			if running == 0 then
				sharpening = false
			end
		end)
	end
end

-- Goes up each time a mesh reaches a client after Builder.useLibrary (late packs, a car's mods,
-- Builder.sharpenRaces), so a model it keeps can be built again.
Builder.meshVersion = 0

function Builder.useLibrary(timeout: number?): boolean
	local library = game:GetService("ReplicatedStorage"):WaitForChild("MeshLibrary", timeout or 60)
	if not library then
		return false
	end
	for _, d in library:GetChildren() do
		if d:IsA("MeshPart") and fits(d) then
			meshParts[d.Name] = d
		end
	end
	table.clear(templates)
	-- Meshes the server loads later (a car's mods, Builder.loadFor) arrive one by one. So do the
	-- race venues' full-detail copies (Builder.sharpenRaces), replacing the ones already here: race
	-- models built from then on use them.
	library.ChildAdded:Connect(function(d: Instance)
		if d:IsA("MeshPart") and fits(d) then
			if meshParts[d.Name] and meshParts[d.Name] ~= d then
				for name in templates do
					if name:sub(1, 5) == "race:" then
						templates[name] = nil
					end
				end
			end
			meshParts[d.Name] = d
			meshArrived()
			Builder.meshVersion += 1
		end
	end)
	return true
end

-- Finds a mesh: one already taken, or (on a client) one that has reached the shared library since.
-- A big library replicates over a while after the folder itself turns up, so a model built early
-- can be missing meshes that arrive later.
local function findMesh(key: string): MeshPart?
	local hit = meshParts[key]
	if hit then
		return hit
	end
	local library = game:GetService("ReplicatedStorage"):FindFirstChild("MeshLibrary")
	local d = library and library:FindFirstChild(key)
	if d and d:IsA("MeshPart") and fits(d) then
		meshParts[key] = d
		meshArrived()
		return d
	end
	return nil
end

-- Whether every mesh of a model has arrived, so a build of it now has no stand-in boxes.
function Builder.complete(name: string): boolean
	if Builder.previewMeshes then
		return true
	end
	local parts = Catalog.MODELS[name]
	if not parts then
		return true
	end
	for _, p in parts do
		if p[1] == "m" and not findMesh(p[13]) then
			return false
		end
	end
	return true
end

-- Whether a built model has stand-in boxes for meshes that hadn't arrived when it was built.
function Builder.boxed(model: Instance): boolean
	if Builder.previewMeshes then
		return false
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Mesh") ~= nil and not d:IsA("MeshPart") then
			return true
		end
	end
	return false
end

-- Loads the mesh packs of a car itself (server only) when some of its meshes are missing (their
-- pack failed or is still queued), waiting up to timeout seconds. Returns whether they're all in.
function Builder.loadCar(car: string, timeout: number?): boolean
	local parts = Catalog.MODELS[car]
	if not parts or Builder.complete(car) then
		return true
	end
	for _, p in parts do
		local m = p[1] == "m" and not meshParts[p[13]] and Meshes.MESHES[p[13]]
		if m and m.asset ~= 0 and not packState[m.asset] then
			loadPacks({ m.asset }, nil, "first")
		end
	end
	local start = os.clock()
	while not Builder.complete(car) and os.clock() - start < (timeout or 8) do
		task.wait(0.1)
	end
	return Builder.complete(car)
end

-- The packs each car's mods are in, found once.
local modPacks: { [string]: { number } } = {}

local function packsOf(car: string): { number }
	local hit = modPacks[car]
	if hit then
		return hit
	end
	local seen: { [number]: boolean } = {}
	local assets: { number } = {}
	local mods, panels = `mod:{car}:`, `panel:{car}:`
	for name, parts in Catalog.MODELS do
		if name:sub(1, #mods) == mods or name:sub(1, #panels) == panels then
			for _, p in parts do
				local m = p[1] == "m" and Meshes.MESHES[p[13]]
				if m and m.asset ~= 0 and not seen[m.asset] then
					seen[m.asset] = true
					table.insert(assets, m.asset)
				end
			end
		end
	end
	modPacks[car] = assets
	return assets
end

-- Whether a car's mod packs have all loaded (true when it has none to load).
function Builder.modsReady(car: string): boolean
	for _, a in packsOf(car) do
		if packState[a] ~= "done" then
			return false
		end
	end
	return true
end

-- Loads the mesh packs of a car's mods (server only), waiting up to timeout seconds. The meshes
-- reach the clients through MeshLibrary.
function Builder.loadFor(car: string, timeout: number?)
	local assets = packsOf(car)
	for _, a in assets do
		if not packState[a] then
			-- Counted done even if it failed, so the town isn't drawn again and again waiting for it.
			loadPacks({ a }, function()
				packState[a] = "done"
			end, "first")
		end
	end
	local start = os.clock()
	while not Builder.modsReady(car) and os.clock() - start < (timeout or 20) do
		task.wait(0.1)
	end
end

-- Whether a mesh has a real MeshPart (false: it's drawn as a box).
function Builder.hasMesh(key: string): boolean
	return (meshParts :: any)[key] ~= nil
end

local function color(hex: string): Color3
	return Color3.fromHex(hex)
end

local function addText(part: BasePart, text: { text: string, fg: string, bg: string })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back -- the web game's +Z side, which faces the street
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	-- The web game paints chequers (the finish line, the flag) as rows of ▚ in its sign font; Roblox's
	-- fonts have no such letter, so they're drawn as squares: two rows, two squares a letter.
	local _, checks = string.gsub(text.text, "▚", "")
	if checks > 0 and string.gsub(text.text, "[▚%s]", "") == "" then
		local cols = checks * 2
		gui:SetAttribute("Checker", cols)
		local back = Instance.new("Frame")
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = color(text.bg)
		back.BorderSizePixel = 0
		back.Parent = gui
		for i = 0, cols - 1 do
			for j = 0, 1 do
				if (i + j) % 2 == 1 then
					local cell = Instance.new("Frame")
					cell.Position = UDim2.fromScale(i / cols, j / 2)
					cell.Size = UDim2.fromScale(1 / cols, 0.5)
					cell.BackgroundColor3 = color(text.fg)
					cell.BorderSizePixel = 0
					cell.Parent = back
				end
			end
		end
		gui.Parent = part
		return
	end
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = color(text.bg)
	label.BorderSizePixel = 0
	label.TextColor3 = color(text.fg)
	label.Text = text.text
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.Parent = label
	label.Parent = gui
	gui.Parent = part
end

-- For a part whose look isn't in Catalog.LOOKS: Catalog and the scenery files are written by the
-- same model build, but a merge can pair one build's Catalog with another's scenery, and a grey
-- piece is better than a race that won't start.
local NO_LOOK = { color = "#9e9e9e", transparency = 0, material = "SmoothPlastic" }

local function makePart(p: { any }): BasePart
	local kind: string = p[1]
	local cf = CFrame.new(p[2], p[3], p[4], p[5], p[6], p[7], p[8])
	local size = Vector3.new(p[9], p[10], p[11])
	local look = Catalog.LOOKS[p[12]] or NO_LOOK
	local part: BasePart
	if kind == "m" then
		local template = meshParts[p[13]]
		if template then
			part = template:Clone()
			;(part :: MeshPart).TextureID = ""
			-- The packs' materials come in as SurfaceAppearance, which would hide the look's colour.
			for _, child in part:GetChildren() do
				if child:IsA("SurfaceAppearance") then
					child:Destroy()
				end
			end
		else
			-- Not uploaded yet (or didn't load): a box of the mesh's size stands in.
			part = Instance.new("Part")
			part:SetAttribute("Mesh", p[13])
		end
	elseif kind == "c" then
		local c = Instance.new("Part")
		c.Shape = Enum.PartType.Cylinder
		part = c
	elseif kind == "s" then
		local s = Instance.new("Part")
		s.Shape = Enum.PartType.Ball
		part = s
	else
		part = Instance.new("Part")
		if kind == "e" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
	end
	part.Size = size
	if kind == "m" and part:IsA("MeshPart") then
		-- Roblox's glTF import turns the geometry half round about Y, so a mesh placed as the web
		-- game places it lands mirrored through its own middle; turn it back.
		part.CFrame = cf * CFrame.Angles(0, math.pi, 0)
	else
		part.CFrame = cf
	end
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color(look.color)
	part.Transparency = look.transparency
	part.Material = (Enum.Material :: any)[look.material]
	-- Kept cheap for big towns: only the town's Hit boxes take clicks and rays, and pieces smaller
	-- than a stud or so cast no shadow (from the town view nobody sees it, and each one costs).
	part.CanQuery = false
	part.CastShadow = look.transparency < 0.5 and math.max(size.X, size.Y, size.Z) > 1.5
	if look.paint then
		part:SetAttribute("Paint", true)
	end
	if look.text then
		addText(part, look.text)
	end
	return part
end

-- Set by the preview tools (tools/emulate), which draw every mesh from its geometry, so stand-in
-- boxes count as the real thing there.
Builder.previewMeshes = false

-- Whether a model of that name exists: "pizza@1" for buildings (id@level), "pip" for cars.
function Builder.has(name: string): boolean
	return Catalog.MODELS[name] ~= nil or Scenery.MODELS[name] ~= nil or RaceScenery.MODELS[name] ~= nil
end

-- A building's model at a level, falling back to the nearest level converted.
function Builder.buildingName(id: string, level: number?): string?
	for l = math.clamp(level or 1, 1, 10), 1, -1 do
		local name = `{id}@{l}`
		if Catalog.MODELS[name] then
			return name
		end
	end
	return nil
end

local function template(name: string): Model?
	local hit = templates[name]
	if hit then
		return hit
	end
	local merged = Scenery.MODELS[name] or RaceScenery.MODELS[name]
	local parts = Catalog.MODELS[name] or merged
	if not parts then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	-- A countryside or race venue mesh covers a whole patch of ground, so a stand-in box would bury
	-- the town or the road: those are left out until their mesh is uploaded.
	-- Racing stripes and hats as boxes would bury the car, so they wait for their meshes too.
	-- Mods and custom paint panels too, and one missing meshes isn't kept, so it fills in once they
	-- arrive.
	local mod = name:sub(1, 4) == "mod:" or name:sub(1, 6) == "panel:"
	local scenery = (merged ~= nil or mod or name:sub(1, 7) == "stripe:" or name:sub(1, 4) == "hat:") and not Builder.previewMeshes
	-- A car's parts and its mods' are named by their place in the list, which Catalog.MOD_DROPS,
	-- WHEELS, PANEL_DROPS and TRIM point at.
	local numbered = mod or MOD_DROPS[name] ~= nil or WHEELS[name] ~= nil or PANEL_DROPS[name] ~= nil or TRIM[name] ~= nil
	local missing = false
	local stood = false
	for i, p in parts do
		local absent = p[1] == "m" and not findMesh(p[13])
		if absent then
			stood = true
		end
		if scenery and absent then
			missing = true
		else
			local part = makePart(p)
			if numbered then
				part.Name = tostring(i)
			end
			part.Parent = model
		end
	end
	model.WorldPivot = CFrame.new()
	if not (mod and missing) then
		templates[name] = model
		if stood and not Builder.previewMeshes then
			boxed[name] = true
		end
	end
	return model
end

-- A new copy of a model, centred on its lot at the origin. paint recolours a car's body.
function Builder.build(name: string, paint: Color3?): Model?
	local t = template(name)
	if not t then
		return nil
	end
	local model = t:Clone()
	if paint then
		Builder.paint(model, paint)
	end
	return model
end

function Builder.paint(model: Model, paint: Color3)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Paint") then
			d.Color = paint
		end
	end
end

return Builder
