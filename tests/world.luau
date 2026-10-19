--!nocheck
-- Tests for server/World's plot layout: plots never overlap, the nearest come first, and every
-- position is found on the right plot.

local World = require("../src/server/World")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

return function(test)
	test("world: plots ring the hub, nearest first, far enough apart for a whole town", function()
		expectEq(World.COUNT, 24, "plots")
		local seen = {}
		for i = 0, World.COUNT - 1 do
			local x, z = World.originXZ(i)
			local key = `{x},{z}`
			assert(not seen[key], `plot {i} repeats {key}`)
			seen[key] = true
			assert(x ~= 0 or z ~= 0, "a plot on the hub")
			-- A full town reaches 560 studs from its middle: with a road between, no overlap.
			for j = 0, i - 1 do
				local px, pz = World.originXZ(j)
				assert(math.max(math.abs(x - px), math.abs(z - pz)) >= 1120 + World.ROAD_W, `plots {i} and {j} overlap`)
			end
		end
		local x0, z0 = World.originXZ(0)
		expectEq(math.abs(x0) + math.abs(z0), World.PITCH, "first plot is beside the hub")
		local x8, z8 = World.originXZ(8)
		expectEq(math.max(math.abs(x8), math.abs(z8)), 2 * World.PITCH, "ninth plot starts the second ring")
	end)

	test("world: a position is on the plot it's in", function()
		for i = 0, World.COUNT - 1 do
			local x, z = World.originXZ(i)
			expectEq(World.plotAtXZ(x + 500, z - 500), i, `plot {i}`)
		end
		expectEq(World.plotAtXZ(0, 0), nil, "the hub")
		expectEq(World.plotAtXZ(4000, 0), nil, "past the last ring")
	end)
end
