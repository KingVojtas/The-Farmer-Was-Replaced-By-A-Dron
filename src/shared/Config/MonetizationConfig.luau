--!strict
--[[
	MonetizationConfig
	==================
	Gamepasses and Developer Products as DATA. ReceiptProcessor reads the `grants` lists,
	so adding or rebalancing a product never needs new code.

	!! IDs: every `id = 0` is a placeholder. Create the pass/product on the Creator Dashboard
	   (Monetization -> Passes / Developer Products) and paste its ID here. The server prints
	   a warning at startup for every product or pass that still has id 0, and an unknown
	   product is never granted (Roblox keeps retrying it until the ID is configured).

	Grant kinds:
	  { kind = "currency", currency = <id from Currencies>, amount = <integer> }
	  { kind = "boost",    boost = "growth" | "yield", seconds = <integer> }
	Buying a boost while it is active extends it from whichever is later: now or its end time.

	SHOP DISPLAY (read by the client ShopController only - never by grant logic)
	  category    "currency" | "boost" | "bundle" (products) - which Shop tab lists it
	  description one or two short lines for the card
	  badge       optional ribbon text ("BEST VALUE", "POPULAR", "LIMITED")
	  order       sort order inside its tab
	  icon        icon key in Config.IconConfig (the big picture on the Shop card)
	The price shown is fetched live with MarketplaceService:GetProductInfo (cached); `price`
	here is only the fallback when that call fails.
]]

export type Grant = {
	kind: string,
	currency: string?,
	amount: number?,
	boost: string?,
	seconds: number?,
}

export type Product = {
	id: number,
	price: number, -- Robux, informational (the real price is set on the dashboard)
	name: string,
	category: "currency" | "boost" | "bundle",
	description: string,
	badge: string?,
	order: number,
	icon: string,
	grants: { Grant },
	-- One-time products: a repeat purchase (only possible through a race or an exploit-made
	-- prompt) grants `fallbackGrants` instead, so the player always receives value.
	oncePerPlayer: boolean?,
	fallbackGrants: { Grant }?,
	offerSeconds: number?, -- how long after first join the store UI offers it
}

export type GamePass = {
	id: number,
	price: number,
	name: string,
	description: string,
	perks: { string }, -- bullet points on the Shop card
	badge: string?,
	order: number,
	icon: string,
}

local MonetizationConfig = {}

-- Timed boosts bought with Developer Products.
MonetizationConfig.Boosts = {
	growth = { multiplier = 2 }, -- crops grow 2x faster
	yield = { multiplier = 1.5 }, -- harvests pay 1.5x
}

-- Gamepass perks (read by GamepassService:GetPerks).
MonetizationConfig.Perks = {
	ExpandedMemoryExtraLines = 50,
	DoubleYieldMultiplier = 2,
	OverclockSpeedMultiplier = 1.5,
}

local GamePasses: { [string]: GamePass } = {
	VIP = {
		id = 0,
		price = 149,
		name = "VIP Terminal & Cosmetics",
		description = "Stand out on every farm.",
		perks = { "Gold VIP tag on your farm sign", "VIP terminal theme" },
		order = 1,
		icon = "vip_crown",
	},
	ExpandedMemory = {
		id = 0,
		price = 299,
		name = "Expanded Memory",
		description = "Room for bigger programs.",
		perks = { "+50 lines in every script slot" },
		order = 2,
		icon = "memory",
	},
	DoubleYield = {
		id = 0,
		price = 399,
		name = "2x Harvest Yield",
		description = "Every ripe harvest pays double.",
		perks = { "2x items from every crop" },
		badge = "POPULAR",
		order = 3,
		icon = "yield_2x",
	},
	Overclock = {
		id = 0,
		price = 599,
		name = "Overclock Module",
		description = "A faster drone, forever.",
		perks = { "Every drone action 50% faster", "Stacks with Servo Motors" },
		badge = "BEST",
		order = 4,
		icon = "overclock",
	},
}
MonetizationConfig.GamePasses = GamePasses

local MINUTE = 60
local HOUR = 60 * MINUTE

local Products: { [string]: Product } = {
	MicroBoost = {
		id = 0,
		price = 19,
		name = "Micro Boost",
		category = "boost",
		description = "Crops grow 2x faster for 10 minutes.",
		order = 1,
		icon = "boost_micro",
		grants = {
			{ kind = "boost", boost = "growth", seconds = 10 * MINUTE },
		},
	},
	GridBoost = {
		id = 0,
		price = 89,
		name = "Grid Boost",
		category = "boost",
		description = "2x growth and 1.5x yield for 30 minutes.",
		badge = "POPULAR",
		order = 2,
		icon = "boost_grid",
		grants = {
			{ kind = "boost", boost = "growth", seconds = 30 * MINUTE },
			{ kind = "boost", boost = "yield", seconds = 30 * MINUTE },
		},
	},
	BatteriesHandful = {
		id = 0,
		price = 49,
		name = "Handful of Lithium Batteries",
		category = "currency",
		description = "100 Lithium Batteries.",
		order = 1,
		icon = "batteries",
		grants = { { kind = "currency", currency = "batteries", amount = 100 } },
	},
	BatteriesBox = {
		id = 0,
		price = 199,
		name = "Box of Lithium Batteries",
		category = "currency",
		description = "450 Lithium Batteries.",
		order = 2,
		icon = "batteries",
		grants = { { kind = "currency", currency = "batteries", amount = 450 } },
	},
	BatteriesContainer = {
		id = 0,
		price = 499,
		name = "Container of Lithium Batteries",
		category = "currency",
		description = "1,250 Lithium Batteries.",
		badge = "POPULAR",
		order = 3,
		icon = "batteries",
		grants = { { kind = "currency", currency = "batteries", amount = 1250 } },
	},
	BatteriesReactor = {
		id = 0,
		price = 1499,
		name = "Lithium Reactor",
		category = "currency",
		description = "4,000 Lithium Batteries.",
		badge = "BEST VALUE",
		order = 4,
		icon = "batteries",
		grants = { { kind = "currency", currency = "batteries", amount = 4000 } },
	},
	StarterPack = {
		id = 0,
		price = 249,
		name = "Starter Pack",
		category = "bundle",
		description = "750 Batteries, 200 Hay and 30 minutes of every boost.",
		badge = "LIMITED",
		order = 1,
		icon = "starter_pack",
		oncePerPlayer = true,
		offerSeconds = 48 * HOUR,
		grants = {
			{ kind = "currency", currency = "batteries", amount = 750 },
			{ kind = "currency", currency = "hay", amount = 200 },
			{ kind = "boost", boost = "growth", seconds = 30 * MINUTE },
			{ kind = "boost", boost = "yield", seconds = 30 * MINUTE },
		},
		fallbackGrants = {
			{ kind = "currency", currency = "batteries", amount = 750 },
		},
	},
}
MonetizationConfig.Products = Products

return MonetizationConfig
