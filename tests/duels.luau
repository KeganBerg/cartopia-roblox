--!nocheck
-- Tests for server/Duels: live drag race challenges, answers, positions passed on, and finishes.

local Duels = require("../src/server/Duels")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

-- Duels with a clock, a list of what each player was sent, and players 1, 2 and 3 here.
local function make()
	local w = { now = 0, sent = {}, here = { [1] = true, [2] = true, [3] = true }, onWait = nil }
	w.d = Duels.new({
		clock = function()
			return w.now
		end,
		send = function(userId, event, payload)
			table.insert(w.sent, { to = userId, event = event, payload = payload })
		end,
		card = function(userId)
			return { name = `P{userId}`, pi = userId * 100, model = "pip" }
		end,
		here = function(userId)
			return w.here[userId] == true
		end,
		wait = function(s)
			w.now += s
			if w.onWait then
				w.onWait()
			end
		end,
	})
	-- The last message of a kind a player was sent.
	function w.last(userId, event)
		for i = #w.sent, 1, -1 do
			local m = w.sent[i]
			if m.to == userId and m.event == event then
				return m.payload
			end
		end
		return nil
	end
	return w
end

return function(test)
	test("duels: a challenge waits in the other's bell, and runs out", function()
		local w = make()
		local id = w.d:challenge(1, 2)
		expectEq(type(id), "string", "challenge id")
		local bell = w.last(2, "invites")
		expectEq(#bell, 1, "in their bell")
		expectEq(bell[1].name, "P1", "with who sent it")
		expectEq(bell[1].left, Duels.INVITE, "seconds left")
		expectEq(select(2, w.d:challenge(1, 1)), "no", "not yourself")
		w.here[3] = nil
		expectEq(select(2, w.d:challenge(1, 3)), "not here", "only players here")
		w.now = Duels.INVITE + 1
		expectEq(#w.d:invitesFor(2), 0, "ran out")
		expectEq(select(2, w.d:answer(2, id, true)), "expired", "too late to say yes")
	end)

	test("duels: a new challenge replaces your last; no means a short wait", function()
		local w = make()
		local first = w.d:challenge(1, 2)
		w.d:challenge(1, 3)
		expectEq(#w.d:invitesFor(2), 0, "the first one went")
		expectEq(#w.d:invitesFor(3), 1, "the new one waits")
		local again = w.d:challenge(1, 2)
		expectEq(first ~= again, true, "a fresh id")
		expectEq(select(2, w.d:answer(2, again, false)), "declined", "said no")
		expectEq(w.last(1, "declined").id, again, "the challenger hears")
		expectEq(select(2, w.d:challenge(1, 2)), "wait", "can't ask again straight away")
		local list = w.d:others(1, { 1, 2, 3 })
		expectEq(#list, 2, "the others here")
		expectEq(list[1].id, 3, "fastest first")
		expectEq(list[2].wait, true, "said no a moment ago")
		w.now = Duels.COOLDOWN + 1
		expectEq(type(w.d:challenge(1, 2)), "string", "after the wait")
		expectEq(w.d:others(1, { 2 })[1].asked, true, "asked")
		w.d:cancel(1)
		expectEq(#w.d:invitesFor(2), 0, "called off")
	end)

	test("duels: yes starts the race for both, and positions go to the other", function()
		local w = make()
		local id = w.d:challenge(1, 2)
		w.d:challenge(3, 2)
		expectEq(w.d:answer(2, id, true), id, "race id")
		expectEq(w.last(1, "go").vs, 2, "challenger told")
		expectEq(w.last(2, "go").vs, 1, "racer told")
		expectEq(w.last(2, "go").card.name, "P1", "with the other's card")
		expectEq(#w.d:invitesFor(2), 0, "the rest of the bell clears")
		local rid, vs = w.d:racing(1)
		expectEq(rid, id, "racing")
		expectEq(vs, 2, "against")
		expectEq(select(2, w.d:challenge(3, 1)), "racing", "busy")
		expectEq(w.d:others(3, { 1, 2 })[1].closed, true, "shown busy")
		w.d:relay(1, { t = 1, dist = 12.5, speed = 20, burning = true })
		local pos = w.last(2, "pos")
		expectEq(pos.dist, 12.5, "position passed on")
		expectEq(pos.burning, true, "boost passed on")
		w.d:relay(1, { t = 0 / 0, dist = 1 })
		expectEq(w.last(2, "pos").dist, 12.5, "nonsense dropped")
		for _ = 1, Duels.RELAY_RATE + 5 do
			w.d:relay(1, { t = 2, dist = 50 })
		end
		local n = 0
		for _, m in w.sent do
			if m.to == 2 and m.event == "pos" then
				n += 1
			end
		end
		expectEq(n, Duels.RELAY_RATE, "kept to the rate")
		w.d:relay(3, { t = 1, dist = 1 })
		expectEq(w.last(1, "pos"), nil, "nobody else's")
	end)

	test("duels: each finish waits for the other's, and a no-show loses", function()
		local w = make()
		local id = w.d:challenge(1, 2)
		w.d:answer(2, id, true)
		-- 2 crosses the line while 1 waits.
		w.onWait = function()
			if w.now >= 1 then
				w.onWait = nil
				expectEq(w.d:finish(2, 9.5), 9.2, "theirs, already in")
			end
		end
		expectEq(w.d:finish(1, 9.2), 9.5, "mine waited for theirs")
		expectEq(w.last(2, "finished").t, 9.2, "told of the other's time")
		expectEq(w.d:racing(1), nil, "done")
		expectEq(w.d.races[id], nil, "race gone")

		local w2 = make()
		local id2 = w2.d:challenge(1, 2)
		w2.d:answer(2, id2, true)
		expectEq(w2.d:finish(1, 10), math.huge, "they never finished")
		expectEq(w2.now >= Duels.WAIT, true, "waited the whole time")
		expectEq(w2.d:finish(2, 12), 10, "the late one still sees mine")
	end)

	test("duels: leaving calls the race off for the other", function()
		local w = make()
		local id = w.d:challenge(1, 2)
		w.d:challenge(3, 1)
		w.d:answer(2, id, true)
		w.d:leave(2)
		expectEq(w.last(1, "off").id, id, "the other hears")
		expectEq(w.d:racing(2), nil, "out of it")
		expectEq(w.d:finish(1, 8), math.huge, "a win by the other leaving")
		w.d:challenge(3, 1)
		w.d:leave(3)
		expectEq(#w.last(1, "invites"), 0, "their challenge goes")
	end)

	test("duels: a race nobody finished is over after a while", function()
		local w = make()
		w.d:answer(2, w.d:challenge(1, 2), true)
		w.now = Duels.LONGEST + 1
		expectEq(w.d:racing(1), nil, "over")
		expectEq(w.d:racing(2), nil, "for both")
		expectEq(type(w.d:challenge(2, 1)), "string", "free to race again")
	end)
end
