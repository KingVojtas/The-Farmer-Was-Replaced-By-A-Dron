--!strict
--[[
	Client bootstrap: Init() every controller (build UI, no yielding), then Start() each one
	(connect events, may yield while waiting for server objects).

	UI layers (ScreenGui.DisplayOrder, see docs/UI_UX_GUIDE.md):
	  0 HUD   1 Terminal (Control Mode only)   2 Control Mode buttons   5 Tech Tree / Shop
	  8 Main Menu   10 Toasts
]]

local Controllers = script.Parent.Controllers

local ORDER = {
	"LightingController", -- first: the world look is applied before anything renders
	"PlotRenderer",
	"NotifyController",
	"HudController",
	"CurrencyHudController", -- builds inside the HUD's ScreenGui, so it comes right after it
	"TerminalController",
	"ControlModeController", -- after the terminal (it shows/hides it), before the main menu
	"WeatherFxController", -- weather looks + rain/dust over your plot (visual only)
	"TutorialController", -- the coach docked on the terminal (server owns the step)
	"TechTreeController",
	"ShopController",
	"MainMenuController",
}

local loaded: { { name: string, controller: any } } = {}
for _, name in ORDER do
	table.insert(loaded, { name = name, controller = require(Controllers:WaitForChild(name)) :: any })
end

for _, entry in loaded do
	if entry.controller.Init ~= nil then
		local ok, err = xpcall(function()
			entry.controller:Init()
		end, debug.traceback)
		if not ok then
			warn(string.format("[Client] %s:Init failed: %s", entry.name, tostring(err)))
		end
	end
end

for _, entry in loaded do
	if entry.controller.Start ~= nil then
		task.spawn(function()
			local ok, err = xpcall(function()
				entry.controller:Start()
			end, debug.traceback)
			if not ok then
				warn(string.format("[Client] %s:Start failed: %s", entry.name, tostring(err)))
			end
		end)
	end
end
