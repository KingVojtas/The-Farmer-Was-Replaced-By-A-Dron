--!strict
--[[
	TutorialController
	==================
	The tutorial coach: ONE banner docked on top of the terminal, so it only shows in Control
	Mode (it fades with the terminal). The SERVER owns the step (Services.TutorialService,
	player attributes TutorialStep / TutorialDone); this only displays it.

	Every step is one short sentence and one primary button. The button never asks for typed
	syntax: it RUNs, opens the Tech Tree, or INSERTS the next legal snippet at the caret
	(TerminalController:InsertSnippet). Each snippet starts and ends at the charger and only
	uses what that step allows (no loops before Loops is researched). After TutorialDone the
	coach is destroyed and never built again (also on rejoin: the server saves it).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TutorialConfig = require(ReplicatedStorage.Shared.Config.TutorialConfig)
local Client = script.Parent.Parent
local Components = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local UIState = require(Client.UI.UIState)
local TerminalController = require(script.Parent.TerminalController)

local C = Theme.Colors
local player = Players.LocalPlayer
local TOTAL_STEPS = 6
-- Idle bob of the docked banner (ANIM-6): +-3 px, 1.4 s Sine InOut, reversing; it only runs
-- while the banner is actually on screen (the terminal's ScreenGui is enabled).
local DOCK_Y = -8
local BOB_PX = 3
local BOB_INFO = TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

local SWEEP = TutorialConfig.Snippets.sweep
local FIRST_LOOP = TutorialConfig.Snippets.firstLoop
local HAY_RUN = TutorialConfig.Snippets.hayRun
local PLANT_WHEAT = TutorialConfig.Snippets.plantWheat

type Step = { text: string, label: string, action: string, snippet: string? }

local function stepInfo(step: number): Step
	if step == 0 then
		return {
			text = "Welcome, farmer! Press RUN: the starter program harvests 3 tiles of wild grass and flies home.",
			label = "RUN",
			action = "run",
		}
	elseif step == 1 then
		return {
			text = "Harvest the whole 3 x 3 field. Insert a sweep of the other two rows, then press RUN.",
			label = "INSERT SWEEP",
			action = "insert",
			snippet = SWEEP,
		}
	elseif step == 2 then
		return {
			text = "9 Hay buys Loops. Research it in the Tech Tree. Short? Run again, the grass grows back.",
			label = "OPEN TECH TREE",
			action = "tech",
		}
	elseif step == 3 then
		return {
			text = "Loops repeat work for you. Insert a loop, then press RUN and watch it repeat.",
			label = "INSERT LOOP",
			action = "insert",
			snippet = FIRST_LOOP,
		}
	elseif step == 4 then
		return {
			text = "Bring a load of Hay home: insert a farm that harvests and unloads at the charger forever.",
			label = "INSERT HAY RUN",
			action = "insert",
			snippet = HAY_RUN,
		}
	end
	if player:GetAttribute("Tech_wheat") ~= true then
		return {
			text = "Last step: research Wheat in the Tech Tree, then plant it.",
			label = "OPEN TECH TREE",
			action = "tech",
		}
	end
	return {
		text = "Last step: plant your first wheat. Insert the code, then press RUN.",
		label = "INSERT PLANTING",
		action = "insert",
		snippet = PLANT_WHEAT,
	}
end

local TutorialController = {}

local coach: Frame? = nil
local stepLabel: TextLabel
local textLabel: TextLabel
local button: TextButton
local current: Step? = nil
local connections: { RBXScriptConnection } = {}
local bob: Tween? = nil

local function stopBob()
	local tween = bob
	if tween ~= nil then
		tween:Cancel()
		bob = nil
	end
	local frame = coach
	if frame ~= nil then
		frame.Position = UDim2.fromOffset(0, DOCK_Y)
	end
end

-- Bob while shown, stop (back on its dock line) while hidden.
local function refreshBob(shown: boolean)
	local frame = coach
	if not shown or frame == nil then
		stopBob()
		return
	end
	if bob ~= nil then
		return
	end
	frame.Position = UDim2.fromOffset(0, DOCK_Y + BOB_PX)
	local tween = TweenService:Create(frame, BOB_INFO, { Position = UDim2.fromOffset(0, DOCK_Y - BOB_PX) })
	bob = tween
	tween:Play()
end

local function build(root: Frame)
	local frame = Components.panel({
		Name = "TutorialCoach",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(0, DOCK_Y),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.04,
		Parent = root,
	})
	Theme.padding(Theme.Space.S, Theme.Space.M).Parent = frame
	Theme.list(Enum.FillDirection.Vertical, 6).Parent = frame
	-- A lime outline: the coach is "growth" guidance (HUD hue rules, UI_UX_GUIDE §2).
	local stroke = frame:FindFirstChildWhichIsA("UIStroke")
	if stroke ~= nil then
		stroke.Color = C.Accent
		stroke.Transparency = 0.25
	end
	stepLabel = Components.label({
		Name = "Step",
		Text = "TUTORIAL",
		Font = Theme.UIFontHeavy,
		TextSize = 12,
		TextColor3 = C.Accent,
		LayoutOrder = 1,
		Parent = frame,
	})
	textLabel = Components.label({
		Name = "Text",
		Text = "",
		TextSize = 14,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Parent = frame,
	})
	button = Theme.button("RUN", C.Accent, {
		Name = "Action",
		TextColor3 = C.Background,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 3,
		Parent = frame,
	})
	Theme.padding(0, Theme.Space.M).Parent = button
	Components.hover(button)
	button.Activated:Connect(function()
		local step = current
		if step == nil then
			return
		end
		if step.action == "run" then
			TerminalController:Run()
		elseif step.action == "tech" then
			UIState.open("TechTree")
		else
			local snippet = step.snippet
			if snippet ~= nil then
				TerminalController:InsertSnippet(snippet)
			end
		end
	end)
	coach = frame
end

local function refresh()
	if player:GetAttribute("TutorialDone") == true then
		-- Finished: tear the coach down for good.
		stopBob()
		local frame = coach
		if frame ~= nil then
			frame:Destroy()
			coach = nil
		end
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
		return
	end
	local step = player:GetAttribute("TutorialStep")
	if type(step) ~= "number" or coach == nil then
		return
	end
	local info = stepInfo(step)
	current = info
	stepLabel.Text = string.format("TUTORIAL  %d / %d", math.min(step + 1, TOTAL_STEPS), TOTAL_STEPS)
	textLabel.Text = info.text
	button.Text = info.label
end

function TutorialController:Start()
	if player:GetAttribute("TutorialDone") == true then
		return -- never built for players who finished it
	end
	local root = TerminalController:GetRoot()
	build(root)
	for _, attribute in { "TutorialStep", "TutorialDone", "Tech_wheat" } do
		table.insert(connections, player:GetAttributeChangedSignal(attribute):Connect(refresh))
	end
	-- The banner lives in the terminal's ScreenGui: bob only while that is enabled.
	local gui = root:FindFirstAncestorWhichIsA("ScreenGui")
	if gui ~= nil then
		table.insert(
			connections,
			gui:GetPropertyChangedSignal("Enabled"):Connect(function()
				refreshBob(gui.Enabled)
			end)
		)
		refreshBob(gui.Enabled)
	end
	refresh()
end

return TutorialController
