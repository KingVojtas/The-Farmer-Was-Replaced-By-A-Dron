--!strict
--[[
	WeatherFxController
	===================
	Makes the weather felt on the plot (docs/ART_BIBLE.md §1.5.1). VISUAL ONLY: the rules,
	durations, auto-watering and growth numbers stay in Server.Services.WeatherService.

	SOURCE: the local plot's "Weather" attribute if it has one, else Workspace "Weather" (the
	same attribute the HUD chip reads today).

	  Sunny    the Bible baseline look (LightingController), no particles
	  Rainy    cooler, denser Atmosphere; rain over YOUR plot only: one emitter on an invisible
	           plate sized to the plot's Zone box; up to 3 splash bursts at once on random tiles
	  Drought  hotter, dustier grade and more haze; procedural crops lean 25 % toward dry
	           straw #C9C27A (artist meshes are skipped); a few dust wisps at ground level
	Look changes tween over 1.5 s (LightingController:SetProfile, PlotRenderer:SetCropTint).
	Weather particles switch off while you are out of Control Mode AND more than 120 studs
	from your plot. All parts here are inert (anchored, no collide / query / touch, no shadow).

	RHYTHM (ANIM-8, visual only):
	  * Rain fades UP over 0.6 s (rate and drop speed follow one 0..1 level) instead of popping
	    to full, and fades down the same way. Splashes stay <= 3. Crop lean is PlotRenderer's
	    wind (ANIM-3); there is no second sway here.
	  * Drought: LightingController:SetBreathe - a slow +-0.02 brightness pulse - only while it
	    is Drought AND the particles are on (Control Mode or within 120 studs). Sunny / Rainy /
	    far away stop it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Client = script.Parent.Parent
local PlotSpace = require(Client.Visuals.PlotSpace)
local ControlModeController = require(script.Parent.ControlModeController)
local LightingController = require(script.Parent.LightingController)
local PlotRenderer = require(script.Parent.PlotRenderer)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)

local CONFIG = {
	ParticleRadius = 120, -- studs from your plot; beyond it (and not in Control Mode) no particles
	CheckInterval = 0.5, -- seconds between weather / distance / plot-size checks
	RainHeight = 28, -- studs above the plot base the rain plate hangs
	RainDensity = 1 / 14, -- drops per second per square stud of plot footprint
	RainRate = NumberRange.new(60, 220), -- clamp for the rate ("modest")
	MaxSplashes = 3, -- splash bursts alive at once
	SplashEvery = 0.3, -- seconds between splash attempts
	SplashLifetime = 0.3,
	DroughtTint = 0.25, -- crop colour lerp toward dry straw
	DustRate = 1.2, -- wisps per second: very few
	RainSpeed = NumberRange.new(42, 48), -- drop speed at full rain
	RainSlowest = 0.7, -- drop speed scale at the very start of the fade-up
}
local RAIN_FADE = TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local DROP_TEXTURE = "rbxasset://textures/smallWhiteCircle.png" -- ships with every client
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

local WeatherFxController = {}

local folder: Folder
local rainPlate: Part
local rain: ParticleEmitter
local dustPlate: Part
local dust: ParticleEmitter
local splashAnchor: Part
local splashAttachment: Attachment
local splash: ParticleEmitter

local weather = "Sunny"
local particlesOn = false
local rainLevel = Instance.new("NumberValue") -- 0..1, tweened: the rain fades up / down
local rainRate = CONFIG.RainRate.Min -- full rate for the plot's footprint (fitPlates)
local rainOn = false
local activeSplashes = 0
local checkClock = 0
local splashClock = 0

local function inertPart(name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 0.2, 1)
	part.Parent = folder
	return part
end

local function sequence(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

local function buildEmitters()
	rainPlate = inertPart("RainPlate")
	rain = Instance.new("ParticleEmitter")
	rain.Name = "Rain"
	rain.Enabled = false
	rain.Texture = DROP_TEXTURE
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Speed = CONFIG.RainSpeed
	rain.SpreadAngle = Vector2.new(3, 3)
	rain.Lifetime = NumberRange.new(0.6, 1.0)
	rain.Size = sequence(0.12, 0.12)
	rain.Squash = sequence(2.6, 2.6) -- tall, thin streaks along the fall direction
	rain.Transparency = sequence(0.45, 0.6)
	rain.Color = ColorSequence.new(Color3.fromRGB(200, 215, 230))
	rain.LightInfluence = 0.6
	rain.LightEmission = 0.1
	rain.Parent = rainPlate

	dustPlate = inertPart("DustPlate")
	dust = Instance.new("ParticleEmitter")
	dust.Name = "DustWisps"
	dust.Enabled = false
	dust.Texture = DUST_TEXTURE
	dust.Rate = CONFIG.DustRate
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Speed = NumberRange.new(1.5, 3)
	dust.SpreadAngle = Vector2.new(80, 80)
	dust.Acceleration = Vector3.new(1.5, 0.15, 0.8) -- a lazy sideways drift, hugging the ground
	dust.Drag = 0.6
	dust.Lifetime = NumberRange.new(3.5, 5)
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.2),
		NumberSequenceKeypoint.new(1, 3.2),
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.82),
		NumberSequenceKeypoint.new(1, 1),
	})
	dust.Color = ColorSequence.new(Color3.fromHex("#C9B48A"))
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-15, 15)
	dust.LightInfluence = 1
	dust.Parent = dustPlate

	-- Splashes: one pooled attachment, bursts only (never Enabled).
	splashAnchor = inertPart("SplashAnchor")
	splashAttachment = Instance.new("Attachment")
	splashAttachment.Name = "Splash"
	splashAttachment.Parent = splashAnchor
	splash = Instance.new("ParticleEmitter")
	splash.Name = "Splash"
	splash.Enabled = false
	splash.Rate = 0
	splash.Texture = DROP_TEXTURE
	splash.EmissionDirection = Enum.NormalId.Top
	splash.Speed = NumberRange.new(4, 6)
	splash.SpreadAngle = Vector2.new(70, 70)
	splash.Acceleration = Vector3.new(0, -35, 0)
	splash.Lifetime = NumberRange.new(CONFIG.SplashLifetime)
	splash.Size = sequence(0.15, 0.08)
	splash.Transparency = sequence(0.15, 0.7)
	splash.Color = ColorSequence.new(Color3.fromRGB(200, 235, 255), Color3.new(1, 1, 1))
	splash.LightEmission = 0.3
	splash.Parent = splashAttachment
end

-- Rate and drop speed follow the rain level (0 = none, 1 = full).
local function applyRain()
	local level = rainLevel.Value
	local speed = CONFIG.RainSlowest + (1 - CONFIG.RainSlowest) * level
	rain.Rate = rainRate * level
	rain.Speed = NumberRange.new(CONFIG.RainSpeed.Min * speed, CONFIG.RainSpeed.Max * speed)
end

-- Rain on / off with a 0.6 s fade (ANIM-8): never pops the emitter to full.
local function setRain(on: boolean)
	if on == rainOn then
		return
	end
	rainOn = on
	if on then
		rainLevel.Value = 0
		applyRain()
		rain.Enabled = true
		TweenService:Create(rainLevel, RAIN_FADE, { Value = 1 }):Play()
		return
	end
	local fade = TweenService:Create(rainLevel, RAIN_FADE, { Value = 0 })
	fade.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed and not rainOn then
			rain.Enabled = false
		end
	end)
	fade:Play()
end

-- Fit the rain plate (high up) and the dust plate (just above the base) to the plot's Zone.
local function fitPlates(zone: BasePart)
	local footprint = Vector3.new(zone.Size.X, 0.2, zone.Size.Z)
	local ground = zone.Position.Y - zone.Size.Y / 2 + GameConfig.Grid.TileHeight + 1.2
	rainPlate.Size = footprint
	rainPlate.CFrame = CFrame.new(zone.Position.X, ground + CONFIG.RainHeight, zone.Position.Z)
	dustPlate.Size = footprint
	dustPlate.CFrame = CFrame.new(zone.Position.X, ground, zone.Position.Z)
	local area = zone.Size.X * zone.Size.Z
	rainRate = math.clamp(area * CONFIG.RainDensity, CONFIG.RainRate.Min, CONFIG.RainRate.Max)
	applyRain()
end

local function setWeather(name: string)
	if name == weather then
		return
	end
	weather = name
	LightingController:SetProfile(name)
	PlotRenderer:SetCropTint(if name == "Drought" then CONFIG.DroughtTint else 0)
end

local function check()
	local plot = PlotSpace.ownPlot()
	setWeather(PlotSpace.weather(plot))
	local zone = if plot ~= nil then PlotSpace.zone(plot) else nil
	local point = PlotSpace.referencePoint()
	local near = plot ~= nil
		and zone ~= nil
		and (
			ControlModeController:IsActive()
			or (point ~= nil and PlotSpace.distanceToPlot(plot, point) <= CONFIG.ParticleRadius)
		)
	particlesOn = near
	if zone ~= nil then
		fitPlates(zone)
	end
	setRain(near and weather == "Rainy")
	dust.Enabled = near and weather == "Drought"
	LightingController:SetBreathe(near and weather == "Drought")
end

-- A splash on a random tile of your plot (rain only, at most MaxSplashes alive).
local function trySplash()
	if not particlesOn or weather ~= "Rainy" or activeSplashes >= CONFIG.MaxSplashes then
		return
	end
	local plot = PlotSpace.ownPlot()
	if plot == nil then
		return
	end
	local tiles = {}
	for _, child in plot:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 5) == "Tile_" then
			table.insert(tiles, child)
		end
	end
	if #tiles == 0 then
		return
	end
	local tile = tiles[math.random(1, #tiles)]
	local x = (math.random() - 0.5) * tile.Size.X * 0.8
	local z = (math.random() - 0.5) * tile.Size.Z * 0.8
	splashAttachment.WorldPosition = tile.Position + Vector3.new(x, tile.Size.Y / 2 + 0.1, z)
	splash:Emit(math.random(3, 4))
	activeSplashes += 1
	task.delay(CONFIG.SplashLifetime, function()
		activeSplashes -= 1
	end)
end

function WeatherFxController:Init()
	folder = Instance.new("Folder")
	folder.Name = "WeatherFx"
	folder.Parent = Workspace
	buildEmitters()
	rainLevel.Changed:Connect(applyRain)
end

function WeatherFxController:Start()
	-- React at once when the weather flips; the periodic check covers plot and distance.
	Workspace:GetAttributeChangedSignal("Weather"):Connect(check)
	check()
	RunService.Heartbeat:Connect(function(dt: number)
		checkClock += dt
		if checkClock >= CONFIG.CheckInterval then
			checkClock = 0
			check()
		end
		splashClock += dt
		if splashClock >= CONFIG.SplashEvery then
			splashClock = 0
			trySplash()
		end
	end)
end

return WeatherFxController
