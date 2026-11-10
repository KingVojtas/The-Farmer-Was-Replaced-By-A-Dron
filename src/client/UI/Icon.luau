--!strict
--[[
	Icon
	====
	The one way the UI draws icons (keys come from Shared.Config.IconConfig).

	  Icon.new(key, size)          -> IconHandle   an ImageLabel (+ emoji fallback + overlay)
	  Icon.tile(key, size, opts?)  -> TileHandle   the icon on a rounded, gradient, glowing tile
	  Icon.robux(size, color?)     -> ImageLabel   Roblox's official Robux icon (built-in image)

	FALLBACK: while an icon's assetId is 0 - or if an uploaded image hasn't loaded after
	LOAD_TIMEOUT seconds - the ImageLabel shows its emoji instead (a TextLabel inside it), so
	the UI is fully illustrated before any art is uploaded. Paste real ids into IconConfig and
	the images replace the emoji automatically.

	ATLAS: generated icons live in ONE texture (art/IconAtlas.png, id in IconAtlas.luau). A key
	with a cell there gets the atlas as its Image plus ImageRectOffset / ImageRectSize for its
	128 px cell; keys without art (or atlas id 0 = not uploaded) keep the emoji.

	PULSE: handle.pulse(strength) pops the icon (UIScale tween, Back easing) - used when a
	currency goes up. Tiles also flash their glow stroke.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local IconConfig = require(ReplicatedStorage.Shared.Config.IconConfig)
local Theme = require(script.Parent.Theme)

local LOAD_TIMEOUT = 5 -- seconds before a non-loading image falls back to its emoji

export type IconHandle = {
	image: ImageLabel,
	fallback: TextLabel,
	overlay: TextLabel,
	scale: UIScale,
	setIcon: (key: string) -> (),
	pulse: (strength: number?) -> (),
}

export type TileHandle = {
	frame: Frame,
	icon: IconHandle,
	stroke: UIStroke,
	setIcon: (key: string) -> (),
	setColor: (color: Color3) -> (),
	pulse: (strength: number?) -> (),
}

export type TileOptions = {
	glow: boolean?, -- neon outline (premium items)
	color: Color3?, -- override the icon's own colour
	iconScale: number?, -- icon size relative to the tile (default 0.68)
}

local Icon = {}

function Icon.new(key: string, size: number): IconHandle
	local image: ImageLabel = Theme.create("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ScaleType = Enum.ScaleType.Fit,
		Image = "",
	})
	local scale: UIScale = Theme.create("UIScale", { Scale = 1, Parent = image })
	local fallback: TextLabel = Theme.create("TextLabel", {
		Name = "Fallback",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Font = Theme.UIFontBold,
		TextScaled = true,
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		Parent = image,
	})
	local overlay: TextLabel = Theme.create("TextLabel", {
		Name = "Overlay",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1.08, 1.08),
		Size = UDim2.fromScale(0.62, 0.42),
		Font = Theme.UIFontHeavy,
		TextScaled = true,
		TextColor3 = Color3.new(1, 1, 1),
		TextStrokeTransparency = 0.2,
		Text = "",
		Visible = false,
		ZIndex = 3,
		Parent = image,
	})

	local loadVersion = 0
	local handle: IconHandle
	handle = {
		image = image,
		fallback = fallback,
		overlay = overlay,
		scale = scale,

		setIcon = function(newKey: string)
			local def = IconConfig.get(newKey)
			local assetImage = IconConfig.image(newKey)
			image.Image = assetImage
			-- ATLAS: a key without its own upload is cropped out of the one shared atlas
			-- texture (IconConfig.atlasRect); everything else shows the whole image.
			local rect = if def.assetId > 0 then nil else IconConfig.atlasRect(newKey)
			if rect ~= nil then
				image.ImageRectOffset = Vector2.new(rect.x, rect.y)
				image.ImageRectSize = Vector2.new(rect.size, rect.size)
			else
				image.ImageRectOffset = Vector2.zero
				image.ImageRectSize = Vector2.zero
			end
			fallback.Text = def.emoji
			fallback.Visible = assetImage == ""
			overlay.Text = def.overlay or ""
			overlay.Visible = def.overlay ~= nil
			loadVersion += 1
			if assetImage ~= "" then
				-- Uploaded art that never arrives (wrong id, moderation, offline Studio) shows the emoji.
				local version = loadVersion
				task.delay(LOAD_TIMEOUT, function()
					if loadVersion == version and image.Parent ~= nil and not image.IsLoaded then
						fallback.Visible = true
					end
				end)
			end
		end,

		pulse = function(strength: number?)
			local s = strength or 1
			local up = TweenService:Create(
				scale,
				TweenInfo.new(0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 + 0.35 * s }
			)
			up.Completed:Connect(function()
				TweenService
					:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
						Scale = 1,
					})
					:Play()
			end)
			up:Play()
		end,
	}
	handle.setIcon(key)
	return handle
end

--[[
	An icon on a rounded tile: tinted background with a top-down UIGradient sheen and a
	UIStroke outline in the icon's colour (bright neon when opts.glow = true).
]]
function Icon.tile(key: string, size: number, opts: TileOptions?): TileHandle
	local options: TileOptions = opts or {}
	local def = IconConfig.get(key)
	local color = options.color or Theme.rgb(def.color)
	local frame: Frame = Theme.create("Frame", {
		Name = "IconTile",
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.72,
	}, {
		Theme.corner(math.max(4, math.floor(size / 3.6))),
		Theme.create("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(120, 120, 120)),
			Rotation = 90,
		}),
	})
	local stroke: UIStroke =
		Theme.stroke(color, if options.glow then 2 else 1, if options.glow then 0 else 0.45)
	stroke.Parent = frame
	local icon = Icon.new(key, math.floor(size * (options.iconScale or 0.68)))
	icon.image.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.image.Position = UDim2.fromScale(0.5, 0.5)
	icon.image.Parent = frame

	local baseTransparency = stroke.Transparency
	local tile: TileHandle
	tile = {
		frame = frame,
		icon = icon,
		stroke = stroke,
		setIcon = function(newKey: string)
			icon.setIcon(newKey)
		end,
		setColor = function(newColor: Color3)
			frame.BackgroundColor3 = newColor
			stroke.Color = newColor
		end,
		pulse = function(strength: number?)
			icon.pulse(strength)
			-- Flash the outline: fully opaque and thicker, then back.
			stroke.Transparency = 0
			stroke.Thickness = 3
			TweenService
				:Create(stroke, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = baseTransparency,
					Thickness = if options.glow then 2 else 1,
				})
				:Play()
		end,
	}
	return tile
end

-- Roblox's official Robux icon (ships with the client). White by default; tint with `color`.
function Icon.robux(size: number, color: Color3?): ImageLabel
	return Theme.create("ImageLabel", {
		Name = "RobuxIcon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		ScaleType = Enum.ScaleType.Fit,
		Image = IconConfig.ROBUX_IMAGE,
		ImageColor3 = color or Color3.new(1, 1, 1),
	})
end

return Icon
