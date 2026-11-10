--!strict
--[[
	CosmeticConfig
	==============
	Drone "clothing": paint jobs and hats. Purely visual - no cosmetic changes gameplay.

	UNLOCK KINDS
	  free     owned by everyone (the defaults)
	  tech     owned once the Tech Tree node that unlocks `feature` is researched
	           ("cosmetic:paint" = Paint Shop, "cosmetic:hat" = Drone Wardrobe)
	  premium  bought once with Lithium Batteries in the Shop (Drone Hangar tab); the
	           server checks the price against SAVED currencies and records the ownership in
	           the same profile record (Progression.Cosmetics)

	Look data stays pure ({R, G, B} 0-255); PlotRenderer turns it into Color3s / parts.
	  paint: primary (body), secondary (arms), accent (eye / light), material name
	  hat:   style (procedural model built by the client) + color
]]

export type Slot = "paint" | "hat"

export type Unlock = { kind: "free" } | { kind: "tech", feature: string } | { kind: "premium", price: number }

export type Cosmetic = {
	id: string,
	slot: Slot,
	name: string,
	description: string,
	unlock: Unlock,
	order: number,
	-- paint
	primary: { number }?,
	secondary: { number }?,
	accent: { number }?,
	material: string?,
	-- hat
	style: string?,
	color: { number }?,
}

local List: { Cosmetic } = {
	---------------------------------------------------------------- paint jobs
	{
		id = "factory",
		slot = "paint",
		name = "Factory Grey",
		description = "Fresh off the assembly line.",
		unlock = { kind = "free" },
		order = 1,
		primary = { 30, 37, 48 }, -- docs/ART_BIBLE.md hull dark #1E2530
		secondary = { 46, 56, 70 }, -- hull mid #2E3846
		accent = { 127, 217, 98 },
		material = "Metal",
	},
	{
		id = "meadow",
		slot = "paint",
		name = "Meadow",
		description = "Soft greens for a calm farmer.",
		unlock = { kind = "tech", feature = "cosmetic:paint" },
		order = 2,
		primary = { 92, 150, 84 },
		secondary = { 60, 98, 56 },
		accent = { 255, 230, 120 },
		material = "SmoothPlastic",
	},
	{
		id = "sunset",
		slot = "paint",
		name = "Sunset",
		description = "Warm orange with a pink glow.",
		unlock = { kind = "tech", feature = "cosmetic:paint" },
		order = 3,
		primary = { 232, 120, 64 },
		secondary = { 150, 70, 52 },
		accent = { 255, 140, 190 },
		material = "SmoothPlastic",
	},
	{
		id = "arctic",
		slot = "paint",
		name = "Arctic",
		description = "Ice white with a cyan visor.",
		unlock = { kind = "tech", feature = "cosmetic:paint" },
		order = 4,
		primary = { 226, 234, 242 },
		secondary = { 150, 168, 186 },
		accent = { 90, 220, 255 },
		material = "SmoothPlastic",
	},
	{
		id = "neon_night",
		slot = "paint",
		name = "Neon Night",
		description = "Midnight chassis, glowing magenta trim.",
		unlock = { kind = "premium", price = 150 },
		order = 5,
		primary = { 24, 22, 40 },
		secondary = { 60, 40, 96 },
		accent = { 255, 60, 200 },
		material = "Metal",
	},
	{
		id = "gold_plated",
		slot = "paint",
		name = "Gold Plated",
		description = "For farmers who have made it.",
		unlock = { kind = "premium", price = 400 },
		order = 6,
		primary = { 230, 180, 60 },
		secondary = { 168, 124, 40 },
		accent = { 255, 250, 220 },
		material = "Metal",
	},

	---------------------------------------------------------------- hats
	{
		id = "none",
		slot = "hat",
		name = "No Hat",
		description = "Classic and aerodynamic.",
		unlock = { kind = "free" },
		order = 1,
	},
	{
		id = "antenna",
		slot = "hat",
		name = "Radio Antenna",
		description = "Picks up the farm report.",
		unlock = { kind = "tech", feature = "cosmetic:hat" },
		order = 2,
		style = "antenna",
		color = { 200, 60, 60 },
	},
	{
		id = "straw_hat",
		slot = "hat",
		name = "Straw Hat",
		description = "Every farmer needs one.",
		unlock = { kind = "tech", feature = "cosmetic:hat" },
		order = 3,
		style = "straw",
		color = { 228, 196, 120 },
	},
	{
		id = "propeller_cap",
		slot = "hat",
		name = "Propeller Cap",
		description = "A spare rotor, just in case.",
		unlock = { kind = "premium", price = 250 },
		order = 4,
		style = "propeller",
		color = { 70, 130, 230 },
	},
	{
		id = "top_hat",
		slot = "hat",
		name = "Top Hat",
		description = "Distinguished drone, distinguished harvest.",
		unlock = { kind = "premium", price = 200 },
		order = 5,
		style = "tophat",
		color = { 30, 30, 36 },
	},
	{
		id = "halo",
		slot = "hat",
		name = "Halo",
		description = "An angel of agriculture.",
		unlock = { kind = "premium", price = 350 },
		order = 6,
		style = "halo",
		color = { 255, 236, 140 },
	},
}

local ById: { [string]: Cosmetic } = {}
local Ids: { string } = {}
local BySlot: { [string]: { Cosmetic } } = { paint = {}, hat = {} }
for _, item in List do
	assert(ById[item.id] == nil, "Duplicate cosmetic " .. item.id)
	ById[item.id] = item
	table.insert(Ids, item.id)
	table.insert(BySlot[item.slot], item)
end
for _, items in BySlot do
	table.sort(items, function(a: Cosmetic, b: Cosmetic): boolean
		return a.order < b.order
	end)
end

return {
	List = List,
	ById = ById,
	Ids = Ids,
	BySlot = BySlot,
	Slots = { "paint", "hat" } :: { Slot },
	Defaults = { paint = "factory", hat = "none" } :: { [string]: string },
}
