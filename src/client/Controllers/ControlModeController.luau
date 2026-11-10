--!strict
--[[
	ControlModeController
	=====================
	Switches the local player between normal multiplayer EXPLORATION and the isolated
	CONTROL MODE (bird's-eye view of their own farm + the coding terminal).
	Runs inside the client LocalScript (ClientMain.client.luau) like every other controller.

	STATE MACHINE
	                 click WATCH / CONTROL                    camera tween done
	  ┌───────────┐ ────────────────────────► ┌──────────┐ ─────────────────► ┌─────────────┐
	  │ Exploring │                           │ Entering │                    │ Controlling │
	  └───────────┘ ◄──────────────────────── └──────────┘ ◄── (Leave while   └─────────────┘
	        ▲          camera tween done        ┌─────────┐      entering)          │ click LEAVE
	        └───────────────────────────────────│ Exiting │◄────────────────────────┘ / gamepad B
	                                            └─────────┘
	  Death, reset, character removal, or the plot disappearing jump straight back to
	  Exploring with NO tween (instant, always safe).

	EXPLORATION
	  * Standard Roblox camera (Custom), the player walks freely, the terminal is hidden.
	  * Every CONFIG.ZoneCheckInterval seconds the HumanoidRootPart position is tested against
	    the invisible "Zone" part of the player's OWN plot (built and resized by the server's
	    GridService; see docs/UI_UX_GUIDE.md). Inside -> the WATCH / CONTROL button fades in;
	    outside -> it fades out. Other players' plots never show the button.
	  * Why not Touched/TouchEnded? They fire per limb, never fire while standing still,
	    flicker during walk animations and depend on physics. A point-in-box test of one part,
	    ten times a second, is exact and nearly free. Hysteresis (CONFIG.ExitMargin) stops the
	    button flickering when standing on the edge.

	CONTROL MODE
	  * Movement is locked through the default PlayerModule (Controls:Disable() - keyboard,
	    gamepad, touch thumbstick and click-to-move). If the PlayerModule isn't available the
	    fallback zeroes WalkSpeed/JumpPower/JumpHeight and restores the exact saved values.
	  * Camera: CameraType = Scriptable, then a TweenService tween of Camera.CFrame from where
	    it is (behind the character's head) to a fixed bird's-eye CFrame above the grid
	    (Shared.Util.PlotFraming computes a distance that fits the field + station row next to
	    the terminal).
	  * The terminal and LEAVE fade in once the camera has arrived.
	  * Leaving tweens the camera back to the pose it had on entry (re-anchored to the head),
	    then CameraType = Custom and movement is restored.

	This mode is presentation only: the drone program keeps running on the server either way,
	and nothing here is trusted by the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local PlotFraming = require(ReplicatedStorage.Shared.Util.PlotFraming)
local Client = script.Parent.Parent
local Components = require(Client.UI.Components)
local Fade = require(Client.UI.Fade)
local Theme = require(Client.UI.Theme)
local UIState = require(Client.UI.UIState)
local TerminalController = require(script.Parent.TerminalController)

--------------------------------------------------------------------------------------- config
local CONFIG = {
	ZoneCheckInterval = 0.1, -- seconds between "am I on my plot?" checks
	ExitMargin = 1.5, -- studs past the zone edge before we count you as "off the plot"
	EnterTime = 1.1, -- camera tween: character -> bird's-eye
	ExitTime = 0.9, -- camera tween: bird's-eye -> character
	ReframeTime = 0.5, -- re-fit after a Grid Expansion or a window resize
	ViewAngle = 80, -- degrees below the horizon; 90 = perfectly straight down
	FrameMargin = 1.12, -- 12 % breathing room around the field
	TerminalReserve = 0.38, -- fraction of the screen width on the left kept free for the terminal
	UiFadeTime = 0.25, -- button / terminal fades
	ResizeDebounce = 0.3, -- seconds to wait after the last viewport change before re-framing
}

local RENDER_STEP_NAME = "DroneFarm_ControlMode"
local CAMERA_EASING = TweenInfo.new(CONFIG.EnterTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

------------------------------------------------------------------------------------- types
type State = "Exploring" | "Entering" | "Controlling" | "Exiting"

-- What we changed on entry, so leaving can put it back exactly.
type EntryState = {
	cameraCFrame: CFrame, -- where the camera was when the player clicked WATCH / CONTROL
	headPosition: Vector3, -- where the head was at that moment
}

type MovementLock = {
	humanoid: Humanoid,
	usedFallback: boolean, -- true if the PlayerModule wasn't available
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
}

------------------------------------------------------------------------------------- state
local player = Players.LocalPlayer
local C = Theme.Colors

local ControlModeController = {}

local state: State = "Exploring"
local inZone = false -- the player's root part is inside their own plot's Zone
local menuOpen = false -- the full-screen main menu is up (it covers everything)
local ownPlot: Model? = nil
local plotConnections: { RBXScriptConnection } = {}
local characterConnections: { RBXScriptConnection } = {}

local entry: EntryState? = nil
local movementLock: MovementLock? = nil
local controls: any = nil -- PlayerModule ControlModule (loaded in Start)
local cameraTween: Tween? = nil
local renderBound = false
local characterParts: { BasePart } = {}
-- Your character while you code: hidden, non-colliding and anchored (saved to restore).
local frozen: { parts: { { part: BasePart, collide: boolean } }, root: BasePart?, anchored: boolean }? = nil
-- You died / were killed in Control Mode: go straight back into it after the respawn.
local resumeAfterRespawn = false
local resizeVersion = 0

-- UI
local gui: ScreenGui
local uiScale: UIScale
local controlRoot: Frame
local leaveRoot: Frame
local controlButton: TextButton
local leaveButton: TextButton

-------------------------------------------------------------------------- small helpers
-- Reads the LIVE state. Tween callbacks run later than the code that scheduled them, so they
-- must not rely on what `state` was when the tween started.
local function currentState(): State
	return state
end

local function disconnectAll(list: { RBXScriptConnection })
	for _, connection in list do
		connection:Disconnect()
	end
	table.clear(list)
end

local function getCharacterPart(name: string): BasePart?
	local character = player.Character
	local part = if character ~= nil then character:FindFirstChild(name) else nil
	return if part ~= nil and part:IsA("BasePart") then part else nil
end

-- The living humanoid of the current character, or nil (no character / dead).
local function getLivingHumanoid(): Humanoid?
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid == nil or humanoid.Health <= 0 then
		return nil
	end
	return humanoid
end

local function getZone(): BasePart?
	local plot = ownPlot
	if plot == nil then
		return nil
	end
	local zone = plot:FindFirstChild("Zone")
	return if zone ~= nil and zone:IsA("BasePart") then zone else nil
end

-------------------------------------------------------------------------------------- UI
--[[
	One function decides what is on screen from the current state - so every event (zone
	change, state change, menu open/close, respawn) just calls refreshUi() and can never leave
	a stale button or terminal behind.
]]
local function refreshUi(animated: boolean)
	local fade = if animated then CONFIG.UiFadeTime else 0
	local showControl = state == "Exploring" and inZone and ownPlot ~= nil and not menuOpen
	local showLeave = state == "Controlling" and not menuOpen
	local showTerminal = state == "Controlling" and not menuOpen

	if showControl then
		Fade.show(controlRoot, fade)
	else
		Fade.hide(controlRoot, fade)
	end
	if showLeave then
		Fade.show(leaveRoot, fade)
	else
		Fade.hide(leaveRoot, fade)
	end
	TerminalController:SetVisible(showTerminal, fade)

	-- Inactive buttons ignore clicks even while they are still fading out.
	controlButton.Active = showControl
	leaveButton.Active = showLeave
end

local function refreshScale()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local viewport = camera.ViewportSize
		-- Same rule as the HUD, so all screen UI scales together.
		uiScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.65, 1.15)
	end
end

-- A big two-line button: title + subtitle.
local function buildButton(
	parent: Instance,
	title: string,
	subtitle: string,
	color: Color3,
	textColor: Color3
): TextButton
	local button: TextButton = Theme.create("TextButton", {
		Text = "",
		AutoButtonColor = true,
		BackgroundColor3 = color,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	}, { Theme.corner(Theme.Radius.M) })
	Components.label({
		Text = title,
		Font = Theme.UIFontHeavy,
		TextSize = 19,
		TextColor3 = textColor,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 8),
		Size = UDim2.new(1, 0, 0, 24),
		Parent = button,
	})
	Components.label({
		Text = subtitle,
		TextSize = 13,
		TextColor3 = textColor,
		TextTransparency = 0.25,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 0, 18),
		Parent = button,
	})
	Components.hover(button)
	return button
end

local function buildUi()
	gui = Theme.create("ScreenGui", {
		Name = "ControlMode",
		ResetOnSpawn = false, -- survives respawns; we manage it ourselves
		DisplayOrder = 2, -- above the HUD (0) and terminal (1), below panels (5)
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	uiScale = Theme.create("UIScale", { Parent = gui })

	-- Both buttons sit in the same spot (bottom-centre) so the player's hand learns one place.
	controlRoot = Theme.create("Frame", {
		Name = "Control",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		Size = UDim2.fromOffset(260, 60),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	controlButton =
		buildButton(controlRoot, "WATCH / CONTROL", "watch & code your farm", C.Accent, C.Background)

	leaveRoot = Theme.create("Frame", {
		Name = "Leave",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -Theme.Space.L),
		Size = UDim2.fromOffset(220, 60),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	leaveButton = buildButton(leaveRoot, "LEAVE", "back to exploring", C.PanelLight, C.Text)
	Theme.stroke(C.Danger, 2, 0.2).Parent = leaveButton

	gui.Parent = player:WaitForChild("PlayerGui")
end

------------------------------------------------------------------------- movement lock
local function lockMovement(humanoid: Humanoid)
	local usedFallback = true
	if controls ~= nil then
		-- Disables every input path the PlayerModule owns (keys, gamepad, thumbstick, click-to-move).
		usedFallback = not pcall(function()
			controls:Disable()
		end)
	end
	movementLock = {
		humanoid = humanoid,
		usedFallback = usedFallback,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
	}
	if usedFallback then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
	humanoid:Move(Vector3.zero) -- stop any momentum from the last key press
end

local function unlockMovement()
	local lock = movementLock
	movementLock = nil
	-- Always re-enable: the ControlModule lives in PlayerScripts and survives respawns, so a
	-- Disable() that is never undone would leave the NEXT character frozen too.
	if controls ~= nil then
		pcall(function()
			controls:Enable()
		end)
	end
	if lock ~= nil and lock.usedFallback and lock.humanoid.Parent ~= nil then
		lock.humanoid.WalkSpeed = lock.walkSpeed
		lock.humanoid.JumpPower = lock.jumpPower
		lock.humanoid.JumpHeight = lock.jumpHeight
	end
end

---------------------------------------------------------------------------------- camera
local function cancelCameraTween()
	local tween = cameraTween
	if tween ~= nil then
		cameraTween = nil
		tween:Cancel()
	end
end

-- Tweens Workspace.CurrentCamera.CFrame; `onArrived` only runs if the tween wasn't replaced.
local function tweenCamera(goal: CFrame, duration: number, onArrived: (() -> ())?)
	cancelCameraTween()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local info = TweenInfo.new(duration, CAMERA_EASING.EasingStyle, CAMERA_EASING.EasingDirection)
	local tween = TweenService:Create(camera, info, { CFrame = goal })
	cameraTween = tween
	tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if cameraTween == tween then
			cameraTween = nil
		end
		if playbackState == Enum.PlaybackState.Completed and onArrived ~= nil then
			onArrived()
		end
	end)
	tween:Play()
end

--[[
	The fixed bird's-eye CFrame for a plot, from the attributes GridService publishes:
	Origin (top-centre of tile 0,0), Size (tiles per side) and Pitch (studs between tiles).
	The camera looks down at CONFIG.ViewAngle; screen-up is world -Z (grid "up"), screen-right
	is world +X (grid x), and the view is shifted left so the field sits right of the terminal.
]]
local function birdsEyeCFrame(plot: Model): CFrame?
	local origin = plot:GetAttribute("Origin")
	local size = plot:GetAttribute("Size")
	local pitch = plot:GetAttribute("Pitch")
	local camera = Workspace.CurrentCamera
	if typeof(origin) ~= "Vector3" or type(size) ~= "number" or type(pitch) ~= "number" or camera == nil then
		return nil
	end
	local viewport = camera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local distance, shift = PlotFraming.solve(
		size,
		pitch,
		camera.FieldOfView,
		aspect,
		CONFIG.TerminalReserve,
		CONFIG.FrameMargin,
		CONFIG.ViewAngle
	)
	local centerX, centerZ = PlotFraming.center(origin.X, origin.Z, size, pitch)
	local target = Vector3.new(centerX - shift, origin.Y, centerZ)
	local angle = math.rad(CONFIG.ViewAngle)
	-- The eye sits above the target and (unless ViewAngle is 90) a little toward +Z, the
	-- walkway side the player came from, so a tilted view looks "into" the field.
	local eye = target + Vector3.new(0, distance * math.sin(angle), distance * math.cos(angle))
	return CFrame.lookAt(eye, target, Vector3.new(0, 0, -1))
end

-- Puts the camera back under the default camera scripts, following the current character.
local function restoreDefaultCamera()
	cancelCameraTween()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	local character = player.Character
	local humanoid = if character ~= nil then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid ~= nil then
		camera.CameraSubject = humanoid
	end
end

local function reframe()
	local plot = ownPlot
	if state ~= "Controlling" or plot == nil then
		return
	end
	local goal = birdsEyeCFrame(plot)
	if goal ~= nil then
		tweenCamera(goal, CONFIG.ReframeTime)
	end
end

--------------------------------------------------------------------- per-frame guard
--[[
	While the camera is ours, the default camera scripts aren't driving the mouse any more. If
	the player entered from first person or shift-lock, the mouse would stay locked to the
	screen centre and the character would stay invisible (first person hides it). This runs
	right after the camera step every frame and keeps both sane. Your own character is HIDDEN
	(LocalTransparencyModifier 1: it would only clutter the bird's-eye view) and kept
	non-colliding while you code.
]]
local function bindRenderGuard()
	if renderBound then
		return
	end
	renderBound = true
	table.clear(characterParts)
	local character = player.Character
	if character ~= nil then
		for _, descendant in character:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(characterParts, descendant)
			end
		end
	end
	RunService:BindToRenderStep(RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		for _, part in characterParts do
			-- Hidden from your own bird's-eye view, and no collisions the Humanoid could re-enable.
			part.LocalTransparencyModifier = 1
			part.CanCollide = false
		end
	end)
end

local function unbindRenderGuard()
	if not renderBound then
		return
	end
	renderBound = false
	RunService:UnbindFromRenderStep(RENDER_STEP_NAME)
	table.clear(characterParts)
end

------------------------------------------------------------------ character safety
-- While coding, your character is non-colliding (nobody can shove it) and its root is
-- anchored so the non-colliding body can't fall through the walkway. Restored on leave.
local function freezeCharacter()
	local character = player.Character
	if character == nil or frozen ~= nil then
		return
	end
	local saved: { parts: { { part: BasePart, collide: boolean } }, root: BasePart?, anchored: boolean } =
		{ parts = {}, root = nil, anchored = false }
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(saved.parts, { part = descendant, collide = descendant.CanCollide })
			descendant.CanCollide = false
		end
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		saved.root = root
		saved.anchored = root.Anchored
		root.Anchored = true
	end
	frozen = saved
end

local function thawCharacter()
	local saved = frozen
	frozen = nil
	if saved == nil then
		return
	end
	for _, entry in saved.parts do
		if entry.part.Parent ~= nil then
			entry.part.CanCollide = entry.collide
			entry.part.LocalTransparencyModifier = 0
		end
	end
	local root = saved.root
	if root ~= nil and root.Parent ~= nil then
		root.Anchored = saved.anchored
	end
end

-- Reset is off while you code, so nobody can "close your IDE" by making you reset.
local function setResetEnabled(enabled: boolean)
	task.spawn(function()
		for _ = 1, 5 do -- SetCore fails until the CoreGui has registered the callback
			if pcall(StarterGui.SetCore, StarterGui, "ResetButtonCallback", enabled) then
				return
			end
			task.wait(0.5)
		end
	end)
end

-------------------------------------------------------------------------- transitions
local function finishExit(animated: boolean)
	unbindRenderGuard()
	thawCharacter()
	setResetEnabled(true)
	restoreDefaultCamera()
	unlockMovement()
	entry = nil
	state = "Exploring"
	refreshUi(animated)
end

local function enter()
	-- Only from Exploration, only on your own plot, only when nothing covers the screen.
	if state ~= "Exploring" or menuOpen or not inZone then
		return
	end
	local plot = ownPlot
	local humanoid = getLivingHumanoid()
	local head = getCharacterPart("Head") or getCharacterPart("HumanoidRootPart")
	local camera = Workspace.CurrentCamera
	if plot == nil or humanoid == nil or head == nil or camera == nil then
		return
	end
	local goal = birdsEyeCFrame(plot)
	if goal == nil then
		return
	end

	state = "Entering"
	entry = { cameraCFrame = camera.CFrame, headPosition = head.Position }
	lockMovement(humanoid)
	freezeCharacter()
	setResetEnabled(false)
	-- Scriptable = the default camera scripts stop moving the camera; we own it now.
	camera.CameraType = Enum.CameraType.Scriptable
	bindRenderGuard()
	refreshUi(true) -- hides WATCH / CONTROL right away

	tweenCamera(goal, CONFIG.EnterTime, function()
		if currentState() ~= "Entering" then
			return -- the player left (or died) during the flight
		end
		state = "Controlling"
		refreshUi(true) -- terminal + LEAVE fade in
	end)
end

--[[
	Leave Control Mode. `instant` skips every tween (used for death, reset, character removal
	and the plot disappearing) so the camera is ALWAYS left in a normal state.
]]
local function exit(instant: boolean)
	if state == "Exploring" then
		return
	end
	if instant then
		finishExit(false)
		return
	end
	if state == "Exiting" then
		return -- already on the way back
	end

	state = "Exiting"
	refreshUi(true) -- terminal + LEAVE fade out (and the editor loses focus)

	-- Return to the pose the camera had on entry, re-anchored to where the head is now.
	local saved = entry
	local head = getCharacterPart("Head") or getCharacterPart("HumanoidRootPart")
	if saved == nil or head == nil then
		finishExit(true)
		return
	end
	local goal = saved.cameraCFrame + (head.Position - saved.headPosition)
	tweenCamera(goal, CONFIG.ExitTime, function()
		if currentState() == "Exiting" then
			finishExit(true)
		end
	end)
end

------------------------------------------------------------------------ zone detection
local function updateZone()
	local zone = getZone()
	local root = getCharacterPart("HumanoidRootPart")
	local nowInside = false
	if zone ~= nil and root ~= nil and getLivingHumanoid() ~= nil then
		local localPoint = zone.CFrame:PointToObjectSpace(root.Position)
		-- Hysteresis: no margin to get in, ExitMargin studs extra before we let you out.
		local margin = if inZone then CONFIG.ExitMargin else 0
		local size = zone.Size
		nowInside =
			PlotFraming.inside(localPoint.X, localPoint.Y, localPoint.Z, size.X, size.Y, size.Z, margin)
	end
	if nowInside ~= inZone then
		inZone = nowInside
		refreshUi(true)
	end
end

--------------------------------------------------------------------------- own plot
--[[
	Your own plot's guest walls (attribute PlotBarrier, Server.Services.PlotGuardService):
	turned off HERE, locally. Your character is simulated by this client, so only you pass;
	every other player still collides with them, and the server ejects any guest anyway.
]]
local function openOwnBarrier(child: Instance)
	if not child:IsA("BasePart") or child:GetAttribute("PlotBarrier") == nil then
		return
	end
	child.CanCollide = false
	table.insert(
		plotConnections,
		child:GetPropertyChangedSignal("CanCollide"):Connect(function()
			if child.CanCollide then
				child.CanCollide = false -- the server re-closed them (AllowVisitors off)
			end
		end)
	)
end

local function setOwnPlot(plot: Model?)
	if ownPlot == plot then
		return
	end
	disconnectAll(plotConnections)
	ownPlot = plot
	if plot == nil then
		-- The plot is gone (streamed out / rebuilt): drop out of Control Mode safely.
		exit(true)
		inZone = false
		refreshUi(true)
		return
	end
	for _, child in plot:GetChildren() do
		openOwnBarrier(child)
	end
	table.insert(plotConnections, plot.ChildAdded:Connect(openOwnBarrier))
	-- Grid Expansion while watching: the server grows the field; fit the new size.
	table.insert(
		plotConnections,
		plot:GetAttributeChangedSignal("Size"):Connect(function()
			reframe()
		end)
	)
	table.insert(
		plotConnections,
		plot.AncestryChanged:Connect(function()
			if not plot:IsDescendantOf(Workspace) and ownPlot == plot then
				setOwnPlot(nil)
			end
		end)
	)
	refreshUi(true)
end

local function considerPlot(child: Instance)
	if child:IsA("Model") and child:GetAttribute("OwnerUserId") == player.UserId then
		setOwnPlot(child)
	end
end

------------------------------------------------------------------------------ character
local function onCharacterAdded(character: Model)
	disconnectAll(characterConnections)
	-- A new life always starts in Exploration with the default camera and working controls,
	-- whatever happened to the previous one.
	if state ~= "Exploring" or movementLock ~= nil or renderBound then
		finishExit(false)
	end
	local camera = Workspace.CurrentCamera
	if
		camera ~= nil
		and camera.CameraType == Enum.CameraType.Scriptable
		and UIState.current() ~= "MainMenu"
	then
		restoreDefaultCamera()
	end

	task.spawn(function()
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid == nil or not humanoid:IsA("Humanoid") or player.Character ~= character then
			return
		end
		-- Dying in the bird's-eye view: snap everything back immediately (no tween), and
		-- remember to go straight back INTO Control Mode once the new character is on the plot.
		table.insert(
			characterConnections,
			humanoid.Died:Connect(function()
				resumeAfterRespawn = state ~= "Exploring"
				exit(true)
			end)
		)
		if resumeAfterRespawn then
			resumeAfterRespawn = false
			-- The server puts the new character on your walkway (inside your Zone) right away.
			local deadline = os.clock() + 6
			while os.clock() < deadline and player.Character == character and not inZone do
				task.wait(0.1)
			end
			if player.Character == character and inZone then
				enter()
			end
		end
		if camera ~= nil and UIState.current() ~= "MainMenu" then
			camera.CameraSubject = humanoid
		end
	end)
end

-------------------------------------------------------------------------- lifecycle
function ControlModeController:Init()
	buildUi()
	refreshScale()

	controlButton.Activated:Connect(function()
		enter()
	end)
	leaveButton.Activated:Connect(function()
		if state == "Controlling" then
			exit(false)
		end
	end)

	-- Connected in Init (no yielding) so the main menu's first open is never missed.
	UIState.Changed:Connect(function(name: string?)
		local nowMenuOpen = name == "MainMenu"
		if nowMenuOpen ~= menuOpen then
			menuOpen = nowMenuOpen
			-- Hide instantly under the menu; fade back in when it closes.
			refreshUi(not menuOpen)
		end
	end)
	-- Gamepad B with no panel open = LEAVE (UIState decides, so one press never does both).
	UIState.Back:Connect(function()
		if state == "Controlling" or state == "Entering" then
			exit(false)
		end
	end)
end

function ControlModeController:Start()
	menuOpen = UIState.current() == "MainMenu"

	-- The default PlayerModule (inserted by Roblox into PlayerScripts) owns movement input.
	task.spawn(function()
		pcall(function()
			local playerScripts = player:WaitForChild("PlayerScripts", 10)
			local module = if playerScripts ~= nil
				then playerScripts:WaitForChild("PlayerModule", 10)
				else nil
			if module ~= nil and module:IsA("ModuleScript") then
				controls = (require(module) :: any):GetControls()
			end
		end)
	end)

	-- Window / device rotation: rescale the buttons and (debounced) re-fit the bird's-eye view.
	local function watchCamera(camera: Camera?)
		if camera == nil then
			return
		end
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			refreshScale()
			resizeVersion += 1
			local version = resizeVersion
			task.delay(CONFIG.ResizeDebounce, function()
				if version == resizeVersion then
					reframe()
				end
			end)
		end)
	end
	watchCamera(Workspace.CurrentCamera)
	-- If the engine replaces the camera object while we own it, take the new one too.
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local camera = Workspace.CurrentCamera
		watchCamera(camera)
		refreshScale()
		if camera ~= nil and (state == "Entering" or state == "Controlling") then
			camera.CameraType = Enum.CameraType.Scriptable
			reframe()
		end
	end)

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		exit(true) -- reset / respawn / teleport: never leave the camera scriptable
		disconnectAll(characterConnections)
	end)
	if player.Character ~= nil then
		onCharacterAdded(player.Character)
	end

	-- Find our plot (it may appear after we join, or be rebuilt / streamed in again later).
	local plots = Workspace:WaitForChild("Plots")
	plots.ChildAdded:Connect(considerPlot)
	plots.ChildRemoved:Connect(function(child: Instance)
		if child == ownPlot then
			setOwnPlot(nil)
		end
	end)
	for _, child in plots:GetChildren() do
		considerPlot(child)
	end

	-- The zone check: a cheap point-in-box test, ten times a second.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt: number)
		elapsed += dt
		if elapsed >= CONFIG.ZoneCheckInterval then
			elapsed = 0
			updateZone()
		end
	end)
	refreshUi(false)
end

-- True while the player is in (or flying into / out of) Control Mode.
function ControlModeController:IsActive(): boolean
	return state ~= "Exploring"
end

-- Leave Control Mode from other code (`instant` = no tween).
function ControlModeController:Exit(instant: boolean?)
	exit(instant == true)
end

return ControlModeController
