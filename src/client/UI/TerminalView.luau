--!strict
--[[
	TerminalView
	============
	Builds the drone terminal ScreenGui in code (no binary .rbxm files) and exposes small
	methods for the controller. Pure presentation: no networking or game logic in here.

	Layout (bottom-left, collapsible):
	  [ DRONE TERMINAL                    12/40 lines   [-] ]
	  [ main | utils | lab                     [ RENAME ]  ]   <- script slot tabs
	  [ 1 | # Welcome, farmer!                             ]   <- editor (gutter + TextBox)
	  [ 2 | move_up()                                      ]
	  [ output log (prints, hints, errors)                 ]
	  [ RUN ] [ STOP ]                               status
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")

local Components = require(script.Parent.Components)
local Fade = require(script.Parent.Fade)
local Theme = require(script.Parent.Theme)

local C = Theme.Colors
local TEXT_SIZE = 15
local GUTTER_WIDTH = 40
local MAX_OUTPUT_LINES = 120
local HEADER_H = 34
local TABS_H = 30
-- Console + drone are one show (ANIM-5): the running line slides, pulses on a NEW line, and
-- its gutter number turns lime; the header bar eases in while running; output rows fade in.
local LINE_SLIDE = TweenInfo.new(Theme.Motion.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LINE_PULSE = TweenInfo.new(0.075, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true) -- 1 -> 1.04 -> 1
local RUN_BAR_IN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RUN_BAR_OUT = TweenInfo.new(Theme.Motion.Base, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local OUTPUT_FADE = TweenInfo.new(Theme.Motion.Fast, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local RUN_EDGE_W = 3 -- px, the lime bar at the left of the running line

local OUTPUT_COLORS: { [string]: Color3 } = {
	print = C.Text,
	hint = C.Warning,
	info = C.Info,
	error = C.Danger,
	system = C.Muted,
}

export type TerminalView = {
	gui: ScreenGui,
	root: Frame, -- the terminal panel (the tutorial coach docks on top of it)
	editor: TextBox,
	runButton: TextButton,
	stopButton: TextButton,
	setLineInfo: (used: number, max: number) -> (),
	setStatus: (text: string, color: Color3) -> (),
	appendOutput: (kind: string, text: string) -> (),
	clearOutput: () -> (),
	highlightLine: (line: number?, kind: "run" | "error") -> (),
	shake: () -> (), -- a short, capped shake of the terminal frame (errors)
	setRunning: (running: boolean) -> (),
	setSlots: (names: { string }, active: number) -> (),
	setVip: (vip: boolean) -> (),
	-- Fade the whole terminal in/out (Control Mode only; hidden while exploring).
	setVisible: (visible: boolean, fadeTime: number?) -> (),
	isVisible: () -> boolean,
	onSlotSelected: ((slot: number) -> ())?,
	onRename: ((slot: number, name: string) -> ())?,
}

local TerminalView = {}

function TerminalView.build(): TerminalView
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- Exact line height of the code font, so the gutter and highlight line up with the text.
	local one = TextService:GetTextSize("A", TEXT_SIZE, Theme.CodeFont, Vector2.new(1000, 1000))
	local two = TextService:GetTextSize("A\nA", TEXT_SIZE, Theme.CodeFont, Vector2.new(1000, 1000))
	local lineHeight = two.Y - one.Y

	local gui = Theme.create("ScreenGui", {
		Name = "DroneTerminal",
		ResetOnSpawn = false,
		-- Starts hidden: the terminal belongs to Control Mode (ControlModeController shows it).
		Enabled = false,
		DisplayOrder = 1,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})

	local root = Theme.create("Frame", {
		Name = "Terminal",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, Theme.Space.M, 1, -Theme.Space.M),
		Size = UDim2.fromScale(0.36, 0.62),
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.04,
		Parent = gui,
	}, {
		Theme.corner(Theme.Radius.M),
		Theme.stroke(C.Border),
		Theme.create(
			"UISizeConstraint",
			{ MinSize = Vector2.new(340, 280), MaxSize = Vector2.new(580, 740) }
		),
	})

	-- Header ----------------------------------------------------------------
	local header = Theme.create("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, HEADER_H),
		BackgroundColor3 = C.Panel,
		Parent = root,
	}, { Theme.corner(Theme.Radius.M) })
	local title: TextLabel = Theme.create("TextLabel", {
		Text = "DRONE TERMINAL",
		Font = Theme.UIFontHeavy,
		TextSize = 14,
		TextColor3 = C.Accent,
		TextXAlignment = Enum.TextXAlignment.Left,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.fromScale(0.5, 1),
		Parent = header,
	})
	local lineInfo: TextLabel = Theme.create("TextLabel", {
		Text = "0/40 lines",
		Font = Theme.UIFont,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -44, 0, 0),
		Size = UDim2.fromScale(0.4, 1),
		Parent = header,
	})
	-- Running indicator (ANIM-5): a 2 px lime bar along the header's bottom edge that eases to
	-- full width when a run starts, sits there, and eases out when it stops. On the terminal,
	-- never over the 3D field.
	local runBar: Frame = Theme.create("Frame", {
		Name = "RunBar",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 2),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		Parent = header,
	})
	local runSweep: Frame = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Parent = runBar,
	})
	local runLoop: Tween? = nil

	local collapseButton = Theme.button("-", C.PanelLight, {
		TextColor3 = C.Text,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -6, 0.5, 0),
		Size = UDim2.fromOffset(28, 24),
		Parent = header,
	})

	-- Slot tabs -----------------------------------------------------------------
	local tabsRow: Frame = Theme.create("Frame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(8, HEADER_H + 2),
		Size = UDim2.new(1, -16, 0, TABS_H - 4),
		Parent = root,
	})
	local tabsList: Frame = Theme.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, -84, 1, 0),
		Parent = tabsRow,
	}, { Theme.list(Enum.FillDirection.Horizontal, 4) })
	local renameButton = Components.ghostButton("RENAME", {
		TextSize = 11,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 76, 1, 0),
		Parent = tabsRow,
	})
	local renameBox: TextBox = Theme.create("TextBox", {
		Name = "RenameBox",
		Text = "",
		PlaceholderText = "new name, then Enter",
		Font = Theme.CodeFont,
		TextSize = 13,
		TextColor3 = C.Text,
		PlaceholderColor3 = C.Muted,
		BackgroundColor3 = C.PanelLight,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -84, 1, 0),
		Visible = false,
		ZIndex = 5,
		Parent = tabsRow,
	}, { Theme.corner(Theme.Radius.S), Theme.stroke(C.Info) })

	-- Body --------------------------------------------------------------------
	local bodyTop = HEADER_H + TABS_H
	local body = Theme.create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, bodyTop),
		Size = UDim2.new(1, 0, 1, -bodyTop),
		Parent = root,
	}, { Theme.padding(8) })

	local editorScroll: ScrollingFrame = Theme.create("ScrollingFrame", {
		Name = "Editor",
		Size = UDim2.new(1, 0, 0.62, -24),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Border,
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, { Theme.corner(6) })

	local highlight: Frame = Theme.create("Frame", {
		Name = "LineHighlight",
		BackgroundColor3 = C.RunLine,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, lineHeight),
		Visible = false,
		ZIndex = 1,
		Parent = editorScroll,
	})
	local highlightScale: UIScale = Theme.create("UIScale", { Scale = 1, Parent = highlight })
	local runEdge: Frame = Theme.create("Frame", {
		Name = "Edge",
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, RUN_EDGE_W, 1, 0),
		ZIndex = 1,
		Parent = highlight,
	})

	local gutter: TextLabel = Theme.create("TextLabel", {
		Name = "Gutter",
		Text = "1",
		RichText = true, -- the running line's number is coloured (ANIM-5)
		Font = Theme.CodeFont,
		TextSize = TEXT_SIZE,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(GUTTER_WIDTH - 8, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 2,
		Parent = editorScroll,
	})

	local editor: TextBox = Theme.create("TextBox", {
		Name = "Code",
		Text = "",
		PlaceholderText = "# Write your drone program here",
		PlaceholderColor3 = C.Muted,
		Font = Theme.CodeFont,
		TextSize = TEXT_SIZE,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		MultiLine = true,
		ClearTextOnFocus = false,
		TextWrapped = false,
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(GUTTER_WIDTH, 0),
		Size = UDim2.new(1, -GUTTER_WIDTH - 6, 1, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		ZIndex = 2,
		Parent = editorScroll,
	})

	local outputScroll: ScrollingFrame = Theme.create("ScrollingFrame", {
		Name = "Output",
		Position = UDim2.new(0, 0, 0.62, -16),
		Size = UDim2.new(1, 0, 0.38, -30),
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Border,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = body,
	}, {
		Theme.corner(6),
		Theme.padding(6),
		Theme.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})

	-- Footer ------------------------------------------------------------------
	local footer = Theme.create("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 30),
		Parent = body,
	})
	local runButton = Theme.button("RUN", C.Accent, { Font = Theme.UIFontHeavy, Parent = footer })
	local stopButton = Theme.button("STOP", C.Danger, {
		Font = Theme.UIFontHeavy,
		Position = UDim2.fromOffset(92, 0),
		Parent = footer,
	})
	Components.hover(runButton)
	Components.hover(stopButton)
	local status: TextLabel = Theme.create("TextLabel", {
		Text = "Idle",
		Font = Theme.UIFont,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, -190, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = footer,
	})

	gui.Parent = playerGui

	-- Behaviour ---------------------------------------------------------------
	local collapsed = false
	collapseButton.Activated:Connect(function()
		collapsed = not collapsed
		body.Visible = not collapsed
		tabsRow.Visible = not collapsed
		root.Size = if collapsed then UDim2.new(0.36, 0, 0, HEADER_H) else UDim2.fromScale(0.36, 0.62)
		collapseButton.Text = if collapsed then "+" else "-"
	end)

	local homePosition = root.Position
	local shaking = false
	local outputOrder = 0
	local outputLabels: { TextLabel } = {}
	local tabButtons: { TextButton } = {}
	local activeSlot = 1
	local accent = C.Accent
	local lineCount = 1
	local running = false
	local runLine: number? = nil -- the line the drone is on while running (lime gutter number)
	local shownLine: number? = nil -- the line the highlight currently sits on
	local RUN_NUMBER = '<font color="#' .. C.Accent:ToHex() .. '">%d</font>'

	-- Gutter numbers 1..lineCount; the running line's number is lime while a run is going.
	local function renderGutter()
		local count = math.max(lineCount, 1)
		local numbers = table.create(count, "")
		for i = 1, count do
			numbers[i] = if running and i == runLine then string.format(RUN_NUMBER, i) else tostring(i)
		end
		gutter.Text = table.concat(numbers, "\n")
	end

	local view: TerminalView
	view = {
		gui = gui,
		root = root,
		editor = editor,
		runButton = runButton,
		stopButton = stopButton,
		onSlotSelected = nil,
		onRename = nil,

		setLineInfo = function(used: number, max: number)
			lineInfo.Text = string.format("%d/%d lines", used, max)
			lineInfo.TextColor3 = if used > max then C.Danger else C.Muted
			lineCount = used
			renderGutter()
		end,

		setStatus = function(text: string, color: Color3)
			status.Text = text
			status.TextColor3 = color
		end,

		appendOutput = function(kind: string, text: string)
			outputOrder += 1
			local label: TextLabel = Theme.create("TextLabel", {
				Text = text,
				Font = Theme.CodeFont,
				TextSize = 14,
				TextColor3 = OUTPUT_COLORS[kind] or C.Text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextWrapped = true,
				BackgroundTransparency = 1,
				Size = UDim2.new(1, -4, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = outputOrder,
				Parent = outputScroll,
			})
			-- Fade the new row in (ANIM-5). While the terminal is hidden, Fade.show does it.
			if Fade.isShown(gui) then
				Fade.setResting(label, "TextTransparency", 0)
				label.TextTransparency = 1
				TweenService:Create(label, OUTPUT_FADE, { TextTransparency = 0 }):Play()
			end
			table.insert(outputLabels, label)
			while #outputLabels > MAX_OUTPUT_LINES do
				local oldest = table.remove(outputLabels, 1)
				if oldest ~= nil then
					oldest:Destroy()
				end
			end
			task.defer(function()
				outputScroll.CanvasPosition = Vector2.new(0, math.max(0, outputScroll.AbsoluteCanvasSize.Y))
			end)
		end,

		clearOutput = function()
			for _, label in outputLabels do
				label:Destroy()
			end
			table.clear(outputLabels)
		end,

		-- The line highlight SLIDES to the new line (Motion.Fast) and pulses once per NEW line
		-- number, in time with the drone (ScriptStatus "line"). Errors use the red line.
		highlightLine = function(line: number?, kind: "run" | "error")
			if line == nil or line < 1 then
				highlight.Visible = false
				shownLine = nil
				runLine = nil
				renderGutter()
				return
			end
			highlight.BackgroundColor3 = if kind == "error" then C.ErrorLine else C.RunLine
			runEdge.BackgroundColor3 = if kind == "error" then C.Danger else C.Accent
			local target = UDim2.fromOffset(0, (line - 1) * lineHeight)
			if highlight.Visible then
				TweenService:Create(highlight, LINE_SLIDE, { Position = target }):Play()
			else
				highlight.Position = target -- appears in place, no slide from a stale line
				highlight.Visible = true
			end
			if line ~= shownLine then
				highlightScale.Scale = 1
				TweenService:Create(highlightScale, LINE_PULSE, { Scale = 1.04 }):Play()
			end
			shownLine = line
			runLine = if kind == "run" then line else nil
			renderGutter()
		end,

		setRunning = function(isRunning: boolean)
			running = isRunning
			runButton.AutoButtonColor = not isRunning
			runButton.BackgroundColor3 = if isRunning then C.PanelLight else accent
			local loop = runLoop
			if loop ~= nil then
				loop:Cancel()
				runLoop = nil
			end
			if isRunning then
				runBar.Visible = true
				runSweep.Size = UDim2.fromScale(0, 1)
				local grow = TweenService:Create(runSweep, RUN_BAR_IN, { Size = UDim2.fromScale(1, 1) })
				runLoop = grow
				grow:Play()
			elseif runBar.Visible then
				local shrink = TweenService:Create(runSweep, RUN_BAR_OUT, { Size = UDim2.fromScale(0, 1) })
				shrink.Completed:Once(function(state: Enum.PlaybackState)
					if state == Enum.PlaybackState.Completed and not running then
						runBar.Visible = false
					end
				end)
				runLoop = shrink
				shrink:Play()
			end
			renderGutter()
		end,

		-- 0.2 s elastic nudge of the whole frame (never the camera). A shake already playing
		-- isn't restarted, so a burst of errors can't make it jitter.
		shake = function()
			if shaking then
				return
			end
			shaking = true
			local offset = Instance.new("NumberValue")
			offset.Value = 7
			offset.Changed:Connect(function()
				root.Position = homePosition + UDim2.fromOffset(offset.Value, 0)
			end)
			local tween = TweenService:Create(
				offset,
				TweenInfo.new(0.2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out),
				{ Value = 0 }
			)
			tween.Completed:Connect(function()
				root.Position = homePosition
				offset:Destroy()
				shaking = false
			end)
			tween:Play()
		end,

		setSlots = function(names: { string }, active: number)
			activeSlot = active
			for _, button in tabButtons do
				button:Destroy()
			end
			table.clear(tabButtons)
			for slot, name in names do
				local isActive = slot == active
				local button: TextButton = Theme.create("TextButton", {
					Name = "Slot" .. slot,
					Text = name,
					Font = Theme.CodeFont,
					TextSize = 13,
					TextColor3 = if isActive then C.Background else C.Muted,
					BackgroundColor3 = if isActive then accent else C.Panel,
					AutoButtonColor = true,
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, TABS_H - 4),
					LayoutOrder = slot,
					Parent = tabsList,
				}, { Theme.corner(Theme.Radius.S), Theme.padding(0, 10) })
				button.Activated:Connect(function()
					local callback = view.onSlotSelected
					if callback ~= nil and slot ~= activeSlot then
						callback(slot)
					end
				end)
				table.insert(tabButtons, button)
			end
		end,

		setVisible = function(visible: boolean, fadeTime: number?)
			if visible then
				Fade.show(gui, fadeTime)
			else
				-- Never leave an invisible TextBox holding keyboard focus.
				if editor:IsFocused() then
					editor:ReleaseFocus()
				end
				if renameBox:IsFocused() then
					renameBox:ReleaseFocus()
				end
				Fade.hide(gui, fadeTime)
			end
		end,

		isVisible = function(): boolean
			return Fade.isShown(gui)
		end,

		setVip = function(vip: boolean)
			accent = if vip then C.Gold else C.Accent
			title.Text = if vip then "DRONE TERMINAL  VIP" else "DRONE TERMINAL"
			title.TextColor3 = accent
			runButton.BackgroundColor3 = accent
			for index, button in tabButtons do
				if index == activeSlot then
					button.BackgroundColor3 = accent
				end
			end
		end,
	}

	renameButton.Activated:Connect(function()
		renameBox.Visible = true
		renameBox.Text = ""
		renameBox:CaptureFocus()
	end)
	renameBox.FocusLost:Connect(function(enterPressed: boolean)
		renameBox.Visible = false
		local callback = view.onRename
		if enterPressed and callback ~= nil and renameBox.Text ~= "" then
			callback(activeSlot, renameBox.Text)
		end
	end)

	return view
end

return TerminalView
