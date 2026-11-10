--!strict
--[[
	TerminalController
	==================
	Editor behaviour and the client side of running programs.

	  * Loads every saved script slot (and its module name) once DataLoaded is true.
	  * Slot tabs: switching saves the current slot first, then shows the other one. RENAME
	    pre-checks the name with the shared ScriptNames rules, then asks the server
	    (RenameScript), which re-validates it. Slot names are what `import` uses.
	  * Editor helpers: Tab inserts 4 spaces, Enter keeps the indentation (and indents after a
	    line ending in ':'), pasted tabs become spaces, size is capped at MaxSourceBytes.
	  * Autosave 3 s after the last keystroke (SaveScript), only when the text changed.
	  * RUN: pre-checks the code with the SAME shared Parser and the player's unlocks (from the
	    Tech_* attributes) for instant feedback, then sends the RAW TEXT to the server, which
	    re-checks everything with saved data. The client never sends anything but the source.
	  * Highlights the line that is running (ScriptStatus "line") or failed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Parser = require(ReplicatedStorage.Shared.DroneScript.Parser)
local ScriptNames = require(ReplicatedStorage.Shared.DroneScript.ScriptNames)
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Text = require(ReplicatedStorage.Shared.Util.Text)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Theme = require(Client.UI.Theme)
local TerminalView = require(Client.UI.TerminalView)
local NotifyController = require(script.Parent.NotifyController)

local C = Theme.Colors
local AUTOSAVE_DELAY = 3
local RUN_COOLDOWN = 1.2

local player = Players.LocalPlayer

local TerminalController = {}

local view: TerminalView.TerminalView
local slot = 1
local sources: { string } = {} -- latest known text per slot (saved or being edited)
local savedSources: { string } = {} -- what the server has per slot
local names: { string } = table.clone(GameConfig.Script.DefaultNames)
local lastText = ""
local suppress = false
local editVersion = 0
local lastRunAt = 0
local lastStopAt = 0
local loaded = false

local function maxLines(): number
	local value = player:GetAttribute("MaxLines")
	return if type(value) == "number" then value else GameConfig.Script.BaseMaxLines
end

-- Unlock predicate from replicated attributes (display only - the server uses saved data).
local function clientUnlocks(): (feature: string) -> boolean
	local unlocks: { [string]: boolean } = {}
	for _, id in Tech.NodeIds do
		if player:GetAttribute("Tech_" .. id) == true then
			unlocks[id] = true
		end
	end
	return function(feature: string): boolean
		return Tech.isFeatureUnlocked(unlocks, feature)
	end
end

local function refreshLineInfo()
	view.setLineInfo(math.max(Text.countLines(view.editor.Text), 1), maxLines())
end

local function setText(text: string, cursor: number?)
	suppress = true
	view.editor.Text = text
	if cursor ~= nil then
		view.editor.CursorPosition = cursor
	end
	suppress = false
	lastText = text
end

-- Saves `targetSlot` if its text differs from what the server has. Returns true when saved.
local function saveSlot(targetSlot: number): boolean
	local text = sources[targetSlot]
	if text == nil or text == savedSources[targetSlot] then
		return true
	end
	local ok, saved = Net.invoke("SaveScript", targetSlot, text)
	if ok and saved == true then
		savedSources[targetSlot] = text
		return true
	end
	return false
end

local function scheduleAutosave()
	editVersion += 1
	local version = editVersion
	local targetSlot = slot
	task.delay(AUTOSAVE_DELAY, function()
		if version ~= editVersion then
			return -- typed again since; a newer timer will save
		end
		saveSlot(targetSlot)
	end)
end

local function onTextChanged()
	if suppress then
		return
	end
	local editor = view.editor
	local text = editor.Text
	local cursor = editor.CursorPosition

	-- Pasted tabs -> 4 spaces.
	if string.find(text, "\t", 1, true) ~= nil then
		local before = if cursor > 0 then string.sub(text, 1, cursor - 1) else text
		local _, tabsBefore = string.gsub(before, "\t", "")
		text = string.gsub(text, "\t", "    ")
		if cursor > 0 then
			cursor += tabsBefore * 3
		end
		setText(text, cursor)
	end

	-- Enter: keep indentation, add one level after a line that ends with ':'.
	if #text == #lastText + 1 and cursor > 1 and string.sub(text, cursor - 1, cursor - 1) == "\n" then
		local before = string.sub(text, 1, cursor - 2)
		if before == string.sub(lastText, 1, cursor - 2) then
			local previousLine = string.match(before, "([^\n]*)$") or ""
			local indent = string.match(previousLine, "^ *") or ""
			if string.match(previousLine, ":%s*$") ~= nil then
				indent ..= "    "
			end
			if indent ~= "" then
				text = string.sub(text, 1, cursor - 1) .. indent .. string.sub(text, cursor)
				setText(text, cursor + #indent)
			end
		end
	end

	-- Size cap (the server rejects anything bigger anyway).
	if #text > GameConfig.Script.MaxSourceBytes then
		text = Text.truncateUtf8(text, GameConfig.Script.MaxSourceBytes)
		setText(text, #text + 1)
	end

	lastText = text
	sources[slot] = text
	view.highlightLine(nil, "run")
	refreshLineInfo()
	scheduleAutosave()
end

local function onTab()
	local editor = view.editor
	local cursor = editor.CursorPosition
	if cursor < 1 then
		return
	end
	local text = editor.Text
	setText(string.sub(text, 1, cursor - 1) .. "    " .. string.sub(text, cursor), cursor + 4)
	sources[slot] = view.editor.Text
	refreshLineInfo()
	scheduleAutosave()
end

local function showSlot(newSlot: number)
	slot = newSlot
	setText(sources[newSlot] or "")
	view.setSlots(names, newSlot)
	view.highlightLine(nil, "run")
	refreshLineInfo()
end

local function switchSlot(newSlot: number)
	if not loaded then
		return
	end
	local previous = slot
	sources[previous] = view.editor.Text
	showSlot(newSlot)
	task.spawn(saveSlot, previous) -- save the slot we left (only if it changed)
end

local function rename(targetSlot: number, name: string)
	local ok, reason = ScriptNames.validate(name, names, targetSlot)
	if not ok then
		NotifyController.show("warning", tostring(reason))
		return
	end
	local invoked, response = Net.invoke("RenameScript", targetSlot, name)
	if invoked and type(response) == "table" then
		if type(response.names) == "table" then
			names = response.names
			view.setSlots(names, slot)
		end
		if response.ok then
			NotifyController.show(
				"success",
				string.format("Renamed to '%s'. Other scripts can now use: import %s", name, name)
			)
		else
			NotifyController.show("warning", tostring(response.message or "Couldn't rename that script."))
		end
	else
		NotifyController.show("error", "Couldn't reach the server.")
	end
end

local function run()
	local now = os.clock()
	if now - lastRunAt < RUN_COOLDOWN then
		return
	end
	lastRunAt = now

	local source = view.editor.Text
	-- Instant local feedback using the shared parser (the server re-checks everything).
	local program, err = Parser.compile(source, Parser.limits(maxLines()), clientUnlocks())
	if program == nil and err ~= nil then
		view.appendOutput("error", string.format("Line %d: %s", err.line, err.message))
		view.highlightLine(err.line, "error")
		view.shake()
		view.setStatus("Error on line " .. err.line, C.Danger)
		return
	end

	view.setStatus("Uploading...", C.Muted)
	local ok, response = Net.invoke("RunScript", slot, source)
	if not ok then
		view.setStatus("Couldn't reach the server (" .. tostring(response) .. ")", C.Danger)
		return
	end
	savedSources[slot] = source
	if type(response) == "table" and response.ok == false and type(response.error) == "table" then
		local e = response.error
		local prefix = if type(e.line) == "number" and e.line > 0
			then string.format("Line %d: ", e.line)
			else ""
		view.appendOutput("error", prefix .. tostring(e.message))
		view.highlightLine(if type(e.line) == "number" then e.line else nil, "error")
		view.shake()
		view.setStatus("Not started", C.Danger)
	end
end

local function onStatus(status: string, line: number)
	if status == "running" then
		view.setRunning(true)
		view.setStatus("Running", C.Accent)
		view.appendOutput("system", "--- program started ---")
	elseif status == "line" then
		view.highlightLine(if line > 0 then line else nil, "run")
	elseif status == "finished" then
		view.setRunning(false)
		view.highlightLine(nil, "run")
		view.setStatus("Finished", C.Muted)
	elseif status == "stopped" then
		view.setRunning(false)
		view.highlightLine(nil, "run")
		view.setStatus("Stopped", C.Warning)
	elseif status == "error" then
		view.setRunning(false)
		view.highlightLine(if line > 0 then line else nil, "error")
		view.shake()
		view.setStatus(if line > 0 then "Error on line " .. line else "Error", C.Danger)
	end
end

local function loadScripts()
	if player:GetAttribute("DataLoaded") ~= true then
		player:GetAttributeChangedSignal("DataLoaded"):Wait()
	end
	for _ = 1, 3 do
		local ok, result = Net.invoke("GetScripts")
		if ok and type(result) == "table" and type(result.scripts) == "table" then
			for index = 1, GameConfig.Script.Slots do
				local source = result.scripts[index]
				sources[index] = if type(source) == "string" then source else ""
				savedSources[index] = sources[index]
			end
			if type(result.names) == "table" then
				names = result.names
			end
			loaded = true
			showSlot(1)
			view.setStatus("Ready", C.Muted)
			return
		end
		task.wait(6) -- GetScripts is rate limited to one call per 5 s
	end
	view.setStatus("Couldn't load your scripts", C.Danger)
end

function TerminalController:Init()
	view = TerminalView.build()
	view.setStatus("Loading...", C.Muted)
	view.setSlots(names, 1)
	refreshLineInfo()
end

function TerminalController:Start()
	view.editor:GetPropertyChangedSignal("Text"):Connect(onTextChanged)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Tab and view.editor:IsFocused() then
			onTab()
		end
	end)
	view.runButton.Activated:Connect(run)
	view.stopButton.Activated:Connect(function()
		local now = os.clock()
		if now - lastStopAt < 0.5 then
			return -- stay under the server's StopScript rate limit
		end
		lastStopAt = now
		Net.fire("StopScript")
	end)
	view.onSlotSelected = switchSlot
	view.onRename = function(targetSlot: number, name: string)
		task.spawn(rename, targetSlot, name)
	end
	player:GetAttributeChangedSignal("MaxLines"):Connect(refreshLineInfo)
	local function refreshVip()
		view.setVip(player:GetAttribute("Pass_VIP") == true)
	end
	player:GetAttributeChangedSignal("Pass_VIP"):Connect(refreshVip)
	refreshVip()

	Net.on("ScriptStatus", onStatus)
	Net.on("ScriptOutput", function(kind: string, text: string)
		view.appendOutput(kind, text)
	end)

	task.spawn(loadScripts)
end

--[[
	The terminal is only on screen in Control Mode (Controllers.ControlModeController owns
	when). `fadeTime` 0 / nil = instant. Hiding also releases keyboard focus from the editor.
]]
function TerminalController:SetVisible(visible: boolean, fadeTime: number?)
	view.setVisible(visible, fadeTime)
end

function TerminalController:IsVisible(): boolean
	return view.isVisible()
end

-- The terminal panel (the tutorial coach docks on top of it, so it only shows in Control Mode).
function TerminalController:GetRoot(): Frame
	return view.root
end

-- Presses RUN (the tutorial coach's first step).
function TerminalController:Run()
	run()
end

--[[
	Inserts a ready-made snippet so nobody has to type syntax to make progress (tutorial).
	At the caret when the editor has one, otherwise at the very TOP so the new code runs
	first. If that would break the drone's line limit, the snippet replaces this slot's
	program instead (a toast says so; the other slots keep theirs).
]]
function TerminalController:InsertSnippet(snippet: string)
	local text = view.editor.Text
	local cursor = view.editor.CursorPosition
	local block = if string.sub(snippet, -1) == "\n" then snippet else snippet .. "\n"
	local newText, caret
	if cursor < 1 then
		newText = block .. text
		caret = #block + 1
	else
		local before = string.sub(text, 1, cursor - 1)
		if before ~= "" and string.sub(before, -1) ~= "\n" then
			before ..= "\n"
		end
		newText = before .. block .. string.sub(text, cursor)
		caret = #before + #block + 1
	end
	if Text.countLines(newText) > maxLines() then
		newText = block
		caret = #block + 1
		NotifyController.show("info", "That wouldn't fit your drone's memory, so it replaced the program.")
	end
	setText(newText, caret)
	sources[slot] = newText
	view.highlightLine(nil, "run")
	refreshLineInfo()
	scheduleAutosave()
end

return TerminalController
