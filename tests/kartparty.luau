--!nocheck
-- Tests for kart parties (server/KartParty): opening, joining and dealing a live kart race between
-- players in the server, passing their race messages on, and settling and paying the places. And
-- the converted web link (Shared.Game.lib_kartNet) that keeps two players' races in step.

local KartParty = require("../src/server/KartParty")
local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

local G = "../src/shared/Game/"
local store = require(G .. "store")
local data = require(G .. "data")
local kart = require(G .. "kart")
local kartNet = require(G .. "lib_kartNet")
local L = require(G .. "lualib_bundle")

local function rng(seed)
	local x = seed
	local function nextNumber()
		x = (x * 1103515245 + 12345) % 2147483648
		return x / 2147483648
	end
	return {
		NextNumber = function(_)
			return nextNumber()
		end,
		NextInteger = function(_, lo, hi)
			return lo + math.floor(nextNumber() * (hi - lo + 1))
		end,
	}
end

-- Three players' towns, a party desk, what it sent, and its clock and timers.
local function setup()
	local towns = Towns.new(store, function()
		return NOW
	end)
	for id = 1, 3 do
		towns:open(id, nil)
	end
	local t = 0
	local timers = {}
	local sent = {}
	local paid = {}
	local parties = KartParty.new(towns, {
		store = store,
		data = data,
		kart = kart,
		raceCar = require(G .. "raceCar"),
		boosts = require(G .. "boosts"),
		random = rng(5),
		clock = function()
			return t
		end,
		delay = function(s, fn)
			table.insert(timers, { at = t + s, fn = fn })
		end,
		send = function(userId, event, payload)
			table.insert(sent, { to = userId, event = event, payload = payload })
		end,
		name = function(userId)
			return `Racer {userId}`
		end,
		paid = function(userId)
			paid[userId] = true
		end,
	})
	local function wait(s)
		t += s
		for _, tm in table.clone(timers) do
			if tm.at <= t and not tm.ran then
				tm.ran = true
				tm.fn()
			end
		end
	end
	local function last(to, event)
		for i = #sent, 1, -1 do
			local m = sent[i]
			if m.to == to and m.event == event then
				return m.payload
			end
		end
		return nil
	end
	return parties, towns, sent, wait, last, paid
end

local function coins(towns, id)
	local c
	towns:_with(id, function(s)
		c = s.coins
	end)
	return c
end

return function(test)
	test("kart party: open, join, and only the host starts it with someone in", function()
		local parties = setup()
		local view = parties:open(1)
		assert(view and #view.players == 1 and view.host == 1)
		local _, why = parties:go(1)
		assert(why == "Wait for someone to join", tostring(why))
		local list = parties:list(2)
		assert(#list.open == 1 and list.open[1].id == view.id and list.mine == nil)
		assert(parties:join(2, view.id))
		assert(#parties:list(3).open == 1 and #parties:list(2).open == 0)
		local _, why2 = parties:go(2)
		assert(why2 == "not your party", tostring(why2))
		local _, why3 = parties:open(2)
		assert(why3 == "already in a party", tostring(why3))
	end)

	test("kart party: the host leaving calls it off; a guest leaving just drops off", function()
		local parties, _, _, _, last = setup()
		local view = parties:open(1)
		parties:join(2, view.id)
		parties:join(3, view.id)
		parties:leave(3)
		assert(#parties:list(1).mine.players == 2)
		parties:leave(1)
		local gone = last(2, "party")
		assert(gone and gone.gone and gone.why:find("called off"), "the guest wasn't told")
		assert(parties:list(2).mine == nil and #parties:list(2).open == 0)
	end)

	test("kart party: every player is dealt the same grid, each driving their own kart", function()
		local parties, _, sentList, _, last = setup()
		local view = parties:open(1)
		parties:join(2, view.id)
		assert(parties:go(1))
		local a, b = last(1, "setup"), last(2, "setup")
		assert(a and b and a.seed == b.seed and a.track == b.track and a.reverse == b.reverse)
		assert(#a.field == kart.FIELD, `{#a.field} karts`)
		-- Four AI at the front, the guest, then the host at the back; the host drives the AI.
		assert(a.live.me == 5 and b.live.me == 4, `{a.live.me} {b.live.me}`)
		for i = 1, 4 do
			assert(a.field[i].ai and a.live.owners[i] == "1")
		end
		assert(not a.field[5].ai and a.field[5].name == "Racer 2" and a.live.owners[5] == "2")
		assert(not a.field[6].ai and a.field[6].name == "Racer 1")
		assert(a.prize == KartParty.prize(a.field[5].pi) and b.prize == KartParty.prize(a.field[6].pi))
		-- The lights wait for both to be ready, or for START_WAIT.
		local function sentGo(p)
			for _, m in sentList do
				if m.to == p and m.event == "go" then
					return true
				end
			end
			return false
		end
		parties:ready(1)
		assert(not sentGo(1))
		parties:ready(2)
		assert(sentGo(1) and sentGo(2), "no lights once both were ready")
		assert(#parties:list(3).open == 0, "a dealt party still takes players")
	end)

	test("kart party: the lights go without a player who never gets ready", function()
		local parties, _, sentList, wait = setup()
		local view = parties:open(1)
		parties:join(2, view.id)
		parties:go(1)
		parties:ready(1)
		local function gos()
			local n = 0
			for _, m in sentList do
				if m.event == "go" then
					n += 1
				end
			end
			return n
		end
		assert(gos() == 0)
		wait(KartParty.START_WAIT)
		assert(gos() == 2, `{gos()} go messages`)
	end)

	test("kart party: race messages go to the others, stamped with who sent them", function()
		local parties, _, sentList = setup()
		local view = parties:open(1)
		parties:join(2, view.id)
		parties:join(3, view.id)
		parties:relay(1, "snap", { t = 1, k = {} })
		assert(#sentList > 0)
		local before = #sentList
		parties:relay(1, "snap", { t = 1, k = {} })
		assert(#sentList == before, "relayed before the race was dealt")
		parties:go(1)
		before = #sentList
		parties:relay(2, "snap", { from = "1", t = 1, k = {} })
		local to = {}
		for i = before + 1, #sentList do
			local m = sentList[i]
			assert(m.event == "snap" and m.payload.from == "2", "the sender wasn't stamped")
			to[m.to] = true
		end
		assert(to[1] and to[3] and not to[2])
		before = #sentList
		parties:relay(2, "crate", {})
		assert(#sentList == before, "an unknown message was passed on")
	end)

	test("kart party: places by time, the floor holds, and everyone is paid by place", function()
		local parties, towns, _, wait, last, paid = setup()
		local view = parties:open(1)
		parties:join(2, view.id)
		parties:join(3, view.id)
		parties:go(1)
		parties:ready(1)
		parties:ready(2)
		parties:ready(3)
		local prize1 = last(1, "setup").prize
		local c1, c2, c3 = coins(towns, 1), coins(towns, 2), coins(towns, 3)
		local _, why = parties:finish(2, 70)
		assert(why == "too quick", tostring(why))
		wait(80)
		-- 1 second can't be driven: it counts as the kart's floor, still the best time.
		assert(parties:finish(2, 1))
		assert(parties:finish(1, 75))
		assert(last(1, "verdict") == nil, "settled before everyone finished")
		assert(parties:finish(3, 78))
		local v1, v2, v3 = last(1, "verdict"), last(2, "verdict"), last(3, "verdict")
		assert(v2.place == 1 and v1.place == 2 and v3.place == 3 and v1.of == 3, `{v1.place} {v2.place} {v3.place}`)
		assert(v2.time == KartParty.kartFloor(last(2, "setup").field[5].pi), tostring(v2.time))
		assert(coins(towns, 2) > c2 and coins(towns, 1) > c1 and coins(towns, 3) > c3)
		assert(coins(towns, 1) - c1 <= prize1, "second paid more than the prize")
		assert(paid[1] and paid[2] and paid[3])
		assert(parties:list(1).mine == nil, "the party is still open after paying")
	end)

	test("kart party: a minute after the first finish it settles without the stragglers", function()
		local parties, _, _, wait, last = setup()
		local view = parties:open(1)
		parties:join(2, view.id)
		parties:go(1)
		parties:ready(1)
		parties:ready(2)
		wait(80)
		parties:finish(1, 75)
		assert(last(1, "verdict") == nil)
		wait(KartParty.SETTLE)
		local v1, v2 = last(1, "verdict"), last(2, "verdict")
		assert(v1 and v1.place == 1 and v2 and v2.place == 2)
	end)

	test("kart party: kartFloor matches the web's kart_floor", function()
		-- 0060_kart_floor_by_pi.sql: PI 1 43.0 s, PI 100 30.9 s.
		assert(math.abs(KartParty.kartFloor(1) - 43.0) < 0.1, tostring(KartParty.kartFloor(1)))
		assert(math.abs(KartParty.kartFloor(100) - 30.9) < 0.1, tostring(KartParty.kartFloor(100)))
	end)

	test("kart party: two players' races stay in step over the link", function()
		local parties, _, _, _, last = setup()
		local view = parties:open(1)
		parties:join(2, view.id)
		parties:go(1)
		local a, b = last(1, "setup"), last(2, "setup")
		-- Each game's race and link, joined by a channel that hands messages straight over.
		local games = {}
		local function game(s)
			local track = kart.buildTrack(kart.TRACKS[s.track + 1], s.reverse)
			local race = L.__TS__New(kart.KartRace, track, s.field, s.seed, s.rules)
			local on = {}
			local g = { race = race, on = on, me = s.live.me }
			local ch = {
				send = function(event, payload)
					for _, other in games do
						if other ~= g and other.on[event] then
							other.on[event](payload)
						end
					end
				end,
				on = function(event, cb)
					on[event] = cb
				end,
			}
			g.link = L.__TS__New(kartNet.KartLink, race, s.live.mine, s.live.owners, ch)
			table.insert(games, g)
			return g
		end
		local ga, gb = game(a), game(b)
		local inputs = {}
		for i = 1, kart.FIELD do
			inputs[i] = kart.idleInput()
		end
		for _ = 1, 120 * 20 do
			for _, g in games do
				local k = g.race.karts[g.me + 1]
				inputs[g.me + 1] = g.race:autoInput(k, g.race:order(), false)
				g.race:step(1 / 120, inputs, true)
				inputs[g.me + 1] = kart.idleInput()
				g.link:tick()
			end
		end
		-- The guest's kart, as the host's game shows it, is close behind where the guest has it.
		local mine, seen = gb.race.karts[gb.me + 1], ga.race.karts[gb.me + 1]
		local gap = math.sqrt((mine.x - seen.x) ^ 2 + (mine.z - seen.z) ^ 2)
		assert(mine.idx > 20 and gap < 8, `the guest's kart is {gap} away on the host's screen`)
		-- And an AI kart the host drives, on the guest's screen.
		local ai, aiSeen = ga.race.karts[1], gb.race.karts[1]
		local gap2 = math.sqrt((ai.x - aiSeen.x) ^ 2 + (ai.z - aiSeen.z) ^ 2)
		assert(gap2 < 8, `an AI kart is {gap2} away on the guest's screen`)
	end)
end
