--!strict
-- The merged blocks' big centres and their life, as the web game draws them for a merged gas
-- station or car wash at level 7-10: the Big Bison travel stop (scene/TravelCenter.tsx, here
-- client/Centres/TravelStop) and the Bubble Car Spa (scene/WashCenter.tsx, client/Centres/CarSpa).
--
-- The server doesn't draw either: it draws a merged block as its one building grown to fill the
-- block (TownView blockModel), so a level 7-10 gas station block shows a giant gas station. Until
-- the model build exports the centres (tools/models/export.test.tsx), they're drawn here, on this
-- player's client, like SpeedwayLife's race: the grown station is hidden on this screen (its tap
-- box and paved lot stay), and the centre is built in its place, still parts placed once, with cars
-- coming and going at the pumps and through the wash, spinning brushes and foam, and people.
--
-- Kept cheap for phones: each frame moves only the cars on the move, the brushes, the gate arms and
-- the few people, all in one BulkMoveTo, and nothing at all from further off than FAR studs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local data = require(Shared:WaitForChild("Game"):WaitForChild("data")) :: any
local Catalog = require(Shared:WaitForChild("Models"):WaitForChild("Catalog")) :: any
local TravelStop = require(script.Parent:WaitForChild("Centres"):WaitForChild("TravelStop"))
local CarSpa = require(script.Parent:WaitForChild("Centres"):WaitForChild("CarSpa"))

local CentreLife = {}
CentreLife._centres = {} :: { [string]: any }

local TILE = data.TILE * Catalog.SCALE -- studs per tile
-- The station's and the wash's own lot, in tiles along its own x and z (data.ts: both 2x1).
local LOT_W, LOT_D = 2, 1
-- Nothing moves from further off than this (studs), where a car is a few pixels.
local FAR = 1600

local KINDS: { [string]: any } = { gas = TravelStop, carwash = CarSpa }

type Life = { folder: Folder, frame: CFrame, step: (any, number, number, Vector3?, { BasePart }, { CFrame }) -> (), refresh: (any, Vector3?) -> () }
type Centre = { lives: { Life }, model: Model, key: string, hidden: { [Instance]: any }, middle: Vector3 }

local function smallScreen(): boolean
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 800)
	return math.min(v.X, v.Y) < 700
end

-- The halves a block is drawn as (merge.ts groupParts), in the block's own turned frame: one for
-- most blocks, two side by side for a 2x4. Each is its middle (studs from the block's) and how
-- much it grows the lot along its own x and z (groupScale). `w`, `d`: the block in tiles along
-- its own x and z; `members`: how many buildings it merges.
local function halves(w: number, d: number, members: number): { { at: Vector3, sx: number, sz: number } }
	if members == 8 then
		-- Two 2x2 blocks: each grows the lot 2x both ways.
		local hw, hd = LOT_W * 2, LOT_D * 2
		if w > hw + 0.5 then
			return { { at = Vector3.new(-w / 4 * TILE, 0, 0), sx = 2, sz = 2 }, { at = Vector3.new(w / 4 * TILE, 0, 0), sx = 2, sz = 2 } }
		end
		return { { at = Vector3.new(0, 0, -d / 4 * TILE), sx = 2, sz = 2 }, { at = Vector3.new(0, 0, d / 4 * TILE), sx = 2, sz = 2 } }
	end
	return { { at = Vector3.zero, sx = w / LOT_W, sz = d / LOT_D } }
end

-- Hides what the server drew for the block on this screen (its grown station or wash), keeping the
-- invisible tap box and the paved lot under it. Returns what it changed, for showing it again.
local function hideModel(model: Model): { [Instance]: any }
	local was: { [Instance]: any } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name ~= "Hit" and d.Name ~= "Lot" then
				-- (Nothing else fades a building, so it goes back to 0.)
				was[d] = d.CanCollide
				d.LocalTransparencyModifier = 1
				d.CanCollide = false
			end
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") or d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Beam") then
			was[d] = (d :: any).Enabled
			;(d :: any).Enabled = false
		end
	end
	return was
end

local function showModel(was: { [Instance]: any })
	for d, v in was do
		if d.Parent then
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
				d.CanCollide = v
			else
				(d :: any).Enabled = v
			end
		end
	end
end

-- Keeps a centre for every level 7-10 merged gas station and car wash in `town` (its Buildings
-- folder); returns a function that looks for new, moved or upgraded ones, and one that moves them
-- all on (each frame).
function CentreLife.attach(town: Folder, parent: Instance?): (() -> (), (dt: number) -> ())
	local buildings = town:WaitForChild("Buildings")
	local holder = Instance.new("Folder")
	holder.Name = "Centres"
	holder.Parent = parent or workspace
	local centres: { [string]: Centre } = {}
	-- (For the preview tools: tools/emulate/travelwash.luau.)
	CentreLife._centres = centres :: any
	local small = smallScreen()

	local function drop(c: Centre)
		for _, life in c.lives do
			life.folder:Destroy()
		end
		showModel(c.hidden)
	end

	local function scan()
		local seen = {}
		for _, m in buildings:GetChildren() do
			local kind = m:IsA("Model") and KINDS[m:GetAttribute("Def") :: any]
			local lvl = (m:GetAttribute("Level") :: number?) or 1
			local members = (m:GetAttribute("Merged") :: number?) or 1
			-- travelCenter.ts isTravelCenter, washCenter.ts isWashCenter: a merged block at its last form.
			if not kind or lvl < 7 or members < 2 then
				continue
			end
			local hit = m:FindFirstChild("Hit") :: BasePart?
			local turn = m:GetAttribute("Turn")
			if not hit or type(turn) ~= "number" then
				continue
			end
			-- Where the block stands (its middle on the ground, turned to face its road) and its size
			-- in tiles along its own x and z (the tap box covers 0.9 of it).
			local p = hit.CFrame.Position
			local frame = CFrame.new(p.X, p.Y - hit.Size.Y / 2, p.Z) * CFrame.Angles(0, turn * math.pi / 2, 0)
			local wx, wz = hit.Size.X / 0.9 / TILE, hit.Size.Z / 0.9 / TILE
			local w, d = if turn % 2 == 1 then wz else wx, if turn % 2 == 1 then wx else wz
			local key = `{lvl}|{members}|{math.round(w)}x{math.round(d)}|{frame}`
			local model = m :: Model
			seen[m.Name] = true
			local have = centres[m.Name]
			if have and (have.key ~= key or have.model ~= model) then
				drop(have)
				have = nil
			end
			if not have then
				local lives = {}
				for i, h in halves(math.round(w), math.round(d), members) do
					table.insert(lives, kind.new(holder, frame * CFrame.new(h.at), h.sx, h.sz, lvl, small, i * 17 + #m.Name))
				end
				have = { lives = lives, model = model, key = key, hidden = hideModel(model), middle = frame.Position }
				centres[m.Name] = have
			end
			-- The cars' detail for how far off they are, and any built before their meshes arrived
			-- built again for real once they're in.
			local cam = workspace.CurrentCamera
			for _, life in (have :: Centre).lives do
				life:refresh(if cam then cam.CFrame.Position else nil)
			end
		end
		for uid, c in centres do
			if not seen[uid] then
				drop(c)
				centres[uid] = nil
			end
		end
	end

	-- Seconds since the town was first drawn.
	local time = 0
	local function step(dt: number)
		time += dt
		local list: { BasePart } = {}
		local cfs: { CFrame } = {}
		local cam = workspace.CurrentCamera
		local eye = if cam then cam.CFrame.Position else nil
		for _, c in centres do
			if eye and (eye - c.middle).Magnitude > FAR then
				continue
			end
			for _, life in c.lives do
				life:step(time, dt, eye, list, cfs)
			end
		end
		if #list > 0 then
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	return scan, step
end

function CentreLife.start()
	local Town = require(script.Parent.Town) :: any
	local Remote = require(script.Parent.Remote) :: any
	task.spawn(function()
		local folder: Folder? = nil
		while not folder do
			folder = Town.folder()
			if not folder then
				task.wait(0.5)
			end
		end
		local scan, step = CentreLife.attach(folder :: Folder)
		-- The server redraws a building when it's built, moved, merged or upgraded; buildings also
		-- stream in and out, so look again every second as well as on every change.
		Remote.changed:Connect(function()
			task.defer(scan)
		end)
		scan()
		local wait = 0
		RunService.RenderStepped:Connect(function(dt)
			wait -= dt
			if wait <= 0 then
				wait = 1
				scan()
			end
			step(math.min(dt, 0.1))
		end)
	end)
end

return CentreLife
