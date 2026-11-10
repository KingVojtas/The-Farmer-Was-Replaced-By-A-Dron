--!strict
--[[
	SoilStates
	==========
	Which soil look a field tile shows (docs/ART_BIBLE.md §2.4 "Gameplay mapping"), from the
	attributes GridService publishes. Pure: Client.Visuals.SoilLook decides how a state is
	drawn (artist MaterialVariant or the built-in fallback).

	  Watered == true                              -> SoilWet    (overrides Tilled; authored
	                                                              over the Tilled height, so the
	                                                              furrows stay)
	  planted / growing / ready PLAYER crop        -> SoilTilled
	  empty, or wild grass (weeds on unbroken dirt) -> SoilDry
	  SoilFertile is reserved for a future mechanic and never returned.
]]

local CropConfig = require(script.Parent.Parent.Config.CropConfig)

export type SoilState = "SoilDry" | "SoilTilled" | "SoilWet"

local SoilStates = {}

-- Every state the game shows, in Bible order (SoilFertile is reserved, not listed).
local NAMES: { SoilState } = { "SoilDry", "SoilTilled", "SoilWet" }
SoilStates.Names = NAMES

function SoilStates.forTile(state: string, cropId: string, watered: boolean): SoilState
	if watered then
		return "SoilWet"
	end
	local crop = CropConfig.Crops[cropId]
	if state ~= "empty" and crop ~= nil and crop.wild ~= true then
		return "SoilTilled"
	end
	return "SoilDry"
end

return SoilStates
