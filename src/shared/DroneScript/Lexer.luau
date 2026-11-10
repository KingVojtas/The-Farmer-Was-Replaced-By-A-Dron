--!strict
--[[
	Lexer
	=====
	Turns drone source code (Python-style) into a flat list of tokens.

	SECURITY: this module never executes anything. It reads a bounded string and produces
	bounded data. Every limit is checked BEFORE the expensive work it protects:
	  1. type + byte size + UTF-8 validity of the whole program,
	  2. line count and line length,
	  3. control characters, identifier/string/number sizes,
	  4. total token count.

	Indentation works like Python:
	  * tabs become 4 spaces, CRLF/CR become LF,
	  * a line that ends with ':' must be followed by a MORE indented line  -> INDENT token,
	  * going back to an outer indentation level                           -> DEDENT token(s),
	  * blank lines and comment-only lines (# ...) are ignored completely.

	Errors are friendly, aimed at first-time programmers, and always carry a line number.

	The lexer tokenizes EVERY operator the language has (math, '=', '[ ]', '{ }', '.'), even
	ones the player hasn't unlocked yet: whether a piece of syntax may be USED is decided by
	the Parser's Tech Tree gate, which can name the research needed. Brackets must be closed on
	the same line they are opened on, and must match: ( ), [ ], { }.
]]

local Text = require(script.Parent.Parent.Util.Text)

export type TokenType =
	"name"
	| "keyword"
	| "number"
	| "string"
	| "op"
	| "newline"
	| "indent"
	| "dedent"
	| "eof"

export type Token = {
	type: TokenType,
	value: string, -- keyword/op/name text, string contents, or the number's source text
	num: number?, -- parsed value for number tokens
	line: number,
	col: number,
}

export type CompileError = {
	line: number,
	col: number,
	message: string,
	internal: string?, -- set only for unexpected internal failures (for server logs)
}

export type Limits = {
	maxLines: number,
	maxLineLength: number,
	maxSourceBytes: number,
	maxTokens: number,
	maxStringLength: number,
	maxIdentifierLength: number,
	maxNumber: number,
}

-- Words with special meaning. `true`/`false` are accepted as friendly aliases of True/False.
local KEYWORDS: { [string]: string } = {
	["repeat"] = "repeat",
	times = "times",
	["while"] = "while",
	["if"] = "if",
	elif = "elif",
	["else"] = "else",
	["not"] = "not",
	["and"] = "and",
	["or"] = "or",
	pass = "pass",
	["for"] = "for",
	["in"] = "in",
	def = "def",
	["return"] = "return",
	import = "import",
	None = "None",
	True = "True",
	["true"] = "True",
	False = "False",
	["false"] = "False",
}

local TWO_CHAR_OPS: { [string]: boolean } = {
	["=="] = true,
	["!="] = true,
	["<="] = true,
	[">="] = true,
	["//"] = true,
	["+="] = true,
	["-="] = true,
	["*="] = true,
	["/="] = true,
}

local ONE_CHAR_OPS: { [string]: boolean } = {
	["<"] = true,
	[">"] = true,
	["("] = true,
	[")"] = true,
	["["] = true,
	["]"] = true,
	["{"] = true,
	["}"] = true,
	[","] = true,
	[":"] = true,
	["="] = true,
	["+"] = true,
	["-"] = true,
	["*"] = true,
	["/"] = true,
	["%"] = true,
	["."] = true,
}

local OPENERS: { [string]: string } = { ["("] = ")", ["["] = "]", ["{"] = "}" }
local CLOSERS: { [string]: string } = { [")"] = "(", ["]"] = "[", ["}"] = "{" }

-- Character sequences people often try, with a helpful explanation.
local FRIENDLY_SEQUENCES: { [string]: string } = {
	["**"] = "Powers (**) aren't available - multiply instead, like x * x.",
	["//="] = "Write it out instead: x = x // 2",
	["%="] = "Write it out instead: x = x % 2",
	["&&"] = "Use 'and' instead of '&&'.",
	["||"] = "Use 'or' instead of '||'.",
}
local FRIENDLY_CHARS: { [string]: string } = {
	["!"] = "Use 'not' instead of '!'.",
	["^"] = "Powers aren't available - multiply instead, like x * x.",
	["&"] = "Use 'and' instead of '&'.",
	["|"] = "Use 'or' instead of '|'.",
	[";"] = "Put each command on its own line instead of using ';'.",
}

local ESCAPES: { [string]: string } = {
	['"'] = '"',
	["'"] = "'",
	["\\"] = "\\",
	n = "\n",
	t = "\t",
}

local MAX_NUMBER_DIGITS = 15

-- Errors are thrown as tables tagged with this metatable and turned into return values by
-- the pcall in Lexer.tokenize. Anything else that gets thrown is an internal bug.
local LexFailure = {}

local function fail(line: number, col: number, message: string): never
	error(setmetatable({ line = line, col = col, message = message }, LexFailure), 0)
end

local Lexer = {}

-- Every reserved word (so other modules can refuse them as names).
Lexer.Keywords = table.freeze(table.clone(KEYWORDS))

local function tokenizeUnsafe(source: string, limits: Limits): { Token }
	-- Normalize line endings and tabs so every later step sees one canonical form.
	local text = string.gsub(source, "\r\n", "\n")
	text = string.gsub(text, "\r", "\n")
	text = string.gsub(text, "\t", "    ")

	local lineCount = Text.countLines(text)
	if lineCount > limits.maxLines then
		fail(
			limits.maxLines + 1,
			1,
			string.format(
				"Your program is %d lines long, but your drone's memory only holds %d lines.",
				lineCount,
				limits.maxLines
			)
		)
	end

	local lines = string.split(text, "\n")
	local tokens: { Token } = {}
	local indentStack: { number } = { 0 }
	local pendingBlockLine: number? = nil -- line number of a ':' line still waiting for its block

	local function push(tokenType: TokenType, value: string, line: number, col: number, num: number?)
		if #tokens >= limits.maxTokens then
			fail(line, col, "Your program is too long for the drone to read. Try making it shorter.")
		end
		table.insert(tokens, { type = tokenType, value = value, num = num, line = line, col = col })
	end

	-- Reads a "..." or '...' literal that starts at `startPos`; returns the position after it.
	local function readString(line: string, lineNo: number, startPos: number): number
		local quote = string.sub(line, startPos, startPos)
		local buffer: { string } = {}
		local i = startPos + 1
		while true do
			if i > #line then
				fail(
					lineNo,
					startPos,
					string.format("This text is missing its closing %s. Add %s at the end.", quote, quote)
				)
			end
			local ch = string.sub(line, i, i)
			if ch == quote then
				break
			elseif ch == "\\" then
				local nextCh = string.sub(line, i + 1, i + 1)
				if nextCh == "" then
					fail(
						lineNo,
						startPos,
						string.format("This text is missing its closing %s. Add %s at the end.", quote, quote)
					)
				end
				local escaped = ESCAPES[nextCh]
				if escaped == nil then
					fail(
						lineNo,
						i,
						string.format("Unknown escape '\\%s'. To write a backslash use '\\\\'.", nextCh)
					)
				end
				table.insert(buffer, escaped)
				i += 2
			else
				table.insert(buffer, ch)
				i += 1
			end
		end
		local value = table.concat(buffer)
		local length = utf8.len(value) or #value
		if length > limits.maxStringLength then
			fail(
				lineNo,
				startPos,
				string.format("This text is too long (max %d characters).", limits.maxStringLength)
			)
		end
		push("string", value, lineNo, startPos)
		return i + 1
	end

	for lineNo, line in lines do
		-- 1. Physical checks on the raw line.
		local controlAt = string.find(line, "%c")
		if controlAt ~= nil then
			fail(
				lineNo,
				controlAt,
				"This line contains an invisible control character. Delete the line and type it again."
			)
		end
		local lineLength = utf8.len(line) or #line
		if lineLength > limits.maxLineLength then
			fail(
				lineNo,
				limits.maxLineLength + 1,
				string.format(
					"This line is too long (%d characters, max %d).",
					lineLength,
					limits.maxLineLength
				)
			)
		end

		-- 2. Skip blank and comment-only lines entirely (they never affect indentation).
		local indent = #(string.match(line, "^ *") or "")
		local rest = string.sub(line, indent + 1)
		if rest == "" or string.sub(rest, 1, 1) == "#" then
			continue
		end

		-- 3. Indentation -> INDENT / DEDENT tokens.
		local top = indentStack[#indentStack]
		if pendingBlockLine ~= nil then
			if indent <= top then
				fail(
					lineNo,
					1,
					string.format(
						"The lines after the ':' on line %d must be indented. Add 4 spaces at the start of this line.",
						pendingBlockLine
					)
				)
			end
			table.insert(indentStack, indent)
			push("indent", "", lineNo, 1)
			pendingBlockLine = nil
		elseif indent > top then
			fail(
				lineNo,
				1,
				"This line is indented, but the line above doesn't end with ':'. Remove the extra spaces."
			)
		elseif indent < top then
			while indent < indentStack[#indentStack] do
				table.remove(indentStack)
				push("dedent", "", lineNo, 1)
			end
			if indent ~= indentStack[#indentStack] then
				fail(
					lineNo,
					1,
					"This line's indentation doesn't line up with any line above it. Use steps of 4 spaces."
				)
			end
		end

		-- 4. Tokens on this line.
		local pos = indent + 1
		local brackets: { { char: string, col: number } } = {}
		while pos <= #line do
			local c = string.sub(line, pos, pos)
			if c == " " then
				pos += 1
			elseif c == "#" then
				break -- comment until the end of the line
			elseif string.match(c, "[%a_]") then
				local word = string.match(line, "^[%a_][%w_]*", pos) or c
				if #word > limits.maxIdentifierLength then
					fail(
						lineNo,
						pos,
						string.format(
							"This name is too long (max %d characters).",
							limits.maxIdentifierLength
						)
					)
				end
				local keyword = KEYWORDS[word]
				if keyword ~= nil then
					push("keyword", keyword, lineNo, pos)
				else
					push("name", word, lineNo, pos)
				end
				pos += #word
			elseif string.match(c, "%d") then
				local numText = string.match(line, "^%d+%.%d+", pos) or string.match(line, "^%d+", pos) or c
				local after = string.sub(line, pos + #numText, pos + #numText)
				if after ~= "" and string.match(after, "[%a_]") then
					fail(lineNo, pos, string.format("Put a space after the number %s.", numText))
				end
				if after == "." then
					fail(lineNo, pos, "This number has an extra '.' in it.")
				end
				if #numText > MAX_NUMBER_DIGITS then
					fail(lineNo, pos, "This number is too long.")
				end
				local value = tonumber(numText) :: number
				if value > limits.maxNumber then
					fail(lineNo, pos, string.format("Numbers can't be bigger than %d.", limits.maxNumber))
				end
				push("number", numText, lineNo, pos, value)
				pos += #numText
			elseif c == '"' or c == "'" then
				pos = readString(line, lineNo, pos)
			else
				local three = string.sub(line, pos, pos + 2)
				local two = string.sub(line, pos, pos + 1)
				local sequenceHint = FRIENDLY_SEQUENCES[three] or FRIENDLY_SEQUENCES[two]
				if sequenceHint ~= nil then
					fail(lineNo, pos, sequenceHint)
				end
				if TWO_CHAR_OPS[two] then
					push("op", two, lineNo, pos)
					pos += 2
				elseif ONE_CHAR_OPS[c] then
					if OPENERS[c] ~= nil then
						table.insert(brackets, { char = c, col = pos })
					elseif CLOSERS[c] ~= nil then
						local open = brackets[#brackets]
						if open == nil then
							fail(
								lineNo,
								pos,
								string.format("This '%s' doesn't have a matching '%s'.", c, CLOSERS[c])
							)
						end
						assert(open ~= nil, "unreachable: fail() never returns")
						if open.char ~= CLOSERS[c] then
							fail(
								lineNo,
								pos,
								string.format(
									"This '%s' doesn't match the '%s' opened at column %d - close that with '%s' first.",
									c,
									open.char,
									open.col,
									OPENERS[open.char]
								)
							)
						end
						table.remove(brackets)
					end
					push("op", c, lineNo, pos)
					pos += 1
				else
					local friendly = FRIENDLY_CHARS[c]
					if friendly ~= nil then
						fail(lineNo, pos, friendly)
					end
					local ok, codepoint = pcall(utf8.codepoint, line, pos)
					local shown = if ok then utf8.char(codepoint) else "?"
					fail(
						lineNo,
						pos,
						string.format("The drone doesn't understand the character '%s' here.", shown)
					)
				end
			end
		end

		local unclosed = brackets[#brackets]
		if unclosed ~= nil then
			local closer = OPENERS[unclosed.char]
			fail(
				lineNo,
				unclosed.col,
				string.format(
					"Missing '%s' - every '%s' needs a matching '%s' on the same line.",
					closer,
					unclosed.char,
					closer
				)
			)
		end

		local last = tokens[#tokens]
		push("newline", "", lineNo, #line + 1)
		if last ~= nil and last.type == "op" and last.value == ":" then
			pendingBlockLine = lineNo
		end
	end

	if pendingBlockLine ~= nil then
		fail(
			pendingBlockLine,
			1,
			string.format("Line %d ends with ':' but has no indented lines after it.", pendingBlockLine)
		)
	end

	local lastLine = math.max(#lines, 1)
	while #indentStack > 1 do
		table.remove(indentStack)
		push("dedent", "", lastLine, 1)
	end
	push("eof", "", lastLine, 1)
	return tokens
end

--[[
	Lexer.tokenize(source, limits) -> (tokens, nil) | (nil, CompileError)
	Never throws: any unexpected failure is reported as an internal CompileError.
]]
function Lexer.tokenize(source: any, limits: Limits): ({ Token }?, CompileError?)
	-- Whole-program checks first, before touching the content.
	if type(source) ~= "string" then
		return nil, { line = 1, col = 1, message = "The program must be text." }
	end
	if #source > limits.maxSourceBytes then
		return nil,
			{
				line = 1,
				col = 1,
				message = string.format(
					"Your program is too big (%d characters, max %d).",
					#source,
					limits.maxSourceBytes
				),
			}
	end
	if utf8.len(source) == nil then
		return nil, { line = 1, col = 1, message = "Your program contains characters the drone can't read." }
	end

	local ok, result = pcall(tokenizeUnsafe, source, limits)
	if ok then
		return result, nil
	end
	if type(result) == "table" and getmetatable(result :: any) == LexFailure then
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

return Lexer
