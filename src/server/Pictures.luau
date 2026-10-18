--!strict
-- Looks up the image inside each uploaded decal (see Shared.Pictures), one at a time and trying
-- each a few times, since InsertService turns away a burst of loads. Ids asked for with `first`
-- jump the queue (the loading screen's pictures, the town's ground).

local InsertService = game:GetService("InsertService")

local Pictures = {}

local queued: { [number]: boolean } = {}
local queue: { number } = {}
local running = false

local function lookUp(id: number)
	for attempt = 1, 4 do
		local ok, model = pcall(InsertService.LoadAsset, InsertService, id)
		if ok and model then
			local decal = model:FindFirstChildWhichIsA("Decal", true)
			local texture = decal and decal.Texture
			model:Destroy()
			if texture and texture ~= "" then
				workspace:SetAttribute(`Splash{id}`, texture)
			end
			return
		end
		task.wait(attempt)
	end
	-- Not a decal (already an image's own id) or not loadable: it stays as it is.
	warn(`[Cartopia] Couldn't look up picture {id}`)
end

local function run()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while #queue > 0 do
			lookUp(table.remove(queue, 1) :: number)
			task.wait(0.1)
		end
		running = false
	end)
end

function Pictures.resolve(id: number?, first: boolean?)
	if not id or id == 0 then
		return
	end
	if queued[id] then
		if first then
			local at = table.find(queue, id)
			if at and at > 1 then
				table.remove(queue, at)
				table.insert(queue, 1, id)
			end
		end
		return
	end
	queued[id] = true
	if first then
		table.insert(queue, 1, id)
	else
		table.insert(queue, id)
	end
	run()
end

return Pictures
