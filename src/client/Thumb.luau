--!strict
-- A little 3D picture of a building or car for shop cards: a ViewportFrame showing the server's
-- copy of the model (ReplicatedStorage.ModelLibrary), seen from the front corner like the web
-- game's thumbnails.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Models = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models")
local Paint = require(Models:WaitForChild("Paint"))
local Builder = require(Models:WaitForChild("Builder"))
local Mods = require(Models:WaitForChild("Mods"))
local Panels = require(Models:WaitForChild("Panels"))
local Trim = require(Models:WaitForChild("Trim"))
local Skins = require(Models:WaitForChild("Skins"))
local CityTint = require(ReplicatedStorage.Shared:WaitForChild("CityTint"))

local Thumb = {}

-- Whether there's a picture of that model (the landmarks only once the model build has them).
function Thumb.has(kind: "Cars" | "Buildings", id: string): boolean
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	return lib ~= nil and (lib :: any)[kind]:FindFirstChild(id) ~= nil
end

-- theme: a building's colour theme (cityLook.themeFor), to show it in the colours it wears in town.
function Thumb.new(kind: "Cars" | "Buildings", id: string, size: UDim2, paint: Color3?, theme: any?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Size = size
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 175, 185)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -2, -1.2)
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local src = lib and (lib :: any)[kind]:FindFirstChild(id)
	if not src then
		return vp
	end
	local m = src:Clone()
	if paint then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Paint") then
				d.Color = paint
			end
		end
	end
	CityTint.apply(m, theme)
	m.Parent = vp
	local cf, ext = m:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local r = ext.Magnitude / 2
	local dir = Vector3.new(1, 0.75, 1.15).Unit
	cam.CFrame = CFrame.lookAt(cf.Position + dir * r * 3.6, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

-- A car in a whole paint job (its colour in its finish, and its stripes), its custom paint, the
-- hat it wears, its mods, its trim and its skins.
function Thumb.car(id: string, size: UDim2, job: Paint.Job, hat: any?, mods: { string }?, panels: any?, trim: any?, skin: string?, modSkin: any?): ViewportFrame
	local vp = Thumb.new("Cars", id, size)
	local m = vp:FindFirstChildOfClass("Model")
	if m then
		Thumb.dress(m, id, job, hat, mods, panels, trim, skin, modSkin)
	end
	return vp
end

-- Puts a whole look on a car model from the library: paint job, custom paint, trim, hat, mods and skins.
function Thumb.dress(m: Model, id: string, job: Paint.Job, hat: any?, mods: { string }?, panels: any?, trim: any?, skin: string?, modSkin: any?)
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local stripes = lib and lib:FindFirstChild("Stripes") and (lib :: any).Stripes:FindFirstChild(id)
	Paint.apply(m, job, stripes)
	Panels.apply(m, id, panels, job.finish, Builder.build)
	Trim.apply(m, id, trim, job.color)
	Paint.wearHat(m, id, hat, Builder.build)
	Mods.fit(m, id, mods, Builder.build)
	Skins.apply(m, skin, modSkin)
end

-- A copy of a car from the library in a whole look (Thumb.dress), for a 3D scene; nil when the
-- library doesn't have that car.
function Thumb.carModel(id: string, job: Paint.Job, hat: any?, mods: { string }?, skin: string?, modSkin: any?): Model?
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local src = lib and (lib :: any).Cars:FindFirstChild(id)
	if not src then
		return nil
	end
	local m = src:Clone()
	Thumb.dress(m, id, job, hat, mods, nil, nil, skin, modSkin)
	return m
end

-- A hat on its own (Paint.hatName), seen a little from above: empty until its meshes have reached
-- this player (Builder.useLibrary), when `fallback` (its emoji) shows instead.
function Thumb.hat(name: string, size: UDim2, fallback: string): GuiObject
	local m = Builder.build(name)
	if not m or #m:GetChildren() == 0 then
		local t = Instance.new("TextLabel")
		t.Size = size
		t.BackgroundTransparency = 1
		t.Text = fallback
		t.TextScaled = true
		return t
	end
	local vp = Instance.new("ViewportFrame")
	vp.Size = size
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(170, 175, 185)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-1, -2, -1.2)
	m.Parent = vp
	local cf, ext = m:GetBoundingBox()
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(0.6, 0.55, 1).Unit * ext.Magnitude * 2, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	return vp
end

return Thumb
