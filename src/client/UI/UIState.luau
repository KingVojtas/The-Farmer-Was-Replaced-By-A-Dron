--!strict
--[[
	UIState
	=======
	The client's panel router: at most ONE full panel (Tech Tree, Shop, ...) is open at a time.
	Controllers register their panel once; buttons anywhere (HUD dock, main menu, the "+" next
	to the premium currency) just call UIState.open("Shop", "batteries").

	  UIState.register(name, { open = function(tab?) end, close = function() end })
	  UIState.open(name, tab?)   closes the current panel first
	  UIState.toggle(name, tab?)
	  UIState.closeAll()
	  UIState.current() -> string?
	  UIState.Changed:Connect(function(name?) end)

	Gamepad: ButtonB closes the open panel.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

export type Panel = {
	open: (tab: string?) -> (),
	close: () -> (),
}

local UIState = {
	Changed = Signal.new(), -- (name?) the open panel changed
	Back = Signal.new(), -- gamepad B pressed while no panel was open
}

local panels: { [string]: Panel } = {}
local currentName: string? = nil

function UIState.register(name: string, panel: Panel)
	assert(panels[name] == nil, "Panel registered twice: " .. name)
	panels[name] = panel
end

function UIState.current(): string?
	return currentName
end

function UIState.closeAll()
	local name = currentName
	if name == nil then
		return
	end
	currentName = nil
	local panel = panels[name]
	if panel ~= nil then
		panel.close()
	end
	UIState.Changed:Fire(nil)
end

function UIState.open(name: string, tab: string?)
	local panel = panels[name]
	if panel == nil then
		warn("[UIState] Unknown panel " .. name)
		return
	end
	if currentName ~= nil and currentName ~= name then
		local previous = panels[currentName]
		if previous ~= nil then
			previous.close()
		end
	end
	currentName = name
	panel.open(tab)
	UIState.Changed:Fire(name)
end

function UIState.toggle(name: string, tab: string?)
	if currentName == name and tab == nil then
		UIState.closeAll()
	else
		UIState.open(name, tab)
	end
end

-- A panel closed itself (its own X button): keep the router in sync.
function UIState.notifyClosed(name: string)
	if currentName == name then
		currentName = nil
		UIState.Changed:Fire(nil)
	end
end

-- Gamepad "back": close the open panel; with no panel open, tell listeners (Control Mode
-- uses it to leave the bird's-eye view). One handler, so one press never does both.
UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if input.KeyCode == Enum.KeyCode.ButtonB and not processed then
		if currentName ~= nil then
			UIState.closeAll()
		else
			UIState.Back:Fire()
		end
	end
end)

return UIState
