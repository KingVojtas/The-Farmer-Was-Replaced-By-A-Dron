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
			Growth.plant(tileAt(0, 0), "wheat")
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
			Growth.plant(tileAt(0, 0), "wheat")
			Growth.plant(tileAt(2, 2), "pumpkin")
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
			Growth.plant(bigAt(3, 3), "wheat")
			local _, smallAt = field(3)
			local changed = FieldSave.restore(FieldSave.snapshot(big, 5), smallAt, 6)
			expect(#changed).toBe(9)
		end)

		-- BUG-11: dig exhaustion is saved and keeps counting down while the player is away.
		it("saves dig exhaustion and counts it down across a rejoin", function()
			local tiles, tileAt = field(3)
			Growth.exhaust(tileAt(1, 0), GameConfig.Dig.ExhaustSeconds)
			local saved = FieldSave.snapshot(tiles, 1000)
			expect(saved.tiles[2][8]).toBe(GameConfig.Dig.ExhaustSeconds)
			local _, quickAt = field(3)
			FieldSave.restore(saved, quickAt, 1000 + 10) -- back after 10 s
			expect(quickAt(1, 0).exhausted).toBe(GameConfig.Dig.ExhaustSeconds - 10)
			expect(Growth.isExhausted(quickAt(1, 0))).toBe(true)
			expect(Growth.isFree(quickAt(1, 0))).toBe(false) -- still can't plant or dig
			local _, lateAt = field(3)
			FieldSave.restore(saved, lateAt, 1000 + GameConfig.Dig.ExhaustSeconds + 1)
			expect(Growth.isExhausted(lateAt(1, 0))).toBe(false)
		end)

		it("reads old 7-value entries (no exhaustion) and clamps garbage", function()
			local clean = FieldSave.sanitize({
				savedAt = 50,
				tiles = {
					{ 0, 0, "", "empty", 0, false, 2 }, -- a v3 entry from before BUG-11
					{ 1, 0, "", "empty", 0, false, 0, 12.5 },
					{ 2, 0, "", "empty", 0, false, 0, -4 },
					{ 0, 1, "", "empty", 0, false, 0, 0 / 0 },
					{ 1, 1, "", "empty", 0, false, 0, 1e12 },
				},
			})
			expect(clean.tiles[1][8]).toBe(0)
			expect(clean.tiles[2][8]).toBe(12.5)
			expect(clean.tiles[3][8]).toBe(0)
			expect(clean.tiles[4][8]).toBe(0)
			expect(clean.tiles[5][8]).toBeAtMost(3600)
			local _, at = field(3)
			FieldSave.restore(clean, at, 50)
			expect(at(0, 0).exhausted).toBe(0)
			expect(at(1, 0).exhausted).toBe(12.5)
		end)
	end)

	describe("Growth exhaustion change (BUG-11)", function()
		it("reports the tick in which dig exhaustion ends, once", function()
			local sunny = {
				weather = { name = "Sunny", growth = 1, waterCost = 1, autoWater = false },
				growthBoost = 1,
			}
			local tile = Growth.newTile(0, 0, false)
			Growth.exhaust(tile, 1)
			expect(Growth.advance(tile, 0.5, sunny).exhausted).toBe(false)
			expect(Growth.advance(tile, 0.5, sunny).exhausted).toBe(true)
			expect(Growth.advance(tile, 0.5, sunny).exhausted).toBe(false)
		end)
	end)
end
