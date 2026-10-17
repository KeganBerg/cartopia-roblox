--!strict
-- Every player's town, run by the web game's own store (Shared.Game.store) on the server.
--
-- The store is one zustand-style singleton, and its actions only ever read and write that one state.
-- So each player keeps their own state table, and running an action swaps it in, calls the action,
-- and takes the new state back out. Actions never yield, so two players' turns can't interleave.
--
-- Clients only ask for actions on the ALLOWED list, with their arguments checked against a shape.
-- Results that come from somewhere the server doesn't run yet (races, crates, gem purchases)
-- stay off the list until the server works them out itself.

local Towns = {}
Towns.__index = Towns

-- Argument shapes per client-callable action: "string", "number", "boolean", "string?" (string or
-- nil), "table", "table?", or a list of allowed strings.
local S, N, B = "string", "number", "boolean"
local ALLOWED: { [string]: { any } } = {
	-- Town building
	placeBuilding = { S, N, N, "number?" },
	moveBuilding = { S, N, N, "number?" },
	paintRoad = { N, N },
	bulldoze = { N, N },
	pickStored = { S },
	placeStored = { S, N, N, "number?" },
	mergeBlock = { S, N },
	splitBlock = { S },
	rotateBlock = { S },
	buyPlot = { N, N },
	renameTown = { S },
	setLights = { "table" },
	setCityTheme = { "string?" },
	setBuildingTint = { S, "string?" },
	-- Jobs and businesses
	tapBuilding = { S },
	collectAll = { "boolean?" },
	upgradeBuilding = { S },
	assignCar = { S, "string?" },
	autoAssign = {},
	refillFuel = {},
	-- Cars
	buyCar = { S, S },
	upgradeCar = { S, { "engine", "turbo", "tires", "weight" } },
	sellCar = { S },
	fixFlat = { S, B },
	serviceCar = { S, { "tires", "gas", "can" } },
	paintCar = { S, "table" },
	paintPanels = { S, "table" },
	setTrim = { S, "table" },
	modCar = { S, S, "boolean?" },
	skinCar = { S, "string?" },
	skinMod = { S, S, "string?" },
	skinTracks = { S, "string?" },
	hatCar = { S, "table?" },
	savePreset = { N, S },
	clearPreset = { N },
	applyPreset = { N, S },
	tutorialStyle = { S, S, S },
	setRaceCar = { S },
	toggleShowcase = { S },
	equipCallCard = { "string?" },
	pickFlair = { { "trail", "cheer" }, S },
	-- Rewards and shop
	claimGoal = { S },
	claimTask = { { "daily", "weekly" }, S },
	claimEndless = { N },
	claimChest = { { "daily", "weekly" } },
	claimTier = { N },
	claimSet = { S },
	claimRoad = {},
	buyDeal = { S },
	-- Rescue yard
	startSearch = { S },
	revealPin = { N },
	fixTruck = {},
	abandonSearch = {},
	towHome = {},
	restoreCar = { S },
	rushRestore = { "number?" },
	collectRestored = { S, "number?" },
	upgradeTruck = {},
	scrapCar = { S },
	-- Tutorial
	setTutorial = { N },
	skipTutorial = { N },
}
Towns.ALLOWED = ALLOWED

local function argOk(want: any, v: any): boolean
	if type(want) == "table" then
		return table.find(want, v) ~= nil
	end
	local optional = string.sub(want, -1) == "?"
	if v == nil then
		return optional
	end
	local kind = if optional then string.sub(want, 1, -2) else want
	if kind == "number" then
		return type(v) == "number" and v == v and math.abs(v) ~= math.huge
	end
	if kind == "string" then
		return type(v) == "string" and #v <= 200
	end
	return type(v) == kind
end

-- Checks a client's request: a listed action, the right number of arguments, each the right kind.
function Towns.check(name: any, args: { any }, n: number): (boolean, string?)
	local shape = if type(name) == "string" then ALLOWED[name] else nil
	if not shape then
		return false, `not an action: {tostring(name)}`
	end
	if n > #shape then
		return false, `{name}: too many arguments`
	end
	for i, want in shape do
		if not argOk(want, args[i]) then
			return false, `{name}: bad argument {i}`
		end
	end
	return true
end

export type Towns = typeof(setmetatable(
	{} :: { store: any, saveOf: (any) -> any, base: any, now: () -> number, states: { [number]: any } },
	Towns
))

-- store: the required Shared.Game.store module. now: milliseconds since the epoch.
function Towns.new(store: any, now: () -> number): Towns
	return setmetatable({
		store = store,
		saveOf = store.saveOf,
		-- The state as the store starts it, actions included: every town starts from a copy.
		base = store.useGame.getState(),
		now = now,
		states = {},
	}, Towns)
end

-- Swaps a player's state in, runs fn on it, and keeps whatever state the store ends up with.
function Towns._with(self: Towns, userId: number, fn: (any) -> ...any): ...any
	local game = self.store.useGame
	game.setState(assert(self.states[userId], "town not open"), true)
	local result = table.pack(pcall(fn, game.getState()))
	self.states[userId] = game.getState()
	game.setState(self.base, true)
	if not result[1] then
		error(result[2], 0)
	end
	return table.unpack(result, 2, result.n)
end

-- Opens a player's town from their save, or a new starter town when save is nil.
function Towns.open(self: Towns, userId: number, save: any?)
	self.states[userId] = self.base
	self:_with(userId, function(s)
		if save then
			s.loadSave(save)
		end
		self.store.useGame.getState().tick(self.now())
	end)
end

function Towns.close(self: Towns, userId: number)
	self.states[userId] = nil
end

function Towns.isOpen(self: Towns, userId: number): boolean
	return self.states[userId] ~= nil
end

-- Moves the town's clock on: jobs finish, fuel refills, daily tasks roll over.
function Towns.tick(self: Towns, userId: number)
	self:_with(userId, function(s)
		s.tick(self.now())
	end)
end

-- Runs an action for a player (already checked with Towns.check). Brings the clock up to date
-- first, so a job that just finished can be collected. Returns the action's result.
function Towns.run(self: Towns, userId: number, name: string, ...: any): any
	local args = table.pack(...)
	return self:_with(userId, function(s)
		s.tick(self.now())
		local get = self.store.useGame.getState
		return get()[name](table.unpack(args, 1, args.n))
	end)
end

-- What the player's client needs after a change: the save, the popups the action opened, and the
-- toasts it showed (taken off the town, since the server never runs the timers that clear them).
function Towns.snapshot(self: Towns, userId: number): { save: any, need: any, panel: any, toasts: { string } }
	local state = assert(self.states[userId], "town not open")
	local toasts = {}
	for _, t in state.toasts or {} do
		table.insert(toasts, t.text)
	end
	if #toasts > 0 then
		self:_with(userId, function()
			self.store.useGame.setState({ toasts = {} })
		end)
	end
	return { save = self.saveOf(self.states[userId]), need = state.need, panel = state.panel, toasts = toasts }
end

-- The save to write to the DataStore.
function Towns.save(self: Towns, userId: number): any
	local state = assert(self.states[userId], "town not open")
	return self.saveOf(state)
end

return Towns
