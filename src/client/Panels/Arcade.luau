--!strict
-- The web game's 'arcade' panel (ui/Arcade.tsx ArcadePanel), opened by the joystick over the
-- Pixel Palace (Popups/ArcadeBadge). The screen itself is client/Arcade.

return {
	id = "arcade",
	open = function(ctx: any, arg: any?): Instance
		return (require :: any)(script.Parent.Parent.Arcade).open(ctx, arg)
	end,
}
