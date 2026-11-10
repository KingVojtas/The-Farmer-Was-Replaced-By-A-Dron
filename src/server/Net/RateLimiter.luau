--!strict
--[[
	RateLimiter
	===========
	Pure rate-limiting primitives (the clock is injected, so tests can control time).

	TokenBucket: each key (usually a Player) owns a bucket holding up to `capacity` tokens that
	refills at `perSecond`. Every request costs one token; an empty bucket rejects. This allows
	short bursts (clicking Run twice) while capping the sustained rate.

	WindowCounter: counts events per key inside a fixed time window. NetService uses it to
	count rejected requests ("violations") and kick clients that keep hammering.
]]

export type Clock = () -> number

export type TokenBucket = {
	Consume: (self: TokenBucket, key: any, cost: number?) -> boolean,
	Peek: (self: TokenBucket, key: any) -> number,
	Reset: (self: TokenBucket, key: any) -> (),
}

export type WindowCounter = {
	Add: (self: WindowCounter, key: any, amount: number?) -> number,
	Reset: (self: WindowCounter, key: any) -> (),
}

local RateLimiter = {}

function RateLimiter.newTokenBucket(capacity: number, perSecond: number, clock: Clock): TokenBucket
	assert(capacity >= 1, "capacity must be >= 1")
	assert(perSecond > 0, "perSecond must be > 0")

	local buckets: { [any]: { tokens: number, last: number } } = {}

	local function refill(key: any): { tokens: number, last: number }
		local now = clock()
		local bucket = buckets[key]
		if bucket == nil then
			bucket = { tokens = capacity, last = now }
			buckets[key] = bucket
		else
			-- math.max guards against a clock that goes backwards.
			local elapsed = math.max(0, now - bucket.last)
			bucket.tokens = math.min(capacity, bucket.tokens + elapsed * perSecond)
			bucket.last = now
		end
		return bucket
	end

	return {
		Consume = function(_self: TokenBucket, key: any, cost: number?): boolean
			local price = cost or 1
			local bucket = refill(key)
			if bucket.tokens < price then
				return false
			end
			bucket.tokens -= price
			return true
		end,
		Peek = function(_self: TokenBucket, key: any): number
			return refill(key).tokens
		end,
		Reset = function(_self: TokenBucket, key: any)
			buckets[key] = nil
		end,
	}
end

function RateLimiter.newWindowCounter(windowSeconds: number, clock: Clock): WindowCounter
	local windows: { [any]: { start: number, count: number } } = {}

	return {
		-- Adds `amount` (default 1) and returns the total inside the current window.
		Add = function(_self: WindowCounter, key: any, amount: number?): number
			local now = clock()
			local window = windows[key]
			if window == nil or now - window.start >= windowSeconds or now < window.start then
				window = { start = now, count = 0 }
				windows[key] = window
			end
			window.count += amount or 1
			return window.count
		end,
		Reset = function(_self: WindowCounter, key: any)
			windows[key] = nil
		end,
	}
end

return RateLimiter
