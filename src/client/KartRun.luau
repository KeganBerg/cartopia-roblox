--!strict
-- The kart race screen, as the web game's KartGame (ui/Kart.tsx) and KartScene: the circuit fills
-- the screen with the six karts on the grid, five start lights come on one by one and go out for
-- GO, then three laps of drifting, boost pads, jumps and items out of the prize crates. The HUD
-- shows the place, the lap, the time, the minimap and the item slot; a podium comes up after
-- the line. Driven with the keyboard (W A S D or arrows, Space or Shift to drift, E, Q or Enter
-- for an item) or on a touch screen with ◀ ▶ pads and the drift, item and brake buttons (the gas
-- is automatic there).
--
-- The race runs on the converted kart rules (Shared.Game.kart's KartRace) at 120 steps a second,
-- the karts drawn between their last two steps. The server (server/Karts) picked the grid and
-- spent the fuel; the place and time over the line are sent back and it pays them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local K = require(Game.kart) :: any
local L = require(Game.lualib_bundle) :: any
local data = require(Game.data) :: any
local store = require(Game.store) :: any
local boosts = require(Game.boosts) :: any
local nearMiss = require(Game.nearMiss) :: any
local cones = require(Game.cones) :: any
local Remote = require(script.Parent.Remote)
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)
local TownCamera = require(script.Parent.TownCamera)
local DayNight = require(script.Parent.DayNight)
local KartWorld = require(script.Parent.KartWorld)

local KartRun = {}

-- Drives the player's kart on the AI's own line (the web's ?autopilot, for the emulator's run).
KartRun.autopilot = false

local S = KartWorld.S
local W = KartWorld.W
local STEP = 1 / 120
local HERO_TIME = 2.2

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local function fmt(s: number): string
	local m = math.floor(s / 60)
	return string.format("%d:%04.1f", m, s - m * 60)
end

local function ord(n: number): string
	return `{n}{if n == 1 then "st" elseif n == 2 then "nd" elseif n == 3 then "rd" else "th"}`
end

local function wrap(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

-- The reel a fresh item spins through (Object.values(ITEMS)).
local ITEM_ORDER = { "nitro", "oil", "hornet", "shield", "tow", "tacks", "smoke", "emp", "nitro3", "ghost", "bomb", "splat", "rocket" }
-- What's on the player right now (Kart.tsx FX): a badge per effect, red for bad, green for good.
local FX = {
	{ key = "flat", icon = "📌", full = K.FLAT_TIME, bad = true },
	{ key = "smoke", icon = "💨", full = K.SMOKE_TIME, bad = true },
	{ key = "emp", icon = "⚡", full = K.EMP_TIME, bad = true },
	{ key = "tow", icon = "🧲", full = K.TOW_TIME, bad = false },
	{ key = "shield", icon = "🫧", full = 8, bad = false },
	{ key = "splat", icon = "🎨", full = K.SPLAT_TIME, bad = true },
	{ key = "ghost", icon = "👻", full = K.GHOST_TIME, bad = false },
	{ key = "rocket", icon = "🚀", full = K.ROCKET_TIME, bad = false },
}
local PLACE = { "#ffd740", "#e0e0e0", "#ffab91" }
-- The paint blobs over the screen (Kart.tsx SPLAT_BLOBS): where across and down, size, colour.
local SPLAT_BLOBS = { { 20, 32, 30, "#ff4081" }, { 78, 26, 34, "#00e5ff" }, { 58, 78, 24, "#ffea00" }, { 90, 68, 20, "#ff4081" }, { 8, 80, 22, "#00e5ff" } }
-- The town's own shops line a town circuit (ArcadeScenery useTownPool), else Main Street's.
local SHOPS = { business = true, gas = true, parts = true }
local FALLBACK = { "pizza", "donut", "burger", "diner", "motel", "carwash", "tires", "gas", "bowling", "icecream", "coffee", "tacos" }

local function townPool(): { string }
	local s = store.useGame.getState()
	local seen, own = {}, {}
	for _, b in s.buildings or {} do
		local d = data.buildingDef(b.def)
		if d and not seen[b.def] and SHOPS[d.kind] and d.w <= 2 and d.h <= 1 then
			seen[b.def] = true
			table.insert(own, b.def)
		end
	end
	return if #own >= 4 then own else FALLBACK
end

-- The finish hero shot (scene/heroShot.ts heroCam): a low sweep from the front corner to the
-- flank, then a rise over the back. Returns the camera's spot and where it looks.
local function heroCam(t: number, x: number, y: number, z: number, h: number, len: number, side: number, room: number): (Vector3, Vector3)
	local k = math.clamp(t / HERO_TIME, 0, 1)
	local function ease(u: number): number
		return u * u * (3 - 2 * u)
	end
	local function mix(a: number, b: number, u: number): number
		return a + (b - a) * u
	end
	local a, r, up
	if k < 0.55 then
		local e = ease(k / 0.55)
		a, r, up = mix(0.6, 1.5, e), mix(1.9, 1.6, e), mix(0.2, 0.3, e)
	else
		local e = ease((k - 0.55) / 0.45)
		a, r, up = mix(1.5, 2.55, e), mix(1.6, 2.4, e), mix(0.3, 0.95, e)
	end
	local d = math.min(r * len, room)
	local fx, fz = math.sin(h), math.cos(h)
	local sx, sz = math.cos(h) * side, -math.sin(h) * side
	local ca, sa = math.cos(a), math.sin(a)
	return Vector3.new(x + (fx * ca + sx * sa) * d, y + up * len, z + (fz * ca + sz * sa) * d), Vector3.new(x + fx * len * 0.1, y + len * 0.14, z + fz * len * 0.1)
end

-- A dark chip of white words (.kt-lap, .kt-time), sized to its text.
local function chip(parent: Instance, text: string, x: number, color: string?, transparency: number?): (Frame, TextLabel)
	local w = math.ceil(Ui.textWidth(text, 15)) + 20
	local f = Ui.new("Frame", { Position = UDim2.fromOffset(x, 0), Size = UDim2.fromOffset(w, 30), BackgroundColor3 = hex(color or "#0a1428"), BackgroundTransparency = transparency or 0.5, Parent = parent }, { Ui.corner(10) })
	local l = Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 14, Size = UDim2.fromScale(1, 1), Parent = f })
	return f, l
end

-- Starts a kart race: kind "gp" (which: the series id), "blast" or "custom" (which: the pick).
-- back: the race menu's tab to come back to. False when the server didn't start it.
local starting = false
function KartRun.start(ctx: any, kind: string, which: any, back: string): boolean
	if starting then
		return false
	end
	starting = true
	local ok, res = Remote.race("kartStart", { kind = kind, which = which })
	starting = false
	if not ok then
		return false
	end
	ctx.close()
	KartRun.run(ctx, res, function()
		ctx.open("race", back)
	end, function(nk: string, nw: any)
		if not KartRun.start(ctx, nk, nw, back) then
			ctx.open("race", back)
		end
	end)
	return true
end

-- Opens the race. started: what Remote.race("kartStart") answered; onExit: back to the menu;
-- again(kind, which): races the next one (the result card's ▶ or ↻).
function KartRun.run(ctx: any, started: any, onExit: () -> (), again: (string, any) -> ())
	local def = K.TRACKS[started.track + 1]
	local t = K.buildTrack(def, started.reverse)
	local field = started.field
	local race = L.__TS__New(K.KartRace, t, field, started.seed, started.rules)
	local me = 1
	for i, f in field do
		if not f.ai then
			me = i
		end
	end
	local meId = me - 1

	-- ── The world ──────────────────────────────────────────────────────────────────────────────
	local world, lamps = KartWorld.circuit(t, townPool())
	local folder = Instance.new("Folder")
	folder.Name = "KartRace"
	folder.Parent = world
	DayNight.setRaceFog({ color = hex(KartWorld.FOG), near = 100 * S, far = 340 * S })
	local views = {}
	for i, f in field do
		views[i] = KartWorld.kart(f, folder)
	end
	local crates = KartWorld.crates(t, folder)
	local glass = KartWorld.obstacles(race, folder)
	local part = KartWorld.part
	local Y_PAINT = 0.04
	local oil = KartWorld.pool(folder, function()
		return part({ Name = "Oil", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04 * S, 2 * S, 2 * S), Color = hex("#1a1a24"), Material = Enum.Material.Glass, Transparency = 1 }, folder)
	end)
	local hornets = KartWorld.pool(folder, function()
		return part({ Name = "Hornet", Shape = Enum.PartType.Ball, Size = Vector3.new(0.64, 0.48, 1) * S, Color = hex("#ffd600"), Material = Enum.Material.Neon, Transparency = 1 }, folder)
	end)
	local mats = KartWorld.pool(folder, function()
		return part({ Name = "Tacks", Size = Vector3.new(2.8, 0.02, 0.85) * S, Color = hex("#5d4037"), Transparency = 1 }, folder)
	end)
	local spikes = KartWorld.pool(folder, function()
		return part({ Name = "Spike", Size = Vector3.new(0.12, 0.28, 0.12) * S, Color = hex("#eceff1"), Material = Enum.Material.Metal, Transparency = 1 }, folder)
	end)
	local puffs = KartWorld.pool(folder, function()
		return part({ Name = "Smoke", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2) * S, Color = hex("#e3e6e8"), Transparency = 1 }, folder)
	end)
	local bombs = KartWorld.pool(folder, function()
		return part({ Name = "Bomb", Shape = Enum.PartType.Ball, Size = Vector3.new(1.1, 1.1, 1.1) * S, Color = hex("#1c1c22"), Material = Enum.Material.Metal, Transparency = 1 }, folder)
	end)
	local fuses = KartWorld.pool(folder, function()
		return part({ Name = "Fuse", Shape = Enum.PartType.Ball, Size = Vector3.new(0.3, 0.3, 0.3) * S, Color = hex("#ffea00"), Material = Enum.Material.Neon, Transparency = 1 }, folder)
	end)
	local blasts = KartWorld.pool(folder, function()
		return part({ Name = "Blast", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2) * S, Color = hex("#ff9100"), Material = Enum.Material.Neon, Transparency = 1 }, folder)
	end)
	local beams = KartWorld.pool(folder, function()
		return part({ Name = "TowBeam", Size = Vector3.new(0.14, 0.14, 1) * S, Color = hex("#e040fb"), Material = Enum.Material.Neon, Transparency = 1 }, folder)
	end)
	-- Traffic cones on the inside of the tightest bends: clipping one sends it flying (game/cones.ts).
	local coneList = cones.placeCones(t)
	local coneParts = {}
	for i = 1, #coneList do
		coneParts[i] = part({ Name = "Cone", Size = Vector3.new(0.4, 0.7, 0.4) * S, Color = hex("#ff6d00"), Material = Enum.Material.SmoothPlastic }, folder)
	end
	-- A warm glow under the player, so their kart reads at a glance (PlayerRing).
	local ring = part({ Name = "PlayerRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.02 * S, 3 * S, 3 * S), Color = hex("#ffd54f"), Material = Enum.Material.Neon, Transparency = 0.75 }, folder)

	-- ── The screen: the town's HUD steps aside, the race takes the camera ─────────────────────
	local root: Frame = ctx.gui
	local hudGui = root:FindFirstAncestorOfClass("ScreenGui") :: ScreenGui
	local raceGui = Ui.new("ScreenGui", { Name = "Race", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = hudGui.Parent })
	local screen = Ui.new("Frame", { Name = "RaceScreen", Size = root.Size, BackgroundTransparency = 1, Parent = raceGui })
	local hudScale = root:FindFirstChildOfClass("UIScale")
	local scale = Ui.new("UIScale", { Scale = if hudScale then hudScale.Scale else 1, Parent = screen })
	hudGui.Enabled = false
	TownCamera.setPaused(true)
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local oldFov = cam.FieldOfView
	local touch = UserInputService.TouchEnabled

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, root:GetPropertyChangedSignal("Size"):Connect(function()
		screen.Size = root.Size
		scale.Scale = if hudScale then hudScale.Scale else 1
	end))
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		for _, c in conns do
			c:Disconnect()
		end
		RunService:UnbindFromRenderStep("KartRun")
		raceGui:Destroy()
		folder:Destroy()
		hudGui.Enabled = true
		DayNight.setRaceFog(nil)
		cam.FieldOfView = oldFov
		TownCamera.setPaused(false)
		onExit()
	end
	-- Closes the race screen and does `go` instead of going back to the menu.
	local function leave(go: () -> ())
		onExit = go
		close()
	end

	-- Overlays under the HUD: smoke haze, the static's crackle, paint over the screen, the phantom glow.
	local haze = Ui.new("Frame", { Name = "Haze", Size = UDim2.fromScale(1, 1), BackgroundColor3 = hex("#8a8a8a"), Visible = false, Parent = screen }, {
		Ui.new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0.1) }), Rotation = 90 }),
	})
	local zap = Ui.new("Frame", { Name = "Zap", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = screen }, { Ui.stroke(36, hex("#b388ff"), 0.25) })
	local ghostGlow = Ui.new("Frame", { Name = "Ghost", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = screen }, { Ui.stroke(44, hex("#d1c4e9"), 0.35) })
	local splat = Ui.new("Frame", { Name = "Splat", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true, Visible = false, Parent = screen })
	for _, b in SPLAT_BLOBS do
		local blob = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(b[1] / 100, b[2] / 100), Size = UDim2.fromOffset(b[3] * 8 * 2.2 * 0.5, b[3] * 8 * 2.2 * 0.5), BackgroundColor3 = hex(b[4]), Parent = splat }, { Ui.round() })
		for j = 0, 4 do
			local a = j * 1.3 + b[1]
			Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5 + math.cos(a) * 0.75, 0, 0.5 + math.sin(a) * 0.75, 0), Size = UDim2.fromScale(0.16, 0.16), BackgroundColor3 = hex(b[4]), Parent = blob }, { Ui.round() })
		end
	end

	-- ── Top: the title over a dark band, and the X (.rf-top) ──────────────────────────────────
	local band = Ui.new("Frame", { Name = "Top", Size = UDim2.new(1, 0, 0, 72), BackgroundColor3 = hex("#0a1e3c"), BorderSizePixel = 0, Parent = screen }, {
		Ui.new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) }) }),
	})
	local _ = band
	Ui.text({ Name = "Title", Text = started.title, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -90, 0, 44), Shadow = 2, ShadowColor = Ui.BLACK, ShadowTransparency = 0.65, Parent = screen })
	Ui.closeButton({ Name = "Leave", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(44, 44), Parent = screen }, function()
		close()
	end)

	-- ── The HUD: place, lap, time, catch-up (.kt-hud) ─────────────────────────────────────────
	local hudRow = Ui.new("Frame", { Name = "KartHud", Position = UDim2.fromOffset(12, 54), Size = UDim2.fromOffset(460, 58), BackgroundTransparency = 1, Visible = false, Parent = screen })
	local placeBig = Ui.text({ Text = "6", TextSize = 54, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(40, 58), Shadow = 3, ShadowColor = Ui.BLACK, ShadowTransparency = 0.55, Parent = hudRow })
	local placeSmall = Ui.text({ Text = "th", TextSize = 22, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(30, 26), Shadow = 2, ShadowColor = Ui.BLACK, ShadowTransparency = 0.55, Parent = hudRow })
	local placeOf = Ui.text({ Text = `/{#field}`, TextSize = 16, TextTransparency = 0.2, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(30, 20), Shadow = 2, ShadowColor = Ui.BLACK, ShadowTransparency = 0.55, Parent = hudRow })
	local lapChip = Ui.new("Frame", { Size = UDim2.fromOffset(90, 30), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.5, Parent = hudRow }, { Ui.corner(10) })
	Ui.text({ Text = "LAP", Body = true, Weight = "heavy", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 0), Size = UDim2.fromOffset(30, 30), Parent = lapChip })
	local lapNum = Ui.text({ Text = "1", Body = true, Weight = "heavy", TextSize = 18, TextColor3 = hex("#ffd740"), Position = UDim2.fromOffset(40, 0), Size = UDim2.fromOffset(14, 30), Parent = lapChip })
	Ui.text({ Text = `/{K.LAPS}`, Body = true, Weight = "heavy", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(55, 0), Size = UDim2.fromOffset(30, 30), Parent = lapChip })
	local timeChip, timeText = chip(hudRow, "0:00.0", 0)
	local catchChip = chip(hudRow, "⏩", 0, "#ff9100", 0.25)
	local function layoutHud(place: number)
		local big = math.ceil(Ui.textWidth(tostring(place), 54))
		placeBig.Size = UDim2.fromOffset(big + 2, 58)
		local small = math.ceil(Ui.textWidth(string.sub(ord(place), -2), 22))
		placeSmall.Position = UDim2.fromOffset(big + 2, 24)
		placeSmall.Size = UDim2.fromOffset(small + 2, 26)
		local of = math.ceil(Ui.textWidth(`/{#field}`, 16))
		placeOf.Position = UDim2.fromOffset(big + small + 8, 30)
		placeOf.Size = UDim2.fromOffset(of + 2, 20)
		local x = big + small + of + 20
		lapChip.Position = UDim2.fromOffset(x, 16)
		timeChip.Position = UDim2.fromOffset(x + 100, 16)
		catchChip.Position = UDim2.fromOffset(x + 100 + timeChip.Size.X.Offset + 10, 16)
	end
	layoutHud(#field)

	-- ── The minimap (.kt-map): the circuit from above, a dot per kart ─────────────────────────
	local mapW, mapH = 132, 120
	local map = Ui.new("Frame", { Name = "MiniMap", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 54), Size = UDim2.fromOffset(mapW, mapH), BackgroundTransparency = 1, Visible = false, Parent = screen })
	local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
	for i = 0, t.n - 1 do
		x0, x1 = math.min(x0, t.x[i]), math.max(x1, t.x[i])
		z0, z1 = math.min(z0, t.z[i]), math.max(z1, t.z[i])
	end
	local vbW, vbH = x1 - x0 + 16, z1 - z0 + 16
	local mk = math.min(mapW / vbW, mapH / vbH)
	local function mapAt(x: number, z: number): (number, number)
		return mapW / 2 + (x - (x0 + x1) / 2) * mk, mapH / 2 + (z - (z0 + z1) / 2) * mk
	end
	for layer = 1, 2 do
		local width = (if layer == 1 then 11 else 3.5) * mk
		local color = if layer == 1 then hex("#0a1428") else Ui.WHITE
		local i = 0
		while i < t.n do
			local j = math.min(i + 4, t.n) % t.n
			local ax, ay = mapAt(t.x[i], t.z[i])
			local bx, by = mapAt(t.x[j], t.z[j])
			local len = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
			Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2), Size = UDim2.fromOffset(len + width * 0.9, width), Rotation = math.deg(math.atan2(by - ay, bx - ax)), BackgroundColor3 = color, BackgroundTransparency = if layer == 1 then 0.45 else 0, BorderSizePixel = 0, ZIndex = layer, Parent = map }, { Ui.corner(math.floor(width / 2)) })
			i += 4
		end
	end
	do
		local sx, sy = mapAt(t.x[0], t.z[0])
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(sx, sy), Size = UDim2.fromOffset(10 * mk, 2.4 * mk), Rotation = -math.deg(math.atan2(t.tx[0], t.tz[0])), BackgroundColor3 = hex("#212121"), BorderSizePixel = 0, ZIndex = 3, Parent = map }, { Ui.stroke(1, Ui.WHITE) })
	end
	local dots = {}
	for i = 1, #field do
		local mine = i == me
		local d = (if mine then 4.6 else 3.2) * 2 * mk
		dots[i] = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(d, d), BackgroundColor3 = hex(if mine then "#ffd740" else "#ef5350"), ZIndex = if mine then 5 else 4, Parent = map }, { Ui.round(), Ui.stroke(if mine then 1.6 else 1.2, if mine then hex("#212121") else Ui.WHITE) })
	end

	-- ── The item slot (.kt-slot), the drift charge bar, wrong way, the flash and the call ──────
	local slot = Ui.new("Frame", { Name = "ItemSlot", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(64, 64), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.5, Visible = false, Parent = screen }, { Ui.corner(16) })
	local slotStroke = Ui.stroke(3, Ui.WHITE, 0.3)
	slotStroke.Parent = slot
	local slotGrad = Ui.new("UIGradient", { Color = Ui.seq("#7c4dff", "#311b92"), Rotation = 90, Enabled = false, Parent = slot })
	local slotIcon = Ui.text({ Text = "", TextSize = 38, Size = UDim2.fromScale(1, 1), Parent = slot })
	local uses = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 14, 1, 12), Size = UDim2.fromOffset(32, 22), BackgroundColor3 = hex("#ff6d00"), Visible = false, Parent = slot }, { Ui.corner(10), Ui.stroke(2, Ui.WHITE) })
	local usesText = Ui.text({ Text = "", Body = true, Weight = "heavy", TextSize = 15, Size = UDim2.fromScale(1, 1), Parent = uses })
	if touch then
		slot.Position = UDim2.new(0.5, 0, 0, 54)
	end
	local charge = Ui.new("Frame", { Name = "Charge", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.66), Size = UDim2.fromOffset(120, 10), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.5, ClipsDescendants = true, Visible = false, Parent = screen }, { Ui.corner(5) })
	local chargeFill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = hex("#fff59d"), BorderSizePixel = 0, Parent = charge }, { Ui.corner(5) })
	local wrongWay = Ui.new("Frame", { Name = "WrongWay", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.fromOffset(math.ceil(Ui.textWidth("↩ WRONG WAY", 28)) + 44, 52), BackgroundColor3 = hex("#d50000"), Visible = false, Parent = screen }, { Ui.corner(14) })
	Ui.text({ Text = "↩ WRONG WAY", TextSize = 28, Size = UDim2.fromScale(1, 1), Parent = wrongWay })
	local flash = Ui.text({ Name = "Flash", Text = "", TextSize = 64, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.26), Size = UDim2.new(1, 0, 0, 76), Stroke = 2, StrokeTransparency = 0.7, Shadow = 5, ShadowColor = Ui.BLACK, ShadowTransparency = 0.6, Parent = screen })
	local flashScale = Ui.new("UIScale", { Parent = flash })
	local callout = Ui.text({ Name = "Callout", Text = "", TextSize = 34, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.44), Size = UDim2.new(1, 0, 0, 44), Shadow = 3, ShadowColor = hex("#e65100"), Parent = screen })
	local fxRow = Ui.new("Frame", { Name = "Effects", Position = UDim2.fromOffset(12, 118), Size = UDim2.fromOffset(400, 40), BackgroundTransparency = 1, Parent = screen })
	local fxBadges = {}
	for i, f in FX do
		local b = Ui.new("Frame", { Name = f.key, Size = UDim2.fromOffset(40, 40), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.3, Visible = false, Parent = fxRow }, { Ui.round() })
		local stroke = Ui.stroke(3, hex(if f.bad then "#ff5252" else "#69f0ae"))
		stroke.Parent = b
		Ui.text({ Text = f.icon, TextSize = 21, Size = UDim2.fromScale(1, 1), Parent = b })
		fxBadges[i] = { frame = b, stroke = stroke }
	end

	-- ── Controls: keys on a computer, pads and buttons on a touch screen ──────────────────────
	local input: any = K.idleInput()
	input.assist = if touch then K.BUTTONS_ASSIST else 0
	local inputs = {}
	for i = 1, #field do
		inputs[i] = input
	end
	local held: { [string]: boolean } = {}
	local KEYS: { [Enum.KeyCode]: string } = {
		[Enum.KeyCode.Left] = "left",
		[Enum.KeyCode.A] = "left",
		[Enum.KeyCode.Right] = "right",
		[Enum.KeyCode.D] = "right",
		[Enum.KeyCode.Up] = "gas",
		[Enum.KeyCode.W] = "gas",
		[Enum.KeyCode.Down] = "brake",
		[Enum.KeyCode.S] = "brake",
		[Enum.KeyCode.Space] = "drift",
		[Enum.KeyCode.LeftShift] = "drift",
		[Enum.KeyCode.RightShift] = "drift",
		[Enum.KeyCode.E] = "item",
		[Enum.KeyCode.Q] = "item",
		[Enum.KeyCode.Return] = "item",
	}
	local keysDown: { [Enum.KeyCode]: boolean } = {}
	local function applyKeys()
		for k in held do
			held[k] = nil
		end
		for code in keysDown do
			held[KEYS[code]] = true
		end
		input.steer = (if held.left then 1 else 0) - (if held.right then 1 else 0)
		input.brake = if held.brake then 1 else 0
		input.gas = if held.gas then 1 else 0
		input.drift = held.drift == true
		input.item = held.item == true
	end
	local ended = false -- the podium is up: keys no longer drive
	table.insert(conns, UserInputService.InputBegan:Connect(function(io: InputObject)
		if KEYS[io.KeyCode] and not ended and not UserInputService:GetFocusedTextBox() then
			keysDown[io.KeyCode] = true
			applyKeys()
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(io: InputObject)
		if KEYS[io.KeyCode] then
			keysDown[io.KeyCode] = nil
			applyKeys()
		end
	end))
	-- Keys held when the window loses focus never come up: let go of them all.
	pcall(function()
		table.insert(conns, UserInputService.WindowFocusReleased:Connect(function()
			table.clear(keysDown)
			applyKeys()
		end))
	end)

	-- Touch (DriveControls TouchDrive with ◀ ▶ pads): hold a pad to turn, the gas is on unless
	-- braking; drift, item and brake on the right.
	local padDir = 0
	local touchBrake = false
	local controls = Ui.new("Frame", { Name = "Controls", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = screen })
	local padFingers: { [InputObject]: number } = {}
	local itemBtn: Frame? = nil
	local itemBtnIcon: TextLabel? = nil
	if touch then
		local pads = Ui.new("Frame", { Name = "Pads", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 18, 1, -18), Size = UDim2.fromOffset(234, 112), BackgroundTransparency = 1, Parent = controls })
		local padFaces = {}
		for i, side in { 1, -1 } do
			local p = Ui.new("TextButton", { Name = if side > 0 then "Left" else "Right", Text = if side > 0 then "◀" else "▶", TextSize = 44, TextColor3 = Ui.WHITE, FontFace = Ui.DISPLAY, AutoButtonColor = false, Position = UDim2.fromOffset((i - 1) * 122, 0), Size = UDim2.fromOffset(112, 112), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.58, Parent = pads }, { Ui.round(), Ui.stroke(3, Ui.WHITE, 0.4) })
			padFaces[side] = p
			table.insert(conns, p.InputBegan:Connect(function(io: InputObject)
				if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
					padFingers[io] = side
				end
			end))
		end
		local function padsUpdate()
			local l, r = false, false
			for _, sd in padFingers do
				if sd > 0 then
					l = true
				else
					r = true
				end
			end
			padDir = (if l then 1 else 0) - (if r then 1 else 0)
			padFaces[1].BackgroundTransparency = if l then 0.5 else 0.58
			padFaces[1].BackgroundColor3 = if l then Ui.WHITE else hex("#0a1428")
			padFaces[-1].BackgroundTransparency = if r then 0.5 else 0.58
			padFaces[-1].BackgroundColor3 = if r then Ui.WHITE else hex("#0a1428")
		end
		table.insert(conns, UserInputService.InputChanged:Connect(function(io: InputObject)
			if padFingers[io] then
				local p = pads.AbsolutePosition
				local w = pads.AbsoluteSize.X
				padFingers[io] = if io.Position.X < p.X + w / 2 then 1 else -1
				padsUpdate()
			end
		end))
		table.insert(conns, UserInputService.InputEnded:Connect(function(io: InputObject)
			if padFingers[io] then
				padFingers[io] = nil
				padsUpdate()
			end
		end))
		table.insert(conns, pads.InputBegan:Connect(function()
			padsUpdate()
		end))
		local cluster = Ui.new("Frame", { Name = "Cluster", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -18, 1, -18), Size = UDim2.fromOffset(196, 190), BackgroundTransparency = 1, Parent = controls })
		local function hold(name: string, size: number, at: UDim2, color: string, transparency: number, words: string, textSize: number, down: () -> (), up: () -> ()): TextButton
			local b = Ui.new("TextButton", { Name = name, Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 1), Position = at, Size = UDim2.fromOffset(size, size), BackgroundColor3 = hex(color), BackgroundTransparency = transparency, Parent = cluster }, { Ui.round(), Ui.stroke(3, Ui.WHITE, 0.3) })
			Ui.text({ Name = "Label", Text = words, TextSize = textSize, Size = UDim2.fromScale(1, 1), Parent = b })
			local finger: InputObject? = nil
			table.insert(conns, b.InputBegan:Connect(function(io: InputObject)
				if io.UserInputType == Enum.UserInputType.Touch or io.UserInputType == Enum.UserInputType.MouseButton1 then
					finger = io
					down()
				end
			end))
			table.insert(conns, UserInputService.InputEnded:Connect(function(io: InputObject)
				if io == finger then
					finger = nil
					up()
				end
			end))
			return b
		end
		hold("Drift", 96, UDim2.new(1, 0, 1, -34), "#ff9100", 0, "DRIFT", 18, function()
			input.drift = true
		end, function()
			input.drift = false
		end)
		local ib = hold("Item", 84, UDim2.new(1, -102, 1, -100), "#0a1428", 0.5, "ITEM", 13, function()
			input.item = true
		end, function()
			input.item = false
		end)
		itemBtn = ib
		itemBtnIcon = ib:FindFirstChild("Label") :: TextLabel
		hold("Brake", 80, UDim2.new(1, -112, 1, 0), "#b71c1c", 0.35, "BRAKE", 13, function()
			touchBrake = true
		end, function()
			touchBrake = false
		end)
	else
		-- A short line of key hints for a computer (KeyHints).
		local parts = { { keys = { "W", "A", "S", "D" }, words = "or arrows" }, { keys = { "Space" }, words = "drift" }, { keys = { "E" }, words = "item" } }
		local hint = Ui.new("Frame", { Name = "KeyHints", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(100, 30), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.55, Parent = controls }, { Ui.round() })
		local x = 14
		for gi, g in parts do
			if gi > 1 then
				x += 14
			end
			for _, k in g.keys do
				local w = math.max(18, math.ceil(Ui.textWidth(k, 11)) + 10)
				local kb = Ui.new("Frame", { Position = UDim2.fromOffset(x, 6), Size = UDim2.fromOffset(w, 18), BackgroundColor3 = Ui.WHITE, Parent = hint }, { Ui.corner(5), Ui.stroke(1, hex("#90a4ae")) })
				Ui.text({ Text = k, Body = true, Weight = "heavy", TextSize = 11, TextColor3 = hex("#263238"), Size = UDim2.fromScale(1, 1), Parent = kb })
				x += w + 2
			end
			local w = math.ceil(Ui.textWidth(g.words, 12) * 0.95) + 4
			Ui.text({ Text = g.words, Body = true, TextSize = 12, Position = UDim2.fromOffset(x + 2, 0), Size = UDim2.fromOffset(w, 30), Parent = hint })
			x += w + 2
		end
		hint.Size = UDim2.fromOffset(x + 14, 30)
	end

	-- ── The podium (Kart.tsx Podium) ───────────────────────────────────────────────────────────
	local result: any = nil -- what the server paid, once it answers
	local refused: string? = nil
	local finishPlace = 0
	local podium: Frame? = nil
	local function nextButton(): { text: string, go: () -> () }?
		if refused then
			return nil
		end
		if started.kind == "gp" then
			local g = result and result.gp
			if not g then
				return nil
			end
			local series = nil
			for _, sr in data.GP_SERIES do
				if sr.id == started.series then
					series = sr
				end
			end
			if g.round == started.round then
				return { text = "↻ Retry", go = function()
					again("gp", started.series)
				end }
			elseif g.round == started.round + 1 and series then
				return { text = `▶ Race {g.round + 1} · ${Ui.commas(data.gpReward(series, g.round))}`, go = function()
					again("gp", started.series)
				end }
			end
			return nil
		end
		return { text = "↻ Again", go = function()
			again(started.kind, if started.kind == "custom" then started.pick else nil)
		end }
	end
	local function drawPodium()
		if podium then
			podium:Destroy()
		end
		local won = finishPlace == 1
		local overlay = Ui.new("Frame", { Name = "Result", Size = UDim2.fromScale(1, 1), BackgroundColor3 = hex(if won then "#3a3418" else "#0a1428"), BackgroundTransparency = if won then 0.35 else 0.45, ZIndex = 40, Parent = screen })
		podium = overlay
		local card = Ui.new("Frame", { Name = "Podium", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 480), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = 0.04, ZIndex = 41, Parent = overlay }, { Ui.corner(22) })
		local INK = hex("#263238")
		Ui.text({ Text = if won then "🏆 You win!" else `{ord(finishPlace)} place`, TextSize = 30, TextColor3 = INK, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 36), ZIndex = 41, Parent = card })
		local order = race:order()
		local ids = {}
		for i, k in order do
			ids[i] = k.id + 1
		end
		-- Second, first, third, the winner's block tallest.
		local steps = Ui.new("Frame", { Name = "Steps", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 58), Size = UDim2.fromOffset(342, 166), BackgroundTransparency = 1, ZIndex = 41, Parent = card })
		local HEIGHTS = { 70, 50, 36 }
		local GRADS = { { "#ffd740", "#ff8f00" }, { "#eceff1", "#90a4ae" }, { "#ffccbc", "#bf6f4a" } }
		for col, p in { 2, 1, 3 } do
			local i = ids[p]
			if not i then
				continue
			end
			local f = field[i]
			local x = (col - 1) * 116
			local h = HEIGHTS[p]
			local block = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, x, 1, 0), Size = UDim2.fromOffset(110, h), BackgroundColor3 = Ui.WHITE, ZIndex = 41, Parent = steps }, { Ui.corner(10), Ui.gradient(GRADS[p][1], GRADS[p][2]) })
			Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = hex(GRADS[p][2]), BorderSizePixel = 0, ZIndex = 41, Parent = block })
			Ui.text({ Text = tostring(p), TextSize = 28, Size = UDim2.fromScale(1, 1), ZIndex = 42, Parent = block })
			Ui.text({ Text = if i == me then "You" else f.name, Body = true, Weight = "heavy", TextSize = 12, TextColor3 = if i == me then hex("#e65100") else INK, TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, x, 1, -h - 4), Size = UDim2.fromOffset(110, 16), ZIndex = 41, Parent = steps })
			local pic = Thumb.car(f.model, UDim2.fromOffset(100, 70), { color = f.color, finish = f.finish or "gloss", stripe = f.stripe or false }, f.hat, f.mods, f.panels, f.trim, f.skin, f.modSkin)
			pic.AnchorPoint = Vector2.new(0.5, 1)
			pic.Position = UDim2.new(0, x + 55, 1, -h - 20)
			pic.ZIndex = 41
			pic.Parent = steps
		end
		-- Everyone, in order, with their times.
		local y = 58 + 166 + 10
		local list = Ui.new("Frame", { Name = "Results", Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, #ids * 22), BackgroundTransparency = 1, ZIndex = 41, Parent = card })
		for n, i in ids do
			local k = race.karts[i]
			local mine = i == me
			local row = Ui.new("Frame", { Position = UDim2.fromOffset(0, (n - 1) * 22), Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = if mine then hex("#fff3e0") else hex("#f1f4f6"), BackgroundTransparency = if mine or n % 2 == 1 then 0 else 1, ZIndex = 41, Parent = list }, { Ui.corner(8) })
			Ui.text({ Text = ord(n), Body = true, Weight = if mine then "heavy" else nil, TextSize = 14, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(40, 22), ZIndex = 41, Parent = row })
			Ui.text({ Text = if mine then "You" else field[i].name, Body = true, Weight = if mine then "heavy" else nil, TextSize = 14, TextColor3 = INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(48, 0), Size = UDim2.new(1, -120, 1, 0), ZIndex = 41, Parent = row })
			Ui.text({ Text = if k.done ~= nil then fmt(k.done) else "—", Body = true, TextSize = 13, TextColor3 = hex("#607d8b"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 0), Size = UDim2.fromOffset(70, 22), ZIndex = 41, Parent = row })
		end
		y += #ids * 22 + 10
		if refused then
			Ui.text({ Text = refused, Body = true, Weight = "heavy", TextSize = 14, TextWrapped = true, TextColor3 = hex("#c62828"), Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, 36), ZIndex = 41, Parent = card })
			y += 42
		else
			-- The prize: all of it for a win, the place's share otherwise (Kart.tsx's pay line).
			local prize = started.prize
			local text = if won then `🪙 +${Ui.commas(prize)}` else `🪙 +${Ui.commas(math.floor(prize * boosts.placeShare(finishPlace, #field) + 0.5))}`
			local w = math.ceil(Ui.textWidth(text, 18)) + 26
			local pill = Ui.new("Frame", { Name = "Pay", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(w, 28), BackgroundColor3 = hex("#fff3c4"), ZIndex = 41, Parent = card }, { Ui.round() })
			Ui.text({ Text = text, TextSize = 18, TextColor3 = INK, Size = UDim2.fromScale(1, 1), ZIndex = 41, Parent = pill })
			y += 38
		end
		-- Back, and the next race.
		local row = Ui.new("Frame", { Name = "Buttons", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y + 4), Size = UDim2.new(1, -36, 0, 46), BackgroundTransparency = 1, ZIndex = 41, Parent = card })
		local nb = nextButton()
		local backW = math.ceil(Ui.textWidth("Back", 16)) + 34
		local nextW = if nb then math.ceil(Ui.textWidth(nb.text, 16)) + 34 else 0
		local total = backW + (if nb then nextW + 8 else 0)
		local back = Ui.new("TextButton", { Name = "Back", Text = "", AutoButtonColor = false, Position = UDim2.new(0.5, -total / 2, 0, 0), Size = UDim2.fromOffset(backW, 44), BackgroundColor3 = Ui.WHITE, ZIndex = 42, Parent = row }, { Ui.corner(10), Ui.stroke(2, hex("#c62828")) })
		Ui.text({ Text = "Back", TextSize = 16, TextColor3 = hex("#c62828"), Size = UDim2.fromScale(1, 1), ZIndex = 42, Parent = back })
		back.Activated:Connect(close)
		if nb then
			local shadow, face = Ui.buy({ Name = "Next", Position = UDim2.new(0.5, -total / 2 + backW + 8, 0, 0), Size = UDim2.fromOffset(nextW, 44), Parent = row }, nb.text, "green", function()
				leave(nb.go)
			end, 16)
			for _, d in shadow:GetDescendants() do
				if d:IsA("GuiObject") then
					d.ZIndex = 42
				end
			end
			shadow.ZIndex = 42
			local _ = face
		end
		card.Size = UDim2.fromOffset(420, y + 4 + 44 + 18)
	end

	-- ── The loop ──────────────────────────────────────────────────────────────────────────────
	local clock = 0 -- seconds since the screen opened
	local goAt = 0.6 + 6 * 0.6 + math.random() * 0.4
	local running = false
	local acc = 0
	local function pose(k: any): { x: number, z: number, h: number, y: number }
		return { x = k.x, z = k.z, h = k.h, y = k.y }
	end
	local prev, drawn = {}, {}
	for i, k in race.karts do
		prev[i], drawn[i] = pose(k), pose(k)
	end
	local camPos: Vector3? = nil
	local camAt: Vector3? = nil
	local fovNow = 0
	local shake, kick = 0, 0
	local hero = -1 -- seconds into the finish hero shot; -2 once it's over
	local heroSkip = false
	local finished = false
	local podiumAt = math.huge
	local podiumUntil = math.huge
	local podiumRefresh = 0
	local podiumDone = 0 -- karts over the line when the podium was last drawn
	local flashUntil = 0
	local flashFrom = 0
	local callUntil = 0
	local hudAt = -1
	local near = nearMiss.nearMiss()
	local itemShown: string? = nil
	local reelAt = 0
	local skip: TextButton? = nil

	local function showFlash(text: string)
		Ui.setText(flash, text)
		flashFrom = clock
		flashUntil = clock + 1.1
	end

	local function finish()
		local k = race.karts[me]
		finishPlace = race:place(k)
		local time = k.done or race.t
		task.spawn(function()
			local ok, res = Remote.race("kartFinish", { place = finishPlace, time = time }, true)
			if ok then
				result = res
			else
				refused = if res == "too quick" then "That race finished too fast to count." else "The race server couldn't check that race."
			end
			if podium and not closed then
				drawPodium()
			end
		end)
		podiumAt = clock + 1.4
		podiumUntil = clock + 4
		hero = 0
		-- A tap skips the hero shot (the web's ⏭).
		local b = Ui.new("TextButton", { Name = "HeroSkip", Text = "⏭", TextSize = 20, TextColor3 = Ui.WHITE, FontFace = Ui.DISPLAY, AutoButtonColor = false, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = hex("#0a1428"), BackgroundTransparency = 0.55, Parent = screen }, { Ui.round() })
		b.Activated:Connect(function()
			heroSkip = true
			podiumAt = clock
		end)
		skip = b
	end

	local function frame(raw: number)
		local dt = math.min(raw, 1 / 20)
		clock += dt
		-- Five lights, one every 0.6 s, then all out: GO.
		local n = 0
		if not running then
			n = math.clamp(math.floor((clock - 0.6) / 0.6), 0, 5)
			if clock >= goAt then
				running = true
				n = 0
				showFlash("GO!")
			end
		end
		for i, lamp in lamps do
			local on = i <= n
			lamp.Color = hex(if on then "#ff1744" else "#3a1010")
			lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end

		-- The player's controls into the input every frame (pads wind on, the auto gas).
		if KartRun.autopilot and running then
			local auto = race:autoInput(race.karts[me], race:order(), false)
			input.steer, input.gas, input.brake, input.drift, input.item = auto.steer, auto.gas, auto.brake, auto.drift, auto.item
		elseif touch then
			if padDir == 0 then
				input.steer = 0
			elseif (if input.steer > 0 then 1 elseif input.steer < 0 then -1 else 0) ~= padDir then
				input.steer = padDir * 0.35
			else
				input.steer = padDir * math.min(1, math.abs(input.steer) + 1.5 * dt)
			end
			input.gas = if touchBrake then 0 else 1
			input.brake = if touchBrake then 1 else 0
		end

		-- Fixed steps of the race; the karts drawn between their last two.
		acc += dt
		local events = {}
		local ks = race.karts
		while acc >= STEP do
			acc -= STEP
			for i, k in ks do
				local p = prev[i]
				p.x, p.z, p.h, p.y = k.x, k.z, k.h, k.y
			end
			race:step(STEP, inputs, running)
			for _, e in race.events do
				table.insert(events, e)
			end
		end
		local alpha = math.min(1, acc / STEP)
		for i, k in ks do
			local a, o = prev[i], drawn[i]
			o.x = a.x + (k.x - a.x) * alpha
			o.z = a.z + (k.z - a.z) * alpha
			o.y = a.y + (k.y - a.y) * alpha
			o.h = a.h + wrap(k.h - a.h) * alpha
		end
		-- Knocks shake the camera, a drift turbo kicks the view wider; laps flash up.
		for _, e in events do
			if e.kart == meId then
				local kind = e.kind
				if kind == "wall" or kind == "bump" or kind == "pothole" then
					shake = math.max(shake, 0.18)
				elseif kind == "boxes" or kind == "glass" then
					shake = math.max(shake, 0.3)
				elseif kind == "hit" or kind == "boom" then
					shake = math.max(shake, 0.45)
				elseif kind == "land" then
					shake = math.max(shake, 0.12)
				elseif kind == "turbo" then
					kick = if e.value == 2 then 9 else 6
				elseif kind == "lap" then
					showFlash(if e.value == K.LAPS then "FINAL LAP!" else `LAP {e.value}`)
				end
			end
		end
		shake = math.max(0, shake - dt * 1.6)
		kick = math.max(0, kick - dt * 14)
		local mine = ks[me]
		if mine.done ~= nil and not finished then
			finished = true
			finish()
		end
		-- Near misses: another kart slips past close without touching.
		if running and mine.done == nil and nearMiss.stepNearMiss(near, mine, ks, race.t) then
			Ui.setText(callout, "Near miss!")
			callUntil = clock + 0.9
		end
		if clock > callUntil and callout.Text ~= "" then
			Ui.setText(callout, "")
		end

		-- The karts and what's on them.
		for i, k in ks do
			local v = views[i]
			local p = drawn[i]
			local sp = math.sqrt(k.vx * k.vx + k.vz * k.vz)
			local pitch = if k.air then math.clamp(-k.vy * 0.03, -0.25, 0.25) else 0
			local roll = -k.steer * math.min(1, sp / 15) * 0.06 - k.drift * 0.05
			local bob = 0
			if k.flat > 0 then
				roll += if k.id % 2 == 1 then -0.07 else 0.07
				bob = math.abs(math.sin(clock * 26)) * 0.05
			end
			local base = CFrame.new(W(p.x, 0, p.z)) * CFrame.Angles(0, p.h, 0)
			local body = base * CFrame.new(0, (p.y + bob) * S, 0) * CFrame.Angles(pitch, k.spinYaw + k.drift * 0.32, roll)
			v.model:PivotTo(body * v.offset)
			local fx = v.fx
			local back = -K.KART_LEN / 2 - 0.05
			local sparking = k.drift ~= 0 and k.charge > K.DRIFT_BLUE * 0.6 and not k.air
			local sparkColor = hex(if k.charge >= K.DRIFT_ORANGE then "#ff9100" elseif k.charge >= K.DRIFT_BLUE then "#40c4ff" else "#fff59d")
			for sd, name in { [-1] = "sparkL", [1] = "sparkR" } do
				local s = fx[name]
				s.Transparency = if sparking then 0.1 else 1
				if sparking then
					s.Color = sparkColor
					s.CFrame = body * CFrame.new(sd * 0.5 * S, 0.12 * S, (back + 0.25) * S)
				end
			end
			fx.flame.Transparency = if k.boost > 0 then 0.15 else 1
			if k.boost > 0 then
				fx.flame.CFrame = body * CFrame.new(0, 0.3 * S, (back - 0.25) * S)
				fx.flame.Size = Vector3.new(0.36, 0.36, 0.5 + math.random() * 0.6) * S
			end
			fx.shield.Transparency = if k.shield > 0 then 0.72 else 1
			if k.shield > 0 then
				fx.shield.CFrame = body * CFrame.new(0, 0.45 * S, 0)
			end
			local zapOn = k.emp > 0 and math.random() > 0.25
			fx.zap.Transparency = if zapOn then 0.2 else 1
			if zapOn then
				fx.zap.CFrame = body * CFrame.new(0, 0.5 * S, 0) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)
			end
			fx.magnet.Transparency = if k.tow > 0 then 0 else 1
			if k.tow > 0 then
				fx.magnet.CFrame = body * CFrame.new(0, 1.25 * S, 0.2 * S)
			end
			local ghosted = k.ghost > 0
			if ghosted ~= v.ghosted then
				v.ghosted = ghosted
				for _, bp in v.parts do
					bp.LocalTransparencyModifier = if ghosted then 0.65 else 0
				end
			end
			fx.ghost.Transparency = if ghosted then 0.8 else 1
			if ghosted then
				fx.ghost.CFrame = body * CFrame.new(0, 0.55 * S, 0)
			end
			fx.rocket.Transparency = if k.rocket > 0 then 0 else 1
			fx.rocketFlame.Transparency = if k.rocket > 0 then 0.1 else 1
			if k.rocket > 0 then
				fx.rocket.CFrame = body * CFrame.new(0, 1.05 * S, -0.15 * S) * CFrame.Angles(0, math.pi / 2, 0)
				fx.rocketFlame.CFrame = body * CFrame.new(0, 1.05 * S, (-0.15 - 1.75 * 0.8) * S)
			end
			fx.splat.Transparency = if k.splat > 0 then 0 else 1
			if k.splat > 0 then
				fx.splat.CFrame = body * CFrame.new(0, 0.62 * S, 0.45 * S) * CFrame.Angles(0, 0, math.pi / 2)
			end
			-- The tow beam to the kart being reeled in.
			local beam = beams(i)
			local o = if k.tow > 0 and k.towTarget >= 0 then drawn[k.towTarget + 1] else nil
			beam.Transparency = if o then 0.3 else 1
			if o then
				local a = W(p.x + math.sin(p.h) * 0.4, 1.3 + p.y, p.z + math.cos(p.h) * 0.4)
				local b = W(o.x, 0.7 + o.y, o.z)
				local w = 1 + math.sin(clock * 30) * 0.35
				beam.Size = Vector3.new(0.14 * w * S, 0.14 * w * S, (b - a).Magnitude)
				beam.CFrame = CFrame.lookAt((a + b) / 2, b)
			end
		end
		do
			local p = drawn[me]
			ring.CFrame = CFrame.new(W(p.x, Y_PAINT + 0.02, p.z)) * CFrame.Angles(0, 0, math.pi / 2)
		end

		-- Crates bob and turn, gone for three seconds after a pick-up.
		for i, c in t.crates do
			local since = race.t - race.crateTaken[i]
			local grow = if since < 3 then 0 else math.min(1, (since - 3) * 3)
			local cr = crates[i]
			cr.Transparency = if grow < 0.05 then 1 else 0.08
			if grow >= 0.05 then
				cr.Size = Vector3.new(0.62, 0.62, 0.62) * S * grow
				cr.CFrame = CFrame.new(W(c.x, 0.75 + math.sin(clock * 2.5 + i) * 0.12, c.z)) * CFrame.Angles(0.5, clock * 1.6 + i, 0.4)
			end
		end
		KartWorld.moveGlass(race, glass)
		-- Cones: knocked flying, back on their spot later.
		if #coneList > 0 then
			cones.stepCones(coneList, ks, race.t, math.min(dt, 0.05))
			for i, c in coneList do
				coneParts[i].CFrame = CFrame.new(W(c.x, c.y + 0.35, c.z)) * CFrame.Angles(c.rx, 0, c.rz)
			end
		end

		-- Hazards: oil slicks, tack strips, smoke clouds, hornets, bumper bombs and their blasts.
		for i = 1, math.max(#race.oil, 0) + 0 do
			local h = race.oil[i]
			local o = oil(i)
			o.Transparency = 0.1
			o.CFrame = CFrame.new(W(h.x, Y_PAINT + 0.01, h.z)) * CFrame.Angles(0, 0, math.pi / 2)
		end
		for i = #race.oil + 1, 12 do
			oil(i).Transparency = 1
		end
		for i = 1, 8 do
			local h = race.tacks[i]
			local m = mats(i)
			m.Transparency = if h then 0 else 1
			if h then
				m.CFrame = CFrame.new(W(h.x, Y_PAINT + 0.012, h.z)) * CFrame.Angles(0, h.h, 0)
			end
			for j = 0, 8 do
				local sp = spikes((i - 1) * 9 + j + 1)
				sp.Transparency = if h then 0 else 1
				if h then
					local a = (j / 8 - 0.5) * 2.3
					local side, sideZ = math.cos(h.h), -math.sin(h.h)
					local off = if j % 2 == 1 then 0.18 else -0.18
					sp.CFrame = CFrame.new(W(h.x + side * a + off * math.sin(h.h), 0.16, h.z + sideZ * a + off * math.cos(h.h)))
				end
			end
		end
		for i = 1, 6 do
			local c = race.smoke[i]
			local age = if c then race.t - c.t else 0
			local grow = math.min(1, 0.4 + age * 1.5) * (if c then math.min(1, (7 - age) / 1.5) else 0)
			for j = 0, 15 do
				local pf = puffs((i - 1) * 16 + j + 1)
				pf.Transparency = if c and grow > 0.02 then 0.4 else 1
				if c and grow > 0.02 then
					local a = j * 2.4 + clock * (0.3 + (j % 3) * 0.1)
					local r = K.SMOKE_R * (0.15 + ((j * 37) % 10) / 12)
					local s = (0.75 + (j % 4) * 0.22) * grow
					pf.Size = Vector3.new(2, 2, 2) * s * S
					pf.CFrame = CFrame.new(W(c.x + math.cos(a) * r * grow, 0.4 + (j % 5) * 0.32 + math.sin(clock * 0.8 + j) * 0.15 + age * 0.1, c.z + math.sin(a) * r * grow))
				end
			end
		end
		for i = 1, 6 do
			local h = race.hornets[i]
			local b = hornets(i)
			b.Transparency = if h then 0 else 1
			if h then
				b.CFrame = CFrame.new(W(h.x, 0.9 + math.sin(clock * 20 + i) * 0.08, h.z)) * CFrame.Angles(0, clock * 6, 0)
			end
		end
		local fade = nil
		for _, h in race.bombs do
			if h.boom then
				fade = h
				break
			end
		end
		for i = 1, 4 do
			local h = race.bombs[i]
			local bm, fu, bl = bombs(i), fuses(i), blasts(i)
			local u = if h then math.min(1, (race.t - h.t) / 0.8) else 0
			local flying = h and not h.boom
			bm.Transparency = if flying then 0 else 1
			fu.Transparency = if flying then 0 else 1
			if flying then
				local at = W(h.sx + (h.x - h.sx) * u, 0.9 + math.sin(u * math.pi) * 5, h.sz + (h.z - h.sz) * u)
				bm.CFrame = CFrame.new(at) * CFrame.Angles(u * 9, 0, u * 5)
				fu.CFrame = CFrame.new(at + Vector3.new(0, 0.6 * S, 0))
				fu.Size = Vector3.new(1, 1, 1) * (0.24 + math.random() * 0.2) * S
			end
			local age = if h and h.boom then race.t - h.t - 0.8 else -1
			bl.Transparency = if age >= 0 and fade then math.clamp(1 - math.max(0, 0.75 - (race.t - fade.t - 0.8) * 1.2), 0, 1) else 1
			if age >= 0 then
				local r = K.BOMB_R * math.min(1, 0.35 + age * 4)
				bl.Size = Vector3.new(2, 2, 2) * r * S
				bl.CFrame = CFrame.new(W(h.x, 0.6, h.z))
			end
		end

		-- The camera: behind and above the kart, swinging wide in a drift, back on a boost; the
		-- hero shot round it after the line.
		local size = cam.ViewportSize
		local tall = size.Y > size.X
		local pm = drawn[me]
		local fwd = Vector3.new(math.sin(pm.h), 0, math.cos(pm.h))
		local mv = math.sqrt(mine.vx * mine.vx + mine.vz * mine.vz)
		if hero >= 0 and not heroSkip and hero + dt < HERO_TIME then
			hero += dt
			local pos, at = heroCam(hero, pm.x, pm.y, pm.z, pm.h, K.KART_LEN, 1, K.KART_LEN * 2.2)
			camPos, camAt = W(pos.X, pos.Y, pos.Z), W(at.X, at.Y, at.Z)
			cam.CFrame = CFrame.lookAt(camPos :: Vector3, camAt :: Vector3)
			fovNow = if tall then 60 else 42
			cam.FieldOfView = fovNow
		else
			if hero >= 0 then
				hero = -2
			end
			local backBy = (if tall then 7.4 else 6.0) + (if mine.boost > 0 then 0.6 else 0)
			local up = if tall then 3.7 else 3.0
			local swing = mine.drift * 0.35
			local want = W(pm.x - math.sin(pm.h - swing) * backBy, up + pm.y * 0.6, pm.z - math.cos(pm.h - swing) * backBy)
			camPos = if camPos then camPos:Lerp(want, math.min(1, dt * 7)) else want
			local at = W(pm.x + fwd.X * 4, 0.55 + pm.y * 0.8, pm.z + fwd.Z * 4)
			camAt = if camAt then camAt:Lerp(at, math.min(1, dt * 10)) else at
			local pos = camPos :: Vector3
			if shake > 0 then
				pos += Vector3.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake * 0.6, (math.random() - 0.5) * shake) * S
			end
			cam.CFrame = CFrame.lookAt(pos, camAt :: Vector3)
			local fov = (if tall then 70 else 58) + (if mine.boost > 0 then 7 else 0) + math.min(5, mv * 0.2)
			fovNow = if fovNow == 0 then fov else fovNow + (fov - fovNow) * math.min(1, dt * 4)
			cam.FieldOfView = fovNow + kick
		end

		-- The flash grows in, holds and fades (kt-pop).
		if clock < flashUntil then
			local u = (clock - flashFrom) / 1.1
			flashScale.Scale = if u < 0.15 then 0.4 + u / 0.15 * 0.72 elseif u < 0.3 then 1.12 - (u - 0.15) / 0.15 * 0.12 else 1
			local tr = if u < 0.15 then 1 - u / 0.15 elseif u > 0.8 then (u - 0.8) / 0.2 else 0
			flash.TextTransparency = tr
			local face = flash:FindFirstChild("Face") :: TextLabel?
			if face then
				face.TextTransparency = tr
			end
			flash.TextTransparency = math.max(tr, 0.6)
		elseif flash.Text ~= "" then
			Ui.setText(flash, "")
		end

		-- The podium, once the hero shot is done (or skipped), a few seconds at most.
		if finished and not ended and clock >= podiumAt and (hero < 0 or heroSkip or clock >= podiumUntil) then
			ended = true
			table.clear(keysDown)
			applyKeys()
			if skip then
				skip:Destroy()
			end
			drawPodium()
			podiumRefresh = clock
			for _, k in ks do
				if k.done ~= nil then
					podiumDone += 1
				end
			end
		end
		if ended and clock - podiumRefresh >= 0.5 then
			-- Finishers who came in after the podium went up still slot into the list.
			podiumRefresh = clock
			local done = 0
			for _, k in ks do
				if k.done ~= nil then
					done += 1
				end
			end
			if done ~= podiumDone then
				podiumDone = done
				drawPodium()
			end
		end

		-- The HUD, ten times a second.
		if clock - hudAt >= 0.1 then
			hudAt = clock
			local show = running and not ended
			hudRow.Visible = show
			map.Visible = show
			slot.Visible = show and not touch
			controls.Visible = running and not ended
			if show then
				local place = race:place(mine)
				Ui.setText(placeBig, tostring(place))
				Ui.setText(placeSmall, string.sub(ord(place), -2))
				local pc = if PLACE[place] then hex(PLACE[place]) else Ui.WHITE
				Ui.setColor(placeBig, pc)
				Ui.setColor(placeSmall, pc)
				Ui.setText(lapNum, tostring(math.max(1, math.min(3, mine.lap))))
				timeText.Text = fmt(race.t)
				catchChip.Visible = K.catchUp(place - 1, #field) > 0
				layoutHud(place)
				for i, k in ks do
					local x, y = mapAt(k.x, k.z)
					dots[i].Position = UDim2.fromOffset(x, y)
				end
				-- The item: a fresh one spins through the reel before it lands.
				local item = mine.item
				if item ~= itemShown then
					itemShown = item
					reelAt = clock
				end
				local dead = mine.emp > 0
				local icon = ""
				if item then
					local n2 = math.floor((clock - reelAt) / 0.07)
					icon = if n2 >= 8 then K.ITEMS[item].icon else K.ITEMS[ITEM_ORDER[(n2 * 3) % #ITEM_ORDER + 1]].icon
				end
				Ui.setText(slotIcon, icon)
				slotGrad.Enabled = item ~= nil and not dead
				slot.BackgroundTransparency = if item and not dead then 0 else 0.5
				slot.BackgroundColor3 = if item and not dead then Ui.WHITE else hex("#0a1428")
				slotStroke.Color = if item and not dead then hex("#ffd740") else Ui.WHITE
				slotStroke.Transparency = if item and not dead then 0 else 0.3
				uses.Visible = item == "nitro3"
				Ui.setText(usesText, `×{mine.uses}`)
				if itemBtn and itemBtnIcon then
					itemBtnIcon.Text = if item then icon else "ITEM"
					itemBtnIcon.TextSize = if item then 38 else 13
					itemBtn.BackgroundColor3 = if item and not dead then hex("#7c4dff") else hex("#0a1428")
					itemBtn.BackgroundTransparency = if item and not dead then 0 else 0.5
				end
				local ch = if mine.drift ~= 0 then mine.charge else 0
				charge.Visible = ch > 0
				chargeFill.Size = UDim2.fromScale(math.min(1, ch / K.DRIFT_ORANGE), 1)
				chargeFill.BackgroundColor3 = hex(if ch >= K.DRIFT_ORANGE then "#ff9100" elseif ch >= K.DRIFT_BLUE then "#40c4ff" else "#fff59d")
				local dir = t.tx[mine.idx] * math.sin(mine.h) + t.tz[mine.idx] * math.cos(mine.h)
				wrongWay.Visible = dir < -0.5 and mv > 2
				wrongWay.BackgroundTransparency = if math.floor(clock * 2) % 2 == 0 then 0 else 0.45
				-- Effects: a badge each, and the screen overlays.
				local x = 0
				for i, f in FX do
					local left = mine[f.key]
					local b = fxBadges[i]
					b.frame.Visible = left > 0
					if left > 0 then
						b.frame.Position = UDim2.fromOffset(x, 0)
						b.stroke.Transparency = 1 - math.min(1, left / f.full) * 0.9
						x += 46
					end
				end
				haze.Visible = mine.smoke > 0
				haze.BackgroundTransparency = 1 - math.min(1, mine.smoke / K.SMOKE_TIME + 0.35) * 0.7
				zap.Visible = mine.emp > 0
				splat.Visible = mine.splat > 0
				ghostGlow.Visible = mine.ghost > 0
			else
				charge.Visible = false
				wrongWay.Visible = false
				haze.Visible, zap.Visible, splat.Visible, ghostGlow.Visible = false, false, false, false
				for _, b in fxBadges do
					b.frame.Visible = false
				end
			end
		end
		if zap.Visible then
			local st = zap:FindFirstChildOfClass("UIStroke")
			if st then
				st.Thickness = if math.floor(clock / 0.045) % 2 == 0 then 36 else 18
			end
		end
	end
	RunService:BindToRenderStep("KartRun", Enum.RenderPriority.Camera.Value + 2, frame)
	return close
end

return KartRun
