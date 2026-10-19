--!strict
-- "Are you sure?" before a step that can't be undone, as the web game's Confirm (ui/Confirm.tsx,
-- confirm.css): a card over a dark backdrop with an icon and title on a red strip, what's at stake
-- below, a "Don't ask again" tick box and Cancel / the step's own button.
--
-- On the web the "Don't ask again" choices are device settings (lib/prefs.ts askLeave, askSell),
-- never part of the save; here they're kept with the account (client/Prefs, server/Prefs).

local Ui = require(script.Parent.Ui)

local Confirm = {}

local LINE = Ui.LINE
local W = 360

-- Which questions are still asked (the web's prefs askLeave and askSell). client/Prefs keeps them
-- with the account: it fills these in, and hears "Don't ask again" through onStop.
Confirm.prefs = { askLeave = true, askSell = true } :: { [string]: boolean }
Confirm.onStop = nil :: ((string) -> ())?

export type Opts = {
	pref: string,
	icon: string,
	title: string,
	ok: string,
	-- Draws what's at stake into the white box (bodyHeight tall); none: no box.
	body: ((Frame) -> ())?,
	bodyHeight: number?,
	onOk: () -> (),
	onCancel: (() -> ())?,
	z: number?,
}

-- Runs onOk at once when the player turned the question off; otherwise opens the card over
-- `parent` and returns it.
function Confirm.ask(parent: Instance, o: Opts): Instance?
	if Confirm.prefs[o.pref] == false then
		o.onOk()
		return nil
	end
	local z = o.z or 40
	local stop = false
	local modal: TextButton
	local function close()
		modal:Destroy()
		if o.onCancel then
			o.onCancel()
		end
	end
	-- The backdrop takes every tap, so nothing underneath can be pressed; a tap on it cancels.
	modal = Ui.new("TextButton", { Name = "Confirm", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#080c1e"), BackgroundTransparency = 0.28, BorderSizePixel = 0, ZIndex = z, Parent = parent })
	modal.Activated:Connect(close)
	local bodyH = if o.body then (o.bodyHeight or 56) + 12 else 0
	local h = 53 + bodyH + 44 + 72
	-- The card, with the web's solid 6px drop under it.
	local drop = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 3), Size = UDim2.fromOffset(W, h), BackgroundColor3 = LINE, ZIndex = z, Parent = modal }, {
		Ui.new("UISizeConstraint", { MaxSize = Vector2.new(W, h) }),
		Ui.corner(18),
	})
	local card = Ui.new("TextButton", { Name = "Card", Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, -6), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.SHEET, ClipsDescendants = true, ZIndex = z, Parent = drop }, {
		Ui.corner(18),
		Ui.stroke(3, LINE),
	})
	card:SetAttribute("SinkTaps", true)

	-- The red strip: the icon in a navy disc and the title.
	local head = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = z, Parent = card }, {
		Ui.gradient("#ff8a65", "#e53935"),
	})
	Ui.new("Frame", { Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = LINE, BorderSizePixel = 0, ZIndex = z, Parent = head })
	local bolt = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = LINE, ZIndex = z, Parent = head }, { Ui.round() })
	Ui.text({ Text = o.icon, TextSize = 20, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = bolt })
	Ui.text({ Name = "Title", Text = o.title, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -66, 1, 0), Stroke = 1.5, Shadow = 3, ZIndex = z, Parent = head })

	local y = 53
	if o.body then
		local box = Ui.new("Frame", { Name = "Body", Position = UDim2.fromOffset(14, y + 12), Size = UDim2.new(1, -28, 0, o.bodyHeight or 56), BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = card }, {
			Ui.corner(12),
			Ui.stroke(2, Color3.fromHex("#e0e0e0")),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10) }),
		})
		o.body(box)
		y += bodyH
	end

	-- "Don't ask again": a big tick box, easy to hit on a phone.
	local row = Ui.new("TextButton", { Name = "DontAsk", Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(14, y + 10), Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1, ZIndex = z, Parent = card })
	local tick = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = row }, {
		Ui.corner(8),
		Ui.stroke(2.5, LINE),
	})
	local tickGrad = Ui.gradient("#7ee05a", "#2fa52f")
	local mark = Ui.text({ Text = "✓", TextSize = 20, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = z, Parent = tick })
	Ui.text({ Text = "Don't ask again", Body = true, Weight = "heavy", TextSize = 16, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -38, 1, 0), ZIndex = z, Parent = row })
	row.Activated:Connect(function()
		stop = not stop
		mark.Visible = stop
		tickGrad.Parent = if stop then tick else nil
	end)
	y += 44

	-- Cancel, and the step itself in red.
	local acts = Ui.new("Frame", { Position = UDim2.fromOffset(14, y + 12), Size = UDim2.new(1, -28, 0, 46), BackgroundTransparency = 1, ZIndex = z, Parent = card }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalFlex = Enum.UIFlexAlignment.Fill, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	local _, no = Ui.button({ LayoutOrder = 1, Size = UDim2.new(0.5, -5, 1, 0), ZIndex = z, Parent = acts }, "white", close, {
		radius = 12,
		stroke = 2.5,
		drop = 3,
		dark = 0.2,
		flat = true,
		text = "Cancel",
		textSize = 18,
		textColor = LINE,
	})
	no.Name = "Cancel"
	local yesShadow, yes = Ui.button({ LayoutOrder = 2, Size = UDim2.new(0.5, -5, 1, 0), ZIndex = z, Parent = acts }, "white", function()
		if stop then
			Confirm.prefs[o.pref] = false
			if Confirm.onStop then
				Confirm.onStop(o.pref)
			end
		end
		modal:Destroy()
		o.onOk()
	end, {
		radius = 12,
		stroke = 2.5,
		drop = 3,
		dark = 0.25,
		strokeColor = Ui.WHITE,
		flat = true,
		text = o.ok,
		textSize = 18,
		textShadow = 1.5,
		textStrokeColor = Color3.fromHex("#7f0000"),
	})
	yes.Name = "Ok"
	local g = yes:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = Ui.seq("#ef5350", "#c62828")
	end
	local _ = yesShadow
	return modal
end

return Confirm
