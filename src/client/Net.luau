--!strict
--[[
	Client Net
	==========
	Thin client wrapper over ReplicatedStorage.Remotes (created by the server's NetService from
	Shared.Net.RemoteSchema). Remote names are checked against the schema so typos fail loudly.

	  Net.fire("StopScript")
	  local ok, result = Net.invoke("RunScript", 1, source)   -- never yields longer than the timeout
	  Net.on("ScriptOutput", function(kind, text) ... end)

	invoke() returns (true, value) when the server handler ran, or (false, reason) for
	"Timeout", "NetworkError", or the server's own rejection codes ("Rejected", "ServerError"...).
	The server is the authority on everything; the client only debounces to stay polite.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteSchema = require(ReplicatedStorage.Shared.Net.RemoteSchema)

local Net = {}

local folder: Instance? = nil

local function getRemote(name: string): Instance
	assert(RemoteSchema[name] ~= nil, "Unknown remote " .. name)
	if folder == nil then
		folder = ReplicatedStorage:WaitForChild("Remotes")
	end
	return (folder :: Instance):WaitForChild(name)
end

function Net.fire(name: string, ...: any)
	local remote = getRemote(name)
	assert(remote:IsA("RemoteEvent"), name .. " is not a RemoteEvent")
	remote:FireServer(...)
end

function Net.invoke(name: string, ...: any): (boolean, any)
	local remote = getRemote(name)
	assert(remote:IsA("RemoteFunction"), name .. " is not a RemoteFunction")

	local args = table.pack(...)
	local thread = coroutine.running()
	local settled = false

	task.spawn(function()
		local results = table.pack(pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end))
		if settled then
			return
		end
		settled = true
		task.defer(thread, results) -- defer: safe even if InvokeServer failed without yielding
	end)
	task.delay(GameConfig.Net.ClientInvokeTimeout, function()
		if settled then
			return
		end
		settled = true
		task.defer(thread, nil)
	end)

	local results: any = coroutine.yield()
	if results == nil then
		return false, "Timeout"
	end
	if not results[1] then
		return false, "NetworkError"
	end
	-- The server always answers (ok: boolean, value).
	return results[2] == true, results[3]
end

function Net.on(name: string, handler: (...any) -> ()): RBXScriptConnection
	local remote = getRemote(name)
	assert(remote:IsA("RemoteEvent"), name .. " is not a RemoteEvent")
	return remote.OnClientEvent:Connect(handler)
end

return Net
