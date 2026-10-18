--!strict
-- A car's trim (the web's game/trim.ts, drawn by CarModel's tintGlass, lampOf and handleOf): the
-- window tint, the headlight colour and the door handles. Catalog.TRIM lists each car's glass,
-- headlight and handle parts.

local Catalog = require(script.Parent.Catalog)
local trim = require(script.Parent.Parent.Game.trim) :: any

local Trim = {}

-- Written by the model build (tools/models/build.mjs); empty in a build from before trim.
local TRIM: { [string]: { [string]: { number } } } = (Catalog :: any).TRIM or {}

-- A text key for a car's trim (for caches of built cars).
function Trim.key(t: any): string
	local tidy = trim.tidyTrim(t)
	if not tidy then
		return ""
	end
	return `{tidy.tint or ""}/{tidy.lights or ""}/{tidy.handles or ""}`
end

local function each(model: Model, list: { number }?, fn: (BasePart) -> ())
	local l: { number } = list or {}
	for _, i in l do
		local p = model:FindFirstChild(tostring(i))
		if p and p:IsA("BasePart") then
			fn(p)
		end
	end
end

-- Puts a car's trim on a freshly built car (after Paint.apply, before Mods.fit takes parts away).
-- color: the car's paint colour (body-coloured handles take it).
function Trim.apply(model: Model, carId: string, t: any, color: string?)
	local tidy = trim.tidyTrim(t)
	local parts = TRIM[carId]
	if not tidy or not parts then
		return
	end
	if tidy.tint then
		local d = trim.tintDef(tidy.tint)
		local mirror = d.id == "blue" or d.id == "gold"
		local c = Color3.fromHex(d.color)
		each(model, parts.tint, function(p)
			p.Color = c
			p.Transparency = 1 - d.opacity
			p.Reflectance = if mirror then 0.4 else 0.1
		end)
	end
	if tidy.lights then
		local c = Color3.fromHex(trim.trimDef("lights", tidy.lights).color)
		each(model, parts.lights, function(p)
			p.Color = c
		end)
	end
	if tidy.handles then
		local c = if tidy.handles == "body" and color then Color3.fromHex(color) else Color3.fromHex(trim.trimDef("handles", tidy.handles).color)
		each(model, parts.handles, function(p)
			p.Color = c
			p.Material = Enum.Material.SmoothPlastic
		end)
	end
end

return Trim
