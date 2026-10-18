--!nocheck
-- Tests for Roblox's per-player rules (shared/Policy, server/Policies) and the crate gate they
-- put on the server's crates (Crates): paid crates refused where paid random items are restricted,
-- free crates still open, and the strict rules whenever PolicyService can't answer.

local Policy = require("../src/shared/Policy")
local Policies = require("../src/server/Policies")
local Crates = require("../src/server/Crates")
local Towns = require("../src/server/Towns")
local Js = require("../src/shared/Game/__js")

local NOW = 1760000000000
Js.setClock(function()
	return NOW
end)

local G = "../src/shared/Game/"

local function fakePlayer(id)
	local attrs = {}
	return {
		UserId = id,
		Name = `p{id}`,
		Parent = true,
		SetAttribute = function(_, k, v)
			attrs[k] = v
		end,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
	}
end

local function service(answer)
	local calls = 0
	return {
		calls = function()
			return calls
		end,
		GetPolicyInfoForPlayerAsync = function(_, _player)
			calls += 1
			if type(answer) == "function" then
				return answer(calls)
			end
			return answer
		end,
	}
end

local function setup(rules)
	local store = require(G .. "store")
	local towns = Towns.new(store, function()
		return NOW
	end)
	towns:open(1, nil)
	towns:_with(1, function()
		store.useGame.setState({ coins = 1000000, bucks = 100000, level = 30, freeCrates = { "gift:1" } })
	end)
	local crates = Crates.new(towns, store, require(G .. "crates"), function(_, free)
		return Policy.canOpenCrate(rules, free)
	end)
	return crates, towns
end

return function(test)
	test("policy: strict until known, and any missing answer counts as strict", function()
		local r = Policy.strict()
		assert(r.paidRandomRestricted and not r.sharing and not r.ready, "strict")
		local partial = Policy.fromInfo({})
		assert(partial.paidRandomRestricted and not partial.sharing, "missing fields are strict")
		local open = Policy.fromInfo({ ArePaidRandomItemsRestricted = false, IsContentSharingAllowed = true, AllowedExternalLinkReferences = { "Discord" } })
		assert(not open.paidRandomRestricted and open.sharing and Policy.canLink(open, "Discord") and not Policy.canLink(open, "YouTube"), "open")
		assert(Policy.canOpenCrate(r, true) and not Policy.canOpenCrate(r, false), "free only when strict")
	end)

	test("policy: rules survive the trip through Player attributes", function()
		local p = fakePlayer(1)
		assert(Policy.fromAttributes(function(k) return p:GetAttribute(k) end).paidRandomRestricted, "nothing set: strict")
		local r = Policy.fromInfo({ ArePaidRandomItemsRestricted = false, IsContentSharingAllowed = true, AllowedExternalLinkReferences = { "X", "Discord" } })
		for k, v in Policy.toAttributes(r) do
			p:SetAttribute(k, v)
		end
		local back = Policy.fromAttributes(function(k) return p:GetAttribute(k) end)
		assert(back.ready and not back.paidRandomRestricted and back.sharing and back.links.X and back.links.Discord, "round trip")
	end)

	test("policies: a failing PolicyService is retried, then the player keeps the strict rules", function()
		local svc = service(function()
			error("HTTP 500")
		end)
		local waits = 0
		local ps = Policies.new(svc, Policy, function()
			waits += 1
		end)
		local p = fakePlayer(7)
		local r = ps:load(p)
		assert(svc.calls() == 3 and waits == 2, `{svc.calls()} calls, {waits} waits`)
		assert(r.paidRandomRestricted and ps:get(7).paidRandomRestricted, "strict")
		assert(p:GetAttribute(Policy.ATTR.paidRandomRestricted) == true and p:GetAttribute(Policy.ATTR.ready) == false, "attributes strict")
	end)

	test("policies: an answer after a failure is used and copied to the player", function()
		local svc = service(function(n)
			if n == 1 then
				error("busy")
			end
			return { ArePaidRandomItemsRestricted = false }
		end)
		local ps = Policies.new(svc, Policy)
		local p = fakePlayer(8)
		ps:load(p)
		assert(not ps:get(8).paidRandomRestricted, "allowed")
		assert(p:GetAttribute(Policy.ATTR.paidRandomRestricted) == false and p:GetAttribute(Policy.ATTR.ready) == true, "attributes")
		ps:forget(8)
		assert(ps:get(8).paidRandomRestricted, "forgotten: strict")
	end)

	test("crates: restricted players can't buy crates, but free ones still open", function()
		local crates, towns = setup(Policy.fromInfo({ ArePaidRandomItemsRestricted = true }))
		local before = towns:snapshot(1).save
		for _, id in { "street", "garage", "gold", "diamond" } do
			for _, n in { 1, 10 } do
				local opens, why = crates:open(1, id, nil, n)
				assert(opens == nil and why == "paid crates restricted", `{id} x{n}: {why}`)
			end
		end
		assert(crates:open(1, "gold", "", 1) == nil, "an empty free source is a paid open")
		local after = towns:snapshot(1).save
		assert(after.coins == before.coins and after.bucks == before.bucks, "nothing charged")
		local opens, why = crates:open(1, "street", "gift:1", 1)
		assert(opens and #opens == 1, `free crate: {why}`)
		assert(opens[1].cost.coins == 0 and opens[1].cost.bucks == 0, "free")
	end)

	test("crates: players whose rules allow it buy crates as before", function()
		local crates = setup(Policy.fromInfo({ ArePaidRandomItemsRestricted = false }))
		local opens = assert(crates:open(1, "gold", nil, 10))
		assert(#opens == 10, `{#opens} opens`)
	end)

	test("crates: until the rules are known, paid crates are refused", function()
		local crates = setup(Policy.strict())
		local none, why = crates:open(1, "street", nil, 1)
		assert(none == nil and why == "paid crates restricted", tostring(why))
	end)
end
