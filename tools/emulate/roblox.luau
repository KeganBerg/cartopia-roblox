--!nocheck
-- Runs the game's own Roblox scripts outside Roblox, with Lune (https://lune-org.github.io):
-- loads the place Rojo builds, and runs ModuleScripts from it with `script`, `game`, `require`
-- and the Roblox types set up as in Roblox. Methods Lune doesn't have (Model:PivotTo,
-- GetBoundingBox, events) are filled in here. No physics, rendering or network: enough to run
-- the code that builds things and check what it built.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local luau = require("@lune/luau")

local Emu = {}

local Instance, CFrame, Vector3 = roblox.Instance, roblox.CFrame, roblox.Vector3
local FixedCFrame

-- A signal that never fires (clicks, renders): connecting works, nothing happens.
local function signal()
	local s = {}
	function s:Connect(fn)
		return { Disconnect = function() end, Connected = true }
	end
	function s:Once(fn)
		return s:Connect(fn)
	end
	function s:Wait() end
	return s
end
for _, pair in { { "ClickDetector", "MouseClick" }, { "GuiButton", "Activated" }, { "Instance", "Destroying" }, { "BindableEvent", "Event" }, { "RemoteEvent", "OnClientEvent" }, { "RemoteEvent", "OnServerEvent" }, { "RunService", "RenderStepped" }, { "RunService", "Heartbeat" }, { "GuiButton", "MouseButton1Down" }, { "GuiButton", "MouseButton1Up" }, { "GuiObject", "MouseEnter" }, { "GuiObject", "MouseLeave" }, { "GuiObject", "InputBegan" }, { "GuiObject", "InputEnded" }, { "TextBox", "FocusLost" }, { "UserInputService", "InputBegan" }, { "UserInputService", "InputChanged" }, { "UserInputService", "InputEnded" }, { "Player", "CharacterAdded" }, { "Instance", "ChildAdded" }, { "Instance", "DescendantAdded" } } do
	pcall(roblox.implementProperty, pair[1], pair[2], function()
		return signal()
	end)
end

-- The emulator stands in for a desktop with a mouse (TouchEnabled and MouseEnabled are set on
-- the service when the place loads: they exist but have no default to read).
pcall(roblox.implementMethod, "UserInputService", "GetMouseLocation", function()
	return roblox.Vector2.new(640, 400)
end)

-- No frames run here, so nothing waits on them (a menu closing goes at once: client/Motion).
pcall(roblox.implementMethod, "RunService", "IsRunning", function()
	return false
end)

-- Text is measured with the same estimate the screen dumps use (tools/emulate/gui.luau).
pcall(roblox.implementMethod, "TextService", "GetTextSize", function(_, text, size, font)
	local family = if font == roblox.Enum.Font.FredokaOne then "FredokaOne" else "Nunito"
	return roblox.Vector2.new(require("./gui").textWidth(text, size, family), size)
end)

-- Property change signals never fire here either.
pcall(roblox.implementMethod, "Instance", "GetPropertyChangedSignal", function()
	return signal()
end)
pcall(roblox.implementMethod, "Instance", "GetAttributeChangedSignal", function()
	return signal()
end)

-- Lune's CFrame.lookAt faces the wrong way (its LookVector points away from the target), so the
-- game code gets a CFrame table with a correct lookAt and everything else from Lune's.
local function lookAt(at, target, up)
	up = up or Vector3.new(0, 1, 0)
	local look = (target - at).Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-6 then
		right = look:Cross(Vector3.new(0, 0, 1))
	end
	right = right.Unit
	local up2 = right:Cross(look)
	local back = -look
	return CFrame.new(at.X, at.Y, at.Z, right.X, up2.X, back.X, right.Y, up2.Y, back.Y, right.Z, up2.Z, back.Z)
end
FixedCFrame = setmetatable({ lookAt = lookAt }, { __index = CFrame })

local function pivotOf(model)
	local ok, wp = pcall(function()
		return model.WorldPivot
	end)
	if ok and wp and model:GetAttribute("EmuPivoted") then
		return wp
	end
	if model.PrimaryPart then
		return model.PrimaryPart.CFrame
	end
	return if ok and wp then wp else CFrame.new()
end

local pivots = setmetatable({}, { __mode = "k" })
roblox.implementMethod("Model", "GetPivot", function(model)
	return pivots[model] or pivotOf(model)
end)
roblox.implementMethod("Model", "PivotTo", function(model, cf)
	local old = pivots[model] or pivotOf(model)
	local delta = cf * old:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	pivots[model] = cf
	-- Lune hands out a new object for the same instance, so the table above misses it later on:
	-- keep the pivot on the model itself too.
	pcall(function()
		model.WorldPivot = cf
		model:SetAttribute("EmuPivoted", true)
	end)
end)
-- Model scale, as Roblox keeps it: ScaleTo resizes every part about the pivot.
roblox.implementMethod("Model", "GetScale", function(model)
	return model:GetAttribute("EmuScale") or 1
end)
roblox.implementMethod("Model", "ScaleTo", function(model, k)
	local by = k / (model:GetAttribute("EmuScale") or 1)
	local pivot = pivots[model] or pivotOf(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rel = pivot:Inverse() * d.CFrame
			d.Size = d.Size * by
			d.CFrame = pivot * (CFrame.new(rel.Position * by) * rel.Rotation)
		end
	end
	model:SetAttribute("EmuScale", k)
end)
roblox.implementMethod("Workspace", "BulkMoveTo", function(_, parts, cfs)
	for i, p in parts do
		p.CFrame = cfs[i]
	end
end)
roblox.implementMethod("Model", "GetBoundingBox", function(model)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size / 2
			for _, c in { Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, -1) } do
				local w = cf * (s * c)
				lo = lo:Min(w)
				hi = hi:Max(w)
			end
		end
	end
	if lo.X == math.huge then
		return CFrame.new(), Vector3.zero
	end
	return CFrame.new((lo + hi) / 2), hi - lo
end)
roblox.implementMethod("Instance", "WaitForChild", function(inst, name)
	return inst:FindFirstChild(name) or error(`emulator: {inst:GetFullName()} has no {name}`)
end)

roblox.implementMethod("TweenService", "Create", function(_, inst, _info, goal)
	local tween = {}
	function tween:Play()
		for k, v in goal do
			inst[k] = v
		end
	end
	function tween:Cancel() end
	function tween:Pause() end
	tween.Completed = { Connect = function() return { Disconnect = function() end } end, Wait = function() end }
	return tween
end)

local waiting = {}
-- task: spawn runs at once, waits return at once (nothing here runs forever).
local Task = {
	spawn = function(fn, ...)
		local co = coroutine.create(fn)
		local ok, err = coroutine.resume(co, ...)
		if not ok then
			print("ERROR in a task:", err)
		end
		return co
	end,
	defer = function(fn, ...)
		fn(...)
	end,
	-- Delayed work runs when a harness moves time on (Emu.resumeWaits), not before.
	delay = function(_, fn, ...)
		local co = coroutine.create(function(...)
			coroutine.yield()
			fn(...)
		end)
		coroutine.resume(co, ...)
		table.insert(waiting, co)
		return co
	end,
	wait = function()
		local co = coroutine.running()
		if coroutine.isyieldable() then
			table.insert(waiting, co)
			coroutine.yield()
		end
		return 0
	end,
}
-- Wakes everything parked in task.wait once (a harness calls this to move time on).
function Emu.resumeWaits()
	local list = waiting
	waiting = {}
	for _, co in list do
		if coroutine.status(co) == "suspended" then
			local ok, err = coroutine.resume(co)
			if not ok then
				print("ERROR in a task:", err)
			end
		end
	end
end

-- Stands in for InsertService:LoadAsset with the mesh packs as Roblox imports them: a Model of
-- MeshParts named by mesh key. Each is marked Imported, so render.mjs turns its geometry half round
-- about Y the way Roblox's glTF import does, and the game's own correction for that gets checked.
function Emu.fakeMeshPacks(emu)
	local Meshes = emu.require(emu.game:GetService("ReplicatedStorage").Shared.Models.Meshes)
	roblox.implementMethod("InsertService", "LoadAsset", function(_, asset)
		local model = Instance.new("Model")
		for key, m in Meshes.MESHES do
			if m.asset == asset then
				local part = Instance.new("MeshPart")
				part.Name = key
				part.Size = m.size
				part:SetAttribute("Mesh", key)
				part:SetAttribute("Imported", true)
				part.Parent = model
			end
		end
		return model
	end)
end

-- Roblox's seeded Random, which Lune doesn't have: the same calls on a small 32-bit generator
-- (mulberry32), so a seed always gives the same run. Not Roblox's own sequence.
Emu.Random = {
	new = function(seed)
		local state = math.floor(seed or os.clock() * 1e6) % 4294967296
		local r = {}
		local function nextFloat()
			state = (state + 0x6D2B79F5) % 4294967296
			local t = state
			t = bit32.bxor(t, bit32.rshift(t, 15)) * bit32.bor(t, 1) % 4294967296
			t = bit32.bxor(t, (t + bit32.bxor(t, bit32.rshift(t, 7)) * bit32.bor(t, 61) % 4294967296) % 4294967296)
			return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
		end
		function r:NextNumber(lo, hi)
			lo, hi = lo or 0, hi or 1
			return lo + nextFloat() * (hi - lo)
		end
		function r:NextInteger(lo, hi)
			return lo + math.floor(nextFloat() * (hi - lo + 1))
		end
		return r
	end,
}

function Emu.load(placeFile: string)
	local game = roblox.deserializePlace(fs.readFile(placeFile))
	pcall(function()
		local uis = game:GetService("UserInputService")
		uis.TouchEnabled = false
		uis.MouseEnabled = true
	end)
	-- Cameras report the reference screen size (no default otherwise).
	local ws = game:GetService("Workspace")
	pcall(function()
		local cam = ws.CurrentCamera
		if not cam then
			cam = roblox.Instance.new("Camera")
			cam.Parent = ws
			ws.CurrentCamera = cam
		end
		cam.ViewportSize = roblox.Vector2.new(1280, 800)
	end)
	local cache = {}
	local env
	local function run(module)
		-- Lune can hand out a fresh userdata per lookup, so key modules by path, not identity.
		local key = module:GetFullName()
		if cache[key] ~= nil then
			return cache[key]
		end
		local fn = luau.load(module.Source, { debugName = module:GetFullName(), environment = env(module) })
		local result = fn()
		cache[key] = result
		return result
	end
	local function resolve(from, path: string)
		-- Roblox's string requires: "./x" is a sibling, "../x" goes up one more.
		local at = from.Parent
		for part in string.gmatch(path, "[^/]+") do
			if part == "." then
				continue
			elseif part == ".." then
				at = at.Parent
			else
				at = at:FindFirstChild(part) or error(`emulator: can't find {path} from {from:GetFullName()}`)
			end
		end
		return at
	end
	env = function(module)
		local e = setmetatable({
			script = module,
			game = game,
			workspace = game:GetService("Workspace"),
			task = Task,
			require = function(x)
				if type(x) == "string" then
					return run(resolve(module, x))
				end
				return run(x)
			end,
			warn = function(...)
				print("WARN", ...)
			end,
			DateTime = { now = function() return { UnixTimestampMillis = os.time() * 1000 } end },
			-- Tweens jump straight to where they end: a still picture has no in-between.
			TweenInfo = { new = function(...) return { ... } end },
		}, nil)
		-- Lune's load doesn't follow __index on the environment, so copy the Roblox types in.
		for _, k in { "Instance", "Vector3", "Vector2", "Color3", "UDim", "UDim2", "Enum", "ColorSequence", "ColorSequenceKeypoint", "NumberSequence", "NumberSequenceKeypoint", "NumberRange", "BrickColor", "Rect", "Ray", "Font", "Content" } do
			e[k] = roblox[k]
		end
		e.CFrame = FixedCFrame
		e.Random = e.Random or Emu.Random
		-- Nothing is laid out here, so screens read a zero size, as before Roblox's first frame.
		e.Instance = setmetatable({
			new = function(class, parent)
				local inst = roblox.Instance.new(class)
				if inst:IsA("GuiBase2d") then
					inst.AbsoluteSize = roblox.Vector2.new(0, 0)
					inst.AbsolutePosition = roblox.Vector2.new(0, 0)
				end
				if parent then
					inst.Parent = parent
				end
				return inst
			end,
		}, { __index = roblox.Instance })
		return e
	end
	return {
		game = game,
		require = function(inst)
			return run(inst)
		end,
	}
end

return Emu
