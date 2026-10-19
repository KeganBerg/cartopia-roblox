--!strict
-- Bringing a town over from the web game. The player gets a one-time code in the web game's
-- Settings (Play on Roblox) and types it into Settings here; this server trades it with the web
-- game's database (Supabase rpc roblox_claim, web migration 0119_roblox_link.sql) for their saved
-- town and the packs they paid for there.
--
-- Roblox's rules don't let things bought off Roblox unlock anything here, so only progress earned
-- by playing comes over: each paid pack's gems, coins and parts are taken back out (stopping at 0,
-- as the web does for a refunded pack) and its car is left behind. Whatever the player bought here
-- with Robux stays theirs: their pack cars, their purchase count, and at least the gems they had.

local WebLink = {}

-- The web game's database. The publishable key is the same one the web game ships in its pages:
-- it can only call what the database lets anyone call (roblox_claim needs a live code).
WebLink.URL = "https://pagxmjtkatpofidqkdto.supabase.co/rest/v1/rpc/roblox_claim"
WebLink.KEY = "sb_publishable_mvjpQtNT10OeVVc6XDgK3A_Hv34_YLT"

-- The code's letters (web roblox_link_code): no I, O, 0 or 1.
local ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

-- The code as typed, cleaned up (spaces and dashes dropped, capitals), or nil when it can't be one.
function WebLink.clean(raw: any): string?
	if type(raw) ~= "string" or #raw > 40 then
		return nil
	end
	local code = raw:upper():gsub("[%s%-]", "")
	if #code ~= 8 then
		return nil
	end
	for i = 1, 8 do
		if not ABC:find(code:sub(i, i), 1, true) then
			return nil
		end
	end
	return code
end

local function num(v: any): number
	return if type(v) == "number" and v == v then v else 0
end

local function isPack(uid: any): boolean
	return type(uid) == "string" and uid:sub(1, 3) == "pk-"
end

-- The town to open here: the web town without its paid packs, with this player's Robux buys kept.
-- web: the web save. paid: its packs { seq, bucks, coins, parts, car? }. here: the town they have
-- here now (nil for none).
function WebLink.strip(web: any, paid: { any }, here: any?): any
	local save = table.clone(web)
	local gems, coins, parts = 0, 0, 0
	local packCars: { [string]: boolean } = {}
	for _, p in paid do
		gems += num(p.bucks)
		coins += num(p.coins)
		parts += num(p.parts)
		if p.car then
			packCars[`pk-{num(p.seq)}`] = true
		end
	end
	save.bucks = math.max(num(web.bucks) - gems, 0)
	save.coins = math.max(num(web.coins) - coins, 0)
	save.parts = math.max(num(web.parts) - parts, 0)
	local cars = {}
	for _, c in (if type(web.cars) == "table" then web.cars else {}) :: { any } do
		if type(c) == "table" and not packCars[c.uid] then
			table.insert(cars, c)
		end
	end
	-- Web admin powers never come over.
	save.admin = nil
	-- Robux buys made here: the receipts count from this town's purchase number.
	save.purchases = if here then here.purchases else nil
	if here and num(here.purchases) > 0 then
		local have: { [string]: boolean } = {}
		for _, c in cars do
			have[c.uid] = true
		end
		for _, c in (if type(here.cars) == "table" then here.cars else {}) :: { any } do
			if type(c) == "table" and isPack(c.uid) and not have[c.uid] then
				table.insert(cars, c)
			end
		end
		save.bucks = math.max(save.bucks, num(here.bucks))
	end
	save.cars = cars
	local race = save.raceCar
	if race ~= nil then
		local found = false
		for _, c in cars do
			if c.uid == race then
				found = true
			end
		end
		if not found then
			save.raceCar = nil
		end
	end
	return save
end

export type Http = {
	RequestAsync: (self: any, req: any) -> any,
	JSONEncode: (self: any, v: any) -> string,
	JSONDecode: (self: any, s: string) -> any,
}

-- Trades a code for { state, paid }, or nil and why: "code" (wrong, used or expired), "other"
-- (that web account is linked to another Roblox player) or "offline" (couldn't reach the web game).
function WebLink.claim(http: Http, code: string, userId: number): (any?, string?)
	local ok, res = pcall(http.RequestAsync, http, {
		Url = WebLink.URL,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json", apikey = WebLink.KEY },
		Body = http:JSONEncode({ p_code = code, p_roblox_user = userId }),
	})
	if not ok or type(res) ~= "table" or not res.Success then
		return nil, "offline"
	end
	local decoded, body = pcall(http.JSONDecode, http, res.Body)
	if not decoded or type(body) ~= "table" then
		return nil, "offline"
	end
	if body.error then
		return nil, if body.error == "other" then "other" else "code"
	end
	if type(body.state) ~= "table" then
		return nil, "code"
	end
	return { state = body.state, paid = if type(body.paid) == "table" then body.paid else {} }, nil
end

return WebLink
