--!strict
--[[
	Cosmetics
	=========
	Pure, non-yielding rules for drone cosmetics (Config.CosmeticConfig) on PlayerData.

	  owned?   free -> always; tech -> the unlocking research is in SAVED techUnlocks;
	           premium -> data.cosmetics.owned[id]
	  buy      premium only: checks ownership and the Lithium Battery balance, then deducts the
	           price and records the ownership in ONE step (same record -> saved together)
	  equip    the item must exist, match the slot and be owned

	Every function validates everything before changing anything.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CosmeticConfig = require(ReplicatedStorage.Shared.Config.CosmeticConfig)
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)

local PREMIUM_CURRENCY = "batteries"

local Cosmetics = {}

function Cosmetics.isOwned(data: any, id: string): boolean
	local item = CosmeticConfig.ById[id]
	if item == nil then
		return false
	end
	local unlock: any = item.unlock
	if unlock.kind == "free" then
		return true
	elseif unlock.kind == "tech" then
		return Tech.isFeatureUnlocked(data.techUnlocks, unlock.feature)
	end
	return data.cosmetics.owned[id] == true
end

function Cosmetics.canBuy(data: any, id: string): (boolean, string?)
	local item = CosmeticConfig.ById[id]
	if item == nil then
		return false, "That item doesn't exist."
	end
	local unlock: any = item.unlock
	if unlock.kind ~= "premium" then
		if unlock.kind == "tech" and not Cosmetics.isOwned(data, id) then
			return false, item.name .. " is unlocked by research in the Tech Tree, not sold."
		end
		return false, "You already own " .. item.name .. "."
	end
	if data.cosmetics.owned[id] == true then
		return false, "You already own " .. item.name .. "."
	end
	if (data.currencies[PREMIUM_CURRENCY] or 0) < unlock.price then
		return false, string.format("%s costs %d Lithium Batteries.", item.name, unlock.price)
	end
	return true
end

function Cosmetics.buy(data: any, id: string): (boolean, string?)
	local ok, reason = Cosmetics.canBuy(data, id)
	if not ok then
		return false, reason
	end
	local price = ((CosmeticConfig.ById[id] :: any).unlock :: any).price :: number
	data.currencies[PREMIUM_CURRENCY] -= price
	data.cosmetics.owned[id] = true
	return true
end

function Cosmetics.equip(data: any, slot: string, id: string): (boolean, string?)
	local item = CosmeticConfig.ById[id]
	if item == nil or item.slot ~= slot then
		return false, "That item doesn't fit there."
	end
	if not Cosmetics.isOwned(data, id) then
		return false, "You don't own " .. item.name .. " yet."
	end
	data.cosmetics.equipped[slot] = id
	return true
end

return Cosmetics
