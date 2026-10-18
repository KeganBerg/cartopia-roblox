--!nocheck
-- Checks the converted game rules against the web project's handoff kit: tests/handoff/Curves.luau is
-- the kit's Curves module (formulas sampled at levels 1-100 by the web repo's
-- scripts/roblox/export.mjs), copied unchanged. Re-copy it when Kegan sends a new kit.

local G = "../src/shared/Game/"
local Curves = require("./handoff/Curves")

local function near(a, b)
	return a == b or math.abs(a - b) < 1e-9 * math.max(1, math.abs(b))
end

return function(test)
	local data = require(G .. "data")
	local packs = require(G .. "bucksPacks")
	local crates = require(G .. "crates")

	local function each(name, fn, key)
		test(`kit: {name} matches the web at every sampled level`, function()
			local bad = {}
			for k, want in Curves[key or name] do
				local got = fn(k)
				if not near(got, want) then
					table.insert(bad, `{k}: {got} ~= {want}`)
				end
			end
			assert(#bad == 0, table.concat(bad, ", "))
		end)
	end
	each("xpToNext", data.xpToNext)
	each("levelXpBoost", data.levelXpBoost)
	each("playXpMult", data.playXpMult)
	each("townXpMult", data.townXpMult)
	each("fuelPerMin", data.fuelPerMin)
	each("baseFuelCap", data.baseFuelCap)
	each("gemCoins", packs.gemCoins)
	test("kit: plot prices match the web", function()
		for bought, want in Curves.plotPriceByPlotsBought do
			assert(data.plotPrice(bought) == want, `{bought}: {data.plotPrice(bought)} ~= {want}`)
		end
	end)

	local function crate(id)
		for _, c in crates.CRATES do
			if c.id == id then
				return c
			end
		end
		error(`no crate {id}`)
	end
	test("kit: crate odds and costs match the web at every level", function()
		local bad = {}
		for id, levels in Curves.crateOddsByLevel do
			local c = crate(id)
			for level, want in levels do
				local got = crates.crateOdds(c, level)
				for kind, w in want do
					if not near(got[kind] or 0, w) then
						table.insert(bad, `{id} {level} {kind}: {got[kind]} ~= {w}`)
					end
				end
			end
		end
		for id, levels in Curves.crateCostByLevel do
			local c = crate(id)
			for level, want in levels do
				local got = crates.crateCost(c, level)
				if got.coins ~= want.coins or got.bucks ~= want.bucks then
					table.insert(bad, `{id} {level} cost: {got.coins}/{got.bucks} ~= {want.coins}/{want.bucks}`)
				end
			end
		end
		assert(#bad == 0, table.concat(bad, ", ", 1, math.min(#bad, 8)))
	end)
end
