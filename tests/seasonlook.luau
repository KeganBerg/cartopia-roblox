--!nocheck
-- Tests for the town's season by the real date (shared/SeasonColours): the colours the models
-- were built in turn into the web's colours for today's season.

local SeasonColours = require("../src/shared/SeasonColours")
local season = require("../src/shared/Game/scene_season")
local Catalog = require("../src/shared/Models/Catalog")

local P = season.PALETTES

return function(test)
	test("season look: shade matches the web's (the built lawn's tuft greens)", function()
		local g = SeasonColours.greens("fall", P.fall)
		assert(g[1] == "#899341" and g[2] == "#b9c65a" and g[5] == "#717935", table.concat(g, " "))
	end)

	test("season look: fall lawn, leaves and flowers turn to spring's", function()
		assert(Catalog.SEASON == "fall" and Catalog.GRASS == P.fall.grass and Catalog.MEADOW == P.fall.ground)
		local m = SeasonColours.maps("fall", P.fall, "spring", P.spring)
		assert(m.ground["a9b552"] == "86d05a" and m.ground["8c9a43"] == "68b444")
		assert(m.leaves["ef6c00"] == "8bd96a" and m.leaves["fbc02d"] == "f8bbd0")
		assert(m.flowers["c62828"] == "ffeb3b")
		assert(m.wild["a7a03c"] == "5fae3a")
		assert(m.tuft["899341"] ~= nil)
		assert(next(m.hedge) == nil, "hedges only change in winter")
	end)

	test("season look: winter darkens hedges and snows on the moss; the same season changes nothing", function()
		local w = SeasonColours.maps("fall", P.fall, "winter", P.winter)
		assert(w.hedge["2e7d32"] == "2e5d31" and w.wild["6a8f3a"] == "f4f8fb" and w.ground["a9b552"] == "eef3f7")
		local same = SeasonColours.maps("fall", P.fall, "fall", P.fall)
		for _, map in same do
			assert(next(map) == nil)
		end
		assert(SeasonColours.kindOf("tuft:3") == "tuft" and SeasonColours.kindOf("tree@1") == "tree" and SeasonColours.kindOf("wildoak") == "wildoak")
	end)

	test("season look: parts left out by season, and the lawn's wildflowers only in spring and summer", function()
		assert(SeasonColours.shows(nil, "winter") and SeasonColours.shows("winter", "fall"))
		assert(not SeasonColours.shows("winter spring summer", "summer") and not SeasonColours.shows("winter", "winter"))
		assert(#SeasonColours.BLOOMS.spring == 4 and #SeasonColours.BLOOMS.summer == 4)
		assert(SeasonColours.BLOOMS.fall == nil and SeasonColours.BLOOMS.winter == nil)
	end)

	test("season look: what another season adds uses only shapes already uploaded", function()
		-- Every mesh some other model draws (and so was uploaded with it).
		local used: { [string]: boolean } = {}
		for name, parts in Catalog.MODELS do
			if string.sub(name, 1, 7) ~= "season:" then
				for _, p in parts do
					if p[1] == "m" then
						used[p[13]] = true
					end
				end
			end
		end
		local adds = 0
		for name, parts in Catalog.MODELS do
			local model, s = string.match(name, "^season:(.+):(%a+)$")
			if model then
				adds += 1
				assert(Catalog.MODELS[model], `{name}: no {model}`)
				assert(s ~= Catalog.SEASON and (s == "winter" or s == "spring" or s == "summer" or s == "fall"), name)
				for _, p in parts do
					assert(p[1] ~= "m" or used[p[13]], `{name}: mesh {p[13]} is new`)
				end
			end
		end
		assert(adds > 0, "no season pieces")
		if Catalog.SEASON == "winter" then
			return
		end
		-- The oak's canopy is left out in winter (and its fallen leaves outside the fall).
		local hide = Catalog.SEASON_HIDE["tree@1"]
		assert(hide, "tree@1 hides nothing")
		local winter = 0
		for i, s in hide do
			assert(Catalog.MODELS["tree@1"][i], `tree@1 has no part {i}`)
			if not SeasonColours.shows(s, "winter") then
				winter += 1
			end
		end
		assert(winter > 0 and Catalog.MODELS["season:tree@1:winter"] ~= nil)
	end)
end
