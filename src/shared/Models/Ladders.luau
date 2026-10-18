--!strict
-- The ladders on the web game's buildings (a garage's ladder to its roof, the billboard's up to
-- its catwalk), found in a model's Catalog parts, so a player walking the town can climb them.
--
-- The web models have no ladder piece: a ladder is two tall rails and a run of evenly spaced
-- rungs, all plain blocks. Ladders.find spots the rungs and works out where an invisible truss
-- (what a Roblox character climbs) has to stand: on the ladder, clear of any ledge or catwalk it
-- passes under, and level at the top with what the player steps off onto. Ladders.add puts the
-- trusses into a built model.

local Ladders = {}

-- Required when first used, so Ladders.find also runs outside Roblox (tests/ladders.luau).
local function catalog(): any
	return require(script.Parent.Catalog) :: any
end

export type Ladder = {
	-- Middle of the truss on the ground plan, in the model's studs.
	x: number,
	z: number,
	-- The truss: its width along the rungs (sx or sz, the other is 2), bottom and top.
	sx: number,
	sz: number,
	bottom: number,
	top: number,
	-- The parts (indexes into the model's Catalog list) that draw the ladder: the truss does the
	-- climbing, so they take no collisions.
	parts: { number },
}

-- A Roblox truss is 2 studs thick and comes in 2 stud steps.
local TRUSS = 2

-- A part's box in the model: its middle and half its size along each world axis.
local function box(p: { any }): (number, number, number, number, number, number)
	local qx, qy, qz, qw = p[5], p[6], p[7], p[8]
	local hx, hy, hz = p[9] / 2, p[10] / 2, p[11] / 2
	-- The rotation's columns (where the part's own X, Y and Z point).
	local xx, xy, xz = 1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy + qz * qw), 2 * (qx * qz - qy * qw)
	local yx, yy, yz = 2 * (qx * qy - qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz + qx * qw)
	local zx, zy, zz = 2 * (qx * qz + qy * qw), 2 * (qy * qz - qx * qw), 1 - 2 * (qx * qx + qy * qy)
	return p[2],
		p[3],
		p[4],
		math.abs(xx) * hx + math.abs(yx) * hy + math.abs(zx) * hz,
		math.abs(xy) * hx + math.abs(yy) * hy + math.abs(zy) * hz,
		math.abs(xz) * hx + math.abs(yz) * hy + math.abs(zz) * hz
end

local function near(a: number, b: number, by: number?): boolean
	return math.abs(a - b) <= (by or 0.05)
end

-- The ladders in a model's Catalog parts.
function Ladders.find(parts: { { any } }): { Ladder }
	-- Rungs: four or more of the same thin bar, one above the other, 1 to 3 studs apart.
	local groups: { [string]: { number } } = {}
	local order: { string } = {}
	for i, p in parts do
		if p[1] ~= "b" then
			continue
		end
		local _, _, _, hx, hy, hz = box(p)
		local long, thin = math.max(hx, hz) * 2, math.min(hx, hz) * 2
		if hy * 2 <= 0.4 and thin <= 0.4 and long >= 1 and long <= 4 then
			local key = string.format("%.2f|%.2f|%.2f|%.2f|%.2f|%s", p[2], p[4], hx, hy, hz, tostring(p[12]))
			if not groups[key] then
				groups[key] = {}
				table.insert(order, key)
			end
			table.insert(groups[key], i)
		end
	end
	local found: { Ladder } = {}
	for _, key in order do
		local rungs = groups[key]
		if #rungs < 4 then
			continue
		end
		table.sort(rungs, function(a, b)
			return parts[a][3] < parts[b][3]
		end)
		local step = parts[rungs[2]][3] - parts[rungs[1]][3]
		local even = step >= 1 and step <= 3
		for k = 3, #rungs do
			if not near(parts[rungs[k]][3] - parts[rungs[k - 1]][3], step) then
				even = false
			end
		end
		if not even then
			continue
		end
		local first = parts[rungs[1]]
		local x, _, z, hx, _, hz = box(first)
		-- The rungs run along X or Z; the wall is behind them, towards the model's middle.
		local alongX = hx > hz
		local half = if alongX then hx else hz
		local members = table.clone(rungs)
		local low, high = first[3] - step, parts[rungs[#rungs]][3] + step / 2
		-- The rails: tall bars of the ladder's look at the rungs' ends.
		for i, p in parts do
			local px, py, pz, phx, phy, phz = box(p)
			if p[12] == first[12] and phy * 2 >= step * 2 and math.max(phx, phz) <= 0.3 then
				local onEnd = if alongX then near(pz, z, 0.2) and near(math.abs(px - x), half, 0.3) else near(px, x, 0.2) and near(math.abs(pz - z), half, 0.3)
				if onEnd then
					table.insert(members, i)
					low = math.min(low, py - phy)
					high = math.max(high, py + phy)
				end
			end
		end
		low = math.max(low, 0)
		local isMember: { [number]: boolean } = {}
		for _, i in members do
			isMember[i] = true
		end
		-- Out from the wall: across the rungs, away from the model's middle.
		local out = if alongX then (if z >= 0 then 1 else -1) else (if x >= 0 then 1 else -1)
		local line = if alongX then z else x
		-- The truss sits on the ladder, pushed out past any ledge or catwalk above that sticks out
		-- further (a character climbing its face would bump its head), and reaches up level with
		-- the top of whatever is just inside it at the top (the roof's edge, a railing).
		local face = line + out * TRUSS / 2
		local mid = if alongX then x else z
		-- Each other part as: along the rungs (middle, half), out from the ladder line (its inner
		-- and outer edges), bottom and top.
		local others = {}
		for i, p in parts do
			if not isMember[i] then
				local px, py, pz, phx, phy, phz = box(p)
				local a, ha, c, hc = px, phx, pz, phz
				if not alongX then
					a, ha, c, hc = pz, phz, px, phx
				end
				if math.abs(a - mid) <= ha + half + 0.5 then
					table.insert(others, { inner = (c - line) * out - hc, outer = (c - line) * out + hc, bottom = py - phy, top = py + phy })
				end
			end
		end
		for _, o in others do
			local reach = (face - line) * out
			if o.bottom > low + 4 and o.bottom < high and o.outer > reach and o.outer - reach < 3 then
				face = line + out * o.outer
			end
		end
		-- What the player steps off onto: reaching to within 3 studs of the ladder from inside, no
		-- higher than a little over the ladder's own top.
		local top = low
		for _, o in others do
			if o.outer > -3 and o.inner < (face - line) * out and o.top <= high + 1.5 and o.top > top then
				top = o.top
			end
		end
		if top <= low + step then
			top = high
		end
		local height = math.max(TRUSS, math.ceil((top - low) / TRUSS - 0.05) * TRUSS)
		local width = math.max(TRUSS, math.floor(half * 2 / TRUSS + 0.5) * TRUSS)
		local centre = face - out * TRUSS / 2
		table.insert(found, {
			x = if alongX then x else centre,
			z = if alongX then centre else z,
			sx = if alongX then width else TRUSS,
			sz = if alongX then TRUSS else width,
			bottom = top - height,
			top = top,
			parts = members,
		})
	end
	return found
end

local cache: { [string]: { Ladder } } = {}

-- The ladders of a Catalog model (cached).
function Ladders.of(name: string): { Ladder }
	local hit = cache[name]
	if hit then
		return hit
	end
	local parts = catalog().MODELS[name]
	local list = if parts then Ladders.find(parts) else {}
	cache[name] = list
	return list
end

-- Puts an invisible truss on each ladder of a freshly built model (Builder.build(name), still at
-- its own origin), and stops the ladder's own bars getting in the way of the climb.
function Ladders.add(model: Model, name: string)
	local list = Ladders.of(name)
	if #list == 0 then
		return
	end
	local parts = catalog().MODELS[name]
	local pivot = model:GetPivot()
	for _, ladder in list do
		-- The ladder's own bars, found by where they sit (a built part keeps its Catalog place).
		for _, i in ladder.parts do
			local p = parts[i]
			local at = pivot * Vector3.new(p[2], p[3], p[4])
			for _, d in model:GetChildren() do
				if d:IsA("BasePart") and (d.CFrame.Position - at).Magnitude < 0.01 and near(d.Size.Y, p[10], 0.01) then
					d:SetAttribute("Ladder", true)
				end
			end
		end
		local truss = Instance.new("TrussPart")
		truss.Name = "Climb"
		truss.Style = Enum.Style.NoSupports
		truss.Size = Vector3.new(ladder.sx, ladder.top - ladder.bottom, ladder.sz)
		truss.CFrame = pivot * CFrame.new(ladder.x, (ladder.top + ladder.bottom) / 2, ladder.z)
		truss.Anchored = true
		truss.CanCollide = true
		truss.CanQuery = false
		truss.CanTouch = false
		truss.CastShadow = false
		truss.Transparency = 1
		truss.Parent = model
	end
end

return Ladders
