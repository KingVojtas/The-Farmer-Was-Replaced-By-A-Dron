return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Sanitize = Loader.get("ServerScriptService.Server.Data.Sanitize")
	local DataTemplate = Loader.get("ServerScriptService.Server.Data.DataTemplate")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")

	describe("Sanitize", function()
		it("creates the v3 template for new players", function()
			local data = Sanitize.run(nil, 1234)
			expect(data.schemaVersion).toBe(DataTemplate.SCHEMA_VERSION)
			expect(data.schemaVersion).toBe(3)
			expect(data.field.savedAt).toBe(0)
			expect(#data.field.tiles).toBe(0)
			expect(data.currencies.hay).toBe(0)
			expect(data.currencies.wheat).toBe(0)
			expect(data.currencies.batteries).toBe(0)
			expect(data.cargo.hay).toBe(0)
			expect(data.cargo.fossil).toBe(0)
			expect(data.cargo.biomass).toBeNil() -- only raw currencies ride in the hold
			expect(next(data.techUnlocks)).toBeNil()
			expect(data.gridSize).toBeNil() -- the field size comes from research now
			expect(#data.scripts).toBe(GameConfig.Script.Slots)
			expect(data.scripts[1]).toBe(GameConfig.StarterScript)
			expect(data.scripts[2]).toBe("")
			expect(data.scriptNames).toEqual({ "main", "utils", "lab" })
			expect(data.cosmetics.equipped).toEqual({ paint = "factory", hat = "none" })
			expect(next(data.cosmetics.owned)).toBeNil()
			expect(data.firstJoin).toBe(1234)
			expect(#data.receipts).toBe(0)
		end)

		it("repairs wrong types and out-of-range values", function()
			local data = Sanitize.run({
				schemaVersion = 2,
				currencies = { wheat = "lots", batteries = 0 / 0, biomass = -5, [3] = 9 },
				techUnlocks = { loops = true, grid_1 = "yes" },
				cargo = "nope",
				factoryBuffer = 999,
				cropsHarvested = -5,
				scripts = { 5, "ok", "\255bad" },
				scriptNames = { "print", "ok_name", "ok_name" },
				cosmetics = {
					owned = { halo = true, top_hat = "yes" },
					equipped = { paint = "halo", hat = "nope" },
				},
				boosts = "nope",
				oneTimeClaims = { StarterPack = true, [1] = true, Other = "yes" },
				tutorial = { step = 2.7, done = "yes" },
				receipts = { "a", 5, string.rep("x", 200), "b" },
			}, 10)
			expect(data.currencies.wheat).toBe(0)
			expect(data.currencies.batteries).toBe(0)
			expect(data.currencies.biomass).toBe(0)
			expect(data.currencies[3]).toBeNil()
			expect(data.techUnlocks).toEqual({ loops = true })
			expect(data.cargo.hay).toBe(0)
			expect(data.factoryBuffer).toBe(GameConfig.Factory.PointsPerBiomass - 1)
			expect(data.cropsHarvested).toBe(0)
			expect(data.scripts).toEqual({ "", "ok", "" })
			-- "print" is a builtin, the second "ok_name" clashes -> defaults
			expect(data.scriptNames).toEqual({ "main", "ok_name", "lab" })
			-- a paint slot can't hold a hat; unknown hat -> defaults; only `true` flags are kept
			expect(data.cosmetics.equipped).toEqual({ paint = "factory", hat = "none" })
			expect(data.cosmetics.owned).toEqual({ halo = true })
			expect(data.boosts).toEqual({ growthUntil = 0, yieldUntil = 0 })
			expect(data.oneTimeClaims).toEqual({ StarterPack = true })
			expect(data.tutorial).toEqual({ step = 2, done = false })
			expect(data.receipts).toEqual({ "a", "b" })
		end)

		it("keeps valid data and unknown keys", function()
			local data = Sanitize.run({
				schemaVersion = 2,
				currencies = { wheat = 50, batteries = 7, gems = 3 },
				scriptNames = { "farm", "helpers", "lab" },
				futureField = { x = 1 },
			}, 10)
			expect(data.currencies.wheat).toBe(50)
			expect(data.currencies.batteries).toBe(7)
			expect(data.currencies.carrot).toBe(0) -- missing currency -> default
			expect(data.currencies.gems).toBe(3) -- unknown currency from a newer server is kept
			expect(data.futureField.x).toBe(1)
			expect(data.scriptNames).toEqual({ "farm", "helpers", "lab" })
			expect(data.scripts[1]).toBe(GameConfig.StarterScript) -- missing field -> default
		end)

		describe("migration 2 -> 3 (saved field)", function()
			it("gives v2 saves an empty field and keeps everything else", function()
				local v2 = { schemaVersion = 2, currencies = { hay = 7 }, cropsHarvested = 12 }
				local data = Sanitize.run(v2, 50)
				expect(data.schemaVersion).toBe(3)
				expect(data.currencies.hay).toBe(7)
				expect(data.cropsHarvested).toBe(12)
				expect(#data.field.tiles).toBe(0)
			end)

			it("keeps only well-formed tiles, one per cell, inside the largest field", function()
				local raw = {
					schemaVersion = 3,
					field = {
						savedAt = 1000,
						tiles = {
							{ 0, 0, "wheat", "growing", 0.5, true, 0 }, -- kept
							{ 0, 0, "carrot", "ready", 1, false, 0 }, -- same cell twice: dropped
							{ 1, 0, "nope", "growing", 0.5, false, 0 }, -- unknown crop
							{ 2, 0, "wheat", "sleeping", 0.5, false, 0 }, -- unknown state
							{ 99, 0, "wheat", "ready", 1, false, 0 }, -- outside any field
							{ 1.5, 0, "wheat", "ready", 1, false, 0 }, -- not a cell
							{ 3, 0, "wheat", "growing", 7, "yes", -4 }, -- clamped
							{ 4, 0, "", "ready", 1, true, 5 }, -- no crop = bare soil
							"garbage",
						},
					},
				}
				local field = Sanitize.run(raw, 2000).field
				expect(field.savedAt).toBe(1000)
				expect(#field.tiles).toBe(3)
				expect(field.tiles[1][3]).toBe("wheat")
				expect(field.tiles[2][5]).toBe(1) -- progress clamped to 1
				expect(field.tiles[2][6]).toBe(false) -- "yes" isn't true
				expect(field.tiles[2][7]).toBe(0) -- bareTime clamped to 0
				expect(field.tiles[3][4]).toBe("empty")
				expect(field.tiles[3][6]).toBe(false)
			end)
		end)

		describe("migration 1 -> 2 (Tech Tree v2)", function()
			it("refunds every v1 research in full and clears the old unlocks", function()
				local v1 = {
					schemaVersion = 1,
					currencies = { wheat = 5, carrot = 1, biomass = 2, batteries = 30 },
					techUnlocks = { sw_loops = true, hw_battery_2 = true, ind_carrots = true, bogus = true },
					gridSize = 4,
					scripts = { "move_up()", "", "" },
				}
				local data = Sanitize.run(v1, 10)
				expect(data.schemaVersion).toBe(3) -- 1 -> 2 -> 3
				-- sw_loops 10 wheat, hw_battery_2 120 wheat + 20 biomass, ind_carrots 50 wheat + 5 biomass
				expect(data.currencies.wheat).toBe(5 + 10 + 120 + 50)
				expect(data.currencies.biomass).toBe(2 + 20 + 5)
				expect(data.currencies.carrot).toBe(1)
				expect(data.currencies.batteries).toBe(30) -- premium currency untouched
				expect(next(data.techUnlocks)).toBeNil()
				expect(data.gridSize).toBeNil()
				expect(data.scripts[1]).toBe("move_up()") -- the player's code survives
				expect(data.scriptNames).toEqual({ "main", "utils", "lab" })
			end)

			it("treats records without a version as v1", function()
				local data = Sanitize.run({ techUnlocks = { sw_senses = true } }, 10)
				expect(data.currencies.wheat).toBe(15)
				expect(next(data.techUnlocks)).toBeNil()
			end)

			it("survives garbage in the fields it migrates", function()
				local data = Sanitize.run(
					{ schemaVersion = 1, currencies = "x", techUnlocks = { sw_loops = true } },
					10
				)
				expect(data.currencies.wheat).toBe(10)
			end)

			it("does not refund again once data is v2", function()
				local once = Sanitize.run({ schemaVersion = 1, techUnlocks = { sw_loops = true } }, 10)
				local twice = Sanitize.run(once, 10)
				expect(twice.currencies.wheat).toBe(10)
			end)
		end)

		it("keeps only the newest receipts", function()
			local receipts = {}
			for i = 1, GameConfig.Data.MaxReceiptHistory + 10 do
				table.insert(receipts, "p" .. i)
			end
			local data = Sanitize.run({ receipts = receipts }, 10)
			expect(#data.receipts).toBe(GameConfig.Data.MaxReceiptHistory)
			expect(data.receipts[1]).toBe("p11")
		end)

		it("truncates oversized scripts without breaking UTF-8", function()
			local big = string.rep("ž", GameConfig.Script.MaxSourceBytes) -- 2 bytes each
			local data = Sanitize.run({ scripts = { big } }, 10)
			expect(#data.scripts[1]).toBeAtMost(GameConfig.Script.MaxSourceBytes)
			expect(utf8.len(data.scripts[1]) ~= nil).toBe(true)
		end)

		it("never downgrades a newer schema version", function()
			expect(Sanitize.run({ schemaVersion = 7 }, 10).schemaVersion).toBe(7)
		end)
	end)
end
