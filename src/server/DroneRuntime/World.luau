--!strict
--[[
	World
	=====
	The interface DroneAPI talks to. Two implementations:

	  LiveWorld  - the player's real plot: GridService tiles, DataService profile data,
	               WeatherService, GamepassService. wait() = task.wait (real time; the client
	               tweens the drone meanwhile).
	  SimWorld   - simulate(): an in-memory copy of the plot with a VIRTUAL clock. wait()
	               advances that clock and grows the crops (Progression.Growth) instantly.
	               It has no access to DataService or Instances at all, so a simulation can
	               never grant rewards or move the real drone.

	Because DroneAPI only depends on this interface, the exact same builtin code runs in both,
	and the offline tests drive DroneAPI through SimWorld.

	Rules for implementations: every method except wait() is synchronous (never yields), and
	query methods never change state.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Growth = require(script.Parent.Parent.Progression.Growth)

export type TileData = Growth.TileData
export type Weather = Growth.Weather

export type DroneState = {
	x: number,
	y: number,
	battery: number,
	water: number,
}

-- The parts of PlayerData the economy functions touch.
export type EconomyData = {
	currencies: { [string]: number },
	cargo: { [string]: number },
	factoryBuffer: number,
}

export type World = {
	isSimulation: boolean,
	drone: DroneState,

	alive: (self: World) -> boolean, -- false once the plot/player is gone (or the sim ended)
	wait: (self: World, seconds: number) -> (),
	now: (self: World) -> number, -- seconds (any origin; only differences matter)
	random: (self: World) -> number, -- [0, 1)

	stats: (self: World) -> Tech.DroneStats,
	speedPerk: (self: World) -> number, -- gamepass speed multiplier (Overclock)
	yieldMultiplier: (self: World) -> number, -- gamepass * timed boost
	weather: (self: World) -> Weather,

	size: (self: World) -> number,
	station: (self: World) -> string?, -- station kind under the drone, if any
	tileAt: (self: World, x: number, y: number) -> TileData?, -- field tiles only
	canMove: (self: World, dx: number, dy: number) -> (boolean, string?),
	moveDrone: (self: World, dx: number, dy: number, duration: number) -> (),

	plant: (self: World, tile: TileData, cropId: string) -> (),
	water: (self: World, tile: TileData) -> (),
	clearTile: (self: World, tile: TileData) -> (),

	data: (self: World) -> EconomyData?,
	addCropsHarvested: (self: World, count: number) -> (),
	publish: (self: World) -> (), -- drone state (battery/water/cargo) changed
	replicate: (self: World) -> (), -- currencies changed
}

return {}
