--!nocheck
-- Tests for the model build's files: every part's look is one Catalog.LOOKS has. Catalog and the
-- scenery files come from the same build (tools/models/build.mjs), so a part pointing past the end
-- of LOOKS means a merge mixed two builds' files: run the model build again.

local Catalog = require("../src/shared/Models/Catalog")
local Scenery = require("../src/shared/Models/Scenery")
local RaceScenery = require("../src/shared/Models/RaceScenery")

return function(test)
	for file, M in { Catalog = Catalog, Scenery = Scenery, RaceScenery = RaceScenery } do
		test(`every {file} part has a look in Catalog.LOOKS`, function()
			local bad, first = 0, nil
			for name, parts in M.MODELS do
				for _, p in parts do
					if Catalog.LOOKS[p[12]] == nil then
						bad += 1
						first = first or `{name} look {p[12]}`
					end
				end
			end
			assert(bad == 0, `{bad} parts with no look (first: {first}; LOOKS has {#Catalog.LOOKS})`)
		end)
	end
end
