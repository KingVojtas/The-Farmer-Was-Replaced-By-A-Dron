--!strict
--[[
	NetService
	==========
	Secure wrapper around every RemoteEvent / RemoteFunction.

	Remotes are created at startup from Shared.Net.RemoteSchema into ReplicatedStorage.Remotes.
	Other services register handlers with OnEvent / OnInvoke; a handler only ever sees a
	request that passed ALL of these checks, in this order:

	  1. The sender is still in the game.
	  2. Rate limits: a global per-player token bucket AND one bucket per player per remote.
	  3. The exact argument count and every argument's validator (Shared.Net.Validate).
	  4. The handler runs inside pcall: a bug in one handler can't break the connection or
	     leak an error to the client. RemoteFunctions always answer `(ok: boolean, result)`.

	Every rejected request counts as a violation. More than
	GameConfig.Net.ViolationKickThreshold violations inside ViolationWindow seconds kicks the
	player (honest clients debounce on their side and never get close). A client firing a
	server-to-client remote is also a violation. The server never invokes clients.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local RemoteSchema = require(ReplicatedStorage.Shared.Net.RemoteSchema)
local Validate = require(ReplicatedStorage.Shared.Net.Validate)
local RateLimiter = require(script.Parent.Parent.Net.RateLimiter)

type RemoteDef = RemoteSchema.RemoteDef
type Handler = (player: Player, ...any) -> ...any

local WARN_INTERVAL = 5 -- seconds between violation warnings per player (log spam guard)

local NetService = {}

local remotes: { [string]: Instance } = {}
local handlers: { [string]: Handler } = {}
local limiters: { [string]: RateLimiter.TokenBucket } = {}
local globalLimiter =
	RateLimiter.newTokenBucket(GameConfig.Net.GlobalBurst, GameConfig.Net.GlobalPerSecond, os.clock)
local violations = RateLimiter.newWindowCounter(GameConfig.Net.ViolationWindow, os.clock)
local lastWarnAt: { [Player]: number } = {}
local kicked: { [Player]: boolean } = {}

local function recordViolation(player: Player, remoteName: string, reason: string)
	local count = violations:Add(player)

	local now = os.clock()
	if now - (lastWarnAt[player] or 0) >= WARN_INTERVAL then
		lastWarnAt[player] = now
		warn(
			string.format(
				"[NetService] Rejected %s from %s (%d): %s [%d in window]",
				remoteName,
				player.Name,
				player.UserId,
				reason,
				count
			)
		)
	end

	if
		count > GameConfig.Net.ViolationKickThreshold
		and GameConfig.Debug.KickOnAbuse
		and not kicked[player]
	then
		kicked[player] = true
		warn(string.format("[NetService] Kicking %s (%d) for request abuse", player.Name, player.UserId))
		player:Kick("Too many requests. Please rejoin.")
	end
end

-- Returns true if the request may reach its handler.
local function admit(player: Player, name: string, def: RemoteDef, ...: any): boolean
	if player.Parent ~= Players or kicked[player] then
		return false
	end
	if not globalLimiter:Consume(player) then
		recordViolation(player, name, "global rate limit")
		return false
	end
	local limiter = limiters[name]
	if limiter ~= nil and not limiter:Consume(player) then
		recordViolation(player, name, "rate limit")
		return false
	end
	local ok, reason = Validate.args(def.args or {}, ...)
	if not ok then
		recordViolation(player, name, reason or "invalid arguments")
		return false
	end
	return true
end

local function createRemote(folder: Folder, name: string, def: RemoteDef)
	if def.rate ~= nil then
		limiters[name] = RateLimiter.newTokenBucket(def.rate.burst, def.rate.perSecond, os.clock)
	end

	if def.kind == "Event" then
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		if def.direction == "ClientToServer" then
			remote.OnServerEvent:Connect(function(player: Player, ...: any)
				if not admit(player, name, def, ...) then
					return
				end
				local handler = handlers[name]
				if handler == nil then
					return
				end
				local ok, err = pcall(handler, player, ...)
				if not ok then
					warn(string.format("[NetService] %s handler error: %s", name, tostring(err)))
				end
			end)
		else
			remote.OnServerEvent:Connect(function(player: Player)
				recordViolation(player, name, "client fired a server-to-client remote")
			end)
		end
		remote.Parent = folder
		remotes[name] = remote
	else
		assert(def.direction == "ClientToServer", "RemoteFunctions must be ClientToServer: " .. name)
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.OnServerInvoke = function(player: Player, ...: any): (boolean, any)
			if not admit(player, name, def, ...) then
				return false, "Rejected"
			end
			local handler = handlers[name]
			if handler == nil then
				return false, "Unavailable"
			end
			local ok, result = pcall(handler, player, ...)
			if not ok then
				warn(string.format("[NetService] %s handler error: %s", name, tostring(result)))
				return false, "ServerError"
			end
			return true, result
		end
		remote.Parent = folder
		remotes[name] = remote
	end
end

function NetService:Init()
	-- A stale folder could only exist from a misconfigured place file; replace it.
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing ~= nil then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for name, def in RemoteSchema do
		createRemote(folder, name, def)
	end
	folder.Parent = ReplicatedStorage
end

function NetService:Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		globalLimiter:Reset(player)
		for _, limiter in limiters do
			limiter:Reset(player)
		end
		violations:Reset(player)
		lastWarnAt[player] = nil
		kicked[player] = nil
	end)
end

-- Registers the handler for a client-to-server RemoteEvent.
function NetService:OnEvent(name: string, handler: (player: Player, ...any) -> ())
	local def = RemoteSchema[name]
	assert(
		def ~= nil and def.kind == "Event" and def.direction == "ClientToServer",
		"Not a C->S event: " .. name
	)
	assert(handlers[name] == nil, "Handler already registered for " .. name)
	handlers[name] = handler
end

-- Registers the handler for a RemoteFunction. Its single return value is sent to the client.
function NetService:OnInvoke(name: string, handler: (player: Player, ...any) -> any)
	local def = RemoteSchema[name]
	assert(def ~= nil and def.kind == "Function", "Not a RemoteFunction: " .. name)
	assert(handlers[name] == nil, "Handler already registered for " .. name)
	handlers[name] = handler
end

-- Fires a server-to-client RemoteEvent to one player (ignored if the player already left).
local function getEvent(name: string): RemoteEvent
	local remote: Instance? = remotes[name]
	assert(remote ~= nil and remote:IsA("RemoteEvent"), "Unknown RemoteEvent " .. name)
	return remote :: RemoteEvent
end

function NetService:Fire(player: Player, name: string, ...: any)
	local remote = getEvent(name)
	if player.Parent ~= Players then
		return
	end
	remote:FireClient(player, ...)
end

function NetService:FireAll(name: string, ...: any)
	local remote = getEvent(name)
	remote:FireAllClients(...)
end

return NetService
