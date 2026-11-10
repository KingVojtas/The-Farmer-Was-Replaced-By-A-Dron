--!strict
--[[
	LightingController
	==================
	Applies the Art Bible look (docs/ART_BIBLE.md §1.5, colours §1.4) on every client, so each
	playtest gets it instead of a one-off Studio click:
	  * Lighting values, Atmosphere, BloomEffect, SunRaysEffect, ColorCorrectionEffect (an
	    existing instance of each class in Lighting is adopted, otherwise one is created);
	  * DepthOfField disabled during play (the main menu has its own tweened BlurEffect,
	    "MenuBlur", which this controller never touches);
	  * a cheap ring of distant hills (#6E8A66, non-colliding, no shadows).
	Lighting.Technology = Future can't be set by scripts: it is set in default.project.json.
	Post effects only touch the 3D view, never ScreenGuis, so the HUD hues stay exact
	(lime = growth, cyan = tech, gold = featured; UI/Theme).

	LOOKS (profiles): Sunny is the Bible baseline. Rainy / Drought are small overrides on top
	of it; WeatherFxController calls SetProfile(name) and the change tweens over 1.5 s.

	BREATHE (ANIM-8): SetBreathe(true) slowly pulses the brightness +-0.02 (4 s Sine InOut,
	reversing) on a SECOND, otherwise neutral ColorCorrectionEffect ("WeatherBreathe"); post
	effects stack, so it never fights the profile tweens on the Bible one. SetBreathe(false)
	eases it back to 0 over the 1.5 s look transition.
]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Theme = require(script.Parent.Parent.UI.Theme)

local GRID = GameConfig.Grid
local TRANSITION = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

type Section = { [string]: any }
type Profile = {
	lighting: Section,
	atmosphere: Section,
	bloom: Section,
	sunRays: Section,
	colorCorrection: Section,
}

-- docs/ART_BIBLE.md §1.5, value for value.
local SUNNY: Profile = {
	lighting = {
		ClockTime = 14.5,
		GeographicLatitude = 35,
		Brightness = 2.4,
		ExposureCompensation = 0.1,
		Ambient = hex("#2A3240"),
		OutdoorAmbient = hex("#8E9AA6"),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.8,
		ShadowSoftness = 0.25,
		ColorShift_Top = Theme.WeatherColors.Sunny, -- #FFF1DC (shared with the HUD weather chip)
	},
	atmosphere = {
		Density = 0.28,
		Offset = 0.2,
		Color = hex("#C8D9E8"),
		Decay = hex("#7A8B9C"),
		Glare = 0.15,
		Haze = 1.0,
	},
	bloom = { Intensity = 0.8, Size = 22, Threshold = 1.4 }, -- only Neon / emissive crosses 1.4
	sunRays = { Intensity = 0.06, Spread = 0.6 },
	colorCorrection = { Brightness = 0.02, Contrast = 0.12, Saturation = 0.08, TintColor = hex("#FFF8EE") },
}

-- Weather overrides, merged onto SUNNY (only the listed values change).
local OVERRIDES: { [string]: { [string]: Section } } = {
	Rainy = {
		atmosphere = { Density = 0.34, Color = Theme.WeatherColors.Rainy }, -- +0.06, cooler grey #B8C6D3
	},
	Drought = {
		lighting = { ColorShift_Top = hex("#FFE6C4") }, -- a hotter sun
		atmosphere = { Haze = 1.6, Color = Theme.WeatherColors.Drought }, -- dusty haze #D6CDBE
		colorCorrection = { Saturation = 0.03, TintColor = hex("#FFEBD2") }, -- -0.05, toward dust
	},
}

local LightingController = {}

local atmosphere: Atmosphere
local bloom: BloomEffect
local sunRays: SunRaysEffect
local colorCorrection: ColorCorrectionEffect
local currentProfile = "Sunny"
local breathe: ColorCorrectionEffect -- neutral except a slow brightness pulse (ANIM-8)
local breatheTween: Tween? = nil
local breathing = false
local BREATHE_AMPLITUDE = 0.02
local BREATHE_LOOP = TweenInfo.new(4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local BREATHE_INTO = TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

local function adopt(className: string, name: string): Instance
	local existing = Lighting:FindFirstChildWhichIsA(className)
	if existing ~= nil then
		return existing
	end
	local created = Instance.new(className :: any)
	created.Name = name
	created.Parent = Lighting
	return created
end

local function merged(name: string): Profile
	local result: Profile = {
		lighting = table.clone(SUNNY.lighting),
		atmosphere = table.clone(SUNNY.atmosphere),
		bloom = table.clone(SUNNY.bloom),
		sunRays = table.clone(SUNNY.sunRays),
		colorCorrection = table.clone(SUNNY.colorCorrection),
	}
	local override = OVERRIDES[name]
	if override ~= nil then
		for section, values in override do
			local target = (result :: any)[section] :: Section
			for key, value in values do
				target[key] = value
			end
		end
	end
	return result
end

local function set(instance: Instance, values: Section, info: TweenInfo?)
	if info == nil then
		for key, value in values do
			(instance :: any)[key] = value
		end
	else
		TweenService:Create(instance, info, values):Play()
	end
end

local function apply(profile: Profile, info: TweenInfo?)
	set(Lighting, profile.lighting, info)
	set(atmosphere, profile.atmosphere, info)
	set(bloom, profile.bloom, info)
	set(sunRays, profile.sunRays, info)
	set(colorCorrection, profile.colorCorrection, info)
end

-- DepthOfField stays off in play (also if one is added later, e.g. by a plugin or an artist).
local function disableDepthOfField(instance: Instance)
	if instance:IsA("DepthOfFieldEffect") then
		instance.Enabled = false
	end
end

-- A ring of soft, distant hills around the whole plot field: 14 stretched spheres, fixed seed
-- (everyone sees the same skyline), inert and shadowless. The Atmosphere hazes them into the sky.
local HILL_COLOR = hex("#6E8A66")
local HILL_COUNT = 14

local function buildBackdrop()
	local folder = Instance.new("Folder")
	folder.Name = "Backdrop"
	local rows = math.max(1, math.ceil(Players.MaxPlayers / GRID.PlotsPerRow))
	local center = Vector3.new(0, 0, GRID.PlotRowOffset + (rows - 1) * GRID.PlotSpacing / 2)
	local fieldRadius = math.max(GRID.PlotsPerRow, rows) * GRID.PlotSpacing / 2
	local radius = math.max(520, fieldRadius + 380)
	local random = Random.new(7)
	local far = SUNNY.atmosphere.Color :: Color3
	for index = 1, HILL_COUNT do
		local angle = (index / HILL_COUNT) * 2 * math.pi + random:NextNumber(-0.12, 0.12)
		local distance = radius + random:NextNumber(-60, 140)
		local width = random:NextNumber(260, 430)
		local height = random:NextNumber(70, 150)
		local hill = Instance.new("Part")
		hill.Name = "Hill" .. index
		hill.Anchored = true
		hill.CanCollide = false
		hill.CanQuery = false
		hill.CanTouch = false
		hill.CastShadow = false
		hill.Locked = true
		hill.Material = Enum.Material.SmoothPlastic
		-- Farther hills lean a little toward the sky colour (aerial perspective).
		hill.Color = HILL_COLOR:Lerp(far, math.clamp((distance - radius) / 400, 0, 0.25))
		hill.Size = Vector3.new(width, height * 2, width * random:NextNumber(0.55, 0.8))
		local position = center
			+ Vector3.new(math.cos(angle) * distance, -height * 0.2, math.sin(angle) * distance)
		hill.CFrame = CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z))
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere -- an ellipsoid hump; cheaper than a mesh asset
		mesh.Parent = hill
		hill.Parent = folder
	end
	folder.Parent = Workspace
end

function LightingController:Init()
	atmosphere = adopt("Atmosphere", "BibleAtmosphere") :: Atmosphere
	bloom = adopt("BloomEffect", "BibleBloom") :: BloomEffect
	sunRays = adopt("SunRaysEffect", "BibleSunRays") :: SunRaysEffect
	colorCorrection = adopt("ColorCorrectionEffect", "BibleColorCorrection") :: ColorCorrectionEffect
	-- Created (never adopted): it must stay neutral, whatever a Studio place already has.
	breathe = Instance.new("ColorCorrectionEffect")
	breathe.Name = "WeatherBreathe"
	breathe.Brightness = 0
	breathe.Contrast = 0
	breathe.Saturation = 0
	breathe.TintColor = Color3.new(1, 1, 1)
	breathe.Parent = Lighting
end

function LightingController:Start()
	apply(merged("Sunny"), nil)
	for _, child in Lighting:GetChildren() do
		disableDepthOfField(child)
	end
	Lighting.ChildAdded:Connect(disableDepthOfField)
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		for _, child in camera:GetChildren() do
			disableDepthOfField(child)
		end
	end
	buildBackdrop()
end

-- Tweens to a named look ("Sunny" | "Rainy" | "Drought"; unknown names = Sunny) over 1.5 s.
function LightingController:SetProfile(name: string, duration: number?)
	if name == currentProfile then
		return
	end
	currentProfile = name
	local info = if duration ~= nil
		then TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		else TRANSITION
	apply(merged(name), info)
end

-- ANIM-8: the drought "breathe" (see BREATHE in the header). Idempotent.
function LightingController:SetBreathe(on: boolean)
	if on == breathing then
		return
	end
	breathing = on
	local running = breatheTween
	if running ~= nil then
		running:Cancel()
		breatheTween = nil
	end
	if not on then
		local settle = TweenService:Create(breathe, TRANSITION, { Brightness = 0 })
		breatheTween = settle
		settle:Play()
		return
	end
	-- Ease down to -0.02 first, then loop -0.02 <-> +0.02 (no jump at the start).
	local into = TweenService:Create(breathe, BREATHE_INTO, { Brightness = -BREATHE_AMPLITUDE })
	into.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and breathing then
			local loop = TweenService:Create(breathe, BREATHE_LOOP, { Brightness = BREATHE_AMPLITUDE })
			breatheTween = loop
			loop:Play()
		end
	end)
	breatheTween = into
	into:Play()
end

-- Exposed for the weather layer (e.g. a debug print); never mutate the result.
function LightingController:GetProfile(): string
	return currentProfile
end

return LightingController
