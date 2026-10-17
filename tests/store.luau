--!nocheck
-- Plays tools/store-script.mjs through the transpiled web store and checks the save after every step
-- against what the web game's own store produced (StoreGolden.luau).

local Js = require("../src/shared/Game/__js")
local Golden = require("./StoreGolden")
local NULL = require("./Null")

local function show(v): string
	if type(v) == "table" then
		if v == NULL then
			return "null"
		end
		local parts = {}
		for k, x in v do
			table.insert(parts, `{k}={show(x)}`)
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	if type(v) == "number" then
		return string.format("%.17g", v)
	end
	return tostring(v)
end

-- The first difference between the web value and ours, as a path, or nil if they match.
local function diff(web, got, path): string?
	if web == got or (web == NULL and got == nil) then
		return nil
	end
	if type(web) ~= "table" or web == NULL or type(got) ~= "table" then
		return `{path}: web {show(web)}, luau {show(got)}`
	end
	for k, v in web do
		local d = diff(v, got[k], `{path}.{k}`)
		if d then
			return d
		end
	end
	for k, v in got do
		if web[k] == nil and v ~= nil and not (type(v) == "table" and next(v) == nil) then
			return `{path}.{k}: web has none, luau {show(v)}`
		end
	end
	return nil
end

return function(test, maxSteps: number?)
	local now = Golden.start
	local x = Golden.seed
	Js.setClock(function()
		return now
	end)
	Js.setRandom(function()
		x = (x * 16807) % 2147483647
		return x / 2147483647
	end)
	local Store = require("../src/shared/Game/store")
	local Data = require("../src/shared/Game/data")
	local g = Store.useGame

	local function arg(a)
		if type(a) == "table" and a ~= NULL then
			local s = g.getState()
			if a.def then
				local n = 0
				for _, b in s.buildings do
					if b.def == a.def then
						if n == (a.i or 0) then
							return b.uid
						end
						n += 1
					end
				end
				return "none"
			elseif a.car then
				local c = s.cars[a.car + 1]
				return if c then c.uid else "none"
			elseif a.goal then
				local goal = Store.activeGoals(s)[a.goal + 1]
				return if goal then goal.id else "none"
			elseif a.now then
				return now
			end
		end
		return if a == NULL then nil else a
	end

	-- Put the store back as it started afterwards, for the tests that come next.
	local start = g.getState()
	for i, step in Golden.steps do
		if maxSteps and i > maxSteps then
			break
		end
		test(`step {i}: {step["do"]}`, function()
			now += step.wait
			local args = {}
			for j, a in step.args do
				args[j] = arg(a)
			end
			local s = g.getState()
			local result = s[step["do"]](table.unpack(args, 1, #step.args))
			local after = g.getState()
			local toasts = {}
			for _, t in after.toasts do
				table.insert(toasts, t.text)
			end
			local got = { save = Store.saveOf(after), need = after.need, panel = after.panel, toasts = toasts, result = result }
			g.setState({ toasts = {} })
			local d = diff(step.expect, got, "")
			if d then
				error(d, 0)
			end
		end)
	end
	g.setState(start, true)
	local _ = Data
end
