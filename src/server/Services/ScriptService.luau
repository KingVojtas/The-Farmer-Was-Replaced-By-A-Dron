--!strict
--[[
	ScriptService
	=============
	Runs players' drone programs. The full path of a program:

	  client TextBox --(RunScript: slot, raw source string)--> NetService (rate limit + validation)
	    -> ScriptService: save source to the profile (in memory; autosave persists it)
	    -> Parser.compile(source, limits for this player's memory, isUnlocked from SAVED research)
	         (parse errors / locked features go straight back to the client with a line number)
	    -> RunGate: cancel + task.cancel() the player's previous run; the new run starts only
	       once no other run drives this drone (a hard mutex, no timeout)
	    -> task.spawn: Interpreter.run(AST, context)
	         * builtins   = DroneAPI on a LiveWorld (the real plot; only unlocked builtins)
	         * yield      = task.wait(YieldEvery / StepsPerSecond)  -> fixed CPU budget, never
	                        times out, even for `while True: pass`
	         * actions    = world:wait(duration) -> task.wait inside DroneAPI
	         * loadModule = `import utils` compiles the SAVED source of the slot named "utils"
	                        (never text from the client) with the same research gate
	         * simulate   = runs a saved slot on a SimWorld (virtual farm, virtual clock), via
	                        DroneRuntime.Simulation. Each call takes >= Simulate.MinRealSeconds
	                        of real time, slots compile once per run (compile cache) and the
	                        simulated steps share the run's CPU budget (Interpreter.Budget)
	    -> ScriptStatus / ScriptOutput remotes report progress, prints, hints and errors
	       ("line" statuses are capped at Script.MaxLineStatusPerSecond).

	At most one run per player, ever: two programs never drive one drone or touch one PlayerData.
	Leaving, pressing Stop or starting a new run kills the old one (DroneRuntime.RunGate).
	Output is throttled (MaxOutputPerSecond) and truncated (MaxOutputLength). Program text and
	output are only ever shown to their author; if that changes, filter with TextService first.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Builtins = require(ReplicatedStorage.Shared.DroneScript.Builtins)
local Parser = require(ReplicatedStorage.Shared.DroneScript.Parser)
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Text = require(ReplicatedStorage.Shared.Util.Text)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)
local Runtime = script.Parent.Parent.DroneRuntime
local DroneAPI = require(Runtime.DroneAPI)
local Interpreter = require(Runtime.Interpreter)
local LiveWorld = require(Runtime.LiveWorld)
local RunGate = require(Runtime.RunGate)
local SimWorld = require(Runtime.SimWorld)
local Simulation = require(Runtime.Simulation)
local DataService = require(script.Parent.DataService)
local GamepassService = require(script.Parent.GamepassService)
local GridService = require(script.Parent.GridService)
local NetService = require(script.Parent.NetService)
local TutorialService = require(script.Parent.TutorialService)
local WeatherService = require(script.Parent.WeatherService)

local SCRIPT = GameConfig.Script
local HINT_REPEAT_SECONDS = 10 -- the same hint is shown at most once per this many seconds

local ScriptService = {}

local gate = RunGate.new()
local outputCounter = RateLimiter.newWindowCounter(1, os.clock)
local lineCounter = RateLimiter.newWindowCounter(1, os.clock) -- ScriptStatus "line" per player
local lastHints: { [Player]: { [string]: number } } = {}

local function sendOutput(player: Player, kind: string, text: string)
	if player.Parent ~= Players then
		return
	end
	local count = outputCounter:Add(player)
	if count > SCRIPT.MaxOutputPerSecond then
		if count == SCRIPT.MaxOutputPerSecond + 1 then
			NetService:Fire(
				player,
				"ScriptOutput",
				"info",
				"(output is coming too fast - some lines were skipped)"
			)
		end
		return
	end
	NetService:Fire(player, "ScriptOutput", kind, Text.ellipsize(text, SCRIPT.MaxOutputLength))
end

local function sendHint(player: Player, text: string)
	local seen = lastHints[player]
	if seen == nil then
		seen = {}
		lastHints[player] = seen
	end
	local now = os.clock()
	if seen[text] ~= nil and now - seen[text] < HINT_REPEAT_SECONDS then
		return
	end
	seen[text] = now
	sendOutput(player, "hint", text)
end

-- Feature predicate built from the player's SAVED unlocks (never from anything the client says).
local function unlockCheck(player: Player): (feature: string) -> boolean
	local data = DataService:GetData(player)
	local unlocks = if data ~= nil then data.techUnlocks else {}
	return function(feature: string): boolean
		return Tech.isFeatureUnlocked(unlocks, feature)
	end
end

local function compileFor(player: Player, source: string): (Parser.Program?, Parser.CompileError?)
	local maxLines = GamepassService:GetPerks(player).maxLines
	return Parser.compile(source, Parser.limits(maxLines), unlockCheck(player))
end

local function interpreterLimits(): Interpreter.Limits
	return {
		maxIdleSteps = SCRIPT.MaxIdleSteps,
		yieldEvery = SCRIPT.YieldEvery,
		maxRepeat = SCRIPT.MaxRepeat,
		maxCallDepth = SCRIPT.MaxCallDepth,
		maxContainerItems = SCRIPT.MaxContainerItems,
		maxLiveItems = SCRIPT.MaxLiveItems,
		heapScanEvery = SCRIPT.HeapScanEvery,
		maxStringResult = SCRIPT.MaxStringResult,
		maxComputed = SCRIPT.MaxComputed,
	}
end

-- The CPU throttle: hands the frame back to the engine AND caps steps per second.
local function throttleYield()
	task.wait(SCRIPT.YieldEvery / SCRIPT.StepsPerSecond)
end

local function slotByName(player: Player, name: string): (number?, string?)
	local names = DataService:GetScriptNames(player)
	if names == nil then
		return nil, "Your save data isn't loaded."
	end
	for slot, slotName in names do
		if slotName == name then
			return slot, nil
		end
	end
	return nil,
		string.format("there's no script called '%s'. Your scripts are: %s.", name, table.concat(names, ", "))
end

-- `import name`: compile the SAVED source of the slot with that name (once per run: `cache`).
local function moduleLoader(player: Player, cache: Simulation.CompileCache): Interpreter.ModuleLoader
	return function(name: string): (Parser.Program?, string?)
		local slot, reason = slotByName(player, name)
		if slot == nil then
			return nil, reason
		end
		local scripts = DataService:GetScripts(player)
		local source = if scripts ~= nil then scripts[slot] else nil
		if source == nil then
			return nil, "your save data isn't loaded."
		end
		local program, err = cache:get(slot, source)
		if program == nil then
			local e = err :: Parser.CompileError
			return nil, string.format("line %d: %s", e.line, e.message)
		end
		return program, nil
	end
end

-- simulate(): SimWorld calls this every virtual second. It always yields (task.wait), so even
-- a 600 s simulation can never hitch a server frame or outlive a Stop / new run.
local function simYield()
	task.wait()
end

-- simulate(slot, seconds) for one run (DroneRuntime.Simulation: cache, shared budget).
local function simulator(
	player: Player,
	plot: GridService.Plot,
	outerStop: () -> boolean,
	cache: Simulation.CompileCache,
	budget: Interpreter.Budget
): DroneAPI.Simulator
	local isUnlocked = unlockCheck(player)
	local simulate = Simulation.new({
		slotByName = function(name: string): (number?, string?)
			return slotByName(player, name)
		end,
		sourceOf = function(slot: number): string?
			local scripts = DataService:GetScripts(player)
			return if scripts ~= nil then scripts[slot] else nil
		end,
		cache = cache,
		newWorld = function(seconds: number): any
			local data = DataService:GetData(player)
			if data == nil then
				return nil
			end
			local stats = GridService:GetStats(player)
			local growthBoost, yieldBoost = DataService:GetBoostMultipliers(player)
			local perks = GamepassService:GetPerks(player)
			local rng = Random.new()
			local charger = GameConfig.Stations.charger
			return SimWorld.new({
				size = plot.size,
				tiles = plot.tiles :: any,
				drone = {
					x = charger.x,
					y = charger.y,
					battery = stats.batteryCapacity,
					water = stats.waterCapacity,
				},
				stats = stats,
				speedPerk = perks.speedMultiplier,
				yieldMultiplier = perks.yieldMultiplier * yieldBoost,
				growthBoost = growthBoost,
				weather = WeatherService:GetFor(player),
				currencies = data.currencies,
				random = function(): number
					return rng:NextNumber()
				end,
				duration = seconds,
				yield = simYield,
				shouldStop = outerStop,
			})
		end,
		isUnlocked = isUnlocked,
		loadModule = moduleLoader(player, cache),
		throttle = throttleYield,
		budget = budget,
		shouldStop = outerStop,
		limits = interpreterLimits(),
		maxSteps = GameConfig.Simulate.MaxSteps,
		onInternal = function(message: string?, trace: string?)
			warn(
				string.format(
					"[ScriptService] simulate internal error: %s\n%s",
					tostring(message),
					tostring(trace)
				)
			)
		end,
	})
	return simulate
end

local function stopRun(player: Player)
	local run, killed = gate:stop(player)
	-- A killed run can't report itself; a run that stops on its own reports "stopped" below.
	if run ~= nil and killed and player.Parent == Players then
		NetService:Fire(player, "ScriptStatus", "stopped", 0)
	end
end

local function startRun(player: Player, program: Parser.Program, plot: GridService.Plot, moduleName: string)
	-- RunGate kills the previous run and only calls this body once nothing else drives the drone.
	gate:start(player, function(run: RunGate.Run)
		local isUnlocked = unlockCheck(player)
		local function shouldStop(): boolean
			return run.cancelled or plot.destroyed or player.Parent ~= Players
		end

		local result: Interpreter.RunResult
		if shouldStop() then
			result = { status = "cancelled" }
		else
			NetService:Fire(player, "ScriptStatus", "running", 0)
			TutorialService:Notify(player, "run")
			local looped = false
			-- One compile cache and one CPU budget for the whole run: the main program, its
			-- imports and every simulate() it starts (DroneRuntime.Simulation, BUG-01).
			local cache = Simulation.newCompileCache(function(source: string)
				return compileFor(player, source)
			end)
			local budget: Interpreter.Budget = { steps = 0 }
			local api = DroneAPI.create({
				world = LiveWorld.new(player, plot, shouldStop),
				output = {
					print = function(text: string)
						sendOutput(player, "print", text)
					end,
					hint = function(text: string)
						sendHint(player, text)
					end,
					info = function(text: string)
						sendOutput(player, "info", text)
					end,
				},
				shouldStop = shouldStop,
				isUnlocked = isUnlocked,
				simulate = simulator(player, plot, shouldStop, cache, budget),
				onUnload = function(moved: { [string]: number })
					if (moved.hay or 0) > 0 then
						TutorialService:Notify(player, "hayUnload")
					end
				end,
			})
			result = Interpreter.run(program, {
				specs = Builtins.ByName,
				builtins = api,
				yield = throttleYield,
				isCancelled = shouldStop,
				onAction = function(line: number, inMain: boolean)
					-- Capped per player: the highlight needs a few updates a second, not a flood.
					if lineCounter:Add(player) <= SCRIPT.MaxLineStatusPerSecond then
						NetService:Fire(player, "ScriptStatus", "line", if inMain then line else 0)
					end
				end,
				onLoop = function()
					if not looped then
						looped = true
						TutorialService:Notify(player, "loop")
					end
				end,
				loadModule = moduleLoader(player, cache),
				moduleName = moduleName,
				limits = interpreterLimits(),
				budget = budget,
			})
		end

		local superseded = gate:current(player) ~= run
		if player.Parent ~= Players then
			return
		end

		if result.status == "finished" or result.status == "limit" then
			NetService:Fire(player, "ScriptStatus", "finished", 0)
		elseif result.status == "cancelled" then
			if not superseded then
				NetService:Fire(player, "ScriptStatus", "stopped", 0)
			end
		elseif result.status == "error" and result.error ~= nil then
			local err = result.error
			NetService:Fire(player, "ScriptOutput", "error", Simulation.formatError(err))
			NetService:Fire(player, "ScriptStatus", "error", if err.module == nil then err.line else 0)
		else
			warn(
				string.format(
					"[ScriptService] Internal error in %s's program: %s\n%s",
					player.Name,
					tostring(result.message),
					tostring(result.trace)
				)
			)
			NetService:Fire(
				player,
				"ScriptOutput",
				"error",
				"Something went wrong on our side. The developers have been notified."
			)
			NetService:Fire(player, "ScriptStatus", "error", 0)
		end
	end)
end

type RunResponse = { ok: boolean, error: { line: number, col: number, message: string }? }

local function errorResponse(message: string, line: number?, col: number?): RunResponse
	return { ok = false, error = { line = line or 0, col = col or 0, message = message } }
end

function ScriptService:Init()
	NetService:OnInvoke("RunScript", function(player: Player, slot: number, source: string): RunResponse
		if DataService:GetData(player) == nil then
			return errorResponse("Your save data is still loading. Try again in a moment.")
		end
		local plot = GridService:GetPlot(player)
		if plot == nil then
			return errorResponse("Your farm is still being built. Try again in a moment.")
		end

		DataService:SetScript(player, slot, source) -- keep the player's work even if it has errors

		local program, err = compileFor(player, source)
		if program == nil then
			local compileError = err :: Parser.CompileError
			if compileError.internal ~= nil then
				warn("[ScriptService] Internal compile error: " .. compileError.internal)
			end
			return errorResponse(compileError.message, compileError.line, compileError.col)
		end

		local names = DataService:GetScriptNames(player)
		startRun(player, program, plot, if names ~= nil then names[slot] else "main")
		return { ok = true }
	end)

	NetService:OnInvoke("SaveScript", function(player: Player, slot: number, source: string): boolean
		return DataService:SetScript(player, slot, source)
	end)

	NetService:OnInvoke("RenameScript", function(player: Player, slot: number, name: string): any
		local ok, reason = DataService:RenameScript(player, slot, name)
		return { ok = ok, message = reason, names = DataService:GetScriptNames(player) }
	end)

	NetService:OnEvent("StopScript", function(player: Player)
		stopRun(player)
	end)

	NetService:OnInvoke("GetScripts", function(player: Player): any
		local scripts = DataService:GetScripts(player)
		if scripts == nil then
			return nil
		end
		return {
			scripts = scripts,
			names = DataService:GetScriptNames(player),
			maxLines = GamepassService:GetPerks(player).maxLines,
		}
	end)
end

function ScriptService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		stopRun(player)
		outputCounter:Reset(player)
		lineCounter:Reset(player)
		lastHints[player] = nil
	end)
end

return ScriptService
