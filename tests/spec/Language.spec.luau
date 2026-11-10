--[[
	The Logic & Data language features end-to-end: Parser + Interpreter with a fake builtin
	table (print collects output; move_up records an action).
]]
return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Parser = Loader.get("ReplicatedStorage.Shared.DroneScript.Parser")
	local Builtins = Loader.get("ReplicatedStorage.Shared.DroneScript.Builtins")
	local Values = Loader.get("ReplicatedStorage.Shared.DroneScript.Values")
	local Interpreter = Loader.get("ServerScriptService.Server.DroneRuntime.Interpreter")

	local BASE_LIMITS = { maxIdleSteps = 20000, yieldEvery = 100, maxRepeat = 1000 }

	-- run(source, { modules = { name = source }, limits = {...} }) -> (outputText, result, world)
	local function run(source, options)
		options = options or {}
		local program, err = Parser.compile(source, Parser.limits(80))
		if program == nil then
			error("compile error line " .. err.line .. ": " .. err.message, 2)
		end
		local out = {}
		local world = { actions = 0, yields = 0 }
		local builtins = {
			print = function(args)
				local parts = {}
				for i, v in args do
					parts[i] = Values.display(v)
				end
				table.insert(out, table.concat(parts, " "))
				return nil
			end,
			move_up = function()
				world.actions += 1
				return true
			end,
			get_cost = function(args)
				return if args[1] == "loops" then { hay = 10 } else nil
			end,
			random = function()
				return 0.25
			end,
		}
		local limits = table.clone(BASE_LIMITS)
		for key, value in options.limits or {} do
			limits[key] = value
		end
		local result = Interpreter.run(program, {
			specs = Builtins.ByName,
			builtins = builtins,
			yield = function()
				world.yields += 1
			end,
			isCancelled = function()
				return false
			end,
			loadModule = function(name)
				local moduleSource = options.modules and options.modules[name]
				if moduleSource == nil then
					return nil, "there's no script called '" .. name .. "'."
				end
				local moduleProgram, moduleError = Parser.compile(moduleSource, Parser.limits(80))
				if moduleProgram == nil then
					return nil, "line " .. moduleError.line .. ": " .. moduleError.message
				end
				return moduleProgram
			end,
			moduleName = "main",
			maxSteps = options.maxSteps,
			limits = limits,
		})
		return table.concat(out, " | "), result, world
	end

	local function output(source, options)
		local text, result = run(source, options)
		if result.status ~= "finished" then
			error(
				"program did not finish: "
					.. tostring(result.error and result.error.message or result.message),
				2
			)
		end
		return text
	end

	local function runtimeError(source, options)
		local _, result = run(source, options)
		expect(result.status).toBe("error")
		return result.error
	end

	describe("Language", function()
		describe("math", function()
			it("follows Python precedence and floor division / modulo", function()
				expect(output("print(1 + 2 * 3, (1 + 2) * 3, 7 // 2, -7 // 2, -7 % 2, 10 / 4)")).toBe(
					"7 9 3 -4 1 2.5"
				)
			end)

			it("joins text and lists with +", function()
				expect(output("print('a' + 'b', [1] + [2, 3])")).toBe("ab [1, 2, 3]")
			end)

			it("refuses division by zero and mixed types", function()
				expect(runtimeError("print(1 / 0)").message).toContain("divide by zero")
				expect(runtimeError("print(1 + 'a')").message).toContain("'+' works on")
				expect(runtimeError("x = 'a' - 1").message).toContain("only works with numbers")
			end)

			it("keeps numbers finite and bounded", function()
				local err = runtimeError("x = 1000000000\nx = x * x * x")
				expect(err.message).toContain("too big")
			end)
		end)

		describe("variables and functions", function()
			it("assigns and updates variables", function()
				expect(output("a = 2\na += 3\na *= 2\na -= 1\na /= 3\nprint(a)")).toBe("3")
			end)

			it("calls functions with return values and recursion", function()
				local source =
					"def fib(n):\n    if n < 2:\n        return n\n    return fib(n - 1) + fib(n - 2)\nprint(fib(15))"
				expect(output(source)).toBe("610")
			end)

			it("returns None from functions without a return value", function()
				expect(output("def f():\n    pass\nprint(f())")).toBe("None")
			end)

			it("gives functions their own local variables (Python scoping)", function()
				expect(
					output("count = 0\ndef bump():\n    count = 5\n    return count\nprint(bump(), count)")
				).toBe("5 0")
				expect(output("base = 10\ndef read():\n    return base\nprint(read())")).toBe("10")
			end)

			it("reports a local used before it gets a value", function()
				expect(runtimeError("def g():\n    print(y)\n    y = 1\ng()").message).toContain(
					"before it gets a value"
				)
			end)

			it("stops runaway recursion", function()
				local err = runtimeError("def f():\n    return f()\nf()")
				expect(err.message).toContain("Too many functions")
				expect(err.line).toBe(2)
			end)

			it("treats functions as values", function()
				expect(output("def two():\n    return 2\nf = two\nprint(f(), f)")).toBe("2 <function two>")
			end)
		end)

		describe("lists, ranges and for loops", function()
			it("indexes (also negative), appends, pops and measures lists", function()
				expect(output("x = [1, 2, 3]\nx.append(4)\nprint(x, len(x), x[0], x[-1])")).toBe(
					"[1, 2, 3, 4] 4 1 4"
				)
				expect(output("x = [1, 2, 3]\nx[1] = 9\nprint(x.pop(), x.pop(0), x)")).toBe("3 1 [9]")
			end)

			it("loops over lists, ranges and dictionaries", function()
				expect(output("t = 0\nfor i in range(5):\n    t += i\nprint(t)")).toBe("10")
				expect(output("for i in range(10, 0, -3):\n    print(i)")).toBe("10 | 7 | 4 | 1")
				expect(output("for v in ['a', 'b']:\n    print(v)")).toBe("a | b")
			end)

			it("supports in / not in for lists, ranges, dicts and text", function()
				expect(
					output("print(2 in [1, 2], 3 not in [1, 2], 4 in range(0, 10, 2), 3 in range(0, 10, 2))")
				).toBe("True True True False")
				expect(output("print('ab' in 'cabin', 'k' in {'k': 1})")).toBe("True True")
			end)

			it("compares lists by value", function()
				expect(output("print([1, [2]] == [1, [2]], [1] != [2], 3 == 3.0)")).toBe("True True True")
			end)

			it("explains bad positions", function()
				expect(runtimeError("items = [1, 2]\nprint(items[5])").message).toContain("positions 0 to 1")
				expect(runtimeError("x = []\nx.pop()").message).toContain("empty list")
				expect(runtimeError("x = [1]\nprint(x[0.5])").message).toContain("whole numbers")
				expect(runtimeError("for c in 5:\n    pass").message).toContain("'for' can loop over")
			end)
		end)

		describe("dictionaries", function()
			it("stores, looks up and iterates in insertion order", function()
				local source =
					"d = {'wheat': 2, 'hay': 1}\nd['carrot'] = 3\nprint(d, d['wheat'], d.keys(), d.values(), d.get('x', 0))\nfor k in d:\n    print(k)"
				expect(output(source)).toBe(
					'{"wheat": 2, "hay": 1, "carrot": 3} 2 ["wheat", "hay", "carrot"] [2, 1, 3] 0 | wheat | hay | carrot'
				)
			end)

			it("rejects missing and unhashable keys", function()
				expect(runtimeError("d = {}\nprint(d['nope'])").message).toContain("no key")
				expect(runtimeError("d = {}\nd[[1]] = 2").message).toContain("Dictionary keys")
			end)

			it("returns research costs as a dictionary (get_cost)", function()
				expect(output("print(get_cost('loops'), get_cost('nope'))")).toBe('{"hay": 10} None') -- this spec's own get_cost stub
			end)
		end)

		describe("import", function()
			local modules = {
				utils = "BASE = 10\ndef double(n):\n    return n * 2\ndef go():\n    move_up()\n",
				a = "import b",
				b = "import a",
				broken = "x = = 1",
				failing = "def boom():\n    return 1 / 0\n",
			}

			it("uses functions and values from another script", function()
				local text, result, world = run(
					"import utils\nprint(utils.double(21), utils.BASE)\nutils.go()",
					{ modules = modules }
				)
				expect(result.status).toBe("finished")
				expect(text).toBe("42 10")
				expect(world.actions).toBe(1)
			end)

			it("detects import cycles and missing or broken modules", function()
				expect(runtimeError("import a", { modules = modules }).message).toContain("imports itself")
				expect(runtimeError("import main", { modules = modules }).message).toContain("imports itself")
				expect(runtimeError("import nope", { modules = modules }).message).toContain(
					"no script called"
				)
				expect(runtimeError("import broken", { modules = modules }).message).toContain(
					"Couldn't import 'broken'"
				)
			end)

			it("reports errors inside a module with the module's name", function()
				local err = runtimeError("import failing\nfailing.boom()", { modules = modules })
				expect(err.module).toBe("failing")
				expect(err.line).toBe(2)
			end)
		end)

		describe("safety limits", function()
			it("caps a single list", function()
				expect(runtimeError("x = []\nwhile True:\n    x.append(1)").message).toContain("at most")
			end)

			it("caps everything a program can still reach", function()
				local source = "keep = []\nwhile True:\n    keep.append([1, 2, 3, 4, 5, 6, 7, 8, 9])"
				local err = runtimeError(source, {
					limits = {
						maxLiveItems = 500,
						heapScanEvery = 100,
						maxContainerItems = 1000,
						maxIdleSteps = 100000,
					},
				})
				expect(err.message).toContain("holding too much data")
			end)

			it("lets garbage be collected without tripping the heap guard", function()
				local source = "repeat 300 times:\n    tmp = [1, 2, 3, 4, 5, 6, 7, 8, 9]\nprint('ok')"
				expect(output(source, { limits = { maxLiveItems = 100, heapScanEvery = 50 } })).toBe("ok")
			end)

			it("caps text built at runtime", function()
				expect(runtimeError("s = 'abcdefghij'\nwhile True:\n    s = s + s").message).toContain(
					"at most"
				)
			end)

			it("yields to the scheduler on a fixed step budget", function()
				local _, _, world = run("t = 0\nrepeat 1000 times:\n    t += 1")
				expect(world.yields).toBeAtLeast(15)
			end)

			it("stops at the optional total step budget", function()
				local _, result = run("while True:\n    move_up()", { maxSteps = 500 })
				expect(result.status).toBe("limit")
			end)
		end)
	end)
end
