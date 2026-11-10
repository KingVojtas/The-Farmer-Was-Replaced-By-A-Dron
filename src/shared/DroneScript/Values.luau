--!strict
--[[
	Values
	======
	The runtime values of drone programs, shared by the server Interpreter, DroneAPI (print)
	and the tests. Pure: no Roblox APIs.

	  number, string, boolean   plain Luau values
	  None                      Values.NONE (a frozen sentinel; a Luau nil never appears in a
	                            program - lists and variables can always hold "nothing")
	  list                      { items = { value } }                     (0-based to players)
	  dict                      { keys = { key }, map = { [key] = value } } insertion-ordered;
	                            keys are numbers, strings or booleans
	  range                     { start, stop, step } - lazy, never allocates its numbers
	  function                  { name, def (AST), module }  - made by `def`
	  module                    { name, globals }            - made by `import`

	Containers are told apart by metatable identity, so a table a builtin returns (e.g. the
	plain { wheat = 40 } from get_cost) is NEVER mistaken for a program value - the Interpreter
	converts it explicitly (and counts it against the memory budget).
]]

local Values = {}

local NoneMeta = {
	__tostring = function()
		return "None"
	end,
}
local ListMeta = {}
local DictMeta = {}
local RangeMeta = {}
local FunctionMeta = {}
local ModuleMeta = {}

Values.NONE = table.freeze(setmetatable({}, NoneMeta))

export type List = { items: { any } }
export type Dict = { keys: { any }, map: { [any]: any } }
export type Range = { start: number, stop: number, step: number }
export type FunctionValue = { name: string, def: any, module: any }
export type Module = { name: string, globals: { [string]: any } }

export type Kind =
	"number"
	| "string"
	| "boolean"
	| "none"
	| "list"
	| "dict"
	| "range"
	| "function"
	| "module"
	| "unknown"

function Values.newList(items: { any }?): List
	return setmetatable({ items = items or {} }, ListMeta) :: any
end

function Values.newDict(): Dict
	return setmetatable({ keys = {}, map = {} }, DictMeta) :: any
end

function Values.newRange(start: number, stop: number, step: number): Range
	return setmetatable({ start = start, stop = stop, step = step }, RangeMeta) :: any
end

function Values.newFunction(name: string, def: any, module: any): FunctionValue
	return setmetatable({ name = name, def = def, module = module }, FunctionMeta) :: any
end

function Values.newModule(name: string): Module
	return setmetatable({ name = name, globals = {} }, ModuleMeta) :: any
end

function Values.isList(value: any): boolean
	return type(value) == "table" and getmetatable(value) == ListMeta
end
function Values.isDict(value: any): boolean
	return type(value) == "table" and getmetatable(value) == DictMeta
end
function Values.isRange(value: any): boolean
	return type(value) == "table" and getmetatable(value) == RangeMeta
end
function Values.isFunction(value: any): boolean
	return type(value) == "table" and getmetatable(value) == FunctionMeta
end
function Values.isModule(value: any): boolean
	return type(value) == "table" and getmetatable(value) == ModuleMeta
end
function Values.isNone(value: any): boolean
	return value == Values.NONE
end

function Values.kind(value: any): Kind
	local t = type(value)
	if t == "number" or t == "string" or t == "boolean" then
		return t :: any
	end
	if t == "table" then
		local meta = getmetatable(value)
		if meta == NoneMeta then
			return "none"
		elseif meta == ListMeta then
			return "list"
		elseif meta == DictMeta then
			return "dict"
		elseif meta == RangeMeta then
			return "range"
		elseif meta == FunctionMeta then
			return "function"
		elseif meta == ModuleMeta then
			return "module"
		end
	end
	return "unknown"
end

local TYPE_WORDS: { [string]: string } = {
	number = "a number",
	string = "text",
	boolean = "True or False",
	none = "None",
	list = "a list",
	dict = "a dictionary",
	range = "a range",
	["function"] = "a function",
	module = "a module",
	unknown = "an unknown value",
}

-- "a number", "text", "a list", ... for error messages.
function Values.typeWord(value: any): string
	return TYPE_WORDS[Values.kind(value)]
end

-- Keys a dictionary accepts (finite numbers, strings, booleans).
function Values.isHashable(value: any): boolean
	local t = type(value)
	if t == "number" then
		return value == value and value ~= math.huge and value ~= -math.huge
	end
	return t == "string" or t == "boolean"
end

function Values.formatNumber(n: number): string
	if n ~= n then
		return "nan"
	elseif n == math.huge then
		return "inf"
	elseif n == -math.huge then
		return "-inf"
	elseif n % 1 == 0 and math.abs(n) < 1e15 then
		return string.format("%d", n)
	end
	return string.format("%.10g", n)
end

-- Builds a bounded string. `budget` is shared by the whole recursive repr.
type Writer = { parts: { string }, left: number, full: boolean }

local function write(w: Writer, s: string)
	if w.full then
		return
	end
	if #s >= w.left then
		table.insert(w.parts, string.sub(s, 1, math.max(0, w.left)))
		w.left = 0
		w.full = true
		return
	end
	table.insert(w.parts, s)
	w.left -= #s
end

local function quote(s: string): string
	local escaped = string.gsub(s, "\\", "\\\\")
	escaped = string.gsub(escaped, '"', '\\"')
	escaped = string.gsub(escaped, "\n", "\\n")
	escaped = string.gsub(escaped, "\t", "\\t")
	return '"' .. escaped .. '"'
end

local function reprInto(w: Writer, value: any, depth: number, seen: { [any]: boolean })
	if w.full then
		return
	end
	local kind = Values.kind(value)
	if kind == "boolean" then
		write(w, if value then "True" else "False")
	elseif kind == "none" then
		write(w, "None")
	elseif kind == "number" then
		write(w, Values.formatNumber(value))
	elseif kind == "string" then
		write(w, quote(value))
	elseif kind == "list" then
		if seen[value] or depth > 6 then
			write(w, "[...]")
			return
		end
		seen[value] = true
		write(w, "[")
		for i, item in value.items do
			if i > 1 then
				write(w, ", ")
			end
			reprInto(w, item, depth + 1, seen)
			if w.full then
				break
			end
		end
		write(w, "]")
		seen[value] = nil
	elseif kind == "dict" then
		if seen[value] or depth > 6 then
			write(w, "{...}")
			return
		end
		seen[value] = true
		write(w, "{")
		for i, key in value.keys do
			if i > 1 then
				write(w, ", ")
			end
			reprInto(w, key, depth + 1, seen)
			write(w, ": ")
			reprInto(w, value.map[key], depth + 1, seen)
			if w.full then
				break
			end
		end
		write(w, "}")
		seen[value] = nil
	elseif kind == "range" then
		if value.step == 1 then
			write(
				w,
				string.format(
					"range(%s, %s)",
					Values.formatNumber(value.start),
					Values.formatNumber(value.stop)
				)
			)
		else
			write(
				w,
				string.format(
					"range(%s, %s, %s)",
					Values.formatNumber(value.start),
					Values.formatNumber(value.stop),
					Values.formatNumber(value.step)
				)
			)
		end
	elseif kind == "function" then
		write(w, "<function " .. tostring(value.name) .. ">")
	elseif kind == "module" then
		write(w, "<module " .. tostring(value.name) .. ">")
	else
		write(w, "<?>")
	end
end

--[[
	Python-style representation: strings quoted, True/False/None, [1, 2], {"a": 1}.
	Never longer than `maxLength` characters (+ "..." when cut); cycles print as [...].
]]
function Values.repr(value: any, maxLength: number?): string
	local limit = maxLength or 200
	local w: Writer = { parts = {}, left = limit, full = false }
	reprInto(w, value, 0, {})
	local text = table.concat(w.parts)
	if w.full then
		text ..= "..."
	end
	return text
end

-- What print() shows: text as-is, everything else as repr.
function Values.display(value: any, maxLength: number?): string
	if type(value) == "string" then
		local limit = maxLength or 200
		if #value > limit then
			return string.sub(value, 1, limit) .. "..."
		end
		return value
	end
	return Values.repr(value, maxLength)
end

local MAX_EQUAL_DEPTH = 16

local function equalsAt(a: any, b: any, depth: number): boolean
	if a == b then
		return true
	end
	local ka, kb = Values.kind(a), Values.kind(b)
	if ka ~= kb or depth > MAX_EQUAL_DEPTH then
		return false
	end
	if ka == "list" then
		local ia, ib = a.items, b.items
		if #ia ~= #ib then
			return false
		end
		for i = 1, #ia do
			if not equalsAt(ia[i], ib[i], depth + 1) then
				return false
			end
		end
		return true
	elseif ka == "dict" then
		if #a.keys ~= #b.keys then
			return false
		end
		for _, key in a.keys do
			local other = b.map[key]
			if other == nil or not equalsAt(a.map[key], other, depth + 1) then
				return false
			end
		end
		return true
	elseif ka == "range" then
		return a.start == b.start and a.stop == b.stop and a.step == b.step
	end
	return false -- numbers/strings/booleans compared by == above; functions/modules by identity
end

-- Structural equality like Python's == (bounded depth, so cyclic lists can't hang it).
function Values.equals(a: any, b: any): boolean
	return equalsAt(a, b, 0)
end

-- Number of values a range produces.
function Values.rangeLength(r: Range): number
	if r.step > 0 then
		return math.max(0, math.ceil((r.stop - r.start) / r.step))
	end
	return math.max(0, math.ceil((r.start - r.stop) / -r.step))
end

-- Inserts or updates a dictionary entry; returns true if a NEW key was added.
function Values.dictSet(dict: Dict, key: any, value: any): boolean
	if dict.map[key] == nil then
		table.insert(dict.keys, key)
		dict.map[key] = value
		return true
	end
	dict.map[key] = value
	return false
end

return Values
