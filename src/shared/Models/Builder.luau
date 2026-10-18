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

local Builder = {}

local templates: { [string]: Model } = {}
local meshParts: { [string]: MeshPart } = {}

-- Loads every uploaded mesh pack (server only: InsertService). Waits for all of them, up to
-- timeout seconds, calling progress(done, total) as each one finishes. Safe to call more than once.
function Builder.loadMeshes(timeout: number?, progress: ((done: number, total: number) -> ())?)
	local InsertService = game:GetService("InsertService")
	local byAsset: { [number]: boolean } = {}
	for _, m in Meshes.MESHES do
		if m.asset ~= 0 then
			byAsset[m.asset] = true
		end
	end
	local left, total = 0, 0
	for _ in byAsset do
		total += 1
	end
	if progress then
		progress(0, total)
	end
	for asset in byAsset do
		left += 1
		task.spawn(function()
			local ok, model = pcall(InsertService.LoadAsset, InsertService, asset)
			if ok and model then
				for _, d in model:GetDescendants() do
					if d:IsA("MeshPart") then
						meshParts[d.Name] = d
					end
				end
			else
				warn(`[Cartopia] mesh pack {asset} didn't load: {model}`)
			end
			left -= 1
			if progress then
				progress(total - left, total)
			end
		end)
	end
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
function Builder.useLibrary(timeout: number?): boolean
	local library = game:GetService("ReplicatedStorage"):WaitForChild("MeshLibrary", timeout or 60)
	if not library then
		return false
	end
	for _, d in library:GetChildren() do
		if d:IsA("MeshPart") then
			meshParts[d.Name] = d
		end
	end
	table.clear(templates)
	return true
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

local function makePart(p: { any }): BasePart
	local kind: string = p[1]
	local cf = CFrame.new(p[2], p[3], p[4], p[5], p[6], p[7], p[8])
	local size = Vector3.new(p[9], p[10], p[11])
	local look = Catalog.LOOKS[p[12]]
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
	return Catalog.MODELS[name] ~= nil or Scenery.MODELS[name] ~= nil
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
	local parts = Catalog.MODELS[name] or Scenery.MODELS[name]
	if not parts then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	-- A countryside mesh covers a whole patch of ground, so a stand-in box would bury the town:
	-- those are left out until their mesh is uploaded.
	local scenery = Scenery.MODELS[name] ~= nil and not Builder.previewMeshes
	for _, p in parts do
		if not (scenery and p[1] == "m" and not meshParts[p[13]]) then
			makePart(p).Parent = model
		end
	end
	model.WorldPivot = CFrame.new()
	templates[name] = model
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
