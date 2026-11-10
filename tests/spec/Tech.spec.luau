return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Tech = Loader.get("ReplicatedStorage.Shared.Progression.Tech")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")
	local Sanitize = Loader.get("ServerScriptService.Server.Data.Sanitize")

	local function freshData()
		return Sanitize.run(nil, 0)
	end

	describe("Tech", function()
		it("has a valid tree (prerequisites, no cycles, real features, reachable costs)", function()
			local ok, problems = Tech.validate()
			if not ok then
				error(table.concat(problems, "\n"))
			end
		end)

		it("only gates features the game implements", function()
			for feature in Tech.FeatureOwner do
				if not Tech.featureExists(feature) then
					error("unknown feature " .. feature)
				end
			end
		end)

		it("keeps the basic commands free", function()
			for _, name in
				{
					"move_up",
					"move_down",
					"move_left",
					"move_right",
					"plant",
					"harvest",
					"charge",
					"if",
					"can_harvest",
					"is_empty",
					"deposit",
					"refine",
					"get_battery",
				}
			do
				expect(Tech.isFeatureUnlocked({}, name)).toBe(true)
			end
			expect(Tech.isFeatureUnlocked({}, "crop:wheat")).toBe(false)
			expect(Tech.isFeatureUnlocked({}, "while")).toBe(false)
			expect(Tech.isFeatureUnlocked({ loops = true }, "while")).toBe(true)
			expect(Tech.isFeatureUnlocked({ wheat = true }, "crop:wheat")).toBe(true)
		end)

		it("pays the full multi-currency cost and records the unlock", function()
			local data = freshData()
			data.techUnlocks.loops = true
			data.techUnlocks.grid_1 = true
			data.techUnlocks.wheat = true
			data.currencies.hay = 100
			data.currencies.wheat = 130
			local ok = Tech.research(data, "grid_2") -- 120 wheat (Hay is only spent on the first nodes)
			expect(ok).toBe(true)
			expect(data.currencies.hay).toBe(100)
			expect(data.currencies.wheat).toBe(10)
			expect(data.techUnlocks.grid_2).toBe(true)
		end)

		it("changes nothing when ANY currency is short", function()
			local data = freshData()
			data.techUnlocks.loops = true
			data.techUnlocks.grid_1 = true
			data.techUnlocks.wheat = true
			data.currencies.hay = 1000
			data.currencies.wheat = 59 -- needs 60
			local ok, reason = Tech.research(data, "grid_2")
			expect(ok).toBe(false)
			expect(reason).toContain("Not enough")
			expect(data.currencies.hay).toBe(1000)
			expect(data.techUnlocks.grid_2).toBeNil()
		end)

		it("requires prerequisites", function()
			local data = freshData()
			data.currencies.hay = 1000
			data.currencies.wheat = 1000
			local ok, reason = Tech.research(data, "grid_2")
			expect(ok).toBe(false)
			expect(reason).toContain("Grid Expansion I")
			expect(reason).toContain("Wheat")
			expect(Tech.status(data.techUnlocks, "grid_2")).toBe("locked")
			expect(Tech.status(data.techUnlocks, "loops")).toBe("available")
		end)

		it("refuses to research twice or unknown nodes", function()
			local data = freshData()
			data.currencies.hay = 100
			expect((Tech.research(data, "loops"))).toBe(true)
			expect((Tech.research(data, "loops"))).toBe(false)
			expect(data.currencies.hay).toBe(91)
			expect((Tech.research(data, "nope"))).toBe(false)
		end)

		it("adds stat bonuses on top of the base drone", function()
			local base = Tech.stats({})
			expect(base.batteryCapacity).toBe(GameConfig.Drone.BaseBattery)
			expect(base.speedMultiplier).toBe(1)
			expect(base.gridSize).toBe(GameConfig.Grid.StartingSize)
			expect(base.waterRadius).toBe(0)
			local upgraded = Tech.stats({
				battery_1 = true,
				battery_2 = true,
				motors_1 = true,
				fast_charger = true,
				grid_1 = true,
				grid_2 = true,
				watering_cans = true,
				water_tanks = true,
			})
			expect(upgraded.batteryCapacity).toBe(GameConfig.Drone.BaseBattery + 120)
			expect(upgraded.speedMultiplier).toBe(1.2)
			expect(upgraded.chargeRate).toBe(GameConfig.Drone.BaseChargeRate * 2)
			expect(upgraded.gridSize).toBe(5)
			expect(upgraded.waterRadius).toBe(1)
			expect(upgraded.waterCapacity).toBe(GameConfig.Drone.BaseWater + 30)
		end)

		it("formats costs in currency order", function()
			expect(Tech.formatCost("grid_3")).toBe("200 Wheat + 30 Biomass")
		end)

		it("explains locked features with the research to do", function()
			local message = Tech.lockedMessage("variables")
			expect(message).toContain("variables (a = 2)")
			expect(message).toContain('Research Loops "while True:"') -- variables come with Loops
			expect(Tech.lockedMessage("crop:carrot")).toContain("Carrots")
		end)

		it("knows which raw currencies are farmable", function()
			local start = Tech.farmableCurrencies({})
			expect(start.hay).toBe(true)
			expect(start.wheat).toBeNil()
			local later = Tech.farmableCurrencies({ wheat = true, fossils = true })
			expect(later.wheat).toBe(true)
			expect(later.fossil).toBe(true)
		end)
	end)
end
