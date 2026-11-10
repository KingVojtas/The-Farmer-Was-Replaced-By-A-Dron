--!strict
--[[
	GridService
	===========
	Owns every player's plot: the field tiles, the off-field stations and the drone's
	authoritative state. The server NEVER animates anything - it publishes state as Instance
	attributes and each client renders and tweens it (Client.Controllers.PlotRenderer). That
	keeps movement smooth for every viewer and costs one attribute change per action instead of
	a CFrame replication every frame.

	COORDINATES (Progression.Field)
	  Field tiles are (0..size-1, 0..size-1); x grows to the right, y grows "up" (away from the
	  station row). Stations sit below row 0: Charging Station (0, -1), Factory (1, -1).
	  Tile (0, 0) has a FIXED world position, so Grid Expansion research can grow the field
	  (GridService:Resize) without moving a single existing crop.

	FIELD SIZE comes from the Tech Tree (Tech.stats(unlocks).gridSize) - never from the client.

	PUBLISHED ATTRIBUTES
	  Plot model : OwnerUserId, Index, Size, Pitch, Origin (Vector3, top-center of tile 0,0),
	               DroneX / DroneY (numbers), Drone (Vector3 x, y, 0), DroneSerial,
	               DroneMoveTime, plus Remote DroneMoved (index, x, y, duration).
	               Battery, BatteryMax, Water, WaterMax, Cargo, CargoMax, DronePaint, DroneHat
	  Tile part  : X, Y, State ("empty"|"planted"|"growing"|"ready"), Crop, Watered,
	               Progress (0..1, 10 % steps)
	  Station    : Kind ("charger"|"factory"), X, Y

	ZONE
	  Every plot model has an invisible part named "Zone" (attribute PlotZone = true) that
	  covers the whole plot base (field, stations, walkway) and ZONE_HEIGHT studs of air above
	  it. It never collides, touches or answers queries; the client only reads its CFrame and
	  Size to detect "standing on my plot" (Client.Controllers.ControlModeController). It is
	  resized together with the base, so it grows with Grid Expansion.

	GROWTH (Progression.Growth, shared with simulate())
	  Bare soil regrows wild grass after Grass.RegrowDelay seconds; crops grow by weather,
	  water and boosts. Tile states live for the session only; currencies, cargo and research
	  are saved.
]]

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local NetService = require(script.Parent.NetService)
local CosmeticConfig = require(ReplicatedStorage.Shared.Config.CosmeticConfig)
local CropConfig = require(ReplicatedStorage.Shared.Config.CropConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local IconConfig = require(ReplicatedStorage.Shared.Config.IconConfig)
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Progression = script.Parent.Parent.Progression
local Economy = require(Progression.Economy)
local Field = require(Progression.Field)
local Growth = require(Progression.Growth)
local FieldSave = require(Progression.FieldSave)
local DataService = require(script.Parent.DataService)
local WeatherService = require(script.Parent.WeatherService)

export type TileState = Growth.TileState

export type Tile = Growth.TileData & {
	part: BasePart,
	shownProgress: number,
}

export type Drone = {
	x: number,
	y: number,
	battery: number,
	water: number,
}

export type Plot = {
	index: number,
	owner: Player,
	size: number,
	model: Model,
	origin: Vector3,
	tiles: { Tile },
	drone: Drone,
	destroyed: boolean,
	base: BasePart,
	sign: BasePart,
	signLabel: TextLabel,
	zone: BasePart,
	barriers: { BasePart }, -- 4 invisible walls around the Zone (PlotGuardService)
}

local GRID = GameConfig.Grid
local STATIONS = GameConfig.Stations :: { [string]: { x: number, y: number, name: string } }
local PITCH = GRID.TileSize + GRID.TileGap
local BASE_THICKNESS = 1
local BASE_TOP = BASE_THICKNESS -- the base sits on y = 0 (top of a standard Baseplate)
local VIP_COLOR = Color3.fromRGB(255, 214, 102)
local ZONE_HEIGHT = 30 -- studs of air above the plot that still count as "on the plot"
local ZONE_MARGIN = 1 -- studs the zone extends past the base on every side
local COLLISION = GameConfig.Collision
local GUARD = GameConfig.PlotGuard

local GridService = {}

local plotsByPlayer: { [Player]: Plot } = {}
local plotsByIndex: { [number]: Plot } = {}
local plotsFolder: Folder

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- World position of the top-center of any cell (tile or station) of a plot.
local function cellTop(origin: Vector3, x: number, y: number): Vector3
	return origin + Vector3.new(x * PITCH, 0, -y * PITCH)
end

local function plotCenter(index: number): Vector3
	local col = (index - 1) % GRID.PlotsPerRow
	local row = math.floor((index - 1) / GRID.PlotsPerRow)
	local x = (col - (GRID.PlotsPerRow - 1) / 2) * GRID.PlotSpacing
	local z = GRID.PlotRowOffset + row * GRID.PlotSpacing
	return Vector3.new(x, 0, z)
end

local function makePart(
	name: string,
	size: Vector3,
	position: Vector3,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function addLabel(parent: BasePart, text: string, offsetY: number): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Label"
	gui.Size = UDim2.fromOffset(220, 40)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 140
	gui.AlwaysOnTop = false
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	gui.Parent = parent
	return label
end

local function publishTile(tile: Tile)
	local part = tile.part
	part:SetAttribute("State", tile.state)
	part:SetAttribute("Crop", tile.crop or "")
	part:SetAttribute("Watered", tile.watered)
	local shown = math.floor(tile.progress * 10) / 10
	tile.shownProgress = shown
	part:SetAttribute("Progress", shown)
end

local function publishProgress(tile: Tile)
	local shown = math.floor(tile.progress * 10) / 10
	if shown ~= tile.shownProgress then
		tile.shownProgress = shown
		tile.part:SetAttribute("Progress", shown)
	end
end

function GridService:GetStats(player: Player): Tech.DroneStats
	local data = DataService:GetData(player)
	return Tech.stats(if data ~= nil then data.techUnlocks else {})
end

-- Pushes the drone's state to the plot attributes (clients render from these).
function GridService:PublishDrone(plot: Plot)
	if plot.destroyed then
		return
	end
	local stats = GridService:GetStats(plot.owner)
	local data = DataService:GetData(plot.owner)
	local model = plot.model
	model:SetAttribute("DroneX", plot.drone.x)
	model:SetAttribute("DroneY", plot.drone.y)
	model:SetAttribute("Drone", Vector3.new(plot.drone.x, plot.drone.y, 0))
	model:SetAttribute("Battery", math.floor(plot.drone.battery))
	model:SetAttribute("BatteryMax", stats.batteryCapacity)
	model:SetAttribute("Water", plot.drone.water)
	model:SetAttribute("WaterMax", stats.waterCapacity)
	model:SetAttribute("Cargo", if data ~= nil then Economy.cargoTotal(data) else 0)
	model:SetAttribute("CargoMax", stats.cargoCapacity)
end

-- Publishes the equipped drone cosmetics (validated ids only; see CosmeticService).
function GridService:PublishCosmetics(player: Player)
	local plot = plotsByPlayer[player]
	local data = DataService:GetData(player)
	if plot == nil or data == nil then
		return
	end
	local equipped = data.cosmetics.equipped
	for _, slot in CosmeticConfig.Slots do
		local id = equipped[slot]
		local item = if id ~= nil then CosmeticConfig.ById[id] else nil
		if item == nil or item.slot ~= slot then
			id = CosmeticConfig.Defaults[slot]
		end
		plot.model:SetAttribute(if slot == "paint" then "DronePaint" else "DroneHat", id)
	end
end

-- VIP shows as a crown icon above the name and gold trim on the sign post (client dressing
-- reads the OwnerVip attribute), never as a text prefix. It only comes from the server-side
-- Pass_VIP flag.
local function refreshSign(plot: Plot)
	local vip = plot.owner:GetAttribute("Pass_VIP") == true
	plot.signLabel.Text = plot.owner.DisplayName .. "'s Farm"
	plot.signLabel.TextColor3 = if vip then VIP_COLOR else Color3.new(1, 1, 1)
	plot.model:SetAttribute("OwnerVip", vip)
	local gui = plot.signLabel.Parent
	if gui == nil then
		return
	end
	local crown = gui:FindFirstChild("Crown")
	if crown == nil and vip then
		local label = Instance.new("TextLabel")
		label.Name = "Crown"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.fromScale(0.5, 0)
		label.Size = UDim2.fromOffset(30, 30)
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Text = IconConfig.get("vip_crown").emoji
		label.Parent = gui
		crown = label
	end
	if crown ~= nil and crown:IsA("GuiObject") then
		crown.Visible = vip
	end
end

local function newTilePart(plot: Plot, x: number, y: number): Tile
	local top = cellTop(plot.origin, x, y)
	local part = makePart(
		string.format("Tile_%d_%d", x, y),
		Vector3.new(GRID.TileSize, GRID.TileHeight, GRID.TileSize),
		top - Vector3.new(0, GRID.TileHeight / 2, 0),
		rgb(CropConfig.SoilColor),
		Enum.Material.Ground
	)
	part.CollisionGroup = COLLISION.Tiles -- characters walk on the Base, never on a farm's tiles
	part:SetAttribute("X", x)
	part:SetAttribute("Y", y)
	local data = Growth.newTile(x, y, GameConfig.Grass.NewTilesGrown)
	local tile: Tile = data :: any
	tile.part = part
	tile.shownProgress = 0
	publishTile(tile)
	part.Parent = plot.model
	return tile
end

-- Sizes the base, sign and field metadata for the plot's current size.
local function layoutPlot(plot: Plot)
	local size = plot.size
	-- Base covers rows y = -2 (walkway) .. size-1 and columns 0 .. size-1 (+ margin).
	local width = size * PITCH + 4
	local depth = (size + 2) * PITCH + 4
	local centerX = plot.origin.X + (size - 1) * PITCH / 2
	local centerZ = plot.origin.Z + (3 - size) * PITCH / 2
	plot.base.Size = Vector3.new(width, BASE_THICKNESS, depth)
	plot.base.Position = Vector3.new(centerX, BASE_THICKNESS / 2, centerZ)
	-- The client-side "on my plot" box: the base footprint + margin, from the ground up.
	plot.zone.Size = Vector3.new(width + 2 * ZONE_MARGIN, ZONE_HEIGHT, depth + 2 * ZONE_MARGIN)
	plot.zone.Position = Vector3.new(centerX, ZONE_HEIGHT / 2, centerZ)
	-- Barrier walls just outside the Zone: north, south, east, west.
	local zoneW = width + 2 * ZONE_MARGIN
	local zoneD = depth + 2 * ZONE_MARGIN
	local h = GUARD.BarrierHeight
	local walls = plot.barriers
	walls[1].Size = Vector3.new(zoneW + 2, h, 1)
	walls[1].Position = Vector3.new(centerX, h / 2, centerZ - zoneD / 2 - 0.5)
	walls[2].Size = Vector3.new(zoneW + 2, h, 1)
	walls[2].Position = Vector3.new(centerX, h / 2, centerZ + zoneD / 2 + 0.5)
	walls[3].Size = Vector3.new(1, h, zoneD)
	walls[3].Position = Vector3.new(centerX + zoneW / 2 + 0.5, h / 2, centerZ)
	walls[4].Size = Vector3.new(1, h, zoneD)
	walls[4].Position = Vector3.new(centerX - zoneW / 2 - 0.5, h / 2, centerZ)
	plot.sign.Position = Vector3.new(centerX, 12, plot.origin.Z - size * PITCH)
	plot.model:SetAttribute("Size", size)
end

local function buildPlot(index: number, player: Player, size: number): Plot
	local center = plotCenter(index)
	-- Tile (0,0) top-center is fixed so that even a MaxSize field stays centred on the plot.
	local half = (GRID.MaxSize - 1) / 2
	local origin = center + Vector3.new(-half * PITCH, BASE_TOP + GRID.TileHeight, half * PITCH)

	local model = Instance.new("Model")
	model.Name = "Plot_" .. index
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic

	-- Plot grass #4E6B3A (docs/ART_BIBLE.md §1.4): the 0.4-stud gutters between tiles show it.
	local base = makePart("Base", Vector3.one, origin, Color3.fromRGB(78, 107, 58), Enum.Material.Grass)
	base.Parent = model
	model.PrimaryPart = base

	local sign = makePart("OwnerSign", Vector3.one, origin, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	sign.Transparency = 1
	sign.CanCollide = false
	sign.CanQuery = false
	local signLabel = addLabel(sign, player.DisplayName .. "'s Farm", 0)
	sign.Parent = model

	-- Invisible, inert detection box (see ZONE in the header); sized by layoutPlot.
	local zone = makePart("Zone", Vector3.one, origin, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	zone.Transparency = 1
	zone.CanCollide = false
	zone.CanTouch = false
	zone.CanQuery = false
	zone.CastShadow = false
	zone.Locked = true
	zone:SetAttribute("PlotZone", true)
	zone.Parent = model

	-- Guest barrier (see PlotGuardService): 4 invisible walls in the PlotBarrier group, which
	-- collides with characters only. The OWNER's client turns its own walls' CanCollide off
	-- locally (characters are simulated by their own client), so only guests are stopped.
	-- AllowVisitors = true opens them (and the server eject skips this plot).
	local barriers: { BasePart } = {}
	for side = 1, 4 do
		local wall =
			makePart("Barrier", Vector3.one, origin, Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		wall.Transparency = 1
		wall.CanQuery = false -- cameras, raycasts and the spawn check ignore it
		wall.CanTouch = false
		wall.CastShadow = false
		wall.Locked = true
		wall.CollisionGroup = COLLISION.Barrier
		wall:SetAttribute("PlotBarrier", side)
		wall.Parent = model
		barriers[side] = wall
	end
	model:SetAttribute("AllowVisitors", false)
	model:GetAttributeChangedSignal("AllowVisitors"):Connect(function()
		local open = model:GetAttribute("AllowVisitors") == true
		for _, wall in barriers do
			wall.CanCollide = not open
		end
	end)

	local stats = GridService:GetStats(player)
	local charger = GameConfig.Stations.charger
	local plot: Plot = {
		index = index,
		owner = player,
		size = size,
		model = model,
		origin = origin,
		tiles = {},
		drone = { x = charger.x, y = charger.y, battery = stats.batteryCapacity, water = stats.waterCapacity },
		destroyed = false,
		base = base,
		sign = sign,
		signLabel = signLabel,
		zone = zone,
		barriers = barriers,
	}

	for y = 0, size - 1 do
		for x = 0, size - 1 do
			plot.tiles[Field.index(size, x, y)] = newTilePart(plot, x, y)
		end
	end

	-- Stations (anchored, static; the drone hovers above them).
	for kind, station in STATIONS do
		local top = cellTop(origin, station.x, station.y)
		local part: Part
		if kind == "factory" then
			part = makePart(
				"Station_" .. kind,
				Vector3.new(GRID.TileSize, 3, GRID.TileSize),
				top + Vector3.new(0, 1.5 - GRID.TileHeight, 0),
				Color3.fromRGB(70, 76, 88),
				Enum.Material.DiamondPlate
			)
			addLabel(part, "FACTORY", 4)
		else
			part = makePart(
				"Station_" .. kind,
				Vector3.new(GRID.TileSize, 0.4, GRID.TileSize),
				top + Vector3.new(0, 0.2 - GRID.TileHeight, 0),
				Color3.fromRGB(60, 200, 255),
				Enum.Material.Neon
			)
			addLabel(part, "CHARGER", 3)
		end
		part:SetAttribute("Kind", kind)
		part:SetAttribute("X", station.x)
		part:SetAttribute("Y", station.y)
		part.Parent = model
	end

	layoutPlot(plot)
	refreshSign(plot)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("Index", index)
	model:SetAttribute("Pitch", PITCH)
	model:SetAttribute("Origin", origin)
	model:SetAttribute("DroneMoveTime", GameConfig.Drone.ActionTimes.move)
	model:SetAttribute("DroneSerial", 0)
	GridService:PublishDrone(plot)
	model.Parent = plotsFolder
	return plot
end

local function spawnPosition(plot: Plot, offsetCells: number): CFrame
	-- On the walkway (y = -2) in front of the field, facing it.
	local x = (plot.size - 1) / 2 + offsetCells
	local feet = cellTop(plot.origin, x, -2) + Vector3.new(0, 3, 0)
	local lookAt = cellTop(plot.origin, x, plot.size - 1) + Vector3.new(0, 3, 0)
	return CFrame.lookAt(feet, lookAt)
end

-- Is another character (any Humanoid model, however big) standing on this spawn spot?
local function spawnOccupied(spot: CFrame, character: Model): boolean
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	for _, part in Workspace:GetPartBoundsInBox(spot, Vector3.new(4, 5, 4), params) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil then
			return true
		end
	end
	return false
end

local function moveCharacterToPlot(player: Player, character: Model)
	local plot = plotsByPlayer[player]
	if plot == nil then
		return
	end
	local root = character:WaitForChild("HumanoidRootPart", 5)
	if root == nil or plot.destroyed then
		return
	end
	task.wait() -- let the default spawn finish placing the character first
	-- The centre walkway cell, or the nearest free one (+-1, +-2 tiles) if someone stands there.
	local spot = spawnPosition(plot, 0)
	for _, offset in { 0, 1, -1, 2, -2 } do
		local cell = (plot.size - 1) / 2 + offset
		if cell >= 0 and cell <= plot.size - 1 then
			local candidate = spawnPosition(plot, offset)
			if not spawnOccupied(candidate, character) then
				spot = candidate
				break
			end
		end
	end
	character:PivotTo(spot)
	local shield = Instance.new("ForceField")
	shield.Name = "SpawnShield"
	shield.Parent = character
	Debris:AddItem(shield, GUARD.SpawnShieldSeconds)
end

local function createPlot(player: Player)
	if plotsByPlayer[player] ~= nil or player.Parent ~= Players then
		return
	end
	local index = 1
	while plotsByIndex[index] ~= nil do
		index += 1
	end
	local plot = buildPlot(index, player, GridService:GetStats(player).gridSize)
	plotsByIndex[index] = plot
	plotsByPlayer[player] = plot
	GridService:PublishCosmetics(player)
	WeatherService:AttachPlot(player, plot.model)
	-- The saved field comes back (no tick replay; long absences snap crops to grown).
	local data = DataService:GetData(player)
	if data ~= nil then
		local function tileAt(x: number, y: number): Growth.TileData?
			return GridService:GetTile(plot, x, y) :: any
		end
		for _, tile in FieldSave.restore(data.field, tileAt, os.time()) do
			publishTile(tile :: any)
		end
		for _, ripe in Growth.settleSquares(plot.size, tileAt) do
			publishTile(ripe :: any)
		end
	end
	player:GetAttributeChangedSignal("Pass_VIP"):Connect(function()
		if not plot.destroyed then
			refreshSign(plot)
		end
	end)
	if player.Character ~= nil then
		task.spawn(moveCharacterToPlot, player, player.Character)
	end
end

local function removePlot(player: Player)
	local plot = plotsByPlayer[player]
	if plot == nil then
		return
	end
	plot.destroyed = true -- running programs see this and stop
	WeatherService:DetachPlot(player)
	plotsByPlayer[player] = nil
	plotsByIndex[plot.index] = nil
	plot.model:Destroy()
end

local function growthTick(dt: number)
	for player, plot in plotsByPlayer do
		local weather = WeatherService:GetFor(player) -- every plot has its own weather
		local growthBoost = DataService:GetBoostMultipliers(player)
		local env: Growth.Env = { weather = weather, growthBoost = growthBoost }
		for _, tile in plot.tiles do
			local change = Growth.advance(tile, dt, env)
			if change.state or change.watered then
				publishTile(tile)
			elseif change.progress then
				publishProgress(tile)
			end
		end
		-- Square crops (pumpkins) ripen together once their 2 x 2 is complete and grown.
		for _, ripe in
			Growth.settleSquares(plot.size, function(x: number, y: number): Growth.TileData?
				return GridService:GetTile(plot, x, y) :: any
			end)
		do
			publishTile(ripe :: any)
		end
	end
end

function GridService:Init()
	local existing = Workspace:FindFirstChild("Plots")
	if existing ~= nil then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Plots"
	folder.Parent = Workspace
	plotsFolder = folder

	-- Every save carries the current field.
	DataService:OnBeforeSave(function(player: Player, data: any)
		local plot = plotsByPlayer[player]
		if plot ~= nil and not plot.destroyed then
			data.field = FieldSave.snapshot(plot.tiles :: any, os.time())
		end
	end)

	-- Connected in Init so no ProfileLoaded can be missed.
	DataService.ProfileLoaded:Connect(function(player: Player)
		createPlot(player)
	end)
end

function GridService:Start()
	for _, player in DataService:GetLoadedPlayers() do
		createPlot(player)
	end

	local function hookCharacter(player: Player)
		player.CharacterAdded:Connect(function(character: Model)
			moveCharacterToPlot(player, character)
		end)
	end
	Players.PlayerAdded:Connect(hookCharacter)
	for _, player in Players:GetPlayers() do
		hookCharacter(player)
	end
	Players.PlayerRemoving:Connect(removePlot)

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(GRID.GrowthTickSeconds)
			local now = os.clock()
			local ok, err = pcall(growthTick :: any, math.min(now - last, 1))
			if not ok then
				warn("[GridService] growth tick failed: " .. tostring(err))
			end
			last = now
		end
	end)
end

-------------------------------------------------------------------------------
-- Queries and mutations used by LiveWorld (all synchronous, never yield)
-------------------------------------------------------------------------------

-- Every live plot (PlotGuardService's eject sweep).
function GridService:GetPlots(): { Plot }
	local list: { Plot } = {}
	for _, plot in plotsByPlayer do
		table.insert(list, plot)
	end
	return list
end

function GridService:GetPlot(player: Player): Plot?
	return plotsByPlayer[player]
end

-- Updates the published capacities after research (battery charge itself is unchanged).
function GridService:RefreshStats(player: Player)
	local plot = plotsByPlayer[player]
	if plot ~= nil then
		GridService:PublishDrone(plot)
	end
end

--[[
	Grows the field to the researched size. Existing tiles (and their crops) stay exactly
	where they are; new tiles start with grown wild grass. Never shrinks a live field.
]]
function GridService:Resize(player: Player): boolean
	local plot = plotsByPlayer[player]
	if plot == nil or plot.destroyed then
		return false
	end
	local newSize = GridService:GetStats(player).gridSize
	if newSize <= plot.size then
		return false
	end
	local oldSize = plot.size
	local tiles: { Tile } = table.create(newSize * newSize)
	for y = 0, newSize - 1 do
		for x = 0, newSize - 1 do
			if x < oldSize and y < oldSize then
				tiles[Field.index(newSize, x, y)] = plot.tiles[Field.index(oldSize, x, y)]
			else
				tiles[Field.index(newSize, x, y)] = newTilePart(plot, x, y)
			end
		end
	end
	plot.tiles = tiles
	plot.size = newSize
	layoutPlot(plot)
	GridService:PublishDrone(plot)
	return true
end

function GridService:GetStation(plot: Plot): string?
	return Field.stationAt(plot.drone.x, plot.drone.y)
end

function GridService:GetTile(plot: Plot, x: number, y: number): Tile?
	if not Field.inField(plot.size, x, y) then
		return nil
	end
	return plot.tiles[Field.index(plot.size, x, y)]
end

function GridService:CanMove(plot: Plot, dx: number, dy: number): (boolean, string?)
	return Field.canMove(plot.size, plot.drone.x, plot.drone.y, dx, dy)
end

function GridService:MoveDrone(plot: Plot, dx: number, dy: number, duration: number)
	plot.drone.x += dx
	plot.drone.y += dy
	plot.model:SetAttribute("DroneMoveTime", duration) -- set BEFORE Drone so the client tween uses it
	GridService:PublishDrone(plot)
	local serial = (plot.model:GetAttribute("DroneSerial") :: number?) or 0
	plot.model:SetAttribute("DroneSerial", serial + 1)
	-- Remotes replicate even when Vector attributes stay silent. Fire after attributes so a
	-- client that re-reads the plot on this event sees the new cell.
	NetService:FireAll("DroneMoved", plot.index, plot.drone.x, plot.drone.y, duration)
end

function GridService:PlantTile(tile: Tile, cropId: string)
	Growth.plant(tile, cropId, WeatherService:GetCurrent())
	publishTile(tile)
end

function GridService:WaterTile(tile: Tile)
	tile.watered = true
	tile.part:SetAttribute("Watered", true)
end

function GridService:ClearTile(tile: Tile)
	Growth.clear(tile)
	publishTile(tile)
end

return GridService
