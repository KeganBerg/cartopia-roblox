--!strict
-- Shapes of the catalog tables in Catalog.luau, mirroring the types in the web game's src/game/data.ts.
-- String unions there are plain strings here; the comment next to each field lists the values.

export type BuildingDef = {
	id: string,
	name: string,
	kind: string, -- business | gas | parts | showroom | garage | decor | house | obstacle
	w: number,
	h: number,
	price: number,
	bucks: number?,
	unlockLevel: number,
	-- Businesses: a job costs fuel, runs for `jobSeconds`, then pays out.
	jobSeconds: number?,
	fuelCost: number?,
	payout: number?,
	xp: number?,
	partsPayout: number?,
	-- Gas stations raise the fuel cap.
	fuelCap: number?,
	color: string,
	roof: string,
	sign: string?,
	-- Only one per town.
	unique: boolean?,
	prop: string?, -- donut | burger | cone | tire | pin | popcorn
	service: boolean?,
	-- Jobs can only start after dark.
	nightOnly: boolean?,
	-- Stand-in for a building this build doesn't know (see Data.buildingDef).
	parked: boolean?,
	-- Sold only while this event runs.
	event: string?,
}

export type CarDef = {
	id: string,
	name: string,
	body: string,
	price: number,
	bucks: number?,
	unlockLevel: number,
	rescueOnly: boolean?,
	season: number?,
	skill: string?, -- launch | nitro | slipstream | smooth | oil | torque | freeze
	likes: { string },
	power: number,
	grip: number,
	weight: number,
	colors: { string },
	parked: boolean?,
	legendary: boolean?,
}

export type Tread = { wet: number?, snow: number?, dust: number? }

export type ModDef = {
	id: string,
	slot: string, -- spoiler | exhaust | kit | hood | rims | tires
	name: string,
	unlockLevel: number,
	coins: number,
	parts: number,
	bucks: number,
	power: number,
	grip: number,
	weight: number,
	only: { string }?,
	notOn: { string }?,
	tread: Tread?,
}

export type GameEvent = { id: string, name: string, icon: string, from: string, to: string }

export type RescueSpot = {
	id: string,
	name: string,
	icon: string,
	unlockLevel: number,
	cost: number,
	cars: { { model: string, rarity: string } },
}

export type GpSeries = {
	id: string,
	name: string,
	unlockLevel: number,
	minCars: number,
	basePi: number,
	step: number,
	prize: number,
	box: { string },
	rivals: { string },
}

export type CampaignChapter = {
	id: string,
	name: string,
	blurb: string,
	unlockLevel: number,
	venue: string,
	pi: { number }, -- { first race, boss }
	rivals: { string }, -- the last one is the boss
	coins: number,
	bucks: number,
	trophies: number,
	starBucks: number,
}

export type CarSet = {
	id: string,
	name: string,
	icon: string,
	cars: { string },
	coins: number,
	bucks: number,
	trophies: number,
	xp: number,
}

export type GoalDef = {
	id: string,
	icon: string,
	text: string,
	stat: string,
	target: number,
	coins: number,
	xp: number,
	bucks: number?,
	level: number?,
	def: string?,
	event: string?,
}

-- The web version's `n(level)` lives in Data.taskCount, keyed by pool and id.
export type TaskDef = { id: string, icon: string, stat: string, text: string, level: number?, needs: string? }

-- Exactly one of the unlock fields is set.
export type SkinUnlock = { level: number?, set: string?, season: number?, bucks: number?, crate: boolean? }
export type SkinDef = { id: string, n: number, name: string, tier: string, blurb: string, unlock: SkinUnlock, swatch: string }

export type DealDef = { id: string, kind: string, item: string?, n: number?, off: number }

export type Upgrades = { engine: number, turbo: number, tires: number, weight: number }

-- Roblox needs every ModuleScript to return a value.
return {}
