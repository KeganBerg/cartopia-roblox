--!nocheck
-- Tests for server/Invites: who invited a new player, and the gems both get at the level.

local Invites = require("../src/server/Invites")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

return function(test)
	test("invites: only a new player from someone else's invite counts, once", function()
		local inv = Invites.new(nil)
		expectEq(inv:arrive(2, 1, false), false, "an old player")
		expectEq(inv:arrive(2, 2, true), false, "their own invite")
		expectEq(inv:arrive(2, 0, true), false, "no invite")
		expectEq(inv:arrive(2, 1, true), true, "a new player")
		expectEq(inv:arrive(2, 3, true), false, "only the first inviter")
		expectEq(inv:arrive(4, 1, true), true, "another")
		expectEq(inv:stats(1).joined, 2, "joined")
		expectEq(inv:stats(3).joined, 0, "the second inviter gets nothing")
	end)

	test("invites: both get the gems once, at the level", function()
		local inv = Invites.new(nil)
		inv:arrive(2, 1, true)
		expectEq(inv:reached(2, Invites.INVITE_LEVEL - 1), 0, "not yet")
		expectEq(inv:claim(1), 0, "nothing waiting yet")
		expectEq(inv:reached(2, Invites.INVITE_LEVEL), Invites.INVITE_GEMS, "the new player's gems")
		expectEq(inv:reached(2, Invites.INVITE_LEVEL + 3), 0, "only once")
		expectEq(inv:reached(5, 20), 0, "nobody invited them")
		local st = inv:stats(1)
		expectEq(st.reached, 1, "reached")
		expectEq(st.waiting, Invites.INVITE_GEMS, "waiting for the inviter")
		expectEq(inv:claim(1), Invites.INVITE_GEMS, "the inviter's gems")
		expectEq(inv:claim(1), 0, "collected once")
		expectEq(inv:stats(1).gems, Invites.INVITE_GEMS, "earned in all")
	end)
end
