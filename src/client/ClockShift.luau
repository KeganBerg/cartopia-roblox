--!strict
-- The time the town's sky, light and weather are drawn at: the real time, or the one the admin
-- panel picked for testing (server/Admin/Panel) for this player's own view. Nothing on the server
-- or in anyone else's game moves with it.

local ClockShift = {}

-- A fixed moment (ms since the epoch) to draw, or nil for the real time.
ClockShift.frozen = nil :: number?

function ClockShift.now(): number
	return ClockShift.frozen or DateTime.now().UnixTimestampMillis
end

return ClockShift
