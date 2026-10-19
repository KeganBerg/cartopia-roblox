--!strict
-- The street race against a street racer visiting town (Race.tsx's street race, lib/visitors.ts):
-- started from the Street challenge card (Panels/StreetRace, client/Visitors), never from the race
-- menu, so the page has no button there. The race screen is the usual drag race titled "🏁 Street
-- challenge", with the usual result card; beating the racer also pays their bonus on the server
-- (server/Modes/Street), which the toast after it says, with the coin sound.

local Ui = require(script.Parent.Parent.Ui)
local Sfx = require(script.Parent.Parent.Sounds.Sfx) :: any

local Street = {}
Street.id = "street"
Street.title = "Street challenge"

-- Never opened from the menu; if it ever is, it says where street races come from.
function Street.draw(page: Frame, _ctx: any, _api: any)
	Ui.text({ Text = "🏁 Street racers visit your town. Tap one to race!", Body = true, Weight = "heavy", TextSize = 18, TextColor3 = Ui.MUTED, Size = UDim2.fromScale(1, 1), Parent = page })
end

function Street.extras(_ctx: any, _which: any, _started: any, _again: (string, any) -> () -> ()): any
	return {
		title = "🏁 Street challenge",
		view = function(_card: Frame, res: any, y: number): number
			if res.street and res.street.paid then
				Sfx.coin()
			end
			return y
		end,
	}
end

return Street
