--!strict
--[[
	LiveWorld
	=========
	The World (DroneRuntime.World) for a player's REAL plot: a thin adapter over GridService
	(tiles, stations, drone attributes), DataService (the session-locked profile data),
	WeatherService and GamepassService. wait() is task.wait - real time passes while the
	client tweens the drone from the published attributes. It waits in slices of at most
	WAIT_SLICE seconds and returns early once shouldStop() is true, so Stop / a new run never
	waits out a long action (a limping 3.2 s move, a full charge, ...).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Services = script.Parent.Parent.Services
local DataService = require(Services.DataService)
local GamepassService = require(Services.GamepassService)
local GridService = require(Services.GridService)
local WeatherService = require(Services.WeatherService)
local WorldTypes = require(script.Parent.World)

type World = WorldTypes.World
type TileData = WorldTypes.TileData

local WAIT_SLICE = 0.1

local LiveWorld = {}

function LiveWorld.new(player: Player, plot: GridService.Plot, shouldStop: (() -> boolean)?): World
	local rng = Random.new()
	local world: World = {
		isSimulation = false,
		drone = plot.drone,

		alive = function(_self: World): boolean
			return not plot.destroyed and player.Parent ~= nil
		end,
		wait = function(_self: World, seconds: number)
			local deadline = os.clock() + math.max(0, seconds)
			while true do
				local left = deadline - os.clock()
				if left <= 0 or (shouldStop ~= nil and shouldStop()) then
					return
				end
				task.wait(math.min(WAIT_SLICE, left))
			end
		end,
		now = function(_self: World): number
			return os.clock()
		end,
		random = function(_self: World): number
			return rng:NextNumber()
		end,

		stats = function(_self: World): Tech.DroneStats
			return GridService:GetStats(player)
		end,
		speedPerk = function(_self: World): number
			return GamepassService:GetPerks(player).speedMultiplier
		end,
		yieldMultiplier = function(_self: World): number
			local _, yieldBoost = DataService:GetBoostMultipliers(player)
			return GamepassService:GetPerks(player).yieldMultiplier * yieldBoost
		end,
		weather = function(_self: World): WorldTypes.Weather
			return WeatherService:GetFor(player) -- this plot's own weather
		end,

		size = function(_self: World): number
			return plot.size
		end,
		station = function(_self: World): string?
			return GridService:GetStation(plot)
		end,
		tileAt = function(_self: World, x: number, y: number): TileData?
			return GridService:GetTile(plot, x, y)
		end,
		canMove = function(_self: World, dx: number, dy: number): (boolean, string?)
			return GridService:CanMove(plot, dx, dy)
		end,
		moveDrone = function(_self: World, dx: number, dy: number, duration: number)
			GridService:MoveDrone(plot, dx, dy, duration)
		end,

		plant = function(_self: World, tile: TileData, cropId: string)
			GridService:PlantTile(tile :: any, cropId)
		end,
		water = function(_self: World, tile: TileData)
			GridService:WaterTile(tile :: any)
		end,
		clearTile = function(_self: World, tile: TileData)
			GridService:ClearTile(tile :: any)
		end,

		data = function(_self: World): WorldTypes.EconomyData?
			return DataService:GetData(player) :: any
		end,
		addCropsHarvested = function(_self: World, count: number)
			DataService:AddCropsHarvested(player, count)
		end,
		publish = function(_self: World)
			GridService:PublishDrone(plot)
		end,
		replicate = function(_self: World)
			DataService:Replicate(player)
		end,
	}
	return world
end

return LiveWorld
