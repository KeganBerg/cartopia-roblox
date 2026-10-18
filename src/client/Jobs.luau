--!strict
-- The badges over the player's businesses, as the web game's JobBadge (ui/Badges.tsx): a grey
-- "⛽ n" to start a job, a dark timer with a progress bar while it runs, and a round gold coin
-- to collect when it's done, each with a little tail pointing down at the building. Tapping one
-- taps the building. Values come from the shared store's copy of the town, by building uid.
--
-- Each badge is built once with its three looks and only switches between them, so the update
-- loop creates nothing; badges are capped and fade out past MaxDistance.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local merge = require(Game.merge) :: any
local clock = require(Game.clock) :: any
local wildLand = require(Game.wildLand) :: any
local Remote = require(script.Parent.Remote)
local Town = require(script.Parent.Town)
local Ui = require(script.Parent.Ui)
local Placement = require(script.Parent.Placement)

local Jobs = {}

local MAX_BADGES = 60
local MAX_DISTANCE = 900

type Badge = {
	gui: BillboardGui,
	idle: Frame,
	idleText: TextLabel,
	working: Frame,
	fill: Frame,
	time: TextLabel,
	ready: Frame,
	coin: TextLabel,
	lvl: Frame,
	lvlText: TextLabel,
	driver: TextLabel,
	merged: TextLabel,
	look: string,
}
local badges: { [string]: Badge } = {}

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

-- Timers as the web's fmt: 45s, 3m 20s.
local function fmt(sec: number): string
	if sec >= 60 then
		return string.format("%dm %02ds", sec // 60, sec % 60)
	end
	return `{sec}s`
end

-- A rounded badge with the navy outline and drop shadow, and the tail under it.
local function shell(parent: Instance, name: string, color: Color3, w: number, h: number, round: boolean): Frame
	local shadow, face = Ui.shadowed({ Name = name, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3), Size = UDim2.fromOffset(w, h), Visible = false, Parent = parent }, {
		radius = if round then h // 2 else 16,
		stroke = 2.5,
		drop = 3,
		dark = 0.3,
		color = color,
	})
	-- The tail: a turned square, half hidden behind the badge (a sibling under the face, since
	-- a child would draw over it).
	Ui.new("Frame", { Name = "Tail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromOffset(11, 11), Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0, ZIndex = 0, Parent = shadow }, {
		Ui.corner(2),
		Ui.stroke(2.5),
	})
	local _ = face
	return shadow
end

local function make(uid: string, model: Model, parent: Instance): Badge
	local gui = Ui.new("BillboardGui", {
		Name = "Job",
		Adornee = model.PrimaryPart or model,
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(150, 52),
		StudsOffsetWorldSpace = Vector3.new(0, ((model:GetAttribute("Height") :: number?) or 10) + 4, 0),
		MaxDistance = MAX_DISTANCE,
		ResetOnSpawn = false,
		Parent = parent,
	})
	local tap = Ui.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0, 60, 1, 0), ZIndex = 5, Parent = gui })
	tap.Activated:Connect(function()
		Remote.act("tapBuilding", uid)
	end)

	-- Idle: "⛽ 3" on light grey.
	local idle = shell(gui, "Idle", Color3.fromHex("#eceff1"), 60, 26, false)
	local idleText = Ui.text({ Text = "", TextSize = 14, TextColor3 = Ui.INK, Size = UDim2.fromScale(1, 1), Parent = (idle :: any).Face })

	-- Working: ⏱, a progress bar and the time left, on dark slate.
	local working = shell(gui, "Working", Color3.fromHex("#263238"), 132, 26, false)
	local wf = (working :: any).Face
	Ui.text({ Text = "⏱", TextSize = 14, Position = UDim2.fromOffset(6, 0), Size = UDim2.fromOffset(18, 26), Parent = wf })
	local track = Ui.new("Frame", { Position = UDim2.fromOffset(26, 9), Size = UDim2.fromOffset(46, 8), BackgroundColor3 = Color3.fromHex("#546e7a"), BorderSizePixel = 0, ClipsDescendants = true, Parent = wf }, { Ui.corner(4) })
	local fill = Ui.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromHex("#76ff03"), BorderSizePixel = 0, Parent = track }, { Ui.corner(4) })
	local time = Ui.text({ Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(77, 0), Size = UDim2.new(1, -80, 1, 0), Parent = wf })

	-- Ready: a gold coin in a round cream badge.
	local ready = shell(gui, "Ready", Color3.fromHex("#ffecb3"), 44, 44, true)
	local rf = (ready :: any).Face
	Ui.gradient("#fff8e1", "#ffecb3").Parent = rf
	rf.BackgroundColor3 = Ui.WHITE
	local coinBox = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Ui.WHITE, Parent = rf }, {
		Ui.round(),
		Ui.stroke(2, Color3.fromHex("#fff3c4")),
		Ui.gradient("#ffe082", "#f9a825"),
	})
	local coin = Ui.text({ Text = "$", TextSize = 22, TextColor3 = Color3.fromHex("#8d5a00"), Size = UDim2.fromScale(1, 1), Parent = coinBox })

	-- The building's level, top right, and its driver, top left (badge-lvl, badge-driver).
	local lvl = Ui.new("Frame", { Name = "Level", AnchorPoint = Vector2.new(0, 0), Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromHex("#ff8f00"), Visible = false, ZIndex = 4, Parent = gui }, {
		Ui.round(),
		Ui.stroke(2, Ui.WHITE),
	})
	local lvlText = Ui.text({ Text = "", TextSize = 11, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = lvl })
	local driver = Ui.text({ Name = "Driver", Text = "", TextSize = 11, BackgroundTransparency = 0, BackgroundColor3 = Ui.WHITE, Size = UDim2.fromOffset(20, 20), Visible = false, ZIndex = 4, Parent = gui })
	Ui.round().Parent = driver
	Ui.stroke(2, Color3.fromHex("#ec407a")).Parent = driver
	-- A merged block's bonus, top left (badge-merge): "+25%".
	local merged = Ui.text({ Name = "Merged", Text = "", TextSize = 11, TextColor3 = Color3.fromHex("#3e2723"), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromHex("#ffb300"), Size = UDim2.fromOffset(36, 18), Visible = false, ZIndex = 4, Parent = gui })
	Ui.round().Parent = merged
	Ui.stroke(2, Ui.WHITE).Parent = merged
	return {
		gui = gui,
		idle = idle,
		idleText = idleText,
		working = working,
		fill = fill,
		time = time,
		ready = ready,
		coin = coin,
		lvl = lvl,
		lvlText = lvlText,
		driver = driver,
		merged = merged,
		look = "",
	}
end

-- Shows one look; the level and driver chips sit on its top corners.
local function setLook(b: Badge, look: string)
	if b.look == look then
		return
	end
	b.look = look
	b.idle.Visible = look == "idle"
	b.working.Visible = look == "working"
	b.ready.Visible = look == "ready"
	local shown = if look == "ready" then b.ready elseif look == "working" then b.working else b.idle
	local w = shown.Size.X.Offset
	b.lvl.Position = UDim2.new(0.5, w / 2 - 10, 0, -5)
	b.driver.Position = UDim2.new(0.5, -w / 2 - 10, 0, -6)
	-- The merge chip takes the corner; the driver sits just right of it.
	b.merged.Position = UDim2.new(0.5, -w / 2 - 10, 0, -5)
	if b.merged.Visible then
		b.driver.Position = UDim2.new(0.5, -w / 2 - 10 + b.merged.Size.X.Offset + 2, 0, -6)
	end
end

local function modelsByUid(): { [string]: Model }
	local out = {}
	local f = Town.folder()
	local list = f and f:FindFirstChild("Buildings")
	if list then
		for _, m in list:GetChildren() do
			local uid = m:GetAttribute("Uid")
			if type(uid) == "string" and m:IsA("Model") then
				out[uid] = m
			end
		end
	end
	return out
end

local function update(holder: Instance)
	local s = store.useGame.getState()
	if not s.buildings then
		return
	end
	local t = now()
	local models = modelsByUid()
	local merges = merge.mergeGroups(s.buildings)
	local jobsDone = (s.stats and s.stats.jobs) or 0
	local seen: { [string]: boolean } = {}
	local count = 0
	-- Edit mode clears the town of badges, as on the web.
	local shown = not Placement.active()
	for _, b in s.buildings do
		local d = data.buildingDef(b.def)
		if not d or not d.jobSeconds or count >= MAX_BADGES then
			continue
		end
		-- A merged block gets one badge, on its anchor.
		if merges.owner:has(b.uid) and not merges.groups:has(b.uid) then
			continue
		end
		local m = models[b.uid]
		if not m then
			continue
		end
		count += 1
		seen[b.uid] = true
		local badge = badges[b.uid]
		if not badge then
			badge = make(b.uid, m, holder)
			badges[b.uid] = badge
		end
		-- The building was drawn again (an upgrade, a merge, a turn): follow the new model.
		local spot = m.PrimaryPart or m
		if badge.gui.Adornee ~= spot then
			badge.gui.Adornee = spot
			badge.gui.StudsOffsetWorldSpace = Vector3.new(0, ((m:GetAttribute("Height") :: number?) or 10) + 4, 0)
		end
		if badge.gui.Enabled ~= shown then
			badge.gui.Enabled = shown
		end
		local g = merges.groups:get(b.uid)
		local members = if g then g.members else { b }
		local ready, idle, finish = false, 0, 0
		for _, o in members do
			if o.jobEndsAt == nil then
				idle += 1
			else
				if t >= o.jobEndsAt then
					ready = true
				end
				finish = math.max(finish, o.jobEndsAt)
			end
		end
		if ready then
			setLook(badge, "ready")
			Ui.setText(badge.coin, if d.kind == "obstacle" then "✔" else "$")
		elseif idle == 0 then
			setLook(badge, "working")
			local left = math.ceil((finish - t) / 1000)
			local total = data.jobSeconds(d, data.jobLevel(b), jobsDone)
			local pct = math.clamp(1 - left / math.max(1, total), 0, 1)
			badge.fill.Size = UDim2.fromScale(pct, 1)
			Ui.setText(badge.time, fmt(left))
		else
			setLook(badge, "idle")
			local text
			if not data.isOpen(d, t) then
				text = `🌙 {fmt(math.max(1, math.ceil(clock.msUntilNight(t) / 1000)))}`
			elseif d.kind == "obstacle" then
				text = `🚜 {Ui.commas(wildLand.clearCost(d, s.level))}`
			else
				text = `⛽ {(d.fuelCost or 0) * idle}`
			end
			Ui.setText(badge.idleText, text)
			-- The grey badge hugs its text.
			local w = math.max(48, #text * 7 + 10)
			if badge.idle.Size.X.Offset ~= w then
				badge.idle.Size = UDim2.fromOffset(w, 26)
				badge.look = ""
				setLook(badge, "idle")
			end
		end
		local n = #members
		if n > 1 then
			local text = `+{math.round(data.mergeBonus(n) * 100)}%`
			if badge.merged.Text ~= text then
				Ui.setText(badge.merged, text)
				badge.merged.Size = UDim2.fromOffset(Ui.textWidth(text, 11) + 10, 18)
			end
		end
		if badge.merged.Visible ~= (n > 1) then
			badge.merged.Visible = n > 1
			badge.look = ""
			setLook(badge, if ready then "ready" elseif idle == 0 then "working" else "idle")
		end
		local lvl = data.buildingLevel(b)
		badge.lvl.Visible = lvl > 1
		Ui.setText(badge.lvlText, tostring(lvl))
		local car: any = nil
		if b.car then
			for _, c in s.cars do
				if c.uid == b.car then
					car = c
				end
			end
		end
		badge.driver.Visible = car ~= nil
		if car then
			local off = car.flat or car.lowFuel
			Ui.setText(badge.driver, if off then "🔧" elseif data.loves(data.carDef(car.model), d.id) then "❤️" else "🚗")
		end
	end
	for uid, badge in badges do
		if not seen[uid] then
			badge.gui:Destroy()
			badges[uid] = nil
		end
	end
end

local holder: Folder? = nil

function Jobs.start(gui: ScreenGui)
	holder = Ui.new("Folder", { Name = "JobBadges", Parent = gui.Parent })
	update(holder :: Folder)
	task.spawn(function()
		while true do
			task.wait(0.25)
			update(holder :: Folder)
		end
	end)
end

-- Brings the badges up to date now (entering or leaving edit mode) rather than on the next tick.
function Jobs.refresh()
	if holder then
		update(holder)
	end
end

-- How many jobs are done and waiting to be collected.
function Jobs.ready(): number
	local s = store.useGame.getState()
	local t = now()
	local n = 0
	for _, b in (s.buildings or {}) do
		if b.jobEndsAt ~= nil and t >= b.jobEndsAt then
			n += 1
		end
	end
	return n
end

return Jobs
