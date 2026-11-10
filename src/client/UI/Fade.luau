--!strict
--[[
	Fade
	====
	Fades a whole piece of UI in or out by tweening the transparency of every descendant -
	without a CanvasGroup, so text and TextBoxes stay perfectly crisp (CanvasGroups render to a
	texture and can blur text, which matters for the code editor).

	  Fade.show(root, duration?)   root = a ScreenGui (uses Enabled) or a GuiObject (uses Visible)
	  Fade.hide(root, duration?)   duration 0 / nil = instant
	  Fade.isShown(root) -> boolean

	HOW IT STAYS CORRECT
	  * The "resting" transparency of every object is whatever the UI code set. It is captured
	    the first time an object takes part in a fade and is only ever changed DURING a fade.
	  * show: enable root -> set every captured property to 1 -> tween back to the captured value.
	  * hide: tween every property to 1 -> disable root -> put the captured values back
	    (invisible, so it's free) - an instant show later is then simply "enable".
	  * Objects created while hidden (e.g. new terminal output lines) are captured on the next
	    show, so nothing pops in at full opacity.
	  * A new show/hide on the same root cancels the running one; calling show on a root that is
	    already shown (and not fading) does nothing.
]]

local TweenService = game:GetService("TweenService")

type Values = { [string]: number }

local Fade = {}

-- Captured resting transparencies, weak so destroyed UI is garbage-collected.
local resting: { [Instance]: Values } = setmetatable({}, { __mode = "k" }) :: any
-- Per root: current tweens, a generation counter (to ignore stale completions), and the state.
local tweensByRoot: { [Instance]: { Tween } } = setmetatable({}, { __mode = "k" }) :: any
local generationByRoot: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any
local shownByRoot: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function transparencyProperties(object: Instance): { string }
	if object:IsA("UIStroke") then
		return { "Transparency" }
	end
	if not object:IsA("GuiObject") then
		return {}
	end
	local props = { "BackgroundTransparency" }
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
		table.insert(props, "TextTransparency")
		table.insert(props, "TextStrokeTransparency")
	end
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then
		table.insert(props, "ImageTransparency")
	end
	if object:IsA("ScrollingFrame") then
		table.insert(props, "ScrollBarImageTransparency")
	end
	return props
end

local function capture(object: Instance): Values
	local values = resting[object]
	if values == nil then
		values = {}
		for _, prop in transparencyProperties(object) do
			values[prop] = (object :: any)[prop]
		end
		resting[object] = values
	end
	return values
end

-- The root itself (if it is a GuiObject) plus everything under it.
local function members(root: Instance): { Instance }
	local list = root:GetDescendants()
	if root:IsA("GuiObject") then
		table.insert(list, root)
	end
	return list
end

local function setRootShown(root: Instance, shown: boolean)
	if root:IsA("LayerCollector") then
		root.Enabled = shown
	elseif root:IsA("GuiObject") then
		root.Visible = shown
	end
end

local function rootIsShown(root: Instance): boolean
	if root:IsA("LayerCollector") then
		return root.Enabled
	elseif root:IsA("GuiObject") then
		return root.Visible
	end
	return false
end

local function cancel(root: Instance): number
	local tweens = tweensByRoot[root]
	if tweens ~= nil then
		for _, tween in tweens do
			tween:Cancel()
		end
	end
	tweensByRoot[root] = {}
	local generation = (generationByRoot[root] or 0) + 1
	generationByRoot[root] = generation
	return generation
end

local function restoreResting(root: Instance)
	for _, object in members(root) do
		local values = resting[object]
		if values ~= nil then
			for prop, value in values do
				(object :: any)[prop] = value
			end
		end
	end
end

--[[
	Records an object's RESTING transparency for `prop` before the UI animates it (e.g. a new
	output line fading in from 1 to 0): a show / hide that starts mid-animation then fades
	toward the real resting value instead of capturing the in-between one.
]]
function Fade.setResting(object: Instance, prop: string, value: number)
	local values = capture(object)
	values[prop] = value
end

function Fade.isShown(root: Instance): boolean
	local shown = shownByRoot[root]
	if shown == nil then
		return rootIsShown(root)
	end
	return shown
end

function Fade.show(root: Instance, duration: number?)
	local time = duration or 0
	if Fade.isShown(root) and #(tweensByRoot[root] or {}) == 0 and rootIsShown(root) then
		return -- already fully shown
	end
	local generation = cancel(root)
	shownByRoot[root] = true
	if time <= 0 then
		restoreResting(root)
		setRootShown(root, true)
		return
	end

	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweens: { Tween } = {}
	for _, object in members(root) do
		local values = capture(object)
		local goal: { [string]: number } = {}
		local any = false
		for prop, value in values do
			if value < 1 then
				(object :: any)[prop] = 1
				goal[prop] = value
				any = true
			end
		end
		if any then
			table.insert(tweens, TweenService:Create(object, info, goal))
		end
	end
	setRootShown(root, true)
	tweensByRoot[root] = tweens
	for _, tween in tweens do
		tween:Play()
	end
	task.delay(time, function()
		if generationByRoot[root] == generation then
			tweensByRoot[root] = {} -- finished; a newer show/hide keeps its own list
		end
	end)
end

function Fade.hide(root: Instance, duration: number?)
	local time = duration or 0
	if not Fade.isShown(root) and #(tweensByRoot[root] or {}) == 0 then
		setRootShown(root, false)
		return -- already hidden
	end
	local generation = cancel(root)
	shownByRoot[root] = false
	if time <= 0 or not rootIsShown(root) then
		setRootShown(root, false)
		restoreResting(root)
		return
	end

	local info = TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local tweens: { Tween } = {}
	for _, object in members(root) do
		local values = capture(object)
		local goal: { [string]: number } = {}
		local any = false
		for prop, value in values do
			if value < 1 then
				goal[prop] = 1
				any = true
			end
		end
		if any then
			table.insert(tweens, TweenService:Create(object, info, goal))
		end
	end
	tweensByRoot[root] = tweens
	for _, tween in tweens do
		tween:Play()
	end
	task.delay(time, function()
		if generationByRoot[root] ~= generation then
			return -- a newer show/hide took over
		end
		tweensByRoot[root] = {}
		setRootShown(root, false)
		restoreResting(root)
	end)
end

return Fade
