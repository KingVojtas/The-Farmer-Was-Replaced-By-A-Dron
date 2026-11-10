return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Tutorial = Loader.get("ServerScriptService.Server.Progression.Tutorial")
	local TechTree = Loader.get("ReplicatedStorage.Shared.Config.TechTree")
	local CropConfig = Loader.get("ReplicatedStorage.Shared.Config.CropConfig")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")
	local TutorialConfig = Loader.get("ReplicatedStorage.Shared.Config.TutorialConfig")
	local Parser = Loader.get("ReplicatedStorage.Shared.DroneScript.Parser")
	local Builtins = Loader.get("ReplicatedStorage.Shared.DroneScript.Builtins")
	local Tech = Loader.get("ReplicatedStorage.Shared.Progression.Tech")
	local Text = Loader.get("ReplicatedStorage.Shared.Util.Text")
	local Interpreter = Loader.get("ServerScriptService.Server.DroneRuntime.Interpreter")
	local DroneAPI = Loader.get("ServerScriptService.Server.DroneRuntime.DroneAPI")
	local SimWorld = Loader.get("ServerScriptService.Server.DroneRuntime.SimWorld")
	local Growth = Loader.get("ServerScriptService.Server.Progression.Growth")
	local S = TutorialConfig.Snippets

	local function gate(unlocks)
		return function(feature)
			return Tech.isFeatureUnlocked(unlocks, feature)
		end
	end

	-- Runs `source` on a fresh 3 x 3 of ripe wild grass, the drone on the charger.
	local function play(source, unlocks, seconds)
		local tiles = {}
		for y = 0, 2 do
			for x = 0, 2 do
				tiles[y * 3 + x + 1] = Growth.newTile(x, y, true)
			end
		end
		local stats = Tech.stats(unlocks)
		local charger = GameConfig.Stations.charger
		local sim = SimWorld.new({
			size = 3,
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
			weather = { name = "Sunny", growth = 1, waterCost = 1, autoWater = false },
			currencies = {},
			random = function()
				return 0.99
			end,
			duration = seconds or 600,
		})
		local loops = 0
		local unloadedHay = 0
		local api, info = DroneAPI.create({
			world = sim,
			output = { print = function() end, hint = function() end, info = function() end },
			shouldStop = function()
				return sim:finished()
			end,
			isUnlocked = gate(unlocks),
			onUnload = function(moved)
				unloadedHay += moved.hay or 0
			end,
		})
		local program, err =
			Parser.compile(source, Parser.limits(GameConfig.Script.BaseMaxLines), gate(unlocks))
		assert(program ~= nil, err and err.message)
		local result = Interpreter.run(program, {
			specs = Builtins.ByName,
			builtins = api,
			yield = function() end,
			isCancelled = function()
				return sim:finished()
			end,
			onLoop = function()
				loops += 1
			end,
			limits = { maxIdleSteps = 20000, yieldEvery = 100, maxRepeat = 1000 },
		})
		return { sim = sim, info = info, result = result, loops = loops, unloadedHay = unloadedHay }
	end

	local function fresh()
		return { step = 0, done = false }
	end
	local function facts(harvested, unlocks, wheatPlanted)
		return {
			cropsHarvested = harvested or 0,
			unlocks = unlocks or {},
			wheatPlanted = wheatPlanted == true,
		}
	end

	describe("Tutorial", function()
		it("walks the six steps in order, on server-seen facts and events", function()
			local s = fresh()
			-- Step 0: only pressing RUN moves it.
			expect(Tutorial.check(s, facts(20))).toBe(false)
			expect(Tutorial.event(s, "loop", facts())).toBe(false)
			expect(Tutorial.event(s, "run", facts())).toBe(true)
			expect(s.step).toBe(1)
			-- Step 1: 9 harvests.
			expect(Tutorial.check(s, facts(8))).toBe(false)
			expect(Tutorial.check(s, facts(9))).toBe(true)
			expect(s.step).toBe(2)
			-- Step 2: Loops researched.
			expect(Tutorial.check(s, facts(9, { loops = true }))).toBe(true)
			expect(s.step).toBe(3)
			-- Step 3 needs a loop pass; a hay unload now does NOT count (it has to come after).
			expect(Tutorial.event(s, "hayUnload", facts(9, { loops = true }))).toBe(false)
			expect(Tutorial.event(s, "loop", facts(9, { loops = true }))).toBe(true)
			expect(s.step).toBe(4)
			expect(Tutorial.event(s, "hayUnload", facts(12, { loops = true }))).toBe(true)
			expect(s.step).toBe(5)
			-- Step 5: Wheat researched AND planted.
			expect(Tutorial.check(s, facts(12, { loops = true, wheat = true }, false))).toBe(false)
			expect(Tutorial.check(s, facts(12, { loops = true, wheat = true }, true))).toBe(true)
			expect(s.done).toBe(true)
			expect(Tutorial.event(s, "run", facts())).toBe(false) -- done stays done
		end)

		it("skips already-met state steps in one go", function()
			local s = fresh()
			Tutorial.event(s, "run", facts(30, { loops = true }))
			expect(s.step).toBe(3) -- harvest goal and Loops were already done
		end)

		it("lets veterans skip it", function()
			expect(Tutorial.isVeteran(facts(80, { wheat = true }))).toBe(true)
			expect(Tutorial.isVeteran(facts(80, {}))).toBe(false)
			local s = fresh()
			Tutorial.finish(s)
			expect(s.done).toBe(true)
		end)

		it("makes the first gate reachable from the starter field", function()
			-- Loops is paid in Hay and the 3 x 3 of wild grass yields exactly the harvest goal.
			local loopsCost = TechTree.Nodes.loops.cost.hay
			local grass = CropConfig.Crops[CropConfig.WildCrop]
			expect(Tutorial.HarvestGoal * grass.yield >= loopsCost).toBe(true)
		end)

		it("inserts only code its step allows", function()
			local none, loops, wheat = {}, { loops = true }, { loops = true, wheat = true }
			local limits = Parser.limits(GameConfig.Script.BaseMaxLines)
			expect(Parser.compile(S.sweep, limits, gate(none)) ~= nil).toBe(true)
			expect(Parser.compile(S.firstLoop, limits, gate(none))).toBeNil() -- loops come at step 2
			expect(Parser.compile(S.firstLoop, limits, gate(loops)) ~= nil).toBe(true)
			expect(Parser.compile(S.hayRun, limits, gate(loops)) ~= nil).toBe(true)
			-- plant("wheat") is gated when it runs (crops are strings), before Wheat it errors:
			expect(play(S.plantWheat, loops).result.status).toBe("error")
			expect(Parser.compile(S.plantWheat, limits, gate(wheat)) ~= nil).toBe(true)
		end)

		it("step 1: the sweep on top of the starter harvests the whole 3 x 3 and banks it", function()
			local source = S.sweep .. "\n" .. GameConfig.StarterScript
			expect(Text.countLines(source) <= GameConfig.Script.BaseMaxLines).toBe(true)
			local report = play(source, {})
			expect(report.result.status).toBe("finished")
			expect(report.info.harvested).toBe(Tutorial.HarvestGoal)
			expect(report.sim:data().currencies.hay >= TechTree.Nodes.loops.cost.hay).toBe(true)
			expect(report.sim.drone.y).toBe(GameConfig.Stations.charger.y)
		end)

		it("steps 3 and 4: the loop snippets really loop and bring Hay home", function()
			local first = play(S.firstLoop, { loops = true })
			expect(first.result.status).toBe("finished")
			expect(first.loops > 0).toBe(true)
			expect(first.unloadedHay > 0).toBe(true)
			local forever = play(S.hayRun, { loops = true }, 120)
			expect(forever.loops > 0).toBe(true)
			expect(forever.unloadedHay > 0).toBe(true)
		end)

		it("step 5: the planting snippet leaves a wheat crop on the field", function()
			local report = play(S.plantWheat, { loops = true, wheat = true })
			expect(report.result.status).toBe("finished")
			local wheat = false
			for y = 0, 2 do
				for x = 0, 2 do
					local tile = report.sim:tileAt(x, y)
					if tile.crop == "wheat" and tile.state ~= "empty" then
						wheat = true
					end
				end
			end
			expect(wheat).toBe(true)
		end)

		it("has print() free from the start (no Terminal Output node)", function()
			expect(TechTree.Nodes.print).toBeNil()
		end)
	end)
end
