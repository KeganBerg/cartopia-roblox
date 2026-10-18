--!strict
-- Player saves in a DataStore, with session locking so two servers never write the same town.
--
-- Each key holds { save = <the web game's SaveState>, lock = { job, at } | nil, version, receipts, seen }.
-- receipts: the Robux purchases (PurchaseIds) already in this save, written in the same UpdateAsync
-- as the save itself, so a purchase is either in both or in neither (see Purchases). seen: when the
-- save was last written, which is about when the player was last here. Loading
-- takes the lock in the same UpdateAsync that reads the save; every write checks this server still
-- holds it, and releasing clears it. A lock that hasn't been refreshed for LOCK_TTL seconds belongs
-- to a server that crashed, so it can be taken over.
--
-- The DataStore, job id and clock are passed in, so the tests can run this outside Studio.

local Saves = {}
Saves.__index = Saves

Saves.LOCK_TTL = 30 * 60
Saves.RETRIES = 5
Saves.RETRY_WAIT = 6

export type Record = { save: any?, lock: { job: string, at: number }?, version: number?, receipts: { string }?, seen: number? }
export type Store = {
	UpdateAsync: (self: any, key: string, fn: (old: Record?) -> Record?) -> any,
}
export type Options = { store: Store, job: string, now: () -> number, wait: ((seconds: number) -> ())? }

export type Saves = typeof(setmetatable(
	{} :: { store: Store, job: string, now: () -> number, wait: (number) -> (), held: { [string]: boolean }, seen: { [string]: number } },
	Saves
))

function Saves.new(opts: Options): Saves
	return setmetatable({
		store = opts.store,
		job = opts.job,
		now = opts.now,
		wait = opts.wait or function(s: number)
			task.wait(s)
		end,
		held = {},
		seen = {},
	}, Saves)
end

local function keyOf(userId: number): string
	return `town_{userId}`
end

local function lockedByOther(self: Saves, record: Record?): boolean
	local lock = record and record.lock
	return lock ~= nil and lock.job ~= self.job and self.now() - lock.at < Saves.LOCK_TTL
end

-- Why a load failed: another server holds the lock, or the DataStore itself failed. "off" is a
-- DataStore that will never answer (Studio without API access, or an unpublished place), so it
-- isn't retried.
export type LoadError = { reason: "locked" | "failed" | "off", message: string }

local function isOff(err: string): boolean
	return string.find(err, "API Services", 1, true) ~= nil
		or string.find(err, "403", 1, true) ~= nil
		or string.find(err, "must publish", 1, true) ~= nil
end

-- Takes the lock and returns the save (nil for a new player) and its receipts. When it can't, it errors with a
-- LoadError, and the caller should not give the player a blank town that would overwrite theirs.
function Saves.load(self: Saves, userId: number): (any?, { string })
	local key = keyOf(userId)
	local failure: LoadError = { reason = "locked", message = "locked by another server" }
	for attempt = 1, Saves.RETRIES do
		local busy = false
		local save: any? = nil
		local seen: number? = nil
		local receipts: { string } = {}
		local ok, err = pcall(function()
			self.store:UpdateAsync(key, function(old: Record?): Record?
				if lockedByOther(self, old) then
					busy = true
					return nil -- leave it untouched
				end
				busy = false
				local record: Record = old or { version = 0 }
				record.lock = { job = self.job, at = self.now() }
				save = record.save
				seen = record.seen
				receipts = record.receipts or {}
				return record
			end)
		end)
		if ok and not busy then
			self.held[key] = true
			self.held[key] = true
			self.seen[key] = seen
			return save, receipts
		end
		if ok then
			failure = { reason = "locked", message = `{key} is locked by another server` }
		else
			local message = tostring(err)
			failure = { reason = if isOff(message) then "off" else "failed", message = `loading {key}: {message}` }
			if failure.reason == "off" then
				break
			end
		end
		if attempt < Saves.RETRIES then
			self.wait(Saves.RETRY_WAIT)
		end
	end
	error(failure)
end

-- Writes the save and refreshes the lock (release = true lets it go). Returns false without
-- writing when this server no longer holds the lock, e.g. another server took it over after this
-- one stalled; that server's copy is the real one now. receipts, when given, replaces the stored list.
function Saves.write(self: Saves, userId: number, save: any, release: boolean?, receipts: { string }?): boolean
	local key = keyOf(userId)
	if not self.held[key] then
		return false
	end
	local wrote = false
	local ok, err = pcall(function()
		self.store:UpdateAsync(key, function(old: Record?): Record?
			local lock = old and old.lock
			if not lock or lock.job ~= self.job then
				wrote = false
				return nil
			end
			wrote = true
			local record = old :: Record
			record.save = save
			record.version = (record.version or 0) + 1
			record.seen = self.now()
			if receipts then
				record.receipts = receipts
			end
			record.lock = if release then nil else { job = self.job, at = self.now() }
			return record
		end)
	end)
	if not ok then
		warn(`[Cartopia] saving {key} failed: {err}`)
		return false
	end
	if not wrote or release then
		self.held[key] = nil
	end
	return wrote
end

-- When the save loaded last was written before (the clock's units), or nil for a new player or
-- an older save: how long they were away, for the welcome back.
function Saves.lastSeen(self: Saves, userId: number): number?
	return self.seen[keyOf(userId)]
end

function Saves.holds(self: Saves, userId: number): boolean
	return self.held[keyOf(userId)] == true
end

return Saves
