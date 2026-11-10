--!strict
--[[
	Field
	=====
	Pure coordinate rules of a plot, shared by GridService (live) and SimWorld (simulate()).

	  Field tiles are (0..size-1, 0..size-1); x grows to the right, y grows "up".
	  Stations sit just below row 0 (GameConfig.Stations):
	    Charging Station (0, -1)   Factory (1, -1)
	  The drone can stand on any tile or station. Everything else is blocked (no wrap-around).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local STATIONS = GameConfig.Stations :: { [string]: { x: number, y: number, name: string } }

local Field = {}

function Field.stationAt(x: number, y: number): string?
	for kind, station in STATIONS do
		if station.x == x and station.y == y then
			return kind
		end
	end
	return nil
end

function Field.inField(size: number, x: number, y: number): boolean
	return x >= 0 and y >= 0 and x < size and y < size
end

-- 1-based index of a tile in a plot's `tiles` array.
function Field.index(size: number, x: number, y: number): number
	return y * size + x + 1
end

function Field.canMove(size: number, x: number, y: number, dx: number, dy: number): (boolean, string?)
	local nx, ny = x + dx, y + dy
	if Field.inField(size, nx, ny) or Field.stationAt(nx, ny) ~= nil then
		return true
	end
	return false,
		string.format("The drone can't fly to (%d, %d) - that's past the edge of the field.", nx, ny)
end

return Field
