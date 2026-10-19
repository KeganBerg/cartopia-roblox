--!strict
-- Surprise visitors in town (the web's lib/visitors.ts, ticked every second from App.tsx): starts
-- client/Visitors (who's in town, asking the server for the next one) and client/VisitorCar (their
-- car on the roads and its badge), then ticks the visitors' clock once a second.

local Visitors = require(script.Parent.Parent.Visitors)
local VisitorCar = require(script.Parent.Parent.VisitorCar)

local VisitorsPopup = {}

function VisitorsPopup.start(ctx: any)
	Visitors.start(ctx)
	VisitorCar.start(ctx)
	while true do
		task.wait(1)
		Visitors.tick()
	end
end

return VisitorsPopup
