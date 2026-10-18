--!strict
-- Draws a Call Card the way the web does (CallCard.tsx, call-cards.css): its animated scene,
-- baked from the web's CSS by tools/callcards/build.mjs into pictures and motion
-- (Shared.CallCardLooks), the tier's frame, and, on a stage, the ground and glow a car stands on.
--
--   CallCardArt.scene(holder, id, { tint, still, g })   the scene filling `holder` (clipped to its corners)
--   CallCardArt.showcase(holder, id, { still, car })    CallCardShowcase: the card with a race car on it
--   CallCardArt.frame(holder, id, inset, radius)        the tier's coloured edge inside a holder
--
-- A holder picks the baked shape nearest its own (wide or tall) and is covered by it. On a stage
-- (`g`, a fraction of the holder's height) the scene slides up so the card's ground (its `f`) meets
-- that line, as the web's .cc-stage does. Until the pictures are uploaded, a card shows its colours
-- as a plain gradient with its icon.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Looks = require(Shared:WaitForChild("CallCardLooks")) :: any
local Pictures = require(Shared:WaitForChild("Pictures"))
local callCards = require(Shared:WaitForChild("Game"):WaitForChild("callCards")) :: any
local Ui = require(script.Parent.Ui)

local CallCardArt = {}

-- The tier's edge colour (.cc-tier-*) and the chip behind its name.
CallCardArt.EDGE = { rare = Color3.fromHex("#4fc3f7"), epic = Color3.fromHex("#b388ff"), legendary = Color3.fromHex("#ffd54f") }
-- The Showroom's light when nobody's colour is given (call-cards.css --cc).
local TINT = Color3.fromHex("#5aa9ff")

-- Stand-ins until the sheets are uploaded: each card's sky, top to bottom.
local FALLBACK: { [string]: { string } } = {
	showroom = { "#1c2747", "#0a1026" }, neonalley = { "#12002b", "#ff2d95" }, raincheck = { "#0c1b33", "#10203a" },
	sunsetstrip = { "#2b1055", "#ff8a3c" }, checkerrush = { "#16181d", "#16181d" }, ravelights = { "#07001a", "#4a0072" },
	warpspeed = { "#6ec6ff", "#020b2a" }, polarglow = { "#020a1a", "#12405e" }, midnightgrid = { "#0d0221", "#ff2a6d" },
	thunderroad = { "#05070d", "#2c3850" }, inferno = { "#120300", "#ff6a00" }, starwarp = { "#070320", "#1a0f3a" },
	goldrush = { "#ffc93c", "#3d2400" }, tiresmoke = { "#2a2f3a", "#1c1f25" }, hazard = { "#3a3320", "#15130c" },
	oceandrive = { "#4fc3f7", "#01579b" }, snowday = { "#6f86b8", "#dfe7f5" }, autumnlane = { "#ffb74d", "#4e2412" },
	dragtree = { "#253048", "#0c1020" }, bubblepop = { "#ffd1f0", "#8fd3ff" }, pixelpark = { "#5c94fc", "#c84c0c" },
	plasma = { "#10002b", "#3a0a6b" }, lasergrid = { "#0a0006", "#1c0010" }, circuitry = { "#0c3b2a", "#04150f" },
	deepsea = { "#0a6c8f", "#021428" }, fireworks = { "#050816", "#1e1440" }, comettrail = { "#2b1d5c", "#0b0820" },
	discoball = { "#3b1060", "#10041f" }, sakura = { "#2a1b3d", "#f3a5c0" }, blackhole = { "#1a0f3a", "#020108" },
	magmacore = { "#1a0a06", "#160704" }, diamondrain = { "#2c5d8f", "#0a1830" }, championlap = { "#6b4a00", "#1a1000" },
}

local function idOf(id: string?): string
	local c = callCards.callCardOr(id)
	return if Looks.cards[c] then c else "showroom"
end

-- A key track's value at u (0..1 of its loop): a number, or { t, v, t, v, ... }.
local function ev(k: any, u: number, step: boolean?): number
	if type(k) == "number" then
		return k
	end
	local n = #k
	for i = 1, n - 2, 2 do
		if u < k[i + 2] then
			if step then
				return k[i + 1]
			end
			return k[i + 1] + (k[i + 3] - k[i + 1]) * (u - k[i]) / (k[i + 2] - k[i])
		end
	end
	return k[n]
end

-- Points an ImageLabel at baked picture `n` (an index into Looks.images).
local function show(img: ImageLabel, n: number)
	local im = Looks.images[n]
	local sheet = Looks.sheets[im[1] + 1]
	if img:GetAttribute("Sheet") ~= sheet then
		img:SetAttribute("Sheet", sheet)
		Pictures.set(img, "Image", sheet)
		-- (render.mjs finds the sheet by this name in previews.)
		img:SetAttribute("Key", `callcard:sheet-{im[1]}`)
	end
	img.ImageRectOffset = Vector2.new(im[2], im[3])
	img.ImageRectSize = Vector2.new(im[4], im[5])
end

local function picture(parent: Instance, n: number, z: number, tint: Color3?): ImageLabel
	local img = Ui.new("ImageLabel", { BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), ImageColor3 = tint or Color3.new(1, 1, 1), ZIndex = z, Parent = parent })
	show(img, n)
	return img
end

-- Whether every sheet a card's shape needs is uploaded.
local function uploaded(look: any): boolean
	local ok = true
	local function need(n: number)
		if (Looks.sheets[Looks.images[n][1] + 1] or 0) == 0 then
			ok = false
		end
	end
	need(look.base)
	need(look.still)
	local function walk(l: any)
		if l.flip then
			for _, f in l.flip do
				need(f)
			end
		elseif l.clip then
			for _, k in l.kids do
				walk(k)
			end
		else
			need(l.img)
		end
	end
	for _, l in look.layers do
		walk(l)
	end
	return ok
end

-- Every playing card: its layers and how to place them, moved each frame while on screen.
type Live = { root: GuiObject, W: number, H: number, parts: { any } }
local live: { [Live]: boolean } = {}
local clock: RBXScriptConnection? = nil

-- Places a layer for moment t in a parent `W` by `H` of the bake's pixels. Everything is in scale,
-- so a card follows its holder's size without being told.
local function place(p: any, W: number, H: number, t: number)
	local l = p.l
	if l.flip then
		local u = (t % l.p) / l.p
		local f = math.floor(u * #l.flip) % #l.flip + 1
		if p.f ~= f then
			p.f = f
			show(p.img, l.flip[f])
		end
		p.img.Position = UDim2.fromScale((l.x + l.w / 2) / W, (l.y + l.h / 2) / H)
		p.img.Size = UDim2.fromScale(l.w / W, l.h / H)
		return
	end
	if l.clip then
		local c = l.clip
		p.win.Position = UDim2.fromScale(c.cx / W, c.cy / H)
		p.win.Size = UDim2.fromScale(c.w / W, c.h / H)
		for _, kid in p.kids do
			place(kid, c.w, c.h, t)
		end
		return
	end
	local per = if l.p and l.p > 0 then l.p else 1
	local u = (t % per) / per
	local img = p.img
	img.Position = UDim2.fromScale(ev(l.cx, u, l.step) / W, ev(l.cy, u, l.step) / H)
	img.Size = UDim2.fromScale(ev(l.w, u, l.step) / W, ev(l.h, u, l.step) / H)
	img.Rotation = ev(l.r, u, l.step)
	img.ImageTransparency = 1 - ev(l.a, u, l.step)
end

local function tick()
	local t = os.clock()
	for c in live do
		if not c.root.Parent then
			live[c] = nil
		elseif c.root.AbsoluteSize.X > 0 then
			for _, p in c.parts do
				place(p, c.W, c.H, t)
			end
		end
	end
	if next(live) == nil and clock then
		clock:Disconnect()
		clock = nil
	end
end

local function build(parent: Instance, l: any, z: number, tint: Color3): any
	if l.clip then
		-- The web's overflow: hidden window; a turned one clips as a CanvasGroup.
		local win = Ui.new(if l.clip.r ~= 0 then "CanvasGroup" else "Frame", { BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5), ClipsDescendants = true, Rotation = l.clip.r, ZIndex = z, Parent = parent })
		local kids = {}
		for i, kl in l.kids do
			table.insert(kids, build(win, kl, i, tint))
		end
		return { l = l, win = win, kids = kids }
	end
	local img = picture(parent, if l.flip then l.flip[1] else l.img, z, if l.tint then tint else nil)
	return { l = l, img = img, f = 1 }
end

-- A holder's width over its height: measured once Roblox has laid it out, else what the caller
-- expects (before the first frame, and in previews).
local function aspectOf(holder: GuiObject, guess: number?): number
	local w, h = holder.AbsoluteSize.X, holder.AbsoluteSize.Y
	if w > 0 and h > 0 then
		return w / h
	end
	return guess or 1
end

-- The card's scene filling `holder`. opts: tint (the Showroom's colour), still (no motion, the
-- picker's swatches), g (a stage: where the holder wants the card's ground, a share of its
-- height), aspect (the holder's width over height, until Roblox measures it).
function CallCardArt.scene(holder: GuiObject, id: string?, opts: { tint: Color3?, still: boolean?, g: number?, aspect: number? }?): GuiObject
	local o = opts or {}
	local cid = idOf(id)
	local card = Looks.cards[cid]
	local corner = holder:FindFirstChildOfClass("UICorner")
	if o.still and uploaded(card.wide) and uploaded(card.tall) then
		-- One picture, the still cropped to the holder (no CanvasGroup: a picker shows 33 at once).
		local img = Ui.new("ImageLabel", { Name = "CardArt", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex(card.base), BorderSizePixel = 0, ZIndex = 0, Parent = holder }, {
			corner and Ui.new("UICorner", { CornerRadius = corner.CornerRadius }) or nil,
		})
		local function crop()
			local a = aspectOf(holder, o.aspect)
			local look = card[if a > 1.2 then "wide" else "tall"]
			local im = Looks.images[look.still]
			show(img, look.still)
			local w, h = im[4], im[5]
			if a > w / h then
				local vh = w / a
				img.ImageRectOffset = Vector2.new(im[2], im[3] + (h - vh) / 2)
				img.ImageRectSize = Vector2.new(w, vh)
			else
				local vw = h * a
				img.ImageRectOffset = Vector2.new(im[2] + (w - vw) / 2, im[3])
				img.ImageRectSize = Vector2.new(vw, h)
			end
		end
		holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(crop)
		crop()
		return img
	end
	-- ZIndex 0: under whatever else the holder shows (names, buttons).
	local root = Ui.new("CanvasGroup", { Name = "CardArt", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromHex(card.base), BorderSizePixel = 0, ZIndex = 0, Parent = holder }, {
		corner and Ui.new("UICorner", { CornerRadius = corner.CornerRadius }) or nil,
	})
	-- (Inside the CanvasGroup the layers stack by their own ZIndex from 1.)
	local scene = Ui.new("Frame", { Name = "Scene", BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 1, Parent = root })
	local state: Live = { root = root, W = 1, H = 1, parts = {} }
	local shape: string? = nil
	local tint = o.tint or TINT

	local function draw()
		local a = aspectOf(holder, o.aspect)
		local want = if a > 1.2 then "wide" else "tall"
		local size = Looks.shapes[want]
		local look = card[want]
		-- Covered: the scene's size as a share of the holder's.
		local ratio = size[1] / size[2]
		local sw, sh = 1, 1
		if a > ratio then
			sh = a / ratio
		else
			sw = ratio / a
		end
		local y = (1 - sh) / 2
		if o.g then
			y = math.min(0, o.g - card.f * sh)
		end
		scene.Position = UDim2.fromScale((1 - sw) / 2, y)
		scene.Size = UDim2.fromScale(sw, sh)
		state.W, state.H = size[1], size[2]
		if want == shape then
			return
		end
		shape = want
		scene:ClearAllChildren()
		state.parts = {}
		live[state] = nil
		if not uploaded(look) then
			local c = FALLBACK[cid] or FALLBACK.showroom
			Ui.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 1, Parent = scene }, {
				Ui.new("UIGradient", { Rotation = 90, Color = Ui.seq(c[1], c[2]) }),
			})
			Ui.text({ Text = callCards.callCardDef(cid).icon, TextSize = 34, TextTransparency = 0.3, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromScale(1, 0.6), ZIndex = 2, Parent = scene })
			return
		end
		local base = picture(scene, if o.still then look.still else look.base, 1)
		base.Position = UDim2.fromScale(0.5, 0.5)
		base.Size = UDim2.fromScale(1, 1)
		if o.still then
			return
		end
		for i, l in look.layers do
			table.insert(state.parts, build(scene, l, 1 + i, tint))
		end
		local t = os.clock()
		for _, p in state.parts do
			place(p, state.W, state.H, t)
		end
		if #state.parts > 0 then
			live[state] = true
			if not clock then
				clock = RunService.RenderStepped:Connect(tick)
			end
		end
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(draw)
	draw()
	return root
end

-- The tier's edge: a 2px line `inset` inside the holder's own border (.cc-show::after).
function CallCardArt.frame(holder: GuiObject, id: string?, inset: number?, radius: number?): Frame
	local d = callCards.callCardDef(idOf(id))
	local i = inset or 2
	return Ui.new("Frame", { Name = "Edge", Position = UDim2.fromOffset(i, i), Size = UDim2.new(1, -2 * i, 1, -2 * i), BackgroundTransparency = 1, ZIndex = holder.ZIndex + 2, Parent = holder }, {
		Ui.corner(radius or 13),
		Ui.stroke(2, if d.tier then CallCardArt.EDGE[d.tier] else Ui.WHITE, if d.tier then 0 else 0.84),
	})
end

-- A small still swatch of a card with its tier's edge (a crate's card list, .crate-cc).
function CallCardArt.chip(holder: GuiObject, id: string?, aspect: number?): GuiObject
	local art = CallCardArt.scene(holder, id, { still = true, aspect = aspect })
	local d = callCards.callCardDef(idOf(id))
	if d.tier then
		local stroke = holder:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = CallCardArt.EDGE[d.tier]
		end
	end
	return art
end

-- A card as a stage with a car standing on it (.cc-stage): the scene slid so its ground meets
-- the holder's line `g`, the ground's shadow and glow under the car (CallCardGround: the card's
-- light, or the car's colour on the Showroom), and the car `carH` of the holder's height tall (no
-- taller than 69% of its width), its wheels on the line as the web's stand thumbnails (60% down).
-- opts.car: { model, color } (nil: the scene alone); opts.tint: the Showroom's colour (the car's).
function CallCardArt.stage(holder: GuiObject, id: string?, opts: { still: boolean?, car: any?, g: number, carH: number, tint: Color3?, aspect: number? }): GuiObject
	local cid = idOf(id)
	local card = Looks.cards[cid]
	local car = opts.car
	local color = opts.tint or (if car then Color3.fromHex(car.color) else nil)
	local art = CallCardArt.scene(holder, cid, { still = opts.still, tint = color, g = opts.g, aspect = opts.aspect })
	if not car then
		return art
	end
	local gd = Looks.ground
	local ground: ImageLabel? = nil
	if (Looks.sheets[Looks.images[gd.img][1] + 1] or 0) ~= 0 then
		local g = picture(art, gd.img, 2, if card.glow then Color3.fromHex(card.glow) else (color or TINT))
		g.AnchorPoint = Vector2.zero
		g.Name = "Ground"
		ground = g
	end
	local Thumb = require(script.Parent.Thumb) :: any
	local v = Thumb.new("Cars", car.model, UDim2.fromScale(0, 0), Color3.fromHex(car.color))
	v.Name = "Car"
	v.ZIndex = 3
	v.Parent = art
	local function lay()
		local a = aspectOf(holder, opts.aspect)
		-- In shares of the holder's height (y) and width (x).
		local H = math.min(opts.carH, 0.69 * a)
		v.Size = UDim2.fromScale(H * 4 / 3 / a, H)
		v.Position = UDim2.fromScale(0.5 - H * 2 / 3 / a, opts.g - 0.6 * H)
		if ground then
			local s = H / gd.H
			ground.Position = UDim2.fromScale(0.5 + gd.x * s / a, opts.g + gd.y * s)
			ground.Size = UDim2.fromScale(gd.w * s / a, gd.h * s)
		end
	end
	holder:GetPropertyChangedSignal("AbsoluteSize"):Connect(lay)
	lay()
	return art
end

-- CallCardShowcase: the card with the player's race car (or opts.car) standing on its own ground
-- (the picker's big card, a crate's prize), with the tier's edge inside the holder's border.
function CallCardArt.showcase(holder: GuiObject, id: string?, opts: { still: boolean?, car: any?, aspect: number? }?): GuiObject
	local o = opts or {}
	local cid = idOf(id)
	local car = o.car
	if car == nil then
		local store = require(Shared.Game.store) :: any
		local raceCar = require(Shared.Game.raceCar) :: any
		local s = store.useGame.getState()
		car = raceCar.raceCarOf(s.cars, s.raceCar)
	end
	local art = CallCardArt.stage(holder, cid, { still = o.still, car = car, g = Looks.cards[cid].f, carH = 0.74, aspect = o.aspect })
	CallCardArt.frame(holder, cid, 0, 13)
	return art
end

return CallCardArt
