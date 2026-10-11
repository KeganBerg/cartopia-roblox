-- Server entry point. The server owns the economy: coins, cars and progress live here and in
-- DataStores, and clients only ask for changes through remotes. Nothing gameplay-facing yet;
-- this step only brings the shared rules over from the web game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Util = require(Shared.Util)
local Data = require(Shared.Data)
local Race = require(Shared.Race)

-- Millisecond clock, so day keys, seasons and events match the web game to the second.
Util.setClock(function()
	return DateTime.now().UnixTimestampMillis
end)

print(`[Cartopia] {#Data.BUILDINGS} buildings, {#Data.CARS} cars, {#Data.MODS} mods loaded`)
print(`[Cartopia] today {Data.dayKey()}, week {Data.weekKey()}, season {Data.seasonNumber()}`)
print(`[Cartopia] PI 60 dyno pull {Race.dynoPull(60)}s, referee floor {Race.raceFloor(60)}s`)
