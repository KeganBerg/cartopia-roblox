--!strict
-- The sky's pictures (Shared.Models.SkyImages, drawn by client/Horizon and client/SkyExtras) as the clients should ask
-- for them. As with the loading screen's (server/Splash), Open Cloud may hand back a decal's id
-- for an uploaded picture rather than its image's: each is looked up once when the server starts
-- and shared as a Workspace attribute Sky<id> = "rbxassetid://<image>".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkyImages = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"):WaitForChild("SkyImages")) :: any
local Insert = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"):WaitForChild("Insert")) :: any

local Sky = {}

local function resolve(id: number)
	if id == 0 then
		return
	end
	task.spawn(function()
		local model = Insert.load(id)
		if not model then
			return -- already an image's own id
		end
		local decal = model:FindFirstChildWhichIsA("Decal", true)
		local texture = decal and decal.Texture
		if texture and texture ~= "" then
			workspace:SetAttribute(`Sky{id}`, texture)
		end
		model:Destroy()
	end)
end

function Sky.start()
	for _, step in SkyImages.steps do
		for _, id in step.faces do
			resolve(id)
		end
	end
	-- The sky's extras (client/SkyExtras): the moon's phases, the northern lights, the season's fliers.
	for _, id in SkyImages.moon or {} do
		resolve(id)
	end
	resolve(SkyImages.aurora or 0)
	for _, id in SkyImages.fliers or {} do
		resolve(id)
	end
end

return Sky
