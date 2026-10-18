--!strict
-- Building colour themes (game/cityLook.ts), as the web game's CityTint.tsx tint(): every plain part
-- of a building is mixed toward the theme's colour by the theme's amount, in linear light as three.js
-- mixes it. Lit, see-through and lettered parts and greenery keep their own colours. Used by the town
-- (server/TownView) and the building pictures (client/Thumb).

local CityTint = {}

local function toLinear(c: number): number
	return if c <= 0.04045 then c / 12.92 else ((c + 0.055) / 1.055) ^ 2.4
end

local function toSrgb(c: number): number
	return if c <= 0.0031308 then c * 12.92 else 1.055 * c ^ (1 / 2.4) - 0.055
end

local function linear(c: Color3): (number, number, number)
	return toLinear(c.R), toLinear(c.G), toLinear(c.B)
end

-- three.js's Color.getHSL, on linear values.
local function hsl(r: number, g: number, b: number): (number, number, number)
	local hi, lo = math.max(r, g, b), math.min(r, g, b)
	local l = (hi + lo) / 2
	if hi == lo then
		return 0, 0, l
	end
	local d = hi - lo
	local s = if l <= 0.5 then d / (hi + lo) else d / (2 - hi - lo)
	local h
	if hi == r then
		h = (g - b) / d + (if g < b then 6 else 0)
	elseif hi == g then
		h = (b - r) / d + 2
	else
		h = (r - g) / d + 4
	end
	return h / 6, s, l
end

-- CityTint.tsx keeps(): lit (Neon), see-through and lettered parts, and greens.
local function keeps(p: BasePart): boolean
	if p.Transparency > 0.05 or p.Material == Enum.Material.Neon or p:FindFirstChildOfClass("SurfaceGui") then
		return true
	end
	local h, s, l = hsl(linear(p.Color))
	return h > 0.19 and h < 0.45 and s > 0.25 and l > 0.12
end

-- Recolours a freshly built model in a theme ({ c, amount }, from cityLook.themeFor); nil leaves it.
function CityTint.apply(model: Instance, theme: any)
	if not theme then
		return
	end
	local tr, tg, tb = linear(Color3.fromHex(theme.c))
	local k = theme.amount
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and not keeps(p) then
			local r, g, b = linear(p.Color)
			p.Color = Color3.new(toSrgb(r + (tr - r) * k), toSrgb(g + (tg - g) * k), toSrgb(b + (tb - b) * k))
		end
	end
end

return CityTint
