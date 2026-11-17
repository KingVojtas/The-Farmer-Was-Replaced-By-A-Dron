--[[
	Station builtins (docs/BUGS.md BUG-09, BUG-10), on the real DroneAPI over a SimWorld. The
	world is wrapped in a proxy that records every publish() with the battery at that moment
	(LiveWorld.publish pushes the drone attributes the HUD and the drone strip read).
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

	local SUNNY = { name = "Sunny", growth = 1, waterCost = 1, autoWater = false }

	local unlocks = {}
	for _, id in Tech.NodeIds do
		unlocks[id] = true
	end
	local function isUnlocked(feature)
		return Tech.isFeatureUnlocked(unlocks, feature)
	end

	-- run(source, setup?) -> { world, sim, published = { battery, ... }, infos, result }
	local function run(source, setup)
		local size = 3
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
				battery = stats.batteryCapacity,
				water = stats.waterCapacity,
			},
			stats = stats,
			speedPerk = 1,
			yieldMultiplier = 1,
			growthBoost = 1,
			weather = SUNNY,
			currencies = { biomass = 40 },
			random = function()
				return 0.99
			end,
			duration = 600,
		})
		local report = { sim = sim, published = {}, infos = {} }
		local world = setmetatable({
			publish = function(_self)
				table.insert(report.published, sim.drone.battery)
			end,
		}, { __index = sim })
		report.world = world
		if setup then
			setup(sim)
		end
		local api = DroneAPI.create({
			world = world :: any,
			output = {
				print = function() end,
				hint = function() end,
				info = function(text)
					table.insert(report.infos, text)
				end,
			},
			shouldStop = function()
				return sim:finished()
			end,
			isUnlocked = isUnlocked,
		})
		local program, err = Parser.compile(source, Parser.limits(80), isUnlocked)
		assert(program ~= nil, err and err.message)
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

	describe("Station builtins", function()
		it("refine() publishes the battery it spent (BUG-09)", function()
			-- charger (0,-1) -> factory (1,-1), then refine 40 Biomass into Biofuel
			local report = run("move_right()\nrefine()")
			expect(report.result.status).toBe("finished")
			expect(report.sim:data().currencies.biofuel).toBeAtLeast(1)
			local last = report.published[#report.published]
			expect(last).toBe(report.sim.drone.battery) -- the last publish shows the final battery
			local afterMove = GameConfig.Drone.EnergyCosts.move
			local expected = Tech.stats(unlocks).batteryCapacity
				- afterMove
				- GameConfig.Drone.EnergyCosts.refine
			expect(last).toBe(expected)
		end)

		it("charge() banks a hold the drone already carries on the charger (BUG-10)", function()
			local report = run("charge()", function(sim)
				sim:data().cargo.hay = 5 -- a hold saved last session; the drone starts on the charger
			end)
			expect(report.result.status).toBe("finished")
			expect(report.sim:data().cargo.hay).toBe(0)
			expect(report.sim:data().currencies.hay).toBe(5)
			expect(report.infos[1]).toContain("Unloaded 5 items")
		end)

		it("charge() with an empty hold doesn't announce an unload", function()
			local report = run("charge()")
			expect(report.result.status).toBe("finished")
			expect(#report.infos).toBe(0)
		end)
	end)
end
