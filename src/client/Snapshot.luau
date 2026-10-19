--!strict
-- The snapshot button on a won race, as the web game's SnapshotButton (ui/Snapshot.tsx). On the
-- web it makes a picture of the race as it stands with a winner's strip along the bottom (the
-- caption in gold, the game's name in white) and shares or saves it.
--
-- Roblox games can't make or save image files themselves, so here the 📸 button turns the screen
-- into that same postcard: the result card steps aside to show the race behind it, and the navy
-- winner's strip goes along the bottom. Then Roblox's own screenshot (CaptureService) takes the
-- picture and offers to save it to the player's Captures, where Roblox lets them share it. Where
-- that isn't available (an older client, Studio), the postcard stays up with a hint to take a
-- screenshot themselves (the hint fades so it stays out of the picture), and a tap brings the result card back.
--
--   Snapshot.button(card, hide, screen, caption, toast)
--     card: where the round 📸 button goes (its top-right corner); hide: what steps aside for the
--     picture (the result overlay); screen: what the strip is drawn over; caption: "🏆 Beat Rosa"; toast: how to say "📸 Saved" (nil: a note over the screen).

local Ui = require(script.Parent.Ui)

local Snapshot = {}

local NAVY = Color3.fromHex("#1b2440")
local GOLD = Color3.fromHex("#ffd54f")
local STRIP = 0.11 -- of the picture's height, as the web's postcard (88 of the race screen's 800)
-- How long to wait for Roblox's screenshot before falling back to the hint.
local CAPTURE_WAIT = 3

-- Roblox's capture service, when this client has it.
local function captureService(): any?
	local ok, svc = pcall(function()
		return game:GetService("CaptureService" :: any)
	end)
	return if ok then svc else nil
end

-- Takes the screenshot: done(contentId) once it's taken, or done(nil) if it can't be.
function Snapshot.capture(done: (string?) -> ())
	local called = false
	local function once(id: string?)
		if not called then
			called = true
			done(id)
		end
	end
	local svc = captureService()
	if not svc then
		once(nil)
		return
	end
	local ok = pcall(function()
		svc:CaptureScreenshot(function(id: any)
			once(if id ~= nil then tostring(id) else nil)
		end)
	end)
	if not ok then
		once(nil)
		return
	end
	task.delay(CAPTURE_WAIT, function()
		once(nil)
	end)
end

-- Offers to keep the picture in the player's Captures. done(saved) after they answer;
-- false straight away when Roblox can't ask.
function Snapshot.save(id: string, done: (boolean) -> ())
	local svc = captureService()
	local ok = svc ~= nil and pcall(function()
		svc:PromptSaveCapturesToGallery({ id }, function(results: any)
			local saved = false
			if type(results) == "table" then
				for _, v in results do
					if v == true then
						saved = true
					end
				end
			end
			done(saved)
		end)
	end)
	if not ok then
		done(false)
	end
end

-- The winner's strip along the bottom of the screen: the caption on the left, the game's name on
-- the right.
function Snapshot.strip(screen: Instance, caption: string): Frame
	local strip = Ui.new("Frame", { Name = "Postcard", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, STRIP), BackgroundColor3 = NAVY, BorderSizePixel = 0, ZIndex = 60, Parent = screen })
	Ui.text({ Name = "Caption", Text = caption, TextSize = 36, TextTruncate = Enum.TextTruncate.AtEnd, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.04, 0, 0.5, 0), Size = UDim2.fromScale(0.62, 0.46), ZIndex = 61, Parent = strip })
	Ui.text({ Name = "Name", Text = "Cartopia", Body = true, Weight = "heavy", TextSize = 28, TextColor3 = Ui.WHITE, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0.96, 0, 0.5, 0), Size = UDim2.fromScale(0.3, 0.34), ZIndex = 61, Parent = strip })
	return strip
end

function Snapshot.button(card: Instance, hide: GuiObject, screen: Instance, caption: string, toast: ((string) -> ())?): TextButton
	-- .snap-btn: a blue disc with a white rim in the card's top-right corner.
	local b = Ui.new("TextButton", { Name = "Snapshot", Text = "📸", TextSize = 20, AutoButtonColor = false, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(44, 44), BackgroundColor3 = Color3.fromHex("#1e88e5"), ZIndex = 50, Parent = card }, {
		Ui.round(),
		Ui.stroke(3, Ui.WHITE),
	})
	local busy = false
	-- The race screen hides the HUD's toasts, so the "Saved" note shows over the screen itself.
	local function say(text: string)
		if toast then
			toast(text)
			return
		end
		local note = Ui.new("Frame", { Name = "SnapNote", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = NAVY, BackgroundTransparency = 0.15, ZIndex = 62, Parent = screen }, {
			Ui.round(),
			Ui.stroke(2, Ui.WHITE),
			Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
		})
		Ui.text({ Text = text, Body = true, Weight = "heavy", TextSize = 15, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 63, Parent = note })
		task.delay(2, function()
			note:Destroy()
		end)
	end
	b.Activated:Connect(function()
		if busy then
			return
		end
		busy = true
		b.TextTransparency = 0.4
		hide.Visible = false
		local strip = Snapshot.strip(screen, caption)
		local back: GuiButton? = nil
		local function restore()
			if strip.Parent then
				strip:Destroy()
			end
			if back then
				back:Destroy()
			end
			hide.Visible = true
			b.TextTransparency = 0
			busy = false
		end
		-- A frame for the postcard to be drawn before the picture is taken.
		task.delay(0, Snapshot.capture, function(id: string?)
			if id then
				restore()
				Snapshot.save(id, function(saved: boolean)
					if saved then
						say("📸 Saved")
					end
				end)
				return
			end
			-- No screenshot from here: the postcard stays up for the player's own screenshot.
			local tap = Ui.new("TextButton", { Name = "PostcardBack", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 62, Parent = screen })
			local hint = Ui.new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = NAVY, BackgroundTransparency = 0.15, ZIndex = 62, Parent = tap }, {
				Ui.round(),
				Ui.stroke(2, Ui.WHITE),
				Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }),
			})
			Ui.text({ Name = "Hint", Text = "📸 Take a screenshot now · tap to go back", Body = true, Weight = "heavy", TextSize = 15, Size = UDim2.fromScale(0, 1), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 63, Parent = hint })
			back = tap
			-- The hint goes after a moment, so it isn't in their picture.
			task.delay(2.5, function()
				if hint.Parent then
					hint.Visible = false
				end
			end)
			tap.Activated:Connect(restore)
		end)
	end)
	return b
end

return Snapshot
