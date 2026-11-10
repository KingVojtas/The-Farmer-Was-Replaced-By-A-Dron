--!strict
--[[
	HudController
	=============
	The always-on HUD shell (layout spec: docs/UI_UX_GUIDE.md, "Main HUD"):

	  top-left      MENU button + active boost timers
	  top-centre    weather tile + water / cargo meters (each with its icon)
	  top-RIGHT     the currency stack - built by CurrencyHudController inside this ScreenGui
	  bottom-right  dock: TECH TREE, SHOP, HANGAR (icon + label buttons)

	Owns the `DroneHud` ScreenGui and its UIScale (other HUD parts parent into GetGui()).
	Read-only: it only listens to attributes the server publishes
	  Workspace : Weather
	  own plot  : Water, WaterMax, Cargo, CargoMax
	  player    : GrowthBoostUntil, YieldBoostUntil
	Buttons only open panels through UIState.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local IconConfig = require(ReplicatedStorage.Shared.Config.IconConfig)
local Client = script.Parent.Parent
local Components = require(Client.UI.Components)
local PlotSpace = require(Client.Visuals.PlotSpace)
local Icon = require(Client.UI.Icon)
local Theme = require(Client.UI.Theme)
local UIState = require(Client.UI.UIState)

local C = Theme.Colors
local player = Players.LocalPlayer

type Meter = { label: TextLabel, bar: Components.ProgressBar, tile: Icon.TileHandle }

local HudController = {}

local gui: ScreenGui
local uiScale: UIScale
local weatherTile: Icon.TileHandle
local weatherLabel: TextLabel
local meters: { [string]: Meter } = {}
local boostLabel: TextLabel
local ownPlot: Model? = nil
local weatherChip: Frame
local weatherStroke: UIStroke
local readyDot: Frame
local readyCount = 0
local lastReadyPulse = -math.huge
local readyPending = false
local READY_PULSE_GAP = 4 -- seconds: the ready pulse never repeats faster than this

------------------------------------------------------------ weather + drone (top-centre)
local function buildMeter(parent: Instance, name: string, iconKey: string, order: number)
	local holder: Frame = Theme.create("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(132, 32),
		LayoutOrder = order,
		Parent = parent,
	}, {
		Theme.list(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	local tile = Icon.tile(iconKey, 26)
	tile.frame.LayoutOrder = 1
	tile.frame.Parent = holder
	local column: Frame = Theme.create("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(98, 32),
		LayoutOrder = 2,
		Parent = holder,
	})
	local label = Components.label({
		Text = name,
		TextSize = 12,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, 0, 0, 16),
		Parent = column,
	})
	local bar = Components.progressBar({ Position = UDim2.fromOffset(0, 21), Parent = column })
	meters[name] = { label = label, bar = bar, tile = tile }
end

local function buildStatusBar()
	local bar = Components.panel({
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, Theme.Space.M),
		Size = UDim2.fromOffset(440, 44),
		BackgroundTransparency = 0.08,
		Parent = gui,
	})
	Theme.padding(6, Theme.Space.M).Parent = bar
	Theme.list(
		Enum.FillDirection.Horizontal,
		Theme.Space.M,
		{ VerticalAlignment = Enum.VerticalAlignment.Center }
	).Parent =
		bar

	-- The weather chip: tinted with the same palette the world uses (Theme.WeatherColors).
	local weather: Frame = Theme.create("Frame", {
		Name = "Weather",
		BackgroundColor3 = Theme.WeatherColors.Sunny,
		BackgroundTransparency = 0.78,
		Size = UDim2.fromOffset(120, 32),
		LayoutOrder = 1,
		Parent = bar,
	}, {
		Theme.corner(Theme.Radius.S),
		Theme.padding(0, 4),
		Theme.list(Enum.FillDirection.Horizontal, 8, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	weatherChip = weather
	weatherStroke = Theme.stroke(Theme.WeatherColors.Sunny, 1, 0.45)
	weatherStroke.Parent = weather
	weatherTile = Icon.tile("weather_Sunny", 30)
	weatherTile.frame.LayoutOrder = 1
	weatherTile.frame.Parent = weather
	weatherLabel = Components.label({
		Text = "Sunny",
		Font = Theme.UIFontBold,
		TextSize = 14,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		LayoutOrder = 2,
		Parent = weather,
	})

	buildMeter(bar, "Water", "water", 2)
	buildMeter(bar, "Cargo", "cargo", 3)

	-- "Something is ready to harvest": a tiny lime dot on the cargo icon while any tile of
	-- your plot is ready.
	readyDot = Theme.create("Frame", {
		Name = "ReadyDot",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 3, 0, -3),
		Size = UDim2.fromOffset(9, 9),
		BackgroundColor3 = C.Accent,
		Visible = false,
		ZIndex = 5,
		Parent = meters.Cargo.tile.frame,
	}, { Theme.corner(5), Theme.stroke(C.Background, 1.5, 0) })
end

local function refreshWeather()
	-- Your plot's own weather if it publishes one, else the server-wide attribute.
	local text = PlotSpace.weather(ownPlot)
	local tint = Theme.WeatherColors[text] or Theme.WeatherColors.Sunny
	weatherChip.BackgroundColor3 = tint
	weatherStroke.Color = tint
	local key = IconConfig.forWeather(text)
	local color = Theme.rgb(IconConfig.get(key).color)
	weatherTile.setIcon(key)
	weatherTile.setColor(color)
	weatherLabel.Text = text
	weatherLabel.TextColor3 = color
end

local function refreshDrone()
	local plot = ownPlot
	local function attr(name: string): number
		local value = if plot ~= nil then plot:GetAttribute(name) else nil
		return if type(value) == "number" then value else 0
	end
	local colors = { Water = C.Info, Cargo = C.Warning }
	for name, meter in meters do
		local current, max = attr(name), attr(name .. "Max")
		local fraction = if max > 0 then current / max else 0
		meter.label.Text = string.format("%s  %d/%d", name, current, max)
		local color = colors[name]
		if (name == "Cargo" and fraction >= 1) or (name == "Water" and max > 0 and current == 0) then
			color = C.Danger
		end
		meter.bar.set(fraction, color)
	end
end

-- Lime pulse on the cargo meter when MORE tiles become ready (never more often than every
-- READY_PULSE_GAP s); the dot stays while anything is ready. No spam, no world popups.
local function refreshReady()
	readyPending = false
	local plot = ownPlot
	local count = 0
	if plot ~= nil then
		for _, child in plot:GetChildren() do
			if string.sub(child.Name, 1, 5) == "Tile_" and child:GetAttribute("State") == "ready" then
				count += 1
			end
		end
	end
	local grew = count > readyCount
	readyCount = count
	readyDot.Visible = count > 0
	local now = os.clock()
	if grew and now - lastReadyPulse >= READY_PULSE_GAP then
		lastReadyPulse = now
		local tile = meters.Cargo.tile
		local base = tile.stroke.Color
		tile.stroke.Color = C.Accent
		tile.pulse(0.7)
		task.delay(0.5, function()
			tile.stroke.Color = base
		end)
	end
end

-- Many tiles change in one server tick: count once.
local function scheduleReady()
	if not readyPending then
		readyPending = true
		task.defer(refreshReady)
	end
end

local function trackPlot(plot: Instance)
	if not plot:IsA("Model") or plot:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end
	ownPlot = plot
	local function watchTile(child: Instance)
		if string.sub(child.Name, 1, 5) == "Tile_" then
			child:GetAttributeChangedSignal("State"):Connect(scheduleReady)
		end
	end
	for _, child in plot:GetChildren() do
		watchTile(child)
	end
	plot.ChildAdded:Connect(watchTile)
	plot:GetAttributeChangedSignal("Weather"):Connect(refreshWeather)
	refreshWeather()
	scheduleReady()
	for _, name in { "Water", "WaterMax", "Cargo", "CargoMax" } do
		plot:GetAttributeChangedSignal(name):Connect(refreshDrone)
	end
	plot.AncestryChanged:Connect(function()
		if plot.Parent == nil and ownPlot == plot then
			ownPlot = nil
			refreshDrone()
			scheduleReady()
		end
	end)
	refreshDrone()
end

---------------------------------------------------------------- menu + boosts (top-left)
local function buildMenuCorner()
	local corner: Frame = Theme.create("Frame", {
		Name = "MenuCorner",
		Position = UDim2.fromOffset(Theme.Space.M, Theme.Space.M),
		Size = UDim2.fromOffset(300, 34),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Theme.list(
			Enum.FillDirection.Horizontal,
			Theme.Space.S,
			{ VerticalAlignment = Enum.VerticalAlignment.Center }
		),
	})
	local menu =
		Components.ghostButton("MENU", { Size = UDim2.fromOffset(76, 34), LayoutOrder = 1, Parent = corner })
	Components.hover(menu)
	menu.Activated:Connect(function()
		UIState.toggle("MainMenu")
	end)
	boostLabel = Components.label({
		Text = "",
		Font = Theme.UIFontBold,
		TextSize = 13,
		TextColor3 = C.Gold,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		LayoutOrder = 2,
		Parent = corner,
	})
end

local function formatDuration(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function refreshBoosts()
	local now = os.time()
	local parts: { string } = {}
	local growth = player:GetAttribute("GrowthBoostUntil")
	local yield = player:GetAttribute("YieldBoostUntil")
	if type(growth) == "number" and growth > now then
		table.insert(
			parts,
			IconConfig.get("boost_micro").emoji .. " 2x GROWTH " .. formatDuration(growth - now)
		)
	end
	if type(yield) == "number" and yield > now then
		table.insert(parts, IconConfig.get("yield_2x").emoji .. " 1.5x YIELD " .. formatDuration(yield - now))
	end
	boostLabel.Text = table.concat(parts, "   ")
end

---------------------------------------------------------------- dock (bottom-right)
-- A button with an icon and a label, laid out by a centred horizontal UIListLayout.
local function dockButton(
	parent: Instance,
	text: string,
	iconKey: string,
	color: Color3,
	order: number
): TextButton
	local button = Theme.button("", color, {
		Name = text,
		Size = UDim2.fromOffset(if order == 1 then 150 else 122, 48),
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.create("UIGradient", {
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)),
		Rotation = 90,
		Parent = button,
	})
	Theme.list(Enum.FillDirection.Horizontal, 6, {
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}).Parent =
		button
	local icon = Icon.new(iconKey, 24)
	icon.image.LayoutOrder = 1
	icon.image.Parent = button
	Components.label({
		Text = text,
		Font = Theme.UIFontHeavy,
		TextSize = 15,
		TextColor3 = C.Background,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 48),
		LayoutOrder = 2,
		Parent = button,
	})
	Components.hover(button)
	return button
end

local function buildDock()
	local dock: Frame = Theme.create("Frame", {
		Name = "Dock",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -Theme.Space.M, 1, -Theme.Space.M),
		Size = UDim2.fromOffset(0, 48),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Theme.list(Enum.FillDirection.Horizontal, Theme.Space.S) })
	local entries: { { text: string, icon: string, color: Color3, panel: string, tab: string? } } = {
		{ text = "TECH TREE", icon = "tech_tree", color = C.Accent, panel = "TechTree", tab = nil },
		{ text = "SHOP", icon = "shop", color = C.Gold, panel = "Shop", tab = nil },
		{ text = "HANGAR", icon = "hangar", color = C.Info, panel = "Shop", tab = "hangar" },
	}
	for index, entry in entries do
		local button = dockButton(dock, entry.text, entry.icon, entry.color, index)
		button.Activated:Connect(function()
			UIState.toggle(entry.panel, entry.tab)
		end)
	end
end

local function refreshScale()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local viewport = camera.ViewportSize
	uiScale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.65, 1.15)
end

function HudController:Init()
	gui = Theme.create("ScreenGui", {
		Name = "DroneHud",
		ResetOnSpawn = false,
		DisplayOrder = 0,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	})
	uiScale = Theme.create("UIScale", { Parent = gui })
	buildMenuCorner()
	buildStatusBar()
	buildDock()
	gui.Parent = player:WaitForChild("PlayerGui")
end

function HudController:Start()
	refreshScale()
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshScale)
	end

	Workspace:GetAttributeChangedSignal("Weather"):Connect(refreshWeather)
	refreshWeather()

	task.spawn(function()
		while true do
			refreshBoosts()
			task.wait(1)
		end
	end)

	local plots = Workspace:WaitForChild("Plots")
	plots.ChildAdded:Connect(trackPlot)
	for _, plot in plots:GetChildren() do
		trackPlot(plot)
	end
	refreshDrone()
end

-- The HUD ScreenGui (scaled with the viewport); other HUD parts parent into it.
function HudController:GetGui(): ScreenGui
	return gui
end

-- The HUD hides while the main menu is up.
function HudController:SetVisible(visible: boolean)
	if (gui :: ScreenGui?) ~= nil then
		gui.Enabled = visible
	end
end

return HudController
