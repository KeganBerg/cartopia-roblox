--!nocheck
-- Tests for server/Mail: help notes, gifts and postcards, their daily limits, and collecting.

local Mail = require("../src/server/Mail")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

local function new()
	local t = { now = 1000, day = "2026-10-19" }
	t.mail = Mail.new(nil, function()
		return t.now
	end, function()
		return t.day
	end)
	return t
end

return function(test)
	test("mail: a gift a friend a day, ten a day, never to yourself", function()
		local t = new()
		local m = t.mail
		expectEq(m:gift(1, "Ann", "Annville", 1, "fuel"), "no", "to yourself")
		expectEq(m:gift(1, "Ann", "Annville", 2, "gems"), "no", "not a gift")
		expectEq(m:gift(1, "Ann", "Annville", 2, "fuel"), "sent", "first gift")
		expectEq(m:gift(1, "Ann", "Annville", 2, "parts"), "already", "second gift to the same friend")
		for i = 3, 11 do
			expectEq(m:gift(1, "Ann", "Annville", i, "parts"), "sent", `gift {i}`)
		end
		expectEq(m:gift(1, "Ann", "Annville", 12, "fuel"), "limit", "11th gift today")
		expectEq(m:sentToday(1).gifts["2"], true, "sent list")
		t.day = "2026-10-20"
		expectEq(m:gift(1, "Ann", "Annville", 2, "fuel"), "sent", "a new day")
		expectEq(m:sentToday(1).gifts["3"], nil, "yesterday's list is gone")
		local box = m:inbox(2)
		expectEq(#box.notes, 2, "two gifts waiting")
		expectEq(box.notes[2].amount, Mail.GIFTS.fuel, "15 fuel")
		expectEq(box.notes[1].name, "Ann", "who from")
	end)

	test("mail: help notes, one a town a day", function()
		local t = new()
		local m = t.mail
		expectEq(m:help(1, "Ann", "Annville", 2), true, "first help")
		expectEq(m:help(1, "Ann", "Annville", 2), false, "same town again today")
		expectEq(m:help(1, "Ann", "Annville", 1), false, "own town")
		expectEq(m:inbox(2).notes[1].kind, "help", "a help note")
		expectEq(m:inbox(2).notes[1].amount, Mail.HELP_FUEL, "10 fuel")
	end)

	test("mail: collecting pays ten a day, oldest first", function()
		local t = new()
		local m = t.mail
		for i = 1, 12 do
			m:gift(100 + i, "P", "T", 2, if i == 1 then "parts" else "fuel")
		end
		expectEq(m:count(2), 12, "count")
		local got = m:claim(2)
		expectEq(got.count, 10, "ten paid")
		expectEq(got.parts, 5, "the oldest (parts) paid first")
		expectEq(got.fuel, 9 * 15, "fuel")
		expectEq(got.left, 2, "two wait")
		got = m:claim(2)
		expectEq(got.count, 0, "nothing more today")
		expectEq(got.left, 2, "still waiting")
		t.day = "2026-10-20"
		got = m:claim(2)
		expectEq(got.count, 2, "tomorrow")
		expectEq(m:count(2), 0, "empty")
	end)

	test("mail: postcards, set pictures and messages, seen once looked at", function()
		local t = new()
		local m = t.mail
		expectEq(m:postcard(1, "Ann", "Annville", 2, "moon", 0), "no", "not a picture")
		expectEq(m:postcard(1, "Ann", "Annville", 2, "neon", 8), "no", "not a message")
		expectEq(m:postcard(1, "Ann", "Annville", 2, "neon", 1.5), "no", "not a whole message")
		expectEq(m:postcard(1, "Ann", "Annville", 2, "neon", 3), "sent", "sent")
		expectEq(m:postcard(1, "Ann", "Annville", 2, "beach", 1), "already", "one a day")
		expectEq(m:count(2), 1, "a new card")
		m:see(2)
		expectEq(m:count(2), 0, "seen")
		expectEq(#m:inbox(2).cards, 1, "still in the mail")
		t.now += 15 * 86400
		expectEq(#m:inbox(2).cards, 0, "gone after 14 days")
	end)
end
