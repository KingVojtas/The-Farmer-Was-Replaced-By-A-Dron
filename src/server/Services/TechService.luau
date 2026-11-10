--!strict
--[[
	TechService
	===========
	Handles Tech Tree research requests. The client only sends a node id (validated against
	the list of real ids by RemoteSchema); EVERYTHING else is decided here from saved data:

	  1. the profile must be loaded and active,
	  2. Tech.research checks prerequisites and the full multi-currency cost, then pays and
	     unlocks in one non-yielding step (all-or-nothing),
	  3. attributes are refreshed (Cur_*, Tech_*, drone capacities); a Grid Expansion grows
	     the field right away (GridService:Resize),
	  4. a save is requested right away. The cost and the unlock are in the same record, so
	     even a crash before that save can't produce a free unlock or lost currency.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local DataService = require(script.Parent.DataService)
local GridService = require(script.Parent.GridService)
local NetService = require(script.Parent.NetService)

type ResearchResponse = { ok: boolean, message: string? }

local TechService = {}

function TechService:Init()
	local ok, problems = Tech.validate()
	if not ok then
		for _, problem in problems do
			warn("[TechService] Tech Tree config problem: " .. problem)
		end
	end

	NetService:OnInvoke("Research", function(player: Player, nodeId: string): ResearchResponse
		local profile = DataService:GetProfile(player)
		local data = DataService:GetData(player)
		if profile == nil or data == nil then
			return { ok = false, message = "Your save data is still loading." }
		end

		local researched, reason = Tech.research(data, nodeId)
		if not researched then
			return { ok = false, message = reason }
		end

		DataService:Replicate(player)
		GridService:RefreshStats(player)
		local grew = GridService:Resize(player)
		task.spawn(function()
			profile:SaveAsync() -- coalesced with any other pending save
		end)
		local node = Tech.Nodes[nodeId]
		local message = node.name .. " researched!"
		if grew then
			local size = Tech.stats(data.techUnlocks).gridSize
			message = string.format("%s Your field is now %d x %d.", message, size, size)
		end
		NetService:Fire(player, "Notify", "research", message)
		return { ok = true, message = message }
	end)
end

return TechService
