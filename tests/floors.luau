--!nocheck
-- Slow check (about a minute with -O2): recomputes every referee floor in Luau and compares it with the
-- table generated from the web game. Run `luau -O2 tests/floors.luau` after changing Race physics.
local Race = require("../src/shared/Race")
local RaceFloors = require("../src/shared/RaceFloors")
local bad = 0
for pi = 1, Race.MAX_RACE_PI do
	local got = Race.computeRaceFloor(pi)
	if got ~= RaceFloors[pi] then
		bad += 1
		print(`PI {pi}: table {RaceFloors[pi]}, computed {got}`)
	end
end
print(`{Race.MAX_RACE_PI - bad} of {Race.MAX_RACE_PI} floors match`)
if bad > 0 then
	error("floors differ", 0)
end
