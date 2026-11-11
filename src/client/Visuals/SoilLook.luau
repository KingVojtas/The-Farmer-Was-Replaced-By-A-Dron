--!strict
--[[
	SoilLook
	========
	The soil-state hook from docs/ART_BIBLE.md §2.2 / §8. PlotRenderer decides WHICH state a
	field tile shows (Shared.Util.SoilStates); this module decides HOW it is drawn.

	EXPECTED MaterialVariants (in MaterialService, any folder; names match the Bible §2.2):
	  name         BaseMaterial  StudsPerTile  MaterialPattern  shown for
	  SoilDry      Ground        8             Organic          bare soil, wild grass
	  SoilTilled   Ground        6.4           Regular          a player crop on the tile
	  SoilWet      Ground        6.4           Regular          Watered == true (authored over
	                                                            the Tilled height: furrows stay)
	  SoilDug      Ground        4             Organic          Exhausted == true (dug up, resting)
	  SoilFertile  Ground        6.4           Regular          reserved; never shown yet

	1. ARTIST VARIANT PRESENT (a MaterialVariant with that name this module didn't create):
	   tile.Material = the variant's BaseMaterial (Ground), tile.MaterialVariant = name, and
	   tile.Color goes to white once and is never tweened again. An Opaque variant ignores
	   Color; a TintMask one then shows its authored albedo untinted. No fighting Color.
	2. NO ARTIST VARIANT: a runtime placeholder MaterialVariant with that name is created, so
	   the hook is exercised before any art lands. Scripts can't set ColorMap / NormalMap /
	   RoughnessMap, so it has no maps: the state reads from Part.Color (the Bible albedo,
	   tweened) and the placeholder's BaseMaterial (Ground; Mud for wet, as the glossy
	   stand-in for roughness). Placeholders keep Ground's physics.
	   An artist variant that replicates in later replaces its placeholder and fires
	   `onChanged`, so every tile re-applies.
	USE_PLACEHOLDERS = false skips step 2: the same states drawn with plain built-in Ground /
	Mud + Color and no MaterialVariant. [verify in Studio] A map-less variant may render
	without the built-in Ground grain; if the placeholders look flatter than you like, flip it.
	Everything here is client-side: the server's tiles stay ordinary Ground Parts.
]]

local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CropConfig = require(ReplicatedStorage.Shared.Config.CropConfig)
local SoilStates = require(ReplicatedStorage.Shared.Util.SoilStates)

-- A SoilStates.SoilState name. Plain string: the old type solver widens singleton unions in tables.
type SoilState = string

local USE_PLACEHOLDERS = true
local PLACEHOLDER_ATTRIBUTE = "SoilLookPlaceholder"
local WHITE = Color3.new(1, 1, 1)
local FADE = TweenInfo.new(0.4)
local FLASH_FADE = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local DUG_COLOR = Color3.fromHex("#6B4A30") -- ART_BIBLE §1.4 Soil Dry dark (clods)

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The built-in stand-in per state (no textures): material + albedo.
local FALLBACK: { [SoilState]: { material: Enum.Material, color: Color3, studs: number, regular: boolean } } =
	{
		SoilDry = {
			material = Enum.Material.Ground,
			color = rgb(CropConfig.SoilColor),
			studs = 8,
			regular = false,
		},
		SoilTilled = {
			material = Enum.Material.Ground,
			color = rgb(CropConfig.TilledSoilColor),
			studs = 6.4,
			regular = true,
		},
		SoilWet = {
			material = Enum.Material.Mud,
			color = rgb(CropConfig.WetSoilColor),
			studs = 6.4,
			regular = true,
		},
		-- Dug up and resting (dig exhaustion): churned clods, Bible "Soil Dry dark" #6B4A30.
		SoilDug = {
			material = Enum.Material.Ground,
			color = DUG_COLOR,
			studs = 4,
			regular = false,
		},
	}

export type Look = {
	variant: string, -- "" = no MaterialVariant
	material: Enum.Material,
	tinted: boolean, -- true: Part.Color carries the state (no artist textures)
	color: Color3,
}

local SoilLook = {}

local looks: { [SoilState]: Look } = {}
local placeholders: { [SoilState]: MaterialVariant } = {}
local colorTweens: { [BasePart]: Tween } = setmetatable({}, { __mode = "k" }) :: any
local onChanged: (() -> ())? = nil
local placeholdersAllowed = true -- false once the engine refuses a client-made MaterialVariant

-- An artist-authored variant with this name (anything in MaterialService we didn't create).
local function findArtistVariant(name: string): MaterialVariant?
	for _, descendant in MaterialService:GetDescendants() do
		if
			descendant:IsA("MaterialVariant")
			and descendant.Name == name
			and descendant:GetAttribute(PLACEHOLDER_ATTRIBUTE) ~= true
		then
			return descendant
		end
	end
	return nil
end

local function resolve(state: SoilState)
	local fallback = FALLBACK[state]
	local artist = findArtistVariant(state)
	if artist ~= nil then
		local placeholder = placeholders[state] :: MaterialVariant?
		if placeholder ~= nil then
			placeholder:Destroy()
			placeholders[state] = nil
		end
		looks[state] = { variant = state, material = artist.BaseMaterial, tinted = false, color = WHITE }
		return
	end
	if not USE_PLACEHOLDERS or not placeholdersAllowed then
		looks[state] = { variant = "", material = fallback.material, tinted = true, color = fallback.color }
		return
	end
	if (placeholders[state] :: MaterialVariant?) == nil then
		-- Client scripts may not be allowed to write MaterialVariant.BaseMaterial ("lacking
		-- capability Plugin"). That error used to escape and abort PlotRenderer:Start, so the
		-- drone was never composed (FIX-DRONE). Try once; on refusal, use the plain built-in
		-- materials for the rest of the session (the USE_PLACEHOLDERS = false path).
		local variant = Instance.new("MaterialVariant")
		local ok, err = pcall(function()
			variant.Name = state
			variant.BaseMaterial = fallback.material
			variant.StudsPerTile = fallback.studs
			variant.MaterialPattern = if fallback.regular
				then Enum.MaterialPattern.Regular
				else Enum.MaterialPattern.Organic
			variant.CustomPhysicalProperties = PhysicalProperties.new(Enum.Material.Ground) -- walks like soil
			variant:SetAttribute(PLACEHOLDER_ATTRIBUTE, true)
			variant.Parent = MaterialService
		end)
		if not ok then
			variant:Destroy()
			placeholdersAllowed = false
			warn(
				"[SoilLook] placeholder MaterialVariants unavailable here, using built-in materials: "
					.. tostring(err)
			)
			looks[state] =
				{ variant = "", material = fallback.material, tinted = true, color = fallback.color }
			return
		end
		placeholders[state] = variant
	end
	looks[state] = { variant = state, material = fallback.material, tinted = true, color = fallback.color }
end

local function resolveAll()
	for _, state in SoilStates.Names do
		resolve(state)
	end
end

--[[
	Resolves every state now, then watches MaterialService: an artist variant that arrives
	(or is renamed into place) later swaps in and `changed()` is called so the caller can
	re-apply its tiles. Call once.
]]
function SoilLook.start(changed: () -> ())
	onChanged = changed
	resolveAll()
	local function check(instance: Instance)
		if
			instance:IsA("MaterialVariant")
			and instance:GetAttribute(PLACEHOLDER_ATTRIBUTE) ~= true
			and FALLBACK[instance.Name] ~= nil
		then
			resolve(instance.Name)
			local callback = onChanged
			if callback ~= nil then
				callback()
			end
		end
	end
	MaterialService.DescendantAdded:Connect(check)
end

function SoilLook.look(state: SoilState): Look
	local look = looks[state]
	if look == nil then
		resolve(state)
		return looks[state]
	end
	return look
end

--[[
	Shows `state` on a tile. `flash` (harvest) briefly sets a lighter colour first; it only
	shows on tinted looks, since an artist variant's albedo comes from its texture. `instant`
	skips the colour tween (first sight, and MID-tier plots: no tweens there).
]]
function SoilLook.apply(tile: BasePart, state: SoilState, flash: Color3?, instant: boolean?)
	local look = SoilLook.look(state)
	if tile.Material ~= look.material then
		tile.Material = look.material
	end
	if tile.MaterialVariant ~= look.variant then
		tile.MaterialVariant = look.variant
	end
	local running = colorTweens[tile] :: Tween?
	if running ~= nil then
		running:Cancel()
		colorTweens[tile] = nil
	end
	if not look.tinted then
		tile.Color = WHITE -- the artist variant owns the colour from now on
		return
	end
	if instant == true then
		tile.Color = look.color
		return
	end
	if flash ~= nil then
		tile.Color = flash
	end
	local tween = TweenService:Create(tile, if flash ~= nil then FLASH_FADE else FADE, { Color = look.color })
	colorTweens[tile] = tween
	tween:Play()
end

return SoilLook
