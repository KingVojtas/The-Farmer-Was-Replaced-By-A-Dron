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

return Text
