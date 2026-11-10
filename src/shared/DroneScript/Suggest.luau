--!strict
--[[
	Suggest
	=======
	"Did you mean ...?" helper for friendly error messages. Uses a bounded Levenshtein distance;
	inputs are capped at 32 characters so the cost is tiny no matter what a player types.
]]

local MAX_LEN = 32

local Suggest = {}

-- Classic edit distance (insert / delete / substitute = 1).
function Suggest.distance(a: string, b: string): number
	a = string.lower(string.sub(a, 1, MAX_LEN))
	b = string.lower(string.sub(b, 1, MAX_LEN))
	local lenA, lenB = #a, #b
	if lenA == 0 then
		return lenB
	end
	if lenB == 0 then
		return lenA
	end
	local previous = table.create(lenB + 1, 0)
	for j = 0, lenB do
		previous[j + 1] = j
	end
	for i = 1, lenA do
		local current = table.create(lenB + 1, 0)
		current[1] = i
		local charA = string.byte(a, i)
		for j = 1, lenB do
			local cost = if charA == string.byte(b, j) then 0 else 1
			current[j + 1] = math.min(previous[j + 1] + 1, current[j] + 1, previous[j] + cost)
		end
		previous = current
	end
	return previous[lenB + 1]
end

-- Returns the closest candidate within `maxDistance` (default 2), or nil.
function Suggest.closest(word: string, candidates: { string }, maxDistance: number?): string?
	local limit = maxDistance or 2
	local best: string? = nil
	local bestDistance = math.huge
	for _, candidate in candidates do
		local d = Suggest.distance(word, candidate)
		if d < bestDistance then
			best, bestDistance = candidate, d
		end
	end
	if best ~= nil and bestDistance <= limit then
		return best
	end
	return nil
end

return Suggest
