--!strict
--[[
	Currencies
	==========
	Every currency a player can own. Tech Tree costs, product grants, the cargo hold and the
	inventory all refer to currencies by these ids.

	  raw       - farmed resources, banked when the drone unloads at the Charging Station.
	              Each one has exactly one SOURCE: a crop whose `currency` is this id
	              (CropConfig), or digging (GameConfig.Dig.currency). Checked by Tech.validate.
	  processed - made at the Factory (deposit() -> Biomass, refine() -> Biofuel)
	  premium   - bought with Robux (Lithium Batteries); spent on cosmetics in the Shop

	`color` ({R, G, B} 0-255, keeps this module pure) and `glyph` (a short text badge) are only
	for the UI: the HUD currency stack, cost chips and shop prices.
	List order = display order everywhere (HUD, cost strings).
]]

export type Kind = "raw" | "processed" | "premium"

export type Currency = {
	id: string,
	name: string,
	kind: Kind,
	color: { number },
	glyph: string,
}

local List: { Currency } = {
	{ id = "hay", name = "Hay", kind = "raw", color = { 214, 196, 120 }, glyph = "HY" },
	{ id = "wheat", name = "Wheat", kind = "raw", color = { 232, 196, 92 }, glyph = "WH" },
	{ id = "carrot", name = "Carrots", kind = "raw", color = { 240, 128, 48 }, glyph = "CR" },
	{ id = "wood", name = "Wood", kind = "raw", color = { 156, 108, 66 }, glyph = "WD" },
	{ id = "sunflower", name = "Sunflowers", kind = "raw", color = { 255, 210, 60 }, glyph = "SF" },
	{ id = "pumpkin", name = "Pumpkins", kind = "raw", color = { 255, 150, 20 }, glyph = "PK" },
	{ id = "cactus", name = "Cacti", kind = "raw", color = { 96, 176, 92 }, glyph = "CT" },
	{ id = "fossil", name = "Fossils", kind = "raw", color = { 222, 214, 196 }, glyph = "FS" },
	{ id = "biomass", name = "Biomass", kind = "processed", color = { 127, 217, 98 }, glyph = "BM" },
	{ id = "biofuel", name = "Biofuel", kind = "processed", color = { 64, 200, 180 }, glyph = "BF" },
	{
		id = "batteries",
		name = "Lithium Batteries",
		kind = "premium",
		color = { 102, 204, 255 },
		glyph = "Li",
	},
}

local ById: { [string]: Currency } = {}
local Ids: { string } = {}
for _, currency in List do
	assert(ById[currency.id] == nil, "Duplicate currency " .. currency.id)
	table.freeze(currency.color)
	ById[currency.id] = table.freeze(currency)
	table.insert(Ids, currency.id)
end

return table.freeze({
	List = table.freeze(List),
	ById = table.freeze(ById),
	Ids = table.freeze(Ids),
})
