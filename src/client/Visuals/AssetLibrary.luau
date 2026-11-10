--!strict
--[[
	AssetLibrary
	============
	The hook between code and art. Artists drop models into ReplicatedStorage.Assets following
	the naming contract in docs/ART_BIBLE.md; PlotRenderer asks this module first and falls
	back to its own procedural low-poly shapes when an asset is missing. So the game always
	runs, and better art replaces the placeholders without touching code.

	  Assets/Drone                     Model: Body, Rotor1..4 (spin), PaintSlot attributes
	  Assets/Crops/<cropId>/<stage>    Model per growth stage: "sprout" | "growing" | "ready"
	  Assets/Hats/<style>              Model, pivot = where it sits on the drone's back
	  Assets/Stations/<kind>           Model placed on the station tile ("charger" | "factory")

	EVERY clone is forced to be inert: Anchored = true, CanCollide / CanQuery / CanTouch = false,
	scripts removed. A model can never bring physics, collisions or code into the game.

	WHERE TO PUT ASSETS: the repo folder `assets/` is synced to ReplicatedStorage.Assets by Rojo
	(default.project.json, `$ignoreUnknownInstances`): save models there as .rbxm / .rbxmx
	(e.g. assets/Drone.rbxm, assets/Crops/wheat/ready.rbxm), OR drop them straight into
	ReplicatedStorage.Assets in Studio; Rojo keeps those too. See assets/README.md.
	A model with no visible part is IGNORED (logged once) and the procedural stand-in stays.
	Never leave an empty placeholder Model named like an asset.

	ARTIST CHECKLIST (details: docs/ART_BIBLE.md §3, §4 and §10; the folder layout above is
	fixed, so don't invent new paths)
	  Crops   ReplicatedStorage.Assets.Crops.<cropId>.<stage>
	          cropId: grass | wheat | carrot | tree | sunflower | pumpkin | cactus
	          stage:  sprout | growing | ready
	    [ ] Model.WorldPivot = the tile's top centre, +Y up.
	    [ ] The game ScaleTo()s the model while it grows (sprout 0.25-0.55, growing 0.55-0.85,
	        ready 1): author the sprout TALLER than it should look (Bible §3.1).
	    [ ] Ready footprint <= 5.2 x 5.2 studs; one MeshPart per stage (two at most).
	    [ ] Opaque only: no alpha-card leaves. CollisionFidelity Box, RenderFidelity Automatic.
	    [ ] CastShadow false on the sprout stage and on grass.
	    [ ] READY must change silhouette AND colour (§3.3), not just size.
	    [ ] Playtest: the stage swaps at progress 0.5 and at ready must not jump in world
	        position (the pivot contract), and every 45-degree yaw step must still look right.
	  Drone   ReplicatedStorage.Assets.Drone (Model, pivot = body centre)
	    [ ] Parts named Body and Rotor1..Rotor4 ("Rotor*" spins around its own origin; model the
	        blades flat, origin at the hub). Optional: Eye (Neon, PaintSlot "accent"), any part
	        with the attribute PaintSlot = primary | secondary | accent, and BatteryBar or
	        StatusLight (Neon, no SurfaceAppearance: the game colours it by battery).
	    [ ] <= 16 MeshParts, <= 1,900 tris. Keep the top of Body clear in a 1.2-stud circle (hats
	        sit 0.4 above the body centre).
	    [ ] It hovers 5 studs up with a 0.35 bob and a 14-degree lean: nothing may clip.
	  Stations ReplicatedStorage.Assets.Stations.charger / .factory (pivot = top of the station
	        tile)
	    [ ] Neon only for STATE (charger rings cyan, factory biofluid #4DFFB0), never decoration.
	Until an asset exists, PlotRenderer draws a procedural stand-in with the same silhouette
	rules, so the game looks finished with zero assets.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AssetLibrary = {}

local function find(path: { string }): Instance?
	local node: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	for _, name in path do
		if node == nil then
			return nil
		end
		node = (node :: Instance):FindFirstChild(name)
	end
	return node
end

-- Makes every part of a cloned asset static and harmless.
function AssetLibrary.makeInert(root: Instance)
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			if descendant:IsA("MeshPart") then
				-- Box is the cheapest collision data; it can only be set where the engine allows it.
				local mesh = descendant :: MeshPart
				pcall(function()
					mesh.CollisionFidelity = Enum.CollisionFidelity.Box
				end)
			end
		elseif
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("Constraint")
			or descendant:IsA("JointInstance")
			or descendant:IsA("Humanoid")
			or descendant:IsA("Animator")
			or descendant:IsA("AnimationController")
		then
			descendant:Destroy()
		end
	end
	if root:IsA("BasePart") then
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
	end
end

--[[
	True when something in the model can actually be seen: at least one BasePart bigger than a
	speck (Size.Magnitude > 0.2) that isn't (nearly) invisible (Transparency < 0.9). An empty
	model, 0-size meshes or an all-transparent import must not replace a procedural stand-in
	with nothing (BUG-DRONE). A SurfaceAppearance whose ColorMap is fully transparent can't be
	detected from a script: keep painted MeshParts opaque (docs/ART_BIBLE.md §4.1).
]]
function AssetLibrary.hasVisiblePart(model: Model): boolean
	for _, descendant in model:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and descendant.Size.Magnitude > 0.2
			and descendant.Transparency < 0.9
		then
			return true
		end
	end
	return false
end

local warnedBroken: { [string]: boolean } = {}

-- Clones a model asset, or nil when it's missing or BROKEN (nothing visible in it: an empty
-- Model, 0-size meshes, all transparent). A broken asset is logged once and the caller
-- falls back to its procedural stand-in, so a bad drop can never make something vanish.
local function cloneModel(path: { string }): Model?
	local source = find(path)
	if source == nil or not source:IsA("Model") then
		return nil
	end
	if not AssetLibrary.hasVisiblePart(source) then
		local key = table.concat(path, ".")
		if not warnedBroken[key] then
			warnedBroken[key] = true
			warn(
				string.format(
					"[AssetLibrary] ignored broken %s (needs a BasePart with Size > 0.2 and Transparency < 0.9)",
					key
				)
			)
		end
		return nil
	end
	local clone = source:Clone()
	AssetLibrary.makeInert(clone)
	return clone
end

-- The artist drone, or nil (procedural drone) if it's missing or broken.
function AssetLibrary.drone(): Model?
	return cloneModel({ "Drone" })
end

function AssetLibrary.crop(cropId: string, stage: string): Model?
	local model = cloneModel({ "Crops", cropId, stage })
	if model ~= nil and (stage == "sprout" or cropId == "grass") then
		-- Tiny shadows are invisible from the gameplay camera but still cost (ART_BIBLE §3.4).
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CastShadow = false
			end
		end
	end
	return model
end

function AssetLibrary.hat(style: string): Model?
	return cloneModel({ "Hats", style })
end

function AssetLibrary.station(kind: string): Model?
	return cloneModel({ "Stations", kind })
end

-- True when an artist station model exists (no clone is made).
function AssetLibrary.hasStation(kind: string): boolean
	local found = find({ "Stations", kind })
	return found ~= nil and found:IsA("Model") and AssetLibrary.hasVisiblePart(found)
end

return AssetLibrary
