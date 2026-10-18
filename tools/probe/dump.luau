-- Prints every MeshPart in a downloaded Roblox model file: name, size, the mesh's own size and
-- orientation, to compare with what tools/models/build.mjs wrote.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local bytes = fs.readFile(process.args[1])
local ok, insts = pcall(roblox.deserializeModel, bytes)
if not ok then
	print("not a model file:", insts, string.sub(bytes, 1, 200))
	return
end
local n = 0
for _, root in insts do
	for _, d in { root, table.unpack(root:GetDescendants()) } do
		if d:IsA("MeshPart") then
			n += 1
			if n <= 40 then
				local cf = d.CFrame
				local rx, ry, rz = cf:ToOrientation()
				local initial = (pcall(function() return d.InitialSize end)) and d.InitialSize or "?"
				print(string.format("%s size=%s initial=%s pos=%s rot=(%.1f,%.1f,%.1f) mesh=%s", d.Name, tostring(d.Size), tostring(initial), tostring(cf.Position), math.deg(rx), math.deg(ry), math.deg(rz), tostring(d.MeshId)))
			end
		end
	end
end
print("meshparts:", n)
