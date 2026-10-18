--!strict
-- Looks up the image inside each uploaded decal (see Shared.Pictures). The loads go through
-- Shared.Models.Insert, which paces them and tries each again; ids asked for with `first` go ahead
-- of the 3D shapes (the loading screen's pictures, the town's ground).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Insert = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"):WaitForChild("Insert")) :: any

local Pictures = {}

local queued: { [number]: boolean } = {}

local function lookUp(id: number, first: boolean?)
	local model = Insert.load(id, if first then "first" else "normal")
	if not model then
		-- Not a decal (already an image's own id) or not loadable: it stays as it is.
		warn(`[Cartopia] Couldn't look up picture {id}`)
		return
	end
	local decal = model:FindFirstChildWhichIsA("Decal", true)
	local texture = decal and decal.Texture
	model:Destroy()
	if texture and texture ~= "" then
		workspace:SetAttribute(`Splash{id}`, texture)
	end
end

function Pictures.resolve(id: number?, first: boolean?)
	if not id or id == 0 or queued[id] then
		return
	end
	queued[id] = true
	task.spawn(lookUp, id, first)
end

return Pictures
