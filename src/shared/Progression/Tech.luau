--!strict
--[[
	Tech
	====
	Pure logic over Config.TechTree. Shared: the server uses it as the authority (validation,
	spending, unlock checks inside the parser) and the client uses the same functions to render
	the Tech Tree graph and pre-check code - so both always agree.

	Unlock sets are dictionaries { [nodeId] = true } (exactly how they are saved).

	FEATURES are the things a node can unlock (see TechTree.luau). A feature that no node lists
	is free from the start. Tech.isFeatureUnlocked is what the Parser calls for every command
	and every gated piece of syntax, which is how the server refuses e.g. `a = 2` before the
	"Variables" research - using the player's SAVED unlocks, never anything the client says.
]]

local Config = script.Parent.Parent.Config
local Builtins = require(script.Parent.Parent.DroneScript.Builtins)
local CosmeticConfig = require(Config.CosmeticConfig)
local Currencies = require(Config.Currencies)
local CropConfig = require(Config.CropConfig)
local GameConfig = require(Config.GameConfig)
local IconConfig = require(Config.IconConfig)
local TechTree = require(Config.TechTree)

export type Node = TechTree.Node
export type Branch = TechTree.Branch
export type UnlockSet = { [string]: boolean }
export type Status = "researched" | "available" | "locked"

export type DroneStats = {
	batteryCapacity: number,
	waterCapacity: number,
	cargoCapacity: number,
	speedMultiplier: number, -- multiplies action speed (1 = base); excludes gamepasses
	chargeRate: number, -- energy per second at the charger
	gridSize: number, -- field is gridSize x gridSize
	waterRadius: number, -- water() also waters tiles within this Manhattan distance
}

export type Edge = { from: string, to: string }

local Tech = {}

Tech.Nodes = TechTree.Nodes
Tech.Branches = TechTree.Branches
Tech.BranchNames = TechTree.BranchNames
Tech.BranchColumn = TechTree.BranchColumn

-- Syntax features the Parser gates, with the phrase used in "locked" messages.
local SYNTAX_LABELS: { [string]: string } = {
	["while"] = "'while' loops",
	["repeat"] = "'repeat' loops",
	math = "math (+ - * /)",
	variables = "variables (a = 2)",
	lists = "lists like [1, 2, 3]",
	["for"] = "'for' loops",
	def = "your own functions (def)",
	dicts = "dictionaries like {1: 2}",
	import = "'import'",
}
Tech.SyntaxFeatures = SYNTAX_LABELS

local COSMETIC_LABELS: { [string]: string } = {
	["cosmetic:paint"] = "paint jobs",
	["cosmetic:hat"] = "drone hats",
}

-- feature -> id of the node that unlocks it
local featureOwner: { [string]: string } = {}
for id, node in TechTree.Nodes do
	local features: { string } = node.unlocks or {}
	for _, feature in features do
		if featureOwner[feature] == nil then
			featureOwner[feature] = id
		end
	end
end
Tech.FeatureOwner = featureOwner

-- Sorted node ids (branch order, then tier, then lane) for stable UI and remote validation.
local branchRank: { [string]: number } = {}
for index, branch in TechTree.Branches do
	branchRank[branch] = index
end
local sortedIds: { string } = {}
for id in TechTree.Nodes do
	table.insert(sortedIds, id)
end
table.sort(sortedIds, function(a: string, b: string): boolean
	local na, nb = TechTree.Nodes[a], TechTree.Nodes[b]
	if na.branch ~= nb.branch then
		return (branchRank[na.branch] or 99) < (branchRank[nb.branch] or 99)
	end
	if na.tier ~= nb.tier then
		return na.tier < nb.tier
	end
	if na.lane ~= nb.lane then
		return na.lane < nb.lane
	end
	return a < b
end)
Tech.NodeIds = sortedIds

-- Every prerequisite edge, in node order (drawn as connector lines by the graph UI).
local edges: { Edge } = {}
for _, id in sortedIds do
	for _, req in TechTree.Nodes[id].requires do
		table.insert(edges, { from = req, to = id })
	end
end
Tech.Edges = edges

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value % 1 == 0 and value < 2 ^ 53
end

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- True if `feature` is something the game actually implements.
function Tech.featureExists(feature: string): boolean
	if SYNTAX_LABELS[feature] ~= nil or Builtins.ByName[feature] ~= nil then
		return true
	end
	local crop = string.match(feature, "^crop:(.+)$")
	if crop ~= nil then
		local def = CropConfig.Crops[crop]
		return def ~= nil and def.wild ~= true
	end
	if COSMETIC_LABELS[feature] ~= nil then
		return true
	end
	return false
end

-- All transitive prerequisites of a node (not including the node itself).
function Tech.ancestors(nodeId: string): { [string]: boolean }
	local result: { [string]: boolean } = {}
	local stack: { string } = {}
	local start = TechTree.Nodes[nodeId]
	if start == nil then
		return result
	end
	for _, req in start.requires do
		table.insert(stack, req)
	end
	local guard = 0
	while #stack > 0 and guard < 10000 do
		guard += 1
		local id = table.remove(stack) :: string
		if not result[id] then
			result[id] = true
			local node = TechTree.Nodes[id]
			if node ~= nil then
				for _, req in node.requires do
					table.insert(stack, req)
				end
			end
		end
	end
	return result
end

--[[
	Raw currencies a player can farm with the features of `unlocks` (plus everything free):
	the currency of every unlocked crop (wild crops are always free) and the dig currency once
	dig() is available.
]]
function Tech.farmableCurrencies(unlocks: UnlockSet): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for cropId, crop in CropConfig.Crops do
		local owner = featureOwner["crop:" .. cropId]
		if crop.wild == true or owner == nil or unlocks[owner] == true then
			result[crop.currency] = true
		end
	end
	local digOwner = featureOwner.dig
	if digOwner == nil or unlocks[digOwner] == true then
		result[GameConfig.Dig.currency] = true
	end
	return result
end

--[[
	Checks the whole tree. Returns (true, {}) or (false, { problem, ... }).
	Called by the unit tests and once at server start (problems are printed as errors).
]]
function Tech.validate(): (boolean, { string })
	local problems: { string } = {}
	local function problem(fmt: string, ...: any)
		table.insert(problems, string.format(fmt, ...))
	end
	local seenFeature: { [string]: string } = {}

	for id, node in TechTree.Nodes do
		if node.id ~= id then
			problem("%s: id field is %q", id, tostring(node.id))
		end
		if branchRank[node.branch] == nil then
			problem("%s: unknown branch %s", id, tostring(node.branch))
		end
		if type(node.icon) ~= "string" or IconConfig.Icons[node.icon] == nil then
			problem("%s: icon %s is not in IconConfig", id, tostring(node.icon))
		end
		if not isFinite(node.tier) or node.tier < 0 or not isFinite(node.lane) then
			problem("%s: needs a numeric tier >= 0 and lane", id)
		end
		for _, req in node.requires do
			local reqNode = TechTree.Nodes[req]
			if reqNode == nil then
				problem("%s: requires unknown node %s", id, req)
			elseif isFinite(node.tier) and reqNode.tier > node.tier then
				problem(
					"%s: prerequisite %s is drawn below it (tier %d > %d)",
					id,
					req,
					reqNode.tier,
					node.tier
				)
			end
		end

		local hasCost = false
		for currency, amount in node.cost do
			hasCost = true
			local def = Currencies.ById[currency]
			if def == nil then
				problem("%s: unknown currency %s", id, currency)
			elseif def.kind == "premium" then
				problem("%s: research must never cost premium currency (%s)", id, currency)
			elseif not isPositiveInteger(amount) then
				problem("%s: cost of %s must be a positive integer", id, currency)
			end
		end
		if not hasCost then
			problem("%s: has no cost", id)
		end

		local features: { string } = node.unlocks or {}
		for _, feature in features do
			if seenFeature[feature] ~= nil then
				problem("feature %s is unlocked by both %s and %s", feature, seenFeature[feature], id)
			end
			seenFeature[feature] = id
			if not Tech.featureExists(feature) then
				problem("%s: unlocks %s, which the game doesn't implement", id, feature)
			end
		end

		local stats = node.stats
		if stats ~= nil and stats.gridSize ~= nil then
			if
				stats.gridSize % 1 ~= 0
				or stats.gridSize < GameConfig.Grid.MinSize
				or stats.gridSize > GameConfig.Grid.MaxSize
			then
				problem("%s: gridSize must be an integer within Grid.MinSize..MaxSize", id)
			end
		end
	end

	-- Cycle detection (depth-first, white/grey/black).
	local state: { [string]: number } = {}
	local function visit(id: string, path: { string })
		if state[id] == 2 then
			return
		end
		if state[id] == 1 then
			table.insert(problems, "cycle: " .. table.concat(path, " -> ") .. " -> " .. id)
			return
		end
		state[id] = 1
		table.insert(path, id)
		local node = TechTree.Nodes[id]
		if node ~= nil then
			for _, req in node.requires do
				visit(req, path)
			end
		end
		table.remove(path)
		state[id] = 2
	end
	for id in TechTree.Nodes do
		visit(id, {})
	end

	-- Every raw currency has exactly one source, and a Factory value.
	local sources: { [string]: number } = {}
	for cropId, crop in CropConfig.Crops do
		local def = Currencies.ById[crop.currency]
		if def == nil or def.kind ~= "raw" then
			problem("crop %s produces %s, which is not a raw currency", cropId, tostring(crop.currency))
		end
		sources[crop.currency] = (sources[crop.currency] or 0) + 1
	end
	sources[GameConfig.Dig.currency] = (sources[GameConfig.Dig.currency] or 0) + 1
	for _, currency in Currencies.List do
		if currency.kind == "raw" then
			if (sources[currency.id] or 0) ~= 1 then
				problem("raw currency %s needs exactly one source (crop or dig)", currency.id)
			end
			if GameConfig.Factory.BiomassPoints[currency.id] == nil then
				problem("raw currency %s has no Factory.BiomassPoints value", currency.id)
			end
		end
	end

	-- Cosmetic sets unlocked by research must have an owning node.
	for _, item in CosmeticConfig.List do
		local unlock: any = item.unlock
		if unlock.kind == "tech" and featureOwner[unlock.feature] == nil then
			problem("cosmetic %s needs %s, which no node unlocks", item.id, tostring(unlock.feature))
		end
	end

	-- Cost reachability: a node may only ask for raw currencies its prerequisites let you farm.
	if #problems == 0 then
		for id, node in TechTree.Nodes do
			local farmable = Tech.farmableCurrencies(Tech.ancestors(id))
			for currency in node.cost do
				local def = Currencies.ById[currency]
				if def ~= nil and def.kind == "raw" and not farmable[currency] then
					problem(
						"%s costs %s, but nothing before it lets the player farm %s",
						id,
						currency,
						currency
					)
				end
			end
		end
	end

	return #problems == 0, problems
end

function Tech.isUnlocked(unlocks: UnlockSet, nodeId: string): boolean
	return unlocks[nodeId] == true
end

-- True if the feature is free, or its node has been researched.
function Tech.isFeatureUnlocked(unlocks: UnlockSet, feature: string): boolean
	local owner = featureOwner[feature]
	return owner == nil or unlocks[owner] == true
end

-- How a node is named in messages: 'Variables "a = 2"'.
function Tech.title(nodeId: string): string
	local node = TechTree.Nodes[nodeId]
	if node == nil then
		return nodeId
	end
	if node.code ~= nil then
		return string.format('%s "%s"', node.name, node.code)
	end
	return node.name
end

-- Player-facing name of a feature.
function Tech.featureLabel(feature: string): string
	local syntax = SYNTAX_LABELS[feature]
	if syntax ~= nil then
		return syntax
	end
	local cosmetic = COSMETIC_LABELS[feature]
	if cosmetic ~= nil then
		return cosmetic
	end
	local crop = string.match(feature, "^crop:(.+)$")
	if crop ~= nil then
		return string.format('plant("%s")', crop)
	end
	return feature .. "()"
end

-- Player-facing explanation for a locked feature.
function Tech.lockedMessage(feature: string): string
	local owner = featureOwner[feature]
	local node = if owner ~= nil then TechTree.Nodes[owner] else nil
	if node == nil then
		return string.format("%s isn't available.", Tech.featureLabel(feature))
	end
	return string.format(
		"You haven't unlocked %s yet. Research %s (%s) in the Tech Tree to use it.",
		Tech.featureLabel(feature),
		Tech.title(node.id),
		TechTree.BranchNames[node.branch] or node.branch
	)
end

function Tech.missingPrerequisites(unlocks: UnlockSet, nodeId: string): { string }
	local missing: { string } = {}
	local node = TechTree.Nodes[nodeId]
	if node == nil then
		return missing
	end
	for _, req in node.requires do
		if unlocks[req] ~= true then
			table.insert(missing, req)
		end
	end
	return missing
end

function Tech.canAfford(currencies: { [string]: number }, nodeId: string): boolean
	local node = TechTree.Nodes[nodeId]
	if node == nil then
		return false
	end
	for currency, amount in node.cost do
		if (currencies[currency] or 0) < amount then
			return false
		end
	end
	return true
end

function Tech.status(unlocks: UnlockSet, nodeId: string): Status
	if unlocks[nodeId] == true then
		return "researched"
	end
	if #Tech.missingPrerequisites(unlocks, nodeId) > 0 then
		return "locked"
	end
	return "available"
end

-- "25 Hay + 5 Biomass" (currency display order)
function Tech.formatCost(nodeId: string): string
	local node = TechTree.Nodes[nodeId]
	if node == nil then
		return ""
	end
	local parts: { string } = {}
	for _, currency in Currencies.List do
		local amount = node.cost[currency.id]
		if amount ~= nil then
			table.insert(parts, string.format("%d %s", amount, currency.name))
		end
	end
	return table.concat(parts, " + ")
end

--[[
	Checks whether `data` (PlayerData: currencies + techUnlocks) can research `nodeId`.
	Returns (true) or (false, player-facing reason).
]]
function Tech.canResearch(data: any, nodeId: string): (boolean, string?)
	local node = TechTree.Nodes[nodeId]
	if node == nil then
		return false, "That research doesn't exist."
	end
	if data.techUnlocks[nodeId] == true then
		return false, node.name .. " is already researched."
	end
	local missing = Tech.missingPrerequisites(data.techUnlocks, nodeId)
	if #missing > 0 then
		local names: { string } = {}
		for _, id in missing do
			table.insert(names, TechTree.Nodes[id].name)
		end
		return false, "Research " .. table.concat(names, " and ") .. " first."
	end
	if not Tech.canAfford(data.currencies, nodeId) then
		return false, "Not enough resources. " .. node.name .. " costs " .. Tech.formatCost(nodeId) .. "."
	end
	return true
end

--[[
	Researches a node: pays the FULL multi-currency cost and records the unlock.
	All-or-nothing and non-yielding: every check happens before the first change, so the data
	can never end up with currency spent but no unlock (or the other way round). Because cost
	and unlock live in the same saved record, a crash persists both or neither.
]]
function Tech.research(data: any, nodeId: string): (boolean, string?)
	local ok, reason = Tech.canResearch(data, nodeId)
	if not ok then
		return false, reason
	end
	local node = TechTree.Nodes[nodeId]
	for currency, amount in node.cost do
		data.currencies[currency] = (data.currencies[currency] or 0) - amount
	end
	data.techUnlocks[nodeId] = true
	return true
end

-- Drone and farm stats for an unlock set (GameConfig bases + node bonuses).
function Tech.stats(unlocks: UnlockSet): DroneStats
	local drone = GameConfig.Drone
	local battery, water, cargo = drone.BaseBattery, drone.BaseWater, drone.BaseCargo
	local speedBonus, chargeBonus = 0, 0
	local gridSize = GameConfig.Grid.StartingSize
	local waterRadius = 0
	for id in unlocks do
		local node = TechTree.Nodes[id]
		local stats = if node ~= nil then node.stats else nil
		if stats ~= nil then
			battery += stats.batteryCapacity or 0
			water += stats.waterCapacity or 0
			cargo += stats.cargoCapacity or 0
			speedBonus += stats.speedBonus or 0
			chargeBonus += stats.chargeRateBonus or 0
			gridSize = math.max(gridSize, stats.gridSize or 0)
			waterRadius = math.max(waterRadius, stats.waterRadius or 0)
		end
	end
	return {
		batteryCapacity = battery,
		waterCapacity = water,
		cargoCapacity = cargo,
		speedMultiplier = 1 + speedBonus,
		chargeRate = drone.BaseChargeRate * (1 + chargeBonus),
		gridSize = math.clamp(gridSize, GameConfig.Grid.MinSize, GameConfig.Grid.MaxSize),
		waterRadius = waterRadius,
	}
end

return Tech
