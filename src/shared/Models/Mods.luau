--!strict
-- Fits a car's mods (the web's CarMods and its Rims and Stance looks) onto a built car.
--
-- Each mod's own parts are a model of their own ("mod:<car>:<mod>", tools/models/export.test.tsx),
-- drawn with that mod alone on the car. A mod can also take some of the car's own parts away (a
-- roof rack goes where the roof gear was): Catalog.MOD_DROPS lists those, and the mod's model
-- carries the redrawn stand-ins (the car's trim without the roof gear). Two mods that take the
-- same part away would both bring a stand-in, so only the first, in slot order, keeps its own.
-- A stance lifts or drops the body over bigger or smaller tyres.

local Catalog = require(script.Parent.Catalog)
local data = require(script.Parent.Parent.Game.data) :: any

local Mods = {}

-- Written by the model build (tools/models/build.mjs); empty in a build from before mods.
local MOD_DROPS: { [string]: any } = (Catalog :: any).MOD_DROPS or {}
local WHEELS: { [string]: any } = (Catalog :: any).WHEELS or {}
local STANCE: { [string]: any } = (Catalog :: any).STANCE or {}

-- Which mod's stand-ins win when two take the same part away.
local ORDER = { spoiler = 1, kit = 2, hood = 3, exhaust = 4, lights = 5, rims = 6, tires = 7, stance = 8 }

-- A text key for a car's fitted mods (for caches of built cars).
function Mods.key(mods: { string }?): string
	if not mods or #mods == 0 then
		return ""
	end
	local list = table.clone(mods)
	table.sort(list)
	return table.concat(list, ",")
end

-- Fits `mods` onto a freshly built car `model` of type `carId` (its parts untouched since
-- Builder.build). build: Builder.build. Comes after Paint.apply and Paint.wearHat: mod parts in
-- the body colour take the car's paint, and a stance carries the stripes and hat with the body.
function Mods.fit(model: Model, carId: string, mods: { string }?, build: (string) -> Model?)
	if not mods or #mods == 0 then
		return
	end
	local list = {}
	for _, id in mods do
		local d = data.modDef(id)
		if d then
			table.insert(list, d)
		end
	end
	table.sort(list, function(a: any, b: any)
		return (ORDER[a.slot] or 9) < (ORDER[b.slot] or 9)
	end)
	local parts = Catalog.MODELS[carId]
	local drops = MOD_DROPS[carId] or {}
	local pivot = model:GetPivot()
	local painted: BasePart? = nil
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and d:GetAttribute("Paint") then
			painted = d
			break
		end
	end
	local wheels: { [BasePart]: boolean } = {}
	for _, i in WHEELS[carId] or {} do
		local w = model:FindFirstChild(tostring(i))
		if w and w:IsA("BasePart") then
			wheels[w] = true
		end
	end
	local claimed: { [number]: boolean } = {}
	local gone: { [number]: boolean } = {}
	local stance: any = nil
	for _, d in list do
		if d.slot == "stance" then
			stance = d
			continue
		end
		-- The looks of the parts this mod takes away: its parts in those looks are stand-ins, kept
		-- only where this mod is first to take that look's part away.
		local swaps: { [number]: boolean } = {}
		for _, i in drops[d.id] or {} do
			local look = parts and parts[i] and parts[i][12]
			if look then
				swaps[look] = swaps[look] or not claimed[i]
			end
			claimed[i] = true
			gone[i] = true
		end
		local name = `mod:{carId}:{d.id}`
		local m = build(name)
		local own = Catalog.MODELS[name]
		if not m or not own then
			continue
		end
		local folder = Instance.new("Model")
		folder.Name = `Mod {d.id}`
		for _, p in m:GetChildren() do
			local i = tonumber(p.Name)
			local look = i and own[i] and own[i][12]
			if p:IsA("BasePart") and not (look and swaps[look] == false) then
				p.CFrame = pivot * p.CFrame
				if p:GetAttribute("Paint") and painted then
					p.Color = painted.Color
					p.Material = painted.Material
					p.Reflectance = painted.Reflectance
				end
				if d.slot == "rims" then
					wheels[p] = true
				end
				p.Parent = folder
			end
		end
		m:Destroy()
		folder.Parent = model
	end
	for i in gone do
		local p = model:FindFirstChild(tostring(i))
		if p then
			wheels[p :: BasePart] = nil
			p:Destroy()
		end
	end
	if stance then
		local rise = (STANCE[carId] or {})[stance.id]
		local look = data.STANCE[stance.id]
		if rise then
			local tyre = look and look.tyre or 1
			for _, p in model:GetDescendants() do
				if p:IsA("BasePart") then
					local at = pivot:ToObjectSpace(p.CFrame)
					if wheels[p] then
						-- The wheel grows (or shrinks) about the road under it.
						p.Size *= tyre
						p.CFrame = pivot * (CFrame.new(0, at.Y * (tyre - 1), 0) * at)
					else
						p.CFrame = pivot * (CFrame.new(0, rise, 0) * at)
					end
				end
			end
		end
	end
end

return Mods
