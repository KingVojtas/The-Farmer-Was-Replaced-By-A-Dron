--!strict
--[[
	MainMenuController
	==================
	The title screen shown on join (layout spec: docs/UI_UX_GUIDE.md, "Main Menu"):

	  DRONE FARM                                   [ How to play card ]
	  Write code. Grow crops. Automate everything.
	  [ PLAY ]  [ TECH TREE ]  [ SHOP ]  [ HOW TO PLAY ]

	  * PLAY stays in a "Loading your farm..." state until the server sets DataLoaded.
	  * While the menu is open the world is blurred (Lighting BlurEffect, tweened) and, on the
	    first open, the camera slowly orbits the player's own plot. The orbit angle is a
	    TweenService-driven NumberValue; only the CAMERA moves, nothing physical.
	  * The HUD is hidden while the menu is up (ControlModeController hides its own terminal and
	    buttons when it sees the menu open); the MENU button brings the menu back.
	  * The camera is only touched for the join orbit, so opening the menu during Control Mode
	    leaves the bird's-eye camera alone.
	  * Registered with UIState as "MainMenu", so opening the Tech Tree or Shop from here
	    closes the menu automatically.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local Components = require(Client.UI.Components)
local Theme = require(Client.UI.Theme)
local UIState = require(Client.UI.UIState)

local C = Theme.Colors
local player = Players.LocalPlayer

local ORBIT_SECONDS = 70
local ORBIT_RADIUS = 46
local ORBIT_HEIGHT = 30
-- Only the HUD is hidden here. The terminal and the Control Mode buttons are owned by
-- ControlModeController, which hides/re-shows them itself while the menu is open.
local HIDDEN_GUIS = { "DroneHud" }
local HOW_TO_PLAY = {
	"1. Your drone runs the code in the terminal (bottom-left). Press RUN.",
	"2. Harvest wild grass for Hay, then fly back to the charger at (0, -1) to bank it.",
	"3. Spend crops in the TECH TREE to unlock loops, new crops, math, lists and more.",
	"4. Deposit crops at the Factory (1, -1) for Biomass, refine Biomass into Biofuel.",
	"5. Watch the battery: charge() at the charging station refills it.",
}

local MainMenuController = {}

local gui: ScreenGui
local root: CanvasGroup
local playButton: TextButton
local helpCard: Frame
local blur: BlurEffect
local orbitAngle: NumberValue
local orbitTween: Tween? = nil
local orbitConnection: RBXScriptConnection? = nil
local isOpen = false
local hasOrbited = false

local function setWorldUiVisible(visible: boolean)
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return
	end
	for _, name in HIDDEN_GUIS do
		local target = playerGui:FindFirstChild(name)
		if target ~= nil and target:IsA("ScreenGui") then
			target.Enabled = visible
		end
	end
end

local function ownPlotCenter(): Vector3?
	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:GetAttribute("OwnerUserId") == player.UserId then
			local origin = plot:GetAttribute("Origin")
			local size = plot:GetAttribute("Size")
			local pitch = plot:GetAttribute("Pitch")
			if typeof(origin) == "Vector3" and type(size) == "number" and type(pitch) == "number" then
				local half = (size - 1) / 2 * pitch
				return origin + Vector3.new(half, 0, -half)
			end
		end
	end
	return nil
end

local function startOrbit()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	orbitAngle.Value = 0
	local tween = TweenService:Create(
		orbitAngle,
		TweenInfo.new(ORBIT_SECONDS, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
		{ Value = 360 }
	)
	orbitTween = tween
	tween:Play()
	orbitConnection = RunService.RenderStepped:Connect(function()
		local center = ownPlotCenter() or Vector3.new(0, 0, 60)
		local angle = math.rad(orbitAngle.Value)
		local eye = center
			+ Vector3.new(math.cos(angle) * ORBIT_RADIUS, ORBIT_HEIGHT, math.sin(angle) * ORBIT_RADIUS)
		camera.CFrame = CFrame.lookAt(eye, center)
	end)
end

local function stopOrbit()
	local wasOrbiting = orbitConnection ~= nil
	local tween = orbitTween
	if tween ~= nil then
		tween:Cancel()
		orbitTween = nil
	end
	local connection = orbitConnection
	if connection ~= nil then
		connection:Disconnect()
		orbitConnection = nil
	end
	-- Only hand the camera back if WE took it (the join orbit). Closing the menu later, e.g.
	-- while the player is in Control Mode, must not touch the bird's-eye camera.
	local camera = Workspace.CurrentCamera
	if wasOrbiting and camera ~= nil then
		camera.CameraType = Enum.CameraType.Custom
	end
end

local function open()
	if isOpen then
		return
	end
	isOpen = true
	gui.Enabled = true
	setWorldUiVisible(false)
	root.GroupTransparency = 1
	Theme.tween(root, { GroupTransparency = 0 }, Theme.Motion.Slow)
	Theme.tween(blur, { Size = 18 }, Theme.Motion.Slow)
	if not hasOrbited then
		hasOrbited = true
		startOrbit()
	end
end

local function close()
	if not isOpen then
		return
	end
	isOpen = false
	stopOrbit()
	helpCard.Visible = false
	setWorldUiVisible(true)
	Theme.tween(blur, { Size = 0 }, Theme.Motion.Slow)
	local fade = Theme.tween(root, { GroupTransparency = 1 }, Theme.Motion.Base)
	fade.Completed:Connect(function()
		if not isOpen then
			gui.Enabled = false
		end
	end)
end

local function menuButton(text: string, color: Color3?, order: number, parent: Instance): TextButton
	local button: TextButton
	if color ~= nil then
		button = Theme.button(text, color, {
			Font = Theme.UIFontHeavy,
			TextSize = 20,
			Size = UDim2.fromOffset(280, 54),
			LayoutOrder = order,
			Parent = parent,
		})
	else
		button = Components.ghostButton(text, {
			Font = Theme.UIFontHeavy,
			TextSize = 18,
			Size = UDim2.fromOffset(280, 46),
			LayoutOrder = order,
			Parent = parent,
		})
	end
	Components.hover(button)
	return button
end

local function refreshPlay()
	local ready = player:GetAttribute("DataLoaded") == true
	playButton.Text = if ready then "PLAY" else "LOADING YOUR FARM..."
	playButton.BackgroundColor3 = if ready then C.Accent else C.Raised
	playButton.AutoButtonColor = ready
end

function MainMenuController:Init()
	gui = Theme.create("ScreenGui", {
		Name = "MainMenu",
		ResetOnSpawn = false,
		DisplayOrder = 8,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Enabled = false,
	})
	root = Theme.create("CanvasGroup", {
		Name = "Root",
		BackgroundColor3 = C.Overlay,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	}, {
		Theme.create("UIGradient", {
			Rotation = 0,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.55, 0.45),
				NumberSequenceKeypoint.new(1, 0.9),
			}),
		}),
	})
	Theme.create("UIScale", { Parent = root })

	local column: Frame = Theme.create("Frame", {
		Name = "Column",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 72, 0.5, 0),
		Size = UDim2.fromOffset(520, 520),
		Parent = root,
	}, { Theme.list(Enum.FillDirection.Vertical, Theme.Space.M) })

	local titleRow: TextLabel = Components.label({
		Text = 'DRONE <font color="#7fd962">FARM</font>',
		RichText = true,
		Font = Theme.UIFontHeavy,
		TextSize = 72,
		Size = UDim2.new(1, 0, 0, 80),
		LayoutOrder = 1,
		Parent = column,
	})
	titleRow.TextStrokeTransparency = 0.7
	Components.label({
		Text = "Write code. Grow crops. Automate everything.",
		Font = Theme.UIFontBold,
		TextSize = 20,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 2,
		Parent = column,
	})
	Theme.create(
		"Frame",
		{ BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 18), LayoutOrder = 3, Parent = column }
	)

	playButton = menuButton("PLAY", C.Accent, 4, column)
	local techButton = menuButton("TECH TREE", nil, 5, column)
	local shopButton = menuButton("SHOP", nil, 6, column)
	local helpButton = menuButton("HOW TO PLAY", nil, 7, column)
	shopButton.TextColor3 = C.Gold

	helpCard = Components.panel({
		Name = "HowToPlay",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -72, 0.5, 0),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = root,
	})
	Theme.padding(Theme.Space.XL).Parent = helpCard
	Theme.list(Enum.FillDirection.Vertical, Theme.Space.S).Parent = helpCard
	Components.label({
		Text = "HOW TO PLAY",
		Font = Theme.UIFontHeavy,
		TextSize = 22,
		TextColor3 = C.Accent,
		Size = UDim2.new(1, 0, 0, 28),
		LayoutOrder = 0,
		Parent = helpCard,
	})
	for index, line in HOW_TO_PLAY do
		Components.label({
			Text = line,
			TextSize = 16,
			TextWrapped = true,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = index,
			Parent = helpCard,
		})
	end

	blur = Theme.create("BlurEffect", { Name = "MenuBlur", Size = 0, Parent = Lighting })
	orbitAngle = Theme.create("NumberValue", { Name = "MenuOrbit", Value = 0, Parent = gui })

	playButton.Activated:Connect(function()
		if player:GetAttribute("DataLoaded") == true then
			UIState.closeAll()
		end
	end)
	techButton.Activated:Connect(function()
		UIState.open("TechTree")
	end)
	shopButton.Activated:Connect(function()
		UIState.open("Shop")
	end)
	helpButton.Activated:Connect(function()
		helpCard.Visible = not helpCard.Visible
	end)

	UIState.register("MainMenu", {
		open = function()
			open()
		end,
		close = function()
			close()
		end,
	})
	gui.Parent = player:WaitForChild("PlayerGui")
end

function MainMenuController:Start()
	player:GetAttributeChangedSignal("DataLoaded"):Connect(refreshPlay)
	refreshPlay()
	task.defer(function()
		UIState.open("MainMenu")
	end)
end

return MainMenuController
