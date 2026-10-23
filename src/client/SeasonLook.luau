--!strict
-- The town's greenery in the season of the real date, as the web game draws it (scene/season.ts
-- SEASON and PAL, from this device's date and hemisphere). The models were built for one season
-- (Catalog.SEASON); here, on this player's screen only, the lawn, meadow, tree canopies, bushes,
-- palm fronds, flower beds, hedges, wild grass and the lawn's grass clumps take today's colours
-- instead (shared/SeasonColours works out which colour becomes which), and the leaf heaps and
-- mushroom rings that only grow in the built season are hidden. Parts are recoloured as they
-- stream in. The falling leaves, the sky and the horizon are other modules'.
--
-- What only another season has is put on here too, and only while it's that season, so it costs
-- no parts the rest of the year: the pieces a season adds to a tree, hedge or wild land
-- ("season:<model>:<season>" models: bare twigs and snow in winter, blossom along the hedges in
-- spring and summer), with the parts it leaves out hidden (Catalog.SEASON_HIDE, marked "Hide" by
-- Builder: the oak's canopy in winter), and the lawn's wildflower drifts in spring and summer (each
-- town's Lawn folder lists where they grow: server/TownView).
--
-- SeasonLook.set(name) shows another season (the admin panel's season preview); nil goes back to
-- the real one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local season = require(Shared:WaitForChild("Game"):WaitForChild("scene_season")) :: any
local Models = Shared:WaitForChild("Models")
local Catalog = require(Models:WaitForChild("Catalog")) :: any
local Builder = require(Models:WaitForChild("Builder")) :: any
local SeasonColours = require(Shared:WaitForChild("SeasonColours"))

local SeasonLook = {}

local BUILT = Catalog.SEASON or "fall"
local REAL = { name = season.SEASON, pal = season.PAL }

local maps: SeasonColours.Maps = {}
local target = BUILT
-- Every part this has looked after: its built colour (lower-case hex), what it is, its own
-- transparency, and the seasons it's left out in. Weak, so removed parts go.
type Seen = { hex: string, kind: string, see: number, hide: string? }
local seen: { [BasePart]: Seen } = setmetatable({}, { __mode = "k" }) :: any

-- The models some season adds pieces to ("season:<model>:<season>" in Catalog).
local DRESSED_IN: { [string]: boolean } = {}
for name in Catalog.MODELS do
	local model = string.match(name, "^season:(.+):%a+$")
	if model then
		DRESSED_IN[model] = true
	end
end

local GROUND_NAMES = { Turf = true, Meadow = true }

local function isGround(p: BasePart): boolean
	return GROUND_NAMES[p.Name] == true or (p.Parent ~= nil and p.Parent.Name == "Land")
end

-- What greenery a part belongs to: "ground", a SeasonColours kind, "only:<season>", or nil.
local function kindOf(p: BasePart): string?
	if isGround(p) then
		return "ground"
	end
	local model = p:FindFirstAncestorOfClass("Model")
	if not model then
		return nil
	end
	local def = model:GetAttribute("Def")
	local name = SeasonColours.kindOf(if type(def) == "string" then def else model.Name)
	local only = (SeasonColours.ONLY :: any)[name]
	if only then
		return "only:" .. only
	end
	return if SeasonColours.KINDS[name] then name else nil
end

local function tintGround(p: BasePart, from: string, to: string)
	for _, t in p:GetChildren() do
		if t:IsA("Texture") and t.Name == "Ground" then
			if from == to then
				t.Color3 = Color3.new(1, 1, 1)
				t.Transparency = 0
			else
				local c, fade = SeasonColours.tint(from, to)
				t.Color3 = c
				t.Transparency = fade
			end
		end
	end
end

-- Gives one part today's look.
local function paint(p: BasePart, s: Seen)
	if string.sub(s.kind, 1, 5) == "only:" then
		local keep = string.sub(s.kind, 6) == target
		p.Transparency = if keep then s.see else 1
		return
	end
	local list: { string } = if s.kind == "ground" then { "ground" } else (SeasonColours.KINDS[s.kind] or {})
	local to = s.hex
	for _, k in list do
		local hit = maps[k] and maps[k][s.hex]
		if hit then
			to = hit
			break
		end
	end
	p.Color = Color3.fromHex(to)
	if s.kind == "ground" then
		tintGround(p, s.hex, to)
	end
	if s.hide then
		p.Transparency = if SeasonColours.shows(s.hide, target) then s.see else 1
	end
end

-- A copy of a model for this screen only: kept out of shadows, taps and SeasonLook's own
-- recolouring. Nil when one of its meshes hasn't loaded (a stand-in box would show).
local function extra(name: string): Model?
	local m = Builder.build(name) :: Model?
	if not m then
		return nil
	end
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			if not d:IsA("MeshPart") and d:GetAttribute("Mesh") and not Builder.previewMeshes then
				m:Destroy()
				return nil
			end
			d:SetAttribute("SeasonExtra", true)
			d.CanQuery = false
			d.CanTouch = false
			d.CanCollide = false
		end
	end
	return m
end

-- Runs `again` once more meshes have reached this screen (one of a model's was still loading).
local function whenMeshes(again: () -> ())
	local v = Builder.meshVersion
	task.spawn(function()
		while Builder.meshVersion == v do
			task.wait(5)
		end
		again()
	end)
end

-- ---------- what a season adds to a model ----------
type Dressed = { season: string?, extra: Model? }
local dressed: { [Model]: Dressed } = setmetatable({}, { __mode = "k" }) :: any

local function dress(model: Model)
	local d = dressed[model]
	if not d or d.season == target then
		return
	end
	if d.extra then
		d.extra.Parent = nil
		d.extra:Destroy()
		d.extra = nil
	end
	d.season = target
	local base = model:GetAttribute("Base")
	local level = model:GetAttribute("Level")
	local name = Builder.buildingName(model:GetAttribute("Def"), if type(level) == "number" then level else 1)
	local key = if name then `season:{name}:{target}` else nil
	if typeof(base) ~= "CFrame" or not key or not Catalog.MODELS[key] then
		return
	end
	local made = extra(key)
	if not made then
		d.season = nil
		whenMeshes(function()
			if model.Parent then
				dress(model)
			end
		end)
		return
	end
	made.Name = "Season"
	made:PivotTo(base)
	made.Parent = model
	d.extra = made
end

-- A building that some season adds to, the first time one of its parts is seen.
local function noteModel(p: BasePart)
	local model = p.Parent
	if not model or not model:IsA("Model") or dressed[model] then
		return
	end
	local def = model:GetAttribute("Def")
	if type(def) ~= "string" or model:GetAttribute("Merged") then
		return
	end
	local level = model:GetAttribute("Level")
	local name = Builder.buildingName(def, if type(level) == "number" then level else 1)
	if not name or not DRESSED_IN[name] then
		return
	end
	dressed[model] = {}
	dress(model)
end

-- ---------- the lawn's wildflower drifts ----------
local lawns: { [Instance]: Model | false } = setmetatable({}, { __mode = "k" }) :: any

local function bloom(folder: Instance)
	local old = lawns[folder]
	if old then
		old.Parent = nil
		old:Destroy()
	end
	lawns[folder] = false
	local colours = SeasonColours.BLOOMS[target]
	local list = folder:GetAttribute("Blooms")
	if not colours or type(list) ~= "string" or list == "" then
		return
	end
	local drift = Instance.new("Model")
	drift.Name = "Blooms"
	for item in string.gmatch(list, "[^;]+") do
		local x, y, z, ry, s, ci = string.match(item, "^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")
		local flower = extra("flower")
		if not flower then
			drift:Destroy()
			whenMeshes(function()
				if folder.Parent and lawns[folder] == false then
					bloom(folder)
				end
			end)
			return
		end
		local size = tonumber(s) :: number
		local tint = Color3.fromHex(colours[(tonumber(ci) :: number) % #colours + 1])
		for _, p in flower:GetDescendants() do
			if p:IsA("BasePart") then
				local cf = p.CFrame
				p.Size *= size
				p.CFrame = CFrame.new(cf.Position * size) * cf.Rotation
				p.Color = SeasonColours.multiply(p.Color, tint)
				p.CastShadow = false
			end
		end
		flower:PivotTo(CFrame.new(tonumber(x) :: number, tonumber(y) :: number, tonumber(z) :: number) * CFrame.Angles(0, tonumber(ry) :: number, 0))
		flower.Parent = drift
	end
	drift.Parent = folder
	lawns[folder] = drift
end

local function noteLawn(folder: Instance)
	if lawns[folder] ~= nil then
		return
	end
	lawns[folder] = false
	folder:GetAttributeChangedSignal("Blooms"):Connect(function()
		bloom(folder)
	end)
	bloom(folder)
end

local function track(p: Instance)
	if p:IsA("Folder") and p.Name == "Lawn" then
		noteLawn(p)
		return
	end
	if not p:IsA("BasePart") or seen[p] or p:GetAttribute("SeasonExtra") then
		return
	end
	noteModel(p)
	local hide = p:GetAttribute("Hide")
	local kind = kindOf(p) or (if type(hide) == "string" then "" else nil)
	if not kind then
		return
	end
	local s: Seen = { hex = string.lower(p.Color:ToHex()), kind = kind, see = p.Transparency, hide = if type(hide) == "string" then hide else nil }
	if kind == "ground" and s.hex ~= string.lower((string.gsub(Catalog.GRASS or "", "#", ""))) and s.hex ~= string.lower((string.gsub(Catalog.MEADOW or "", "#", ""))) then
		return
	end
	seen[p] = s
	paint(p, s)
end

-- Shows `name`'s look (nil: the real season's).
function SeasonLook.set(name: string?)
	local pal = if name then season.PALETTES[name] else REAL.pal
	target = name or REAL.name
	maps = SeasonColours.maps(BUILT, season.PALETTES[BUILT], target, pal)
	for p, s in seen do
		if p.Parent then
			paint(p, s)
		end
	end
	for model in dressed do
		if model.Parent then
			dress(model)
		end
	end
	for folder in lawns do
		if folder.Parent then
			bloom(folder)
		end
	end
end

-- Looks after everything under `root` now (the emulator's stand-in for DescendantAdded, which never
-- fires there).
function SeasonLook._scan(root: Instance)
	track(root)
	for _, d in root:GetDescendants() do
		track(d)
	end
end

local started = false
function SeasonLook.start()
	if started then
		return
	end
	started = true
	SeasonLook.set(nil)
	workspace.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("Texture") and d.Name == "Ground" then
			-- A lawn's image laid after the part arrived.
			local p = d.Parent
			local s = p and p:IsA("BasePart") and seen[p :: BasePart]
			if s then
				paint(p :: BasePart, s)
			end
			return
		end
		track(d)
	end)
	task.spawn(function()
		for i, d in workspace:GetDescendants() do
			track(d)
			if i % 4000 == 0 then
				task.wait()
			end
		end
	end)
end

return SeasonLook
