--!strict
--[[
	FieldKeeper
	===========
	Hands each player's LIVE field to their saved data (PlayerData.field). Pure: GridService
	injects how to reach the data (DataService:GetData) and the clock.

	  attach(player, tilesOf)   createPlot: the plot's tiles from now on (a getter, because
	                            Grid Expansion swaps the tiles table)
	  beforeSave(player, data)  DataService:OnBeforeSave hook: autosave, leave, shutdown
	  detach(player)            removePlot: writes a final snapshot (if the data is still loaded),
	                            then forgets the player

	WHY (docs/BUGS.md BUG-02): DataService and GridService both listen to PlayerRemoving, and
	Roblox doesn't guarantee which handler runs first. If the plot were removed first, the
	leave-save would carry the last autosave's field (up to 90 s old). With detach() writing its
	own snapshot, the saved field is fresh in BOTH orders:
	  DataService first: beforeSave snapshots the live plot; detach finds the data released.
	  GridService first: detach snapshots into the still-loaded data; beforeSave finds nothing.
]]

local FieldSave = require(script.Parent.FieldSave)
local Growth = require(script.Parent.Growth)

type TileData = Growth.TileData

export type FieldKeeper = {
	attach: (self: FieldKeeper, player: any, tilesOf: () -> { TileData }) -> (),
	beforeSave: (self: FieldKeeper, player: any, data: any) -> (),
	detach: (self: FieldKeeper, player: any) -> (),
	isAttached: (self: FieldKeeper, player: any) -> boolean,
}

local FieldKeeper = {}

function FieldKeeper.new(getData: (player: any) -> any?, now: () -> number): FieldKeeper
	local fields: { [any]: () -> { TileData } } = {}

	local function write(player: any, data: any)
		local tilesOf = fields[player]
		if tilesOf ~= nil and data ~= nil then
			data.field = FieldSave.snapshot(tilesOf(), now())
		end
	end

	return {
		attach = function(_self: FieldKeeper, player: any, tilesOf: () -> { TileData })
			fields[player] = tilesOf
		end,
		beforeSave = function(_self: FieldKeeper, player: any, data: any)
			write(player, data)
		end,
		detach = function(_self: FieldKeeper, player: any)
			write(player, getData(player))
			fields[player] = nil
		end,
		isAttached = function(_self: FieldKeeper, player: any): boolean
			return fields[player] ~= nil
		end,
	}
end

return FieldKeeper
