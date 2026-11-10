--!strict
--[[
	DroneSignals
	============
	Pure decisions behind "the drone looks like a running program" (Client PlotRenderer,
	docs/ART_BIBLE.md §4.1.1). The client never learns which builtin ran, so these infer it
	from what the server publishes. No Roblox types: the offline tests cover it.

	  statusLight(battery, max, onCharger, limping) -> { key, blink, dim }
	      key "cyan" on the charger, otherwise by charge: > 50 % "lime", 15-50 % "amber",
	      < 15 % "red" (blink = slow blink). dim = limping (moves far slower than normal).
	  isLimping(moveTime, baseMoveTime)   a move CLEARLY slower than the normal move
	  stationAt(x, y) -> "charger" | "factory" | nil
	  action(events, plantedWild, droneOverTile, raining) -> "plant" | "harvest" | "water" | nil
	      Conservative on purpose (wrong FX is worse than none): only with the drone right
	      over the tile, only ripe harvests, never wild-grass regrowth, never rain watering.
	  cellXY(value) -> x, y from a Vector2, Vector3 (x, y, 0) or any {X, Y}.
	  cellFromAttributes(droneX, droneY, drone) -> prefers the number pair.
]]

local CropTransitions = require(script.Parent.CropTransitions)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

export type StatusKey = "lime" | "amber" | "red" | "cyan"
export type Status = { key: StatusKey, blink: boolean, dim: boolean }
export type Action = "plant" | "harvest" | "water"

-- A limping move is LimpSlowdown (4x) slower; 1.75x leaves room for Servo speed upgrades.
local LIMP_FACTOR = 1.75

local DroneSignals = {}

function DroneSignals.statusLight(battery: any, max: any, onCharger: boolean, limping: boolean): Status
	if onCharger then
		return { key = "cyan", blink = false, dim = false }
	end
	local fraction = 1
	if type(battery) == "number" and type(max) == "number" and max > 0 then
		fraction = battery / max
	end
	local key: StatusKey = if fraction > 0.5 then "lime" elseif fraction >= 0.15 then "amber" else "red"
	return { key = key, blink = key == "red", dim = limping }
end

function DroneSignals.isLimping(moveTime: any, baseMoveTime: number): boolean
	return type(moveTime) == "number" and moveTime > baseMoveTime * LIMP_FACTOR
end

-- Grid cell from a published Drone attribute (Vector3 x,y,0 or legacy Vector2).
function DroneSignals.cellXY(value: any): (number?, number?)
	local kind = type(value)
	if kind ~= "table" and kind ~= "userdata" and kind ~= "vector" then
		return nil, nil
	end
	local x = (value :: any).X
	local y = (value :: any).Y
	if type(x) == "number" and type(y) == "number" then
		return x, y
	end
	return nil, nil
end

-- Prefer the number pair (always replicates). Fall back to the vector attribute.
function DroneSignals.cellFromAttributes(droneX: any, droneY: any, drone: any): (number?, number?)
	if type(droneX) == "number" and type(droneY) == "number" then
		return droneX, droneY
	end
	return DroneSignals.cellXY(drone)
end

function DroneSignals.stationAt(x: number, y: number): string?
	local stations: { [string]: { x: number, y: number } } = GameConfig.Stations :: any
	for kind, station in stations do
		if station.x == x and station.y == y then
			return kind
		end
	end
	return nil
end

function DroneSignals.action(
	events: CropTransitions.Events,
	plantedWild: boolean,
	droneOverTile: boolean,
	raining: boolean
): Action?
	if not droneOverTile then
		return nil
	end
	if events.plant and not plantedWild then
		return "plant"
	end
	if events.harvest and events.ripe then
		return "harvest"
	end
	if events.water and not raining then
		return "water"
	end
	return nil
end

return DroneSignals
