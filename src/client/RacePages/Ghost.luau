--!strict
-- The Ghosts page (ui/GhostRace.tsx, lib/ghosts.ts): race the ghost of another player's best run.
-- On the web you race a friend's ghost from their town; here the page lists everyone in this
-- server, then your Roblox friends who've played, each with their best time (or a par for their
-- best car), above the taunts other players left you (TauntsPanel). After a run the result card
-- says who won and offers the preset taunts (GhostResultCard). The server (server/Modes/Ghost,
-- server/Ghosts) keeps the times and taunts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local data = require(Game.data) :: any
local Remote = require(script.Parent.Parent.Remote)
local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local DragStrip = require(script.Parent.Parent.DragStrip)

local Ghost = {}
Ghost.id = "ghost"
Ghost.title = "Ghost races"
Ghost.mini = { icon = "👻", label = "Ghosts" }

local function secs(t: number): string
	return string.format("%.3fs", t)
end

-- A taunt's line (TauntsPanel tauntLine).
local function tauntLine(t: any): string
	if t.their == nil then
		return `raced your ghost in {secs(t.t)}`
	end
	return if t.won then `beat your ghost by {secs(t.their - t.t)}` else `lost to your ghost by {secs(t.t - t.their)}`
end

local function draw(page: Frame, _ctx: any, api: any, info: any)
	local list = Ui.scroller({ Name = "Ghosts", Size = UDim2.fromScale(1, 1), Parent = page })
	Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = list })
	local car = api.myCar()

	-- Your own ghost: what others race.
	local mine = Ui.new("Frame", { Name = "Mine", LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = Color3.fromHex("#ede7f6"), Parent = list }, { Ui.corner(12), Ui.stroke(2, Color3.fromHex("#7e57c2")) })
	Ui.text({
		Text = if info.best then `👻 Your ghost runs {secs(info.best)}` else "👻 Your ghost runs a par for your car until you set a time",
		Body = true,
		Weight = "heavy",
		TextSize = 14,
		TextColor3 = Ui.INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -24, 1, 0),
		Parent = mine,
	})

	-- Taunts left for you, newest first (TauntsPanel), with a rematch for each.
	local seen = {}
	for i, t in info.inbox do
		table.insert(seen, t.id)
		local row = Ui.new("Frame", { Name = "Taunt", LayoutOrder = 10 + i, Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = Color3.fromHex("#fff8e1"), Parent = list }, { Ui.corner(14), Ui.stroke(2, Color3.fromHex("#ffb300")) })
		Ui.text({ Text = if t.won then "😤" else "😎", TextSize = 28, Position = UDim2.fromOffset(8, 0), Size = UDim2.new(0, 40, 1, 0), Parent = row })
		Ui.text({ Text = t.town, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(54, 6), Size = UDim2.new(1, -190, 0, 18), Parent = row })
		Ui.text({ Text = tauntLine(t), Body = true, TextSize = 12, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(54, 24), Size = UDim2.new(1, -190, 0, 16), Parent = row })
		Ui.text({ Text = `“{t.text}”`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Color3.fromHex("#6d4c41"), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(54, 42), Size = UDim2.new(1, -190, 0, 18), Parent = row })
		Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 40), Parent = row }, `Rematch ⛽{info.fuel}`, if car then "green" else "grey", if car then function()
			api.start("ghost", { vs = t.from })
		end else nil, 14)
	end
	-- Read now: the server clears them (taunts_seen).
	if #seen > 0 then
		task.spawn(Remote.race, "act", { mode = "ghost", which = { seen = seen } }, true)
	end

	-- Everyone with a ghost to race: players here first, then friends.
	Ui.text({ Text = "Race their best run", Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 100, Size = UDim2.new(1, 0, 0, 18), Parent = list })
	for i, g in info.people do
		local row = Ui.new("Frame", { Name = "Ghost", LayoutOrder = 100 + i, Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = Ui.WHITE, Parent = list }, { Ui.corner(14), Ui.stroke(2, Ui.LINE) })
		local ok, pic = pcall(Thumb.new, "Cars", g.model, UDim2.fromOffset(72, 52), Color3.fromHex(g.color))
		if ok and pic then
			pic.Position = UDim2.fromOffset(6, 5)
			pic.Parent = row
		end
		Ui.text({ Text = `{if g.here then "🟢 " else ""}{g.name} · {g.town}`, Body = true, Weight = "heavy", TextSize = 15, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(84, 8), Size = UDim2.new(1, -230, 0, 20), Parent = row })
		Ui.text({ Text = `{g.car}  PI {g.pi}`, Body = true, TextSize = 12, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(84, 30), Size = UDim2.new(1, -230, 0, 16), Parent = row })
		Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(140, 42), Parent = row }, `👻 {if g.par then "Par" else "Best"} {string.format("%.2f", g.t)}s ⛽{info.fuel}`, if car then "green" else "grey", if car then function()
			api.start("ghost", { vs = g.owner })
		end else nil, 14)
	end
	if #info.people == 0 then
		Ui.text({ Text = "👻 No ghosts to race yet. Friends who play Cartopia, and everyone in this server, show up here.", Body = true, Weight = "heavy", TextSize = 15, TextWrapped = true, TextColor3 = Ui.MUTED, LayoutOrder = 100, Size = UDim2.new(1, 0, 0, 70), Parent = list })
	end
end

function Ghost.draw(page: Frame, ctx: any, api: any)
	Ui.text({ Text = "Finding ghosts...", Body = true, TextSize = 20, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.MUTED, Parent = page })
	task.spawn(function()
		local ok, info = Remote.race("list", { mode = "ghost" }, true)
		if not page.Parent then
			return
		end
		page:ClearAllChildren()
		if not ok or not info then
			Ui.text({ Text = "📡 Couldn't find any ghosts", Body = true, TextSize = 20, Size = UDim2.fromScale(1, 1), TextColor3 = Ui.MUTED, Parent = page })
			return
		end
		draw(page, ctx, api, info)
	end)
end

-- The result card (GhostResultCard): who won (the race screen already shows both times and the
-- gap), and a taunt to leave them.
function Ghost.extras(ctx: any, which: any, started: any, again: (string, any) -> () -> ()): DragStrip.Extras
	local e = started.extra or {}
	return {
		title = `👻 {e.town or "Ghost"}'s {if e.par then "par time" else "best run"}`,
		icon = "👻",
		heading = function(res: any): string?
			local g = res.ghost
			if not g or not g.kept then
				return "NO TIME"
			end
			return if g.won then "GHOST BEATEN!" elseif math.abs(g.kept - g.their) < 0.3 then "SO CLOSE!" else "OUTRUN!"
		end,
		view = function(card: Frame, res: any, y: number): number
			local g = res.ghost
			if not g or not g.kept then
				return y
			end
			-- Leave them a taunt (.taunt-pick): chips that wrap; one per run.
			Ui.text({ Text = "Leave them a taunt", Body = true, TextSize = 12, TextColor3 = Ui.MUTED, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 16), Parent = card })
			y += 20
			local chips = Ui.new("Frame", { Name = "Taunts", Position = UDim2.fromOffset(18, y), Size = UDim2.new(1, -36, 0, 110), BackgroundTransparency = 1, Parent = card }, {
				Ui.new("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 32), CellPadding = UDim2.fromOffset(6, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }),
			})
			-- The friendliest first; after a win the first brag ones too.
			local shown = math.min(#g.taunts, if g.won then 6 else 4)
			for i = 1, shown do
				local t = g.taunts[i]
				local chip = Ui.new("TextButton", { Name = `Taunt{t.id}`, LayoutOrder = i, Text = "", AutoButtonColor = true, BackgroundColor3 = Ui.WHITE, Parent = chips }, { Ui.corner(16), Ui.stroke(2, Ui.LINE) })
				Ui.text({ Text = t.text, Body = true, Weight = "heavy", TextSize = 13, TextColor3 = Ui.INK, TextTruncate = Enum.TextTruncate.AtEnd, Size = UDim2.fromScale(1, 1), Parent = chip })
				;(chip :: TextButton).Activated:Connect(function()
					local ok, said = Remote.race("act", { mode = "ghost", which = { taunt = t.id } })
					if ok and said == "sent" then
						chips:ClearAllChildren()
						Ui.text({ Text = `Sent “{t.text}” 📨`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.MUTED, Size = UDim2.new(1, 0, 0, 32), Parent = chips })
					elseif ok then
						ctx.toast(if said == "limit" then "That's enough taunts for today" else "Couldn't send that")
					end
				end)
			end
			return y + math.ceil(shown / 2) * 38
		end,
		buttons = function(_res: any): { DragStrip.Button }?
			return { { text = "Back", kind = "garage" }, { text = `↻ Again · ⛽{data.RACE_FUEL}`, go = again("ghost", which) } }
		end,
	}
end

return Ghost
