--!strict
-- Live events on the client, as the web game's lib/liveEventsSync.ts and ui/LiveBanner.tsx. The
-- server (server/LiveEvents, started from the owner's admin panel) puts the live list in
-- Workspace's LiveEvents attribute; this hands it to the converted game/liveEvents.ts, which the
-- rest already follows: the town clock for night and day (clock.ts, DayNight), the sky for
-- weather (weather.ts, TownWeather), Rave Mode for rave (techno.ts, client/Rave). It also:
--   - pins a 'banner' event's message at the top of the screen until it ends (live-banner.css);
--   - shows an event's optional message once as a toast when it starts.
-- The server's times are moved onto this device's clock, as client/Rave does with RaveFrom.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local liveEvents = require(Game:WaitForChild("liveEvents")) :: any
local Js = require(Game:WaitForChild("__js")) :: any
local Ui = require(script.Parent.Ui)
local Motion = require(script.Parent.Motion)

local LiveBanner = {}

local MAX_W = 560 -- live-banner.css max-width: min(560px, 100% - 24px)
local TOP = 128

-- The game code's clock (Date.now() in the converted code: this device's).
local function nowMs(): number
	return Js.JsDate.now(Js.JsDate)
end

local function root(): Instance?
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("Cartopia")
	return hud and hud:FindFirstChild("Root")
end

local function messageOf(e: any): string
	local m = type(e) == "table" and type(e.payload) == "table" and e.payload.message
	return if type(m) == "string" then string.sub(m, 1, 120) else ""
end

-- ---------- The banner ----------
local banner: Frame? = nil

local function hide()
	if banner then
		banner:Destroy()
		banner = nil
	end
end

-- live-banner.css .live-banner: amber gradient, dark brown letters, a navy outline, a hard drop
-- shadow, the 📢 then the message, centred under the top bar. It never takes taps.
local function show(text: string)
	hide()
	local parent = root()
	if not parent or text == "" then
		return
	end
	local okW, measured = pcall(Ui.textWidth, text, 16)
	local textW = if okW and type(measured) == "number" then measured else #text * 8
	local width = (parent :: any).Size.X.Offset
	width = if type(width) == "number" and width > 0 then width else 1280
	local maxW = math.min(MAX_W, width - 24)
	local inner = maxW - 28 - 28 -- padding 14 each side, the icon and its gap
	local lines = math.max(1, math.ceil(textW / inner))
	local w = if lines == 1 then textW + 28 + 28 + 2 else maxW
	local h = 12 + lines * 20 + 4
	local shadow, face = Ui.shadowed({
		Name = "LiveBanner",
		ZIndex = 60,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, TOP),
		Size = UDim2.fromOffset(w, h),
		Active = false,
		Parent = parent,
	}, { radius = 14, stroke = 2.5, drop = 3, dark = 0.3, color = Ui.WHITE })
	face.ZIndex = 60
	Ui.gradient("#ffca28", "#ff8f00").Parent = face
	Ui.text({ Name = "Icon", Text = "📢", TextSize = 20, ZIndex = 61, Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 22, 1, 0), Parent = face })
	Ui.text({
		Name = "Message",
		Text = text,
		TextSize = 16,
		TextWrapped = true,
		TextColor3 = Color3.fromHex("#3e2723"),
		TextXAlignment = if lines == 1 then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left,
		ZIndex = 61,
		Position = UDim2.fromOffset(42, 0),
		Size = UDim2.new(1, -54, 1, 0),
		Parent = face,
	})
	Motion.pop(shadow)
	banner = shadow
end

liveEvents.registerLiveKind("banner", {
	start = function(e: any)
		show(messageOf(e))
	end,
	stop = hide,
})

-- A live rave goes through client/Rave, so the music, heads-up and countdown come with it (the
-- converted techno.ts handler would start only the lights).
local Rave = require(script.Parent.Rave) :: any
for _, kind in { "rave", "techno" } do
	liveEvents.registerLiveKind(kind, {
		start = function(e: any)
			Rave.startTest(e.from, e.to)
		end,
		stop = function()
			Rave.stop()
		end,
	})
end

-- ---------- Start toasts ----------
local seen: { [number]: boolean } = {}
local function toast(text: string)
	local r = root()
	local toasts = r and r:FindFirstChild("Toasts")
	if not toasts then
		return
	end
	local t = Ui.toast(toasts, text, 0)
	task.delay(3.5, function()
		t:Destroy()
	end)
end

-- liveEventsSync.ts announce: an event's message once, when it starts (or now, if it's on).
local function announce(list: { any }, now: number)
	for _, e in list do
		local text = messageOf(e)
		if text ~= "" and not seen[e.id] and e.from <= now and now < e.to then
			seen[e.id] = true
			toast(text)
		end
	end
end

-- ---------- Following the server ----------
local list: { any } = {}

-- The attribute's list on this device's clock.
function LiveBanner.read(json: any, skew: number): { any }
	local ok, raw = pcall(HttpService.JSONDecode, HttpService, if type(json) == "string" then json else "[]")
	local out = {}
	if not ok or type(raw) ~= "table" then
		return out
	end
	for _, e in raw do
		if type(e) == "table" and type(e.id) == "number" and type(e.kind) == "string" and type(e.from) == "number" and type(e.to) == "number" then
			table.insert(out, { id = e.id, kind = e.kind, payload = if type(e.payload) == "table" then e.payload else {}, from = e.from + skew, to = e.to + skew })
		end
	end
	return out
end

local function skew(): number
	local ok, server = pcall(function()
		return workspace:GetServerTimeNow() * 1000
	end)
	return if ok then nowMs() - server else 0
end

local function refresh()
	list = LiveBanner.read(workspace:GetAttribute("LiveEvents"), skew())
	liveEvents.setLiveEvents(list)
	liveEvents.syncHandlers(nowMs())
	announce(list, nowMs())
end

-- For the emulator, where attribute signals never fire.
LiveBanner._refresh = refresh

local started = false
function LiveBanner.start()
	if started then
		return
	end
	started = true
	refresh()
	workspace:GetAttributeChangedSignal("LiveEvents"):Connect(refresh)
	-- Scheduled starts and ends on time (liveEventsSync.ts runs syncHandlers once a second).
	task.spawn(function()
		while true do
			task.wait(1)
			local now = nowMs()
			liveEvents.syncHandlers(now)
			announce(list, now)
		end
	end)
end

return LiveBanner
