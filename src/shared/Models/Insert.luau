--!strict
-- Every InsertService:LoadAsset the server makes goes through here (server only): a few at a time
-- and each tried again when it fails, since Roblox turns away a burst of loads, and a pack turned
-- away for good left boxes in the town. Urgent loads (the loading screen's pictures) go ahead of
-- the 3D shapes, and the far land waits behind everything.

local Insert = {}

export type Priority = "first" | "normal" | "last"

local AT_ONCE = 16 -- loads in flight together
local TRIES = 4

local ORDER = { "first", "normal", "last" }
local queues: { [string]: { () -> () } } = { first = {}, normal = {}, last = {} }
local running = 0

local function nextJob(): (() -> ())?
	for _, p in ORDER do
		local q = queues[p]
		if #q > 0 then
			return table.remove(q, 1)
		end
	end
	return nil
end

local function pump()
	while running < AT_ONCE do
		local job = nextJob()
		if not job then
			return
		end
		running += 1
		task.spawn(function()
			job()
			running -= 1
			pump()
		end)
	end
end

-- Loads asset id (yielding), trying a few times. Returns the model, or nil and the last error.
function Insert.load(id: number, priority: Priority?): (Model?, string?)
	local thread = coroutine.running()
	local result: Model?, err: string? = nil, nil
	local done, waiting = false, false
	local level: Priority = priority or "normal"
	table.insert(queues[level], function()
		local InsertService = game:GetService("InsertService")
		for attempt = 1, TRIES do
			local ok, model = pcall(InsertService.LoadAsset, InsertService, id)
			if ok and model then
				result = model
				break
			end
			err = tostring(model)
			if attempt < TRIES then
				task.wait(attempt)
			end
		end
		done = true
		if waiting then
			task.spawn(thread)
		end
	end)
	pump()
	if not done then
		waiting = true
		coroutine.yield()
	end
	return result, err
end

return Insert
