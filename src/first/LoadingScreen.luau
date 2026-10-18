--!strict
-- The cover shown while the game loads, drawn like the web game's LoadingScene (ui/Loading.tsx,
-- loading.css): a sunburst over the town's green, and a gold pill with a spinning tyre saying what
-- is loading. Built from plain frames, so it needs nothing downloaded before it can show.

local LoadingScreen = {}
LoadingScreen.__index = LoadingScreen

local INK = Color3.fromHex("#14213d")
local FONT = Font.fromEnum(Enum.Font.FredokaOne)

-- loading.css: the backdrop and the sun's rings (--s1 inner to --s4 outer) by time of day.
local LOOKS = {
	day = { bg = "#3f8f3a", s = { "#fff4c9", "#ffc46b", "#ff9b5c", "#ef6f8e" }, ray = 0.8 },
	dusk = { bg = "#3f8f3a", s = { "#ffd9a3", "#ff9d6c", "#d4618f", "#6c4aa1" }, ray = 0.84 },
	night = { bg = "#18213a", s = { "#5a5fc0", "#3a3f96", "#262b6c", "#151a45" }, ray = 0.9 },
}

local RINGS = 24

local function new(class: string, props: { [string]: any }): any
	local inst = Instance.new(class)
	for k, v in props do
		if k ~= "Parent" then
			(inst :: any)[k] = v
		end
	end
	inst.Parent = props.Parent
	return inst
end

local function round(parent: Instance, radius: UDim?)
	new("UICorner", { CornerRadius = radius or UDim.new(1, 0), Parent = parent })
end

export type LoadingScreen = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		bg: Frame,
		rings: { Frame },
		rays: Frame,
		tyre: Frame,
		label: TextLabel,
		fill: Frame,
		shown: number,
		target: number,
		text: string,
	},
	LoadingScreen
))

function LoadingScreen.new(parent: Instance): LoadingScreen
	local gui = new("ScreenGui", {
		Name = "Loading",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 1000, -- over every screen of the game
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	-- Covers the whole screen and swallows taps, so nothing underneath can be pressed.
	local bg = new("TextButton", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = gui,
	})
	-- The sun: rings from the outside in (the CSS radial gradient), 120% of the shorter side.
	local sun = new("Frame", {
		Name = "Sun",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.2, 1.2),
		BackgroundTransparency = 1,
		Parent = bg,
	})
	new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height, Parent = sun })
	-- The CSS gradient runs s1 (middle) to s2 at 30%, s3 at 58% and clear at 71%; drawn here as
	-- rings from the outside in, each a step of that blend, the outer ones fading out.
	local rings = {}
	for i = 1, RINGS do
		local r = 1 - (i - 1) / RINGS -- this ring's edge, as a share of the sun's radius
		local ring = new("Frame", {
			Name = `Ring{i}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(r, r),
			BorderSizePixel = 0,
			BackgroundTransparency = if r > 0.58 then 0.35 + 0.65 * (r - 0.58) / 0.42 else 0,
			ZIndex = i,
			Parent = sun,
		})
		round(ring)
		rings[i] = ring
	end
	-- Rays: thin bars through the middle every 15 degrees (repeating-conic-gradient), faded at both
	-- ends as the CSS mask does, turning slowly.
	local rays = new("Frame", {
		Name = "Rays",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = RINGS + 1,
		Parent = sun,
	})
	for a = 0, 165, 15 do
		local ray = new("Frame", {
			Name = "Ray",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0.04, 0),
			Rotation = a,
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = RINGS + 1,
			Parent = rays,
		})
		new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.18, 0.4),
				NumberSequenceKeypoint.new(0.4, 0),
				NumberSequenceKeypoint.new(0.6, 0),
				NumberSequenceKeypoint.new(0.82, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = ray,
		})
	end

	-- The game's name, in the display font with the ink outline the web buttons use.
	local title = new("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.new(0.9, 0, 0, 96),
		BackgroundTransparency = 1,
		FontFace = FONT,
		Text = "Cartopia",
		TextSize = 88,
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 30,
		Parent = bg,
	})
	new("UIStroke", { Color = INK, Thickness = 6, Parent = title })

	-- The pill (.ls-pill): gold, ink border and drop, tyre then label, with a thin progress bar.
	local pill = new("Frame", {
		Name = "Pill",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.9, 0),
		Size = UDim2.fromOffset(330, 52),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ZIndex = 11,
		Parent = bg,
	})
	round(pill)
	new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = pill })
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.fromHex("#ffe98a"), Color3.fromHex("#ffb21a")),
		Parent = pill,
	})
	local drop = new("Frame", {
		Name = "Drop",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.9, 5),
		Size = UDim2.fromOffset(333, 55),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = bg,
	})
	round(drop)
	local tyre = new("Frame", {
		Name = "Tyre",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Color3.fromHex("#e8ecf4"),
		BorderSizePixel = 0,
		ZIndex = 12,
		Parent = pill,
	})
	round(tyre)
	new("UIStroke", { Color = INK, Thickness = 5, Parent = tyre })
	-- Spokes and a hub, so the tyre is seen turning.
	for a = 0, 135, 45 do
		new("Frame", {
			Name = "Spoke",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, 3),
			Rotation = a,
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromHex("#c3cad8"),
			ZIndex = 12,
			Parent = tyre,
		})
	end
	local hub = new("Frame", {
		Name = "Hub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.4, 0.4),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 13,
		Parent = tyre,
	})
	round(hub)
	local label = new("TextLabel", {
		Name = "Label",
		Position = UDim2.new(0, 52, 0, 4),
		Size = UDim2.new(1, -66, 1, -16),
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextSize = 21,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "Loading…",
		ZIndex = 12,
		Parent = pill,
	})
	local track = new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 52, 1, -8),
		Size = UDim2.new(1, -74, 0, 6),
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
		ZIndex = 12,
		Parent = pill,
	})
	round(track)
	local fill = new("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 13,
		Parent = track,
	})
	round(fill)

	local self = setmetatable({
		gui = gui,
		bg = bg :: any,
		rings = rings,
		rays = rays,
		tyre = tyre,
		label = label,
		fill = fill,
		shown = 0,
		target = 0,
		text = "Loading",
	}, LoadingScreen)
	self:tint("day")
	gui.Parent = parent
	return self
end

-- Day, dusk or night colours, as the web picks from the town clock.
function LoadingScreen.tint(self: LoadingScreen, tod: string)
	local look = LOOKS[tod] or LOOKS.day
	local s = {}
	for i, h in look.s do
		s[i] = Color3.fromHex(h)
	end
	self.bg.BackgroundColor3 = Color3.fromHex(look.bg)
	for i, ring in self.rings do
		local r = 1 - (i - 1) / RINGS
		ring.BackgroundColor3 = if r <= 0.3
			then s[1]:Lerp(s[2], r / 0.3)
			elseif r <= 0.58 then s[2]:Lerp(s[3], (r - 0.3) / 0.28)
			else s[3]:Lerp(s[4], (r - 0.58) / 0.42)
	end
	for _, ray in self.rays:GetChildren() do
		(ray :: Frame).BackgroundTransparency = look.ray
	end
end

-- What is loading now, and how far along everything is (0 to 1). The bar eases towards it.
function LoadingScreen.set(self: LoadingScreen, text: string, progress: number)
	self.text = text
	self.target = math.max(self.target, math.clamp(progress, 0, 1))
	self.label.Text = `{text}… {math.floor(self.target * 100 + 0.5)}%`
end

-- One frame of motion: the tyre spins (0.8 s a turn), the rays turn (60 s), the bar catches up.
function LoadingScreen.step(self: LoadingScreen, dt: number)
	self.tyre.Rotation = (self.tyre.Rotation + dt * 450) % 360
	self.rays.Rotation = (self.rays.Rotation + dt * 6) % 360
	self.shown += (self.target - self.shown) * math.min(1, dt * 6)
	self.fill.Size = UDim2.fromScale(self.shown, 1)
end

return LoadingScreen
