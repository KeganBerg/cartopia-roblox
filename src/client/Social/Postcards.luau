--!strict
-- Postcards and gifts for friends (the web game's lib/postcards.ts, ui/Postcards.tsx and
-- ui/Gifts.tsx GiftButton): a picture card with a set message (no free text), and today's gift
-- of 15 fuel or 5 parts. The server keeps the limits (server/Mail).

local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)

local Postcards = {}

-- The pictures: name, stamp and colours top to bottom (the web's gradients).
Postcards.CARDS = {
	{ id = "sunset", name = "Sunset Drive", icon = "🌅", colors = { "#ffb36b", "#f0625d", "#6a3d7a" } },
	{ id = "neon", name = "Neon Night", icon = "🌃", colors = { "#1a0630", "#4b1d7a", "#ff4fd8" } },
	{ id = "beach", name = "Beach Day", icon = "🏖️", colors = { "#7fd8ff", "#4fc3f7", "#ffe0a3" } },
	{ id = "snow", name = "Snow Peak", icon = "🏔️", colors = { "#e6f0f7", "#a9c7e3", "#5d7fa8" } },
	{ id = "flag", name = "Race Day", icon = "🏁", colors = { "#fafafa", "#9e9e9e", "#222222" } },
	{ id = "garage", name = "Garage", icon = "🔧", colors = { "#90a4ae", "#546e7a", "#ffca28" } },
}
Postcards.MESSAGES = {
	"Wish you were here!",
	"Race you later?",
	"Love your town!",
	"Thanks for the help!",
	"GG, well raced!",
	"Happy racing!",
	"Come visit soon!",
	"Check out my new car!",
}
Postcards.GIFTS = {
	{ item = "fuel", icon = "⛽", amount = 15 },
	{ item = "parts", icon = "⚙", amount = 5 },
}

function Postcards.cardOf(id: string): any
	for _, c in Postcards.CARDS do
		if c.id == id then
			return c
		end
	end
	return Postcards.CARDS[1]
end

local function gradient(colors: { string }): UIGradient
	local a, b, c = Color3.fromHex(colors[1]), Color3.fromHex(colors[2]), Color3.fromHex(colors[3])
	return Ui.new("UIGradient", { Rotation = 70, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(0.55, b), ColorSequenceKeypoint.new(1, c) }) })
end

-- A postcard: the picture, its stamp, the message and who it's from.
function Postcards.face(parent: Instance, card: string, msg: number, from: string, size: UDim2, order: number?): Frame
	local c = Postcards.cardOf(card)
	local f = Ui.new("Frame", { Name = "Postcard", LayoutOrder = order or 0, Size = size, BackgroundColor3 = Ui.WHITE, Parent = parent }, {
		Ui.corner(12),
		Ui.stroke(3, Ui.WHITE),
		gradient(c.colors),
	})
	Ui.new("Frame", { Name = "Stamp", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(38, 44), BackgroundColor3 = Ui.WHITE, Rotation = 6, Parent = f }, {
		Ui.corner(4),
		Ui.text({ Text = c.icon, TextSize = 24, Size = UDim2.fromScale(1, 1) }),
	})
	Ui.text({ Name = "Message", Text = Postcards.MESSAGES[msg + 1] or Postcards.MESSAGES[1], TextSize = 20, TextWrapped = true, Stroke = 1.5, StrokeColor = Color3.fromHex("#1b1f24"), Position = UDim2.new(0, 12, 0.2, 0), Size = UDim2.new(1, -60, 0.55, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = f })
	Ui.text({ Name = "From", Text = `from {from}`, Body = true, Weight = "heavy", TextSize = 13, Stroke = 1, StrokeColor = Color3.fromHex("#1b1f24"), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 12, 1, -24), Size = UDim2.new(1, -24, 0, 18), Parent = f })
	return f
end

-- The postcard picker over parent: a picture, a message, then Send. onSent after it's sent.
function Postcards.pick(parent: Instance, to: number, name: string, onSent: () -> ()): Instance
	local overlay: Instance
	local function close()
		overlay:Destroy()
	end
	local o, _sheet, body = Ui.panel(parent, "💌 Postcard", { width = 500, height = 620, onClose = close })
	overlay = o
	o.Name = "PostcardPicker"
	local card, msg = Postcards.CARDS[1].id, 0
	local list = Ui.scroller({ Name = "List", Size = UDim2.fromScale(1, 1), Parent = body })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = list })
	Ui.text({ Name = "To", LayoutOrder = 1, Text = `To {name}`, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, Size = UDim2.new(1, 0, 0, 20), Parent = list })
	local preview = Ui.new("Frame", { Name = "Preview", LayoutOrder = 2, Size = UDim2.fromOffset(300, 170), BackgroundTransparency = 1, Parent = list })
	local cards = Ui.new("Frame", { Name = "Cards", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = list }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local msgs = Ui.new("Frame", { Name = "Messages", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = list }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 36), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local draw: () -> ()
	draw = function()
		for _, holder in { preview, cards, msgs } do
			for _, c in holder:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
		end
		Postcards.face(preview, card, msg, "You", UDim2.fromScale(1, 1))
		for i, c in Postcards.CARDS do
			local on = c.id == card
			local b = Ui.new("TextButton", { Name = c.id, Text = c.icon, TextSize = 22, LayoutOrder = i, Size = UDim2.fromOffset(48, 48), BackgroundColor3 = Ui.WHITE, Parent = cards }, {
				Ui.corner(10),
				Ui.stroke(if on then 4 else 2, if on then Color3.fromHex("#f5b400") else Ui.WHITE),
				gradient(c.colors),
			})
			b.Activated:Connect(function()
				card = c.id
				draw()
			end)
		end
		for i, m in Postcards.MESSAGES do
			local on = i - 1 == msg
			local b = Ui.new("TextButton", { Name = `Msg{i}`, Text = m, FontFace = Ui.HEAVY, TextSize = 14, TextColor3 = Ui.INK, LayoutOrder = i, BackgroundColor3 = if on then Color3.fromHex("#fff3c4") else Ui.WHITE, Parent = msgs }, {
				Ui.corner(10),
				Ui.stroke(2, if on then Color3.fromHex("#f5b400") else Color3.fromHex("#e0e0e0")),
			})
			b.Activated:Connect(function()
				msg = i - 1
				draw()
			end)
		end
	end
	draw()
	local acts = Ui.new("Frame", { Name = "Acts", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = list }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	Ui.buy({ Name = "Cancel", LayoutOrder = 1, Size = UDim2.fromOffset(120, 40), Parent = acts }, "Cancel", "grey", close, 17)
	local busy = false
	Ui.buy({ Name = "Send", LayoutOrder = 2, Size = UDim2.fromOffset(140, 40), Parent = acts }, "💌 Send", "green", function()
		if busy then
			return
		end
		busy = true
		local ok = Remote.social("postcard", { to = to, card = card, msg = msg, name = name })
		busy = false
		if ok then
			close()
			onSent()
		end
	end, 17)
	return overlay
end

-- Today's gift: a small choice over parent of 15 fuel or 5 parts. onSent after it's sent.
function Postcards.gift(parent: Instance, to: number, name: string, onSent: () -> ()): Instance
	local overlay: Instance
	local function close()
		overlay:Destroy()
	end
	local o, _sheet, body = Ui.panel(parent, "🎁 Gift", { width = 420, height = 300, onClose = close })
	overlay = o
	o.Name = "GiftPicker"
	Ui.text({ Name = "To", Text = `A gift for {name}, once a day`, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, TextWrapped = true, Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 40), Parent = body })
	local row = Ui.new("Frame", { Name = "Choices", Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 90), BackgroundTransparency = 1, Parent = body }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 14), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local busy = false
	for i, g in Postcards.GIFTS do
		Ui.buy({ Name = g.item, LayoutOrder = i, Size = UDim2.fromOffset(150, 80), Parent = row }, `{g.icon} {g.amount} {g.item}`, "green", function()
			if busy then
				return
			end
			busy = true
			local ok = Remote.social("gift", { to = to, item = g.item, name = name })
			busy = false
			if ok then
				close()
				onSent()
			end
		end, 20)
	end
	return overlay
end

return Postcards
