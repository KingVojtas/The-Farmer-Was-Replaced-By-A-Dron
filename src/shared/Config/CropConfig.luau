--!strict
--[[
	CropConfig
	==========
	Crop definitions. The key (e.g. "carrot") is exactly what players type in plant("carrot").
	A harvest puts `yield` items of the crop's `currency` into the drone's cargo hold
	(cargo and currencies are both keyed by CURRENCY id, e.g. a "tree" yields "wood").

	Locked crops are unlocked by Tech Tree nodes with the feature "crop:<id>".

	FIELDS
	  displayName     UI name
	  currency        raw currency the harvest produces (Currencies, kind "raw")
	  growSeconds     planting -> ready, Sunny weather, unwatered, no boosts
	  yield           items per harvest (before gamepass / boost multipliers)
	  wild            grows on its own on bare soil and can't be planted (wild grass)
	  energyOnHarvest battery energy the drone gains when it harvests this crop ripe
	  noWater         water() refuses this crop (it never needs it)
	  weatherGrowth   per-weather growth multiplier that REPLACES the weather's normal one
	  shape           procedural look used when no artist model exists (PlotRenderer)
	  color           ripe colour {R, G, B} 0-255 (pure data; the client builds Color3s)

	Factory value (Biomass points per item) lives in GameConfig.Factory.BiomassPoints because
	it is per CURRENCY (fossils are dug, not grown, but are processed the same way).
]]

export type Shape = "grass" | "stalk" | "bush" | "tree" | "flower" | "round" | "cactus"

export type Crop = {
	displayName: string,
	currency: string,
	growSeconds: number,
	yield: number,
	wild: boolean?,
	energyOnHarvest: number?,
	noWater: boolean?,
	weatherGrowth: { [string]: number }?,
	-- Puzzle crop: ripens only inside a complete N x N square of this crop, every tile fully
	-- grown (Progression.Growth.settleSquares; the live farm and simulate() share it).
	square: number?,
	shape: Shape,
	color: { number },
}

local Crops: { [string]: Crop } = {
	grass = {
		displayName = "Wild Grass",
		currency = "hay",
		growSeconds = 8,
		yield = 1,
		wild = true,
		shape = "grass",
		color = { 150, 196, 84 },
	},
	wheat = {
		displayName = "Wheat",
		currency = "wheat",
		growSeconds = 6,
		yield = 2,
		shape = "stalk",
		color = { 232, 196, 92 },
	},
	carrot = {
		displayName = "Carrot",
		currency = "carrot",
		growSeconds = 12,
		yield = 1,
		shape = "bush",
		color = { 240, 128, 48 },
	},
	tree = {
		displayName = "Tree",
		currency = "wood",
		growSeconds = 30,
		yield = 3,
		shape = "tree",
		color = { 74, 140, 70 },
	},
	sunflower = {
		displayName = "Sunflower",
		currency = "sunflower",
		growSeconds = 15,
		yield = 1,
		energyOnHarvest = 8,
		shape = "flower",
		color = { 255, 210, 60 },
	},
	pumpkin = {
		displayName = "Pumpkin",
		currency = "pumpkin",
		growSeconds = 25,
		yield = 1,
		-- A single pumpkin never ripens: plant a 2 x 2 of them. can_harvest() is False until the
		-- whole square is grown; harvesting a waiting pumpkin destroys it (the other three keep
		-- waiting for a new fourth).
		square = 2,
		shape = "round",
		color = { 255, 150, 20 },
	},
	cactus = {
		displayName = "Cactus",
		currency = "cactus",
		growSeconds = 20,
		yield = 2,
		noWater = true,
		weatherGrowth = { Drought = 1.5 },
		shape = "cactus",
		color = { 96, 176, 92 },
	},
}

-- Display order (Tech Tree / UI). Plantable = every non-wild crop, used for suggestions.
local Order: { string } = { "grass", "wheat", "carrot", "tree", "sunflower", "pumpkin", "cactus" }
local Plantable: { string } = {}
for _, id in Order do
	if Crops[id].wild ~= true then
		table.insert(Plantable, id)
	end
end

-- currency id -> crop id (each raw currency comes from at most one crop)
local ByCurrency: { [string]: string } = {}
for id, crop in Crops do
	assert(ByCurrency[crop.currency] == nil, "Two crops produce " .. crop.currency)
	ByCurrency[crop.currency] = id
end

local CropConfig = {
	Crops = Crops,
	Order = Order,
	Plantable = Plantable,
	ByCurrency = ByCurrency,
	WildCrop = "grass", -- what bare soil regrows into (GameConfig.Grass)
	SproutColor = { 110, 200, 90 },
	-- Soil albedo per state (docs/ART_BIBLE.md §1.4). Only used while no artist
	-- MaterialVariant exists for the state (Client.Visuals.SoilLook).
	SoilColor = { 138, 101, 68 }, -- SoilDry: Soil Dry base #8A6544
	TilledSoilColor = { 110, 74, 47 }, -- SoilTilled: Tilled ridge #6E4A2F
	WetSoilColor = { 74, 51, 36 }, -- SoilWet: Soil Wet base #4A3324
}

return CropConfig
