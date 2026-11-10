--!strict
--[[
	RemoteSchema
	============
	The single source of truth for every remote in the game. NetService (server) creates the
	RemoteEvent/RemoteFunction instances from this table, and the client Net module looks them
	up by the same names, so names can never drift apart.

	direction:
	  "ClientToServer" - the client may call it; the server validates + rate limits.
	  "ServerToClient" - only the server fires it. A client firing it is logged as a violation.

	rate: token bucket per player per remote. `burst` = requests allowed back-to-back,
	      `perSecond` = sustained refill. (A global per-player budget applies on top, see
	      GameConfig.Net.)
	args: exact list of validators (argument count must match).
]]

local CosmeticConfig = require(script.Parent.Parent.Config.CosmeticConfig)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Tech = require(script.Parent.Parent.Progression.Tech)
local Validate = require(script.Parent.Validate)

export type RemoteDef = {
	kind: "Event" | "Function",
	direction: "ClientToServer" | "ServerToClient",
	rate: { burst: number, perSecond: number }?,
	args: { Validate.Validator }?,
}

local slot = Validate.integer(1, GameConfig.Script.Slots)
local source = Validate.string(GameConfig.Script.MaxSourceBytes)

local Schema: { [string]: RemoteDef } = {
	-- Save + compile + run a program. Returns { ok = true } or { ok = false, error = {...} }.
	RunScript = {
		kind = "Function",
		direction = "ClientToServer",
		rate = { burst = 3, perSecond = 0.5 },
		args = { slot, source },
	},
	-- Save a program without running it (editor autosave).
	SaveScript = {
		kind = "Function",
		direction = "ClientToServer",
		rate = { burst = 4, perSecond = 0.5 },
		args = { slot, source },
	},
	-- Stop the running program.
	StopScript = {
		kind = "Event",
		direction = "ClientToServer",
		rate = { burst = 5, perSecond = 2 },
		args = {},
	},
	-- Fetch saved scripts once the player's data has loaded.
	GetScripts = {
		kind = "Function",
		direction = "ClientToServer",
		rate = { burst = 2, perSecond = 0.2 },
		args = {},
	},

	-- Rename a script slot (its module name for `import`). The server re-validates the name
	-- (identifier, unique, not reserved) with Shared.DroneScript.ScriptNames.
	RenameScript = {
		kind = "Function",
		direction = "ClientToServer",
		rate = { burst = 3, perSecond = 0.5 },
		args = { slot, Validate.string(GameConfig.Script.MaxNameLength * 4) },
	},

	-- Research a Tech Tree node. The argument must be an existing node id (enum check), the
	-- server then verifies prerequisites and the full multi-currency cost.
	Research = {
		kind = "Function",
		direction = "ClientToServer",
		rate = { burst = 4, perSecond = 1 },
		args = { Validate.enum(Tech.NodeIds) },
	},

	-- Drone Hangar (Shop): buy a premium cosmetic with Lithium Batteries / equip one.
	BuyCosmetic = {
		kind = "Function",
		direction = "ClientToServer",
		rate = { burst = 3, perSecond = 0.5 },
		args = { Validate.enum(CosmeticConfig.Ids) },
	},
	EquipCosmetic = {
		kind = "Function",
		direction = "ClientToServer",
		rate = { burst = 5, perSecond = 1 },
		args = { Validate.enum(CosmeticConfig.Slots :: any), Validate.enum(CosmeticConfig.Ids) },
	},

	-- Server -> client
	ScriptOutput = { kind = "Event", direction = "ServerToClient" }, -- (kind, text)
	ScriptStatus = { kind = "Event", direction = "ServerToClient" }, -- (status, line)
	-- Plot index, cell x, cell y, move duration. Attributes alone parked the drone.
	DroneMoved = { kind = "Event", direction = "ServerToClient" },
	PurchaseGranted = { kind = "Event", direction = "ServerToClient" }, -- (productKey)
	Notify = { kind = "Event", direction = "ServerToClient" }, -- (kind, text) toast
}

return table.freeze(Schema)
