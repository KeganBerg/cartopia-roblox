--!strict
-- The challenge bell's menu (the web game's ChallengeBell, ui/ChallengeBell.tsx): the live drag
-- races other players here have asked you to, each with their car, its PI, the prize for beating
-- it and how long it stays open, with Race and No. Opens from the HUD's 🏁 bell (client/LiveDuels).

local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local LiveDuels = require(script.Parent.Parent.LiveDuels)

local Invites = {}
Invites.id = "invites"

-- The web's liveReward (Race.tsx): what beating a live rival pays, by their PI.
function Invites.prize(pi: number): number
	return 300 + pi * 8
end

local function money(n: number): string
	return if n >= 10000 then `${math.round(n / 1000)}k` else `${Ui.commas(n)}`
end

function Invites.open(ctx: any): Instance
	local overlay, _sheet, body = Ui.panel(ctx.gui, "Race challenges", { width = 560, height = 560, onClose = ctx.close })
	local list = Ui.scroller({ Name = "List", Size = UDim2.fromScale(1, 1), Parent = body })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = list })
	local clocks: { [string]: { label: TextLabel, prize: string } } = {}

	local function draw()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		table.clear(clocks)
		local waiting = LiveDuels.waiting()
		if #waiting == 0 then
			Ui.text({ Name = "Empty", LayoutOrder = 1, Text = "🏁 No challenges right now. Race another driver here from the Race menu's Live page!", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, TextWrapped = true, Size = UDim2.new(1, 0, 0, 60), Parent = list })
			return
		end
		for i, inv in waiting do
			local row = Ui.new("Frame", { Name = `Invite{i}`, LayoutOrder = i, Size = UDim2.new(1, 0, 0, 92), BackgroundColor3 = Ui.WHITE, Parent = list }, {
				Ui.corner(12),
				Ui.stroke(2, Color3.fromHex("#e0e0e0")),
			})
			if inv.model then
				local ok, pic = pcall(function()
					return Thumb.new("Cars", inv.model, UDim2.fromOffset(96, 66), if inv.color then Color3.fromHex(inv.color) else nil)
				end)
				if ok and pic then
					pic.Position = UDim2.fromOffset(6, 13)
					pic.Parent = row
				end
			end
			local name = tostring(inv.name or "A driver")
			Ui.text({ Text = name, TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(110, 8), Size = UDim2.new(1, -250, 0, 24), Parent = row })
			Ui.text({ Text = `{inv.carName or "Car"} · PI {inv.pi or 0}`, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(110, 33), Size = UDim2.new(1, -250, 0, 18), Parent = row })
			local prize = `🏆 {money(Invites.prize(inv.pi or 0))}`
			local clock = Ui.text({ Name = "Left", Text = `⏳ {inv.left}s · {prize}`, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Color3.fromHex("#e65100"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(110, 56), Size = UDim2.new(1, -250, 0, 18), Parent = row })
			clocks[inv.id] = { label = clock, prize = prize }
			local acts = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(130, 84), BackgroundTransparency = 1, Parent = row }, {
				Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			Ui.buy({ Name = "Race", LayoutOrder = 1, Size = UDim2.fromOffset(130, 40), Parent = acts }, "🏁 Race!", "green", function()
				LiveDuels.answer(inv.id, true)
			end, 17)
			Ui.buy({ Name = "No", LayoutOrder = 2, Size = UDim2.fromOffset(130, 36), Parent = acts }, "Not now", "garage", function()
				LiveDuels.answer(inv.id, false)
			end, 15)
		end
	end
	draw()
	local conn = LiveDuels.changed:Connect(function()
		if overlay.Parent then
			draw()
		end
	end)
	-- The countdowns tick; a challenge that runs out goes.
	task.spawn(function()
		while overlay.Parent do
			task.wait(1)
			if not overlay.Parent then
				break
			end
			local waiting = LiveDuels.waiting()
			local shown = 0
			for _ in clocks do
				shown += 1
			end
			if #waiting ~= shown then
				draw()
			else
				for _, inv in waiting do
					local c = clocks[inv.id]
					if c then
						Ui.setText(c.label, `⏳ {inv.left}s · {c.prize}`)
					end
				end
			end
		end
		conn:Disconnect()
	end)
	return overlay
end

return Invites
