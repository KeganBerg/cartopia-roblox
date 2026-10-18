--!strict
-- Crates, opened on the server: the web game rolls a guest's crate in the browser with the store's
-- own openCrate (game/store.ts, game/crates.ts), so the server runs that same function inside the
-- player's town. The level, price and free-crate checks, the roll, the pity counter and the prize
-- all come from the web game's code; the client only gets back what was opened, for the reveal.
--
-- Crates are paid random items, so a player whose Roblox rules restrict those
-- (PolicyService ArePaidRandomItemsRestricted, see shared/Policy and server/Policies) can only open
-- free crates. That check is here, before the store runs, whatever the client's menu showed.

local Crates = {}
Crates.__index = Crates

export type Crates = typeof(setmetatable({} :: { towns: any, store: any, crates: any, canOpen: (number, boolean) -> boolean }, Crates))

-- `canOpen(userId, free)` says whether the player's Roblox rules let them open a paid (free false)
-- or free crate; without one, every open is allowed (as in tests of the opening itself).
function Crates.new(towns: any, store: any, crates: any, canOpen: ((number, boolean) -> boolean)?): Crates
	return setmetatable({
		towns = towns,
		store = store,
		crates = crates,
		canOpen = canOpen or function()
			return true
		end,
	}, Crates)
end

-- Opens `count` (1 or 10) of crate `id`, or the free crate `free` (a source in the town's
-- freeCrates). Returns the opens, or nil and why (the town's "you need" note says what's short).
function Crates.open(self: Crates, userId: number, id: any, free: any, count: any): (any, string?)
	if type(id) ~= "string" or not self.crates.crateDef(id) then
		return nil, "no such crate"
	end
	if free ~= nil and type(free) ~= "string" then
		return nil, "bad free crate"
	end
	-- The store only treats a non-empty source as free (and then charges nothing).
	if not self.canOpen(userId, free ~= nil and free ~= "") then
		return nil, "paid crates restricted"
	end
	local n = if count == 10 and free == nil then 10 else 1
	return self.towns:_with(userId, function(s: any): (any, string?)
		s.tick(self.towns.now())
		local opened: any = nil
		-- No await happens on this path (no server opener is plugged in), so the promise has
		-- settled by the time openCrate returns.
		local promise = self.store.openCrate(id, free, n)
		promise["then"](promise, function(_, value)
			opened = value
		end)
		if opened == nil then
			return nil, "not opened"
		end
		return opened, nil
	end)
end

return Crates
