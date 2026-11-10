--!strict
--[[
	TechTree
	========
	Every research node as plain data. Shared by the server (authoritative checks + spending)
	and the client (graph UI). The logic that reads this table lives in Shared.Progression.Tech.

	SHAPE OF THE TREE
	                               [ while True: ]                         Root
	              ┌────────────────────┼──────────────────┐
	         [ Wheat ]                       [ Grid Expansion I -> II -> III ]
	   ┌─────────┼──────────────┐
	 Botany            System & Drone            Logic & Data
	 Carrots           set_speed(), get_time()   1 + 1
	 Water Tanks,Trees                           ((x, y) with Grid I, a = 2 with Loops)
	 Sunflowers,Pump.  simulate()                [1, 2, 3], def F():
	 Watering Cans     hardware + clothing       {1: 2}, import, random(), get_cost()
	 Cacti
	 Bones & Fossils

	NODE FIELDS
	  id          unique key: what the client sends with Research, and what players type in
	              get_cost("carrots")
	  name        display name;  code  (optional) the code-styled headline on the card
	  icon        icon key in Config.IconConfig (the picture on the Tech Tree card)
	  maxTier     (optional) the last step of an upgrade chain: shows a glowing star once
	              researched
	  branch      "Root" | "Botany" | "System" | "Logic"
	  tier, lane  graph position: tier = row (0 = top), lane = horizontal offset inside the
	              branch column (0 = centre, +-1 = one card to the side; fractions allowed)
	  description one sentence for the UI
	  requires    ids of nodes that must be researched first
	  cost        multi-currency price { [currencyId] = amount }; ALL of it is paid at once.
	              Raw currencies must be farmable with what the prerequisites unlock
	              (Tech.validate checks this, so the tree can never soft-lock a player).
	  unlocks     (optional) features:
	                - builtin names ("get_x", "set_speed", "dig", ...)
	                - syntax features ("while", "repeat", "math", "variables", "lists", "for",
	                  "def", "dicts", "import")
	                - crops as "crop:<id>", cosmetic sets as "cosmetic:<slot>"
	              A feature that NO node unlocks is available from the start.
	  stats       (optional) drone/farm bonuses on top of GameConfig bases:
	                batteryCapacity, waterCapacity, cargoCapacity (flat), speedBonus (+0.2 =
	                20 % faster), chargeRateBonus (+1 = 2x), gridSize (field becomes N x N),
	                waterRadius (water() also waters tiles this many steps away)
]]

export type Branch = "Root" | "Botany" | "System" | "Logic"

export type Stats = {
	batteryCapacity: number?,
	waterCapacity: number?,
	cargoCapacity: number?,
	speedBonus: number?,
	chargeRateBonus: number?,
	gridSize: number?,
	waterRadius: number?,
}

export type Node = {
	id: string,
	name: string,
	code: string?,
	icon: string,
	maxTier: boolean?,
	branch: Branch,
	tier: number,
	lane: number,
	description: string,
	requires: { string },
	cost: { [string]: number },
	unlocks: { string }?,
	stats: Stats?,
}

local List: { Node } = {
	------------------------------------------------------------------------ Root
	{
		id = "loops",
		icon = "loop",
		name = "Loops",
		code = "while True:",
		branch = "Root",
		tier = 0,
		lane = 0,
		description = "Let the drone repeat work forever with 'while' and 'repeat 5 times:', and keep values in variables (a = 2).",
		requires = {},
		cost = { hay = 9 }, -- exactly the starter 3 x 3 of wild grass (the tutorial)
		-- Variables come with the very first loop: a counter is the first thing a loop needs.
		unlocks = { "while", "repeat", "variables" },
	},
	{
		id = "wheat",
		icon = "wheat",
		name = "Wheat",
		code = 'plant("wheat")',
		branch = "Root",
		tier = 1,
		lane = 0,
		description = "Plant wheat: 2 items per harvest. Opens the Botany, System and Logic branches.",
		requires = { "loops" },
		cost = { hay = 25 },
		unlocks = { "crop:wheat" },
	},
	{
		id = "grid_1",
		icon = "grid",
		name = "Grid Expansion I",
		branch = "Root",
		tier = 1,
		lane = 1.5,
		description = "Your field grows to 4 x 4, and the drone can read its position: get_x(), get_y(), get_size().",
		requires = { "loops" },
		cost = { hay = 40 },
		stats = { gridSize = 4 },
		-- A bigger field is when you start needing to know where you are.
		unlocks = { "get_x", "get_y", "get_size" },
	},
	{
		id = "grid_2",
		icon = "grid",
		name = "Grid Expansion II",
		branch = "Root",
		tier = 1,
		lane = 2.5,
		description = "Your field grows to 5 x 5.",
		requires = { "grid_1", "wheat" },
		cost = { wheat = 120 },
		stats = { gridSize = 5 },
	},
	{
		id = "grid_3",
		icon = "grid",
		maxTier = true,
		name = "Grid Expansion III",
		branch = "Root",
		tier = 1,
		lane = 3.5,
		description = "Your field grows to 6 x 6.",
		requires = { "grid_2" },
		cost = { wheat = 200, biomass = 30 },
		stats = { gridSize = 6 },
	},

	---------------------------------------------------------------------- Botany
	{
		id = "carrots",
		icon = "carrot",
		name = "Carrots",
		code = 'plant("carrot")',
		branch = "Botany",
		tier = 2,
		lane = 0,
		description = "Carrots grow slower than wheat but are worth 3x more Biomass.",
		requires = { "wheat" },
		cost = { wheat = 70 },
		unlocks = { "crop:carrot" },
	},
	{
		id = "water_tanks",
		icon = "water",
		name = "Water Tanks",
		code = "water()",
		branch = "Botany",
		tier = 3,
		lane = -0.5,
		description = "water() makes a crop grow twice as fast. +10 water tank capacity.",
		requires = { "carrots" },
		cost = { carrot = 30, wheat = 60 },
		unlocks = { "water", "get_water" },
		stats = { waterCapacity = 10 },
	},
	{
		id = "trees",
		icon = "tree",
		name = "Trees",
		code = 'plant("tree")',
		branch = "Botany",
		tier = 3,
		lane = 0.5,
		description = "Trees take a while to grow, then give 3 Wood each.",
		requires = { "carrots" },
		cost = { carrot = 100 },
		unlocks = { "crop:tree" },
	},
	{
		id = "sunflowers",
		icon = "sunflower",
		name = "Sunflowers",
		code = 'plant("sunflower")',
		branch = "Botany",
		tier = 4,
		lane = -0.5,
		description = "Harvesting a ripe sunflower recharges the drone's battery a little.",
		requires = { "water_tanks" },
		cost = { carrot = 80, biomass = 20 },
		unlocks = { "crop:sunflower" },
	},
	{
		id = "pumpkins",
		icon = "pumpkin",
		name = "Pumpkins",
		code = 'plant("pumpkin")',
		branch = "Botany",
		tier = 4,
		lane = 0.5,
		description = "Slow growers and a Biomass powerhouse at the Factory.",
		requires = { "trees" },
		cost = { wood = 40, carrot = 60 },
		unlocks = { "crop:pumpkin" },
	},
	{
		id = "watering_cans",
		icon = "watering_can",
		name = "Watering Cans",
		branch = "Botany",
		tier = 5,
		lane = 0,
		description = "+20 water tank capacity, and water() also waters the 4 neighbouring tiles.",
		requires = { "sunflowers", "pumpkins" },
		cost = { pumpkin = 40, sunflower = 40, biomass = 30 },
		stats = { waterCapacity = 20, waterRadius = 1 },
	},
	{
		id = "cacti",
		icon = "cactus",
		name = "Cacti",
		code = 'plant("cactus")',
		branch = "Botany",
		tier = 6,
		lane = 0,
		description = "Cacti never need water and grow FASTER in a drought.",
		requires = { "watering_cans" },
		cost = { pumpkin = 60, wood = 80, biomass = 50 },
		unlocks = { "crop:cactus" },
	},
	{
		id = "fossils",
		icon = "fossil",
		name = "Bones & Fossils",
		code = "dig()",
		branch = "Botany",
		tier = 7,
		lane = 0,
		description = "dig() searches the soil below for fossils - superb fuel at the Factory.",
		requires = { "cacti" },
		cost = { cactus = 80, biofuel = 15 },
		unlocks = { "dig" },
	},

	--------------------------------------------------------------- System & Drone
	{
		id = "set_speed",
		icon = "speed",
		name = "Throttle Control",
		code = "set_speed()",
		branch = "System",
		tier = 3,
		lane = -0.5,
		description = "set_speed(2) doubles action speed but doubles energy use; set_speed(0.5) saves battery.",
		requires = { "wheat" }, -- print() is free from the start (debugging is not prestige)
		cost = { wheat = 105 },
		unlocks = { "set_speed" },
	},
	{
		id = "get_time",
		icon = "clock",
		name = "System Clock",
		code = "get_time()",
		branch = "System",
		tier = 3,
		lane = 0.5,
		description = "get_time() returns the seconds since your program started - time your farm.",
		requires = { "wheat" }, -- print() is free from the start (debugging is not prestige)
		cost = { wheat = 40 },
		unlocks = { "get_time" },
	},
	{
		id = "simulate",
		icon = "simulate",
		name = "Simulator",
		code = "simulate()",
		branch = "System",
		tier = 4,
		lane = 0,
		description = 'simulate("lab", 60) test-runs a saved script on a virtual farm and returns its harvest.',
		requires = { "set_speed", "get_time" },
		cost = { wheat = 150, biomass = 30 },
		unlocks = { "simulate" },
	},
	{
		id = "battery_1",
		icon = "battery_pack",
		name = "Battery Pack I",
		branch = "System",
		tier = 5,
		lane = -1.5,
		description = "+40 battery capacity.",
		requires = { "simulate" },
		cost = { wheat = 100, biomass = 20 },
		stats = { batteryCapacity = 40 },
	},
	{
		id = "battery_2",
		icon = "battery_pack",
		name = "Battery Pack II",
		branch = "System",
		tier = 6,
		lane = -1.5,
		description = "+80 battery capacity.",
		requires = { "battery_1" },
		cost = { biomass = 60, biofuel = 10 },
		stats = { batteryCapacity = 80 },
	},
	{
		id = "battery_3",
		icon = "battery_pack",
		maxTier = true,
		name = "Battery Pack III",
		branch = "System",
		tier = 7,
		lane = -1.5,
		description = "+160 battery capacity.",
		requires = { "battery_2" },
		cost = { biomass = 150, biofuel = 40 },
		stats = { batteryCapacity = 160 },
	},
	{
		id = "fast_charger",
		icon = "charger",
		name = "Fast Charger",
		branch = "System",
		tier = 7,
		lane = -0.5,
		description = "The Charging Station charges twice as fast.",
		requires = { "battery_2" },
		cost = { biomass = 40, biofuel = 25 },
		stats = { chargeRateBonus = 1 },
	},
	{
		id = "motors_1",
		icon = "motor",
		name = "Servo Motors I",
		branch = "System",
		tier = 5,
		lane = -0.5,
		description = "Every drone action is 20% faster.",
		requires = { "simulate" },
		cost = { wheat = 150, biomass = 30 },
		stats = { speedBonus = 0.2 },
	},
	{
		id = "motors_2",
		icon = "motor",
		maxTier = true,
		name = "Servo Motors II",
		branch = "System",
		tier = 6,
		lane = -0.5,
		description = "Every drone action is another 30% faster.",
		requires = { "motors_1" },
		cost = { biomass = 80, biofuel = 15 },
		stats = { speedBonus = 0.3 },
	},
	{
		id = "cargo_1",
		icon = "cargo",
		name = "Cargo Bay I",
		branch = "System",
		tier = 5,
		lane = 0.5,
		description = "+15 cargo space.",
		requires = { "simulate" },
		cost = { wheat = 210 },
		stats = { cargoCapacity = 15 },
	},
	{
		id = "cargo_2",
		icon = "cargo",
		maxTier = true,
		name = "Cargo Bay II",
		branch = "System",
		tier = 6,
		lane = 0.5,
		description = "+30 cargo space.",
		requires = { "cargo_1" },
		cost = { wheat = 200, biomass = 60 },
		stats = { cargoCapacity = 30 },
	},
	{
		id = "paint_shop",
		icon = "paint",
		name = "Paint Shop",
		branch = "System",
		tier = 5,
		lane = 1.5,
		description = "Unlocks drone paint jobs in the Drone Hangar.",
		requires = { "simulate" },
		cost = { wheat = 100, biomass = 10 },
		unlocks = { "cosmetic:paint" },
	},
	{
		id = "wardrobe",
		icon = "hat",
		name = "Drone Wardrobe",
		branch = "System",
		tier = 6,
		lane = 1.5,
		description = "Unlocks hats and antennas for your drone in the Drone Hangar.",
		requires = { "paint_shop" },
		cost = { biomass = 50, biofuel = 10 },
		unlocks = { "cosmetic:hat" },
	},

	---------------------------------------------------------------- Logic & Data
	{
		id = "math",
		icon = "math",
		name = "Math",
		code = "1 + 1",
		branch = "Logic",
		tier = 2,
		lane = 0,
		description = "Calculate with + - * / // % and negative numbers.",
		requires = { "wheat" },
		cost = { wheat = 55 },
		unlocks = { "math" },
	},
	{
		id = "arrays",
		icon = "list",
		name = "Lists",
		code = "[1, 2, 3]",
		branch = "Logic",
		tier = 3,
		lane = -0.5,
		description = "Lists, len(), range() and 'for x in list:' loops.",
		requires = { "math" },
		cost = { wheat = 150, biomass = 20 },
		unlocks = { "lists", "for", "len", "range" },
	},
	{
		id = "functions",
		icon = "function",
		name = "Functions",
		code = "def F():",
		branch = "Logic",
		tier = 3,
		lane = 0.5,
		description = "Write your own commands with def and return.",
		requires = { "math" },
		cost = { wheat = 150, biomass = 30 },
		unlocks = { "def" },
	},
	{
		id = "dictionaries",
		icon = "dictionary",
		name = "Dictionaries",
		code = "{1: 2}",
		branch = "Logic",
		tier = 4,
		lane = -1.5,
		description = "Look values up by key: prices = {'wheat': 2}.",
		requires = { "arrays" },
		cost = { wheat = 250, biomass = 60 },
		unlocks = { "dicts" },
	},
	{
		id = "get_cost",
		icon = "cost",
		name = "Cost Scanner",
		code = "get_cost()",
		branch = "Logic",
		tier = 4,
		lane = -0.5,
		description = 'get_cost("carrots") returns what a research costs, as a dictionary.',
		requires = { "arrays", "functions" },
		cost = { biomass = 60, biofuel = 10 },
		unlocks = { "get_cost" },
	},
	{
		id = "import",
		icon = "import",
		name = "Modules",
		code = "import",
		branch = "Logic",
		tier = 4,
		lane = 0.5,
		description = "import utils - use the functions from another of your script slots.",
		requires = { "functions" },
		cost = { biomass = 80, biofuel = 10 },
		unlocks = { "import" },
	},
	{
		id = "random",
		icon = "random",
		name = "Randomness",
		code = "random()",
		branch = "Logic",
		tier = 4,
		lane = 1.5,
		description = "random() returns a random number from 0 up to (not including) 1.",
		requires = { "functions" },
		cost = { wheat = 200, biomass = 40 },
		unlocks = { "random" },
	},
}

local Nodes: { [string]: Node } = {}
for _, node in List do
	assert(Nodes[node.id] == nil, "Duplicate tech node " .. node.id)
	Nodes[node.id] = node
end

local Branches: { Branch } = { "Root", "Botany", "System", "Logic" }

local BranchNames: { [string]: string } = {
	Root = "Core",
	Botany = "Botany",
	System = "System & Drone",
	Logic = "Logic & Data",
}

-- Which of the three graph columns a branch is drawn in (Root sits above the middle one).
local BranchColumn: { [string]: number } = { Root = 2, Botany = 1, System = 2, Logic = 3 }

return {
	Nodes = Nodes,
	List = List,
	Branches = Branches,
	BranchNames = BranchNames,
	BranchColumn = BranchColumn,
}
