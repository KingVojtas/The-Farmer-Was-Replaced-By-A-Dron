--!strict
--[[
	Interpreter
	===========
	Executes a parsed drone Program (AST from Shared.DroneScript.Parser) by walking the tree.

	SECURITY MODEL
	  * The AST is data. The only side effects a program can cause are calls into the
	    `builtins` table the caller hands in (DroneAPI on the server). No Lua code is created,
	    no loadstring, no access to globals, Instances or the environment. Program values live
	    in their own little world (Shared.DroneScript.Values).
	  * CPU: every statement, loop pass and call costs one "step".
	      - every `yieldEvery` steps -> ctx.yield() (ScriptService: task.wait(yieldEvery /
	        StepsPerSecond)), so a program gets a fixed CPU budget per second, whatever it does.
	      - `maxIdleSteps` steps WITHOUT any drone action -> error "stuck loop". A program that
	        keeps doing actions (a real `while True:` farm loop) may run forever, because each
	        action takes real time.
	      - optional ctx.maxSteps: hard total budget (used by simulate()).
	  * Recursion: user functions nest at most `maxCallDepth` deep; expressions/blocks are
	    bounded by the Parser's depth limits. So the Lua stack stays small.
	  * Memory: one list/dict holds at most `maxContainerItems` items; every `heapScanEvery`
	    created items a bounded reachability scan (from every variable of every running frame
	    and loaded module) fails the program if more than `maxLiveItems` items are reachable.
	    Strings built at runtime are capped at `maxStringResult` characters; numbers must stay
	    finite and within `maxComputed`.
	  * Cancellation is cooperative: ctx.isCancelled() is checked after every yield and every
	    builtin call (actions yield inside the builtin).

	RESULTS (never throws):
	  { status = "finished" }
	  { status = "cancelled" }
	  { status = "limit" }                                       -- ctx.maxSteps reached
	  { status = "error", error = { line, col, message, module? } }  -- the player's mistake
	  { status = "internal", message, trace }                    -- a bug on OUR side
	Every result also carries `steps` (total steps executed).

	Conditions must be True/False - no truthiness - which gives clearer errors to learners.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BuiltinsModule = require(ReplicatedStorage.Shared.DroneScript.Builtins)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Parser = require(ReplicatedStorage.Shared.DroneScript.Parser)
local Values = require(ReplicatedStorage.Shared.DroneScript.Values)

type Program = Parser.Program
type Block = Parser.Block
type Stmt = Parser.Stmt
type Expr = Parser.Expr
type DefStmt = Parser.DefStmt
type Spec = BuiltinsModule.Spec
type Module = Values.Module

-- A builtin implementation receives the evaluated arguments and returns a value, or
-- (nil, message) to raise a runtime error on the calling line.
export type BuiltinImpl = (args: { any }) -> (any, string?)

export type Limits = {
	maxIdleSteps: number,
	yieldEvery: number,
	maxRepeat: number,
	maxCallDepth: number?,
	maxContainerItems: number?,
	maxLiveItems: number?,
	heapScanEvery: number?,
	maxStringResult: number?,
	maxComputed: number?,
}

-- Returns the compiled program of another script slot, or (nil, player-facing reason).
export type ModuleLoader = (name: string) -> (Program?, string?)

export type Context = {
	specs: { [string]: Spec },
	builtins: { [string]: BuiltinImpl },
	yield: () -> (),
	isCancelled: () -> boolean,
	-- called right before each action; `inMain` is false while code from an imported module runs
	onAction: ((line: number, inMain: boolean) -> ())?,
	-- called after each completed pass of a while / repeat body (the tutorial's "it loops")
	onLoop: (() -> ())?,
	loadModule: ModuleLoader?,
	moduleName: string?, -- name of the running script (importing it from itself is a cycle)
	maxSteps: number?,
	limits: Limits,
}

export type RunResult = {
	status: "finished" | "cancelled" | "limit" | "error" | "internal",
	error: { line: number, col: number, message: string, module: string? }?,
	message: string?,
	trace: string?,
	steps: number?,
}

type Pos = { line: number, col: number }

type Frame = {
	module: Module,
	def: DefStmt?,
	locals: { [string]: any },
	returnValue: any,
}

-- Unique markers for control flow through error().
local CANCEL = table.freeze({ cancel = true })
local LIMIT = table.freeze({ limit = true })
local ScriptError = {}
-- Returned (not thrown) by statements to unwind a `return` up to its function call.
local RETURN = table.freeze({ returning = true })

local NONE = Values.NONE

local TYPE_WORDS: { [string]: string } = {
	number = "a number",
	string = "text",
	boolean = "True or False",
}

local function showValue(value: any): string
	return Values.repr(value, 60)
end

local function isInteger(value: any): boolean
	return type(value) == "number" and value % 1 == 0 and value == value
end

local Interpreter = {}

function Interpreter.run(program: Program, ctx: Context): RunResult
	local limits = ctx.limits
	local S = GameConfig.Script
	local maxCallDepth = limits.maxCallDepth or S.MaxCallDepth
	local maxContainerItems = limits.maxContainerItems or S.MaxContainerItems
	local maxLiveItems = limits.maxLiveItems or S.MaxLiveItems
	local heapScanEvery = limits.heapScanEvery or S.HeapScanEvery
	local maxStringResult = limits.maxStringResult or S.MaxStringResult
	local maxComputed = limits.maxComputed or S.MaxComputed

	local idleSteps = 0
	local stepsSinceYield = 0
	local totalSteps = 0
	local allocated = 0
	local callDepth = 0

	local mainModule = Values.newModule(ctx.moduleName or "main")
	local modules: { [string]: Module } = {}
	local loading: { [string]: boolean } = {}
	local frames: { Frame } = {}

	local function currentModule(): Module
		local top = frames[#frames]
		return if top ~= nil then top.module else mainModule
	end

	local function raise(node: Pos, message: string): never
		local module = currentModule()
		error(
			setmetatable({
				line = node.line,
				col = node.col,
				message = message,
				module = if module ~= mainModule then module.name else nil,
			}, ScriptError),
			0
		)
	end

	local function checkCancel()
		if ctx.isCancelled() then
			error(CANCEL, 0)
		end
	end

	local function step(node: Pos)
		idleSteps += 1
		stepsSinceYield += 1
		totalSteps += 1
		if ctx.maxSteps ~= nil and totalSteps > ctx.maxSteps then
			error(LIMIT, 0)
		end
		if idleSteps > limits.maxIdleSteps then
			raise(
				node,
				string.format(
					"Your program ran %d steps without the drone doing anything. Is there a loop that never moves, plants, waters or harvests?",
					limits.maxIdleSteps
				)
			)
		end
		if stepsSinceYield >= limits.yieldEvery then
			stepsSinceYield = 0
			ctx.yield()
			checkCancel()
		end
	end

	---------------------------------------------------------------------------------- memory
	local function scanHeap(node: Pos)
		local visited: { [any]: boolean } = {}
		local stack: { any } = {}
		local count = 0
		local function push(value: any)
			if (Values.isList(value) or Values.isDict(value)) and not visited[value] then
				visited[value] = true
				table.insert(stack, value)
			end
		end
		local function pushAll(map: { [string]: any })
			for _, value in map do
				push(value)
			end
		end
		pushAll(mainModule.globals)
		for _, module in modules do
			pushAll(module.globals)
		end
		for _, frame in frames do
			pushAll(frame.locals)
		end
		while #stack > 0 do
			local value = table.remove(stack)
			if Values.isList(value) then
				count += #value.items
				if count > maxLiveItems then
					break
				end
				for _, item in value.items do
					push(item)
				end
			else
				count += #value.keys
				if count > maxLiveItems then
					break
				end
				for _, item in value.map do
					push(item)
				end
			end
		end
		if count > maxLiveItems then
			raise(
				node,
				string.format(
					"Your program is holding too much data (more than %d items in lists and dictionaries).",
					maxLiveItems
				)
			)
		end
	end

	local function allocate(node: Pos, count: number)
		allocated += count
		if allocated >= heapScanEvery then
			allocated = 0
			scanHeap(node)
		end
	end

	local function checkSize(node: Pos, size: number)
		if size > maxContainerItems then
			raise(node, string.format("A list or dictionary can hold at most %d items.", maxContainerItems))
		end
	end

	-- Converts what a builtin returned into a program value.
	local function fromHost(node: Pos, value: any): any
		if value == nil then
			return NONE
		end
		local t = type(value)
		if t ~= "table" or Values.kind(value) ~= "unknown" then
			return value
		end
		-- A plain { key = primitive } table (e.g. get_cost) becomes a dictionary.
		local keys: { any } = {}
		for key in value do
			if Values.isHashable(key) then
				table.insert(keys, key)
			end
		end
		table.sort(keys, function(a: any, b: any): boolean
			return tostring(a) < tostring(b)
		end)
		checkSize(node, #keys)
		local dict = Values.newDict()
		for _, key in keys do
			local item = value[key]
			local kind = type(item)
			if kind == "number" or kind == "string" or kind == "boolean" then
				Values.dictSet(dict, key, item)
			end
		end
		allocate(node, #dict.keys)
		return dict
	end

	----------------------------------------------------------------------------- variables
	local function lookupName(node: Pos, name: string, frame: Frame): any
		local def = frame.def
		local value: any
		if def ~= nil and def.locals[name] then
			value = frame.locals[name]
		else
			value = frame.module.globals[name]
		end
		if value == nil then
			raise(node, string.format("'%s' is used before it gets a value.", name))
		end
		return value
	end

	local function assignName(frame: Frame, name: string, value: any)
		local def = frame.def
		if def ~= nil and def.locals[name] then
			frame.locals[name] = value
		else
			frame.module.globals[name] = value
		end
	end

	------------------------------------------------------------------------------- values
	local function requireBool(value: any, node: Pos, what: string): boolean
		if type(value) ~= "boolean" then
			raise(
				node,
				string.format(
					"%s needs True or False, but got %s (%s).",
					what,
					Values.typeWord(value),
					showValue(value)
				)
			)
		end
		return value
	end

	local function checkNumber(node: Pos, n: number): number
		if n ~= n or n == math.huge or n == -math.huge or math.abs(n) > maxComputed then
			raise(node, "That calculation gives a number that is too big (or not a number at all).")
		end
		return n
	end

	local function binary(node: Pos, op: string, a: any, b: any): any
		local ta, tb = type(a), type(b)
		if op == "+" then
			if ta == "number" and tb == "number" then
				return checkNumber(node, a + b)
			elseif ta == "string" and tb == "string" then
				local joined = a .. b
				if #joined > maxStringResult then
					raise(node, string.format("Text can be at most %d characters long.", maxStringResult))
				end
				return joined
			elseif Values.isList(a) and Values.isList(b) then
				local items = table.move(a.items, 1, #a.items, 1, {})
				table.move(b.items, 1, #b.items, #items + 1, items)
				checkSize(node, #items)
				allocate(node, #items)
				return Values.newList(items)
			end
			raise(
				node,
				string.format(
					"'+' works on two numbers, two texts or two lists, but got %s and %s.",
					Values.typeWord(a),
					Values.typeWord(b)
				)
			)
		end
		if ta ~= "number" or tb ~= "number" then
			raise(
				node,
				string.format(
					"'%s' only works with numbers, but got %s and %s.",
					op,
					Values.typeWord(a),
					Values.typeWord(b)
				)
			)
		end
		if op == "-" then
			return checkNumber(node, a - b)
		elseif op == "*" then
			return checkNumber(node, a * b)
		end
		if b == 0 then
			raise(node, "You can't divide by zero.")
		end
		if op == "/" then
			return checkNumber(node, a / b)
		elseif op == "//" then
			return checkNumber(node, math.floor(a / b))
		elseif op == "%" then
			return checkNumber(node, a % b) -- Luau's % is floored, exactly like Python's
		end
		error("Interpreter: unknown operator " .. op)
		return nil
	end

	-- 0-based player position -> 1-based Lua index (negative counts from the end).
	local function listIndex(node: Pos, list: Values.List, position: any): number
		if not isInteger(position) then
			raise(
				node,
				string.format("List positions must be whole numbers, but got %s.", showValue(position))
			)
		end
		local n = #list.items
		local i = position :: number
		if i < 0 then
			i += n
		end
		if i < 0 or i >= n then
			if n == 0 then
				raise(
					node,
					string.format("Position %s doesn't exist - the list is empty.", showValue(position))
				)
			end
			raise(
				node,
				string.format(
					"Position %s is outside the list (it has %d item%s: positions 0 to %d).",
					showValue(position),
					n,
					if n == 1 then "" else "s",
					n - 1
				)
			)
		end
		return i + 1
	end

	local function requireKey(node: Pos, key: any): any
		if not Values.isHashable(key) then
			raise(
				node,
				string.format(
					"Dictionary keys must be numbers, text or True/False, but got %s.",
					Values.typeWord(key)
				)
			)
		end
		return key
	end

	local function indexGet(node: Pos, object: any, key: any): any
		if Values.isList(object) then
			return object.items[listIndex(node, object, key)]
		elseif Values.isDict(object) then
			local value = object.map[requireKey(node, key)]
			if value == nil then
				raise(node, string.format("The dictionary has no key %s.", showValue(key)))
			end
			return value
		end
		raise(
			node,
			string.format(
				"You can only use [ ] on lists and dictionaries, not on %s.",
				Values.typeWord(object)
			)
		)
		return nil
	end

	local function indexSet(node: Pos, object: any, key: any, value: any)
		if Values.isList(object) then
			object.items[listIndex(node, object, key)] = value
		elseif Values.isDict(object) then
			requireKey(node, key)
			if object.map[key] == nil then
				checkSize(node, #object.keys + 1)
				allocate(node, 1)
			end
			Values.dictSet(object, key, value)
		else
			raise(
				node,
				string.format(
					"You can only use [ ] on lists and dictionaries, not on %s.",
					Values.typeWord(object)
				)
			)
		end
	end

	local function contains(node: Pos, container: any, item: any): boolean
		if Values.isList(container) then
			for _, value in container.items do
				if Values.equals(value, item) then
					return true
				end
			end
			return false
		elseif Values.isDict(container) then
			return Values.isHashable(item) and container.map[item] ~= nil
		elseif type(container) == "string" then
			if type(item) ~= "string" then
				raise(node, '\'in\' on text needs text on the left, like: "ab" in "cabin"')
			end
			return string.find(container, item, 1, true) ~= nil
		elseif Values.isRange(container) then
			if not isInteger(item) then
				return false
			end
			local r = container :: Values.Range
			local offset = item - r.start
			if offset % r.step ~= 0 then
				return false
			end
			local position = offset / r.step
			return position >= 0 and position < Values.rangeLength(r)
		end
		raise(
			node,
			string.format(
				"'in' works with lists, dictionaries, ranges and text, but got %s.",
				Values.typeWord(container)
			)
		)
		return false
	end

	---------------------------------------------------------------------------- execution
	local evaluate: (expr: Expr, frame: Frame) -> any
	local executeBlock: (block: Block, frame: Frame) -> any

	local function evalArgs(args: { Expr }, frame: Frame): { any }
		local values = table.create(#args)
		for i, arg in args do
			values[i] = evaluate(arg, frame)
		end
		return values
	end

	local function callFunction(node: Pos, fn: any, args: { any }, label: string): any
		if not Values.isFunction(fn) then
			raise(node, string.format("'%s' is %s, not a function.", label, Values.typeWord(fn)))
		end
		local def = fn.def :: DefStmt
		if #args ~= #def.params then
			raise(
				node,
				string.format(
					"%s() needs %d value%s, but got %d.",
					def.name,
					#def.params,
					if #def.params == 1 then "" else "s",
					#args
				)
			)
		end
		if callDepth >= maxCallDepth then
			raise(
				node,
				string.format(
					"Too many functions calling each other (more than %d deep). Does a function call itself forever?",
					maxCallDepth
				)
			)
		end
		step(node)
		local locals: { [string]: any } = {}
		for i, param in def.params do
			locals[param] = args[i]
		end
		local frame: Frame = { module = fn.module, def = def, locals = locals, returnValue = nil }
		callDepth += 1
		table.insert(frames, frame)
		executeBlock(def.body, frame)
		table.remove(frames)
		callDepth -= 1
		local result = frame.returnValue
		return if result == nil then NONE else result
	end

	local function intrinsic(call: Parser.CallExpr, args: { any }): any
		local name = call.name
		if name == "len" then
			local value = args[1]
			if Values.isList(value) then
				return #value.items
			elseif Values.isDict(value) then
				return #value.keys
			elseif type(value) == "string" then
				return utf8.len(value) or #value
			elseif Values.isRange(value) then
				return Values.rangeLength(value)
			end
			raise(
				call,
				string.format(
					"len() works on lists, dictionaries and text, but got %s.",
					Values.typeWord(value)
				)
			)
		elseif name == "range" then
			for _, value in args do
				if not isInteger(value) then
					raise(call, string.format("range() needs whole numbers, but got %s.", showValue(value)))
				end
			end
			local start, stop, stepBy = 0, args[1], 1
			if #args >= 2 then
				start, stop = args[1], args[2]
			end
			if #args == 3 then
				stepBy = args[3]
			end
			if stepBy == 0 then
				raise(call, "range() can't count in steps of 0.")
			end
			return Values.newRange(start, stop, stepBy)
		end
		error("Interpreter: unknown intrinsic " .. name)
	end

	local function callBuiltin(call: Parser.CallExpr, frame: Frame): any
		local spec = ctx.specs[call.name]
		if spec == nil then
			raise(call, string.format("Unknown command '%s'.", call.name)) -- the parser prevents this
		end
		assert(spec ~= nil, "unreachable: raise() never returns")

		local args = table.create(#call.args)
		for index, argExpr in call.args do
			local value = evaluate(argExpr, frame)
			local wanted = spec.params[math.min(index, #spec.params)]
			if wanted ~= nil and wanted ~= "any" and type(value) ~= wanted then
				raise(
					argExpr,
					string.format(
						"%s() needs %s for value %d, but got %s (%s).",
						call.name,
						TYPE_WORDS[wanted] or wanted,
						index,
						Values.typeWord(value),
						showValue(value)
					)
				)
			end
			args[index] = value
		end

		step(call)
		if spec.kind == "intrinsic" then
			return intrinsic(call, args)
		end
		local impl = ctx.builtins[call.name]
		if impl == nil then
			raise(call, string.format("Unknown command '%s'.", call.name)) -- locked: defence in depth
		end
		assert(impl ~= nil, "unreachable: raise() never returns")
		if spec.kind == "action" then
			idleSteps = 0 -- the drone did real (time-consuming) work
			if ctx.onAction then
				ctx.onAction(call.line, currentModule() == mainModule)
			end
		end

		local result, message = impl(args)
		checkCancel() -- actions yield inside impl; the player may have pressed Stop meanwhile
		if message ~= nil then
			raise(call, message)
		end
		return fromHost(call, result)
	end

	local function callMethod(expr: Parser.MethodCallExpr, frame: Frame): any
		local object = evaluate(expr.object, frame)
		local args = evalArgs(expr.args, frame)
		local method = expr.method

		if Values.isModule(object) then
			local fn = object.globals[method]
			if fn == nil then
				raise(expr, string.format("Module '%s' has no '%s'.", object.name, method))
			end
			return callFunction(expr, fn, args, object.name .. "." .. method)
		end

		step(expr)
		if Values.isList(object) then
			local items = object.items
			if method == "append" then
				checkSize(expr, #items + 1)
				table.insert(items, args[1])
				allocate(expr, 1)
				return NONE
			elseif method == "pop" then
				if #items == 0 then
					raise(expr, "pop() can't take anything from an empty list.")
				end
				local index = if args[1] ~= nil then listIndex(expr, object, args[1]) else #items
				return table.remove(items, index)
			end
		elseif Values.isDict(object) then
			if method == "keys" or method == "values" then
				local result: { any } = table.create(#object.keys)
				for i, key in object.keys do
					result[i] = if method == "keys" then key else object.map[key]
				end
				allocate(expr, #result)
				return Values.newList(result)
			elseif method == "get" then
				local key = args[1]
				local value = if Values.isHashable(key) then object.map[key] else nil
				if value ~= nil then
					return value
				end
				return if args[2] ~= nil then args[2] else NONE
			end
		end
		raise(expr, string.format("%s has no method '.%s()'.", Values.typeWord(object), method))
		return nil
	end

	evaluate = function(expr: Expr, frame: Frame): any
		if expr.kind == "Number" or expr.kind == "String" or expr.kind == "Bool" then
			return (expr :: any).value
		elseif expr.kind == "None" then
			return NONE
		elseif expr.kind == "Name" then
			return lookupName(expr, expr.name, frame)
		elseif expr.kind == "Call" then
			if expr.builtin then
				return callBuiltin(expr, frame)
			end
			local fn = lookupName(expr, expr.name, frame)
			return callFunction(expr, fn, evalArgs(expr.args, frame), expr.name)
		elseif expr.kind == "MethodCall" then
			return callMethod(expr, frame)
		elseif expr.kind == "Attribute" then
			local object = evaluate(expr.object, frame)
			if not Values.isModule(object) then
				raise(expr, string.format("%s has no '.%s'.", Values.typeWord(object), expr.name))
			end
			local value = object.globals[expr.name]
			if value == nil then
				raise(expr, string.format("Module '%s' has no '%s'.", object.name, expr.name))
			end
			return value
		elseif expr.kind == "Index" then
			local object = evaluate(expr.object, frame)
			return indexGet(expr, object, evaluate(expr.index, frame))
		elseif expr.kind == "List" then
			checkSize(expr, #expr.items)
			local items = evalArgs(expr.items, frame)
			allocate(expr, #items)
			return Values.newList(items)
		elseif expr.kind == "Dict" then
			checkSize(expr, #expr.keys)
			local dict = Values.newDict()
			for i, keyExpr in expr.keys do
				local key = requireKey(keyExpr, evaluate(keyExpr, frame))
				Values.dictSet(dict, key, evaluate(expr.values[i], frame))
			end
			allocate(expr, #dict.keys)
			return dict
		elseif expr.kind == "Unary" then
			local value = evaluate(expr.operand, frame)
			if type(value) ~= "number" then
				raise(expr, string.format("'-' only works with numbers, but got %s.", Values.typeWord(value)))
			end
			return checkNumber(expr, -value)
		elseif expr.kind == "Binary" then
			local left = evaluate(expr.left, frame)
			local right = evaluate(expr.right, frame)
			return binary(expr, expr.op, left, right)
		elseif expr.kind == "Not" then
			return not requireBool(evaluate(expr.operand, frame), expr, "'not'")
		elseif expr.kind == "Logical" then
			local left = requireBool(evaluate(expr.left, frame), expr, "'" .. expr.op .. "'")
			-- Short-circuit exactly like Python.
			if expr.op == "and" and not left then
				return false
			elseif expr.op == "or" and left then
				return true
			end
			return requireBool(evaluate(expr.right, frame), expr, "'" .. expr.op .. "'")
		elseif expr.kind == "Compare" then
			local left = evaluate(expr.left, frame)
			local right = evaluate(expr.right, frame)
			local op = expr.op
			if op == "==" then
				return Values.equals(left, right)
			elseif op == "!=" then
				return not Values.equals(left, right)
			elseif op == "in" then
				return contains(expr, right, left)
			elseif op == "not in" then
				return not contains(expr, right, left)
			end
			if type(left) ~= "number" or type(right) ~= "number" then
				raise(
					expr,
					string.format(
						"'%s' only works with numbers, but got %s and %s.",
						op,
						Values.typeWord(left),
						Values.typeWord(right)
					)
				)
			end
			if op == "<" then
				return left < right
			elseif op == ">" then
				return left > right
			elseif op == "<=" then
				return left <= right
			elseif op == ">=" then
				return left >= right
			end
		end
		error("Interpreter: unknown expression kind " .. tostring((expr :: any).kind))
		return nil
	end

	local function importModule(stmt: { name: string, line: number, col: number }, frame: Frame)
		local name = stmt.name
		local cached = modules[name]
		if cached ~= nil then
			frame.module.globals[name] = cached
			return
		end
		if name == mainModule.name or loading[name] then
			raise(stmt, string.format("'%s' imports itself (directly or through another module).", name))
		end
		local loader = ctx.loadModule
		if loader == nil then
			raise(stmt, "'import' isn't available here.")
		end
		assert(loader ~= nil, "unreachable: raise() never returns")
		local moduleProgram, reason = loader(name)
		checkCancel()
		if moduleProgram == nil then
			raise(stmt, string.format("Couldn't import '%s': %s", name, reason or "it doesn't exist."))
		end
		assert(moduleProgram ~= nil, "unreachable: raise() never returns")

		local module = Values.newModule(name)
		local moduleFrame: Frame = { module = module, def = nil, locals = {}, returnValue = nil }
		loading[name] = true
		table.insert(frames, moduleFrame)
		executeBlock(moduleProgram.body, moduleFrame)
		table.remove(frames)
		loading[name] = nil
		modules[name] = module
		frame.module.globals[name] = module
	end

	local function executeStatement(stmt: Stmt, frame: Frame): any
		step(stmt)
		if stmt.kind == "CallStmt" then
			evaluate(stmt.call, frame)
		elseif stmt.kind == "Pass" then
			return nil -- 'pass' does nothing on purpose
		elseif stmt.kind == "Assign" then
			local target = stmt.target
			if target.kind == "Name" then
				local value: any
				if stmt.op == "=" then
					value = evaluate(stmt.value, frame)
				else
					local current = lookupName(target, target.name, frame)
					value = binary(stmt, string.sub(stmt.op, 1, 1), current, evaluate(stmt.value, frame))
				end
				assignName(frame, target.name, value)
			elseif target.kind == "Index" then
				local object = evaluate(target.object, frame)
				local key = evaluate(target.index, frame)
				local value: any
				if stmt.op == "=" then
					value = evaluate(stmt.value, frame)
				else
					local current = indexGet(target, object, key)
					value = binary(stmt, string.sub(stmt.op, 1, 1), current, evaluate(stmt.value, frame))
				end
				indexSet(target, object, key, value)
			end
		elseif stmt.kind == "Repeat" then
			local count = evaluate(stmt.count, frame)
			if type(count) ~= "number" or count % 1 ~= 0 or count < 0 or count > limits.maxRepeat then
				raise(
					stmt,
					string.format(
						"'repeat' needs a whole number from 0 to %d, but got %s.",
						limits.maxRepeat,
						showValue(count)
					)
				)
			end
			for _ = 1, count do
				step(stmt)
				local signal = executeBlock(stmt.body, frame)
				if signal ~= nil then
					return signal
				end
				if ctx.onLoop then
					ctx.onLoop()
				end
			end
		elseif stmt.kind == "While" then
			while true do
				step(stmt)
				if not requireBool(evaluate(stmt.cond, frame), stmt, "'while'") then
					break
				end
				local signal = executeBlock(stmt.body, frame)
				if signal ~= nil then
					return signal
				end
				if ctx.onLoop then
					ctx.onLoop()
				end
			end
		elseif stmt.kind == "If" then
			for _, clause in stmt.clauses do
				if requireBool(evaluate(clause.cond, frame), clause.cond, "'if'") then
					return executeBlock(clause.body, frame)
				end
			end
			if stmt.elseBody ~= nil then
				return executeBlock(stmt.elseBody, frame)
			end
		elseif stmt.kind == "For" then
			local iterable = evaluate(stmt.iterable, frame)
			if Values.isList(iterable) then
				local items = iterable.items
				local i = 1
				while i <= #items do -- live: items appended during the loop are visited too
					step(stmt)
					assignName(frame, stmt.var, items[i])
					local signal = executeBlock(stmt.body, frame)
					if signal ~= nil then
						return signal
					end
					i += 1
				end
			elseif Values.isRange(iterable) then
				local r = iterable :: Values.Range
				local value = r.start
				while (r.step > 0 and value < r.stop) or (r.step < 0 and value > r.stop) do
					step(stmt)
					assignName(frame, stmt.var, value)
					local signal = executeBlock(stmt.body, frame)
					if signal ~= nil then
						return signal
					end
					value += r.step
				end
			elseif Values.isDict(iterable) then
				local keys = iterable.keys
				local i = 1
				while i <= #keys do
					step(stmt)
					assignName(frame, stmt.var, keys[i])
					local signal = executeBlock(stmt.body, frame)
					if signal ~= nil then
						return signal
					end
					i += 1
				end
			else
				raise(
					stmt,
					string.format(
						"'for' can loop over lists, dictionaries and range(), but got %s.",
						Values.typeWord(iterable)
					)
				)
			end
		elseif stmt.kind == "Def" then
			frame.module.globals[stmt.name] = Values.newFunction(stmt.name, stmt, frame.module)
		elseif stmt.kind == "Return" then
			frame.returnValue = if stmt.value ~= nil then evaluate(stmt.value, frame) else NONE
			return RETURN
		elseif stmt.kind == "Import" then
			importModule(stmt, frame)
		else
			error("Interpreter: unknown statement kind " .. tostring((stmt :: any).kind))
		end
		return nil
	end

	executeBlock = function(block: Block, frame: Frame): any
		for _, stmt in block do
			local signal = executeStatement(stmt, frame)
			if signal ~= nil then
				return signal
			end
		end
		return nil
	end

	local mainFrame: Frame = { module = mainModule, def = nil, locals = {}, returnValue = nil }
	local ok, err = xpcall(function()
		checkCancel()
		table.insert(frames, mainFrame)
		executeBlock(program.body, mainFrame)
	end, function(e: any): any
		if type(e) == "table" then
			return e -- CANCEL, LIMIT or a ScriptError: pass through untouched
		end
		return { internal = true, message = tostring(e), trace = debug.traceback(tostring(e), 2) }
	end)

	if ok then
		return { status = "finished", steps = totalSteps }
	elseif err == CANCEL then
		return { status = "cancelled", steps = totalSteps }
	elseif err == LIMIT then
		return { status = "limit", steps = totalSteps }
	elseif type(err) == "table" and getmetatable(err) == ScriptError then
		return {
			status = "error",
			error = { line = err.line, col = err.col, message = err.message, module = err.module },
			steps = totalSteps,
		}
	end
	local info = if type(err) == "table" then err else { message = tostring(err), trace = nil }
	return { status = "internal", message = info.message, trace = info.trace, steps = totalSteps }
end

return Interpreter
