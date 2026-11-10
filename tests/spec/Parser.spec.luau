return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Parser = Loader.get("ReplicatedStorage.Shared.DroneScript.Parser")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")
	local limits = Parser.limits(40)

	local function compile(source, customLimits)
		local program, err = Parser.compile(source, customLimits or limits)
		if program == nil then
			error("unexpected compile error: line " .. err.line .. ": " .. err.message, 2)
		end
		return program
	end

	local function compileError(source, customLimits)
		local program, err = Parser.compile(source, customLimits or limits)
		expect(program).toBeNil()
		expect(err).toBeTruthy()
		return err
	end

	describe("Parser", function()
		it("compiles the starter script", function()
			local program = compile(GameConfig.StarterScript)
			expect(program.kind).toBe("Program")
			expect(program.body[1].kind).toBe("CallStmt")
		end)

		it("builds repeat blocks with and without 'times'", function()
			local a = compile("repeat 3 times:\n    move_up()")
			local b = compile("repeat 3:\n    move_up()")
			for _, program in { a, b } do
				local stmt = program.body[1]
				expect(stmt.kind).toBe("Repeat")
				expect(stmt.count.value).toBe(3)
				expect(stmt.body[1].kind).toBe("CallStmt")
				expect(stmt.body[1].call.name).toBe("move_up")
			end
		end)

		it("builds if / elif / else chains", function()
			local program = compile(
				"if can_harvest():\n    harvest()\nelif is_empty():\n    plant('wheat')\nelse:\n    water()"
			)
			local stmt = program.body[1]
			expect(stmt.kind).toBe("If")
			expect(#stmt.clauses).toBe(2)
			expect(stmt.clauses[2].cond.name).toBe("is_empty")
			expect(stmt.elseBody[1].call.name).toBe("water")
		end)

		it("gives 'not' lower precedence than comparisons and 'and' lower than 'not'", function()
			local program = compile("if not get_x() == 1 and is_empty():\n    pass")
			local cond = program.body[1].clauses[1].cond
			expect(cond.kind).toBe("Logical")
			expect(cond.op).toBe("and")
			expect(cond.left.kind).toBe("Not")
			expect(cond.left.operand.kind).toBe("Compare")
			expect(cond.right.kind).toBe("Call")
		end)

		it("binds 'and' tighter than 'or'", function()
			local program = compile("if True or False and False:\n    pass")
			local cond = program.body[1].clauses[1].cond
			expect(cond.op).toBe("or")
			expect(cond.right.op).toBe("and")
		end)

		it("supports parentheses and while loops", function()
			local program = compile("while (get_x() < 3):\n    move_right()")
			expect(program.body[1].kind).toBe("While")
			expect(program.body[1].cond.kind).toBe("Compare")
		end)

		it("keeps line numbers on every statement", function()
			local program = compile("# intro\n\nmove_up()\nrepeat 2:\n    move_down()")
			expect(program.body[1].line).toBe(3)
			expect(program.body[2].body[1].line).toBe(5)
		end)

		it("suggests the closest command for typos", function()
			local err = compileError("mvoe_up()")
			expect(err.message).toContain("Did you mean 'move_up'")
		end)

		it("asks for () after a command name", function()
			local err = compileError("move_up")
			expect(err.message).toContain("Add () after 'move_up'")
		end)

		it("checks argument counts", function()
			expect(compileError("plant()").message).toContain("needs 1 value")
			expect(compileError("move_up(1)").message).toContain("doesn't take any values")
		end)

		it("rejects obviously wrong literal types", function()
			expect(compileError("plant(5)").message).toContain("needs text in quotes")
		end)

		it("explains unquoted text", function()
			expect(compileError("plant(wheat)").message).toContain("put it in quotes")
		end)

		it("suggests a command for an unknown bare name", function()
			expect(compileError("if can_harvst:\n    pass").message).toContain("can_harvest()")
		end)

		it("explains 'else if'", function()
			expect(compileError("if True:\n    pass\nelse if False:\n    pass").message).toContain("elif")
		end)

		it("rejects elif/else without an if", function()
			expect(compileError("elif True:\n    pass").message).toContain("must come right after an 'if'")
		end)

		it("requires a ':' at the end of block lines", function()
			local err = compileError("if True\nmove_up()")
			expect(err.line).toBe(1)
			expect(err.message).toContain("Add ':'")
		end)

		it("requires a repeat count", function()
			expect(compileError("repeat times:\n    pass").message).toContain("how many times")
		end)

		it("rejects chained comparisons", function()
			expect(compileError("if 1 < 2 < 3:\n    pass").message).toContain("two values at a time")
		end)

		it("explains unsupported Python keywords", function()
			expect(compileError("while True:\n    break").message).toContain("'break' isn't available")
			expect(compileError("x = lambda").message).toContain("def")
		end)

		it("rejects two commands on one line", function()
			expect(compileError("move_up() move_down()").message).toContain("own line")
		end)

		it("rejects one-line blocks", function()
			expect(compileError("if True: move_up()").message).toContain("next lines")
		end)

		it("limits block nesting", function()
			local lines = {}
			for depth = 0, 8 do
				table.insert(lines, string.rep("    ", depth) .. "if True:")
			end
			table.insert(lines, string.rep("    ", 9) .. "pass")
			expect(compileError(table.concat(lines, "\n")).message).toContain("Too many blocks")
		end)

		it("limits expression nesting", function()
			local source = "if " .. string.rep("not ", 20) .. "True:\n    pass"
			expect(compileError(source).message).toContain("too many brackets")
		end)

		describe("Logic & Data syntax", function()
			it("follows Python operator precedence", function()
				local program = compile("x = 1 + 2 * 3 - -4")
				local value = program.body[1].value
				expect(value.kind).toBe("Binary")
				expect(value.op).toBe("-")
				expect(value.left.op).toBe("+")
				expect(value.left.right.op).toBe("*")
				expect(value.right.kind).toBe("Number") -- '-4' folds into a literal
				expect(value.right.value).toBe(-4)
			end)

			it("builds assignments, lists, dicts, indexing and methods", function()
				local program = compile("items = [1, 2]\nitems[0] += 5\nd = {'a': 1}\nitems.append(d['a'])")
				expect(program.body[1].kind).toBe("Assign")
				expect(program.body[1].value.kind).toBe("List")
				expect(program.body[2].op).toBe("+=")
				expect(program.body[2].target.kind).toBe("Index")
				expect(program.body[3].value.kind).toBe("Dict")
				expect(program.body[4].call.kind).toBe("MethodCall")
				expect(program.body[4].call.method).toBe("append")
			end)

			it("records Python scoping for functions", function()
				local program = compile("total = 0\ndef add(n):\n    step = n * 2\n    return step\nadd(1)")
				local def = program.defs.add
				expect(def.params[1]).toBe("n")
				expect(def.locals.n).toBe(true)
				expect(def.locals.step).toBe(true)
				expect(def.locals.total).toBeNil()
			end)

			it("parses for loops, in / not in and imports", function()
				local program =
					compile("import utils\nfor x in range(3):\n    if x not in [1]:\n        pass")
				expect(program.body[1].kind).toBe("Import")
				expect(program.imports.utils).toBe(true)
				expect(program.body[2].kind).toBe("For")
				expect(program.body[2].body[1].clauses[1].cond.op).toBe("not in")
			end)

			it("allows calling a function defined further down", function()
				expect(compile("go()\ndef go():\n    move_up()")).toBeTruthy()
			end)

			it("reports unknown names, wrong arity and misplaced def/return/import", function()
				expect(compileError("print(speed)").message).toContain("isn't something the drone knows")
				expect(compileError("def f(a):\n    pass\nf()").message).toContain("needs 1 value")
				expect(compileError("if True:\n    def f():\n        pass").message).toContain("top level")
				expect(compileError("return 5").message).toContain("inside a function")
				expect(compileError("if True:\n    import utils").message).toContain("top level")
				expect(compileError("x = [1]\nx.push(2)").message).toContain("Unknown method")
				expect(compileError("print = 5").message).toContain("built-in command")
				expect(compileError("x == 5").message).toContain("single '='")
				expect(compileError("x + 1").message).toContain("doesn't do anything")
				expect(compileError("def f():\n    pass\ndef f():\n    pass").message).toContain(
					"already a function"
				)
			end)

			it("treats names assigned inside a function as local to it", function()
				local err = compileError("def f():\n    secret = 1\n    return secret\nprint(secret)")
				expect(err.line).toBe(4)
			end)
		end)

		describe("Tech Tree gate", function()
			local Tech = Loader.get("ReplicatedStorage.Shared.Progression.Tech")
			local function gate(unlocks)
				return function(feature)
					return Tech.isFeatureUnlocked(unlocks, feature)
				end
			end
			local function gatedError(source, unlocks)
				local program, err = Parser.compile(source, limits, gate(unlocks))
				expect(program).toBeNil()
				return err
			end
			local function compiles(source, unlocks)
				local program, err = Parser.compile(source, limits, gate(unlocks))
				if program == nil then
					error("expected to compile, got: " .. err.message, 2)
				end
			end
			local function allExcept(nodeId)
				local unlocks = {}
				for _, id in Tech.NodeIds do
					unlocks[id] = true
				end
				unlocks[nodeId] = nil
				return unlocks
			end

			it("compiles the starter script with no research at all", function()
				compiles(GameConfig.StarterScript, {})
			end)

			it("keeps if / can_harvest free from the start", function()
				compiles("if can_harvest():\n    harvest()", {})
			end)

			it("rejects while loops until Loops is researched", function()
				local source = "while True:\n    move_up()"
				local err = gatedError(source, {})
				expect(err.line).toBe(1)
				expect(err.message).toContain('Research Loops "while True:"')
				compiles(source, { loops = true })
			end)

			it("names the node for every gated piece of Logic & Data syntax", function()
				local cases = {
					{ "x = 2", "loops", "Loops" },
					{ "print(1 + 1)", "math", "Math" },
					{ "move_up()\nprint(get_x())", "grid_1", "Grid Expansion I" },
					{ "x = [1, 2]", "arrays", "Lists" },
					{ "for i in range(3):\n    pass", "arrays", "Lists" },
					{ "def f():\n    pass", "functions", "Functions" },
					{ "d = {1: 2}", "dictionaries", "Dictionaries" },
					{ "import utils", "import", "Modules" },
					{ "print(random())", "random", "Randomness" },
					{ "print(get_cost('loops'))", "get_cost", "Cost Scanner" },
				}
				for _, case in cases do
					local err = gatedError(case[1], allExcept(case[2]))
					expect(err.message).toContain(case[3])
				end
			end)

			it("has print() free from the start but gates set_speed() behind System research", function()
				compiles("print(1)", {}) -- no research needed
				expect(gatedError("set_speed(2)", {}).message).toContain("Throttle Control")
			end)
		end)

		it("limits the total number of AST nodes", function()
			local small = table.clone(limits)
			small.maxNodes = 5
			expect(compileError("move_up()\nmove_up()\nmove_up()\nmove_up()", small).message).toContain(
				"too complex"
			)
		end)
	end)
end
