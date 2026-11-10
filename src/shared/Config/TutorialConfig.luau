--!strict
--[[
	TutorialConfig
	==============
	The code snippets the tutorial coach inserts (Client.Controllers.TutorialController).
	Shared and pure so tests/spec/Tutorial.spec.luau can prove each one compiles with exactly the
	research its step has, and does what the step asks on a simulated 3 x 3 farm. Every snippet
	starts and ends on the charger (0, -1), so inserting it at the top of a program is safe.
]]

local TutorialConfig = {}

TutorialConfig.Snippets = {} :: { [string]: string }

local function lines(list: { string }): string
	return table.concat(list, "\n")
end

-- Step 1: the starter harvests row 0; this sweeps rows 1 and 2 (no loops needed yet).
TutorialConfig.Snippets.sweep = lines({
	"# Sweep rows 1 and 2, then fly home",
	"move_up()",
	"move_up()",
	"harvest()",
	"move_right()",
	"harvest()",
	"move_right()",
	"harvest()",
	"move_up()",
	"harvest()",
	"move_left()",
	"harvest()",
	"move_left()",
	"harvest()",
	"move_down()",
	"move_down()",
	"move_down()",
})

-- Step 3: the first loop.
TutorialConfig.Snippets.firstLoop = lines({
	"# A loop repeats the indented lines",
	"repeat 3 times:",
	"    move_up()",
	"    harvest()",
	"repeat 3 times:",
	"    move_down()",
})

-- Step 4: a farm that keeps bringing Hay home (every pass ends on the charger).
TutorialConfig.Snippets.hayRun = lines({
	"# Forever: harvest the left column, unload at the charger",
	"while True:",
	"    repeat 3 times:",
	"        move_up()",
	"        if can_harvest():",
	"            harvest()",
	"    repeat 3 times:",
	"        move_down()",
})

-- Step 5: plant the first wheat (planting over wild grass is allowed).
TutorialConfig.Snippets.plantWheat = lines({
	"# Your first real crop",
	"move_up()",
	"harvest()",
	'plant("wheat")',
	"move_down()",
})

return TutorialConfig
