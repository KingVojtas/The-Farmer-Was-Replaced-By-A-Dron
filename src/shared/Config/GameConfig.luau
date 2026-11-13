--!strict
--[[
	GameConfig
	==========
	Every tuning number in one place. Shared by server AND client (the client uses the
	script limits to pre-check code before sending it).

	This module is pure data: no Roblox APIs, so the offline Lune tests can load it.
	Positions/colors are plain numbers; the modules that build Instances convert them.
]]

local GameConfig = {}

-- The program every new player finds in their first script slot. It only uses commands that
-- are free from the start (loops, variables etc. are Tech Tree research).
GameConfig.StarterScript = table.concat({
	"# Welcome, farmer! Press RUN to start your drone.",
	"# Lines starting with # are notes - the drone ignores them.",
	"# Wild grass grows on your field by itself. Harvest it for Hay,",
	"# then fly back to the charger at (0, -1) to unload it into your silo.",
	"",
	"move_up()",
	"harvest()",
	"move_right()",
	"harvest()",
	"move_right()",
	"harvest()",
	"move_left()",
	"move_left()",
	"move_down()",
	"charge()  # back on the charger: refill the battery",
}, "\n")

GameConfig.Grid = {
	StartingSize = 3, -- new players get a 3x3 field; Grid Expansion research grows it (Tech.stats)
	MinSize = 3,
	MaxSize = 10,
	TileSize = 6, -- studs (X and Z)
	TileGap = 0.4, -- studs between tiles
	TileHeight = 0.6,
	--[[
		Plot slots: the farm village. The spawn village sits in the middle of a 5 x 5 grid of farms
		(slot centres 120 studs apart in x, 128 in z, so a full 10 x 10 field plus its zone never
		touches a neighbour and 40+ stud roads run between them). Slots fill in this order: the
		8 farms right around the village first (N, S, E, W, then the corners), then the outer
		ring. { x, z } = the plot centre GridService builds the field around. The map
		(tools/build_map.luau) keeps every slot free, so a server needs MaxPlayers <= #PlotSlots.
	]]
	PlotSlots = {
		{ 0, -128 },
		{ 0, 128 },
		{ 120, 0 },
		{ -120, 0 },
		{ 120, -128 },
		{ -120, -128 },
		{ 120, 128 },
		{ -120, 128 },
		{ 0, -256 },
		{ 0, 256 },
		{ 240, 0 },
		{ -240, 0 },
		{ 120, -256 },
		{ -120, -256 },
		{ 120, 256 },
		{ -120, 256 },
		{ 240, -128 },
		{ -240, -128 },
		{ 240, 128 },
		{ -240, 128 },
		{ 240, -256 },
		{ -240, -256 },
		{ 240, 256 },
		{ -240, 256 },
	},
	-- Only for slots past #PlotSlots (a server bigger than the map): the old rows, far north.
	PlotSpacing = 90, -- distance between neighbouring plot centers
	PlotsPerRow = 4,
	PlotRowOffset = 60, -- first row of plots starts this far from the world origin (keeps spawn clear)
	OverflowOffset = 900, -- overflow rows start this far north of the map
	GrowthTickSeconds = 0.25, -- how often the server advances crop growth
	SproutProgress = 0.15, -- growth progress at which "planted" becomes "growing"
	-- Rain doesn't replace watering: a dry crop is watered after this much rain, so fast crops
	-- (wheat grows in 6 s) still want water() from the tank.
	RainSoakSeconds = 12,
	WateredGrowthMultiplier = 2, -- watered crops grow this much faster
}

--[[
	Off-field stations. The drone can stand on field tiles and on these cells; everything else
	is blocked (no wrap-around). Both sit just below the field's bottom row, so they are
	reachable from any field size: (0, 0) -> move_down() -> charger, charger -> move_right() -> factory.
]]
GameConfig.Stations = {
	charger = { x = 0, y = -1, name = "Charging Station" },
	factory = { x = 1, y = -1, name = "Factory" },
}

GameConfig.Drone = {
	-- Seconds each action takes (divided by the drone's speed multiplier).
	ActionTimes = {
		move = 0.4,
		plant = 0.5,
		water = 0.4,
		harvest = 0.5,
		deposit = 1.0,
		refine = 1.5,
		charge = 0.5, -- minimum; charging an empty battery takes longer
		dig = 1.0,
		failed = 0.3, -- an action that did nothing still costs time (no zero-cost busy loops)
	},
	-- Battery energy each action uses. Sensors and print() are free.
	EnergyCosts = {
		move = 1,
		plant = 1,
		water = 1,
		harvest = 1,
		deposit = 2,
		refine = 2,
		dig = 2,
	},
	BaseBattery = 50,
	BaseWater = 10,
	BaseCargo = 10,
	BaseChargeRate = 25, -- energy per second at the Charging Station
	LimpSlowdown = 4, -- moves take this many times longer with an empty battery
	HoverHeight = 5, -- studs above the tile surface
	TweenFraction = 0.85, -- the client tween finishes slightly before the next action starts
	-- set_speed(s): actions take (time / s) and cost (energy * s). Turbo trades battery for time.
	Throttle = { Min = 0.5, Max = 2, Default = 1 },
}

--[[
	Wild grass: bare soil that stays untouched for RegrowDelay seconds sprouts wild grass
	(CropConfig.WildCrop), which then grows like any crop. New tiles start fully grown, so a
	brand-new player can harvest() Hay right away.
]]
GameConfig.Field = {
	-- Saved field (PlayerData.field): away longer than this and growing crops come back fully
	-- grown. No tick replay (Progression.FieldSave).
	OfflineReadySeconds = 2 * 60 * 60,
}

GameConfig.Grass = {
	RegrowDelay = 4,
	NewTilesGrown = true,
}

-- Collision groups (Server.Services.PlotGuardService registers them; GridService assigns).
GameConfig.Collision = {
	Players = "Players", -- every character part
	Tiles = "PlotTiles", -- field tiles: never collide with characters (nobody stands on a farm)
	Barrier = "PlotBarrier", -- invisible walls around each plot Zone: collide with characters only
}

GameConfig.PlotGuard = {
	CheckSeconds = 0.5, -- how often the server looks for guests inside a plot's Zone
	EjectClearance = 4, -- studs past the Zone edge a guest is put back
	BarrierHeight = 16, -- taller than any jump
	SpawnShieldSeconds = 2, -- ForceField on every spawn on your walkway
}

-- dig() (Bones & Fossils research): on BARE soil only (harvest what grows there first), a
-- chance to find a fossil.
GameConfig.Dig = {
	-- Low odds, fossils stay a jackpot (25 Biomass points). With the exhaustion below a
	-- `while True: dig()` sweep earns well under a wheat pipeline.
	Chance = 0.05,
	currency = "fossil",
	yield = 1,
	-- After ANY dig (found or not) the tile is exhausted this long: no wild grass, no planting,
	-- no digging. Progression.Growth tracks it, so the live farm and simulate() agree.
	ExhaustSeconds = 25,
}

GameConfig.Factory = {
	-- Biomass points one item of each raw currency is worth at the Factory (deposit()).
	BiomassPoints = {
		hay = 0, -- wild grass regrows forever: Hay is never Factory feedstock (bank it instead)
		wheat = 1,
		carrot = 3,
		wood = 2,
		sunflower = 3,
		pumpkin = 8,
		cactus = 5,
		fossil = 25, -- "fossil fuel"
	} :: { [string]: number },
	PointsPerBiomass = 5, -- biomass points needed for 1 Biomass
	BiomassPerBiofuel = 4,
	MaxRefineBatches = 10, -- Biofuel made per refine() call at most
}

GameConfig.Weather = {
	-- growth: crop growth multiplier, waterCost: tank units per water(), autoWater: rain soaks dry
	-- crops (each one is watered after Grid.RainSoakSeconds of rain, Progression.Growth)
	Types = {
		Sunny = { growth = 1, waterCost = 1, autoWater = false },
		Rainy = { growth = 1.25, waterCost = 0, autoWater = true },
		Drought = { growth = 0.5, waterCost = 2, autoWater = false },
	},
	Weights = { Sunny = 7, Rainy = 2, Drought = 1 }, -- 70 / 20 / 10 % (repeats allowed; per plot)
	TutorialSunnySeconds = 180, -- a new player's plot is Sunny for at least this long
	Initial = "Sunny",
	MinSeconds = 90,
	MaxSeconds = 180,
}

GameConfig.Script = {
	Slots = 3, -- saved script slots per player
	DefaultNames = { "main", "utils", "lab" }, -- module names used by `import` (renamable)
	MaxNameLength = 16,
	BaseMaxLines = 40, -- "drone memory"; Expanded Memory adds more (see MonetizationConfig)
	MaxLineLength = 120, -- characters per line
	MaxSourceBytes = 12000, -- hard cap on the whole program, checked before anything else
	MaxTokens = 4000,
	MaxNodes = 3000, -- AST nodes
	MaxBlockDepth = 8, -- nested repeat/while/if/for/def
	MaxExprDepth = 16, -- nested brackets / calls / 'not'
	MaxStringLength = 100, -- characters in a "text" literal
	MaxStringResult = 200, -- characters a string built at runtime may reach ("a" + "b")
	MaxIdentifierLength = 32,
	MaxNumber = 1e9, -- largest number LITERAL
	MaxComputed = 1e15, -- largest magnitude a calculation may produce
	MaxRepeat = 1000, -- largest allowed repeat count

	-- CPU budget. Every statement, loop pass and call is one step. After YieldEvery steps the
	-- interpreter waits YieldEvery / StepsPerSecond seconds (task.wait), so ONE player's
	-- program can never use more than StepsPerSecond steps per second, no matter what it does.
	StepsPerSecond = 2000,
	YieldEvery = 100,
	MaxIdleSteps = 20000, -- steps without any drone action => "stuck loop" error
	MaxCallDepth = 32, -- nested function calls (recursion)

	-- Memory budget for lists and dictionaries (checked with a bounded reachability scan).
	MaxContainerItems = 1000, -- items in ONE list or dictionary
	MaxLiveItems = 5000, -- items in all lists/dictionaries the program can still reach
	HeapScanEvery = 1000, -- items created between two scans

	MaxOutputPerSecond = 20, -- print()/hint messages sent to the client
	MaxLineStatusPerSecond = 20, -- ScriptStatus "line" (running-line highlight) updates per player
	MaxOutputLength = 200, -- characters per output message
}

-- simulate(slot, seconds): runs a saved program on a virtual copy of the farm.
GameConfig.Simulate = {
	MaxSeconds = 600, -- largest simulated duration
	MaxSteps = 100000, -- step budget for one simulate() call (still CPU-throttled)
	-- Real seconds every simulate() call takes on the live farm at least (it runs on a virtual
	-- clock, so without this a loop of simulate() calls would cost no time at all).
	MinRealSeconds = 1,
}

GameConfig.Data = {
	StoreName = "PlayerData_v1",
	KeyPrefix = "u_",
	AutosaveSeconds = 90,
	LockStaleSeconds = 300, -- a lock not refreshed for this long belongs to a crashed server
	LoadRetries = 8,
	LoadRetryDelay = 4, -- seconds between attempts while another server holds the lock
	WriteRetries = 3,
	MaxReceiptHistory = 200, -- processed PurchaseIds remembered per player
	ShutdownTimeout = 25, -- BindToClose budget (Roblox allows 30 s)
	ProfileWaitTimeout = 30, -- how long ProcessReceipt waits for a profile to load
}

GameConfig.Net = {
	GlobalBurst = 20, -- per-player budget shared by ALL remotes
	GlobalPerSecond = 10,
	ViolationWindow = 10, -- seconds
	ViolationKickThreshold = 30, -- rejected requests inside the window before a kick
	ClientInvokeTimeout = 15,
}

GameConfig.Debug = {
	-- Grants every gamepass in Studio play-tests only (never in live servers).
	StudioGrantAllPasses = false,
	-- Kick players that keep hammering remotes. Turn off temporarily while debugging limits.
	KickOnAbuse = true,
}

return GameConfig
