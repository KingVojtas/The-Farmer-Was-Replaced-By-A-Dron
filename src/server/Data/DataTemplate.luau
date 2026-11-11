--!strict
--[[
	DataTemplate
	============
	The shape of one player's saved data (schema version 3) and the defaults for new players.

	Everything here must be DataStore-serializable: only strings, finite numbers, booleans,
	arrays (no holes) and string-keyed dictionaries. No Instances, Vector3s, functions or NaN.
	Bump SCHEMA_VERSION and add a migration in Sanitize when the shape changes.

	Things that must change TOGETHER live in this one record, so a single UpdateAsync writes
	them atomically: a research's cost + its unlock, a purchase's reward + its PurchaseId,
	a cosmetic's price + its ownership, a factory deposit's cargo + the Biomass it produced.

	VERSION HISTORY
	  1  first release (Hardware/Software/Industry tech tree, gridSize field)
	  2  Tech Tree v2 (Root/Botany/System/Logic), field size derived from research,
	     scriptNames (for `import`), cosmetics. v1 research is refunded (Sanitize).
	  3  the field is saved: field = { savedAt, tiles = { {x, y, crop, state, progress,
	     watered, bareTime, exhausted?}, ... } } (Progression.FieldSave). v2 saves start with an
	     empty one. `exhausted` (dig exhaustion) was added later as an optional 8th value: no
	     version bump, a 7-value entry reads as 0.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CosmeticConfig = require(ReplicatedStorage.Shared.Config.CosmeticConfig)
local Currencies = require(ReplicatedStorage.Shared.Config.Currencies)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

export type PlayerData = {
	schemaVersion: number,
	currencies: { [string]: number }, -- every id in Currencies (raw, processed, premium)
	techUnlocks: { [string]: boolean }, -- researched Tech Tree node ids
	cargo: { [string]: number }, -- raw currencies in the drone's hold (saved: nothing is lost on leave)
	factoryBuffer: number, -- leftover biomass points at the Factory (< PointsPerBiomass)
	cropsHarvested: number, -- lifetime stat (leaderboard)
	scripts: { string }, -- one source string per slot (exactly GameConfig.Script.Slots entries)
	scriptNames: { string }, -- one unique module name per slot (`import <name>`)
	cosmetics: {
		owned: { [string]: boolean }, -- premium cosmetics bought with Lithium Batteries
		equipped: { [string]: string }, -- slot ("paint" | "hat") -> cosmetic id
	},
	boosts: {
		growthUntil: number, -- os.time() when the growth boost ends (0 = none)
		yieldUntil: number,
	},
	oneTimeClaims: { [string]: boolean }, -- product keys bought once (e.g. StarterPack)
	firstJoin: number, -- os.time() of the very first session (Starter Pack offer window)
	tutorial: { step: number, done: boolean },
	field: { savedAt: number, tiles: { { any } } }, -- the plot's tiles (Progression.FieldSave)
	receipts: { string }, -- last N processed PurchaseIds, oldest first (receipt dedupe)
}

local DataTemplate = {}

DataTemplate.SCHEMA_VERSION = 3

function DataTemplate.new(now: number): PlayerData
	local currencies: { [string]: number } = {}
	local cargo: { [string]: number } = {}
	for _, currency in Currencies.List do
		currencies[currency.id] = 0
		if currency.kind == "raw" then
			cargo[currency.id] = 0
		end
	end
	local scripts = table.create(GameConfig.Script.Slots, "")
	scripts[1] = GameConfig.StarterScript
	local scriptNames = table.create(GameConfig.Script.Slots, "")
	for slot = 1, GameConfig.Script.Slots do
		scriptNames[slot] = GameConfig.Script.DefaultNames[slot] or ("slot" .. slot)
	end

	return {
		schemaVersion = DataTemplate.SCHEMA_VERSION,
		currencies = currencies,
		techUnlocks = {},
		cargo = cargo,
		factoryBuffer = 0,
		cropsHarvested = 0,
		scripts = scripts,
		scriptNames = scriptNames,
		cosmetics = {
			owned = {},
			equipped = table.clone(CosmeticConfig.Defaults),
		},
		boosts = { growthUntil = 0, yieldUntil = 0 },
		oneTimeClaims = {},
		firstJoin = now,
		tutorial = { step = 0, done = false },
		field = { savedAt = 0, tiles = {} },
		receipts = {},
	}
end

return DataTemplate
