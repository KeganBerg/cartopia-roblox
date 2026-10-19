--!strict
-- The first ten minutes, as the web game's tutorial (ui/Tutorial.tsx) and its unlocks
-- (game/unlocks.ts): the steps' words, what each waits for, where it points, which buttons a new
-- player has yet, and the server's checks on the tutorial's own actions. Shared by the client
-- (client/Popups/Tutorial draws the card and the pointing hand) and the server (Towns' guards).
--
-- The save keeps the step number (`tutorial`): 0..8 are the steps, 9 is the goal screen
-- (client/Popups/GoalSplash) and 99 is done. Each function takes the town's state; `search` is
-- Rusty's search in progress (the server's state.search, the client's Remote.search).

local Tutorial = {}

Tutorial.DONE = 99
-- The steps (0..8); past the last one the goal screen shows, then 99.
Tutorial.STEPS = 9
-- The make-it-yours step: skipping at or before it keeps the free paint pick for the Paint Shop.
Tutorial.PICK_STEP = 6
Tutorial.GAS_STEP = 7
-- The colours every new town has, for the body and the rims (data.ts STARTER_PAINTS).
Tutorial.STARTER_PAINTS = { "#e53935", "#1e88e5", "#fafafa", "#212121" }

local function stat(s: any, k: string): number
	return (s.stats and s.stats[k]) or 0
end

local function jobRunning(s: any): boolean
	for _, b in s.buildings or {} do
		if b.jobEndsAt ~= nil then
			return true
		end
	end
	return false
end

local function hasRescue(s: any): boolean
	for _, b in s.buildings or {} do
		if b.def == "rescue" then
			return true
		end
	end
	return false
end
Tutorial.hasRescue = hasRescue

export type Step = {
	icon: string,
	-- The step's one line; editing: placing or moving in edit mode; touch: a phone or tablet.
	text: (s: any, editing: boolean, touch: boolean) -> string,
	-- The spoken line's key (the web's lib/tutorialVoice.ts clip names).
	voice: (s: any, editing: boolean, touch: boolean) -> string,
	-- What it points at in town: "pizza", "shop", "rescue", "done" (edit mode's Done) or "race".
	target: ((s: any, editing: boolean) -> string?)?,
	-- Waits for the player to do something; steps without it move on with a tap on Next.
	done: ((s: any, search: any) -> boolean)?,
	pick: boolean?,
	gas: boolean?,
}

-- Steps either wait for the player to do something (`done`) or for a tap on Next. One short line
-- each, as on the web; the pointing hand does the rest of the explaining.
local STEPS: { Step } = {
	{ icon = "👋", text = function() return "Welcome to Cartopia! Let's earn your first coins." end, voice = function() return "01-welcome" end },
	{
		icon = "⛽",
		text = function() return "Tap a pulsing ⛽ bubble to send a car on a pizza job." end,
		voice = function() return "02-pizza-job" end,
		target = function() return "pizza" end,
		done = function(s) return jobRunning(s) or stat(s, "jobs") > 0 end,
	},
	{
		icon = "💰",
		text = function() return "When the gold $ pops up, tap it to collect." end,
		voice = function() return "03-collect" end,
		target = function() return "pizza" end,
		done = function(s) return stat(s, "jobs") > 0 end,
	},
	{
		icon = "🔧",
		text = function(_, editing, touch)
			if editing then
				return if touch then "Tap the glowing lot to build Rusty's there." else "Click the glowing lot to build Rusty's there."
			end
			return "Build Rusty's Rescue: tap SHOP, then START HERE."
		end,
		voice = function(_, editing, touch)
			return if editing then (if touch then "05-build-lot-tap" else "06-build-lot-click") else "04-build-shop"
		end,
		target = function(_, editing) return if editing then nil else "shop" end,
		done = function(s) return hasRescue(s) end,
	},
	{
		icon = "🔍",
		text = function(_, editing)
			return if editing then "Built! Tap Done, then 🔍 Find cars over Rusty’s." else "Tap 🔍 Find cars over Rusty’s to hunt for old cars."
		end,
		voice = function(_, editing) return if editing then "07-built-find" else "08-find-cars" end,
		target = function(_, editing) return if editing then "done" else "rescue" end,
		done = function(s) return stat(s, "searches") > 0 end,
	},
	{
		icon = "🛠",
		text = function() return "Restore a find in Rusty’s bay. Fixed-up cars drive around town." end,
		voice = function() return "09-restore" end,
		target = function() return "rescue" end,
		-- A search that turned up no cars has nothing to restore: move on rather than stall.
		done = function(s, search)
			return s.restoring ~= nil or stat(s, "rescued") > 0 or (search == nil and #(s.junkyard or {}) == 0)
		end,
	},
	{ icon = "🎨", text = function() return "Make it yours: one paint, one set of rims." end, voice = function() return "10-paint-rims" end, pick = true },
	{ icon = "⛽", text = function() return "Races use gas. It refills, and Gas Stations hold more." end, voice = function() return "11-gas" end, gas = true },
	-- Done after the first race, not on opening the menu: the hand leads the way to it there.
	{
		icon = "🏁",
		text = function() return "While Rusty works, tap RACE for your first race!" end,
		voice = function() return "12-first-race" end,
		target = function() return "race" end,
		done = function(s) return stat(s, "races") > 0 end,
	},
}
Tutorial.list = STEPS

-- The step showing now (nil once past the last step).
function Tutorial.step(s: any): Step?
	local t = s.tutorial or Tutorial.DONE
	return STEPS[t + 1]
end

-- The menus each step works in. Any other menu a new player wanders into points them at its close.
Tutorial.STEP_PANELS = { shop = { 3 }, rescue = { 4, 5 }, race = { 8 } } :: { [string]: { number } }

function Tutorial.inStepPanel(panel: string, step: number): boolean
	local list = Tutorial.STEP_PANELS[panel]
	return list ~= nil and table.find(list, step) ~= nil
end

-- ── Unlocks (game/unlocks.ts) ──────────────────────────────────────────────────────────────────
-- New players start with a nearly empty screen: coins and their level. Each button and counter
-- arrives when the game first needs it. Built only from the save, so nothing new is stored.
local function crewHouse(s: any): boolean
	if s.admin then
		return true
	end
	for _, list in { s.buildings or {}, s.stored or {} } do
		for _, b in list do
			if b.def == "crew" then
				return true
			end
		end
	end
	return false
end

local DONE = Tutorial.DONE
Tutorial.UNLOCKS = {
	fuel = function(s: any) return (s.tutorial or DONE) >= 1 end,
	shop = function(s: any) return (s.tutorial or DONE) >= 3 end,
	edit = function(s: any) return (s.tutorial or DONE) >= 4 end,
	parts = function(s: any) return (s.tutorial or DONE) >= 5 end,
	cars = function(s: any) return (s.tutorial or DONE) >= 6 end,
	race = function(s: any) return (s.tutorial or DONE) >= 8 end,
	gems = function(s: any) return (s.tutorial or DONE) >= DONE end,
	trophies = function(s: any) return (s.tutorial or DONE) >= DONE or stat(s, "races") > 0 end,
	social = function(s: any) return (s.tutorial or DONE) >= DONE and (s.level or 1) >= 2 end,
	season = function(s: any) return (s.tutorial or DONE) >= DONE and (s.level or 1) >= 3 end,
	-- The Bank and Car Packs (real money) wait for the town's own Crew House.
	bank = function(s: any) return (s.tutorial or DONE) >= DONE and crewHouse(s) end,
} :: { [string]: (any) -> boolean }

-- Is `id` unlocked? A friend's town shows everything but the Bank.
function Tutorial.unlocked(s: any, id: string): boolean
	if id ~= "bank" and s.visiting then
		return true
	end
	local f = Tutorial.UNLOCKS[id]
	return f ~= nil and f(s)
end

-- ── The server's checks on the tutorial's actions ─────────────────────────────────────────────
-- setTutorial(n): one step on, once the step's own condition holds (a Next step moves on with a
-- tap), or 99 from the goal screen. Never back, never ahead.
function Tutorial.canSet(s: any, search: any, n: any): (boolean, string?)
	local cur = s.tutorial or DONE
	if type(n) ~= "number" or n % 1 ~= 0 then
		return false, "not a step"
	end
	if cur >= DONE then
		return false, "tutorial done"
	end
	if n == DONE then
		if cur == Tutorial.STEPS then
			return true
		end
		return false, "not at the goal screen"
	end
	if n ~= cur + 1 or cur >= Tutorial.STEPS then
		return false, "not the next step"
	end
	local st = STEPS[cur + 1]
	if st.done and not st.done(s, search) then
		return false, "step not done"
	end
	return true
end

-- skipTutorial(pickStep): only while it runs, and with the web's own paint step (so a client can't
-- claim the free paint pick by naming a later step).
function Tutorial.canSkip(s: any, pickStep: any): (boolean, string?)
	if (s.tutorial or DONE) >= DONE then
		return false, "tutorial done"
	end
	if pickStep ~= Tutorial.PICK_STEP then
		return false, "wrong paint step"
	end
	return true
end

-- tutorialStyle: the one free pick, only on the make-it-yours step.
function Tutorial.canStyle(s: any): (boolean, string?)
	if s.tutorial ~= Tutorial.PICK_STEP then
		return false, "not the paint step"
	end
	return true
end

-- A save written before the tutorial came to Roblox: every town then still said step 0 (the port
-- had no tutorial to move it on). On the web, saves from before the tutorial skip it; here, a town
-- at step 0 that has clearly been played (past level 1, Rusty's built, or a race run) skips it too.
-- A brand new town at step 0 has done none of these.
function Tutorial.playedBefore(save: any): boolean
	if save == nil or save.tutorial ~= 0 then
		return false
	end
	return (save.level or 1) > 1 or hasRescue(save) or stat(save, "races") > 0
end

return Tutorial
