--!strict
-- The town's greenery in the season of the real date, as the web game draws it (scene/season.ts
-- SEASON and PAL, from this device's date and hemisphere). The models were built for one season
-- (Catalog.SEASON); here, on this player's screen only, the lawn, meadow, tree canopies, bushes,
-- palm fronds, flower beds, hedges, wild grass and the lawn's grass clumps take today's colours
-- instead (shared/SeasonColours works out which colour becomes which), and the leaf heaps and
-- mushroom rings that only grow in the built season are hidden. Parts are recoloured as they
-- stream in. The falling leaves, the sky and the horizon are other modules'.
--
-- SeasonLook.set(name) shows another season (the admin panel's season preview); nil goes back to
-- the real one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local season = require(Shared:WaitForChild("Game"):WaitForChild("scene_season")) :: any
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local SeasonColours = require(Shared:WaitForChild("SeasonColours"))

local SeasonLook = {}

local BUILT = Catalog.SEASON or "fall"
local REAL = { name = season.SEASON, pal = season.PAL }

local maps: SeasonColours.Maps = {}
local target = BUILT
-- Every part this has looked after: its built colour (lower-case hex), what it is, and for a hidden
-- one its own transparency. Weak, so removed parts go.
type Seen = { hex: string, kind: string, see: number? }
local seen: { [BasePart]: Seen } = setmetatable({}, { __mode = "k" }) :: any

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
		p.Transparency = if keep then (s.see or 0) else 1
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
end

local function track(p: Instance)
	if not p:IsA("BasePart") or seen[p] then
		return
	end
	local kind = kindOf(p)
	if not kind then
		return
	end
	local s: Seen = { hex = string.lower(p.Color:ToHex()), kind = kind, see = p.Transparency }
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
