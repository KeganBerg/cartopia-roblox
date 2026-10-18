--!strict
-- Bumper Blast (ui/RaceHub.tsx's 💥 button): straight into a kart race on any circuit, either way
-- round, every kart tuned the same, bumps landing hard and the road full of obstacles. No page of
-- its own; the server (server/Karts) picks the circuit, spends the fuel and pays the party prize.

local Blast = {}
Blast.id = "blast"
Blast.title = "Bumper Blast"
Blast.mini = {
	icon = "💥",
	label = "Bumper Blast",
	go = function(_ctx: any, api: any)
		api.kart("blast", nil)
	end,
}

function Blast.draw(_page: Frame, _ctx: any, api: any)
	api.show("hub")
end

return Blast
