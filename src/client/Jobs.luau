--!strict
-- The bubbles over the player's businesses, as on the web: a start bubble with the fuel a job
-- takes, a countdown while the job runs, and a coin to collect when it's done. Tapping a bubble
-- taps the building.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local Remote = require(script.Parent.Remote)
local Town = require(script.Parent.Town)
local Ui = require(script.Parent.Ui)

local Jobs = {}

type Bubble = { gui: BillboardGui, button: TextButton, text: TextLabel }
local bubbles: { [Model]: Bubble } = {}

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

local function make(model: Model, parent: Instance): Bubble
	local gui = Ui.new("BillboardGui", {
		Name = "Job",
		Adornee = model.PrimaryPart,
		AlwaysOnTop = true,
		Active = true,
		Size = UDim2.fromOffset(96, 44),
		StudsOffsetWorldSpace = Vector3.new(0, ((model:GetAttribute("Height") :: number?) or 10) / 2 + 6, 0),
		MaxDistance = 600,
		ResetOnSpawn = false,
		Parent = parent,
	})
	local button = Ui.button({ Size = UDim2.fromScale(1, 1), Text = "", Parent = gui }, "white", "", function()
		Remote.act("tapBuilding", model:GetAttribute("Uid"))
	end)
	local text = Ui.label({ Size = UDim2.fromScale(1, 1), TextSize = 18, Parent = button })
	return { gui = gui, button = button, text = text }
end

local function style(b: Bubble, colors: string, text: string)
	local c = Ui.COLORS[colors]
	local g = b.button:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(Color3.fromHex(c[1]), Color3.fromHex(c[2]))
	end
	b.text.Text = text
end

function Jobs.start(gui: ScreenGui)
	local holder = Ui.new("Folder", { Name = "JobBubbles", Parent = gui.Parent })
	task.spawn(function()
		while true do
			local town = Town.folder()
			local seen: { [Model]: boolean } = {}
			if town then
				for _, m in (town :: any).Buildings:GetChildren() do
					local def = data.buildingDef(m:GetAttribute("Def") or "")
					if not def.jobSeconds or not m.PrimaryPart then
						continue
					end
					seen[m] = true
					local b = bubbles[m] or make(m, holder)
					bubbles[m] = b
					local ends: number? = m:GetAttribute("JobEndsAt")
					if ends == nil then
						style(b, "white", `▶ ⛽{def.fuelCost}`)
					elseif now() >= ends then
						style(b, "edit", `🪙 {Ui.compact(def.payout or 0)}`)
					else
						style(b, "navy", `⏱ {Ui.clock((ends - now()) / 1000)}`)
					end
				end
			end
			for m, b in bubbles do
				if not seen[m] then
					b.gui:Destroy()
					bubbles[m] = nil
				end
			end
			task.wait(0.25)
		end
	end)
end

-- How many jobs are done and waiting to be collected.
function Jobs.ready(): number
	local n = 0
	local town = Town.folder()
	if not town then
		return 0
	end
	for _, m in (town :: any).Buildings:GetChildren() do
		local ends: number? = m:GetAttribute("JobEndsAt")
		if ends and now() >= ends then
			n += 1
		end
	end
	return n
end

return Jobs
