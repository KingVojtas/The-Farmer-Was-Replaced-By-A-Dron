--!strict
--[[
	Economy
	=======
	Pure, non-yielding operations on PlayerData for the harvest -> cargo -> silo/factory loop.
	Each function validates first and then mutates, so it can never leave half-applied state,
	and everything it touches lives in the one saved record (atomic with the next save).

	The cargo hold is keyed by RAW CURRENCY id (a harvested "tree" fills the hold with "wood").

	  harvest() / dig()  -> addToCargo        items go into the drone's hold (limited space)
	  arrive at charger  -> unloadCargo       hold is banked as raw currencies
	  deposit() factory  -> depositCargo      hold becomes Biomass (Factory.BiomassPoints)
	  refine()  factory  -> refine            Biomass becomes Biofuel

	`data` only needs { currencies, cargo, factoryBuffer }, so simulate() can run these same
	functions against a throwaway table (DroneRuntime.SimWorld).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Currencies = require(ReplicatedStorage.Shared.Config.Currencies)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local POINTS = GameConfig.Factory.BiomassPoints

local Economy = {}

function Economy.cargoTotal(data: any): number
	local total = 0
	for _, count in data.cargo do
		total += count
	end
	return total
end

-- Adds up to `amount` items of a raw currency to the hold; returns how many actually fit.
function Economy.addToCargo(data: any, currencyId: string, amount: number, capacity: number): number
	local currency = Currencies.ById[currencyId]
	if currency == nil or currency.kind ~= "raw" or amount <= 0 then
		return 0
	end
	local space = math.max(0, capacity - Economy.cargoTotal(data))
	local added = math.min(math.floor(amount), space)
	if added > 0 then
		data.cargo[currencyId] = (data.cargo[currencyId] or 0) + added
	end
	return added
end

-- Banks the whole hold as raw currencies. Returns { [currencyId] = count } and the total.
function Economy.unloadCargo(data: any): ({ [string]: number }, number)
	local moved: { [string]: number } = {}
	local total = 0
	for currencyId, count in data.cargo do
		if count > 0 then
			moved[currencyId] = count
			total += count
		end
	end
	for currencyId, count in moved do
		data.currencies[currencyId] = (data.currencies[currencyId] or 0) + count
		data.cargo[currencyId] = 0
	end
	return moved, total
end

-- Items in the hold the Factory takes (Biomass points > 0). Hay is worth 0: it stays aboard.
function Economy.depositable(data: any): number
	local count = 0
	for currencyId, amount in data.cargo do
		local value = POINTS[currencyId]
		if value ~= nil and value > 0 and amount > 0 then
			count += amount
		end
	end
	return count
end

-- Turns the hold into Biomass. Items worth 0 points (Hay) stay in the hold, to be banked at
-- the charger. Returns (biomassGained, itemsUsed).
function Economy.depositCargo(data: any): (number, number)
	local points = data.factoryBuffer
	local used = 0
	for currencyId, count in data.cargo do
		local value = POINTS[currencyId]
		if value ~= nil and value > 0 and count > 0 then
			points += count * value
			used += count
		end
	end
	if used == 0 then
		return 0, 0
	end
	local perBiomass = GameConfig.Factory.PointsPerBiomass
	local gained = math.floor(points / perBiomass)
	for currencyId in data.cargo do
		local value = POINTS[currencyId]
		if value ~= nil and value > 0 then
			data.cargo[currencyId] = 0
		end
	end
	data.factoryBuffer = points - gained * perBiomass
	data.currencies.biomass = (data.currencies.biomass or 0) + gained
	return gained, used
end

-- Converts Biomass into up to `maxBatches` Biofuel. Returns (biofuelGained, biomassUsed).
function Economy.refine(data: any, maxBatches: number): (number, number)
	local cost = GameConfig.Factory.BiomassPerBiofuel
	local batches = math.min(maxBatches, math.floor((data.currencies.biomass or 0) / cost))
	if batches <= 0 then
		return 0, 0
	end
	data.currencies.biomass -= batches * cost
	data.currencies.biofuel = (data.currencies.biofuel or 0) + batches
	return batches, batches * cost
end

return Economy
