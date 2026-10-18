--!strict
-- Brings back the motion of the web game's car skins (scene/skins.ts), which Roblox can't draw with
-- a shader. Each skinned face carries the skin's glow at two moments (Models/Skins, tiles from
-- tools/models/skins.mjs):
--   * they fade into each other and back, so the skin's stars twinkle and its lines pulse;
--   * they slide against the paint as the camera moves or the car turns, as if they lay `Depth`
--     studs under the clear coat, the web's parallax: where the view ray reaches that depth under
--     the face is what shows there.
-- Works for cars in the world (the player's camera) and in 3D pictures (their ViewportFrame's
-- camera). Only cars near the camera move, a few times a frame's budget, for phones.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local SkinMotion = {}

-- How fast the two moments trade places (radians a second): about 3 seconds a twinkle.
local FADE = 2.1
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

type Glow = { tex: Texture, axes: { Vector3 }, depth: number, second: boolean }
type Skinned = { part: BasePart, view: ViewportFrame?, phase: number, glows: { Glow } }

local parts: { [BasePart]: Skinned } = {}

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
		-- Each car's faces trade at their own beat, so the twinkle runs over the car.
		rec = { part = part, view = view, phase = math.random() * math.pi * 2, glows = {} }
		parts[part] = rec
	end
	for _, g in rec.glows do
		if g.tex == tex then
			return
		end
	end
	table.insert(rec.glows, { tex = tex, axes = AXES[tex.Face.Name], depth = tex:GetAttribute("Depth") or 0, second = tex:GetAttribute("Moment") == 2 })
end

-- Moves one part's glows for a camera at `eye`.
local function move(rec: Skinned, eye: Vector3, now: number)
	local cf = rec.part.CFrame
	local look = cf:VectorToObjectSpace((cf.Position - eye).Unit)
	local mix = 0.5 + 0.5 * math.sin(now * FADE + rec.phase)
	for _, g in rec.glows do
		local tex = g.tex
		tex.Transparency = if g.second then 1 - mix else mix * 0.85
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
