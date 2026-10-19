--!strict
-- Invite rewards, as the web game's lib/invite.ts and supabase/migrations/0112_invite_rewards.sql:
-- a new player who joins from a friend's invite is counted as theirs, and once the new player
-- reaches INVITE_LEVEL, each of them gets INVITE_GEMS gems (the new player straight away, the
-- inviter the next time this or any server checks their invites).
--
-- In Roblox the inviter is the game invite the new player joined from (Player:GetJoinData()'s
-- ReferredByPlayerId), and only a player with no save yet counts as new. Each player's record is
-- kept in "Invites_v1" and changed with UpdateAsync, so two servers can't both pay the same
-- reward. Without DataStores (tests, the emulator) everything lives in memory.

local Invites = {}
Invites.__index = Invites

Invites.INVITE_GEMS = 100
Invites.INVITE_LEVEL = 10
local STORE = "Invites_v1"

export type Backend = { plain: (name: string) -> any }

-- A player's record: by (who invited them), paid (their reward is done), and as an inviter:
-- joined, reached (of those, how many reached the level), gems (earned in all) and waiting
-- (earned, not collected yet).
export type Record = { by: number?, paid: boolean?, joined: number?, reached: number?, gems: number?, waiting: number? }

export type Invites = typeof(setmetatable(
	{} :: {
		backend: Backend?,
		mem: { [string]: any },
	},
	Invites
))

function Invites.new(backend: Backend?): Invites
	return setmetatable({ backend = backend, mem = {} }, Invites)
end

function Invites._get(self: Invites, userId: number): Record
	local b = self.backend
	if not b then
		return self.mem[tostring(userId)] or {}
	end
	local ok, v = pcall(function()
		return b.plain(STORE):GetAsync(tostring(userId))
	end)
	return if ok and type(v) == "table" then v else {}
end

-- Changes a record in one step. fn returns the new record, or nil to leave it. True when the
-- store took it (or nothing needed writing).
function Invites._update(self: Invites, userId: number, fn: (Record) -> Record?): boolean
	local b = self.backend
	if not b then
		local v = fn(table.clone(self.mem[tostring(userId)] or {}))
		if v ~= nil then
			self.mem[tostring(userId)] = v
		end
		return true
	end
	return (pcall(function()
		b.plain(STORE):UpdateAsync(tostring(userId), function(old: any): any
			return fn(if type(old) == "table" then old else {})
		end)
	end))
end

-- A player joined. ref: who invited them (0 or nil: nobody); new: they had no save until now.
-- Counts them as the inviter's once. True when it did.
function Invites.arrive(self: Invites, userId: number, ref: number?, new: boolean): boolean
	if not new or type(ref) ~= "number" or ref <= 0 or ref == userId or ref ~= math.floor(ref) then
		return false
	end
	local took = false
	local ok = self:_update(userId, function(r: Record): Record?
		took = false
		if r.by ~= nil then
			return nil
		end
		r.by = ref
		took = true
		return r
	end)
	if not (ok and took) then
		return false
	end
	self:_update(ref, function(r: Record): Record?
		r.joined = (r.joined or 0) + 1
		return r
	end)
	return true
end

-- A player is at `level`. The first time an invited player reaches INVITE_LEVEL, the inviter's
-- gems wait for them and the player's own are returned, for the server to pay now (else 0).
function Invites.reached(self: Invites, userId: number, level: number): number
	if level < Invites.INVITE_LEVEL then
		return 0
	end
	local by: number? = nil
	local ok = self:_update(userId, function(r: Record): Record?
		by = nil
		if r.by == nil or r.paid then
			return nil
		end
		r.paid = true
		by = r.by
		return r
	end)
	local inviter = by
	if not ok or inviter == nil then
		return 0
	end
	self:_update(inviter, function(r: Record): Record?
		r.reached = (r.reached or 0) + 1
		r.gems = (r.gems or 0) + Invites.INVITE_GEMS
		r.waiting = (r.waiting or 0) + Invites.INVITE_GEMS
		return r
	end)
	return Invites.INVITE_GEMS
end

-- Takes the gems waiting for an inviter, for the server to pay now (0 when none).
function Invites.claim(self: Invites, userId: number): number
	local got = 0
	local ok = self:_update(userId, function(r: Record): Record?
		got = r.waiting or 0
		if got <= 0 then
			return nil
		end
		r.waiting = 0
		return r
	end)
	return if ok then got else 0
end

-- What the Friends tab shows: { joined, reached, gems, waiting }.
function Invites.stats(self: Invites, userId: number): { joined: number, reached: number, gems: number, waiting: number }
	local r = self:_get(userId)
	return { joined = r.joined or 0, reached = r.reached or 0, gems = r.gems or 0, waiting = r.waiting or 0 }
end

return Invites
