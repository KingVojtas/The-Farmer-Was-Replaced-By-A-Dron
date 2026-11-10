--!strict
--[[
	Parser
	======
	Recursive-descent parser: tokens -> AST (plain tables). The AST is later walked by the
	server Interpreter. Nothing is ever compiled to Lua source and nothing is passed to
	loadstring - the only callable things are the whitelisted Builtins, the list/dict methods,
	and functions the program itself defines with `def`.

	Grammar (a small, Python-style language):
	  program    := { stmt } EOF
	  stmt       := simple NEWLINE
	              | 'repeat' expr ['times'] ':' block
	              | 'while' expr ':' block
	              | 'if' expr ':' block { 'elif' expr ':' block } [ 'else' ':' block ]
	              | 'for' NAME 'in' expr ':' block
	              | 'def' NAME '(' [ NAME { ',' NAME } ] ')' ':' block        (top level only)
	  simple     := 'pass' | 'return' [expr] | 'import' NAME                  (import: top level)
	              | target ('=' | '+=' | '-=' | '*=' | '/=') expr
	              | call                                   (a line must DO something)
	  target     := NAME | postfix '[' expr ']'
	  block      := NEWLINE INDENT stmt { stmt } DEDENT
	  expr       := and_expr { 'or' and_expr }
	  and_expr   := not_expr { 'and' not_expr }
	  not_expr   := 'not' not_expr | comparison
	  comparison := arith [ ('=='|'!='|'<'|'>'|'<='|'>='|'in'|'not' 'in') arith ]
	  arith      := term { ('+'|'-') term }
	  term       := unary { ('*'|'/'|'//'|'%') unary }
	  unary      := '-' unary | postfix
	  postfix    := primary { '[' expr ']' | '.' NAME [ '(' args ')' ] }
	  primary    := NUMBER | STRING | True | False | None | NAME | NAME '(' args ')'
	              | '(' expr ')' | '[' [ expr { ',' expr } ] ']' | '{' [ expr ':' expr { ',' ... } ] '}'

	Compile-time checks: unknown names and commands (with "did you mean"), argument counts,
	obviously wrong literal argument types, nesting depth, total AST size, and Python's scope
	rules (a name assigned inside a function is local to it; `return` only inside `def`).

	TECH TREE GATE: when an `isUnlocked(feature)` predicate is passed (the server always passes
	one built from the player's SAVED unlocks), every builtin and every gated piece of syntax
	is checked against it:
	  while / repeat -> "while"/"repeat"     + - * / // % and unary - -> "math"
	  assignments and variable names -> "variables"     [..], x[i], in, len, range -> "lists"
	  for -> "for"     def / return / calling your functions -> "def"     {..} -> "dicts"
	  import -> "import"     list methods -> "lists"     dict methods -> "dicts"
	A locked feature is a compile error that names the research needed, so a program can never
	even start with something the player hasn't unlocked.
]]

local Builtins = require(script.Parent.Builtins)
local Lexer = require(script.Parent.Lexer)
local Suggest = require(script.Parent.Suggest)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Tech = require(script.Parent.Parent.Progression.Tech)

type Token = Lexer.Token
export type CompileError = Lexer.CompileError

type Pos = { line: number, col: number }

-- Expressions --------------------------------------------------------------------------------
export type CallExpr = {
	kind: "Call",
	name: string,
	builtin: boolean, -- true: Builtins entry; false: a function the program defines
	args: { Expr },
	line: number,
	col: number,
}
export type MethodCallExpr = {
	kind: "MethodCall",
	object: Expr,
	method: string,
	args: { Expr },
	line: number,
	col: number,
}

export type Expr =
	{ kind: "Number", value: number, line: number, col: number }
	| { kind: "String", value: string, line: number, col: number }
	| { kind: "Bool", value: boolean, line: number, col: number }
	| { kind: "None", line: number, col: number }
	| { kind: "Name", name: string, line: number, col: number }
	| CallExpr
	| MethodCallExpr
	| { kind: "Attribute", object: Expr, name: string, line: number, col: number }
	| { kind: "Index", object: Expr, index: Expr, line: number, col: number }
	| { kind: "List", items: { Expr }, line: number, col: number }
	| { kind: "Dict", keys: { Expr }, values: { Expr }, line: number, col: number }
	| { kind: "Unary", op: string, operand: Expr, line: number, col: number }
	| { kind: "Binary", op: string, left: Expr, right: Expr, line: number, col: number }
	| { kind: "Not", operand: Expr, line: number, col: number }
	| { kind: "Logical", op: string, left: Expr, right: Expr, line: number, col: number }
	| { kind: "Compare", op: string, left: Expr, right: Expr, line: number, col: number }

-- Statements ---------------------------------------------------------------------------------
export type Clause = { cond: Expr, body: Block, line: number }

export type DefStmt = {
	kind: "Def",
	name: string,
	params: { string },
	locals: { [string]: boolean }, -- params + every name assigned inside (Python scoping)
	body: Block,
	line: number,
	col: number,
}

export type Stmt =
	{ kind: "CallStmt", call: CallExpr | MethodCallExpr, line: number, col: number }
	| { kind: "Pass", line: number, col: number }
	| { kind: "Repeat", count: Expr, body: Block, line: number, col: number }
	| { kind: "While", cond: Expr, body: Block, line: number, col: number }
	| { kind: "If", clauses: { Clause }, elseBody: Block?, line: number, col: number }
	| { kind: "For", var: string, iterable: Expr, body: Block, line: number, col: number }
	| { kind: "Assign", target: Expr, op: string, value: Expr, line: number, col: number }
	| { kind: "Return", value: Expr?, line: number, col: number }
	| { kind: "Import", name: string, line: number, col: number }
	| DefStmt

export type Block = { Stmt }

export type Program = {
	kind: "Program",
	body: Block,
	defs: { [string]: DefStmt },
	imports: { [string]: boolean },
}

export type FeatureCheck = (feature: string) -> boolean

export type Limits = Lexer.Limits & {
	maxNodes: number,
	maxBlockDepth: number,
	maxExprDepth: number,
}

-- Words people coming from Python/Lua will try; each gets a targeted explanation.
local UNSUPPORTED: { [string]: string } = {
	["break"] = "'break' isn't available - use a 'while' condition to stop a loop.",
	continue = "'continue' isn't available - use 'if' to skip the rest of the loop instead.",
	global = "Functions can read outside variables but not change them - return the new value instead.",
	nonlocal = "Functions can read outside variables but not change them - return the new value instead.",
	lambda = "Use 'def' to make a function.",
	class = "Classes aren't available - use a dictionary to group values together.",
	del = "'del' isn't available.",
	from = "Write 'import utils', then use utils.my_function().",
	["elseif"] = "Use 'elif'.",
	["function"] = "Use 'def' to make a function.",
	["nil"] = "Use None.",
	null = "Use None.",
	["end"] = "Blocks don't need 'end' - just stop indenting.",
	["then"] = "Write ':' instead of 'then'.",
	["do"] = "Write ':' instead of 'do'.",
	["until"] = "'until' isn't available - use 'while not ...:' instead.",
	["local"] = "Just write the name: a = 2",
	var = "Just write the name: a = 2",
	let = "Just write the name: a = 2",
}

local COMPARE_OPS: { [string]: boolean } = {
	["=="] = true,
	["!="] = true,
	["<"] = true,
	[">"] = true,
	["<="] = true,
	[">="] = true,
}

local ASSIGN_OPS: { [string]: boolean } = {
	["="] = true,
	["+="] = true,
	["-="] = true,
	["*="] = true,
	["/="] = true,
}

local TYPE_WORDS: { [string]: string } = {
	string = "text in quotes",
	number = "a number",
	boolean = "True or False",
}

local ParseFailure = {}

local function failAt(token: Pos, message: string): never
	error(setmetatable({ line = token.line, col = token.col, message = message }, ParseFailure), 0)
end

local function describe(token: Token): string
	if token.type == "newline" then
		return "the end of the line"
	elseif token.type == "eof" then
		return "the end of the program"
	elseif token.type == "indent" or token.type == "dedent" then
		return "a change in indentation"
	elseif token.type == "string" then
		return "text"
	elseif token.type == "number" then
		return "the number " .. token.value
	end
	return "'" .. token.value .. "'"
end

local function plural(n: number, word: string): string
	return string.format("%d %s%s", n, word, if n == 1 then "" else "s")
end

-- "needs 1 value" / "needs 1 to 3 values"
local function arityText(minArgs: number, maxArgs: number): string
	if minArgs == maxArgs then
		return plural(minArgs, "value")
	end
	return string.format("%d to %d values", minArgs, maxArgs)
end

local Parser = {}

-- Limits for a player whose drone memory holds `maxLines` lines.
function Parser.limits(maxLines: number?): Limits
	local s = GameConfig.Script
	return {
		maxLines = maxLines or s.BaseMaxLines,
		maxLineLength = s.MaxLineLength,
		maxSourceBytes = s.MaxSourceBytes,
		maxTokens = s.MaxTokens,
		maxStringLength = s.MaxStringLength,
		maxIdentifierLength = s.MaxIdentifierLength,
		maxNumber = s.MaxNumber,
		maxNodes = s.MaxNodes,
		maxBlockDepth = s.MaxBlockDepth,
		maxExprDepth = s.MaxExprDepth,
	}
end

type DefContext = { name: string, locals: { [string]: boolean } }

local function parseUnsafe(tokens: { Token }, limits: Limits, isUnlocked: FeatureCheck?): Program
	local pos = 1
	local nodeCount = 0
	local blockDepth = 0
	local exprDepth = 0
	local currentDef: DefContext? = nil

	-- What the program defines (filled while parsing, checked by resolveNames afterwards).
	local globalNames: { [string]: boolean } = {}
	local defs: { [string]: DefStmt } = {}
	local imports: { [string]: boolean } = {}

	local function peek(): Token
		return tokens[pos]
	end

	local function peekAt(offset: number): Token
		return tokens[math.min(pos + offset, #tokens)]
	end

	local function advance(): Token
		local token = tokens[pos]
		if pos < #tokens then -- never move past EOF
			pos += 1
		end
		return token
	end

	local function isOp(token: Token, value: string): boolean
		return token.type == "op" and token.value == value
	end

	local function isKeyword(token: Token, value: string): boolean
		return token.type == "keyword" and token.value == value
	end

	local function countNode(token: Pos)
		nodeCount += 1
		if nodeCount > limits.maxNodes then
			failAt(token, "Your program is too complex for the drone. Try making it shorter.")
		end
	end

	local function enterExpr(token: Pos)
		exprDepth += 1
		if exprDepth > limits.maxExprDepth then
			failAt(token, "This line has too many brackets or 'not's inside each other.")
		end
	end

	local function leaveExpr()
		exprDepth -= 1
	end

	-- Tech Tree gate (see header).
	local function requireFeature(token: Pos, feature: string)
		if isUnlocked ~= nil and not isUnlocked(feature) then
			failAt(token, Tech.lockedMessage(feature))
		end
	end

	local function expectColon(what: string)
		if isOp(peek(), ":") then
			advance()
			return
		end
		failAt(peek(), string.format("Add ':' at the end of the '%s' line.", what))
	end

	-- A simple statement must be followed by the end of its line.
	local function expectEndOfLine()
		local token = peek()
		if token.type == "newline" then
			advance()
		elseif token.type ~= "eof" and token.type ~= "dedent" then
			failAt(
				token,
				string.format("Unexpected %s - each command goes on its own line.", describe(token))
			)
		end
	end

	local function checkNotBuiltin(token: Token, what: string)
		if Builtins.ByName[token.value] ~= nil then
			failAt(
				token,
				string.format(
					"'%s' is a built-in command - pick another name for your %s.",
					token.value,
					what
				)
			)
		end
	end

	-- Records that `name` gets a value here (a local inside a def, otherwise a global).
	local function defineName(name: string)
		local def = currentDef
		if def ~= nil then
			def.locals[name] = true
		else
			globalNames[name] = true
		end
	end

	-- Forward declarations (the grammar is mutually recursive).
	local parseExpression: () -> Expr
	local parseStatement: () -> Stmt

	-- '(' already peeked. Returns the argument list.
	local function parseArgs(nameToken: Token, what: string): { Expr }
		advance() -- '('
		enterExpr(nameToken)
		local args: { Expr } = {}
		if not isOp(peek(), ")") then
			while true do
				table.insert(args, parseExpression())
				if isOp(peek(), ",") then
					advance()
					if isOp(peek(), ")") then
						break -- trailing comma
					end
				else
					break
				end
			end
		end
		if not isOp(peek(), ")") then
			failAt(peek(), string.format("Missing ')' after the values for %s.", what))
		end
		advance()
		leaveExpr()
		return args
	end

	local function parseCall(nameToken: Token): CallExpr
		local name = nameToken.value
		local spec = Builtins.ByName[name]
		if spec == nil then
			-- A function the program defines (checked by resolveNames once everything is parsed).
			local args = parseArgs(nameToken, name .. "()")
			countNode(nameToken)
			return {
				kind = "Call",
				name = name,
				builtin = false,
				args = args,
				line = nameToken.line,
				col = nameToken.col,
			}
		end
		requireFeature(nameToken, name)
		local args = parseArgs(nameToken, name .. "()")

		local count = #args
		if count < spec.minArgs or count > spec.maxArgs then
			if spec.maxArgs == 0 then
				failAt(
					nameToken,
					string.format("%s() doesn't take any values. Write it as %s.", name, spec.example)
				)
			end
			failAt(
				nameToken,
				string.format(
					"%s() needs %s, like %s.",
					name,
					arityText(spec.minArgs, spec.maxArgs),
					spec.example
				)
			)
		end

		-- Catch obviously wrong literals now (e.g. plant(5)); everything else is checked at runtime.
		for i, arg in args do
			local wanted = spec.params[math.min(i, #spec.params)]
			local literal = if arg.kind == "Number"
				then "number"
				elseif arg.kind == "String" then "string"
				elseif arg.kind == "Bool" then "boolean"
				else nil
			if wanted ~= nil and wanted ~= "any" and literal ~= nil and literal ~= wanted then
				failAt(
					arg,
					string.format("%s() needs %s here, like %s.", name, TYPE_WORDS[wanted], spec.example)
				)
			end
		end

		countNode(nameToken)
		return {
			kind = "Call",
			name = name,
			builtin = true,
			args = args,
			line = nameToken.line,
			col = nameToken.col,
		}
	end

	local function parsePrimary(): Expr
		local token = peek()
		if token.type == "number" then
			advance()
			countNode(token)
			return { kind = "Number", value = token.num :: number, line = token.line, col = token.col }
		elseif token.type == "string" then
			advance()
			countNode(token)
			return { kind = "String", value = token.value, line = token.line, col = token.col }
		elseif isKeyword(token, "True") or isKeyword(token, "False") then
			advance()
			countNode(token)
			return { kind = "Bool", value = token.value == "True", line = token.line, col = token.col }
		elseif isKeyword(token, "None") then
			advance()
			countNode(token)
			return { kind = "None", line = token.line, col = token.col }
		elseif token.type == "name" then
			local hint = UNSUPPORTED[token.value]
			if hint ~= nil then
				failAt(token, hint)
			end
			if isOp(peekAt(1), "(") then
				advance()
				return parseCall(token)
			end
			advance()
			countNode(token)
			return { kind = "Name", name = token.value, line = token.line, col = token.col }
		elseif isOp(token, "(") then
			advance()
			enterExpr(token)
			local inner = parseExpression()
			if isOp(peek(), ",") then
				failAt(peek(), "Pairs like (x, y) aren't available - use a list instead: [x, y]")
			end
			if not isOp(peek(), ")") then
				failAt(peek(), "Missing ')'.")
			end
			advance()
			leaveExpr()
			return inner
		elseif isOp(token, "[") then
			requireFeature(token, "lists")
			advance()
			enterExpr(token)
			local items: { Expr } = {}
			while not isOp(peek(), "]") do
				table.insert(items, parseExpression())
				if isOp(peek(), ",") then
					advance()
				elseif not isOp(peek(), "]") then
					failAt(peek(), "Separate list items with ',' and end the list with ']'.")
				end
			end
			advance() -- ']'
			leaveExpr()
			countNode(token)
			return { kind = "List", items = items, line = token.line, col = token.col }
		elseif isOp(token, "{") then
			requireFeature(token, "dicts")
			advance()
			enterExpr(token)
			local keys: { Expr } = {}
			local values: { Expr } = {}
			while not isOp(peek(), "}") do
				table.insert(keys, parseExpression())
				if not isOp(peek(), ":") then
					failAt(peek(), "Write each entry as key: value, like {'wheat': 2}.")
				end
				advance()
				table.insert(values, parseExpression())
				if isOp(peek(), ",") then
					advance()
				elseif not isOp(peek(), "}") then
					failAt(peek(), "Separate entries with ',' and end the dictionary with '}'.")
				end
			end
			advance() -- '}'
			leaveExpr()
			countNode(token)
			return { kind = "Dict", keys = keys, values = values, line = token.line, col = token.col }
		end
		return failAt(
			token,
			string.format(
				'Expected a value here (like True, 5, "wheat" or can_harvest()), but found %s.',
				describe(token)
			)
		)
	end

	local function parsePostfix(): Expr
		local expr = parsePrimary()
		while true do
			local token = peek()
			if isOp(token, "[") then
				requireFeature(token, "lists")
				advance()
				enterExpr(token)
				local index = parseExpression()
				if not isOp(peek(), "]") then
					failAt(peek(), "Missing ']'.")
				end
				advance()
				leaveExpr()
				countNode(token)
				expr = { kind = "Index", object = expr, index = index, line = token.line, col = token.col }
			elseif isOp(token, ".") then
				advance()
				local nameToken = peek()
				if nameToken.type ~= "name" then
					failAt(nameToken, "Write a name after '.', like items.append(5).")
				end
				advance()
				countNode(nameToken)
				if isOp(peek(), "(") then
					local args = parseArgs(nameToken, "." .. nameToken.value .. "()")
					expr = {
						kind = "MethodCall",
						object = expr,
						method = nameToken.value,
						args = args,
						line = nameToken.line,
						col = nameToken.col,
					}
				else
					expr = {
						kind = "Attribute",
						object = expr,
						name = nameToken.value,
						line = nameToken.line,
						col = nameToken.col,
					}
				end
			elseif isOp(token, "(") then
				failAt(token, "Only commands and functions can be called, like move_up() or my_function().")
			else
				break
			end
		end
		return expr
	end

	local function parseUnary(): Expr
		local token = peek()
		if isOp(token, "-") then
			requireFeature(token, "math")
			advance()
			enterExpr(token)
			local operand = parseUnary()
			leaveExpr()
			countNode(token)
			if operand.kind == "Number" then
				return { kind = "Number", value = -operand.value, line = token.line, col = token.col }
			end
			return { kind = "Unary", op = "-", operand = operand, line = token.line, col = token.col }
		end
		return parsePostfix()
	end

	local function parseTerm(): Expr
		local left = parseUnary()
		while true do
			local token = peek()
			if
				token.type == "op"
				and (token.value == "*" or token.value == "/" or token.value == "//" or token.value == "%")
			then
				requireFeature(token, "math")
				advance()
				local right = parseUnary()
				countNode(token)
				local op: string = token.value
				left = {
					kind = "Binary",
					op = op,
					left = left,
					right = right,
					line = token.line,
					col = token.col,
				}
			else
				return left
			end
		end
	end

	local function parseArith(): Expr
		local left = parseTerm()
		while true do
			local token = peek()
			if token.type == "op" and (token.value == "+" or token.value == "-") then
				requireFeature(token, "math")
				advance()
				local right = parseTerm()
				countNode(token)
				local op: string = token.value
				left = {
					kind = "Binary",
					op = op,
					left = left,
					right = right,
					line = token.line,
					col = token.col,
				}
			else
				return left
			end
		end
	end

	local function isComparisonStart(token: Token): boolean
		return (token.type == "op" and COMPARE_OPS[token.value] == true)
			or isKeyword(token, "in")
			or (isKeyword(token, "not") and isKeyword(peekAt(1), "in"))
	end

	local function parseComparison(): Expr
		local left = parseArith()
		local opToken = peek()
		if not isComparisonStart(opToken) then
			return left
		end
		local op: string
		if isKeyword(opToken, "in") then
			requireFeature(opToken, "lists")
			advance()
			op = "in"
		elseif isKeyword(opToken, "not") then
			requireFeature(opToken, "lists")
			advance()
			advance()
			op = "not in"
		else
			advance()
			op = opToken.value
		end
		local right = parseArith()
		if isComparisonStart(peek()) then
			failAt(peek(), "Compare two values at a time and join them with 'and', like: a < b and b < c")
		end
		countNode(opToken)
		return {
			kind = "Compare",
			op = op,
			left = left,
			right = right,
			line = opToken.line,
			col = opToken.col,
		}
	end

	local function parseNot(): Expr
		local token = peek()
		if isKeyword(token, "not") then
			advance()
			enterExpr(token)
			local operand = parseNot()
			leaveExpr()
			countNode(token)
			return { kind = "Not", operand = operand, line = token.line, col = token.col }
		end
		return parseComparison()
	end

	local function parseAnd(): Expr
		local left = parseNot()
		while isKeyword(peek(), "and") do
			local opToken = advance()
			local right = parseNot()
			countNode(opToken)
			left = {
				kind = "Logical",
				op = "and",
				left = left,
				right = right,
				line = opToken.line,
				col = opToken.col,
			}
		end
		return left
	end

	local function parseOr(): Expr
		local left = parseAnd()
		while isKeyword(peek(), "or") do
			local opToken = advance()
			local right = parseAnd()
			countNode(opToken)
			left = {
				kind = "Logical",
				op = "or",
				left = left,
				right = right,
				line = opToken.line,
				col = opToken.col,
			}
		end
		return left
	end

	parseExpression = parseOr

	local function parseBlock(header: Token): Block
		if peek().type ~= "newline" then
			failAt(peek(), "Put the commands for this block on the next lines, indented by 4 spaces.")
		end
		advance()
		if peek().type ~= "indent" then
			failAt(header, string.format("Line %d needs indented lines after it.", header.line))
		end
		advance()

		blockDepth += 1
		if blockDepth > limits.maxBlockDepth then
			failAt(header, string.format("Too many blocks inside each other (max %d).", limits.maxBlockDepth))
		end

		local body: Block = {}
		while peek().type ~= "dedent" and peek().type ~= "eof" do
			table.insert(body, parseStatement())
		end
		if peek().type == "dedent" then
			advance()
		end

		blockDepth -= 1
		return body
	end

	local function parseRepeat(): Stmt
		local token = advance() -- 'repeat'
		requireFeature(token, "repeat")
		if peek().type == "newline" or isOp(peek(), ":") or isKeyword(peek(), "times") then
			failAt(peek(), "Say how many times to repeat, like: repeat 5 times:")
		end
		local count = parseExpression()
		if isKeyword(peek(), "times") then
			advance()
		end
		expectColon("repeat")
		local body = parseBlock(token)
		countNode(token)
		return { kind = "Repeat", count = count, body = body, line = token.line, col = token.col }
	end

	local function parseWhile(): Stmt
		local token = advance() -- 'while'
		requireFeature(token, "while")
		if peek().type == "newline" or isOp(peek(), ":") then
			failAt(peek(), "Add a condition after 'while', like: while True:")
		end
		local cond = parseExpression()
		expectColon("while")
		local body = parseBlock(token)
		countNode(token)
		return { kind = "While", cond = cond, body = body, line = token.line, col = token.col }
	end

	local function parseIf(): Stmt
		local token = advance() -- 'if'
		requireFeature(token, "if")
		if peek().type == "newline" or isOp(peek(), ":") then
			failAt(peek(), "Add a condition after 'if', like: if can_harvest():")
		end
		local clauses: { Clause } = {}
		local cond = parseExpression()
		expectColon("if")
		table.insert(clauses, { cond = cond, body = parseBlock(token), line = token.line })

		local elseBody: Block? = nil
		while true do
			local nextToken = peek()
			if isKeyword(nextToken, "elif") then
				advance()
				local elifCond = parseExpression()
				expectColon("elif")
				table.insert(
					clauses,
					{ cond = elifCond, body = parseBlock(nextToken), line = nextToken.line }
				)
			elseif isKeyword(nextToken, "else") then
				advance()
				if isKeyword(peek(), "if") then
					failAt(peek(), "Use 'elif' instead of 'else if'.")
				end
				expectColon("else")
				elseBody = parseBlock(nextToken)
				break
			else
				break
			end
		end

		countNode(token)
		return { kind = "If", clauses = clauses, elseBody = elseBody, line = token.line, col = token.col }
	end

	local function parseFor(): Stmt
		local token = advance() -- 'for'
		requireFeature(token, "for")
		local nameToken = peek()
		if nameToken.type ~= "name" then
			failAt(nameToken, "Write a variable name after 'for', like: for x in range(5):")
		end
		checkNotBuiltin(nameToken, "loop variable")
		advance()
		if not isKeyword(peek(), "in") then
			failAt(peek(), "Write 'in' after the name, like: for x in range(5):")
		end
		advance()
		if peek().type == "newline" or isOp(peek(), ":") then
			failAt(peek(), "Say what to loop over, like: for x in range(5):")
		end
		local iterable = parseExpression()
		expectColon("for")
		defineName(nameToken.value)
		local body = parseBlock(token)
		countNode(token)
		return {
			kind = "For",
			var = nameToken.value,
			iterable = iterable,
			body = body,
			line = token.line,
			col = token.col,
		}
	end

	local function parseDef(): Stmt
		local token = advance() -- 'def'
		requireFeature(token, "def")
		if blockDepth > 0 or currentDef ~= nil then
			failAt(token, "Define functions at the top level of your program (not indented).")
		end
		local nameToken = peek()
		if nameToken.type ~= "name" then
			failAt(nameToken, "Write the function's name after 'def', like: def plant_row():")
		end
		checkNotBuiltin(nameToken, "function")
		if defs[nameToken.value] ~= nil then
			failAt(
				nameToken,
				string.format(
					"There's already a function called '%s' (line %d).",
					nameToken.value,
					defs[nameToken.value].line
				)
			)
		end
		advance()
		if not isOp(peek(), "(") then
			failAt(peek(), string.format("Add () after the name, like: def %s():", nameToken.value))
		end
		advance()
		local params: { string } = {}
		local locals: { [string]: boolean } = {}
		while not isOp(peek(), ")") do
			local paramToken = peek()
			if paramToken.type ~= "name" then
				failAt(paramToken, "Function inputs must be names, like: def go(steps):")
			end
			checkNotBuiltin(paramToken, "input")
			if locals[paramToken.value] then
				failAt(paramToken, string.format("'%s' is listed twice.", paramToken.value))
			end
			advance()
			table.insert(params, paramToken.value)
			locals[paramToken.value] = true
			if isOp(peek(), ",") then
				advance()
			elseif not isOp(peek(), ")") then
				failAt(peek(), "Separate the inputs with ',' and close them with ')'.")
			end
		end
		advance() -- ')'
		expectColon("def")

		local def: DefStmt = {
			kind = "Def",
			name = nameToken.value,
			params = params,
			locals = locals,
			body = {},
			line = token.line,
			col = token.col,
		}
		defs[def.name] = def
		globalNames[def.name] = true

		currentDef = { name = def.name, locals = locals }
		def.body = parseBlock(token)
		currentDef = nil
		countNode(token)
		return def
	end

	local function parseReturn(): Stmt
		local token = advance() -- 'return'
		if currentDef == nil then
			failAt(token, "'return' only works inside a function (def).")
		end
		requireFeature(token, "def")
		local value: Expr? = nil
		local nextToken = peek()
		if nextToken.type ~= "newline" and nextToken.type ~= "eof" and nextToken.type ~= "dedent" then
			value = parseExpression()
		end
		expectEndOfLine()
		countNode(token)
		return { kind = "Return", value = value, line = token.line, col = token.col }
	end

	local function parseImport(): Stmt
		local token = advance() -- 'import'
		requireFeature(token, "import")
		if blockDepth > 0 or currentDef ~= nil then
			failAt(token, "Put 'import' lines at the top level of your program (not indented).")
		end
		local nameToken = peek()
		if nameToken.type ~= "name" then
			failAt(nameToken, "Write the name of one of your script slots after 'import', like: import utils")
		end
		checkNotBuiltin(nameToken, "module")
		advance()
		if isOp(peek(), ".") or isOp(peek(), ",") then
			failAt(peek(), "Import one script per line, like: import utils")
		end
		expectEndOfLine()
		imports[nameToken.value] = true
		globalNames[nameToken.value] = true
		countNode(token)
		return { kind = "Import", name = nameToken.value, line = token.line, col = token.col }
	end

	local function parseSimple(): Stmt
		local token = peek()
		if token.type == "name" then
			local hint = UNSUPPORTED[token.value]
			if hint ~= nil then
				failAt(token, hint)
			end
		end
		local expr = parseExpression()
		local opToken = peek()
		if opToken.type == "op" and ASSIGN_OPS[opToken.value] then
			requireFeature(opToken, "variables")
			if opToken.value ~= "=" then
				requireFeature(opToken, "math")
			end
			if expr.kind == "Name" then
				if Builtins.ByName[expr.name] ~= nil then
					failAt(
						expr,
						string.format("'%s' is a built-in command - pick another variable name.", expr.name)
					)
				end
				if defs[expr.name] ~= nil or imports[expr.name] then
					failAt(
						expr,
						string.format("'%s' is a function or module - pick another variable name.", expr.name)
					)
				end
				defineName(expr.name)
			elseif expr.kind ~= "Index" then
				failAt(opToken, "You can only set a name (a = 2) or a list item (items[0] = 2).")
			end
			advance()
			if peek().type == "newline" or peek().type == "eof" then
				failAt(peek(), string.format("Write a value after '%s', like: a = 2", opToken.value))
			end
			local value = parseExpression()
			expectEndOfLine()
			countNode(opToken)
			return {
				kind = "Assign",
				target = expr,
				op = opToken.value,
				value = value,
				line = token.line,
				col = token.col,
			}
		end

		if expr.kind ~= "Call" and expr.kind ~= "MethodCall" then
			if expr.kind == "Name" then
				local spec = Builtins.ByName[expr.name]
				if spec ~= nil then
					failAt(
						expr,
						string.format("Add () after '%s' to run it, like %s.", expr.name, spec.example)
					)
				elseif defs[expr.name] ~= nil then
					failAt(
						expr,
						string.format("Add () after '%s' to run it, like %s().", expr.name, expr.name)
					)
				end
			end
			if expr.kind == "Compare" and expr.op == "==" and expr.left.kind == "Name" then
				failAt(expr, "Use a single '=' to set a variable: a = 2  ('==' compares two values).")
			end
			failAt(
				token,
				"This line doesn't do anything. Start it with a command like move_up(), or set a variable: a = 2"
			)
		end
		expectEndOfLine()
		countNode(token)
		return { kind = "CallStmt", call = expr :: any, line = token.line, col = token.col }
	end

	parseStatement = function(): Stmt
		local token = peek()
		if token.type == "keyword" then
			local word = token.value
			if word == "repeat" then
				return parseRepeat()
			elseif word == "while" then
				return parseWhile()
			elseif word == "if" then
				return parseIf()
			elseif word == "for" then
				return parseFor()
			elseif word == "def" then
				return parseDef()
			elseif word == "return" then
				return parseReturn()
			elseif word == "import" then
				return parseImport()
			elseif word == "pass" then
				advance()
				countNode(token)
				expectEndOfLine()
				return { kind = "Pass", line = token.line, col = token.col }
			elseif word == "elif" or word == "else" then
				failAt(
					token,
					string.format(
						"'%s' must come right after an 'if' block, at the same indentation as the 'if'.",
						word
					)
				)
			elseif word == "not" or word == "True" or word == "False" or word == "None" then
				return parseSimple()
			end
			failAt(
				token,
				string.format("A line can't start with '%s'. Start it with a command like move_up().", word)
			)
		elseif
			token.type == "name" or (token.type == "op" and (token.value == "(" or token.value == "["))
		then
			return parseSimple()
		end
		return failAt(
			token,
			string.format("Expected a command like move_up() here, but found %s.", describe(token))
		)
	end

	local body: Block = {}
	while peek().type ~= "eof" do
		if peek().type == "dedent" then
			advance() -- defensive: the lexer always pairs DEDENTs with INDENTs
		else
			table.insert(body, parseStatement())
		end
	end

	---------------------------------------------------------------------------------------
	-- Name resolution (needs the whole program: functions may be defined below their use)
	---------------------------------------------------------------------------------------
	local candidates: { string } = table.clone(Builtins.Names)
	for name in globalNames do
		table.insert(candidates, name)
	end
	for _, def in defs do
		for name in def.locals do
			table.insert(candidates, name)
		end
	end

	local function isImport(name: string, def: DefStmt?): boolean
		return imports[name] == true and not (def ~= nil and def.locals[name] == true)
	end

	local resolveExpr: (expr: Expr, def: DefStmt?) -> ()
	local resolveBlock: (block: Block, def: DefStmt?) -> ()

	local function resolveName(node: Pos, name: string, def: DefStmt?)
		if def ~= nil and def.locals[name] then
			requireFeature(node, "variables")
			return
		end
		if globalNames[name] then
			if defs[name] ~= nil then
				requireFeature(node, "def")
			elseif imports[name] then
				requireFeature(node, "import")
			else
				requireFeature(node, "variables")
			end
			return
		end
		local spec = Builtins.ByName[name]
		if spec ~= nil then
			failAt(node, string.format("Add () after '%s' to run it, like %s.", name, spec.example))
		end
		local suggestion = Suggest.closest(name, candidates)
		if suggestion ~= nil then
			local shown = if Builtins.ByName[suggestion] ~= nil or defs[suggestion] ~= nil
				then suggestion .. "()"
				else suggestion
			failAt(node, string.format("Unknown name '%s'. Did you mean '%s'?", name, shown))
		end
		failAt(
			node,
			string.format(
				"'%s' isn't something the drone knows. If you meant text, put it in quotes: \"%s\".",
				name,
				name
			)
		)
	end

	resolveExpr = function(expr: Expr, def: DefStmt?)
		if expr.kind == "Name" then
			resolveName(expr, expr.name, def)
		elseif expr.kind == "Call" then
			if not expr.builtin then
				local name = expr.name
				local target = defs[name]
				local isLocal = def ~= nil and def.locals[name] == true
				if target ~= nil and not isLocal then
					requireFeature(expr, "def")
					if #expr.args ~= #target.params then
						failAt(
							expr,
							string.format(
								"%s() needs %s (see 'def %s' on line %d).",
								name,
								plural(#target.params, "value"),
								name,
								target.line
							)
						)
					end
				elseif isLocal or globalNames[name] then
					requireFeature(expr, "def")
				else
					local suggestion = Suggest.closest(name, candidates)
					if suggestion ~= nil then
						failAt(
							expr,
							string.format("Unknown command '%s'. Did you mean '%s'?", name, suggestion)
						)
					end
					failAt(expr, string.format("Unknown command '%s'.", name))
				end
			end
			for _, arg in expr.args do
				resolveExpr(arg, def)
			end
		elseif expr.kind == "MethodCall" then
			local object = expr.object
			if object.kind == "Name" and isImport(object.name, def) then
				requireFeature(object, "import")
			else
				local method = Builtins.MethodByName[expr.method]
				if method == nil then
					local suggestion = Suggest.closest(expr.method, Builtins.MethodNames)
					local hint = if suggestion ~= nil
						then string.format(" Did you mean '.%s()'?", suggestion)
						else ""
					failAt(
						expr,
						string.format(
							"Unknown method '.%s()'.%s Lists have append() and pop(); dictionaries have keys(), values() and get().",
							expr.method,
							hint
						)
					)
				end
				assert(method ~= nil, "unreachable: failAt() never returns")
				requireFeature(expr, method.feature)
				local count = #expr.args
				if count < method.minArgs or count > method.maxArgs then
					failAt(
						expr,
						string.format(
							".%s() needs %s, like %s.",
							method.name,
							arityText(method.minArgs, method.maxArgs),
							method.example
						)
					)
				end
				resolveExpr(object, def)
			end
			for _, arg in expr.args do
				resolveExpr(arg, def)
			end
		elseif expr.kind == "Attribute" then
			local object = expr.object
			if object.kind ~= "Name" or not isImport(object.name, def) then
				failAt(
					expr,
					"Use '.' to call methods like items.append(5), or to reach into a module you imported (utils.x)."
				)
			end
			resolveExpr(object, def)
		elseif expr.kind == "Index" then
			resolveExpr(expr.object, def)
			resolveExpr(expr.index, def)
		elseif expr.kind == "List" then
			for _, item in expr.items do
				resolveExpr(item, def)
			end
		elseif expr.kind == "Dict" then
			for i, key in expr.keys do
				resolveExpr(key, def)
				resolveExpr(expr.values[i], def)
			end
		elseif expr.kind == "Unary" or expr.kind == "Not" then
			resolveExpr(expr.operand, def)
		elseif expr.kind == "Binary" or expr.kind == "Logical" or expr.kind == "Compare" then
			resolveExpr(expr.left, def)
			resolveExpr(expr.right, def)
		end
	end

	resolveBlock = function(block: Block, def: DefStmt?)
		for _, stmt in block do
			if stmt.kind == "CallStmt" then
				resolveExpr(stmt.call, def)
			elseif stmt.kind == "Repeat" then
				resolveExpr(stmt.count, def)
				resolveBlock(stmt.body, def)
			elseif stmt.kind == "While" then
				resolveExpr(stmt.cond, def)
				resolveBlock(stmt.body, def)
			elseif stmt.kind == "If" then
				for _, clause in stmt.clauses do
					resolveExpr(clause.cond, def)
					resolveBlock(clause.body, def)
				end
				if stmt.elseBody ~= nil then
					resolveBlock(stmt.elseBody, def)
				end
			elseif stmt.kind == "For" then
				resolveExpr(stmt.iterable, def)
				resolveBlock(stmt.body, def)
			elseif stmt.kind == "Assign" then
				local target = stmt.target
				if target.kind == "Index" then
					resolveExpr(target, def)
				elseif stmt.op ~= "=" and target.kind == "Name" then
					resolveName(target, target.name, def)
				end
				resolveExpr(stmt.value, def)
			elseif stmt.kind == "Return" then
				if stmt.value ~= nil then
					resolveExpr(stmt.value, def)
				end
			elseif stmt.kind == "Def" then
				resolveBlock(stmt.body, stmt)
			end
		end
	end

	resolveBlock(body, nil)

	return { kind = "Program", body = body, defs = defs, imports = imports }
end

--[[
	Parser.parse(tokens, limits, isUnlocked?) -> (Program, nil) | (nil, CompileError). Never throws.
]]
function Parser.parse(tokens: { Token }, limits: Limits, isUnlocked: FeatureCheck?): (Program?, CompileError?)
	if #tokens == 0 or tokens[#tokens].type ~= "eof" then
		return nil,
			{
				line = 1,
				col = 1,
				message = "Something went wrong while reading your program.",
				internal = "bad token stream",
			}
	end
	local ok, result = pcall(parseUnsafe, tokens, limits, isUnlocked)
	if ok then
		return result, nil
	end
	if type(result) == "table" and getmetatable(result :: any) == ParseFailure then
		local failure = result :: any
		return nil, { line = failure.line, col = failure.col, message = failure.message }
	end
	return nil,
		{
			line = 1,
			col = 1,
			message = "Something went wrong while reading your program.",
			internal = tostring(result),
		}
end

--[[
	Parser.compile(source, limits, isUnlocked?) -> (Program, nil) | (nil, CompileError)
	Lex + parse in one call. This is what the server (and the client pre-check) use.
	Omitting `isUnlocked` allows every feature (used by tests and tooling only).
]]
function Parser.compile(source: any, limits: Limits, isUnlocked: FeatureCheck?): (Program?, CompileError?)
	local tokens, lexError = Lexer.tokenize(source, limits)
	if tokens == nil then
		return nil, lexError
	end
	return Parser.parse(tokens, limits, isUnlocked)
end

return Parser
