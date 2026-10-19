--!strict
-- The Social menu's Meet tab, as the web game's MeetPanel (ui/Meet.tsx): your display of up to
-- three cars (pick them here or with "Show off" in the garage), then other drivers' displays with
-- a like each (one a town, 40 a day) and Visit for drivers in this server (server/Meet).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local meetRules = require(Game.meet) :: any
local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)
local Card = require(script.Parent.Card)

local Meet = {}

local CAR = 74 -- a car picture's size
local ROW_H = 92

local thumb = Card.thumb

-- Draws the tab into list. kit: the Friends panel's note, visit(userId), card(userId, name, town)
-- and toast.
function Meet.draw(list: Instance, kit: any, state: any)
	local function redraw()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		Meet.draw(list, kit, state)
	end
	local s = store.useGame.getState()
	local shown = meetRules.showcaseOf(s.cars or {}, s.showcase)

	-- Your display.
	local mine = Ui.new("Frame", { Name = "Mine", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 40 + CAR + 22), BackgroundColor3 = Ui.WHITE, Parent = list }, {
		Ui.corner(12),
		Ui.stroke(2, Color3.fromHex("#e0e0e0")),
	})
	Ui.text({ Text = "Your display", TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(200, 24), Parent = mine })
	local likesLabel = Ui.text({ Name = "Likes", Text = "", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(140, 9), Size = UDim2.fromOffset(120, 22), Parent = mine })
	Ui.buy({ Name = "Pick", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 6), Size = UDim2.fromOffset(96, 30), Parent = mine }, if state.picking then "Done" else "✏️ Pick", "garage", function()
		state.picking = not state.picking
		redraw()
	end, 14)
	local lot = Ui.new("Frame", { Name = "Lot", Position = UDim2.fromOffset(12, 40), Size = UDim2.new(1, -24, 0, CAR + 20), BackgroundTransparency = 1, Parent = mine }, {
		Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i = 1, meetRules.SHOWCASE_MAX do
		local c = shown[i]
		local spot = Ui.new("Frame", { Name = `Spot{i}`, LayoutOrder = i, Size = UDim2.fromOffset(CAR + 30, CAR + 20), BackgroundTransparency = 1, Parent = lot })
		if c then
			thumb(c, CAR, spot).Position = UDim2.fromOffset(15, 0)
			Ui.text({ Text = data.carDef(c.model).name, Body = true, TextSize = 12, TextColor3 = Ui.MUTED, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(0, CAR + 2), Size = UDim2.new(1, 0, 0, 16), Parent = spot })
		else
			Ui.buy({ Position = UDim2.fromOffset(15, 0), Size = UDim2.fromOffset(CAR, CAR), Parent = spot }, "＋", "garage", function()
				state.picking = true
				redraw()
			end, 24)
		end
	end
	local order = 2
	if state.picking then
		local picks = s.showcase or {}
		kit.note(list, order, `Pick up to {meetRules.SHOWCASE_MAX}. {if #picks > 0 then "" else "Showing your best cars for now."}`)
		order += 1
		local cars = table.clone(s.cars or {})
		local function pi(c: any): number
			return data.performance(data.carDef(c.model), c.upgrades, c.mods)
		end
		table.sort(cars, function(a, b)
			return pi(a) > pi(b)
		end)
		local chips = Ui.new("Frame", { Name = "Chips", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Parent = list }, {
			Ui.new("UIGridLayout", { CellSize = UDim2.fromOffset(64, 76), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		order += 1
		for i, c in cars do
			local on = table.find(picks, c.uid) ~= nil
			local chip = Ui.new("TextButton", { Name = c.uid, Text = "", AutoButtonColor = true, LayoutOrder = i, BackgroundColor3 = if on then Color3.fromHex("#fff3c4") else Ui.WHITE, Parent = chips }, {
				Ui.corner(10),
				Ui.stroke(2, if on then Color3.fromHex("#f5b400") else Color3.fromHex("#e0e0e0")),
			})
			thumb(c, 56, chip).Position = UDim2.fromOffset(4, 2)
			Ui.text({ Text = if on then "⭐" else "☆", TextSize = 15, Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 0, 18), Parent = chip })
			chip.Activated:Connect(function()
				Remote.act("toggleShowcase", c.uid)
				redraw()
			end)
		end
	end

	local loading = Ui.text({ Name = "Loading", Text = "Loading the car meet…", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 40), Parent = list })
	order += 1
	task.spawn(function()
		local ok, res = Remote.social("meet", nil, true)
		if not loading.Parent then
			return
		end
		loading:Destroy()
		if not ok then
			kit.note(list, order, "Couldn't reach the car meet right now. Try again in a moment.")
			return
		end
		local me = Players.LocalPlayer
		local likes = res.likes or {}
		local own = likes[tostring(me.UserId)]
		likesLabel.Text = `❤️ {if own then own.likes else 0}`
		if #res.displays == 0 then
			kit.note(list, order, "No other displays yet. Put your best cars on show!")
		end
		for _, d in res.displays do
			order += 1
			local row = Ui.new("Frame", { Name = `Display{d.id}`, LayoutOrder = order, Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = Ui.WHITE, Parent = list }, {
				Ui.corner(12),
				Ui.stroke(2, Color3.fromHex("#e0e0e0")),
			})
			Ui.text({ Text = tostring(d.name or "Driver"), TextSize = 16, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(12, 14), Size = UDim2.fromOffset(150, 22), Parent = row })
			Ui.text({ Text = `{d.town or ""} · ⭐ {d.level or 1}`, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(12, 38), Size = UDim2.fromOffset(150, 18), Parent = row })
			if d.here then
				Ui.text({ Text = "🟢 in this server", Body = true, TextSize = 12, TextColor3 = Color3.fromHex("#2e7d32"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(12, 58), Size = UDim2.fromOffset(150, 16), Parent = row })
			end
			-- Tapping the driver or their cars opens their card.
			Ui.new("TextButton", { Name = "Open", Text = "", BackgroundTransparency = 1, ZIndex = 0, Size = UDim2.new(1, -200, 1, 0), Parent = row }).Activated:Connect(function()
				kit.card(d.id, tostring(d.name or "Driver"), d.town)
			end)
			local cars = Ui.new("Frame", { Name = "Cars", Position = UDim2.fromOffset(168, (ROW_H - CAR) / 2), Size = UDim2.new(1, -168 - 200, 0, CAR), BackgroundTransparency = 1, ClipsDescendants = true, Parent = row }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			for i, c in d.cars or {} do
				thumb(c, CAR, cars, i)
			end
			local acts = Ui.new("Frame", { Name = "Acts", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(186, 36), BackgroundTransparency = 1, Parent = row }, {
				Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			Card.like(acts, d.id, likes[tostring(d.id)] or { likes = 0, liked = false }, { LayoutOrder = 1, Size = UDim2.fromOffset(78, 34) })
			if d.here then
				Ui.buy({ Name = "Visit", LayoutOrder = 2, Size = UDim2.fromOffset(96, 34), Parent = acts }, "🏠 Visit", "garage", function()
					kit.visit(d.id)
				end, 15)
			end
		end
	end)
end

return Meet
