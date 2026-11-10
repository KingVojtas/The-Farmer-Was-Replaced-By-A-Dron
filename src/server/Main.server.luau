--!strict
--[[
	Server bootstrap.
	Requires every service, then calls Init() on all of them in order (create remotes, register
	handlers, assign ProcessReceipt, connect signals - nothing that yields), then Start() on all
	of them (connect player events, start loops). Order matters only for Init: NetService must
	create the remotes before anyone registers a handler.
]]

local Services = script.Parent.Services

local ORDER = {
	"NetService",
	"DataService",
	"GamepassService",
	"ReceiptService",
	"WeatherService",
	"GridService",
	"PlotGuardService", -- after GridService (collision groups, guest eject)
	"TutorialService", -- before ScriptService (which reports runs, loops and unloads to it)
	"TechService",
	"CosmeticService",
	"ScriptService",
}

local loaded: { { name: string, service: any } } = {}
for _, name in ORDER do
	table.insert(loaded, { name = name, service = require(Services:WaitForChild(name)) :: any })
end

for _, entry in loaded do
	if entry.service.Init ~= nil then
		local ok, err = xpcall(function()
			entry.service:Init()
		end, debug.traceback)
		if not ok then
			error(string.format("[Main] %s:Init failed: %s", entry.name, tostring(err)))
		end
	end
end

for _, entry in loaded do
	if entry.service.Start ~= nil then
		task.spawn(function()
			local ok, err = xpcall(function()
				entry.service:Start()
			end, debug.traceback)
			if not ok then
				warn(string.format("[Main] %s:Start failed: %s", entry.name, tostring(err)))
			end
		end)
	end
end

print("[Main] Server ready")
