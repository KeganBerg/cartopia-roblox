--!strict
-- Brings back the motion of the web game's car skins (scene/skins.ts), which Roblox can't draw with
-- a shader. Each skinned face carries two glow textures (Models/Skins), and the skin's glow is
-- baked at a few moments half a second apart (tools/models/skins.mjs):
--   * the two textures play through the moments like a flipbook, each fading into the next while
--     the hidden one is handed the moment after, so the stars twinkle and the lines pulse and flow;
--   * they slide against the paint as the camera moves or the car turns, as if they lay `Depth`
--     studs under the clear coat, the web's parallax: where the view ray reaches that depth under
--     the face is what shows there.
-- Works for cars in the world (the player's camera) and in 3D pictures (their ViewportFrame's
-- camera). Only cars near the camera move, a few times a frame's budget, for phones.

local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Pictures = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Pictures"))

local SkinMotion = {}

-- Cars further than this from the camera keep still (they're too small to see it).
local NEAR = 90
-- How often the glows move (a second): smooth enough, and half the work of every frame.
local STEP = 1 / 30

-- A face's way out and the directions its tile runs along (U across, V down), in the part's space,
-- as Roblox lays a Texture on it, by the face's name.
local AXES: { [string]: { Vector3 } } = {
	Front = { Vector3.new(0, 0, -1), Vector3.new(-1, 0, 0), Vector3.new(0, -1, 0) },
	Back = { Vector3.new(0, 0, 1), Vector3.new(1, 0, 0), Vector3.new(0, -1, 0) },
	Right = { Vector3.new(1, 0, 0), Vector3.new(0, 0, -1), Vector3.new(0, -1, 0) },
	Left = { Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, -1, 0) },
	Top = { Vector3.new(0, 1, 0), Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) },
	Bottom = { Vector3.new(0, -1, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1) },
}

type Glow = { tex: Texture, axes: { Vector3 }, depth: number, slot: number }
type Skinned = { part: BasePart, view: ViewportFrame?, phase: number, step: number, frames: { number }, names: { string }, showing: { number }, glows: { Glow } }

local parts: { [BasePart]: Skinned } = {}
-- Skins whose moments have been asked to load (by their Frames list).
local loading: { [string]: boolean } = {}

-- Loads every moment of a skin ahead, so a swap never shows a blank.
local function preload(list: string, frames: { number })
	if loading[list] then
		return
	end
	loading[list] = true
	task.spawn(function()
		local ok, err = pcall(function()
			local all = {}
			for _, id in frames do
				local t = Instance.new("Texture")
				t.Texture = Pictures.content(id)
				table.insert(all, t)
			end
			ContentProvider:PreloadAsync(all)
		end)
		if not ok then
			warn(`[Cartopia] skin moments didn't preload: {err}`)
		end
	end)
end

local function add(tex: Instance)
	-- The name first: this sees everything the town builds.
	if tex.Name ~= "SkinGlow" or not tex:IsA("Texture") then
		return
	end
	local part = tex.Parent
	if not part or not part:IsA("BasePart") then
		return
	end
	local rec = parts[part]
	if not rec then
		local view = part:FindFirstAncestorOfClass("ViewportFrame")
		local list = (tex:GetAttribute("Frames") :: string?) or ""
		local frames = {}
		for id in string.gmatch(list, "%d+") do
			table.insert(frames, tonumber(id) :: number)
		end
		preload(list, frames)
		-- The moments' names, which the previews (tools/emulate) draw by.
		local names = string.split((tex:GetAttribute("Patterns") :: string?) or "", ",")
		-- Each part runs at its own point in the flipbook, so the twinkle runs over the car.
		local step = math.max((tex:GetAttribute("Step") :: number?) or 0.5, 0.1)
		rec = { part = part, view = view, phase = math.random() * step * #frames, step = step, frames = frames, names = names, showing = { 1, 2 }, glows = {} }
		parts[part] = rec
	end
	for _, g in rec.glows do
		if g.tex == tex then
			return
		end
	end
	table.insert(rec.glows, { tex = tex, axes = AXES[tex.Face.Name], depth = tex:GetAttribute("Depth") or 0, slot = tex:GetAttribute("Slot") or 1 })
end

-- Moves one part's glows for a camera at `eye`.
local function move(rec: Skinned, eye: Vector3, now: number)
	local cf = rec.part.CFrame
	local look = cf:VectorToObjectSpace((cf.Position - eye).Unit)
	-- Where the flipbook is: moment k fading out, moment k + 1 fading in, each in the slot that
	-- matches its turn (so the slot that just faded out is the one handed the next moment).
	local n = #rec.frames
	local see = { 0, 1 }
	if n >= 2 then
		local u = (now + rec.phase) / rec.step
		local k = math.floor(u)
		local f = u - k
		f = f * f * (3 - 2 * f)
		local out, into = k % 2 + 1, (k + 1) % 2 + 1
		rec.showing[out] = k % n + 1
		rec.showing[into] = (k + 1) % n + 1
		-- Squared, so the two together never dim much halfway.
		see[out] = f * f
		see[into] = (1 - f) * (1 - f)
	end
	local want = {}
	for slot = 1, 2 do
		local id = rec.frames[rec.showing[slot]]
		want[slot] = if id then Pictures.content(id) else nil
	end
	for _, g in rec.glows do
		local tex = g.tex
		tex.Transparency = see[g.slot] or 1
		local pic = want[g.slot]
		if pic and tex.Texture ~= pic then
			tex.Texture = pic
			tex:SetAttribute("Pattern", rec.names[rec.showing[g.slot]])
		end
		if g.depth > 0 then
			local into = -look:Dot(g.axes[1])
			-- A face turned away is out of sight: leave it.
			if into > 0.02 then
				-- The web's skAt: the ray goes on `depth` under the paint, steeper at a glancing look.
				local k = g.depth / math.max(into, 0.3)
				tex.OffsetStudsU = -look:Dot(g.axes[2]) * k
				tex.OffsetStudsV = -look:Dot(g.axes[3]) * k
			end
		end
	end
end

-- Follows the skinned parts under `root`, now and as they come.
function SkinMotion.watch(root: Instance)
	for _, d in root:GetDescendants() do
		add(d)
	end
	root.DescendantAdded:Connect(add)
end

-- Moves every followed glow to where it is at time `now` (seconds).
function SkinMotion.step(now: number)
	local cam = workspace.CurrentCamera
	local eye = cam and cam.CFrame.Position
	for part, rec in parts do
		if part.Parent == nil then
			parts[part] = nil
			continue
		end
		local view = rec.view
		if view then
			local vc = view.CurrentCamera
			if vc and view.Visible then
				move(rec, vc.CFrame.Position, now)
			end
		elseif eye and (part.CFrame.Position - eye).Magnitude < NEAR then
			move(rec, eye, now)
		end
	end
end

local started = false
function SkinMotion.start()
	if started then
		return
	end
	started = true
	SkinMotion.watch(workspace)
	SkinMotion.watch(Players.LocalPlayer:WaitForChild("PlayerGui"))
	local wait, sweep = 0, 0
	RunService.RenderStepped:Connect(function(dt: number)
		wait += dt
		sweep += dt
		if wait < STEP then
			return
		end
		wait = 0
		SkinMotion.step(os.clock())
		-- Now and then forget cars taken out of the game whole (their parts keep their model).
		if sweep > 2 then
			sweep = 0
			for part in parts do
				if not part:IsDescendantOf(game) then
					parts[part] = nil
				end
			end
		end
	end)
end

return SkinMotion
