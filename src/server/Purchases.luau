--!strict
-- Robux purchases: the web game's gem packs and car packs (Shared.Game.bucksPacks). Gem packs are
-- Developer Products; car packs are Game Passes, so they show in the game page's Store row and can
-- be bought there too.
--
-- Each gem pack is a Developer Product named exactly like the pack ("Bag of Gems"), made by
-- tools/products/sync.mjs. The server finds their ids by name when it starts (setProducts), so no
-- product id lives in the code, and a pack whose product doesn't exist yet just isn't on sale. Car
-- packs' Game Passes are made by the same script, which writes their ids to Shared.GamePasses
-- (setPasses). A pass is paid once: when it's bought in game, or when its owner joins after buying
-- it on the game page. Its receipt is "pass:<pack id>", kept with the save for good.
--
-- A paid pack goes through the web store's own applyPurchases, with the row the web's Stripe webhook
-- would have written: the next purchase number, the pack's gems, and coins and parts for the buyer's
-- level (packGrant). Car packs are one per account, so a car the town already has is never offered.
--
-- ProcessReceipt can run more than once for one purchase (a retry, another server). Every PurchaseId
-- granted is kept with the save and written in the same DataStore update (Saves.write receipts), so
-- a purchase is either in the save with its id or in neither. A grant whose save didn't write yet
-- stays "pending": the town has it, and the next save of the town (an autosave or leaving) carries
-- its id; until one does, Roblox is told to ask again rather than counting it as granted.

local Purchases = {}
Purchases.__index = Purchases

-- Receipts kept per player: Roblox retries a receipt only for a while, so the last few hundred do.
Purchases.KEEP = 300

-- Roblox's warn, or print where there is none (the tests run on plain Luau).
local say: (...any) -> () = (warn :: any) or print

export type Purchases = typeof(setmetatable(
	{} :: {
		towns: any,
		store: any,
		packs: any,
		write: (userId: number) -> boolean,
		-- pack id -> { product, robux }, from setProducts; product id -> pack id.
		products: { [string]: { product: number, robux: number? } },
		byProduct: { [number]: string },
		-- car pack id -> { pass, robux }, from setPasses; pass id -> pack id.
		passes: { [string]: { pass: number, robux: number? } },
		byPass: { [number]: string },
		receipts: { [number]: { list: { string }, has: { [string]: "saved" | "pending" } } },
	},
	Purchases
))

-- towns: the Towns. store: Shared.Game.store. packs: Shared.Game.bucksPacks. write(userId): saves
-- that player's town with toSave's receipts and calls saved() with them when it wrote.
function Purchases.new(towns: any, store: any, packs: any, write: (number) -> boolean): Purchases
	return setmetatable({
		towns = towns,
		store = store,
		packs = packs,
		write = write,
		products = {},
		byProduct = {},
		passes = {},
		byPass = {},
		receipts = {},
	}, Purchases)
end

-- Every pack still sold, then the retired ones (a purchase started before a pack was retired still
-- has to deliver).
function Purchases.pack(self: Purchases, id: string): any?
	for _, list in { self.packs.ALL_PACKS, self.packs.RETIRED_PACKS } do
		for _, p in list do
			if p.id == id then
				return p
			end
		end
	end
	return nil
end

-- The Developer Products the experience has, as { { name, product, robux } }: matches each to the
-- pack with that name.
function Purchases.setProducts(self: Purchases, list: { { name: string, product: number, robux: number? } })
	local byName = {}
	for _, l in { self.packs.ALL_PACKS, self.packs.RETIRED_PACKS } do
		for _, p in l do
			byName[p.name] = p.id
		end
	end
	self.products, self.byProduct = {}, {}
	for _, d in list do
		local id = byName[d.name]
		if id then
			self.products[id] = { product = d.product, robux = d.robux }
			self.byProduct[d.product] = id
		end
	end
end

-- The car packs' Game Passes, as { { id = pack id, pass, robux } } (Shared.GamePasses and their
-- prices; robux nil for one off sale, which isn't sold but still pays its owners). Gem packs aren't
-- sold as passes.
function Purchases.setPasses(self: Purchases, list: { { id: string, pass: number, robux: number? } })
	self.passes, self.byPass = {}, {}
	for _, d in list do
		local p = self:pack(d.id)
		if p and p.car then
			self.passes[d.id] = { pass = d.pass, robux = d.robux }
			self.byPass[d.pass] = d.id
		end
	end
end

local function passReceipt(id: string): string
	return `pass:{id}`
end

-- What a player's receipts start as: the ones saved with their town.
function Purchases.load(self: Purchases, userId: number, saved: { string }?)
	local r: { list: { string }, has: { [string]: "saved" | "pending" } } = { list = {}, has = {} }
	for _, id in saved or ({} :: { string }) do
		if not r.has[id] then
			table.insert(r.list, id)
			r.has[id] = "saved"
		end
	end
	self.receipts[userId] = r
end

-- The receipts to write with the town's next save: the newest KEEP, and every pass's (a pass is
-- owned for good, so its receipt must never drop off).
function Purchases.toSave(self: Purchases, userId: number): { string }?
	local r = self.receipts[userId]
	if not r then
		return nil
	end
	local from = math.max(1, #r.list - Purchases.KEEP + 1)
	local out = {}
	for i = 1, from - 1 do
		if r.list[i]:sub(1, 5) == "pass:" then
			table.insert(out, r.list[i])
		end
	end
	return table.move(r.list, from, #r.list, #out + 1, out)
end

-- After a save wrote: the receipts written with it (toSave's list) are saved now.
function Purchases.saved(self: Purchases, userId: number, list: { string })
	local r = self.receipts[userId]
	if r then
		for _, id in list do
			if r.has[id] then
				r.has[id] = "saved"
			end
		end
	end
end

function Purchases.forget(self: Purchases, userId: number)
	self.receipts[userId] = nil
end

-- Real-money buys open with the town's Crew House, built or packed away (web game/payGate.ts).
function Purchases.hasCrewHouse(save: any): boolean
	if save.admin then
		return true
	end
	for _, list in { save.buildings or {}, save.stored or {} } do
		for _, b in list do
			if type(b) == "table" and b.def == "crew" then
				return true
			end
		end
	end
	return false
end

local function owns(save: any, car: string): boolean
	for _, c in save.cars or {} do
		if c.model == car then
			return true
		end
	end
	return false
end

-- The shop as this player sees it: every pack on sale with its Robux price (nil until its product
-- exists) and whether they already own its car. open: false until the town has a Crew House.
function Purchases.shop(self: Purchases, userId: number): { open: boolean, packs: { [string]: { robux: number?, owned: boolean? } } }
	local save = self.towns:save(userId)
	local packs = {}
	for _, p in self.packs.ALL_PACKS do
		local d = if p.car then self.passes[p.id] else self.products[p.id]
		packs[p.id] = { robux = d and d.robux, owned = if p.car then owns(save, p.car) else nil }
	end
	return { open = Purchases.hasCrewHouse(save), packs = packs }
end

-- Whether a player may buy a pack now: the id to prompt and whether it's a "product" or a "pass",
-- or nil and why ("unknown", "soon" for a pack whose product or pass isn't made yet, "crew",
-- "owned").
function Purchases.canBuy(self: Purchases, userId: number, id: any): (number?, string?, ("product" | "pass")?)
	local p = if type(id) == "string" then self:pack(id) else nil
	if not p or not table.find(self.packs.ALL_PACKS, p) then
		return nil, "unknown"
	end
	local pass = if p.car then self.passes[p.id] else nil
	local d = self.products[p.id]
	if not (if p.car then pass and pass.robux else d) then
		return nil, "soon"
	end
	local save = self.towns:save(userId)
	if not Purchases.hasCrewHouse(save) then
		return nil, "crew"
	end
	local r = self.receipts[userId]
	if p.car and (owns(save, p.car) or (r and r.has[passReceipt(p.id)])) then
		return nil, "owned"
	end
	if pass then
		return pass.pass, nil, "pass"
	end
	return d.product, nil, "product"
end

-- Pays one pack into the player's town and notes its receipt as pending its save.
local function grant(self: Purchases, userId: number, p: any, receipt: string)
	local packs = self.packs
	self.towns:_with(userId, function(s)
		local g = packs.packGrant(p, s.level)
		local row: any = { seq = (s.purchases or 0) + 1, pack = p.id, bucks = g.bucks, coins = g.coins, parts = g.parts }
		-- One of each car per account: a second copy (bought from two servers at once) pays its gems only.
		if p.car and not owns(s, p.car) then
			row.car = p.car
		end
		s.applyPurchases({ row })
		local get = self.store.useGame.getState
		local bits = { `💎 +{g.bucks}` }
		if g.coins > 0 then
			table.insert(bits, `$ +{g.coins}`)
		end
		if g.parts > 0 then
			table.insert(bits, `⚙ +{g.parts}`)
		end
		if row.car then
			table.insert(bits, "🚗 new car in your garage")
		end
		get().toast(`Thanks! {table.concat(bits, "  ")}`)
	end)
	local r = self.receipts[userId]
	table.insert(r.list, receipt)
	r.has[receipt] = "pending"
end

-- A Game Pass the player owns (just bought in game, or found when they join): pays its car pack
-- the first time. "granted" once that's in their saved town, "later" when it can't be yet (call
-- again, as a join or the next save does), "unknown" for a pass that isn't a car pack's.
function Purchases.grantPass(self: Purchases, userId: number, passId: number): "granted" | "later" | "unknown"
	local id = self.byPass[passId]
	local p = id and self:pack(id)
	if not p then
		return "unknown"
	end
	local r = self.receipts[userId]
	if not r or not self.towns:isOpen(userId) then
		return "later"
	end
	local receipt = passReceipt(p.id)
	if r.has[receipt] == nil then
		grant(self, userId, p, receipt)
	end
	if r.has[receipt] == "pending" then
		self.write(userId)
	end
	return if r.has[receipt] == "saved" then "granted" else "later"
end

-- Handles one receipt. Returns "granted" once the pack is in the player's saved town, or "later"
-- when it can't be yet (player not here, town not loaded, save not written): Roblox asks again.
function Purchases.process(self: Purchases, userId: number, productId: number, purchaseId: string): "granted" | "later"
	local r = self.receipts[userId]
	if not r or not self.towns:isOpen(userId) then
		return "later"
	end
	local state = r.has[purchaseId]
	if state == "saved" then
		return "granted"
	end
	if state == nil then
		local id = self.byProduct[productId]
		local p = id and self:pack(id)
		if not p then
			say(`[Cartopia] receipt {purchaseId}: product {productId} isn't a pack`)
			return "later"
		end
		grant(self, userId, p, purchaseId)
	end
	self.write(userId)
	return if r.has[purchaseId] == "saved" then "granted" else "later"
end

return Purchases
