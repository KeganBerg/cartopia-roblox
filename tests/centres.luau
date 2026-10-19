--!nocheck
-- Tests for the merged gas station's and car wash's layouts (src/shared/CentreLayout, a hand copy of
-- the web game's game/travelCenter.ts and game/washCenter.ts that client/CentreLife draws from):
-- every block shape must come out where the web code puts it (tests/CentresGolden.luau, from
-- tools/gen-centres-golden.mjs).

local function near(a: number, b: number, what: string)
	assert(math.abs(a - b) < 1e-6, `{what}: got {a}, want {b}`)
end

-- Every number in `want` (nested tables and lists) matches the same place in `got`.
local function same(got: any, want: any, what: string)
	if type(want) == "table" then
		assert(type(got) == "table", `{what}: got {got}, want a table`)
		local n = 0
		for k, v in want do
			n += 1
			same(got[k], v, `{what}.{k}`)
		end
		if #want > 0 then
			assert(#got == #want, `{what}: {#got} items, want {#want}`)
		end
	elseif type(want) == "number" then
		assert(type(got) == "number", `{what}: got {got}, want {want}`)
		near(got, want, what)
	else
		assert(got == want, `{what}: got {got}, want {want}`)
	end
end

return function(test)
	local CentreLayout = require("../src/shared/CentreLayout")
	local Golden = require("./CentresGolden")

	test("the travel stop's store, pumps and bays match the web game for every block", function()
		for _, want in Golden.travel do
			local got = CentreLayout.travel(want.sx, want.sz)
			same(got, want.t, `travel {want.sx}x{want.sz}`)
			assert((got.statue == nil) == (want.t.statue == nil), `travel {want.sx}x{want.sz}: statue`)
		end
	end)

	test("the car spa's tunnels, vacuum bays and door match the web game for every block", function()
		for _, want in Golden.wash do
			local got = CentreLayout.wash(want.sx, want.sz)
			same(got, want.t, `wash {want.sx}x{want.sz}`)
			near(CentreLayout.washDoor(got), want.door, `wash {want.sx}x{want.sz} door`)
		end
	end)
end
