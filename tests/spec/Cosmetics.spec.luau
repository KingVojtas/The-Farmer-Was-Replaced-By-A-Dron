return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Cosmetics = Loader.get("ServerScriptService.Server.Progression.Cosmetics")
	local CosmeticConfig = Loader.get("ReplicatedStorage.Shared.Config.CosmeticConfig")
	local Sanitize = Loader.get("ServerScriptService.Server.Data.Sanitize")

	local function freshData()
		return Sanitize.run(nil, 0)
	end

	describe("Cosmetics", function()
		it("owns the defaults from the start", function()
			local data = freshData()
			expect(Cosmetics.isOwned(data, CosmeticConfig.Defaults.paint)).toBe(true)
			expect(Cosmetics.isOwned(data, CosmeticConfig.Defaults.hat)).toBe(true)
			expect(Cosmetics.isOwned(data, "halo")).toBe(false)
		end)

		it("unlocks research cosmetics through the Tech Tree only", function()
			local data = freshData()
			expect(Cosmetics.isOwned(data, "meadow")).toBe(false)
			local ok, reason = Cosmetics.buy(data, "meadow")
			expect(ok).toBe(false)
			expect(reason).toContain("research")
			data.techUnlocks.paint_shop = true
			expect(Cosmetics.isOwned(data, "meadow")).toBe(true)
		end)

		it("buys premium cosmetics all-or-nothing", function()
			local data = freshData()
			data.currencies.batteries = 349 -- halo costs 350
			local ok, reason = Cosmetics.buy(data, "halo")
			expect(ok).toBe(false)
			expect(reason).toContain("350")
			expect(data.currencies.batteries).toBe(349)
			expect(data.cosmetics.owned.halo).toBeNil()

			data.currencies.batteries = 400
			expect((Cosmetics.buy(data, "halo"))).toBe(true)
			expect(data.currencies.batteries).toBe(50)
			expect(data.cosmetics.owned.halo).toBe(true)
			expect((Cosmetics.buy(data, "halo"))).toBe(false) -- never charged twice
			expect(data.currencies.batteries).toBe(50)
		end)

		it("equips only owned items in the matching slot", function()
			local data = freshData()
			expect((Cosmetics.equip(data, "hat", "halo"))).toBe(false)
			expect((Cosmetics.equip(data, "paint", "none"))).toBe(false) -- a hat in the paint slot
			data.cosmetics.owned.halo = true
			expect((Cosmetics.equip(data, "hat", "halo"))).toBe(true)
			expect(data.cosmetics.equipped.hat).toBe("halo")
		end)

		it("prices every premium cosmetic in whole batteries", function()
			for _, item in CosmeticConfig.List do
				if item.unlock.kind == "premium" then
					expect(item.unlock.price % 1).toBe(0)
					expect(item.unlock.price > 0).toBe(true)
				end
			end
		end)
	end)
end
