--!strict
-- The web game's lib/clubSet.ts track picker: which of the nightclub's tracks plays on a night,
-- the same for every player. String requires, so tests can run it with plain Luau.
local Js = require("./Game/__js") :: any

local ClubSet = {}

-- A little hash every player computes the same (clubSet.ts hash), 0..1.
function ClubSet.hash(a: number, b: number): number
	local h = Js.__bxor(Js.imul(Js.__bxor(a, 0x9e3779b9), 0x85ebca6b), Js.imul(b + 0x7f4a7c15, 0xc2b2ae35))
	h = Js.imul(Js.__bxor(h, Js.__ushr(h, 15)), 0x2c1b3c6d)
	h = Js.__bxor(h, Js.__ushr(h, 12))
	return (h % 4294967296) / 4294967296
end

-- The track (from 0, in clubGrooves.ts order) for a night (floor(wall ms / clock.DAY_MS)), of
-- count tracks: every track plays once in each round of nights, in a shuffled order, never the
-- same one twice in a row.
function ClubSet.trackOf(night: number, count: number): number
	local function order(r: number): { [number]: number }
		local o = {}
		for i = 0, count - 1 do
			o[i] = i
		end
		for i = count - 1, 1, -1 do
			local j = math.floor(ClubSet.hash(r, i) * (i + 1))
			o[i], o[j] = o[j], o[i]
		end
		return o
	end
	local r = math.floor(night / count)
	local o = order(r)
	if o[0] == order(r - 1)[count - 1] then
		o[0], o[1] = o[1], o[0]
	end
	return o[((night % count) + count) % count]
end

return ClubSet
