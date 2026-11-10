return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local task = require("@lune/task")
	local ReceiptProcessor = Loader.get("ServerScriptService.Server.Monetization.ReceiptProcessor")
	local Sanitize = Loader.get("ServerScriptService.Server.Data.Sanitize")
	local SessionStore = Loader.get("ServerScriptService.Server.Data.SessionStore")
	local MockDataStore = Loader.get("ServerScriptService.Server.Data.MockDataStore")
	local MonetizationConfig = Loader.get("ReplicatedStorage.Shared.Config.MonetizationConfig")

	local PRODUCTS = {
		Batteries = {
			id = 1,
			price = 49,
			name = "B",
			grants = { { kind = "currency", currency = "batteries", amount = 100 } },
		},
		Starter = {
			id = 2,
			price = 249,
			name = "S",
			oncePerPlayer = true,
			grants = {
				{ kind = "currency", currency = "wheat", amount = 2000 },
				{ kind = "currency", currency = "batteries", amount = 750 },
			},
			fallbackGrants = { { kind = "currency", currency = "batteries", amount = 750 } },
		},
		Boost = {
			id = 3,
			price = 19,
			name = "M",
			grants = { { kind = "boost", boost = "growth", seconds = 600 } },
		},
		Placeholder = {
			id = 0,
			price = 1,
			name = "P",
			grants = { { kind = "currency", currency = "wheat", amount = 1 } },
		},
	}

	-- A fake profile whose SaveAsync results can be scripted.
	local function makeProfile()
		local profile = { data = Sanitize.run(nil, 0), active = true, saves = 0, failSaves = 0 }
		function profile:IsActive()
			return self.active
		end
		function profile:SaveAsync()
			self.saves += 1
			if self.failSaves > 0 then
				self.failSaves -= 1
				return false
			end
			return true
		end
		return profile
	end

	local function makeProcessor(profile, overrides)
		local granted = {}
		local clock = { t = 1000 }
		local options = {
			products = PRODUCTS,
			getProfile = function(_userId)
				return profile
			end,
			now = function()
				return clock.t
			end,
			maxReceipts = 200,
			onGranted = function(userId, key)
				table.insert(granted, key)
			end,
		}
		for k, v in overrides or {} do
			options[k] = v
		end
		return ReceiptProcessor.new(options), granted, clock
	end

	local function receipt(purchaseId, productId)
		return { PurchaseId = purchaseId, PlayerId = 1, ProductId = productId }
	end

	describe("ReceiptProcessor", function()
		it("grants a product and records the receipt", function()
			local profile = makeProfile()
			local processor, granted = makeProcessor(profile)
			expect(processor:Process(receipt("p1", 1))).toBe("PurchaseGranted")
			expect(profile.data.currencies.batteries).toBe(100)
			expect(profile.data.receipts).toEqual({ "p1" })
			expect(granted).toEqual({ "Batteries" })
		end)

		it("never grants the same PurchaseId twice", function()
			local profile = makeProfile()
			local processor, granted = makeProcessor(profile)
			processor:Process(receipt("p1", 1))
			expect(processor:Process(receipt("p1", 1))).toBe("PurchaseGranted")
			expect(profile.data.currencies.batteries).toBe(100)
			expect(#granted).toBe(1)
			processor:Process(receipt("p2", 1))
			expect(profile.data.currencies.batteries).toBe(200)
		end)

		it("returns NotProcessedYet when the save fails, and the retry does not double-grant", function()
			local profile = makeProfile()
			profile.failSaves = 1
			local processor, granted = makeProcessor(profile)
			expect(processor:Process(receipt("p1", 1))).toBe("NotProcessedYet")
			expect(#granted).toBe(0)
			expect(processor:Process(receipt("p1", 1))).toBe("PurchaseGranted")
			expect(profile.data.currencies.batteries).toBe(100)
			expect(granted).toEqual({ "Batteries" })
		end)

		it("leaves unknown products and placeholder ids unprocessed", function()
			local profile = makeProfile()
			local processor = makeProcessor(profile)
			expect(processor:Process(receipt("p1", 999))).toBe("NotProcessedYet")
			expect(processor:Process(receipt("p2", 0))).toBe("NotProcessedYet")
			expect(processor.productKeysById[0]).toBeNil()
			expect(profile.data.currencies.wheat).toBe(0)
			expect(#profile.data.receipts).toBe(0)
		end)

		it("waits for the player: no profile or inactive profile -> NotProcessedYet", function()
			local processor = makeProcessor(nil)
			expect(processor:Process(receipt("p1", 1))).toBe("NotProcessedYet")

			local profile = makeProfile()
			profile.active = false
			local processor2 = makeProcessor(profile)
			expect(processor2:Process(receipt("p1", 1))).toBe("NotProcessedYet")
			expect(profile.data.currencies.batteries).toBe(0)
		end)

		it("rejects malformed receipts", function()
			local processor = makeProcessor(makeProfile())
			expect(processor:Process({ PurchaseId = 5, PlayerId = 1, ProductId = 1 })).toBe("NotProcessedYet")
			expect(processor:Process({ PurchaseId = "x", PlayerId = "1", ProductId = 1 })).toBe(
				"NotProcessedYet"
			)
		end)

		it("gives the fallback on a repeat purchase of a one-time product", function()
			local profile = makeProfile()
			local processor = makeProcessor(profile)
			processor:Process(receipt("s1", 2))
			expect(profile.data.currencies.wheat).toBe(2000)
			expect(profile.data.currencies.batteries).toBe(750)
			expect(profile.data.oneTimeClaims.Starter).toBe(true)
			processor:Process(receipt("s2", 2))
			expect(profile.data.currencies.wheat).toBe(2000)
			expect(profile.data.currencies.batteries).toBe(1500)
		end)

		it("stacks timed boosts from the later of now / current end", function()
			local profile = makeProfile()
			local processor, _, clock = makeProcessor(profile)
			processor:Process(receipt("b1", 3))
			expect(profile.data.boosts.growthUntil).toBe(1600)
			processor:Process(receipt("b2", 3))
			expect(profile.data.boosts.growthUntil).toBe(2200)
			clock.t = 5000 -- boost long expired
			processor:Process(receipt("b3", 3))
			expect(profile.data.boosts.growthUntil).toBe(5600)
		end)

		it("keeps the receipt history bounded", function()
			local profile = makeProfile()
			local processor = makeProcessor(profile, { maxReceipts = 3 })
			for i = 1, 5 do
				processor:Process(receipt("p" .. i, 1))
			end
			expect(profile.data.receipts).toEqual({ "p3", "p4", "p5" })
		end)

		it("ignores a duplicate delivery while the first is still in flight", function()
			local profile = makeProfile()
			local processor = makeProcessor(profile, {
				getProfile = function()
					task.wait(0.05) -- profile still loading
					return profile
				end,
			})
			local first, second
			task.spawn(function()
				first = processor:Process(receipt("p1", 1))
			end)
			task.spawn(function()
				second = processor:Process(receipt("p1", 1))
			end)
			task.wait(0.2)
			expect(first).toBe("PurchaseGranted")
			expect(second).toBe("NotProcessedYet")
			expect(profile.data.currencies.batteries).toBe(100)
		end)

		it("treats errors as NotProcessedYet", function()
			local processor = makeProcessor(nil, {
				getProfile = function()
					error("datastore exploded")
				end,
			})
			expect(processor:Process(receipt("p1", 1))).toBe("NotProcessedYet")
		end)

		it("validates product definitions", function()
			local bad = {
				{ grants = {} },
				{ grants = { { kind = "currency", currency = "wheat", amount = 1.5 } } },
				{ grants = { { kind = "boost", boost = "x", seconds = 5 } } },
				{ grants = { { kind = "currency", currency = "gems", amount = 5 } } },
				{ oncePerPlayer = true, grants = { { kind = "currency", currency = "wheat", amount = 5 } } },
			}
			for index, product in bad do
				local ok = ReceiptProcessor.validateProduct(product)
				if ok then
					error("bad product " .. index .. " was accepted")
				end
			end
		end)

		it("accepts every product in MonetizationConfig", function()
			for key, product in MonetizationConfig.Products do
				local ok, reason = ReceiptProcessor.validateProduct(product)
				if not ok then
					error(key .. ": " .. tostring(reason))
				end
			end
		end)

		it("is exactly-once across sessions with the real SessionStore", function()
			local store = MockDataStore.new()
			local function session(name)
				return SessionStore.new({
					store = store,
					sessionId = name,
					jobId = name,
					now = function()
						return 1000
					end,
					wait = task.wait,
					sanitize = Sanitize.run,
					lockStaleSeconds = 300,
					loadRetries = 1,
					loadRetryDelay = 0.01,
					writeRetries = 1,
					writeRetryDelay = 0.01,
					pollInterval = 0.005,
				})
			end

			-- Session A: the save fails, so the purchase is NOT granted and nothing persists.
			local profileA = session("A"):LoadAsync("u_1")
			local processorA = makeProcessor(profileA)
			store:FailNext(1)
			expect(processorA:Process(receipt("p1", 1))).toBe("NotProcessedYet")
			store:FailNext(1)
			expect(profileA:ReleaseAsync()).toBe(false) -- final save fails too (server outage)
			expect(store:Peek("u_1").data.currencies.batteries).toBe(0)

			-- Session B (lock is stale by now in real life; simulate by clearing it).
			local record = store:Peek("u_1")
			record.lock = nil
			store:SetAsync("u_1", record)
			local profileB = session("B"):LoadAsync("u_1")
			local processorB = makeProcessor(profileB)
			expect(processorB:Process(receipt("p1", 1))).toBe("PurchaseGranted")
			expect(store:Peek("u_1").data.currencies.batteries).toBe(100)

			-- Roblox re-delivers the same receipt (e.g. it never saw our answer): no double grant.
			expect(processorB:Process(receipt("p1", 1))).toBe("PurchaseGranted")
			profileB:ReleaseAsync()
			local profileC = session("C"):LoadAsync("u_1")
			expect(makeProcessor(profileC):Process(receipt("p1", 1))).toBe("PurchaseGranted")
			expect(profileC.data.currencies.batteries).toBe(100)
		end)
	end)
end
