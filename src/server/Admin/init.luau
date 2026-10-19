--!strict
-- The admin panel's server side: testing tools for Kegan's account only.
--
-- Who's an admin is decided here, by Roblox user id (never by name: anyone can take a display
-- name, and a username can change hands). Only an admin gets the panel at all: the server copies
-- its screen (Admin/Panel, a LocalScript kept in ServerScriptService where no client can read it)
-- into that player's own PlayerGui, with the AdminRemote it talks through. Nobody else's client
-- ever has the panel's code or the remote, and every call is still checked again here: the caller
-- must be an admin, the action one of the list below, each argument the right kind and in range.
--
-- Remote (in the admin's PlayerGui.CartopiaAdmin):
--   AdminRemote  RemoteFunction  client -> server: (op, target user id, ...) -> ok, result or why
--     "info"                         the players here, the cars, the server's numbers
--     "set"    target, field, value  coins / bucks (gems) / parts / xp / level to exactly value
--     "give"   target, field, amount adds amount (xp levels the town up as play would)
--     "car"    target, model         a car of that model in their garage
--     "crate"  target, count         free Gold Crates waiting in their Crate Depot
--     "visitor" target               the next visitor may come now
--     "rave"                         Rave Mode for everyone, as the DJ's button
--     "tp"     target, kind, value   moves target to the hub, a plot, or another player
--     "inspect" target               their save, summed up
--     "reset"  target, "RESET"       a brand new town in place of theirs (saved at once)
--     "kick"   target, reason        removes them from this server

local Admin = {}
Admin.__index = Admin

-- Kegan's account: kbergerun, shown in game as "kbergy", the experience's owner
-- (users.roblox.com/v1/users/122354997).
Admin.IDS = { [122354997] = true } :: { [number]: boolean }

Admin.FIELDS = { coins = true, bucks = true, parts = true, xp = true, level = true }
Admin.MAX = 1e12 -- more than any town will ever hold, and still exact in a double
Admin.MAX_LEVEL = 200
Admin.MAX_CRATES = 50

function Admin.isAdmin(userId: any): boolean
	return type(userId) == "number" and Admin.IDS[userId] == true
end

-- mods, as the server wires them up (init.server.luau); the tests pass stand-ins.
export type Mods = {
	towns: any,
	store: any,
	data: any,
	visitors: any,
	-- The player in this server with that id, or nil.
	player: (userId: number) -> any,
	players: () -> { any },
	-- Sends the town to its player's client and redraws it in the world.
	push: (player: any, force: boolean?) -> (),
	-- Writes the town to the DataStore now.
	save: (player: any) -> (),
	-- Where to stand: the hub, a plot (0..plots-1), or nil for a plot that doesn't exist.
	hub: () -> CFrame,
	plot: (i: number) -> CFrame?,
	plots: number,
	-- Starts Rave Mode as the admin's press of the DJ button would.
	rave: (player: any) -> (boolean, string?),
	-- The server's own numbers for the debug view.
	stats: () -> { [string]: any },
	now: () -> number,
	uid: () -> string,
}

export type Admin = typeof(setmetatable({} :: { mods: Mods, calls: { [number]: { n: number, at: number } } }, Admin))

function Admin.new(mods: Mods): Admin
	return setmetatable({ mods = mods, calls = {} }, Admin)
end

-- A whole number from lo to hi, or nil.
local function whole(v: any, lo: number, hi: number): number?
	if type(v) ~= "number" or v ~= v or v ~= math.floor(v) or v < lo or v > hi then
		return nil
	end
	return v
end

-- A burst of 20 calls, refilling 10 a second: enough for any clicking, not for a runaway loop.
function Admin._allow(self: Admin, userId: number): boolean
	local clock = os.clock()
	local b: { n: number, at: number } = self.calls[userId] or { n = 20, at = clock }
	b.n = math.min(20, b.n + (clock - b.at) * 10)
	b.at = clock
	self.calls[userId] = b
	if b.n < 1 then
		return false
	end
	b.n -= 1
	return true
end

-- Levels a town up through `xp` more points, as the store's addXp counts them (without the
-- level-up prizes: this is for testing, not a reward).
local function levelled(data: any, level: number, xp: number): (number, number)
	while level < Admin.MAX_LEVEL and xp >= data.xpToNext(level) do
		xp -= data.xpToNext(level)
		level += 1
	end
	return level, xp
end

-- One player's line in the panel.
function Admin._card(self: Admin, p: any): { [string]: any }
	local m = self.mods
	local out: { [string]: any } = { userId = p.UserId, name = p.Name, display = p.DisplayName }
	if m.towns:isOpen(p.UserId) then
		local s = m.towns:save(p.UserId)
		out.town = s.townName
		out.level, out.xp, out.coins, out.bucks, out.parts = s.level, s.xp, s.coins, s.bucks, s.parts
		out.cars = #(s.cars or {})
	end
	return out
end

-- Runs one call from `caller`. Returns ok, and the result or why not.
function Admin.run(self: Admin, caller: any, op: any, target: any, a: any, b: any): (boolean, any)
	local m = self.mods
	if not caller or not Admin.isAdmin(caller.UserId) then
		return false, "not allowed"
	end
	if not self:_allow(caller.UserId) then
		return false, "slow down"
	end
	if op == "info" then
		local list = {}
		for _, p in m.players() do
			table.insert(list, self:_card(p))
		end
		local cars = {}
		for _, c in m.data.CARS do
			table.insert(cars, { id = c.id, name = c.name, level = c.unlockLevel or 1 })
		end
		return true, { players = list, cars = cars, plots = m.plots, server = m.stats() }
	elseif op == "rave" then
		return m.rave(caller)
	end

	-- Everything else is done to one player in this server, whose town is open.
	local id = whole(target, 1, 2 ^ 53)
	local who = id and m.player(id)
	if not who then
		return false, "not here"
	end

	if op == "kick" then
		local reason = if type(a) == "string" and #a > 0 then string.sub(a, 1, 120) else "Removed by the game's owner."
		who:Kick(reason)
		return true, nil
	elseif op == "tp" then
		local character = who.Character
		if not character then
			return false, "no character"
		end
		local at: CFrame?
		if a == "hub" then
			at = m.hub()
		elseif a == "plot" then
			local i = whole(b, 0, m.plots - 1)
			at = if i then m.plot(i) else nil
		elseif a == "player" then
			local to = whole(b, 1, 2 ^ 53)
			local other = to and m.player(to)
			local root = other and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			at = if root then root.CFrame * CFrame.new(0, 0, 6) else nil
		end
		if not at then
			return false, "nowhere"
		end
		character:PivotTo(at + Vector3.new(0, 4, 0))
		return true, nil
	end

	if not m.towns:isOpen(id) then
		return false, "town not loaded"
	end
	local store = m.store.useGame
	if op == "inspect" then
		local s = m.towns:save(id)
		local count = function(t: any): number
			local n = 0
			for _ in t or {} do
				n += 1
			end
			return n
		end
		return true, {
			card = self:_card(who),
			buildings = count(s.buildings),
			roads = count(s.roads),
			cars = count(s.cars),
			trophies = s.trophies,
			racesWon = s.racesWon,
			tutorial = s.tutorial,
			freeCrates = count(s.freeCrates),
			updatedAt = s.updatedAt,
		}
	elseif op == "set" or op == "give" then
		if type(a) ~= "string" or not Admin.FIELDS[a] then
			return false, "bad field"
		end
		local v = whole(b, if op == "give" then -Admin.MAX else 0, Admin.MAX)
		if not v then
			return false, "bad amount"
		end
		local field, value = a, v
		m.towns:_with(id, function(s: any)
			if field == "level" then
				local level = math.clamp(if op == "set" then value else s.level + value, 1, Admin.MAX_LEVEL)
				store.setState({ level = level, xp = 0, updatedAt = m.now() })
			elseif field == "xp" then
				local level, xp = levelled(m.data, s.level, math.max(0, if op == "set" then value else s.xp + value))
				store.setState({ level = level, xp = xp, updatedAt = m.now() })
			else
				local next = math.clamp(if op == "set" then value else (s[field] or 0) + value, 0, Admin.MAX)
				store.setState({ [field] = next, updatedAt = m.now() })
			end
		end)
	elseif op == "car" then
		-- Only the cars in the game's list (carDef makes up a parked car for any other id).
		local def: any = nil
		for _, c in m.data.CARS do
			if c.id == a then
				def = c
			end
		end
		if not def then
			return false, "no such car"
		end
		m.towns:_with(id, function(s: any)
			local cars = table.clone(s.cars or {})
			table.insert(cars, { uid = `admin-{m.uid()}`, model = def.id, color = def.colors[1], upgrades = { engine = 0, turbo = 0, tires = 0, weight = 0 } })
			store.setState({ cars = cars, updatedAt = m.now() })
			s.toast(`{def.name} added to your garage!`)
		end)
	elseif op == "crate" then
		local n = whole(a, 1, Admin.MAX_CRATES)
		if not n then
			return false, "bad amount"
		end
		m.towns:_with(id, function(s: any)
			local free = table.clone(s.freeCrates or {})
			for _ = 1, n do
				-- An "arcade:" source opens a Gold Crate (game/cups.ts freeCrateOf).
				table.insert(free, `arcade:admin-{m.uid()}`)
			end
			store.setState({ freeCrates = free, updatedAt = m.now() })
		end)
	elseif op == "visitor" then
		local v = m.visitors
		local rec = v:_record(id)
		rec.lastAt, rec.n = 0, 0
		v.cur[id] = nil
	elseif op == "reset" then
		if a ~= "RESET" then
			return false, "not confirmed"
		end
		m.towns:close(id)
		m.towns:open(id, nil)
		m.save(who)
		m.push(who, true)
		return true, nil
	else
		return false, "unknown"
	end
	m.push(who, true)
	return true, nil
end

function Admin.forget(self: Admin, userId: number)
	self.calls[userId] = nil
end

-- Wires the panel up in Roblox: each admin who joins gets the panel and its remote in their own
-- PlayerGui, answered by run(). Everyone else gets nothing.
function Admin.start(self: Admin, Players: Players)
	local panel = script:FindFirstChild("Panel")
	local function give(player: Player)
		if not Admin.isAdmin(player.UserId) or not panel then
			return
		end
		local gui = player:WaitForChild("PlayerGui", 30)
		if not gui or gui:FindFirstChild("CartopiaAdmin") then
			return
		end
		local holder = Instance.new("ScreenGui")
		holder.Name = "CartopiaAdmin"
		holder.ResetOnSpawn = false
		holder.DisplayOrder = 50
		holder.IgnoreGuiInset = true
		local remote = Instance.new("RemoteFunction")
		remote.Name = "AdminRemote"
		remote.OnServerInvoke = function(caller: Player, op: any, target: any, a: any, b: any)
			-- Only the player this remote was made for, and only while they're an admin.
			if caller ~= player then
				return false, "not allowed"
			end
			local ran, ok, result = pcall(self.run, self, caller, op, target, a, b)
			if not ran then
				warn(`[Cartopia] admin {op}: {ok}`)
				return false, "error"
			end
			return ok, result
		end
		remote.Parent = holder
		panel:Clone().Parent = holder
		holder.Parent = gui
	end
	Players.PlayerAdded:Connect(give)
	for _, p in Players:GetPlayers() do
		task.spawn(give, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		self:forget(p.UserId)
	end)
end

return Admin
