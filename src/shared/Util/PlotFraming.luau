--!strict
--[[
	PlotFraming
	===========
	Pure numbers-only math for Control Mode (Client.Controllers.ControlModeController):
	"am I standing on my plot?" and "where must the bird's-eye camera be so the whole field
	fits on screen next to the terminal?". No Roblox datatypes, so the offline tests cover it.

	PLOT GEOMETRY (matches Server.Services.GridService)
	  Tile (x, y) has its top-centre at  origin + (x * pitch, 0, -y * pitch).
	  The camera frames grid columns 0 .. n-1 and rows -1 .. n-1 (the field plus the station
	  row with the Charging Station and the Factory).
]]

local PlotFraming = {}

--[[
	Point-in-box test in the box's OWN space (the caller converts the world point with
	zone.CFrame:PointToObjectSpace). `margin` grows the box on every side; Control Mode uses a
	margin only while the player is already inside, so walking along the edge never flickers
	(hysteresis: enter at the edge, leave only `margin` studs past it).
]]
function PlotFraming.inside(
	localX: number,
	localY: number,
	localZ: number,
	sizeX: number,
	sizeY: number,
	sizeZ: number,
	margin: number
): boolean
	return math.abs(localX) <= sizeX / 2 + margin
		and math.abs(localY) <= sizeY / 2 + margin
		and math.abs(localZ) <= sizeZ / 2 + margin
end

-- World X/Z of the centre of the framed area (field + station row) of a plot.
function PlotFraming.center(
	originX: number,
	originZ: number,
	gridSize: number,
	pitch: number
): (number, number)
	local x = originX + (gridSize - 1) / 2 * pitch
	-- rows -1 .. n-1 -> the middle row is (n - 2) / 2; grid +y is world -Z
	local z = originZ - (gridSize - 2) / 2 * pitch
	return x, z
end

-- Width (world X) and depth (world Z) of the framed area in studs.
function PlotFraming.extent(gridSize: number, pitch: number): (number, number)
	return gridSize * pitch, (gridSize + 1) * pitch
end

--[[
	Camera distance (along the view direction) and sideways shift for the bird's-eye view.

	  gridSize, pitch  plot size in tiles and studs between tile centres
	  fovDeg           Camera.FieldOfView (Roblox's FOV is VERTICAL)
	  aspect           viewport width / height
	  leftReserve      fraction of the screen width on the left kept free for the terminal
	  margin           >= 1, breathing room around the field (1.12 = 12 %)
	  viewAngleDeg     90 = looking straight down; smaller values tilt the view

	Returns (distance, shiftX):
	  distance  how far the camera must be from the field centre so the area fits both
	            vertically (whole screen height) and horizontally (the part of the screen
	            right of the terminal)
	  shiftX    how many studs to move the camera towards -X so the field appears centred
	            in that free area instead of in the middle of the screen
]]
function PlotFraming.solve(
	gridSize: number,
	pitch: number,
	fovDeg: number,
	aspect: number,
	leftReserve: number,
	margin: number,
	viewAngleDeg: number?
): (number, number)
	local width, depth = PlotFraming.extent(gridSize, pitch)
	local angle = math.rad(math.clamp(viewAngleDeg or 90, 30, 90))
	local tanHalf = math.tan(math.rad(math.clamp(fovDeg, 1, 120)) / 2)
	local safeAspect = math.max(aspect, 0.1)
	local usable = math.clamp(1 - leftReserve, 0.2, 1)

	-- A tilted camera sees the ground foreshortened by sin(angle).
	local halfDepth = depth * math.sin(angle) / 2 * margin
	local halfWidth = width / 2 * margin

	local distanceVertical = halfDepth / tanHalf
	local distanceHorizontal = halfWidth / (tanHalf * safeAspect * usable)
	local distance = math.max(distanceVertical, distanceHorizontal)

	-- At that distance the whole screen is 2 * distance * aspect * tanHalf studs wide; moving
	-- the field's centre right by leftReserve / 2 of the screen centres it in the free part.
	local shiftX = leftReserve * distance * safeAspect * tanHalf
	return distance, shiftX
end

--[[
	The nearest point just OUTSIDE a box, in the box's own space (X/Z only): across the
	closest side, `clearance` studs past it. PlotGuardService uses it to put a guest back out
	of someone else's plot by the shortest way.
]]
function PlotFraming.exitPoint(
	x: number,
	z: number,
	sizeX: number,
	sizeZ: number,
	clearance: number
): (number, number)
	local halfX, halfZ = sizeX / 2, sizeZ / 2
	if halfX - math.abs(x) <= halfZ - math.abs(z) then
		return (if x >= 0 then 1 else -1) * (halfX + clearance), z
	end
	return x, (if z >= 0 then 1 else -1) * (halfZ + clearance)
end

return PlotFraming
