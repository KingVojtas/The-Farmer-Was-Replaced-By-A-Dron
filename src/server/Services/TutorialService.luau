--!strict
--[[
	TutorialService
	===============
	Runs the first-session tutorial (Progression.Tutorial has the steps). The SERVER owns
	PlayerData.tutorial = { step, done }: it only advances on facts the server sees itself.

	  * events from ScriptService: "run" (a program started), "loop" (a live run finished a
	    while / repeat pass), "hayUnload" (an unload at the charger banked Hay)
	  * state, checked every CheckSeconds and on load: cropsHarvested, researched nodes, and
	    whether a wheat crop is on the player's field (GridService)

	Published as player attributes for the client coach (Client.Controllers.TutorialController):
	  TutorialStep  number   0 .. 5 while it runs, 6 when done
	  TutorialDone  boolean  true = never show the coach again (saved, honoured on rejoin)
]]

local Players = game:GetService("Players")

local Tutorial = require(script.Parent.Parent.Progression.Tutorial)
local DataService = require(script.Parent.DataService)
local GridService = require(script.Parent.GridService)

local CHECK_SECONDS = 1

local TutorialService = {}

local function factsFor(player: Player, data: any): Tutorial.Facts
	local wheatPlanted = false
	local plot = GridService:GetPlot(player)
	if plot ~= nil then
		for _, tile in plot.tiles do
			if tile.crop == "wheat" and tile.state ~= "empty" then
				wheatPlanted = true
				break
			end
		end
	end
	return {
		cropsHarvested = data.cropsHarvested,
		unlocks = data.techUnlocks,
		wheatPlanted = wheatPlanted,
	}
end

local function publish(player: Player, data: any)
	player:SetAttribute("TutorialStep", data.tutorial.step)
	player:SetAttribute("TutorialDone", data.tutorial.done)
end

local function check(player: Player)
	local data = DataService:GetData(player)
	if data == nil or data.tutorial.done then
		return
	end
	if Tutorial.check(data.tutorial, factsFor(player, data)) then
		publish(player, data)
	end
end

local function onLoaded(player: Player)
	local data = DataService:GetData(player)
	if data == nil then
		return
	end
	if not data.tutorial.done and Tutorial.isVeteran(factsFor(player, data)) then
		Tutorial.finish(data.tutorial) -- long-time players never see the coach
	end
	publish(player, data)
	check(player)
end

-- An event only ScriptService can see. Ignored unless it is the current step's goal.
function TutorialService:Notify(player: Player, event: string)
	local data = DataService:GetData(player)
	if data == nil or data.tutorial.done then
		return
	end
	if Tutorial.event(data.tutorial, event, factsFor(player, data)) then
		publish(player, data)
	end
end

-- True while the player hasn't finished the tutorial (WeatherService keeps the start sunny).
function TutorialService:IsActive(player: Player): boolean
	local data = DataService:GetData(player)
	return data ~= nil and data.tutorial.done ~= true
end

function TutorialService:Init()
	DataService.ProfileLoaded:Connect(onLoaded)
end

function TutorialService:Start()
	for _, player in DataService:GetLoadedPlayers() do
		onLoaded(player)
	end
	task.spawn(function()
		while true do
			task.wait(CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(check :: any, player)
				if not ok then
					warn("[TutorialService] check failed: " .. tostring(err))
				end
			end
		end
	end)
end

return TutorialService
