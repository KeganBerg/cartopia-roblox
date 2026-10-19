--!strict
-- Rave Mode's button on the server, as the web game's rave_start() (supabase/migrations/
-- 0083_rave_button.sql): only the DJ (Kegan's account, the experience's owner) may start it; it
-- runs 68.2 seconds from the press (a ten-second build-up, then the drop), and a press while one
-- is on changes nothing. The rave reaches every player in this server through Workspace's
-- RaveFrom / RaveUntil attributes (server clock, ms; client/Rave.luau plays it), and every other
-- server through MessagingService, so it's on in every town at once.
--
-- Remote (in ReplicatedStorage.Cartopia):
--   Rave  RemoteFunction  client -> server: ("start") -> true, or false and why

local RaveTime = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RaveTime"))

local Rave = {}

local TOPIC = "CartopiaRave"
local BUILD_MS = 10000 -- techno.ts BUILD_MS

-- Whether this player is the DJ: the experience's owner, or the owner of the group that owns it.
function Rave.isDj(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId ~= 0 and player.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return player:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

local function now(): number
	return DateTime.now().UnixTimestampMillis
end

local function current(): RaveTime.Window?
	local from, to = workspace:GetAttribute("RaveFrom"), workspace:GetAttribute("RaveUntil")
	if type(from) == "number" and type(to) == "number" then
		return { from = from, drop = from + BUILD_MS, to = to }
	end
	return nil
end

local function show(w: RaveTime.Window)
	workspace:SetAttribute("RaveFrom", w.from)
	workspace:SetAttribute("RaveUntil", w.to)
end

-- A press of the button by `player` at `at`: the window now on, or nil and why.
function Rave.press(player: Player, at: number): (RaveTime.Window?, string?)
	if not Rave.isDj(player) then
		return nil, "not allowed"
	end
	local w = RaveTime.press(at, current(), BUILD_MS)
	show(w)
	return w, nil
end

function Rave.start(remotes: Instance)
	local MessagingService = game:GetService("MessagingService")
	local remote = Instance.new("RemoteFunction")
	remote.Name = "Rave"
	remote.Parent = remotes
	local lastPress: { [number]: number } = {}
	remote.OnServerInvoke = function(player: Player, op: any): (boolean, string?)
		if op ~= "start" then
			return false, "unknown"
		end
		-- One press a second is plenty.
		local t = os.clock()
		if lastPress[player.UserId] and t - lastPress[player.UserId] < 1 then
			return false, "slow down"
		end
		lastPress[player.UserId] = t
		local was = current()
		local w, why = Rave.press(player, now())
		if not w then
			return false, why
		end
		if not was or was.from ~= w.from then
			task.spawn(function()
				pcall(function()
					MessagingService:PublishAsync(TOPIC, { from = w.from, to = w.to })
				end)
			end)
		end
		return true, nil
	end
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		lastPress[p.UserId] = nil
	end)
	-- A rave started in another server.
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(msg: any)
				local d = msg.Data
				if type(d) == "table" and type(d.from) == "number" and type(d.to) == "number" and d.to > now() and d.to - d.from <= RaveTime.BUTTON_MS + 1000 then
					show({ from = d.from, drop = d.from + BUILD_MS, to = d.to })
				end
			end)
		end)
	end)
end

return Rave
