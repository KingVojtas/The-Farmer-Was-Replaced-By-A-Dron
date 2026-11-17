--[[
	Text.withoutTypedTab (docs/BUGS.md BUG-17): one Tab is 4 spaces, whether or not the Roblox
	TextBox also types a "\t", and in either order of the two edits. Replays the editor's two
	edit paths: onTab (inserts "    " at the caret) and the TextBox's own "\t".
]]
return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Text = Loader.get("ReplicatedStorage.Shared.Util.Text")

	-- The editor: `text` + 1-based caret, onTextChanged's tab rule, onTab's insert.
	local function editor(initial, caret)
		local e = { text = initial, caret = caret }
		function e.native(char) -- the TextBox types `char` at the caret
			local before = e.text
			e.text = string.sub(before, 1, e.caret - 1) .. char .. string.sub(before, e.caret)
			e.caret += #char
			local cleaned, cursor = Text.withoutTypedTab(before, e.text, e.caret)
			if cleaned ~= nil then
				e.text, e.caret = cleaned, cursor
			end
		end
		function e.onTab()
			e.text = string.sub(e.text, 1, e.caret - 1) .. "    " .. string.sub(e.text, e.caret)
			e.caret += 4
		end
		return e
	end

	describe("Text.withoutTypedTab (BUG-17)", function()
		it("gives 4 spaces when the TextBox types no tab", function()
			local e = editor("ab", 2)
			e.onTab()
			expect(e.text).toBe("a    b")
			expect(e.caret).toBe(6)
		end)

		it("gives 4 spaces when the Tab handler runs first, then the TextBox types \\t", function()
			local e = editor("ab", 2)
			e.onTab()
			e.native("\t")
			expect(e.text).toBe("a    b")
			expect(e.caret).toBe(6)
		end)

		it("gives 4 spaces when the TextBox types \\t first, then the Tab handler runs", function()
			local e = editor("ab", 2)
			e.native("\t")
			e.onTab()
			expect(e.text).toBe("a    b")
			expect(e.caret).toBe(6)
		end)

		it("leaves ordinary typing and pasted tabs alone (they're converted elsewhere)", function()
			expect(Text.withoutTypedTab("ab", "axb", 3)).toBeNil()
			expect(Text.withoutTypedTab("ab", "a\t\tb", 4)).toBeNil() -- a paste
			expect(Text.withoutTypedTab("ab", "a\tb", -1)).toBeNil() -- no caret
		end)
	end)
end
