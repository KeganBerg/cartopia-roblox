--!strict
-- A car's paint job (the web game's PaintMaterial and stripes): its colour, the finish that colour
-- is drawn in, and racing stripes laid over the body. Used for town cars, the drag strip and the
-- garage's turntable alike, so a paint job looks the same everywhere.

local Paint = {}

local LIFT = 0.3

export type Job = { color: string, finish: string?, stripe: (string | boolean)? }

-- Each finish (data.ts FINISH_LOOK): the colour it leans toward and how far, and the Roblox
-- material closest to its shine.
local FINISH: { [string]: { material: Enum.Material, toward: string?, lift: number, reflect: number } } = {
	gloss = { material = Enum.Material.SmoothPlastic, lift = 0, reflect = 0.08 },
	matte = { material = Enum.Material.Plastic, lift = 0, reflect = 0 },
	chrome = { material = Enum.Material.Foil, toward = "#ffffff", lift = 0.15, reflect = 0.35 },
	gold = { material = Enum.Material.Foil, toward = "#ffc83d", lift = 0.62, reflect = 0.25 },
	diamond = { material = Enum.Material.Glass, toward = "#e6f7ff", lift = 0.6, reflect = 0.3 },
	galaxy = { material = Enum.Material.Glass, toward = "#3b1f8f", lift = 0.6, reflect = 0.2 },
}

-- The colour a paint job shows in its finish.
function Paint.color(color: string, finish: string?): Color3
	local f = FINISH[finish or "gloss"] or FINISH.gloss
	local c = Color3.fromHex(color)
	if f.toward then
		c = c:Lerp(Color3.fromHex(f.toward), f.lift)
	end
	return c
end

-- What a car wears, from its save: no finish is gloss, no stripe is false (data.ts STRIPES).
function Paint.jobOf(car: any): Job
	return { color = car.color, finish = car.finish or "gloss", stripe = car.stripe or false }
end

function Paint.same(a: Job, b: Job): boolean
	return a.color == b.color and (a.finish or "gloss") == (b.finish or "gloss") and (a.stripe or false) == (b.stripe or false)
end

-- A short key for a paint job, to tell when a drawn car needs painting again.
function Paint.key(job: Job): string
	return `{job.color}|{job.finish or "gloss"}|{job.stripe or ""}`
end

-- Paints a car's body. `stripes`: the car's stripe pieces (Builder's "stripe:<car>" model, or the
-- client's ModelLibrary copy, left as it is), copied on when the job has a stripe colour; any old ones go.
function Paint.apply(model: Model, job: Job, stripes: Model?)
	local f = FINISH[job.finish or "gloss"] or FINISH.gloss
	local c = Paint.color(job.color, job.finish)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Paint") then
			d.Color = c
			d.Material = f.material
			d.Reflectance = f.reflect
		end
	end
	local old = model:FindFirstChild("Stripes")
	if old then
		old:Destroy()
	end
	local stripe = job.stripe
	if stripes and type(stripe) == "string" then
		local s = stripes:Clone()
		s.Name = "Stripes"
		local at = model:GetPivot()
		for _, d in s:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = Color3.fromHex(stripe)
				d.Material = Enum.Material.SmoothPlastic
				-- A touch higher than the web lays them: Roblox's simpler body meshes can bulge
				-- through a stripe lying a hair off the paint.
				d.CFrame = at * CFrame.new(0, LIFT, 0) * d.CFrame
			end
		end
		s.Parent = model
	end
end

return Paint
