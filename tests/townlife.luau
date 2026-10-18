--!nocheck
-- Tests for the town's life on the client (TownLife): the web game's traffic sim and walk graph,
-- converted, driving cars and townspeople round a starter town.

local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")
local G = "../src/shared/Game/"

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

return function(test)
	local store = require(G .. "store")
	local lualib = require(G .. "lualib_bundle")
	local towns = Towns.new(store, function()
		return NOW
	end)
	towns:open(1, nil)
	local save = towns:snapshot(1).save

	test("traffic drives the starter town's cars round its roads", function()
		local sim = require(G .. "scene_traffic_sim")
		local placement = require(G .. "placement")
		local traffic = lualib.__TS__New(sim.Traffic)
		traffic:setTown(save.roads, save.buildings, placement.turnOf)
		local specs = {}
		for _, c in save.cars do
			table.insert(specs, { uid = c.uid, len = 0.8, wid = 0.4, cruise = 1.5, stalled = false })
		end
		traffic:setCars(specs, 10)
		local start = {}
		for _ = 1, 30 do
			traffic:step(1 / 30)
		end
		traffic.agents:forEach(function(_, a, uid)
			start[uid] = { a.x, a.z }
		end)
		for _ = 1, 600 do
			traffic:step(1 / 30)
		end
		local n, moved = 0, 0
		traffic.agents:forEach(function(_, a, uid)
			n += 1
			assert(a.x == a.x and a.z == a.z and a.yaw == a.yaw, `{uid} has no position`)
			local s = start[uid]
			if s and math.abs(a.x - s[1]) + math.abs(a.z - s[2]) > 0.5 then
				moved += 1
			end
		end)
		assert(n == #save.cars, `{n} cars on the road, want {#save.cars}`)
		assert(moved > 0, "no car moved")
	end)

	test("townspeople find a way along the sidewalks", function()
		local walk = require(G .. "walkGraph")
		local g = walk.buildWalkGraph(lualib.__TS__New(lualib.Set, save.roads), save.buildings, save.land)
		local homes = {}
		for i, n in g.nodes do
			if n.kind == "b" then
				table.insert(homes, i - 1)
			end
		end
		assert(#homes >= 2, "no buildings in the walk graph")
		-- From the first building, most of the others can be walked to.
		local reached = 0
		for i = 2, #homes do
			local route = walk.findPath(g, homes[1], homes[i])
			if route then
				reached += 1
				local steps = walk.stepsFor(g, route, g.nodes[homes[1] + 1].center)
				assert(#steps > 1, "a route with no steps")
			end
		end
		assert(reached >= (#homes - 1) / 2, `only {reached} of {#homes - 1} buildings reachable`)
	end)
end
