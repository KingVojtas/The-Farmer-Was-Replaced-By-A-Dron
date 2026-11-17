--!strict
--[[
	RateLimiter (server path). The implementation is pure and lives in
	ReplicatedStorage.Shared.Net.RateLimiter, so the client can mirror a remote's token bucket
	with the very same code (TerminalController's RUN button, BUG-13). Server modules keep
	requiring this path.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = require(ReplicatedStorage.Shared.Net.RateLimiter)

export type Clock = Shared.Clock
export type TokenBucket = Shared.TokenBucket
export type WindowCounter = Shared.WindowCounter

return Shared
