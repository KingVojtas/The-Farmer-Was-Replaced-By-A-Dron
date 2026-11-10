--!strict
--[[
	SimWorld
	========
	The World behind simulate(): a throwaway, in-memory copy of a plot with a VIRTUAL clock.

	  * wait(seconds) advances the virtual clock and grows every crop by that much
	    (Progression.Growth - the same rules as the live farm), instantly.
	  * Its economy table is a copy: deposits/refines/harvests change nothing real.
	  * It has no access to DataService, Instances, remotes or the real drone. A simulation can
	    therefore never grant rewards, spend currency or move anything players can see.
	  * alive() turns false once `duration` virtual seconds have passed; ScriptService also
	    cancels the simulated program at that moment.
	  * Every virtual second inside wait() it calls config.yield (if any) and stops at once
	    when config.shouldStop() is true, so even a 600 s simulation can't hitch the server
	    or outlive a Stop / a new run (ScriptService also task.cancel()s the whole run).

	The CPU cost of a simulation is still bounded: the simulated program runs on the same
	Interpreter with the same per-step throttle (task.wait) and a hard step budget.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Field = require(script.Parent.Parent.Progression.Field)
local Growth = require(script.Parent.Parent.Progression.Growth)
local WorldTypes = require(script.Parent.World)

type World = WorldTypes.World
type TileData = WorldTypes.TileData

export type Config = {
	size: number,
	tiles: { TileData }, -- copied, never mutated
	drone: WorldTypes.DroneState, -- copied
	stats: Tech.DroneStats,
	speedPerk: number,
	yieldMultiplier: number,
	growthBoost: number,
	weather: WorldTypes.Weather,
	currencies: { [string]: number }, -- copied (refine() reads Biomass)
	random: () -> number,
	duration: number, -- virtual seconds the simulation may run
	yield: (() -> ())?, -- called every virtual second inside wait() (may task.wait)
	shouldStop: (() -> boolean)?, -- checked every virtual second: true = stop waiting now
}

export type SimWorld = World & {
	time: number,
	harvestedTotal: number,
	finished: (self: SimWorld) -> boolean,
}

local MAX_GROWTH_STEP = 1 -- seconds per growth sub-step (keeps grass regrowth timing exact enough)

local SimWorld = {}

local function copyTile(tile: TileData): TileData
	return {
		x = tile.x,
		y = tile.y,
		state = tile.state,
		crop = tile.crop,
		progress = tile.progress,
		watered = tile.watered,
		bareTime = tile.bareTime,
		exhausted = tile.exhausted,
		soak = tile.soak,
	}
end

function SimWorld.new(config: Config): SimWorld
	local tiles: { TileData } = table.create(#config.tiles)
	for i, tile in config.tiles do
		tiles[i] = copyTile(tile)
	end
	local data: WorldTypes.EconomyData = {
		currencies = table.clone(config.currencies),
		cargo = {},
		factoryBuffer = 0,
	}
	local env: Growth.Env = { weather = config.weather, growthBoost = config.growthBoost }
	local size = config.size

	local function tileAt(x: number, y: number): TileData?
		if not Field.inField(size, x, y) then
			return nil
		end
		return tiles[Field.index(size, x, y)]
	end

	local world: SimWorld
	world = {
		isSimulation = true,
		drone = {
			x = config.drone.x,
			y = config.drone.y,
			battery = config.drone.battery,
			water = config.drone.water,
		},
		time = 0,
		harvestedTotal = 0,

		finished = function(self: SimWorld): boolean
			return self.time >= config.duration
		end,
		alive = function(_self: World): boolean
			return world.time < config.duration
		end,
		wait = function(_self: World, seconds: number)
			local remaining = math.max(0, seconds)
			while remaining > 0 do
				-- At least once per virtual second: stop if cancelled, then let the server breathe.
				local stop = config.shouldStop
				if stop ~= nil and stop() then
					return
				end
				local dt = math.min(MAX_GROWTH_STEP, remaining)
				remaining -= dt
				world.time += dt
				for _, tile in tiles do
					Growth.advance(tile, dt, env)
				end
				Growth.settleSquares(size, tileAt) -- pumpkins ripen in complete 2 x 2s (same rule live)
				local yield = config.yield
				if yield ~= nil then
					yield()
				end
			end
		end,
		now = function(_self: World): number
			return world.time
		end,
		random = function(_self: World): number
			return config.random()
		end,

		stats = function(_self: World): Tech.DroneStats
			return config.stats
		end,
		speedPerk = function(_self: World): number
			return config.speedPerk
		end,
		yieldMultiplier = function(_self: World): number
			return config.yieldMultiplier
		end,
		weather = function(_self: World): WorldTypes.Weather
			return config.weather
		end,

		size = function(_self: World): number
			return size
		end,
		station = function(_self: World): string?
			return Field.stationAt(world.drone.x, world.drone.y)
		end,
		tileAt = function(_self: World, x: number, y: number): TileData?
			if not Field.inField(size, x, y) then
				return nil
			end
			return tiles[Field.index(size, x, y)]
		end,
		canMove = function(_self: World, dx: number, dy: number): (boolean, string?)
			return Field.canMove(size, world.drone.x, world.drone.y, dx, dy)
		end,
		moveDrone = function(_self: World, dx: number, dy: number, _duration: number)
			world.drone.x += dx
			world.drone.y += dy
		end,

		plant = function(_self: World, tile: TileData, cropId: string)
			Growth.plant(tile, cropId, config.weather)
		end,
		water = function(_self: World, tile: TileData)
			tile.watered = true
		end,
		clearTile = function(_self: World, tile: TileData)
			Growth.clear(tile)
		end,

		data = function(_self: World): WorldTypes.EconomyData?
			return data
		end,
		addCropsHarvested = function(_self: World, count: number)
			world.harvestedTotal += count
		end,
		publish = function(_self: World) end,
		replicate = function(_self: World) end,
	}
	return world
end

return SimWorld
