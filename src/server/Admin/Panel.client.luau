--!strict
-- The admin panel's screen (server/Admin). The server only puts this script in an admin's own
-- PlayerGui, with the AdminRemote beside it, so nobody else's game has it. Everything that
-- changes a town goes through the remote, where the server checks it again; the time, season and
-- weather here change only this player's own view, and fly, noclip and speed only their avatar.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local holder = script.Parent :: ScreenGui
local remote = holder:WaitForChild("AdminRemote") :: RemoteFunction
local player = Players.LocalPlayer
-- The game's own client modules (outside a running game, in the emulator, they stay in StarterPlayer).
local scripts = if RunService:IsRunning() then player:WaitForChild("PlayerScripts") else game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")
local Client = scripts:WaitForChild("Client")
local Ui = require(Client:WaitForChild("Ui")) :: any
local ClockShift = require(Client:WaitForChild("ClockShift")) :: any
local TownWeather = require(Client:WaitForChild("TownWeather")) :: any
local TownCamera = require(Client:WaitForChild("TownCamera")) :: any
local GetIn = require(Client:WaitForChild("GetIn")) :: any
local Visitors = require(Client:WaitForChild("Visitors")) :: any
local SeasonLook = require(Client:WaitForChild("SeasonLook")) :: any
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local clock = require(Game:WaitForChild("clock")) :: any
local weather = require(Game:WaitForChild("weather")) :: any
local season = require(Game:WaitForChild("scene_season")) :: any
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any

local realSeason = { scene = season.SEASON, catalog = Catalog.SEASON }

-- ---------- Talking to the server ----------
local info: any = { players = {}, cars = {}, plots = 0, server = {} }
local target = player.UserId -- whose town the buttons change

local toastLabel: TextLabel? = nil
local function say(text: string)
	local l = toastLabel
	if not l then
		return
	end
	l.Text = text
	l.Visible = true
	local mine = text
	task.delay(3, function()
		if l.Text == mine then
			l.Visible = false
		end
	end)
end

local WHY = {
	["not allowed"] = "Only the game's owner can do that.",
	["not here"] = "That player isn't in this server.",
	["town not loaded"] = "Their town hasn't loaded yet.",
	["slow down"] = "Slow down a little.",
	["bad amount"] = "That amount won't work.",
	["no such car"] = "No car by that name.",
	["nowhere"] = "Can't go there.",
	["empty"] = "Write the banner's message first.",
	["bad weather"] = "Pick a weather.",
	["not allowed words"] = "Roblox's filter won't let that message be shown.",
}
local function call(op: string, ...: any): (boolean, any)
	local sent, ok, result = pcall(remote.InvokeServer, remote, op, ...)
	if not sent then
		say("Couldn't reach the server.")
		return false, nil
	end
	if not ok then
		say(WHY[result] or `Didn't work ({tostring(result)})`)
	end
	return ok, result
end

local function refresh()
	local ok, result = call("info")
	if ok and type(result) == "table" then
		info = result
	end
end

local function targetCard(): any
	for _, p in info.players do
		if p.userId == target then
			return p
		end
	end
	return nil
end

-- ---------- Fly, noclip and speed (this player's own avatar) ----------
local flying = false
local noclip = false
local flyForce: LinearVelocity? = nil
local flyAlign: AlignOrientation? = nil

local function rootPart(): BasePart?
	local c = player.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function stopFly()
	flying = false
	if flyForce then
		local att = flyForce.Attachment0
		flyForce:Destroy()
		if att then
			att:Destroy()
		end
	end
	if flyAlign then
		flyAlign:Destroy()
	end
	flyForce, flyAlign = nil, nil
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h then
		h.PlatformStand = false
	end
end

local function startFly()
	local root = rootPart()
	if not root then
		say("Walk around first (press the walk button), then fly.")
		return
	end
	stopFly()
	flying = true
	local att = Instance.new("Attachment")
	att.Name = "AdminFly"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 30
	ao.Parent = root
	flyForce, flyAlign = lv, ao
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h then
		h.PlatformStand = true
	end
end

local FLY_SPEED = 80
RunService.RenderStepped:Connect(function()
	local lv, ao = flyForce, flyAlign
	if flying and lv and ao then
		local cam = workspace.CurrentCamera
		local look = cam.CFrame
		local move = Vector3.zero
		-- WASD, or the thumbstick, follows the camera; Space goes up and Q (or Ctrl) down.
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h and h.MoveDirection.Magnitude > 0 then
			local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
			local ahead = if flat.Magnitude > 0 then flat.Unit else Vector3.zAxis
			-- MoveDirection is flat; tilt it with the camera's pitch when heading where it looks.
			local along = h.MoveDirection:Dot(ahead)
			move = h.MoveDirection + Vector3.new(0, look.LookVector.Y * along, 0)
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
			move += Vector3.yAxis
		end
		if UserInputService:IsKeyDown(Enum.KeyCode.Q) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			move -= Vector3.yAxis
		end
		local fast = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then 3 else 1
		lv.VectorVelocity = if move.Magnitude > 0 then move.Unit * FLY_SPEED * fast * GetIn.speedScale else Vector3.zero
		ao.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(look.LookVector.X, 0, look.LookVector.Z) + Vector3.new(0, 0, 1e-4))
	end
end)
RunService.Stepped:Connect(function()
	if noclip and player.Character then
		for _, d in player.Character:GetDescendants() do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
	end
end)
player.CharacterAdded:Connect(function()
	flying = false
	flyForce, flyAlign = nil, nil
end)

-- ---------- The debug readout (top right) ----------
local debugOn = false
local debugLabel: TextLabel = Ui.text({
	Name = "AdminDebug",
	Body = true,
	Visible = false,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -10, 0, 60),
	Size = UDim2.fromOffset(230, 150),
	BackgroundTransparency = 0.35,
	BackgroundColor3 = Color3.fromHex("#0a1630"),
	Parent = holder,
})
Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingTop = UDim.new(0, 6), Parent = debugLabel })
Ui.corner(8).Parent = debugLabel

local frames, frameAt, fps = 0, os.clock(), 0
RunService.RenderStepped:Connect(function()
	frames += 1
	local t = os.clock()
	if t - frameAt >= 0.5 then
		fps = math.floor(frames / (t - frameAt) + 0.5)
		frames, frameAt = 0, t
	end
end)
-- The readout, once a second while it's on (the server's numbers come with the player list).
local function drawDebug()
	refresh()
	local s = info.server or {}
	local root = rootPart()
	local pos = if root then root.Position else Vector3.zero
	local ping = math.floor(player:GetNetworkPing() * 1000)
	debugLabel.Text = table.concat({
		`FPS {fps}   ping {ping} ms`,
		`Your memory {math.floor(Stats:GetTotalMemoryUsageMb())} MB`,
		`Server memory {s.memoryMb or "?"} MB`,
		`Server physics {s.physicsFps or "?"} fps, beat {s.heartbeatMs or "?"} ms`,
		`Players {s.players or "?"}   up {math.floor((s.uptime or 0) / 60)} min`,
		`Parts here {s.instances or "?"}   version {s.version or "?"}`,
		`At {math.floor(pos.X)}, {math.floor(pos.Y)}, {math.floor(pos.Z)}`,
		`Town hour {math.floor(clock.townHour(ClockShift.now()))}   {season.SEASON}`,
	}, "\n")
end
task.spawn(function()
	while true do
		task.wait(1)
		if debugOn then
			pcall(drawDebug)
		end
	end
end)

-- ---------- Small building blocks ----------
local ROW = 40
-- Items in a row go left to right in the order they're made.
local made = 0
local function nextOrder(order: number?): number
	made += 1
	return order or made
end

local function row(parent: Instance, order: number, height: number?): Frame
	return Ui.new("Frame", {
		Name = `Row{order}`,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -8, 0, height or ROW),
		Parent = parent,
	}, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
	})
end

local function label(parent: Instance, text: string, width: number, order: number?): TextLabel
	return Ui.text({ Text = text, TextSize = 16, Body = true, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(width, ROW), LayoutOrder = nextOrder(order), TextTruncate = Enum.TextTruncate.AtEnd, Parent = parent })
end

local function heading(parent: Instance, text: string, order: number)
	local r = row(parent, order, 28)
	Ui.text({ Text = text, TextSize = 18, TextColor3 = Ui.BLUE, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 1, 0), Parent = r })
end

local function button(parent: Instance, text: string, width: number, kind: string?, onClick: () -> (), order: number?): Frame
	local b = Ui.buy({ Size = UDim2.fromOffset(width, 34), LayoutOrder = nextOrder(order), Parent = parent }, text, kind or "green", onClick, 14)
	return b
end

-- A button that asks to be pressed again before it does anything that can't be undone.
local function careful(parent: Instance, text: string, width: number, onClick: () -> (), order: number?)
	local armed = false
	local frame: Frame
	frame = button(parent, text, width, "broke", function()
		local face = (frame :: any).Face
		local l = face and face:FindFirstChild("Label") :: TextLabel?
		if not armed then
			armed = true
			if l then
				Ui.setText(l, "Sure? Tap again")
			end
			task.delay(3, function()
				armed = false
				if l then
					Ui.setText(l, text)
				end
			end)
			return
		end
		armed = false
		if l then
			Ui.setText(l, text)
		end
		onClick()
	end, order)
end

local function box(parent: Instance, placeholder: string, width: number, order: number?): TextBox
	return Ui.new("TextBox", {
		PlaceholderText = placeholder,
		Text = "",
		ClearTextOnFocus = false,
		FontFace = Ui.BODY,
		TextSize = 16,
		TextColor3 = Ui.INK,
		BackgroundColor3 = Ui.WHITE,
		Size = UDim2.fromOffset(width, 34),
		LayoutOrder = nextOrder(order),
		Parent = parent,
	}, { Ui.corner(8), Ui.stroke(2, Ui.EDGE) })
end

-- "1m", "250k", "1,500" -> a number.
local function amount(text: string): number?
	local t = string.lower(string.gsub(text, "[,%s]", ""))
	local n, unit = string.match(t, "^(%-?[%d%.]+)([kmb]?)$")
	local v = tonumber(n)
	if not v then
		return nil
	end
	local scale = ({ k = 1e3, m = 1e6, b = 1e9 } :: any)[unit] or 1
	return math.floor(v * scale + 0.5)
end

-- ---------- The pages ----------
local PAGES = {
	{ id = "money", label = "Money" },
	{ id = "items", label = "Cars" },
	{ id = "world", label = "World" },
	{ id = "move", label = "Move" },
	{ id = "people", label = "Players" },
	{ id = "live", label = "Live" },
}

local FIELDS = {
	{ "coins", "Coins" },
	{ "bucks", "Gems" },
	{ "parts", "Parts" },
	{ "xp", "XP" },
	{ "level", "Level" },
}

local function pageMoney(list: Instance, redraw: () -> ())
	local card = targetCard() or {}
	heading(list, "Their money and level", 1)
	for i, f in FIELDS do
		local field, name = f[1], f[2]
		local r = row(list, 1 + i)
		label(r, `{name}: {Ui.commas(card[field] or 0)}`, 150)
		local input = box(r, "amount", 110)
		button(r, "Give", 70, "green", function()
			local v = amount(input.Text)
			if v and call("give", target, field, v) then
				say(`Gave {Ui.commas(v)} {name}`)
				refresh()
				redraw()
			end
		end)
		button(r, "Set", 60, "garage", function()
			local v = amount(input.Text)
			if v and call("set", target, field, v) then
				say(`{name} set to {Ui.commas(v)}`)
				refresh()
				redraw()
			end
		end)
	end
	heading(list, "Quick", 10)
	local quick = {
		{ "+1M coins", "coins", 1e6 },
		{ "+10K gems", "bucks", 1e4 },
		{ "+1K parts", "parts", 1e3 },
		{ "+1 level", "level", 1 },
	}
	local r = row(list, 11)
	for _, q in quick do
		button(r, q[1] :: string, 112, "garage", function()
			if call("give", target, q[2], q[3]) then
				say(`{q[1]} done`)
				refresh()
				redraw()
			end
		end)
	end
end

local carFilter = ""
local function pageItems(list: Instance, redraw: () -> ())
	heading(list, "Free crates", 1)
	local r = row(list, 2)
	button(r, "+1 Gold Crate", 140, "garage", function()
		if call("crate", target, 1) then
			say("A free Gold Crate is waiting in the Crate Depot")
		end
	end)
	button(r, "+10 Gold Crates", 150, "garage", function()
		if call("crate", target, 10) then
			say("10 free Gold Crates are waiting in the Crate Depot")
		end
	end)
	heading(list, "Give a car (tap one)", 3)
	local s = row(list, 4)
	local search = box(s, "search cars", 300)
	search.Text = carFilter
	search.FocusLost:Connect(function()
		carFilter = search.Text
		redraw()
	end)
	local n = 0
	for _, c in info.cars do
		local name = string.lower(c.name .. " " .. c.id)
		if carFilter == "" or string.find(name, string.lower(carFilter), 1, true) then
			n += 1
			local line = row(list, 10 + n, 36)
			label(line, `{c.name}  (level {c.level})`, 300)
			button(line, "Give", 80, "green", function()
				if call("car", target, c.id) then
					say(`{c.name} is in their garage`)
				end
			end)
		end
	end
end

local function setSeason(name: string?)
	season.SEASON = name or realSeason.scene
	Catalog.SEASON = name or realSeason.catalog
	SeasonLook.set(name)
end

local function pageWorld(list: Instance, _redraw: () -> ())
	heading(list, "Time of day (your view only)", 1)
	local hours = { { "6am", 6 }, { "9am", 9 }, { "Noon", 12 }, { "4pm", 16 }, { "7pm", 19 }, { "10pm", 22 }, { "2am", 2 } }
	local r1 = row(list, 2)
	local r2 = row(list, 3)
	for i, h in hours do
		button(if i <= 4 then r1 else r2, h[1] :: string, 90, "garage", function()
			local phase = (((h[2] :: number) - 12) / 24) % 1
			ClockShift.frozen = clock.nextPhaseAt(phase, DateTime.now().UnixTimestampMillis)
			say(`Time stopped at {h[1]}`)
		end)
	end
	button(r2, "Real time", 100, "green", function()
		ClockShift.frozen = nil
		say("Back to the real time")
	end)

	heading(list, "Season (your view only)", 4)
	local r3 = row(list, 5)
	for _, s in { "winter", "spring", "summer", "fall" } do
		button(r3, s:sub(1, 1):upper() .. s:sub(2), 84, "garage", function()
			setSeason(s)
			say(`Season: {s}. The lawn and greenery change; snow on trees and bare winter branches need a model rebuild.`)
		end)
	end
	button(r3, "Real", 64, "green", function()
		setSeason(nil)
		say("Back to the real season")
	end)

	heading(list, "Weather (your view only)", 6)
	local kinds = weather.WEATHER_KINDS
	local rowAt, inRow = 7, 0
	local r = row(list, rowAt)
	for _, k in kinds do
		if inRow == 4 then
			rowAt += 1
			r = row(list, rowAt)
			inRow = 0
		end
		inRow += 1
		button(r, k, 104, "garage", function()
			local ok = pcall(TownWeather.pin, k)
			say(if ok then `Weather: {k}` else `Can't show {k}`)
		end)
	end
	local rr = row(list, rowAt + 1)
	button(rr, "Real weather", 140, "green", function()
		TownWeather.pin(nil)
		say("Back to the real weather")
	end)

	heading(list, "Events", 30)
	local e = row(list, 31)
	button(e, "Visitor now", 130, "garage", function()
		if call("visitor", target) then
			if target == player.UserId then
				task.delay(0.3, Visitors.ask)
			end
			say("A visitor is on the way")
		end
	end)
	button(e, "Rave for everyone", 170, "broke", function()
		if call("rave") then
			say("Rave Mode is on in every server")
		end
	end)
end

local SPEEDS = { 1, 2, 4, 8 }
local function pageMove(list: Instance, redraw: () -> ())
	heading(list, "Your avatar", 1)
	local r = row(list, 2)
	button(r, if flying then "Fly: ON" else "Fly: off", 110, if flying then "green" else "grey", function()
		if flying then
			stopFly()
		else
			if not TownCamera.isWalking() then
				TownCamera.setWalking(true)
				task.wait(0.2)
			end
			startFly()
		end
		redraw()
	end)
	button(r, if noclip then "Noclip: ON" else "Noclip: off", 130, if noclip then "green" else "grey", function()
		noclip = not noclip
		if not noclip and player.Character then
			-- Back to normal: Roblox puts the body's collisions back on respawn; the torso and root
			-- are the ones that matter for walking.
			for _, d in player.Character:GetDescendants() do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
					d.CanCollide = d.Name == "UpperTorso" or d.Name == "LowerTorso" or d.Name == "Torso" or d.Name == "Head"
				end
			end
		end
		redraw()
	end)
	local s = row(list, 3)
	label(s, "Speed", 60)
	for _, v in SPEEDS do
		button(s, `x{v}`, 60, if GetIn.speedScale == v then "green" else "grey", function()
			GetIn.speedScale = v
			pcall(GetIn.applySpeed)
			redraw()
		end)
	end
	local tip = row(list, 4, 44)
	Ui.text({ Text = "Fly: WASD to move, Space up, Q down, Shift faster.", Body = true, TextSize = 14, TextColor3 = Ui.MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 1, 0), Parent = tip })

	heading(list, "Teleport the chosen player", 5)
	local t = row(list, 6)
	local function went(ok: boolean)
		if ok and target == player.UserId then
			TownCamera.setWalking(true)
		end
	end
	button(t, "Hub", 70, "garage", function()
		went(call("tp", target, "hub"))
	end)
	local plot = box(t, `plot 0-{math.max(0, (info.plots or 1) - 1)}`, 110)
	button(t, "Go to plot", 110, "garage", function()
		local i = tonumber(plot.Text)
		if i then
			went(call("tp", target, "plot", math.floor(i)))
		end
	end)
	heading(list, "Go to a player", 7)
	for i, p in info.players do
		if p.userId ~= target then
			local line = row(list, 10 + i, 36)
			label(line, `{p.display} (@{p.name})`, 250)
			button(line, "Go there", 100, "garage", function()
				went(call("tp", target, "player", p.userId))
			end)
			button(line, "Bring", 80, "garage", function()
				call("tp", p.userId, "player", target)
			end)
		end
	end
end

local inspected: any = nil
local function pagePeople(list: Instance, redraw: () -> ())
	local card = targetCard() or {}
	heading(list, `{card.display or "?"} (@{card.name or "?"})`, 1)
	local r = row(list, 2)
	button(r, "Look at their save", 170, "garage", function()
		local ok, result = call("inspect", target)
		if ok then
			inspected = result
			redraw()
		end
	end)
	if inspected and inspected.card and inspected.card.userId == target then
		local i = inspected
		local lines = {
			`Town "{i.card.town or "?"}"  level {i.card.level}  xp {Ui.commas(i.card.xp or 0)}`,
			`Coins {Ui.commas(i.card.coins or 0)}  gems {Ui.commas(i.card.bucks or 0)}  parts {Ui.commas(i.card.parts or 0)}`,
			`Buildings {i.buildings}  roads {i.roads}  cars {i.cars}`,
			`Trophies {i.trophies or 0}  races won {i.racesWon or 0}  tutorial step {i.tutorial or 0}`,
			`Free crates waiting {i.freeCrates}`,
		}
		for k, text in lines do
			local l = row(list, 2 + k, 24)
			Ui.text({ Text = text, Body = true, TextSize = 14, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 1, 0), Parent = l })
		end
	end
	heading(list, "Careful: these can't be undone", 20)
	local d = row(list, 21)
	careful(d, "Reset their town", 180, function()
		if call("reset", target, "RESET") then
			say("Their town is brand new")
			inspected = nil
			refresh()
			redraw()
		end
	end)
	if target ~= player.UserId then
		careful(d, "Kick them", 130, function()
			if call("kick", target, "Removed by the game's owner.") then
				say("Kicked")
				target = player.UserId
				task.wait(0.5)
				refresh()
				redraw()
			end
		end)
	end
	heading(list, "Debug", 30)
	local g = row(list, 31)
	button(g, if debugOn then "FPS and memory: ON" else "FPS and memory: off", 210, if debugOn then "green" else "grey", function()
		debugOn = not debugOn
		debugLabel.Visible = debugOn
		redraw()
	end)
end


-- ---------- Live events: for every player in every server (server/LiveEvents), as the web's
-- Admin.tsx LiveTab ----------
local KINDS = {
	{ id = "night", icon = "🌙", label = "Night" },
	{ id = "day", icon = "☀️", label = "Day" },
	{ id = "rave", icon = "🎧", label = "Rave" },
	{ id = "weather", icon = "🌦️", label = "Weather" },
	{ id = "banner", icon = "📢", label = "Banner" },
}
local KIND_ICON: { [string]: string } = {}
for _, k in KINDS do
	KIND_ICON[k.id] = k.icon
end
local SKIES = {
	{ "clear", "☀️" }, { "rain", "🌧️" }, { "storm", "⛈️" }, { "drizzle", "🌦️" }, { "fog", "🌫️" },
	{ "wind", "💨" }, { "snow", "🌨️" }, { "blizzard", "❄️" }, { "mist", "🌁" }, { "heat", "🥵" },
}
local MINUTES = { 5, 15, 30, 60, 120 }
local liveKind, liveMins, liveSky, liveMsg = "night", 15, "rain", ""

-- Admin.tsx clock(): h:mm:ss or m:ss.
local function left(ms: number): string
	local sec = math.max(0, math.ceil(ms / 1000))
	local h, m, ss = sec // 3600, (sec % 3600) // 60, sec % 60
	return if h > 0 then string.format("%d:%02d:%02d", h, m, ss) else string.format("%d:%02d", m, ss)
end

local function pageLive(list: Instance, redraw: () -> ())
	local ok, got = call("live")
	local events = if ok and type(got) == "table" and type(got.list) == "table" then got.list else {}
	-- The server's clock to this device's.
	local skew = if ok and type(got) == "table" and type(got.now) == "number" then DateTime.now().UnixTimestampMillis - got.now else 0
	local now = DateTime.now().UnixTimestampMillis - skew
	local running = {}
	for _, e in events do
		if e.from <= now and now < e.to then
			table.insert(running, e)
		end
	end
	heading(list, "Running now (every server)", 1)
	local timers: { [TextLabel]: number } = {}
	if #running == 0 then
		label(row(list, 2), "Nothing live right now.", 400)
	end
	for i, e in running do
		local r = row(list, 1 + i)
		local sky = if type(e.payload) == "table" and type(e.payload.kind) == "string" then ` · {e.payload.kind}` else ""
		label(r, `{KIND_ICON[e.kind] or "✨"} {e.kind}{sky}`, 200)
		local t = label(r, "⏱ " .. left(e.to - now), 110)
		timers[t] = e.to
		button(r, "⏹ End", 90, "broke", function()
			local done, n = call("liveEnd", e.kind)
			if done then
				say(`⏹ Ended {n or 0}`)
				redraw()
			end
		end)
	end
	if #running > 1 then
		careful(row(list, 20), "⏹ End all", 140, function()
			local done, n = call("liveEnd", nil)
			if done then
				say(`⏹ Ended {n or 0}`)
				redraw()
			end
		end)
	end
	task.spawn(function()
		while list.Parent do
			task.wait(1)
			local at = DateTime.now().UnixTimestampMillis - skew
			for l, to in timers do
				l.Text = "⏱ " .. left(to - at)
			end
		end
	end)

	heading(list, "Start for everyone", 21)
	local kr = row(list, 22)
	for _, k in KINDS do
		local on = false
		for _, e in running do
			on = on or e.kind == k.id
		end
		button(kr, `{k.icon} {k.label}{if on then " ●" else ""}`, 98, if k.id == liveKind then "green" else "garage", function()
			liveKind = k.id
			redraw()
		end)
	end
	if liveKind == "weather" then
		local w1, w2 = row(list, 23), row(list, 24)
		for i, w in SKIES do
			button(if i <= 5 then w1 else w2, w[2], 52, if w[1] == liveSky then "green" else "garage", function()
				liveSky = w[1]
				redraw()
			end)
		end
	end
	local mr = row(list, 25)
	for _, m in MINUTES do
		button(mr, `⏱ {if m < 60 then `{m}m` else `{m // 60}h`}`, 84, if m == liveMins then "green" else "garage", function()
			liveMins = m
			redraw()
		end)
	end
	local br = row(list, 26)
	local needsMsg = liveKind == "banner"
	local msgBox = box(br, if needsMsg then "📢 Message" else "💬 Toast (optional)", 500)
	msgBox.Text = liveMsg
	msgBox:GetPropertyChangedSignal("Text"):Connect(function()
		if #msgBox.Text > 120 then
			msgBox.Text = string.sub(msgBox.Text, 1, 120)
		end
		liveMsg = msgBox.Text
	end)
	local label_ = ""
	for _, k in KINDS do
		if k.id == liveKind then
			label_ = k.label
		end
	end
	careful(row(list, 27), `▶ Start {label_} · {liveMins} min`, 260, function()
		if needsMsg and not liveMsg:match("%S") then
			say("Write the banner's message first.")
			return
		end
		local payload: { [string]: any } = {}
		if liveMsg:match("%S") then
			payload.message = liveMsg
		end
		if liveKind == "weather" then
			payload.kind = liveSky
		end
		if call("liveStart", liveKind, liveMins, payload) then
			liveMsg = ""
			say(`{KIND_ICON[liveKind]} Live for {liveMins} min`)
			redraw()
		end
	end)
end

local BUILD = { money = pageMoney, items = pageItems, world = pageWorld, move = pageMove, people = pagePeople, live = pageLive }

-- ---------- The panel ----------
local page = "money"
local open: Instance? = nil

local function close()
	if open then
		open:Destroy()
		open = nil
	end
end

local function show()
	close()
	refresh()
	local overlay, _sheet, body = Ui.panel(holder, "Admin", { onClose = close, width = 560, height = 700 })
	open = overlay

	-- Whose town: the chosen player, with arrows through everyone here.
	local top = row(body, 0, 40)
	top.Parent = body
	top.Size = UDim2.new(1, 0, 0, 40)
	local function name(): string
		local c = targetCard()
		return if c then `{c.display} (@{c.name})` else "?"
	end
	local who = label(top, `Player: {name()}`, 330)
	local function step(by: number)
		local list = info.players
		if #list == 0 then
			return
		end
		local at = 1
		for i, p in list do
			if p.userId == target then
				at = i
			end
		end
		target = list[((at - 1 + by) % #list) + 1].userId
		show()
	end
	button(top, "◀", 44, "garage", function()
		step(-1)
	end)
	button(top, "▶", 44, "garage", function()
		step(1)
	end)
	button(top, "Me", 50, "green", function()
		target = player.UserId
		show()
	end)
	who.Text = `Player: {name()}`

	-- The page tabs.
	local tabs = Ui.new("Frame", { Name = "Pages", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 36), Parent = body }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, p in PAGES do
		button(tabs, p.label, 84, if p.id == page then "green" else "grey", function()
			page = p.id
			show()
		end, i)
	end

	local scroller = Ui.scroller({ Name = "Page", Position = UDim2.fromOffset(0, 90), Size = UDim2.new(1, 0, 1, -90), Parent = body })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroller })
	local ok, err = pcall(BUILD[page], scroller, show)
	if not ok then
		warn(`[Cartopia] admin page {page}: {err}`)
	end
end

-- The little button only the admin has: a spanner on the left edge, under the top bar.
local toggle = Ui.button({ Name = "AdminButton", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.42, 0), Size = UDim2.fromOffset(40, 40), Parent = holder }, "navy", function()
	if open then
		close()
	else
		show()
	end
end, { radius = 12, stroke = 2, drop = 2, text = "🛠", textSize = 20 })
toggle:SetAttribute("NoMotion", true)

toastLabel = Ui.text({
	Name = "AdminToast",
	Visible = false,
	Text = "",
	TextSize = 16,
	Body = true,
	ZIndex = 60,
	TextWrapped = true,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -24),
	Size = UDim2.fromOffset(520, 44),
	BackgroundTransparency = 0.2,
	BackgroundColor3 = Color3.fromHex("#0a1630"),
	Parent = holder,
})
Ui.corner(10).Parent = toastLabel :: any
