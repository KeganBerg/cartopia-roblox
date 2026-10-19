--!nocheck
-- Tests for server/Leaders: the player boards, all time and this week, kept in memory here.

local Leaders = require("../src/server/Leaders")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

return function(test)
	test("leaders: boards rank players best first, with their towns", function()
		local now, week = 0, "2026-W42"
		local l = Leaders.new(nil, function()
			return now
		end, function()
			return week
		end)
		l:record(1, "Ann", "Annville", { power = 300, race_wins = 4, trophies = 9, level = 5 })
		l:record(2, "Bo", "Bo Town", { power = 500, race_wins = 2, trophies = 3, level = 7 })
		local rows = l:board("power", "all")
		expectEq(#rows, 2, "rows")
		expectEq(rows[1].name, "Bo", "first on power")
		expectEq(rows[1].town, "Bo Town", "town")
		expectEq(rows[2].value, 300, "Ann's power")
		expectEq(l:board("race_wins", "all")[1].name, "Ann", "first on wins")
		-- Nobody gained anything yet this week.
		expectEq(#l:board("trophies", "week"), 0, "week before gains")
		-- Ann wins two races: the week board shows the gain, after the once-a-minute limit.
		l:record(1, "Ann", "Annville", { power = 300, race_wins = 6, trophies = 11, level = 5 })
		l:refresh()
		expectEq(#l:board("race_wins", "week"), 0, "limited to once a minute")
		now = 61
		l:record(1, "Ann", "Annville", { power = 300, race_wins = 6, trophies = 11, level = 5 })
		l:refresh()
		local wk = l:board("race_wins", "week")
		expectEq(#wk, 1, "week rows")
		expectEq(wk[1].value, 2, "wins this week")
		-- A player off the board still sees their own number.
		local _, mine = l:board("race_wins", "week", 3, { power = 10, race_wins = 1, trophies = 0, level = 1 })
		expectEq(mine, 0, "a new player's week starts at nothing")
		local _, mineAll = l:board("level", "all", 3, { power = 10, race_wins = 1, trophies = 0, level = 2 })
		expectEq(mineAll, 2, "own level")
		local _, onBoard = l:board("power", "all", 2, { power = 500, race_wins = 2, trophies = 3, level = 7 })
		expectEq(onBoard, nil, "no extra row when already on the board")
	end)
end
