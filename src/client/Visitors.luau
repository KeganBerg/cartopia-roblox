--!strict
-- Surprise visitors in town, the client's side (the web's lib/visitors.ts): every few minutes it
-- asks the server for a visitor (server/Visitors rolls who comes and what they pay), says hello with
-- a horn and a toast, and sends them on their way when their time is up. Tapping tourists or the
-- mystery car claims their prize from the server; tapping a street racer opens the Street
-- challenge card (Panels/StreetRace), and Race! starts a street race through the race desk (mode
-- "street", server/Modes/Street). The car in town and its badge are client/VisitorCar.
--
-- The state is here for the others to read: Visitors.visitor (or nil), Visitors.busy, and
-- Visitors.changed fires whenever it changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local raceCar = require(Game.raceCar) :: any
local Remote = require(script.Parent.Remote)
local Placement = require(script.Parent.Placement)
local Sfx = require(script.Parent.Sounds.Sfx) :: any

local Visitors = {}

export type Visitor = {
	id: string,
	kind: string,
	coins: number,
	xp: number,
	parts: number,
	bucks: number,
	expiresAt: number,
	model: string,
	color: string,
	name: string,
	pi: number,
	body: string,
	group: number?,
	-- On its way out of town: still drawn while it fades.
	gone: boolean?,
}

Visitors.visitor = nil :: Visitor?
Visitors.busy = false
-- A street race against the visitor is underway (it doesn't leave mid-race).
Visitors.racing = false
local changedEvent = Instance.new("BindableEvent")
Visitors.changed = changedEvent.Event

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

local function changed()
	changedEvent:Fire(Visitors.visitor)
end

-- How long until the next visitor is asked for. Starts a minute or so after load.
local nextAt = 0
local asking = false
local ctxRef: any = nil

local function gap(): number
	return (data.VISIT_GAP_MIN + math.random() * 2) * 60000
end

-- The web's HELLO.
local HELLO = {
	racer = "🏁 A street racer rolled into town!",
	tourist = "📸 Tourists are driving around town!",
	mystery = "❓ A mystery car! Tap it before it leaves!",
	barn = "📞 Rusty got a tip about a free car!",
}

local function toast(text: string)
	if ctxRef and ctxRef.toast then
		ctxRef.toast(text)
	end
end

-- Is the town in a state to have a visitor turn up? Not while visiting a friend, building, or
-- still in the tutorial; and only with a few roads to drive on.
function Visitors.ready(): boolean
	local s = store.useGame.getState()
	if ctxRef and ctxRef.visiting ~= nil then
		return false
	end
	return not Placement.active() and (s.tutorial or 0) >= 99 and #(s.roads or {}) >= 4
end

local function arrived()
	local v = Visitors.visitor
	if not v then
		return
	end
	Sfx.horn(v.body)
	toast(if v.group then `📸 A tour group of {v.group} campers rolled into town!` else HELLO[v.kind])
end

-- Asks the server for the next visitor (visitor_next()).
function Visitors.ask()
	if asking then
		return
	end
	asking = true
	local ok, res = Remote.visitor("next")
	asking = false
	if not ok or type(res) ~= "table" then
		nextAt = now() + 5 * 60000
		return
	end
	if res.wait ~= nil or not res.id then
		nextAt = now() + math.max(30, res.wait or 60) * 1000
		return
	end
	Visitors.visitor = res
	changed()
	arrived()
end

-- Sends the visitor on its way: it fades out of town, and the next one comes a few minutes later.
function Visitors.leave()
	local v = Visitors.visitor
	if not v or v.gone then
		return
	end
	local gone = table.clone(v)
	gone.gone = true
	Visitors.visitor = gone
	changed()
	task.spawn(Remote.visitor, "leave", v.id)
	task.delay(1.2, function()
		if Visitors.visitor and Visitors.visitor.id == v.id then
			Visitors.visitor = nil
			changed()
		end
	end)
	-- Tourists, alone or in a group, never pop up more than once every TOURIST_GAP_MIN minutes.
	nextAt = now() + (if v.kind == "tourist" then math.max(gap(), data.TOURIST_GAP_MIN * 60000) else gap())
end

-- Collects the visitor's prize from the server. False if it couldn't (it left, or storage is full).
function Visitors.claim(): boolean
	local v = Visitors.visitor
	if not v or v.gone or Visitors.busy then
		return false
	end
	local s = store.useGame.getState()
	if v.kind == "barn" and #(s.junkyard or {}) >= data.STORAGE_MAX then
		toast("Storage is full. Restore or scrap a car first, then call Rusty back.")
		return false
	end
	Visitors.busy = true
	changed()
	local ok = Remote.visitor("claim", v.id)
	Visitors.busy = false
	if not ok then
		toast(if v.kind == "mystery" then "Too slow! The mystery car got away." else "Your visitor already left town.")
		Visitors.leave()
		return false
	end
	-- The server's snapshot has the prize and its thanks toast.
	Sfx.coin()
	Visitors.leave()
	return true
end

-- Tapping a visitor in town: a racer asks for a race; the rest pay out there and then.
function Visitors.tap()
	local v = Visitors.visitor
	if not v or v.gone or Visitors.busy then
		return
	end
	if v.kind == "racer" then
		if ctxRef then
			ctxRef.open("streetRace")
		end
	else
		task.spawn(Visitors.claim)
	end
end

-- Race! on the Street challenge card: a street race at no fuel, through the race desk. The racer
-- leaves after it, won or lost (a win pays their bonus on the server), and if it's left early.
function Visitors.race(ctx: any): boolean
	local v = Visitors.visitor
	if not v or v.gone or v.kind ~= "racer" then
		return false
	end
	local s = store.useGame.getState()
	local car = raceCar.raceCarOf(s.cars, s.raceCar)
	if not car then
		ctx.toast("You need a car to race")
		return false
	end
	local ok, res = Remote.race("start", { mode = "street", which = v.id })
	if not ok then
		-- Already raced, or gone: they drive off.
		if res ~= "slow down" and res ~= "no answer" and res ~= "town not loaded" then
			Visitors.leave()
		end
		return false
	end
	Visitors.racing = true
	ctx.close()
	local DragStrip = require(script.Parent.DragStrip) :: any
	local Street = require(script.Parent.RacePages.Street) :: any
	DragStrip.run(ctx, res, car, function()
		Visitors.racing = false
		Visitors.leave()
		ctx.close()
	end, Street.extras(ctx, v.id, res, function()
		return function() end
	end))
	return true
end

-- Called every second.
function Visitors.tick(t: number?)
	local at = t or now()
	local v = Visitors.visitor
	if v then
		-- Ran out of time (a racer mid-race gets to finish first).
		if not v.gone and at > v.expiresAt and not Visitors.busy and not Visitors.racing then
			Visitors.leave()
		end
		return
	end
	if at >= nextAt and Visitors.ready() then
		nextAt = at + 60000
		task.spawn(Visitors.ask)
	end
end

-- The client's ctx (for toasts and opening the card); starts the clock.
function Visitors.start(ctx: any)
	ctxRef = ctx
	nextAt = now() + 60000 + math.random() * 30000
end

-- For the emulator: bring the next ask forward.
function Visitors._askNow()
	nextAt = 0
end

return Visitors
