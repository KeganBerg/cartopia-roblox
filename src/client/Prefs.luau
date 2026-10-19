--!strict
-- The player's settings apart from sound (the web's lib/prefs.ts and game/flashing.ts): graphics,
-- the FPS counter, reduce motion and flashing, the flashing warning's "Don't show me this again",
-- the "Are you sure?" questions (client/Confirm) and the one-time tips already seen (Popups/Tips).
-- The web keeps them on the device; here they're kept with the account (server/Prefs), arriving
-- in the player's UiPrefs attribute and sent back on the Prefs remote a moment after a change.
--
-- What other modules read is also set where they already look:
-- - the player's Graphics attribute ("auto", "high", "saver"): TownWeather draws the phone's
--   lighter rain and snow on Saver; Saver also turns off the town's shadows and glow here;
-- - ReduceMotion (true when on): the menus' and buttons' animations (Motion, UIMotion), on top of
--   Roblox's own Reduced Motion setting;
-- - CalmFlashing: Rave Mode and the storm's lightning (Rave, TownWeather). Rave Mode's heads-up
--   sets it too; that choice is kept like the rest.

local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Confirm = require(script.Parent.Confirm)

local Prefs = {}

export type Graphics = "auto" | "high" | "saver"
export type Ui = {
	graphics: Graphics,
	fps: boolean,
	reduceMotion: boolean?,
	calmFlash: boolean?,
	flashHide: boolean,
	askLeave: boolean,
	askSell: boolean,
	tips: { string },
}

local prefs: Ui = { graphics = "auto", fps = false, reduceMotion = nil, calmFlash = nil, flashHide = false, askLeave = true, askSell = true, tips = {} }
-- The saved settings came in (the flashing warning waits for them, so it never flashes up for a
-- player who hid it).
Prefs.loaded = false

local changed = Instance.new("BindableEvent")
Prefs.changed = changed.Event

local me = Players.LocalPlayer

local function deviceCalm(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

function Prefs.get(): Ui
	return prefs
end

-- Reduce motion and Reduce flashing as they stand: the player's pick, or the device's.
function Prefs.reduceMotion(): boolean
	if prefs.reduceMotion ~= nil then
		return prefs.reduceMotion
	end
	return deviceCalm()
end
function Prefs.calmFlash(): boolean
	if prefs.calmFlash ~= nil then
		return prefs.calmFlash
	end
	return deviceCalm()
end

local applying = false
local function apply()
	applying = true
	if me then
		me:SetAttribute("Graphics", prefs.graphics)
		me:SetAttribute("ReduceMotion", if Prefs.reduceMotion() then true else nil)
		me:SetAttribute("CalmFlashing", Prefs.calmFlash())
	end
	-- Saver: no shadows or glow (lib/prefs.ts). The glow is DayNight's bloom, which it only ever
	-- dims and brightens, so turning it off here sticks.
	local saver = prefs.graphics == "saver"
	pcall(function()
		Lighting.GlobalShadows = not saver
		local glow = Lighting:FindFirstChild("Glow")
		if glow and glow:IsA("BloomEffect") then
			glow.Enabled = not saver
		end
	end)
	Confirm.prefs.askLeave = prefs.askLeave
	Confirm.prefs.askSell = prefs.askSell
	applying = false
end

local function read(raw: any): Ui
	local t = if type(raw) == "table" then raw else {}
	local g = t.graphics
	local tips = {}
	if type(t.tips) == "table" then
		for _, id in t.tips do
			if type(id) == "string" then
				table.insert(tips, id)
			end
		end
	end
	return {
		graphics = if g == "high" or g == "saver" then g else "auto",
		fps = t.fps == true,
		reduceMotion = if type(t.reduceMotion) == "boolean" then t.reduceMotion else nil,
		calmFlash = if type(t.calmFlash) == "boolean" then t.calmFlash else nil,
		flashHide = t.flashHide == true,
		askLeave = t.askLeave ~= false,
		askSell = t.askSell ~= false,
		tips = tips,
	}
end

local saving = false
local function save()
	if saving then
		return
	end
	saving = true
	task.delay(2, function()
		saving = false
		local remotes = ReplicatedStorage:FindFirstChild("Cartopia")
		local remote = remotes and remotes:FindFirstChild("Prefs")
		if remote and remote:IsA("RemoteEvent") then
			remote:FireServer({ ui = prefs })
		end
	end)
end

-- Prefs.set({ graphics = "saver" }): changes only what's given. (Use Prefs.follow to go back
-- to following the device for reduceMotion / calmFlash.)
function Prefs.set(patch: { [string]: any })
	local next = table.clone(prefs) :: any
	for k, v in patch do
		next[k] = v
	end
	prefs = read(next)
	apply()
	changed:Fire()
	save()
end

-- Marks a one-time tip as seen.
function Prefs.seeTip(id: string)
	if table.find(prefs.tips, id) then
		return
	end
	local tips = table.clone(prefs.tips)
	table.insert(tips, id)
	Prefs.set({ tips = tips })
end

function Prefs.seen(id: string): boolean
	return table.find(prefs.tips, id) ~= nil
end

local function loaded()
	local raw = me and me:GetAttribute("UiPrefs")
	if raw == nil then
		return
	end
	if type(raw) ~= "string" then
		return
	end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, raw)
	if ok then
		-- Tips seen this session before the save arrived stay seen.
		local seenNow = prefs.tips
		prefs = read(data)
		for _, id in seenNow do
			if not table.find(prefs.tips, id) then
				table.insert(prefs.tips, id)
			end
		end
		Prefs.loaded = true
		apply()
		changed:Fire()
	end
end

-- Reads the UiPrefs attribute again (it does so by itself when the attribute changes).
Prefs.load = loaded

-- "Don't ask again" on an "Are you sure?" card turns its question off for good (Settings turns
-- it back on).
Confirm.onStop = function(pref: string)
	Prefs.set({ [pref] = false })
end

apply()
if me then
	loaded()
	me:GetAttributeChangedSignal("UiPrefs"):Connect(loaded)
	-- Rave Mode's heads-up flips Reduce flashing on the attribute: keep that choice.
	me:GetAttributeChangedSignal("CalmFlashing"):Connect(function()
		if applying then
			return
		end
		local on = me:GetAttribute("CalmFlashing") == true
		if on ~= Prefs.calmFlash() then
			Prefs.set({ calmFlash = on })
		end
	end)
	-- The glow may be made after this runs (DayNight makes it on its first frame).
	Lighting.ChildAdded:Connect(function(c)
		if c.Name == "Glow" then
			task.defer(apply)
		end
	end)
end

return Prefs
