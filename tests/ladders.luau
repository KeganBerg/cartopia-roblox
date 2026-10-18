--!nocheck
-- Tests for Models/Ladders: the web buildings' ladders found in their Catalog parts, with a truss
-- where a climbing player fits.

local Ladders = require("../src/shared/Models/Ladders")
local Catalog = require("../src/shared/Models/Catalog")

return function(test)
	local all = {}
	for name, parts in Catalog.MODELS do
		local list = Ladders.find(parts)
		if #list > 0 then
			all[name] = list
		end
	end

	test("finds the garage's and the billboard's ladders, and nothing else", function()
		local names = {}
		for name in all do
			table.insert(names, name)
		end
		table.sort(names)
		assert(table.concat(names, ",") == "billboard@1,garage@1", table.concat(names, ","))
	end)

	test("the garage ladder's truss stands on the wall and tops out level with the roof", function()
		local l = all["garage@1"][1]
		assert(#all["garage@1"] == 1)
		-- Rails at x 18.3, z -10 and -8; the roof's skin is at 17.48 (its edge overhangs to x 19,
		-- inside the truss's face at 19.3).
		assert(math.abs(l.x - 18.3) < 0.01 and math.abs(l.z + 9) < 0.01, `{l.x},{l.z}`)
		assert(l.sx == 2 and l.sz == 2, `{l.sx}x{l.sz}`)
		assert(math.abs(l.top - 17.48) < 0.01, `top {l.top}`)
		assert(l.bottom <= 0 and l.bottom > -2, `bottom {l.bottom}`)
		assert(#l.parts == 10, `{#l.parts} parts`)
	end)

	test("the billboard ladder's truss clears the catwalk and tops out at its railing", function()
		local l = all["billboard@1"][1]
		-- The catwalk reaches out to z 2.6 and its lamp to 2.8: the truss's face is past both, so a
		-- climber doesn't hit them.
		assert(l.z + 1 >= 2.6 and l.z + 1 < 3 and math.abs(l.x + 5) < 0.01, `{l.x},{l.z}`)
		assert(math.abs(l.top - 14.1) < 0.01, `top {l.top}`)
		assert(l.bottom <= 0.11 and l.bottom > -2, `bottom {l.bottom}`)
	end)
end
