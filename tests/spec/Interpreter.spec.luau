return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Parser = Loader.get("ReplicatedStorage.Shared.DroneScript.Parser")
	local Builtins = Loader.get("ReplicatedStorage.Shared.DroneScript.Builtins")
	local Interpreter = Loader.get("ServerScriptService.Server.DroneRuntime.Interpreter")
	local limits = Parser.limits(40)

	-- A fake world: records every call, sensors read from `world`.
	local function makeRun(source, setup)
		local program, err = Parser.compile(source, limits)
		if program == nil then
			error("compile error: " .. err.message, 2)
		end

		local world = { calls = {}, x = 0, harvestable = false, empty = true, cancelled = false, yields = 0 }
		local builtins = {}
		for _, spec in Builtins.List do
			builtins[spec.name] = function(args)
				local label = spec.name
				if args[1] ~= nil then
					label ..= "(" .. tostring(args[1]) .. ")"
				end
				table.insert(world.calls, label)
				return if spec.kind == "action" then true else nil
			end
		end
		builtins.get_x = function()
			return world.x
		end
		builtins.move_right = function()
			table.insert(world.calls, "move_right")
			world.x += 1
			return true
		end
		builtins.can_harvest = function()
			table.insert(world.calls, "can_harvest")
			return world.harvestable
		end
		builtins.is_empty = function()
			return world.empty
		end

		local ctx = {
			specs = Builtins.ByName,
			builtins = builtins,
			yield = function()
				world.yields += 1
			end,
			isCancelled = function()
				return world.cancelled
			end,
			limits = { maxIdleSteps = 2000, yieldEvery = 200, maxRepeat = 1000 },
		}
		if setup then
			setup(world, builtins, ctx)
		end
		return function()
			return Interpreter.run(program, ctx)
		end, world
	end

	describe("Interpreter", function()
		it("runs commands in order", function()
			local run, world = makeRun('move_up()\nplant("wheat")\nharvest()')
			expect(run().status).toBe("finished")
			expect(world.calls).toEqual({ "move_up", "plant(wheat)", "harvest" })
		end)

		it("repeats a block N times (and 0 times)", function()
			local run, world = makeRun("repeat 3 times:\n    move_up()\nrepeat 0:\n    move_down()")
			expect(run().status).toBe("finished")
			expect(world.calls).toEqual({ "move_up", "move_up", "move_up" })
		end)

		it("picks the right if / elif / else branch", function()
			local source =
				"if can_harvest():\n    harvest()\nelif is_empty():\n    plant('wheat')\nelse:\n    water()"
			local run, world = makeRun(source)
			run()
			expect(world.calls).toEqual({ "can_harvest", "plant(wheat)" })

			local run2, world2 = makeRun(source, function(w)
				w.empty = false
			end)
			run2()
			expect(world2.calls).toEqual({ "can_harvest", "water" })
		end)

		it("loops while a condition holds", function()
			local run, world = makeRun("while get_x() < 3:\n    move_right()")
			expect(run().status).toBe("finished")
			expect(world.x).toBe(3)
		end)

		it("short-circuits 'and' / 'or'", function()
			local run, world =
				makeRun("if False and can_harvest():\n    pass\nif True or can_harvest():\n    pass")
			run()
			expect(#world.calls).toBe(0)
		end)

		it("compares values of any type with == and !=", function()
			local run, world =
				makeRun("if get_x() == 'zero':\n    move_up()\nif get_x() != 'zero':\n    move_down()")
			run()
			expect(world.calls).toEqual({ "move_down" })
		end)

		it("stops idle infinite loops with a friendly error", function()
			local run = makeRun("while True:\n    pass")
			local result = run()
			expect(result.status).toBe("error")
			expect(result.error.message).toContain("without the drone doing anything")
		end)

		it("lets loops that keep doing actions run until cancelled", function()
			local run, world = makeRun("while True:\n    move_up()", function(w, builtins)
				builtins.move_up = function()
					table.insert(w.calls, "move_up")
					if #w.calls >= 5000 then
						w.cancelled = true
					end
					return true
				end
			end)
			local result = run()
			expect(result.status).toBe("cancelled")
			expect(#world.calls).toBe(5000) -- far beyond maxIdleSteps: actions reset the idle counter
			expect(world.yields).toBeAtLeast(1)
		end)

		it("yields to the scheduler regularly", function()
			local run, world = makeRun("repeat 1000 times:\n    move_up()")
			run()
			expect(world.yields).toBeAtLeast(10)
		end)

		it("does nothing when already cancelled", function()
			local run, world = makeRun("move_up()", function(w)
				w.cancelled = true
			end)
			expect(run().status).toBe("cancelled")
			expect(#world.calls).toBe(0)
		end)

		it("requires True/False for conditions", function()
			local run = makeRun("move_up()\nif get_x():\n    pass")
			local result = run()
			expect(result.status).toBe("error")
			expect(result.error.line).toBe(2)
			expect(result.error.message).toContain("needs True or False")
		end)

		it("validates repeat counts", function()
			for _, count in { "2.5", "1001", "True", "get_x() == 0" } do
				local run = makeRun("repeat " .. count .. " times:\n    pass")
				local result = run()
				expect(result.status).toBe("error")
				expect(result.error.message).toContain("whole number")
			end
		end)

		it("only orders numbers with < and >", function()
			local run = makeRun("if 'a' < 1:\n    pass")
			local result = run()
			expect(result.status).toBe("error")
			expect(result.error.message).toContain("only works with numbers")
		end)

		it("type-checks builtin arguments at runtime", function()
			local run = makeRun("plant(can_harvest())", function(w)
				w.harvestable = true
			end)
			local result = run()
			expect(result.status).toBe("error")
			expect(result.error.message).toContain("needs text")
		end)

		it("turns builtin error messages into script errors with a line", function()
			local run = makeRun("move_up()\nplant('wheet')", function(_, builtins)
				builtins.plant = function()
					return nil, "Unknown crop"
				end
			end)
			local result = run()
			expect(result.status).toBe("error")
			expect(result.error.line).toBe(2)
			expect(result.error.message).toBe("Unknown crop")
		end)

		it("reports internal errors separately from player mistakes", function()
			local run = makeRun("move_up()", function(_, builtins)
				builtins.move_up = function()
					error("boom")
				end
			end)
			local result = run()
			expect(result.status).toBe("internal")
			expect(result.message).toContain("boom")
		end)

		it("calls onAction with the line of each action", function()
			local lines = {}
			local run = makeRun("is_empty()\nmove_up()\nrepeat 2:\n    harvest()", function(_, _, ctx)
				ctx.onAction = function(line)
					table.insert(lines, line)
				end
			end)
			run()
			expect(lines).toEqual({ 2, 4, 4 })
		end)
	end)
end
