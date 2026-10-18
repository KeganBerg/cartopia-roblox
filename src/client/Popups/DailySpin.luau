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

function DailySpin.start(ctx: any)
	if not Remote.last then
		Remote.changed:Wait()
	end
	task.wait(0.8)
	local s = store.useGame.getState()
	if s.level ~= nil and s.lastDaily ~= store.today() and not busy(ctx) then
		ctx.open("daily")
	end
end

return DailySpin
