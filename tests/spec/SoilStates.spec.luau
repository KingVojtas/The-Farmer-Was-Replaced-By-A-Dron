return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local SoilStates = Loader.get("ReplicatedStorage.Shared.Util.SoilStates")
	local CropConfig = Loader.get("ReplicatedStorage.Shared.Config.CropConfig")

	describe("SoilStates", function()
		it("shows bare soil as SoilDry", function()
			expect(SoilStates.forTile("empty", "", false)).toBe("SoilDry")
		end)

		it("keeps wild grass on SoilDry (weeds on unbroken dirt)", function()
			local wild = CropConfig.WildCrop
			expect(CropConfig.Crops[wild].wild).toBe(true)
			for _, state in { "planted", "growing", "ready" } do
				expect(SoilStates.forTile(state, wild, false)).toBe("SoilDry")
			end
		end)

		it("tills the soil under every player crop, in every stage", function()
			for _, cropId in CropConfig.Plantable do
				for _, state in { "planted", "growing", "ready" } do
					expect(SoilStates.forTile(state, cropId, false)).toBe("SoilTilled")
				end
			end
		end)

		it("shows Watered as SoilWet, overriding tilled and dry", function()
			expect(SoilStates.forTile("growing", "wheat", true)).toBe("SoilWet")
			expect(SoilStates.forTile("planted", CropConfig.WildCrop, true)).toBe("SoilWet")
		end)

		it("treats unknown crops as bare soil and never returns the reserved SoilFertile", function()
			expect(SoilStates.forTile("growing", "nope", false)).toBe("SoilDry")
			for _, name in SoilStates.Names do
				expect(name == "SoilFertile").toBe(false)
			end
		end)
	end)
end
