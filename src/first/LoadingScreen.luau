--!strict
-- The loading screen, drawn as the web game's own (scripts/splash/build.mjs in the web repo): the
-- town in this season and time of day, slowly panning; the sunburst panel with the "Cartopia"
-- wordmark popping in, the tag line and the loading pill, its gold bar filling up; and the player's
-- own race car in their paint parking in front, bobbing, then driving off when the game is ready.
--
-- The pictures are the web's, uploaded by tools/splash/build.mjs (SplashImages). Each one shows
-- once it has downloaded; until then (or if it was never uploaded) a stand-in drawn from frames
-- takes its place, so the screen is never blank.

local TweenService = game:GetService("TweenService")

local Images = require(script.Parent:WaitForChild("SplashImages")) :: any

local LoadingScreen = {}
LoadingScreen.__index = LoadingScreen

local INK = Color3.fromHex("#14213d")
local FONT = Font.fromEnum(Enum.Font.FredokaOne)
local HERO_W = 572 -- the Hot Shot's render width; other cars scale against it, as on the web
local WORDMARK_AR = 1150 / 4070 -- height over width of the wordmark's picture
local SETTLE = 2 -- seconds before the layout stays as it is (see LoadingScreen.centred)

-- The page colour and the stand-in sun's colours by time of day (the web's --s1..--s4).
local LOOKS = {
	day = { bg = "#3f8f3a", s = { "#fff4c9", "#ffc46b", "#ff9b5c", "#ef6f8e" } },
	dusk = { bg = "#3f8f3a", s = { "#ffd9a3", "#ff9d6c", "#d4618f", "#6c4aa1" } },
	night = { bg = "#18213a", s = { "#5a5fc0", "#3a3f96", "#262b6c", "#151a45" } },
}
-- Where the web scatters its night stars, as shares of the sun's side of the screen.
local STARS = { { 0.22, 0.7, 2 }, { 0.34, 0.58, 2 }, { 0.48, 0.8, 1.5 }, { 0.64, 0.62, 2 }, { 0.76, 0.76, 1.5 }, { 0.58, 0.88, 2 }, { 0.12, 0.52, 1.5 }, { 0.86, 0.6, 2 } }

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

local function clamp(x: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, x))
end

-- CSS's cubic-bezier(x1, y1, x2, y2) easing at time t (0 to 1), solved for x by bisection.
local function bezier(x1: number, y1: number, x2: number, y2: number, t: number): number
	local function at(a: number, b: number, s: number): number
		return 3 * a * s * (1 - s) ^ 2 + 3 * b * s ^ 2 * (1 - s) + s ^ 3
	end
	local lo, hi = 0, 1
	for _ = 1, 20 do
		local mid = (lo + hi) / 2
		if at(x1, x2, mid) < t then
			lo = mid
		else
			hi = mid
		end
	end
	return at(y1, y2, (lo + hi) / 2)
end

local function easeInOut(t: number): number
	return (1 - math.cos(math.pi * clamp(t, 0, 1))) / 2
end

-- A picture from SplashImages: hidden until it has loaded.
local function picture(props: { [string]: any }): ImageLabel
	props.BackgroundTransparency = 1
	props.ImageTransparency = 1
	props.Image = ""
	props.ImageColor3 = Color3.new(1, 1, 1)
	return new("ImageLabel", props)
end

export type Options = {
	-- The content string for an uploaded image id (the server may have found its image's own id;
	-- see Loading.client), and whether it's surely an image's (not a decal's, which shows nothing).
	-- Defaults to rbxassetid://<id>.
	content: ((id: number) -> (string, boolean?))?,
	-- Whether an image has downloaded. Defaults to ImageLabel.IsLoaded.
	isLoaded: ((image: ImageLabel) -> boolean)?,
	-- The screen's size in pixels, for previews outside Roblox. Defaults to the ScreenGui's.
	size: Vector2?,
}

export type LoadingScreen = typeof(setmetatable(
	{} :: {
		gui: ScreenGui,
		root: Frame,
		scale: UIScale,
		parts: { [string]: any },
		opts: Options,
		tod: string,
		model: string?,
		paint: Color3,
		progress: number,
		shownProgress: number,
		text: string,
		clock: number,
		carSince: number?,
		goSince: number?,
		w: number,
		h: number,
		box: { [string]: Rect },
		tagY: { number },
		fading: boolean,
		-- Each picture's content string: whether it has downloaded (false while it's on its way),
		-- and the ones that are surely images.
		fetched: { [string]: boolean },
		sure: { [string]: boolean },
		-- A wide screen whose town picture isn't in yet stacks everything down the middle instead
		-- of in the web's left panel, which looked broken beside a bare background. Settled
		-- (locked) once the town arrives or after a moment, so the screen doesn't jump about later.
		centred: boolean,
		locked: boolean,
	},
	LoadingScreen
))

function LoadingScreen.new(parent: Instance, opts: Options?): LoadingScreen
	local gui = new("ScreenGui", {
		Name = "Loading",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 1000, -- over every screen of the game
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	-- Covers the whole screen and swallows taps, so nothing underneath can be pressed.
	local root = new("TextButton", {
		Name = "Cover",
		Size = UDim2.fromScale(1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ClipsDescendants = true,
		Parent = gui,
	})
	local scale = new("UIScale", { Parent = root })
	local p: { [string]: any } = {}

	p.town = picture({ Name = "Town", ScaleType = Enum.ScaleType.Crop, ZIndex = 1, Parent = root })
	p.vignette = picture({ Name = "Edge", Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch, ZIndex = 2, Parent = root })
	-- The sun: the web's picture, or until it loads a rounded panel in its colours.
	p.sunStandIn = new("Frame", { Name = "SunStandIn", BorderSizePixel = 0, BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3, Parent = root })
	round(p.sunStandIn)
	p.sunGradient = new("UIGradient", { Parent = p.sunStandIn })
	p.sun = picture({ Name = "Sun", ScaleType = Enum.ScaleType.Stretch, ZIndex = 4, Parent = root })
	p.stars = {}
	for i, s in STARS do
		local star = new("Frame", {
			Name = `Star{i}`,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(s[3] * 2, s[3] * 2),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 5,
			Parent = root,
		})
		round(star)
		p.stars[i] = star
	end

	-- The wordmark, or the name in the display font until it loads.
	p.wordmark = picture({ Name = "Wordmark", AnchorPoint = Vector2.new(0.5, 0.5), ScaleType = Enum.ScaleType.Fit, ZIndex = 20, Parent = root })
	p.wordmarkScale = new("UIScale", { Parent = p.wordmark })
	p.title = new("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		FontFace = FONT,
		Text = "Cartopia",
		TextColor3 = Color3.new(1, 1, 1),
		ZIndex = 20,
		Parent = root,
	})
	p.titleScale = new("UIScale", { Parent = p.title })
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("#fff8d6")),
			ColorSequenceKeypoint.new(0.45, Color3.fromHex("#ffe066")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("#ffaa1a")),
		}),
		Parent = p.title,
	})
	p.titleStroke = new("UIStroke", { Color = INK, Thickness = 6, LineJoinMode = Enum.LineJoinMode.Round, Parent = p.title })

	-- The tag line: white with an ink outline and a drop, one line each.
	p.tag = {}
	for i, line in { "Build your town", "Collect cars", "Race your friends" } do
		local l = new("TextLabel", {
			Name = `Tag{i}`,
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			FontFace = FONT,
			Text = line,
			TextColor3 = Color3.new(1, 1, 1),
			ZIndex = 21,
			Parent = root,
		})
		new("UIStroke", { Color = INK, Thickness = 2.5, LineJoinMode = Enum.LineJoinMode.Round, Parent = l })
		local drop = new("TextLabel", {
			Name = `TagDrop{i}`,
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			FontFace = FONT,
			Text = line,
			TextColor3 = INK,
			ZIndex = 20,
			Parent = root,
		})
		new("UIStroke", { Color = INK, Thickness = 2.5, LineJoinMode = Enum.LineJoinMode.Round, Parent = drop })
		p.tag[i] = { l, drop }
	end

	-- The car: its render, its paint layer tinted with the player's paint, and a soft shadow.
	p.car = new("Frame", { Name = "Car", AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1, ZIndex = 10, Parent = root })
	p.shadow = new("Frame", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.88),
		Size = UDim2.fromScale(0.96, 0.24),
		BackgroundColor3 = Color3.fromHex("#0a0e1e"),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 10,
		Parent = p.car,
	})
	round(p.shadow)
	p.shadowFade = new("UIGradient", {
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.25, 0.55),
			NumberSequenceKeypoint.new(0.5, 0.4),
			NumberSequenceKeypoint.new(0.75, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = p.shadow,
	})
	p.body = picture({ Name = "Body", Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch, ZIndex = 11, Parent = p.car })
	p.paint = picture({ Name = "Paint", Size = UDim2.fromScale(1, 1), ScaleType = Enum.ScaleType.Stretch, ZIndex = 12, Parent = p.body })

	-- The pill (.ld): an amber body that the gold bar fills, a spinning tyre and the label.
	p.pillDrop = new("Frame", { Name = "PillDrop", BackgroundColor3 = INK, BorderSizePixel = 0, ZIndex = 29, Parent = root })
	round(p.pillDrop)
	p.pill = new("Frame", {
		Name = "Pill",
		BackgroundColor3 = Color3.fromHex("#c9790e"),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 30,
		Parent = root,
	})
	round(p.pill)
	new("UIStroke", { Color = INK, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = p.pill })
	p.fill = new("Frame", { Name = "Fill", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 31, Parent = p.pill })
	round(p.fill)
	new("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromHex("#fff6c4")),
			ColorSequenceKeypoint.new(0.12, Color3.fromHex("#ffe98a")),
			ColorSequenceKeypoint.new(1, Color3.fromHex("#ffb21a")),
		}),
		Parent = p.fill,
	})
	p.tyre = new("Frame", {
		Name = "Tyre",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(26, 26),
		BackgroundColor3 = Color3.fromHex("#e8ecf4"),
		BorderSizePixel = 0,
		ZIndex = 33,
		Parent = p.pill,
	})
	round(p.tyre)
	new("UIStroke", { Color = INK, Thickness = 5, Parent = p.tyre })
	for a = 0, 135, 45 do
		new("Frame", {
			Name = "Spoke",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, 4),
			Rotation = a,
			BorderSizePixel = 0,
			BackgroundColor3 = Color3.fromHex("#c3cad8"),
			ZIndex = 33,
			Parent = p.tyre,
		})
	end
	local hub = new("Frame", {
		Name = "Hub",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.36, 0.36),
		BackgroundColor3 = INK,
		BorderSizePixel = 0,
		ZIndex = 34,
		Parent = p.tyre,
	})
	round(hub)
	p.label = new("TextLabel", {
		Name = "Label",
		BackgroundTransparency = 1,
		FontFace = FONT,
		TextSize = 20,
		TextColor3 = INK,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = "",
		ZIndex = 33,
		Parent = p.pill,
	})

	local self = setmetatable({
		gui = gui,
		root = root :: any,
		scale = scale,
		parts = p,
		opts = opts or {},
		tod = "day",
		model = nil,
		paint = Color3.fromHex("#d32f2f"),
		progress = 0.06,
		shownProgress = 0.06,
		text = "Loading your town…",
		clock = 0,
		carSince = nil,
		goSince = nil,
		w = 0,
		h = 0,
		box = {},
		tagY = {},
		fading = false,
		fetched = {},
		sure = {},
		centred = true,
		locked = false,
	}, LoadingScreen)
	self:setTime("day")
	self:set(self.text, self.progress)
	gui.Parent = parent
	return self
end

function LoadingScreen._content(self: LoadingScreen, id: number): string
	if id == 0 then
		return ""
	end
	if self.opts.content then
		local content, sure = self.opts.content(id)
		if sure then
			self.sure[content] = true
		end
		return content
	end
	return `rbxassetid://{id}`
end

function LoadingScreen._loaded(self: LoadingScreen, image: ImageLabel): boolean
	if image.Image == "" then
		return false
	end
	if self.opts.isLoaded then
		return self.opts.isLoaded(image)
	end
	local content = image.Image
	return image.IsLoaded or (self.fetched[content] == true and self.sure[content] == true)
end

-- Downloads a picture, noting when it's in. ImageLabel.IsLoaded alone wasn't enough: a picture
-- waiting unseen (fully transparent) may never be fetched, and its content changes when the
-- server finds the image inside an uploaded decal.
function LoadingScreen._fetch(self: LoadingScreen, content: string)
	if content == "" or self.fetched[content] ~= nil or self.opts.isLoaded then
		return
	end
	self.fetched[content] = false
	task.spawn(function()
		local ContentProvider = game:GetService("ContentProvider")
		pcall(ContentProvider.PreloadAsync, ContentProvider, { content }, function(_, status)
			if status == Enum.AssetFetchStatus.Success then
				self.fetched[content] = true
			end
		end)
		if self.fetched[content] ~= true then
			-- Try again when it's asked for next (refreshImages).
			self.fetched[content] = nil
		end
	end)
end

-- Points every picture at its image (again, after the server finds an image's own id).
function LoadingScreen.refreshImages(self: LoadingScreen)
	local p = self.parts
	local kind = if self.w >= self.h then "wide" else "tall"
	local function set(image: ImageLabel, id: number, key: string)
		local content = self:_content(id)
		if image.Image ~= content then
			image.Image = content
		end
		self:_fetch(content)
		-- Which picture it is, for the preview tools (tools/emulate/render.mjs).
		image:SetAttribute("Key", key)
	end
	set(p.town, Images.town[self.tod][kind], `town-{self.tod}-{kind}`)
	set(p.sun, Images.sun[self.tod][kind], `sun-{self.tod}-{kind}`)
	set(p.vignette, Images.vignette, "vignette")
	set(p.wordmark, Images.wordmark, "wordmark")
	local car = self.model and Images.cars[self.model]
	set(p.body, if car then car.car else 0, `car-{self.model}`)
	set(p.paint, if car then car.paint else 0, `paint-{self.model}`)
end

-- Every image the screen shows, for ContentProvider:PreloadAsync.
function LoadingScreen.images(self: LoadingScreen): { Instance }
	local p = self.parts
	return { p.town, p.sun, p.vignette, p.wordmark, p.body, p.paint }
end

-- Day, dusk or night: the town render, the sun and the stars change with the town clock.
function LoadingScreen.setTime(self: LoadingScreen, tod: string)
	local look = LOOKS[tod] or LOOKS.day
	self.tod = if LOOKS[tod] then tod else "day"
	self.root.BackgroundColor3 = Color3.fromHex(look.bg)
	local s = {}
	for i, h in look.s do
		s[i] = Color3.fromHex(h)
	end
	self.parts.sunGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, s[3]),
		ColorSequenceKeypoint.new(0.5, s[2]),
		ColorSequenceKeypoint.new(1, s[3]),
	})
	for _, star in self.parts.stars do
		star.Visible = self.tod == "night"
	end
	self:refreshImages()
end

-- The player's race car (a CARS id) and its paint. A car without a render shows the Hot Shot.
function LoadingScreen.setCar(self: LoadingScreen, model: string?, paint: string?)
	if not (model and Images.cars[model] and Images.cars[model].car ~= 0) then
		model = "hotshot"
	end
	if paint and string.match(paint, "^#%x%x%x%x%x%x$") then
		self.paint = Color3.fromHex(paint)
	end
	if model ~= self.model then
		self.model = model
		self.carSince = nil
		self.box = {}
	end
	self:refreshImages()
end

-- What is loading now, and how far along everything is (0 to 1). The bar eases towards it.
function LoadingScreen.set(self: LoadingScreen, text: string, progress: number)
	self.text = text
	self.progress = math.max(self.progress, clamp(progress, 0, 1))
	self.parts.label.Text = text
	self.box = {} -- the pill's width follows its label
end

local function textWidth(text: string, size: number): number
	local ok, v = pcall(function()
		return game:GetService("TextService"):GetTextSize(text, size, Enum.Font.FredokaOne, Vector2.new(2000, 200)).X
	end)
	return if ok and v and v > 0 then v else #text * size * 0.55
end

-- Lays everything out for a w by h screen, as the web's CSS does for wide and tall screens.
function LoadingScreen._layout(self: LoadingScreen, w: number, h: number)
	local p = self.parts
	local kindChanged = (self.w >= self.h) ~= (w >= h)
	-- Centred: a wide screen laid out down the middle (see LoadingScreen.centred).
	local centred = w >= h and self.centred
	local wide = w >= h and not centred
	self.w, self.h = w, h
	local box: { [string]: Rect } = {}

	-- The sun panel, and its picture with the margin round it for the rim and glow.
	local sx, sy, sw, sh
	if centred then
		sx, sy, sw, sh = -0.1 * w, -0.45 * h, 1.2 * w, 1.05 * h
	elseif wide then
		sx, sy, sw, sh = -0.24 * w, -0.3 * h, 0.7 * w, 1.6 * h
	else
		sx, sy, sw, sh = -0.3 * w, -0.24 * h, 1.6 * w, 0.7 * h
	end
	p.sunStandIn.Position = UDim2.fromOffset(sx, sy)
	p.sunStandIn.Size = UDim2.fromOffset(sw, sh)
	p.sunGradient.Rotation = if wide then 0 else 90
	local pad = Images.PAD
	p.sun.Position = UDim2.fromOffset(sx - sw * pad, sy - sh * pad)
	p.sun.Size = UDim2.fromOffset(sw * (1 + 2 * pad), sh * (1 + 2 * pad))
	for i, s in STARS do
		local rx, rw = 0, if wide then w * 0.5 else w
		p.stars[i].Position = UDim2.fromOffset(rx + s[1] * rw, s[2] * h * (if wide then 1 else 0.55))
	end

	-- Wordmark, tag line and pill, stacked.
	local wmw = if centred
		then math.min(0.4 * w, 520, 0.22 * h / WORDMARK_AR)
		elseif wide then math.min(0.36 * w, 520)
		else math.min(0.8 * w, 560)
	local fs = if centred
		then clamp(0.03 * h, 15, 26)
		elseif wide then clamp(0.021 * w, 18, 30)
		else clamp(0.046 * w, 15, 24)
	local cx = if wide then 0.23 * w else 0.5 * w
	local top = if centred then 0.07 * h elseif wide then 0.15 * h else 0.06 * h
	local wmh = wmw * WORDMARK_AR
	box.wordmark = Rect.new(cx - wmw / 2, top, cx + wmw / 2, top + wmh)
	local tagTop = if centred then top + wmh + 0.02 * h else top + wmw * (if wide then 0.32 else 0.3)
	local tagHidden = (w >= h and h <= 520) or (w < h and h <= 640)
	local tagW = if wide then 0.46 * w else w
	local tagCx = tagW / 2
	for i, pair in p.tag do
		self.tagY[i] = tagTop + (i - 1) * fs * 1.25
		for j, l in pair do
			l.Visible = not tagHidden
			l.TextSize = fs
			l.Size = UDim2.fromOffset(tagW, fs * 1.25)
			l.Position = UDim2.fromOffset(tagCx, self.tagY[i] + (if j == 2 then 3 else 0))
		end
	end

	local labelW = textWidth(self.text, 20)
	local pw, ph = 16 + 26 + 10 + labelW + 26, 50
	local pillTop
	if wide then
		pillTop = if tagHidden then tagTop + 12 else tagTop + fs * 4.6
		box.pill = Rect.new(cx - pw / 2, pillTop, cx + pw / 2, pillTop + ph)
	else
		pillTop = h - (if centred then 0.07 else 0.06) * h - ph
		box.pill = Rect.new(w / 2 - pw / 2, pillTop, w / 2 + pw / 2, pillTop + ph)
	end
	p.pill.Position = UDim2.fromOffset(box.pill.Min.X, box.pill.Min.Y)
	p.pill.Size = UDim2.fromOffset(pw, ph)
	p.pillDrop.Position = UDim2.fromOffset(box.pill.Min.X - 1.5, box.pill.Min.Y + 5)
	p.pillDrop.Size = UDim2.fromOffset(pw + 3, ph + 1.5)
	p.tyre.Position = UDim2.fromOffset(16 + 13, ph / 2)
	p.label.Position = UDim2.fromOffset(16 + 26 + 10, 0)
	p.label.Size = UDim2.fromOffset(labelW + 8, ph)

	-- The car, centred in the space under the pill (wide) or below the tag line (tall).
	local car = self.model and Images.cars[self.model]
	local cw0, ch0 = if car then car.w else HERO_W, if car then car.h else 438
	local k = clamp(cw0 / HERO_W, 0.8, 1.25)
	local ar = ch0 / cw0
	local cw, ctop, ccx
	if centred then
		-- In the gap between the tag line and the pill.
		local above = if tagHidden then top + wmh + 0.04 * h else tagTop + fs * 3.75 + 0.03 * h
		local below = pillTop - 0.04 * h
		cw = math.min(math.min(0.36 * w, 460) * k, (below - above) / ar)
		ctop = above + (below - above - cw * ar) / 2
		ccx = 0.5 * w
	elseif wide then
		local ldb = if tagHidden then top + wmw * 0.32 + 76 else tagTop + fs * 4.6 + 64
		local cmax = if tagHidden then math.min(0.22 * w, 300) else math.min(0.3 * w, 460)
		cw = math.min(cmax * k, (h - ldb - 0.08 * h) / ar)
		ctop = ldb + (h - ldb - cw * ar) / 2
		ccx = 0.24 * w
	else
		cw = math.min(0.76 * w, 340) * k
		ctop = (if tagHidden then 0.3 else 0.37) * h
		ccx = 0.5 * w
	end
	box.car = Rect.new(ccx - cw / 2, ctop, ccx + cw / 2, ctop + cw * ar)
	self.box = box
	if kindChanged then
		self:refreshImages()
	end
end

-- One frame: lays out (when the screen size or label changed) and moves everything.
function LoadingScreen.step(self: LoadingScreen, dt: number)
	self.clock += dt
	local t = self.clock
	local p = self.parts
	local size = self.opts.size or self.gui.AbsoluteSize
	local w, h = size.X, size.Y
	if w <= 0 or h <= 0 then
		local cam = workspace.CurrentCamera
		w, h = if cam then cam.ViewportSize.X else 1280, if cam then cam.ViewportSize.Y else 800
	end
	-- The web's layout once the town picture is in; down the middle until then, settled after a
	-- moment either way.
	if not self.locked then
		local townIn = self:_loaded(p.town)
		if townIn or self.clock > SETTLE then
			self.locked = true
		end
		if self.centred == townIn then
			self.centred = not townIn
			self.box = {}
		end
	end
	if w ~= self.w or h ~= self.h or not self.box.pill or not self.box.car then
		self:_layout(w, h)
	end
	local box = self.box

	-- Pictures fade in as they arrive; their stand-ins step aside.
	local function show(image: ImageLabel, target: number?)
		local want = if self:_loaded(image) then (target or 0) else 1
		image.ImageTransparency += (want - image.ImageTransparency) * math.min(1, dt * 6)
		return image.ImageTransparency < 0.99
	end
	-- While the screen fades away (finish) only the car still moves.
	local fading = self.fading
	if not fading then
		show(p.vignette)
		if self.centred and w >= h then
			-- The sun picture is drawn for the web's shapes; the stand-in fits this one.
			p.sun.ImageTransparency = 1
		else
			show(p.sun)
		end
		p.sunStandIn.BackgroundTransparency = math.clamp(1 - p.sun.ImageTransparency, 0, 1)
		show(p.town)
	end

	-- The town pans back and forth (40 s each way), slightly zoomed so its edges never show.
	local pan = easeInOut((t / 40) % 2 <= 1 and (t / 40) % 1 or 1 - (t / 40) % 1)
	local tw, th = w * 1.08 * 1.1, h * 1.08 * 1.1
	local dx, dy = (-0.03 + 0.06 * pan) * tw, (0.015 - 0.03 * pan) * th
	p.town.Size = UDim2.fromOffset(tw, th)
	p.town.Position = UDim2.fromOffset((w - tw) / 2 + dx, (h - th) / 2 + dy)

	-- Stars twinkle (3 s).
	for i, star in p.stars do
		star.BackgroundTransparency = 0.6 * (0.5 + 0.5 * math.sin(t * math.pi / 3 + i))
	end

	-- The wordmark pops in (0.7 s, overshooting).
	local wm = box.wordmark
	local pop = clamp(t / 0.7, 0, 1)
	local popScale = 0.6 + 0.4 * bezier(0.2, 1.6, 0.4, 1, pop)
	for _, g in { p.wordmark, p.title } do
		g.Position = UDim2.fromOffset((wm.Min.X + wm.Max.X) / 2, (wm.Min.Y + wm.Max.Y) / 2)
		g.Size = UDim2.fromOffset(wm.Width, wm.Height)
	end
	p.title.TextSize = math.floor(wm.Height * 0.75)
	p.wordmarkScale.Scale = popScale
	p.titleScale.Scale = popScale
	if fading then
		return self:_moveCar(t, w, h)
	end
	local markIn = show(p.wordmark, 1 - pop)
	p.title.TextTransparency = if markIn then 1 else 1 - pop
	p.titleStroke.Transparency = p.title.TextTransparency

	-- The tag line rises in after it (0.6 s, from 0.15 s).
	local rise = clamp((t - 0.15) / 0.6, 0, 1)
	local eased = 1 - (1 - rise) ^ 2
	for i, pair in p.tag do
		for j, l in pair do
			l.TextTransparency = 1 - eased
			local stroke = l:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Transparency = 1 - eased
			end
			l.Position = UDim2.fromOffset(l.Position.X.Offset, self.tagY[i] + (if j == 2 then 3 else 0) + 10 * (1 - eased))
		end
	end

	-- The pill's bar fills (eases towards the progress) and the tyre spins (0.8 s a turn).
	self.shownProgress += (self.progress - self.shownProgress) * math.min(1, dt * 5)
	local pill = box.pill
	local fillW = math.max(pill.Height, pill.Width * self.shownProgress)
	p.fill.Size = UDim2.fromOffset(fillW, pill.Height)
	p.tyre.Rotation = (p.tyre.Rotation + dt * 450) % 360

	-- The car's render and paint fade in; at night it's a little darker, as on the web.
	local bodyIn = show(p.body)
	show(p.paint)
	local shade = if self.tod == "night" then 0.85 else 1
	p.body.ImageColor3 = Color3.new(shade, shade, shade)
	p.paint.ImageColor3 = self.paint:Lerp(Color3.new(0, 0, 0), 1 - shade)
	if bodyIn and not self.carSince then
		self.carSince = t
	end
	p.shadow.BackgroundTransparency = math.clamp(p.body.ImageTransparency, 0, 1)
	self:_moveCar(t, w, h)
end

-- The car parks (0.7 s, overshooting) once its render is in, bobs, and drives off at the end.
function LoadingScreen._moveCar(self: LoadingScreen, t: number, w: number, h: number)
	local p = self.parts
	local car = self.box.car
	local x, y, rot, sc = 0, 0, 0, 1
	if self.carSince then
		local park = clamp((t - self.carSince) / 0.7, 0, 1)
		local e = bezier(0.2, 1.3, 0.4, 1, park)
		x, y, sc = 0.3 * car.Width * (1 - e), -0.14 * car.Height * (1 - e), 0.9 + 0.1 * e
	end
	-- Bob 1.5% up and down (1.6 s each way).
	local bob = easeInOut((t / 1.6) % 2 <= 1 and (t / 1.6) % 1 or 1 - (t / 1.6) % 1)
	local bobY = -0.015 * car.Height * bob
	if self.goSince then
		local g = clamp((t - self.goSince) / 0.9, 0, 1)
		local vmax = math.max(w, h)
		local e = bezier(0.5, 0, 0.9, 0.6, g)
		-- A little lurch back first (to 18%), then off the bottom left of the screen.
		if e < 0.18 then
			local f = e / 0.18
			x, y, rot = 0.06 * car.Width * f, -0.03 * car.Height * f, -1.5 * f
		else
			local f = (e - 0.18) / 0.82
			x = 0.06 * car.Width + (-0.95 * vmax - 0.06 * car.Width) * f
			y = -0.03 * car.Height + (0.42 * vmax + 0.03 * car.Height) * f
			rot = -1.5 + 3.5 * f
		end
		bobY = 0
	end
	p.car.Size = UDim2.fromOffset(car.Width * sc, car.Height * sc)
	p.car.Position = UDim2.fromOffset((car.Min.X + car.Max.X) / 2 + x, car.Min.Y + y + car.Height * (1 - sc) / 2)
	p.car.Rotation = rot
	p.body.Position = UDim2.fromOffset(0, bobY)
end

-- The game is ready: the bar fills, the pill says so, the car drives off and the screen fades
-- away. Returns once it's gone.
function LoadingScreen.finish(self: LoadingScreen)
	self:set("Let's go!", 1)
	task.wait(0.25)
	if self.carSince then
		self.goSince = self.clock
		task.wait(0.75)
	end
	self.fading = true
	local fade = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(self.scale, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Scale = 1.04 }):Play()
	for _, d in self.gui:GetDescendants() do
		if d:IsA("GuiObject") then
			TweenService:Create(d, fade, { BackgroundTransparency = 1 }):Play()
		end
		if d:IsA("TextLabel") then
			TweenService:Create(d, fade, { TextTransparency = 1 }):Play()
		end
		if d:IsA("ImageLabel") then
			TweenService:Create(d, fade, { ImageTransparency = 1 }):Play()
		end
		if d:IsA("UIStroke") then
			TweenService:Create(d, fade, { Transparency = 1 }):Play()
		end
	end
	task.wait(0.65)
	self.gui:Destroy()
end

return LoadingScreen
