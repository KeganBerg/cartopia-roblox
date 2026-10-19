--!strict
-- The Live page (ui/RaceHub.tsx's 🟢 Live, Race.tsx's live list, and LiveKartParty.tsx's roster):
-- live drag races and kart parties with the other players in this server. A driver's ⚔️ button
-- challenges them to a drag race (client/LiveDuels; it waits in their 🏁 bell). Start one and wait for others to join, or join one that's open;
-- the host's Go deals the race to everyone in it (server/KartParty, client/LiveKarts). AI karts
-- fill the grid up to six, and the prize is the live kart prize for the others' PI.

local Players = game:GetService("Players")

local Ui = require(script.Parent.Parent.Ui)
local Thumb = require(script.Parent.Parent.Thumb)
local Remote = require(script.Parent.Parent.Remote)
local LiveKarts = require(script.Parent.Parent.LiveKarts)
local LiveDuels = require(script.Parent.Parent.LiveDuels)

local Live = {}
Live.id = "live"
Live.title = "Live"
Live.mini = { icon = "🟢", label = "Live" }

function Live.chip(_s: any): string
	return "🏎️ Kart party"
end

local function hex(h: string): Color3
	return Color3.fromHex(h)
end

local ROW = 64

-- One player in a party: their car, name, PI, and whether they're in.
local function playerRow(parent: Instance, order: number, p: any, me: number)
	local row = Ui.new("Frame", { Name = `Player{order}`, LayoutOrder = order, Size = UDim2.new(1, 0, 0, ROW), BackgroundColor3 = if p.id == me then hex("#fff3e0") else Ui.WHITE, Parent = parent }, { Ui.corner(12), Ui.stroke(2, hex("#cfd8dc")) })
	if p.model then
		local pic = Thumb.new("Cars", p.model, UDim2.fromOffset(84, 58), if p.color then Color3.fromHex(p.color) else nil)
		pic.Position = UDim2.fromOffset(6, 3)
		pic.Parent = row
	end
	Ui.text({ Text = if p.id == me then "You" else p.name, TextSize = 19, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(98, 0), Size = UDim2.new(1, -200, 1, 0), Parent = row })
	local piText = `PI {p.pi}`
	local chip = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -52, 0.5, 0), Size = UDim2.fromOffset(math.ceil(Ui.textWidth(piText, 14)) + 16, 22), BackgroundColor3 = hex("#ffd54f"), Parent = row }, { Ui.corner(7), Ui.stroke(1.5, Ui.LINE) })
	Ui.text({ Text = piText, TextSize = 14, TextColor3 = Ui.LINE, Size = UDim2.fromScale(1, 1), Parent = chip })
	Ui.text({ Text = "✅", TextSize = 22, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(30, 30), Parent = row })
end

local function heading(parent: Instance, order: number, text: string)
	Ui.text({ Name = "Heading", LayoutOrder = order, Text = text, TextSize = 20, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 28), Parent = parent })
end

local function note(parent: Instance, order: number, text: string)
	Ui.text({ Name = "Note", LayoutOrder = order, Text = text, Body = true, Weight = "heavy", TextSize = 15, TextWrapped = true, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, 0, 0, 40), Parent = parent })
end

-- The web's liveReward (Race.tsx): what beating a live rival pays, by their PI.
local function prize(pi: number): number
	return 300 + pi * 8
end

local function money(n: number): string
	return if n >= 10000 then `${math.round(n / 1000)}k` else `${Ui.commas(n)}`
end

function Live.draw(page: Frame, ctx: any, _api: any)
	local me = Players.LocalPlayer and Players.LocalPlayer.UserId or 0
	local list = Ui.new("ScrollingFrame", { Name = "Live", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = page }, {
		Ui.new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8) }),
	})
	local busy = false
	local function call(op: string, arg: any?)
		if busy then
			return
		end
		busy = true
		task.spawn(function()
			Remote.race(op, arg)
			busy = false
		end)
	end
	-- The other drivers here, for a drag race (nil while loading).
	local drivers: { any }? = nil
	local refresh: () -> ()
	local function drawDrivers(nextOrder: () -> number)
		heading(list, nextOrder(), "⚔️ Drag race a driver")
		local rows = drivers
		if not rows then
			note(list, nextOrder(), "Looking for drivers…")
			return
		end
		if #rows == 0 then
			note(list, nextOrder(), "Nobody else is in this server right now. When a friend joins, challenge them here!")
			return
		end
		for _, p in rows do
			local card = Ui.new("Frame", { Name = `Driver{p.id}`, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, ROW), BackgroundColor3 = Ui.WHITE, Parent = list }, { Ui.corner(12), Ui.stroke(2, hex("#cfd8dc")) })
			if p.model then
				local pic = Thumb.new("Cars", p.model, UDim2.fromOffset(84, 58), if p.color then Color3.fromHex(p.color) else nil)
				pic.Position = UDim2.fromOffset(6, 3)
				pic.Parent = card
			end
			Ui.text({ Text = p.name or "Driver", TextSize = 19, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(98, 6), Size = UDim2.new(1, -250, 0, 26), Parent = card })
			Ui.text({ Text = `Lv {p.level or 1} · PI {p.pi or 0}`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(98, 34), Size = UDim2.new(1, -250, 0, 20), Parent = card })
			local text, kind = `⚔️ {money(prize(p.pi or 0))}`, "green"
			if p.asked then
				text, kind = "⏳ Cancel", "garage"
			elseif p.closed then
				text, kind = "🚫 Busy", "grey"
			elseif p.wait then
				text, kind = "⏱ Soon", "grey"
			end
			Ui.buy({ Name = "Challenge", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(130, 46), Parent = card }, text, kind, function()
				if busy or p.closed or p.wait then
					return
				end
				busy = true
				task.spawn(function()
					if p.asked then
						Remote.race("duelCancel")
						LiveDuels.outgoing = nil
					else
						LiveDuels.challenge(ctx, p.id, p.name or "Driver")
					end
					busy = false
					refresh()
				end)
			end, 17)
		end
	end
	local function draw(state: any)
		for _, d in list:GetChildren() do
			if d:IsA("GuiObject") then
				d:Destroy()
			end
		end
		local n = 0
		local function nextOrder(): number
			n += 1
			return n
		end
		local mine = state and state.mine
		if not mine then
			drawDrivers(nextOrder)
		end
		if mine then
			-- Your party: the roster, and Go for the host (2 players or more) or the wait.
			heading(list, nextOrder(), if mine.host == me then "🏎️ Your kart party" else `🏎️ {mine.hostName}'s kart party`)
			for _, p in mine.players do
				playerRow(list, nextOrder(), p, me)
			end
			local empty = (mine.max or 6) - #mine.players
			if empty > 0 then
				note(list, nextOrder(), `🤖 {empty} AI {if empty == 1 then "driver fills" else "drivers fill"} the rest of the grid.`)
			end
			local row = Ui.new("Frame", { Name = "Buttons", LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = list })
			if mine.host == me then
				local ready = #mine.players >= 2
				Ui.buy({ Name = "Go", Size = UDim2.new(0.62, -6, 0, 50), Parent = row }, if ready then `🏁 Go ×{#mine.players}` else "⏳ Waiting for racers", if ready then "green" else "grey", function()
					if ready then
						call("partyGo")
					end
				end, 19)
			else
				Ui.text({ Text = "⏳ The host starts the race", Body = true, Weight = "heavy", TextSize = 16, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.62, -6, 1, 0), Parent = row })
			end
			Ui.buy({ Name = "Leave", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.38, -6, 0, 50), Parent = row }, if mine.host == me then "Call off" else "Leave", "grey", function()
				call("partyLeave")
				LiveKarts.mine = nil
				task.delay(0.2, function()
					local ok, s = Remote.race("partyList", nil, true)
					if ok and list.Parent then
						draw(s)
					end
				end)
			end, 17)
		else
			heading(list, nextOrder(), "🏎️ Kart party")
			note(list, nextOrder(), "Race the other players in this server, live. Up to six racers, AI karts fill the grid.")
			local row = Ui.new("Frame", { Name = "Start", LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = list })
			Ui.buy({ Name = "Open", Size = UDim2.new(1, 0, 0, 50), Parent = row }, "🏎️ Start a kart party", "green", function()
				call("partyOpen")
			end, 19)
		end

		-- The parties open to join in this server.
		local open = state and state.open or {}
		if not mine then
			heading(list, nextOrder(), "🟢 Parties in this server")
			if #open == 0 then
				local ok, everyone = pcall(function()
					return #Players:GetPlayers()
				end)
				local others = if ok then everyone - 1 else 0
				note(list, nextOrder(), if others > 0 then "Nobody has a party open yet. Start one and the others can join." else "Nobody else is in this server right now.")
			end
			for _, p in open do
				local host = p.players[1] or {}
				local card = Ui.new("Frame", { Name = `Party{p.id}`, LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, ROW), BackgroundColor3 = Ui.WHITE, Parent = list }, { Ui.corner(12), Ui.stroke(2, hex("#cfd8dc")) })
				if host.model then
					local pic = Thumb.new("Cars", host.model, UDim2.fromOffset(84, 58), if host.color then Color3.fromHex(host.color) else nil)
					pic.Position = UDim2.fromOffset(6, 3)
					pic.Parent = card
				end
				Ui.text({ Text = p.hostName, TextSize = 19, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(98, 6), Size = UDim2.new(1, -230, 0, 26), Parent = card })
				Ui.text({ Text = `👥 {#p.players}/{p.max or 6}`, Body = true, Weight = "heavy", TextSize = 14, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(98, 34), Size = UDim2.fromOffset(120, 20), Parent = card })
				Ui.buy({ Name = "Join", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 46), Parent = card }, "Join", "green", function()
					call("partyJoin", p.id)
				end, 18)
			end
		end
	end
	refresh = function()
		task.spawn(function()
			local okD, d = Remote.race("duelList", nil, true)
			if okD and type(d) == "table" then
				drivers = d
			end
			local ok, s = Remote.race("partyList", nil, true)
			if ok and list.Parent then
				draw(s)
			end
		end)
	end
	draw(if LiveKarts.mine then { mine = LiveKarts.mine, open = {} } else nil)
	refresh()
	local conns: { RBXScriptConnection } = {}
	for _, signal in { LiveKarts.changed, LiveDuels.changed } do
		table.insert(conns, signal:Connect(function()
			if not list.Parent or not page.Parent then
				for _, c in conns do
					c:Disconnect()
				end
				return
			end
			refresh()
		end))
	end
end

return Live
