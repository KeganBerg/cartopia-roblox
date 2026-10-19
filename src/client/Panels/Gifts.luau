--!strict
-- Friends' mail, as the web game's GiftsPanel (ui/Gifts.tsx): who helped your town or sent you a
-- gift (+fuel or +parts each), the postcards you've been sent, and Collect, which takes what the
-- server pays today (10 notes a day; the rest wait). The HUD's gift bell opens it (server/Mail).

local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)
local Postcards = require(script.Parent.Parent.Social.Postcards)

local Gifts = {}
Gifts.id = "gifts"

local ICON = { help = "🤝", fuel = "⛽", parts = "⚙️" }
local CLAIMS_PER_DAY = 10

local function avatar(parent: Instance, userId: number, name: string, kind: string)
	local hue = 7
	for _, c in utf8.codes(name) do
		hue = (hue * 31 + c) % 360
	end
	local holder = Ui.new("Frame", { Name = "Avatar", Position = UDim2.fromOffset(10, 7), Size = UDim2.fromOffset(36, 36), BackgroundColor3 = Color3.fromHSV(hue / 360, 0.6, 0.85), Parent = parent }, {
		Ui.round(),
		Ui.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = `rbxthumb://type=AvatarHeadShot&id={userId}&w=48&h=48` }, { Ui.round() }),
	})
	Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1.15, 1.1), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Ui.WHITE, ZIndex = 2, Parent = holder }, {
		Ui.round(),
		Ui.text({ Text = ICON[kind] or "🎁", TextSize = 12, Size = UDim2.fromScale(1, 1), ZIndex = 2 }),
	})
end

function Gifts.open(ctx: any): Instance
	local overlay, _sheet, body = Ui.panel(ctx.gui, "Friends helped you!", { width = 560, height = 720, onClose = ctx.close })
	local list = Ui.scroller({ Name = "List", Size = UDim2.new(1, 0, 1, -58), Parent = body })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = list })
	local foot = Ui.new("Frame", { Name = "Foot", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = body })
	local loading = Ui.text({ Name = "Loading", Text = "Checking the mail…", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, Size = UDim2.new(1, 0, 0, 40), Parent = list })

	local function draw(box: any)
		for _, holder in { list, foot } do
			for _, c in holder:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
		end
		local notes, cards = box.notes or {}, box.cards or {}
		-- What Collect pays now: the oldest ten (the list is newest first).
		local fuel, parts = 0, 0
		for i = #notes, math.max(1, #notes - CLAIMS_PER_DAY + 1), -1 do
			local n = notes[i]
			if n.kind == "parts" then
				parts += n.amount
			else
				fuel += n.amount
			end
		end
		if #notes == 0 and #cards == 0 then
			Ui.text({ Name = "Empty", LayoutOrder = 1, Text = "📭 Nothing in the mail yet. Help a friend's town or send them a gift, and they can do the same for you!", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, TextWrapped = true, Size = UDim2.new(1, 0, 0, 60), Parent = list })
		end
		if fuel > 0 or parts > 0 then
			local totals = Ui.new("Frame", { Name = "Totals", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = list }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for i, t in { { fuel, "⛽", "#e3f2fd", "#1565c0" }, { parts, "⚙", "#fff3e0", "#e65100" } } do
				if (t[1] :: number) > 0 then
					Ui.new("Frame", { Name = if i == 1 then "Fuel" else "Parts", LayoutOrder = i, Size = UDim2.fromOffset(110, 38), BackgroundColor3 = Color3.fromHex(t[3] :: string), Parent = totals }, {
						Ui.corner(19),
						Ui.stroke(2, Color3.fromHex(t[4] :: string)),
						Ui.text({ Text = `{t[2]} +{t[1]}`, TextSize = 20, TextColor3 = Color3.fromHex(t[4] :: string), Size = UDim2.fromScale(1, 1) }),
					})
				end
			end
		end
		for i, n in notes do
			local r = Ui.new("Frame", { Name = `Note{n.id}`, LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Ui.WHITE, Parent = list }, {
				Ui.corner(12),
				Ui.stroke(2, Color3.fromHex("#e0e0e0")),
			})
			local name = tostring(n.name or n.town or "A friend")
			avatar(r, tonumber(n.from) or 0, name, n.kind)
			Ui.text({ Text = name, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(58, 6), Size = UDim2.new(1, -150, 0, 20), Parent = r })
			Ui.text({ Text = if n.kind == "help" then `helped {n.town or "your town"}` else "sent you a gift", Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(58, 26), Size = UDim2.new(1, -150, 0, 17), Parent = r })
			Ui.text({ Text = `+{n.amount} {if n.kind == "parts" then "⚙" else "⛽"}`, TextSize = 18, TextColor3 = Color3.fromHex("#2e7d32"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(80, 24), Parent = r })
		end
		if #cards > 0 then
			Ui.text({ Name = "CardsHead", LayoutOrder = 100, Text = "💌 Postcards", TextSize = 19, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 26), Parent = list })
			local grid = Ui.new("Frame", { Name = "Cards", LayoutOrder = 101, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = list }, {
				Ui.new("UIGridLayout", { CellSize = UDim2.new(0.5, -5, 0, 140), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for i, c in cards do
				Postcards.face(grid, c.card, c.msg, tostring(c.name or c.town or "a friend"), UDim2.new(), i)
			end
		end
		if #notes > 0 then
			local busy = false
			Ui.buy({ Name = "Collect", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(220, 44), Parent = foot }, "🎁 Collect", "green", function()
				if busy then
					return
				end
				busy = true
				local ok, got = Remote.social("claimMail")
				busy = false
				if not ok or not overlay.Parent then
					return
				end
				if got.left == 0 and #cards == 0 then
					ctx.close()
					return
				end
				local rest = {}
				for j = 1, got.left do
					rest[j] = notes[j]
				end
				draw({ notes = rest, cards = cards })
			end, 20)
		else
			Ui.buy({ Name = "Nice", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.fromOffset(180, 44), Parent = foot }, "👍 Nice", "garage", ctx.close, 20)
		end
	end

	task.spawn(function()
		local ok, box = Remote.social("mail", nil, true)
		if not overlay.Parent then
			return
		end
		loading:Destroy()
		if not ok then
			Ui.text({ Name = "Note", Text = "Couldn't check the mail right now. Try again in a moment.", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, TextWrapped = true, Size = UDim2.new(1, 0, 0, 40), Parent = list })
			return
		end
		draw(box)
	end)
	return overlay
end

return Gifts
