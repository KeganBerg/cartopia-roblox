--!strict
-- The Bank's car packs (client/Bank), as the web game's "carpacks" panel.
local Bank = require(script.Parent.Parent.Bank)

return {
	id = "carpacks",
	open = function(ctx: any, _arg: any?): Instance
		return Bank.open(ctx, "carpacks")
	end,
}
