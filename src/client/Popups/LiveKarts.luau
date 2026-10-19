--!strict
-- Starts listening for kart parties (client/LiveKarts) once the HUD is up.

return {
	start = function(ctx: any)
		require(script.Parent.Parent.LiveKarts).start(ctx)
	end,
}
