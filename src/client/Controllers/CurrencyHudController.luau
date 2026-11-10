--!strict
--[[
	CurrencyHudController
	=====================
	Builds and updates the TOP-RIGHT CURRENCY HUD: every tracked resource as an icon
	(ImageLabel) + its amount, plus the drone's battery percentage. Runs inside the client
	LocalScript (ClientMain.client.luau) like every controller; it parents into the DroneHud
	ScreenGui so it shares the HUD's UIScale and hides with it under the main menu.

	LAYOUT (exact hierarchy; also in docs/UI_UX_GUIDE.md)

	  DroneHud (ScreenGui)
	  └── Currencies (Frame)  AnchorPoint (1,0), top-right, 230 px wide, AutomaticSize Y
	      │                   UIListLayout (vertical, 4 px)
	      ├── Energy (Frame row)                        UICorner · UIStroke · UIGradient
	      │   ├── IconTile (Frame) ── Icon (ImageLabel "energy") ── Fallback (TextLabel ⚡)
	      │   ├── Name  (TextLabel "Battery")            UIFlexItem Fill
	      │   ├── Value (TextLabel "86%")
	      │   └── Bar (Frame) ── Fill (Frame + UIGradient)
	      ├── Premium (Frame)                            UIListLayout (horizontal)
	      │   ├── Row_batteries (row, neon cyan UIStroke)  IconTile 💎 · Name · Value
	      │   └── Buy (TextButton "+") ───────────────── opens Shop > Lithium Batteries
	      ├── RawHeader (TextLabel "RAW")
	      ├── Row_hay, Row_wheat, Row_carrot, Row_pumpkin, ...   (one per raw currency)
	      ├── ProcessedHeader (TextLabel "PROCESSED")
	      └── Row_biomass, Row_biofuel

	  Every row = Frame { UICorner, UIStroke (currency colour), UIGradient (tinted -> panel),
	  UIPadding, UIListLayout (horizontal, centred) } with IconTile · Name (UIFlexItem Fill,
	  so the amount always hugs the right edge on any screen) · Value.

	ICONS
	  Icon keys come from Shared.Config.IconConfig (key = currency id). Paste uploaded image
	  ids there (assetId); until then each ImageLabel shows its emoji fallback.

	ANIMATION
	  * Amounts count up/down (NumberValue tween, 0.35 s).
	  * A GAIN pops the icon (UIScale Back-ease pulse, stronger for bigger gains), flashes the
	    tile's glow stroke and the amount, and floats a "+N" label up out of the row.
	  * The battery row turns red and its stroke blinks at 15 % or less; it pulses when the
	    battery is full again.

	DATA (read-only - the server is the authority)
	  player    Cur_<currencyId>, Tech_<nodeId> (which raw currencies are farmable yet)
	  own plot  Battery, BatteryMax
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Currencies = require(ReplicatedStorage.Shared.Config.Currencies)
local IconConfig = require(ReplicatedStorage.Shared.Config.IconConfig)
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Client = script.Parent.Parent
local Components = require(Client.UI.Components)
local Icon = require(Client.UI.Icon)
local Theme = require(Client.UI.Theme)
local UIState = require(Client.UI.UIState)
local HudController = require(script.Parent.HudController)

local C = Theme.Colors
local player = Players.LocalPlayer

local WIDTH = 230
local ROW_HEIGHT = 32
local ICON_SIZE = 24
local LOW_BATTERY = 0.15
local COUNT_TIME = 0.35

type Row = {
	frame: Frame,
	tile: Icon.TileHandle,
	value: TextLabel,
	counter: NumberValue,
	color: Color3,
	known: number?, -- last amount seen (nil until the first update, so joining doesn't "gain")
	padding: UIPadding, -- tweened for the 4 px pop on a gain
}

local CurrencyHudController = {}

local stack: Frame
local rows: { [string]: Row } = {}
local rawHeader: TextLabel
local energy: {
	row: Row,
	fill: Frame,
	stroke: UIStroke,
	lowBlink: Tween?,
	wasFull: boolean,
}
local ownPlot: Model? = nil

------------------------------------------------------------------------------- helpers
-- 1234 -> "1,234"; 123456 -> "123.5K"; 1234567 -> "1.23M"
function CurrencyHudController.formatAmount(n: number): string
	n = math.floor(n)
	if n >= 1e6 then
		return string.format("%.2fM", n / 1e6)
	elseif n >= 1e5 then
		return string.format("%.1fK", n / 1e3)
	end
	local text = string.reverse((string.gsub(string.reverse(tostring(n)), "(%d%d%d)", "%1,")))
	return (string.gsub(text, "^,", ""))
end

local function attributeNumber(instance: Instance?, name: string): number
	local value = if instance ~= nil then instance:GetAttribute(name) else nil
	return if type(value) == "number" then value else 0
end

local function unlockSet(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	for _, id in Tech.NodeIds do
		if player:GetAttribute("Tech_" .. id) == true then
			set[id] = true
		end
	end
	return set
end

------------------------------------------------------------------------------- building
--[[
	One currency row:  [IconTile] Name ............ Value
	The horizontal UIListLayout + UIFlexItem(Fill) on Name keep the icon left and the
	amount right-aligned at every width / UIScale.
]]
local function buildRow(
	parent: Instance,
	name: string,
	label: string,
	iconKey: string,
	order: number,
	glow: boolean?
): Row
	local color = Theme.rgb(IconConfig.get(iconKey).color)
	local frame: Frame = Theme.create("Frame", {
		Name = name,
		BackgroundColor3 = Color3.new(1, 1, 1), -- the UIGradient supplies the colours
		BackgroundTransparency = 0.08,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = order,
		ClipsDescendants = false,
		Parent = parent,
	}, {
		Theme.corner(Theme.Radius.S),
		Theme.stroke(color, if glow then 1.5 else 1, if glow then 0.05 else 0.7),
		-- High-tech fill: a tint of the currency colour on the left fading into the panel colour.
		Theme.create("UIGradient", {
			Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, color:Lerp(C.Panel, 0.72)),
				ColorSequenceKeypoint.new(0.45, C.Panel),
				ColorSequenceKeypoint.new(1, C.Background),
			}),
		}),
		Theme.padding(0, 5),
		Theme.list(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	local padding = frame:FindFirstChildWhichIsA("UIPadding") :: UIPadding

	local tile = Icon.tile(iconKey, ICON_SIZE, { glow = glow })
	tile.frame.LayoutOrder = 1
	tile.frame.Parent = frame

	local nameLabel = Components.label({
		Name = "Name",
		Text = label,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.fromOffset(0, ROW_HEIGHT),
		LayoutOrder = 2,
		Parent = frame,
	})
	Theme.create("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill, Parent = nameLabel })

	local value = Components.label({
		Name = "Value",
		Text = "0",
		Font = Theme.UIFontHeavy,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Right,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, ROW_HEIGHT),
		LayoutOrder = 3,
		Parent = frame,
	})

	local counter: NumberValue = Theme.create("NumberValue", { Name = "Counter", Value = 0, Parent = frame })
	counter.Changed:Connect(function(current: number)
		value.Text = CurrencyHudController.formatAmount(current)
	end)

	return {
		frame = frame,
		tile = tile,
		value = value,
		counter = counter,
		color = color,
		known = nil,
		padding = padding,
	}
end

local function sectionHeader(parent: Instance, text: string, order: number): TextLabel
	return Components.label({
		Name = text .. "Header",
		Text = text,
		Font = Theme.UIFontHeavy,
		TextSize = 11,
		TextColor3 = C.Faint,
		Size = UDim2.new(1, 0, 0, 16),
		LayoutOrder = order,
		Parent = parent,
	})
end

local function buildEnergyRow(order: number)
	local row = buildRow(stack, "Energy", "Battery", "energy", order, false)
	row.value.Text = "100%"
	-- An inline mini meter after the percentage - just the 4th item of the row's horizontal
	-- UIListLayout, so it stays aligned at every width. Its fill has a lime -> cyan gradient.
	local track: Frame = Theme.create("Frame", {
		Name = "Bar",
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(46, 6),
		LayoutOrder = 4,
		Parent = row.frame,
	}, { Theme.corner(3), Theme.stroke(C.Border, 1, 0.3) })
	local fill: Frame = Theme.create("Frame", {
		Name = "Fill",
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = track,
	}, {
		Theme.corner(3),
		Theme.create("UIGradient", { Color = ColorSequence.new(C.Accent, C.Info) }),
	})
	local stroke = row.frame:FindFirstChildOfClass("UIStroke") :: UIStroke
	energy = { row = row, fill = fill, stroke = stroke, lowBlink = nil, wasFull = true }
end

local function buildStack()
	local gui = HudController:GetGui()
	stack = Theme.create("Frame", {
		Name = "Currencies",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -Theme.Space.M, 0, Theme.Space.M),
		Size = UDim2.fromOffset(WIDTH, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Parent = gui,
	}, { Theme.list(Enum.FillDirection.Vertical, 4) })

	buildEnergyRow(1)

	-- Premium: the highlighted Lithium Batteries row + the Shop shortcut.
	local premium: Frame = Theme.create("Frame", {
		Name = "Premium",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT + 2),
		LayoutOrder = 2,
		Parent = stack,
	}, {
		Theme.list(Enum.FillDirection.Horizontal, 4, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	for _, currency in Currencies.List do
		if currency.kind == "premium" then
			local row = buildRow(
				premium,
				"Row_" .. currency.id,
				"Lithium",
				IconConfig.forCurrency(currency.id),
				1,
				true
			)
			row.frame.Size = UDim2.new(1, -(ROW_HEIGHT + 6), 0, ROW_HEIGHT + 2)
			rows[currency.id] = row
		end
	end
	local plus = Theme.button("+", C.Premium, {
		Name = "Buy",
		TextSize = 22,
		Size = UDim2.fromOffset(ROW_HEIGHT + 2, ROW_HEIGHT + 2),
		LayoutOrder = 2,
		Parent = premium,
	})
	Theme.stroke(C.Premium, 1.5, 0).Parent = plus
	Components.hover(plus)
	plus.Activated:Connect(function()
		UIState.open("Shop", "batteries")
	end)

	local order = 10
	rawHeader = sectionHeader(stack, "RAW", order)
	for _, currency in Currencies.List do
		if currency.kind == "raw" then
			order += 1
			rows[currency.id] = buildRow(
				stack,
				"Row_" .. currency.id,
				currency.name,
				IconConfig.forCurrency(currency.id),
				order
			)
		end
	end
	order += 1
	sectionHeader(stack, "PROCESSED", order)
	for _, currency in Currencies.List do
		if currency.kind == "processed" then
			order += 1
			rows[currency.id] = buildRow(
				stack,
				"Row_" .. currency.id,
				currency.name,
				IconConfig.forCurrency(currency.id),
				order
			)
		end
	end
end

------------------------------------------------------------------------------ feedback
-- "+12" rising out of the icon and fading away. It is parented to the icon TILE (which has no
-- layout), so the row's UIListLayout never moves it and it scales with the HUD's UIScale.
local function floatGain(row: Row, amount: number)
	local label = Components.label({
		Name = "Gain",
		Text = "+" .. CurrencyHudController.formatAmount(amount),
		Font = Theme.UIFontHeavy,
		TextSize = 15,
		TextColor3 = row.color,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(0, -6, 0.5, 0),
		Size = UDim2.fromOffset(70, 18),
		ZIndex = 5,
		Parent = row.tile.frame,
	})
	local rise =
		TweenService:Create(label, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(0, -6, 0.5, -24),
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
	rise.Completed:Connect(function()
		label:Destroy()
	end)
	rise:Play()
end

local function onGain(row: Row, gained: number, total: number)
	-- Bigger relative gains pop harder (capped), so a +1 is a nudge and a +500 a punch.
	local strength = math.clamp(0.5 + gained / math.max(total, 1) * 2, 0.5, 1.4)
	row.tile.pulse(strength)
	floatGain(row, gained)
	-- The row's content pops 4 px up and settles (extra bottom padding lifts the centred items
	-- by half of it). Only the HUD row moves: nothing floats over the 3D field.
	local up = TweenService:Create(
		row.padding,
		TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ PaddingBottom = UDim.new(0, 8) }
	)
	up.Completed:Connect(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			TweenService:Create(
				row.padding,
				TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ PaddingBottom = UDim.new(0, 0) }
			):Play()
		end
	end)
	up:Play()
	local flash = TweenService:Create(row.value, TweenInfo.new(0.12), { TextColor3 = C.Accent })
	flash.Completed:Connect(function()
		TweenService:Create(row.value, TweenInfo.new(0.4), { TextColor3 = C.Text }):Play()
	end)
	flash:Play()
end

------------------------------------------------------------------------------ refreshing
local function refreshCurrencies()
	local farmable = Tech.farmableCurrencies(unlockSet())
	local anyRaw = false
	for _, currency in Currencies.List do
		local row = rows[currency.id]
		if row ~= nil then
			local amount = attributeNumber(player, "Cur_" .. currency.id)
			if currency.kind == "raw" then
				-- A raw row appears once the crop is farmable (or you already hold some).
				row.frame.Visible = farmable[currency.id] == true or amount > 0
				anyRaw = anyRaw or row.frame.Visible
			end
			local previous = row.known
			row.known = amount
			if previous == nil then
				row.counter.Value = amount -- first value: no animation, no "gain"
			elseif amount ~= previous then
				TweenService:Create(
					row.counter,
					TweenInfo.new(COUNT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Value = amount }
				):Play()
				if amount > previous and row.frame.Visible then
					onGain(row, amount - previous, amount)
				end
			end
		end
	end
	rawHeader.Visible = anyRaw
end

local function refreshEnergy()
	local plot = ownPlot
	local battery = attributeNumber(plot, "Battery")
	local maxBattery = attributeNumber(plot, "BatteryMax")
	local fraction = if maxBattery > 0 then math.clamp(battery / maxBattery, 0, 1) else 0
	local row = energy.row
	row.value.Text = string.format("%d%%", math.floor(fraction * 100 + 0.5))
	TweenService:Create(energy.fill, TweenInfo.new(0.25), { Size = UDim2.fromScale(fraction, 1) }):Play()

	local low = maxBattery > 0 and fraction <= LOW_BATTERY
	row.value.TextColor3 = if low then C.Danger else C.Text
	if low and energy.lowBlink == nil then
		-- Blink the outline red until the battery recovers.
		energy.stroke.Color = C.Danger
		local blink = TweenService:Create(
			energy.stroke,
			TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0 }
		)
		energy.lowBlink = blink
		blink:Play()
	elseif not low and (energy.lowBlink :: Tween?) ~= nil then
		(energy.lowBlink :: any):Cancel()
		energy.lowBlink = nil
		energy.stroke.Color = row.color
		energy.stroke.Transparency = 0.7
	end

	-- Celebrate a full recharge.
	local full = maxBattery > 0 and fraction >= 1
	if full and not energy.wasFull then
		row.tile.pulse(1)
	end
	energy.wasFull = full
end

local function trackPlot(plot: Instance)
	if not plot:IsA("Model") or plot:GetAttribute("OwnerUserId") ~= player.UserId then
		return
	end
	ownPlot = plot
	plot:GetAttributeChangedSignal("Battery"):Connect(refreshEnergy)
	plot:GetAttributeChangedSignal("BatteryMax"):Connect(refreshEnergy)
	plot.AncestryChanged:Connect(function()
		if plot.Parent == nil and ownPlot == plot then
			ownPlot = nil
			refreshEnergy()
		end
	end)
	refreshEnergy()
end

----------------------------------------------------------------------------- lifecycle
function CurrencyHudController:Init()
	buildStack()
end

function CurrencyHudController:Start()
	for _, currency in Currencies.List do
		player:GetAttributeChangedSignal("Cur_" .. currency.id):Connect(refreshCurrencies)
	end
	for _, id in Tech.NodeIds do
		player:GetAttributeChangedSignal("Tech_" .. id):Connect(refreshCurrencies)
	end
	refreshCurrencies()
	refreshEnergy()

	local plots = Workspace:WaitForChild("Plots")
	plots.ChildAdded:Connect(trackPlot)
	for _, plot in plots:GetChildren() do
		trackPlot(plot)
	end
end

return CurrencyHudController
