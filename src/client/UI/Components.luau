--!strict
--[[
	Components
	==========
	Small reusable UI building blocks on top of Theme. Each function returns plain Instances
	(and, where needed, a tiny handle with setter functions). No game logic in here.

	  Components.label(props)                  TextLabel with theme defaults
	  Components.panel(props)                  rounded, stroked, gradient Frame
	  Components.ghostButton(text, props)      outlined secondary button
	  Components.progressBar(props) -> handle  { frame, set(fraction, color?) }
	  Components.badge(text, color)            small ribbon / tag
	  Components.costChip(currencyId, amount, affordable)   [currency icon] amount chip
	  (icons themselves: UI/Icon.luau)
	  Components.modal(parent, title, size) -> handle  { root, body, open(), close(), onClose }
	  Components.hover(button)                 subtle scale feedback on hover/press
]]

local Theme = require(script.Parent.Theme)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local IconConfig = require(ReplicatedStorage.Shared.Config.IconConfig)
local Icon = require(script.Parent.Icon)

local C = Theme.Colors

local Components = {}

function Components.label(props: { [string]: any }): TextLabel
	local base: { [string]: any } = {
		BackgroundTransparency = 1,
		Font = Theme.UIFont,
		TextSize = 14,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 18),
	}
	for key, value in props do
		base[key] = value
	end
	return Theme.create("TextLabel", base)
end

function Components.panel(props: { [string]: any }, children: { any }?): Frame
	local base: { [string]: any } = {
		BackgroundColor3 = C.Panel,
		BorderSizePixel = 0,
	}
	for key, value in props do
		base[key] = value
	end
	local frame: Frame = Theme.create("Frame", base, children)
	Theme.corner(Theme.Radius.M).Parent = frame
	Theme.stroke(C.Border, 1).Parent = frame
	Theme.gradient(Color3.new(1, 1, 1), Color3.fromRGB(200, 205, 215)).Parent = frame
	Theme.skin(frame, "panel")
	return frame
end

function Components.ghostButton(text: string, props: { [string]: any }?): TextButton
	local base: { [string]: any } = {
		Text = text,
		Font = Theme.UIFontBold,
		TextSize = 13,
		TextColor3 = C.Text,
		BackgroundColor3 = C.PanelLight,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(84, 30),
	}
	if props ~= nil then
		for key, value in props do
			base[key] = value
		end
	end
	local button: TextButton =
		Theme.create("TextButton", base, { Theme.corner(Theme.Radius.S), Theme.stroke(C.Border) })
	Theme.skin(button, "button_secondary")
	return button
end

export type ProgressBar = { frame: Frame, set: (fraction: number, color: Color3?) -> () }

function Components.progressBar(props: { [string]: any }): ProgressBar
	local base: { [string]: any } = {
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
	}
	for key, value in props do
		base[key] = value
	end
	local frame: Frame = Theme.create("Frame", base, { Theme.corner(3) })
	Theme.skin(frame, "meter_track")
	local fill: Frame = Theme.create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Parent = frame,
	}, { Theme.corner(3) })
	return {
		frame = frame,
		set = function(fraction: number, color: Color3?)
			local f = math.clamp(if fraction == fraction then fraction else 0, 0, 1)
			Theme.tween(fill, { Size = UDim2.fromScale(f, 1) }, Theme.Motion.Base)
			if color ~= nil then
				fill.BackgroundColor3 = color
			end
		end,
	}
end

function Components.badge(text: string, color: Color3): TextLabel
	return Theme.create("TextLabel", {
		Text = text,
		Font = Theme.UIFontHeavy,
		TextSize = 11,
		TextColor3 = C.Background,
		BackgroundColor3 = color,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 18),
	}, { Theme.corner(9), Theme.padding(0, 8) })
end

-- "[WH] 40" chip; the amount turns red when the player can't afford it.
-- [icon] 40 chip; the amount turns red (and the outline too) when the player can't afford it.
function Components.costChip(currencyId: string, amount: number, affordable: boolean): Frame
	local color = Theme.currencyColor(currencyId)
	local chip: Frame = Theme.create("Frame", {
		BackgroundColor3 = C.Background,
		BackgroundTransparency = 0.2,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
	}, {
		Theme.corner(10),
		Theme.padding(0, 6),
		Theme.stroke(if affordable then color else C.Danger, 1, 0.55),
		Theme.list(Enum.FillDirection.Horizontal, 4, { VerticalAlignment = Enum.VerticalAlignment.Center }),
	})
	local icon = Icon.new(IconConfig.forCurrency(currencyId), 14)
	icon.image.LayoutOrder = 1
	icon.image.Parent = chip
	Components.label({
		Text = tostring(amount),
		Font = Theme.UIFontBold,
		TextSize = 12,
		TextColor3 = if affordable then C.Text else C.Danger,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		LayoutOrder = 2,
		Parent = chip,
	})
	return chip
end

function Components.hover(button: GuiButton)
	local scale: UIScale = Theme.create("UIScale", { Scale = 1, Parent = button })
	button.MouseEnter:Connect(function()
		Theme.tween(scale, { Scale = 1.04 }, Theme.Motion.Fast)
	end)
	button.MouseLeave:Connect(function()
		Theme.tween(scale, { Scale = 1 }, Theme.Motion.Fast)
	end)
	button.MouseButton1Down:Connect(function()
		Theme.tween(scale, { Scale = 0.97 }, Theme.Motion.Fast)
	end)
	button.MouseButton1Up:Connect(function()
		Theme.tween(scale, { Scale = 1.04 }, Theme.Motion.Fast)
	end)
end

export type Modal = {
	root: Frame,
	body: Frame,
	title: TextLabel,
	isOpen: () -> boolean,
	open: () -> (),
	close: () -> (),
	onClose: (() -> ())?,
}

--[[
	A centred panel with a title bar and close button that pops in/out (scale + fade).
	`size` is the panel size; it is clamped for small screens.
]]
function Components.modal(parent: Instance, titleText: string, size: UDim2): Modal
	local root: Frame = Components.panel({
		Name = titleText,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = size,
		BackgroundColor3 = C.Background,
		Visible = false,
		Parent = parent,
	})
	Theme.create(
		"UISizeConstraint",
		{ MinSize = Vector2.new(340, 300), MaxSize = Vector2.new(1180, 780), Parent = root }
	)
	local scale: UIScale = Theme.create("UIScale", { Scale = 1, Parent = root })

	local header: Frame = Theme.create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 48),
		Parent = root,
	}, { Theme.padding(0, Theme.Space.L) })
	Theme.skin(header, "modal_header")
	local title = Components.label({
		Text = titleText,
		Font = Theme.UIFontHeavy,
		TextSize = 20,
		Size = UDim2.fromScale(0.5, 1),
		Parent = header,
	})
	local closeButton = Components.ghostButton("X", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromOffset(34, 30),
		Parent = header,
	})
	Theme.create("Frame", {
		Name = "Divider",
		BackgroundColor3 = C.Border,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 48),
		Size = UDim2.new(1, 0, 0, 1),
		Parent = root,
	})
	local body: Frame = Theme.create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 49),
		Size = UDim2.new(1, 0, 1, -49),
		Parent = root,
	})

	local openState = false
	local modal: Modal
	modal = {
		root = root,
		body = body,
		title = title,
		isOpen = function(): boolean
			return openState
		end,
		-- ANIM-6: opens 0.96 -> 1 (Quad Out, Motion.Base), closes 1 -> 0.98, then hides. Scale
		-- only, no CanvasGroup (it blurs text) and no Fade (cards change their own strokes /
		-- glows while open, and Fade restores captured transparencies). Opening twice, or
		-- closing twice, doesn't restart the tween.
		open = function()
			if openState then
				return
			end
			openState = true
			root.Visible = true
			scale.Scale = 0.96
			Theme.tween(scale, { Scale = 1 }, Theme.Motion.Base, Enum.EasingStyle.Quad)
		end,
		close = function()
			if not openState then
				return
			end
			openState = false
			local tween = Theme.tween(scale, { Scale = 0.98 }, Theme.Motion.Fast, Enum.EasingStyle.Quad)
			tween.Completed:Connect(function()
				if not openState then
					root.Visible = false
					scale.Scale = 1
				end
			end)
			local onClose = modal.onClose
			if onClose ~= nil then
				onClose()
			end
		end,
		onClose = nil,
	}
	closeButton.Activated:Connect(function()
		modal.close()
	end)
	return modal
end

return Components
