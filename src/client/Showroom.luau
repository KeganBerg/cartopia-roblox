--!strict
-- The Showroom, as the web game's For Sale dealership (ui/Menus.tsx SaleSection): the car picked
-- turns on a turntable, the cars for sale are listed on the left, and its colours and Buy button
-- are on the right. Cars unlock with Rusty's Rescue and by level, as on the web.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local data = require(Game.data) :: any
local Ui = require(script.Parent.Ui)
local Thumb = require(script.Parent.Thumb)
local Remote = require(script.Parent.Remote)

local Showroom = {}

local NO_UPGRADES = { engine = 0, turbo = 0, tires = 0, weight = 0 }
local lastSale: string? = nil

function Showroom.open(gui: ScreenGui, close: () -> (), toast: (string) -> ())
	local frame, body = Ui.sheet(gui, "Showroom", "showroom", UDim2.new(0.9, 0, 0.82, 0), close)
	local forSale = {}
	for _, c in data.CARS do
		if not c.rescueOnly and not c.season and not c.secret and not c.pack then
			table.insert(forSale, c)
		end
	end

	local list = Ui.new("ScrollingFrame", {
		Size = UDim2.new(0.34, 0, 1, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 8,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { Ui.new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local stage = Ui.new("Frame", {
		Position = UDim2.new(0.35, 0, 0, 0),
		Size = UDim2.new(0.65, 0, 1, 0),
		BackgroundColor3 = Color3.fromHex("#263238"),
		Parent = body,
	}, { Ui.corner(14), Ui.stroke(2.5) })
	local title = Ui.label({ TextSize = 26, Size = UDim2.new(1, -20, 0, 36), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, Parent = stage })
	local stats = Ui.label({ TextSize = 16, Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(12, 44), TextXAlignment = Enum.TextXAlignment.Left, Parent = stage })
	local colors = Ui.new("Frame", {
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.new(0, 12, 1, -112),
		BackgroundTransparency = 1,
		Parent = stage,
	}, { Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 10) }) })
	local buy: TextButton
	local view: ViewportFrame? = nil
	local spin: RBXScriptConnection? = nil

	local function select(c: any, color: string)
		lastSale = c.id
		local s = store.useGame.getState()
		local gate = store.gateLevel(s)
		local rusty = store.hasRusty(s)
		local locked = gate < c.unlockLevel
		local afford = s.coins >= c.price and s.bucks >= (c.bucks or 0)
		title.Text = c.name
		stats.Text = `PI {data.performance(c, NO_UPGRADES)} · Power {c.power} · Grip {c.grip} · Weight {c.weight}`
		if view then
			view:Destroy()
		end
		if spin then
			spin:Disconnect()
		end
		local v = Thumb.new("Cars", c.id, UDim2.new(1, -20, 1, -190), Color3.fromHex(color))
		v.Position = UDim2.fromOffset(10, 70)
		v.Parent = stage
		view = v
		local model = v:FindFirstChildOfClass("Model")
		local cam = v:FindFirstChildOfClass("Camera")
		if model and cam then
			local cf = model:GetBoundingBox()
			local a = 0
			local dist = (cam.CFrame.Position - cf.Position).Magnitude
			spin = RunService.RenderStepped:Connect(function(dt: number)
				a += dt * 0.6
				cam.CFrame = CFrame.lookAt(cf.Position + Vector3.new(math.cos(a), 0.55, math.sin(a)).Unit * dist, cf.Position)
			end)
		end
		for _, ch in colors:GetChildren() do
			if ch:IsA("GuiButton") then
				ch:Destroy()
			end
		end
		for i, hex in c.colors do
			local sw = Ui.new("TextButton", {
				Text = "",
				LayoutOrder = i,
				Size = UDim2.fromOffset(40, 40),
				BackgroundColor3 = Color3.fromHex(hex),
				Parent = colors,
			}, { Ui.corner(20), Ui.stroke(if hex == color then 4 else 2, if hex == color then Color3.new(1, 1, 1) else Ui.LINE) })
			sw.Activated:Connect(function()
				select(c, hex)
			end)
		end
		buy.Text = if not rusty then "🔒 Build Rusty's first"
			elseif locked then `🔒 Level {c.unlockLevel}`
			elseif (c.bucks or 0) > 0 then `Buy  💎 {Ui.compact(c.bucks)}`
			else `Buy  🪙 {Ui.compact(c.price)}`
		buy:SetAttribute("Car", c.id)
		buy:SetAttribute("Color", color)
		buy:SetAttribute("Ok", rusty and not locked and afford)
		buy:SetAttribute("Why", if not rusty then "Build Rusty's Rescue first: the Showroom opens with it"
			elseif locked then `Reach level {c.unlockLevel} to buy the {c.name}`
			elseif not afford then (if s.bucks < (c.bucks or 0) then `You need {Ui.commas((c.bucks or 0) - s.bucks)} more gems` else `You need {Ui.commas(c.price - s.coins)} more coins`)
			else "")
	end

	buy = Ui.button({ Size = UDim2.new(1, -24, 0, 52), Position = UDim2.new(0, 12, 1, -60), TextSize = 24, Parent = stage }, "green", "Buy", function()
		if buy:GetAttribute("Ok") then
			local ok = Remote.act("buyCar", buy:GetAttribute("Car"), buy:GetAttribute("Color"))
			if ok then
				toast("New car! It's parked by your garage.")
			end
		else
			toast(buy:GetAttribute("Why") :: string)
		end
	end)

	local s = store.useGame.getState()
	local gate = store.gateLevel(s)
	table.sort(forSale, function(a, b)
		local ga = if gate < a.unlockLevel then a.unlockLevel else 0
		local gb = if gate < b.unlockLevel then b.unlockLevel else 0
		if ga ~= gb then
			return ga < gb
		end
		return a.price + (a.bucks or 0) * 100 < b.price + (b.bucks or 0) * 100
	end)
	local first
	for i, c in forSale do
		local locked = gate < c.unlockLevel
		local row = Ui.new("TextButton", {
			Text = "",
			LayoutOrder = i,
			Size = UDim2.new(1, -10, 0, 64),
			BackgroundColor3 = if locked then Color3.fromHex("#cfd8dc") else Color3.new(1, 1, 1),
			Parent = list,
		}, { Ui.corner(12), Ui.stroke(2) })
		local pic = Thumb.new("Cars", c.id, UDim2.fromOffset(84, 60), nil)
		pic.Position = UDim2.fromOffset(4, 2)
		pic.Parent = row
		Ui.new("TextLabel", {
			Text = c.name,
			Font = Ui.FONT,
			TextSize = 16,
			TextColor3 = Ui.INK,
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(94, 6),
			Size = UDim2.new(1, -100, 0, 26),
			Parent = row,
		})
		Ui.new("TextLabel", {
			Text = if locked then `🔒 Level {c.unlockLevel}` elseif (c.bucks or 0) > 0 then `💎 {Ui.compact(c.bucks)}` else `🪙 {Ui.compact(c.price)}`,
			Font = Ui.BODY,
			TextSize = 14,
			TextColor3 = Color3.fromHex("#455a64"),
			TextXAlignment = Enum.TextXAlignment.Left,
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(94, 34),
			Size = UDim2.new(1, -100, 0, 22),
			Parent = row,
		})
		row.Activated:Connect(function()
			select(c, c.colors[1])
		end)
		if c.id == lastSale or (not first and not lastSale) then
			first = c
		end
	end
	select(first or forSale[1], (first or forSale[1]).colors[1])
	frame.Destroying:Connect(function()
		if spin then
			spin:Disconnect()
		end
	end)
	return frame
end

return Showroom
