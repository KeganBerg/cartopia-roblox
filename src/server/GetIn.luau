--!strict
-- Getting in any car on foot (client/GetIn): the player's own (by uid, drawn as they've done it
-- up) or one of the townsfolk's everyday cars (client/TownLife), and out again. The driving is
-- the shared world's (server/Drive): the car is welded round the hidden avatar.
--
-- Remote Cartopia.GetIn (RemoteFunction): ("enter", { uid, model, color, cf }) -> ok or why not;
-- ("exit") -> ok, where the car was left (CFrame, nose along +Z), and the uid it was got in by.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = Shared:WaitForChild("Game")
local data = require(Game.data) :: any
local Builder = require(Shared.Models.Builder) :: any
local Paint = require(Shared.Models.Paint) :: any
local Mods = require(Shared.Models.Mods) :: any
local Panels = require(Shared.Models.Panels) :: any
local Trim = require(Shared.Models.Trim) :: any
local Skins = require(Shared.Models.Skins) :: any
local Drive = require(script.Parent.Drive) :: any

local GetIn = {}

-- How far from the car the avatar can be when it gets in (studs).
local REACH = 24
-- The townsfolk's cars: everyday cars only (no gem or special cars).
local EVERYDAY_MAX = 22000

-- The uid of the car each player got in on foot.
local riding: { [Player]: string } = {}

local function everyday(id: string): boolean
	local c = data.carDef(id)
	return c ~= nil and c.id == id and not c.bucks and not c.parked and (c.price or 0) > 0 and c.price <= EVERYDAY_MAX
end

-- The car as the player sees it in town: theirs with paint, mods and all, or a plain painted one.
local function build(car: any): Model?
	-- Its own shapes first (a pack that failed or is still queued would leave it a pile of boxes).
	Builder.loadCar(car.model, 8)
	local m = Builder.build(car.model)
	if not m then
		return nil
	end
	-- Which car it is, for the driver's own view of it (client/CarDrive turns its wheels).
	m:SetAttribute("Model", car.model)
	local job = Paint.jobOf(car)
	Paint.apply(m, job, if type(job.stripe) == "string" then Builder.build(`stripe:{car.model}`) else nil)
	if car.uid then
		pcall(function()
			Panels.apply(m, car.model, car.panels, job.finish, Builder.build)
			Trim.apply(m, car.model, car.trim, job.color)
			Paint.wearHat(m, car.model, car.hat, Builder.build)
			Mods.fit(m, car.model, car.mods, Builder.build)
			Skins.apply(m, car.skin, car.modSkin)
		end)
	end
	return m
end

function GetIn.enter(player: Player, towns: any, spec: any): (boolean, string?)
	if type(spec) ~= "table" or typeof(spec.cf) ~= "CFrame" or type(spec.model) ~= "string" then
		return false, "bad car"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and humanoid and root) or humanoid.Health <= 0 then
		return false, "no avatar"
	end
	if Drive.isDriving(player) then
		return false, "already driving"
	end
	local cf = spec.cf :: CFrame
	if (cf.Position - root.CFrame.Position).Magnitude > REACH then
		return false, "too far"
	end
	-- Which car: one of the player's own by uid, or a townsfolk car.
	local car: any = nil
	if type(spec.uid) == "string" and not string.find(spec.uid, "^visitor:") then
		local ok, save = pcall(function()
			return towns:save(player.UserId)
		end)
		for _, c in (ok and save and save.cars) or {} do
			if c.uid == spec.uid then
				car = c
			end
		end
		if not car then
			return false, "not your car"
		end
	else
		if not everyday(spec.model) then
			return false, "not a town car"
		end
		local color = if type(spec.color) == "string" and string.match(spec.color, "^#%x%x%x%x%x%x$") then spec.color else "#9e9e9e"
		car = { model = spec.model, color = color }
	end
	local m = build(car)
	if not m then
		return false, "no model"
	end
	-- Stand the avatar where the car is, facing its nose (cars face +Z, avatars -Z), and drive off.
	local turn = select(2, cf:ToEulerAnglesYXZ())
	local up = humanoid.HipHeight + root.Size.Y / 2
	character:PivotTo(CFrame.new(cf.Position + Vector3.new(0, up + 0.1, 0)) * CFrame.Angles(0, turn + math.pi, 0))
	Drive.set(player, m)
	riding[player] = if type(spec.uid) == "string" then spec.uid else nil
	if Builder.boxed(m) then
		-- Still missing some shapes: swapped for the real car as soon as they're in.
		task.spawn(function()
			local deadline = os.clock() + 120
			while os.clock() < deadline and not Builder.loadCar(car.model, 10) do
				task.wait(5)
			end
			local now = character:FindFirstChild("Car")
			if now == m and Builder.complete(car.model) then
				local fresh = build(car)
				if fresh then
					Drive.set(player, fresh)
				end
			end
		end)
	end
	return true, nil
end

-- Out of the car on foot, beside it. Returns where the car was (nose along +Z) and its uid.
function GetIn.exit(player: Player): (CFrame?, string?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (character and humanoid and root) or not Drive.isDriving(player) then
		return nil, nil
	end
	local uid = riding[player]
	riding[player] = nil
	local up = humanoid.HipHeight + root.Size.Y / 2
	local here = root.CFrame
	local look = here.LookVector
	local feet = Vector3.new(here.Position.X, here.Position.Y - up, here.Position.Z)
	-- The car's nose is the way the avatar faced.
	local at = CFrame.lookAt(feet, feet - Vector3.new(look.X, 0, look.Z))
	Drive.set(player, false)
	-- Out on the driver's side.
	local side = Vector3.new(-look.Z, 0, look.X).Unit
	local spot = feet + side * 7
	character:PivotTo(CFrame.lookAt(spot + Vector3.new(0, up + 0.1, 0), spot + Vector3.new(look.X, up + 0.1, look.Z)))
	return at, uid
end

function GetIn.start(towns: any)
	local remotes = ReplicatedStorage:WaitForChild("Cartopia")
	local remote = Instance.new("RemoteFunction")
	remote.Name = "GetIn"
	remote.Parent = remotes
	remote.OnServerInvoke = function(player: Player, op: any, spec: any)
		if op == "enter" then
			return GetIn.enter(player, towns, spec)
		elseif op == "exit" then
			local at, uid = GetIn.exit(player)
			return at ~= nil, at, uid
		end
		return false, "bad op"
	end
	Players.PlayerRemoving:Connect(function(player)
		riding[player] = nil
	end)
end

return GetIn
