--[[
	DroneAPI + SimWorld: real drone programs running against the virtual farm that simulate()
	uses. Because DroneAPI only talks to the World interface, this is the same builtin code the
	live farm runs - just with a virtual clock.
]]
return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Parser = Loader.get("ReplicatedStorage.Shared.DroneScript.Parser")
	local Builtins = Loader.get("ReplicatedStorage.Shared.DroneScript.Builtins")
	local Tech = Loader.get("ReplicatedStorage.Shared.Progression.Tech")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")
	local Interpreter = Loader.get("ServerScriptService.Server.DroneRuntime.Interpreter")
	local DroneAPI = Loader.get("ServerScriptService.Server.DroneRuntime.DroneAPI")
	local SimWorld = Loader.get("ServerScriptService.Server.DroneRuntime.SimWorld")
	local Growth = Loader.get("ServerScriptService.Server.Progression.Growth")
	local CropConfig = Loader.get("ReplicatedStorage.Shared.Config.CropConfig")

	local SUNNY = { name = "Sunny", growth = 1, waterCost = 1, autoWater = false }
	local DROUGHT = { name = "Drought", growth = 0.5, waterCost = 2, autoWater = false }

	local function allUnlocked()
		local set = {}
		for _, id in Tech.NodeIds do
			set[id] = true
		end
		return set
	end

	--[[
		farm(source, options) -> { sim, info, result, hints, infos, prints }
		options: unlocks, size, weather, random, battery, setup(sim), duration
	]]
	local function farm(source, options)
		options = options or {}
		local unlocks = options.unlocks or allUnlocked()
		local size = options.size or 3
		local tiles = {}
		for y = 0, size - 1 do
			for x = 0, size - 1 do
				tiles[y * size + x + 1] = Growth.newTile(x, y, true)
			end
		end
		local stats = Tech.stats(unlocks)
		local charger = GameConfig.Stations.charger
		local sim = SimWorld.new({
			size = size,
			tiles = tiles,
			drone = {
				x = charger.x,
				y = charger.y,
				battery = options.battery or stats.batteryCapacity,
				water = stats.waterCapacity,
			},
			stats = stats,
			speedPerk = 1,
			yieldMultiplier = 1,
			growthBoost = 1,
			weather = options.weather or SUNNY,
			currencies = {},
			random = options.random or function()
				return 0.99
			end,
			duration = options.duration or 600,
		})
		if options.setup then
			options.setup(sim)
		end
		local report = { sim = sim, hints = {}, infos = {}, prints = {} }
		local function isUnlocked(feature)
			return Tech.isFeatureUnlocked(unlocks, feature)
		end
		local api, info = DroneAPI.create({
			world = sim,
			output = {
				print = function(text)
					table.insert(report.prints, text)
				end,
				hint = function(text)
					table.insert(report.hints, text)
				end,
				info = function(text)
					table.insert(report.infos, text)
				end,
			},
			shouldStop = function()
				return sim:finished()
			end,
			isUnlocked = isUnlocked,
			simulate = options.simulate,
		})
		report.api = api
		report.info = info
		local program, err = Parser.compile(source, Parser.limits(80), isUnlocked)
		if program == nil then
			report.compileError = err
			return report
		end
		report.result = Interpreter.run(program, {
			specs = Builtins.ByName,
			builtins = api,
			yield = function() end,
			isCancelled = function()
				return sim:finished()
			end,
			limits = { maxIdleSteps = 20000, yieldEvery = 100, maxRepeat = 1000 },
		})
		return report
	end

	local function tile(sim, x, y)
		return sim:tileAt(x, y)
	end

	describe("DroneAPI on SimWorld", function()
		it("runs the starter script: grass -> Hay, banked at the charger", function()
			local report = farm(GameConfig.StarterScript, { unlocks = {} })
			expect(report.result.status).toBe("finished")
			expect(report.sim:data().currencies.hay).toBe(3)
			expect(report.info.harvested).toBe(3)
			expect(report.sim.drone.x).toBe(0)
			expect(report.sim.drone.y).toBe(-1)
			expect(tile(report.sim, 0, 0).state).toBe("empty")
		end)

		it("regrows wild grass on bare soil over (virtual) time", function()
			local report = farm("move_up()\nharvest()", { unlocks = {} })
			local t = tile(report.sim, 0, 0)
			expect(t.state).toBe("empty")
			report.sim:wait(GameConfig.Grass.RegrowDelay + 1)
			expect(t.crop).toBe("grass")
			report.sim:wait(60)
			expect(t.state).toBe("ready")
		end)

		it("plants over wild grass once the crop is researched", function()
			local locked = farm('move_up()\nplant("wheat")', { unlocks = {} })
			expect(locked.result.status).toBe("error")
			expect(locked.result.error.message).toContain("Wheat")

			local report = farm('move_up()\nplant("wheat")', { unlocks = { loops = true, wheat = true } })
			expect(report.result.status).toBe("finished")
			local t = tile(report.sim, 0, 0)
			expect(t.crop).toBe("wheat")
			expect(t.state).toBe("planted")
			report.sim:wait(10)
			expect(t.state).toBe("ready")
		end)

		it("can't plant wild grass", function()
			local report = farm('move_up()\nplant("grass")')
			expect(report.result.status).toBe("error")
			expect(report.result.error.message).toContain("grows by itself")
		end)

		it("set_speed trades battery for time", function()
			local normal = farm("move_up()\nmove_down()")
			local fast = farm("set_speed(2)\nmove_up()\nmove_down()")
			local stats = Tech.stats(allUnlocked())
			expect(stats.batteryCapacity - normal.sim.drone.battery).toBe(2)
			expect(stats.batteryCapacity - fast.sim.drone.battery).toBe(4)
			expect(fast.sim.time < normal.sim.time).toBe(true)
			local bad = farm("set_speed(5)")
			expect(bad.result.error.message).toContain("0.5 to 2")
		end)

		it("get_time follows the run's clock", function()
			local report = farm("move_up()\nprint(get_time())")
			expect(tonumber(report.prints[1]) > 0).toBe(true)
		end)

		it("sunflowers recharge the battery when harvested ripe", function()
			local report = farm("move_up()\nharvest()", {
				battery = 20,
				setup = function(sim)
					Growth.growFully(sim:tileAt(0, 0), "sunflower")
				end,
			})
			-- 1 energy to move, 1 to harvest, +8 from the sunflower
			expect(report.sim.drone.battery).toBe(20 - 2 + 8)
			expect(report.sim:data().cargo.sunflower).toBe(1)
		end)

		it("trees fill the hold with Wood", function()
			local report = farm("move_up()\nharvest()", {
				setup = function(sim)
					Growth.growFully(sim:tileAt(0, 0), "tree")
				end,
			})
			expect(report.sim:data().cargo.wood).toBe(3)
		end)

		it("cacti refuse water but thrive in a drought", function()
			local report = farm('move_up()\nplant("cactus")\nprint(water())', { weather = DROUGHT })
			expect(report.prints[1]).toBe("False")
			expect(report.hints[1]).toContain("never needs water")
			local cactus = tile(report.sim, 0, 0)
			local before = cactus.progress
			report.sim:wait(4)
			-- Drought growth for cacti is 1.5 instead of the usual 0.5
			expect(math.abs((cactus.progress - before) - 4 * 1.5 / 20) < 1e-9).toBe(true)
		end)

		it("Watering Cans water the neighbouring tiles too", function()
			local source = 'move_up()\nplant("wheat")\nmove_right()\nplant("wheat")\nmove_left()\nwater()'
			local report = farm(source)
			expect(tile(report.sim, 0, 0).watered).toBe(true)
			expect(tile(report.sim, 1, 0).watered).toBe(true)

			local noCans = allUnlocked()
			noCans.watering_cans = nil
			noCans.cacti = nil
			noCans.fossils = nil
			local plain = farm(source, { unlocks = noCans })
			expect(tile(plain.sim, 0, 0).watered).toBe(true)
			expect(tile(plain.sim, 1, 0).watered).toBe(false)
		end)

		it("dig() finds fossils with the injected randomness (bare soil only)", function()
			local lucky = farm("move_up()\nharvest()\nprint(dig())", {
				random = function()
					return 0.01
				end,
			})
			expect(lucky.prints[1]).toBe("True")
			expect(lucky.sim:data().cargo.fossil).toBe(1)
			local unlucky = farm("move_up()\nharvest()\nprint(dig())")
			expect(unlucky.prints[1]).toBe("False")
			-- Wild grass is not bare soil: no digging through it.
			local grassy = farm("move_up()\nprint(dig())", {
				random = function()
					return 0.01
				end,
			})
			expect(grassy.prints[1]).toBe("False")
			expect(grassy.sim:data().cargo.fossil or 0).toBe(0)
		end)

		it("dig() exhausts the tile: no re-dig, no planting, no grass until it recovers", function()
			local report =
				farm("move_up()\nharvest()\ndig()\nprint(dig())\nprint(plant('wheat'))\nprint(is_empty())")
			expect(report.prints[1]).toBe("False") -- dug up a moment ago
			expect(report.prints[2]).toBe("False") -- nothing can be planted in exhausted soil
			expect(report.prints[3]).toBe("False")
			local t = tile(report.sim, 0, 0)
			expect(t.state).toBe("empty")
			-- No wild grass while exhausted, even past the normal regrowth delay ...
			report.sim:wait(GameConfig.Dig.ExhaustSeconds - 5)
			expect(t.state).toBe("empty")
			-- ... then the soil recovers and grass comes back as usual.
			report.sim:wait(5 + GameConfig.Grass.RegrowDelay + 1)
			expect(t.crop).toBe("grass")
		end)

		it("pumpkins ripen only in a complete 2 x 2 (and together)", function()
			local square = "move_up()\nplant('pumpkin')\nmove_right()\nplant('pumpkin')\n"
				.. "move_up()\nplant('pumpkin')\nmove_left()\nplant('pumpkin')"
			local report = farm(square, { duration = 10000 })
			expect(report.result.status).toBe("finished")
			local growSeconds = CropConfig.Crops.pumpkin.growSeconds
			report.sim:wait(growSeconds * 0.5)
			expect(tile(report.sim, 0, 0).state ~= "ready").toBe(true)
			report.sim:wait(growSeconds * 2)
			for _, cell in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
				local t = tile(report.sim, cell[1], cell[2])
				expect(t.crop).toBe("pumpkin")
				expect(t.state).toBe("ready")
			end
		end)

		it("a lone pumpkin grows fully but never ripens; can_harvest() stays False", function()
			local report = farm("move_up()\nplant('pumpkin')", { duration = 10000 })
			report.sim:wait(CropConfig.Crops.pumpkin.growSeconds * 4)
			local t = tile(report.sim, 0, 0)
			expect(t.progress).toBe(1)
			expect(t.state).toBe("growing")
			report.api.move_down({})
			report.api.move_up({})
			expect(report.api.can_harvest({})).toBe(false)
		end)

		it("breaking a forming square keeps the rest waiting until it is complete again", function()
			local square = "move_up()\nplant('pumpkin')\nmove_right()\nplant('pumpkin')\n"
				.. "move_up()\nplant('pumpkin')\nmove_left()\nplant('pumpkin')\nharvest()"
			local report = farm(square, { duration = 10000 })
			expect(tile(report.sim, 0, 1).state).toBe("empty") -- destroyed while forming
			local hinted = false
			for _, hint in report.hints do
				if string.find(hint, "waiting for its square", 1, true) then
					hinted = true
				end
			end
			expect(hinted).toBe(true)
			local growSeconds = CropConfig.Crops.pumpkin.growSeconds
			report.sim:wait(growSeconds * 3)
			for _, cell in { { 0, 0 }, { 1, 0 }, { 1, 1 } } do
				local t = tile(report.sim, cell[1], cell[2])
				expect(t.state).toBe("growing") -- fully grown, still waiting
				expect(t.progress).toBe(1)
			end
			-- Replant the gap: once it has grown, the whole square ripens.
			report.api.plant({ "pumpkin" })
			report.sim:wait(growSeconds * 3)
			for _, cell in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
				expect(tile(report.sim, cell[1], cell[2]).state).toBe("ready")
			end
		end)

		it("rain soaks dry crops over time instead of watering them at once", function()
			local RAINY = { name = "Rainy", growth = 1.25, waterCost = 0, autoWater = true }
			local soak = GameConfig.Grid.RainSoakSeconds
			-- A tree grows slowly enough (30 s) to get soaked while it grows.
			local report = farm("move_up()\nplant('tree')", { weather = RAINY, duration = 10000 })
			local t = tile(report.sim, 0, 0)
			expect(t.watered).toBe(false) -- planting in the rain doesn't water
			report.sim:wait(soak - 1)
			expect(t.watered).toBe(false)
			report.sim:wait(2)
			expect(t.watered).toBe(true)
			-- ...while wheat (6 s) ripens before any soak: Water Tanks still pay off.
			local wheat = CropConfig.Crops.wheat
			expect(wheat.growSeconds / RAINY.growth < soak).toBe(true)
		end)

		it("deposits the hold at the Factory as Biomass", function()
			local source = "move_up()\nharvest()\nmove_down()\nmove_right()\ndeposit()"
			local report = farm(source, {
				setup = function(sim)
					Growth.growFully(sim:tileAt(0, 0), "pumpkin") -- 8 biomass points
				end,
			})
			-- the charger unloads the pumpkin on the way, so deposit has nothing left
			expect(report.sim:data().currencies.pumpkin).toBe(1)
			expect(report.hints[#report.hints]).toContain("isn't carrying anything")
		end)

		it("refuses nested simulations", function()
			local report = farm('print(simulate("main", 10))')
			expect(report.result.status).toBe("error")
			expect(report.result.error.message).toContain("inside a simulation")
		end)

		it("forwards simulate() to the injected simulator", function()
			local report = farm('print(simulate("lab", 30))', {
				simulate = function(slot, seconds)
					return if slot == "lab" and seconds == 30 then 12 else nil, "bad call"
				end,
			})
			expect(report.prints[1]).toBe("12")
			local bad = farm('print(simulate("lab", 99999))', {
				simulate = function()
					return 1
				end,
			})
			expect(bad.result.error.message).toContain("1 to")
		end)

		it("stops a simulation when its virtual time is up", function()
			local report = farm("while True:\n    move_up()\n    move_down()", { duration = 30 })
			expect(report.result.status).toBe("cancelled")
			expect(report.sim.time >= 30).toBe(true)
		end)

		it("removes locked builtins from the table entirely", function()
			local report = farm("pass", { unlocks = {} })
			expect(report.api.get_x).toBeNil()
			expect(report.api.dig).toBeNil()
			expect(report.api.move_up).toBeTruthy()
		end)

		it("can't fly past the edge of the field", function()
			local report = farm("print(move_left())")
			expect(report.prints[1]).toBe("False")
			expect(report.hints[1]).toContain("past the edge")
		end)
	end)
end
