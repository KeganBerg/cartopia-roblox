--!nocheck
-- Minimal assertions for the test files.
local function fmt(v)
	return if type(v) == "number" then string.format("%.17g", v) else tostring(v)
end
local function expect(got)
	local e = {}
	function e.toBe(want)
		if got ~= want then
			error(`expected {fmt(want)}, got {fmt(got)}`, 2)
		end
	end
	function e.toBeLessThan(x)
		if not (got < x) then
			error(`expected {fmt(got)} < {fmt(x)}`, 2)
		end
	end
	function e.toBeGreaterThan(x)
		if not (got > x) then
			error(`expected {fmt(got)} > {fmt(x)}`, 2)
		end
	end
	function e.toBeCloseTo(x)
		if math.abs(got - x) >= 0.005 then
			error(`expected {fmt(got)} close to {fmt(x)}`, 2)
		end
	end
	return e
end
return expect
