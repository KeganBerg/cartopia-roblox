--!nocheck
-- Tests for shared/CarFeel: the driving feel out in the world (client/CarDrive).

local CarFeel = require("../src/shared/CarFeel")

local DT = 1 / 60

local function run(s, seconds, throttle, steer, boost)
	for _ = 1, math.floor(seconds / DT + 0.5) do
		s = CarFeel.step(s, DT, throttle, steer, boost)
	end
	return s
end

return function(test)
	test("pulls away smoothly and settles at the top speed", function()
		local s = run(CarFeel.new(), 1, 1, 0, false)
		assert(s.speed > 20 and s.speed < 35, `after 1 s: {s.speed}`)
		s = run(s, 3, 1, 0, false)
		assert(s.speed > 55, `after 4 s: {s.speed}`)
		s = run(s, 10, 1, 0, false)
		assert(math.abs(s.speed - CarFeel.TOP) < 0.01, `top: {s.speed}`)
		assert(CarFeel.TOP < 110, "slower than before")
	end)

	test("boost raises the top speed, then eases back down", function()
		local s = run(CarFeel.new(), 15, 1, 0, true)
		assert(math.abs(s.speed - CarFeel.TOP * CarFeel.BOOST) < 0.01, `boost top: {s.speed}`)
		s = run(s, 0.5, 1, 0, false)
		assert(s.speed < CarFeel.TOP * CarFeel.BOOST and s.speed > CarFeel.TOP, `easing: {s.speed}`)
		s = run(s, 5, 1, 0, false)
		assert(math.abs(s.speed - CarFeel.TOP) < 0.01, `back to top: {s.speed}`)
	end)

	test("coasts, brakes, then backs up slowly", function()
		local s = run(CarFeel.new(), 10, 1, 0, false)
		local c = run(s, 1, 0, 0, false)
		assert(c.speed < s.speed and c.speed > s.speed - 20, `coast: {c.speed}`)
		local b = run(s, 0.9, -1, 0, false)
		assert(b.speed >= 0 and b.speed < 5, `nearly stopped by braking in 0.9 s: {b.speed}`)
		b = run(b, 10, -1, 0, false)
		assert(math.abs(b.speed + CarFeel.REVERSE) < 0.01, `reverse: {b.speed}`)
		b = run(b, 1, 1, 0, false)
		assert(b.speed >= 0, "forward brakes a reversing car first")
		local stop = run(s, 30, 0, 0, false)
		assert(stop.speed == 0, "rolls to a stop")
	end)

	test("steers gradually, never spins in place, gentler at speed", function()
		local still = run(CarFeel.new(), 1, 0, 1, false)
		assert(still.turn == 0, "no turning standing still")
		assert(still.steer == 1, "wheel fully turned after a second")
		local first = CarFeel.step(CarFeel.new(), DT, 0, 1, false)
		assert(first.steer < 0.2, "a key press turns the wheel in, not all at once")
		local slow = run(CarFeel.new(), 0.6, 1, 0, false)
		slow = run(slow, 1, 0.3, 1, false)
		local fast = run(CarFeel.new(), 15, 1, 0, false)
		fast = run(fast, 1, 1, 1, false)
		local rSlow = slow.speed / slow.turn
		local rFast = fast.speed / fast.turn
		assert(rFast > rSlow * 2.5, `wider circle when fast: {rSlow} vs {rFast}`)
		assert(fast.turn <= CarFeel.MAX_TURN and fast.turn > 0.4, `turn at top speed: {fast.turn}`)
		local back = run(CarFeel.new(), 3, -1, 1, false)
		assert(back.turn < 0, "backing up with right lock swings the nose the other way")
	end)

	test("loses speed against a wall", function()
		local s = run(CarFeel.new(), 10, 1, 0, false)
		CarFeel.blocked(s, 0)
		assert(s.speed <= 6, `blocked: {s.speed}`)
		local free = run(CarFeel.new(), 10, 1, 0, false)
		CarFeel.blocked(free, free.speed - 1)
		assert(math.abs(free.speed - CarFeel.TOP) < 0.01, "unchanged when free")
	end)
end
