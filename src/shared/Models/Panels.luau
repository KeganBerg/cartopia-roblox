--!strict
-- A car's custom paint (the web's panelPaint.ts): the hood, the doors and the roof each in their
-- own colour and pattern, a pattern over the rest of the body, and a colour on the rims.
--
-- The web picks the panel per pixel in its shader. Here the body's paint comes cut into those
-- panels ("panel:<car>:<hood|doors|roof|body>" models, tools/models/export.test.tsx), which take
-- the place of the car's own paint (Catalog.PANEL_DROPS) when a panel has paint of its own.
-- Patterns are tiles (Catalog.TEXTURES "pattern_<id>") laid over a panel's faces, each pixel the
-- black, white or fire colour the shader mixes into the panel's colour.

local Catalog = require(script.Parent.Catalog)
local Paint = require(script.Parent.Paint)

local Panels = {}

-- Written by the model build (tools/models/build.mjs); empty in a build from before custom paint.
local PANEL_DROPS: { [string]: { number } } = (Catalog :: any).PANEL_DROPS or {}
local RIMS: { [string]: { number } } = (Catalog :: any).RIMS or {}
local TEXTURES: { [string]: { image: number, span: number, name: string } } = (Catalog :: any).TEXTURES or {}

local ZONES = { "body", "hood", "doors", "roof" }
-- The faces a panel's pattern goes on: the hood and roof face up, the doors sideways.
local N = Enum.NormalId
local FACES: { [string]: { Enum.NormalId } } = {
	body = { N.Top, N.Left, N.Right, N.Front, N.Back },
	hood = { N.Top, N.Front },
	doors = { N.Left, N.Right },
	roof = { N.Top },
}

-- A text key for a car's custom paint (for caches of built cars).
function Panels.key(panels: any): string
	if not panels then
		return ""
	end
	local bits = {}
	for _, z in { "body", "hood", "doors", "roof", "rims" } do
		local p = panels[z]
		if p and (p.color or p.pattern) then
			table.insert(bits, `{z}={p.color or ""}/{p.pattern or ""}`)
		end
	end
	return table.concat(bits, ",")
end

-- Whether a panel has paint of its own (a colour or a pattern).
local function own(p: any): boolean
	return p ~= nil and (p.color ~= nil or p.pattern ~= nil)
end

-- The pattern a panel shows (as setPanels works it out): its own when it has paint of its own,
-- otherwise the body's.
function Panels.patternOf(panels: any, zone: string): string?
	local body = panels and panels.body and panels.body.pattern
	if zone == "body" then
		return body
	end
	local p = panels and panels[zone]
	if own(p) then
		return p.pattern
	end
	return body
end

-- Lays a pattern's tile over a part's faces.
local function lay(part: BasePart, pattern: string?, faces: { Enum.NormalId })
	local t = pattern and TEXTURES[`pattern_{pattern}`]
	if not t then
		return
	end
	for _, face in faces do
		local tex = Instance.new("Texture")
		tex.Name = "Pattern"
		tex.Texture = `rbxassetid://{t.image}`
		tex.Face = face
		tex.StudsPerTileU = t.span
		tex.StudsPerTileV = t.span
		-- The previews (tools/emulate) find the image by name.
		tex:SetAttribute("Pattern", t.name)
		tex.Parent = part
	end
end

-- Paints a freshly built and painted car's panels (after Paint.apply, before Mods.fit, which colours
-- rims it fits from the RimColor this leaves). finish: the car's paint finish, which panel colours
-- are drawn in too. build: Builder.build.
function Panels.apply(model: Model, carId: string, panels: any, finish: string?, build: (string) -> Model?)
	if not panels then
		return
	end
	local pivot = model:GetPivot()
	local painted: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Paint") then
			table.insert(painted, d)
		end
	end
	local zoned = own(panels.hood) or own(panels.doors) or own(panels.roof)
	local drops = PANEL_DROPS[carId]
	local done = false
	if zoned and drops and painted[1] then
		-- Every panel's model, or none: half a body would show holes.
		local built: { [string]: Model } = {}
		local all = true
		for _, z in ZONES do
			local m = build(`panel:{carId}:{z}`)
			if m and #m:GetChildren() > 0 then
				built[z] = m
			else
				all = false
			end
		end
		if all then
			local like = painted[1]
			local folder = Instance.new("Model")
			folder.Name = "Panels"
			for _, z in ZONES do
				local p = panels[z]
				local colour = if z ~= "body" and own(p) and p.color then Paint.color(p.color, finish) else nil
				for _, part in built[z]:GetChildren() do
					if part:IsA("BasePart") then
						part.CFrame = pivot * part.CFrame
						part.Color = colour or like.Color
						part.Material = like.Material
						part.Reflectance = like.Reflectance
						if colour then
							-- Its own colour: mods in the body colour don't take it.
							part:SetAttribute("Paint", nil)
						end
						lay(part, Panels.patternOf(panels, z), FACES[z])
						part.Parent = folder
					end
				end
				built[z]:Destroy()
			end
			for _, i in drops do
				local old = model:FindFirstChild(tostring(i))
				if old then
					old:Destroy()
				end
			end
			folder.Parent = model
			done = true
		else
			for _, m in built do
				m:Destroy()
			end
		end
	end
	if not done then
		-- One pattern over the whole body.
		local pattern = Panels.patternOf(panels, "body")
		for _, part in painted do
			lay(part, pattern, FACES.body)
		end
	end
	local rims = panels.rims and panels.rims.color
	if rims then
		local c = Color3.fromHex(rims)
		local list: { number } = RIMS[carId] or {}
		for _, i in list do
			local part = model:FindFirstChild(tostring(i))
			if part and part:IsA("BasePart") then
				part.Color = c
			end
		end
		model:SetAttribute("RimColor", c)
	end
end

return Panels
