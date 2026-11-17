--!strict
--[[
	Growth
	======
	Pure crop-growth rules, shared by the live farm (GridService growth tick) and the virtual
	farm used by simulate() (DroneRuntime.SimWorld), so a simulation grows crops exactly like
	the real thing.

	TILE LIFECYCLE
	  empty --(bare for Grass.RegrowDelay s)--> planted (wild grass)
	  empty --plant()--> planted --(SproutProgress)--> growing --(progress 1)--> ready
	  any   --harvest()/dig()--> empty

	RATE
	  progress += dt * weatherGrowth * growthBoost * wetness / crop.growSeconds
	    weatherGrowth = crop.weatherGrowth[weather] if the crop defines it, else weather.growth
	    wetness       = Grid.WateredGrowthMultiplier when watered (never for noWater crops)
	  Rain (weather.autoWater) SOAKS crops that accept water: each one is watered after
	  GameConfig.Grid.RainSoakSeconds of rain (tile.soak), so it doesn't replace water().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CropConfig = require(ReplicatedStorage.Shared.Config.CropConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

export type TileState = "empty" | "planted" | "growing" | "ready"

-- The growth-relevant part of a tile. GridService tiles add their Part on top of this.
export type TileData = {
	x: number,
	y: number,
	state: TileState,
	crop: string?,
	progress: number,
	watered: boolean,
	bareTime: number, -- seconds this tile has been bare soil (wild grass regrowth)
	exhausted: number?, -- seconds left of dig exhaustion (nothing grows / plants / digs)
	soak: number?, -- seconds of rain this dry crop has had (watered at RainSoakSeconds)
}

export type Weather = {
	name: string,
	growth: number,
	waterCost: number,
	autoWater: boolean,
}

export type Env = {
	weather: Weather,
	growthBoost: number,
}

-- What a tick changed (the live farm republishes attributes only for these).
-- `exhausted`: dig exhaustion just ended (the tile's Exhausted attribute turns false).
export type Change = { state: boolean, watered: boolean, progress: boolean, exhausted: boolean }

local GRID = GameConfig.Grid
local GRASS = GameConfig.Grass

local Growth = {}

function Growth.newTile(x: number, y: number, grown: boolean): TileData
	local tile: TileData = {
		x = x,
		y = y,
		state = "empty",
		crop = nil,
		progress = 0,
		watered = false,
		bareTime = 0,
		exhausted = 0,
	}
	if grown then
		Growth.growFully(tile, CropConfig.WildCrop)
	end
	return tile
end

-- True if the tile holds wild grass (any stage).
function Growth.isWild(tile: TileData): boolean
	local crop = if tile.crop ~= nil then CropConfig.Crops[tile.crop] else nil
	return crop ~= nil and crop.wild == true and tile.state ~= "empty"
end

-- True while a recent dig() has exhausted the soil (GameConfig.Dig.ExhaustSeconds).
function Growth.isExhausted(tile: TileData): boolean
	return (tile.exhausted or 0) > 0
end

--[[
	DIG EXHAUSTION (shared by the live farm and simulate()): after any dig the tile stays
	bare soil for `seconds`. While exhausted: wild grass doesn't regrow (bareTime stays 0),
	plant() and dig() are refused (isFree is false) and is_empty() is False.
]]
function Growth.exhaust(tile: TileData, seconds: number)
	tile.exhausted = math.max(tile.exhausted or 0, seconds)
	tile.bareTime = 0
end

-- True when nothing the PLAYER planted is on the tile (bare soil or wild grass) and the soil
-- isn't exhausted.
function Growth.isFree(tile: TileData): boolean
	return not Growth.isExhausted(tile) and (tile.state == "empty" or Growth.isWild(tile))
end

function Growth.acceptsWater(tile: TileData): boolean
	local crop = if tile.crop ~= nil then CropConfig.Crops[tile.crop] else nil
	return crop ~= nil and crop.noWater ~= true and (tile.state == "planted" or tile.state == "growing")
end

-- Rain doesn't water on planting (it soaks crops over time: advance), so no weather here.
function Growth.plant(tile: TileData, cropId: string)
	tile.crop = cropId
	tile.state = "planted"
	tile.progress = 0
	tile.bareTime = 0
	tile.watered = false
	tile.soak = 0 -- rain soaks it over time (advance), it isn't watered on planting
end

function Growth.growFully(tile: TileData, cropId: string)
	tile.crop = cropId
	tile.state = "ready"
	tile.progress = 1
	tile.bareTime = 0
	tile.watered = false
end

function Growth.clear(tile: TileData)
	tile.crop = nil
	tile.state = "empty"
	tile.progress = 0
	tile.bareTime = 0
	tile.watered = false
end

--[[
	SQUARE CROPS (pumpkins, CropConfig.square = 2): RULE
	  A square crop grows to progress 1 on its own but stays "growing". It ripens only when it
	  is part of a COMPLETE N x N block whose every tile holds that crop at progress 1; then the
	  whole block turns "ready" together. A lone tile, or a block with a gap, never ripens.
	  Breaking a forming block (harvesting / clearing one of its tiles before it ripens) just
	  removes that tile: the others STAY fully grown and waiting, nothing resets, and they ripen
	  as soon as a replanted tile completes the block again. Ready tiles stay ready.
	Call settleSquares after advancing a field (GridService's tick, SimWorld.wait). It returns
	the tiles that just ripened (the live farm republishes them).
]]
function Growth.isWaitingForSquare(tile: TileData): boolean
	local crop = if tile.crop ~= nil then CropConfig.Crops[tile.crop] else nil
	return crop ~= nil and crop.square ~= nil and tile.state ~= "ready" and tile.state ~= "empty"
end

function Growth.settleSquares(size: number, tileAt: (x: number, y: number) -> TileData?): { TileData }
	local ripened: { TileData } = {}
	for y = 0, size - 1 do
		for x = 0, size - 1 do
			local corner = tileAt(x, y)
			local crop = if corner ~= nil and corner.crop ~= nil then CropConfig.Crops[corner.crop] else nil
			local n = if crop ~= nil then crop.square else nil
			if corner == nil or n == nil or x + n > size or y + n > size then
				continue
			end
			-- Is the n x n block starting here complete and fully grown?
			local block: { TileData } = {}
			local complete = true
			for dy = 0, n - 1 do
				for dx = 0, n - 1 do
					local tile = tileAt(x + dx, y + dy)
					if
						tile == nil
						or tile.crop ~= corner.crop
						or tile.state == "empty"
						or tile.progress < 1
					then
						complete = false
					else
						table.insert(block, tile)
					end
				end
			end
			if complete then
				for _, tile in block do
					if tile.state ~= "ready" then
						tile.state = "ready"
						table.insert(ripened, tile)
					end
				end
			end
		end
	end
	return ripened
end

-- Advances one tile by `dt` seconds. Never yields.
function Growth.advance(tile: TileData, dt: number, env: Env): Change
	local change: Change = { state = false, watered = false, progress = false, exhausted = false }
	if dt <= 0 then
		return change
	end

	if Growth.isExhausted(tile) then
		tile.exhausted = math.max(0, (tile.exhausted or 0) - dt)
		change.exhausted = tile.exhausted <= 0
		if tile.state == "empty" then
			tile.bareTime = 0 -- dug-up soil stays bare until it recovers
			return change
		end
	end
	if tile.state == "empty" then
		tile.bareTime += dt
		if tile.bareTime >= GRASS.RegrowDelay then
			Growth.plant(tile, CropConfig.WildCrop)
			change.state = true
			change.watered = true
			change.progress = true
		end
		return change
	end
	if tile.state ~= "planted" and tile.state ~= "growing" then
		return change
	end

	local crop = CropConfig.Crops[tile.crop or ""]
	if crop == nil then
		return change
	end
	if env.weather.autoWater and not tile.watered and crop.noWater ~= true then
		tile.soak = (tile.soak or 0) + dt
		if tile.soak >= GRID.RainSoakSeconds then
			tile.watered = true
			tile.soak = 0
			change.watered = true
		end
	end

	local weatherGrowth = env.weather.growth
	local override = crop.weatherGrowth
	if override ~= nil and override[env.weather.name] ~= nil then
		weatherGrowth = override[env.weather.name]
	end
	local wetness = if tile.watered and crop.noWater ~= true then GRID.WateredGrowthMultiplier else 1
	local rate = weatherGrowth * env.growthBoost * wetness / crop.growSeconds
	local before = tile.progress
	tile.progress = math.min(1, tile.progress + dt * rate)
	change.progress = tile.progress ~= before

	if tile.progress >= 1 then
		if crop.square ~= nil then
			-- Fully grown, but a square crop waits for its square (settleSquares) to ripen.
			if tile.state == "planted" then
				tile.state = "growing"
				change.state = true
			end
		else
			tile.state = "ready"
			change.state = true
		end
	elseif tile.state == "planted" and tile.progress >= GRID.SproutProgress then
		tile.state = "growing"
		change.state = true
	end
	return change
end

return Growth
