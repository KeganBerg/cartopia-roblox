--!strict
-- The thought bubble over a townsperson the player tapped (the web game's ui/Thought.tsx and
-- game/thoughts.ts): a blue chip for where they're headed ("➜ ☕ Coffee", green with a 📍 once
-- they're there), and a line on what they're up to ("☕ Riley is grabbing a coffee"). It rides over
-- their head, keeps up with them (TownLife calls show() again as things change) and goes after six
-- seconds, or when the bubble or anywhere else is tapped.
--
-- The words are the web's own tables, copied: what people are off to do at each shop and park
-- spot, and what they do when they get there.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local data = require(Game:WaitForChild("data")) :: any
local Ui = require(script.Parent.Ui)

local Thought = {}

-- Townspeople.tsx: what someone is off to do at each shop, and at each park spot, and what they
-- do once they're there.
Thought.SHOP = {
	pizza = { "🍕", "grabbing a pizza" }, donut = { "🍩", "getting donuts" }, burger = { "🍔", "getting a burger" },
	icecream = { "🍦", "getting ice cream" }, diner = { "🥞", "heading to the diner" }, gas = { "🥤", "grabbing a cold drink" },
	cinema = { "🍿", "catching a movie" }, bowling = { "🎳", "going bowling" }, motel = { "🧳", "checking in at the motel" },
	carwash = { "🧽", "checking out the car wash" }, rescue = { "🔧", "dropping by Rusty's" }, tires = { "🛞", "asking about tires" },
	parts = { "🔩", "picking up parts" }, crew = { "🤝", "hanging out at the Crew House" }, tuner = { "🔩", "browsing the tuner shop" }, stadium = { "🏁", "going to the speedway" },
	coffee = { "☕", "grabbing a coffee" }, tacos = { "🌮", "getting tacos" }, lube = { "🛢", "booking an oil change" }, arcade = { "🕹️", "chasing a high score" },
	bodyshop = { "🎨", "picking a new paint colour" }, market = { "🛒", "doing the grocery run" }, firehouse = { "🚒", "visiting the firefighters" },
	police = { "👮", "dropping by the police station" }, parkade = { "🅿️", "fetching the car from the garage" },
	junkyard = { "🧲", "digging for parts at the junkyard" },
	offices = { "💼", "heading in to the office" }, hq = { "📊", "off to a big meeting at HQ" }, glasstower = { "🏙️", "riding the lift up the Glass Tower" },
	hospital = { "🏥", "visiting a friend in hospital" }, helipad = { "🚁", "booking a helicopter tour" },
	academy = { "🚗", "off to a driving lesson" }, school = { "🎒", "picking the kids up from school" }, highschool = { "🏈", "going to the big game" },
	university = { "🎓", "heading to a lecture" },
	muffler = { "💨", "getting a louder exhaust" }, brakes = { "🛑", "getting the brakes checked" }, wraps = { "🎞️", "picking a car wrap" },
	dynolab = { "📈", "watching a dyno run" }, engines = { "🔩", "ordering an engine rebuild" }, racefab = { "🏎️", "touring the race shop" },
	laundry = { "🧺", "doing the laundry" }, vet = { "🐾", "taking the dog to the vet" }, postoffice = { "📮", "mailing a parcel" },
	library = { "📚", "returning library books" }, busdepot = { "🚌", "catching a bus downtown" }, cityhall = { "🏛️", "paying a parking ticket" },
	minigolf = { "⛳", "playing mini golf" }, pool = { "🏊", "going for a swim" }, funfair = { "🎡", "riding the ferris wheel" },
	waterpark = { "🌊", "hitting the water slides" }, haunted = { "👻", "braving the haunted manor" },
} :: { [string]: { string } }
Thought.PARK_GO = {
	bench = { "🪑", "heading for a bench" }, fountain = { "⛲", "going to see the fountain" }, pond = { "🦆", "going to see the ducks" },
	flowers = { "🌷", "going to smell the flowers" }, tree = { "🌳", "taking a walk in the park" }, palm = { "🌴", "taking a walk in the park" },
	statue = { "🏆", "going to see the golden car" }, pine = { "🌲", "taking a walk in the park" }, picnic = { "🧺", "off for a picnic" },
	busstop = { "🚌", "catching the bus" }, hotdog = { "🌭", "getting a hot dog" }, flagpole = { "🚩", "going to see the town flag" },
	playground = { "🛝", "heading to the playground" }, gazebo = { "🎶", "going to the gazebo" },
	clocktower = { "🕰️", "meeting a friend at the clock tower" },
	dogpark = { "🐕", "taking the dog to the dog park" }, skatepark = { "🛹", "going skating" }, koi = { "🐟", "going to feed the koi" },
	garden = { "🌺", "visiting the botanical garden" },
	pumpkins = { "🎃", "picking a pumpkin" }, scarecrow = { "🌾", "going to see the scarecrow" },
	graves = { "👻", "daring a friend to visit the graveyard" }, deadtree = { "🦇", "going to see the haunted tree" },
	court = { "🏀", "shooting hoops" }, tennis = { "🎾", "playing tennis" }, cornmaze = { "🌽", "getting lost in the corn maze" },
	cauldron = { "🧪", "peeking in the cauldron" }, jacklamp = { "🎃", "going to see the jack-o'-lanterns" },
} :: { [string]: { string } }
Thought.PARK_AT = {
	bench = { "🪑", "resting on the bench" }, fountain = { "⛲", "watching the fountain" }, pond = { "🦆", "watching the ducks" },
	flowers = { "🌷", "smelling the flowers" }, tree = { "🌳", "enjoying the shade" }, palm = { "🌴", "enjoying the shade" },
	statue = { "🏆", "admiring the golden car" }, pine = { "🌲", "enjoying the shade" }, picnic = { "🧺", "having a picnic" },
	busstop = { "🚌", "waiting for the bus" }, hotdog = { "🌭", "eating a hot dog" }, flagpole = { "🚩", "saluting the town flag" },
	playground = { "🛝", "playing on the swings" }, gazebo = { "🎶", "listening to the band" },
	clocktower = { "🕰️", "waiting by the clock tower" },
	dogpark = { "🎾", "playing fetch" }, skatepark = { "🛹", "watching the skaters" }, koi = { "🐟", "feeding the koi" },
	garden = { "🌺", "admiring the orchids" },
	pumpkins = { "🎃", "picking out a pumpkin" }, scarecrow = { "🌾", "taking a selfie with the scarecrow" },
	graves = { "👻", "telling ghost stories" }, deadtree = { "🦇", "spotting bats in the haunted tree" },
	court = { "🏀", "shooting hoops" }, tennis = { "🎾", "playing a set" }, cornmaze = { "🌽", "finding the way out" },
	cauldron = { "🧪", "stirring the potion" }, jacklamp = { "🎃", "admiring the jack-o'-lanterns" },
} :: { [string]: { string } }

-- thoughts.ts: fallback icons for places without their own.
local KIND_ICON: { [string]: string } = {
	business = "🏪", gas = "⛽", parts = "🔩", showroom = "🚗", garage = "🔧", decor = "🌳", house = "🏡", obstacle = "🌿",
}
local ICON: { [string]: string } = { gas = "⛽", club = "🪩", garage = "🔧", showroom = "🚗" }

-- A short name for a building: its sign in title case ("LUBE & GO" -> "Lube & Go"), else its name.
function Thought.shortName(def: string): string
	local d = data.buildingDef(def)
	if not d.sign then
		return d.name
	end
	local out, up = {}, true
	for _, c in utf8.codes(string.lower(d.sign)) do
		local ch = utf8.char(c)
		table.insert(out, if up then string.upper(ch) else ch)
		up = ch == " " or ch == "&" or ch == "-"
	end
	return table.concat(out)
end

-- The chip for a destination building or decoration ("☕ Coffee"), using `icon` when the caller
-- knows a better one.
function Thought.placeChip(def: string, icon: string?): string
	local kind = data.buildingDef(def).kind
	return `{ICON[def] or icon or KIND_ICON[kind] or "📍"} {Thought.shortName(def)}`
end

---------------------------------------------------------------------------------------------------
-- The bubble (index.css .badge.thought): a light grey rounded badge with a white border and a tail
-- under it, the chip on top and the line under it, at most 230 pixels wide (175 on phones).

local BUBBLE = Color3.fromHex("#eceff1")
local BLUE = Color3.fromHex("#1e88e5")
local GREEN = Color3.fromHex("#43a047")
local LIFE = 6 -- seconds a tap shows it for

type Bubble = { gui: BillboardGui, card: TextButton, tail: Frame, chip: Frame, chipText: TextLabel, line: TextLabel, small: boolean }
local bubble: Bubble? = nil
local shownId: string? = nil
local untilAt = 0
local shownText = ""

local function phone(): boolean
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 600
end

local BOARD = Vector2.new(240, 100) -- the billboard: the bubble sits at its bottom middle

local function build(): Bubble
	local small = phone()
	local gui = Ui.new("BillboardGui", {
		Name = "Thought",
		AlwaysOnTop = true,
		Active = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(BOARD.X, BOARD.Y),
		StudsOffsetWorldSpace = Vector3.new(0, 1.5, 0),
		SizeOffset = Vector2.new(0, 0.5),
		ResetOnSpawn = false,
		Enabled = false,
	})
	local card = Ui.new("TextButton", {
		Name = "Card",
		Text = "",
		AutoButtonColor = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -8),
		BackgroundColor3 = BUBBLE,
		ZIndex = 2,
		Parent = gui,
	}, {
		Ui.corner(16),
		Ui.stroke(3, Ui.WHITE),
	})
	-- The tail, a turned white square poking out under the card.
	local tail = Ui.new("Frame", { Name = "Tail", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -9), Size = UDim2.fromOffset(10, 10), Rotation = 45, BackgroundColor3 = Ui.WHITE, BorderSizePixel = 0, ZIndex = 1, Parent = gui })
	local chip = Ui.new("Frame", { Name = "Where", BackgroundColor3 = BLUE, ZIndex = 3, Parent = card }, { Ui.round() })
	local chipText = Ui.text({ Name = "Text", Body = true, Text = "", TextSize = if small then 11 else 12, Size = UDim2.fromScale(1, 1), TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4, Parent = chip })
	local line = Ui.text({ Name = "Line", Text = "", TextSize = if small then 11.5 else 13, TextColor3 = Ui.INK, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3, Parent = card })
	card.Activated:Connect(function()
		Thought.hide()
	end)
	local player = Players.LocalPlayer
	gui.Parent = if player then player:WaitForChild("PlayerGui") else nil
	return { gui = gui, card = card, tail = tail, chip = chip, chipText = chipText, line = line, small = small }
end

-- Sizes the card round its chip and line: as wide as the longer (at most 230 pixels, 175 on
-- phones), the line wrapping under the chip.
local function layout(b: Bubble, chip: string, text: string)
	local padX, padY = if b.small then 7 else 10, if b.small then 3 else 5
	local inner = (if b.small then 175 else 230) - padX * 2
	local cs, ls = b.chipText.TextSize, b.line.TextSize
	local chipW = if chip ~= "" then math.min(inner, Ui.textWidth(chip, cs) + 16) else 0
	local chipH = if chip ~= "" then cs + 6 else 0
	local textW = Ui.textWidth(text, ls) + 2
	local lines = math.max(1, math.ceil(textW / inner))
	local lineW = math.min(inner, textW)
	local lineH = math.ceil(lines * ls * 1.25)
	local w = math.max(chipW, lineW) + padX * 2
	local gap = if chip ~= "" then 3 else 0
	b.card.Size = UDim2.fromOffset(w, padY * 2 + chipH + gap + lineH)
	b.chip.Position = UDim2.fromOffset(padX, padY)
	b.chip.Size = UDim2.fromOffset(chipW, chipH)
	b.line.Position = UDim2.fromOffset(padX, padY + chipH + gap)
	b.line.Size = UDim2.fromOffset(lineW + 1, lineH)
end

-- Shows (or updates) the bubble for person `id` over `adornee` (their head). `fresh` restarts its
-- six seconds (a new tap).
function Thought.show(id: string, adornee: BasePart, where: string, there: boolean, text: string, fresh: boolean?)
	local b = bubble or build()
	bubble = b
	if fresh or shownId ~= id then
		untilAt = os.clock() + LIFE
	end
	shownId = id
	b.gui.Adornee = adornee
	b.gui.Enabled = true
	local chip = if where ~= "" then `{if there then "📍" else "➜"} {where}` else ""
	b.chip.Visible = chip ~= ""
	b.chip.BackgroundColor3 = if there then GREEN else BLUE
	local key = chip .. "|" .. text
	if key ~= shownText then
		shownText = key
		Ui.setText(b.chipText, chip)
		Ui.setText(b.line, text)
		layout(b, chip, text)
	end
end

-- Whose thought is showing, if any, while it hasn't run out.
function Thought.current(): string?
	if shownId and os.clock() > untilAt then
		Thought.hide()
	end
	return shownId
end

function Thought.hide()
	shownId = nil
	shownText = ""
	if bubble then
		bubble.gui.Enabled = false
		bubble.gui.Adornee = nil
	end
end

-- The bubble's own card, so a tap on it isn't taken for a tap on the town.
function Thought.card(): GuiObject?
	return if bubble and bubble.gui.Enabled then bubble.card else nil
end

return Thought
