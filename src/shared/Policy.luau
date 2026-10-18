--!strict
-- Roblox's per-player rules (PolicyService:GetPolicyInfoForPlayerAsync), in one place for the
-- server and the client. The server asks Roblox once a player joins (server/Policies) and copies
-- the answer onto the Player as attributes, so the client's menus show exactly what the server
-- will allow. Until the answer is in, or when Roblox can't be reached, every rule is the strict
-- one: no paid crates, no outside links, no sharing.
--
-- What each rule covers in Cartopia:
--   paidRandomRestricted  Crates bought with coins or gems (both can come from Robux gem packs,
--                         bucksPacks coinGems) can't be opened. Free crates (cup prizes, gifts) can.
--   links                 The outside sites a share or "follow us" link may name, e.g. "Discord"
--                         (AllowedExternalLinkReferences). Roblox now always sends an empty list,
--                         so in practice no outside link is ever shown; shares stay inside Roblox.
--   sharing               Whether the player may share things they made, like a race snapshot or
--                         a challenge link (IsContentSharingAllowed).
--   paidTrading           Whether paid items can be traded between players (IsPaidItemTradingAllowed).

local Policy = {}

export type Rules = {
	ready: boolean,
	paidRandomRestricted: boolean,
	links: { [string]: boolean },
	sharing: boolean,
	paidTrading: boolean,
}

-- The rules while nothing is known.
function Policy.strict(): Rules
	return { ready = false, paidRandomRestricted = true, links = {}, sharing = false, paidTrading = false }
end

-- The rules from a PolicyService answer (any field missing counts as the strict one).
function Policy.fromInfo(info: any): Rules
	if type(info) ~= "table" then
		return Policy.strict()
	end
	local links = {}
	if type(info.AllowedExternalLinkReferences) == "table" then
		for _, name in info.AllowedExternalLinkReferences do
			if type(name) == "string" then
				links[name] = true
			end
		end
	end
	return {
		ready = true,
		paidRandomRestricted = info.ArePaidRandomItemsRestricted ~= false,
		links = links,
		sharing = info.IsContentSharingAllowed == true,
		paidTrading = info.IsPaidItemTradingAllowed == true,
	}
end

-- Player attributes the server sets (server/Policies) and the client reads.
Policy.ATTR = {
	ready = "PolicyReady",
	paidRandomRestricted = "PaidRandomRestricted",
	links = "PolicyLinks",
	sharing = "PolicySharing",
	paidTrading = "PolicyPaidTrading",
}

function Policy.toAttributes(r: Rules): { [string]: any }
	local names = {}
	for name in r.links do
		table.insert(names, name)
	end
	table.sort(names)
	return {
		[Policy.ATTR.ready] = r.ready,
		[Policy.ATTR.paidRandomRestricted] = r.paidRandomRestricted,
		[Policy.ATTR.links] = table.concat(names, ","),
		[Policy.ATTR.sharing] = r.sharing,
		[Policy.ATTR.paidTrading] = r.paidTrading,
	}
end

-- The rules as attributes say (`get` reads one attribute, e.g. player:GetAttribute).
function Policy.fromAttributes(get: (string) -> any): Rules
	if get(Policy.ATTR.ready) ~= true then
		return Policy.strict()
	end
	local links = {}
	local list = get(Policy.ATTR.links)
	if type(list) == "string" then
		for name in list:gmatch("[^,]+") do
			links[name] = true
		end
	end
	return {
		ready = true,
		paidRandomRestricted = get(Policy.ATTR.paidRandomRestricted) ~= false,
		links = links,
		sharing = get(Policy.ATTR.sharing) == true,
		paidTrading = get(Policy.ATTR.paidTrading) == true,
	}
end

-- Whether a crate may be opened: paid opens need paid random items allowed; free ones always can.
function Policy.canOpenCrate(r: Rules, free: boolean): boolean
	return free or not r.paidRandomRestricted
end

-- Whether a link to an outside site (as PolicyService names it, e.g. "Discord") may be shown.
function Policy.canLink(r: Rules, site: string): boolean
	return r.links[site] == true
end

-- Whether the player may share something they made (a race snapshot, a challenge link).
function Policy.canShare(r: Rules): boolean
	return r.sharing
end

return Policy
