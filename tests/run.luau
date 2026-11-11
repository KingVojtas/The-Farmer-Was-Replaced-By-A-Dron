--[[
	Offline unit tests for the pure game modules.
	Usage (from the repository root):  lune run tests/run
]]

local process = require("@lune/process")

local T = require("./lib/test")
local Loader = require("./lib/loader")

local specs = {
	require("./spec/Lexer.spec"),
	require("./spec/Parser.spec"),
	require("./spec/Interpreter.spec"),
	require("./spec/Validate.spec"),
	require("./spec/RateLimiter.spec"),
	require("./spec/Sanitize.spec"),
	require("./spec/SessionStore.spec"),
	require("./spec/ReceiptProcessor.spec"),
	require("./spec/Tech.spec"),
	require("./spec/TechTree.spec"),
	require("./spec/Economy.spec"),
	require("./spec/Values.spec"),
	require("./spec/Language.spec"),
	require("./spec/DroneWorld.spec"),
	require("./spec/Cosmetics.spec"),
	require("./spec/PlotFraming.spec"),
	require("./spec/IconConfig.spec"),
	require("./spec/CropTransitions.spec"),
	require("./spec/SoilStates.spec"),
	require("./spec/DroneSignals.spec"),
	require("./spec/RunGate.spec"),
	require("./spec/Tutorial.spec"),
	require("./spec/FieldSave.spec"),
	require("./spec/Simulation.spec"),
	require("./spec/FieldKeeper.spec"),
	require("./spec/DroneStations.spec"),
	require("./spec/Text.spec"),
	require("./spec/UiSlices.spec"),
}

for _, register in specs do
	register(T, Loader)
end

local _, failed = T.run()
process.exit(if failed > 0 then 1 else 0)
