--!nocheck
-- Tests for server/Leaders: the player boards, all time and this week, kept in memory here.

local Leaders = require("../src/server/Leaders")
local Crews = require("../src/server/Crews")

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
		expectEq(rows[1].crew, nil, "no crew yet")
		-- Bo joins a crew: the tag goes on his rows at once (a new badge isn't held back).
		l:record(2, "Bo", "Bo Town", { power = 500, race_wins = 2, trophies = 3, level = 7 }, nil, { tag = "NITE", emblem = "🐺", color = "#8e24aa", name = "x" })
		l:refresh()
		local tagged = l:board("power", "all")[1].crew
		expectEq(tagged and tagged.tag, "NITE", "crew tag on the row")
		expectEq(tagged and tagged.name, nil, "only the badge is kept")
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

	test("leaders: the crews board ranks crews by their members combined, all time and this week", function()
		local now, week = 0, "2026-W42"
		local c = Crews.new({
			clock = function()
				return now
			end,
			newId = (function()
				local n = 0
				return function()
					n += 1
					return `crew{n}`
				end
			end)(),
			emblems = { "🏁", "🔥" },
			colors = { "#ff7043", "#1e88e5" },
			week = function()
				return week
			end,
		})
		local function who(name, level, power, wins, trophies)
			return { name = name, town = name .. "ville", level = level, power = power, wins = wins, trophies = trophies }
		end
		local a = c:create(1, who("Ann", 5, 300, 4, 9), { name = "Night Riders", tag = "NR", emblem = "🏁", color = "#ff7043", motto = "", minLevel = 1, joinMode = "open" })
		local b = c:create(2, who("Bo", 7, 500, 2, 3), { name = "Dust Devils", tag = "DD", emblem = "🔥", color = "#1e88e5", motto = "", minLevel = 1, joinMode = "open" })
		assert(a and b, "crews made")
		c:ask(3, who("Cy", 4, 250, 6, 1), a)
		-- All time: Night Riders 300 + 250 power beat Dust Devils' 500.
		local rows = Leaders.crews(c:browse(), "power", "all", week)
		expectEq(#rows, 2, "crew rows")
		expectEq(rows[1].tag, "NR", "first on power")
		expectEq(rows[1].value, 550, "members' power added up")
		expectEq(rows[1].members, 2, "members")
		expectEq(rows[1].place, 1, "place")
		expectEq(Leaders.crews(c:browse(), "level", "all", week)[1].value, 9, "levels added up")
		expectEq(Leaders.crews(c:browse(), "race_wins", "all", week)[1].value, 10, "wins added up")
		-- This week: nothing gained until members play on.
		expectEq(Leaders.crews(c:browse(), "race_wins", "week", week)[1].value, 0, "no gains yet")
		c:touch(2, who("Bo", 7, 500, 2, 3)) -- first seen this week
		c:touch(2, who("Bo", 8, 520, 5, 3))
		local wk = Leaders.crews(c:browse(), "race_wins", "week", week)
		expectEq(wk[1].tag, "DD", "first on this week's wins")
		expectEq(wk[1].value, 3, "wins gained this week")
		-- A new week starts everyone at nothing again.
		week = "2026-W43"
		expectEq(Leaders.crews(c:browse(), "race_wins", "week", week)[1].value, 0, "last week's gains don't count")
	end)
end
