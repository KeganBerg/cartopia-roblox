--!strict
-- The season recap card, as the web game's RecapPopup (ui/Recap.tsx, game/recap.ts): shown once
-- when a new season starts, summing up the one that just ended: races and wins, trophies and coins
-- earned, cars added, season stars, how far the reputation title moved and the season tiers won.
-- The server works it out (server/Towns recapCheck) and keeps it on the town until "On to the new
-- season!" closes it (closeRecap), so a rejoin doesn't lose it. Nothing is paid: it's a look back,
-- with a share button (Roblox's invite prompt, with the season's line on it).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local reputation = require(Game.reputation) :: any
local Client = script.Parent.Parent
local Ui = require(Client.Ui)
local Remote = require(Client.Remote)
local Sfx = require(Client.Sounds.Sfx)
local Kit = require(script.Parent.Kit)

local Recap = {}

local W = 360
local H2 = Color3.fromHex("#e65100")

-- The words under the stats: the title then and now, and the tiers won.
function Recap.repLine(r: any): string
	local from = reputation.REP_TITLES[(r.repFrom or 0) + 1] or reputation.REP_TITLES[1]
	local to = reputation.REP_TITLES[(r.repTo or 0) + 1] or from
	local line = if (r.repTo or 0) > (r.repFrom or 0) then `Title: {from.icon} {from.name} → <b>{to.icon} {to.name}</b>` else `Title: <b>{to.icon} {to.name}</b>`
	if (r.tiers or 0) > 0 then
		line ..= ` · {r.tiers} season tier{if r.tiers > 1 then "s" else ""} won`
	end
	return line
end

-- The six stats, as the web's grid.
function Recap.stats(r: any): { { string } }
	return {
		{ "🏎️", "Races", Ui.commas(r.races or 0) },
		{ "🥇", "Wins", Ui.commas(r.wins or 0) },
		{ "🏆", "Trophies", Ui.commas(r.trophies or 0) },
		{ "💵", "Coins earned", Ui.commas(r.coins or 0) },
		{ "🚗", "New cars", Ui.commas(r.cars or 0) },
		{ "⭐", "Season stars", Ui.commas(r.stars or 0) },
	}
end

local function share(ctx: any, r: any)
	local ok = pcall(function()
		local opts = Instance.new("ExperienceInviteOptions")
		opts.PromptMessage = `My Cartopia {r.name}: {r.races} races · {r.wins} wins · +{r.trophies} trophies · {r.stars} stars`
		SocialService:PromptGameInvite(Players.LocalPlayer, opts)
	end)
	if not ok then
		ctx.toast("Sharing isn't available here")
	end
end

-- Draws the card for recap r; close runs when its button is pressed.
function Recap.show(ctx: any, r: any, close: () -> ())
	local overlay = Kit.overlay(ctx, false)
	overlay.Name = "Popup"
	local cellH, gap = 64, 6
	local h = 18 + 16 + 2 + 30 + 10 + cellH * 2 + gap + 10 + 36 + 8 + 44 + 18
	local _, face = Ui.shadowed({ Name = "Recap", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, h), ZIndex = 2, Parent = overlay }, {
		radius = 22,
		stroke = 4,
		drop = 0,
		dark = 0.25,
		color = Kit.PANEL,
		strokeColor = Kit.GOLD,
		class = "TextButton",
	})
	face.Selectable = false
	local y = 18
	Ui.text({ Name = "Eyebrow", Text = "SEASON RECAP", Body = true, Weight = "heavy", TextSize = 12, TextColor3 = Color3.fromHex("#8a6d00"), Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 16), Parent = face })
	y += 18
	Ui.text({ Name = "Title", Text = `{r.icon} {r.name}`, TextSize = 26, TextColor3 = H2, Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 30), Parent = face })
	y += 30 + 10
	local grid = Ui.new("Frame", { Name = "Stats", Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, cellH * 2 + gap), BackgroundTransparency = 1, Parent = face }, {
		Ui.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -5, 0, cellH), CellPadding = UDim2.fromOffset(gap, gap), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, st in Recap.stats(r) do
		local cell = Ui.new("Frame", { Name = st[2], LayoutOrder = i, BackgroundColor3 = Kit.GOLD, BackgroundTransparency = 0.86, Parent = grid }, { Ui.corner(12) })
		Ui.text({ Text = st[1], TextSize = 20, Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0, 22), Parent = cell })
		Ui.text({ Name = "Value", Text = st[3], TextSize = 18, TextColor3 = Ui.INK, Position = UDim2.fromOffset(2, 26), Size = UDim2.new(1, -4, 0, 20), TextScaled = #st[3] > 9, Parent = cell })
		Ui.text({ Text = st[2], Body = true, Weight = "heavy", TextSize = 11, TextColor3 = Color3.fromHex("#607d8b"), Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 14), Parent = cell })
	end
	y += cellH * 2 + gap + 10
	Ui.text({ Name = "Rep", Text = Recap.repLine(r), RichText = true, Body = true, TextSize = 13, TextColor3 = Ui.INK, TextWrapped = true, Position = UDim2.fromOffset(22, y), Size = UDim2.new(1, -44, 0, 36), Parent = face })
	y += 36 + 8
	-- Share (the blue .alt) and the way on, side by side (.prize .row).
	Kit.button(face, "📤 Share", -104, y, 100, 44, "garage", function()
		share(ctx, r)
	end, 17)
	Kit.button(face, "On to the new season!", 54, y, 200, 44, "green", close, 16)
	-- A moment after it lands, the reward sound (as the web's).
	task.delay(0.25, Sfx.reward)
	return overlay
end

function Recap.start(ctx: any)
	local shown: number? = nil
	local function look(snap: any)
		local r = snap and snap.save and snap.save.recap
		if type(r) ~= "table" or r.n == shown then
			return
		end
		local n = r.n
		Kit.push(ctx, "recap", 7, function(done)
			shown = n
			local overlay: Instance? = nil
			local closed = false
			overlay = Recap.show(ctx, r, function()
				if closed then
					return
				end
				closed = true
				task.spawn(Remote.act, "closeRecap")
				if overlay then
					overlay:Destroy()
				end
				done()
			end)
		end)
	end
	Remote.changed:Connect(look)
	look(Remote.last)
end

return Recap
