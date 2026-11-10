--!strict
--[[
	Theme
	=====
	Design tokens and a tiny Instance builder for the code-built UI (no binary .rbxm files).
	docs/UI_UX_GUIDE.md describes how these tokens are meant to be used.

	  Theme.Colors     palette (dark "mission control" base, lime = action, cyan = info/premium,
	                   gold = VIP / featured)
	  Theme.Space      spacing scale in px (4 / 8 / 12 / 16 / 24)
	  Theme.Radius     corner radii
	  Theme.Motion     tween durations (s) - keep UI motion short and calm
	  Theme.*Font      typography: Builder Sans for UI, Roboto Mono for code
	  Theme.currencyColor(id) / Theme.rgb({r, g, b})
	  Theme.create / corner / stroke / padding / gradient / button / tween
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Currencies = require(ReplicatedStorage.Shared.Config.Currencies)

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(11, 15, 21),
	Panel = Color3.fromRGB(19, 25, 33),
	PanelLight = Color3.fromRGB(30, 38, 49),
	Raised = Color3.fromRGB(40, 50, 64),
	Border = Color3.fromRGB(48, 60, 76),
	BorderBright = Color3.fromRGB(78, 94, 116),
	Text = Color3.fromRGB(222, 230, 242),
	Muted = Color3.fromRGB(128, 142, 162),
	Faint = Color3.fromRGB(78, 90, 108),
	Accent = Color3.fromRGB(127, 217, 98),
	AccentDark = Color3.fromRGB(52, 98, 44),
	Info = Color3.fromRGB(102, 204, 255),
	Premium = Color3.fromRGB(102, 204, 255),
	Gold = Color3.fromRGB(255, 214, 102),
	Danger = Color3.fromRGB(255, 107, 107),
	Warning = Color3.fromRGB(255, 196, 87),
	Overlay = Color3.fromRGB(4, 6, 10),
	RunLine = Color3.fromRGB(40, 60, 32),
	ErrorLine = Color3.fromRGB(70, 28, 30),
	Botany = Color3.fromRGB(127, 217, 98),
	System = Color3.fromRGB(102, 204, 255),
	Logic = Color3.fromRGB(196, 140, 255),
	Root = Color3.fromRGB(255, 214, 102),
}

Theme.Space = { XS = 4, S = 8, M = 12, L = 16, XL = 24 }
Theme.Radius = { S = 6, M = 10, L = 14 }
Theme.Motion = { Fast = 0.12, Base = 0.2, Slow = 0.35 }

-- ONE weather palette for the world and the HUD: LightingController tints the sky / atmosphere
-- with these, and the HUD weather chip uses the same colours (sunny warm, rain cool, drought
-- dust), so the chip always matches what the plot looks like.
Theme.WeatherColors = {
	Sunny = Color3.fromHex("#FFF1DC"), -- the warm sun tint (Lighting.ColorShift_Top)
	Rainy = Color3.fromHex("#B8C6D3"), -- the cool rain atmosphere
	Drought = Color3.fromHex("#D6CDBE"), -- the dusty drought haze
} :: { [string]: Color3 }

Theme.CodeFont = Enum.Font.RobotoMono
Theme.UIFont = Enum.Font.BuilderSansMedium
Theme.UIFontBold = Enum.Font.BuilderSansBold
Theme.UIFontHeavy = Enum.Font.BuilderSansExtraBold
Theme.BodyFont = Enum.Font.BuilderSans

function Theme.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function Theme.currencyColor(id: string): Color3
	local currency = Currencies.ById[id]
	return if currency ~= nil then Theme.rgb(currency.color) else Theme.Colors.Text
end

function Theme.branchColor(branch: string): Color3
	return (Theme.Colors :: any)[branch] or Theme.Colors.Text
end

-- Theme.create("Frame", { Size = ..., Parent = ... }, { child1, child2 })
-- Properties are applied before children; Parent is applied last.
function Theme.create(className: string, props: { [string]: any }, children: { any }?): any
	local instance: any = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if children ~= nil then
		for _, child in children do
			child.Parent = instance
		end
	end
	if props.Parent ~= nil then
		instance.Parent = props.Parent
	end
	return instance
end

function Theme.corner(radius: number): any
	return Theme.create("UICorner", { CornerRadius = UDim.new(0, radius) })
end

function Theme.stroke(color: Color3, thickness: number?, transparency: number?): any
	return Theme.create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Theme.padding(px: number, horizontal: number?): any
	local h = horizontal or px
	return Theme.create("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

-- Subtle top-to-bottom sheen used on panels and cards.
function Theme.gradient(top: Color3, bottom: Color3): any
	return Theme.create("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
	})
end

function Theme.list(direction: Enum.FillDirection, gap: number, props: { [string]: any }?): any
	local base: { [string]: any } = {
		FillDirection = direction,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, gap),
	}
	if props ~= nil then
		for key, value in props do
			base[key] = value
		end
	end
	return Theme.create("UIListLayout", base)
end

function Theme.tween(
	instance: Instance,
	props: { [string]: any },
	duration: number?,
	style: Enum.EasingStyle?
): Tween
	local tween = TweenService:Create(
		instance,
		TweenInfo.new(duration or Theme.Motion.Base, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		props
	)
	tween:Play()
	return tween
end

function Theme.button(text: string, color: Color3, props: { [string]: any }?): TextButton
	local base: { [string]: any } = {
		Text = text,
		Font = Theme.UIFontBold,
		TextSize = 14,
		TextColor3 = Theme.Colors.Background,
		BackgroundColor3 = color,
		AutoButtonColor = true,
		Size = UDim2.fromOffset(84, 30),
	}
	if props ~= nil then
		for key, value in props do
			base[key] = value
		end
	end
	return Theme.create("TextButton", base, { Theme.corner(Theme.Radius.S) })
end

return Theme
