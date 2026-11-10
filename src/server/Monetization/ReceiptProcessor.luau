--!strict
--[[
	ReceiptProcessor
	================
	The decision logic behind MarketplaceService.ProcessReceipt. Pure: the profile lookup,
	clock and logging are injected, so every path is unit-tested offline.

	THE EXACTLY-ONCE GUARANTEE
	  Roblox may deliver the same receipt many times (retries, rejoins, several servers).
	  We return PurchaseGranted only after the grant is DURABLY saved, and we never grant the
	  same PurchaseId twice:

	    1. Unknown ProductId                          -> NotProcessedYet (retried later, never lost)
	    2. Same PurchaseId already being processed    -> NotProcessedYet (the first call finishes it)
	    3. Profile not loaded / player gone / lost    -> NotProcessedYet
	    4. PurchaseId NOT in data.receipts:
	         apply grants + record PurchaseId         <- one block, NO yields in between
	    5. profile:SaveAsync()
	         success                                  -> PurchaseGranted
	         failure                                  -> NotProcessedYet

	  The grant and its PurchaseId live in the SAME record and are written by the SAME
	  UpdateAsync, so they persist together or not at all:
	    * retry after a failed save in this session -> PurchaseId already in memory -> only re-save
	    * session ends without any successful save  -> neither persisted -> next session grants fresh
	    * session lock stolen                       -> save refuses -> NotProcessedYet -> the new
	                                                   owner's copy decides (still exactly once)

	  Grants are declarative (MonetizationConfig) and validated up front, so applying them
	  cannot fail half-way.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Currencies = require(ReplicatedStorage.Shared.Config.Currencies)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)

type Product = MonetizationConfig.Product
type Grant = MonetizationConfig.Grant

export type Decision = "PurchaseGranted" | "NotProcessedYet"

export type ProfileLike = {
	data: any,
	IsActive: (self: any) -> boolean,
	SaveAsync: (self: any) -> boolean,
}

export type Receipt = {
	PurchaseId: any,
	PlayerId: any,
	ProductId: any,
}

export type Options = {
	products: { [string]: Product }, -- by product key (MonetizationConfig.Products)
	getProfile: (userId: number) -> ProfileLike?, -- may yield while the profile loads
	now: () -> number, -- os.time
	maxReceipts: number,
	log: ((level: string, message: string) -> ())?,
	-- Called once per newly granted purchase, after it was saved (notifications / UI refresh).
	onGranted: ((userId: number, productKey: string, grants: { Grant }) -> ())?,
}

export type Processor = {
	Process: (self: Processor, receipt: Receipt) -> Decision,
	productKeysById: { [number]: string },
}

local VALID_BOOSTS: { [string]: boolean } = { growth = true, yield = true }

local function isPositiveInteger(value: any): boolean
	return type(value) == "number" and value == value and value > 0 and value % 1 == 0 and value < 2 ^ 53
end

local ReceiptProcessor = {}

-- Returns (true) or (false, reason) for a single grant list.
function ReceiptProcessor.validateGrants(grants: any): (boolean, string?)
	if type(grants) ~= "table" or #grants == 0 then
		return false, "grants must be a non-empty list"
	end
	for index, grant in grants do
		if type(grant) ~= "table" then
			return false, "grant " .. tostring(index) .. " is not a table"
		end
		if grant.kind == "currency" then
			if type(grant.currency) ~= "string" or Currencies.ById[grant.currency] == nil then
				return false,
					"grant " .. tostring(index) .. " has unknown currency " .. tostring(grant.currency)
			end
			if not isPositiveInteger(grant.amount) then
				return false, "grant " .. tostring(index) .. " needs a positive integer amount"
			end
		elseif grant.kind == "boost" then
			if not VALID_BOOSTS[grant.boost] or not isPositiveInteger(grant.seconds) then
				return false,
					"grant " .. tostring(index) .. " needs boost=growth|yield and positive integer seconds"
			end
		else
			return false, "grant " .. tostring(index) .. " has unknown kind " .. tostring(grant.kind)
		end
	end
	return true
end

function ReceiptProcessor.validateProduct(product: any): (boolean, string?)
	if type(product) ~= "table" then
		return false, "product is not a table"
	end
	local ok, reason = ReceiptProcessor.validateGrants(product.grants)
	if not ok then
		return false, reason
	end
	if product.oncePerPlayer then
		local fallbackOk, fallbackReason = ReceiptProcessor.validateGrants(product.fallbackGrants)
		if not fallbackOk then
			return false, "fallbackGrants: " .. tostring(fallbackReason)
		end
	end
	return true
end

-- Applies validated grants. All new values are computed first and assigned at the end, so
-- the data is never left half-updated.
function ReceiptProcessor.applyGrants(data: any, grants: { Grant }, now: number)
	local currencyDeltas: { [string]: number } = {}
	local growthUntil = data.boosts.growthUntil
	local yieldUntil = data.boosts.yieldUntil

	for _, grant in grants do
		if grant.kind == "currency" then
			local id = grant.currency :: string
			currencyDeltas[id] = (currencyDeltas[id] or 0) + (grant.amount :: number)
		elseif grant.kind == "boost" then
			-- Extend from whichever is later: now, or the end of the boost that is still running.
			if grant.boost == "growth" then
				growthUntil = math.max(growthUntil, now) + (grant.seconds :: number)
			else
				yieldUntil = math.max(yieldUntil, now) + (grant.seconds :: number)
			end
		end
	end

	for id, delta in currencyDeltas do
		data.currencies[id] = (data.currencies[id] or 0) + delta
	end
	data.boosts.growthUntil = growthUntil
	data.boosts.yieldUntil = yieldUntil
end

function ReceiptProcessor.hasReceipt(data: any, purchaseId: string): boolean
	for _, id in data.receipts do
		if id == purchaseId then
			return true
		end
	end
	return false
end

function ReceiptProcessor.recordReceipt(data: any, purchaseId: string, maxReceipts: number)
	table.insert(data.receipts, purchaseId)
	while #data.receipts > maxReceipts do
		table.remove(data.receipts, 1) -- drop the oldest
	end
end

function ReceiptProcessor.new(options: Options): Processor
	local log: (level: string, message: string) -> () = function(_level: string, _message: string) end
	if options.log ~= nil then
		log = options.log
	end

	-- Build the ProductId -> key index, skipping placeholders and invalid definitions.
	local productKeysById: { [number]: string } = {}
	for key, product in options.products do
		local ok, reason = ReceiptProcessor.validateProduct(product)
		if not ok then
			log(
				"error",
				string.format(
					"[Receipts] Product %s is misconfigured and will never be granted: %s",
					key,
					tostring(reason)
				)
			)
		elseif product.id == 0 then
			log(
				"warn",
				string.format("[Receipts] Product %s has id 0 - set its real ID in MonetizationConfig", key)
			)
		elseif productKeysById[product.id] ~= nil then
			log(
				"error",
				string.format(
					"[Receipts] Products %s and %s share id %d - only %s will be granted",
					productKeysById[product.id],
					key,
					product.id,
					productKeysById[product.id]
				)
			)
		else
			productKeysById[product.id] = key
		end
	end

	local inFlight: { [string]: boolean } = {}
	-- Grants applied in THIS session but not yet confirmed by a save (for onGranted).
	local pendingNotify: { [string]: { grants: { Grant }, key: string } } = {}

	local function process(_self: Processor, receipt: Receipt): Decision
		local purchaseId = receipt.PurchaseId
		local userId = receipt.PlayerId
		local productId = receipt.ProductId
		if type(purchaseId) ~= "string" or type(userId) ~= "number" or type(productId) ~= "number" then
			log("error", "[Receipts] Malformed receipt")
			return "NotProcessedYet"
		end

		local key = productKeysById[productId]
		if key == nil then
			log(
				"warn",
				string.format(
					"[Receipts] Unknown ProductId %d (purchase %s) - not granted yet",
					productId,
					purchaseId
				)
			)
			return "NotProcessedYet"
		end
		local product = options.products[key]

		if inFlight[purchaseId] then
			return "NotProcessedYet"
		end
		inFlight[purchaseId] = true

		local ok, decision = pcall(function(): Decision
			local profile = options.getProfile(userId)
			if profile == nil or not profile:IsActive() then
				return "NotProcessedYet"
			end
			local data = profile.data

			if not ReceiptProcessor.hasReceipt(data, purchaseId) then
				-- ===== critical section: NO yields until the PurchaseId is recorded =====
				local grants = product.grants
				if product.oncePerPlayer then
					if data.oneTimeClaims[key] then
						grants = product.fallbackGrants :: { Grant }
					else
						data.oneTimeClaims[key] = true
					end
				end
				ReceiptProcessor.applyGrants(data, grants, options.now())
				ReceiptProcessor.recordReceipt(data, purchaseId, options.maxReceipts)
				-- ===== end critical section =====
				pendingNotify[purchaseId] = { grants = grants, key = key }
				log(
					"info",
					string.format("[Receipts] Applied %s for user %d (purchase %s)", key, userId, purchaseId)
				)
			end

			if not profile:SaveAsync() then
				log("warn", string.format("[Receipts] Save failed for purchase %s - will retry", purchaseId))
				return "NotProcessedYet"
			end

			local notify = pendingNotify[purchaseId]
			pendingNotify[purchaseId] = nil
			if notify ~= nil and options.onGranted ~= nil then
				local notifyOk, notifyErr = pcall(options.onGranted :: any, userId, notify.key, notify.grants)
				if not notifyOk then
					log("error", "[Receipts] onGranted failed: " .. tostring(notifyErr))
				end
			end
			return "PurchaseGranted"
		end)

		inFlight[purchaseId] = nil

		if not ok then
			log(
				"error",
				string.format("[Receipts] Error processing purchase %s: %s", purchaseId, tostring(decision))
			)
			return "NotProcessedYet"
		end
		return decision :: Decision
	end

	return {
		Process = process,
		productKeysById = productKeysById,
	}
end

return ReceiptProcessor
