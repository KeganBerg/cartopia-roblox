--!strict
-- A little 3D picture of a building or car for shop cards: a ViewportFrame showing the server's
-- copy of the model (ReplicatedStorage.ModelLibrary), seen from the front corner like the web
-- game's thumbnails.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Paint = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"):WaitForChild("Paint"))

local Thumb = {}

function Thumb.new(kind: "Cars" | "Buildings", id: string, size: UDim2, paint: Color3?): ViewportFrame
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

-- A car in a whole paint job: its colour in its finish, and its stripes.
function Thumb.car(id: string, size: UDim2, job: Paint.Job): ViewportFrame
	local vp = Thumb.new("Cars", id, size)
	local m = vp:FindFirstChildOfClass("Model")
	local lib = ReplicatedStorage:FindFirstChild("ModelLibrary")
	local stripes = lib and lib:FindFirstChild("Stripes") and (lib :: any).Stripes:FindFirstChild(id)
	if m then
		Paint.apply(m, job, stripes)
		end
	return vp
end

return Thumb
