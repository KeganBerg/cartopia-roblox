--!strict
-- The Bank's gem packs (client/Bank), as the web game's "bank" panel.
local Bank = require(script.Parent.Parent.Bank)

return {
	id = "bank",
	open = function(ctx: any, _arg: any?): Instance
		return Bank.open(ctx, "bank")
	end,
}
