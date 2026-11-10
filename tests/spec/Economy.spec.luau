return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Economy = Loader.get("ServerScriptService.Server.Progression.Economy")
	local Sanitize = Loader.get("ServerScriptService.Server.Data.Sanitize")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")
	local CropConfig = Loader.get("ReplicatedStorage.Shared.Config.CropConfig")

	describe("Economy", function()
		it("fills the cargo hold up to its capacity", function()
			local data = Sanitize.run(nil, 0)
			expect(Economy.addToCargo(data, "wheat", 6, 10)).toBe(6)
			expect(Economy.addToCargo(data, "carrot", 6, 10)).toBe(4)
			expect(Economy.addToCargo(data, "wheat", 1, 10)).toBe(0)
			expect(Economy.cargoTotal(data)).toBe(10)
			expect(Economy.addToCargo(data, "notacrop", 1, 99)).toBe(0)
		end)

		it("banks the hold as raw currencies at the charger", function()
			local data = Sanitize.run(nil, 0)
			Economy.addToCargo(data, "wheat", 3, 10)
			Economy.addToCargo(data, "carrot", 2, 10)
			local moved, total = Economy.unloadCargo(data)
			expect(total).toBe(5)
			expect(moved).toEqual({ wheat = 3, carrot = 2 })
			expect(data.currencies.wheat).toBe(3)
			expect(data.currencies.carrot).toBe(2)
			expect(Economy.cargoTotal(data)).toBe(0)
		end)

		it("turns cargo into Biomass and keeps the remainder", function()
			local data = Sanitize.run(nil, 0)
			Economy.addToCargo(data, "wheat", 7, 20) -- 7 points
			Economy.addToCargo(data, "carrot", 1, 20) -- 3 points
			local gained, used = Economy.depositCargo(data) -- 10 points -> 2 biomass
			expect(gained).toBe(2)
			expect(used).toBe(8)
			expect(data.factoryBuffer).toBe(0)
			Economy.addToCargo(data, "wheat", 3, 20)
			expect((Economy.depositCargo(data))).toBe(0)
			expect(data.factoryBuffer).toBe(3) -- kept for the next deposit
			Economy.addToCargo(data, "wheat", 2, 20)
			expect((Economy.depositCargo(data))).toBe(1)
			expect(data.currencies.biomass).toBe(3)
		end)

		it("never turns Hay into Biomass: it stays in the hold for the charger", function()
			local data = Sanitize.run(nil, 0)
			Economy.addToCargo(data, "hay", 10, 20)
			expect(Economy.depositable(data)).toBe(0)
			local gained, used = Economy.depositCargo(data)
			expect(gained).toBe(0)
			expect(used).toBe(0)
			expect(data.cargo.hay).toBe(10)
			Economy.addToCargo(data, "wheat", 5, 20)
			expect(Economy.depositable(data)).toBe(5)
			expect((Economy.depositCargo(data))).toBe(1) -- 5 wheat points -> 1 Biomass
			expect(data.cargo.hay).toBe(10)
			expect(data.cargo.wheat).toBe(0)
		end)

		it("keys the hold by raw currency and values fossils highly", function()
			local data = Sanitize.run(nil, 0)
			expect(Economy.addToCargo(data, "biomass", 1, 10)).toBe(0) -- processed goods never ride in the hold
			expect(Economy.addToCargo(data, "fossil", 1, 10)).toBe(1)
			local gained = Economy.depositCargo(data) -- 25 points -> 5 biomass
			expect(gained).toBe(5)
			expect(data.cargo.fossil).toBe(0)
		end)

		it("refines Biomass into Biofuel in whole batches", function()
			local data = Sanitize.run(nil, 0)
			data.currencies.biomass = 10
			local gained, used = Economy.refine(data, 10)
			expect(gained).toBe(2)
			expect(used).toBe(8)
			expect(data.currencies.biomass).toBe(2)
			expect(data.currencies.biofuel).toBe(2)
			expect((Economy.refine(data, 10))).toBe(0)
		end)

		it("keeps dig() below a wheat pipeline (no `while True: dig()` meta)", function()
			local points = GameConfig.Factory.BiomassPoints
			local times = GameConfig.Drone.ActionTimes
			-- Dig's BEST case: every dig is on fresh soil, no moves, no exhaustion waits.
			local digPerSecond = GameConfig.Dig.Chance * points[GameConfig.Dig.currency] / times.dig
			-- One wheat tile per plant + harvest + move, ignoring growth time (also a best case).
			local wheat = CropConfig.Crops.wheat
			local wheatPerSecond = wheat.yield * points.wheat / (times.plant + times.harvest + times.move)
			expect(digPerSecond < wheatPerSecond).toBe(true)
			expect(points.hay).toBe(0) -- endless wild grass is never Biomass
			expect(GameConfig.Dig.ExhaustSeconds > 0).toBe(true)
		end)
	end)
end
