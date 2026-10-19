--!strict
-- Picking a plot in the shared world (server/World): a new arrival sees the whole map from above,
-- with a Claim button over every free plot and the names of the towns already built, and a banner
-- with "Nearest free plot". Claiming builds their town there and the view drops down over it.
--
-- Shown while the player's NeedsPlot attribute is set (the server sets it when they join).

local Players = game:GetService("Players")

local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)
local TownCamera = require(script.Parent.Parent.TownCamera)

local Claim = {}

function Claim.start(ctx: any)
	local me = Players.LocalPlayer
	local shown: { Instance } = {}
	local busy = false

	local function clear()
		for _, inst in shown do
			inst:Destroy()
		end
		shown = {}
	end

	local function claim(i: number?)
		if busy then
			return
		end
		busy = true
		local ok = Remote.social("claim", i)
		busy = false
		if ok then
			clear()
			TownCamera.setOverview(false)
			ctx.toast("Welcome to your plot! Your town is built.")
		end
	end

	local function draw()
		clear()
		local plots = workspace:FindFirstChild("World") and (workspace :: any).World:FindFirstChild("Plots")
		if not plots then
			return
		end
		local holder = Ui.new("Folder", { Name = "PlotPicker", Parent = me:WaitForChild("PlayerGui") })
		table.insert(shown, holder)
		for _, m in plots:GetChildren() do
			local i = m:GetAttribute("Index")
			local pad = m:FindFirstChild("Pad")
			if type(i) ~= "number" or not pad then
				continue
			end
			local free = m:GetAttribute("Free") == true
			local gui = Ui.new("BillboardGui", {
				Name = `Plot{i}`,
				Adornee = pad,
				AlwaysOnTop = true,
				Active = true,
				LightInfluence = 0,
				Size = UDim2.fromOffset(150, 52),
				StudsOffsetWorldSpace = Vector3.new(0, 30, 0),
				ResetOnSpawn = false,
				Parent = holder,
			})
			if free then
				Ui.buy({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(120, 40), Parent = gui }, "🏡 Claim", "green", function()
					claim(i)
				end, 17)
			else
				local name = tostring(m:GetAttribute("OwnerName") or "Taken")
				local _, face = Ui.pill({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(140, 30), Parent = gui })
				Ui.text({ Text = `🏠 {name}`, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.fromScale(1, 1), Parent = face })
			end
		end
		-- The banner along the bottom (like the visit banner).
		local shadow, face = Ui.shadowed({ Name = "ClaimBanner", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(560, 64), Parent = ctx.gui }, { radius = 18, stroke = 3, drop = 5, dark = 0.3, color = Ui.SHEET })
		table.insert(shown, shadow)
		Ui.text({ Text = "Pick a plot for your town", TextSize = 19, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 9), Size = UDim2.fromOffset(320, 24), Parent = face })
		Ui.text({ Text = "Your neighbours can drive over to see it", Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#607d8b"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 33), Size = UDim2.fromOffset(320, 18), Parent = face })
		Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, -1), Size = UDim2.fromOffset(190, 40), Parent = face }, "🏡 Nearest free plot", "green", function()
			claim(nil)
		end, 16)
	end

	local function update()
		if me:GetAttribute("NeedsPlot") == true then
			TownCamera.setOverview(true)
			draw()
		elseif #shown > 0 then
			clear()
			TownCamera.setOverview(false)
		end
	end
	me:GetAttributeChangedSignal("NeedsPlot"):Connect(update)
	-- Others claiming while you look: their plots turn into town names.
	local plots = workspace:FindFirstChild("World") and (workspace :: any).World:FindFirstChild("Plots")
	if plots then
		for _, m in plots:GetChildren() do
			m:GetAttributeChangedSignal("Free"):Connect(function()
				if me:GetAttribute("NeedsPlot") == true then
					draw()
				end
			end)
		end
	end
	update()
end

return Claim
