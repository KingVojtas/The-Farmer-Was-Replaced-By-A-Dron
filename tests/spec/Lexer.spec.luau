return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Lexer = Loader.get("ReplicatedStorage.Shared.DroneScript.Lexer")
	local Parser = Loader.get("ReplicatedStorage.Shared.DroneScript.Parser")
	local limits = Parser.limits(40)

	local function types(tokens)
		local out = {}
		for _, token in tokens do
			table.insert(out, token.type)
		end
		return table.concat(out, " ")
	end

	local function lexError(source, customLimits)
		local tokens, err = Lexer.tokenize(source, customLimits or limits)
		expect(tokens).toBeNil()
		expect(err).toBeTruthy()
		return err
	end

	describe("Lexer", function()
		it("tokenizes a simple call", function()
			local tokens = Lexer.tokenize("move_up()", limits)
			expect(types(tokens)).toBe("name op op newline eof")
			expect(tokens[1].value).toBe("move_up")
			expect(tokens[1].line).toBe(1)
		end)

		it("emits INDENT and DEDENT around blocks", function()
			local tokens = Lexer.tokenize("repeat 2 times:\n    move_up()\nmove_down()", limits)
			expect(types(tokens)).toBe(
				"keyword number keyword op newline indent name op op newline dedent name op op newline eof"
			)
		end)

		it("closes all open blocks at the end of the program", function()
			local tokens = Lexer.tokenize("if True:\n    if True:\n        pass", limits)
			local dedents = 0
			for _, token in tokens do
				if token.type == "dedent" then
					dedents += 1
				end
			end
			expect(dedents).toBe(2)
			expect(tokens[#tokens].type).toBe("eof")
		end)

		it("normalizes tabs and CRLF line endings", function()
			local tokens, err = Lexer.tokenize("repeat 2:\r\n\tmove_up()\r\n", limits)
			expect(err).toBeNil()
			expect(types(tokens)).toBe("keyword number op newline indent name op op newline dedent eof")
		end)

		it("ignores blank lines and comments but keeps # inside text", function()
			local tokens = Lexer.tokenize('# hello\n\n   \nprint("#1") # note', limits)
			expect(types(tokens)).toBe("name op string op newline eof")
			expect(tokens[3].value).toBe("#1")
		end)

		it("parses numbers, strings and escapes", function()
			local tokens = Lexer.tokenize("print(2.5)\nprint('it\\'s')", limits)
			expect(tokens[3].num).toBe(2.5)
			expect(tokens[8].value).toBe("it's")
		end)

		it("accepts true/false as aliases of True/False", function()
			local tokens = Lexer.tokenize("while true:\n    pass", limits)
			expect(tokens[2].type).toBe("keyword")
			expect(tokens[2].value).toBe("True")
		end)

		it("allows UTF-8 inside strings and comments", function()
			local _, err = Lexer.tokenize('print("pšenice") # žluťoučký', limits)
			expect(err).toBeNil()
		end)

		it("rejects an unexpected indent", function()
			local err = lexError("move_up()\n    move_down()")
			expect(err.line).toBe(2)
			expect(err.message).toContain("doesn't end with ':'")
		end)

		it("requires an indented block after ':'", function()
			local err = lexError("repeat 3 times:\nmove_up()")
			expect(err.line).toBe(2)
			expect(err.message).toContain("must be indented")
		end)

		it("rejects a ':' line at the end of the program", function()
			local err = lexError("if True:")
			expect(err.line).toBe(1)
			expect(err.message).toContain("no indented lines")
		end)

		it("rejects indentation that matches no outer level", function()
			local err = lexError("if True:\n        move_up()\n    move_down()")
			expect(err.line).toBe(3)
			expect(err.message).toContain("doesn't line up")
		end)

		it("reports unclosed strings", function()
			local err = lexError('plant("wheat)')
			expect(err.message).toContain("closing")
		end)

		it("tokenizes math, assignment and the new keywords", function()
			local tokens = Lexer.tokenize("a += x // 2 % 3 - -1", limits)
			expect(types(tokens)).toBe("name op name op number op number op op number newline eof")
			expect(tokens[2].value).toBe("+=")
			expect(tokens[4].value).toBe("//")
			local kw = Lexer.tokenize("for i in range(3):\n    pass\ndef f():\n    return None", limits)
			expect(kw[1].type).toBe("keyword")
			expect(kw[1].value).toBe("for")
			expect(kw[3].value).toBe("in")
		end)

		it("tokenizes lists, dictionaries and attribute access", function()
			local tokens = Lexer.tokenize("d = {'a': [1, 2]}\nitems.append(d['a'][0])", limits)
			local ops = {}
			for _, token in tokens do
				if token.type == "op" then
					table.insert(ops, token.value)
				end
			end
			expect(table.concat(ops, " ")).toBe("= { : [ , ] } . ( [ ] [ ] )")
		end)

		it("explains powers and C-style operators", function()
			expect(lexError("x = 2 ** 3").message).toContain("multiply")
			expect(lexError("if a && b:\n    pass").message).toContain("'and'")
			expect(lexError("if !a:\n    pass").message).toContain("'not'")
		end)

		it("requires brackets to match", function()
			expect(lexError("x = [1, 2)").message).toContain("doesn't match")
			expect(lexError("x = {1: 2").message).toContain("Missing '}'")
		end)

		it("exposes the reserved words", function()
			expect(Lexer.Keywords["def"]).toBe("def")
			expect(Lexer.Keywords["None"]).toBe("None")
		end)

		it("reports missing ')' on the same line", function()
			local err = lexError('plant("wheat"')
			expect(err.message).toContain("Missing ')'")
		end)

		it("reports a ')' without '('", function()
			local err = lexError("move_up())")
			expect(err.message).toContain("matching '('")
		end)

		it("rejects control characters", function()
			local err = lexError("move_up()\7")
			expect(err.message).toContain("control character")
		end)

		it("rejects invalid UTF-8 before reading anything", function()
			local err = lexError("move_up()\255")
			expect(err.message).toContain("can't read")
		end)

		it("rejects non-string input", function()
			local err = lexError({})
			expect(err.message).toContain("must be text")
		end)

		it("rejects programs above the byte limit before tokenizing", function()
			local err = lexError(string.rep("a", limits.maxSourceBytes + 1))
			expect(err.message).toContain("too big")
		end)

		it("enforces the line limit but ignores trailing blank lines", function()
			local lines = table.create(40, "pass")
			local ok = Lexer.tokenize(table.concat(lines, "\n") .. "\n\n\n", limits)
			expect(ok).toBeTruthy()
			table.insert(lines, "pass")
			local err = lexError(table.concat(lines, "\n"))
			expect(err.message).toContain("only holds 40 lines")
		end)

		it("enforces the line length limit", function()
			local err = lexError("print('" .. string.rep("a", 130) .. "')")
			expect(err.message).toContain("too long")
		end)

		it("enforces the string length limit", function()
			local err = lexError("print('" .. string.rep("a", 101) .. "')")
			expect(err.message).toContain("too long (max 100")
		end)

		it("enforces the token limit", function()
			local small = table.clone(limits)
			small.maxTokens = 8
			local err = lexError("move_up()\nmove_up()\nmove_up()", small)
			expect(err.message).toContain("too long")
		end)

		it("asks for a space between a number and a word", function()
			local err = lexError("repeat 5times:\n    pass")
			expect(err.message).toContain("Put a space")
		end)

		it("rejects numbers above the maximum", function()
			local err = lexError("repeat 99999999999 times:\n    pass")
			expect(err.message).toContain("bigger than")
		end)
	end)
end
