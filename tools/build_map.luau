--[[
	build_map.luau: composes the farm village and the countryside around the plots into
	map/Map.rbxm (Workspace.Map).

	    lune run tools/build_map          (from the repo root, after roblox_upload.py models)

	Reads the finished models in map/props/*.rbxm (Blender tools/blender/props.py and
	buildings.py -> Open Cloud -> tools/apply_parts.luau: coloured, detail MaterialVariants,
	turned back, pivot on the ground centre) and places clones with a FIXED seed, so a rebuild
	gives the same map. The layout is tools/map_layout.luau's:
	  Village   the free cell in the middle of the 5 x 5 slot grid, round the SpawnLocation: the
	            square (plaza, well, benches, lamps, market stalls, welcome sign), the farmhouse
	            with its garden beds, the barn with silo / tractor / haystacks, chicken coop, tool
	            shed, greenhouse, water tower, the windmill by the pond; a picket fence round it,
	            open where its four lanes meet the roads
	  Roads     one double-width path piece along every gap between slot rows and columns, plus
	            the ring road round the farm district
	  Lamps     along the roads (alternating sides) and at a corner of every crossing
	  Farm      tree avenues along the inner roads, hay / carts / barrels / scarecrows at the
	            crossings, a picket fence along the outside of the ring road
	  Nature    orchards, a berry field, forest groves, a pond and meadows in the countryside
	  Backdrop  a ring of faceted hills far out (LightingController skips its own then)
	Nothing ever lands inside a plot slot or on a road: tests/spec/MapLayout.spec.luau checks the
	written file. Buildings and big things collide (Box); decoration doesn't (the part sheets
	decide; see apply_parts).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Loader = require("../tests/lib/loader")
local MapLayout = require("./map_layout")

local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")
local Instance, CFrame, Vector3, Color3, Enum, UDim2 =
	roblox.Instance, roblox.CFrame, roblox.Vector3, roblox.Color3, roblox.Enum, roblox.UDim2

local PROPS_DIR = "map/props"
local OUT = "map/Map.rbxm"
local HOUSE = 1.35 -- buildings.py models are small: at 1.35 a door fits an avatar
local WORLD_RADIUS = 600 -- the countryside ends here; the hills stand beyond

-- ------------------------------------------------------------------ templates
local templates = {}
local radiusOf = {} -- circle round the pivot (for scattered props)
local footprintOf = {} -- local x/z box (for buildings)
for _, file in fs.readDir(PROPS_DIR) do
	local name = string.match(file, "^(.+)%.rbxm$")
	if name then
		local root = roblox.deserializeModel(fs.readFile(PROPS_DIR .. "/" .. file))[1]
		templates[name] = root
		local r = 0
		local box = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				local p, s = d.CFrame.Position, d.Size
				r = math.max(r, math.sqrt(p.X * p.X + p.Z * p.Z) + math.max(s.X, s.Z) / 2)
				box.minX, box.maxX = math.min(box.minX, p.X - s.X / 2), math.max(box.maxX, p.X + s.X / 2)
				box.minZ, box.maxZ = math.min(box.minZ, p.Z - s.Z / 2), math.max(box.maxZ, p.Z + s.Z / 2)
			end
		end
		radiusOf[name] = r
		footprintOf[name] = box
	end
end
local NEEDED = {
	"oak",
	"pine",
	"birch",
	"bush",
	"berry_bush",
	"rock_small",
	"rock_medium",
	"rock_large",
	"flowers_yellow",
	"flowers_pink",
	"flowers_white",
	"grass_tuft",
	"log",
	"mushroom",
	"hay_bale",
	"crate",
	"barrel",
	"cart",
	"scarecrow",
	"well",
	"lamp_post",
	"bench",
	"windmill",
	"welcome_sign",
	"plaza",
	"path",
	"pond",
	"hedge",
	"hill_a",
	"hill_b",
	"hill_c",
	"farmhouse",
	"barn",
	"silo",
	"greenhouse",
	"chicken_coop",
	"water_tower",
	"tool_shed",
	"market_stall",
	"tractor",
	"fence_segment",
	"garden_bed",
	"haystack",
}
local missing = {}
for _, name in NEEDED do
	if templates[name] == nil then
		table.insert(missing, name)
	end
end
if #missing > 0 then
	print("missing props in " .. PROPS_DIR .. ": " .. table.concat(missing, ", "))
	print("run: python tools/roblox_upload.py models")
	process.exit(1)
end

-- ------------------------------------------------------------------ deterministic random
local state = 20261113
local function rand(): number
	state = (state * 1103515245 + 12345) % 2147483648
	return state / 2147483648
end
local function range(a: number, b: number): number
	return a + (b - a) * rand()
end
local function pick(list)
	return list[math.floor(rand() * #list) + 1]
end

-- ------------------------------------------------------------------ the map model
local map = Instance.new("Model")
map.Name = "Map"
local folders = {}
for _, name in { "Village", "Roads", "Lamps", "Farm", "Nature", "Backdrop" } do
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = map
	folders[name] = f
end

-- The yaw that turns a prop's front (local -Z) toward world (tx, tz) from (x, z).
local function faceYaw(x: number, z: number, tx: number, tz: number): number
	return math.atan2(-(tx - x), -(tz - z))
end

-- The yaw that points a lamp's arm (local +X) from (x, z) toward (tx, tz).
local function armYaw(x: number, z: number, tx: number, tz: number): number
	return math.atan2(-(tz - z), tx - x)
end

local placed: { any } = {} -- what takes room: circles { x, z, r } and boxes { rect, name }
local counts = {}

--[[
	Places a clone of `name` with its pivot at (x, y, z), turned `yaw` about Y and scaled
	(a number, or a Vector3 for the flat road pieces; the parts are axis-aligned in the
	template, so a per-axis scale is safe). room: "rect" keeps the turned footprint free (houses),
	false keeps nothing (flat or thin things), anything else a circle.
]]
local function put(
	name: string,
	x: number,
	z: number,
	yaw: number,
	scale: any,
	folder: string,
	room: any?,
	y: number?
)
	local s = if type(scale) == "number" then Vector3.new(scale, scale, scale) else scale
	local clone = templates[name]:Clone()
	clone.Name = name
	local at = CFrame.new(x, y or 0, z) * CFrame.Angles(0, yaw, 0)
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			local p = cf.Position
			d.CFrame = at * (CFrame.new(p.X * s.X, p.Y * s.Y, p.Z * s.Z) * (cf - p))
			d.Size = Vector3.new(d.Size.X * s.X, d.Size.Y * s.Y, d.Size.Z * s.Z)
		end
	end
	clone.WorldPivotData = at
	clone.Parent = folders[folder]
	if room == "rect" then
		local f = footprintOf[name]
		local c, sn = math.cos(yaw), math.sin(yaw)
		local box = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
		for _, corner in { { f.minX, f.minZ }, { f.maxX, f.minZ }, { f.minX, f.maxZ }, { f.maxX, f.maxZ } } do
			local lx, lz = corner[1] * s.X, corner[2] * s.Z
			local wx, wz = x + lx * c + lz * sn, z - lx * sn + lz * c
			box.minX, box.maxX = math.min(box.minX, wx), math.max(box.maxX, wx)
			box.minZ, box.maxZ = math.min(box.minZ, wz), math.max(box.maxZ, wz)
		end
		table.insert(placed, { rect = box, name = name })
	elseif room ~= false then
		table.insert(placed, { x = x, z = z, r = radiusOf[name] * math.max(s.X, s.Z) })
	end
	counts[name] = (counts[name] or 0) + 1
	return clone
end

-- ------------------------------------------------------------------ space rules
local RW = MapLayout.RoadWidth
local roadX, roadZ = MapLayout.roads(GameConfig)
local roads = MapLayout.paths(GameConfig)
local VILLAGE = MapLayout.village(GameConfig)
local FENCE = {
	minX = VILLAGE.minX + 1.5,
	maxX = VILLAGE.maxX - 1.5,
	minZ = VILLAGE.minZ + 1.5,
	maxZ = VILLAGE.maxZ - 1.5,
}
-- The farm district out to the far edge of the ring road and its fence.
local OUTER = {
	minX = roadX[1] - RW / 2 - 4,
	maxX = roadX[#roadX] + RW / 2 + 4,
	minZ = roadZ[1] - RW / 2 - 4,
	maxZ = roadZ[#roadZ] + RW / 2 + 4,
}
local lanes = {} -- the village lanes (plaza -> roads), same shape as roads

local function isRing(s): boolean
	return s.x0 == s.x1 and (s.x0 == roadX[1] or s.x0 == roadX[#roadX])
		or s.z0 == s.z1 and (s.z0 == roadZ[1] or s.z0 == roadZ[#roadZ])
end

--[[
	Is there room for something of radius r at (x, z)? zone: "village" (inside the fence),
	"district" (between the farms, out of the village) or "country" (outside the ring road).
	Never in a plot slot, on a road or lane, or on anything already placed.
]]
local function free(x: number, z: number, r: number, gap: number?, zone: string): boolean
	if zone == "village" then
		if not MapLayout.inside(FENCE, x, z, -r - 0.3) then
			return false
		end
	elseif MapLayout.inside(VILLAGE, x, z, r + 1) then
		return false
	end
	if zone == "district" and not MapLayout.inside(OUTER, x, z, -r) then
		return false
	end
	if zone == "country" and (MapLayout.inside(OUTER, x, z, r) or x * x + z * z > (WORLD_RADIUS - r) ^ 2) then
		return false
	end
	if MapLayout.inPlot(GameConfig, x, z, r + 1) then
		return false
	end
	for _, list in { roads, lanes } do
		for _, s in list do
			if MapLayout.distanceToSegment(s, x, z) < s.width / 2 + r + 0.5 then
				return false
			end
		end
	end
	local g = gap or 1
	for _, p in placed do
		if p.rect then
			if MapLayout.inside(p.rect, x, z, r + g) then
				return false
			end
		else
			local dx, dz = x - p.x, z - p.z
			if dx * dx + dz * dz < (p.r + r + g) ^ 2 then
				return false
			end
		end
	end
	return true
end

-- Scatter `count` props drawn from `names` inside `region`, with random yaw and scale.
local function scatter(
	names,
	count: number,
	region,
	folder: string,
	scaleMin: number,
	scaleMax: number,
	gap: number?,
	zone: string
)
	local done, tries = 0, 0
	while done < count and tries < count * 60 do
		tries += 1
		local name = pick(names)
		local scale = range(scaleMin, scaleMax)
		local x, z = range(region.minX, region.maxX), range(region.minZ, region.maxZ)
		if free(x, z, radiusOf[name] * scale, gap, zone) then
			put(name, x, z, range(0, 2 * math.pi), scale, folder)
			done += 1
		end
	end
	return done
end

-- Place one thing only if it fits (crossing kits, avenues).
local function try(
	name: string,
	x: number,
	z: number,
	yaw: number,
	scale: number,
	folder: string,
	gap: number?,
	zone: string
): boolean
	if free(x, z, radiusOf[name] * scale, gap, zone) then
		put(name, x, z, yaw, scale, folder)
		return true
	end
	return false
end

-- Lay flat path pieces (12 long, 6.4 wide) along a segment, `width` wide.
local function pave(s, width: number, folder: string, lift: number)
	local dx, dz = s.x1 - s.x0, s.z1 - s.z0
	local length = math.sqrt(dx * dx + dz * dz)
	local k = width / 6.4
	local piece = 12 * k
	local ux, uz = dx / length, dz / length
	local yaw = math.atan2(ux, uz)
	local n = math.max(1, math.ceil((length - piece) / (piece * 0.95)) + 1)
	for i = 0, n - 1 do
		local t = if n == 1 then length / 2 else piece / 2 + i * (length - piece) / (n - 1)
		put(
			"path",
			s.x0 + ux * t,
			s.z0 + uz * t,
			yaw + math.rad(range(-1, 1)),
			Vector3.new(k, 1, k),
			folder,
			false,
			lift
		)
	end
end

-- ------------------------------------------------------------------ the village square
local function nearest(list, sign)
	local best = nil
	for _, v in list do
		if v * sign > 0 and (best == nil or math.abs(v) < math.abs(best)) then
			best = v
		end
	end
	return best
end
local edge = {
	west = nearest(roadX, -1) + RW / 2,
	east = nearest(roadX, 1) - RW / 2,
	south = nearest(roadZ, -1) + RW / 2,
	north = nearest(roadZ, 1) - RW / 2,
}
local PLAZA_SCALE = 1.3
local PLAZA_R = radiusOf.plaza * PLAZA_SCALE
local LANE = 8
put("plaza", 0, 0, 0, PLAZA_SCALE, "Village", false)
table.insert(placed, { x = 0, z = 0, r = PLAZA_R - 2 }) -- the square stays open (spawn)
for _, s in
	{
		{ x0 = 0, z0 = PLAZA_R - 1, x1 = 0, z1 = edge.north },
		{ x0 = 0, z0 = -(PLAZA_R - 1), x1 = 0, z1 = edge.south },
		{ x0 = PLAZA_R - 1, z0 = 0, x1 = edge.east, z1 = 0 },
		{ x0 = -(PLAZA_R - 1), z0 = 0, x1 = edge.west, z1 = 0 },
	}
do
	s.width = LANE
	table.insert(lanes, s)
	pave(s, LANE, "Village", 0.01)
end

-- The well, benches and a ring of lamps on the square; market stalls round it.
put("well", -11, 11, math.rad(20), 1.15, "Village")
for _, b in { { 11, 11 }, { 11, -11 }, { -11, -11 } } do
	put("bench", b[1], b[2], faceYaw(b[1], b[2], 0, 0) + math.pi, 1.1, "Village")
end
for k = 0, 7 do
	local a = math.rad(90 * math.floor(k / 2) + (if k % 2 == 0 then -16 else 16))
	local x, z = math.cos(a) * (PLAZA_R + 1.2), math.sin(a) * (PLAZA_R + 1.2)
	put("lamp_post", x, z, armYaw(x, z, 0, 0), 1.1, "Lamps")
end
for _, d in { { 1, 1 }, { 1, -1 }, { -1, -1 }, { -1, 1 } } do
	local x, z = d[1] * 20, d[2] * 20
	put("market_stall", x, z, faceYaw(x, z, 0, 0), HOUSE, "Village", "rect")
	for j = 1, 2 do
		local cx, cz = x + d[1] * range(3, 5) + j * d[1], z + d[2] * range(4, 6) - j * d[2]
		try(pick({ "crate", "barrel" }), cx, cz, range(0, 6.28), 1, "Village", 0.3, "village")
	end
end

-- The welcome sign by the south lane (slot 1 is that way), facing the square, with its text.
local signX, signZ = 10, -(PLAZA_R + 7)
local sign = put("welcome_sign", signX, signZ, faceYaw(signX, signZ, 0, 0), 1.2, "Village")
local board = sign:FindFirstChild("Board")
if board then
	local toPlaza = Vector3.new(-signX, 0, -signZ).Unit
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Welcome"
	gui.Face = if board.CFrame.LookVector:Dot(toPlaza) >= 0 then Enum.NormalId.Front else Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.LightInfluence = 1
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "DRONE FARM\nwrite code - grow crops"
	label.TextScaled = true
	label.FontFace = roblox.Font.fromEnum(Enum.Font.BuilderSansExtraBold)
	label.TextColor3 = Color3.fromRGB(58, 40, 24)
	label.Parent = gui
	gui.Parent = board
end

-- ------------------------------------------------------------------ the village buildings
-- North-west: the farmhouse (front to the square), garden beds behind, shed and coop beside.
put("farmhouse", -29, 40, 0, HOUSE, "Village", "rect")
for k = 0, 3 do
	put("garden_bed", -44 + k * 8, 54, 0, HOUSE, "Village", "rect")
end
put("tool_shed", -46, 30, faceYaw(-46, 30, 0, 30), HOUSE, "Village", "rect")
put("chicken_coop", -12, 47, 0, HOUSE, "Village", "rect")
-- North-east: the barn (doors to the square), the silo, the tractor and haystacks.
put("barn", 27, 42, 0, HOUSE, "Village", "rect")
put("silo", 44.5, 47, 0, HOUSE, "Village", "rect")
put("tractor", 44, 29, math.rad(-150), HOUSE, "Village", "rect")
put("haystack", 10.5, 49, 0, 1.15, "Village")
put("haystack", 10, 38, math.rad(40), 1.0, "Village")
-- South-east: the greenhouse, garden beds, the water tower in the corner.
put("greenhouse", 28, -36, 0, HOUSE, "Village", "rect")
put("garden_bed", 33, -18, 0, HOUSE, "Village", "rect")
put("garden_bed", 42, -18, 0, HOUSE, "Village", "rect")
put("water_tower", 44, -40, math.rad(10), HOUSE, "Village", "rect")
-- South-west: the windmill by the pond, benches looking at the water.
put("pond", -30, -37, math.rad(8), 1.2, "Village", "rect")
put("windmill", -42, -16, faceYaw(-42, -16, 0, 0), 1.3, "Village", "rect")
for _, b in { { -27, -24 }, { -39, -24 } } do
	put("bench", b[1], b[2], math.pi, 1.1, "Village")
end

-- Hand-placed houses must not overlap one another (a layout slip shows up here, not in Studio).
for i = 1, #placed do
	for j = i + 1, #placed do
		local a, b = placed[i], placed[j]
		if a.rect and b.rect and MapLayout.overlaps(a.rect, b.rect) then
			print(string.format("WARNING: %s and %s overlap", a.name, b.name))
		end
	end
end

-- The picket fence round the village, open where the lanes leave it.
local function fenceLine(x0: number, z0: number, x1: number, z1: number, folder: string, gaps)
	local dx, dz = x1 - x0, z1 - z0
	local length = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / length, dz / length
	local yaw = math.atan2(-uz, ux) -- the segment's long axis is local X
	local n = math.floor(length / 6)
	local inset = (length - n * 6) / 2
	for i = 0, n - 1 do
		local t = inset + i * 6 + 3
		local x, z = x0 + ux * t, z0 + uz * t
		local open = false
		for _, g in gaps do
			if math.abs(x - g[1]) < g[3] and math.abs(z - g[2]) < g[3] then
				open = true
			end
		end
		if not open then
			put("fence_segment", x, z, yaw, 1, folder, false)
		end
	end
end
local laneGaps = {
	{ 0, FENCE.maxZ, LANE / 2 + 3 },
	{ 0, FENCE.minZ, LANE / 2 + 3 },
	{ FENCE.maxX, 0, LANE / 2 + 3 },
	{ FENCE.minX, 0, LANE / 2 + 3 },
}
fenceLine(FENCE.minX, FENCE.minZ, FENCE.maxX, FENCE.minZ, "Village", laneGaps)
fenceLine(FENCE.minX, FENCE.maxZ, FENCE.maxX, FENCE.maxZ, "Village", laneGaps)
fenceLine(FENCE.minX, FENCE.minZ, FENCE.minX, FENCE.maxZ, "Village", laneGaps)
fenceLine(FENCE.maxX, FENCE.minZ, FENCE.maxX, FENCE.maxZ, "Village", laneGaps)

-- Village life: a few shade trees, bushes, flowers, farm clutter.
scatter({ "oak", "birch" }, 6, VILLAGE, "Village", 0.8, 1.0, 1.5, "village")
scatter({ "hay_bale", "crate", "barrel" }, 10, VILLAGE, "Village", 0.9, 1.1, 0.8, "village")
scatter({ "bush", "berry_bush" }, 10, VILLAGE, "Village", 0.8, 1.1, 0.6, "village")
scatter(
	{ "flowers_yellow", "flowers_pink", "flowers_white" },
	30,
	VILLAGE,
	"Village",
	0.9,
	1.3,
	0.3,
	"village"
)
scatter({ "grass_tuft" }, 25, VILLAGE, "Village", 0.8, 1.3, 0.3, "village")

-- ------------------------------------------------------------------ roads, crossings, lamps
for _, s in roads do
	-- Each road runs half a width past its ends, so the ring's corners close. x-running roads
	-- sit a hair higher, so the crossings don't z-fight.
	local dx, dz = s.x1 - s.x0, s.z1 - s.z0
	local length = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / length * RW / 2, dz / length * RW / 2
	local long = { x0 = s.x0 - ux, z0 = s.z0 - uz, x1 = s.x1 + ux, z1 = s.z1 + uz }
	pave(long, RW, "Roads", if s.z0 == s.z1 then 0.03 else 0)
end

local function nearCrossing(s, x: number, z: number, d: number): boolean
	local across = if s.x0 == s.x1 then roadZ else roadX
	for _, v in across do
		if math.abs((if s.x0 == s.x1 then z else x) - v) < d then
			return true
		end
	end
	return false
end

-- Crossings: a lamp at one corner, and a little farm scene at some of the others.
local KITS = {
	function(x, z)
		try("haystack", x, z, range(0, 6.28), range(0.9, 1.15), "Farm", 1, "district")
	end,
	function(x, z)
		for j = 0, 2 do
			try(
				"hay_bale",
				x + range(-2.5, 2.5),
				z + range(-2.5, 2.5),
				range(0, 6.28),
				1,
				"Farm",
				0.2,
				"district"
			)
		end
	end,
	function(x, z)
		try("cart", x, z, range(0, 6.28), 1.1, "Farm", 0.5, "district")
		try("barrel", x + 2.8, z + 1.5, 0, 1, "Farm", 0.2, "district")
	end,
	function(x, z)
		try("scarecrow", x, z, range(0, 6.28), 1.1, "Farm", 0.5, "district")
		try(pick({ "flowers_yellow", "flowers_white" }), x + 2.2, z - 1.5, 0, 1.2, "Farm", 0.2, "district")
	end,
	function(x, z)
		try("crate", x, z, range(0, 6.28), 1, "Farm", 0.2, "district")
		try("crate", x + 1.6, z + 0.4, range(0, 6.28), 1, "Farm", 0.2, "district")
		try("barrel", x - 0.6, z + 1.8, 0, 1, "Farm", 0.2, "district")
	end,
	function(_x, _z) end,
}
local CORNERS = { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } }
local crossing = 0
for _, x in roadX do
	for _, z in roadZ do
		crossing += 1
		local lampCorner = (crossing % 4) + 1
		for k, c in CORNERS do
			local off = RW / 2 + 3.5
			local cx, cz = x + c[1] * off, z + c[2] * off
			if k == lampCorner then
				local lx, lz = x + c[1] * (RW / 2 + 1.3), z + c[2] * (RW / 2 + 1.3)
				if free(lx, lz, 0.6, 0.2, "district") then
					put("lamp_post", lx, lz, armYaw(lx, lz, x, z), 1, "Lamps")
				end
			else
				pick(KITS)(cx, cz)
			end
		end
	end
end

-- Lamps along the roads, alternating sides.
for _, s in roads do
	local dx, dz = s.x1 - s.x0, s.z1 - s.z0
	local length = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / length, dz / length
	local side = 1
	local t = 20
	while t < length - 10 do
		local nx, nz = -uz * side, ux * side
		local off = RW / 2 + 1.3
		local x, z = s.x0 + ux * t + nx * off, s.z0 + uz * t + nz * off
		if not nearCrossing(s, x, z, 14) and free(x, z, 0.6, 0.2, "district") then
			put("lamp_post", x, z, armYaw(x, z, x - nx, z - nz), 1, "Lamps")
		end
		side = -side
		t += 36
	end
end

-- Tree avenues: both sides of the inner roads (one kind of tree per road), and the far side of
-- the ring road behind its fence (the ring's inner verge is too narrow for trees).
for _, s in roads do
	local dx, dz = s.x1 - s.x0, s.z1 - s.z0
	local length = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / length, dz / length
	if isRing(s) then
		local cx, cz = (s.x0 + s.x1) / 2, (s.z0 + s.z1) / 2
		local nx, nz = -uz, ux
		if nx * cx + nz * cz < 0 then
			nx, nz = -nx, -nz -- outward, away from the district's middle
		end
		for t = 0, length, 14 do
			local x, z = s.x0 + ux * t + nx * (RW / 2 + 8.5), s.z0 + uz * t + nz * (RW / 2 + 8.5)
			try(
				pick({ "oak", "oak", "birch" }),
				x,
				z,
				range(0, 6.28),
				range(0.85, 1.05),
				"Farm",
				0.3,
				"country"
			)
		end
	else
		local kind = pick({ "oak", "birch", "oak" })
		for t = 12, length - 12, 16 do
			for _, side in { 1, -1 } do
				local nx, nz = -uz * side, ux * side
				local x, z = s.x0 + ux * t + nx * (RW / 2 + 5), s.z0 + uz * t + nz * (RW / 2 + 5)
				if not nearCrossing(s, x, z, 13) then
					try(kind, x, z, range(0, 6.28), range(0.85, 1.0), "Farm", 0.3, "district")
				end
			end
		end
	end
end

-- The picket fence along the outside of the ring road.
do
	local o = RW / 2 + 1.5
	local x0, x1 = roadX[1] - o, roadX[#roadX] + o
	local z0, z1 = roadZ[1] - o, roadZ[#roadZ] + o
	fenceLine(x0, z0, x1, z0, "Farm", {})
	fenceLine(x0, z1, x1, z1, "Farm", {})
	fenceLine(x0, z0, x0, z1, "Farm", {})
	fenceLine(x1, z0, x1, z1, "Farm", {})
end

-- ------------------------------------------------------------------ the countryside
local TREES = { "pine", "pine", "pine", "oak", "oak", "oak", "birch", "birch" }

-- Orchards: oak rows on a grid, slightly jittered, a cart and crates at the end of the rows.
local function orchard(cx: number, cz: number, cols: number, rows: number, yaw: number)
	local c, sn = math.cos(yaw), math.sin(yaw)
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local lx, lz = (i - (cols - 1) / 2) * 8, (j - (rows - 1) / 2) * 8
			local x, z = cx + lx * c + lz * sn + range(-0.6, 0.6), cz - lx * sn + lz * c + range(-0.6, 0.6)
			try("oak", x, z, range(0, 6.28), range(0.72, 0.82), "Nature", 0.2, "country")
		end
	end
	local ex, ez = cx + ((cols + 1) / 2 * 8) * c, cz - ((cols + 1) / 2 * 8) * sn
	try("cart", ex, ez, yaw, 1.1, "Nature", 0.5, "country")
	try("crate", ex + 3, ez + 2, 0, 1, "Nature", 0.2, "country")
end
orchard(420, 60, 7, 9, 0)
orchard(-420, -60, 7, 9, 0)
orchard(-120, 420, 10, 5, 0)
orchard(140, -430, 10, 5, 0)

-- A berry field: berry bushes in close rows.
for i = 0, 11 do
	for j = 0, 5 do
		try("berry_bush", 330 + i * 3.6, 330 + j * 4.5, 0, 0.9, "Nature", -0.6, "country")
	end
end

-- A hay meadow: haystacks and bales on the open grass.
scatter(
	{ "haystack", "hay_bale", "hay_bale" },
	16,
	{ minX = -470, maxX = -330, minZ = 330, maxZ = 430 },
	"Nature",
	0.9,
	1.2,
	4,
	"country"
)

-- A country pond with a windmill beside it.
put("pond", 360, -330, math.rad(-20), 1.5, "Nature", "rect")
try("windmill", 396, -364, faceYaw(396, -364, 360, -330), 1.2, "Nature", 2, "country")
for _, b in { { 342, -318 }, { 372, -312 } } do
	try("bench", b[1], b[2], faceYaw(b[1], b[2], 360, -330), 1.1, "Nature", 0.5, "country")
end

--[[
	Groves: trees grow in clumps, not evenly sprinkled (an even sprinkle over a wide belt reads
	as an empty meadow). Each grove picks a centre in the countryside and packs trees round it,
	with bushes, mushrooms and a fallen log in its undergrowth.
]]
local COUNTRY = { minX = -WORLD_RADIUS, maxX = WORLD_RADIUS, minZ = -WORLD_RADIUS, maxZ = WORLD_RADIUS }
local function groves(count: number, trees: number, spread: number)
	local made, tries = 0, 0
	while made < count and tries < count * 40 do
		tries += 1
		local gx, gz = range(COUNTRY.minX, COUNTRY.maxX), range(COUNTRY.minZ, COUNTRY.maxZ)
		if free(gx, gz, 4, 2, "country") then
			made += 1
			local planted = 0
			for _ = 1, trees * 6 do
				if planted >= trees then
					break
				end
				-- the average of two draws: denser in the middle of the grove
				local x = gx + (range(-spread, spread) + range(-spread, spread)) / 2
				local z = gz + (range(-spread, spread) + range(-spread, spread)) / 2
				local name, scale = pick(TREES), range(0.85, 1.35)
				if free(x, z, radiusOf[name] * scale, 0.6, "country") then
					put(name, x, z, range(0, 2 * math.pi), scale, "Nature")
					planted += 1
				end
			end
			local floor = { minX = gx - spread, maxX = gx + spread, minZ = gz - spread, maxZ = gz + spread }
			scatter({ "bush", "berry_bush" }, 3, floor, "Nature", 0.8, 1.3, 0.5, "country")
			scatter({ "mushroom" }, 3, floor, "Nature", 0.8, 1.6, 0.3, "country")
			scatter({ "log", "rock_medium" }, 1, floor, "Nature", 0.9, 1.3, 0.5, "country")
		end
	end
end
groves(34, 13, 26)
scatter(TREES, 60, COUNTRY, "Nature", 0.85, 1.3, 2, "country") -- strays between the groves
scatter({ "rock_medium", "rock_large" }, 24, COUNTRY, "Nature", 0.8, 1.4, 1, "country")
scatter({ "bush", "berry_bush" }, 40, COUNTRY, "Nature", 0.8, 1.2, 2, "country")
scatter({ "rock_small" }, 50, COUNTRY, "Nature", 0.8, 1.6, 1, "country")
scatter(
	{ "flowers_yellow", "flowers_pink", "flowers_white" },
	160,
	COUNTRY,
	"Nature",
	0.9,
	1.5,
	0.6,
	"country"
)
scatter({ "grass_tuft" }, 160, COUNTRY, "Nature", 0.8, 1.6, 0.4, "country")
scatter({ "scarecrow" }, 3, COUNTRY, "Nature", 1, 1.15, 3, "country")

-- A few flowers and tufts in the verges between the farms.
scatter(
	{ "flowers_yellow", "flowers_white", "grass_tuft", "grass_tuft" },
	120,
	OUTER,
	"Farm",
	0.9,
	1.3,
	0.4,
	"district"
)

-- ------------------------------------------------------------------ backdrop hills
local HILLS = 20
for k = 0, HILLS - 1 do
	local a = k / HILLS * 2 * math.pi + range(-0.06, 0.06)
	local r = range(1000, 1080)
	put(
		pick({ "hill_a", "hill_b", "hill_c" }),
		math.cos(a) * r,
		math.sin(a) * r,
		range(0, 2 * math.pi),
		range(0.85, 1.15),
		"Backdrop",
		false
	)
end

-- ------------------------------------------------------------------ write
fs.writeFile(OUT, roblox.serializeModel({ map }))
local total, parts = 0, 0
for _, n in counts do
	total += n
end
for _, d in map:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
local names = {}
for name, n in counts do
	table.insert(names, string.format("%s %d", name, n))
end
table.sort(names)
print(string.format("%s: %d props, %d MeshParts", OUT, total, parts))
print("  " .. table.concat(names, ", "))
