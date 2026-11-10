--[[
	Minimal test framework for Lune: describe / it / expect.
	Test bodies may yield (task.wait) - each case runs inside pcall.
]]

local T = {}

local cases = {}
local prefix = nil

local function format(value)
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		local parts = {}
		for k, v in value do
			table.insert(parts, tostring(k) .. "=" .. format(v))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

function T.describe(name, fn)
	local previous = prefix
	prefix = if previous then previous .. " > " .. name else name
	fn()
	prefix = previous
end

function T.it(name, fn)
	table.insert(cases, { name = if prefix then prefix .. " > " .. name else name, fn = fn })
end

function T.expect(actual)
	local matchers = {}

	function matchers.toBe(expected)
		if actual ~= expected then
			error(string.format("expected %s, got %s", format(expected), format(actual)), 2)
		end
	end

	function matchers.never_toBe(expected)
		if actual == expected then
			error(string.format("expected value to differ from %s", format(expected)), 2)
		end
	end

	function matchers.toEqual(expected)
		if not deepEqual(actual, expected) then
			error(string.format("expected %s, got %s", format(expected), format(actual)), 2)
		end
	end

	function matchers.toBeNil()
		if actual ~= nil then
			error(string.format("expected nil, got %s", format(actual)), 2)
		end
	end

	function matchers.toBeTruthy()
		if not actual then
			error(string.format("expected truthy value, got %s", format(actual)), 2)
		end
	end

	function matchers.toContain(fragment)
		if type(actual) ~= "string" or string.find(actual, fragment, 1, true) == nil then
			error(string.format("expected %s to contain %s", format(actual), format(fragment)), 2)
		end
	end

	function matchers.toBeAtMost(limit)
		if type(actual) ~= "number" or actual > limit then
			error(string.format("expected <= %s, got %s", format(limit), format(actual)), 2)
		end
	end

	function matchers.toBeAtLeast(limit)
		if type(actual) ~= "number" or actual < limit then
			error(string.format("expected >= %s, got %s", format(limit), format(actual)), 2)
		end
	end

	return matchers
end

function T.run()
	local passed, failed = 0, 0
	local failures = {}
	for _, case in cases do
		local ok, err = pcall(case.fn)
		if ok then
			passed += 1
		else
			failed += 1
			table.insert(failures, { name = case.name, err = err })
		end
	end
	for _, failure in failures do
		print("  FAIL  " .. failure.name)
		print("        " .. tostring(failure.err))
	end
	print(string.format("\n%d passed, %d failed, %d total", passed, failed, passed + failed))
	return passed, failed
end

return T
