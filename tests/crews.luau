--!nocheck
-- Tests for server/Crews: starting, joining, requests, ranks, leaving and the browser.

local Crews = require("../src/server/Crews")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

local EMBLEMS = { "🏁", "🔥" }
local COLORS = { "#ff7043", "#1e88e5" }

local function make()
	local w = { now = 0, n = 0 }
	w.c = Crews.new({
		clock = function()
			return w.now
		end,
		newId = function()
			w.n += 1
			return `crew{w.n}`
		end,
		emblems = EMBLEMS,
		colors = COLORS,
	})
	return w
end

local function who(name, level, power)
	return { name = name, town = name .. "ville", level = level or 10, power = power or 100, wins = 1, trophies = 2 }
end

local function spec(over)
	local s = { name = "Night Riders", tag = "nr", emblem = "🏁", color = "#ff7043", motto = "Go fast", minLevel = 1, joinMode = "open" }
	for k, v in over or {} do
		s[k] = v
	end
	return s
end

return function(test)
	test("crews: starting one checks the name, tag and look, and names are taken once", function()
		local w = make()
		expectEq(select(2, w.c:create(1, who("Ann"), spec({ name = "ab" }))), "name", "too short")
		expectEq(select(2, w.c:create(1, who("Ann"), spec({ tag = "N-R" }))), "tag", "bad tag")
		expectEq(select(2, w.c:create(1, who("Ann"), spec({ emblem = "💩" }))), "emblem", "not on the list")
		expectEq(select(2, w.c:create(1, who("Ann"), spec({ joinMode = "secret" }))), "mode", "join mode")
		local id = w.c:create(1, who("Ann"), spec())
		expectEq(id, "crew1", "started")
		local mine = w.c:mine(1)
		expectEq(mine.role, "leader", "leader")
		expectEq(mine.crew.tag, "NR", "tag upper-cased")
		expectEq(select(2, w.c:create(1, who("Ann"), spec({ name = "Other", tag = "OT" }))), "in a crew", "one crew")
		expectEq(select(2, w.c:create(2, who("Bo"), spec({ name = "night riders", tag = "BO" }))), "name taken", "name, any case")
		expectEq(select(2, w.c:create(2, who("Bo"), spec({ name = "Bo Crew", tag = "NR" }))), "tag taken", "tag")
		expectEq(w.c:mineId(2), nil, "a failed start leaves no claim")
		expectEq(w.c:create(2, who("Bo"), spec({ name = "Bo Crew", tag = "BO" })), "crew4", "a free name")
		local list = w.c:browse()
		expectEq(#list, 2, "both in the browser")
		expectEq(#w.c:browse("bo"), 1, "search")
		expectEq(w.c:badge(1).tag, "NR", "badge")
	end)

	test("crews: open crews take anyone at the level; full and closed ones don't", function()
		local w = make()
		local id = w.c:create(1, who("Ann"), spec({ minLevel = 5 }))
		expectEq(select(2, w.c:ask(2, who("Bo", 3), id)), "level", "too low")
		expectEq(w.c:ask(2, who("Bo", 5), id), "joined", "joined")
		expectEq(w.c:mine(2).role, "member", "a member")
		expectEq(w.c:browse()[1].members, 2, "counted")
		for i = 3, Crews.CAP do
			expectEq(w.c:ask(i, who(`P{i}`), id), "joined", `joined {i}`)
		end
		expectEq(select(2, w.c:ask(99, who("Late"), id)), "full", "full")
		w.c:settings(1, spec({ joinMode = "closed" }))
		w.c:leave(3)
		expectEq(select(2, w.c:ask(99, who("Late"), id)), "closed", "closed")
	end)

	test("crews: requests wait for a Leader or Co-Leader", function()
		local w = make()
		local id = w.c:create(1, who("Ann"), spec({ joinMode = "request" }))
		local other = w.c:create(5, who("Eve"), spec({ name = "Eve Crew", tag = "EV", joinMode = "request" }))
		expectEq(w.c:ask(2, who("Bo"), id), "requested", "asked")
		expectEq(w.c:ask(2, who("Bo"), other), "requested", "asked another")
		expectEq(#w.c:asked(2), 2, "two out")
		w.c:ask(3, who("Cy"), id)
		w.c:ask(4, who("Di"), id)
		expectEq(select(2, w.c:respond(3, 2, true)), "rank", "only officers")
		expectEq(w.c:respond(1, 2, true), "joined", "accepted")
		expectEq(w.c:mine(2).role, "member", "in")
		expectEq(#w.c:asked(2), 0, "other requests go")
		expectEq(w.c:crew(other).requests["2"], nil, "gone from the other crew")
		expectEq(w.c:respond(1, 3, false), "declined", "declined")
		expectEq(w.c:mineId(3), nil, "not in")
		w.c:ask(6, who("Fy"), other)
		w.c:respond(5, 6, true)
		expectEq(w.c:respond(1, 4, true), "joined", "Di joins")
		expectEq(w.c:respond(1, 4, true), "gone", "answered already")
		w.c:cancel(4, id)
		for i = 1, Crews.MAX_ASKS do
			w.c:create(100 + i, who(`L{i}`), spec({ name = `Crew {i}`, tag = `C{i}`, joinMode = "request" }))
		end
		local n = 0
		for _, row in w.c:browse() do
			if row.joinMode == "request" and row.id ~= id and row.id ~= other then
				local r, why = w.c:ask(50, who("Many"), row.id)
				if r then
					n += 1
				else
					expectEq(why, "asks", "five at most")
				end
			end
		end
		expectEq(n, Crews.MAX_ASKS, "five out")
	end)

	test("crews: ranks, removing and handing over the lead", function()
		local w = make()
		local id = w.c:create(1, who("Ann"), spec())
		w.now = 1
		w.c:ask(2, who("Bo"), id)
		w.now = 2
		w.c:ask(3, who("Cy"), id)
		w.now = 3
		w.c:ask(4, who("Di"), id)
		expectEq(w.c:setRank(2, 3, "co_leader"), false, "only the Leader sets ranks")
		expectEq(w.c:setRank(1, 3, "co_leader"), true, "Cy is Co-Leader")
		expectEq(w.c:kick(3, 1), false, "nobody removes the Leader")
		expectEq(w.c:kick(2, 4), false, "Members can't remove")
		expectEq(w.c:kick(3, 4), true, "a Co-Leader removes a Member")
		expectEq(w.c:mineId(4), nil, "removed")
		expectEq(w.c:setRank(1, 2, "leader"), true, "handed over")
		expectEq(w.c:mine(1).role, "co_leader", "old Leader is Co-Leader")
		expectEq(w.c:mine(2).role, "leader", "new Leader")
		-- The Leader leaves: the longest-serving Co-Leader takes over (Ann, from the start).
		w.c:leave(2)
		expectEq(w.c:mine(1).role, "leader", "Ann leads again")
		w.c:leave(1)
		expectEq(w.c:mine(3).role, "leader", "then the last one")
		w.c:leave(3)
		expectEq(w.c:crew(id), nil, "the last one out closes it")
		expectEq(#w.c:browse(), 0, "gone from the browser")
		expectEq(w.c:create(9, who("Zed"), spec()), "crew2", "its name is free again")
	end)

	test("crews: members' numbers add up in the browser", function()
		local w = make()
		local id = w.c:create(1, who("Ann", 10, 100), spec())
		w.c:ask(2, who("Bo", 5, 50), id)
		expectEq(w.c:browse()[1].power, 150, "power")
		w.c:touch(2, who("Bo", 6, 80))
		local row = w.c:browse()[1]
		expectEq(row.power, 180, "after Bo's garage grew")
		expectEq(row.levels, 16, "levels")
		expectEq(w.c:crew(id).members["2"].level, 6, "kept")
	end)
end
