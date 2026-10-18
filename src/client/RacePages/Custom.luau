--!strict
-- A custom kart race (ui/CustomKart.tsx): pick the circuit and which way round, mix the rules
-- (obstacles, Bumper Blast's hard bumps, max boost), then race. Every mix pays the party prize.
-- A card over the race menu; the server (server/Karts) checks the pick and starts it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local K = require(Game.kart) :: any
local Ui = require(script.Parent.Parent.Ui)

local Custom = {}
Custom.id = "custom"
Custom.title = "Custom race"

local RULES = {
	{ id = "obstacles", icon = "📦", label = "Obstacles" },
	{ id = "blast", icon = "💥", label = "Bumper" },
	{ id = "maxBoost", icon = "🔥", label = "Max boost" },
}

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

-- The picker card (.ck-modal): the circuits, the direction, the rules, Back and 🏁 Race.
function Custom.open(ctx: any, api: any): Frame
	local track, reverse = 0, false
	local rules: { [string]: boolean } = { obstacles = true }
	local overlay = Ui.new("TextButton", { Name = "CustomRace", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = hex("#080c1e"), BackgroundTransparency = 0.28, ZIndex = 60, Parent = api.sheet or ctx.gui })
	local function close()
		overlay:Destroy()
	end
	overlay.Activated:Connect(close)
	local card = Ui.new("TextButton", { Name = "Card", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(380, 352), BackgroundColor3 = Ui.SHEET, ClipsDescendants = true, ZIndex = 61, Parent = overlay }, { Ui.corner(18), Ui.stroke(3, Ui.LINE) })
	-- The card itself stops taps from reaching the backdrop (which closes it).
	card:SetAttribute("SinkTaps", true)
	-- The head: blue, the 🛠️ in its navy disc, the title.
	local head = Ui.new("Frame", { Name = "Head", Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 61, Parent = card }, { Ui.gradient("#64b5f6", "#1e88e5") })
	Ui.new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = Ui.LINE, BorderSizePixel = 0, ZIndex = 62, Parent = head })
	local bolt = Ui.new("Frame", { Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Ui.LINE, ZIndex = 62, Parent = head }, { Ui.round() })
	Ui.text({ Text = "🛠️", TextSize = 20, Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = bolt })
	Ui.text({ Text = "Custom race", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 4), Size = UDim2.new(1, -70, 0, 40), Stroke = 1.5, Shadow = 3, ZIndex = 62, Parent = head })

	local tracksRow = Ui.new("Frame", { Name = "Tracks", Position = UDim2.fromOffset(14, 64), Size = UDim2.new(1, -28, 0, 64), BackgroundTransparency = 1, ZIndex = 61, Parent = card })
	local seg = Ui.new("Frame", { Name = "Direction", Position = UDim2.fromOffset(14, 138), Size = UDim2.new(1, -28, 0, 38), BackgroundColor3 = Ui.SEG, ZIndex = 61, Parent = card }, { Ui.corner(12) })
	local rulesRow = Ui.new("Frame", { Name = "Rules", Position = UDim2.fromOffset(14, 186), Size = UDim2.new(1, -28, 0, 64), BackgroundTransparency = 1, ZIndex = 61, Parent = card })
	local function tile(parent: Instance, k: number, of: number, icon: string, label: string, on: boolean, onColor: string, onEdge: string, onClick: () -> ()): TextButton
		local w = (352 - 8 * (of - 1)) / of
		local b = Ui.new("TextButton", { Text = "", AutoButtonColor = false, Position = UDim2.fromOffset((k - 1) * (w + 8), 0), Size = UDim2.fromOffset(w, 64), BackgroundColor3 = if on then hex(onColor) else Ui.WHITE, ZIndex = 62, Parent = parent }, { Ui.corner(12), Ui.stroke(2.5, if on then hex(onEdge) else hex("#cfd8dc")) })
		Ui.text({ Text = icon, TextSize = 24, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 26), ZIndex = 62, Parent = b })
		Ui.text({ Text = label, TextSize = 14, TextColor3 = Ui.LINE, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 20), ZIndex = 62, Parent = b })
		b.Activated:Connect(onClick)
		return b
	end
	local draw: () -> ()
	draw = function()
		tracksRow:ClearAllChildren()
		for i, t in K.TRACKS do
			tile(tracksRow, i, #K.TRACKS, t.icon, t.short, track == i - 1, "#e3f2fd", "#1e88e5", function()
				track = i - 1
				draw()
			end)
		end
		seg:ClearAllChildren()
		Ui.corner(12).Parent = seg
		for i, o in { { false, "↻ Normal" }, { true, "↺ Reversed" } } do
			local sel = reverse == o[1]
			local b = Ui.new("TextButton", { Name = if o[1] then "Reversed" else "Normal", Text = "", AutoButtonColor = false, Position = UDim2.new((i - 1) * 0.5, 3, 0, 3), Size = UDim2.new(0.5, -4.5, 1, -6), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = if sel then 0 else 1, ZIndex = 62, Parent = seg }, { Ui.corner(9) })
			Ui.text({ Text = o[2], TextSize = 14, TextColor3 = if sel then Ui.INK else hex("#546e7a"), Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = b })
			b.Activated:Connect(function()
				reverse = o[1]
				draw()
			end)
		end
		rulesRow:ClearAllChildren()
		for i, r in RULES do
			local on = rules[r.id] == true
			local b = tile(rulesRow, i, #RULES, r.icon, r.label, on, "#e8f5e9", "#43a047", function()
				rules[r.id] = not rules[r.id]
				draw()
			end)
			b.Name = r.id
			if on then
				Ui.text({ Text = "✓", Body = true, Weight = "heavy", TextSize = 16, TextColor3 = hex("#2e7d32"), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 4), Size = UDim2.fromOffset(16, 16), ZIndex = 62, Parent = b })
			end
		end
	end
	draw()
	-- Back and 🏁 Race (.cf-actions).
	local back = Ui.new("TextButton", { Name = "Back", Text = "", AutoButtonColor = false, Position = UDim2.new(0, 14, 1, -60), Size = UDim2.new(0.5, -19, 0, 46), BackgroundColor3 = Ui.WHITE, ZIndex = 62, Parent = card }, { Ui.corner(12), Ui.stroke(2.5, Ui.LINE) })
	Ui.text({ Text = "Back", TextSize = 18, TextColor3 = Ui.LINE, Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = back })
	back.Activated:Connect(close)
	local go = Ui.new("TextButton", { Name = "Race", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 1, -60), Size = UDim2.new(0.5, -19, 0, 46), BackgroundColor3 = Ui.WHITE, ZIndex = 62, Parent = card }, { Ui.corner(12), Ui.stroke(2.5, Ui.WHITE), Ui.gradient("#66bb6a", "#2e7d32") })
	Ui.text({ Text = "🏁 Race", TextSize = 18, Size = UDim2.fromScale(1, 1), Stroke = 1.5, ZIndex = 62, Parent = go })
	go.Activated:Connect(function()
		local pick = { track = track, reverse = reverse, rules = { obstacles = rules.obstacles == true, blast = rules.blast == true, maxBoost = rules.maxBoost == true } }
		close()
		api.kart("custom", pick)
	end)
	return overlay
end

Custom.mini = {
	icon = "🛠️",
	label = "Custom race",
	go = function(ctx: any, api: any)
		Custom.open(ctx, api)
	end,
}

function Custom.draw(_page: Frame, _ctx: any, api: any)
	api.show("hub")
end

return Custom
