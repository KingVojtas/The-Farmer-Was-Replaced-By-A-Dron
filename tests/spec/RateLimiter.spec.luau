return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local RateLimiter = Loader.get("ServerScriptService.Server.Net.RateLimiter")

	describe("RateLimiter", function()
		it("allows a burst, then rejects, then refills over time", function()
			local now = 0
			local bucket = RateLimiter.newTokenBucket(3, 0.5, function()
				return now
			end)
			expect(bucket:Consume("p")).toBe(true)
			expect(bucket:Consume("p")).toBe(true)
			expect(bucket:Consume("p")).toBe(true)
			expect(bucket:Consume("p")).toBe(false)
			now = 1.9
			expect(bucket:Consume("p")).toBe(false) -- only 0.95 tokens so far
			now = 2
			expect(bucket:Consume("p")).toBe(true)
			expect(bucket:Consume("p")).toBe(false)
		end)

		it("never refills above capacity and keeps keys separate", function()
			local now = 0
			local bucket = RateLimiter.newTokenBucket(2, 10, function()
				return now
			end)
			now = 1000
			expect(bucket:Peek("a")).toBe(2)
			bucket:Consume("a")
			bucket:Consume("a")
			expect(bucket:Consume("a")).toBe(false)
			expect(bucket:Consume("b")).toBe(true)
		end)

		it("survives a clock that goes backwards", function()
			local now = 10
			local bucket = RateLimiter.newTokenBucket(1, 1, function()
				return now
			end)
			bucket:Consume("a")
			now = 5
			expect(bucket:Consume("a")).toBe(false)
		end)

		it("resets a key", function()
			local bucket = RateLimiter.newTokenBucket(1, 0.001, function()
				return 0
			end)
			bucket:Consume("a")
			expect(bucket:Consume("a")).toBe(false)
			bucket:Reset("a")
			expect(bucket:Consume("a")).toBe(true)
		end)

		it("counts events per window", function()
			local now = 0
			local counter = RateLimiter.newWindowCounter(10, function()
				return now
			end)
			expect(counter:Add("p")).toBe(1)
			expect(counter:Add("p", 4)).toBe(5)
			now = 9.9
			expect(counter:Add("p")).toBe(6)
			now = 10
			expect(counter:Add("p")).toBe(1)
		end)
	end)
end
