--!strict
-- Turns the game's English into another language from a dictionary (the web's src/i18n/translate.ts,
-- dictionaries converted by tools/i18n/build.mjs into shared/I18n/<lang>). A line with `{}` or a
-- lone `#` in the web's dictionary is a pattern here: "Win {} races" also covers "Win 12 races".
-- A translation fills its gaps in order with `{}`, or by position with `{0}`, `{1}`.

local Translate = {}

type Pattern = { pat: string, to: string }
export type Compiled = { exact: { [string]: string }, byWord: { [string]: { Pattern } }, loose: { Pattern }, cache: { [string]: string | false }, size: number }

local CACHE_MAX = 4000
local SEP = " · "

-- exacts: the dictionary's exact lines (in parts); pats: { longest word, Lua pattern, translation }.
function Translate.compile(exacts: { { [string]: string } }, pats: { { string } }): Compiled
	local exact = {}
	for _, part in exacts do
		for en, to in part do
			exact[en] = to
		end
	end
	local byWord: { [string]: { Pattern } } = {}
	local loose: { Pattern } = {}
	for _, p in pats do
		local entry = { pat = p[2], to = p[3] }
		if p[1] == "" then
			table.insert(loose, entry)
		else
			local list = byWord[p[1]]
			if not list then
				list = {}
				byWord[p[1]] = list
			end
			table.insert(list, entry)
		end
	end
	return { exact = exact, byWord = byWord, loose = loose, cache = {}, size = 0 }
end

-- The words of three or more letters, lowercase, each once, in order.
local function words(text: string): { string }
	local out, seen = {}, {}
	for w in string.gmatch(string.lower(text), "%a+") do
		if #w >= 3 and not seen[w] then
			seen[w] = true
			table.insert(out, w)
		end
	end
	return out
end

local function fill(to: string, gaps: { string }): string
	local i = 0
	return (string.gsub(to, "{(%d*)}", function(n: string)
		if n == "" then
			i += 1
			return gaps[i] or ""
		end
		return gaps[(tonumber(n) :: number) + 1] or ""
	end))
end

local function find(c: Compiled, text: string): string?
	local hit = c.exact[text]
	if hit then
		return hit
	end
	if not string.find(text, "%a%a") then
		return nil
	end
	local tried = {}
	local list = words(text)
	table.insert(list, "")
	for _, w in list do
		local pats = if w == "" then c.loose else c.byWord[w]
		if pats and not tried[pats] then
			tried[pats] = true
			for _, p in pats :: { Pattern } do
				local m = { string.match(text, p.pat) }
				if #m > 0 then
					-- Gaps are usually numbers or names; a gap that is itself English in the dictionary is translated too.
					local gaps = {}
					for k, g in m do
						gaps[k] = c.exact[g] or g
					end
					return fill(p.to, gaps)
				end
			end
		end
	end
	return nil
end

local function upFirst(s: string): string
	-- (The first letter may be more than one byte: á, ç.)
	local first = utf8.offset(s, 2) or #s + 1
	return string.upper(string.sub(s, 1, first - 1)) .. string.sub(s, first)
end

-- The translation of one piece of text (trimmed), or nil when the dictionary has none. Past the
-- dictionary's own lines it also tries the line with a capital the game added, a count in
-- brackets ("Compact (1)"), an icon in front, and each part of a line joined with " · " ("Back Streets · 1/5").
function Translate.lookup(c: Compiled, text: string): string?
	local known = c.cache[text]
	if known ~= nil then
		return if known == false then nil else known :: string
	end
	local out = find(c, text)
	if out == nil and string.find(text, "^%u%l") then
		local low = find(c, string.lower(string.sub(text, 1, 1)) .. string.sub(text, 2))
		if low ~= nil then
			out = upFirst(low)
		end
	end
	if out == nil then
		local head, count = string.match(text, "^(.-)( %(%d[%d,]*%))$")
		if head and head ~= "" then
			local h = Translate.lookup(c, head)
			if h ~= nil then
				out = h .. (count :: string)
			end
		end
	end
	if out == nil and string.find(text, SEP, 1, true) then
		local parts = string.split(text, SEP)
		local any = false
		for i, p in parts do
			local d = Translate.lookup(c, p)
			if d ~= nil then
				parts[i] = d
				any = true
			end
		end
		if any then
			out = table.concat(parts, SEP)
		end
	end
	-- An icon in front ("🌐  Language", "🏁 Quick race"): the web draws the two apart, so its
	-- dictionary has the words alone.
	if out == nil then
		local pre, rest = string.match(text, "^([^%w%s%(%[]+%s+)(.+)$")
		if pre and rest then
			local r = Translate.lookup(c, rest)
			if r ~= nil then
				out = pre .. r
			end
		end
	end
	if c.size > CACHE_MAX then
		c.cache = {}
		c.size = 0
	end
	c.cache[text] = if out == nil then false else out
	c.size += 1
	return out
end

-- Translate keeping one leading and one trailing space if the text had them.
function Translate.text(c: Compiled, raw: string): string?
	local text = string.gsub(string.gsub(raw, "%s+", " "), "^ ", "")
	text = string.gsub(text, " $", "")
	if text == "" then
		return nil
	end
	local to = Translate.lookup(c, text)
	if to == nil then
		return nil
	end
	local lead = if string.find(raw, "^%s") then " " else ""
	local trail = if string.find(raw, "%s$") then " " else ""
	return lead .. to .. trail
end

return Translate
