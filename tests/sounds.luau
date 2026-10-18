--!nocheck
-- Tests for the game's sound: the store's sfx.* calls reach the player's client with the town's
-- snapshot (Towns), and the nightclub picks the web's track for each night (ClubSet).

local Towns = require("../src/server/Towns")
local ClubSet = require("../src/shared/ClubSet")
local Js = require("../src/shared/Game/__js")

local function expectEq(a, b, what)
	if a ~= b then
		error(`{what}: expected {tostring(b)}, got {tostring(a)}`, 2)
	end
end

-- clubSet.ts trackOf for nights -40 .. 399 with the web's 18 tracks.
local WEB = {7,15,0,8,10,8,15,12,3,16,5,7,14,11,0,2,4,13,1,6,9,17,16,15,11,12,7,5,3,8,6,2,4,14,9,13,1,17,0,10,6,3,13,16,5,1,11,12,4,14,9,8,15,2,17,7,10,0,1,0,17,13,12,3,11,16,4,6,2,14,8,9,5,10,7,15,5,17,15,12,9,14,7,4,1,2,0,16,3,6,13,10,8,11,1,13,16,14,7,9,8,5,4,17,10,15,6,0,3,11,2,12,7,4,1,15,12,2,6,14,13,16,0,5,9,3,10,17,11,8,17,11,1,5,0,9,2,8,6,7,15,13,3,10,4,16,12,14,15,1,13,14,0,11,4,3,17,5,16,6,9,7,10,12,8,2,7,2,16,15,13,1,11,10,4,12,9,6,17,0,3,8,5,14,11,16,15,13,12,1,9,6,0,5,4,8,14,2,17,7,10,3,12,14,5,8,1,2,9,0,4,17,11,6,13,15,3,16,7,10,6,12,1,13,9,8,2,14,15,0,4,7,17,10,11,16,5,3,13,2,1,4,5,17,7,8,3,11,9,0,14,10,12,15,16,6,17,3,13,6,1,5,2,11,16,8,7,0,14,4,10,9,15,12,8,16,5,0,9,17,15,3,2,6,7,12,14,4,11,10,1,13,7,1,0,9,12,15,10,4,17,11,5,14,8,13,3,2,6,16,9,4,2,10,12,11,16,14,17,7,8,1,6,3,15,13,0,5,12,0,4,8,2,7,1,15,17,10,13,6,9,11,5,14,3,16,13,12,8,15,9,14,7,4,6,1,11,16,2,10,5,17,3,0,13,11,10,16,3,15,9,4,1,12,7,8,6,5,0,2,17,14,11,0,7,4,2,9,16,3,17,10,5,12,14,15,13,1,6,8,17,9,5,15,14,7,11,0,13,8,2,10,3,1,6,12,4,16,9,13,14,17,11,16,2,0,12,5,10,1,8,4,15,3,6,7,12,7,16,2}

return function(test)
	test("sounds: the club plays the web's track each night", function()
		for i, want in WEB do
			expectEq(ClubSet.trackOf(i - 41, 18), want, `night {i - 41}`)
		end
	end)

	test("sounds: the store's sounds go out once with the snapshot", function()
		local now = Js.JsDate.UTC(2026, 9, 17, 12)
		Js.setClock(function()
			return now
		end)
		local store = require("../src/shared/Game/store")
		local sound = require("../src/shared/Game/lib_sound")
		local towns = Towns.new(store, function()
			return now
		end, sound)
		towns:open(7, nil)
		towns:snapshot(7)
		expectEq(towns:run(7, "placeBuilding", "rescue", 12, 12), true, "builds Rusty's")
		local snap = towns:snapshot(7)
		expectEq(#snap.sounds > 0, true, "a sound for building")
		expectEq(snap.sounds[1][1], "click", "placing a building clicks, as on the web")
		expectEq(#towns:snapshot(7).sounds, 0, "sent only once")
		expectEq(sound.heard, nil, "nothing listens outside an action")
		towns:close(7)
	end)
end
