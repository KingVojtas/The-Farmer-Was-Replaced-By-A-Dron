return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local task = require("@lune/task")
	local SessionStore = Loader.get("ServerScriptService.Server.Data.SessionStore")
	local MockDataStore = Loader.get("ServerScriptService.Server.Data.MockDataStore")
	local Sanitize = Loader.get("ServerScriptService.Server.Data.Sanitize")

	local function makeClock(start)
		local clock = { t = start or 1000 }
		function clock.now()
			return clock.t
		end
		return clock
	end

	local function makeSession(store, clock, name, overrides)
		local options = {
			store = store,
			sessionId = name,
			jobId = "job-" .. name,
			now = clock.now,
			wait = task.wait,
			sanitize = Sanitize.run,
			lockStaleSeconds = 300,
			loadRetries = 2,
			loadRetryDelay = 0.01,
			writeRetries = 3,
			writeRetryDelay = 0.01,
			pollInterval = 0.005,
		}
		for k, v in overrides or {} do
			options[k] = v
		end
		return SessionStore.new(options)
	end

	describe("SessionStore", function()
		it("creates and locks a new record", function()
			local store, clock = MockDataStore.new(), makeClock()
			local profile, err = makeSession(store, clock, "A"):LoadAsync("u_1", { 1 })
			expect(err).toBeNil()
			expect(profile:IsActive()).toBe(true)
			expect(profile.data.currencies.wheat).toBe(0)
			local record = store:Peek("u_1")
			expect(record.lock.sessionId).toBe("A")
			expect(record.meta.loads).toBe(1)
		end)

		it("persists saves", function()
			local store, clock = MockDataStore.new(), makeClock()
			local profile = makeSession(store, clock, "A"):LoadAsync("u_1")
			profile.data.currencies.wheat = 42
			expect(profile:SaveAsync()).toBe(true)
			expect(store:Peek("u_1").data.currencies.wheat).toBe(42)
		end)

		it("refuses to load while another session holds a fresh lock", function()
			local store, clock = MockDataStore.new(), makeClock()
			local first = makeSession(store, clock, "A"):LoadAsync("u_1")
			expect(first).toBeTruthy()
			local second, err = makeSession(store, clock, "B"):LoadAsync("u_1")
			expect(second).toBeNil()
			expect(err).toBe("Locked")
		end)

		it("hands the record over after release", function()
			local store, clock = MockDataStore.new(), makeClock()
			local first = makeSession(store, clock, "A"):LoadAsync("u_1")
			first.data.currencies.wheat = 7
			expect(first:ReleaseAsync()).toBe(true)
			expect(first:IsActive()).toBe(false)
			expect(store:Peek("u_1").lock).toBeNil()

			local second = makeSession(store, clock, "B"):LoadAsync("u_1")
			expect(second.data.currencies.wheat).toBe(7)
		end)

		it("takes over a stale lock and the old session loses its profile", function()
			local store, clock = MockDataStore.new(), makeClock()
			local first = makeSession(store, clock, "A"):LoadAsync("u_1")
			local lostFired = 0
			first.onLost = function()
				lostFired += 1
			end

			clock.t += 301 -- server A stopped refreshing its lock (crashed / hung)
			local second = makeSession(store, clock, "B"):LoadAsync("u_1")
			expect(second).toBeTruthy()

			first.data.currencies.wheat = 999 -- must never reach the store
			expect(first:SaveAsync()).toBe(false)
			expect(first:IsLost()).toBe(true)
			expect(first:IsActive()).toBe(false)
			expect(lostFired).toBe(1)
			expect(store:Peek("u_1").data.currencies.wheat).toBe(0)
			expect(store:Peek("u_1").lock.sessionId).toBe("B")
		end)

		it("refreshes the lock time on every save", function()
			local store, clock = MockDataStore.new(), makeClock()
			local profile = makeSession(store, clock, "A"):LoadAsync("u_1")
			clock.t += 200
			profile:SaveAsync()
			clock.t += 200 -- 400 s after load, but only 200 s after the last save
			local _, err = makeSession(store, clock, "B"):LoadAsync("u_1")
			expect(err).toBe("Locked")
		end)

		it("never touches a corrupt record", function()
			local store, clock = MockDataStore.new(), makeClock()
			store:SetAsync("u_1", "garbage")
			local profile, err = makeSession(store, clock, "A"):LoadAsync("u_1")
			expect(profile).toBeNil()
			expect(err).toBe("Corrupt")
			expect(store:Peek("u_1")).toBe("garbage")
		end)

		it("retries failed writes", function()
			local store, clock = MockDataStore.new(), makeClock()
			local profile = makeSession(store, clock, "A"):LoadAsync("u_1")
			store:FailNext(2)
			profile.data.currencies.wheat = 5
			expect(profile:SaveAsync()).toBe(true)
			expect(store:Peek("u_1").data.currencies.wheat).toBe(5)
		end)

		it("reports failure when every retry fails, but stays active", function()
			local store, clock = MockDataStore.new(), makeClock()
			local profile = makeSession(store, clock, "A"):LoadAsync("u_1")
			store:FailNext(10)
			expect(profile:SaveAsync()).toBe(false)
			expect(profile:IsActive()).toBe(true)
			store:FailNext(0)
			expect(profile:SaveAsync()).toBe(true)
		end)

		it("retries loads that fail", function()
			local store, clock = MockDataStore.new(), makeClock()
			store:FailNext(1)
			local profile = makeSession(store, clock, "A"):LoadAsync("u_1")
			expect(profile).toBeTruthy()
		end)

		it("coalesces concurrent saves", function()
			local store, clock = MockDataStore.new({ latency = 0.03, wait = task.wait }), makeClock()
			local profile = makeSession(store, clock, "A"):LoadAsync("u_1")
			local writesBefore = store.writes
			local results = {}
			for i = 1, 6 do
				task.spawn(function()
					profile.data.currencies.wheat = i
					results[i] = profile:SaveAsync()
				end)
			end
			task.wait(0.5)
			for i = 1, 6 do
				expect(results[i]).toBe(true)
			end
			expect(store.writes - writesBefore).toBeAtMost(2)
			expect(store:Peek("u_1").data.currencies.wheat).toBe(6)
		end)

		it("makes concurrent releases share one write", function()
			local store, clock = MockDataStore.new({ latency = 0.03, wait = task.wait }), makeClock()
			local profile = makeSession(store, clock, "A"):LoadAsync("u_1")
			local writesBefore = store.writes
			local a, b
			task.spawn(function()
				a = profile:ReleaseAsync()
			end)
			task.spawn(function()
				b = profile:ReleaseAsync()
			end)
			task.wait(0.3)
			expect(a).toBe(true)
			expect(b).toBe(true)
			expect(store.writes - writesBefore).toBe(1)
			expect(profile:SaveAsync()).toBe(false) -- released profiles can't save
		end)

		it("lets a save that was waiting on a release succeed through the release write", function()
			local store, clock = MockDataStore.new({ latency = 0.03, wait = task.wait }), makeClock()
			local profile = makeSession(store, clock, "A"):LoadAsync("u_1")
			local saveResult
			task.spawn(function()
				profile.data.currencies.wheat = 11
				saveResult = profile:SaveAsync() -- in flight
			end)
			task.spawn(function()
				profile:ReleaseAsync()
			end)
			task.wait(0.3)
			expect(saveResult).toBe(true)
			expect(store:Peek("u_1").data.currencies.wheat).toBe(11)
			expect(store:Peek("u_1").lock).toBeNil()
		end)
	end)
end
