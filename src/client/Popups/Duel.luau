--!strict
-- Starts listening for live drag race challenges (client/LiveDuels) once the HUD is up.

return {
	start = function(ctx: any)
		require(script.Parent.Parent.LiveDuels).start(ctx)
	end,
}
