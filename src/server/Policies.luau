--!strict
-- Each player's Roblox rules (shared/Policy), asked of PolicyService when they join. The call can
-- fail or be slow, so it's wrapped in pcall and retried a few times; until it answers (or if it
-- never does) the player gets the strict rules. The answer is copied onto the Player as
-- attributes for the client's menus; the server's own checks (server/Crates) use `rules`.

local Policies = {}
Policies.__index = Policies

export type Policies = typeof(setmetatable({} :: { service: any, policy: any, rules: { [number]: any }, wait: (number) -> () }, Policies))

local TRIES = 3
-- Roblox's warn, or print where there is none (the plain-Luau tests).
local log = (warn :: any) or print

-- `service` is PolicyService (or a stand-in with GetPolicyInfoForPlayerAsync), `policy` is
-- shared/Policy, and `wait` sleeps between tries (task.wait).
function Policies.new(service: any, policy: any, wait: ((number) -> ())?): Policies
	return setmetatable({ service = service, policy = policy, rules = {}, wait = wait or function() end }, Policies)
end

-- The rules for a player by user id: strict until their answer is in.
function Policies.get(self: Policies, userId: number): any
	return self.rules[userId] or self.policy.strict()
end

local function setAttributes(policy: any, player: any, r: any)
	for name, value in policy.toAttributes(r) do
		player:SetAttribute(name, value)
	end
end

-- Asks Roblox for a player's rules (yields). Keeps the strict ones if every try fails.
function Policies.load(self: Policies, player: any): any
	setAttributes(self.policy, player, self.policy.strict())
	for try = 1, TRIES do
		local ok, info = pcall(self.service.GetPolicyInfoForPlayerAsync, self.service, player)
		if ok and type(info) == "table" then
			local r = self.policy.fromInfo(info)
			if player.Parent then
				self.rules[player.UserId] = r
				setAttributes(self.policy, player, r)
			end
			return r
		end
		log(`[Cartopia] policy for {player.Name} (try {try}): {info}`)
		if not player.Parent or try == TRIES then
			break
		end
		self.wait(2 ^ try)
	end
	return self.policy.strict()
end

function Policies.forget(self: Policies, userId: number)
	self.rules[userId] = nil
end

return Policies
