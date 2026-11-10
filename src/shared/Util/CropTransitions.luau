--!strict
--[[
	CropTransitions
	===============
	Pure logic behind the crop "juice" in Client.Controllers.PlotRenderer: it compares two
	snapshots of one tile's published attributes (GridService.publishTile) and says which
	visual events to play. It also clamps particle bursts to the on-screen budget. No Roblox
	types, so the offline tests cover it.

	EVENTS (a tile can raise several in one update)
	  plant    a crop appeared on a tile that had none (or a different crop replaced it)
	  sprout   planted -> growing, same crop             (growth pop + leaf bits)
	  ready    became harvestable                        (silhouette cue + lime ping)
	  harvest  the crop was removed; `ripe` says if it was ready (crop-coloured bits) or
	           not (grey/brown bits); `harvestedCrop` is the removed crop's id
	  water    Watered became true on a growing crop. Not raised when it comes with `plant`
	           (rain waters fresh seeds) and never for true -> false.
	  wetChanged  Watered flipped either way (the soil colour must update)

	The first snapshot of a tile (previous = nil, e.g. on join) raises nothing, so joining a
	server never sets off a field of bursts.
]]

export type Snapshot = {
	state: string,
	crop: string,
	watered: boolean,
	progress: number,
}

export type Events = {
	plant: boolean,
	sprout: boolean,
	ready: boolean,
	harvest: boolean,
	ripe: boolean,
	harvestedCrop: string,
	water: boolean,
	wetChanged: boolean,
}

local CropTransitions = {}

-- Normalises raw attribute values (any type, possibly nil) into a Snapshot.
function CropTransitions.snapshot(state: any, crop: any, watered: any, progress: any): Snapshot
	return {
		state = if type(state) == "string" then state else "empty",
		crop = if type(crop) == "string" then crop else "",
		watered = watered == true,
		progress = if type(progress) == "number" and progress == progress then progress else 0,
	}
end

local function hasCrop(snapshot: Snapshot): boolean
	return snapshot.state ~= "empty" and snapshot.crop ~= ""
end

function CropTransitions.diff(previous: Snapshot?, current: Snapshot): Events
	local events: Events = {
		plant = false,
		sprout = false,
		ready = false,
		harvest = false,
		ripe = false,
		harvestedCrop = "",
		water = false,
		wetChanged = false,
	}
	if previous == nil then
		return events
	end
	local had = hasCrop(previous)
	local has = hasCrop(current)
	local sameCrop = had and has and previous.crop == current.crop

	if had and not sameCrop then
		events.harvest = true
		events.ripe = previous.state == "ready"
		events.harvestedCrop = previous.crop
	end
	if has and not sameCrop then
		events.plant = true
	end
	if sameCrop and previous.state == "planted" and current.state == "growing" then
		events.sprout = true
	end
	if has and current.state == "ready" and (previous.state ~= "ready" or not sameCrop) then
		events.ready = true
	end
	events.wetChanged = previous.watered ~= current.watered
	events.water = has and current.watered and not previous.watered and not events.plant
	return events
end

-- How many particles a burst may emit: `requested`, cut down so no more than `max` are
-- alive at once (`active` = alive right now). 0 means skip the burst.
function CropTransitions.burstSize(requested: number, active: number, max: number): number
	return math.max(0, math.min(math.floor(requested), max - active))
end

return CropTransitions
