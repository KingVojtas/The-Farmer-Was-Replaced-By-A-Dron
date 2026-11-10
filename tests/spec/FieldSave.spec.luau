return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local FieldSave = Loader.get("ServerScriptService.Server.Progression.FieldSave")
	local Growth = Loader.get("ServerScriptService.Server.Progression.Growth")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")

	local function field(size)
		local tiles = {}
		for y = 0, size - 1 do
			for x = 0, size - 1 do
				tiles[y * size + x + 1] = Growth.newTile(x, y, false)
			end
		end
		local function tileAt(x, y)
			if x < 0 or y < 0 or x >= size or y >= size then
				return nil
			end
			return tiles[y * size + x + 1]
		end
		return tiles, tileAt
	end

	describe("FieldSave", function()
		it("round-trips a field without replaying growth", function()
			local tiles, tileAt = field(3)
			Growth.plant(
				tileAt(0, 0),
				"wheat",
				{ name = "Sunny", growth = 1, waterCost = 1, autoWater = false }
			)
			tileAt(0, 0).state = "growing"
			tileAt(0, 0).progress = 0.4
			tileAt(0, 0).watered = true
			tileAt(1, 1).bareTime = 12
			local saved = FieldSave.snapshot(tiles, 1000)
			local fresh, freshAt = field(3)
			FieldSave.restore(saved, freshAt, 1000 + 60) -- back after a minute
			expect(freshAt(0, 0).crop).toBe("wheat")
			expect(freshAt(0, 0).state).toBe("growing")
			expect(freshAt(0, 0).progress).toBe(0.4) -- no offline ticks
			expect(freshAt(0, 0).watered).toBe(true)
			expect(freshAt(1, 1).bareTime).toBe(12)
			expect(#fresh).toBe(9)
		end)

		it("snaps growing crops to grown after a long absence (pumpkins via their square)", function()
			local tiles, tileAt = field(3)
			local sunny = { name = "Sunny", growth = 1, waterCost = 1, autoWater = false }
			Growth.plant(tileAt(0, 0), "wheat", sunny)
			Growth.plant(tileAt(2, 2), "pumpkin", sunny)
			local saved = FieldSave.snapshot(tiles, 1000)
			local _, freshAt = field(3)
			FieldSave.restore(saved, freshAt, 1000 + GameConfig.Field.OfflineReadySeconds + 1)
			expect(freshAt(0, 0).state).toBe("ready")
			expect(freshAt(0, 0).progress).toBe(1)
			-- A lone pumpkin is fully grown but still needs its 2 x 2.
			expect(freshAt(2, 2).state).toBe("growing")
			expect(freshAt(2, 2).progress).toBe(1)
			expect(#Growth.settleSquares(3, freshAt)).toBe(0)
		end)

		it("ignores saved tiles outside the current field", function()
			local big, bigAt = field(4)
			Growth.plant(
				bigAt(3, 3),
				"wheat",
				{ name = "Sunny", growth = 1, waterCost = 1, autoWater = false }
			)
			local _, smallAt = field(3)
			local changed = FieldSave.restore(FieldSave.snapshot(big, 5), smallAt, 6)
			expect(#changed).toBe(9)
		end)
	end)
end
