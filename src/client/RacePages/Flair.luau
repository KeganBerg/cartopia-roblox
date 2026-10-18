--!strict
-- The Flair page (ui/Flair.tsx): the boost trails and win celebrations, each a tile. Open ones are
-- picked with a tap (the store's pickFlair, on the server); locked ones show their challenge's
-- progress, and a tap says the challenge (the web shows it on hover). Everything open counts as
-- seen once the page shows (seeFlair), as on the web.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local flair = require(Game.flair) :: any
local Remote = require(script.Parent.Parent.Remote)
local Ui = require(script.Parent.Parent.Ui)

local Flair = {}
Flair.id = "flair"
Flair.title = "Flair"
Flair.mini = { icon = "🎆", label = "Flair" }

local COLS = 7
local GAP = 8
local EDGE = Color3.fromHex("#c6d7ee")
local MUTED = Color3.fromHex("#4a6283")

-- The challenge as a short chip: its icon and progress (Flair.tsx need).
local function need(c: any, have: number): string
	return `{c.icon} {Ui.commas(have)}/{Ui.commas(c.goal)}`
end

local function grey(c: Color3): Color3
	local l = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return Color3.new(l, l, l)
end

function Flair.draw(page: Frame, ctx: any, api: any)
	local s = store.useGame.getState()
	local save = { trophies = s.trophies, stats = s.stats, cups = s.cups, mastery = s.mastery, trail = s.trail, cheer = s.cheer }
	-- Everything open is seen once this page shows (clears the front page's count).
	if flair.flairOpenCount(save) ~= s.flairSeen then
		task.spawn(Remote.act, "seeFlair")
	end
	local trail = flair.myTrail(save).id
	local cheer = flair.myCheer(save).id

	local list = Ui.scroller({ Name = "Flair", Size = UDim2.fromScale(1, 1), Parent = page })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), Parent = list })

	local order = 0
	local function heading(text: string)
		order += 1
		Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22), Parent = list })
	end
	-- A grid of tiles (.fl-grid), as many rows as it takes.
	local function grid(name: string, n: number, h: number): Frame
		order += 1
		local rows = math.ceil(n / COLS)
		local g = Ui.new("Frame", { Name = name, LayoutOrder = order, Size = UDim2.new(1, 0, 0, rows * h + (rows - 1) * GAP), BackgroundTransparency = 1, Parent = list })
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / COLS, -math.ceil(GAP * (COLS - 1) / COLS) - 1, 0, h), CellPadding = UDim2.fromOffset(GAP, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = g })
		return g
	end
	-- A tile (.fl-tile): picked (.sel) has a navy edge on cream; locked is faded.
	local function tile(parent: Instance, i: number, def: any, kind: string, picked: boolean): (TextButton, boolean)
		local open = flair.flairOpen(def.challenge, save)
		local b = Ui.new("TextButton", {
			Name = def.id,
			Text = "",
			AutoButtonColor = false,
			LayoutOrder = i,
			BackgroundColor3 = if picked then Color3.fromHex("#fff8e1") else Ui.WHITE,
			BackgroundTransparency = if open then 0 else 0.45,
			Parent = parent,
		}, { Ui.corner(14), Ui.stroke(2.5, if picked then Ui.LINE else EDGE, if open then 0 else 0.45) })
		local fade = if open then 0 else 0.45
		local small = if picked then "✔" elseif open then "" else need(def.challenge, flair.flairProgress(def.challenge, save))
		Ui.text({ Name = "Name", Text = def.name, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Ui.INK, TextTransparency = fade, TextTruncate = Enum.TextTruncate.AtEnd, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 4, 1, -24), Size = UDim2.new(1, -8, 0, 18), Parent = b })
		Ui.text({ Name = "Need", Text = small, Body = true, TextSize = 11, TextColor3 = MUTED, TextTransparency = fade, AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 2, 1, -8), Size = UDim2.new(1, -4, 0, 14), Parent = b })
		b.Activated:Connect(function()
			if not open then
				ctx.toast(`{def.name}: {def.challenge.text}`)
				return
			end
			if picked then
				return
			end
			if Remote.act("pickFlair", kind, def.id) then
				api.show("flair")
			end
		end)
		return b, open
	end

	heading("🔥 Boost trail")
	local trails = grid("Trails", #flair.TRAILS, 70)
	for i, t in flair.TRAILS do
		local b, open = tile(trails, i, t, "trail", t.id == trail)
		-- The trail: fading in from its tail colour to its head (.fl-trail).
		local head = Color3.fromHex(t.look.head)
		local tail = Color3.fromHex(t.look.tail)
		if not open then
			head, tail = grey(head), grey(tail)
		end
		local sw = Ui.new("Frame", { Name = "Trail", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 9), Size = UDim2.new(0.8, 0, 0, 14), BackgroundColor3 = Ui.WHITE, BackgroundTransparency = if open then 0 else 0.45, Parent = b }, { Ui.corner(7) })
		Ui.new("UIGradient", {
			Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, tail), ColorSequenceKeypoint.new(0.5, tail), ColorSequenceKeypoint.new(1, head) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0) }),
			Parent = sw,
		})
	end

	heading("🎉 Win celebration")
	local cheers = grid("Cheers", #flair.CHEERS, 84)
	for i, c in flair.CHEERS do
		local b, open = tile(cheers, i, c, "cheer", c.id == cheer)
		Ui.text({ Name = "Icon", Text = c.icon, TextSize = 26, TextTransparency = if open then 0 else 0.5, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(40, 30), Parent = b })
	end
end

return Flair
