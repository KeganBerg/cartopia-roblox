--!strict
-- Visiting another player's town, as the web game's VisitBanner and HelpBadges (ui/Friends.tsx,
-- ui/Badges.tsx): the banner along the bottom ("Visiting <town>", their level, trophies and cars,
-- the help meter, + Friend and Home) in place of the bottom bar, a help bubble over each business
-- asking for a hand today (a tick once helped), and the countryside round their town.
--
-- Driving onto someone's plot in the shared world makes it a visit: the server sets the player's
-- "Visiting" attribute (server/init's plot watch) and this asks for the town's details; Visit in
-- the Friends menu drives you over and hands them in with ctx.setVisit. Tapping a bubble, or the
-- building itself, helps there. Home takes you back to the view over your own town.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Ui = require(script.Parent.Parent.Ui)
local Remote = require(script.Parent.Parent.Remote)
local TownCamera = require(script.Parent.Parent.TownCamera)
local Countryside = require(script.Parent.Parent.Countryside)
local Builder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Models"):WaitForChild("Builder"))

local Visit = {}

local HELPS_PER_TOWN = 5

-- How you lend a hand at each kind of business: the bubble's icon (game/help.ts helpAct).
local ACTS: { { any } } = {
	{ { "wash" }, "🧽" },
	{ { "tires", "lube", "bodyshop", "tuner", "parts", "muffler", "brakes", "wraps", "dynolab", "engines", "racefab" }, "🔧" },
	{ { "gas" }, "⛽" },
	{ { "pizza", "burger", "donut", "icecream", "diner", "tacos", "hotdog", "coffee" }, "🍔" },
	{ { "cinema", "bowling", "arcade", "club", "stadium", "minigolf", "funfair", "waterpark", "haunted" }, "🎟️" },
	{ { "pool" }, "🛟" },
	{ { "laundry" }, "🧺" },
	{ { "vet" }, "🐾" },
	{ { "postoffice" }, "📮" },
	{ { "library" }, "📚" },
	{ { "busdepot" }, "🚌" },
	{ { "cityhall" }, "📋" },
	{ { "motel", "hotel" }, "🛏️" },
	{ { "school", "academy", "university" }, "📚" },
	{ { "hospital", "firehouse", "police" }, "🩹" },
	{ { "market" }, "🛒" },
	{ { "offices", "hq", "glasstower", "helipad" }, "📋" },
}
local function actIcon(def: string): string
	for _, act in ACTS do
		for _, word in act[1] do
			if string.find(def, word, 1, true) then
				return act[2]
			end
		end
	end
	return "🧹"
end

local function helpedList(): { string }
	local out = {}
	local raw = Players.LocalPlayer:GetAttribute("Helped")
	if type(raw) == "string" then
		for uid in raw:gmatch("[^,]+") do
			table.insert(out, uid)
		end
	end
	return out
end

-- The town folder (Workspace.Towns) of the player with this user id.
local function townOf(userId: number): Folder?
	local towns = workspace:FindFirstChild("Towns")
	if towns then
		for _, f in towns:GetChildren() do
			if f:GetAttribute("Owner") == userId then
				return f :: Folder
			end
		end
	end
	return nil
end

function Visit.start(ctx: any)
	local me = Players.LocalPlayer
	local town: any = nil
	local scenery: Instance? = nil
	local bubbles: Folder? = nil
	local banner: Frame? = nil
	local meter: { pips: { Frame }, label: TextLabel, box: Frame }? = nil

	local function clear()
		for _, inst in { scenery, bubbles, banner } :: { Instance? } do
			if inst then
				inst:Destroy()
			end
		end
		scenery, bubbles, banner, meter = nil, nil, nil, nil
	end

	local setVisit: (any?) -> ()

	local function help(uid: string)
		Remote.social("help", uid)
	end

	-- The banner along the bottom of the screen (web .visit-banner).
	local function drawBanner()
		local w = 640
		local shadow, face = Ui.shadowed({ Name = "VisitBanner", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(w, 64), Parent = ctx.gui }, { radius = 18, stroke = 3, drop = 5, dark = 0.3, color = Ui.SHEET })
		banner = shadow
		local title = `Visiting {town.townName}`
		Ui.text({ Text = title, TextSize = 18, TextColor3 = Ui.INK, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, 9), Size = UDim2.fromOffset(250, 24), Parent = face })
		local host = Players:GetPlayerByUserId(town.host)
		local who = if host then `{host.DisplayName} · ` else ""
		Ui.text({ Text = `{who}Lvl {town.level} · 🏆 {town.trophies} · {town.cars} cars`, Body = true, TextSize = 13, TextColor3 = Color3.fromHex("#607d8b"), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, 33), Size = UDim2.fromOffset(250, 18), Parent = face })
		local row = Ui.new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, -1), Size = UDim2.fromOffset(w - 280, 40), BackgroundTransparency = 1, Parent = face }, {
			Ui.new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Right, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		-- The help meter: a pip per help today, green once done.
		local box = Ui.new("Frame", { Name = "HelpMeter", LayoutOrder = 1, Size = UDim2.fromOffset(120, 30), BackgroundColor3 = Color3.fromHex("#e8f5e9"), Parent = row }, {
			Ui.corner(12),
			Ui.stroke(2, Color3.fromHex("#a5d6a7")),
		})
		local pips = {}
		for i = 1, HELPS_PER_TOWN do
			table.insert(pips, Ui.new("Frame", { Position = UDim2.fromOffset(8 + (i - 1) * 11, 11), Size = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.fromHex("#c8e6c9"), Parent = box }, { Ui.round() }))
		end
		local label = Ui.text({ Text = "", TextSize = 14, TextColor3 = Color3.fromHex("#1b5e20"), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(66, 0), Size = UDim2.new(1, -68, 1, 0), Parent = box })
		meter = { pips = pips, label = label, box = box }
		local okFriend, isFriend = pcall(function()
			return host ~= nil and me:IsFriendsWith(town.host)
		end)
		if host and okFriend and not isFriend then
			Ui.buy({ LayoutOrder = 2, Size = UDim2.fromOffset(56, 34), Parent = row }, "+ 👫", "garage", function()
				pcall(function()
					StarterGui:SetCore("PromptSendFriendRequest", host)
				end)
			end, 15)
		end
		Ui.buy({ LayoutOrder = 3, Size = UDim2.fromOffset(96, 34), Parent = row }, "🏠 Home", "garage", function()
			-- Back to the town view over their own town (which takes them home), or just home.
			if TownCamera.isWalking() then
				TownCamera.setWalking(false)
				setVisit(nil)
			elseif Remote.social("home") then
				setVisit(nil)
			end
		end, 15)
	end

	local function refreshMeter()
		if not meter or not town then
			return
		end
		local n = #helpedList()
		local left = if town.dayFull then 0 else math.max(0, HELPS_PER_TOWN - n)
		for i, p in meter.pips do
			p.BackgroundColor3 = if i <= n then Color3.fromHex("#43a047") else Color3.fromHex("#c8e6c9")
		end
		Ui.setText(meter.label, if left > 0 then `🤝 {left}` else "🤝 ✔")
		meter.box.BackgroundColor3 = if left > 0 then Color3.fromHex("#e8f5e9") else Color3.fromHex("#c8e6c9")
	end

	-- Help bubbles over the asking businesses (and a tick over the ones helped).
	local made: { [string]: { gui: BillboardGui, help: GuiObject, done: GuiObject } } = {}
	local function refreshBubbles()
		if not bubbles or not town then
			return
		end
		local f = townOf(town.host)
		local list = f and f:FindFirstChild("Buildings")
		if not list then
			return
		end
		local done: { [string]: boolean } = {}
		for _, uid in helpedList() do
			done[uid] = true
		end
		local left = not town.dayFull and #helpedList() < HELPS_PER_TOWN
		for _, uid in town.asking do
			local m = list:FindFirstChild(uid)
			local b = made[uid]
			if m and m:IsA("Model") and not b then
				local gui = Ui.new("BillboardGui", {
					Name = "Help",
					Adornee = m.PrimaryPart or m,
					AlwaysOnTop = true,
					Active = true,
					LightInfluence = 0,
					Size = UDim2.fromOffset(44, 44),
					StudsOffsetWorldSpace = Vector3.new(0, ((m:GetAttribute("Height") :: number?) or 10) + 4, 0),
					MaxDistance = 900,
					ResetOnSpawn = false,
					Parent = bubbles,
				})
				local helpShadow, helpFace = Ui.button({ Name = "Ask", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(34, 34), Parent = gui }, "white", function()
					help(uid)
				end, { radius = 17, stroke = 3, drop = 3, flat = true, strokeColor = Ui.WHITE })
				Ui.gradient("#f1fff4", "#b9f6ca").Parent = helpFace
				Ui.text({ Text = actIcon(tostring(m:GetAttribute("Def") or "")), TextSize = 18, Size = UDim2.fromScale(1, 1), Parent = helpFace })
				local tick = Ui.new("Frame", { Name = "Done", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = Color3.fromHex("#2e7d32"), BackgroundTransparency = 0.15, Parent = gui }, {
					Ui.round(),
					Ui.stroke(2, Ui.WHITE),
					Ui.text({ Text = "✔", TextSize = 12, Size = UDim2.fromScale(1, 1) }),
				})
				b = { gui = gui, help = helpShadow, done = tick }
				made[uid] = b
			end
			if b then
				b.help.Visible = not done[uid] and left
				b.done.Visible = done[uid] == true
				b.gui.Enabled = done[uid] == true or left
			end
		end
	end

	function setVisit(info: any?)
		clear()
		made = {}
		town = info
		ctx.visiting = info
		if not info then
			return
		end
		drawBanner()
		refreshMeter()
		bubbles = Ui.new("Folder", { Name = "HelpBadges", Parent = me:WaitForChild("PlayerGui") })
		refreshBubbles()
		-- Their countryside: the forest ring, wild plots and town line, as round your own town.
		task.spawn(function()
			local f: Folder? = nil
			for _ = 1, 40 do
				f = townOf(info.host)
				if f then
					break
				end
				task.wait(0.25)
			end
			if not f or town ~= info then
				return
			end
			Builder.useLibrary(60)
			local holder = Instance.new("Folder")
			holder.Name = "VisitScenery"
			holder.Parent = workspace
			scenery = holder
			Countryside.draw(f:GetAttribute("Origin") :: any, holder)({ land = info.land, roads = info.roads })
		end)
	end
	ctx.setVisit = setVisit

	me:GetAttributeChangedSignal("Visiting"):Connect(function()
		local host = me:GetAttribute("Visiting")
		if host == nil then
			if town then
				setVisit(nil)
			end
		elseif not town or town.host ~= host then
			-- Drove into their town: ask for its details.
			local ok, info = Remote.social("town", host, true)
			if ok and me:GetAttribute("Visiting") == host then
				setVisit(info)
			end
		end
	end)
	me:GetAttributeChangedSignal("Helped"):Connect(function()
		refreshMeter()
		refreshBubbles()
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			if town then
				refreshBubbles()
			end
		end
	end)
end

return Visit
