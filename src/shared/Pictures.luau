--!strict
-- Uploaded pictures as Roblox can show them. Open Cloud hands back a Decal's id for each picture
-- tools/models/upload.mjs uploads, but a Texture or an ImageLabel needs the id of the image inside
-- the decal. Ids already swapped at build time (tools/models/images.json) work as they are; for the
-- rest the server looks the image up (server/Pictures) and shares it as the Workspace attribute
-- Splash<id> = "rbxassetid://<image>".

local Pictures = {}

-- The content string to show for an uploaded picture's id.
function Pictures.content(id: number): string
	return (workspace:GetAttribute(`Splash{id}`) :: string?) or `rbxassetid://{id}`
end

-- Shows picture `id` in inst[prop] (a Texture's Texture, an ImageLabel's Image), and swaps in the
-- image's own id once the server has looked it up.
function Pictures.set(inst: Instance, prop: string, id: number)
	local key = `Splash{id}`
	;(inst :: any)[prop] = Pictures.content(id)
	if workspace:GetAttribute(key) ~= nil then
		return
	end
	local conn: RBXScriptConnection
	conn = workspace:GetAttributeChangedSignal(key):Connect(function()
		conn:Disconnect()
		;(inst :: any)[prop] = Pictures.content(id)
	end)
	inst.Destroying:Once(function()
		conn:Disconnect()
	end)
end

return Pictures
