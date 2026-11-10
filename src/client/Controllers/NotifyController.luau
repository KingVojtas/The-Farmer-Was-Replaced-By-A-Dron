--!strict
--[[
	NotifyController
	================
	Toasts: short messages that slide in under the top HUD bar and fade out by themselves.
	At most MAX_VISIBLE at once; older ones are pushed out.

	Sources
	  * Notify remote (server)       - e.g. research completed
	  * PurchaseGranted remote       - a Developer Product was granted AND saved
	  * NotifyController.show(...)   - any client controller (shop errors, cosmetics, ...)

	Display only - a toast never changes game state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local Client = script.Parent.Parent
local Net = require(Client.Net)
local Components = require(Client.UI.Components)
local Fade = require(Client.UI.Fade)
local Theme = require(Client.UI.Theme)

local C = Theme.Colors
local MAX_VISIBLE = 3
local LIFETIME = 3.5
local SLIDE_IN = 16 -- px: a new toast slides in from the right by this much (ANIM-6)

local KIND_COLORS: { [string]: Color3 } = {
	success = C.Accent,
	research = C.Accent,
	purchase = C.Gold,
	info = C.Info,
	warning = C.Warning,
	error = C.Danger,
}

local NotifyController = {}

local stack: Frame
local visible: { Frame } = {}
local order = 0

local function dismiss(toast: Frame)
	local index = table.find(visible, toast)
	if index ~= nil then
		table.remove(visible, index)
	end
	-- The toast is a layout slot; its visible card fades (the slot keeps its place meanwhile).
	local card = toast:FindFirstChild("Card")
	local target: GuiObject = if card ~= nil and card:IsA("GuiObject") then card else toast
	local fade = Theme.tween(target, { BackgroundTransparency = 1 }, Theme.Motion.Slow)
	for _, child in target:GetDescendants() do
		if child:IsA("TextLabel") then
			Theme.tween(child, { TextTransparency = 1 }, Theme.Motion.Slow)
		elseif child:IsA("UIStroke") then
			Theme.tween(child, { Transparency = 1 }, Theme.Motion.Slow)
		end
	end
	fade.Completed:Connect(function()
		toast:Destroy()
	end)
end

function NotifyController.show(kind: string, text: string)
	if (stack :: Frame?) == nil then
		return
	end
	local color = KIND_COLORS[kind] or C.Info
	order += 1
	-- The list layout owns the slot's position, so the CARD inside it is what slides (ANIM-6).
	local toast: Frame = Theme.create("Frame", {
		Name = "Toast",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(360, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = stack,
	})
	local card: Frame = Theme.create("Frame", {
		Name = "Card",
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.05,
		Position = UDim2.fromOffset(SLIDE_IN, 0),
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false, -- Fade.show reveals it
		Parent = toast,
	}, {
		Theme.corner(Theme.Radius.M),
		Theme.stroke(color, 1, 0.3),
		Theme.padding(10, 14),
	})
	Theme.create("Frame", {
		Name = "Accent",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(-14, -10),
		Size = UDim2.new(0, 4, 1, 20),
		Parent = card,
	}, { Theme.corner(2) })
	Components.label({
		Text = text,
		Font = Theme.UIFontBold,
		TextSize = 15,
		TextWrapped = true,
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 0),
		Parent = card,
	})

	table.insert(visible, toast)
	while #visible > MAX_VISIBLE do
		dismiss(visible[1])
	end
	-- Slide in from the right (16 px) while fading in.
	Fade.show(card, Theme.Motion.Base)
	Theme.tween(card, { Position = UDim2.fromOffset(0, 0) }, Theme.Motion.Base, Enum.EasingStyle.Quad)
	task.delay(LIFETIME, function()
		if toast.Parent ~= nil and table.find(visible, toast) ~= nil then
			dismiss(toast)
		end
	end)
end

function NotifyController:Init()
	local gui = Theme.create("ScreenGui", {
		Name = "Toasts",
		ResetOnSpawn = false,
		DisplayOrder = 10,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
	})
	stack = Theme.create("Frame", {
		Name = "Stack",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.fromOffset(360, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	}, {
		Theme.list(Enum.FillDirection.Vertical, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
	})
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function NotifyController:Start()
	Net.on("Notify", function(kind: string, text: string)
		if type(kind) == "string" and type(text) == "string" then
			NotifyController.show(kind, text)
		end
	end)
	Net.on("PurchaseGranted", function(productKey: string)
		local product = MonetizationConfig.Products[productKey]
		local name = if product ~= nil then product.name else "your purchase"
		NotifyController.show("purchase", "Thank you! " .. name .. " has been added to your account.")
	end)
end

return NotifyController
