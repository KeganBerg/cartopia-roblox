--!strict
-- The photosensitivity warning, as the web game's FlashWarning (ui/FlashWarning.tsx, flash.css):
-- on every visit until the player ticks "Don't show me this again", and again from Menu > Help >
-- Photosensitivity warning. A card over a dark backdrop with a bolt on a yellow strip, the warning,
-- the Reduce flashing switch (client/Prefs) and Got it. Nothing underneath can be tapped while
-- it's up. At launch it goes first in the pop-up queue, so the daily spin waits behind it.

local Client = script.Parent.Parent
local Ui = require(Client.Ui)
local Prefs = require(Client.Prefs)
local Kit = require(script.Parent.Kit)

local FlashWarning = {}

local LINE = Ui.LINE
local W = 380

-- The web's .calm-switch: grey, or green with the knob right when flashing is reduced.
local function calmSwitch(parent: Instance, z: number): TextButton
	local sw = Ui.new("TextButton", { Name = "Calm", Text = "", AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(48, 28), BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = parent }, {
		Ui.round(),
		Ui.stroke(2.5, LINE),
	})
	local grad = Ui.gradient("#b0bec5", "#b0bec5")
	grad.Parent = sw
	local knob = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(19, 19), BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = sw }, { Ui.round(), Ui.stroke(2, LINE) })
	local function paint()
		local on = Prefs.calmFlash()
		knob.Position = UDim2.new(0, if on then 23 else 3, 0.5, 0)
		grad.Color = if on then Ui.seq("#7ee05a", "#2fa52f") else Ui.seq("#b0bec5", "#b0bec5")
	end
	paint()
	sw.Activated:Connect(function()
		Prefs.set({ calmFlash = not Prefs.calmFlash() })
		paint()
	end)
	return sw
end

-- Opens the warning over gui; done runs when Got it closes it.
function FlashWarning.show(gui: Instance, done: (() -> ())?): Instance
	local z = 80
	local hide = Prefs.get().flashHide
	local modal = Ui.new("TextButton", { Name = "FlashWarning", Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex("#080c1e"), BackgroundTransparency = 0.28, BorderSizePixel = 0, ZIndex = z, Parent = gui })
	modal.Selectable = false
	local text = "Cartopia has flashing lights, like Rave Mode and the nightclub. They may trigger seizures for people with photosensitive epilepsy."
	local textH = 4 * 20
	local h = 53 + 12 + textH + 10 + 48 + 10 + 34 + 10 + 46 + 14
	local drop = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 3), Size = UDim2.fromOffset(W, h), BackgroundColor3 = LINE, ZIndex = z, Parent = modal }, { Ui.corner(18) })
	local card = Ui.new("TextButton", { Name = "Card", Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(0, -6), Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.SHEET, ClipsDescendants = true, ZIndex = z, Parent = drop }, {
		Ui.corner(18),
		Ui.stroke(3, LINE),
	})
	-- The yellow strip: the bolt in a navy disc and the title.
	local head = Ui.new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = z, Parent = card }, { Ui.gradient("#ffd43b", "#ff9f1a") })
	Ui.new("Frame", { Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 3), BackgroundColor3 = LINE, BorderSizePixel = 0, ZIndex = z, Parent = head })
	local bolt = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = LINE, ZIndex = z, Parent = head }, { Ui.round() })
	Ui.text({ Text = "⚡", TextSize = 20, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = bolt })
	Ui.text({ Name = "Title", Text = "Flashing lights", TextSize = 24, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(56, 0), Size = UDim2.new(1, -66, 1, 0), Stroke = 1.5, Shadow = 3, ZIndex = z, Parent = head })
	local y = 53 + 12
	Ui.text({ Name = "Warning", Text = text, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = LINE, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, textH), ZIndex = z, Parent = card })
	y += textH + 10
	-- Reduce flashing, in a white row.
	local row = Ui.new("Frame", { Name = "Reduce", Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 48), BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = card }, {
		Ui.corner(12),
		Ui.stroke(2, Color3.fromHex("#e0e0e0")),
	})
	Ui.text({ Text = "Reduce flashing", Body = true, Weight = "heavy", TextSize = 16, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -70, 1, 0), ZIndex = z, Parent = row })
	calmSwitch(row, z)
	y += 48 + 10
	-- "Don't show me this again": a big tick box.
	local tickRow = Ui.new("TextButton", { Name = "DontShow", Text = "", AutoButtonColor = false, Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 34), BackgroundTransparency = 1, ZIndex = z, Parent = card })
	local tick = Ui.new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 2, 0.5, 0), Size = UDim2.fromOffset(26, 26), BackgroundColor3 = Ui.WHITE, ZIndex = z, Parent = tickRow }, { Ui.corner(8), Ui.stroke(2.5, LINE) })
	local tickGrad = Ui.gradient("#7ee05a", "#2fa52f")
	local mark = Ui.text({ Text = "✓", TextSize = 20, Size = UDim2.fromScale(1, 1), ZIndex = z, Parent = tick })
	local function paintTick()
		mark.Visible = hide
		tickGrad.Parent = if hide then tick else nil
	end
	paintTick()
	Ui.text({ Text = "Don't show me this again", Body = true, Weight = "heavy", TextSize = 16, TextColor3 = LINE, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(38, 0), Size = UDim2.new(1, -38, 1, 0), ZIndex = z, Parent = tickRow })
	tickRow.Activated:Connect(function()
		hide = not hide
		paintTick()
	end)
	y += 34 + 10
	local closed = false
	local function close()
		if closed then
			return
		end
		closed = true
		if hide ~= Prefs.get().flashHide then
			Prefs.set({ flashHide = hide })
		end
		modal:Destroy()
		if done then
			done()
		end
	end
	local _, ok = Ui.buy({ Name = "GotIt", Position = UDim2.fromOffset(14, y), Size = UDim2.new(1, -28, 0, 46), ZIndex = z, Parent = card }, "Got it", "green", close, 18)
	ok.Name = "GotIt"
	for _, d in modal:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex = z
		end
	end
	return modal
end

-- At launch: once the saved settings are in, unless the player hid it.
function FlashWarning.start(ctx: any)
	local waited = 0
	while not Prefs.loaded and waited < 20 do
		task.wait(0.25)
		waited += 0.25
	end
	if not Prefs.loaded or Prefs.get().flashHide then
		return
	end
	-- (Not over a menu opened in the first moments: it waits for the town.)
	Kit.push(ctx, "flashWarning", 0, function(done)
		FlashWarning.show(ctx.gui, done)
	end, function()
		return not Kit.menuOpen(ctx)
	end)
end

return FlashWarning
