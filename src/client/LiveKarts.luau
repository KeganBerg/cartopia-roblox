--!strict
-- Kart parties on the player's side (the web game's LiveKartParty): hears the server's Kart remote
-- (server/KartParty) and starts the race screen when the host's Go deals the race, tells the
-- Live page when the parties in this server change, and says why when a party is called off.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local KartRun = require(script.Parent.KartRun)

local LiveKarts = {}

-- Fires when the parties in this server, or the player's own, change (the Live page redraws).
local changed = Instance.new("BindableEvent")
LiveKarts.changed = changed.Event
-- The player's own party as the server last showed it, or nil.
LiveKarts.mine = nil :: any
-- The race screen is up.
LiveKarts.racing = false

function LiveKarts.start(ctx: any)
	local kartEvent = ReplicatedStorage:WaitForChild("Cartopia"):WaitForChild("Kart") :: RemoteEvent
	kartEvent.OnClientEvent:Connect(function(event: string, payload: any)
		if event == "party" then
			if type(payload) == "table" and payload.gone then
				LiveKarts.mine = nil
				if payload.why then
					ctx.toast(payload.why)
				end
			else
				LiveKarts.mine = payload
			end
			changed:Fire()
		elseif event == "parties" then
			changed:Fire()
		elseif event == "setup" and type(payload) == "table" and not LiveKarts.racing then
			-- The host pressed Go: straight into the race, back to the Live page after it.
			LiveKarts.mine = nil
			LiveKarts.racing = true
			ctx.close()
			KartRun.run(ctx, payload, function()
				LiveKarts.racing = false
				ctx.open("race", "live")
			end, function() end)
		end
	end)
end

return LiveKarts
