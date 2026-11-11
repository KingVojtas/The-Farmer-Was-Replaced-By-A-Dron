--!strict
--[[
	Text
	====
	Small, pure string helpers that are safe for UTF-8 (shared by server, client and tests).
]]

local Text = {}

-- Cuts `s` to at most `maxBytes` bytes without splitting a multi-byte UTF-8 character.
-- Assumes `s` is valid UTF-8 (callers validate with utf8.len first).
function Text.truncateUtf8(s: string, maxBytes: number): string
	if #s <= maxBytes then
		return s
	end
	local cut = maxBytes
	-- Continuation bytes look like 10xxxxxx (128..191). Step back until the byte AFTER the cut
	-- is the start of a character, so the kept prefix only contains whole characters.
	while cut > 0 do
		local nextByte = string.byte(s, cut + 1)
		if nextByte == nil or nextByte < 128 or nextByte >= 192 then
			break
		end
		cut -= 1
	end
	return string.sub(s, 1, cut)
end

-- Same as truncateUtf8 but appends "..." when something was removed.
function Text.ellipsize(s: string, maxBytes: number): string
	if #s <= maxBytes then
		return s
	end
	return Text.truncateUtf8(s, math.max(0, maxBytes - 3)) .. "..."
end

-- Number of lines a program occupies in the editor, ignoring trailing blank lines.
function Text.countLines(source: string): number
	local lines = string.split(source, "\n")
	local count = #lines
	while count > 0 and string.match(lines[count], "^%s*$") ~= nil do
		count -= 1
	end
	return count
end

--[[
	The terminal's Tab key (BUG-17). The Tab key handler inserts the 4 spaces itself. If the
	TextBox ALSO inserts a "\t", in either order, that edit is exactly one "\t" right before
	the caret: this returns the text and caret with it removed, so one Tab is always 4 spaces.
	Anything else (typing, a paste that contains tabs) returns nil.
	`cursor` is the TextBox CursorPosition after the edit (1-based, -1 = none).
]]
function Text.withoutTypedTab(previous: string, current: string, cursor: number): (string?, number?)
	if #current ~= #previous + 1 or cursor < 2 or string.sub(current, cursor - 1, cursor - 1) ~= "\t" then
		return nil, nil
	end
	local text = string.sub(current, 1, cursor - 2) .. string.sub(current, cursor)
	if text ~= previous then
		return nil, nil -- not a single tab inserted at the caret
	end
	return text, cursor - 1
end

return Text
