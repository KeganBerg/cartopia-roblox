--!strict
-- The language the game is shown in (the web's src/i18n/lang.ts and dom.ts). English is written in
-- the code; Spanish and Portuguese come from the web game's dictionaries (shared/I18n, converted
-- by tools/i18n/build.mjs) and load only for players who use them.
--
-- As the web swaps the page's text as React draws it, every text on the player's screens is
-- swapped as it appears or changes: Text, and a text box's PlaceholderText (never what's typed in
-- it). What the game wrote is kept, so switching back to English puts it back. Anything with the
-- NoI18n attribute (on it or a parent: player names, the language picker) is left alone. Car,
-- rival, track and brand names stay as written, since the dictionaries don't hold them.
--
-- The pick is kept with the player's settings (Prefs.lang); with none, the device's language.

local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Prefs = require(script.Parent.Prefs)
local Ui = require(script.Parent.Ui)
local Translate = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Translate"))

local Lang = {}

export type Id = "en" | "es" | "pt"
-- Each language is named in itself, so a player who can't read the current one still finds theirs.
Lang.LANGS = { { id = "en", label = "English" }, { id = "es", label = "Español" }, { id = "pt", label = "Português" } }

local changed = Instance.new("BindableEvent")
Lang.changed = changed.Event

local current: Id = "en"
local dict: Translate.Compiled? = nil
local loaded: { [string]: Translate.Compiled } = {}

-- What the game wrote in each text, and what we last wrote over it (weak: gone with the text).
local source: { [Instance]: string } = setmetatable({} :: any, { __mode = "k" })
local wrote: { [Instance]: string } = setmetatable({} :: any, { __mode = "k" })
local placeSource: { [Instance]: string } = setmetatable({} :: any, { __mode = "k" })
local placeWrote: { [Instance]: string } = setmetatable({} :: any, { __mode = "k" })
local hooked: { [Instance]: boolean } = setmetatable({} :: any, { __mode = "k" })

-- The device's language when the player hasn't picked one (lang.ts deviceLang).
function Lang.device(): Id
	for _, get in { function()
		return LocalizationService.RobloxLocaleId
	end, function()
		return LocalizationService.SystemLocaleId
	end } do
		local ok, id = pcall(get)
		if ok and type(id) == "string" and #id >= 2 then
			local base = string.lower(string.sub(id, 1, 2))
			if base == "es" or base == "pt" then
				return base :: Id
			end
			if base == "en" then
				return "en"
			end
		end
	end
	return "en"
end

function Lang.current(): Id
	return current
end

local function compile(id: Id): Translate.Compiled?
	if id == "en" then
		return nil
	end
	if loaded[id] then
		return loaded[id]
	end
	local folder = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("I18n"):FindFirstChild(id)
	if not folder then
		return nil
	end
	local parts = {}
	for i = 1, 20 do
		local m = folder:FindFirstChild("exact" .. i)
		if not m then
			break
		end
		table.insert(parts, (require :: any)(m))
	end
	local pats = folder:FindFirstChild("pats")
	local c = Translate.compile(parts, if pats then (require :: any)(pats) else {})
	loaded[id] = c
	return c
end

-- A line of English in the current language, for words drawn outside a text label (or worked out
-- before they're shown). Untranslated lines come back as they are.
function Lang.tr(en: string): string
	if not dict then
		return en
	end
	return Translate.text(dict, en) or en
end

-- Labels sized to their words (Ui.textWidth) are sized to the translation.
Ui.translate = Lang.tr

local function skipped(inst: Instance): boolean
	local p: Instance? = inst
	while p do
		if p:GetAttribute("NoI18n") then
			return true
		end
		p = p.Parent
	end
	return false
end

local function doText(t: TextLabel | TextButton | TextBox)
	if t:IsA("TextBox") then
		local now = t.PlaceholderText
		if placeWrote[t] ~= now then
			placeSource[t] = now
		end
		local en = placeSource[t] or now
		local to = if dict and en ~= "" and not skipped(t) then Translate.text(dict, en) or en else en
		placeWrote[t] = to
		if t.PlaceholderText ~= to then
			t.PlaceholderText = to
		end
		return
	end
	local now = t.Text
	-- The game changed it since we last wrote: what it says now is the new English.
	if wrote[t] ~= now then
		source[t] = now
	end
	local en = source[t] or now
	local to = en
	if dict and en ~= "" and not skipped(t) then
		to = Translate.text(dict, en) or en
	end
	wrote[t] = to
	if t.Text ~= to then
		t.Text = to
	end
end

local function hook(d: Instance)
	if hooked[d] or not (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) then
		return
	end
	hooked[d] = true
	local t = d :: any
	if d:IsA("TextBox") then
		d:GetPropertyChangedSignal("PlaceholderText"):Connect(function()
			doText(t)
		end)
	else
		d:GetPropertyChangedSignal("Text"):Connect(function()
			doText(t)
		end)
	end
	if dict then
		doText(t)
	end
end

local function redoAll()
	for d in hooked do
		if d.Parent then
			doText(d :: any)
		end
	end
end

local function show(id: Id)
	if id == current and (id == "en" or dict ~= nil) then
		return
	end
	current = id
	dict = compile(id)
	redoAll()
	changed:Fire(id)
end

-- Picks a language (Settings) and keeps it with the player's settings.
function Lang.set(id: Id)
	Prefs.set({ lang = id })
	show(id)
end

-- Takes in every text under `root` now (start does this for the screens; the emulator, whose
-- DescendantAdded never fires, calls it after drawing a screen).
function Lang.sweep(root: Instance)
	for _, d in root:GetDescendants() do
		hook(d)
		if hooked[d] and dict then
			doText(d :: any)
		end
	end
end

local started = false
-- Called once at start-up: follows the saved pick (or the device), and every text on screen from then.
function Lang.start()
	if started then
		return
	end
	started = true
	local me = Players.LocalPlayer
	local gui = me and me:WaitForChild("PlayerGui")
	local function want(): Id
		local p = Prefs.get().lang
		return if p == "en" or p == "es" or p == "pt" then p :: Id else Lang.device()
	end
	show(want())
	Prefs.changed:Connect(function()
		show(want())
	end)
	if gui then
		for _, d in gui:GetDescendants() do
			hook(d)
		end
		gui.DescendantAdded:Connect(hook)
	end
end

return Lang
