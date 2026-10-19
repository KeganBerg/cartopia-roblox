--!nocheck
-- What the town's weather (client/TownWeather) set up, as plain tables for render.mjs: the light
-- (Lighting and its Grade, Glow and Air effects), every particle emitter with the box it emits
-- from, and every beam (lightning, rainbow) as its curve. The emulator runs no particles or
-- post-processing, so render.mjs pictures these from the values the game set.

local W = {}

local function first(seq)
	return seq.Keypoints[1].Value
end
local function at(seq, t)
	local k = seq.Keypoints
	for i = 1, #k - 1 do
		if t <= k[i + 1].Time then
			local a, b = k[i], k[i + 1]
			local f = if b.Time > a.Time then (t - a.Time) / (b.Time - a.Time) else 0
			return a.Value + (b.Value - a.Value) * f
		end
	end
	return k[#k].Value
end
local function samples(seq, n)
	local out = {}
	for i = 0, n do
		table.insert(out, at(seq, i / n))
	end
	return out
end
local function cf(c)
	return { c:GetComponents() }
end
local function enumName(e)
	return tostring(e):match("%.(%w+)$")
end

function W.lighting(game)
	local L = game:GetService("Lighting")
	local grade = L:FindFirstChild("Grade")
	local glow = L:FindFirstChild("Glow")
	local air = L:FindFirstChild("Air")
	return {
		brightness = L.Brightness,
		sun = L.ColorShift_Top:ToHex(),
		ambient = L.OutdoorAmbient:ToHex(),
		exposure = L.ExposureCompensation,
		contrast = grade and grade.Contrast or 0,
		saturation = grade and grade.Saturation or 0,
		tint = grade and grade.TintColor:ToHex() or "ffffff",
		bloom = glow and glow.Intensity or 0,
		air = air and { density = air.Density, color = air.Color:ToHex(), haze = air.Haze } or nil,
	}
end

function W.effects(folder)
	local emitters, beams = {}, {}
	if not folder then
		return { emitters = emitters, beams = beams }
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Enabled and d.Rate > 0 then
			local part = d.Parent
			table.insert(emitters, {
				name = d.Name,
				cf = cf(part.CFrame),
				size = { part.Size.X, part.Size.Y, part.Size.Z },
				dir = enumName(d.EmissionDirection),
				orientation = enumName(d.Orientation),
				rate = d.Rate,
				life = { d.Lifetime.Min, d.Lifetime.Max },
				speed = { d.Speed.Min, d.Speed.Max },
				psize = samples(d.Size, 4),
				squash = first(d.Squash),
				color = d.Color.Keypoints[1].Value:ToHex(),
				transparency = samples(d.Transparency, 10),
				texture = d.Texture,
			})
		elseif d:IsA("Beam") and d.Enabled and d.Attachment0 and d.Attachment1 then
			local a0, a1 = d.Attachment0, d.Attachment1
			local c0, c1 = a0.Parent.CFrame * a0.CFrame, a1.Parent.CFrame * a1.CFrame
			local p0, p3 = c0.Position, c1.Position
			local p1 = p0 + c0.RightVector * d.CurveSize0
			local p2 = p3 - c1.RightVector * d.CurveSize1
			local pts = {}
			local n = math.max(1, d.Segments)
			for i = 0, n do
				local t = i / n
				local u = 1 - t
				local p = p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
				table.insert(pts, { p.X, p.Y, p.Z })
			end
			table.insert(beams, {
				name = d.Name,
				points = pts,
				width = { d.Width0, d.Width1 },
				color = d.Color.Keypoints[1].Value:ToHex(),
				transparency = samples(d.Transparency, n),
				light = d.LightEmission,
			})
		end
	end
	return { emitters = emitters, beams = beams }
end

return W
