--!strict
-- The Social menu's Friends tab, as the web game's FriendsPanel (ui/Friends.tsx), with Roblox's
-- own friends in place of the web's friend requests: Invite friends, your friends (in this server:
-- Visit; playing Cartopia elsewhere: Join; online in another game or offline: greyed), then the
-- other drivers in this server to visit and help. Leaderboards: client/Social/Leaders. The Crew and
-- Meet tabs aren't on Roblox yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")
local StarterGui = game:GetService("StarterGui")

local Game = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game")
local friendship = require(Game.friendship) :: any
local store = require(Game.store) :: any
local Policy = require(ReplicatedStorage.Shared.Policy)
local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)
local Leaders = require(script.Parent.Parent.Social.Leaders)

local Friends = {}
Friends.id = "friends"

local ROW_H = 52
local GAP = 6
local HELPS_PER_TOWN = 5

-- The web's Avatar: a coloured circle with the name's first letter (hue from the name), under
-- the player's Roblox headshot.
local function avatar(parent: Instance, name: string, userId: number?, on: boolean)
	local hue = 7
	for _, c in utf8.codes(name) do
		hue = (hue * 31 + c) % 360
	end
	local holder = Ui.new("Frame", { Name = "Avatar", Position = UDim2.fromOffset(10, (ROW_H - 34) / 2), Size = UDim2.fromOffset(34, 34), BackgroundColor3 = Color3.fromHSV(hue / 360, 0.6, 0.85), Parent = parent }, {
		Ui.round(),
		Ui.text({ Text = string.upper(string.sub(name, 1, 1)), TextSize = 18, Size = UDim2.fromScale(1, 1) }),
	})
	if userId and userId > 0 then
		Ui.new("ImageLabel", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Image = `rbxthumb://type=AvatarHeadShot&id={userId}&w=48&h=48`, Parent = holder }, { Ui.round() })
	end
	if on then
		Ui.new("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1.05, 1.05), Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromHex("#43a047"), ZIndex = 2, Parent = holder }, { Ui.round(), Ui.stroke(2, Ui.WHITE) })
	end
end

-- One row: avatar, name (and friendship badge), a small line, then its buttons right to left.
type Button = { text: string, kind: string, width: number, onClick: () -> () }
local function row(list: Instance, order: number, o: { name: string, userId: number?, on: boolean, line: string, badge: string?, dim: boolean?, buttons: { Button } })
	local r = Ui.new("Frame", { Name = o.name, LayoutOrder = order, Size = UDim2.new(1, 0, 0, ROW_H), BackgroundColor3 = Ui.WHITE, Parent = list }, {
		Ui.corner(12),
		Ui.stroke(2, Color3.fromHex("#e0e0e0")),
	})
	avatar(r, o.name, o.userId, o.on)
	local right = 10
	for _, b in o.buttons do
		Ui.buy({ AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -right, 0.5, -1), Size = UDim2.fromOffset(b.width, 34), Parent = r }, b.text, b.kind, b.onClick, 15)
		right += b.width + 6
	end
	local ink = if o.dim then Ui.MUTED else Ui.INK
	Ui.text({ Text = o.name .. (if o.badge then ` {o.badge}` else ""), Body = true, Weight = "heavy", TextSize = 16, TextColor3 = ink, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(54, 7), Size = UDim2.new(1, -54 - right, 0, 20), Parent = r })
	Ui.text({ Text = o.line, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(54, 27), Size = UDim2.new(1, -54 - right, 0, 17), Parent = r })
	return r
end

local function heading(list: Instance, order: number, text: string, small: string?)
	local h = Ui.new("Frame", { Name = "Heading", LayoutOrder = order, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = list })
	local w = Ui.textWidth(text, 19)
	Ui.text({ Text = text, TextSize = 19, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(2, 2), Size = UDim2.new(0, w + 4, 1, 0), Parent = h })
	if small then
		Ui.text({ Text = small, Body = true, TextSize = 13, TextColor3 = Ui.MUTED, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(w + 12, 5), Size = UDim2.new(1, -w - 12, 1, 0), Parent = h })
	end
end

local function note(list: Instance, order: number, text: string)
	Ui.text({ Name = "Note", Text = text, Body = true, TextSize = 14, TextColor3 = Ui.MUTED, TextWrapped = true, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 34), Parent = list })
end

-- The friendship badge for a player (game/friendship.ts: helps, gifts and postcards add up).
local function badge(userId: number): string?
	local s = store.useGame.getState()
	local pts = (s.friendship or {})[tostring(userId)] or 0
	if pts <= 0 then
		return nil
	end
	local lv = friendship.FRIEND_LEVELS[friendship.friendLevel(pts) + 1]
	return lv and lv.icon
end

-- Roblox friends with where they are: { id, name, online, here, cartopia }.
local function robloxFriends(): { any }
	local me = Players.LocalPlayer
	local out: { any } = {}
	local seen: { [number]: any } = {}
	local ok, online = pcall(me.GetFriendsOnline, me, 200)
	if ok and type(online) == "table" then
		for _, f in online do
			local entry = {
				id = f.VisitorId,
				name = f.DisplayName or f.UserName,
				online = true,
				here = f.GameId == game.JobId and Players:GetPlayerByUserId(f.VisitorId) ~= nil,
				cartopia = f.PlaceId == game.PlaceId and f.GameId ~= nil,
			}
			seen[f.VisitorId] = entry
			table.insert(out, entry)
		end
	end
	local pagesOk, pages = pcall(Players.GetFriendsAsync, Players, me.UserId)
	if pagesOk and pages then
		for _, f in (pages :: FriendPages):GetCurrentPage() do
			if not seen[f.Id] then
				table.insert(out, { id = f.Id, name = f.DisplayName or f.Username, online = false, here = false, cartopia = false })
			end
		end
	end
	-- In this server, then in Cartopia, then online, then everyone else.
	local function rank(f: any): number
		return if f.here then 0 elseif f.cartopia then 1 elseif f.online then 2 else 3
	end
	table.sort(out, function(a, b)
		if rank(a) ~= rank(b) then
			return rank(a) < rank(b)
		end
		return a.name < b.name
	end)
	return out
end

function Friends.open(ctx: any, arg: any?): Instance
	local overlay, _sheet, body = Ui.panel(ctx.gui, "Social", { wide = true, onClose = ctx.close, bodyTop = 0 })
	local soon = { clan = "Crews", meet = "The Car Meet" }
	local first = if arg == "leaders" then "leaders" else "friends"
	local pick: (string) -> ()
	local show: (string) -> ()
	_, pick = Ui.tabs(body, {
		{ id = "friends", label = "👫 Friends" },
		{ id = "clan", label = "🛡️ Crew" },
		{ id = "meet", label = "🚗 Meet" },
		{ id = "leaders", label = "🏅 Leaderboards" },
	}, first, function(id)
		if soon[id] then
			ctx.toast(`{soon[id]} are coming to Roblox soon`)
			pick("friends")
			return
		end
		show(id)
	end, { position = UDim2.fromOffset(-14, 0), size = UDim2.new(1, 28, 0, 54) })

	local list = Ui.scroller({ Name = "List", Position = UDim2.fromOffset(-6, 64), Size = UDim2.new(1, 12, 1, -64), Parent = body })
	Ui.new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4), Parent = list })
	Ui.new("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

	local me = Players.LocalPlayer
	local function visit(userId: number)
		local ok, town = Remote.social("visit", userId)
		if ok then
			ctx.close()
			ctx.setVisit(town)
		end
	end
	local function join(userId: number, name: string)
		ctx.toast(`Joining {name}…`)
		local ok, res = Remote.social("join", userId)
		if ok and res.here then
			ctx.close()
			ctx.setVisit(res.town)
		end
	end
	local function addFriend(userId: number)
		local p = Players:GetPlayerByUserId(userId)
		if p then
			pcall(function()
				StarterGui:SetCore("PromptSendFriendRequest", p)
			end)
		end
	end

	local leaderState = {}
	local shown = ""
	local function clear()
		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		list.CanvasPosition = Vector2.zero
	end
	local function drawFriends()
		local loading = Ui.text({ Name = "Loading", Text = "Finding your friends…", Body = true, TextSize = 15, TextColor3 = Ui.MUTED, LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 40), Parent = list })
		task.spawn(function()
			local rules = Policy.fromAttributes(function(name)
				return me:GetAttribute(name)
			end)
			local canInvite = Policy.canShare(rules) and (function()
				local ok, can = pcall(SocialService.CanSendGameInviteAsync, SocialService, me)
				return ok and can == true
			end)()
			local friends = robloxFriends()
			local okPlayers, here = Remote.social("players", nil, true)
			if not overlay.Parent or shown ~= "friends" then
				return
			end
			loading:Destroy()
			local order = 1
			local function nextOrder(): number
				order += 1
				return order
			end
			if canInvite then
				local holder = Ui.new("Frame", { Name = "Invite", LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = list })
				Ui.buy({ Position = UDim2.fromOffset(0, 2), Size = UDim2.new(1, 0, 0, 40), Parent = holder }, "🔗 Invite friends", "green", function()
					pcall(SocialService.PromptGameInvite, SocialService, me)
				end, 18)
			end

			local byId: { [number]: any } = {}
			for _, p in (if okPlayers then here else {}) :: { any } do
				byId[p.id] = p
			end
			local online = 0
			for _, f in friends do
				if f.online then
					online += 1
				end
			end
			heading(list, nextOrder(), "Friends", if #friends > 0 then `{online} online · {#friends}` else nil)
			if #friends == 0 then
				note(list, nextOrder(), "No Roblox friends yet. Add the drivers below, or invite yours.")
			end
			local shown = 0
			for _, f in friends do
				if shown >= 40 then
					break
				end
				shown += 1
				local p = byId[f.id]
				local buttons: { Button } = {}
				local line: string
				if p then
					line = `{p.townName} · Lvl {p.level} · 🏆 {p.trophies} · in this server`
					local helpedAll = p.helped >= HELPS_PER_TOWN
					table.insert(buttons, { text = if helpedAll then "🏠 Visit" else "🤝 Visit", kind = "garage", width = 92, onClick = function()
						visit(f.id)
					end })
				elseif f.cartopia then
					line = "🟢 Playing Cartopia"
					table.insert(buttons, { text = "Join", kind = "green", width = 74, onClick = function()
						join(f.id, f.name)
					end })
				elseif f.online then
					line = "🟢 Online"
				else
					line = "Offline"
				end
				row(list, nextOrder(), { name = f.name, userId = f.id, on = f.online, line = line, badge = badge(f.id), dim = not f.online, buttons = buttons })
			end

			-- The other drivers in this server (web: "Drivers to visit").
			local others = {}
			for _, p in (if okPlayers then here else {}) :: { any } do
				if not p.friend then
					table.insert(others, p)
				end
			end
			heading(list, nextOrder(), "Drivers to visit", `tap {HELPS_PER_TOWN} shops each for coins`)
			if #others == 0 then
				note(list, nextOrder(), "Nobody else is in this server yet.")
			end
			for _, p in others do
				local helpedAll = p.helped >= HELPS_PER_TOWN
				row(list, nextOrder(), {
					name = p.name,
					userId = p.id,
					on = true,
					line = `{p.townName} · Lvl {p.level} · 🏆 {p.trophies}`,
					badge = badge(p.id),
					buttons = {
						{ text = if helpedAll then "🏠 Visit" else "🤝 Visit", kind = "garage", width = 92, onClick = function()
							visit(p.id)
						end },
						{ text = "+ 👫", kind = "garage", width = 56, onClick = function()
							addFriend(p.id)
						end },
					},
				})
			end
		end)
	end

	show = function(id: string)
		if shown == id then
			return
		end
		shown = id
		clear()
		if id == "leaders" then
			Leaders.draw(list, { row = row, heading = heading, note = note, visit = visit }, leaderState)
		else
			drawFriends()
		end
	end
	show(first)
	return overlay
end

return Friends
