--!strict
-- The visitor's car in town and the badge over it (the web's TownCars.tsx visitor car and
-- ui/Visitors.tsx VisitorBadges): a street racer's car, a camper (a tour group brings two or
-- three, each its own colour) or the black mystery supercar drives round the town's roads, with a
-- bobbing badge over it: "🏁 Race me!", "📸 $", "❓ 23s". Tapping the car or its badge is
-- client/Visitors' tap. When the visitor leaves it fades out where it is.
--
-- It drives with its own small copy of the web's traffic sim (Shared.Game.scene_traffic_sim) on the
-- town's roads, apart from the town's traffic (client/TownLife, which this leaves alone); it only
-- reads that traffic's lights each frame, so the visitor stops at the same reds the town shows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local Builder = require(Shared.Models:WaitForChild("Builder")) :: any
local Paint = require(Shared.Models:WaitForChild("Paint")) :: any
local lualib = require(Game:WaitForChild("lualib_bundle")) :: any
local data = require(Game:WaitForChild("data")) :: any
local placement = require(Game:WaitForChild("placement")) :: any
local sim = require(Game:WaitForChild("scene_traffic_sim")) :: any
local store = require(Game.store) :: any
local Remote = require(script.Parent.Remote)
local Town = require(script.Parent.Town)
local Ui = require(script.Parent.Ui)
local Placement = require(script.Parent.Placement)
local Visitors = require(script.Parent.Visitors)

local VisitorCar = {}

local S = Catalog.SCALE
local HIDDEN = CFrame.new(0, -10000, 0)
local MAX_DISTANCE = 900
local H = 26
-- A tour group's other campers (TownCars.tsx TOUR_COLORS).
local TOUR_COLORS = { "#80deea", "#f8bbd0", "#c5e1a5", "#ffe082" }
-- How fast each kind drives (TownCars.tsx).
local CRUISE = { racer = 2.6, mystery = 2.2 }

-- The badge's look by kind (.badge-visitor-*): fill top and bottom, text colour.
local LOOKS = {
	racer = { "#ff7043", "#d84315", "#ffffff" },
	tourist = { "#fff8e1", "#ffecb3", "#1b2a4a" },
	mystery = { "#5e35b1", "#311b92", "#ffffff" },
	barn = { "#ffb74d", "#ef6c00", "#ffffff" },
}

local traffic = lualib.__TS__New(sim.Traffic)
local townKey = ""
local models: { [string]: Model } = {}
local sizes: { [string]: { number } } = {}
local shownId: string? = nil
local folder: Folder? = nil

type Badge = { gui: BillboardGui, shadow: Frame, face: GuiButton, label: TextLabel, coin: Frame?, kind: string, id: string }
local badge: Badge? = nil

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

-- The cars a visitor brings: the lead car, and a tour group's other campers.
function VisitorCar.cars(v: any): { { uid: string, model: string, color: string, stripe: string? } }
	local lead = { uid = `visitor:{v.id}`, model = v.model, color = v.color, stripe = if v.kind == "racer" then "#fafafa" else nil }
	local out = { lead }
	local at = table.find(TOUR_COLORS, v.color) or 0
	for i = 1, math.max(0, (v.group or 1) - 1) do
		table.insert(out, { uid = `visitor:{v.id}:{i + 1}`, model = v.model, color = TOUR_COLORS[(at - 1 + i) % #TOUR_COLORS + 1], stripe = nil })
	end
	return out
end

local function build(c: any): Model?
	local m = Builder.build(c.model)
	if not m then
		return nil
	end
	local stripes = if c.stripe then Builder.build(`stripe:{c.model}`) else nil
	Paint.apply(m, Paint.jobOf(c), stripes)
	m.Name = c.uid
	m:SetAttribute("Visitor", true)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = true
			d.CanTouch = false
		end
	end
	-- Tapping the car is tapping the visitor (TownCar onTap).
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = MAX_DISTANCE
	click.Parent = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	click.MouseClick:Connect(function()
		Visitors.tap()
	end)
	m:PivotTo(HIDDEN)
	m.Parent = folder
	return m
end

-- The town's roads for the visitor's sim, kept up to date with the save.
local function updateTown(save: any)
	local roads = save.roads or {}
	local buildings = save.buildings or {}
	local parts = {}
	for _, b in buildings do
		table.insert(parts, `{b.uid}:{b.def}:{b.x}:{b.z}:{b.rot or "-"}`)
	end
	local key = table.concat(roads, ";") .. "|" .. table.concat(parts, ";")
	if key ~= townKey then
		townKey = key
		traffic:setTown(roads, buildings, placement.turnOf)
	end
end

-- The visitor's cars on the road, or none (the sim fades leaving visitors out where they are).
local function updateCars()
	local v = Visitors.visitor
	local show = v ~= nil and not v.gone and v.kind ~= "barn"
	if not show or (shownId ~= nil and v and v.id ~= shownId) then
		if shownId then
			traffic:setCars({}, 0)
			shownId = nil
		end
		if not show then
			return
		end
	end
	local visitor = v :: any
	if shownId == visitor.id then
		return
	end
	shownId = visitor.id
	local specs = {}
	for _, c in VisitorCar.cars(visitor) do
		local size = (Catalog.TOWN_SIZE or {})[c.model] or { 0.8, 0.45, 0.8 }
		sizes[c.uid] = size
		if not models[c.uid] then
			models[c.uid] = build(c) :: any
		end
		table.insert(specs, { uid = c.uid, len = size[1], wid = size[2], cruise = CRUISE[visitor.kind] or 1.4, stalled = false })
	end
	traffic:setCars(specs, #specs)
end

-- The town's traffic lights, read from the town's own traffic (client/TownLife) when it drives
-- the same roads, so the visitor keeps to them.
local function copyLights()
	local ok, TownLife = pcall(require, script.Parent.TownLife)
	local town = ok and (TownLife :: any)._traffic
	if not town or not town.net or not traffic.net then
		return
	end
	if #town.net.layout.clusters ~= #traffic.net.layout.clusters then
		return
	end
	local mine = lualib.__TS__New(lualib.Map)
	town.sigs:forEach(function(_, g: any, id: number)
		mine:set(id, table.clone(g))
	end)
	traffic.sigs = mine
end

-- The badge over the lead car (or over Rusty's for a barn tip).
local function makeBadge(parent: Instance, v: any, adornee: Instance): Badge
	local gui = Ui.new("BillboardGui", {
		Name = "Visitor",
		Adornee = adornee,
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(160, 46),
		StudsOffsetWorldSpace = Vector3.new(0, 14, 0),
		MaxDistance = MAX_DISTANCE,
		ResetOnSpawn = false,
		Parent = parent,
	})
	local look = LOOKS[v.kind] or LOOKS.racer
	local shadow, face = Ui.shadowed({ Name = "Badge", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(110, H + 4), Parent = gui }, {
		radius = 16,
		stroke = 3,
		drop = 3,
		dark = 0.35,
		color = Ui.WHITE,
		class = "TextButton",
	})
	Ui.gradient(look[1], look[2]).Parent = face
	Ui.new("Frame", { Name = "Tail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -2), Size = UDim2.fromOffset(11, 11), Rotation = 45, BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 0, Parent = shadow })
	local label = Ui.text({ Name = "Label", Text = "", TextSize = 15, TextColor3 = Color3.fromHex(look[3]), Size = UDim2.fromScale(1, 1), Shadow = if look[3] == "#ffffff" then 1 else nil, Parent = face })
	local coin: Frame? = nil
	if v.kind == "tourist" then
		-- 📸 and the gold coin (.coin).
		label.TextXAlignment = Enum.TextXAlignment.Left
		coin = Ui.new("Frame", { Name = "Coin", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromHex("#f9a825"), Parent = face }, {
			Ui.round(),
			Ui.stroke(2, Color3.fromHex("#fff3c4")),
			Ui.gradient("#ffe082", "#f9a825"),
		})
		Ui.text({ Text = "$", TextSize = 15, TextColor3 = Color3.fromHex("#8d5a00"), Size = UDim2.fromScale(1, 1), Parent = coin })
	end
	;(face :: GuiButton).Activated:Connect(function()
		Visitors.tap()
	end)
	return { gui = gui, shadow = shadow, face = face, label = label, coin = coin, kind = v.kind, id = v.id }
end

-- The badge's text (VisitorBadges).
function VisitorCar.label(v: any, t: number): string
	if v.kind == "racer" then
		return "🏁 Race me!"
	elseif v.kind == "tourist" then
		return "📸"
	elseif v.kind == "mystery" then
		return `❓ {math.max(0, math.ceil((v.expiresAt - t) / 1000))}s`
	end
	return "🛻 Free car"
end

local holder: Instance? = nil
local ctxRef: any = nil

local function rustyModel(): Instance?
	local s = store.useGame.getState()
	local f = Town.folder()
	local list = f and f:FindFirstChild("Buildings")
	for _, b in s.buildings or {} do
		if b.def == "rescue" and list then
			local m = list:FindFirstChild(b.uid)
			if m and m:IsA("Model") then
				return m.PrimaryPart or m
			end
		end
	end
	return nil
end

local function updateBadge(t: number)
	local v = Visitors.visitor
	local adornee: Instance? = nil
	if v and not v.gone and holder then
		if v.kind == "barn" then
			adornee = rustyModel()
		else
			local m = models[`visitor:{v.id}`]
			adornee = m and (m.PrimaryPart or m)
		end
	end
	if not v or v.gone or not adornee then
		if badge then
			badge.gui:Destroy()
			badge = nil
		end
		return
	end
	if badge and badge.id ~= v.id then
		badge.gui:Destroy()
		badge = nil
	end
	local b = badge or makeBadge(holder :: Instance, v, adornee)
	badge = b
	if b.gui.Adornee ~= adornee then
		b.gui.Adornee = adornee
	end
	-- Badges clear away in edit mode and away from home, as on the web.
	local shown = not Placement.active() and not (ctxRef and ctxRef.visiting ~= nil)
	if b.gui.Enabled ~= shown then
		b.gui.Enabled = shown
	end
	local text = VisitorCar.label(v, t)
	if b.label.Text ~= text then
		Ui.setText(b.label, text)
		local w = math.max(56, math.ceil(Ui.textWidth(text, 15)) + 24 + (if b.coin then 26 else 0))
		b.shadow.Size = UDim2.fromOffset(w, H + 4)
		if b.coin then
			b.label.Position = UDim2.fromOffset(10, 0)
		end
	end
	b.face.Active = not Visitors.busy
	-- bob: 6px up and back every 0.9 s; the mystery car's badge pulses instead (badgepulse).
	local c = os.clock()
	if v.kind == "mystery" then
		local k = 1 + 0.35 * (0.5 - 0.5 * math.cos(c / 0.6 * math.pi * 2))
		b.shadow.Position = UDim2.new(0.5, 0, 0, 6)
		local scale = b.shadow:FindFirstChildOfClass("UIScale") or Ui.new("UIScale", { Parent = b.shadow })
		;(scale :: UIScale).Scale = k
	else
		local y = 6 - 6 * (0.5 - 0.5 * math.cos(c / 0.9 * math.pi * 2))
		b.shadow.Position = UDim2.new(0.5, 0, 0, y)
	end
end

-- Moves the visitor's cars on by dt and draws them where the sim has them.
function VisitorCar.step(dt: number)
	local f = Town.folder()
	local origin: Vector3? = f and f:GetAttribute("Origin") :: any
	local save = Remote.last and Remote.last.save
	if save then
		updateTown(save)
	end
	updateCars()
	pcall(copyLights)
	traffic:step(math.min(dt, 0.1))
	for uid, m in models do
		local a = traffic.agents:get(uid)
		if not a or not origin then
			-- Gone from the road: faded out, so the model goes too.
			if not a then
				m:Destroy()
				models[uid] = nil
				sizes[uid] = nil
			end
			continue
		end
		local k = (sizes[uid] and sizes[uid][3] or 0.8) * math.max(0.01, a.show)
		if math.abs(m:GetScale() - k) > 0.001 then
			m:ScaleTo(k)
		end
		m:PivotTo(CFrame.new((origin :: Vector3) + Vector3.new(a.x * S, 0.02 * S, a.z * S)) * CFrame.Angles(0, a.yaw, 0))
	end
	updateBadge(now())
end

function VisitorCar.start(ctx: any)
	if folder then
		return
	end
	ctxRef = ctx
	folder = Ui.new("Folder", { Name = "Visitors", Parent = workspace })
	local root: Instance = ctx.gui
	local screen = root:FindFirstAncestorOfClass("ScreenGui")
	holder = Ui.new("Folder", { Name = "VisitorBadges", Parent = if screen then screen.Parent else Players.LocalPlayer:WaitForChild("PlayerGui") })
	RunService.RenderStepped:Connect(VisitorCar.step)
end

VisitorCar._traffic = traffic
VisitorCar._models = models

return VisitorCar
