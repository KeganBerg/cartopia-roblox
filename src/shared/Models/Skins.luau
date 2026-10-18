--!strict
-- Car skins (the web's scene/skins.ts): patterns drawn inside the paint. The web draws them live
-- with a shader; here each is a tile baked from that shader (tools/models/skins.mjs) and laid on the
-- paint's faces: the base, tinted the paint's colour, then the skin's glow over it. A body skin goes
-- on the car's paint and the body-colour parts of its mods; a mod skin (the spoiler, exhaust, body
-- kit or hood slot) on the whole of the part fitted there.

local Catalog = require(script.Parent.Catalog)
local data = require(script.Parent.Parent.Game.data) :: any

local Skins = {}

-- Written by the model build (tools/models/build.mjs); empty in a build from before skins.
local TEXTURES: { [string]: { image: number, span: number, name: string } } = (Catalog :: any).TEXTURES or {}

local FACES = { Enum.NormalId.Top, Enum.NormalId.Bottom, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Front, Enum.NormalId.Back }

-- A text key for a car's skins (for caches of built cars).
function Skins.key(skin: string?, modSkin: any): string
	local bits = { skin or "" }
	for _, slot in data.SKINNED_SLOTS do
		local id = modSkin and modSkin[slot]
		if id then
			table.insert(bits, `{slot}={id}`)
		end
	end
	return table.concat(bits, ",")
end

-- The base and glow tiles of skin number `n`, or nil when the build has none.
function Skins.tiles(n: number): (any, any)
	return TEXTURES[`skin_{n}`], TEXTURES[`skinglow_{n}`]
end

-- Lays skin number `n` on a part (taking off any skin it had).
function Skins.lay(part: BasePart, n: number)
	for _, t in part:GetChildren() do
		if t:IsA("Texture") and t.Name == "Skin" then
			t:Destroy()
		end
	end
	local base, glow = Skins.tiles(n)
	if n == 0 or not base then
		return
	end
	for _, face in FACES do
		for i, t in { base, glow } do
			if t then
				local tex = Instance.new("Texture")
				tex.Name = "Skin"
				tex.Texture = `rbxassetid://{t.image}`
				tex.Face = face
				tex.StudsPerTileU = t.span
				tex.StudsPerTileV = t.span
				-- Under the custom paint patterns (ZIndex 1), the glow over everything.
				tex.ZIndex = if i == 1 then 0 else 2
				tex.Color3 = if i == 1 then part.Color else Color3.new(1, 1, 1)
				-- The previews (tools/emulate) find the image by name.
				tex:SetAttribute("Pattern", t.name)
				tex.Parent = part
			end
		end
	end
end

-- Puts a car's skins on a freshly built car, after everything else (Paint.apply, Panels.apply,
-- Trim.apply, Mods.fit), since the base takes the paint's final colour. skin: the car's skin id;
-- modSkin: its mod skins by slot.
function Skins.apply(model: Model, skin: string?, modSkin: any)
	local body = data.skinNumber(skin)
	local bySlot: { [string]: number } = {}
	for _, slot in data.SKINNED_SLOTS do
		local n = data.modSkinNumber(modSkin and modSkin[slot])
		if n > 0 then
			bySlot[slot] = n
		end
	end
	if body == 0 and next(bySlot) == nil then
		return
	end
	for _, p in model:GetDescendants() do
		if not p:IsA("BasePart") then
			continue
		end
		-- A mod's parts sit in its own folder (Mods.fit names them "Mod <id>").
		local folder = p.Parent
		local id = folder and folder.Parent == model and folder.Name:match("^Mod (.+)$")
		local d = id and data.modDef(id)
		local slot = d and d.slot
		local own = slot and not p:GetAttribute("StandIn") and bySlot[slot]
		if own then
			-- A mod skin covers the whole part, but not its lights or glass.
			if p.Material ~= Enum.Material.Neon and p.Material ~= Enum.Material.Glass and p.Transparency == 0 then
				Skins.lay(p, own)
			end
		elseif body > 0 and (p:GetAttribute("Paint") or (folder and folder.Name == "Panels")) then
			Skins.lay(p, body)
		end
	end
end

return Skins
