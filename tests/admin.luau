--!nocheck
-- Tests for the admin panel's server side (server/Admin): only the owner's user id may use it,
-- each call is checked, and the changes land in the town the way the panel says.

local Admin = require("../src/server/Admin")
local Towns = require("../src/server/Towns")
local Visitors = require("../src/server/Visitors")
local Js = require("../src/shared/Game/__js")

local G = "../src/shared/Game/"
local data = require(G .. "data")

local OWNER = 122354997
local OTHER = 555

local function player(id, name)
	return { UserId = id, Name = name, DisplayName = name, kicked = nil, Kick = function(self, why)
		self.kicked = why
	end }
end

local function setup()
	local clock = { t = 1760000000000 }
	Js.setClock(function()
		return clock.t
	end)
	local store = require(G .. "store")
	local towns = Towns.new(store, function()
		return clock.t
	end)
	local me, them = player(OWNER, "kbergerun"), player(OTHER, "someone")
	local here = { [OWNER] = me, [OTHER] = them }
	towns:open(OWNER, nil)
	towns:open(OTHER, nil)
	local visitors = Visitors.new(towns, { store = store, data = data, random = math.random, now = function()
		return clock.t
	end })
	local pushed, saved, raved, n = {}, {}, 0, 0
	local admin = Admin.new({
		towns = towns,
		store = store,
		data = data,
		visitors = visitors,
		player = function(id)
			return here[id]
		end,
		players = function()
			return { me, them }
		end,
		push = function(p)
			pushed[p.UserId] = (pushed[p.UserId] or 0) + 1
		end,
		save = function(p)
			saved[p.UserId] = true
		end,
		hub = function()
			return nil
		end,
		plot = function()
			return nil
		end,
		plots = 12,
		rave = function()
			raved += 1
			return true, nil
		end,
		stats = function()
			return { players = 2 }
		end,
		now = function()
			return clock.t
		end,
		uid = function()
			n += 1
			return tostring(n)
		end,
	})
	return admin, towns, me, them, { pushed = pushed, saved = saved, raved = function()
		return raved
	end }, visitors
end

return function(test)
	test("admin: only the owner's user id may use the panel, whatever the name", function()
		local admin, towns, me, them = setup()
		assert(Admin.isAdmin(OWNER) and not Admin.isAdmin(OTHER) and not Admin.isAdmin("122354997"))
		local before = towns:save(OTHER).coins
		local ok, why = admin:run(them, "give", OTHER, "coins", 1000000)
		assert(not ok and why == "not allowed")
		local fake = player(OTHER, "kbergy")
		ok = admin:run(fake, "give", OTHER, "coins", 1000000)
		assert(not ok, "a display name of kbergy is not enough")
		assert(towns:save(OTHER).coins == before)
		assert(admin:run(me, "info") == true)
	end)

	test("admin: give and set money, gems, parts, level and xp", function()
		local admin, towns, me, _, seen = setup()
		local s = towns:save(OWNER)
		assert(admin:run(me, "give", OWNER, "coins", 1000000))
		assert(towns:save(OWNER).coins == s.coins + 1000000)
		assert(admin:run(me, "set", OWNER, "bucks", 777))
		assert(towns:save(OWNER).bucks == 777)
		assert(admin:run(me, "give", OWNER, "parts", -1000000))
		assert(towns:save(OWNER).parts == 0, "never below zero")
		assert(admin:run(me, "set", OWNER, "level", 12))
		assert(towns:save(OWNER).level == 12 and towns:save(OWNER).xp == 0)
		assert(admin:run(me, "give", OWNER, "xp", data.xpToNext(12) + 5))
		assert(towns:save(OWNER).level == 13 and towns:save(OWNER).xp == 5, "xp levels up")
		assert(seen.pushed[OWNER] >= 5, "the client hears each change")
		-- Checked: unknown fields, amounts that aren't whole numbers or are out of range.
		assert(not admin:run(me, "set", OWNER, "trophies", 5))
		assert(not admin:run(me, "set", OWNER, "coins", 1.5))
		assert(not admin:run(me, "set", OWNER, "coins", -1))
		assert(not admin:run(me, "set", OWNER, "coins", 0 / 0))
		assert(not admin:run(me, "set", OWNER, "coins", math.huge))
		assert(not admin:run(me, "set", OWNER, "coins", "5"))
		assert(not admin:run(me, "nuke", OWNER))
		assert(not admin:run(me, "give", 999, "coins", 5), "only players in this server")
	end)

	test("admin: cars, free crates, visitors and the rave", function()
		local admin, towns, me, them, seen, visitors = setup()
		local cars = #towns:save(OTHER).cars
		assert(admin:run(me, "car", OTHER, "pip"))
		local after = towns:save(OTHER).cars
		assert(#after == cars + 1 and after[#after].model == "pip")
		assert(not admin:run(me, "car", OTHER, "no-such-car"))
		assert(admin:run(me, "crate", OWNER, 3))
		assert(#towns:save(OWNER).freeCrates == 3)
		assert(not admin:run(me, "crate", OWNER, 500))
		visitors:_record(OWNER).lastAt = 1760000000000
		assert(admin:run(me, "visitor", OWNER))
		assert(visitors:_record(OWNER).lastAt == 0)
		assert(admin:run(me, "rave") and seen.raved() == 1)
		assert(not them.kicked)
	end)

	test("admin: inspect, reset (only when confirmed) and kick", function()
		local admin, towns, me, them, seen = setup()
		admin:run(me, "set", OTHER, "coins", 123456)
		local ok, card = admin:run(me, "inspect", OTHER)
		assert(ok and card.card.coins == 123456 and card.buildings > 0)
		assert(not admin:run(me, "reset", OTHER), "needs RESET")
		assert(towns:save(OTHER).coins == 123456)
		assert(admin:run(me, "reset", OTHER, "RESET"))
		assert(towns:save(OTHER).coins ~= 123456 and seen.saved[OTHER], "a new town, saved at once")
		assert(admin:run(me, "kick", OTHER, "bye"))
		assert(them.kicked == "bye")
	end)
end
