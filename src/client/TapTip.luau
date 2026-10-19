--!strict
-- Tap-to-explain, as the web game's TapTip (ui/TapTip.tsx, taptip.css). Phones never show
-- tooltips, so badges explain themselves in a small navy bubble when tapped:
-- - a plain badge (TapTip.mark): one tap shows its line;
-- - a badge sitting on a button (a card, a row): the badge takes the tap, so tapping it explains
--   instead of pressing what's under it;
-- - a button (TapTip.hold): press and hold shows its line, a normal tap still presses it.
-- A car's skill and the businesses it loves get a richer bubble (TapTip.skill, TapTip.loves).
-- "Name: what it does" reads as a bold name over one line. The bubble sits above the badge when it
-- fits, else below it, and goes by itself after 6 seconds or on the next tap anywhere.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local Ui = require(script.Parent.Ui)

local TapTip = {}

local BG = Color3.fromHex("#1f2340")
local MAX_W = 300
local PAD_X, PAD_Y = 12, 10
local EDGE = 8
local HOLD = 0.45

-- What each skill does in a drag race, as two chips: the effect and when it kicks in (the web's
-- SKILL_CHIPS, which its tests check against skillBoost/skillDrag).
TapTip.SKILL_CHIPS = {
	launch = { "+20% speed", "⚙️ Gear 1" },
	nitro = { "+15% power", "⚙️ Top 2 gears" },
	slipstream = { "+8% speed", "💨 When behind" },
	smooth = { "Good = Perfect", "⚙️ Every shift" },
	oil = { "Rival −10% grip", "⏱ First 4 s" },
	torque = { "+10% power", "⚙️ Gears 1–2" },
	freeze = { "Rival −10% speed", "⚙️ Their gear 2" },
} :: { [string]: { string } }

export type Chip = { text: string, kind: string? } -- kind: "fx" (green) or "off" (faint)
export type Body = { head: string?, text: string?, loves: { string }?, chips: { Chip }? }

local gui: ScreenGui? = nil
local bubble: Frame? = nil
local shownAt = 0
local seq = 0

local function pctOf(n: number): string
	return `+{math.round(n * 100)}%`
end

-- The web's bodyFor: "Name: what it does" as a bold name over the line.
function TapTip.bodyFor(text: string): Body
	local name, rest = string.match(text, "^([^:%.]+): (.+)$")
	if name and #name >= 2 and #name <= 32 then
		return { head = name, text = rest }
	end
	return { text = text }
end

function TapTip.skillBody(sk: string): Body?
	local s = data.SKILLS[sk]
	local chips = TapTip.SKILL_CHIPS[sk]
	if not s or not chips then
		return nil
	end
	return { head = `{s.icon} {s.name}`, chips = { { text = chips[1], kind = "fx" }, { text = chips[2] }, { text = "🏁 Drag races" } } }
end

-- likes: business ids; icons: each one's little icon.
function TapTip.lovesBody(likes: { string }, icons: { [string]: string }?): Body
	local list = {}
	for _, id in likes do
		local ok, d = pcall(data.buildingDef, id)
		table.insert(list, `{(icons and icons[id]) or "🏪"} {if ok and d then d.name else id}`)
	end
	return {
		head = "❤️ Favorite Job",
		loves = list,
		chips = { { text = `{pctOf(data.FAVORITE_BONUS)} 🪙 a job`, kind = "fx" }, { text = `Others {pctOf(data.DRIVER_BONUS)}` }, { text = "🏁 No race effect", kind = "off" } },
	}
end

local function scaleNow(): number
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("Cartopia")
	local root = hud and hud:FindFirstChild("Root")
	local s = root and root:FindFirstChildOfClass("UIScale")
	return if s then s.Scale else 1
end

local function measure(text: string, size: number, width: number): Vector2
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, Enum.Font.Nunito, Vector2.new(width, 10000))
	end)
	if ok and v then
		-- Bold Nunito runs a little wider than the plain face measured here.
		return Vector2.new(math.ceil(v.X * 1.08) + 2, v.Y + 2)
	end
	return Vector2.new(math.min(width, #text * size * 0.55), size * 1.4)
end

function TapTip.hide()
	if bubble then
		bubble:Destroy()
		bubble = nil
	end
end

function TapTip.showing(): Frame?
	return bubble
end

-- Shows a bubble over (or under) a badge.
function TapTip.show(anchor: GuiObject, body: Body)
	TapTip.hide()
	local g = gui
	if not g then
		return
	end
	local sc = scaleNow()
	local scale = g:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = sc
	end
	local cam = workspace.CurrentCamera
	local view = if cam then cam.ViewportSize / sc else Vector2.new(1280, 800)
	local maxW = math.min(MAX_W, view.X - 16) - PAD_X * 2
	-- Lay the pieces out top to bottom, measuring each.
	local pieces: { { kind: string, text: string?, list: { any }?, w: number, h: number } } = {}
	local w = 0
	if body.head then
		local m = measure(body.head, 16, maxW)
		table.insert(pieces, { kind = "head", text = body.head, w = m.X, h = m.Y })
		w = math.max(w, m.X)
	end
	if body.text then
		local m = measure(body.text, 15, maxW)
		table.insert(pieces, { kind = "text", text = body.text, w = m.X, h = m.Y })
		w = math.max(w, m.X)
	end
	-- Rows of little pills that wrap (.tt-loves and .tt-chips).
	local function rows(items: { any }, size: number, padX: number, gap: number, h: number): ({ { any } }, number, number)
		local out: { { any } } = { {} }
		local x, widest = 0, 0
		for _, it in items do
			local iw = measure(it.text, size, 1000).X + padX * 2
			if x > 0 and x + iw > maxW then
				table.insert(out, {})
				x = 0
			end
			table.insert(out[#out], { text = it.text, kind = it.kind, x = x, w = iw })
			x += iw + gap
			widest = math.max(widest, x - gap)
		end
		return out, widest, #out * h + (#out - 1) * 4
	end
	if body.loves then
		local items = {}
		for _, l in body.loves do
			table.insert(items, { text = l })
		end
		local list, rw, rh = rows(items, 15, 0, 10, 20)
		table.insert(pieces, { kind = "loves", list = list, w = rw, h = rh })
		w = math.max(w, rw)
	end
	if body.chips then
		local list, rw, rh = rows(body.chips, 13, 8, 5, 22)
		table.insert(pieces, { kind = "chips", list = list, w = rw, h = rh })
		w = math.max(w, rw)
	end
	local h = 0
	for i, p in pieces do
		h += p.h + (if i > 1 then 6 else 0)
	end
	local bw, bh = w + PAD_X * 2, h + PAD_Y * 2

	-- Where: centred over the badge, kept on screen; above it when it fits, else below.
	local a = anchor.AbsolutePosition / sc
	local s = anchor.AbsoluteSize / sc
	local cx = a.X + s.X / 2
	local left = math.min(view.X - EDGE - bw, math.max(EDGE, cx - bw / 2))
	local below = a.Y - bh - 12 < EDGE
	local top = if below then a.Y + s.Y + 10 else a.Y - bh - 10
	local arrow = math.min(bw - 14, math.max(14, cx - left))

	seq += 1
	local f = Ui.new("TextButton", {
		Name = "TapTip",
		Text = "",
		AutoButtonColor = false,
		BackgroundColor3 = BG,
		Position = UDim2.fromOffset(math.round(left), math.round(top)),
		Size = UDim2.fromOffset(math.ceil(bw), math.ceil(bh)),
		ZIndex = 2,
		Parent = g,
	}, { Ui.corner(14) })
	f.Activated:Connect(TapTip.hide)
	-- The little arrow at the badge (a turned square half under the bubble).
	Ui.new("Frame", { Name = "Arrow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, arrow, if below then 0 else 1, 0), Size = UDim2.fromOffset(14, 14), Rotation = 45, BackgroundColor3 = BG, BorderSizePixel = 0, ZIndex = 1, Parent = f }, { Ui.corner(2) })
	local y = PAD_Y
	for _, p in pieces do
		if p.kind == "head" or p.kind == "text" then
			Ui.text({ Text = p.text :: string, Body = true, Weight = if p.kind == "head" then "heavy" else nil, TextSize = if p.kind == "head" then 16 else 15, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(PAD_X, y), Size = UDim2.fromOffset(maxW, p.h), ZIndex = 3, Parent = f })
		else
			local rowH = if p.kind == "chips" then 22 else 20
			for r, row in p.list :: { { any } } do
				for _, it in row do
					local ry = y + (r - 1) * (rowH + 4)
					if p.kind == "chips" then
						local c = Ui.new("Frame", { Position = UDim2.fromOffset(PAD_X + it.x, ry), Size = UDim2.fromOffset(it.w, rowH), BackgroundColor3 = if it.kind == "fx" then Color3.fromHex("#43a047") else Ui.WHITE, BackgroundTransparency = if it.kind == "fx" then 0 elseif it.kind == "off" then 0.94 else 0.86, ZIndex = 3, Parent = f }, { Ui.round() })
						Ui.text({ Text = it.text, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = if it.kind == "off" then Color3.fromHex("#c5cae9") else Ui.WHITE, Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = c })
					else
						Ui.text({ Text = it.text, Body = true, Weight = "heavy", TextSize = 15, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(PAD_X + it.x, ry), Size = UDim2.fromOffset(it.w + 4, rowH), ZIndex = 3, Parent = f })
					end
				end
			end
		end
		y += p.h + 6
	end
	bubble = f
	shownAt = os.clock()
	local mine = seq
	task.delay(6, function()
		if seq == mine then
			TapTip.hide()
		end
	end)
end

-- The bubble a marked badge shows.
local function bodyOf(g: Instance): Body?
	local sk = g:GetAttribute("TipSkill")
	if type(sk) == "string" then
		return TapTip.skillBody(sk)
	end
	local loves = g:GetAttribute("TipLoves")
	if type(loves) == "string" then
		local icons = g:GetAttribute("TipIcons")
		local iconOf: { [string]: string } = {}
		if type(icons) == "string" then
			for pair in string.gmatch(icons, "[^,]+") do
				local id, icon = string.match(pair, "^([^=]+)=(.+)$")
				if id and icon then
					iconOf[id] = icon
				end
			end
		end
		return TapTip.lovesBody(string.split(loves, ","), iconOf)
	end
	local text = g:GetAttribute("Tip")
	return if type(text) == "string" and text ~= "" then TapTip.bodyFor(text) else nil
end

-- A clear button over the badge takes its taps, so a badge on a card explains rather than presses.
local function catcher(g: GuiObject)
	if g:FindFirstChild("TipTap") then
		return
	end
	local b = Ui.new("TextButton", { Name = "TipTap", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = g.ZIndex + 1, Parent = g })
	b.Activated:Connect(function()
		local body = bodyOf(g)
		if body then
			TapTip.show(g, body)
		end
	end)
end

-- A badge (not a button) that explains itself when tapped.
function TapTip.mark(g: GuiObject, text: string)
	g:SetAttribute("Tip", text)
	catcher(g)
end

-- A car's race skill badge.
function TapTip.skill(g: GuiObject, sk: string)
	g:SetAttribute("TipSkill", sk)
	g:SetAttribute("Tip", if data.SKILLS[sk] then `{data.SKILLS[sk].name}: {data.SKILLS[sk].text}` else nil)
	catcher(g)
end

-- The businesses a car loves.
function TapTip.loves(g: GuiObject, likes: { string }, icons: { [string]: string }?)
	g:SetAttribute("TipLoves", table.concat(likes, ","))
	local pairs_ = {}
	for _, id in likes do
		if icons and icons[id] then
			table.insert(pairs_, `{id}={icons[id]}`)
		end
	end
	g:SetAttribute("TipIcons", table.concat(pairs_, ","))
	catcher(g)
end

-- A button whose line shows on press and hold (a normal tap still presses it).
function TapTip.hold(g: GuiObject, text: string)
	g:SetAttribute("Tip", text)
	g:SetAttribute("TipHold", true)
end

-- The marked button under a press, if any.
local function heldAt(pos: Vector2): GuiObject?
	local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return nil
	end
	local ok, list = pcall(function()
		return (pg :: PlayerGui):GetGuiObjectsAtPosition(pos.X, pos.Y)
	end)
	if not ok or not list then
		return nil
	end
	for _, o in list do
		local p: Instance? = o
		while p and not p:IsA("LayerCollector") do
			if p:GetAttribute("TipHold") == true then
				return p :: GuiObject
			end
			p = p.Parent
		end
	end
	return nil
end

-- Mounted once (init.client): the bubble's layer, and the listener for holds and taps elsewhere.
function TapTip.start()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Ui.new("ScreenGui", { Name = "TapTips", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Parent = pg })
	Ui.new("UIScale", { Scale = 1, Parent = g })
	gui = g
	local hold: { input: InputObject, at: Vector2, n: number }? = nil
	local holds = 0
	UserInputService.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then
			return
		end
		-- A tap anywhere but the bubble closes it (a badge's own tap opens it again after).
		local b = bubble
		if b then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			local okInset, inset = pcall(function()
				return game:GetService("GuiService"):GetGuiInset()
			end)
			local sp = p + (if okInset then inset else Vector2.zero)
			local a, s = b.AbsolutePosition, b.AbsoluteSize
			local inside = sp.X >= a.X and sp.X <= a.X + s.X and sp.Y >= a.Y and sp.Y <= a.Y + s.Y
			if not inside and os.clock() - shownAt > 0.05 then
				TapTip.hide()
			end
		end
		local pos = Vector2.new(input.Position.X, input.Position.Y)
		local el = heldAt(pos)
		if not el then
			return
		end
		holds += 1
		local mine = holds
		hold = { input = input, at = pos, n = mine }
		task.delay(HOLD, function()
			local h = hold
			if not h or h.n ~= mine then
				return
			end
			local body = bodyOf(el)
			if not body then
				return
			end
			TapTip.show(el, body)
			-- The hold explained the button: don't press it on release.
			local button = if el:IsA("GuiButton") then el else el:FindFirstAncestorWhichIsA("GuiButton")
			if button then
				pcall(function()
					(button :: any).Interactable = false
				end)
				local c: RBXScriptConnection
				c = UserInputService.InputEnded:Connect(function(e)
					if e == h.input or e.UserInputType == Enum.UserInputType.MouseButton1 then
						c:Disconnect()
						task.defer(function()
							pcall(function()
								(button :: any).Interactable = true
							end)
						end)
					end
				end)
			end
		end)
	end)
	UserInputService.InputChanged:Connect(function(input)
		local h = hold
		if h and (input == h.input or input.UserInputType == Enum.UserInputType.MouseMovement) then
			if (Vector2.new(input.Position.X, input.Position.Y) - h.at).Magnitude > 10 then
				hold = nil
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local h = hold
		if h and (input == h.input or input.UserInputType == Enum.UserInputType.MouseButton1) then
			hold = nil
		end
	end)
end

return TapTip
