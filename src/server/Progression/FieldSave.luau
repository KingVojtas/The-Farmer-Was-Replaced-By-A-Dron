--!strict
--[[
	FieldSave
	=========
	Saving the player's field (PlayerData.field, schema v3). Pure, shared by Data.Sanitize
	(validation), Services.GridService (snapshot before every save, restore on join) and the
	offline tests.

	  PlayerData.field = { savedAt = os.time(), tiles = { entry, ... } }
	  entry = { x, y, crop, state, progress, watered, bareTime, exhausted }
	          (compact array; crop "" = none; `exhausted` = seconds of dig exhaustion left,
	          added later and optional: a 7-value entry from an older save means 0)

	RESTORE never replays growth ticks. If the player was away longer than
	GameConfig.Field.OfflineReadySeconds (2 hours), every planted / growing crop snaps to fully
	grown: "ready", except square crops (pumpkins), which stay fully grown and ripen through
	their 2 x 2 (the caller runs Growth.settleSquares). A shorter absence resumes exactly where
	the field was. Dig exhaustion IS saved and keeps counting down while you're away, so a
	rejoin can't clear it (BUG-11). Rain soak isn't saved (it lasts seconds).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CropConfig = require(ReplicatedStorage.Shared.Config.CropConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Growth = require(script.Parent.Growth)

type TileData = Growth.TileData

export type Entry = { any }
export type Saved = { savedAt: number, tiles: { Entry } }

local STATES: { [string]: boolean } = { empty = true, planted = true, growing = true, ready = true }
local MAX_BARE_TIME = 3600
local MAX_EXHAUSTED = 3600 -- far above GameConfig.Dig.ExhaustSeconds: only a sanity bound

local FieldSave = {}

-- One compact entry { x, y, crop, state, progress, watered, bareTime, exhausted } (mixed types).
local function entryOf(...: any): Entry
	return { ... }
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function FieldSave.empty(): Saved
	return { savedAt = 0, tiles = {} }
end

function FieldSave.snapshot(tiles: { TileData }, now: number): Saved
	local out: { Entry } = table.create(#tiles)
	for _, tile in tiles do
		table.insert(
			out,
			entryOf(
				tile.x,
				tile.y,
				tile.crop or "",
				tile.state,
				math.floor(tile.progress * 1000 + 0.5) / 1000,
				tile.watered,
				math.floor(math.min(tile.bareTime, MAX_BARE_TIME) * 10 + 0.5) / 10,
				math.ceil(math.min(tile.exhausted or 0, MAX_EXHAUSTED) * 10) / 10
			)
		)
	end
	return { savedAt = now, tiles = out }
end

-- Rebuilds raw saved data from scratch: only well-formed entries inside the largest field
-- survive, one per cell. Never errors on garbage.
function FieldSave.sanitize(raw: any): Saved
	local result = FieldSave.empty()
	if type(raw) ~= "table" then
		return result
	end
	if finite(raw.savedAt) and raw.savedAt > 0 then
		result.savedAt = math.floor(raw.savedAt)
	end
	if type(raw.tiles) ~= "table" then
		return result
	end
	local maxSize = GameConfig.Grid.MaxSize
	local seen: { [number]: boolean } = {}
	for _, entry in ipairs(raw.tiles) do
		if type(entry) ~= "table" or #result.tiles >= maxSize * maxSize then
			continue
		end
		local x, y, crop, state = entry[1], entry[2], entry[3], entry[4]
		if not finite(x) or not finite(y) or x % 1 ~= 0 or y % 1 ~= 0 then
			continue
		end
		if x < 0 or y < 0 or x >= maxSize or y >= maxSize or seen[y * maxSize + x] then
			continue
		end
		if type(crop) ~= "string" or (crop ~= "" and CropConfig.Crops[crop] == nil) then
			continue
		end
		if type(state) ~= "string" or STATES[state] ~= true then
			continue
		end
		if crop == "" or state == "empty" then
			crop, state = "", "empty"
		end
		local progress = if finite(entry[5]) then math.clamp(entry[5], 0, 1) else 0
		local bareTime = if finite(entry[7]) then math.clamp(entry[7], 0, MAX_BARE_TIME) else 0
		local exhausted = if finite(entry[8]) then math.clamp(entry[8], 0, MAX_EXHAUSTED) else 0
		seen[y * maxSize + x] = true
		table.insert(
			result.tiles,
			entryOf(
				x,
				y,
				crop,
				state,
				if state == "empty" then 0 else progress,
				state ~= "empty" and entry[6] == true,
				bareTime,
				exhausted
			)
		)
	end
	return result
end

-- Writes `saved` onto the live tiles (tileAt). Returns the tiles it changed.
function FieldSave.restore(
	saved: Saved,
	tileAt: (x: number, y: number) -> TileData?,
	now: number
): { TileData }
	local changed: { TileData } = {}
	local away = now - saved.savedAt
	local snap = saved.savedAt > 0 and away > GameConfig.Field.OfflineReadySeconds
	for _, entry in saved.tiles do
		local tile = tileAt(entry[1], entry[2])
		if tile == nil then
			continue -- outside the current field (e.g. saved by a newer, bigger layout)
		end
		local cropId = entry[3] :: string
		tile.crop = if cropId == "" then nil else cropId
		tile.state = entry[4] :: any
		tile.progress = entry[5] :: number
		tile.watered = entry[6] == true
		tile.bareTime = entry[7] :: number
		-- Exhaustion keeps counting down while the player is away (a rejoin never clears it).
		local exhausted = if type(entry[8]) == "number" then entry[8] else 0
		tile.exhausted = math.max(0, exhausted - math.max(0, away))
		local crop = if tile.crop ~= nil then CropConfig.Crops[tile.crop] else nil
		if snap and crop ~= nil and (tile.state == "planted" or tile.state == "growing") then
			tile.progress = 1
			tile.watered = false
			tile.state = if crop.square ~= nil then "growing" else "ready"
		end
		table.insert(changed, tile)
	end
	return changed
end

return FieldSave
