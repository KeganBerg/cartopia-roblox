--!nocheck
-- Tests for the Speedway's life (client/SpeedwayLife): the web game's grandstand and fans
-- (scene/speedwayCrowd.ts, converted with the three.js stand-in) must seat the same fans at the
-- same seats and hang their arms the same way as the web game does with the real three.js
-- (tests/SpeedwayGolden.luau, from tools/gen-speedway-golden.mjs).

local G = "../src/shared/Game/"

local function near(a: number, b: number, what: string)
	assert(math.abs(a - b) < 1e-7, `{what}: got {a}, want {b}`)
end

return function(test)
	local crowd = require(G .. "scene_speedwayCrowd")
	local layout = require(G .. "scene_speedwayLayout")
	local Golden = require("./SpeedwayGolden")

	test("speedway seats and fans match the web game at every level", function()
		for _, want in Golden.stands do
			local got = crowd.speedwayStands(want.lvl, want.k)
			local tag = `level {want.lvl}, k {want.k}`
			assert(#got.seats == want.seats, `{tag}: {#got.seats} seats, want {want.seats}`)
			assert(#got.aisles == want.aisles, `{tag}: {#got.aisles} aisle steps, want {want.aisles}`)
			assert(#got.fans == #want.fans, `{tag}: {#got.fans} fans, want {#want.fans}`)
			for i, f in want.fans do
				assert(got.fans[i] == f, `{tag}: fan {i} at seat {got.fans[i]}, want {f}`)
			end
			local rows = {}
			local n = 0
			for _, s in got.seats do
				if not rows[s.row] then
					rows[s.row] = true
					n += 1
				end
			end
			assert(n == want.rows, `{tag}: {n} rows, want {want.rows}`)
			for _, p in want.picks do
				local s = got.seats[p.i + 1]
				near(s.a, p.a, `{tag} seat {p.i} angle`)
				near(s.r, p.r, `{tag} seat {p.i} radius`)
				near(s.y, p.y, `{tag} seat {p.i} height`)
				assert(s.row == p.row, `{tag} seat {p.i} row`)
				local m = crowd.seatMatrix(s, 1, 1)
				for j, e in p.m do
					near(m.elements[j], e, `{tag} seat {p.i} matrix[{j - 1}]`)
				end
			end
		end
	end)

	test("the upper deck opens at level 7", function()
		assert(not layout.deckAt(6) and layout.deckAt(7), "deckAt")
		assert(#crowd.speedwayStands(7, 1).seats > #crowd.speedwayStands(6, 1).seats, "no deck seats at level 7")
	end)

	test("fans' arms hang and cheer as in the web game", function()
		for _, want in Golden.arms do
			local m = crowd.armMatrix(want.side, want.cheer, want.wave)
			for j, e in want.m do
				near(m.elements[j], e, `arm side {want.side} cheer {want.cheer} wave {want.wave} [{j - 1}]`)
			end
		end
		near(crowd.BODY.shoulderY, Golden.BODY.shoulderY, "shoulder height")
		near(crowd.BODY.at, Golden.BODY.at, "where fans stand")
		near(crowd.SEAT_IN, Golden.SEAT_IN, "SEAT_IN")
	end)
end
