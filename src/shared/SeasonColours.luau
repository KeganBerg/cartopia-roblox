--!strict
-- The town's season by the real date, without rebuilding the models. The models (Catalog) were
-- drawn for one season (Catalog.SEASON); the web game draws the town for the season of the day
-- (scene/season.ts SEASON, blended toward the next one during a changeover: PAL). This works out,
-- for each kind of greenery, which colour of the built season becomes which colour of today's, from
-- the web's own per-season colours:
--   ground  the town's lawn and the meadow past it (PALETTES grass / ground)
--   leaves  oak canopies (decorProps oak: PAL.leaves)
--   bush    bushes (PAL.bush)
--   fronds  palm fronds (PAL.fronds)
--   flowers flower beds' blooms (decorProps flowers)
--   hedge   hedges (decorProps hedge: darker in winter)
--   wild    long grass and moss on wild land (decorProps WILD_GRASS, the boulder's moss)
--   tuft    the lawn's grass clumps (Tufts.tsx GREENS)
-- and which lawn pieces only belong to the built season (Tufts.tsx: leaf heaps and mushroom rings
-- in the fall). client/SeasonLook applies it. Colours are lower-case hex without the '#', as
-- Color3:ToHex() gives them.

local SeasonColours = {}

export type Palette = { [string]: any }
export type Maps = { [string]: { [string]: string } }

local FLOWERS = {
	fall = { "#ff8f00", "#c62828", "#fbc02d", "#8e24aa" },
	other = { "#e91e63", "#ffeb3b", "#ab47bc", "#ff7043", "#ffffff" },
}
local HEDGE = { winter = { "#2e5d31", "#356b38" }, other = { "#2e7d32", "#33873a", "#3c9142" } }
local WILD_GRASS = {
	spring = { "#5fae3a", "#76c043", "#4e9a2f" },
	summer = { "#4e9a2f", "#5fae3a", "#3f8a26" },
	fall = { "#a7a03c", "#8c9a43", "#c2a34a" },
	winter = { "#b9a98a", "#a1907a", "#cbbd9f" },
}
local MOSS = { winter = "#f4f8fb", other = "#6a8f3a" }
local WINTER_GREENS = { "#c9b98f", "#bfae84", "#d6c79d" }

-- Lawn pieces drawn only in one season (Tufts.tsx).
SeasonColours.ONLY = { heap = "fall", mushroom = "fall" }

-- The lawn's wildflower drifts, by season (Tufts.tsx BLOOMS): only in spring and summer.
SeasonColours.BLOOMS = {
	spring = { "#fff59d", "#ffffff", "#f8bbd0", "#ce93d8" },
	summer = { "#fdd835", "#ffffff", "#ffffff", "#ec407a" },
} :: { [string]: { string } }

-- Whether a part marked with the seasons it's left out in (Catalog.SEASON_HIDE, "winter spring")
-- shows in `season`.
function SeasonColours.shows(hide: string?, season: string): boolean
	if not hide then
		return true
	end
	for s in string.gmatch(hide, "%a+") do
		if s == season then
			return false
		end
	end
	return true
end

-- Which colours each kind of model takes, by its building def or model name.
SeasonColours.KINDS = {
	tree = { "leaves" },
	wildoak = { "leaves", "wild" },
	wildpine = { "wild" },
	wildrock = { "wild" },
	bush = { "bush" },
	palm = { "fronds" },
	flowers = { "flowers" },
	hedge = { "hedge" },
	tuft = { "tuft" },
} :: { [string]: { string } }

-- ---------- flora.ts shade(): three.js Color.offsetHSL, in linear light ----------
local function toLinear(c: number): number
	return if c < 0.04045 then c * 0.0773993808 else ((c * 0.9478672986 + 0.0521327014) ^ 2.4)
end
local function toSrgb(c: number): number
	return if c < 0.0031308 then c * 12.92 else 1.055 * (c ^ 0.41666) - 0.055
end
local function hue2rgb(p: number, q: number, t: number): number
	if t < 0 then
		t += 1
	end
	if t > 1 then
		t -= 1
	end
	if t < 1 / 6 then
		return p + (q - p) * 6 * t
	end
	if t < 1 / 2 then
		return q
	end
	if t < 2 / 3 then
		return p + (q - p) * 6 * (2 / 3 - t)
	end
	return p
end

local function hexOf(r: number, g: number, b: number): string
	local function ch(v: number): number
		return math.floor(math.clamp(v * 255, 0, 255) + 0.5)
	end
	return string.format("%02x%02x%02x", ch(r), ch(g), ch(b))
end

function SeasonColours.shade(hex: string, dl: number): string
	local h = string.gsub(hex, "#", "")
	local r = toLinear(tonumber(string.sub(h, 1, 2), 16) :: number / 255)
	local g = toLinear(tonumber(string.sub(h, 3, 4), 16) :: number / 255)
	local b = toLinear(tonumber(string.sub(h, 5, 6), 16) :: number / 255)
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local l = (min + max) / 2
	local hue, sat = 0, 0
	if min ~= max then
		local d = max - min
		sat = if l <= 0.5 then d / (max + min) else d / (2 - max - min)
		if max == r then
			hue = (g - b) / d + (if g < b then 6 else 0)
		elseif max == g then
			hue = (b - r) / d + 2
		else
			hue = (r - g) / d + 4
		end
		hue /= 6
	end
	l = math.clamp(l + dl, 0, 1)
	if sat == 0 then
		r, g, b = l, l, l
	else
		local p = if l <= 0.5 then l * (1 + sat) else l + sat - l * sat
		local q = 2 * l - p
		r, g, b = hue2rgb(q, p, hue + 1 / 3), hue2rgb(q, p, hue), hue2rgb(q, p, hue - 1 / 3)
	end
	return "#" .. hexOf(toSrgb(r), toSrgb(g), toSrgb(b))
end

-- Two colours multiplied in linear light, as three.js tints an instance (a wildflower by its colour).
function SeasonColours.multiply(a: Color3, b: Color3): Color3
	local function ch(x: number, y: number): number
		return math.clamp(toSrgb(toLinear(x) * toLinear(y)), 0, 1)
	end
	return Color3.new(ch(a.R, b.R), ch(a.G, b.G), ch(a.B, b.B))
end

-- Tufts.tsx GREENS for a season and its palette.
function SeasonColours.greens(season: string, pal: Palette): { string }
	if season == "winter" then
		return WINTER_GREENS
	end
	local s = SeasonColours.shade
	return { s(pal.grass, -0.1), s(pal.grass, 0.06), pal.grassSpeckle[3], pal.grassSpeckle[4], s(pal.grass, -0.16) }
end

local function key(hex: string): string
	return string.lower((string.gsub(hex, "#", "")))
end

-- Each colour of `a` to the one at the same place in `b` (round again when `b` is shorter).
local function pair(map: { [string]: string }, a: { string }, b: { string })
	for i, c in a do
		local k = key(c)
		if map[k] == nil then
			map[k] = key(b[(i - 1) % #b + 1])
		end
	end
end

-- The colour changes from the built season `from` (palette `fromPal`) to `to` (palette `toPal`).
-- Empty maps when nothing changes.
function SeasonColours.maps(from: string, fromPal: Palette, to: string, toPal: Palette): Maps
	local m: Maps = { ground = {}, leaves = {}, bush = {}, fronds = {}, flowers = {}, hedge = {}, wild = {}, tuft = {} }
	pair(m.ground, { fromPal.grass, fromPal.ground }, { toPal.grass, toPal.ground })
	pair(m.leaves, fromPal.leaves, toPal.leaves)
	pair(m.bush, fromPal.bush, toPal.bush)
	pair(m.fronds, fromPal.fronds, toPal.fronds)
	pair(m.flowers, FLOWERS[if from == "fall" then "fall" else "other"], FLOWERS[if to == "fall" then "fall" else "other"])
	pair(m.hedge, HEDGE[if from == "winter" then "winter" else "other"], HEDGE[if to == "winter" then "winter" else "other"])
	pair(m.wild, WILD_GRASS[from] or WILD_GRASS.summer, WILD_GRASS[to] or WILD_GRASS.summer)
	pair(m.wild, { MOSS[if from == "winter" then "winter" else "other"] }, { MOSS[if to == "winter" then "winter" else "other"] })
	pair(m.tuft, SeasonColours.greens(from, fromPal), SeasonColours.greens(to, toPal))
	-- Drop the colours that stay the same.
	for _, map in m do
		for k, v in map do
			if k == v then
				map[k] = nil
			end
		end
	end
	return m
end

-- What kind of greenery a model is, from its building def or its name ("tree@1", "tuft:3").
function SeasonColours.kindOf(name: string): string
	return (string.match(name, "^([%a]+)") or name)
end

-- A ground texture's tint and see-through for a lawn recoloured from `fromHex` to `toHex`: the
-- image keeps its detail, multiplied toward the new colour; where the new colour is lighter than
-- the image can be tinted to, the image fades so the part's own colour shows through.
function SeasonColours.tint(fromHex: string, toHex: string): (Color3, number)
	local a, b = Color3.fromHex(fromHex), Color3.fromHex(toHex)
	local function ratio(x: number, y: number): number
		return if x <= 0 then 1 else y / x
	end
	local rr, rg, rb = ratio(a.R, b.R), ratio(a.G, b.G), ratio(a.B, b.B)
	local over = math.max(rr, rg, rb)
	local fade = if over > 1.05 then math.min(0.85, 1 - 1 / over) else 0
	return Color3.new(math.min(rr, 1), math.min(rg, 1), math.min(rb, 1)), fade
end

return SeasonColours
