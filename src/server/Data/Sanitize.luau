--!strict
--[[
	Sanitize
	========
	Turns whatever came out of the DataStore into a well-formed PlayerData:
	  1. runs schema migrations (old version -> current),
	  2. fills every missing field with its default,
	  3. replaces wrong-typed / out-of-range values with safe values,
	  4. keeps unknown top-level keys untouched (forward compatibility during rolling updates).

	It never throws and never yields, so it is safe inside an UpdateAsync transform.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CosmeticConfig = require(ReplicatedStorage.Shared.Config.CosmeticConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local ScriptNames = require(ReplicatedStorage.Shared.DroneScript.ScriptNames)
local Text = require(ReplicatedStorage.Shared.Util.Text)
local DataTemplate = require(script.Parent.DataTemplate)
local FieldSave = require(script.Parent.Parent.Progression.FieldSave)

type PlayerData = DataTemplate.PlayerData

local MAX_RECEIPT_ID_LENGTH = 100
local MAX_SAFE_INTEGER = 2 ^ 53

-- The full cost of every v1 (Hardware/Software/Industry) research node, frozen as it was when
-- v1 shipped. Migration 2 refunds these, because the v2 tree has entirely different nodes.
local V1_NODE_COSTS: { [string]: { [string]: number } } = table.freeze({
	sw_loops = { wheat = 10 },
	sw_senses = { wheat = 15 },
	sw_navigation = { wheat = 40 },
	sw_power_monitor = { wheat = 60, biomass = 5 },
	sw_weather_station = { carrot = 40, biomass = 10 },
	sw_cargo_scanner = { wheat = 80, biomass = 10 },
	hw_battery_1 = { wheat = 25 },
	hw_battery_2 = { wheat = 120, biomass = 20 },
	hw_battery_3 = { carrot = 150, biofuel = 20 },
	hw_motors_1 = { wheat = 50 },
	hw_motors_2 = { carrot = 80, biomass = 25 },
	hw_cargo_1 = { wheat = 40 },
	hw_cargo_2 = { pumpkin = 30, biomass = 30 },
	hw_water_tank = { wheat = 60, biomass = 10 },
	hw_fast_charger = { biomass = 40, biofuel = 5 },
	ind_irrigation = { wheat = 20 },
	ind_processing = { wheat = 30 },
	ind_carrots = { wheat = 50, biomass = 5 },
	ind_pumpkins = { carrot = 60, biomass = 20 },
	ind_bioreactor = { carrot = 40, biomass = 50 },
})

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- Migrations: MIGRATIONS[n] upgrades data from version n-1 to n (mutating in place).
-- They run BEFORE field sanitizing, so they must tolerate garbage in any field.
local MIGRATIONS: { [number]: (data: { [string]: any }) -> () } = {
	--[[
		1 -> 2: Tech Tree v2.
		  * Every researched v1 node is refunded in full (its currencies are added back) and
		    techUnlocks is cleared - no v1 id exists in the v2 tree, so nothing is "granted"
		    without its prerequisites.
		  * gridSize is dropped: the field size now comes from Grid Expansion research.
		  * scriptNames / cosmetics are filled with defaults by the sanitizer below.
	]]
	[2] = function(data: { [string]: any })
		local currencies = if type(data.currencies) == "table" then data.currencies else {}
		if type(data.techUnlocks) == "table" then
			for nodeId, researched in data.techUnlocks do
				local cost = if researched == true and type(nodeId) == "string"
					then V1_NODE_COSTS[nodeId]
					else nil
				if cost ~= nil then
					for currency, amount in cost do
						local current = currencies[currency]
						local base = if isFinite(current) and current >= 0 then current else 0
						currencies[currency] = base + amount
					end
				end
			end
		end
		data.currencies = currencies
		data.techUnlocks = {}
		data.gridSize = nil
	end,
	--[[
		2 -> 3: the field is saved. Old saves had none: they start with an empty field
		(wild grass, as before). The sanitizer below validates every saved tile.
	]]
	[3] = function(data: { [string]: any })
		if type(data.field) ~= "table" then
			data.field = FieldSave.empty()
		end
	end,
}

local function integerOr(value: any, default: number, min: number, max: number): number
	if not isFinite(value) then
		return default
	end
	return math.clamp(math.floor(value), min, max)
end

--[[
	{ [string] = non-negative integer } maps (currencies, cargo). Every key of `defaults` is
	present afterwards. Unknown string keys with valid amounts are KEPT: during a rolling update
	a newer server may have added a currency, and an older server must not delete it on save.
]]
local function sanitizeAmounts(raw: any, defaults: { [string]: number }): { [string]: number }
	local result: { [string]: number } = {}
	if type(raw) == "table" then
		for key, value in raw do
			if type(key) == "string" and isFinite(value) then
				result[key] = math.clamp(math.floor(value), 0, MAX_SAFE_INTEGER)
			end
		end
	end
	for key, default in defaults do
		if result[key] == nil then
			result[key] = default
		end
	end
	return result
end

-- { [string] = true } sets (tech unlocks, one-time claims, owned cosmetics); anything else is dropped.
local function sanitizeFlags(raw: any): { [string]: boolean }
	local result: { [string]: boolean } = {}
	if type(raw) == "table" then
		for key, value in raw do
			if type(key) == "string" and value == true then
				result[key] = true
			end
		end
	end
	return result
end

local Sanitize = {}

Sanitize.V1_NODE_COSTS = V1_NODE_COSTS

function Sanitize.run(raw: any, now: number): PlayerData
	local template = DataTemplate.new(now)
	if type(raw) ~= "table" then
		return template
	end

	-- Shallow copy keeps unknown keys; every known key is rebuilt below.
	local data: { [string]: any } = table.clone(raw)

	-- 1. Migrations
	local version = integerOr(data.schemaVersion, 1, 1, MAX_SAFE_INTEGER)
	for target = version + 1, DataTemplate.SCHEMA_VERSION do
		local migrate = MIGRATIONS[target]
		if migrate ~= nil then
			migrate(data)
		end
	end
	-- Never downgrade: data written by a NEWER server version keeps its version number.
	data.schemaVersion = math.max(version, DataTemplate.SCHEMA_VERSION)

	-- 2. + 3. Known fields
	data.currencies = sanitizeAmounts(data.currencies, template.currencies)
	data.cargo = sanitizeAmounts(data.cargo, template.cargo)
	data.techUnlocks = sanitizeFlags(data.techUnlocks)
	data.factoryBuffer = integerOr(data.factoryBuffer, 0, 0, GameConfig.Factory.PointsPerBiomass - 1)
	data.cropsHarvested = integerOr(data.cropsHarvested, 0, 0, MAX_SAFE_INTEGER)
	data.firstJoin = integerOr(data.firstJoin, now, 1, MAX_SAFE_INTEGER)

	-- Scripts: exactly `Slots` strings, each valid UTF-8 and within the size cap.
	local rawScripts = if type(data.scripts) == "table" then data.scripts else nil
	local scripts = table.create(GameConfig.Script.Slots, "")
	for slot = 1, GameConfig.Script.Slots do
		if rawScripts == nil then
			scripts[slot] = template.scripts[slot]
		else
			local source = rawScripts[slot]
			if type(source) == "string" and utf8.len(source) ~= nil then
				scripts[slot] = Text.truncateUtf8(source, GameConfig.Script.MaxSourceBytes)
			end
		end
	end
	data.scripts = scripts

	-- Script names: valid, unique identifiers; anything invalid falls back to the default.
	local rawNames = if type(data.scriptNames) == "table" then data.scriptNames else {}
	local names: { string } = table.create(GameConfig.Script.Slots, "")
	for slot = 1, GameConfig.Script.Slots do
		local candidate = rawNames[slot]
		if ScriptNames.validate(candidate, names, slot) then
			names[slot] = candidate
		end
	end
	for slot = 1, GameConfig.Script.Slots do
		if names[slot] == "" then
			local fallback = template.scriptNames[slot]
			if not ScriptNames.validate(fallback, names, slot) then
				fallback = "slot" .. slot
			end
			names[slot] = fallback
		end
	end
	data.scriptNames = names

	-- Cosmetics: ownership flags are kept (even unknown ids: a newer server may have sold
	-- them); equipped ids must be known items of the right slot.
	local rawCosmetics = if type(data.cosmetics) == "table" then data.cosmetics else {}
	local rawEquipped = if type(rawCosmetics.equipped) == "table" then rawCosmetics.equipped else {}
	local equipped: { [string]: string } = {}
	for _, slot in CosmeticConfig.Slots do
		local id = rawEquipped[slot]
		local item = if type(id) == "string" then CosmeticConfig.ById[id] else nil
		equipped[slot] = if item ~= nil and item.slot == slot then id else CosmeticConfig.Defaults[slot]
	end
	data.cosmetics = { owned = sanitizeFlags(rawCosmetics.owned), equipped = equipped }

	local rawBoosts = if type(data.boosts) == "table" then data.boosts else {}
	data.boosts = {
		growthUntil = integerOr(rawBoosts.growthUntil, 0, 0, MAX_SAFE_INTEGER),
		yieldUntil = integerOr(rawBoosts.yieldUntil, 0, 0, MAX_SAFE_INTEGER),
	}

	data.oneTimeClaims = sanitizeFlags(data.oneTimeClaims)

	local rawTutorial = if type(data.tutorial) == "table" then data.tutorial else {}
	data.tutorial = {
		step = integerOr(rawTutorial.step, 0, 0, 10000),
		done = rawTutorial.done == true,
	}

	data.field = FieldSave.sanitize(data.field)

	-- Receipts: array of short strings, only the newest MaxReceiptHistory entries.
	local receipts: { string } = {}
	if type(data.receipts) == "table" then
		for _, purchaseId in ipairs(data.receipts) do
			if type(purchaseId) == "string" and #purchaseId <= MAX_RECEIPT_ID_LENGTH then
				table.insert(receipts, purchaseId)
			end
		end
	end
	local overflow = #receipts - GameConfig.Data.MaxReceiptHistory
	if overflow > 0 then
		receipts = table.move(receipts, overflow + 1, #receipts, 1, {})
	end
	data.receipts = receipts

	return (data :: any) :: PlayerData
end

return Sanitize
