--!nocheck
-- Tests for live events on the server (server/LiveEvents) and the admin panel's calls to them:
-- only the owner starts or ends them, each call is checked as the web's admin_live_start is,
-- a change reaches the store and every other server, and the list carries on without either.

local LiveEvents = require("../src/server/LiveEvents")
local Admin = require("../src/server/Admin")

local OWNER = 122354997
local OTHER = 555

local function setup(opts)
	opts = opts or {}
	local clock = { t = 1760000000000 }
	local box = { stored = {}, sent = {}, shown = nil, storeDown = opts.storeDown }
	local live = LiveEvents.new({
		now = function()
			return clock.t
		end,
		random = function()
			return 0.5
		end,
		update = function(fn)
			if box.storeDown then
				return nil
			end
			box.stored = fn(box.stored)
			return box.stored
		end,
		read = function()
			if box.storeDown then
				return nil
			end
			return box.stored
		end,
		publish = function(change)
			table.insert(box.sent, change)
		end,
		show = function(list)
			box.shown = list
		end,
		filter = function(_, text)
			return (string.gsub(text, "badword", "#######"))
		end,
	})
	return live, clock, box
end

local function running(list, now)
	local out = {}
	for _, e in list do
		if e.from <= now and now < e.to then
			table.insert(out, e)
		end
	end
	return out
end

local function admin(live)
	return Admin.new({ live = live, now = function()
		return 0
	end })
end

return function(test)
	test("live: only the owner may start or end events from the panel", function()
		local live, clock = setup()
		local a = admin(live)
		local me, them = { UserId = OWNER }, { UserId = OTHER }
		local ok, why = a:run(them, "liveStart", "banner", 15, { message = "Hello" })
		assert(not ok and why == "not allowed")
		assert(not a:run(them, "liveEnd", nil))
		assert(#running(live:current(), clock.t) == 0)
		ok = a:run(me, "liveStart", "banner", 15, { message = "Hello" })
		assert(ok)
		local ok2, info = a:run(me, "live")
		assert(ok2 and #info.list == 1 and info.list[1].payload.message == "Hello")
		local ok3, n = a:run(me, "liveEnd", nil)
		assert(ok3 and n == 1)
	end)

	test("live: each start is checked like admin_live_start", function()
		local live = setup()
		assert(not live:start(OWNER, "party", 15, {}), "unknown kind")
		assert(not live:start(OWNER, "night", 0, {}), "minutes 1..1440")
		assert(not live:start(OWNER, "night", 1441, {}))
		assert(not live:start(OWNER, "night", 1.5, {}))
		assert(not live:start(OWNER, "night", "15", {}))
		local _, why = live:start(OWNER, "banner", 15, { message = "   " })
		assert(why == "empty", "a banner needs a message")
		_, why = live:start(OWNER, "weather", 15, { kind = "lava" })
		assert(why == "bad weather")
		_, why = live:start(OWNER, "banner", 15, { message = "a badword here" })
		assert(why == "not allowed words", "the text filter has the last word")
		local id = live:start(OWNER, "banner", 15, { message = "  " .. string.rep("x", 200) .. "  " })
		assert(id)
		local e = live:current()[1]
		assert(#e.payload.message == 120 and e.payload.by == "admin", "trimmed to 120")
		id = live:start(OWNER, "weather", 30, { kind = "snow", message = "Snow day!", extra = "dropped" })
		assert(id)
		local w = live:current()[2]
		assert(w.payload.kind == "snow" and w.payload.message == "Snow day!" and w.payload.extra == nil)
		assert(w.to - w.from == 30 * 60000)
	end)

	test("live: a new event ends the running one of its kind; night and day end each other", function()
		local live, clock = setup()
		live:start(OWNER, "night", 60, {})
		live:start(OWNER, "banner", 60, { message = "Hi" })
		clock.t += 5000
		live:start(OWNER, "day", 15, {})
		local now = running(live:current(), clock.t)
		local kinds = {}
		for _, e in now do
			kinds[e.kind] = (kinds[e.kind] or 0) + 1
		end
		assert(kinds.day == 1 and kinds.night == nil and kinds.banner == 1)
		clock.t += 1000
		live:start(OWNER, "banner", 15, { message = "Second" })
		local banners = 0
		for _, e in running(live:current(), clock.t) do
			if e.kind == "banner" then
				banners += 1
				assert(e.payload.message == "Second")
			end
		end
		assert(banners == 1)
	end)

	test("live: ending one kind or all, and ended ones linger only briefly", function()
		local live, clock = setup()
		live:start(OWNER, "night", 60, {})
		live:start(OWNER, "banner", 60, { message = "Hi" })
		clock.t += 2000
		assert(live:finish("banner") == 1)
		assert(#running(live:current(), clock.t) == 1)
		assert(#live:current() == 2, "the ended banner stays a moment")
		assert(live:finish(nil) == 1)
		assert(live:finish("nonsense") == nil)
		clock.t += LiveEvents.KEEP_MS + 1
		live:refresh()
		assert(#live:current() == 0)
	end)

	test("live: every change reaches the store and every other server", function()
		local live, clock, box = setup()
		local other, _, otherBox = setup()
		live:start(OWNER, "banner", 15, { message = "Everyone!" })
		assert(#box.stored == 1 and #box.sent == 1 and box.shown and #box.shown == 1)
		-- The other server hears it through MessagingService.
		other:received(box.sent[1])
		assert(#otherBox.shown == 1 and otherBox.shown[1].payload.message == "Everyone!")
		other:received(box.sent[1])
		assert(#other:current() == 1, "a repeat changes nothing")
		clock.t += 1000
		live:finish(nil)
		other:received(box.sent[2])
		assert(#running(other:current(), clock.t) == 0)
		-- Junk from the topic is ignored.
		other:received({ op = "start", e = { id = 1, kind = "nuke", from = 0, to = 1e15 } })
		other:received("nope")
		assert(#other:current() == 1)
		-- A server that starts later reads the store.
		local late, _, lateBox = setup()
		lateBox.stored = box.stored
		late:refresh()
		assert(#late:current() == 1 and #running(late:current(), clock.t) == 0)
	end)

	test("live: without the DataStore the events still run here", function()
		local live, clock, box = setup({ storeDown = true })
		assert(live:start(OWNER, "night", 15, {}))
		live:refresh()
		assert(#running(live:current(), clock.t) == 1, "kept in memory")
		assert(#box.sent == 1, "still sent to other servers")
		box.storeDown = false
		live:refresh()
		assert(#running(live:current(), clock.t) == 1, "the store missed it, so it carries on")
	end)
end
