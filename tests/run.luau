--!nocheck
-- Runs every test file: `luau tests/run.luau` from the project root (see README).
-- A tiny runner so the shared modules can be tested outside Studio, with plain Luau.

local files = { "./parity", "./store", "./server", "./race", "./races", "./crates", "./rescue", "./townlife", "./kit" }

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end

for _, f in files do
	print(f)
	require(f)(test)
end
print(`\n{passed} passed, {failed} failed`)
if failed > 0 then
	error("tests failed", 0)
end
