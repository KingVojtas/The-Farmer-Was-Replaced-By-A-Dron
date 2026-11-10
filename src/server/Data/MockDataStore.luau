--!strict
--[[
	MockDataStore
	=============
	In-memory stand-in for a GlobalDataStore. Used by:
	  * Studio play-tests when "Enable Studio Access to API Services" is off (data is lost
	    when the test stops - DataService prints a loud warning),
	  * the offline unit tests.
	It is NEVER used in live servers.

	Behaves like the real thing where it matters:
	  * values are deep-copied in and out (as if serialized), so callers can't share tables
	    with the "database",
	  * a transform returning nil cancels the write,
	  * values that a real DataStore would reject (functions, Instances, NaN, mixed keys) raise,
	  * FailNext(n) makes the next n calls throw, to test retry logic,
	  * optional latency through an injected wait function, to test concurrency.
]]

export type MockDataStore = {
	UpdateAsync: (self: MockDataStore, key: string, transform: (any, any) -> ...any) -> any,
	GetAsync: (self: MockDataStore, key: string) -> any,
	SetAsync: (self: MockDataStore, key: string, value: any) -> (),
	RemoveAsync: (self: MockDataStore, key: string) -> any,
	FailNext: (self: MockDataStore, count: number) -> (),
	Peek: (self: MockDataStore, key: string) -> any,
	writes: number,
}

export type Options = {
	latency: number?,
	wait: ((seconds: number) -> ())?,
}

local function deepCopy(value: any, path: string): any
	local kind = type(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			error("MockDataStore: cannot store NaN/inf at " .. path)
		end
		return value
	elseif kind == "string" or kind == "boolean" or kind == "nil" then
		return value
	elseif kind == "table" then
		local copy = {}
		local hasStringKeys, hasNumberKeys = false, false
		for k, v in value do
			if type(k) == "string" then
				hasStringKeys = true
			elseif type(k) == "number" then
				hasNumberKeys = true
			else
				error("MockDataStore: invalid key type at " .. path)
			end
			copy[k] = deepCopy(v, path .. "." .. tostring(k))
		end
		if hasStringKeys and hasNumberKeys then
			error("MockDataStore: mixed array/dictionary table at " .. path)
		end
		return copy
	end
	error("MockDataStore: cannot store a " .. kind .. " at " .. path)
end

local MockDataStore = {}

function MockDataStore.new(options: Options?): MockDataStore
	local opts: Options = options or {}
	local storage: { [string]: any } = {}
	local failures = 0

	local function before()
		if opts.latency and opts.wait then
			opts.wait(opts.latency)
		end
		if failures > 0 then
			failures -= 1
			error("MockDataStore: simulated request failure")
		end
	end

	local store: MockDataStore
	store = {
		writes = 0,
		UpdateAsync = function(_self: MockDataStore, key: string, transform: (any, any) -> ...any): any
			before()
			local newValue = transform(deepCopy(storage[key], key), nil)
			if newValue == nil then
				return nil -- cancelled
			end
			storage[key] = deepCopy(newValue, key)
			store.writes += 1
			return deepCopy(storage[key], key)
		end,
		GetAsync = function(_self: MockDataStore, key: string): any
			before()
			return deepCopy(storage[key], key)
		end,
		SetAsync = function(_self: MockDataStore, key: string, value: any)
			before()
			storage[key] = deepCopy(value, key)
			store.writes += 1
		end,
		RemoveAsync = function(_self: MockDataStore, key: string): any
			before()
			local old = storage[key]
			storage[key] = nil
			return old
		end,
		FailNext = function(_self: MockDataStore, count: number)
			failures = count
		end,
		Peek = function(_self: MockDataStore, key: string): any
			return deepCopy(storage[key], key)
		end,
	}
	return store
end

return MockDataStore
