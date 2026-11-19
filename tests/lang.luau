--!nocheck
-- Tests for the Spanish and Portuguese (shared/Translate with the converted shared/I18n
-- dictionaries), against what the web's src/i18n/translate.test.ts expects of the same lines.

local Translate = require("../src/shared/Translate")

local function load(lang)
	local d = "../src/shared/I18n/" .. lang .. "/"
	local parts = {}
	for i = 1, 9 do
		local ok, p = pcall(require, d .. "exact" .. i)
		if not ok then
			break
		end
		table.insert(parts, p)
	end
	return Translate.compile(parts, require(d .. "pats"))
end

return function(test)
	local es = load("es")
	local pt = load("pt")
	test("lang: both dictionaries load, thousands of lines each", function()
		local n = 0
		for _ in es.exact do
			n += 1
		end
		assert(n > 2000, `es has {n} lines`)
		assert(next(pt.exact) ~= nil, "pt is empty")
	end)
	test("lang: exact lines, patterns with gaps and unknown text", function()
		assert(Translate.lookup(es, "+ Add") == "+ Agregar", Translate.lookup(es, "+ Add"))
		assert(Translate.lookup(es, "+1 fuel in 42s") == "+1 gasolina en 42s", tostring(Translate.lookup(es, "+1 fuel in 42s")))
		assert(Translate.lookup(es, "Zorblax Quux") == nil)
		assert(Translate.lookup(es, "123") == nil)
	end)
	test("lang: a count in brackets, parts joined with ·, spaces kept", function()
		local add = Translate.lookup(es, "+ Add")
		assert(Translate.lookup(es, "+ Add (3)") == add .. " (3)")
		assert(Translate.lookup(es, "+ Add · Zorblax") == add .. " · Zorblax")
		assert(Translate.text(es, " + Add ") == " " .. add .. " ")
		assert(Translate.lookup(es, "🌐  Language") == "🌐  Idioma", tostring(Translate.lookup(es, "🌐  Language")))
	end)
	test("lang: the race menu's lane headings are in both", function()
		for _, en in { "Story", "Events", "Free play", "Quick race" } do
			assert(Translate.lookup(es, en) ~= nil, `es lacks {en}`)
			assert(Translate.lookup(pt, en) ~= nil, `pt lacks {en}`)
		end
	end)
end
