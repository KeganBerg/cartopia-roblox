--!strict
-- The funfair's visitors, as the web game's scene/FairCrowd.tsx draws them inside the 'funfair'
-- building (scene/RecBuildings.tsx Funfair): more of them as the fair levels up, some standing at
-- the game stalls and the carts, looking about, and some strolling the lane past the stalls and out
-- along the front to the gate, there and back. Who stands where, from which level, is
-- RecBuildings.tsx's FAIR_VISITORS; the lane is FairCrowd.tsx's FAIR_PATH.
--
-- The visitors are TownLife's townspeople (LotPeople), at a Roblox character's height like the
-- ones on the pavements. It all runs on this player's client, like SpeedwayLife: placed once,
-- moved in one BulkMoveTo, and left alone when the fair is further than FAR studs from the camera.

local RunService = game:GetService("RunService")

local LotPeople = require(script.Parent.LotPeople)

local FairCrowd = {}

local FAR = 1600
-- The fair's paving (RecBuildings.tsx stands the crowd 0.05 up, on it).
local GROUND = 0.05

-- A visitor from `lvl` on: standing at (x, z) facing `face` (0 is +z), or walking the lane from
-- `walk` (0..1 of the way along it, 1..2 on the way back) at `speed` (of that a second).
type Visitor = { lvl: number, x: number?, z: number?, face: number?, walk: number?, speed: number? }
local PI = math.pi
local VISITORS: { Visitor } = {
	{ lvl = 1, x = -1.27, z = 0.45, face = -PI / 2 },
	{ lvl = 1, x = -1.27, z = 1.3, face = -PI / 2 },
	{ lvl = 1, walk = 0.2, speed = 0.045 },
	{ lvl = 2, x = -0.4, z = 1.43, face = PI },
	{ lvl = 2, walk = 1.1, speed = 0.05 },
	{ lvl = 3, x = 0.25, z = 0.18, face = -PI / 2 - 0.4 },
	{ lvl = 3, x = 0.2, z = 0.95, face = -PI / 2 },
	{ lvl = 4, x = 0.17, z = 0.55, face = -PI / 2 },
	{ lvl = 4, x = -0.15, z = 0.12, face = PI },
	{ lvl = 5, walk = 0.65, speed = 0.04 },
	{ lvl = 5, walk = 1.55, speed = 0.055 },
	{ lvl = 6, x = -0.58, z = -0.12, face = -PI / 2 },
	{ lvl = 6, walk = 0.9, speed = 0.035 },
	{ lvl = 7, x = -1.27, z = -0.38, face = -PI / 2 },
	{ lvl = 8, x = 1.17, z = 1.58, face = PI / 2 },
	{ lvl = 8, walk = 1.35, speed = 0.06 },
	{ lvl = 9, x = 0.08, z = 1.76, face = PI },
	{ lvl = 10, walk = 0.05, speed = 0.05 },
	{ lvl = 10, walk = 1.8, speed = 0.04 },
}

-- The lane in front of the stalls and across the front by the gate, walked there and back.
local PATH = { { -1.08, -0.62 }, { -1.08, 1.64 }, { -0.1, 1.64 } }
local SEGS = {}
local LONG = 0
for i = 2, #PATH do
	local a, b = PATH[i - 1], PATH[i]
	local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	table.insert(SEGS, len)
	LONG += len
end

-- Where along the lane `u` is (0..1 there, 1..2 back, wrapping).
local function along(u: number): (number, number)
	local t = u % 2
	local d = (if t > 1 then 2 - t else t) * LONG
	for i, len in SEGS do
		if d <= len or i == #SEGS then
			local a, b = PATH[i], PATH[i + 1]
			local k = math.min(1, d / len)
			return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k
		end
		d -= len
	end
	return PATH[1][1], PATH[1][2]
end

---------------------------------------------------------------------------------------------------
-- One fair's crowd.

export type Life = {
	folder: Folder,
	frame: CFrame,
	yaw: number,
	here: { Visitor },
	crowd: LotPeople.Crowd,
	step: (self: Life, time: number, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame }) -> (),
	destroy: (self: Life) -> (),
}

local Life = {}
Life.__index = Life

-- The visitors of a fair at `lvl` whose model sits at `frame`, turned `yaw`. On a phone (`small`)
-- the fair has a few fewer: every third of the ones who stand about stays home.
function FairCrowd.new(parent: Instance, uid: string, frame: CFrame, yaw: number, lvl: number, small: boolean?): Life
	local folder = Instance.new("Folder")
	folder.Name = `FairCrowd:{uid}`
	local here = {}
	local standing = 0
	for _, v in VISITORS do
		if v.lvl <= lvl then
			if v.walk == nil then
				standing += 1
				if small and standing % 3 == 0 then
					continue
				end
			end
			table.insert(here, v)
		end
	end
	local crowd = LotPeople.new(folder, `fair:{uid}`, #here)
	folder.Parent = parent
	local self = setmetatable({ folder = folder, frame = frame, yaw = yaw, here = here, crowd = crowd }, Life)
	return (self :: any) :: Life
end

function Life.step(self: Life, time: number, dt: number, eye: Vector3?, list: { BasePart }, cfs: { CFrame })
	for i, v in self.here do
		if v.walk ~= nil then
			local speed = v.speed or 0.05
			local x, z = along(v.walk + time * speed)
			local x2, z2 = along(v.walk + (time + 0.08) * speed)
			LotPeople.walk(self.crowd, i, self.frame, self.yaw, GROUND, x, z, x2, z2, dt)
		else
			-- Looking about a little at the stall in front of them.
			local face = (v.face or 0) + math.sin(time * 0.4 + (i - 1) * 1.7) * 0.12
			LotPeople.stand(self.crowd, i, self.frame, self.yaw, GROUND, v.x or 0, v.z or 0, face)
		end
	end
	LotPeople.draw(self.crowd, time, eye, list, cfs)
end

function Life.destroy(self: Life)
	self.folder:Destroy()
end

---------------------------------------------------------------------------------------------------
-- Every funfair in the player's town.

-- Keeps a Life for every funfair in `town` (its Buildings folder); returns a function that looks
-- for new, moved or upgraded ones, and one that moves them all on (each frame).
function FairCrowd.attach(town: Folder, parent: Instance?): (() -> (), (dt: number) -> ())
	local buildings = town:WaitForChild("Buildings")
	local holder = Instance.new("Folder")
	holder.Name = "FairCrowds"
	holder.Parent = parent or workspace
	local lives: { [string]: { life: Life, key: string } } = {}
	local small = LotPeople.smallScreen()

	local function scan()
		local seen = {}
		for _, m in buildings:GetChildren() do
			if not m:IsA("Model") or m:GetAttribute("Def") ~= "funfair" then
				continue
			end
			local frame, yaw = LotPeople.frameOf(m)
			if not frame then
				continue
			end
			local lvl = math.clamp(math.floor((m:GetAttribute("Level") :: number?) or 1), 1, 10)
			local key = `{lvl}|{frame}`
			seen[m.Name] = true
			local have = lives[m.Name]
			if have and have.key ~= key then
				have.life:destroy()
				have = nil
			end
			if not have then
				lives[m.Name] = { life = FairCrowd.new(holder, m.Name, frame, yaw, lvl, small), key = key }
			end
		end
		for uid, have in lives do
			if not seen[uid] then
				have.life:destroy()
				lives[uid] = nil
			end
		end
	end

	-- Seconds since the town was first drawn (the web's clock.elapsedTime).
	local time = 0
	local function step(dt: number)
		time += dt
		local list: { BasePart } = {}
		local cfs: { CFrame } = {}
		local cam = workspace.CurrentCamera
		local eye = cam and cam.CFrame.Position
		for _, have in lives do
			local life = have.life
			if eye and (eye - life.frame.Position).Magnitude > FAR then
				continue
			end
			life:step(time, dt, eye, list, cfs)
		end
		if #list > 0 then
			workspace:BulkMoveTo(list, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
	return scan, step
end

function FairCrowd.start()
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
		local scan, step = FairCrowd.attach(folder :: Folder)
		-- The server redraws a building when it's built, moved or upgraded; buildings also stream in
		-- and out, so look again every second as well as on every change.
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

return FairCrowd
