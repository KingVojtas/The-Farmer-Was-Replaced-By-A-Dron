--!strict
--[[
	ScriptNames
	===========
	Rules for script-slot names. A slot's name is what other programs `import` (import utils),
	so it must be a valid, unique identifier that doesn't collide with the language itself.
	Shared: the server enforces it (DataService:RenameScript, Sanitize), the client pre-checks
	the rename box with the same function.
]]

local Builtins = require(script.Parent.Builtins)
local Lexer = require(script.Parent.Lexer)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local ScriptNames = {}

--[[
	Returns (true) or (false, player-facing reason). `names` are the current names of all
	slots; `slot` is the slot being renamed (its own current name doesn't count as a clash).
]]
function ScriptNames.validate(name: any, names: { string }, slot: number): (boolean, string?)
	if type(name) ~= "string" then
		return false, "The name must be text."
	end
	local maxLength = GameConfig.Script.MaxNameLength
	if #name == 0 then
		return false, "Give the script a name."
	end
	if #name > maxLength then
		return false, string.format("Names can be at most %d characters long.", maxLength)
	end
	if string.match(name, "^[%a_][%w_]*$") == nil then
		return false, "Use letters, digits and _ only, and don't start with a digit (like farm_utils)."
	end
	if Lexer.Keywords[name] ~= nil then
		return false, string.format("'%s' is a reserved word.", name)
	end
	if Builtins.ByName[name] ~= nil then
		return false, string.format("'%s' is a built-in command.", name)
	end
	for otherSlot, other in names do
		if otherSlot ~= slot and other == name then
			return false, string.format("Another script is already called '%s'.", name)
		end
	end
	return true
end

return ScriptNames
