--!strict
-- When Rave Mode is on, worked out the way the web game does (game/techno.ts and the server's
-- rave_start() in supabase/migrations/0083_rave_button.sql), kept apart from Roblox services so
-- the tests can run it:
--   - the DJ's button (Kegan's account only) starts one in every town at once: a ten-second
--     build-up, the drop, and 68.2 seconds in all; pressing again while one is on changes nothing;
--   - every Friday at 10:00 pm on the player's own clock it drops for one minute, after a
--     build-up through the ten seconds before.
-- Times are milliseconds since the epoch.

local RaveTime = {}

-- rave_start(): now() to now() + 68.2 seconds.
RaveTime.BUTTON_MS = 68200

export type Window = { from: number, drop: number, to: number }

-- What a press of the button at `now` does: starts a rave, or leaves the one already on.
function RaveTime.press(now: number, current: Window?, buildMs: number): Window
	if current and current.from <= now and now < current.to then
		return current
	end
	return { from = now, drop = now + buildMs, to = now + RaveTime.BUTTON_MS }
end

-- techno.ts weeklyRave: the weekly rave around `now`, or nil outside it. `date` turns seconds into
-- the local calendar (os.date("*t")) and `time` back (os.time); `weekly` is techno.WEEKLY
-- ({ day = 5 (Friday, Sunday being 0), hour = 22, minutes = 1 }).
function RaveTime.weekly(now: number, weekly: { day: number, hour: number, minutes: number }, buildMs: number, date: ((number) -> any)?, time: ((any) -> number)?): Window?
	local toDate = date or function(s: number): any
		return os.date("*t", s)
	end
	local toTime = time or function(t: any): number
		return os.time(t)
	end
	local d = toDate(math.floor(now / 1000))
	-- os.date's wday counts Sunday as 1; JavaScript's getDay() counts it as 0.
	local day = d.wday - 1
	local drop = toTime({ year = d.year, month = d.month, day = d.day + (weekly.day - day), hour = weekly.hour, min = 0, sec = 0 }) * 1000
	local w = { from = drop - buildMs, drop = drop, to = drop + weekly.minutes * 60000 }
	if now >= w.from and now < w.to then
		return w
	end
	return nil
end

return RaveTime
