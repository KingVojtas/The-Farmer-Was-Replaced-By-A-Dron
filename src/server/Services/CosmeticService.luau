--!strict
--[[
	CosmeticService
	===============
	Handles the Shop's Drone Hangar: buying premium cosmetics with Lithium Batteries and
	equipping paint jobs / hats. The client sends only enum-validated ids (RemoteSchema);
	everything else is decided here from SAVED data by Progression.Cosmetics:

	  BuyCosmetic(id)          -> price checked against saved Batteries, deducted and the
	                              ownership recorded in one non-yielding step, then saved
	  EquipCosmetic(slot, id)  -> ownership checked (free / researched / bought), equipped,
	                              published on the plot (DronePaint / DroneHat) for every client
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CosmeticConfig = require(ReplicatedStorage.Shared.Config.CosmeticConfig)
local Cosmetics = require(script.Parent.Parent.Progression.Cosmetics)
local DataService = require(script.Parent.DataService)
local GridService = require(script.Parent.GridService)
local NetService = require(script.Parent.NetService)

type Response = { ok: boolean, message: string? }

local CosmeticService = {}

function CosmeticService:Init()
	NetService:OnInvoke("BuyCosmetic", function(player: Player, id: string): Response
		local profile = DataService:GetProfile(player)
		local data = DataService:GetData(player)
		if profile == nil or data == nil then
			return { ok = false, message = "Your save data is still loading." }
		end
		local bought, reason = Cosmetics.buy(data, id)
		if not bought then
			return { ok = false, message = reason }
		end
		DataService:Replicate(player)
		task.spawn(function()
			profile:SaveAsync() -- price + ownership are in the same record: saved together or not at all
		end)
		return { ok = true, message = CosmeticConfig.ById[id].name .. " is yours!" }
	end)

	NetService:OnInvoke("EquipCosmetic", function(player: Player, slot: string, id: string): Response
		local data = DataService:GetData(player)
		if data == nil then
			return { ok = false, message = "Your save data is still loading." }
		end
		local equipped, reason = Cosmetics.equip(data, slot, id)
		if not equipped then
			return { ok = false, message = reason }
		end
		DataService:Replicate(player)
		GridService:PublishCosmetics(player)
		return { ok = true }
	end)
end

return CosmeticService
