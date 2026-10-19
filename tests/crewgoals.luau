--!nocheck
-- Tests for server/CrewGoals: a crew's weekly goal, the bank that points come out of, and chests.

local CrewGoals = require("../src/server/CrewGoals")
local R = CrewGoals.RULES

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

-- Monday 19 October 2026, 12:00 UTC.
local MONDAY = 1792411200

local function make()
	local w = { now = MONDAY }
	w.g = CrewGoals.new({
		clock = function()
			return w.now
		end,
	})
	return w
end

return function(test)
	test("crew goals: weeks start on Monday, UTC", function()
		local this, last = CrewGoals.weeks(MONDAY)
		expectEq(this, "2026-10-19", "this week")
		expectEq(last, "2026-10-12", "last week")
		expectEq(CrewGoals.weeks(MONDAY - 12 * 3600 - 1), "2026-10-12", "Sunday night is last week")
		expectEq(CrewGoals.weeks(MONDAY + 6 * 86400), "2026-10-19", "Sunday is still this week")
		expectEq(CrewGoals.left(MONDAY), 7 * 86400 - 12 * 3600, "until next Monday")
		expectEq(CrewGoals.target(1), R.perMember * R.minMembers, "a small crew counts as three")
		expectEq(CrewGoals.target(5), R.perMember * 5, "per member")
	end)

	test("crew goals: points come out of a bank that refills", function()
		local w = make()
		expectEq(w.g:add(1, "c", 3, 10, 2), 10 + 2 * R.race, "jobs and races")
		expectEq(w.g:add(1, "c", 3, 1000, 0), R.bankMax - 16, "the bank runs dry")
		expectEq(w.g:add(1, "c", 3, 5, 0), 0, "nothing left")
		w.now += 40
		expectEq(w.g:add(1, "c", 3, 50, 0), 40 // R.bankSeconds, "refilled with time")
		expectEq(w.g:add(2, "c", 3, -5, 0 / 0), 0, "nonsense counts nothing")
		local v = w.g:goal(1, "c", 3).current
		expectEq(v.mine, R.bankMax + 10, "my points")
		expectEq(v.points, R.bankMax + 10, "the crew's")
		expectEq(v.reached, false, "not there yet")
	end)

	test("crew goals: the target, capped shares and the chest", function()
		local w = make()
		-- Four members; one player's share counts up to the cap.
		for _ = 1, 3 do
			w.g:add(1, "c", 4, 240, 0)
			w.now += R.bankMax * R.bankSeconds
		end
		expectEq(w.g:goal(1, "c", 4).current.points, R.memberCap, "one share is capped")
		expectEq(select(2, w.g:open(1, CrewGoals.weeks(w.now))), "chest locked", "not reached yet")
		local _, reached = w.g:add(3, "c", 4, 0, 0)
		expectEq(reached, false, "no points, no change")
		local got, now = w.g:add(3, "c", 4, 0, 10)
		expectEq(got, 30, "races")
		expectEq(now, false, "still short")
		local _, hit = w.g:add(2, "c", 4, 0, 30)
		expectEq(hit, true, "this made it")
		local _, done = w.g:add(3, "c", 4, 5, 0)
		local v = w.g:goal(1, "c", 4).current
		expectEq(v.reached, true, "reached")
		expectEq(v.target, R.perMember * 4, "the target")
		expectEq(v.members[1].id, 1, "most points first")
		expectEq(done, false, "only counted once")
		local week = CrewGoals.weeks(w.now)
		expectEq(w.g:open(1, week), 1, "a chest")
		expectEq(select(2, w.g:open(1, week)), "chest opened", "once a week")
		expectEq(w.g:goal(1, "c", 3).current.opened, true, "shown opened")
		expectEq(select(2, w.g:open(2, "2020-01-06")), "chest expired", "old weeks are gone")
		expectEq(w.g:chests(1), 1, "counted")
		-- Someone who added fewer than the minimum gets none.
		w.g:add(4, "c", 4, 5, 0)
		expectEq(select(2, w.g:open(4, week)), "chest points", "too few points")
	end)

	test("crew goals: last week's chest waits a week, even in no crew", function()
		local w = make()
		w.g:add(1, "c", 1, 240, 0)
		w.now += R.bankMax * R.bankSeconds
		w.g:add(1, "c", 1, 120, 0)
		local week = CrewGoals.weeks(w.now)
		expectEq(w.g:goal(1, "c", 1).current.reached, true, "a crew of one counts as three")
		w.now += 7 * 86400
		local g = w.g:goal(1, nil, 0)
		expectEq(g.current, nil, "no crew now")
		expectEq(g.last and g.last.week, week, "last week's chest")
		expectEq(w.g:open(1, week), 1, "opened late")
		expectEq(w.g:goal(1, nil, 0).last, nil, "gone once opened")
		w.now += 7 * 86400
		expectEq(select(2, w.g:open(1, week)), "chest expired", "two weeks on")
	end)
end
