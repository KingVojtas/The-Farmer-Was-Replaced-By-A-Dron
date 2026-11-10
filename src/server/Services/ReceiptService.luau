--!strict
--[[
	ReceiptService
	==============
	The ONE place in the game that assigns MarketplaceService.ProcessReceipt (Roblox allows a
	single callback; a second assignment anywhere would silently replace this one).

	All decisions are made by Monetization.ReceiptProcessor (pure + unit-tested); this file
	only connects it to real players, DataService and the network:
	  * getProfile waits (up to GameConfig.Data.ProfileWaitTimeout) for the buyer's data to load,
	  * after a purchase is saved, the client is told (PurchaseGranted remote) and attributes
	    are refreshed,
	  * the Starter Pack offer window is published as the StarterPackEndsAt attribute
	    (os.time() when the offer ends, 0 = not available) for the upcoming store popup.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local ReceiptProcessor = require(script.Parent.Parent.Monetization.ReceiptProcessor)
local DataService = require(script.Parent.DataService)
local NetService = require(script.Parent.NetService)

local ReceiptService = {}

local processor: ReceiptProcessor.Processor

local function updateStarterPackOffer(player: Player)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	local product = MonetizationConfig.Products.StarterPack
	local endsAt = data.firstJoin + (product.offerSeconds or 0)
	local available = product.id ~= 0 and not data.oneTimeClaims.StarterPack and os.time() < endsAt
	player:SetAttribute("StarterPackEndsAt", if available then endsAt else 0)
end

function ReceiptService:Init()
	processor = ReceiptProcessor.new({
		products = MonetizationConfig.Products,
		getProfile = function(userId: number)
			local player = Players:GetPlayerByUserId(userId)
			if player == nil then
				return nil -- not in this server; Roblox retries when they join one
			end
			return DataService:WaitForProfile(player, GameConfig.Data.ProfileWaitTimeout)
		end,
		now = os.time,
		maxReceipts = GameConfig.Data.MaxReceiptHistory,
		log = function(level: string, message: string)
			if level == "info" then
				print(message)
			else
				warn(message)
			end
		end,
		onGranted = function(userId: number, productKey: string)
			local player = Players:GetPlayerByUserId(userId)
			if player == nil then
				return
			end
			DataService:Replicate(player)
			updateStarterPackOffer(player)
			NetService:Fire(player, "PurchaseGranted", productKey)
		end,
	})

	MarketplaceService.ProcessReceipt = function(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
		local ok, decision = pcall(processor.Process, processor, receiptInfo :: any)
		if ok and decision == "PurchaseGranted" then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		if not ok then
			warn("[ReceiptService] ProcessReceipt error: " .. tostring(decision))
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
end

function ReceiptService:Start()
	DataService.ProfileLoaded:Connect(function(player: Player)
		updateStarterPackOffer(player)
	end)
	for _, player in DataService:GetLoadedPlayers() do
		updateStarterPackOffer(player)
	end
end

return ReceiptService
