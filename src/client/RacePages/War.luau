--!strict
-- War races (the web game's crew war map, lib/warMap.ts): started from the Crew tab's war map
-- (client/Social/Crew), so no page of its own here, only the result card: the stars taken off
-- the rival and the war points they made for the crew (server/Modes/War).

local Ui = require(script.Parent.Parent.Ui)
local DragStrip = require(script.Parent.Parent.DragStrip)

local War = {}
War.id = "war"
War.title = "Crew war"

function War.extras(ctx: any, _which: any, started: any, _again: (string, any) -> () -> ()): DragStrip.Extras
	local e = (started.extra or {}).war or {}
	return {
		title = `⚔️ War race · {e.name or "Rival"}`,
		icon = "⚔️",
		heading = function(res: any): string?
			local w = res.war
			if not w or not w.kept then
				return "NO TIME"
			end
			return if w.stars == 3 then "⭐⭐⭐ CRUSHED!" elseif w.won then "RIVAL BEATEN!" else "OUTRUN!"
		end,
		view = function(card: Frame, res: any, y: number): number
			local w = res.war
			if not w then
				return y
			end
			-- The stars taken: gold, the rest grey.
			local row = Ui.new("Frame", { Name = "WarStars", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(96, 34), BackgroundTransparency = 1, Parent = card })
			for i = 1, 3 do
				Ui.text({ Text = "★", TextSize = 30, TextColor3 = if i <= w.stars then Color3.fromHex("#ffb300") else Color3.fromHex("#cfd8dc"), Stroke = 1.5, Position = UDim2.fromOffset((i - 1) * 32, 0), Size = UDim2.fromOffset(32, 34), Parent = row })
			end
			y += 36
			Ui.text({ Text = if w.points > 0 then `+{w.points} war points for your crew` else "Win by 1% for ★★, by 3% for ★★★", Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 20), Parent = card })
			y += 22
			Ui.text({ Text = `🎟 {w.left} war race{if w.left == 1 then "" else "s"} left today`, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 18), Parent = card })
			return y + 22
		end,
		buttons = function(_res: any): { DragStrip.Button }?
			local list: { DragStrip.Button } = {
				{ text = "🛡️ Crew war", go = function()
					ctx.open("friends", "clan")
				end },
			}
			return list
		end,
	}
end

return War
