--[[
	Simulation (docs/BUGS.md BUG-01): simulate() on the live farm must cost real time, compile a
	slot once per run and share the run's CPU budget, so `while True: simulate("lab", 1)` can't
	flood the server with compiles, free steps and "line" statuses.

	The "live" world is a SimWorld here: its wait() advances a virtual clock, standing in for
	the real time LiveWorld.wait (task.wait) would take. Every other piece is the server's code:
	DroneAPI, Interpreter and DroneRuntime.Simulation (what ScriptService wires up).
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
	local Simulation = Loader.get("ServerScriptService.Server.DroneRuntime.Simulation")
	local Growth = Loader.get("ServerScriptService.Server.Progression.Growth")

	local SUNNY = { name = "Sunny", growth = 1, waterCost = 1, autoWater = false }
	local LIMITS = { maxIdleSteps = 20000, yieldEvery = 100, maxRepeat = 1000 }
	local SILENT = { print = function() end, hint = function() end, info = function() end }

	local unlocks = {}
	for _, id in Tech.NodeIds do
		unlocks[id] = true
	end
	local function isUnlocked(feature)
		return Tech.isFeatureUnlocked(unlocks, feature)
	end
	local function compile(source)
		return Parser.compile(source, Parser.limits(80), isUnlocked)
	end

	local function newFarm(duration)
		local size = 3
		local tiles = {}
		for y = 0, size - 1 do
			for x = 0, size - 1 do
				tiles[y * size + x + 1] = Growth.newTile(x, y, true)
			end
		end
		local stats = Tech.stats(unlocks)
		local charger = GameConfig.Stations.charger
		return SimWorld.new({
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
			currencies = {},
			random = function()
				return 0.99
			end,
			duration = duration,
		})
	end

	-- A 40-line lab slot with no drone actions: the cheapest simulation to call, the most
	-- expensive one to compile (the abuse case of BUG-01).
	local labLines = {}
	for _ = 1, 40 do
		table.insert(labLines, "a = 1 + 2 * 3 - 4 + 5 * 6 - 7 + 8 * 9 - 10")
	end
	local LAB = table.concat(labLines, "\n")

	-- Runs `source` as a live run for `seconds` of (virtual) real time, with simulate() wired
	-- exactly like ScriptService: one compile cache and one CPU budget for the whole run.
	local function liveRun(source, seconds, labSource)
		local live = newFarm(seconds)
		local function stopped()
			return live:finished()
		end
		local cache = Simulation.newCompileCache(compile)
		local budget = { steps = 0 }
		local report = { yields = 0, actions = 0, live = live, cache = cache }
		local function throttle()
			report.yields += 1
		end
		local simulate, stats = Simulation.new({
			slotByName = function(name)
				if name == "lab" then
					return 3
				end
				return nil, "there's no script called '" .. name .. "'."
			end,
			sourceOf = function(_slot)
				return labSource or LAB
			end,
			cache = cache,
			newWorld = newFarm,
			isUnlocked = isUnlocked,
			throttle = throttle,
			budget = budget,
			shouldStop = stopped,
			limits = LIMITS,
			maxSteps = GameConfig.Simulate.MaxSteps,
		})
		report.stats = stats
		local api = DroneAPI.create({
			world = live,
			output = SILENT,
			shouldStop = stopped,
			isUnlocked = isUnlocked,
			simulate = simulate,
		})
		local program, err = compile(source)
		assert(program ~= nil, err and err.message)
		report.result = Interpreter.run(program, {
			specs = Builtins.ByName,
			builtins = api,
			yield = throttle,
			isCancelled = stopped,
			onAction = function()
				report.actions += 1
			end,
			-- Without the fix the virtual clock never moves: fail with "limit" instead of hanging.
			maxSteps = 50000,
			limits = LIMITS,
			budget = budget,
		})
		return report
	end

	describe("Simulation (BUG-01)", function()
		it("makes a simulate() loop take real time: one call per MinRealSeconds", function()
			local seconds = 10
			local report = liveRun('while True:\n    simulate("lab", 1)', seconds)
			expect(report.result.status).toBe("cancelled")
			local most = math.ceil(seconds / GameConfig.Simulate.MinRealSeconds)
			expect(report.stats.calls).toBeAtMost(most)
			expect(report.stats.calls).toBeAtLeast(most - 1)
			-- every call is one action, so the "line" statuses are bounded the same way
			expect(report.actions).toBe(report.stats.calls)
		end)

		it("compiles the simulated slot once per run", function()
			local report = liveRun('while True:\n    simulate("lab", 1)', 10)
			expect(report.stats.calls).toBeAtLeast(2)
			expect(report.cache.compiles).toBe(1)
		end)

		it("counts the simulated program's steps in the run's CPU budget", function()
			local report = liveRun('while True:\n    simulate("lab", 1)', 10)
			-- 40 lab steps per call never reach yieldEvery (100) on their own; shared, they do.
			local labSteps = 40 * report.stats.calls
			expect(report.yields).toBeAtLeast(math.floor(labSteps / LIMITS.yieldEvery))
		end)

		it("still takes the minimum time when the simulation fails", function()
			local report = liveRun('simulate("nope", 1)', 60)
			expect(report.result.status).toBe("error")
			expect(report.result.error.message).toContain("no script called 'nope'")
			expect(report.live.time).toBeAtLeast(GameConfig.Simulate.MinRealSeconds)
		end)

		it("returns the simulated harvest like before", function()
			local report =
				liveRun('print(simulate("lab", 30))', 60, "move_up()\nharvest()\nmove_right()\nharvest()")
			expect(report.result.status).toBe("finished")
			expect(report.stats.calls).toBe(1)
		end)
	end)

	describe("Simulation compile cache", function()
		it("hits on the same slot + source and recompiles an edited slot", function()
			local cache = Simulation.newCompileCache(compile)
			expect(cache:get(3, "move_up()")).toBeTruthy()
			expect(cache:get(3, "move_up()")).toBeTruthy()
			expect(cache.compiles).toBe(1)
			expect(cache:get(3, "move_down()")).toBeTruthy()
			expect(cache.compiles).toBe(2)
			expect(cache:get(2, "move_down()")).toBeTruthy()
			expect(cache.compiles).toBe(3)
		end)

		it("never caches a failed compile (research done mid-run must count)", function()
			local cache = Simulation.newCompileCache(compile)
			local program, err = cache:get(1, "move_up(")
			expect(program).toBeNil()
			expect(err).toBeTruthy()
			cache:get(1, "move_up(")
			expect(cache.compiles).toBe(2)
		end)
	end)
end
