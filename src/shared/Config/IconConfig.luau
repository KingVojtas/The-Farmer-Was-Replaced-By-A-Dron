--!strict
--[[
	IconConfig
	==========
	Every icon the UI shows, in ONE place. Each entry has:

	  assetId  Roblox image asset id (a number). 0 = not uploaded yet.
	           Upload the PNG (Studio Asset Manager or Creator Dashboard -> Development Items ->
	           Decals/Images), copy its ASSET id and paste it here. The UI turns it into
	           "rbxassetid://<id>" on an ImageLabel automatically.
	  emoji    fallback drawn inside the same ImageLabel while assetId is 0 (or if the image
	           fails to load), so every screen is fully illustrated from day one.
	  color    {R, G, B} 0-255: the icon tile's tint, glow and the colour of pulses / "+N" text
	  overlay  optional short text stamped on the icon (e.g. "2x")

	Recommended source art: 256 x 256 PNG, transparent background, flat stylised icon that
	reads at 20 px (see docs/UI_UX_GUIDE.md "Iconography").

	ROBUX uses Roblox's own Robux icon that ships inside every client
	(rbxasset://textures/ui/common/robux.png - the same image Roblox's purchase prompts use),
	so buy buttons show the official icon without any upload. It is white; the UI tints it.

	Pure data: no Roblox APIs (the offline tests validate it).
]]

export type IconDef = {
	assetId: number,
	emoji: string,
	color: { number },
	overlay: string?,
}

local ROBUX_IMAGE = "rbxasset://textures/ui/common/robux.png"
-- The generated-icon atlas (art/IconAtlas.png + this generated module): tools/build_icon_atlas.py.
local IconAtlas = require(script.Parent.IconAtlas)

local Icons: { [string]: IconDef } = {
	------------------------------------------------------------- currencies (key = currency id)
	hay = { assetId = 0, emoji = "🌿", color = { 214, 196, 120 } },
	wheat = { assetId = 0, emoji = "🌾", color = { 232, 196, 92 } },
	carrot = { assetId = 0, emoji = "🥕", color = { 240, 128, 48 } },
	wood = { assetId = 0, emoji = "🌲", color = { 156, 108, 66 } },
	sunflower = { assetId = 0, emoji = "🌻", color = { 255, 210, 60 } },
	pumpkin = { assetId = 0, emoji = "🎃", color = { 255, 150, 20 } },
	cactus = { assetId = 0, emoji = "🌵", color = { 96, 176, 92 } },
	fossil = { assetId = 0, emoji = "🦴", color = { 222, 214, 196 } },
	biomass = { assetId = 0, emoji = "♻️", color = { 127, 217, 98 } },
	biofuel = { assetId = 0, emoji = "⛽", color = { 64, 200, 180 } },
	batteries = { assetId = 0, emoji = "💎", color = { 102, 204, 255 } }, -- premium: Lithium Batteries

	------------------------------------------------------------------------ drone & world
	energy = { assetId = 0, emoji = "⚡", color = { 140, 255, 90 } },
	water = { assetId = 0, emoji = "💧", color = { 102, 204, 255 } },
	cargo = { assetId = 0, emoji = "📦", color = { 255, 196, 87 } },
	weather_Sunny = { assetId = 0, emoji = "☀️", color = { 255, 214, 102 } },
	weather_Rainy = { assetId = 0, emoji = "🌧️", color = { 102, 178, 255 } },
	weather_Drought = { assetId = 0, emoji = "🔥", color = { 255, 140, 90 } },

	------------------------------------------------------------------------ status badges
	lock = { assetId = 0, emoji = "🔒", color = { 128, 142, 162 } },
	check = { assetId = 0, emoji = "✅", color = { 127, 217, 98 } },
	star = { assetId = 0, emoji = "⭐", color = { 255, 214, 102 } },

	--------------------------------------------------------------------- tech tree nodes
	loop = { assetId = 0, emoji = "🔁", color = { 255, 214, 102 } },
	grid = { assetId = 0, emoji = "🗺️", color = { 255, 214, 102 } },
	tree = { assetId = 0, emoji = "🌳", color = { 74, 140, 70 } },
	watering_can = { assetId = 0, emoji = "🚿", color = { 102, 204, 255 } },
	print = { assetId = 0, emoji = "💬", color = { 102, 204, 255 } },
	speed = { assetId = 0, emoji = "⏩", color = { 102, 204, 255 } },
	clock = { assetId = 0, emoji = "⏰", color = { 102, 204, 255 } },
	simulate = { assetId = 0, emoji = "🧪", color = { 102, 204, 255 } },
	battery_pack = { assetId = 0, emoji = "🔋", color = { 140, 255, 90 } },
	charger = { assetId = 0, emoji = "🔌", color = { 60, 220, 255 } },
	factory = { assetId = 0, emoji = "🏭", color = { 77, 255, 176 } },
	drone = { assetId = 0, emoji = "🛸", color = { 102, 204, 255 } },
	motor = { assetId = 0, emoji = "⚙️", color = { 142, 154, 166 } },
	paint = { assetId = 0, emoji = "🎨", color = { 255, 61, 203 } },
	hat = { assetId = 0, emoji = "🎩", color = { 196, 140, 255 } },
	math = { assetId = 0, emoji = "➕", color = { 196, 140, 255 } },
	coordinates = { assetId = 0, emoji = "📍", color = { 196, 140, 255 } },
	variable = { assetId = 0, emoji = "🏷️", color = { 196, 140, 255 } },
	list = { assetId = 0, emoji = "📋", color = { 196, 140, 255 } },
	["function"] = { assetId = 0, emoji = "🧩", color = { 196, 140, 255 } },
	dictionary = { assetId = 0, emoji = "📖", color = { 196, 140, 255 } },
	import = { assetId = 0, emoji = "📥", color = { 196, 140, 255 } },
	random = { assetId = 0, emoji = "🎲", color = { 196, 140, 255 } },
	cost = { assetId = 0, emoji = "🧾", color = { 196, 140, 255 } },

	------------------------------------------------------------------- shop products
	vip_crown = { assetId = 0, emoji = "👑", color = { 255, 214, 102 } },
	memory = { assetId = 0, emoji = "💾", color = { 102, 204, 255 } },
	yield_2x = { assetId = 0, emoji = "🌾", color = { 255, 214, 102 }, overlay = "2x" },
	overclock = { assetId = 0, emoji = "⚡", color = { 255, 196, 87 } },
	starter_pack = { assetId = 0, emoji = "🎁", color = { 255, 214, 102 } },
	boost_micro = { assetId = 0, emoji = "🌱", color = { 127, 217, 98 } },
	boost_grid = { assetId = 0, emoji = "🚀", color = { 127, 217, 98 } },

	----------------------------------------------------------------------------- hats
	hat_antenna = { assetId = 0, emoji = "📡", color = { 200, 60, 60 } },
	hat_straw = { assetId = 0, emoji = "👒", color = { 228, 196, 120 } },
	hat_propeller = { assetId = 0, emoji = "🧢", color = { 70, 130, 230 } },
	hat_tophat = { assetId = 0, emoji = "🎩", color = { 160, 160, 170 } },
	hat_halo = { assetId = 0, emoji = "😇", color = { 255, 236, 140 } },

	------------------------------------------------------------------------ navigation
	tech_tree = { assetId = 0, emoji = "🔬", color = { 127, 217, 98 } },
	shop = { assetId = 0, emoji = "🛒", color = { 255, 214, 102 } },
	hangar = { assetId = 0, emoji = "🛸", color = { 102, 204, 255 } },
	unknown = { assetId = 0, emoji = "❔", color = { 128, 142, 162 } },
}

local IconConfig = {}

IconConfig.Icons = Icons
IconConfig.ROBUX_IMAGE = ROBUX_IMAGE

--[[
	ICON ATLAS: ONE texture for every generated icon (never one TextureId per icon). Cells are
	128 px, 8 per row, in this order (tools/build_icon_atlas.py packs art/icons/<key>.png in it).
	IconAtlas.cells lists only keys that HAVE art; with IconAtlas.assetId = 0 (not uploaded)
	or no cell, a key keeps its emoji. A dedicated per-icon assetId above still wins.
]]
IconConfig.AtlasOrder = {
	"hay",
	"wheat",
	"carrot",
	"wood",
	"sunflower",
	"pumpkin",
	"cactus",
	"fossil",
	"biomass",
	"biofuel",
	"batteries",
	"loop",
	"grid",
	"water",
	"print",
	"speed",
	"clock",
	"simulate",
	"cargo",
	"paint",
	"hat",
	"math",
	"list",
	"function",
	"dictionary",
	"random",
	"import",
	"weather_Sunny",
	"weather_Rainy",
	"weather_Drought",
	"charger",
	"factory",
	"drone",
} :: { string }
IconConfig.Atlas = IconAtlas

export type AtlasRect = { x: number, y: number, size: number }

-- Where a key's art sits in the UPLOADED atlas (pixels), or nil: not uploaded / no art for it.
function IconConfig.atlasRect(key: string?): AtlasRect?
	if key == nil or IconAtlas.assetId <= 0 then
		return nil
	end
	local index = IconAtlas.cells[key]
	if index == nil then
		return nil
	end
	return {
		x = (index % IconAtlas.columns) * IconAtlas.cell,
		y = math.floor(index / IconAtlas.columns) * IconAtlas.cell,
		size = IconAtlas.cell,
	}
end

-- The definition for a key (never nil: unknown keys get the "?" icon).
function IconConfig.get(key: string?): IconDef
	return (if key ~= nil then Icons[key] else nil) or Icons.unknown
end

-- "rbxassetid://<id>" for an uploaded icon (its own upload, else the atlas; Icon.luau then
-- crops the atlas with atlasRect), or "" while it is still a placeholder.
function IconConfig.image(key: string?): string
	local def = IconConfig.get(key)
	if def.assetId > 0 then
		return "rbxassetid://" .. tostring(def.assetId)
	end
	if IconConfig.atlasRect(key) ~= nil then
		return "rbxassetid://" .. tostring(IconAtlas.assetId)
	end
	return ""
end

-- Currency ids are icon keys.
function IconConfig.forCurrency(currencyId: string): string
	return if Icons[currencyId] ~= nil then currencyId else "unknown"
end

function IconConfig.forWeather(weather: string): string
	local key = "weather_" .. weather
	return if Icons[key] ~= nil then key else "weather_Sunny"
end

-- Checks the table (used by the tests). Returns { problem, ... }.
function IconConfig.validate(): { string }
	local problems: { string } = {}
	for key, def in Icons do
		if type(def.assetId) ~= "number" or def.assetId < 0 or def.assetId % 1 ~= 0 then
			table.insert(problems, key .. ": assetId must be a whole number >= 0")
		end
		if type(def.emoji) ~= "string" or def.emoji == "" then
			table.insert(problems, key .. ": needs an emoji fallback")
		end
		if type(def.color) ~= "table" or #def.color ~= 3 then
			table.insert(problems, key .. ": color must be {R, G, B}")
		end
	end
	-- The atlas: every cell key is a real icon, at its AtlasOrder position, inside the texture.
	local position: { [string]: number } = {}
	for index, key in IconConfig.AtlasOrder do
		if Icons[key] == nil then
			table.insert(problems, "AtlasOrder: unknown icon " .. key)
		end
		if position[key] ~= nil then
			table.insert(problems, "AtlasOrder: " .. key .. " listed twice")
		end
		position[key] = index - 1
	end
	local capacity = (IconAtlas.width // IconAtlas.cell) * (IconAtlas.height // IconAtlas.cell)
	for key, index in IconAtlas.cells do
		if position[key] ~= index then
			table.insert(
				problems,
				"IconAtlas: " .. key .. " is not in its AtlasOrder cell (rebuild the atlas)"
			)
		end
		if index >= capacity then
			table.insert(problems, "IconAtlas: " .. key .. " lies outside the texture")
		end
	end
	return problems
end

return IconConfig
