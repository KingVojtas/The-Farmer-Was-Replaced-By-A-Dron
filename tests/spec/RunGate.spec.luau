--[[
	RunGate: one driver per player. Reproduces the P0 race offline: a run busy inside a long
	simulate() must be killed by a new RunScript, the new run must not start before the old one
	is gone, and the shared plot / PlayerData must only see ONE program's effects.

	The "live plot" here is a SimWorld shared by both runs, behind a proxy whose wait() takes
	REAL (scaled) time like LiveWorld, so the two runs really interleave on the task scheduler.
]]
local task = require("@lune/task")

return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Parser = Loader.get("ReplicatedStorage.Shared.DroneScript.Parser")
	local Builtins = Loader.get("ReplicatedStorage.Shared.DroneScript.Builtins")
	local Tech = Loader.get("ReplicatedStorage.Shared.Progression.Tech")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")
	local Interpreter = Loader.get("ServerScriptService.Server.DroneRuntime.Interpreter")
	local DroneAPI = Loader.get("ServerScriptService.Server.DroneRuntime.DroneAPI")
	local SimWorld = Loader.get("ServerScriptService.Server.DroneRuntime.SimWorld")
	local RunGate = Loader.get("ServerScriptService.Server.DroneRuntime.RunGate")
	local Growth = Loader.get("ServerScriptService.Server.Progression.Growth")

	local SUNNY = { name = "Sunny", growth = 1, waterCost = 1, autoWater = false }
	local TIME_SCALE = 0.02 -- real seconds per game second in the fake live world

	local unlocks = {}
	for _, id in Tech.NodeIds do
		unlocks[id] = true
	end
	local function isUnlocked(feature)
		return Tech.isFeatureUnlocked(unlocks, feature)
	end
	local function compile(source)
		local program, err = Parser.compile(source, Parser.limits(80), isUnlocked)
		assert(program ~= nil, err and err.message)
		return program
	end

	local function newSim(duration, extra)
		local size = 3
		local tiles = {}
		for y = 0, size - 1 do
			for x = 0, size - 1 do
				tiles[y * size + x + 1] = Growth.newTile(x, y, true)
			end
		end
		local stats = Tech.stats(unlocks)
		local charger = GameConfig.Stations.charger
		local config = {
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
		}
		for key, value in extra or {} do
			config[key] = value
		end
		return SimWorld.new(config)
	end

	local function yieldStep()
		task.wait()
	end

	-- Runs `source` like ScriptService does, on `plot` (shared), as run `run`.
	local function runProgram(run, plot, source, moves)
		local function shouldStop()
			return run.cancelled
		end
		-- The fake LIVE world: the shared plot, but wait() takes real (scaled) time in slices.
		local live = setmetatable({
			moveDrone = function(_self, dx, dy, d)
				moves[run.id] = (moves[run.id] or 0) + 1
				plot:moveDrone(dx, dy, d)
			end,
			wait = function(_self, seconds)
				local deadline = os.clock() + seconds * TIME_SCALE
				while os.clock() < deadline and not shouldStop() do
					task.wait(math.min(0.005, deadline - os.clock()))
				end
			end,
		}, { __index = plot })
		-- simulate(): a 600 s virtual farm with the per-virtual-second yield hook.
		local function simulate(_slot, seconds)
			local sim = newSim(seconds, { yield = yieldStep, shouldStop = shouldStop })
			local simApi, simInfo = DroneAPI.create({
				world = sim,
				output = { print = function() end, hint = function() end, info = function() end },
				shouldStop = function()
					return sim:finished() or shouldStop()
				end,
				isUnlocked = isUnlocked,
			})
			Interpreter.run(compile("while True:\n\tmove_up()\n\tmove_down()"), {
				specs = Builtins.ByName,
				builtins = simApi,
				yield = yieldStep,
				isCancelled = function()
					return sim:finished() or shouldStop()
				end,
				maxSteps = GameConfig.Simulate.MaxSteps,
				limits = { maxIdleSteps = 20000, yieldEvery = 100, maxRepeat = 1000 },
			})
			return simInfo.harvested, nil
		end
		local api = DroneAPI.create({
			world = live,
			output = { print = function() end, hint = function() end, info = function() end },
			shouldStop = shouldStop,
			isUnlocked = isUnlocked,
			simulate = simulate,
		})
		return Interpreter.run(compile(source), {
			specs = Builtins.ByName,
			builtins = api,
			yield = yieldStep,
			isCancelled = shouldStop,
			limits = { maxIdleSteps = 20000, yieldEvery = 100, maxRepeat = 1000 },
		})
	end

	local function waitFor(condition, timeout)
		local start = os.clock()
		while not condition() and os.clock() - start < timeout do
			task.wait(0.01)
		end
		return condition()
	end

	describe("RunGate (one driver per player)", function()
		it("kills a run busy in a long simulate() and lets only the new run drive", function()
			local gate = RunGate.new()
			local plot = newSim(1e9)
			local moves = {}
			local harvestProgram = "move_up()\nharvest()\nmove_down()"

			local first = gate:start("player", function(run)
				runProgram(run, plot, 'x = simulate("lab", 600)\n' .. harvestProgram, moves)
			end)
			task.wait(0.02) -- the first run is now deep inside simulate()
			expect(gate:driver("player")).toBe(first)

			local firstGoneWhenSecondStarted = nil
			local second = gate:start("player", function(run)
				firstGoneWhenSecondStarted = first.finished and not first.driving
				runProgram(run, plot, harvestProgram, moves)
			end)

			expect(first.cancelled).toBe(true)
			expect(first.finished).toBe(true)
			expect(coroutine.status(first.thread)).toBe("dead")
			expect(waitFor(function()
				return second.finished
			end, 5)).toBe(true)
			task.wait(0.1) -- a leaked first run would act now

			expect(firstGoneWhenSecondStarted).toBe(true)
			expect(moves[first.id] or 0).toBe(0)
			expect(moves[second.id]).toBe(2)
			expect(plot:data().currencies.hay).toBe(1) -- not doubled
			expect(plot.drone.x).toBe(GameConfig.Stations.charger.x)
			expect(plot.drone.y).toBe(GameConfig.Stations.charger.y)
			expect(gate:driver("player")).toBe(nil)
		end)

		it("stop() kills the running program at once", function()
			local gate = RunGate.new()
			local plot = newSim(1e9)
			local moves = {}
			local run = gate:start("player", function(r)
				runProgram(r, plot, "while True:\n\tmove_up()\n\tmove_down()", moves)
			end)
			task.wait(0.05)
			local stopped, killed = gate:stop("player")
			expect(stopped).toBe(run)
			expect(killed).toBe(true)
			expect(run.finished).toBe(true)
			local before = moves[run.id] or 0
			task.wait(0.1)
			expect(moves[run.id] or 0).toBe(before)
			expect(gate:current("player")).toBe(nil)
		end)

		it("never runs two bodies at once, even when starts pile up", function()
			local gate = RunGate.new()
			local all = {}
			local entries, completions, overlap = 0, 0, false
			for i = 1, 5 do
				all[i] = gate:start("player", function(run)
					entries += 1
					for _, other in all do
						if other ~= run and other.driving then
							overlap = true -- another body still owns the drone
						end
					end
					for _ = 1, 20 do
						task.wait(0.002)
					end
					completions += 1
				end)
			end
			expect(waitFor(function()
				return all[5].finished
			end, 5)).toBe(true)
			expect(overlap).toBe(false)
			expect(entries).toBe(5) -- each start ran its body ...
			expect(completions).toBe(1) -- ... but only the newest one survived to the end
			for i = 1, 4 do
				expect(all[i].cancelled).toBe(true)
				expect(all[i].finished).toBe(true)
			end
			expect(gate:driver("player")).toBe(nil)
		end)

		it("SimWorld.wait yields every virtual second and stops when cancelled", function()
			local yields = 0
			local stop = false
			local sim = newSim(1e9, {
				yield = function()
					yields += 1
					if yields >= 3 then
						stop = true
					end
				end,
				shouldStop = function()
					return stop
				end,
			})
			sim:wait(10)
			expect(yields).toBe(3)
			expect(sim:now()).toBe(3)
			stop = false
			yields = 0
			local free = newSim(1e9, {
				yield = function()
					yields += 1
				end,
			})
			free:wait(10)
			expect(yields).toBe(10)
		end)
	end)
end
