--!strict
--[[
	Simulation
	==========
	simulate(slotName, seconds) for ONE live run, plus the run's compile cache. Pure: the
	Roblox side (saved data, the plot, perks, weather) is injected by ScriptService, so the
	offline tests drive the exact code the server runs (tests/spec/Simulation.spec.luau).

	COST CONTROL (docs/BUGS.md BUG-01). A simulation runs on a virtual clock, so without these
	`while True: simulate("lab", 1)` would compile and run hundreds of farms per second:
	  * COMPILE CACHE: a slot's SAVED source compiles once per run (keyed by slot + source, so
	    an edited slot recompiles). The run's `import`s and every simulation share the cache.
	    Only successful compiles are cached, so research done mid-run is never ignored.
	  * SHARED CPU BUDGET: the simulated program counts its steps in the run's Interpreter
	    budget, so its steps throttle exactly like the outer program's.
	  * MINIMUM REAL TIME: DroneAPI.simulate makes every call last at least
	    GameConfig.Simulate.MinRealSeconds on the live farm.
	It still reads only SAVED slots (never client text) and can't touch real data: SimWorld has
	no access to DataService or Instances.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Builtins = require(ReplicatedStorage.Shared.DroneScript.Builtins)
local Parser = require(ReplicatedStorage.Shared.DroneScript.Parser)
local DroneAPI = require(script.Parent.DroneAPI)
local Interpreter = require(script.Parent.Interpreter)
local SimWorldModule = require(script.Parent.SimWorld)

type Program = Parser.Program
type CompileError = Parser.CompileError
type SimWorld = SimWorldModule.SimWorld

export type CompileCache = {
	get: (self: CompileCache, slot: number, source: string) -> (Program?, CompileError?),
	compiles: number, -- how many times the compiler actually ran
}

export type Options = {
	slotByName: (name: string) -> (number?, string?), -- (slot) or (nil, reason)
	sourceOf: (slot: number) -> string?, -- the SAVED source of a slot (nil = data not loaded)
	cache: CompileCache, -- the run's cache
	newWorld: (seconds: number) -> SimWorld?, -- a fresh virtual farm (nil = data not loaded)
	isUnlocked: (feature: string) -> boolean, -- from SAVED research
	loadModule: Interpreter.ModuleLoader?,
	throttle: () -> (), -- the run's CPU throttle (ScriptService: task.wait)
	budget: Interpreter.Budget, -- the run's shared step budget
	shouldStop: () -> boolean, -- the outer (live) run was stopped
	limits: Interpreter.Limits,
	maxSteps: number,
	onInternal: ((message: string?, trace: string?) -> ())?, -- a bug on our side
}

export type Stats = { calls: number }

local SILENT: DroneAPI.Output = {
	print = function(_text: string) end,
	hint = function(_text: string) end,
	info = function(_text: string) end,
}

local Simulation = {}

function Simulation.formatError(err: { line: number, message: string, module: string? }): string
	if err.module ~= nil then
		return string.format("In '%s', line %d: %s", err.module, err.line, err.message)
	end
	return string.format("Line %d: %s", err.line, err.message)
end

-- compile(source) -> (Program?, CompileError?); called only on a cache miss.
function Simulation.newCompileCache(compile: (source: string) -> (Program?, CompileError?)): CompileCache
	local entries: { [number]: { source: string, program: Program } } = {}
	local cache: CompileCache
	cache = {
		compiles = 0,
		get = function(_self: CompileCache, slot: number, source: string): (Program?, CompileError?)
			local entry = entries[slot]
			if entry ~= nil and entry.source == source then
				return entry.program, nil
			end
			cache.compiles += 1
			local program, err = compile(source)
			if program ~= nil then
				entries[slot] = { source = source, program = program }
			end
			return program, err
		end,
	}
	return cache
end

function Simulation.new(options: Options): (DroneAPI.Simulator, Stats)
	local stats: Stats = { calls = 0 }

	local function simulate(slotName: string, seconds: number): (number?, string?)
		stats.calls += 1
		local slot, reason = options.slotByName(slotName)
		if slot == nil then
			return nil, "simulate(): " .. tostring(reason)
		end
		local source = options.sourceOf(slot)
		if source == nil then
			return nil, "simulate(): your save data isn't loaded."
		end
		local program, compileError = options.cache:get(slot, source)
		if program == nil then
			local e = compileError :: CompileError
			return nil, string.format("simulate(): '%s' line %d: %s", slotName, e.line, e.message)
		end
		local sim = options.newWorld(seconds)
		if sim == nil then
			return nil, "simulate(): your save data isn't loaded."
		end
		local world = sim :: SimWorld

		local function simStop(): boolean
			return world:finished() or options.shouldStop()
		end
		local api, info = DroneAPI.create({
			world = world,
			output = SILENT,
			shouldStop = simStop,
			isUnlocked = options.isUnlocked,
			simulate = nil, -- no simulations inside simulations
		})
		local result = Interpreter.run(program, {
			specs = Builtins.ByName,
			builtins = api,
			yield = options.throttle,
			isCancelled = simStop,
			loadModule = options.loadModule,
			moduleName = slotName,
			maxSteps = options.maxSteps,
			limits = options.limits,
			budget = options.budget,
		})
		if options.shouldStop() then
			return 0, nil -- the real run was stopped; its interpreter cancels right after this
		end
		if result.status == "error" and result.error ~= nil then
			return nil,
				"simulate(): " .. Simulation.formatError({
					line = result.error.line,
					message = result.error.message,
					module = result.error.module or slotName,
				})
		elseif result.status == "internal" then
			local onInternal = options.onInternal
			if onInternal ~= nil then
				onInternal(result.message, result.trace)
			end
			return nil, "The simulation failed on our side."
		end
		return info.harvested, nil
	end

	return simulate, stats
end

return Simulation
