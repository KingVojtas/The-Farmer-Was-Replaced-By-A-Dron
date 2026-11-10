return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local CropTransitions = Loader.get("ReplicatedStorage.Shared.Util.CropTransitions")

	local function snap(state, crop, watered, progress)
		return CropTransitions.snapshot(state, crop, watered, progress)
	end

	local function diff(before, after)
		return CropTransitions.diff(before, after)
	end

	describe("CropTransitions", function()
		it("normalises raw attribute values", function()
			local s = snap(nil, 5, "yes", 0 / 0)
			expect(s.state).toBe("empty")
			expect(s.crop).toBe("")
			expect(s.watered).toBe(false)
			expect(s.progress).toBe(0)
		end)

		it("raises nothing for the first snapshot (joining a server)", function()
			local e = diff(nil, snap("ready", "wheat", false, 1))
			for _, key in { "plant", "sprout", "ready", "harvest", "water", "wetChanged" } do
				expect(e[key]).toBe(false)
			end
		end)

		it("detects planting on an empty tile", function()
			local e = diff(snap("empty", "", false, 0), snap("planted", "wheat", false, 0))
			expect(e.plant).toBe(true)
			expect(e.harvest).toBe(false)
			expect(e.sprout).toBe(false)
		end)

		it("detects planted -> growing as a sprout (same crop only)", function()
			local e = diff(snap("planted", "wheat", false, 0.1), snap("growing", "wheat", false, 0.2))
			expect(e.sprout).toBe(true)
			expect(e.plant).toBe(false)
			local progressOnly =
				diff(snap("growing", "wheat", false, 0.2), snap("growing", "wheat", false, 0.3))
			expect(progressOnly.sprout).toBe(false)
			expect(progressOnly.ready).toBe(false)
		end)

		it("detects becoming ready once", function()
			expect(diff(snap("growing", "wheat", false, 0.9), snap("ready", "wheat", false, 1)).ready).toBe(
				true
			)
			expect(diff(snap("ready", "wheat", false, 1), snap("ready", "wheat", false, 1)).ready).toBe(false)
		end)

		it("tells a ripe harvest from an unripe one", function()
			local ripe = diff(snap("ready", "carrot", false, 1), snap("empty", "", false, 0))
			expect(ripe.harvest).toBe(true)
			expect(ripe.ripe).toBe(true)
			expect(ripe.harvestedCrop).toBe("carrot")
			local unripe = diff(snap("growing", "carrot", true, 0.4), snap("empty", "", false, 0))
			expect(unripe.harvest).toBe(true)
			expect(unripe.ripe).toBe(false)
			expect(unripe.water).toBe(false)
			expect(unripe.wetChanged).toBe(true)
		end)

		it("treats a crop replacing another as harvest + plant", function()
			local e = diff(snap("ready", "grass", false, 1), snap("planted", "wheat", false, 0))
			expect(e.harvest).toBe(true)
			expect(e.ripe).toBe(true)
			expect(e.harvestedCrop).toBe("grass")
			expect(e.plant).toBe(true)
		end)

		it("raises water only for false -> true on a crop, and not with planting", function()
			expect(diff(snap("growing", "wheat", false, 0.3), snap("growing", "wheat", true, 0.3)).water).toBe(
				true
			)
			local dried = diff(snap("growing", "wheat", true, 0.3), snap("growing", "wheat", false, 0.3))
			expect(dried.water).toBe(false)
			expect(dried.wetChanged).toBe(true)
			local rainPlant = diff(snap("empty", "", false, 0), snap("planted", "wheat", true, 0))
			expect(rainPlant.plant).toBe(true)
			expect(rainPlant.water).toBe(false)
			expect(diff(snap("empty", "", false, 0), snap("empty", "", true, 0)).water).toBe(false)
		end)

		it("clamps bursts to the live-particle budget", function()
			expect(CropTransitions.burstSize(8, 0, 40)).toBe(8)
			expect(CropTransitions.burstSize(8, 36, 40)).toBe(4)
			expect(CropTransitions.burstSize(8, 40, 40)).toBe(0)
			expect(CropTransitions.burstSize(8, 45, 40)).toBe(0)
			expect(CropTransitions.burstSize(5.7, 0, 40)).toBe(5)
		end)
	end)
end
