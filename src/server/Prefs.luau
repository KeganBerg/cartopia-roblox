--!strict
-- Each player's sound settings (client/Sounds/Mixer: Music and Town sounds on/off and volume, the
-- Effects volume), kept with their account as the web keeps them in the browser. Loaded on join
-- into the player's SoundPrefs attribute (JSON) for their client; the client sends changes on the
-- Prefs remote, and they're written when the player leaves.

local HttpService = game:GetService("HttpService")

local Prefs = {}

local function vol(v: any, fallback: number): number
	return if type(v) == "number" and v == v then math.clamp(v, 0, 1) else fallback
end
local function bool(v: any): boolean
	return v ~= false
end

-- Only the shape the client uses, with numbers clamped: anything else is dropped.
function Prefs.clean(raw: any): any
	local t = if type(raw) == "table" then raw else {}
	local m = if type(t.music) == "table" then t.music else {}
	local w = if type(t.town) == "table" then t.town else {}
	return {
		music = { on = bool(m.on), volume = vol(m.volume, 0.5) },
		town = { on = bool(w.on), volume = vol(w.volume, 0.7) },
		effects = vol(t.effects, 1),
	}
end

-- store: a DataStore (GetAsync / SetAsync); remote: the Prefs RemoteEvent.
function Prefs.start(store: any, remote: RemoteEvent, players: Players)
	local changed: { [Player]: any } = {}
	players.PlayerAdded:Connect(function(player)
		local ok, saved = pcall(store.GetAsync, store, tostring(player.UserId))
		if ok and saved ~= nil and player.Parent and not changed[player] then
			player:SetAttribute("SoundPrefs", HttpService:JSONEncode(Prefs.clean(saved)))
		end
	end)
	remote.OnServerEvent:Connect(function(player, raw)
		changed[player] = Prefs.clean(raw)
	end)
	players.PlayerRemoving:Connect(function(player)
		local p = changed[player]
		changed[player] = nil
		if p then
			pcall(store.SetAsync, store, tostring(player.UserId), p)
		end
	end)
end

return Prefs
