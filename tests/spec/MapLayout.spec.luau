--[[
	The low-poly map (tools/map_layout.luau + tools/build_map.luau -> map/Map.rbxm) must never
	put anything inside a plot: for any field size (3 .. MaxSize) and every slot in
	GameConfig.Grid.PlotSlots, the base, zone, barriers and owner sign stay clear. Checks the
	layout maths against GridService's own formulas, that the slots and the village never
	overlap, then every part in the built map file.
]]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local MapLayout = require("../../tools/map_layout")

return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")
	local GRID = GameConfig.Grid
	local PITCH = GRID.TileSize + GRID.TileGap

	-- GridService.buildPlot / layoutPlot for slot `index` at field `size`: base, zone, sign.
	local function plotFootprint(index, size)
		local cx, cz = GRID.PlotSlots[index][1], GRID.PlotSlots[index][2] -- GridService.plotCenter
		local originX = cx - (GRID.MaxSize - 1) / 2 * PITCH
		local originZ = cz + (GRID.MaxSize - 1) / 2 * PITCH
		local width, depth = size * PITCH + 4, (size + 2) * PITCH + 4
		local centerX = originX + (size - 1) * PITCH / 2
		local centerZ = originZ + (3 - size) * PITCH / 2
		local outer = 1 + 1 -- zone margin + barrier
		return {
			minX = centerX - width / 2 - outer,
			maxX = centerX + width / 2 + outer,
			minZ = centerZ - depth / 2 - outer,
			maxZ = centerZ + depth / 2 + outer,
			signX = centerX,
			signZ = originZ - size * PITCH,
		}
	end

	describe("MapLayout", function()
		it("reserves every plot slot at every field size, sign included", function()
			local slots = MapLayout.plots(GameConfig)
			expect(#slots).toBe(#GRID.PlotSlots)
			local eps = 1e-6 -- the same edge computed in a different order differs in the last bits
			for index, slot in slots do
				for size = GRID.MinSize, GRID.MaxSize do
					local f = plotFootprint(index, size)
					expect(f.minX >= slot.minX - eps and f.maxX <= slot.maxX + eps).toBe(true)
					expect(f.minZ >= slot.minZ - eps and f.maxZ <= slot.maxZ + eps).toBe(true)
					expect(MapLayout.inside(slot, f.signX, f.signZ)).toBe(true)
				end
			end
		end)

		it("keeps the slots apart and the village free", function()
			local slots = MapLayout.plots(GameConfig)
			for i = 1, #slots do
				for j = i + 1, #slots do
					expect(MapLayout.overlaps(slots[i], slots[j])).toBe(false)
				end
			end
			local village = MapLayout.village(GameConfig)
			expect(village.maxX - village.minX > 80 and village.maxZ - village.minZ > 80).toBe(true)
			expect(MapLayout.inside(village, 0, 0)).toBe(true) -- the SpawnLocation is in it
			for _, slot in slots do
				expect(MapLayout.overlaps(slot, village)).toBe(false)
			end
		end)

		it("runs the roads between the farms, never through a plot", function()
			for _, s in MapLayout.paths(GameConfig) do
				local half = (s.width or MapLayout.PathWidth) / 2
				for t = 0, 1, 0.01 do
					local x, z = s.x0 + (s.x1 - s.x0) * t, s.z0 + (s.z1 - s.z0) * t
					expect(MapLayout.inPlot(GameConfig, x, z, half)).toBe(false)
				end
			end
		end)

		it("builds a map file whose parts all stay out of the plots", function()
			if not fs.isFile("map/Map.rbxm") then
				error("map/Map.rbxm is missing: run `lune run tools/build_map`")
			end
			local map = roblox.deserializeModel(fs.readFile("map/Map.rbxm"))[1]
			expect(map.Name).toBe("Map")
			expect(map:FindFirstChild("Backdrop") ~= nil).toBe(true)
			local slots = MapLayout.plots(GameConfig)
			local checked, bad = 0, {}
			for _, folder in map:GetChildren() do
				if folder.Name ~= "Backdrop" then
					for _, part in folder:GetDescendants() do
						if part:IsA("BasePart") then
							checked += 1
							-- The part's world-space box (rotation included): half extents along X / Z.
							local cf, s = part.CFrame, part.Size / 2
							local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
							local hx = math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z
							local hz = math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
							local p = cf.Position
							for _, slot in slots do
								local overlaps = p.X + hx > slot.minX
									and p.X - hx < slot.maxX
									and p.Z + hz > slot.minZ
									and p.Z - hz < slot.maxZ
								if overlaps then
									table.insert(
										bad,
										string.format(
											"%s.%s at (%.1f, %.1f)",
											folder.Name,
											part.Name,
											p.X,
											p.Z
										)
									)
									break
								end
							end
						end
					end
				end
			end
			if #bad > 0 then
				error(
					#bad
						.. " map parts inside a plot slot, e.g. "
						.. table.concat(bad, "; ", 1, math.min(5, #bad))
				)
			end
			expect(checked > 200).toBe(true)
		end)
	end)
end
