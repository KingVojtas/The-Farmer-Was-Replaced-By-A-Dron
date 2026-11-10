--!strict
--[[
	WeatherService
	==============
	PER-PLOT dynamic weather: every plot runs its own cycle, so one player's drought is not
	everybody's. Every MinSeconds..MaxSeconds a plot picks its next weather from
	GameConfig.Weather.Weights (Sunny 70 % / Rainy 20 % / Drought 10 %; repeats allowed, so
	the long-run shares match the weights).

	  Sunny   - normal growth, water() uses 1 water
	  Rainy   - faster growth, water() is free, and rain SOAKS dry crops: a crop is watered
	            after GameConfig.Grid.RainSoakSeconds of rain (Progression.Growth), so Water Tanks
	            still matter for fast crops
	  Drought - slow growth, water() uses 2 water

	A new player (tutorial not done) always starts with at least TutorialSunnySeconds of Sunny.

	Published on the PLOT model for clients (HUD chip, world weather FX):
	  Weather        string   current weather name
	  WeatherNext    string   what comes next
	  WeatherEndsAt  number   os.time() when it changes
	Workspace.Weather stays "Sunny": the hub / lobby, and the fallback for clients with no plot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local DataService = require(script.Parent.DataService)

export type Weather = {
	name: string,
	growth: number,
	waterCost: number,
	autoWater: boolean,
}

type PlotWeather = { model: Model, name: string, nextName: string, endsAt: number }

local WEATHER = GameConfig.Weather
local WEIGHTS = WEATHER.Weights :: { [string]: number }
local TYPES = WEATHER.Types :: { [string]: { growth: number, waterCost: number, autoWater: boolean } }

local WeatherService = {}

local random = Random.new()
local plots: { [Player]: PlotWeather } = {}

-- Weighted pick; the same weather may come again (that is what makes Sunny ~70 % of the time).
local function pick(): string
	local total = 0
	for _, weight in WEIGHTS do
		total += weight
	end
	local roll = random:NextNumber() * total
	for name, weight in WEIGHTS do
		roll -= weight
		if roll <= 0 then
			return name
		end
	end
	return WEATHER.Initial
end

local function rollDuration(): number
	return random:NextNumber(WEATHER.MinSeconds, WEATHER.MaxSeconds)
end

local function publish(state: PlotWeather)
	state.model:SetAttribute("Weather", state.name)
	state.model:SetAttribute("WeatherNext", state.nextName)
	state.model:SetAttribute("WeatherEndsAt", math.ceil(state.endsAt))
end

local function describe(name: string): Weather
	local def = TYPES[name] or TYPES[WEATHER.Initial]
	return { name = name, growth = def.growth, waterCost = def.waterCost, autoWater = def.autoWater }
end

-- Starts the plot's own weather (GridService.createPlot).
function WeatherService:AttachPlot(player: Player, model: Model)
	local data = DataService:GetData(player)
	local learning = data ~= nil and data.tutorial.done ~= true
	local duration = rollDuration()
	if learning then
		duration = math.max(duration, WEATHER.TutorialSunnySeconds) -- a calm, sunny first session
	end
	local state: PlotWeather = {
		model = model,
		name = WEATHER.Initial,
		nextName = pick(),
		endsAt = os.time() + duration,
	}
	plots[player] = state
	publish(state)
end

function WeatherService:DetachPlot(player: Player)
	plots[player] = nil
end

-- The weather on this player's plot (Sunny if they have none).
function WeatherService:GetFor(player: Player): Weather
	local state = plots[player]
	return describe(if state ~= nil then state.name else WEATHER.Initial)
end

-- The hub's weather (always the Initial type). Only for callers that have no plot in mind.
function WeatherService:GetCurrent(): Weather
	return describe(WEATHER.Initial)
end

function WeatherService:Init()
	assert(TYPES[WEATHER.Initial] ~= nil, "GameConfig.Weather.Initial must be a weather type")
	Workspace:SetAttribute("Weather", WEATHER.Initial)
end

function WeatherService:Start()
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for player, state in plots do
				if state.model.Parent == nil then
					plots[player] = nil
				elseif now >= state.endsAt then
					state.name = state.nextName
					state.nextName = pick()
					state.endsAt = now + rollDuration()
					publish(state)
				end
			end
		end
	end)
end

return WeatherService
