--!strict
-- Car skins (the web's scene/skins.ts): patterns drawn inside the paint. The web draws them live
-- with a shader; here each is a tile baked from that shader (tools/models/skins.mjs) and laid on the
-- paint's faces: the base, a layer that turns the paint under it into the shader's colours, then the
-- skin's glow over it. The glow is baked at a few moments; on the player's screen SkinMotion
-- (client) plays through them, two textures fading one into the next, and slides them with the
-- camera as if they lay under the paint. A body skin goes
-- on the car's paint and the body-colour parts of its mods; a mod skin (the spoiler, exhaust, body
-- kit or hood slot) on the whole of the part fitted there.

local Catalog = require(script.Parent.Catalog)
local Pictures = require(script.Parent.Parent.Pictures)
local data = require(script.Parent.Parent.Game.data) :: any

local Skins = {}

-- Written by the model build (tools/models/build.mjs); empty in a build from before skins.
type Tile = { image: number, span: number, name: string, depth: number?, step: number? }
local TEXTURES: { [string]: Tile } = (Catalog :: any).TEXTURES or {}

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
	if modSkin and modSkin.tracks then
		table.insert(bits, `tracks={modSkin.tracks}`)
	end
	return table.concat(bits, ",")
end

-- Track skins (the web's TankTracks in CarModel.tsx): the colours of a tracked body's links, kept in
-- the car's modSkin.tracks. The model build keeps each link's colour roles as their own parts, in
-- the stock colours of TRACK_STEEL (as the build wrote them: linear, so darker than they read on
-- the web) and the gear's steel; a skin recolours each role, lights its glowing role, alternates
-- its two tints link pair by link pair (Hazard) and turns the gear's steel and hubs its way, as
-- the web's gearLook. The rubber stays.
local GEAR_STEEL = "#4f545b"
local LINK_ROLES = { "plate", "grouser", "horn", "pin", "stud" }

local function linear(hex: string): Color3
	local c = Color3.fromHex(hex)
	local function f(v: number): number
		return if v <= 0.04045 then v / 12.92 else ((v + 0.055) / 1.055) ^ 2.4
	end
	return Color3.new(f(c.R), f(c.G), f(c.B))
end

local function near(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 2.5 / 255 and math.abs(a.G - b.G) < 2.5 / 255 and math.abs(a.B - b.B) < 2.5 / 255
end

function Skins.tracks(model: Model, id: string?)
	local sk = id and data.trackSkinDef(id)
	local def = data.carDef(model.Name)
	if not sk or not def or def.body ~= "tank" then
		return
	end
	local stock: { { role: string, color: Color3 } } = {}
	for _, role in LINK_ROLES do
		table.insert(stock, { role = role, color = linear(data.TRACK_STEEL.look[role]) })
	end
	local steel = linear(GEAR_STEEL)
	local plate = Color3.fromHex(sk.look.plate)
	local metal = if sk.metal >= 0.6 then Enum.Material.Metal else Enum.Material.SmoothPlastic
	local link, inLink = -1, false
	for _, p in model:GetDescendants() do
		if not p:IsA("BasePart") or p.Transparency >= 1 then
			continue
		end
		local folder = p.Parent
		if folder and folder.Parent == model and folder.Name:match("^Mod ") then
			continue
		end
		local role = nil
		for _, s in stock do
			if near(p.Color, s.color) then
				role = s.role
				break
			end
		end
		if role == "plate" then
			link += 1
			inLink = true
		elseif not role then
			inLink = false
			if near(p.Color, steel) then
				-- The road wheels, idlers and arms: steel half way to the skin's plates.
				p.Color = Color3.fromHex(GEAR_STEEL):Lerp(plate, 0.5)
				p.Material = metal
			end
			continue
		end
		local color = Color3.fromHex(sk.look[role])
		if sk.alt and inLink then
			local tint = Color3.fromHex(sk.alt[(link // 2) % 2 + 1])
			color = Color3.new(color.R * tint.R, color.G * tint.G, color.B * tint.B)
		end
		p.Color = color
		if sk.glow and sk.glow.role == role then
			p.Color = Color3.fromHex(sk.glow.color)
			p.Material = Enum.Material.Neon
		else
			p.Material = metal
		end
		p.Reflectance = if sk.metal >= 0.95 then 0.25 else 0
	end
end

-- The base tile of skin number `n` and its glow at each moment, or nil when the build has none.
function Skins.tiles(n: number): (Tile?, { Tile })
	local glows = {}
	local first = TEXTURES[`skinglow_{n}`]
	if first then
		table.insert(glows, first)
		for k = 2, 16 do
			local t = TEXTURES[`skinglow{k}_{n}`]
			if not t then
				break
			end
			table.insert(glows, t)
		end
	end
	return TEXTURES[`skin_{n}`], glows
end

-- The picker swatch of skin `id` (a body or mod skin's id), or nil when the build has none.
function Skins.swatch(id: string): Tile?
	return TEXTURES[`skinswatch_{id}`]
end

-- Lays skin number `n` on a part (taking off any skin it had).
function Skins.lay(part: BasePart, n: number)
	for _, t in part:GetChildren() do
		if t:IsA("Texture") and (t.Name == "Skin" or t.Name == "SkinGlow") then
			t:Destroy()
		end
	end
	local base, glows = Skins.tiles(n)
	if n == 0 or not base then
		return
	end
	-- Every moment of the glow, for SkinMotion to swap in (and the previews to find by name).
	local ids, names = {}, {}
	for _, g in glows do
		table.insert(ids, tostring(g.image))
		table.insert(names, g.name)
	end
	for _, face in FACES do
		-- The base, then two glows: the first moment showing, the second hidden over it until
		-- SkinMotion fades it in.
		for i, t in { base, glows[1] or false, glows[2] or false } do
			if t then
				local tex = Instance.new("Texture")
				-- SkinMotion moves the glows (it finds them by name).
				tex.Name = if i == 1 then "Skin" else "SkinGlow"
				Pictures.set(tex, "Texture", t.image)
				tex.Face = face
				tex.StudsPerTileU = t.span
				tex.StudsPerTileV = t.span
				-- Under the custom paint patterns (ZIndex 1), the glows over everything.
				tex.ZIndex = if i == 1 then 0 else i
				if i > 1 then
					tex:SetAttribute("Depth", t.depth or 0)
					tex:SetAttribute("Step", t.step or 0.5)
					tex:SetAttribute("Slot", i - 1)
					tex:SetAttribute("Frames", table.concat(ids, ","))
					tex:SetAttribute("Patterns", table.concat(names, ","))
					tex.Transparency = if i == 3 then 1 else 0
				end
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
	Skins.tracks(model, modSkin and modSkin.tracks)
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
