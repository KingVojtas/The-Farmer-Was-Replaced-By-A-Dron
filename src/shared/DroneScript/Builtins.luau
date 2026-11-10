--!strict
--[[
	Builtins
	========
	The ONLY functions and methods a drone program can call. This file holds their
	*signatures* (name, parameter types, kind, docs). It is shared so that:
	  * the Parser rejects unknown names / wrong argument counts at compile time,
	  * the client can pre-check code and show docs,
	  * the server Interpreter type-checks arguments at runtime.

	The server-side implementations live in ServerScriptService.Server.DroneRuntime.DroneAPI
	(world-facing builtins) and in the Interpreter itself (`intrinsic` ones like len/range,
	and the list/dict methods). There is no way for a program to reach anything not listed.

	kind:
	  "action"    - makes the drone do something and takes time. Resets the idle-step counter.
	  "sensor"    - instant read of the world.
	  "utility"   - instant helper (print, set_speed, random, get_cost).
	  "intrinsic" - implemented by the Interpreter on its own values (len, range).

	Arguments: `params` lists the type of each argument. minArgs/maxArgs default to #params;
	arguments past #params use the LAST param type (variadic print).
]]

export type ParamType = "string" | "number" | "boolean" | "any"
export type Kind = "action" | "sensor" | "utility" | "intrinsic"

export type Spec = {
	name: string,
	kind: Kind,
	params: { ParamType },
	minArgs: number,
	maxArgs: number,
	returns: string,
	example: string,
	description: string,
}

export type MethodSpec = {
	name: string,
	receiver: "list" | "dict",
	feature: string, -- syntax feature that gates the method ("lists" / "dicts")
	params: { ParamType },
	minArgs: number,
	maxArgs: number,
	example: string,
	description: string,
}

type SpecInput = {
	name: string,
	kind: Kind,
	params: { ParamType },
	minArgs: number?,
	maxArgs: number?,
	returns: string,
	example: string,
	description: string,
}

local Input: { SpecInput } = {
	-- Movement (the field has edges; the stations sit just below row 0)
	{
		name = "move_up",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "move_up()",
		description = "Fly one tile up (north).",
	},
	{
		name = "move_down",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "move_down()",
		description = "Fly one tile down (south).",
	},
	{
		name = "move_left",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "move_left()",
		description = "Fly one tile left (west).",
	},
	{
		name = "move_right",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "move_right()",
		description = "Fly one tile right (east).",
	},

	-- Farming
	{
		name = "plant",
		kind = "action",
		params = { "string" },
		returns = "boolean",
		example = 'plant("wheat")',
		description = "Plant a crop on the tile below the drone (replaces wild grass).",
	},
	{
		name = "water",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "water()",
		description = "Water the crop below the drone so it grows twice as fast.",
	},
	{
		name = "harvest",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "harvest()",
		description = "Harvest the crop below. Unripe crops are destroyed - check can_harvest() first!",
	},
	{
		name = "dig",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "dig()",
		description = "Dig the soil below for fossils. Returns True if you found one.",
	},

	-- Sensors
	{
		name = "can_harvest",
		kind = "sensor",
		params = {},
		returns = "boolean",
		example = "can_harvest()",
		description = "True if the crop below the drone is ready.",
	},
	{
		name = "is_empty",
		kind = "sensor",
		params = {},
		returns = "boolean",
		example = "is_empty()",
		description = "True if nothing has been planted below the drone (bare soil or wild grass).",
	},
	{
		name = "get_x",
		kind = "sensor",
		params = {},
		returns = "number",
		example = "get_x()",
		description = "The drone's column, starting at 0 on the left.",
	},
	{
		name = "get_y",
		kind = "sensor",
		params = {},
		returns = "number",
		example = "get_y()",
		description = "The drone's row, starting at 0 at the bottom.",
	},
	{
		name = "get_size",
		kind = "sensor",
		params = {},
		returns = "number",
		example = "get_size()",
		description = "How many tiles wide (and tall) your field is.",
	},

	-- Energy & logistics (stations sit below the field: charger (0, -1), factory (1, -1))
	{
		name = "charge",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "charge()",
		description = "At the Charging Station: refill the battery and the water tank.",
	},
	{
		name = "deposit",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "deposit()",
		description = "At the Factory: turn everything in the cargo hold into Biomass.",
	},
	{
		name = "refine",
		kind = "action",
		params = {},
		returns = "boolean",
		example = "refine()",
		description = "At the Factory: turn Biomass into Biofuel.",
	},
	{
		name = "get_battery",
		kind = "sensor",
		params = {},
		returns = "number",
		example = "get_battery()",
		description = "How much energy is left in the drone's battery.",
	},
	{
		name = "get_water",
		kind = "sensor",
		params = {},
		returns = "number",
		example = "get_water()",
		description = "How much water is left in the drone's tank.",
	},
	{
		name = "get_weather",
		kind = "sensor",
		params = {},
		returns = "string",
		example = "get_weather()",
		description = 'The current weather: "Sunny", "Rainy" or "Drought".',
	},
	{
		name = "get_cargo",
		kind = "sensor",
		params = {},
		returns = "number",
		example = "get_cargo()",
		description = "How many items the drone is carrying.",
	},

	-- System & Drone
	{
		name = "print",
		kind = "utility",
		params = { "any" },
		minArgs = 0,
		maxArgs = 8,
		returns = "None",
		example = 'print("battery:", get_battery())',
		description = "Show values in the terminal output.",
	},
	{
		name = "set_speed",
		kind = "utility",
		params = { "number" },
		returns = "None",
		example = "set_speed(1.5)",
		description = "Throttle from 0.5 to 2: faster actions use more energy per action.",
	},
	{
		name = "get_time",
		kind = "sensor",
		params = {},
		returns = "number",
		example = "get_time()",
		description = "Seconds since your program started.",
	},
	{
		name = "simulate",
		kind = "action",
		params = { "string", "number" },
		returns = "number",
		example = 'simulate("lab", 60)',
		description = "Run a saved script on a virtual copy of your farm; returns how many items it harvested.",
	},

	-- Logic & Data
	{
		name = "len",
		kind = "intrinsic",
		params = { "any" },
		returns = "number",
		example = "len([1, 2, 3])",
		description = "How many items a list, dictionary or text has.",
	},
	{
		name = "range",
		kind = "intrinsic",
		params = { "number", "number", "number" },
		minArgs = 1,
		maxArgs = 3,
		returns = "range",
		example = "range(5)",
		description = "Counts 0, 1, ... up to (not including) the number - use it in 'for' loops.",
	},
	{
		name = "random",
		kind = "utility",
		params = {},
		returns = "number",
		example = "random()",
		description = "A random number from 0 up to (not including) 1.",
	},
	{
		name = "get_cost",
		kind = "utility",
		params = { "string" },
		returns = "dictionary",
		example = 'get_cost("carrots")',
		description = "What a Tech Tree research costs, e.g. {'wheat': 40, 'hay': 40}. None if unknown.",
	},
}

type MethodInput = {
	name: string,
	receiver: "list" | "dict",
	params: { ParamType },
	minArgs: number?,
	maxArgs: number?,
	example: string,
	description: string,
}

local MethodInputs: { MethodInput } = {
	{
		name = "append",
		receiver = "list",
		params = { "any" },
		example = "items.append(5)",
		description = "Add a value to the end of the list.",
	},
	{
		name = "pop",
		receiver = "list",
		params = { "number" },
		minArgs = 0,
		maxArgs = 1,
		example = "items.pop()",
		description = "Remove and return the last item (or the item at a position).",
	},
	{
		name = "keys",
		receiver = "dict",
		params = {},
		example = "prices.keys()",
		description = "A list of the dictionary's keys.",
	},
	{
		name = "values",
		receiver = "dict",
		params = {},
		example = "prices.values()",
		description = "A list of the dictionary's values.",
	},
	{
		name = "get",
		receiver = "dict",
		params = { "any", "any" },
		minArgs = 1,
		maxArgs = 2,
		example = 'prices.get("wheat", 0)',
		description = "The value for a key, or the default (None) if the key is missing.",
	},
}

local List: { Spec } = {}
local ByName: { [string]: Spec } = {}
local Names: { string } = {}
for _, input in Input do
	assert(ByName[input.name] == nil, "Duplicate builtin " .. input.name)
	local spec: Spec = table.freeze({
		name = input.name,
		kind = input.kind,
		params = table.freeze(input.params),
		minArgs = input.minArgs or #input.params,
		maxArgs = input.maxArgs or #input.params,
		returns = input.returns,
		example = input.example,
		description = input.description,
	})
	table.insert(List, spec)
	ByName[spec.name] = spec
	table.insert(Names, spec.name)
end

local Methods: { [string]: { [string]: MethodSpec } } = { list = {}, dict = {} }
local MethodNames: { string } = {}
for _, input in MethodInputs do
	local method: MethodSpec = table.freeze({
		name = input.name,
		receiver = input.receiver,
		feature = if input.receiver == "list" then "lists" else "dicts",
		params = table.freeze(input.params),
		minArgs = input.minArgs or #input.params,
		maxArgs = input.maxArgs or #input.params,
		example = input.example,
		description = input.description,
	})
	assert(Methods[input.receiver][input.name] == nil, "Duplicate method " .. input.name)
	Methods[input.receiver][input.name] = method
	table.insert(MethodNames, input.name)
end

-- Method name -> spec, for the parser (method names are unique across receivers).
local MethodByName: { [string]: MethodSpec } = {}
for _, receiverMethods in Methods do
	for name, method in receiverMethods do
		assert(MethodByName[name] == nil, "Method name used twice: " .. name)
		MethodByName[name] = method
	end
end

return table.freeze({
	List = table.freeze(List),
	ByName = table.freeze(ByName),
	Names = table.freeze(Names),
	Methods = Methods,
	MethodByName = MethodByName,
	MethodNames = MethodNames,
})
