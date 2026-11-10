--!strict
--[[
	Validate
	========
	Tiny argument validators for remote payloads. Everything a client sends is hostile until
	proven otherwise, so each validator checks the exact Lua type FIRST (cheap) and only then
	looks at the content.

	A validator is `(value: any) -> (boolean, string?)`; the string explains a rejection (for
	server logs only - never shown to players).

	Notes on exploit payloads this guards against:
	  * NaN / +-inf numbers (NaN ~= NaN, and both break math and DataStores)
	  * huge strings (size is checked before UTF-8 decoding)
	  * invalid UTF-8 (breaks text rendering and JSON encoding)
	  * Instances / tables / functions where a primitive is expected (type() ~= "string")
	  * extra or missing arguments (exact count via select("#", ...))
]]

export type Validator = (value: any) -> (boolean, string?)

local Validate = {}

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Validate.string(maxBytes: number): Validator
	return function(value: any)
		if type(value) ~= "string" then
			return false, "expected string, got " .. type(value)
		end
		if #value > maxBytes then
			return false, string.format("string too long (%d > %d bytes)", #value, maxBytes)
		end
		if utf8.len(value) == nil then
			return false, "string is not valid UTF-8"
		end
		return true
	end
end

function Validate.integer(min: number, max: number): Validator
	return function(value: any)
		if not isFiniteNumber(value) then
			return false, "expected finite number"
		end
		if value % 1 ~= 0 then
			return false, "expected integer"
		end
		if value < min or value > max then
			return false, string.format("integer out of range [%d, %d]", min, max)
		end
		return true
	end
end

function Validate.number(min: number, max: number): Validator
	return function(value: any)
		if not isFiniteNumber(value) then
			return false, "expected finite number"
		end
		if value < min or value > max then
			return false, "number out of range"
		end
		return true
	end
end

function Validate.boolean(): Validator
	return function(value: any)
		if type(value) ~= "boolean" then
			return false, "expected boolean"
		end
		return true
	end
end

function Validate.enum(options: { string }): Validator
	local allowed: { [string]: boolean } = {}
	for _, option in options do
		allowed[option] = true
	end
	return function(value: any)
		if type(value) ~= "string" or not allowed[value] then
			return false, "value not in enum"
		end
		return true
	end
end

--[[
	Validate.args(validators, ...) -> (ok, reason?)
	The number of arguments must match EXACTLY. Trailing nils count (select("#") sees them),
	so a client cannot smuggle extra values past a handler.
]]
function Validate.args(validators: { Validator }, ...: any): (boolean, string?)
	local count = select("#", ...)
	if count ~= #validators then
		return false, string.format("expected %d argument(s), got %d", #validators, count)
	end
	for index, validator in validators do
		local ok, reason = validator((select(index, ...)))
		if not ok then
			return false, string.format("argument %d: %s", index, reason or "invalid")
		end
	end
	return true
end

return Validate
