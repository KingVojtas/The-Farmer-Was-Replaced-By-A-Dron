--!strict
--[[
	PlotDressing
	============
	Makes each plot read as a tiny farm instead of brown squares on a green slab
	(docs/ART_BIBLE.md §1.1: organics warm and rounded, tech dark and crisp). Client-side, in
	the plot's visual folder. Every part is inert (anchored; CanCollide / CanQuery / CanTouch
	false; AssetLibrary rules): players still walk on the SERVER base, nothing here changes
	collision.

	LEVELS (PlotRenderer picks one per plot on every LOD tick)
	  full   your own plot: gravel walkway with plank edging on row y = -2, the low wooden
	         fence, the sign post, and the station extras (charger copper coil, factory
	         biofluid slit, amber work lamp)
	  basic  other plots within 120 studs: fence + sign post only
	  none   farther away: nothing
	The fence runs along three sides of the field. The side facing the station row stays
	open, so the drone's way in and out reads clearly.
	The sign post stands under the server's owner billboard; VIP (the OwnerVip attribute,
	set by the server from the pass) adds gold trim, never a text prefix.
	setStation("factory") lights the biofluid slit (Neon, flickering) and the amber lamp (pulsing)
	while the drone deposits or refines; any other value returns them to idle: dark, no Neon. The charger's ring pulse is
	PlotRenderer's, since it owns the rings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local AssetLibrary = require(script.Parent.AssetLibrary)

local GRID = GameConfig.Grid

export type Level = "full" | "basic" | "none"
export type Dressing = {
	setLevel: (level: string) -> (),
	rebuild: () -> (),
	setStation: (kind: string?) -> (),
	destroy: () -> (),
}

-- docs/ART_BIBLE.md §1.4.
local WOOD = Color3.fromHex("#8A6A4A") -- Fence wood
local WOOD_DARK = Color3.fromHex("#6E5238")
local GRAVEL = Color3.fromHex("#7A7468") -- Walkway gravel
local GOLD = Color3.fromHex("#FFD666")
local COPPER = Color3.fromHex("#C27744")
local BIOFLUID = Color3.fromHex("#4DFFB0")
local AMBER = Color3.fromHex("#FFB547")

local FENCE_OFFSET = 1.1 -- studs outside the field edge
local POST_EVERY = 2 -- at most this many tiles between fence posts
local SIGN_POST_TOP = 10.6 -- just under the server's billboard (the sign part sits at y = 12)
-- Idle = dark, opaque, no Neon (ART-6: Neon only for state). Working = Neon + flicker / pulse.
local SLIT_IDLE = Color3.fromHex("#1E4034")
local LAMP_IDLE = Color3.fromHex("#4A3A22")
local SLIT_FLICKER = TweenInfo.new(0.09, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true)
local LAMP_PULSE = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)

--[[
	The low-poly dressing kit (ReplicatedStorage.Assets.Dressing, tools/blender/tiles.py):
	places a clone of mesh piece `name` at `cframe`, stretched per axis in the piece's own space
	(`scale`: the rail along Z, the walkway along X; the kit's parts are axis-aligned). Returns
	false when the piece isn't there, so the caller builds its procedural Part instead.
]]
local function placePiece(
	name: string,
	cframe: CFrame,
	scale: Vector3,
	parent: Instance,
	shadow: boolean
): boolean
	local model = AssetLibrary.dressing(name)
	if model == nil then
		return false
	end
	local pivot = model:GetPivot()
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			local rel = pivot:ToObjectSpace(descendant.CFrame)
			descendant.Size = descendant.Size * scale
			descendant.CFrame = cframe * (CFrame.new(rel.Position * scale) * rel.Rotation)
			descendant.CastShadow = shadow
		end
	end
	model.WorldPivot = cframe
	model.Parent = parent
	return true
end

local function inert(
	name: string,
	size: Vector3,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function rank(level: string): number
	return if level == "full" then 2 elseif level == "basic" then 1 else 0
end

local PlotDressing = {}

function PlotDressing.new(plot: Model, folder: Folder): Dressing
	local level = "none"
	local root: Folder? = nil
	local slit: BasePart? = nil
	local lamp: BasePart? = nil
	local stationTweens: { Tween } = {}
	local activeStation: string? = nil
	local pending = false
	local connections: { RBXScriptConnection } = {}

	local function geometry(): (Vector3?, number, number)
		local origin = plot:GetAttribute("Origin")
		local pitch = plot:GetAttribute("Pitch")
		local size = plot:GetAttribute("Size")
		if typeof(origin) ~= "Vector3" or type(pitch) ~= "number" or type(size) ~= "number" then
			return nil, 0, 0
		end
		return origin, pitch, size
	end

	-- Low wooden fence: left, back and right of the field; open toward the station row.
	local function buildFence(parent: Folder, origin: Vector3, pitch: number, size: number)
		local half = GRID.TileSize / 2
		local ground = origin.Y - GRID.TileHeight
		local xMin = origin.X - half - FENCE_OFFSET
		local xMax = origin.X + (size - 1) * pitch + half + FENCE_OFFSET
		local zFront = origin.Z + half -- the field edge on the station side: the fence stops here
		local zBack = origin.Z - (size - 1) * pitch - half - FENCE_OFFSET
		local corners = {
			Vector3.new(xMin, ground, zFront),
			Vector3.new(xMin, ground, zBack),
			Vector3.new(xMax, ground, zBack),
			Vector3.new(xMax, ground, zFront),
		}
		for run = 1, 3 do
			local a, b = corners[run], corners[run + 1]
			local length = (b - a).Magnitude
			local segments = math.max(1, math.ceil(length / (POST_EVERY * pitch)))
			-- Each corner post is placed once: runs skip their last post, except the final run.
			for i = 0, if run == 3 then segments else segments - 1 do
				local at = CFrame.new(a:Lerp(b, i / segments) + Vector3.new(0, 0.65, 0))
				if not placePiece("FencePost", at, Vector3.one, parent, true) then
					local post = inert("FencePost", Vector3.new(0.32, 1.3, 0.32), WOOD, Enum.Material.Wood)
					post.CFrame = at
					post.Parent = parent
				end
			end
			for _, height in { 0.55, 1.0 } do
				local mid = (a + b) / 2 + Vector3.new(0, height, 0)
				local at = CFrame.lookAt(mid, b + Vector3.new(0, height, 0))
				-- The mesh rail is 2 studs long: stretch it along its own Z to the run's length.
				if not placePiece("FenceRail", at, Vector3.new(1, 1, length / 2), parent, false) then
					local rail =
						inert("FenceRail", Vector3.new(0.12, 0.12, length), WOOD_DARK, Enum.Material.Wood)
					rail.CastShadow = false
					rail.CFrame = at
					rail.Parent = parent
				end
			end
		end
	end

	-- A simple post under the server's owner billboard; VIP adds gold trim.
	local function buildSignPost(parent: Folder)
		local sign = plot:FindFirstChild("OwnerSign")
		if sign == nil or not sign:IsA("BasePart") then
			return
		end
		local base = Vector3.new(sign.Position.X, 0, sign.Position.Z)
		local vip = plot:GetAttribute("OwnerVip") == true
		-- The mesh post brings its own pole, bar and wooden cap; VIP still adds the gold cap + trim.
		local meshPost = placePiece("SignPost", CFrame.new(base), Vector3.one, parent, true)
		if not meshPost then
			local pole = inert("SignPole", Vector3.new(0.45, SIGN_POST_TOP, 0.45), WOOD, Enum.Material.Wood)
			pole.CFrame = CFrame.new(base + Vector3.new(0, SIGN_POST_TOP / 2, 0))
			pole.Parent = parent
			local bar = inert("SignBar", Vector3.new(3.4, 0.28, 0.28), WOOD_DARK, Enum.Material.Wood)
			bar.CFrame = CFrame.new(base + Vector3.new(0, SIGN_POST_TOP - 0.25, 0))
			bar.Parent = parent
		end
		if meshPost and not vip then
			return
		end
		local cap = inert(
			"SignCap",
			Vector3.new(0.6, 0.6, 0.6),
			if vip then GOLD else WOOD,
			if vip then Enum.Material.Metal else Enum.Material.Wood,
			Enum.PartType.Ball
		)
		cap.CFrame = CFrame.new(base + Vector3.new(0, SIGN_POST_TOP + 0.15, 0))
		cap.Parent = parent
		if vip then
			for _, height in { SIGN_POST_TOP - 0.8, 1.2 } do
				local band = inert("SignTrim", Vector3.new(0.58, 0.26, 0.58), GOLD, Enum.Material.Metal)
				band.CastShadow = false
				band.CFrame = CFrame.new(base + Vector3.new(0, height, 0))
				band.Parent = parent
			end
		end
	end

	-- Gravel strip with plank edging along the walkway row (y = -2).
	local function buildWalkway(parent: Folder, origin: Vector3, pitch: number, size: number)
		local ground = origin.Y - GRID.TileHeight
		local width = size * pitch + 3.2
		local center = Vector3.new(origin.X + (size - 1) * pitch / 2, ground, origin.Z + 2 * pitch)
		-- The mesh walkway is 6.4 wide: stretch it along X to the field's width.
		if placePiece("Walkway", CFrame.new(center), Vector3.new(width / 6.4, 1, 1), parent, false) then
			return
		end
		local gravel = inert("Gravel", Vector3.new(width, 0.06, GRID.TileSize), GRAVEL, Enum.Material.Pebble)
		gravel.CastShadow = false
		gravel.CFrame = CFrame.new(center + Vector3.new(0, 0.03, 0))
		gravel.Parent = parent
		for _, side in { -1, 1 } do
			local plank = inert("Plank", Vector3.new(width, 0.12, 0.35), WOOD, Enum.Material.WoodPlanks)
			plank.CastShadow = false
			plank.CFrame = CFrame.new(center + Vector3.new(0, 0.06, side * (GRID.TileSize / 2 + 0.18)))
			plank.Parent = parent
		end
	end

	-- Station extras (procedural stations only; an artist station brings its own detail).
	local function buildStationExtras(parent: Folder)
		for _, child in plot:GetChildren() do
			local kind = child:GetAttribute("Kind")
			if not child:IsA("BasePart") or type(kind) ~= "string" or AssetLibrary.hasStation(kind) then
				continue
			end
			local top = child.CFrame * CFrame.new(0, child.Size.Y / 2, 0)
			if kind == "charger" then
				-- Copper coil windings around the pylon (§4.2 suggestion).
				for _, height in { 0.6, 1.05 } do
					local coil = inert(
						"Coil",
						Vector3.new(0.22, 0.8, 0.8),
						COPPER,
						Enum.Material.Metal,
						Enum.PartType.Cylinder
					)
					coil.CFrame = top * CFrame.new(-2.6, height, -2.6) * CFrame.Angles(0, 0, math.rad(90))
					coil.Parent = parent
				end
			elseif kind == "factory" then
				local fluid =
					inert("BiofluidSlit", Vector3.new(0.28, 1.6, 0.1), SLIT_IDLE, Enum.Material.SmoothPlastic)
				fluid.CastShadow = false
				fluid.CFrame = top * CFrame.new(2.4, -1.0, 3.03)
				fluid.Parent = parent
				slit = fluid
				local light = inert(
					"WorkLamp",
					Vector3.new(0.36, 0.36, 0.36),
					LAMP_IDLE,
					Enum.Material.SmoothPlastic,
					Enum.PartType.Ball
				)
				light.CastShadow = false
				light.CFrame = top * CFrame.new(1.4, 1.38, 1.2)
				light.Parent = parent
				lamp = light
			end
		end
	end

	local function stopStation()
		for _, tween in stationTweens do
			tween:Cancel()
		end
		table.clear(stationTweens)
		-- Idle: dark and opaque, no Neon (ART-6).
		local s, l = slit, lamp
		if s ~= nil then
			s.Material = Enum.Material.SmoothPlastic
			s.Color = SLIT_IDLE
			s.Transparency = 0
		end
		if l ~= nil then
			l.Material = Enum.Material.SmoothPlastic
			l.Color = LAMP_IDLE
			l.Transparency = 0
		end
	end

	local function applyStation()
		stopStation()
		local s, l = slit, lamp
		if activeStation ~= "factory" or s == nil or l == nil then
			return
		end
		-- Working: the biofluid glows and flickers, the amber lamp pulses.
		s.Material = Enum.Material.Neon
		s.Color = BIOFLUID
		s.Transparency = 0.6
		l.Material = Enum.Material.Neon
		l.Color = AMBER
		l.Transparency = 0.75
		for _, tween in
			{
				TweenService:Create(s, SLIT_FLICKER, { Transparency = 0.05 }),
				TweenService:Create(l, LAMP_PULSE, { Transparency = 0 }),
			}
		do
			table.insert(stationTweens, tween)
			tween:Play()
		end
	end

	local function rebuild()
		pending = false
		stopStation()
		local old = root
		if old ~= nil then
			old:Destroy()
		end
		root = nil
		slit = nil
		lamp = nil
		local origin, pitch, size = geometry()
		if origin == nil or rank(level) == 0 or folder.Parent == nil then
			return
		end
		local group = Instance.new("Folder")
		group.Name = "Dressing"
		buildFence(group, origin, pitch, size)
		buildSignPost(group)
		if rank(level) >= 2 then
			buildWalkway(group, origin, pitch, size)
			buildStationExtras(group)
		end
		group.Parent = folder
		root = group
		applyStation()
	end

	-- Several changes in one frame (Size + sign move, stations arriving) rebuild once.
	local function schedule()
		if not pending then
			pending = true
			task.defer(rebuild)
		end
	end

	for _, attribute in { "Size", "Origin", "OwnerVip" } do
		table.insert(connections, plot:GetAttributeChangedSignal(attribute):Connect(schedule))
	end
	table.insert(
		connections,
		plot.ChildAdded:Connect(function(child: Instance)
			if child:GetAttribute("Kind") ~= nil or child.Name == "OwnerSign" then
				schedule()
			end
		end)
	)

	return {
		setLevel = function(newLevel: string)
			if newLevel ~= level then
				level = newLevel
				schedule()
			end
		end,
		rebuild = schedule,
		setStation = function(kind: string?)
			if kind ~= activeStation then
				activeStation = kind
				applyStation()
			end
		end,
		destroy = function()
			for _, connection in connections do
				connection:Disconnect()
			end
			stopStation()
			local old = root
			if old ~= nil then
				old:Destroy()
			end
		end,
	}
end

return PlotDressing
