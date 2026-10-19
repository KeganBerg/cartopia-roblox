--!nocheck
-- Tests for server/CrewParts: asking the crew for parts once a day, giving, and collecting.

local CrewParts = require("../src/server/CrewParts")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

local NOON = 1792411200 -- Monday 19 October 2026, 12:00 UTC

local function make()
	local w = { now = NOON }
	w.p = CrewParts.new({
		clock = function()
			return w.now
		end,
	})
	return w
end

return function(test)
	test("crew parts: one ask a day, in one crew", function()
		local w = make()
		expectEq(w.p:ask(1, "c", "Ana"), "asked", "asked")
		expectEq(w.p:ask(1, "c", "Ana"), "already", "once a day")
		expectEq(w.p:ask(1, "d", "Ana"), "already", "not in another crew either")
		expectEq(#w.p:list("d", 2), 0, "nothing left in the other crew")
		local list = w.p:list("c", 2)
		expectEq(#list, 1, "listed")
		expectEq(list[1].id, 1, "who asked")
		expectEq(list[1].want, CrewParts.ASK, "how many")
		w.now += 86400
		expectEq(#w.p:list("c", 2), 0, "a new day")
		expectEq(w.p:ask(1, "c", "Ana"), "asked", "asks again the next day")
	end)

	test("crew parts: giving one at a time, within the limits", function()
		local w = make()
		w.p:ask(1, "c", "Ana")
		expectEq(w.p:give(1, "c", 1), "own", "not to yourself")
		expectEq(w.p:give(2, "c", 9), "no", "no such request")
		for i = 1, CrewParts.GIVE_MAX do
			expectEq(w.p:give(2, "c", 1), "given", `part {i}`)
		end
		expectEq(w.p:give(2, "c", 1), "limit", "5 to one request")
		expectEq(w.p:list("c", 2)[1].mine, CrewParts.GIVE_MAX, "mine")
		for _ = 1, 5 do
			w.p:give(3, "c", 1)
		end
		expectEq(w.p:list("c", 3)[1].given, CrewParts.ASK, "filled")
		expectEq(w.p:give(4, "c", 1), "full", "already filled")
		-- 20 a day in all.
		for a = 10, 14 do
			w.p:ask(a, "c", "x")
			for _ = 1, 5 do
				w.p:give(5, "c", a)
			end
		end
		expectEq(w.p:give(5, "c", 14), "limit", "20 a day")
	end)

	test("crew parts: what's given is collected once, for a week", function()
		local w = make()
		w.p:ask(1, "c", "Ana")
		expectEq(w.p:claim(1), 0, "nothing yet")
		w.p:give(2, "c", 1)
		w.p:give(2, "c", 1)
		expectEq(w.p:claim(1), 2, "two parts")
		expectEq(w.p:claim(1), 0, "once")
		w.p:give(3, "c", 1)
		w.now += 86400
		w.p:ask(1, "c", "Ana")
		w.p:give(3, "c", 1)
		expectEq(w.p:claim(1), 2, "yesterday's late one and today's")
		w.now += 8 * 86400
		w.p:ask(1, "c", "Ana")
		expectEq(w.p:claim(1), 0, "old asks are dropped")
	end)
end
