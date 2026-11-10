--!strict
--[[
	Tutorial
	========
	The first-session tutorial as a pure state machine. Services.TutorialService feeds it
	facts the SERVER sees itself (never anything the client claims) and saves the result in
	PlayerData.tutorial = { step, done }.

	  step  goal                              advances on
	  0     press RUN                         event "run" (a program run starts)
	  1     harvest the starter 3x3           facts.cropsHarvested >= HarvestGoal (9)
	  2     research Loops                    facts.unlocks.loops
	  3     a program really loops            event "loop" (the interpreter finished a while /
	                                          repeat pass in a live run)
	  4     bring Hay home                    event "hayUnload" (an unload at the charger banked
	                                          Hay; only AFTER step 3, events count on their step)
	  5     research Wheat and plant it       facts.unlocks.wheat and facts.wheatPlanted
	  6     done (done = true; the coach hides for good)

	Veterans (Wheat researched and VeteranHarvests crops harvested) skip it when they load.
]]

export type State = { step: number, done: boolean }

export type Facts = {
	cropsHarvested: number,
	unlocks: { [string]: boolean },
	wheatPlanted: boolean, -- a wheat crop is on the player's field right now
}

local Tutorial = {}

Tutorial.LastStep = 5
Tutorial.HarvestGoal = 9 -- the whole starter 3 x 3 of wild grass
Tutorial.VeteranHarvests = 50

local EVENT_STEP: { [string]: number } = { run = 0, loop = 3, hayUnload = 4 }

function Tutorial.finish(state: State)
	state.done = true
	state.step = Tutorial.LastStep + 1
end

local function advance(state: State)
	state.step += 1
	if state.step > Tutorial.LastStep then
		Tutorial.finish(state)
	end
end

local function met(step: number, facts: Facts): boolean
	if step == 1 then
		return facts.cropsHarvested >= Tutorial.HarvestGoal
	elseif step == 2 then
		return facts.unlocks.loops == true
	elseif step == 5 then
		return facts.unlocks.wheat == true and facts.wheatPlanted
	end
	return false
end

-- Advances through every step whose condition `facts` already meet. True if it moved.
function Tutorial.check(state: State, facts: Facts): boolean
	local moved = false
	while not state.done and met(state.step, facts) do
		advance(state)
		moved = true
	end
	return moved
end

-- An event the server observed; it only counts on its own step. True if it moved.
function Tutorial.event(state: State, event: string, facts: Facts): boolean
	if state.done or EVENT_STEP[event] ~= state.step then
		return false
	end
	advance(state)
	Tutorial.check(state, facts)
	return true
end

function Tutorial.isVeteran(facts: Facts): boolean
	return facts.unlocks.wheat == true and facts.cropsHarvested >= Tutorial.VeteranHarvests
end

return Tutorial
