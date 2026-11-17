--[[
	map_layout.luau: the geometry of the farm village. It's pure: give it GameConfig.
	Used by tools/build_map.luau (to place the map) and tests/spec/MapLayout.spec.luau (to
	prove nothing in map/Map.rbxm can ever stand inside a plot).

	The plots sit on GameConfig.Grid.PlotSlots (a 5 x 5 grid, the spawn village in the middle).
	Each slot reserves what GridService builds at the LARGEST field (GameConfig.Grid.MaxSize):
	the base + zone margin + barrier, plus room for the owner sign north of the field.
	Roads run along the gaps between slot columns and rows; the village is the free cell in the
	middle, inside the four roads around it.
]]

local MapLayout = {}

MapLayout.ZoneMargin = 1 -- GridService ZONE_MARGIN
MapLayout.BarrierDepth = 1 -- barrier walls sit just outside the zone, 1 stud thick
MapLayout.SignRoom = 3 -- the owner sign post stands 1.2 studs north of the base
MapLayout.PathWidth = 6.4 -- one path piece is 6.4 wide (roads use two side by side)
MapLayout.RoadWidth = 12.8

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }
export type Segment = { x0: number, z0: number, x1: number, z1: number, width: number? }

-- The reserved rectangle of a plot centred on (cx, cz), at the largest field.
function MapLayout.slotRect(GameConfig, cx: number, cz: number): Rect
	local GRID = GameConfig.Grid
	local pitch = GRID.TileSize + GRID.TileGap
	local size = GRID.MaxSize
	local originZ = cz + (GRID.MaxSize - 1) / 2 * pitch
	local width = size * pitch + 4
	local depth = (size + 2) * pitch + 4
	local centerZ = originZ + (3 - size) * pitch / 2
	local guard = MapLayout.ZoneMargin + MapLayout.BarrierDepth
	return {
		minX = cx - width / 2 - guard,
		maxX = cx + width / 2 + guard,
		minZ = centerZ - depth / 2 - guard - MapLayout.SignRoom,
		maxZ = centerZ + depth / 2 + guard,
	}
end

-- Every plot slot's reserved rectangle.
function MapLayout.plots(GameConfig): { Rect }
	local rects = {}
	for _, slot in GameConfig.Grid.PlotSlots do
		table.insert(rects, MapLayout.slotRect(GameConfig, slot[1], slot[2]))
	end
	return rects
end

-- The bounding box of all slots: the farms' district.
function MapLayout.district(GameConfig): Rect
	local box = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
	for _, r in MapLayout.plots(GameConfig) do
		box.minX, box.maxX = math.min(box.minX, r.minX), math.max(box.maxX, r.maxX)
		box.minZ, box.maxZ = math.min(box.minZ, r.minZ), math.max(box.maxZ, r.maxZ)
	end
	return box
end

-- Sorted unique values.
local function unique(values: { number }): { number }
	table.sort(values)
	local out = {}
	for _, v in values do
		if #out == 0 or math.abs(out[#out] - v) > 1e-6 then
			table.insert(out, v)
		end
	end
	return out
end

--[[
	The road lines: x of every gap between two slot columns, z of every gap between two slot
	rows (the middle of the free strip between their reserved rectangles), plus a ring road just
	outside the district.
]]
function MapLayout.roads(GameConfig): ({ number }, { number })
	local xs, zs = {}, {}
	for _, slot in GameConfig.Grid.PlotSlots do
		table.insert(xs, slot[1])
		table.insert(zs, slot[2])
	end
	xs, zs = unique(xs), unique(zs)
	local probe = MapLayout.slotRect(GameConfig, 0, 0)
	local roadX, roadZ = {}, {}
	for k = 1, #xs - 1 do
		table.insert(roadX, ((xs[k] + probe.maxX) + (xs[k + 1] + probe.minX)) / 2)
	end
	for k = 1, #zs - 1 do
		table.insert(roadZ, ((zs[k] + probe.maxZ) + (zs[k + 1] + probe.minZ)) / 2)
	end
	local d = MapLayout.district(GameConfig)
	table.insert(roadX, 1, d.minX - 10)
	table.insert(roadX, d.maxX + 10)
	table.insert(roadZ, 1, d.minZ - 10)
	table.insert(roadZ, d.maxZ + 10)
	return roadX, roadZ
end

-- The road network as straight segments (each one a road MapLayout.RoadWidth wide).
function MapLayout.paths(GameConfig): { Segment }
	local roadX, roadZ = MapLayout.roads(GameConfig)
	local x0, x1 = roadX[1], roadX[#roadX]
	local z0, z1 = roadZ[1], roadZ[#roadZ]
	local segments = {}
	for _, x in roadX do
		table.insert(segments, { x0 = x, z0 = z0, x1 = x, z1 = z1, width = MapLayout.RoadWidth })
	end
	for _, z in roadZ do
		table.insert(segments, { x0 = x0, z0 = z, x1 = x1, z1 = z, width = MapLayout.RoadWidth })
	end
	return segments
end

--[[
	The village: the free cell in the middle of the grid (where a slot at (0, 0) would be),
	inside the four roads around it, with a little margin off the road edges.
]]
function MapLayout.village(GameConfig): Rect
	local roadX, roadZ = MapLayout.roads(GameConfig)
	local function nearest(list, sign)
		local best = nil
		for _, v in list do
			if v * sign > 0 and (best == nil or math.abs(v) < math.abs(best)) then
				best = v
			end
		end
		return best
	end
	local m = MapLayout.RoadWidth / 2 + 2
	return {
		minX = nearest(roadX, -1) + m,
		maxX = nearest(roadX, 1) - m,
		minZ = nearest(roadZ, -1) + m,
		maxZ = nearest(roadZ, 1) - m,
	}
end

function MapLayout.inside(rect: Rect, x: number, z: number, pad: number?): boolean
	local p = pad or 0
	return x >= rect.minX - p and x <= rect.maxX + p and z >= rect.minZ - p and z <= rect.maxZ + p
end

function MapLayout.overlaps(a: Rect, b: Rect): boolean
	return a.minX < b.maxX and a.maxX > b.minX and a.minZ < b.maxZ and a.maxZ > b.minZ
end

-- Distance from (x, z) to a segment (for keeping props off the roads).
function MapLayout.distanceToSegment(s: Segment, x: number, z: number): number
	local dx, dz = s.x1 - s.x0, s.z1 - s.z0
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((x - s.x0) * dx + (z - s.z0) * dz) / len2, 0, 1) else 0
	local px, pz = s.x0 + t * dx, s.z0 + t * dz
	return math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
end

-- True when (x, z) with clearance `radius` touches any plot slot.
function MapLayout.inPlot(GameConfig, x: number, z: number, radius: number): boolean
	for _, r in MapLayout.plots(GameConfig) do
		if MapLayout.inside(r, x, z, radius) then
			return true
		end
	end
	return false
end

return MapLayout
