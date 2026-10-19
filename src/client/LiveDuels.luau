--!strict
-- Live drag races on the player's side (the web game's live challenges, lib/live.ts and
-- ui/ChallengeBell.tsx): hears the server's Duel remote (server/Duels), keeps the challenges
-- waiting for the 🏁 bell, and when both have said yes, takes the player straight to the strip
-- with the other racer's car drawn from where their game says it is (DragStrip's live extras).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remote = require(script.Parent.Remote)
local DragStrip = require(script.Parent.DragStrip)

local LiveDuels = {}

-- Fires when the challenges waiting change (the bell and the Invites menu redraw).
local changed = Instance.new("BindableEvent")
LiveDuels.changed = changed.Event
-- The challenges waiting for this player, as the server last sent them: { id, from, name, town,
-- carName, model, color, pi, left (seconds) }, and when they came (os.clock()).
LiveDuels.invites = {} :: { any }
LiveDuels.heardAt = 0
-- The challenge this player has out: { to, name, at }, or nil.
LiveDuels.outgoing = nil :: any
-- A live race is on screen.
LiveDuels.racing = false

-- Seconds a challenge stays open (server/Duels INVITE).
LiveDuels.INVITE = 45

-- The challenges still open, each with its seconds left counted down since the server sent them.
function LiveDuels.waiting(): { any }
	local gone = os.clock() - LiveDuels.heardAt
	local out = {}
	for _, inv in LiveDuels.invites do
		local left = math.ceil((inv.left or 0) - gone)
		if left > 0 then
			local row = table.clone(inv)
			row.left = left
			table.insert(out, row)
		end
	end
	return out
end

-- Challenges another player here. Toasts why not.
function LiveDuels.challenge(ctx: any, userId: number, name: string): boolean
	local ok = Remote.race("duel", userId)
	if ok then
		LiveDuels.outgoing = { to = userId, name = name, at = os.clock() }
		ctx.toast(`🏁 Challenge sent to {name}`)
		changed:Fire()
	end
	return ok
end

-- Answers a challenge from the bell.
function LiveDuels.answer(id: string, yes: boolean): boolean
	local ok = Remote.race("duelAnswer", { id = id, yes = yes }, not yes)
	for i, inv in LiveDuels.invites do
		if inv.id == id then
			table.remove(LiveDuels.invites, i)
			break
		end
	end
	changed:Fire()
	return ok
end

local function busy(): boolean
	local gui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	return LiveDuels.racing or (gui ~= nil and gui:FindFirstChild("Race") ~= nil)
end

-- Both said yes: off to the strip.
local function go(ctx: any, payload: any, duelEvent: RemoteEvent)
	local vs = payload.card or {}
	local name = vs.name or "Racer"
	LiveDuels.outgoing = nil
	changed:Fire()
	if busy() then
		-- Already racing something else: this one is called off for them.
		Remote.race("duelLeave", nil, true)
		return
	end
	LiveDuels.racing = true
	local ok, started = Remote.race("start", { mode = "live", which = { duel = payload.id } })
	if not ok then
		Remote.race("duelLeave", nil, true)
		LiveDuels.racing = false
		return
	end
	local them = { dist = 0, speed = 0, burning = false, done = false, at = os.clock() }
	local conn = duelEvent.OnClientEvent:Connect(function(event: string, p: any)
		if event == "pos" and type(p) == "table" then
			them.dist, them.speed, them.burning, them.done, them.at = p.dist or them.dist, p.speed or 0, p.burning == true, p.done == true or them.done, os.clock()
		elseif event == "finished" then
			them.done = true
		elseif event == "off" then
			them.done = true
			them.speed = 0
			ctx.toast(`{name} left the race`)
		end
	end)
	ctx.close()
	local car = started.car
	if not car then
		local s = require(ReplicatedStorage.Shared.Game.store).useGame.getState() :: any
		car = require(ReplicatedStorage.Shared.Game.raceCar).raceCarOf(s.cars or {}, s.raceCar)
	end
	DragStrip.run(ctx, started, car, function()
		conn:Disconnect()
		LiveDuels.racing = false
		ctx.open("race", "live")
	end, {
		title = `Live race vs {name}`,
		quote = function(res: any): string?
			if res.theirTime == math.huge then
				return `{name} didn't finish`
			end
			return nil
		end,
		live = {
			send = function(p: any)
				duelEvent:FireServer("pos", p)
			end,
			them = them,
			leave = function()
				task.spawn(Remote.race, "duelLeave", nil, true)
			end,
		},
	})
end

function LiveDuels.start(ctx: any)
	local duelEvent = ReplicatedStorage:WaitForChild("Cartopia"):WaitForChild("Duel") :: RemoteEvent
	duelEvent.OnClientEvent:Connect(function(event: string, payload: any)
		if event == "invites" and type(payload) == "table" then
			LiveDuels.invites = payload
			LiveDuels.heardAt = os.clock()
			changed:Fire()
		elseif event == "declined" then
			local out = LiveDuels.outgoing
			LiveDuels.outgoing = nil
			ctx.toast(`{if out then out.name else "They"} said no this time`)
			changed:Fire()
		elseif event == "go" and type(payload) == "table" then
			task.spawn(go, ctx, payload, duelEvent)
		elseif event == "off" and not LiveDuels.racing then
			ctx.toast("That live race was called off")
		end
	end)
	-- Anything already waiting (a challenge sent while the town loaded).
	task.spawn(function()
		local ok, list = Remote.race("duelInvites", nil, true)
		if ok and type(list) == "table" then
			LiveDuels.invites = list
			LiveDuels.heardAt = os.clock()
			changed:Fire()
		end
	end)
end

return LiveDuels
