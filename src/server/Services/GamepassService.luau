--!strict
--[[
	GamepassService
	===============
	Caches gamepass ownership per player and turns it into gameplay perks.

	  * On join: UserOwnsGamePassAsync for every configured pass (pcall + 3 retries).
	  * On purchase: PromptGamePassPurchaseFinished (a SERVER-side event fired by Roblox, so a
	    client can't fake it) grants the perk immediately, no rejoin needed.
	  * Attributes for the client UI: Pass_<Key> (boolean) and MaxLines (number).

	Passes with id 0 are placeholders and are never owned (except with
	GameConfig.Debug.StudioGrantAllPasses, which only works inside Studio).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)

export type Perks = {
	vip: boolean,
	maxLines: number,
	yieldMultiplier: number,
	speedMultiplier: number,
}

local GamepassService = {}

local owned: { [Player]: { [string]: boolean } } = {}
local keyById: { [number]: string } = {}

local function setOwned(player: Player, key: string, value: boolean)
	local set = owned[player]
	if set == nil then
		return -- player left
	end
	set[key] = value
	player:SetAttribute("Pass_" .. key, value)
	player:SetAttribute("MaxLines", GamepassService:GetPerks(player).maxLines)
end

local function checkOwnership(player: Player, passId: number): boolean
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
		end)
		if ok then
			return result == true
		end
		warn(
			string.format(
				"[GamepassService] Ownership check %d/3 failed for %d: %s",
				attempt,
				passId,
				tostring(result)
			)
		)
		task.wait(attempt)
	end
	return false
end

local function loadOwnership(player: Player)
	owned[player] = {}
	player:SetAttribute("MaxLines", GameConfig.Script.BaseMaxLines)

	local grantAll = GameConfig.Debug.StudioGrantAllPasses and RunService:IsStudio()
	for key, pass in MonetizationConfig.GamePasses do
		local has = grantAll or (pass.id ~= 0 and checkOwnership(player, pass.id))
		local set = owned[player]
		if set == nil then
			return -- player left while we were checking
		end
		-- Never downgrade a pass that was bought while this check was running.
		setOwned(player, key, has or set[key] == true)
	end
end

function GamepassService:Init()
	for key, pass in MonetizationConfig.GamePasses do
		if pass.id == 0 then
			warn(
				string.format(
					"[GamepassService] Gamepass %s has id 0 - set its real ID in MonetizationConfig",
					key
				)
			)
		elseif keyById[pass.id] ~= nil then
			warn(
				string.format(
					"[GamepassService] Gamepasses %s and %s share id %d",
					keyById[pass.id],
					key,
					pass.id
				)
			)
		else
			keyById[pass.id] = key
		end
	end
end

function GamepassService:Start()
	Players.PlayerAdded:Connect(loadOwnership)
	Players.PlayerRemoving:Connect(function(player: Player)
		owned[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(loadOwnership, player)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end
			local key = keyById[passId]
			if key ~= nil then
				setOwned(player, key, true)
			end
		end
	)
end

function GamepassService:Owns(player: Player, key: string): boolean
	local set = owned[player]
	return set ~= nil and set[key] == true
end

function GamepassService:GetPerks(player: Player): Perks
	local set: { [string]: boolean } = owned[player] or {}
	local perks = MonetizationConfig.Perks
	return {
		vip = set.VIP == true,
		maxLines = GameConfig.Script.BaseMaxLines
			+ (if set.ExpandedMemory then perks.ExpandedMemoryExtraLines else 0),
		yieldMultiplier = if set.DoubleYield then perks.DoubleYieldMultiplier else 1,
		speedMultiplier = if set.Overclock then perks.OverclockSpeedMultiplier else 1,
	}
end

return GamepassService
