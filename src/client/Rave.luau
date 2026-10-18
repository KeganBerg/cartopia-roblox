--!strict
-- Rave Mode, as the web game's game/techno.ts (converted), ui/Techno.tsx, scene/TechnoLights.tsx
-- and the heads-up in ui/FlashWarning.tsx. The whole town drops into the night (techno.ts forces
-- the town clock, which DayNight follows), a ten-second build-up, then the drop: the screen edges
-- glow in a new colour on every beat, lasers sweep over the town, the drop flashes, the RAVE MODE
-- title lands, a tag in the HUD counts down, and every neon light in town (street lamps, signs,
-- the club's windows) flashes the club's colour on the kick, back to normal afterwards.
--
-- It comes on:
--   - when the DJ (Kegan's account: the server checks, see server/Rave.luau) presses the Neon
--     Owl's Rave button: Workspace's RaveFrom / RaveUntil attributes, the same for every player;
--   - every Friday at 10:00 pm on the player's own clock, for a minute (RaveTime.weekly).
--
-- No music plays from here (the game's music player owns that). Its hook: Rave.onChange(fn) calls
-- fn(on, window) when Rave Mode starts or stops, and the LocalPlayer carries RaveOn, RaveDrop and
-- RaveUntil attributes (ms, this device's clock) for anything that would rather not require this.
-- The beat itself is techno.technoBeat(now) / techno.technoDrop() from Shared.Game.techno: the
-- music runs on the wall clock from the drop, so everyone hears the same bar.
--
-- Reduce flashing (web game/flashing.ts) is the LocalPlayer's CalmFlashing attribute: the glow
-- swells slowly, the colour moves on once a bar, no strobe, lasers or title. Roblox's reduced
-- motion setting drops the movement too.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local techno = require(Game:WaitForChild("techno")) :: any
local clock = require(Game:WaitForChild("clock")) :: any
local RaveTime = require(Shared:WaitForChild("RaveTime"))
local Ui = require(script.Parent.Ui)

local Rave = {}

local LINE = Ui.LINE
local RAINBOW = { "#ff1744", "#ff9100", "#ffea00", "#00e676", "#00b0ff", "#d500f9" }
local HEADS_UP_S = 9

-- The screen's size (a ScreenGui that ignores the inset covers the camera's viewport).
local function screen(): Vector2
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.zero
	return if v.X < 2 then Vector2.new(1280, 800) else v
end

local function nowMs(): number
	return DateTime.now().UnixTimestampMillis
end

-- CSS hsl(h 100% l%) as a Color3.
local function hsl(h: number, l: number): Color3
	local function f(n: number): number
		local k = (n + h / 30) % 12
		local a = math.min(l, 1 - l)
		return l - a * math.max(-1, math.min(k - 3, 9 - k, 1))
	end
	return Color3.new(f(0), f(8), f(4))
end

local function ease(t: number): number
	-- CSS ease-in-out, near enough.
	return t * t * (3 - 2 * t)
end

function Rave.calm(): boolean
	local p = Players.LocalPlayer
	return p ~= nil and p:GetAttribute("CalmFlashing") == true
end
function Rave.setCalm(on: boolean)
	local p = Players.LocalPlayer
	if p then
		p:SetAttribute("CalmFlashing", on)
	end
end
local function reducedMotion(): boolean
	local ok, on = pcall(function()
		return (GuiService :: any).ReducedMotionEnabled
	end)
	return ok and on == true
end

function Rave.isOn(now: number?): boolean
	return techno.technoOn(now or nowMs())
end

-- The rave now on: when it built up, dropped and ends (ms, this device's clock), or nil.
local window: RaveTime.Window? = nil
function Rave.window(): RaveTime.Window?
	return if Rave.isOn() then window else nil
end

local changed = Instance.new("BindableEvent")
-- Calls fn(on, window) whenever Rave Mode starts or stops. Returns the connection.
function Rave.onChange(fn: (boolean, RaveTime.Window?) -> ()): RBXScriptConnection
	return changed.Event:Connect(fn)
end

-- Kegan's account: the experience's owner (or the owning group's owner). The server checks again.
function Rave.isDj(): boolean
	local p = Players.LocalPlayer
	if not p then
		return false
	end
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId ~= 0 and p.UserId == game.CreatorId
	end
	local ok, rank = pcall(function()
		return p:GetRankInGroup(game.CreatorId)
	end)
	return ok and rank == 255
end

-- Starts (or extends) the rave from a window, the way techno.startEvent does on the web.
local function begin(w: RaveTime.Window)
	window = w
	techno.startEvent("techno", { from = w.from, drop = w.drop, ["until"] = w.to })
end
-- For the emulator and tests: a rave starting now (or at `from`), with no end unless given.
function Rave.startTest(from: number?, to: number?)
	local f = from or nowMs()
	begin({ from = f, drop = f + techno.BUILD_MS, to = to or f + 3600000 })
end
function Rave.stop()
	techno.stopEvent("techno")
end

-- ---------- The light show over the screen (ui/Techno.tsx TechnoLayer) ----------
type Layer = {
	gui: ScreenGui,
	glow: { Frame },
	dark: { Frame },
	lasers: { Frame },
	strobe: Frame,
	count: TextLabel,
	countScale: UIScale,
	title: Frame,
	titleScale: UIScale,
	titleText: TextLabel,
	sub: TextLabel,
	subBox: Frame,
	subStroke: UIStroke,
}
local layer: Layer? = nil

local function edge(parent: Instance, name: string, pos: UDim2, size: UDim2, anchor: Vector2, rot: number): Frame
	return Ui.new("Frame", { Name = name, AnchorPoint = anchor, Position = pos, Size = size, BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), Parent = parent }, {
		Ui.new("UIGradient", { Rotation = rot, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.45, 0.6), NumberSequenceKeypoint.new(1, 1) }) }),
	})
end

local function buildLayer(): Layer
	local gui: ScreenGui = Ui.new("ScreenGui", {
		Name = "RaveMode",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		-- Under the HUD (theme.css .techno-fx and .techno-words sit under it): every control
		-- works as normal.
		DisplayOrder = -1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Players.LocalPlayer:WaitForChild("PlayerGui"),
	})
	-- .tk-glow: the screen edges glow inwards, over a dark vignette.
	local glow, dark = {}, {}
	local sides = {
		{ "Top", UDim2.fromScale(0, 0), Vector2.new(0, 0), 90, true },
		{ "Bottom", UDim2.fromScale(0, 1), Vector2.new(0, 1), -90, true },
		{ "Left", UDim2.fromScale(0, 0), Vector2.new(0, 0), 0, false },
		{ "Right", UDim2.fromScale(1, 0), Vector2.new(1, 0), 180, false },
	}
	for _, s in sides do
		local wide = s[5] :: boolean
		local d = edge(gui, `Dark{s[1]}`, s[2] :: UDim2, if wide then UDim2.new(1, 0, 0.3, 0) else UDim2.new(0.25, 0, 1, 0), s[3] :: Vector2, s[4] :: number)
		d.BackgroundColor3 = Color3.fromRGB(8, 0, 30)
		table.insert(dark, d)
	end
	for _, s in sides do
		local wide = s[5] :: boolean
		table.insert(glow, edge(gui, `Glow{s[1]}`, s[2] :: UDim2, if wide then UDim2.new(1, 0, 0, 100) else UDim2.new(0, 100, 1, 0), s[3] :: Vector2, s[4] :: number))
	end
	-- .tk-lasers: four beams from the bottom corners sweeping over the town.
	local lasers = {}
	for i = 1, 4 do
		table.insert(lasers, Ui.new("Frame", {
			Name = `Laser{i}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(5, 100),
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = gui,
		}, {
			Ui.new("UIGradient", {
				Rotation = -90,
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(0.7, 0.5), NumberSequenceKeypoint.new(1, 1) }),
			}),
		}))
	end
	-- .tk-strobe: a flash over everything on the drop.
	local strobe = Ui.new("Frame", { Name = "Strobe", Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, Parent = gui })
	-- .tk-count: the last five seconds, big, over the town.
	local count = Ui.text({ Name = "Count", Text = "", TextSize = 120, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(240, 150), Stroke = 3, Parent = gui })
	local countScale = Ui.new("UIScale", { Parent = count })
	-- .tk-title: RAVE MODE lands on the drop, then fades away.
	local title = Ui.new("Frame", { Name = "Title", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(460, 110), BackgroundTransparency = 1, Visible = false, Parent = gui })
	local titleScale = Ui.new("UIScale", { Parent = title })
	local titleText = Ui.text({ Name = "Big", Text = "RAVE MODE", TextSize = 64, Position = UDim2.fromScale(0, 0), Size = UDim2.new(1, 0, 0, 66), Stroke = 2, Parent = title })
	local subText = `{techno.TECHNO_BPM} BPM · EVERY TOWN`
	local subW = Ui.textWidth(subText, 15) + 24 + 2 * 15
	local subBox = Ui.new("Frame", { Name = "Sub", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 74), Size = UDim2.fromOffset(subW, 26), BackgroundColor3 = Color3.fromRGB(10, 6, 30), BackgroundTransparency = 0.3, Parent = title }, {
		Ui.corner(10),
	})
	local subStroke = Ui.stroke(2, Color3.new(1, 1, 1))
	subStroke.Parent = subBox
	local sub = Ui.text({ Name = "Text", Text = subText, TextSize = 15, Size = UDim2.fromScale(1, 1), Parent = subBox })
	return { gui = gui, glow = glow, dark = dark, lasers = lasers, strobe = strobe, count = count, countScale = countScale, title = title, titleScale = titleScale, titleText = titleText, sub = sub, subBox = subBox, subStroke = subStroke }
end

-- Where each laser stands (share of the screen's width from the left) and the angles it sweeps
-- between (degrees), with its head start (s) through the 3.2-second sweep.
local LASERS = {
	{ x = 0.06, a = -38, b = 12, delay = 0 },
	{ x = 0.08, a = -10, b = 40, delay = -1.6 },
	{ x = 0.92, a = 10, b = -40, delay = -0.8 },
	{ x = 0.94, a = 38, b = -12, delay = -2.4 },
}

local droppedAt: number? = nil
local function drawLayer(L: Layer, b: any, toDrop: number, t: number, soft: boolean, calmish: boolean)
	local view = screen()
	local phone = view.X <= 600
	-- --tk: the kick (a slow swell with Reduce flashing), --tk-h: a new colour each beat (each bar).
	local swell = 0.2 + 0.12 * math.sin((b.n / 32) * math.pi)
	local tk = if soft then swell elseif calmish then b.kick * 0.4 else b.kick
	local h = ((if soft then b.bar * 67 else b.beat * 67) % 360 + 360) % 360
	local c = hsl(h, 0.55)
	local build = b.build
	local drop = if calmish then 0 else b.drop
	-- Glow: inset 0 0 (50 + tk*90)px (tk*14)px, alpha .25 + tk*.4 - build*.2.
	local thick = 50 + tk * 90 + tk * 14
	local alpha = math.clamp(0.25 + tk * 0.4 - build * 0.2, 0, 1)
	for i, g in L.glow do
		g.BackgroundColor3 = c
		g.BackgroundTransparency = 1 - alpha
		g.Size = if i <= 2 then UDim2.new(1, 0, 0, thick) else UDim2.new(0, thick, 1, 0)
	end
	local da = math.clamp(0.18 + build * 0.35, 0, 1)
	for _, d in L.dark do
		d.BackgroundTransparency = 1 - da
	end
	-- Lasers: opacity .18 + tk*.45, the whole set fading in through the build-up.
	local laserOn = not calmish
	local la = (0.18 + tk * 0.45) * (if toDrop > 0 then 0.25 + build * 0.75 else 1)
	local len = view.Y * 1.5
	for i, l in L.lasers do
		l.Visible = laserOn
		if laserOn then
			local s = LASERS[i]
			local p = ((t - s.delay) / 3.2) % 2
			local k = ease(if p < 1 then p else 2 - p)
			local ang = s.a + (s.b - s.a) * k
			local foot = Vector2.new(view.X * s.x, view.Y * 1.1)
			local r = math.rad(ang)
			local mid = foot + Vector2.new(math.sin(r), -math.cos(r)) * len / 2
			l.Position = UDim2.fromOffset(mid.X, mid.Y)
			l.Size = UDim2.fromOffset(5, len)
			l.Rotation = ang
			l.BackgroundColor3 = hsl(h, 0.65)
			l.BackgroundTransparency = 1 - math.clamp(la, 0, 1)
		end
	end
	L.strobe.Visible = not calmish
	-- An overlay-blended white at .32 on the web; a plain white reads as strong at about half that.
	L.strobe.BackgroundTransparency = 1 - drop * 0.16
	-- The countdown: the last five seconds, each one popping in big and settling.
	local secs = if toDrop > 0 and toDrop <= 5000 then math.ceil(toDrop / 1000) else 0
	L.count.Visible = secs > 0
	if secs > 0 then
		L.count.TextSize = if phone then 84 else 120
		Ui.setText(L.count, tostring(secs))
		-- How far through this second's number (it appeared as the clock reached secs).
		local f = (secs * 1000 - toDrop) / 1000
		local sc, op = 1, 1
		if not calmish then
			if f < 0.15 then
				sc, op = 1.8 - 0.8 * (f / 0.15), f / 0.15
			elseif f > 0.85 then
				sc, op = 1 - 0.15 * ((f - 0.85) / 0.15), 1 - (f - 0.85) / 0.15
			end
		end
		L.countScale.Scale = sc
		L.count.TextTransparency = 1 - op
		local st = L.count:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = 1 - op
		end
	end
	-- The title lands on the drop and fades out over 3.2 s (none at all with Reduce flashing).
	if toDrop <= 0 and droppedAt == nil then
		droppedAt = t
	end
	local show = droppedAt ~= nil and not calmish
	L.title.Visible = show
	if show then
		local f = (t - (droppedAt :: number)) / 3.2
		local sc, op
		if f < 0.12 then
			sc, op = 0.6 + 0.46 * (f / 0.12), f / 0.12
		elseif f < 0.2 then
			sc, op = 1.06 - 0.06 * ((f - 0.12) / 0.08), 1
		elseif f < 0.8 then
			sc, op = 1, 1
		else
			local g = math.min(1, (f - 0.8) / 0.2)
			sc, op = 1 + 0.1 * g, 1 - g
		end
		L.titleScale.Scale = sc * (if phone then 38 / 64 else 1) * (1 + b.kick * 0.08)
		L.titleText.TextTransparency = 1 - op
		for _, st in { L.titleText:FindFirstChildOfClass("UIStroke"), L.subStroke } do
			if st then
				st.Transparency = 1 - op
				if st == L.subStroke then
					st.Color = c
				end
			end
		end
		L.sub.TextTransparency = 1 - op
		L.subBox.BackgroundTransparency = 1 - 0.7 * op
	end
end

-- ---------- The tag in the HUD (TechnoTag): an equaliser and the time to the drop, then left ----------
type Tag = { frame: Frame, stroke: UIStroke, bars: { Frame }, left: TextLabel, name: TextLabel }
local tag: Tag? = nil
local function buildTag(): Tag?
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("Cartopia")
	local center = hud and hud:FindFirstChild("Center", true)
	if not center then
		return nil
	end
	local w = 7 + 18 + 6 + Ui.textWidth("RAVE MODE", 13) + 6 + Ui.textWidth("DROP IN 0:00", 13) + 9 + 4
	local frame = Ui.new("Frame", { Name = "RaveTag", LayoutOrder = -1, Size = UDim2.fromOffset(w, 22), BackgroundColor3 = Color3.new(1, 1, 1), Parent = center }, {
		Ui.corner(10),
		Ui.gradient("#2a1150", "#12082b"),
	})
	local stroke = Ui.stroke(2, Color3.new(1, 1, 1))
	stroke.Parent = frame
	local bars = {}
	for i = 1, 4 do
		table.insert(bars, Ui.new("Frame", { Name = `Eq{i}`, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromOffset(7 + (i - 1) * 5, 17), Size = UDim2.fromOffset(3, 6), BorderSizePixel = 0, Parent = frame }, { Ui.corner(1) }))
	end
	local name = Ui.text({ Name = "Name", Text = "RAVE MODE", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(7 + 18 + 6, 0), Size = UDim2.new(0, Ui.textWidth("RAVE MODE", 13) + 2, 1, 0), Parent = frame })
	local left = Ui.text({ Name = "Left", Text = "", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(7 + 18 + 6 + Ui.textWidth("RAVE MODE", 13) + 6, 0), Size = UDim2.new(0, Ui.textWidth("DROP IN 0:00", 13) + 4, 1, 0), Parent = frame })
	return { frame = frame, stroke = stroke, bars = bars, left = left, name = name }
end

local function drawTag(T: Tag, b: any, now: number, tk: number, h: number)
	local c = hsl(h, 0.6)
	T.stroke.Color = c
	local heights = { 0.25 + tk * 0.75, 0.55 + tk * 0.45 * b.side, 0.4 + tk * 0.6, 0.7 - tk * 0.4 }
	if math.floor(now / 100) % 2 == 0 then
		heights[3] = 0.35
	end
	for i, bar in T.bars do
		bar.BackgroundColor3 = c
		bar.Size = UDim2.fromOffset(3, math.max(1, math.floor(13 * math.clamp(heights[i], 0, 1) + 0.5)))
	end
	local toDrop = techno.technoToDrop(now)
	local left = if toDrop > 0 then toDrop else techno.technoLeft(now)
	local text = ""
	if left ~= nil then
		local secs = if toDrop > 0 then math.ceil(left / 1000) else math.floor(left / 1000)
		text = `{if toDrop > 0 then "DROP IN " else ""}{secs // 60}:{string.format("%02d", secs % 60)}`
	end
	Ui.setText(T.left, text)
	T.left.TextColor3 = hsl(h, 0.75)
	-- The tag hugs what it shows.
	local w = 7 + 18 + 6 + Ui.textWidth("RAVE MODE", 13) + (if text ~= "" then 6 + Ui.textWidth(text, 13) else 0) + 9
	T.frame.Size = UDim2.fromOffset(w, 22)
end

-- ---------- The heads-up as it starts building (FlashWarning.tsx RaveHeadsUp) ----------
local headsUp: ScreenGui? = nil
local function switch(parent: Instance, x: number): (TextButton, () -> ())
	local s = Ui.new("TextButton", { Name = "Reduce", Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(x, 12), Size = UDim2.fromOffset(38, 22), BackgroundColor3 = Color3.fromHex("#5b4a7a"), Parent = parent }, { Ui.round() })
	local knob = Ui.new("Frame", { Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.new(1, 1, 1), Parent = s }, { Ui.round() })
	local function draw()
		local on = Rave.calm()
		s.BackgroundColor3 = if on then Color3.fromHex("#2fae35") else Color3.fromHex("#5b4a7a")
		knob.Position = if on then UDim2.new(1, -19, 0.5, 0) else UDim2.new(0, 3, 0.5, 0)
	end
	s.Activated:Connect(function()
		Rave.setCalm(not Rave.calm())
		draw()
	end)
	draw()
	return s, draw
end
local function showHeadsUp()
	if headsUp then
		headsUp:Destroy()
	end
	local gui: ScreenGui = Ui.new("ScreenGui", { Name = "RaveHeadsUp", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 5, Parent = Players.LocalPlayer:WaitForChild("PlayerGui") })
	headsUp = gui
	local phone = screen().X <= 600
	local big = if phone then 14 else 16
	local textW = math.max(Ui.textWidth("⚡ Flashing lights ahead", big), Ui.textWidth("Rave Mode is starting", 12)) + 4
	local reduceW = Ui.textWidth("Reduce", 13)
	local w = 12 + textW + 10 + reduceW + 6 + 38 + 10 + 26 + 8
	local box = Ui.new("Frame", { Name = "Box", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, if phone then 118 else 126), Size = UDim2.fromOffset(w, 46), BackgroundColor3 = Color3.new(1, 1, 1), Parent = gui }, {
		Ui.corner(14),
		Ui.gradient("#2a1150", "#12082b"),
		Ui.stroke(2.5, Color3.fromHex("#ffd43b")),
	})
	Ui.text({ Name = "Head", Text = "⚡ Flashing lights ahead", TextSize = big, TextColor3 = Color3.fromHex("#ffe066"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 6), Size = UDim2.fromOffset(textW, 18), Parent = box })
	Ui.text({ Name = "Sub", Text = "Rave Mode is starting", Body = true, TextSize = 12, TextTransparency = 0.15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 25), Size = UDim2.fromOffset(textW, 15), Parent = box })
	local x = 12 + textW + 10
	Ui.text({ Name = "ReduceLabel", Text = "Reduce", TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(x, 0), Size = UDim2.new(0, reduceW + 2, 1, 0), Parent = box })
	switch(box, x + reduceW + 6)
	local close = Ui.new("TextButton", { Name = "Close", Text = "✕", TextSize = 12, FontFace = Ui.DISPLAY, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false, BackgroundTransparency = 1, Position = UDim2.fromOffset(w - 8 - 26, 10), Size = UDim2.fromOffset(26, 26), Parent = box }, {
		Ui.corner(8),
		Ui.stroke(2, Color3.new(1, 1, 1), 0.5),
	})
	close.Activated:Connect(function()
		gui:Destroy()
	end)
	task.delay(HEADS_UP_S, function()
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

-- ---------- The town's lights (TechnoLights.tsx) ----------
-- Every neon light in the towns (lamp bulbs, signs, the club's windows) and every light source:
-- what it was, so it goes back afterwards.
-- What each one was is kept on it as attributes (RaveColor, RaveBrightness), so it always goes
-- back to its own colour however often the towns are looked through.
local lit: { Instance } = {}
local lastScan = -math.huge
local function scan(t: number)
	if t - lastScan < 2 then
		return
	end
	lastScan = t
	local towns = workspace:FindFirstChild("Towns")
	if not towns then
		return
	end
	for _, d in towns:GetDescendants() do
		if d:GetAttribute("RaveColor") == nil then
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
				d:SetAttribute("RaveColor", d.Color)
				table.insert(lit, d)
			elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				d:SetAttribute("RaveColor", d.Color)
				d:SetAttribute("RaveBrightness", d.Brightness)
				table.insert(lit, d)
			end
		end
	end
end
local function restoreLights()
	for _, inst in lit do
		local color, bright = inst:GetAttribute("RaveColor"), inst:GetAttribute("RaveBrightness")
		if typeof(color) == "Color3" then
			(inst :: any).Color = color
		end
		if type(bright) == "number" then
			(inst :: any).Brightness = bright
		end
		inst:SetAttribute("RaveColor", nil)
		inst:SetAttribute("RaveBrightness", nil)
	end
	lit = {}
	lastScan = -math.huge
end
local function drawLights(tint: Color3, hit: number, n: number)
	-- The bulbs take the club's colour (a touch of their own warm white kept) and swell on the kick.
	local k = math.clamp(0.45 + n * 0.35 * (0.6 + hit), 0, 1)
	local keep = {}
	for _, inst in lit do
		if inst.Parent then
			table.insert(keep, inst)
			local bright = inst:GetAttribute("RaveBrightness")
			if type(bright) == "number" then
				local l = inst :: any
				l.Color = tint
				l.Brightness = bright * (0.6 + 1.4 * hit)
			else
				local was = inst:GetAttribute("RaveColor")
				local c = tint:Lerp(if typeof(was) == "Color3" then was else tint, 0.15)
				local part = inst :: BasePart
				part.Color = Color3.new(c.R * k, c.G * k, c.B * k)
			end
		end
	end
	lit = keep
end

-- ---------- Each frame ----------
local wasOn = false
local step = 0 -- the club's colour moves on with every kick (clubBeat.ts clubPulse)
local stepBeat = math.huge
local t0 = os.clock()
local serverFrom: number? = nil
local weeklyDrop: number? = nil

local function announce(on: boolean)
	local p = Players.LocalPlayer
	if p then
		p:SetAttribute("RaveOn", on)
		p:SetAttribute("RaveDrop", if on and window then window.drop else nil)
		p:SetAttribute("RaveUntil", if on and window then window.to else nil)
	end
	changed:Fire(on, if on then window else nil)
end

-- Picks up a rave from the server or the weekly schedule (checked about once a second).
local function sources(now: number)
	local from = workspace:GetAttribute("RaveFrom")
	local to = workspace:GetAttribute("RaveUntil")
	if type(from) == "number" and type(to) == "number" and from ~= serverFrom then
		-- The server's clock to this device's.
		local skew = now - workspace:GetServerTimeNow() * 1000
		local w = { from = from + skew, drop = from + skew + techno.BUILD_MS, to = to + skew }
		if now < w.to then
			serverFrom = from
			begin(w)
		end
	end
	local weekly = RaveTime.weekly(now, techno.WEEKLY, techno.BUILD_MS)
	if weekly and weekly.drop ~= weeklyDrop and not Rave.isOn(now) then
		weeklyDrop = weekly.drop
		begin(weekly)
	end
end

-- One frame of Rave Mode at `now` (ms), `t` seconds into the session.
function Rave.step(now: number, t: number)
	local on = Rave.isOn(now)
	if on ~= wasOn then
		if not on then
			-- techno.ts ends on a timer; here the frame notices, so its listeners still hear it.
			if window and now >= window.to then
				techno.stopEvent("techno")
			end
			restoreLights()
			droppedAt = nil
			if layer then
				layer.gui.Enabled = false
			end
			if tag then
				tag.frame:Destroy()
				tag = nil
			end
		else
			stepBeat = math.huge
			-- Only for the build-up: someone loading in after the drop is already seeing it.
			if techno.technoToDrop(now) > 0 then
				showHeadsUp()
			end
		end
		wasOn = on
		announce(on)
	end
	if not on then
		return
	end
	local soft = Rave.calm()
	local calmish = soft or reducedMotion()
	local b = techno.technoBeat(now)
	if b.kick > 0 and b.beat ~= stepBeat then
		step += 1
		stepBeat = b.beat
	end
	local L = layer or buildLayer()
	layer = L
	L.gui.Enabled = true
	drawLayer(L, b, techno.technoToDrop(now), t, soft, calmish)
	tag = tag or buildTag()
	local tk = if soft then 0.2 + 0.12 * math.sin((b.n / 32) * math.pi) else b.kick
	if tag then
		drawTag(tag, b, now, tk, ((if soft then b.bar * 67 else b.beat * 67) % 360 + 360) % 360)
	end
	scan(t)
	local n = clock.nightAmount(clock.dayPhase(now))
	local hit = if soft then 0.25 else math.max(b.kick, b.drop)
	local colour = Color3.fromHex(RAINBOW[((if soft then step // 4 else step) % #RAINBOW) + 1])
	drawLights(colour, hit, n)
end

-- ---------- The DJ's button (Upgrade sheet of the Neon Owl club) ----------
-- Adds it to a list at `order` for the DJ only; returns the height it took (0 for everyone else).
function Rave.button(list: Instance, order: number, onStart: () -> ()): number
	if not Rave.isDj() then
		return 0
	end
	local on = Rave.isOn()
	local text = if on then "🎧 Rave on!" else "🎧 Rave Mode for everyone"
	local busy = false
	local shadow = Ui.buy({ Name = "RaveButton", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 42), Parent = list }, text, "green", function()
		if busy or Rave.isOn() then
			return
		end
		busy = true
		local remotes = ReplicatedStorage:FindFirstChild("Cartopia")
		local remote = remotes and remotes:FindFirstChild("Rave")
		local ok = false
		if remote and remote:IsA("RemoteFunction") then
			local ran, result = pcall(function()
				return remote:InvokeServer("start")
			end)
			ok = ran and result == true
		end
		busy = false
		if not ok then
			local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
			local hud = pg and pg:FindFirstChild("Cartopia")
			local toasts = hud and hud:FindFirstChild("Toasts", true)
			if toasts then
				Ui.toast(toasts, "Rave Mode could not start", 0)
			end
			return
		end
		onStart()
	end, 19)
	-- theme.css .buy.rave-btn: violet to blue, a deep purple edge; faded while one is on.
	local face = (shadow :: any).Face :: GuiObject
	local g = face:FindFirstChildOfClass("UIGradient")
	if g then
		g.Rotation = 10
		g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromHex("#d500f9")), ColorSequenceKeypoint.new(0.55, Color3.fromHex("#651fff")), ColorSequenceKeypoint.new(1, Color3.fromHex("#00b8d4")) })
	end
	local st = face:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = Color3.fromHex("#3a0a6b")
	end
	if on then
		face.BackgroundTransparency = 0.4
	end
	return 42
end

local started = false
function Rave.start()
	if started then
		return
	end
	started = true
	local last = -math.huge
	RunService.RenderStepped:Connect(function()
		local now = nowMs()
		local t = os.clock() - t0
		if t - last >= 1 then
			last = t
			sources(now)
		end
		Rave.step(now, t)
	end)
end

return Rave
