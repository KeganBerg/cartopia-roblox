--!strict
-- Welcome back (ui/WelcomeBack.tsx): after five minutes or more away, and when something finished
-- meanwhile, the "welcome" menu (Panels/Welcome) opens shortly after the town loads. How long the
-- player was away comes from the server (the AwayMs attribute: since their save was last written).
-- Not over another menu, the level-up splash, edit mode, or a new player's tutorial (no Rusty's).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local Remote = require(script.Parent.Parent.Remote)
local Placement = require(script.Parent.Parent.Placement)
local Kit = require(script.Parent.Kit)
local Panel = require(script.Parent.Parent.Panels.Welcome)

local Welcome = {}

-- Shorter breaks don't earn a welcome.
Welcome.AWAY_MS = 5 * 60000

local function now(): number
	return workspace:GetServerTimeNow() * 1000
end

function Welcome.start(ctx: any)
	local player = Players.LocalPlayer
	local asked = false
	local function try()
		local away = player:GetAttribute("AwayMs")
		if asked or type(away) ~= "number" or away < Welcome.AWAY_MS or not Remote.last then
			return
		end
		asked = true
		task.delay(0.6, function()
			Kit.push(ctx, "welcome", 5, function(done)
				local s = store.useGame.getState()
				if not store.hasRusty(s) or not Panel.hasNews(s, now()) then
					done()
					return
				end
				ctx.open("welcome", away)
				local open = ctx.gui:FindFirstChild("Panel")
				if not open then
					done()
					return
				end
				open.Destroying:Connect(done)
			end, function()
				local s = store.useGame.getState()
				return not Kit.menuOpen(ctx) and not s.levelUp and not Placement.active() and not s.visiting
			end)
		end)
	end
	pcall(function()
		player:GetAttributeChangedSignal("AwayMs"):Connect(try)
	end)
	Remote.changed:Connect(try)
	try()
end

return Welcome
