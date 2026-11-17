--!strict
--[[
	DroneAPI
	========
	Implementations of every world-facing builtin a drone program can call. The Interpreter
	only ever calls functions from the table this module returns.

	It talks to a World (DroneRuntime.World): the real plot (LiveWorld) or the virtual farm of
	simulate() (SimWorld). It has NO other dependencies on services or Instances, which is what
	makes simulate() safe and lets the offline tests run real farm programs.

	RULES EVERY ACTION FOLLOWS
	  * Validate first (position, tile state, energy, water, cargo), mutate second - a failed
	    action changes nothing.
	  * Every action waits (world:wait -> task.wait on the live farm) for its duration,
	    INCLUDING failed ones (ActionTimes.failed). So no program can spin through actions
	    without time passing, even `while True: move_left()` against a wall.
	  * State changes are published as attributes by the World; clients tween the drone
	    (TweenService, anchored parts) from them. Nothing here moves parts.
	  * Builtins that aren't unlocked in the Tech Tree are removed from the table (the parser
	    already rejects them at compile time - this is defence in depth).

	ENERGY & THROTTLE
	  Actions cost battery (GameConfig.Drone.EnergyCosts) x the set_speed() throttle; their
	  time is divided by (tech speed x Overclock x throttle). With an empty battery the drone
	  can still MOVE, but LimpSlowdown times slower, so it can always crawl home - no soft-lock.
	  charge() at the Charging Station (0, -1) refills battery and water tank. Arriving at the
	  charger, and charge() itself, also unload the cargo hold into the silo (raw currencies).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CropConfig = require(ReplicatedStorage.Shared.Config.CropConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local TechTree = require(ReplicatedStorage.Shared.Config.TechTree)
local Suggest = require(ReplicatedStorage.Shared.DroneScript.Suggest)
local Values = require(ReplicatedStorage.Shared.DroneScript.Values)
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Economy = require(script.Parent.Parent.Progression.Economy)
local Growth = require(script.Parent.Parent.Progression.Growth)
local WorldTypes = require(script.Parent.World)

type World = WorldTypes.World
type TileData = WorldTypes.TileData
export type BuiltinImpl = (args: { any }) -> (any, string?)

export type Output = {
	print: (text: string) -> (), -- print() from the program
	hint: (text: string) -> (), -- gentle explanation of why an action did nothing (deduplicated)
	info: (text: string) -> (), -- notable events (unloading, factory output)
}

-- simulate(slot, seconds) is provided by ScriptService (it needs the parser and saved data).
export type Simulator = (slotName: string, seconds: number) -> (number?, string?)

export type Options = {
	world: World,
	output: Output,
	shouldStop: () -> boolean, -- true once the run was cancelled (long actions check it)
	isUnlocked: (feature: string) -> boolean,
	simulate: Simulator?, -- nil inside a simulation (no nested simulations)
	-- live runs only: the hold was unloaded at the charger (TutorialService watches for Hay)
	onUnload: ((moved: { [string]: number }, total: number) -> ())?,
}

-- Live statistics of one run (simulate() reports `harvested`).
export type RunInfo = {
	harvested: number, -- items put into the cargo hold by harvest() and dig()
	actions: number,
}

local DRONE = GameConfig.Drone
local STATIONS = GameConfig.Stations
local THROTTLE = DRONE.Throttle
local NO_ENERGY = string.format(
	"Battery empty! Fly back to the Charging Station at (%d, %d) and call charge().",
	STATIONS.charger.x,
	STATIONS.charger.y
)
local CARGO_FULL = string.format(
	"The cargo hold is full! Unload at the Charging Station (%d, %d) or deposit() at the Factory (%d, %d).",
	STATIONS.charger.x,
	STATIONS.charger.y,
	STATIONS.factory.x,
	STATIONS.factory.y
)

local DroneAPI = {}

function DroneAPI.create(options: Options): ({ [string]: BuiltinImpl }, RunInfo)
	local world, output = options.world, options.output
	local drone = world.drone
	local info: RunInfo = { harvested = 0, actions = 0 }
	local throttle = THROTTLE.Default
	local startTime = world:now()

	local function stats(): Tech.DroneStats
		return world:stats()
	end

	-- Seconds an action takes: base time / (tech speed * Overclock * throttle).
	local function duration(kind: string): number
		local speed = stats().speedMultiplier * world:speedPerk() * throttle
		return (DRONE.ActionTimes :: any)[kind] / speed
	end

	-- A failed action: explain (optional), still cost time, return False to the program.
	local function fail(message: string?): boolean
		if message ~= nil then
			output.hint(message)
		end
		world:wait(DRONE.ActionTimes.failed)
		return false
	end

	local function spendEnergy(kind: string): boolean
		local cost = ((DRONE.EnergyCosts :: any)[kind] :: number) * throttle
		if drone.battery < cost then
			return false
		end
		drone.battery -= cost
		return true
	end

	local function tileHere(): TileData?
		return world:tileAt(drone.x, drone.y)
	end

	local function noSoilMessage(): string
		local station = world:station()
		local def = if station ~= nil then (STATIONS :: any)[station] else nil
		if def ~= nil then
			return "There's no soil here - the drone is at the " .. def.name .. "."
		end
		return "There's no soil here."
	end

	local function unloadAtCharger()
		local data = world:data()
		if data == nil then
			return
		end
		local moved, total = Economy.unloadCargo(data)
		local onUnload = options.onUnload
		if total > 0 and onUnload ~= nil then
			onUnload(moved, total)
		end
		if total > 0 then
			world:replicate()
			output.info(
				string.format("Unloaded %d item%s into the silo.", total, if total == 1 then "" else "s")
			)
		end
	end

	local api: { [string]: BuiltinImpl } = {}

	------------------------------------------------------------------ movement
	local function move(dx: number, dy: number): BuiltinImpl
		return function(_args: { any }): (any, string?)
			if not world:alive() then
				return false
			end
			info.actions += 1
			local ok, reason = world:canMove(dx, dy)
			if not ok then
				return fail(reason)
			end
			local limping = not spendEnergy("move")
			local seconds = duration("move") * (if limping then DRONE.LimpSlowdown else 1)
			world:moveDrone(dx, dy, seconds)
			if limping then
				output.hint("Battery empty - the drone is crawling. " .. NO_ENERGY)
			end
			if world:station() == "charger" then
				unloadAtCharger()
				world:publish()
			end
			world:wait(seconds) -- the client's TweenService tween runs during this wait
			return true
		end
	end
	api.move_up = move(0, 1)
	api.move_down = move(0, -1)
	api.move_left = move(-1, 0)
	api.move_right = move(1, 0)

	------------------------------------------------------------------ farming
	api.plant = function(args: { any }): (any, string?)
		local cropId = args[1] :: string
		local crop = CropConfig.Crops[cropId]
		if crop == nil then
			local suggestion = Suggest.closest(cropId, CropConfig.Plantable)
			local hint = if suggestion ~= nil then string.format(' Did you mean "%s"?', suggestion) else ""
			return nil, string.format('Unknown crop "%s".%s', cropId, hint)
		end
		if crop.wild == true then
			return nil, string.format("%s grows by itself - you can't plant it.", crop.displayName)
		end
		if not options.isUnlocked("crop:" .. cropId) then
			return nil, Tech.lockedMessage("crop:" .. cropId)
		end
		if not world:alive() then
			return false
		end
		info.actions += 1
		local tile = tileHere()
		if tile == nil then
			return fail(noSoilMessage())
		end
		if not Growth.isFree(tile) then
			return fail("This tile already has a crop on it.")
		end
		if not spendEnergy("plant") then
			return fail(NO_ENERGY)
		end
		world:plant(tile, cropId)
		world:publish()
		world:wait(duration("plant"))
		return true
	end

	api.water = function(_args: { any }): (any, string?)
		if not world:alive() then
			return false
		end
		info.actions += 1
		local tile = tileHere()
		if tile == nil then
			return fail(noSoilMessage())
		end
		local crop = if tile.crop ~= nil then CropConfig.Crops[tile.crop] else nil
		local growing = tile.state == "planted" or tile.state == "growing"
		if crop ~= nil and crop.noWater == true and growing then
			return fail(crop.displayName .. " never needs water.")
		end
		if not growing then
			return fail("There's no growing crop here to water.")
		end
		if tile.watered then
			return fail("This crop is already watered.")
		end
		local cost = world:weather().waterCost
		if drone.water < cost then
			return fail("The water tank is empty. Refill it at the Charging Station with charge().")
		end
		if not spendEnergy("water") then
			return fail(NO_ENERGY)
		end
		drone.water -= cost
		world:water(tile)
		-- Watering Cans: one pour also reaches the tiles around it.
		local radius = stats().waterRadius
		if radius > 0 then
			for ox = -radius, radius do
				for oy = -radius, radius do
					local distance = math.abs(ox) + math.abs(oy)
					if distance > 0 and distance <= radius then
						local other = world:tileAt(tile.x + ox, tile.y + oy)
						if other ~= nil and not other.watered and Growth.acceptsWater(other) then
							world:water(other)
						end
					end
				end
			end
		end
		world:publish()
		world:wait(duration("water"))
		return true
	end

	api.harvest = function(_args: { any }): (any, string?)
		if not world:alive() then
			return false
		end
		info.actions += 1
		local data = world:data()
		local tile = tileHere()
		if data == nil or tile == nil then
			return fail("There's no soil here to harvest.")
		end
		if tile.state == "empty" then
			return fail("There's nothing to harvest here.")
		end

		local ready = tile.state == "ready"
		local crop = CropConfig.Crops[tile.crop or ""]
		local amount = 0
		local capacity = stats().cargoCapacity
		if ready and crop ~= nil then
			amount = math.max(1, math.floor(crop.yield * world:yieldMultiplier()))
			if Economy.cargoTotal(data) >= capacity then
				return fail(CARGO_FULL)
			end
		end
		if not spendEnergy("harvest") then
			return fail(NO_ENERGY)
		end

		world:clearTile(tile)
		if ready and crop ~= nil then
			local added = Economy.addToCargo(data, crop.currency, amount, capacity)
			info.harvested += added
			world:addCropsHarvested(added)
			if added < amount then
				output.hint("The cargo hold filled up - part of that harvest didn't fit.")
			end
			local energy = crop.energyOnHarvest
			if energy ~= nil and energy > 0 then
				drone.battery = math.min(stats().batteryCapacity, drone.battery + energy)
			end
		elseif crop ~= nil and crop.square ~= nil then
			output.hint(
				string.format(
					"harvest() destroyed a %s that was waiting for its square: %ss only ripen in a full %d x %d of them.",
					string.lower(crop.displayName),
					string.lower(crop.displayName),
					crop.square,
					crop.square
				)
			)
		elseif crop == nil or crop.wild ~= true then
			output.hint("harvest() destroyed a crop that wasn't ready yet. Check can_harvest() first!")
		end
		world:publish()
		world:wait(duration("harvest"))
		return ready
	end

	api.dig = function(_args: { any }): (any, string?)
		if not world:alive() then
			return false
		end
		info.actions += 1
		local data = world:data()
		local tile = tileHere()
		if data == nil or tile == nil then
			return fail(noSoilMessage())
		end
		if tile.state ~= "empty" then
			return fail("dig() only works on bare soil - harvest what's growing here first.")
		end
		if Growth.isExhausted(tile) then
			return fail(
				string.format(
					"This soil was dug up recently - try another tile (it recovers in about %d s).",
					math.ceil(tile.exhausted or 0)
				)
			)
		end
		local capacity = stats().cargoCapacity
		if Economy.cargoTotal(data) >= capacity then
			return fail(CARGO_FULL)
		end
		if not spendEnergy("dig") then
			return fail(NO_ENERGY)
		end
		-- Every dig exhausts the tile, found or not (Growth.exhaust; the live farm publishes it).
		world:exhaust(tile, GameConfig.Dig.ExhaustSeconds)
		local found = world:random() < GameConfig.Dig.Chance
		if found then
			local added = Economy.addToCargo(data, GameConfig.Dig.currency, GameConfig.Dig.yield, capacity)
			info.harvested += added
			if added > 0 then
				output.info("The drone dug up a fossil!")
			end
		end
		world:publish()
		world:wait(duration("dig"))
		return found
	end

	------------------------------------------------------------------ stations
	api.charge = function(_args: { any }): (any, string?)
		if not world:alive() then
			return false
		end
		info.actions += 1
		if world:station() ~= "charger" then
			return fail(
				string.format(
					"charge() only works at the Charging Station (%d, %d).",
					STATIONS.charger.x,
					STATIONS.charger.y
				)
			)
		end
		-- The hold is banked here too, not only when a move ARRIVES: a drone that is already on
		-- the charger (a rejoin with a saved hold) would otherwise keep it full (BUG-10).
		unloadAtCharger()
		local s = stats()
		drone.water = s.waterCapacity
		local total = math.max(DRONE.ActionTimes.charge, (s.batteryCapacity - drone.battery) / s.chargeRate)
		-- Charge in small steps: the HUD fills up smoothly and Stop stays responsive.
		local elapsed = 0
		while elapsed < total do
			local step = math.min(0.25, total - elapsed)
			world:wait(step)
			elapsed += step
			if not world:alive() or options.shouldStop() then
				break
			end
			drone.battery = math.min(s.batteryCapacity, drone.battery + s.chargeRate * step)
			world:publish()
		end
		if elapsed >= total then
			drone.battery = s.batteryCapacity
		end
		world:publish()
		return true
	end

	api.deposit = function(_args: { any }): (any, string?)
		if not world:alive() then
			return false
		end
		info.actions += 1
		if world:station() ~= "factory" then
			return fail(
				string.format(
					"deposit() only works at the Factory (%d, %d).",
					STATIONS.factory.x,
					STATIONS.factory.y
				)
			)
		end
		local data = world:data()
		if data == nil or Economy.cargoTotal(data) == 0 then
			return fail("The drone isn't carrying anything to deposit.")
		end
		if Economy.depositable(data) == 0 then
			return fail("The Factory can't use Hay - unload it at the Charging Station instead.")
		end
		if not spendEnergy("deposit") then
			return fail(NO_ENERGY)
		end
		local gained, used = Economy.depositCargo(data)
		world:replicate()
		world:publish()
		output.info(string.format("Factory processed %d items into %d Biomass.", used, gained))
		world:wait(duration("deposit"))
		return true
	end

	api.refine = function(_args: { any }): (any, string?)
		if not world:alive() then
			return false
		end
		info.actions += 1
		if world:station() ~= "factory" then
			return fail(
				string.format(
					"refine() only works at the Factory (%d, %d).",
					STATIONS.factory.x,
					STATIONS.factory.y
				)
			)
		end
		local data = world:data()
		if data == nil or (data.currencies.biomass or 0) < GameConfig.Factory.BiomassPerBiofuel then
			return fail(
				string.format(
					"The Bioreactor needs at least %d Biomass.",
					GameConfig.Factory.BiomassPerBiofuel
				)
			)
		end
		if not spendEnergy("refine") then
			return fail(NO_ENERGY)
		end
		local gained, used = Economy.refine(data, GameConfig.Factory.MaxRefineBatches)
		world:replicate()
		world:publish() -- the battery changed (BUG-09)
		output.info(string.format("Bioreactor turned %d Biomass into %d Biofuel.", used, gained))
		world:wait(duration("refine"))
		return true
	end

	------------------------------------------------------------------ sensors
	api.can_harvest = function(_args: { any }): (any, string?)
		local tile = tileHere()
		return tile ~= nil and tile.state == "ready"
	end
	api.is_empty = function(_args: { any }): (any, string?)
		local tile = tileHere()
		return tile ~= nil and Growth.isFree(tile)
	end
	api.get_x = function(_args: { any }): (any, string?)
		return drone.x
	end
	api.get_y = function(_args: { any }): (any, string?)
		return drone.y
	end
	api.get_size = function(_args: { any }): (any, string?)
		return world:size()
	end
	api.get_battery = function(_args: { any }): (any, string?)
		return math.floor(drone.battery)
	end
	api.get_water = function(_args: { any }): (any, string?)
		return drone.water
	end
	api.get_weather = function(_args: { any }): (any, string?)
		return world:weather().name
	end
	api.get_cargo = function(_args: { any }): (any, string?)
		local data = world:data()
		return if data ~= nil then Economy.cargoTotal(data) else 0
	end
	api.get_time = function(_args: { any }): (any, string?)
		return math.floor((world:now() - startTime) * 100 + 0.5) / 100
	end

	------------------------------------------------------------------ utility
	api.print = function(args: { any }): (any, string?)
		local parts = table.create(#args)
		for i, value in args do
			parts[i] = Values.display(value, GameConfig.Script.MaxOutputLength)
		end
		output.print(table.concat(parts, " "))
		return nil
	end

	api.set_speed = function(args: { any }): (any, string?)
		local value = args[1] :: number
		if value ~= value or value < THROTTLE.Min or value > THROTTLE.Max then
			return nil,
				string.format(
					"set_speed() needs a number from %s to %s, but got %s.",
					Values.formatNumber(THROTTLE.Min),
					Values.formatNumber(THROTTLE.Max),
					Values.formatNumber(value)
				)
		end
		throttle = value
		return nil
	end

	api.random = function(_args: { any }): (any, string?)
		return world:random()
	end

	api.get_cost = function(args: { any }): (any, string?)
		local node = TechTree.Nodes[args[1] :: string]
		if node == nil then
			return nil -- None: unknown research
		end
		return table.clone(node.cost)
	end

	api.simulate = function(args: { any }): (any, string?)
		local simulator = options.simulate
		if simulator == nil then
			return nil, "simulate() can't run inside a simulation."
		end
		local seconds = args[2] :: number
		local maxSeconds = GameConfig.Simulate.MaxSeconds
		if seconds ~= seconds or seconds < 1 or seconds > maxSeconds then
			return nil,
				string.format(
					"simulate() can run 1 to %d seconds, but got %s.",
					maxSeconds,
					Values.formatNumber(seconds)
				)
		end
		-- A simulation runs on its own virtual clock, so on the REAL world it would take no time
		-- at all: `while True: simulate(...)` could compile and run hundreds of farms a second.
		-- Every call (failed ones too) therefore takes at least MinRealSeconds here.
		local started = world:now()
		local harvested, err = simulator(args[1] :: string, seconds)
		local spent = world:now() - started
		local minimum = GameConfig.Simulate.MinRealSeconds
		if spent < minimum and not options.shouldStop() then
			world:wait(minimum - spent)
		end
		if harvested == nil then
			return nil, err or "The simulation failed."
		end
		return harvested
	end

	-- Defence in depth: locked builtins don't exist for this run at all.
	for name in api do
		if not options.isUnlocked(name) then
			api[name] = nil
		end
	end
	return api, info
end

return DroneAPI
