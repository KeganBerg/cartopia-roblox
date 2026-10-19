--!strict
-- One-time tips after the tutorial, as the web game's Tips (ui/Tips.tsx): the first time a feature
-- matters, one short line on the tutorial's navy card and a pulse on the thing itself (the web's
-- tut-pulse). "Show me" goes there; "Later" / "Got it" closes it. Seen tips stay seen (kept with the
-- account by client/Prefs). A tip only shows over the plain town: never during the tutorial, over a
-- menu or a pop-up, in edit mode or on a visit, and tips wait 40 seconds after the last one so
-- they never stack up.
--
-- The buttons a tip points at carry the `Tut` attribute the tutorial's hand uses (set in Hud):
-- "gems", "goals", "cars", "shop", "fuel".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Client = script.Parent.Parent
local Ui = require(Client.Ui)
local Remote = require(Client.Remote)
local Placement = require(Client.Placement)
local Prefs = require(Client.Prefs)
local Kit = require(script.Parent.Kit)
local Tutorial = require(script.Parent.Tutorial)

local Tips = {}

local CARD_W = 440
local GAP = 40 -- seconds after one tip before the next
local NAVY = { "#2a4370", "#1c2e52" }

export type Tip = { id: string, icon: string, text: string, target: string, when: (any) -> boolean, go: ((any) -> ())? }

local function owns(s: any, def: string): boolean
	for _, b in s.buildings or {} do
		if b.def == def then
			return true
		end
	end
	return false
end
local function stat(s: any, k: string): number
	return (s.stats and s.stats[k]) or 0
end
local function feature(id: string): string
	return data.FEATURES[id] or ""
end

-- The web's TIPS, in order: the first unseen one whose moment has come shows.
Tips.TIPS = {
	{ id = "gems", icon = "💎", text = "Gems are rare. Use them to skip waits, refill fuel and open Gold crates.", target = "gems", when = function() return true end },
	{ id = "goals", icon = "📋", text = "Not sure what to do next? Goals show the way and pay coins.", target = "goals", when = function(s) return stat(s, "jobs") >= 8 end },
	{ id = "garage", icon = "🔧", text = "Upgrade your car under CARS to win more races.", target = "cars", when = function(s) return stat(s, "races") >= 1 and stat(s, "upgrades") == 0 end, go = function(ctx) ctx.open("garage") end },
	{ id = "taptip", icon = "👆", text = "Tap any badge or icon to see what it does.", target = "cars", when = function(s) return stat(s, "races") >= 1 end, go = function(ctx) ctx.open("garage") end },
	{ id = "fuel", icon = "⛽", text = "Jobs burn fuel. It refills by itself over time.", target = "fuel", when = function(s) return (s.fuel or 0) <= 3 end },
	{ id = "tires", icon = "🛞", text = `Build a Tire Shop: {feature("tires")}.`, target = "shop", when = function(s) return s.level >= 2 and not owns(s, "tires") end, go = function(ctx) ctx.open("shop", "tires") end },
	{ id = "crates", icon = "📦", text = "Crates under CARS hold cars, parts and skins.", target = "cars", when = function() return true end, go = function(ctx) ctx.open("crates") end },
	{ id = "crew", icon = "👥", text = `Build a Crew House: {feature("crew")}.`, target = "shop", when = function(s) return s.level >= 3 and not owns(s, "crew") end, go = function(ctx) ctx.open("shop", "crew") end },
	{ id = "arcade", icon = "🕹️", text = `Build the Arcade: {feature("arcade")}.`, target = "shop", when = function(s) return s.level >= 5 and not owns(s, "arcade") end, go = function(ctx) ctx.open("shop", "arcade") end },
} :: { Tip }

local ctxRef: any = nil

-- Only over the plain town, never over a menu, a pop-up, edit mode, the tutorial or a visit.
function Tips.calm(s: any): boolean
	if s.level == nil or (s.tutorial or 99) < 99 or s.visiting then
		return false
	end
	local ctx = ctxRef
	if not ctx or ctx.panel() ~= nil or ctx.visiting ~= nil then
		return false
	end
	if Placement.active() or Kit.showing() ~= nil or Kit.menuOpen(ctx) or not Kit.hudUp() then
		return false
	end
	if ctx.gui:FindFirstChild("Popup") or ctx.gui:FindFirstChild("FlashWarning") or ctx.gui:FindFirstChild("Tutorial") then
		return false
	end
	return Players.LocalPlayer:GetAttribute("NeedsPlot") ~= true
end

-- The tip to show next for this town (ignoring the gap), or nil.
function Tips.next(s: any, seen: (string) -> boolean): Tip?
	for _, t in Tips.TIPS do
		if not seen(t.id) and t.when(s) then
			return t
		end
	end
	return nil
end

local tip: Tip? = nil
local lastShown = -math.huge
local card: Frame? = nil
local ring: Frame? = nil

-- The tip up now, and what it points at (the emulator presses through these).
function Tips.current(): Tip?
	return tip
end

local function close()
	local t = tip
	if t then
		Prefs.seeTip(t.id)
	end
	lastShown = os.clock()
	tip = nil
	if card then
		card:Destroy()
		card = nil
	end
end
Tips.close = close

local function drawCard(root: GuiObject, t: Tip): Frame
	local actW = 74
	local leftW = 40
	local textW = CARD_W - 20 - 6 - leftW - actW - 20
	local lines = math.max(1, math.ceil(Ui.textWidth(t.text, 16) * 0.92 / textW))
	local textH = lines * 21
	local h = math.max(40, textH) + 16 + 6
	local shadow, face = Ui.shadowed({ Name = "Tip", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -96), Size = UDim2.fromOffset(CARD_W, h), ZIndex = 15, Parent = root }, {
		radius = 16,
		stroke = 3,
		drop = 5,
		dark = 0.3,
		colors = "navy",
	})
	for _, d in shadow:GetDescendants() do
		if d:IsA("UIGradient") then
			d.Color = Ui.seq(NAVY[1], NAVY[2])
		end
	end
	local inner = h - 6
	local icon = Ui.new("Frame", { Name = "Icon", Position = UDim2.fromOffset(10, (inner - 40) / 2), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Ui.WHITE, Parent = face }, {
		Ui.round(),
		Ui.gradient("#ffe082", "#ffb300"),
		Ui.stroke(2, Ui.LINE, 0.6),
	})
	Ui.text({ Text = t.icon, TextSize = 22, Size = UDim2.fromScale(1, 1), Parent = icon })
	Ui.text({ Name = "Line", Text = t.text, Body = true, Weight = "heavy", TextSize = 16, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10 + leftW + 10, (inner - textH) / 2), Size = UDim2.fromOffset(textW, textH), Parent = face })
	local acts = Ui.new("Frame", { Name = "Actions", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0, inner / 2), Size = UDim2.fromOffset(actW, if t.go then 54 else 30), BackgroundTransparency = 1, Parent = face })
	local go = t.go
	if go then
		Ui.buy({ Name = "ShowMe", Size = UDim2.fromOffset(actW, 30), Parent = acts }, "Show me", "green", function()
			close()
			go(ctxRef)
		end, 14)
		local later = Ui.new("TextButton", { Name = "Later", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(actW, 20), Parent = acts })
		Ui.text({ Text = "Later", Body = true, Weight = "heavy", TextSize = 12, TextColor3 = Color3.fromHex("#b0bec5"), Size = UDim2.fromScale(1, 1), Parent = later })
		Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromOffset(28, 1), BackgroundColor3 = Color3.fromHex("#b0bec5"), BorderSizePixel = 0, Parent = later })
		later.Activated:Connect(close)
	else
		Ui.buy({ Name = "GotIt", Size = UDim2.fromOffset(actW, 30), Parent = acts }, "Got it", "green", close, 14)
	end
	for _, d in shadow:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = 15
		end
	end
	shadow.ZIndex = 15
	return shadow
end

-- The button the tip points at, shown on screen.
local function targetOf(name: string): GuiObject?
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not pg or not ctxRef then
		return nil
	end
	for _, d in ctxRef.gui:GetDescendants() do
		if d:GetAttribute("Tut") == name and d:IsA("GuiObject") and d.AbsoluteSize.X > 0 then
			local p: Instance? = d
			local visible = true
			while p and p ~= ctxRef.gui do
				if p:IsA("GuiObject") and not p.Visible then
					visible = false
					break
				end
				p = p.Parent
			end
			if visible then
				return d
			end
		end
	end
	return nil
end

function Tips.start(ctx: any)
	ctxRef = ctx
	local root: GuiObject = ctx.gui
	ring = Ui.new("Frame", { Name = "TipPulse", BackgroundTransparency = 1, Visible = false, ZIndex = 14, Parent = root }, {
		Ui.corner(16),
		Ui.new("UIStroke", { Thickness = 4, Color = Color3.fromHex("#ffca28") }),
	})
	local function pick()
		if tip or not Prefs.loaded then
			return
		end
		local s = store.useGame.getState()
		if not Tips.calm(s) or os.clock() - lastShown < GAP then
			return
		end
		local t = Tips.next(s, Prefs.seen)
		if not t then
			return
		end
		lastShown = os.clock()
		tip = t
	end
	Tips.pick = pick
	-- Every frame: the card shows only while the town is calm, and the ring pulses on the target.
	RunService:BindToRenderStep("Tips", Enum.RenderPriority.Last.Value - 1, function()
		local t = tip
		local s = store.useGame.getState()
		local show = t ~= nil and Tips.calm(s)
		if show and t and not card then
			card = drawCard(root, t)
		elseif not show and card then
			card:Destroy()
			card = nil
		end
		local r = ring :: Frame
		local el = if show and t then targetOf(t.target) else nil
		if not el then
			r.Visible = false
			return
		end
		local x, y, w, hh = Tutorial.rectOf(el, root)
		-- tutPulse: a gold ring swelling out from the button and fading, 1.1 s round.
		local f = (os.clock() % 1.1) / 1.1
		local grow = 8 * f
		r.Position = UDim2.fromOffset(math.round(x - 2 - grow), math.round(y - 2 - grow))
		r.Size = UDim2.fromOffset(math.round(w + 4 + grow * 2), math.round(hh + 4 + grow * 2))
		local st = r:FindFirstChildOfClass("UIStroke")
		if st then
			st.Transparency = f * 0.95
		end
		r.Visible = true
	end)
	Remote.changed:Connect(function()
		task.defer(pick)
	end)
	while true do
		task.wait(4)
		pick()
	end
end

return Tips
