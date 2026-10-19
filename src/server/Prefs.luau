--!strict
-- Each player's settings, kept with their account as the web keeps them in the browser:
-- - sound (client/Sounds/Mixer: Music and Town sounds on/off and volume, the Effects volume);
-- - the rest of Menu > Settings and the one-time bits (client/Prefs, the web's lib/prefs.ts and
--   game/flashing.ts): graphics, the FPS counter, reduce motion and flashing, the flashing
--   warning's "Don't show me this again", the "Are you sure?" questions, and the tips seen.
-- Loaded on join into the player's SoundPrefs and UiPrefs attributes (JSON) for their client;
-- the client sends changes on the Prefs remote (the sound settings, or { ui = ... }), and they're
-- written when the player leaves.

local Prefs = {}

local function vol(v: any, fallback: number): number
	return if type(v) == "number" and v == v then math.clamp(v, 0, 1) else fallback
end
local function bool(v: any): boolean
	return v ~= false
end
-- true, false, or nil for "follow the device".
local function maybe(v: any): boolean?
	return if type(v) == "boolean" then v else nil
end

local GRAPHICS = { auto = true, high = true, saver = true }
Prefs.MAX_TIPS = 32

-- The settings part: only the known keys, each the right kind, with defaults for the rest.
function Prefs.cleanUi(raw: any): any
	local t = if type(raw) == "table" then raw else {}
	local tips = {}
	if type(t.tips) == "table" then
		for _, id in t.tips do
			if type(id) == "string" and #id > 0 and #id <= 24 and not table.find(tips, id) and #tips < Prefs.MAX_TIPS then
				table.insert(tips, id)
			end
		end
	end
	return {
		graphics = if type(t.graphics) == "string" and GRAPHICS[t.graphics] then t.graphics else "auto",
		fps = t.fps == true,
		reduceMotion = maybe(t.reduceMotion),
		calmFlash = maybe(t.calmFlash),
		flashHide = t.flashHide == true,
		askLeave = bool(t.askLeave),
		askSell = bool(t.askSell),
		tips = tips,
	}
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
		ui = Prefs.cleanUi(t.ui),
	}
end

-- A change from the client on top of what's kept: { ui = ... } changes the settings only,
-- anything else is the sound settings (and keeps the settings as they were).
function Prefs.merge(current: any, raw: any): any
	local base = Prefs.clean(current)
	if type(raw) ~= "table" then
		return base
	end
	if type(raw.ui) == "table" and raw.music == nil and raw.town == nil and raw.effects == nil then
		base.ui = Prefs.cleanUi(raw.ui)
		return base
	end
	local next = Prefs.clean(raw)
	next.ui = base.ui
	return next
end

-- store: a DataStore (GetAsync / SetAsync); remote: the Prefs RemoteEvent.
function Prefs.start(store: any, remote: RemoteEvent, players: Players)
	local HttpService = game:GetService("HttpService")
	-- What each player has now, and whether it changed since it was loaded.
	local current: { [Player]: any } = {}
	local changed: { [Player]: boolean } = {}
	-- Changes that came in before the saved settings did: put on top once they arrive.
	local early: { [Player]: { any } } = {}
	players.PlayerAdded:Connect(function(player)
		local ok, saved = pcall(store.GetAsync, store, tostring(player.UserId))
		if not player.Parent then
			return
		end
		local p = Prefs.clean(if ok then saved else nil)
		for _, raw in early[player] or {} do
			p = Prefs.merge(p, raw)
		end
		early[player] = nil
		current[player] = p
		if ok and saved ~= nil then
			player:SetAttribute("SoundPrefs", HttpService:JSONEncode(p))
		end
		-- Always set, so the client knows its settings are in (the flashing warning waits on it).
		player:SetAttribute("UiPrefs", HttpService:JSONEncode(p.ui))
	end)
	remote.OnServerEvent:Connect(function(player, raw)
		changed[player] = true
		local p = current[player]
		if p == nil then
			local list = early[player] or {}
			early[player] = list
			if #list < 20 then
				table.insert(list, raw)
			end
			return
		end
		current[player] = Prefs.merge(p, raw)
	end)
	players.PlayerRemoving:Connect(function(player)
		local p = current[player]
		local dirty = changed[player]
		current[player], changed[player], early[player] = nil, nil, nil
		if p and dirty then
			pcall(store.SetAsync, store, tostring(player.UserId), p)
		end
	end)
end

return Prefs
