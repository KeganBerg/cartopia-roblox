--!strict
-- How a car drives out in the world (client/CarDrive): speed that builds and fades instead of
-- jumping, brakes, reverse, and steering that turns the car round its back wheels like a real
-- one, tighter when slow and gentler when fast. Plain maths, so tests/drive.luau can check it.
--
-- Distances are studs: the cars are drawn at 0.8 scale (server/Drive.SCALE), about 27 studs long.

local CarFeel = {}

CarFeel.TOP = 70 -- top speed, studs a second (a plot's width in about 20 seconds)
CarFeel.BOOST = 1.5 -- Shift or the BOOST button: this times the top speed
CarFeel.REVERSE = 22 -- top speed backwards
CarFeel.ACCEL = 30 -- pull from a standstill, studs a second each second (0 to 60 in about 4 s)
CarFeel.BOOST_ACCEL = 1.5 -- and this much harder while boosting
CarFeel.BRAKE = 75 -- braking
CarFeel.COAST = 9 -- slowing with nothing pressed
CarFeel.OVER = 22 -- slowing back to the top speed after a boost ends
CarFeel.WHEELBASE = 16
CarFeel.STEER_SLOW = math.rad(38) -- front wheels' lock when slow...
CarFeel.STEER_FAST = math.rad(9) -- ...and at top speed
CarFeel.STEER_IN = 4.5 -- how fast the wheel turns in (lock fractions a second)
CarFeel.STEER_OUT = 7 -- and back to straight when let go
CarFeel.MAX_TURN = 1.7 -- the fastest the car swings round, radians a second

export type State = {
	speed: number, -- studs a second along the nose; negative backwards
	steer: number, -- -1 (full left) to 1 (full right)
	accel: number, -- this step's change of speed, studs a second each second (for the body's lean)
	turn: number, -- radians a second, positive to the right
}

function CarFeel.new(): State
	return { speed = 0, steer = 0, accel = 0, turn = 0 }
end

local function toward(x: number, target: number, step: number): number
	if x < target then
		return math.min(x + step, target)
	end
	return math.max(x - step, target)
end

-- One step. throttle: 1 forward, -1 back or brake (analog sticks give in between); steer: -1
-- left to 1 right; boost: Shift held. Returns the new state; the car's heading changes by
-- -state.turn * dt (Roblox turns left for a positive angle round Y).
function CarFeel.step(s: State, dt: number, throttle: number, steer: number, boost: boolean): State
	throttle = math.clamp(throttle, -1, 1)
	steer = math.clamp(steer, -1, 1)
	local top = CarFeel.TOP * (if boost then CarFeel.BOOST else 1)
	local speed = s.speed
	local before = speed
	if throttle > 0.05 and speed >= -0.5 then
		-- Forward: strong pull at first, fading near the top speed.
		local pull = CarFeel.ACCEL * (if boost then CarFeel.BOOST_ACCEL else 1) * throttle
		if speed < top then
			local room = 1 - (math.max(speed, 0) / top) ^ 2
			speed = math.min(speed + pull * math.max(room, 0.08) * dt, top)
		else
			speed = toward(speed, top, CarFeel.OVER * dt)
		end
	elseif throttle < -0.05 and speed > 0.5 then
		speed = math.max(speed - CarFeel.BRAKE * -throttle * dt, 0)
	elseif throttle < -0.05 then
		-- Stopped (or backing up): reverse, gently.
		speed = math.max(speed - CarFeel.ACCEL * 0.6 * -throttle * dt, -CarFeel.REVERSE)
	elseif throttle > 0.05 then
		-- Forward pressed while rolling backwards: brake first.
		speed = math.min(speed + CarFeel.BRAKE * throttle * dt, 0)
	else
		speed = toward(speed, 0, (CarFeel.COAST + math.abs(speed) * 0.04) * dt)
	end
	if speed > top then
		speed = toward(speed, top, CarFeel.OVER * dt)
	end

	-- The wheel turns in and back at a steady rate, so a key press doesn't snap the car round.
	local rate = if math.abs(steer) > math.abs(s.steer) and steer * s.steer >= 0 then CarFeel.STEER_IN else CarFeel.STEER_OUT
	local wheel = toward(s.steer, steer, rate * dt)
	local t = math.clamp(math.abs(speed) / CarFeel.TOP, 0, 1)
	local lock = CarFeel.STEER_SLOW + (CarFeel.STEER_FAST - CarFeel.STEER_SLOW) * t
	local turn = speed / CarFeel.WHEELBASE * math.tan(wheel * lock)
	turn = math.clamp(turn, -CarFeel.MAX_TURN, CarFeel.MAX_TURN)

	return { speed = speed, steer = wheel, accel = if dt > 0 then (speed - before) / dt else 0, turn = turn }
end

-- After the physics step: if the car hit something and is really going slower than it wanted,
-- it loses the speed (no pushing on at full speed against a wall).
function CarFeel.blocked(s: State, actual: number): State
	if s.speed > 0 and actual < s.speed - 6 then
		s.speed = math.max(actual + 6, 0)
	elseif s.speed < 0 and actual > s.speed + 6 then
		s.speed = math.min(actual - 6, 0)
	end
	return s
end

return CarFeel
