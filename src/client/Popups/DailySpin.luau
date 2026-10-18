--!strict
-- Opens the Daily Spin when the game starts and today's spin hasn't been taken, as the web game
-- does a moment after launch (App.tsx, openDaily in ui/FlashWarning.tsx): only when nothing else
-- is open, so it never lands on top of a menu or a race.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local store = require(Game.store) :: any
local Client = script.Parent.Parent
local Remote = require(Client.Remote)
local Placement = require(Client.Placement)

local DailySpin = {}

local function busy(ctx: any): boolean
	if ctx.gui:FindFirstChild("Panel") or Placement.active() then
		return true
	end
	local race = Players.LocalPlayer:FindFirstChild("PlayerGui") and (Players.LocalPlayer :: any).PlayerGui:FindFirstChild("Race")
	return race ~= nil and race:FindFirstChild("RaceScreen") ~= nil
end

-- Today's spin still to take, nothing in the way, and the tutorial over (a new player's first
-- spin is the tutorial's reward: it opens once the tutorial is done or skipped, App.tsx).
local function due(ctx: any): boolean
	local s = store.useGame.getState()
	return s.level ~= nil and s.lastDaily ~= store.today() and (s.tutorial or 99) >= 99 and not busy(ctx)
end

function DailySpin.start(ctx: any)
	if not Remote.last then
		Remote.changed:Wait()
	end
	task.wait(0.8)
	if due(ctx) then
		ctx.open("daily")
	end
	-- The tutorial ending (Let's go! or Skip): the first spin opens a moment later.
	local was = store.useGame.getState().tutorial or 99
	Remote.changed:Connect(function()
		local now = store.useGame.getState().tutorial or 99
		local ended = was < 99 and now >= 99
		was = now
		if ended then
			task.delay(1.2, function()
				if due(ctx) then
					ctx.open("daily")
				end
			end)
		end
	end)
end

return DailySpin
