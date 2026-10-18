--!strict
-- The game's sound effects: Kegan's recordings of the web game's own (lib/sound.ts, arcadeSound.ts,
-- wheelSfx.ts, crateOpenSfx.ts), all in one uploaded sprite (tools/audio/build.mjs), each played
-- from its part with a PlaybackRegion. The calls match the web's, so a screen ported from the web
-- plays the same sound at the same moment:
--
--   Sfx.click()  Sfx.coin()  Sfx.coins(n)  Sfx.buy()  Sfx.error()  Sfx.levelUp()  Sfx.win()  Sfx.lose()
--   Sfx.menuOpen()  Sfx.menuClose()  Sfx.tab()  Sfx.equip()  Sfx.countdown(go)  Sfx.shift(good)
--   Sfx.boost()  Sfx.horn(body)  Sfx.bulldoze(rock) ...
--   Sfx.rescue.reveal(tier)  Sfx.crate.open(crateId)  Sfx.wheel.win(tier)  Sfx.arcade.crash() ...
--
-- Sounds the store's actions make on the server (the web store's sfx.* calls) come back with the
-- town's snapshot and play here (Sfx.heard), so buying, collecting or levelling up sounds as on the web.
-- Everything goes through the Effects group (the Menu's Effects slider; the Sound switch mutes it).

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AudioAssets")) :: any
local Mixer = require(script.Parent.Mixer)

local Sfx = {}

local SPRITE = Assets.sprites.sfx
local loaded: Sound? = nil

-- Loads the sprite once, so the first click isn't silent while it downloads.
function Sfx.preload()
	if loaded or SPRITE.id == 0 then
		return
	end
	local s = Mixer.sound(SPRITE.id, Mixer.effects, "SfxSprite")
	loaded = s
	if s then
		task.spawn(function()
			pcall(ContentProvider.PreloadAsync, ContentProvider, { s })
		end)
	end
end

-- Plays one sound from the sprite: `name` is its recording's name ("coin", "crate-open-gold").
-- opts: volume (1 = as recorded), speed (pitch and pace), length (cut it short, s), group.
-- Returns the Sound playing, or nil when it isn't uploaded yet or there's no such sound.
function Sfx.play(name: string, opts: { volume: number?, speed: number?, length: number?, group: SoundGroup? }?): Sound?
	local part = SPRITE.regions[name]
	if not part then
		return nil
	end
	local o = opts or {}
	local s = Mixer.sound(SPRITE.id, o.group or Mixer.effects, name)
	if not s then
		return nil
	end
	local length = if o.length then math.min(o.length, part.length) else part.length
	Mixer.region(s, part.start, length)
	local speed = o.speed or 1
	s.PlaybackSpeed = speed
	s.Volume = o.volume or 1
	s:Play()
	task.delay(length / speed + 0.5, function()
		s:Destroy()
	end)
	return s
end

-- The web keeps some sounds from piling up (menus flicking open and shut, a burst of messages).
local last: { [string]: number } = {}
local function throttled(key: string, ms: number): boolean
	local now = os.clock() * 1000
	if last[key] and now - last[key] < ms then
		return true
	end
	last[key] = now
	return false
end

local function plain(name: string, key: string?, ms: number?)
	return function()
		if key and ms and throttled(key, ms) then
			return
		end
		Sfx.play(name)
	end
end

-- lib/sound.ts sfx
Sfx.click = plain("click")
Sfx.coin = plain("coin")
-- Collect All: a cascade of coins (the recording is the long one).
Sfx.coins = function(_n: number?)
	Sfx.play("coins")
end
Sfx.start = plain("start")
-- Bulldozing wild land: a boulder's crunch or a tree's crack and fall.
Sfx.bulldoze = function(rock: boolean?)
	Sfx.play(if rock then "bulldoze-rock" else "bulldoze-tree")
end
Sfx.sweep = function(_collected: number?, _started: number?, _fixed: number?)
	Sfx.play("sweep")
end
Sfx.challenge = plain("challenge")
Sfx.menuOpen = plain("menu-open", "menu", 120)
Sfx.menuClose = plain("menu-close", "menu", 120)
Sfx.tab = plain("tab", "tab", 60)
Sfx.equip = plain("equip", "equip", 150)
Sfx.notify = plain("notify", "notify", 1500)
Sfx.message = plain("message", "message", 4000)
Sfx.send = plain("send", "send", 150)
Sfx.reward = plain("reward", "reward", 300)
Sfx.unlock = plain("unlock", "unlock", 600)
Sfx.step = plain("step")
Sfx.error = plain("error")
Sfx.levelUp = plain("level-up")
Sfx.dispatch = function(_n: number?)
	Sfx.play("dispatch")
end
Sfx.buy = plain("buy")
-- A car's horn; the ice cream truck plays its jingle instead.
Sfx.horn = function(body: string?)
	Sfx.play(if body == "icecream" then "horn-icecream" else "horn")
end
-- A soft chime on a clean shift (a missed one makes no sound).
Sfx.shift = function(good: boolean?)
	if good then
		Sfx.play("shift")
	end
end
Sfx.win = plain("win")
Sfx.lose = plain("lose")
Sfx.putt = plain("putt")
Sfx.jet = plain("jet")
Sfx.boost = plain("boost")
-- The race lights: a beep for each red, a higher one on GO.
Sfx.countdown = function(go: boolean?)
	Sfx.play(if go then "countdown-go" else "countdown")
end

-- Rusty's Rescue (rescueSfx). tier: "nothing" | "small" | "common" | "scarce" | "rare".
Sfx.rescue = {
	go = plain("rescue-go"),
	-- The ground rumbling as the magnet digs, for len seconds; rarer finds rumble harder.
	rumble = function(tier: string?, len: number?)
		Sfx.play(if tier == "rare" or tier == "scarce" then "rescue-rumble-rare" else "rescue-rumble", { length = len })
	end,
	reveal = function(tier: string?)
		Sfx.play(`rescue-reveal-{tier or "common"}`)
	end,
	clunk = plain("rescue-clunk"),
	land = function(car: boolean?)
		Sfx.play(if car then "rescue-land-car" else "rescue-land")
	end,
	-- A glockenspiel tick per step of the count, a semitone higher each time (up to an octave).
	tick = function(n: number?)
		Sfx.play("rescue-tick", { speed = 2 ^ (math.min(n or 0, 12) / 12) })
	end,
	home = plain("rescue-home"),
	fanfare = function(big: boolean?)
		Sfx.play(if big then "rescue-fanfare-big" else "rescue-fanfare")
	end,
}

-- The Crate Depot (crateSfx, crateOpenSfx.ts).
Sfx.crate = {
	-- The crate shaking before it opens, for len seconds.
	charge = function(len: number?)
		Sfx.play("crate-charge", { length = len })
	end,
	-- tier 0 (common) to 3 (the rarest); coins: a coin prize (tier 0 only).
	reveal = function(tier: number?, coins: boolean?)
		local t = math.clamp(tier or 0, 0, 3)
		Sfx.play(if t == 0 and coins then "crate-reveal-coins" else `crate-reveal-{t + 1}`)
	end,
	-- The crate bursting open: "street", "garage", "gold" or "diamond".
	open = function(crate: string?)
		Sfx.play(`crate-open-{crate or "street"}`)
	end,
}

-- The prize wheel (wheelSfx.ts). speed: 0 (crawling) to 1 (full spin): fast ticks are higher and
-- quieter. tier: "common" | "uncommon" | "rare" | "epic" | "legendary".
Sfx.wheel = {
	tick = function(speed: number?)
		local s = math.clamp(speed or 0, 0, 1)
		Sfx.play("wheel-tick", { speed = (1500 + s * 500) / 1500, volume = (0.05 + (1 - s) * 0.05) / 0.1 })
	end,
	win = function(tier: string?)
		Sfx.play(`wheel-win-{tier or "common"}`)
	end,
}

-- The arcade games' sounds (arcadeSound.ts).
Sfx.arcade = {
	crash = plain("arcade-crash"),
	bump = plain("arcade-bump"),
	siren = plain("arcade-siren"),
	wrench = plain("arcade-wrench"),
	buzz = plain("arcade-buzz"),
	-- pitch: 1 as recorded; higher for a run of pickups.
	ding = function(pitch: number?)
		Sfx.play("arcade-ding", { speed = pitch or 1 })
	end,
	-- Scrubbing and squealing vary a little each time on the web.
	scrub = function()
		Sfx.play("arcade-scrub", { speed = 0.9 + math.random() * 0.25 })
	end,
	splash = plain("arcade-splash"),
	fuel = plain("arcade-fuel"),
	land = plain("arcade-land"),
	squeal = function()
		Sfx.play("arcade-squeal", { speed = 0.95 + math.random() * 0.12 })
	end,
	air = plain("arcade-air"),
	gun = plain("arcade-gun"),
	-- An engine rev, secs long (cut short when less than the recording).
	rev = function(secs: number?)
		Sfx.play("arcade-rev", { length = secs })
	end,
}

-- Thunder, louder and nearer as loud goes 0..1 (the weather's strikes, see Ambience).
function Sfx.thunder(loud: number?)
	local l = math.clamp(loud or 0.5, 0, 1)
	Sfx.play(if l > 0.6 then "thunder-near" else "thunder-far", { volume = 0.4 + 0.6 * l, group = Mixer.town })
end

-- The store's sfx.* calls from the server: { name, args... } each, as the web store made them.
function Sfx.heard(list: { any }?)
	for _, call in list or {} do
		local f = (Sfx :: any)[call[1]]
		if type(f) == "function" then
			f(table.unpack(call, 2))
		end
	end
end

return Sfx
