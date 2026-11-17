return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local DroneSignals = Loader.get("ReplicatedStorage.Shared.Util.DroneSignals")
	local CropTransitions = Loader.get("ReplicatedStorage.Shared.Util.CropTransitions")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")

	local function snap(state, crop, watered)
		return CropTransitions.snapshot(state, crop, watered, 0)
	end

	describe("DroneSignals", function()
		it("colours the status light by charge", function()
			expect(DroneSignals.statusLight(80, 100, false, false).key).toBe("lime")
			expect(DroneSignals.statusLight(50, 100, false, false).key).toBe("amber")
			expect(DroneSignals.statusLight(15, 100, false, false).key).toBe("amber")
			local low = DroneSignals.statusLight(10, 100, false, false)
			expect(low.key).toBe("red")
			expect(low.blink).toBe(true)
			expect(DroneSignals.statusLight(80, 100, false, false).blink).toBe(false)
		end)

		it("turns cyan on the charger and dims while limping", function()
			local charging = DroneSignals.statusLight(5, 100, true, true)
			expect(charging.key).toBe("cyan")
			expect(charging.blink).toBe(false)
			expect(DroneSignals.statusLight(0, 100, false, true).dim).toBe(true)
		end)

		it("survives missing battery attributes", function()
			expect(DroneSignals.statusLight(nil, nil, false, false).key).toBe("lime")
			expect(DroneSignals.statusLight(5, 0, false, false).key).toBe("lime")
		end)

		it("detects limping only for clearly slow moves", function()
			local base = GameConfig.Drone.ActionTimes.move
			expect(DroneSignals.isLimping(base, base)).toBe(false)
			expect(DroneSignals.isLimping(base * 1.2, base)).toBe(false)
			expect(DroneSignals.isLimping(base * GameConfig.Drone.LimpSlowdown, base)).toBe(true)
			expect(DroneSignals.isLimping(nil, base)).toBe(false)
		end)

		it("reads a grid cell from Vector2-shaped or Vector3-shaped values", function()
			local x, y = DroneSignals.cellXY({ X = 3, Y = 4 })
			expect(x).toBe(3)
			expect(y).toBe(4)
			local gx, gy = DroneSignals.cellXY({ X = 1, Y = -1, Z = 0 })
			expect(gx).toBe(1)
			expect(gy).toBe(-1)
			local nx, ny = DroneSignals.cellXY(nil)
			expect(nx).toBe(nil)
			expect(ny).toBe(nil)
			local bx, by = DroneSignals.cellXY(12)
			expect(bx).toBe(nil)
			expect(by).toBe(nil)
		end)

		it("prefers DroneX / DroneY numbers over the vector attribute", function()
			local x, y = DroneSignals.cellFromAttributes(2, 5, { X = 9, Y = 9 })
			expect(x).toBe(2)
			expect(y).toBe(5)
			local fx, fy = DroneSignals.cellFromAttributes(nil, nil, { X = 0, Y = -1 })
			expect(fx).toBe(0)
			expect(fy).toBe(-1)
			local mx, my = DroneSignals.cellFromAttributes(nil, 3, { X = 4, Y = 1 })
			expect(mx).toBe(4)
			expect(my).toBe(1)
		end)

		it("finds the stations by cell", function()
			for kind, station in GameConfig.Stations do
				expect(DroneSignals.stationAt(station.x, station.y)).toBe(kind)
			end
			expect(DroneSignals.stationAt(3, 3)).toBe(nil)
		end)

		it("infers actions conservatively", function()
			local plant = CropTransitions.diff(snap("empty", "", false), snap("planted", "wheat", false))
			expect(DroneSignals.action(plant, false, true, false)).toBe("plant")
			expect(DroneSignals.action(plant, false, false, false)).toBe(nil) -- drone elsewhere
			expect(DroneSignals.action(plant, true, true, false)).toBe(nil) -- wild regrowth

			local ripe = CropTransitions.diff(snap("ready", "wheat", false), snap("empty", "", false))
			expect(DroneSignals.action(ripe, false, true, false)).toBe("harvest")
			local unripe = CropTransitions.diff(snap("growing", "wheat", false), snap("empty", "", false))
			expect(DroneSignals.action(unripe, false, true, false)).toBe(nil)

			local water =
				CropTransitions.diff(snap("growing", "wheat", false), snap("growing", "wheat", true))
			expect(DroneSignals.action(water, false, true, false)).toBe("water")
			expect(DroneSignals.action(water, false, true, true)).toBe(nil) -- rain's auto-water
		end)

		-- BUG-05 / BUG-06: the remote and the attributes deliver the same move in either order.
		it("applies a drone cell only for a newer DroneSerial", function()
			expect(DroneSignals.shouldApply(nil, 5, false)).toBe(true) -- nothing shown yet
			expect(DroneSignals.shouldApply(5, 6, true)).toBe(true) -- the next move
			expect(DroneSignals.shouldApply(6, 6, false)).toBe(false) -- the duplicate (remote + attrs)
			expect(DroneSignals.shouldApply(6, 5, true)).toBe(false) -- a lagging attribute: no tween back
			expect(DroneSignals.shouldApply(6, 6, true)).toBe(false) -- half-replicated X/Y: wait for the serial
		end)

		it("replays remote-first and attributes-first without a step back", function()
			-- The drone shows serial 10 at cell A; move 11 goes to cell B.
			for _, order in { { "remote", "attrs" }, { "attrs", "remote" } } do
				local applied, cell, tweens = 10, "A", 0
				local function deliver(serial, target)
					if DroneSignals.shouldApply(applied, serial, target ~= cell) then
						applied = serial
						if target ~= cell then
							cell = target
							tweens += 1
						end
					end
				end
				for _, source in order do
					deliver(11, "B") -- both sources carry move 11
					if source == "remote" then
						deliver(10, "A") -- the per-frame poll still reads the OLD attributes
					end
				end
				expect(cell).toBe("B")
				expect(tweens).toBe(1)
			end
		end)

		it("ignores a cached move from an older plot that reused the Index", function()
			-- Serials are server-wide: the new plot starts at the counter's current value.
			local oldPlotLastMove = 41
			local newPlotStart = 41
			expect(DroneSignals.shouldApply(newPlotStart, oldPlotLastMove, true)).toBe(false)
		end)

		it("falls back to 'cell differs' without serials (old server)", function()
			expect(DroneSignals.shouldApply(3, nil, true)).toBe(true)
			expect(DroneSignals.shouldApply(3, nil, false)).toBe(false)
		end)
	end)
end
