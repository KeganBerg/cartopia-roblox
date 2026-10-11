--!nocheck
-- Catalog checks ported from the web game's src/game/data.test.ts. Formula results are covered by
-- parity.luau; these check the catalog itself hangs together.
local Data = require("../src/shared/Data")
local expect = require("./expect")

return function(test)
	test("gives unknown ids from newer builds harmless stand-ins", function()
		local d = Data.buildingDef("crew-house-from-the-future")
		expect(d.parked).toBe(true)
		expect(d.jobSeconds).toBe(nil)
		expect(Data.buildingDef("crew-house-from-the-future")).toBe(d)
		expect(Data.buildingDef("pizza").parked).toBe(nil)
		local c = Data.carDef("future-car")
		expect(c.parked).toBe(true)
		expect(c.id).toBe("future-car")
		expect(Data.carDef("pip").parked).toBe(nil)
		-- The stand-in is a copy: the starter car itself is untouched.
		expect(Data.CARS[1].parked).toBe(nil)
		expect(#Data.CARS[1].likes).toBe(3)
	end)

	test("only lets cars love businesses that take a driver, and every one has fans", function()
		for _, c in Data.CARS do
			expect(#c.likes).toBe(3)
			for _, id in c.likes do
				if not (Data.knownBuilding(id) and Data.takesDriver(Data.buildingDef(id))) then
					error(`{c.id} loves {id}, which takes no driver`)
				end
			end
		end
		for _, d in Data.BUILDINGS do
			if Data.takesDriver(d) then
				local fan = false
				for _, c in Data.CARS do
					fan = fan or Data.loves(c, d.id)
				end
				if not fan then
					error(`{d.id} has no fans`)
				end
			end
		end
	end)

	test("gives every skill to at least one car", function()
		for id in Data.SKILLS do
			local found = false
			for _, c in Data.CARS do
				found = found or c.skill == id
			end
			if not found then
				error(`no car has {id}`)
			end
		end
	end)

	test("gives every vehicle a part for every slot", function()
		for _, c in Data.CARS do
			for _, s in Data.MOD_SLOTS do
				local any = false
				for _, m in Data.MODS do
					any = any or (m.slot == s.id and Data.modFits(m, c.body))
				end
				if not any then
					error(`{c.id} has no {s.id}`)
				end
			end
		end
	end)

	test("prices every mod in coins or bucks, never both, with unique ids", function()
		local seen = {}
		for _, m in Data.MODS do
			expect(seen[m.id]).toBe(nil)
			seen[m.id] = true
			expect(m.bucks > 0).toBe(m.coins == 0 and m.parts == 0)
		end
	end)

	test("puts every car in exactly one collection set", function()
		local count = {}
		for _, s in Data.CAR_SETS do
			for _, id in s.cars do
				count[id] = (count[id] or 0) + 1
			end
		end
		for _, c in Data.CARS do
			expect(count[c.id]).toBe(1)
		end
	end)

	test("says where to find each car", function()
		expect(Data.carSource(Data.carDef("bug")).text).toBe("Rusty's · Suburbs")
		expect(Data.carSource(Data.carDef("lambo")).text).toBe("Showroom · 💎90")
		expect(Data.carSource(Data.carDef("vette")).text).toBe("Showroom · Lv 15")
	end)
end
