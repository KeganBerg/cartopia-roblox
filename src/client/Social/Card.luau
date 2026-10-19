--!strict
-- A player's card, as the web game's PlayerCardPopup (ui/PlayerCard.tsx): their level, best PI,
-- races won and trophies, a big look at one of their cars with its PI, a strip of all their cars
-- (the ones on show starred), a like for their Car Meet display, and Visit and ⚔️ Race when
-- they're in this server. Opens over the Social menu from a driver's name or car in Leaderboards,
-- Meet and Drivers to visit (server/Meet keeps the cards of players in other servers).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local data = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"):WaitForChild("data")) :: any
local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)
local Thumb = require(script.Parent.Parent.Thumb)
local LiveDuels = require(script.Parent.Parent.LiveDuels)
local CrewTab = require(script.Parent.Crew)

local Card = {}

local VIEW = 210 -- the big car picture
local CHIP = 56

-- A car's picture, as the garage draws it.
function Card.thumb(car: any, size: number, parent: Instance, order: number?): GuiObject
	local ok, vp = pcall(function()
		return Thumb.car(car.model, UDim2.fromOffset(size, size), { color = car.color, finish = car.finish, stripe = car.stripe }, car.hat, car.mods, car.panels, car.trim, car.skin, car.modSkin)
	end)
	local box = Ui.new("Frame", { Name = "Car", LayoutOrder = order or 0, Size = UDim2.fromOffset(size, size), BackgroundColor3 = Color3.fromHex("#eef3fb"), Parent = parent }, { Ui.corner(10) })
	if ok and vp then
		vp.Size = UDim2.fromScale(1, 1)
		vp.Parent = box
	end
	return box
end

-- A like button: "🤍 n", or "❤️ n" once liked (one a town, 40 a day).
function Card.like(parent: Instance, owner: number, l: { likes: number, liked: boolean }, props: { [string]: any }): Frame
	local label: TextLabel
	props.Name = "Like"
	props.Parent = parent
	local frame, face = Ui.buy(props, `{if l.liked then "❤️" else "🤍"} {l.likes}`, if l.liked then "garage" else "green", function()
		if l.liked then
			return
		end
		local ok, r = Remote.social("like", owner)
		if ok then
			l.liked, l.likes = true, r.likes
			Ui.setText(label, `❤️ {l.likes}`)
		end
	end, 15)
	label = face:FindFirstChildWhichIsA("TextLabel", true) :: TextLabel
	return frame
end

local function stat(parent: Instance, order: number, icon: string, n: number, tip: string)
	local box = Ui.new("Frame", { Name = tip, LayoutOrder = order, Size = UDim2.new(0.25, -6, 1, 0), BackgroundColor3 = Ui.WHITE, Parent = parent }, {
		Ui.corner(12),
		Ui.stroke(2, Color3.fromHex("#e0e0e0")),
	})
	Ui.text({ Text = `{icon} {n}`, TextSize = 20, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 26), Parent = box })
	Ui.text({ Text = tip, Body = true, TextSize = 12, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 16), Parent = box })
end

-- Opens the card of userId over parent. who: the name and town to show while it loads, and the car
-- to open on. kit: visit(userId), and ctx (the HUD's) for a live race challenge.
function Card.open(parent: Instance, userId: number, who: { name: string, town: string?, car: string? }, kit: any): Instance
	local overlay: Instance
	local function close()
		overlay:Destroy()
	end
	local o, _sheet, body = Ui.panel(parent, who.name, { width = 520, height = 640, onClose = close })
	overlay = o
	o.Name = "PlayerCard"
	local list = Ui.scroller({ Name = "List", Size = UDim2.fromScale(1, 1), Parent = body })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Center, Parent = list })
	local loading = Ui.text({ Name = "Loading", Text = "Loading their garage…", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, Size = UDim2.new(1, 0, 0, 40), Parent = list })

	task.spawn(function()
		local ok, card = Remote.social("card", userId, true)
		if not overlay.Parent then
			return
		end
		loading:Destroy()
		if not ok then
			Ui.text({ Name = "Note", Text = "Couldn't load their garage right now.", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, Size = UDim2.new(1, 0, 0, 40), Parent = list })
			return
		end
		local townRow = Ui.new("Frame", { Name = "TownRow", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = list }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		local townText = `🏘️ {card.town or who.town or ""}`
		Ui.text({ Name = "Town", LayoutOrder = 1, Text = townText, Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.INK, Size = UDim2.fromOffset(math.ceil(Ui.textWidth(townText, 16)) + 6, 22), Parent = townRow })
		-- Their crew's badge (client/Social/Crew).
		if card.crew then
			CrewTab.tag(townRow, card.crew, { LayoutOrder = 2 })
		end
		local stats = Ui.new("Frame", { Name = "Stats", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, Parent = list }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		stat(stats, 1, "⭐", card.level or 1, "Level")
		stat(stats, 2, "⚡", card.bestPi or 0, "Best PI")
		stat(stats, 3, "🏁", card.raceWins or 0, "Races won")
		stat(stats, 4, "🏆", card.trophies or 0, "Trophies")

		local cars = card.cars or {}
		if #cars == 0 then
			Ui.text({ Name = "Empty", LayoutOrder = 3, Text = "🚗 No cars yet", Body = true, TextSize = 16, TextColor3 = Ui.MUTED, Size = UDim2.new(1, 0, 0, 60), Parent = list })
		else
			local view = Ui.new("Frame", { Name = "View", LayoutOrder = 3, Size = UDim2.new(1, 0, 0, VIEW + 34), BackgroundColor3 = Ui.WHITE, Parent = list }, {
				Ui.corner(14),
				Ui.stroke(2, Color3.fromHex("#e0e0e0")),
			})
			local strip = Ui.new("ScrollingFrame", { Name = "Strip", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, CHIP + 32), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 5, ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), Parent = list }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			local chips: { [string]: GuiObject } = {}
			local function pick(c: any)
				for _, k in view:GetChildren() do
					if k:IsA("GuiObject") then
						k:Destroy()
					end
				end
				local pic = Card.thumb(c, VIEW, view)
				pic.AnchorPoint = Vector2.new(0.5, 0)
				pic.Position = UDim2.new(0.5, 0, 0, 4)
				pic.BackgroundTransparency = 1
				Ui.text({ Name = "CarName", Text = data.carDef(c.model).name, TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, VIEW + 6), Size = UDim2.new(1, -110, 0, 24), Parent = view })
				Ui.text({ Name = "Pi", Text = `PI {c.pi or 0}`, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Color3.fromHex("#1565c0"), TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, VIEW + 8), Size = UDim2.fromOffset(90, 22), Parent = view })
				for uid, chip in chips do
					local stroke = chip:FindFirstChildOfClass("UIStroke")
					if stroke then
						stroke.Color = if uid == c.uid then Color3.fromHex("#f5b400") else Color3.fromHex("#e0e0e0")
					end
				end
			end
			local first = cars[1]
			for i, c in cars do
				local on = table.find(card.showcase or {}, c.uid) ~= nil
				local chip = Ui.new("TextButton", { Name = c.uid, Text = "", AutoButtonColor = true, LayoutOrder = i, Size = UDim2.fromOffset(CHIP + 8, CHIP + 24), BackgroundColor3 = Ui.WHITE, Parent = strip }, {
					Ui.corner(10),
					Ui.stroke(2, Color3.fromHex("#e0e0e0")),
				})
				Card.thumb(c, CHIP, chip).Position = UDim2.fromOffset(4, 2)
				Ui.text({ Text = `{if on then "⭐" else ""}{c.pi or 0}`, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, CHIP + 3), Size = UDim2.new(1, 0, 0, 18), Parent = chip })
				chips[c.uid] = chip
				chip.Activated:Connect(function()
					pick(c)
				end)
				if c.uid == who.car then
					first = c
				end
			end
			pick(first)
		end

		local acts = Ui.new("Frame", { Name = "Acts", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, Parent = list }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		if not card.mine then
			Card.like(acts, userId, card.likes or { likes = 0, liked = false }, { LayoutOrder = 1, Size = UDim2.fromOffset(96, 38) })
		end
		if card.here then
			Ui.buy({ Name = "Visit", LayoutOrder = 2, Size = UDim2.fromOffset(120, 38), Parent = acts }, "🏘️ Visit", "garage", function()
				close()
				kit.visit(userId)
			end, 16)
			-- A live drag race (client/LiveDuels): it waits in their 🏁 bell.
			if not card.mine and kit.ctx then
				Ui.buy({ Name = "Challenge", LayoutOrder = 3, Size = UDim2.fromOffset(120, 38), Parent = acts }, "⚔️ Race", "green", function()
					task.spawn(LiveDuels.challenge, kit.ctx, userId, who.name)
				end, 16)
			end
		end
	end)
	return overlay
end

return Card
