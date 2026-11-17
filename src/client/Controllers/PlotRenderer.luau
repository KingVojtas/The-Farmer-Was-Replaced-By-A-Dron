--!strict
--[[
	PlotRenderer
	============
	Draws every plot's drone, crops and station dressing LOCALLY from the attributes the
	server publishes (see GridService). Nothing here affects gameplay; the server is the
	authority. Art direction: docs/ART_BIBLE.md. Artist models are used when present
	(Visuals.AssetLibrary), otherwise the procedural low-poly shapes below.

	MOVEMENT ENGINE (no physics at all)
	  * Every drone part is Anchored = true, CanCollide/CanQuery/CanTouch = false. No
	    BodyVelocity, no constraints, no welds.
	  * All motion comes from TweenService tweens on value objects:
	      move  (CFrameValue)  - flight between cells, Quad InOut, length = server action time
	      tilt  (NumberValue)  - leans into each move and back (reversing tween)
	      bob   (NumberValue)  - endless gentle hover (reversing, infinite repeat)
	      spin  (NumberValue)  - rotor angle: advanced each frame at 360 / rotorPeriod degrees
	                             per second; rotorPeriod is TWEENED (idle 0.35 s, flying 0.22 s,
	                             limping 0.7 s), so the rotors speed up without restarting
	    YOUR drone's flight feel (ANIM-1), more finite tweens on value objects per move:
	      lift  (NumberValue)  - hop: up 0.25 stud in the first 15 % (Quad Out), glide, then a
	                             Quad InOut settle in the last 20 % (no overshoot)
	      roll  (NumberValue)  - banks up to 8 degrees into a turn (a strafe), reversing like tilt
	      land  (NumberValue)  - studs below the hover height: drops to 1.6 over the charger
	                             pad on a one-step move there, rises again on the next takeoff
	    One RenderStepped connection composes those tweened values into final CFrames and
	    applies them with workspace:BulkMoveTo. It never computes motion itself (except
	    advancing the rotor angle by the tweened period).
	  * Rotation toward the travel direction is part of the `move` tween's target CFrame.
	  * The server publishes DroneX / DroneY (numbers), Drone (Vector3), DroneSerial, and
	    fires RemoteEvent DroneMoved (plot index, x, y, duration). ScriptStatus "line" also
	    re-reads the cell. NEAR plots poll each frame. Any one of these is enough to tween.

	LOD TIERS (pass 7; refreshLod every FX.LodInterval s, distance from the character or the
	camera, whichever is nearer, with FX.TierSlack studs of hysteresis so edges never thrash)
	  NEAR  your own plot ALWAYS, or < FX.NearRadius studs: the full drone (bob / tilt / spin,
	        path ghost, hats), full crops + crop juice, station decor, soil states.
	  MID   < FX.FarRadius studs: a 2-part drone (body + status light) SNAPPED to its cell on
	        each Drone change (no TweenService); one plain part per growing / ready tile
	        (sprouts aren't drawn); soil states set instantly; no particles, no sway, no
	        station decor; fence + sign within FX.DressingRadius.
	  FAR   everything DESTROYED (not hidden: infinite tweens would leak); the server tiles get
	        their own plain look back; only a DronePaint listener (cached for the rebuild)
	        and AncestryChanged stay connected.
	A tier change tears the plot visual down and rebuilds it. Only NEAR drones are composed
	in RenderStepped, and only NEAR drones run infinite tweens (bob, spin, battery blink).
	Debug: set the FxDebugPrint attribute on Workspace.ClientVisuals to true (default false)
	to print near / mid / far, tween and part counts every 2 s.

	COSMETICS
	  Plot attributes DronePaint / DroneHat (validated by the server) recolour the parts tagged
	  with a paint role and attach a hat whose parts join the same pose list.

	DRONE AS A RUNNING PROGRAM (docs/ART_BIBLE.md §4.1.1, decisions in Shared.Util.DroneSignals)
	  Every drone: the neon BatteryBar strip on the spine shows the battery (> 50 % lime, 15-50 %
	  amber, < 15 % red with a slow blink). The visor Eye stays the paint's accent.
	  YOUR drone only: a 16-dot path ghost on the tiles it left (lime, fading over 4 s); a
	  0.15 s tool flash under it for plant / harvest / water, inferred conservatively from tile
	  changes right under it; cyan light + pulsing charger rings on the charger; the factory's
	  slit and lamp work while it is on the factory; a limping move (far slower than normal)
	  flattens the hover bob (bobScale tween) and dims the light.

	PLOT DRESSING (Visuals.PlotDressing): walkway, fence, sign post and station extras; full on
	your plot, fence + sign within FX.DressingRadius studs, nothing farther away.

	CROP JUICE (gameplay readability, not decoration)
	  Attribute changes on a tile are coalesced into one refresh and diffed by
	  Shared.Util.CropTransitions:
	    plant    a seed drops from the drone into the tile (only if the drone is over it)
	    sprout   planted -> growing: pop to 1.08x and settle, 8 leaf bits
	    ready    silhouette cue (pop to 1.12x and settle), matte -> glossy, lime ping (own plot)
	    harvest  6-12 crop-coloured bits (grey/brown if unripe), tile flashes Soil Dry dust
	    water    4-6 cyan-white droplets (when the drone waters; rain only darkens the soil)
	  LOD: full effects only on NEAR plots (your plot and plots within FX.NearRadius); other plots
	  only get the growth tweens. Budgets: <= FX.MaxParticles live particles, one burst per tile
	  at a time, bursts from ONE pooled Attachment per plot folder (emitters cloned from one
	  template, never Enabled). Ready crops on YOUR plot sway (two shared drivers, <= FX.MaxSway
	  crops; angle + speed by weather, WIND) and show a lime dot in Control Mode (hidden above
	  FX.MaxReadyMarkers ready tiles). No lights, no trails.
	  Debug (Workspace.ClientVisuals attributes): FxParticles, FxTweens, FxSwaying,
	  FxReadyMarkers, FxFullPlots. FxSwayNeighbours (default false) lets nearby plots sway
	  too, but never while more than FX.TweenBudget FX tweens are running.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CosmeticConfig = require(ReplicatedStorage.Shared.Config.CosmeticConfig)
local CropConfig = require(ReplicatedStorage.Shared.Config.CropConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local CropTransitions = require(ReplicatedStorage.Shared.Util.CropTransitions)
local DroneSignals = require(ReplicatedStorage.Shared.Util.DroneSignals)
local SoilStates = require(ReplicatedStorage.Shared.Util.SoilStates)
local AssetLibrary = require(script.Parent.Parent.Visuals.AssetLibrary)
local PlotDressing = require(script.Parent.Parent.Visuals.PlotDressing)
local PlotSpace = require(script.Parent.Parent.Visuals.PlotSpace)
local SoilLook = require(script.Parent.Parent.Visuals.SoilLook)
local SoundController = require(script.Parent.SoundController)

local DRONE = GameConfig.Drone
local GRID = GameConfig.Grid
local BOB_HEIGHT = 0.35
local MAX_TILT = math.rad(14)
local FULL = GRID.TileSize * 0.55 -- size of a fully grown crop (studs)

local STEM_COLOR = Color3.fromRGB(88, 150, 66)
local LEAF_COLOR = Color3.fromRGB(96, 170, 72)
local DARK_COLOR = Color3.fromRGB(110, 74, 46)
-- Weather tint (WeatherFxController): Drought leans procedural crops toward dry straw.
local STRAW_COLOR = Color3.fromHex("#C9C27A")
local TINT_FADE = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

-- Crop juice tuning (client only; see CROP JUICE above).
local FX = {
	NearRadius = 80, -- studs to a plot's edge: NEAR (full visuals + crop juice); own plot always
	FarRadius = 140, -- studs: MID up to here, FAR (nothing built) beyond
	TierSlack = 6, -- hysteresis: a plot changes tier only this far past an edge
	DebugPrintEvery = 2, -- seconds between debug count prints (FxDebugPrint attribute)
	MaxParticles = 40, -- live particles at once, all plots together
	MaxQueued = 8, -- bursts waiting per plot (one is emitted per frame)
	MaxSway = 36, -- ready crops swaying at once
	-- Sway angle + speed: WIND (by weather, ANIM-3).
	MaxReadyMarkers = 40, -- more ready tiles than this: the dots hide (they'd be noise)
	TweenBudget = 160, -- above this many running FX tweens, neighbour plots never sway
	LodInterval = 0.25, -- seconds between LOD / sway / marker refreshes
	DroneNear = 1.5, -- cells: seed drops and droplets need the drone this close to the tile
	DressingRadius = 120, -- studs: other plots closer than this get fence + sign post
}

-- Drone program signals (§4.1.1).
local STATUS_COLORS: { [string]: Color3 } = {
	lime = Color3.fromHex("#8CFF5A"),
	amber = Color3.fromHex("#FFB547"),
	red = Color3.fromHex("#FF4D5E"),
	cyan = Color3.fromHex("#3CDCFF"),
}
local ACTION_COLORS: { [string]: Color3 } = {
	plant = Color3.fromHex("#8CFF5A"),
	water = Color3.fromHex("#3CDCFF"),
	harvest = Color3.fromHex("#FFD666"),
}
local GHOST_COUNT = 16
local GHOST_FADE = TweenInfo.new(4, Enum.EasingStyle.Linear)
local TOOL_FLASH = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local STATUS_FADE = TweenInfo.new(0.3)
local STATUS_BLINK = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local RING_PULSE = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
-- Station theater (ANIM-7, your NEAR plot): the charger pad punches when the drone touches
-- down, the rings spin up while the battery is actually rising; a factory deposit makes the
-- hopper tick and the chimney puff. Idle stations stay dark and still.
local RING_PULSE_FAST = TweenInfo.new(0.28, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local PAD_PUNCH = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true) -- 1 -> 1.06 -> 1
local PAD_PUNCH_SCALE = 1.06
local HOPPER_JITTER = TweenInfo.new(0.1 / 6, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 2, true) -- 3 cycles, 0.1 s
local HOPPER_JITTER_STUDS = 0.08
local SMOKE_PUFFS = 3
local LIMP_BOB = 0.25 -- hover bob scale while limping
-- Flight feel (ANIM-1, your NEAR drone; MID drones still snap, neighbours keep the plain tween).
local TAKEOFF_LIFT = 0.25 -- studs of extra height at the top of the hop
local TAKEOFF_PART = 0.15 -- fraction of the move spent lifting off
local SETTLE_PART = 0.2 -- fraction of the move spent settling into the cell (Quad InOut)
local CRUISE_LIFT = 0.4 -- fraction of the hop still held when the settle starts
local MAX_ROLL = math.rad(8) -- bank into a turn (strafe left / right), reversing like the tilt
local ROLL_MIN_TURN = 0.2 -- sin(yaw change) below this is "straight on" (no bank)
local ROTOR_IDLE = 0.35 -- seconds per rotor turn
local ROTOR_FLY = 0.22
local ROTOR_LIMP = 0.7
local ROTOR_EASE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local LAND_HEIGHT = 1.6 -- studs above the charger pad's tile top while docked
local LAND_DROP = DRONE.HoverHeight - LAND_HEIGHT
local LANDED_BOB = 0.3 -- hover bob scale while docked
-- Action body language (ANIM-2, your drone): one pose at a time, a move cancels it.
local PLANT_DIP = 0.8 -- studs; the seed falls during the dip
local PLANT_NOD = math.rad(8)
local PLANT_HALF = 0.14 -- down, then back (0.28 s)
local SCOOP_NOD = math.rad(18) -- ripe harvest: nose-down scoop ...
local SCOOP_DIP = 0.35
local SCOOP_DOWN = 0.18 -- ... then a quick snap back
local SCOOP_BACK = 0.1
local WATER_YAW = math.rad(6) -- +-6 degree wobble, 0.22 s
local WATER_QUARTER = 0.055
local FACTORY_DIP = 0.3 -- a small settle when cargo goes into the factory
local FACTORY_HALF = 0.15
local POSE_RESET = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Stations (ART-6): Neon only for STATE. Idle = dark; lit only while YOUR drone is on them.
local STATION_IDLE = Color3.fromHex("#22343C") -- dark teal-grey rings / pylon light
local PAD_IDLE = Color3.fromHex("#2A3440") -- the charger pad, idle
local FACTORY_GLASS = Color3.fromHex("#24332E") -- dark window glass (no glow)
local LIME = Color3.fromRGB(140, 255, 90) -- ART_BIBLE neon lime #8CFF5A
-- Harvest flash: Soil Dry dust #A98258 (resting dry soil is Soil Dry base, so the flash is lighter).
local SOIL_DUST_FLASH = Color3.fromRGB(169, 130, 88)
local SEED_COLOR = Color3.fromRGB(214, 178, 112)
local SPROUT_PEAK = 1.08
local READY_PEAK = 1.12
local POP_UP = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local POP_SETTLE = TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local SEED_FALL = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local PING = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Growth between Progress ticks (ANIM-3, NEAR plots): ease toward the published size, no
-- overshoot, so a field rises smoothly instead of clicking. MID proxies still snap.
local GROW_LERP = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- Wind on YOUR ready crops (ANIM-3), by the weather your plot sees (PlotSpace.weather):
-- sway angle and half period. Tweened over WIND_FADE, so a weather change never jerks.
local WIND: { [string]: { angle: number, half: number } } = {
	Sunny = { angle = math.rad(2), half = 1.6 },
	Rainy = { angle = math.rad(3.2), half = 1.25 },
	Drought = { angle = math.rad(0.8), half = 2.2 },
}
local WIND_FADE = TweenInfo.new(1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

-- Particle textures that ship with every Roblox client (no upload needed).
local SQUARE_TEXTURE = "rbxasset://textures/particles/SquareParticle.png"
local DROP_TEXTURE = "rbxasset://textures/smallWhiteCircle.png"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"

type BurstKind = {
	lifetime: number, -- seconds; also how long the tile counts as "busy"
	speed: NumberRange,
	spread: number, -- degrees around the emission direction
	direction: Enum.NormalId,
	acceleration: Vector3,
	drag: number,
	size: NumberSequence,
	texture: string,
	lightEmission: number,
	lift: number, -- studs above the tile top the burst starts
	transparency: NumberSequence?, -- overrides the template's fade
}

-- Cargo leaving your drone (ANIM-4): aimed bits, gravity pre-compensated in queueAimed.
local UNLOAD_GRAVITY = 12
local UNLOAD_SPEED_MAX = 30 -- studs / s: a far target (the sign) just sets the direction

local BURSTS: { [string]: BurstKind } = {
	unload = { -- cargo bits flying off your drone (ANIM-4); aimed + speed set per burst
		lifetime = 0.45,
		speed = NumberRange.new(20),
		spread = 10,
		direction = Enum.NormalId.Front,
		acceleration = Vector3.new(0, -UNLOAD_GRAVITY, 0),
		drag = 0,
		size = NumberSequence.new(0.3, 0.12),
		texture = SQUARE_TEXTURE,
		lightEmission = 0.05,
		lift = 0,
	},
	smoke = { -- chimney puffs after a factory deposit (ANIM-7)
		lifetime = 1,
		speed = NumberRange.new(1.5, 2.5),
		spread = 15,
		direction = Enum.NormalId.Top,
		acceleration = Vector3.new(0, 1.5, 0),
		drag = 1,
		size = NumberSequence.new(0.7, 1.8),
		texture = SMOKE_TEXTURE,
		lightEmission = 0,
		lift = 0.3,
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1),
		}),
	},
	biofluid = { -- a couple of biofluid bits rising out of the factory chimney (ANIM-4)
		lifetime = 0.6,
		speed = NumberRange.new(5, 7),
		spread = 8,
		direction = Enum.NormalId.Top,
		acceleration = Vector3.new(0, 3, 0),
		drag = 1,
		size = NumberSequence.new(0.24, 0.06),
		texture = SQUARE_TEXTURE,
		lightEmission = 0.6,
		lift = 0.2,
	},
	leaf = { -- planted -> growing
		lifetime = 0.4,
		speed = NumberRange.new(5, 8),
		spread = 55,
		direction = Enum.NormalId.Top,
		acceleration = Vector3.new(0, -26, 0),
		drag = 2,
		size = NumberSequence.new(0.24, 0.06),
		texture = SQUARE_TEXTURE,
		lightEmission = 0,
		lift = 0.4,
	},
	harvest = { -- ripe: crop colour; unripe: grey/brown
		lifetime = 0.6,
		speed = NumberRange.new(7, 11),
		spread = 40,
		direction = Enum.NormalId.Top,
		acceleration = Vector3.new(0, -30, 0),
		drag = 1.5,
		size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.32),
			NumberSequenceKeypoint.new(0.7, 0.26),
			NumberSequenceKeypoint.new(1, 0.08),
		}),
		texture = SQUARE_TEXTURE,
		lightEmission = 0.05,
		lift = 0.6,
	},
	water = { -- a small splash where the water hits the soil
		lifetime = 0.3,
		speed = NumberRange.new(5, 7),
		spread = 65,
		direction = Enum.NormalId.Top,
		acceleration = Vector3.new(0, -35, 0),
		drag = 0,
		size = NumberSequence.new(0.18, 0.1),
		texture = DROP_TEXTURE,
		lightEmission = 0.35,
		lift = 0.15,
	},
	wash = { -- rotor wash: a puff of dust kicked out under your drone as it lifts off
		lifetime = 0.6,
		speed = NumberRange.new(2, 3.5),
		spread = 85,
		direction = Enum.NormalId.Top,
		acceleration = Vector3.new(0, -1.5, 0),
		drag = 2,
		size = NumberSequence.new(0.6, 1.6),
		texture = SMOKE_TEXTURE,
		lightEmission = 0,
		lift = 0.1,
		transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.55),
			NumberSequenceKeypoint.new(1, 1),
		}),
	},
}
-- Ripe harvest bits per crop shape (6-12: bigger crops burst bigger).
local HARVEST_BITS: { [string]: number } =
	{ grass = 6, stalk = 9, bush = 9, flower = 10, round = 12, tree = 12, cactus = 8 }
local UNRIPE_BITS = 6
local UNRIPE_COLORS = ColorSequence.new(Color3.fromRGB(128, 116, 100), Color3.fromRGB(110, 74, 46))
local LEAF_COLORS = ColorSequence.new(LEAF_COLOR, Color3.fromRGB(150, 220, 100))
local WATER_COLORS = ColorSequence.new(Color3.fromRGB(190, 240, 255), Color3.new(1, 1, 1))
local WASH_COLORS = ColorSequence.new(Color3.fromHex("#A98258")) -- Bible Soil Dry dust
local WASH_PUFF = 3 -- particles per lift-off
-- Cargo colour: the cargo total has no crop breakdown, so hay / crop gold (ANIM-4).
local UNLOAD_COLORS = ColorSequence.new(Color3.fromHex("#C9C27A"), Color3.fromHex("#E8DC9A"))
local BIOFLUID_COLORS = ColorSequence.new(Color3.fromHex("#4DFFB0"), Color3.fromHex("#66CCFF"))
local CHIMNEY_DELAY = 0.3 -- seconds after the hopper bits before the chimney bits rise
local SMOKE_COLORS = ColorSequence.new(Color3.fromHex("#8A8F99"), Color3.fromHex("#5E636C"))
-- Your drone's ground shadow (ART-5): a dark ellipse on the tile top, hidden over stations.
local SHADOW_SIZE = Vector3.new(3.5, 0.05, 3.5)
local SHADOW_COLOR = Color3.fromHex("#0E1218")
local SHADOW_ALPHA = 0.55
local SHADOW_FADE = TweenInfo.new(0.2)
local BEAM_WIDTH = 0.04 -- V-CONTACT height beam (cyan, Control Mode only)
local BEAM_ALPHA = 0.85

type PartPose = { part: BasePart, offset: CFrame, spins: boolean }
type PaintRole = "primary" | "secondary" | "accent"

type DroneVisual = {
	model: Model,
	poses: { PartPose },
	hatPoses: { PartPose },
	paintParts: { { part: BasePart, role: PaintRole } },
	move: CFrameValue,
	tilt: NumberValue,
	bob: NumberValue,
	spin: NumberValue,
	lift: NumberValue, -- takeoff hop, 0..1 of TAKEOFF_LIFT (your drone)
	roll: NumberValue, -- bank, -1..1 of MAX_ROLL (+ = left)
	land: NumberValue, -- studs below the hover height (charger landing)
	rotorPeriod: NumberValue, -- seconds per rotor turn (tweened); render advances `spin` by it
	rotorTarget: number,
	flight: { Tween }, -- this move's finite flight tweens (lift chain, roll, land)
	poseY: NumberValue, -- action body language (ANIM-2): studs (negative = dip)
	posePitch: NumberValue, -- radians, positive = nose down
	poseYaw: NumberValue, -- radians
	pose: { Tween }, -- the current action pose's tweens (one pose at a time)
	cell: Vector2?,
	serial: number?, -- DroneSerial of `cell` (only a newer serial moves the drone, BUG-05)
	moveTween: Tween?,
	bobScale: NumberValue, -- 1 = normal hover, LIMP_BOB while limping (tweened)
	status: BasePart, -- the battery / state light
	statusKey: string,
	statusBlink: Tween?,
	limping: boolean,
	ghosts: { Part }, -- path ghost pool (own drone only, <= GHOST_COUNT)
	ghostNext: number,
	simple: boolean, -- MID tier: body + status light only, snapped, no tweens
	loops: { Tween }, -- infinite tweens (bob, spin): cancelled on teardown
	shadow: Part?, -- soft ground shadow under YOUR near drone (moved with BulkMoveTo)
	beam: Beam?, -- V-CONTACT height beam shadow -> body (Control Mode only)
}

type PartSpec = {
	frame: CFrame, -- the part's pose above the tile top; position in multiples of FULL
	size: Vector3, -- in multiples of FULL
	role: string, -- "main" (crop colour by progress) | "stem" | "leaf" | "dark"
	shape: Enum.PartType?,
	color: Color3?, -- fixed colour (overrides the role colour)
	mesh: string?, -- "sphere": an ellipsoid via SpecialMesh (Ball parts must be round)
	noShadow: boolean?,
}

type CropVisual = {
	cropId: string,
	tile: BasePart,
	parts: { Part },
	specs: { PartSpec },
	model: Model?,
	stage: string?,
	base: CFrame, -- the tile top (with the tile's fixed yaw)
	scale: number, -- last scale posed (identical updates are skipped)
	mainColor: Color3, -- untinted main colour of the last pose (re-tinting needs it)
	ready: boolean,
	restParts: { BasePart }, -- sway: the parts and their rest pose relative to `base`
	restLocal: { CFrame },
	restAt: number, -- os.clock() once the tweens are done and the crop may sway
	swaying: boolean,
	swayCos: number,
	swaySin: number,
	marker: BillboardGui?,
	proxy: boolean, -- MID tier: a single plain part
}

type Burst = {
	emitter: ParticleEmitter,
	position: Vector3,
	count: number,
	lifetime: number,
	aim: Vector3?, -- the attachment turns to face this point (Front bursts)
	speed: NumberRange?, -- per-burst speed (aimed bursts)
	low: boolean?, -- low priority: waits while a normal (harvest, ...) burst is queued
}

type FxState = {
	anchor: Part?, -- invisible part holding the plot's single FX attachment (made on first burst)
	attachment: Attachment?,
	emitters: { [string]: ParticleEmitter },
	queue: { Burst },
	busy: { [BasePart]: number }, -- tile -> os.clock() until its current burst is over
}

type PlotVisual = {
	plot: Model,
	drone: DroneVisual,
	crops: { [BasePart]: CropVisual },
	connections: { RBXScriptConnection },
	folder: Folder,
	fx: FxState,
	snaps: { [BasePart]: CropTransitions.Snapshot },
	pending: { [BasePart]: boolean },
	soil: { [BasePart]: string }, -- the SoilStates name last shown per tile
	own: boolean,
	fullFx: boolean,
	dressing: PlotDressing.Dressing,
	chargerGlow: { BasePart }, -- the charger's rings + pylon light (lit + pulsing only while charging)
	chargerPad: { part: BasePart, material: Enum.Material, color: Color3, size: Vector3 }?, -- server pad, restored on teardown
	battery: number?, -- last Battery seen (rising on the charger = charging: rings spin up)
	ringFast: boolean, -- the rings pulse at RING_PULSE_FAST (charging)
	ringTweens: { Tween },
	activeStation: string?, -- station your drone is on (own plot only)
	tier: string, -- "near" | "mid" (FAR plots have no PlotVisual)
	cargo: number?, -- last Cargo seen (a drop at a station = unload / deposit, ANIM-2/4/7)
	unloadUntil: number, -- os.clock() until the current unload burst is over (one at a time)
	hopper: BasePart?, -- the factory hopper (procedural, or an artist part named "Hopper")
	hopperRest: CFrame?,
	chimneyTop: Vector3?, -- where chimney bits / smoke leave the factory
}

type Style = "initial" | "plain" | "plant" | "sprout" | "ready"

local BALL = Enum.PartType.Ball
local CYLINDER = Enum.PartType.Cylinder

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

--[[
	piece(position, rotation, size, role, extra) -> PartSpec
	position and size are in multiples of FULL; rotation is in degrees (X, Y, Z), applied Z
	first, then Y, then X (CFrame.Angles). A Cylinder's axis is its X: rotation Z 90 stands it
	up. extra: shape, color (fixed, overrides the role colour), mesh = "sphere" (an ellipsoid
	through a SpecialMesh), noShadow.
]]
local function piece(
	position: Vector3,
	rotation: Vector3,
	size: Vector3,
	role: string,
	extra: { [string]: any }?
): PartSpec
	local result: PartSpec = {
		frame = CFrame.new(position)
			* CFrame.Angles(math.rad(rotation.X), math.rad(rotation.Y), math.rad(rotation.Z)),
		size = size,
		role = role,
		shape = nil,
		color = nil,
		mesh = nil,
		noShadow = nil,
	}
	if extra ~= nil then
		for key, value in extra do
			(result :: any)[key] = value
		end
	end
	return result
end

local function vec(x: number, y: number, z: number): Vector3
	return Vector3.new(x, y, z)
end

-- A part sitting on top of another spec's part (e.g. a straw-gold grass tip).
local function tipOf(base: PartSpec, size: Vector3, color: Color3): PartSpec
	return {
		frame = base.frame * CFrame.new(0, base.size.Y / 2 - size.Y / 2 + 0.02, 0),
		size = size,
		role = "main",
		shape = nil,
		color = color,
		mesh = nil,
		noShadow = true,
	}
end

-- The sunflower head: a seed disc facing up-and-toward +Z (the camera side) with a petal ring.
local function flowerHead(center: Vector3, tiltDegrees: number, petals: number): { PartSpec }
	local head = CFrame.new(center) * CFrame.Angles(math.rad(tiltDegrees), 0, 0)
	local out: { PartSpec } = {
		{
			frame = head * CFrame.Angles(0, 0, math.rad(90)),
			size = vec(0.07, 0.36, 0.36),
			role = "dark",
			shape = CYLINDER,
			color = hex("#5A3C1E"),
			mesh = nil,
			noShadow = nil,
		},
	}
	for index = 1, petals do
		local angle = (index - 1) / petals * 2 * math.pi
		table.insert(out, {
			frame = head * CFrame.Angles(0, angle, 0) * CFrame.new(0.25, 0, 0),
			size = vec(0.16, 0.03, 0.1),
			role = "main",
			shape = nil,
			color = if index % 2 == 0 then hex("#FFB01F") else hex("#FFD23C"),
			mesh = nil,
			noShadow = true,
		})
	end
	return out
end

local function join(...: { PartSpec }): { PartSpec }
	local out: { PartSpec } = {}
	for _, list in { ... } do
		for _, item in list do
			table.insert(out, item)
		end
	end
	return out
end

local STRAW = hex("#C9C27A")
local GRASS_BLADES: { PartSpec } = {
	piece(vec(-0.3, 0.18, -0.1), vec(0, 0, 15), vec(0.1, 0.36, 0.1), "main", { noShadow = true }),
	piece(vec(0.05, 0.22, 0.25), vec(0, 0, -10), vec(0.1, 0.44, 0.1), "main", { noShadow = true }),
	piece(vec(0.3, 0.16, -0.2), vec(0, 0, 8), vec(0.1, 0.32, 0.1), "main", { noShadow = true }),
	piece(vec(-0.05, 0.14, -0.3), vec(0, 0, -4), vec(0.09, 0.28, 0.09), "main", { noShadow = true }),
}

-- Wheat (ready): three gold stalks, each with a fat head drooping 20 degrees outward.
local WHEAT_STALK = hex("#C7A84A")
local WHEAT_HEAD = hex("#E8C45C")

--[[
	Procedural low-poly crops, per CropConfig shape and per stage (docs/ART_BIBLE.md §3.3).
	The game scales a whole recipe with growth (0.25 -> 0.85, ready 1), so sprout recipes are
	authored bigger than they look, as the Bible asks of artist models. READY changes colour
	AND silhouette (gold drooping heads, the orange shoulder, the open flower, ribs, bloom).
	Rules: opaque parts only, no unions, no alpha cards, <= 8 parts per tile, no shadows on
	grass and sprouts.
]]
local SHAPES: { [string]: { sprout: { PartSpec }, growing: { PartSpec }, ready: { PartSpec } } } = {
	-- Wild grass: four leaning blades; ready = straw-gold tips on the two tallest.
	grass = {
		sprout = GRASS_BLADES,
		growing = GRASS_BLADES,
		ready = join(GRASS_BLADES, {
			tipOf(GRASS_BLADES[2], vec(0.11, 0.12, 0.11), STRAW),
			tipOf(GRASS_BLADES[1], vec(0.11, 0.11, 0.11), STRAW),
		}),
	},
	-- Wheat (max 6 parts): blades -> green upright stalks with closed heads -> drooping gold heads.
	stalk = {
		sprout = {
			piece(vec(-0.08, 0.3, 0), vec(0, 0, 18), vec(0.06, 0.6, 0.06), "main", { noShadow = true }),
			piece(vec(0.08, 0.32, 0.03), vec(0, 0, -15), vec(0.06, 0.64, 0.06), "main", { noShadow = true }),
			piece(vec(0, 0.28, -0.08), vec(-15, 0, 0), vec(0.06, 0.56, 0.06), "main", { noShadow = true }),
		},
		growing = {
			piece(
				vec(-0.12, 0.42, 0.04),
				vec(0, 0, 4),
				vec(0.07, 0.84, 0.07),
				"stem",
				{ color = hex("#7FA04A") }
			),
			piece(
				vec(0.12, 0.4, -0.05),
				vec(0, 0, -4),
				vec(0.07, 0.8, 0.07),
				"stem",
				{ color = hex("#7FA04A") }
			),
			piece(
				vec(0.01, 0.45, 0.13),
				vec(5, 0, 0),
				vec(0.07, 0.9, 0.07),
				"stem",
				{ color = hex("#7FA04A") }
			),
			piece(
				vec(-0.13, 0.94, 0.04),
				vec(0, 0, 4),
				vec(0.12, 0.22, 0.12),
				"main",
				{ color = hex("#B9C46A") }
			),
			piece(
				vec(0.11, 0.9, -0.05),
				vec(0, 0, -4),
				vec(0.12, 0.22, 0.12),
				"main",
				{ color = hex("#B9C46A") }
			),
		},
		ready = {
			piece(
				vec(-0.13, 0.45, 0.03),
				vec(0, 0, 8),
				vec(0.07, 0.9, 0.07),
				"stem",
				{ color = WHEAT_STALK }
			),
			piece(
				vec(0.13, 0.43, -0.04),
				vec(0, 0, -8),
				vec(0.07, 0.86, 0.07),
				"stem",
				{ color = WHEAT_STALK }
			),
			piece(vec(0, 0.47, 0.13), vec(8, 0, 0), vec(0.07, 0.94, 0.07), "stem", { color = WHEAT_STALK }),
			piece(
				vec(-0.24, 0.95, 0.03),
				vec(0, 0, 22),
				vec(0.14, 0.26, 0.14),
				"main",
				{ color = WHEAT_HEAD }
			),
			piece(
				vec(0.24, 0.9, -0.04),
				vec(0, 0, -20),
				vec(0.14, 0.26, 0.14),
				"main",
				{ color = WHEAT_HEAD }
			),
			piece(vec(0, 0.99, 0.25), vec(22, 0, 0), vec(0.14, 0.26, 0.14), "main", { color = WHEAT_HEAD }),
		},
	},
	-- Carrot: feathery leaves -> leafy dome + a small orange shoulder -> a big plume and a
	-- chunky orange shoulder clearly above the soil.
	bush = {
		sprout = {
			piece(
				vec(0, 0.05, 0),
				vec(0, 0, 0),
				vec(0.14, 0.14, 0.14),
				"leaf",
				{ shape = BALL, noShadow = true }
			),
			piece(vec(0, 0.28, 0.06), vec(15, 0, 0), vec(0.04, 0.48, 0.16), "leaf", { noShadow = true }),
			piece(
				vec(0.05, 0.28, -0.04),
				vec(-10, 0, -14),
				vec(0.04, 0.46, 0.16),
				"leaf",
				{ noShadow = true }
			),
			piece(
				vec(-0.05, 0.27, -0.03),
				vec(-8, 0, 14),
				vec(0.04, 0.44, 0.16),
				"leaf",
				{ noShadow = true }
			),
		},
		growing = {
			piece(
				vec(0, 0.04, 0),
				vec(0, 0, 0),
				vec(0.2, 0.2, 0.2),
				"main",
				{ shape = BALL, color = hex("#E07A35") }
			),
			piece(
				vec(0, 0.34, 0),
				vec(0, 0, 0),
				vec(0.42, 0.42, 0.42),
				"leaf",
				{ shape = BALL, color = hex("#5FAE45") }
			),
			piece(
				vec(0.1, 0.52, 0.05),
				vec(0, 0, -15),
				vec(0.05, 0.38, 0.18),
				"leaf",
				{ color = hex("#5FAE45") }
			),
			piece(
				vec(-0.1, 0.5, -0.05),
				vec(0, 0, 15),
				vec(0.05, 0.36, 0.18),
				"leaf",
				{ color = hex("#5FAE45") }
			),
		},
		ready = {
			piece(
				vec(0, 0.12, 0),
				vec(0, 0, 0),
				vec(0.3, 0.3, 0.3),
				"main",
				{ shape = BALL, color = hex("#F08030") }
			),
			piece(
				vec(0, 0.4, 0),
				vec(0, 0, 0),
				vec(0.28, 0.28, 0.28),
				"leaf",
				{ shape = BALL, color = hex("#4E9E3A") }
			),
			piece(vec(0, 0.5, 0.08), vec(14, 0, 0), vec(0.07, 0.5, 0.24), "leaf", { color = hex("#4E9E3A") }),
			piece(
				vec(0.08, 0.5, -0.05),
				vec(-10, 0, -16),
				vec(0.07, 0.48, 0.24),
				"leaf",
				{ color = hex("#4E9E3A") }
			),
			piece(
				vec(-0.08, 0.49, -0.05),
				vec(-10, 0, 16),
				vec(0.07, 0.46, 0.24),
				"leaf",
				{ color = hex("#4E9E3A") }
			),
		},
	},
	-- Tree: a sapling -> trunk + canopy -> a fuller, darker double canopy (about 5 studs).
	tree = {
		sprout = {
			piece(vec(0, 0.16, 0), vec(0, 0, 0), vec(0.06, 0.32, 0.06), "dark", { noShadow = true }),
			piece(
				vec(0, 0.36, 0),
				vec(0, 0, 0),
				vec(0.22, 0.22, 0.22),
				"main",
				{ shape = BALL, noShadow = true }
			),
		},
		growing = {
			piece(vec(0, 0.36, 0), vec(0, 0, 0), vec(0.14, 0.72, 0.14), "dark"),
			piece(vec(0, 0.82, 0), vec(0, 0, 0), vec(0.62, 0.62, 0.62), "main", { shape = BALL }),
			piece(vec(0.18, 0.98, 0.06), vec(0, 0, 0), vec(0.4, 0.4, 0.4), "main", { shape = BALL }),
		},
		ready = {
			piece(vec(0, 0.42, 0), vec(0, 0, 0), vec(0.22, 0.84, 0.22), "dark", { color = hex("#6E4A2E") }),
			piece(
				vec(0, 1.0, 0),
				vec(0, 0, 0),
				vec(0.82, 0.82, 0.82),
				"main",
				{ shape = BALL, color = hex("#4A8C46") }
			),
			piece(
				vec(0.22, 1.2, 0.1),
				vec(0, 0, 0),
				vec(0.58, 0.58, 0.58),
				"main",
				{ shape = BALL, color = hex("#5A9A48") }
			),
			piece(
				vec(-0.18, 1.12, -0.12),
				vec(0, 0, 0),
				vec(0.44, 0.44, 0.44),
				"main",
				{ shape = BALL, color = hex("#6DB25A") }
			),
		},
	},
	-- Sunflower (8 parts at ready): 2 round cotyledons -> stem, 2 leaves, a closed green bud ->
	-- an open head (seed disc + 6 petals) tilted toward +Z.
	flower = {
		sprout = {
			piece(vec(0, 0.16, 0), vec(0, 0, 0), vec(0.05, 0.32, 0.05), "stem", { noShadow = true }),
			piece(
				vec(0.09, 0.34, 0),
				vec(0, 0, 115),
				vec(0.03, 0.2, 0.2),
				"leaf",
				{ shape = CYLINDER, color = hex("#76C452"), noShadow = true }
			),
			piece(
				vec(-0.09, 0.34, 0),
				vec(0, 0, 65),
				vec(0.03, 0.2, 0.2),
				"leaf",
				{ shape = CYLINDER, color = hex("#76C452"), noShadow = true }
			),
		},
		growing = {
			piece(vec(0, 0.5, 0), vec(0, 0, 0), vec(0.07, 1.0, 0.07), "stem", { color = hex("#5A9A3C") }),
			piece(vec(0.13, 0.45, 0), vec(0, 0, -25), vec(0.26, 0.04, 0.14), "leaf"),
			piece(vec(-0.13, 0.6, 0), vec(0, 0, 25), vec(0.26, 0.04, 0.14), "leaf"),
			piece(
				vec(0, 1.06, 0),
				vec(0, 0, 0),
				vec(0.18, 0.18, 0.18),
				"main",
				{ shape = BALL, color = hex("#9AB84A") }
			),
		},
		ready = join({
			piece(vec(0, 0.48, 0), vec(0, 0, 0), vec(0.08, 0.96, 0.08), "stem", { color = hex("#5A9A3C") }),
		}, flowerHead(vec(0, 1.0, 0.05), 25, 6)),
	},
	-- Pumpkin: 2 broad leaves -> leaves + a small green fruit -> a squashed, glossy orange fruit
	-- with darker ribs, a curly stem and a leaf behind it.
	round = {
		sprout = {
			piece(vec(0, 0.06, 0), vec(0, 0, 0), vec(0.06, 0.12, 0.06), "stem", { noShadow = true }),
			piece(
				vec(0.12, 0.12, 0),
				vec(0, 0, -18),
				vec(0.3, 0.04, 0.22),
				"leaf",
				{ color = hex("#7DC45A"), noShadow = true }
			),
			piece(
				vec(-0.12, 0.13, 0.02),
				vec(0, 0, 18),
				vec(0.3, 0.04, 0.22),
				"leaf",
				{ color = hex("#7DC45A"), noShadow = true }
			),
		},
		growing = {
			piece(vec(0, 0.16, 0), vec(0, 0, 0), vec(0.36, 0.36, 0.36), "main", { shape = BALL }),
			piece(
				vec(0.26, 0.1, 0.05),
				vec(0, 20, -12),
				vec(0.36, 0.04, 0.26),
				"leaf",
				{ color = hex("#5FA040") }
			),
			piece(
				vec(-0.24, 0.1, 0.1),
				vec(0, -25, 12),
				vec(0.36, 0.04, 0.26),
				"leaf",
				{ color = hex("#5FA040") }
			),
			piece(
				vec(0.02, 0.1, -0.27),
				vec(14, 0, 0),
				vec(0.26, 0.04, 0.36),
				"leaf",
				{ color = hex("#5FA040") }
			),
		},
		ready = {
			piece(
				vec(0, 0.28, 0),
				vec(0, 0, 0),
				vec(0.8, 0.56, 0.8),
				"main",
				{ mesh = "sphere", color = hex("#FF9614") }
			),
			piece(
				vec(0, 0.285, 0),
				vec(0, 0, 0),
				vec(0.16, 0.57, 0.82),
				"dark",
				{ mesh = "sphere", color = hex("#C46A10") }
			),
			piece(
				vec(0, 0.285, 0),
				vec(0, 60, 0),
				vec(0.16, 0.57, 0.82),
				"dark",
				{ mesh = "sphere", color = hex("#C46A10") }
			),
			piece(
				vec(0, 0.285, 0),
				vec(0, 120, 0),
				vec(0.16, 0.57, 0.82),
				"dark",
				{ mesh = "sphere", color = hex("#C46A10") }
			),
			piece(
				vec(0.02, 0.6, 0),
				vec(0, 0, 20),
				vec(0.06, 0.14, 0.06),
				"stem",
				{ color = hex("#6B7A2E") }
			),
			piece(
				vec(0, 0.08, -0.42),
				vec(12, 0, 0),
				vec(0.34, 0.04, 0.26),
				"leaf",
				{ color = hex("#5FA040") }
			),
		},
	},
	-- Cactus: a ridged nub -> a column with one arm -> two arms at different heights and a
	-- small pink bloom on top (no spine parts).
	cactus = {
		sprout = {
			piece(
				vec(0, 0.13, 0),
				vec(0, 0, 0),
				vec(0.26, 0.26, 0.26),
				"main",
				{ shape = BALL, noShadow = true }
			),
			piece(
				vec(0, 0.13, 0),
				vec(0, 0, 0),
				vec(0.05, 0.24, 0.28),
				"dark",
				{ color = hex("#5E9E52"), noShadow = true }
			),
			piece(
				vec(0, 0.13, 0),
				vec(0, 90, 0),
				vec(0.05, 0.24, 0.28),
				"dark",
				{ color = hex("#5E9E52"), noShadow = true }
			),
		},
		growing = {
			piece(vec(0, 0.38, 0), vec(0, 0, 90), vec(0.76, 0.26, 0.26), "main", { shape = CYLINDER }),
			piece(vec(0.17, 0.38, 0), vec(0, 0, 0), vec(0.14, 0.1, 0.1), "main", { shape = CYLINDER }),
			piece(vec(0.25, 0.5, 0), vec(0, 0, 90), vec(0.24, 0.1, 0.1), "main", { shape = CYLINDER }),
		},
		ready = {
			piece(
				vec(0, 0.5, 0),
				vec(0, 0, 90),
				vec(1.0, 0.3, 0.3),
				"main",
				{ shape = CYLINDER, color = hex("#60B05C") }
			),
			piece(
				vec(0.2, 0.42, 0),
				vec(0, 0, 0),
				vec(0.16, 0.12, 0.12),
				"main",
				{ shape = CYLINDER, color = hex("#60B05C") }
			),
			piece(
				vec(0.29, 0.56, 0),
				vec(0, 0, 90),
				vec(0.3, 0.12, 0.12),
				"main",
				{ shape = CYLINDER, color = hex("#60B05C") }
			),
			piece(
				vec(-0.19, 0.62, 0),
				vec(0, 0, 0),
				vec(0.14, 0.11, 0.11),
				"main",
				{ shape = CYLINDER, color = hex("#60B05C") }
			),
			piece(
				vec(-0.27, 0.73, 0),
				vec(0, 0, 90),
				vec(0.24, 0.11, 0.11),
				"main",
				{ shape = CYLINDER, color = hex("#60B05C") }
			),
			piece(
				vec(0, 1.02, 0),
				vec(0, 0, 0),
				vec(0.14, 0.14, 0.14),
				"main",
				{ shape = BALL, color = hex("#FF6FA0") }
			),
		},
	},
}

local PlotRenderer = {}

local visuals: { [Model]: PlotVisual } = {}
-- plot Index -> last DroneMoved cell + serial (attrs can lag). Cleared when the plot goes.
local lastMoved: { [number]: { cell: Vector2, serial: number? } } = {}
local localFolder: Folder

-- Crop juice state.
local activeParticles = 0
local activeTweens = 0
local swayList: { CropVisual } = {}
local nextLodAt = 0
local nextDebugAt = 0
-- Tier of every known plot (NEAR / MID plots also have a PlotVisual in `visuals`).
local tiers: { [Model]: string } = {}
local farHooks: { [Model]: { RBXScriptConnection } } = {}
local farPaint: { [Model]: any } = {} -- DronePaint cached while FAR
local cropTint = 0 -- 0..1 toward STRAW_COLOR (SetCropTint)
local controlMode: { IsActive: (any) -> boolean }? = nil -- ControlModeController, set in Start
-- Two shared sway drivers a quarter period apart; each crop mixes them by its own phase.
-- They are the same sine waves the old Sine InOut reversing tweens made (-cos), advanced by
-- render at the TWEENED half period, so the wind can change speed smoothly (ANIM-3).
local swayA = Instance.new("NumberValue")
local swayB = Instance.new("NumberValue")
local swayAngle = Instance.new("NumberValue") -- radians (WIND, tweened)
swayAngle.Value = WIND.Sunny.angle
local swayHalf = Instance.new("NumberValue") -- seconds from one side to the other (tweened)
swayHalf.Value = WIND.Sunny.half
local swayPhase = 0
local windWeather = "Sunny"

local function buildEmitterTemplate(): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "BurstTemplate"
	emitter.Enabled = false -- NEVER enabled: bursts only, via :Emit(n)
	emitter.Rate = 0
	emitter.LockedToPart = false -- emitted bits stay put while the attachment moves on
	emitter.Orientation = Enum.ParticleOrientation.FacingCamera
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-220, 220)
	emitter.LightInfluence = 1
	emitter.ZOffset = 0.2
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.65, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	return emitter
end
local emitterTemplate = buildEmitterTemplate()

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function decorPart(
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
	part.Anchored = true -- REQUIRED: no physics anywhere in the drone, crops or decorations
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- World CFrame (no rotation) the drone hovers at above a cell.
local function cellCFrame(plot: Model, cell: Vector2): CFrame
	local origin = plot:GetAttribute("Origin") :: Vector3
	local pitch = plot:GetAttribute("Pitch") :: number
	return CFrame.new(origin + Vector3.new(cell.X * pitch, DRONE.HoverHeight, -cell.Y * pitch))
end

-- Numbers first (DroneX / DroneY), then Vector3 / Vector2 Drone.
local function readDroneCell(plot: Model): Vector2?
	local x, y = DroneSignals.cellFromAttributes(
		plot:GetAttribute("DroneX"),
		plot:GetAttribute("DroneY"),
		plot:GetAttribute("Drone")
	)
	if x == nil or y == nil then
		return nil
	end
	return Vector2.new(x, y)
end

local function sameCell(a: Vector2?, b: Vector2?): boolean
	return a ~= nil and b ~= nil and a.X == b.X and a.Y == b.Y
end

-- ASSETS-8: your drone's step sound. One tile only: a reset to the charger is a snap, not a hop.
-- Both move paths call it; whichever lands second sees the same cell and stays quiet.
local function hopSound(own: boolean, from: Vector2?, to: Vector2?)
	if own and from ~= nil and to ~= nil and not sameCell(from, to) and (to - from).Magnitude <= 1.5 then
		SoundController.play("hop")
	end
end

-- The published DroneSerial (nil on an old server without it).
local function readDroneSerial(plot: Model): number?
	local serial = plot:GetAttribute("DroneSerial")
	return if type(serial) == "number" then serial else nil
end

---------------------------------------------------------------------------------- drone
local CERAMIC = Color3.fromHex("#D7E2EC") -- Bible ceramic white (visor rim)
-- Colours BEFORE the paint job applies (it tweens in a moment later): the default Factory Grey,
-- with a lime eye, so a drone is never an all-black blob (BUG-DRONE).
local HULL_COLOR = Color3.fromHex("#1E2530")
local HULL_MID_COLOR = Color3.fromHex("#2E3846")

-- The procedural drone (docs/ART_BIBLE.md §4.1): a dark hull (paint primary; the default
-- Factory Grey is hull dark #1E2530), a ceramic visor rim with one neon eye slit on -Z (paint
-- accent), a neon battery strip on the spine (coloured by charge), 4 arms and 4 rotors (each a
-- translucent blur disc + a spinning blade). 16 parts. The top of the body stays clear in a
-- 1.2-stud circle for hats.
local ROTOR_BLUR_COLOR = Color3.fromHex("#C9D3DC") -- Bible chrome
local ROTOR_BLUR_ALPHA = 0.62
local ROTOR_BLADE_COLOR = Color3.fromHex("#2A313C")
local function buildProceduralDrone(model: Model, add: (BasePart, CFrame, boolean, PaintRole?) -> ())
	add(
		decorPart("Body", Vector3.new(2.4, 0.8, 2.4), HULL_COLOR, Enum.Material.Metal),
		CFrame.identity,
		false,
		"primary"
	)
	add(
		decorPart("VisorRim", Vector3.new(1.1, 0.5, 0.08), CERAMIC, Enum.Material.SmoothPlastic),
		CFrame.new(0, 0, -1.23),
		false,
		nil
	)
	add(
		decorPart("Eye", Vector3.new(0.7, 0.16, 0.06), STATUS_COLORS.lime, Enum.Material.Neon),
		CFrame.new(0, 0.02, -1.28),
		false,
		"accent"
	)
	-- Behind the hat circle (radius 0.6): spans z 0.63 .. 0.93 on top of the body.
	add(
		decorPart("BatteryBar", Vector3.new(1.2, 0.12, 0.3), STATUS_COLORS.lime, Enum.Material.Neon),
		CFrame.new(0, 0.46, 0.78),
		false,
		nil
	)
	for i, corner in
		{ Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) }
	do
		local armOffset = CFrame.new(corner * 1.1) * CFrame.Angles(0, math.rad(45 + 90 * i), 0)
		add(
			decorPart("Arm" .. i, Vector3.new(0.25, 0.2, 1.4), HULL_MID_COLOR, Enum.Material.Metal),
			armOffset,
			false,
			"secondary"
		)
		-- Rotor = a translucent blur disc + one dark blade bar (ASSETS-2). A solid disc is
		-- rotationally symmetric, so it never LOOKED like it spun; the blade does, and the disc
		-- reads as motion blur from the bird's-eye camera. Both spin (render's rotor pose).
		local hub = corner * 1.6 + Vector3.new(0, 0.5, 0)
		local disc = decorPart(
			"Rotor" .. i,
			Vector3.new(0.05, 1.5, 1.5),
			ROTOR_BLUR_COLOR,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		disc.Transparency = ROTOR_BLUR_ALPHA
		disc.CastShadow = false
		add(disc, CFrame.new(hub) * CFrame.Angles(0, 0, math.rad(90)), true, nil)
		local blade = decorPart(
			"Rotor" .. i .. "Blade",
			Vector3.new(0.16, 0.05, 1.42),
			ROTOR_BLADE_COLOR,
			Enum.Material.Metal
		)
		blade.CastShadow = false
		add(blade, CFrame.new(hub + Vector3.new(0, 0.04, 0)), true, nil)
	end
	model.Name = "Drone"
end

local function buildDrone(folder: Folder, simple: boolean): DroneVisual
	local poses: { PartPose } = {}
	local paintParts: { { part: BasePart, role: PaintRole } } = {}
	local model = if simple then nil else AssetLibrary.drone()
	if simple then
		-- MID tier: just the hull (paint primary) + the status light below. No tweens.
		local simpleModel = Instance.new("Model")
		simpleModel.Name = "Drone"
		local body = decorPart("Body", Vector3.new(2.4, 0.8, 2.4), HULL_COLOR, Enum.Material.Metal)
		body.CastShadow = false
		body.Parent = simpleModel
		table.insert(poses, { part = body :: BasePart, offset = CFrame.identity, spins = false })
		table.insert(paintParts, { part = body :: BasePart, role = "primary" :: PaintRole })
		model = simpleModel
	elseif model ~= nil then
		-- Artist drone: every BasePart keeps its offset from the model pivot; "Rotor*" parts spin.
		local pivot = model:GetPivot()
		for _, descendant in model:GetDescendants() do
			if descendant:IsA("BasePart") then
				table.insert(poses, {
					part = descendant,
					offset = pivot:ToObjectSpace(descendant.CFrame),
					spins = string.sub(descendant.Name, 1, 5) == "Rotor",
				})
				local role = descendant:GetAttribute("PaintSlot")
				if role == "primary" or role == "secondary" or role == "accent" then
					table.insert(paintParts, { part = descendant, role = role })
				end
			end
		end
	else
		model = Instance.new("Model")
		buildProceduralDrone(
			model :: Model,
			function(part: BasePart, offset: CFrame, spins: boolean, role: PaintRole?)
				part.Parent = model
				table.insert(poses, { part = part, offset = offset, spins = spins })
				if role ~= nil then
					table.insert(paintParts, { part = part, role = role })
				end
			end
		)
	end
	local droneModel = model :: Model
	droneModel.Parent = folder

	-- The battery / state light on the spine (§4.1.1): an artist part named "BatteryBar" or
	-- "StatusLight" (Neon, no SurfaceAppearance), else a procedural strip. The visor Eye stays
	-- the paint's accent.
	local status: BasePart? = nil
	for _, pose in poses do
		if pose.part.Name == "BatteryBar" or pose.part.Name == "StatusLight" then
			status = pose.part
		end
	end
	if status == nil then
		local light =
			decorPart("BatteryBar", Vector3.new(1.2, 0.12, 0.3), STATUS_COLORS.lime, Enum.Material.Neon)
		light.CastShadow = false
		light.Parent = droneModel
		table.insert(poses, { part = light :: BasePart, offset = CFrame.new(0, 0.46, 0.78), spins = false })
		status = light
	end

	local function value(className: string, initial: any): any
		local v: any = Instance.new(className)
		v.Value = initial
		v.Parent = droneModel
		return v
	end

	local visual: DroneVisual = {
		model = droneModel,
		poses = poses,
		hatPoses = {},
		paintParts = paintParts,
		move = value("CFrameValue", CFrame.identity),
		tilt = value("NumberValue", 0),
		bob = value("NumberValue", 0),
		spin = value("NumberValue", 0),
		lift = value("NumberValue", 0),
		roll = value("NumberValue", 0),
		land = value("NumberValue", 0),
		rotorPeriod = value("NumberValue", ROTOR_IDLE),
		rotorTarget = ROTOR_IDLE,
		flight = {},
		poseY = value("NumberValue", 0),
		posePitch = value("NumberValue", 0),
		poseYaw = value("NumberValue", 0),
		pose = {},
		cell = nil,
		serial = nil,
		moveTween = nil,
		bobScale = value("NumberValue", 1),
		status = status :: BasePart,
		statusKey = "",
		statusBlink = nil,
		limping = false,
		ghosts = {},
		ghostNext = 1,
		simple = simple,
		loops = {},
	}

	if simple then
		return visual -- MID: no infinite tweens at all
	end
	-- Endless hover, pure TweenService (NEAR only; cancelled on teardown). The rotors are
	-- advanced by render at the tweened rotorPeriod, so their speed can change smoothly.
	local bobLoop = TweenService:Create(
		visual.bob,
		TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{
			Value = 1,
		}
	)
	table.insert(visual.loops, bobLoop)
	bobLoop:Play()
	return visual
end

local function applyPaint(drone: DroneVisual, paintId: any)
	local item: CosmeticConfig.Cosmetic? = if type(paintId) == "string"
		then CosmeticConfig.ById[paintId]
		else nil
	if item == nil or item.slot ~= "paint" then
		item = CosmeticConfig.ById[CosmeticConfig.Defaults.paint]
	end
	if item == nil then
		return
	end
	local material = (Enum.Material :: any)[item.material or "Metal"] or Enum.Material.Metal
	for _, entry in drone.paintParts do
		local color = (item :: any)[entry.role]
		if color ~= nil then
			if drone.simple then
				entry.part.Color = rgb(color)
			else
				TweenService:Create(entry.part, TweenInfo.new(0.4), { Color = rgb(color) }):Play()
			end
		end
		if entry.role ~= "accent" then
			entry.part.Material = material
		end
	end
end

-- Procedural hats (offsets relative to the drone body centre; its top is at y = 0.4).
local function buildHatParts(
	style: string,
	color: Color3
): { { part: BasePart, offset: CFrame, spins: boolean } }
	local out: { { part: BasePart, offset: CFrame, spins: boolean } } = {}
	local function add(part: BasePart, offset: CFrame, spins: boolean?)
		table.insert(out, { part = part, offset = offset, spins = spins == true })
	end
	local up = CFrame.Angles(0, 0, math.rad(90)) -- turns a Cylinder's X axis upright
	if style == "antenna" then
		add(
			decorPart(
				"HatPole",
				Vector3.new(0.08, 1.2, 0.08),
				Color3.fromRGB(60, 64, 72),
				Enum.Material.Metal
			),
			CFrame.new(0.6, 1.0, 0.6)
		)
		add(
			decorPart("HatTip", Vector3.new(0.28, 0.28, 0.28), color, Enum.Material.Neon, BALL),
			CFrame.new(0.6, 1.65, 0.6)
		)
	elseif style == "straw" then
		add(
			decorPart(
				"HatBrim",
				Vector3.new(0.12, 2.6, 2.6),
				color,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			),
			CFrame.new(0, 0.5, 0) * up
		)
		add(
			decorPart(
				"HatCrown",
				Vector3.new(0.6, 1.3, 1.3),
				color,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			),
			CFrame.new(0, 0.82, 0) * up
		)
		add(
			decorPart(
				"HatBand",
				Vector3.new(0.14, 1.36, 1.36),
				Color3.fromRGB(200, 70, 60),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			),
			CFrame.new(0, 0.62, 0) * up
		)
	elseif style == "propeller" then
		add(
			decorPart("HatCap", Vector3.new(1.3, 0.7, 1.3), color, Enum.Material.SmoothPlastic, BALL),
			CFrame.new(0, 0.55, 0)
		)
		add(
			decorPart(
				"HatStem",
				Vector3.new(0.1, 0.35, 0.1),
				Color3.fromRGB(230, 230, 235),
				Enum.Material.Metal
			),
			CFrame.new(0, 1.0, 0)
		)
		add(
			decorPart(
				"HatBlade",
				Vector3.new(1.8, 0.06, 0.28),
				Color3.fromRGB(255, 200, 60),
				Enum.Material.SmoothPlastic
			),
			CFrame.new(0, 1.18, 0),
			true
		)
	elseif style == "tophat" then
		add(
			decorPart(
				"HatBrim",
				Vector3.new(0.1, 1.9, 1.9),
				color,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			),
			CFrame.new(0, 0.46, 0) * up
		)
		add(
			decorPart(
				"HatCrown",
				Vector3.new(1.1, 1.2, 1.2),
				color,
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			),
			CFrame.new(0, 1.05, 0) * up
		)
		add(
			decorPart(
				"HatBand",
				Vector3.new(0.16, 1.24, 1.24),
				Color3.fromRGB(200, 40, 60),
				Enum.Material.SmoothPlastic,
				Enum.PartType.Cylinder
			),
			CFrame.new(0, 0.62, 0) * up
		)
	elseif style == "halo" then
		for i = 1, 10 do
			local angle = (i / 10) * math.pi * 2
			add(
				decorPart("HatHalo" .. i, Vector3.new(0.5, 0.1, 0.14), color, Enum.Material.Neon),
				CFrame.new(math.cos(angle) * 0.85, 1.5, math.sin(angle) * 0.85)
					* CFrame.Angles(0, -angle + math.pi / 2, 0)
			)
		end
	end
	return out
end

local function applyHat(drone: DroneVisual, hatId: any)
	for _, pose in drone.hatPoses do
		pose.part:Destroy()
	end
	table.clear(drone.hatPoses)
	if drone.simple then
		return -- MID tier: no hats
	end
	local item = if type(hatId) == "string" then CosmeticConfig.ById[hatId] else nil
	if item == nil or item.slot ~= "hat" or item.style == nil then
		return
	end
	local style = item.style :: string
	local color = if item.color ~= nil then rgb(item.color) else Color3.new(1, 1, 1)
	local asset = AssetLibrary.hat(style)
	if asset ~= nil then
		local pivot = asset:GetPivot()
		for _, descendant in asset:GetDescendants() do
			if descendant:IsA("BasePart") then
				local offset = CFrame.new(0, 0.4, 0) * pivot:ToObjectSpace(descendant.CFrame)
				descendant.Parent = drone.model
				-- "Rotor*" parts spin around their own origin, like the drone's (propeller cap).
				local spins = string.sub(descendant.Name, 1, 5) == "Rotor"
				table.insert(drone.hatPoses, { part = descendant, offset = offset, spins = spins })
			end
		end
		asset:Destroy()
		return
	end
	for _, entry in buildHatParts(style, color) do
		entry.part.Parent = drone.model
		table.insert(drone.hatPoses, entry)
	end
end

-- Path ghost: a pooled (<= GHOST_COUNT) lime dot on the tile top, fading 0.4 -> 1 over 4 s.
local function dropGhost(plotVisual: PlotVisual, cell: Vector2)
	local drone = plotVisual.drone
	local plot = plotVisual.plot
	local origin = plot:GetAttribute("Origin")
	local pitch = plot:GetAttribute("Pitch")
	if typeof(origin) ~= "Vector3" or type(pitch) ~= "number" then
		return
	end
	local dot = drone.ghosts[drone.ghostNext] :: Part?
	if dot == nil then
		local created = decorPart(
			"PathGhost",
			Vector3.new(0.06, 1.1, 1.1),
			STATUS_COLORS.lime,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Cylinder
		)
		created.CastShadow = false
		created.Parent = plotVisual.folder
		drone.ghosts[drone.ghostNext] = created
		dot = created
	end
	local ghost = dot :: Part
	drone.ghostNext = drone.ghostNext % GHOST_COUNT + 1
	ghost.CFrame = CFrame.new(origin + Vector3.new(cell.X * pitch, 0.04, -cell.Y * pitch))
		* CFrame.Angles(0, 0, math.rad(90))
	ghost.Transparency = 0.4
	TweenService:Create(ghost, GHOST_FADE, { Transparency = 1 }):Play()
end

------------------------------------------------------------------------- flight feel (ANIM-1)
-- Cancels the current move's flight tweens (a new move, a teleport, teardown).
local function cancelFlight(drone: DroneVisual)
	for _, tween in drone.flight do
		tween:Cancel()
	end
	table.clear(drone.flight)
end

local function rotorPeriodFor(drone: DroneVisual, flying: boolean): number
	if drone.limping then
		return ROTOR_LIMP
	end
	return if flying then ROTOR_FLY else ROTOR_IDLE
end

-- Eases the rotor speed toward `period` (the spin angle keeps going: no restart from 0).
local function setRotorPeriod(drone: DroneVisual, period: number)
	if drone.simple or drone.rotorTarget == period then
		return
	end
	drone.rotorTarget = period
	TweenService:Create(drone.rotorPeriod, ROTOR_EASE, { Value = period }):Play()
end

local function isCharger(cell: Vector2): boolean
	return DroneSignals.stationAt(cell.X, cell.Y) == "charger"
end

--[[
	Your drone's one-step move: a hop (lift up in the first TAKEOFF_PART, glide, Quad InOut
	settle in the last SETTLE_PART), a bank into a turn, a landing on / take-off from the
	charger, and faster rotors. All finite tweens on the drone's value objects; render composes.
	oldLook / newLook: facing before and after the move (the move tween turns between them).
]]
local function startFlight(
	drone: DroneVisual,
	to: Vector2,
	oldLook: Vector3,
	newLook: Vector3,
	duration: number
)
	cancelFlight(drone)
	local flight = drone.flight
	local function add(instance: Instance, info: TweenInfo, goal: number): Tween
		local tween = TweenService:Create(instance, info, { Value = goal })
		table.insert(flight, tween)
		return tween
	end

	-- 1. Takeoff -> glide -> settle, chained (a cancelled stage never starts the next one).
	local takeoff = add(
		drone.lift,
		TweenInfo.new(duration * TAKEOFF_PART, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		1
	)
	local glide = add(
		drone.lift,
		TweenInfo.new(
			duration * (1 - TAKEOFF_PART - SETTLE_PART),
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut
		),
		CRUISE_LIFT
	)
	local settle = add(
		drone.lift,
		TweenInfo.new(duration * SETTLE_PART, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		0
	)
	takeoff.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			glide:Play()
		end
	end)
	glide.Completed:Once(function(state: Enum.PlaybackState)
		if state == Enum.PlaybackState.Completed then
			settle:Play()
		end
	end)
	takeoff:Play()

	-- 2. Bank: sin of the yaw change. A strafe (90 degree turn) leans, straight on / back only pitches.
	local side = oldLook:Cross(newLook).Y
	if math.abs(side) >= ROLL_MIN_TURN then
		add(
			drone.roll,
			TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true),
			math.clamp(side, -1, 1)
		):Play()
	end

	-- 3. Charger: drop to LAND_HEIGHT during the move there; climb back on the next takeoff.
	local landing = isCharger(to)
	local goal = if landing then LAND_DROP else 0
	if math.abs(drone.land.Value - goal) > 0.01 then
		add(
			drone.land,
			TweenInfo.new(
				duration,
				Enum.EasingStyle.Quad,
				if landing then Enum.EasingDirection.InOut else Enum.EasingDirection.Out
			),
			goal
		):Play()
	end

	-- 4. Rotors spin up for the flight (back to idle when the move tween completes).
	setRotorPeriod(drone, rotorPeriodFor(drone, true))
end

---------------------------------------------------------------- action body language (ANIM-2)
-- A move cancels the pose: the body eases back to neutral (0.08 s) while it takes off.
local function cancelPose(drone: DroneVisual)
	for _, tween in drone.pose do
		tween:Cancel()
	end
	table.clear(drone.pose)
	for _, value in { drone.poseY, drone.posePitch, drone.poseYaw } do
		if value.Value ~= 0 then
			local back = TweenService:Create(value, POSE_RESET, { Value = 0 })
			table.insert(drone.pose, back)
			back:Play()
		end
	end
end

--[[
	The body acts out the builtin the client inferred (DroneSignals.action, or cargo going
	into the factory). One pose at a time: a new one replaces the old from neutral. Every pose
	ends exactly at neutral (reversing tweens, or an explicit return).
	  plant    dip PLANT_DIP + slight nose-down, back up       0.28 s
	  harvest  nose-down scoop, quick snap back (ripe only)   0.28 s
	  water    yaw wobble +-6 degrees                         0.22 s
	  factory  small settle                                   0.3 s
]]
local function playPose(drone: DroneVisual, kind: string)
	if drone.simple then
		return
	end
	for _, tween in drone.pose do
		tween:Cancel()
	end
	table.clear(drone.pose)
	drone.poseY.Value = 0
	drone.posePitch.Value = 0
	drone.poseYaw.Value = 0
	local function add(value: NumberValue, info: TweenInfo, goal: number): Tween
		local tween = TweenService:Create(value, info, { Value = goal })
		table.insert(drone.pose, tween)
		return tween
	end
	local function after(first: Tween, ...: Tween)
		local next = { ... }
		first.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed then
				for _, tween in next do
					tween:Play()
				end
			end
		end)
	end
	if kind == "plant" then
		local info = TweenInfo.new(PLANT_HALF, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true)
		add(drone.poseY, info, -PLANT_DIP):Play()
		add(drone.posePitch, info, PLANT_NOD):Play()
	elseif kind == "harvest" then
		local down = TweenInfo.new(SCOOP_DOWN, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local back = TweenInfo.new(SCOOP_BACK, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local nod = add(drone.posePitch, down, SCOOP_NOD)
		local dip = add(drone.poseY, down, -SCOOP_DIP)
		after(nod, add(drone.posePitch, back, 0), add(drone.poseY, back, 0))
		nod:Play()
		dip:Play()
	elseif kind == "water" then
		local info = TweenInfo.new(WATER_QUARTER, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
		local left = add(drone.poseYaw, info, WATER_YAW)
		after(left, add(drone.poseYaw, info, -WATER_YAW))
		left:Play()
	elseif kind == "factory" then
		add(
			drone.poseY,
			TweenInfo.new(FACTORY_HALF, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true),
			-FACTORY_DIP
		):Play()
	end
end

-- The battery / state light (every drone; charger and limp only count on your own).
local function refreshStatus(plotVisual: PlotVisual)
	local plot = plotVisual.plot
	local drone = plotVisual.drone
	local cell = drone.cell
	local onCharger = plotVisual.own and cell ~= nil and DroneSignals.stationAt(cell.X, cell.Y) == "charger"
	local status = DroneSignals.statusLight(
		plot:GetAttribute("Battery"),
		plot:GetAttribute("BatteryMax"),
		onCharger,
		plotVisual.own and drone.limping
	)
	local key = status.key .. (if status.dim then ":dim" else "")
	if key == drone.statusKey then
		return
	end
	drone.statusKey = key
	local light = drone.status
	if drone.simple then
		light.Color = STATUS_COLORS[status.key] -- MID: colour only, no tween, no blink
		return
	end
	TweenService:Create(light, STATUS_FADE, { Color = STATUS_COLORS[status.key] }):Play()
	local blink = drone.statusBlink
	if blink ~= nil then
		blink:Cancel()
		drone.statusBlink = nil
	end
	light.Transparency = if status.dim then 0.5 else 0
	if status.blink then
		local tween = TweenService:Create(light, STATUS_BLINK, { Transparency = 0.85 })
		drone.statusBlink = tween
		tween:Play()
	end
end

-- Limp (your drone): a move clearly slower than normal flattens the bob and dims the light.
local function refreshLimp(plotVisual: PlotVisual)
	local drone = plotVisual.drone
	local limping = plotVisual.own
		and DroneSignals.isLimping(plotVisual.plot:GetAttribute("DroneMoveTime"), DRONE.ActionTimes.move)
	if limping ~= drone.limping then
		drone.limping = limping
		TweenService:Create(drone.bobScale, TweenInfo.new(0.5), { Value = if limping then LIMP_BOB else 1 })
			:Play()
	end
	if plotVisual.own then
		local moving = drone.moveTween
		setRotorPeriod(
			drone,
			rotorPeriodFor(drone, moving ~= nil and moving.PlaybackState == Enum.PlaybackState.Playing)
		)
	end
	refreshStatus(plotVisual)
end

-- The charger rings pulse at `info` (RING_PULSE docked, RING_PULSE_FAST while charging).
local function pulseRings(plotVisual: PlotVisual, info: TweenInfo)
	for _, tween in plotVisual.ringTweens do
		tween:Cancel()
	end
	table.clear(plotVisual.ringTweens)
	for _, ring in plotVisual.chargerGlow do
		ring.Transparency = 0
		local tween = TweenService:Create(ring, info, { Transparency = 0.6 })
		table.insert(plotVisual.ringTweens, tween)
		tween:Play()
	end
end

-- ANIM-7: the charger pad punches 1 -> 1.06 -> 1 (0.3 s) as the drone touches down. Only
-- X / Z grow, and the server pad's own size is restored exactly (teardown too).
local function punchPad(plotVisual: PlotVisual)
	local pad = plotVisual.chargerPad
	if pad == nil or pad.part.Parent == nil then
		return
	end
	local base = pad.size
	pad.part.Size = base
	TweenService:Create(pad.part, PAD_PUNCH, {
		Size = Vector3.new(base.X * PAD_PUNCH_SCALE, base.Y, base.Z * PAD_PUNCH_SCALE),
	}):Play()
end

-- Your drone on a station: the charger rings pulse; the factory's slit and lamp work.
local function refreshStations(plotVisual: PlotVisual, force: boolean?)
	local cell = plotVisual.drone.cell
	local station = if plotVisual.own and cell ~= nil then DroneSignals.stationAt(cell.X, cell.Y) else nil
	if station == plotVisual.activeStation and force ~= true then
		return
	end
	local arriving = station == "charger" and plotVisual.activeStation ~= "charger" and force ~= true
	plotVisual.activeStation = station
	plotVisual.ringFast = false
	if plotVisual.own then
		SoundController.setLoop("charge", false) -- onBattery starts it again while charging
	end
	local shadow = plotVisual.drone.shadow
	if shadow ~= nil then
		TweenService
			:Create(shadow, SHADOW_FADE, { Transparency = if station ~= nil then 1 else SHADOW_ALPHA })
			:Play()
	end
	for _, tween in plotVisual.ringTweens do
		tween:Cancel()
	end
	table.clear(plotVisual.ringTweens)
	local charging = station == "charger"
	local pad = plotVisual.chargerPad
	if pad ~= nil and pad.part.Parent ~= nil then
		pad.part.Material = if charging then Enum.Material.Neon else Enum.Material.SmoothPlastic
		pad.part.Color = if charging then STATUS_COLORS.cyan else PAD_IDLE
	end
	for _, ring in plotVisual.chargerGlow do
		ring.Transparency = 0
		ring.Material = if charging then Enum.Material.Neon else Enum.Material.SmoothPlastic
		ring.Color = if charging then STATUS_COLORS.cyan else STATION_IDLE
	end
	if charging then
		pulseRings(plotVisual, RING_PULSE)
	end
	if arriving then
		-- Punch when it touches down: the end of the landing tween (ANIM-1), or now.
		local moving = plotVisual.drone.moveTween
		local touchdown = if moving ~= nil and moving.PlaybackState == Enum.PlaybackState.Playing
			then moving.TweenInfo.Time * 0.9
			else 0
		task.delay(touchdown, function()
			if visuals[plotVisual.plot] == plotVisual and plotVisual.activeStation == "charger" then
				punchPad(plotVisual)
				SoundController.play("land")
			end
		end)
	end
	plotVisual.dressing.setStation(station)
end

-- Puts every drone part where the render step would put it, right now (first pose, teleports,
-- late Origin / Pitch), so a drone never spends a frame at the world origin under the ground.
-- The shadow's pose: on the tile top straight under the drone's hover point.
local function shadowCFrame(drone: DroneVisual): CFrame
	return CFrame.new(drone.move.Value.Position - Vector3.new(0, DRONE.HoverHeight - 0.08, 0))
end

local function snapDrone(drone: DroneVisual)
	local base = drone.move.Value * CFrame.new(0, -drone.land.Value, 0)
	pcall(function()
		drone.model:PivotTo(base)
	end)
	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	local shadow = drone.shadow
	if shadow ~= nil then
		table.insert(parts, shadow)
		table.insert(cframes, shadowCFrame(drone))
	end
	for _, list in { drone.poses, drone.hatPoses } do
		for _, pose in list do
			table.insert(parts, pose.part)
			table.insert(cframes, base * pose.offset)
		end
	end
	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

--[[
	Tween the drone to a cell (attribute, remote, or poll). Without `cellOverride` the cell and
	its serial come from the plot attributes; with it, pass the serial that came with it (the
	DroneMoved payload, the poll's attribute read, the cached last remote).
	SERIAL ORDER (BUG-05): a non-instant update moves the drone only when its DroneSerial is
	NEWER than the one it shows (Shared.Util.DroneSignals.shouldApply), so a remote that beats
	the attributes (or a lagging attribute after the remote) can never tween the drone back,
	and duplicate fires never restart a running tween. An instant pose adopts the serial it was
	given, so the poll stays in step with the attributes afterwards.
]]
local function updateDroneTarget(
	plotVisual: PlotVisual,
	instant: boolean,
	cellOverride: Vector2?,
	serialOverride: number?
)
	local plot = plotVisual.plot
	local drone = plotVisual.drone
	local cell = cellOverride or readDroneCell(plot)
	local serial = if cellOverride ~= nil then serialOverride else readDroneSerial(plot)
	-- Without all three the drone can't be placed; the Origin / Pitch / Drone listeners retry.
	if
		cell == nil
		or typeof(plot:GetAttribute("Origin")) ~= "Vector3"
		or type(plot:GetAttribute("Pitch")) ~= "number"
	then
		return
	end
	local previous = drone.cell
	if instant then
		drone.serial = serial
	else
		if not DroneSignals.shouldApply(drone.serial, serial, not sameCell(previous, cell)) then
			return -- an older (or the same) move: never tween back, never restart a tween
		end
		if serial ~= nil then
			drone.serial = serial
		end
		if sameCell(previous, cell) then
			return -- a newer serial for the cell already shown: nothing to animate
		end
	end
	local target = cellCFrame(plot, cell)
	drone.cell = cell
	-- Your drone leaves a fading dot on every field tile it flies off (not on teleports).
	if
		plotVisual.own
		and not instant
		and previous ~= nil
		and previous.Y >= 0
		and (cell - previous).Magnitude <= 1.5
		and cell ~= previous
	then
		dropGhost(plotVisual, previous)
	end

	if drone.simple then
		-- MID: snap to the cell (facing the move), no tween, no RenderStepped composition.
		local delta = target.Position - drone.move.Value.Position
		local facing = if previous ~= nil and delta.Magnitude > 0.01
			then CFrame.lookAt(Vector3.zero, Vector3.new(delta.X, 0, delta.Z)).Rotation
			else drone.move.Value.Rotation
		drone.move.Value = target * facing
		for _, pose in drone.poses do
			pose.part.CFrame = drone.move.Value * pose.offset
		end
		return
	end
	if instant or previous == nil or (cell - previous).Magnitude > 1.5 then
		-- Teleport / first pose: snap. No takeoff, no landing animation; a drone that appears
		-- on the charger is simply already docked (your drone).
		if drone.moveTween ~= nil then
			drone.moveTween:Cancel()
			drone.moveTween = nil
		end
		cancelFlight(drone)
		cancelPose(drone)
		drone.lift.Value = 0
		drone.roll.Value = 0
		drone.land.Value = if plotVisual.own and isCharger(cell) then LAND_DROP else 0
		if plotVisual.own then
			setRotorPeriod(drone, rotorPeriodFor(drone, false))
		end
		drone.move.Value = target * drone.move.Value.Rotation
		snapDrone(drone)
		return
	end

	-- Face the travel direction: the rotation is part of the tween target.
	local delta = target.Position - drone.move.Value.Position
	local facing = if delta.Magnitude > 0.01
		then CFrame.lookAt(Vector3.zero, Vector3.new(delta.X, 0, delta.Z)).Rotation
		else drone.move.Value.Rotation
	local duration = ((plot:GetAttribute("DroneMoveTime") :: number?) or DRONE.ActionTimes.move)
		* DRONE.TweenFraction

	if drone.moveTween ~= nil then
		drone.moveTween:Cancel()
	end
	local oldLook = drone.move.Value.LookVector
	local tween = TweenService:Create(
		drone.move,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{
			Value = target * facing,
		}
	)
	drone.moveTween = tween
	tween:Play()
	if plotVisual.own then
		cancelPose(drone) -- a move always wins over an action pose
		startFlight(drone, cell, oldLook, facing.LookVector, duration)
		tween.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and drone.moveTween == tween then
				drone.moveTween = nil
				setRotorPeriod(drone, rotorPeriodFor(drone, false)) -- hovering: idle rotors
			end
		end)
	end
	TweenService:Create(
		drone.tilt,
		TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true),
		{
			Value = 1,
		}
	):Play()
end

---------------------------------------------------------------------------------- crops
local function tileTopCFrame(tile: BasePart): CFrame
	local x = (tile:GetAttribute("X") :: number?) or 0
	local y = (tile:GetAttribute("Y") :: number?) or 0
	local yaw = math.rad(((x * 73 + y * 37) % 8) * 45) -- fixed per tile: varied but stable
	return CFrame.new(tile.Position + Vector3.new(0, tile.Size.Y / 2, 0)) * CFrame.Angles(0, yaw, 0)
end

-- Plays a tween and counts it while it runs (FxTweens debug attribute + neighbour-sway guard).
-- Counted by its nominal length, so tweens on destroyed or overridden parts never leak.
local function playTracked(tween: Tween): Tween
	local info = tween.TweenInfo
	activeTweens += 1
	task.delay(info.Time + info.DelayTime, function()
		activeTweens -= 1
	end)
	tween:Play()
	return tween
end

local function tinted(color: Color3): Color3
	return if cropTint > 0 then color:Lerp(STRAW_COLOR, cropTint) else color
end

local function roleColor(role: string, mainColor: Color3): Color3
	return tinted(
		if role == "main"
			then mainColor
			elseif role == "stem" then STEM_COLOR
			elseif role == "leaf" then LEAF_COLOR
			else DARK_COLOR
	)
end

-- A recipe part's colour: its fixed colour, else its role colour (both weather-tinted).
local function partColor(item: PartSpec, mainColor: Color3): Color3
	local fixed = item.color
	return if fixed ~= nil then tinted(fixed) else roleColor(item.role, mainColor)
end

-- A part's rest pose (relative to the tile top) at a growth scale.
local function restFrame(item: PartSpec, scale: number): CFrame
	return CFrame.new(item.frame.Position * FULL * scale) * item.frame.Rotation
end

local function newCropVisual(tile: BasePart, cropId: string, base: CFrame, stage: string): CropVisual
	local x = (tile:GetAttribute("X") :: number?) or 0
	local y = (tile:GetAttribute("Y") :: number?) or 0
	local phase = x * 1.9 + y * 2.7 -- neighbours sway out of step
	return {
		cropId = cropId,
		tile = tile,
		parts = {},
		specs = {},
		model = nil,
		stage = stage,
		base = base,
		scale = -1,
		mainColor = Color3.new(1, 1, 1),
		ready = false,
		restParts = {},
		restLocal = {},
		restAt = math.huge,
		swaying = false,
		swayCos = math.cos(phase),
		swaySin = math.sin(phase),
		marker = nil,
		proxy = false,
	}
end

-- Tweens a procedural crop to `scale` and records each part's rest pose (used by the sway).
local function poseProcedural(visual: CropVisual, scale: number, mainColor: Color3, info: TweenInfo): Tween?
	local last: Tween? = nil
	for index, spec in visual.specs do
		local rest = restFrame(spec, scale)
		visual.restLocal[index] = rest
		last = playTracked(TweenService:Create(visual.parts[index], info, {
			Size = spec.size * FULL * scale,
			CFrame = visual.base * rest,
			Color = partColor(spec, mainColor),
		}))
	end
	return last
end

-- Poses a procedural crop at once (first sight / tier rebuilds: no grow-in tweens).
local function poseInstant(visual: CropVisual, scale: number, mainColor: Color3)
	for index, spec in visual.specs do
		local rest = restFrame(spec, scale)
		visual.restLocal[index] = rest
		local part = visual.parts[index]
		part.Size = spec.size * FULL * scale
		part.CFrame = visual.base * rest
		part.Color = partColor(spec, mainColor)
	end
end

--[[
	Creates the parts of `recipe` for a crop visual, posed at once at `scale` (a new crop starts
	tiny; a stage swap starts at the old scale, then tweens on). Sprouts, grass and noShadow
	parts cast no shadow (docs/ART_BIBLE.md §3.4).
]]
local function buildCropParts(
	plotVisual: PlotVisual,
	visual: CropVisual,
	recipe: { PartSpec },
	mainColor: Color3,
	scale: number,
	shadows: boolean
)
	for _, part in visual.parts do
		part:Destroy()
	end
	table.clear(visual.parts)
	table.clear(visual.restParts)
	table.clear(visual.restLocal)
	visual.specs = recipe
	for index, item in recipe do
		local part = decorPart(
			"Crop" .. index,
			item.size * FULL * scale,
			partColor(item, mainColor),
			Enum.Material.Plastic,
			item.shape
		)
		if item.mesh == "sphere" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere -- an ellipsoid that follows the part's Size
			mesh.Parent = part
		end
		part.CastShadow = shadows and item.noShadow ~= true
		local rest = restFrame(item, scale)
		part.CFrame = visual.base * rest
		part.Parent = plotVisual.folder
		visual.parts[index] = part
		visual.restParts[index] = part
		visual.restLocal[index] = rest
	end
end

-- MID tier proxies: ONE plain part per tile, in multiples of FULL (centre height = lift or
-- half the height).
local PROXY: { [string]: { size: Vector3, ball: boolean, lift: number? } } = {
	grass = { size = Vector3.new(0.6, 0.35, 0.6), ball = false },
	stalk = { size = Vector3.new(0.35, 1.0, 0.35), ball = false },
	bush = { size = Vector3.new(0.6, 0.6, 0.6), ball = true },
	tree = { size = Vector3.new(1, 1, 1), ball = true, lift = 1.15 },
	flower = { size = Vector3.new(0.45, 1.1, 0.45), ball = false },
	round = { size = Vector3.new(0.85, 0.85, 0.85), ball = true },
	cactus = { size = Vector3.new(0.35, 1.0, 0.35), ball = false },
}

-- Overshoot to `scale * peak`, then settle: the growth pop (1.08) and the ready silhouette
-- cue (1.12). Returns the seconds until the crop is at rest.
local function popProcedural(
	plotVisual: PlotVisual,
	visual: CropVisual,
	scale: number,
	mainColor: Color3,
	peak: number
): number
	local up = poseProcedural(visual, scale * peak, mainColor, POP_UP)
	if up ~= nil then
		up.Completed:Once(function(playbackState: Enum.PlaybackState)
			-- A newer update cancels the pop; that update then owns the final pose.
			if playbackState == Enum.PlaybackState.Completed and plotVisual.crops[visual.tile] == visual then
				poseProcedural(visual, scale, mainColor, POP_SETTLE)
			end
		end)
	end
	return POP_UP.Time + POP_SETTLE.Time
end

-- The same pop for artist models: a short NumberValue tween drives Model:ScaleTo.
local function popModel(model: Model, scale: number, peak: number): number
	local value = Instance.new("NumberValue")
	value.Value = scale
	value.Changed:Connect(function()
		if model.Parent ~= nil then
			model:ScaleTo(math.max(0.05, value.Value))
		end
	end)
	local up = playTracked(TweenService:Create(value, POP_UP, { Value = scale * peak }))
	up.Completed:Once(function()
		local settle = playTracked(TweenService:Create(value, POP_SETTLE, { Value = scale }))
		settle.Completed:Once(function()
			value:Destroy()
		end)
	end)
	return POP_UP.Time + POP_SETTLE.Time
end

-- Artist models ease toward a new growth scale (ANIM-3) through ONE NumberValue per model
-- that drives Model:ScaleTo (the pivot, the tile top, stays put). Destroyed with the model.
local function scaleModelTo(model: Model, scale: number)
	local driver = model:FindFirstChild("GrowScale")
	if driver == nil or not driver:IsA("NumberValue") then
		local created = Instance.new("NumberValue")
		created.Name = "GrowScale"
		created.Value = model:GetScale()
		created.Changed:Connect(function(value: number)
			if model.Parent ~= nil then
				model:ScaleTo(math.max(0.05, value))
			end
		end)
		created.Parent = model
		driver = created
	end
	playTracked(TweenService:Create(driver :: NumberValue, GROW_LERP, { Value = scale }))
end

-- Puts a crop back on its rest pose (when it stops swaying).
local function restPose(visual: CropVisual)
	for index, part in visual.restParts do
		local rest = visual.restLocal[index] :: CFrame?
		if rest ~= nil and part.Parent ~= nil then
			part.CFrame = visual.base * rest
		end
	end
end

-- Artist models: remember every part's pose relative to the tile once the model is at rest.
local function captureModelRest(visual: CropVisual, model: Model)
	table.clear(visual.restParts)
	table.clear(visual.restLocal)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(visual.restParts, descendant)
			table.insert(visual.restLocal, visual.base:ToObjectSpace(descendant.CFrame))
		end
	end
end

local function destroyCrop(plotVisual: PlotVisual, tile: BasePart, animate: boolean)
	local visual = plotVisual.crops[tile]
	if visual == nil then
		return
	end
	plotVisual.crops[tile] = nil
	visual.swaying = false
	local marker = visual.marker
	if marker ~= nil then
		marker:Destroy()
	end
	local model = visual.model
	if model ~= nil then
		model:Destroy()
	end
	for _, part in visual.parts do
		if animate then
			local shrink = TweenService:Create(
				part,
				TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In),
				{
					Size = Vector3.new(0.05, 0.05, 0.05),
				}
			)
			shrink.Completed:Connect(function()
				part:Destroy()
			end)
			shrink:Play()
		else
			part:Destroy()
		end
	end
end

--[[
	Crop look for a tile: shape from CropConfig, size/colour from State + Progress.
	`style` picks the animation (only when `juicy`, i.e. full effects for this plot):
	  plain   the growth tween between Progress steps (always)
	  plant   the same, delayed until the seed has dropped into the tile
	  sprout  planted -> growing: pop to 1.08x, then settle
	  ready   silhouette cue: pop to 1.12x, then settle (and matte -> glossy)
]]
local function updateCrop(plotVisual: PlotVisual, tile: BasePart, style: Style, juicy: boolean)
	local state = tile:GetAttribute("State")
	local cropId = tile:GetAttribute("Crop")
	local crop = if type(cropId) == "string" then CropConfig.Crops[cropId] else nil

	if state == "empty" or state == nil or crop == nil or type(cropId) ~= "string" then
		destroyCrop(plotVisual, tile, plotVisual.tier == "near")
		return
	end
	local existing: CropVisual? = plotVisual.crops[tile]
	if existing ~= nil and existing.cropId ~= cropId then
		destroyCrop(plotVisual, tile, false)
		existing = nil
	end

	local progress = (tile:GetAttribute("Progress") :: number?) or 0
	local ready = state == "ready"
	local scale = if ready then 1 else 0.25 + 0.6 * progress
	local stage = if ready then "ready" elseif progress < 0.5 then "sprout" else "growing"
	local mainColor = if ready
		then rgb(crop.color)
		else rgb(CropConfig.SproutColor):Lerp(rgb(crop.color), progress * 0.6)
	local base = tileTopCFrame(tile)
	local now = os.clock()
	local peak = if not juicy
		then nil
		elseif style == "ready" then READY_PEAK
		elseif style == "sprout" then SPROUT_PEAK
		else nil

	-- MID tier: one snapped plain part per tile; sprouts aren't drawn.
	if plotVisual.tier ~= "near" then
		if existing ~= nil and not existing.proxy then
			destroyCrop(plotVisual, tile, false)
			existing = nil
		end
		if stage == "sprout" then
			destroyCrop(plotVisual, tile, false)
			return
		end
		local recipe = PROXY[crop.shape] or PROXY.bush
		local proxy = existing
		if proxy == nil then
			local created = newCropVisual(tile, cropId, base, stage)
			created.proxy = true
			local part = decorPart(
				"CropProxy",
				recipe.size,
				mainColor,
				Enum.Material.SmoothPlastic,
				if recipe.ball then BALL else nil
			)
			part.CastShadow = false
			part.Parent = plotVisual.folder
			created.parts[1] = part
			plotVisual.crops[tile] = created
			proxy = created
		end
		local current: CropVisual = proxy :: CropVisual
		current.scale = scale
		current.ready = ready
		current.stage = stage
		current.mainColor = mainColor
		local part = current.parts[1]
		part.Size = recipe.size * FULL * scale
		part.Color = roleColor("main", mainColor)
		part.CFrame = base * CFrame.new(0, (recipe.lift or recipe.size.Y / 2) * FULL * scale, 0)
		return
	end

	-- Artist model for this crop + stage? (AssetLibrary already made it inert.)
	local visual: CropVisual? = existing
	if visual == nil or visual.model ~= nil then
		local previous = visual
		if previous ~= nil then
			local previousModel = previous.model
			if previousModel ~= nil and previous.stage == stage then
				previous.ready = ready
				if previous.scale ~= scale then
					previous.scale = scale
					previous.swaying = false
					table.clear(previous.restParts) -- re-captured once it is at rest
					table.clear(previous.restLocal)
					-- Ease toward the new size inside the stage (ANIM-3); pivot = tile top.
					scaleModelTo(previousModel, scale)
					previous.restAt = now + GROW_LERP.Time
				end
				return
			end
		end
		local model = AssetLibrary.crop(cropId, stage)
		if model ~= nil then
			if visual ~= nil then
				destroyCrop(plotVisual, tile, false)
			end
			model:PivotTo(base)
			model:ScaleTo(math.max(0.05, scale))
			model.Parent = plotVisual.folder
			local created = newCropVisual(tile, cropId, base, stage)
			created.model = model
			created.scale = scale
			created.ready = ready
			created.restAt = now + (if peak ~= nil then popModel(model, scale, peak) else 0)
			plotVisual.crops[tile] = created
			return
		end
		if visual ~= nil then
			-- This stage has no artist model: fall back to the procedural shape.
			destroyCrop(plotVisual, tile, false)
			visual = nil
		end
	end

	-- Procedural low-poly shape: one recipe per stage, so READY changes the silhouette too.
	local recipes = SHAPES[crop.shape] or SHAPES.bush
	local recipe = recipes[stage :: any] :: { PartSpec }
	local shadows = stage ~= "sprout" and crop.shape ~= "grass"
	if visual == nil then
		local created = newCropVisual(tile, cropId, base, stage)
		plotVisual.crops[tile] = created
		-- First sight poses at once below; a freshly planted crop grows in from 10 %.
		buildCropParts(
			plotVisual,
			created,
			recipe,
			mainColor,
			if style == "initial" then scale else 0.1,
			shadows
		)
		visual = created
	elseif visual.specs ~= recipe then
		-- Stage change: swap to the new silhouette at the old size, then tween on.
		local swapping: CropVisual = visual
		buildCropParts(plotVisual, swapping, recipe, mainColor, math.max(0.1, swapping.scale), shadows)
		swapping.swaying = false
		swapping.scale = -1 -- force the pose below
	end
	assert(visual ~= nil, "crop visual was just created")
	local current: CropVisual = visual
	if current.scale == scale and current.ready == ready then
		return -- nothing visible changed (e.g. only Watered flipped): no tweens
	end
	current.scale = scale
	current.mainColor = mainColor
	current.ready = ready
	current.stage = stage
	current.swaying = false -- the tweens own the parts until `restAt`

	-- Ripe crops read glossy; growing ones stay matte (wild grass uses the Grass material).
	local material = if ready
		then Enum.Material.SmoothPlastic
		elseif crop.shape == "grass" then Enum.Material.Grass
		else Enum.Material.Plastic
	for _, part in current.parts do
		part.Material = material
	end

	if style == "initial" then
		poseInstant(current, scale, mainColor)
		current.restAt = now
	elseif peak ~= nil then
		current.restAt = now + popProcedural(plotVisual, current, scale, mainColor, peak)
	elseif style == "plain" and not ready then
		-- Between Progress ticks (ANIM-3): ease toward the published size, no overshoot.
		poseProcedural(current, scale, mainColor, GROW_LERP)
		current.restAt = now + GROW_LERP.Time
	else
		local delay = if juicy and style == "plant" then SEED_FALL.Time else 0
		local info = TweenInfo.new(
			if ready then 0.45 else 0.3,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.Out,
			0,
			false,
			delay
		)
		poseProcedural(current, scale, mainColor, info)
		current.restAt = now + delay + info.Time
	end
end

-------------------------------------------------------------------------------- crop fx
-- Is the drone over (or right next to) this tile? Seed drops and droplets need it.
local function droneNear(plotVisual: PlotVisual, tile: BasePart): boolean
	local cell = plotVisual.drone.cell
	local x = tile:GetAttribute("X")
	local y = tile:GetAttribute("Y")
	if cell == nil or type(x) ~= "number" or type(y) ~= "number" then
		return false
	end
	return math.abs(cell.X - x) <= FX.DroneNear and math.abs(cell.Y - y) <= FX.DroneNear
end

-- The plot's emitter for one burst kind + colour variant, cloned once from the template
-- into the plot's single FX attachment. Emitters are never Enabled; bursts use :Emit(n).
local function emitterFor(
	fx: FxState,
	attachment: Attachment,
	kind: string,
	variant: string,
	colors: ColorSequence
): ParticleEmitter
	local key = kind .. ":" .. variant
	local existing = fx.emitters[key] :: ParticleEmitter?
	if existing ~= nil then
		return existing
	end
	local spec = BURSTS[kind]
	local emitter = emitterTemplate:Clone()
	emitter.Name = key
	emitter.Lifetime = NumberRange.new(spec.lifetime)
	emitter.Speed = spec.speed
	emitter.SpreadAngle = Vector2.new(spec.spread, spec.spread)
	emitter.EmissionDirection = spec.direction
	emitter.Acceleration = spec.acceleration
	emitter.Drag = spec.drag
	emitter.Size = spec.size
	emitter.Texture = spec.texture
	emitter.LightEmission = spec.lightEmission
	local fade = spec.transparency
	if fade ~= nil then
		emitter.Transparency = fade
	end
	emitter.Color = colors
	emitter.Parent = attachment
	fx.emitters[key] = emitter
	return emitter
end

-- The plot's single FX anchor part + attachment, created on the first burst (NEAR only).
local function ensureFxAnchor(plotVisual: PlotVisual): Attachment
	local fx = plotVisual.fx
	local existing = fx.attachment
	if existing ~= nil then
		return existing
	end
	local anchor =
		decorPart("FxAnchor", Vector3.new(0.2, 0.2, 0.2), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	anchor.CastShadow = false
	local origin = plotVisual.plot:GetAttribute("Origin")
	anchor.CFrame = CFrame.new(if typeof(origin) == "Vector3" then origin else Vector3.zero)
	anchor.Parent = plotVisual.folder
	local attachment = Instance.new("Attachment")
	attachment.Name = "CropFx"
	attachment.Parent = anchor
	fx.anchor = anchor
	fx.attachment = attachment
	return attachment
end

-- Rotor wash (ART-5): a 3-particle dust puff on the ground where your drone lifts off.
local function rotorWash(plotVisual: PlotVisual, ground: Vector3)
	local fx = plotVisual.fx
	if #fx.queue >= FX.MaxQueued then
		return
	end
	local spec = BURSTS.wash
	table.insert(fx.queue, {
		emitter = emitterFor(fx, ensureFxAnchor(plotVisual), "wash", "wash", WASH_COLORS),
		position = ground + Vector3.new(0, spec.lift, 0),
		count = WASH_PUFF,
		lifetime = spec.lifetime,
	})
end

-- A low-priority burst not tied to a tile (chimney bits, smoke): waits behind harvests.
local function queueLoose(
	plotVisual: PlotVisual,
	kind: string,
	colors: ColorSequence,
	position: Vector3,
	count: number
)
	local fx = plotVisual.fx
	if #fx.queue >= FX.MaxQueued then
		return
	end
	local spec = BURSTS[kind]
	table.insert(fx.queue, {
		emitter = emitterFor(fx, ensureFxAnchor(plotVisual), kind, kind, colors),
		position = position + Vector3.new(0, spec.lift, 0),
		count = count,
		lifetime = spec.lifetime,
		low = true,
	})
end

--[[
	An aimed burst (ANIM-4): `count` bits from `from` toward `target`, fast enough to arrive
	within the burst's lifetime, aimed a little high so gravity brings them onto it. The speed
	is capped (UNLOAD_SPEED_MAX), so a far target only sets the direction. Low priority.
]]
local function queueAimed(
	plotVisual: PlotVisual,
	kind: string,
	colors: ColorSequence,
	from: Vector3,
	target: Vector3,
	count: number
)
	local fx = plotVisual.fx
	if #fx.queue >= FX.MaxQueued then
		return
	end
	local spec = BURSTS[kind]
	local travel = spec.lifetime * 0.85
	local distance = (target - from).Magnitude
	local speed = math.clamp(distance / travel, 4, UNLOAD_SPEED_MAX)
	local time = math.min(travel, distance / speed)
	local drop = 0.5 * UNLOAD_GRAVITY * time * time
	table.insert(fx.queue, {
		emitter = emitterFor(fx, ensureFxAnchor(plotVisual), kind, kind, colors),
		position = from,
		count = count,
		lifetime = spec.lifetime,
		aim = target + Vector3.new(0, drop, 0),
		speed = NumberRange.new(speed * 0.9, speed * 1.1),
		low = true,
	})
end

-- Queues a burst on a tile; at most one burst per tile at a time (later ones are dropped).
local function queueBurst(
	plotVisual: PlotVisual,
	tile: BasePart,
	kind: string,
	variant: string,
	colors: ColorSequence,
	top: Vector3,
	count: number
)
	local fx = plotVisual.fx
	local now = os.clock()
	local spec = BURSTS[kind]
	if (fx.busy[tile] or 0) > now or #fx.queue >= FX.MaxQueued then
		return
	end
	fx.busy[tile] = now + spec.lifetime
	table.insert(fx.queue, {
		emitter = emitterFor(fx, ensureFxAnchor(plotVisual), kind, variant, colors),
		position = top + Vector3.new(0, spec.lift, 0),
		count = count,
		lifetime = spec.lifetime,
	})
end

-- One burst per plot per frame: the plot's single attachment moves to the burst's tile and
-- emits there. Bursts that don't fit the live-particle budget shrink or are dropped.
local function drainBursts()
	for _, plotVisual in visuals do
		local fx = plotVisual.fx
		if #fx.queue == 0 then
			continue
		end
		-- Harvest (and every other normal burst) goes before a low-priority unload burst.
		local index = 1
		for i, queued in fx.queue do
			if queued.low ~= true then
				index = i
				break
			end
		end
		local burst = table.remove(fx.queue, index)
		if burst == nil then
			continue
		end
		local count = CropTransitions.burstSize(burst.count, activeParticles, FX.MaxParticles)
		if count <= 0 then
			continue
		end
		local attachment = fx.attachment
		if attachment == nil then
			continue
		end
		-- Unrotated for Top bursts; turned toward the target for aimed (Front) bursts.
		local aim = burst.aim
		attachment.WorldCFrame = if aim ~= nil and (aim - burst.position).Magnitude > 0.01
			then CFrame.lookAt(burst.position, aim)
			else CFrame.new(burst.position)
		local speed = burst.speed
		if speed ~= nil then
			burst.emitter.Speed = speed
		end
		burst.emitter:Emit(count)
		activeParticles += count
		task.delay(burst.lifetime, function()
			activeParticles -= count
		end)
	end
end

-- Planting: a seed falls from the drone into the tile (0.2 s), then disappears.
local function seedDrop(plotVisual: PlotVisual, top: Vector3)
	local seed =
		decorPart("Seed", Vector3.new(0.34, 0.34, 0.34), SEED_COLOR, Enum.Material.SmoothPlastic, BALL)
	seed.CastShadow = false
	seed.CFrame = CFrame.new(plotVisual.drone.move.Value.Position - Vector3.new(0, 0.45, 0))
	seed.Parent = plotVisual.folder
	local fall = playTracked(
		TweenService:Create(seed, SEED_FALL, { CFrame = CFrame.new(top + Vector3.new(0, 0.17, 0)) })
	)
	fall.Completed:Once(function()
		seed:Destroy()
	end)
end

-- Ready (own plot only): a flat lime neon disc expands over the soil and fades.
local function readyPing(plotVisual: PlotVisual, top: Vector3)
	local disc =
		decorPart("ReadyPing", Vector3.new(0.06, 0.8, 0.8), LIME, Enum.Material.Neon, Enum.PartType.Cylinder)
	disc.CastShadow = false
	disc.Transparency = 0.15
	disc.CFrame = CFrame.new(top + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)) -- axis up
	disc.Parent = plotVisual.folder
	local width = GRID.TileSize * 0.95
	local grow = playTracked(
		TweenService:Create(disc, PING, { Size = Vector3.new(0.06, width, width), Transparency = 1 })
	)
	grow.Completed:Once(function()
		disc:Destroy()
	end)
end

-- The lime "ready" dot above a ripe crop (Control Mode, own plot). Built once per crop.
local function ensureMarker(plotVisual: PlotVisual, visual: CropVisual): BillboardGui
	local existing = visual.marker
	if existing ~= nil then
		return existing
	end
	local height = 0
	local model = visual.model
	if model ~= nil then
		height = model:GetExtentsSize().Y
	else
		for _, spec in visual.specs do
			height = math.max(height, (spec.frame.Position.Y + spec.size.Y / 2) * FULL)
		end
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ReadyMarker"
	gui.Adornee = visual.tile -- a reference only: the marker itself lives in the plot's visual folder
	gui.Size = UDim2.new(0.15, 8, 0.15, 8) -- 0.15 studs + 8 px, so it still reads from bird's-eye
	gui.StudsOffsetWorldSpace = Vector3.new(0, visual.tile.Size.Y / 2 + height + 0.6, 0)
	gui.LightInfluence = 0 -- unlit
	gui.AlwaysOnTop = false
	gui.Enabled = false
	local dot = Instance.new("Frame")
	dot.Name = "Dot"
	dot.Size = UDim2.fromScale(1, 1)
	dot.BackgroundColor3 = LIME
	dot.BorderSizePixel = 0
	dot.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = dot
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(16, 30, 14)
	stroke.Transparency = 0.3
	stroke.Parent = dot
	gui.Parent = plotVisual.folder
	visual.marker = gui
	return gui
end

-- A 0.15 s tool flash under your drone (a transient part, destroyed right after). `depth`:
-- how far the action pose dips the body (ANIM-2), so the flash stays under it.
local function toolFlash(plotVisual: PlotVisual, color: Color3, depth: number)
	local flash =
		decorPart("ToolFlash", Vector3.new(0.05, 0.7, 0.7), color, Enum.Material.Neon, Enum.PartType.Cylinder)
	flash.CastShadow = false
	flash.Transparency = 0.2
	-- Just under the body at the ToolMount (0, -0.45, -0.3), flat.
	flash.CFrame = plotVisual.drone.move.Value
		* CFrame.new(0, -0.65 - depth, -0.3)
		* CFrame.Angles(0, 0, math.rad(90))
	flash.Parent = plotVisual.folder
	local grow = playTracked(
		TweenService:Create(flash, TOOL_FLASH, { Size = Vector3.new(0.05, 1.8, 1.8), Transparency = 1 })
	)
	grow.Completed:Once(function()
		flash:Destroy()
	end)
end

-- Is the drone exactly over this tile?
local function droneOver(plotVisual: PlotVisual, tile: BasePart): boolean
	local cell = plotVisual.drone.cell
	return cell ~= nil and tile:GetAttribute("X") == cell.X and tile:GetAttribute("Y") == cell.Y
end

-- Coalesced: every attribute change of a tile schedules ONE refresh (task.defer), so a
-- publishTile (State + Crop + Watered + Progress) is diffed as a single, consistent update.
local function refreshTile(plotVisual: PlotVisual, tile: BasePart)
	plotVisual.pending[tile] = nil
	if visuals[plotVisual.plot] ~= plotVisual or tile.Parent == nil then
		return
	end
	local current = CropTransitions.snapshot(
		tile:GetAttribute("State"),
		tile:GetAttribute("Crop"),
		tile:GetAttribute("Watered"),
		tile:GetAttribute("Progress")
	)
	local previous = plotVisual.snaps[tile]
	plotVisual.snaps[tile] = current
	local events = CropTransitions.diff(previous, current)
	local juicy = plotVisual.fullFx
	local planted = CropConfig.Crops[current.crop]
	local plantedWild = planted ~= nil and planted.wild == true
	local raining = PlotSpace.weather(plotVisual.plot) == "Rainy"
	-- Wild grass regrows by itself: no seed drop for it.
	local seed = juicy and events.plant and not plantedWild and droneNear(plotVisual, tile)
	local style: Style = if previous == nil
		then "initial"
		elseif events.ready then "ready"
		elseif events.sprout then "sprout"
		elseif seed then "plant"
		else "plain"

	updateCrop(plotVisual, tile, style, juicy)
	-- Soil state (docs/ART_BIBLE.md §2.4): Dry / Tilled / Wet / Dug, via Visuals.SoilLook.
	local soil = SoilStates.forTile(
		current.state,
		current.crop,
		current.watered,
		tile:GetAttribute("Exhausted") == true
	)
	local flash = juicy and events.harvest
	local wasSoil = plotVisual.soil[tile]
	if soil ~= wasSoil or flash then
		plotVisual.soil[tile] = soil
		if plotVisual.own and wasSoil ~= nil and wasSoil ~= "SoilDug" and soil == "SoilDug" then
			SoundController.play("dig") -- dig() exhausted this tile (never on first sight)
		end
		SoilLook.apply(
			tile,
			soil,
			if flash then SOIL_DUST_FLASH else nil,
			previous == nil or plotVisual.tier ~= "near"
		)
	end
	if not juicy then
		return -- distant plots: growth tweens only
	end

	local top = tile.Position + Vector3.new(0, tile.Size.Y / 2, 0)
	if events.harvest then
		local harvested = CropConfig.Crops[events.harvestedCrop]
		if events.ripe and harvested ~= nil then
			local color = rgb(harvested.color)
			queueBurst(
				plotVisual,
				tile,
				"harvest",
				events.harvestedCrop,
				ColorSequence.new(color, color:Lerp(Color3.new(1, 1, 1), 0.35)),
				top,
				HARVEST_BITS[harvested.shape] or 9
			)
		else
			queueBurst(plotVisual, tile, "harvest", "unripe", UNRIPE_COLORS, top, UNRIPE_BITS)
		end
	end
	if seed then
		seedDrop(plotVisual, top)
	end
	if events.sprout then
		queueBurst(plotVisual, tile, "leaf", "leaf", LEAF_COLORS, top, 8)
	end
	if events.ready and plotVisual.own then
		readyPing(plotVisual, top)
	end
	-- Rain waters whole fields at once: only the soil darkens, no droplets.
	if events.water and not raining and droneNear(plotVisual, tile) then
		queueBurst(plotVisual, tile, "water", "water", WATER_COLORS, top, math.random(4, 6))
	end
	-- Your drone's tool flash + body pose (ANIM-2), only for actions we are sure about
	-- (DroneSignals.action: never unripe harvests, wild-grass regrowth or rain).
	if plotVisual.own then
		local over = droneOver(plotVisual, tile)
		local action = DroneSignals.action(events, plantedWild, over, raining)
		if action ~= nil then
			toolFlash(
				plotVisual,
				ACTION_COLORS[action],
				if action == "plant" then PLANT_DIP elseif action == "harvest" then SCOOP_DIP else 0
			)
			playPose(plotVisual.drone, action)
			SoundController.play(action) -- "plant" | "harvest" | "water"
		elseif events.harvest and not events.ripe and over then
			SoundController.play("unripe")
		end
	end
end

local function watchTile(plotVisual: PlotVisual, child: Instance)
	if not child:IsA("BasePart") or string.sub(child.Name, 1, 5) ~= "Tile_" then
		return
	end
	local tile = child :: BasePart
	local function schedule()
		if plotVisual.pending[tile] then
			return
		end
		plotVisual.pending[tile] = true
		task.defer(refreshTile, plotVisual, tile)
	end
	for _, attribute in { "State", "Crop", "Progress", "Watered", "Exhausted" } do
		table.insert(plotVisual.connections, tile:GetAttributeChangedSignal(attribute):Connect(schedule))
	end
	refreshTile(plotVisual, tile)
end

---------------------------------------------------------------------------------- lod
-- Distance from the nearer of the character and the camera to the plot's Zone box.
local function plotDistance(plot: Model): number
	local best = math.huge
	local point = PlotSpace.referencePoint()
	if point ~= nil then
		best = PlotSpace.distanceToPlot(plot, point)
	end
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		best = math.min(best, PlotSpace.distanceToPlot(plot, camera.CFrame.Position))
	end
	return best
end

-- The tier a plot should have (hysteresis around both edges). Your own plot is always NEAR, so
-- walking the hub never makes it pop in again when you return to Control Mode.
local function desiredTier(plot: Model, current: string?, distance: number): string
	if PlotSpace.isOwn(plot) then
		return "near"
	end
	local slack = FX.TierSlack
	local nearEdge = FX.NearRadius
		+ (if current == "near" then slack elseif current == nil then 0 else -slack)
	local farEdge = FX.FarRadius + (if current == "far" then -slack elseif current == nil then 0 else slack)
	if distance < nearEdge then
		return "near"
	elseif distance <= farEdge then
		return "mid"
	end
	return "far"
end

-- ART-5: only YOUR near drone casts the soft ground shadow (no other drone gets one).
local function refreshShadow(plotVisual: PlotVisual)
	local drone = plotVisual.drone
	local want = plotVisual.own and plotVisual.tier == "near"
	local current = drone.shadow
	if current ~= nil then
		if not want then
			current:Destroy() -- takes the beam with it (it lives in the shadow part)
			drone.shadow = nil
			local head = drone.beam and drone.beam.Attachment1
			if head ~= nil then
				head:Destroy()
			end
			drone.beam = nil
		end
		return
	end
	if not want then
		return
	end
	local part = decorPart("DroneShadow", SHADOW_SIZE, SHADOW_COLOR, Enum.Material.SmoothPlastic)
	part.CastShadow = false
	part.Transparency = SHADOW_ALPHA
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere -- a soft-edged ellipse, not a hard square
	mesh.Parent = part
	part.CFrame = shadowCFrame(drone)
	part.Parent = drone.model
	drone.shadow = part
	-- V-CONTACT: a thin cyan height beam from the shadow up to the body. Both ends are
	-- attachments in parts BulkMoveTo already moves; shown only in Control Mode (refreshLod).
	local bodyPose = drone.poses[1]
	for _, pose in drone.poses do
		if pose.part.Name == "Body" then
			bodyPose = pose
		end
	end
	if bodyPose ~= nil then
		local foot = Instance.new("Attachment")
		foot.Name = "BeamFoot"
		foot.Parent = part
		local head = Instance.new("Attachment")
		head.Name = "BeamHead"
		head.Position = Vector3.new(0, -0.4, 0) -- the underside of the body
		head.Parent = bodyPose.part
		local beam = Instance.new("Beam")
		beam.Name = "HeightBeam"
		beam.Attachment0 = foot
		beam.Attachment1 = head
		beam.Color = ColorSequence.new(STATUS_COLORS.cyan)
		beam.Width0 = BEAM_WIDTH
		beam.Width1 = BEAM_WIDTH
		beam.Transparency = NumberSequence.new(BEAM_ALPHA)
		beam.LightEmission = 0.5
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Enabled = false
		beam.Parent = part
		drone.beam = beam
	end
end

local function updatePlotLod(plotVisual: PlotVisual, distance: number)
	local wasOwn = plotVisual.own
	plotVisual.own = PlotSpace.isOwn(plotVisual.plot)
	plotVisual.fullFx = plotVisual.tier == "near"
	plotVisual.dressing.setLevel(
		if plotVisual.own
			then "full"
			elseif plotVisual.tier == "near" or distance <= FX.DressingRadius then "basic"
			else "none"
	)
	if plotVisual.own ~= wasOwn then
		refreshLimp(plotVisual)
		refreshStations(plotVisual)
	end
	refreshShadow(plotVisual)
end

--[[
	Every FX.LodInterval seconds (after refreshTiers): per built plot, which ready crops sway
	(own plot first, max FX.MaxSway) and whether the ready markers show (Control Mode, own
	plot, at most FX.MaxReadyMarkers ready tiles). Also publishes the Fx* debug attributes.
]]
local function refreshLod(distances: { [Model]: number })
	local mode = controlMode
	local controlling = mode ~= nil and mode:IsActive()
	-- DEBUG: neighbour sway is OFF by default and switches itself off under tween load.
	local neighboursSway = localFolder:GetAttribute("FxSwayNeighbours") == true
		and activeTweens <= FX.TweenBudget
	local now = os.clock()

	local ordered: { PlotVisual } = {}
	local fullPlots = 0
	local ownPlot: Model? = nil
	for plot, plotVisual in visuals do
		updatePlotLod(plotVisual, distances[plot] or math.huge)
		if plotVisual.fullFx then
			fullPlots += 1
		end
		if plotVisual.own then
			ownPlot = plot
			table.insert(ordered, 1, plotVisual) -- the own plot gets the sway budget first
		else
			table.insert(ordered, plotVisual)
		end
	end

	-- Wind (ANIM-3): the weather YOUR plot sees sets the sway angle and speed.
	local weather = PlotSpace.weather(ownPlot)
	if weather ~= windWeather then
		windWeather = weather
		local wind = WIND[weather] or WIND.Sunny
		TweenService:Create(swayAngle, WIND_FADE, { Value = wind.angle }):Play()
		TweenService:Create(swayHalf, WIND_FADE, { Value = wind.half }):Play()
	end

	table.clear(swayList)
	local markers = 0
	for _, plotVisual in ordered do
		local readyCount = 0
		for _, visual in plotVisual.crops do
			if visual.ready then
				readyCount += 1
			end
		end
		local showMarkers = plotVisual.own and controlling and readyCount <= FX.MaxReadyMarkers
		local beam = plotVisual.drone.beam
		if beam ~= nil and beam.Enabled ~= (plotVisual.own and controlling) then
			beam.Enabled = plotVisual.own and controlling
		end
		local canSway = plotVisual.own or (neighboursSway and plotVisual.fullFx)
		for _, visual in plotVisual.crops do
			if showMarkers and visual.ready then
				local marker = ensureMarker(plotVisual, visual)
				if not marker.Enabled then
					marker.Enabled = true
				end
				markers += 1
			else
				local marker = visual.marker
				if marker ~= nil and marker.Enabled then
					marker.Enabled = false
				end
			end

			local sway = canSway and visual.ready and now >= visual.restAt and #swayList < FX.MaxSway
			if sway then
				local model = visual.model
				if model ~= nil and #visual.restParts == 0 then
					captureModelRest(visual, model)
				end
				table.insert(swayList, visual)
			elseif visual.swaying then
				restPose(visual)
			end
			visual.swaying = sway
		end
	end

	localFolder:SetAttribute("FxParticles", activeParticles)
	localFolder:SetAttribute("FxTweens", activeTweens)
	localFolder:SetAttribute("FxSwaying", #swayList)
	localFolder:SetAttribute("FxReadyMarkers", markers)
	localFolder:SetAttribute("FxFullPlots", fullPlots)
end

------------------------------------------------------------------------------- stations
local function decorateStation(plotVisual: PlotVisual, station: Instance)
	if not station:IsA("BasePart") then
		return
	end
	local kind = station:GetAttribute("Kind")
	if type(kind) ~= "string" then
		return
	end
	local top = station.CFrame * CFrame.new(0, station.Size.Y / 2, 0)
	-- The factory's hopper + chimney mouth (ANIM-4 / ANIM-7): defaults from the procedural
	-- layout; an artist model can name parts "Hopper" and "ChimneyCap" / "Chimney".
	if kind == "factory" then
		plotVisual.chimneyTop = (top * CFrame.new(-1.9, 3.25, -1.9)).Position
	end
	local function useFactoryParts(root: Instance)
		local hopper = root:FindFirstChild("Hopper", true)
		if hopper ~= nil and hopper:IsA("BasePart") then
			plotVisual.hopper = hopper
			plotVisual.hopperRest = hopper.CFrame
		end
		local chimney = root:FindFirstChild("ChimneyCap", true) or root:FindFirstChild("Chimney", true)
		if chimney ~= nil and chimney:IsA("BasePart") then
			plotVisual.chimneyTop = chimney.Position + Vector3.new(0, chimney.Size.Y / 2, 0)
		end
	end
	-- The server's pad is Neon; locally it goes dark while idle (restored on teardown).
	local function darkenChargerPad()
		if plotVisual.chargerPad == nil then
			plotVisual.chargerPad =
				{ part = station, material = station.Material, color = station.Color, size = station.Size }
			station.Material = Enum.Material.SmoothPlastic
			station.Color = PAD_IDLE
		end
	end
	local asset = AssetLibrary.station(kind)
	if asset ~= nil then
		asset:PivotTo(top)
		asset.Parent = plotVisual.folder
		if kind == "factory" then
			useFactoryParts(asset)
			-- Its biofluid ("Slit") and work "Lamp" light up while the drone works (PlotDressing).
			local slit = asset:FindFirstChild("Slit", true)
			local lamp = asset:FindFirstChild("Lamp", true)
			plotVisual.dressing.setFactoryLights(
				if slit ~= nil and slit:IsA("BasePart") then slit else nil,
				if lamp ~= nil and lamp:IsA("BasePart") then lamp else nil
			)
		elseif kind == "charger" then
			-- Its light guides (Ring1..4), PylonLight and Conduit glow and pulse cyan while
			-- charging, exactly like the procedural rings (refreshStations / pulseRings).
			for _, descendant in asset:GetDescendants() do
				local name = descendant.Name
				if
					descendant:IsA("BasePart")
					and (
						string.match(name, "^Ring%d+$") ~= nil
						or name == "PylonLight"
						or string.sub(name, 1, 7) == "Conduit"
					)
				then
					descendant.Material = Enum.Material.SmoothPlastic
					descendant.Color = STATION_IDLE
					table.insert(plotVisual.chargerGlow, descendant)
				end
			end
			darkenChargerPad()
		end
		return
	end
	local function add(part: BasePart, offset: CFrame)
		part.CFrame = top * offset
		part.Parent = plotVisual.folder
	end
	if kind == "factory" then
		add(
			decorPart("Roof", Vector3.new(6.4, 0.4, 6.4), Color3.fromRGB(52, 58, 70), Enum.Material.Metal),
			CFrame.new(0, 0.2, 0)
		)
		add(
			decorPart("Chimney", Vector3.new(1, 2.6, 1), Color3.fromRGB(96, 102, 116), Enum.Material.Metal),
			CFrame.new(-1.9, 1.7, -1.9)
		)
		add(
			decorPart(
				"ChimneyCap",
				Vector3.new(1.3, 0.3, 1.3),
				Color3.fromRGB(40, 44, 52),
				Enum.Material.Metal
			),
			CFrame.new(-1.9, 3.1, -1.9)
		)
		add(
			decorPart("Window", Vector3.new(3.6, 0.6, 0.12), FACTORY_GLASS, Enum.Material.Glass),
			CFrame.new(0, -1.2, 3.02)
		)
		add(
			decorPart(
				"Hopper",
				Vector3.new(1.8, 0.8, 1.8),
				Color3.fromRGB(230, 160, 60),
				Enum.Material.SmoothPlastic
			),
			CFrame.new(1.4, 0.8, 1.2)
		)
		useFactoryParts(plotVisual.folder)
	elseif kind == "charger" then
		for i, offset in
			{
				Vector3.new(2.6, 0, 0),
				Vector3.new(-2.6, 0, 0),
				Vector3.new(0, 0, 2.6),
				Vector3.new(0, 0, -2.6),
			}
		do
			local horizontal = i <= 2
			local ring = decorPart(
				"Ring" .. i,
				if horizontal then Vector3.new(0.2, 0.2, 5.4) else Vector3.new(5.4, 0.2, 0.2),
				STATION_IDLE,
				Enum.Material.SmoothPlastic
			)
			add(ring, CFrame.new(offset + Vector3.new(0, 0.15, 0)))
			table.insert(plotVisual.chargerGlow, ring)
		end
		add(
			decorPart("Pylon", Vector3.new(0.4, 2.2, 0.4), Color3.fromRGB(70, 76, 88), Enum.Material.Metal),
			CFrame.new(-2.6, 1.1, -2.6)
		)
		local pylonLight = decorPart(
			"PylonLight",
			Vector3.new(0.6, 0.6, 0.6),
			STATION_IDLE,
			Enum.Material.SmoothPlastic,
			BALL
		)
		add(pylonLight, CFrame.new(-2.6, 2.4, -2.6))
		table.insert(plotVisual.chargerGlow, pylonLight)
		darkenChargerPad()
	end
end

-- ANIM-7: the hopper ticks (0.08 stud, 3 cycles in 0.1 s) and ends exactly on its rest pose.
local function jitterHopper(plotVisual: PlotVisual)
	local hopper = plotVisual.hopper
	local rest = plotVisual.hopperRest
	if hopper == nil or rest == nil or hopper.Parent == nil then
		return
	end
	local part: BasePart = hopper
	local home: CFrame = rest
	part.CFrame = home
	local tween =
		TweenService:Create(part, HOPPER_JITTER, { CFrame = home * CFrame.new(HOPPER_JITTER_STUDS, 0, 0) })
	tween.Completed:Once(function()
		if part:IsDescendantOf(Workspace) then
			part.CFrame = home
		end
	end)
	tween:Play()
end

--[[
	Cargo leaving YOUR drone at a station, inferred from the Cargo attribute dropping while the
	drone sits on the charger (unload) or the factory (deposit). Cargo going UP (a harvest) or
	not changing does nothing; MID / FAR plots and other players' plots never react.
]]
local function onCargo(plotVisual: PlotVisual)
	local now = plotVisual.plot:GetAttribute("Cargo")
	local before = plotVisual.cargo
	plotVisual.cargo = if type(now) == "number" then now else nil
	if type(now) ~= "number" or before == nil or now >= before then
		return
	end
	if not plotVisual.own or plotVisual.tier ~= "near" then
		return
	end
	-- The PUBLISHED cell: Cargo can replicate before the Drone change is handled.
	local cell = readDroneCell(plotVisual.plot) or plotVisual.drone.cell
	local station = if cell ~= nil then DroneSignals.stationAt(cell.X, cell.Y) else nil
	if station == nil then
		return
	end
	local drone = plotVisual.drone
	if station == "factory" then
		playPose(drone, "factory") -- ANIM-2: a small settle, no scoop
	end
	SoundController.play(if station == "factory" then "deposit" else "unload")

	-- ANIM-4: the bits leave the drone (one unload burst at a time).
	local clock = os.clock()
	if clock < plotVisual.unloadUntil then
		return
	end
	local dropped = before - now
	local from = drone.move.Value.Position - Vector3.new(0, drone.land.Value + 0.45, 0)
	if station == "charger" then
		-- Unload: 4-8 gold bits toward the sign post (it stands past the far end of the field).
		local sign = plotVisual.plot:FindFirstChild("OwnerSign")
		if sign ~= nil and sign:IsA("BasePart") then
			plotVisual.unloadUntil = clock + BURSTS.unload.lifetime
			local target = Vector3.new(sign.Position.X, from.Y + 0.5, sign.Position.Z)
			queueAimed(
				plotVisual,
				"unload",
				UNLOAD_COLORS,
				from,
				target,
				math.clamp(math.round(dropped), 4, 8)
			)
		end
	elseif station == "factory" then
		-- Deposit: 3-5 bits into the hopper, then 2 biofluid bits up the chimney.
		local hopper = plotVisual.hopper
		local into = if hopper ~= nil
			then hopper.Position + Vector3.new(0, hopper.Size.Y / 2, 0)
			else from - Vector3.new(0, 2.5, 0)
		plotVisual.unloadUntil = clock + BURSTS.unload.lifetime + CHIMNEY_DELAY
		queueAimed(plotVisual, "unload", UNLOAD_COLORS, from, into, math.clamp(math.round(dropped), 3, 5))
		-- ANIM-7: the hopper ticks as the bits land in it.
		task.delay(BURSTS.unload.lifetime * 0.8, function()
			if visuals[plotVisual.plot] == plotVisual then
				jitterHopper(plotVisual)
			end
		end)
		local chimney = plotVisual.chimneyTop
		if chimney ~= nil then
			task.delay(CHIMNEY_DELAY, function()
				if visuals[plotVisual.plot] == plotVisual then
					queueLoose(plotVisual, "biofluid", BIOFLUID_COLORS, chimney, 2)
					queueLoose(plotVisual, "smoke", SMOKE_COLORS, chimney, SMOKE_PUFFS) -- ANIM-7
				end
			end)
		end
	end
end

-- ANIM-7: the battery RISING while your drone is docked = charging: the rings spin up.
local function onBattery(plotVisual: PlotVisual)
	local now = plotVisual.plot:GetAttribute("Battery")
	local before = plotVisual.battery
	plotVisual.battery = if type(now) == "number" then now else nil
	if type(now) ~= "number" or before == nil or now <= before then
		return
	end
	if plotVisual.own and plotVisual.activeStation == "charger" and not plotVisual.ringFast then
		plotVisual.ringFast = true
		pulseRings(plotVisual, RING_PULSE_FAST)
		SoundController.setLoop("charge", true)
	end
end

---------------------------------------------------------------------------------- plots
local untrackPlot: (plot: Model) -> ()

-- Tears a plot visual down COMPLETELY (tier change or removal): connections, infinite and
-- running tweens, parts. Hiding would leak the tweens.
local function teardownPlot(plot: Model)
	local plotVisual = visuals[plot]
	if plotVisual == nil then
		return
	end
	visuals[plot] = nil
	if plotVisual.own then
		SoundController.setLoop("charge", false)
	end
	for _, connection in plotVisual.connections do
		connection:Disconnect()
	end
	local drone = plotVisual.drone
	for _, loop in drone.loops do
		loop:Cancel()
	end
	table.clear(drone.loops)
	local blink = drone.statusBlink
	if blink ~= nil then
		blink:Cancel()
		drone.statusBlink = nil
	end
	local moveTween = drone.moveTween
	if moveTween ~= nil then
		moveTween:Cancel()
	end
	cancelFlight(drone)
	for _, tween in drone.pose do
		tween:Cancel()
	end
	table.clear(drone.pose)
	for _, tween in plotVisual.ringTweens do
		tween:Cancel()
	end
	table.clear(plotVisual.ringTweens)
	local pad = plotVisual.chargerPad
	if pad ~= nil and pad.part.Parent ~= nil then
		pad.part.Material = pad.material -- the server's own look again
		pad.part.Color = pad.color
		pad.part.Size = pad.size
	end
	for _, visual in plotVisual.crops do
		visual.swaying = false -- the render loop must not move destroyed parts
	end
	plotVisual.dressing.destroy()
	plotVisual.folder:Destroy()
end

-- FAR: the server tiles get their own plain look back (no stale client soil states).
local function resetTiles(plot: Model)
	local soil = rgb(CropConfig.SoilColor)
	for _, child in plot:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, 5) == "Tile_" then
			child.Material = Enum.Material.Ground
			child.MaterialVariant = ""
			child.Color = soil
		end
	end
end

-- Builds the visual of a NEAR or MID plot.
local function buildPlot(plot: Model, tier: string)
	local folder = Instance.new("Folder")
	folder.Name = plot.Name
	folder.Parent = localFolder

	local plotVisual: PlotVisual = {
		plot = plot,
		drone = buildDrone(folder, tier ~= "near"),
		crops = {},
		connections = {},
		folder = folder,
		fx = { anchor = nil, attachment = nil, emitters = {}, queue = {}, busy = {} },
		snaps = {},
		pending = {},
		soil = {},
		own = false,
		fullFx = false,
		dressing = PlotDressing.new(plot, folder),
		chargerGlow = {},
		chargerPad = nil,
		ringTweens = {},
		activeStation = nil,
		tier = tier,
		cargo = nil,
		unloadUntil = 0,
		battery = nil,
		ringFast = false,
		hopper = nil,
		hopperRest = nil,
		chimneyTop = nil,
	}
	visuals[plot] = plotVisual
	local startCargo = plot:GetAttribute("Cargo")
	plotVisual.cargo = if type(startCargo) == "number" then startCargo else nil
	local startBattery = plot:GetAttribute("Battery")
	plotVisual.battery = if type(startBattery) == "number" then startBattery else nil
	updatePlotLod(plotVisual, plotDistance(plot))

	-- The drone FIRST: painted, hatted and standing on its cell this very frame, so nothing
	-- built after it (tiles, stations, dressing) can leave it parked at the world origin.
	local cachedPaint = farPaint[plot]
	farPaint[plot] = nil
	applyPaint(plotVisual.drone, if cachedPaint ~= nil then cachedPaint else plot:GetAttribute("DronePaint"))
	applyHat(plotVisual.drone, plot:GetAttribute("DroneHat"))
	updateDroneTarget(plotVisual, true)
	-- A DroneMoved that beat the attributes here: only if it's NEWER than what they say (a
	-- stale entry from an older plot with this Index has an older serial: BUG-06).
	local index = plot:GetAttribute("Index")
	local moved = if type(index) == "number" then lastMoved[index] else nil
	if
		moved ~= nil
		and DroneSignals.shouldApply(
			plotVisual.drone.serial,
			moved.serial,
			not sameCell(plotVisual.drone.cell, moved.cell)
		)
	then
		updateDroneTarget(plotVisual, true, moved.cell, moved.serial)
	end

	local function onChild(child: Instance)
		local ok, err = pcall(function()
			watchTile(plotVisual, child)
			if child:GetAttribute("Kind") ~= nil and tier == "near" then
				decorateStation(plotVisual, child) -- MID: the server's station parts are enough
			end
		end)
		if not ok then
			warn(string.format("[PlotRenderer] %s.%s: %s", plot.Name, child.Name, tostring(err)))
		end
	end
	local function on(attribute: string, callback: () -> ())
		table.insert(plotVisual.connections, plot:GetAttributeChangedSignal(attribute):Connect(callback))
	end
	local function onDroneMoved()
		local drone = plotVisual.drone
		local from = drone.cell
		local liftOff = drone.move.Value.Position - Vector3.new(0, DRONE.HoverHeight, 0)
		updateDroneTarget(plotVisual, false)
		-- Your drone kicks up dust when it leaves a field tile (one step, not a teleport).
		local to = drone.cell
		hopSound(plotVisual.own, from, to)
		if
			plotVisual.own
			and plotVisual.fullFx
			and from ~= nil
			and to ~= nil
			and from.Y >= 0
			and from ~= to
			and (to - from).Magnitude <= 1.5
		then
			rotorWash(plotVisual, liftOff)
		end
		refreshStations(plotVisual)
		refreshStatus(plotVisual)
	end
	-- Numbers and the vector: any one of these firing is enough to tween.
	on("Drone", onDroneMoved)
	on("DroneX", onDroneMoved)
	on("DroneY", onDroneMoved)
	on("DroneSerial", onDroneMoved)
	on("DronePaint", function()
		applyPaint(plotVisual.drone, plot:GetAttribute("DronePaint"))
	end)
	-- Arriving late (streaming, a rebuilt plot): place the drone as soon as they're known.
	for _, attribute in { "Origin", "Pitch" } do
		on(attribute, function()
			plotVisual.drone.cell = nil -- force the instant pose + snap
			updateDroneTarget(plotVisual, true)
		end)
	end
	on("Battery", function()
		refreshStatus(plotVisual)
		onBattery(plotVisual)
	end)
	on("BatteryMax", function()
		refreshStatus(plotVisual)
	end)
	if tier == "near" then
		on("DroneHat", function()
			applyHat(plotVisual.drone, plot:GetAttribute("DroneHat"))
		end)
		on("DroneMoveTime", function()
			refreshLimp(plotVisual)
		end)
		on("Cargo", function()
			onCargo(plotVisual)
		end)
	end
	table.insert(plotVisual.connections, plot.ChildAdded:Connect(onChild))
	table.insert(
		plotVisual.connections,
		plot.AncestryChanged:Connect(function()
			if plot.Parent == nil then
				untrackPlot(plot)
			end
		end)
	)
	for _, child in plot:GetChildren() do
		onChild(child)
	end
	refreshLimp(plotVisual)
	refreshStations(plotVisual, true) -- the stations exist now: apply idle / lit
end

-- FAR: nothing is built. Only DronePaint (cached for the rebuild) and removal stay connected.
local function enterFar(plot: Model)
	resetTiles(plot)
	farHooks[plot] = {
		plot:GetAttributeChangedSignal("DronePaint"):Connect(function()
			farPaint[plot] = plot:GetAttribute("DronePaint")
		end),
		plot.AncestryChanged:Connect(function()
			if plot.Parent == nil then
				untrackPlot(plot)
			end
		end),
	}
end

local function leaveFar(plot: Model)
	local hooks = farHooks[plot]
	if hooks ~= nil then
		for _, connection in hooks do
			connection:Disconnect()
		end
		farHooks[plot] = nil
	end
end

local function setTier(plot: Model, tier: string)
	local current = tiers[plot]
	if current == tier then
		return
	end
	tiers[plot] = tier
	if current == "far" then
		leaveFar(plot)
	else
		teardownPlot(plot)
	end
	if tier == "far" then
		enterFar(plot)
	else
		local ok, err = pcall(buildPlot :: any, plot, tier)
		if not ok then
			warn(string.format("[PlotRenderer] building %s (%s) failed: %s", plot.Name, tier, tostring(err)))
		end
	end
end

local function trackPlot(plot: Instance)
	if not plot:IsA("Model") or tiers[plot] ~= nil then
		return
	end
	setTier(plot, desiredTier(plot, nil, plotDistance(plot)))
end

untrackPlot = function(plot: Model)
	if tiers[plot] == nil then
		return
	end
	tiers[plot] = nil
	farPaint[plot] = nil
	-- The next plot with this Index belongs to someone else: drop the cached remote (BUG-06).
	local index = plot:GetAttribute("Index")
	if type(index) == "number" then
		lastMoved[index] = nil
	end
	leaveFar(plot)
	teardownPlot(plot)
end

-- Re-tiers every known plot; returns each plot's distance for refreshLod.
local function refreshTiers(): { [Model]: number }
	local distances: { [Model]: number } = {}
	local counts = { near = 0, mid = 0, far = 0 }
	for plot, tier in tiers do
		local distance = plotDistance(plot)
		distances[plot] = distance
		local desired = desiredTier(plot, tier, distance)
		if desired ~= tier then
			setTier(plot, desired)
		end
		counts[desired] += 1
	end
	localFolder:SetAttribute("FxNear", counts.near)
	localFolder:SetAttribute("FxMid", counts.mid)
	localFolder:SetAttribute("FxFar", counts.far)
	return distances
end

-- DEBUG (FxDebugPrint attribute, default false): tier, tween and part counts.
local function printCounts()
	local counts = { near = 0, mid = 0, far = 0 }
	for _, tier in tiers do
		counts[tier] += 1
	end
	local loops = 0 -- infinite tweens (the sway drivers and rotors are advanced in render)
	for _, plotVisual in visuals do
		local drone = plotVisual.drone
		loops += #drone.loops + (if drone.statusBlink ~= nil then 1 else 0) + #plotVisual.ringTweens
	end
	local parts = 0
	for _, descendant in localFolder:GetDescendants() do
		if descendant:IsA("BasePart") then
			parts += 1
		end
	end
	for plot, plotVisual in visuals do
		local drone = plotVisual.drone
		local first = drone.poses[1]
		print(
			string.format(
				"[PlotRenderer] drone %s tier=%s own=%s cell=%s parts=%d first=%s T=%.2f size=%s at=%s",
				plot.Name,
				plotVisual.tier,
				tostring(plotVisual.own),
				tostring(drone.cell),
				#drone.poses + #drone.hatPoses,
				if first ~= nil then first.part.Name else "-",
				if first ~= nil then first.part.Transparency else -1,
				if first ~= nil then tostring(first.part.Size) else "-",
				if first ~= nil then tostring(first.part.Position) else "-"
			)
		)
	end
	print(
		string.format(
			"[PlotRenderer] near=%d mid=%d far=%d | tweens: %d FX + %d loops | parts=%d | particles=%d",
			counts.near,
			counts.mid,
			counts.far,
			activeTweens,
			loops,
			parts,
			activeParticles
		)
	)
end

-- Composes the tweened values into final CFrames (no motion is computed here, except the
-- rotor angle advancing at its tweened period).
local function render(dt: number)
	local now = os.clock()
	if now >= nextLodAt then
		nextLodAt = now + FX.LodInterval
		local ok, err = pcall(function()
			refreshLod(refreshTiers())
		end)
		if not ok then
			warn("[PlotRenderer] LOD refresh failed: " .. tostring(err))
		end
	end
	if now >= nextDebugAt and localFolder:GetAttribute("FxDebugPrint") == true then
		nextDebugAt = now + FX.DebugPrintEvery
		printCounts()
	end
	drainBursts()

	local parts: { BasePart } = {}
	local cframes: { CFrame } = {}
	for _, plotVisual in visuals do
		local drone = plotVisual.drone
		-- Catch a missed AttributeChanged on any NEAR plot (own is always NEAR).
		if plotVisual.tier == "near" then
			local published = readDroneCell(plotVisual.plot)
			local serial = readDroneSerial(plotVisual.plot)
			if
				published ~= nil
				and DroneSignals.shouldApply(drone.serial, serial, not sameCell(drone.cell, published))
			then
				-- Guarded: one bad plot must never stop every drone from being composed.
				local ok, err = pcall(updateDroneTarget :: any, plotVisual, false, published, serial)
				if not ok then
					warn("[PlotRenderer] drone update failed: " .. tostring(err))
				end
			end
		end
		if plotVisual.tier ~= "near" or drone.cell == nil then
			continue -- MID drones are snapped on change; only NEAR drones are composed here
		end
		local shadow = drone.shadow
		if shadow ~= nil then
			table.insert(parts, shadow)
			table.insert(cframes, shadowCFrame(drone))
		end
		-- Rotors: advance by the (tweened) period, so a speed change never restarts them.
		drone.spin.Value = (drone.spin.Value + dt * 360 / math.max(drone.rotorPeriod.Value, 0.05)) % 360
		local landed = drone.land.Value
		local docked = math.clamp(landed / LAND_DROP, 0, 1)
		local hover = (drone.bob.Value - 0.5)
			* 2
			* BOB_HEIGHT
			* drone.bobScale.Value
			* (1 - (1 - LANDED_BOB) * docked)
		local base = drone.move.Value
			* CFrame.new(0, hover + drone.lift.Value * TAKEOFF_LIFT - landed + drone.poseY.Value, 0)
			* CFrame.Angles(
				-(drone.tilt.Value * MAX_TILT + drone.posePitch.Value),
				drone.poseYaw.Value,
				drone.roll.Value * MAX_ROLL
			)
		pcall(function()
			drone.model:PivotTo(base)
		end)
		local spin = CFrame.Angles(0, math.rad(drone.spin.Value), 0)
		for _, list in { drone.poses, drone.hatPoses } do
			for _, pose in list do
				table.insert(parts, pose.part)
				-- Rotors spin around the drone's vertical axis at their own position.
				table.insert(
					cframes,
					if pose.spins
						then base * CFrame.new(pose.offset.Position) * spin * pose.offset.Rotation
						else base * pose.offset
				)
			end
		end
	end

	-- Ready crops sway around their tile top: the two shared drivers, mixed by each crop's
	-- own phase (a mostly back-and-forth wobble of the weather's angle, WIND).
	swayPhase = (swayPhase + dt * math.pi / math.max(swayHalf.Value, 0.2)) % (2 * math.pi)
	swayA.Value = -math.cos(swayPhase)
	swayB.Value = -math.cos(swayPhase - math.pi / 2)
	if #swayList > 0 then
		local a = swayA.Value
		local b = swayB.Value
		local angle = swayAngle.Value
		for _, visual in swayList do
			if not visual.swaying then
				continue
			end
			local c, s = visual.swayCos, visual.swaySin
			local pose = visual.base
				* CFrame.Angles(angle * (a * c + b * s), 0, angle * 0.4 * (b * c - a * s))
			for index, part in visual.restParts do
				local rest = visual.restLocal[index] :: CFrame?
				if rest ~= nil then
					table.insert(parts, part)
					table.insert(cframes, pose * rest)
				end
			end
		end
	end

	if #parts > 0 then
		Workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function PlotRenderer:Init()
	local folder = Instance.new("Folder")
	folder.Name = "ClientVisuals"
	folder.Parent = Workspace
	localFolder = folder
	-- DEBUG toggles (Studio: select ClientVisuals while playing). Defaults: other players'
	-- crops never sway; no count prints.
	folder:SetAttribute("FxSwayNeighbours", false)
	folder:SetAttribute("FxDebugPrint", false)
end

function PlotRenderer:Start()
	local plots = Workspace:WaitForChild("Plots")
	plots.ChildAdded:Connect(trackPlot)
	plots.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Model") then
			untrackPlot(child)
		end
	end)
	-- Loaded by ClientMain already; required here (not at the top) so this module stays
	-- first in the load order.
	controlMode = require(script.Parent.ControlModeController) :: any

	-- FIX-DRONE: the compose loop connects FIRST. Anything optional below (soil looks, ...)
	-- used to throw here and abort Start before this line, so the drone was snapped onto the
	-- charger once and never moved again while the terminal kept running.
	swayA.Value = -1 -- sway drivers: advanced in render (WIND sets speed and angle)
	swayB.Value = 0
	RunService.RenderStepped:Connect(render)

	-- Soil looks: an artist MaterialVariant arriving later re-applies every tile. Optional:
	-- a failure here only costs the soil look, never the drone.
	local soilOk, soilErr = pcall(SoilLook.start :: any, function()
		for _, plotVisual in visuals do
			for tile, soil in plotVisual.soil do
				if tile.Parent ~= nil then
					SoilLook.apply(tile, soil, nil, plotVisual.tier ~= "near")
				end
			end
		end
	end)
	if not soilOk then
		warn("[PlotRenderer] soil looks unavailable: " .. tostring(soilErr))
	end

	for _, plot in plots:GetChildren() do
		trackPlot(plot)
	end

	-- ScriptStatus already reaches the client (the terminal highlights). DroneMoved carries
	-- the cell so a silent Vector attribute cannot park the drone.
	local Net = require(script.Parent.Parent.Net)
	Net.on("DroneMoved", function(plotIndex: any, x: any, y: any, duration: any, serialValue: any)
		if type(plotIndex) ~= "number" or type(x) ~= "number" or type(y) ~= "number" then
			return
		end
		local cell = Vector2.new(x, y)
		local serial: number? = if type(serialValue) == "number" then serialValue else nil
		lastMoved[plotIndex] = { cell = cell, serial = serial }
		for plot, plotVisual in visuals do
			if plot:GetAttribute("Index") == plotIndex then
				if
					not DroneSignals.shouldApply(
						plotVisual.drone.serial,
						serial,
						not sameCell(plotVisual.drone.cell, cell)
					)
				then
					return -- the attributes already delivered this move (or a newer one)
				end
				if type(duration) == "number" then
					plot:SetAttribute("DroneMoveTime", duration)
				end
				local from = plotVisual.drone.cell
				local liftOff = plotVisual.drone.move.Value.Position - Vector3.new(0, DRONE.HoverHeight, 0)
				updateDroneTarget(plotVisual, false, cell, serial)
				local to = plotVisual.drone.cell
				hopSound(plotVisual.own, from, to)
				if
					plotVisual.own
					and plotVisual.fullFx
					and from ~= nil
					and to ~= nil
					and from.Y >= 0
					and not sameCell(from, to)
					and (to - from).Magnitude <= 1.5
				then
					rotorWash(plotVisual, liftOff)
				end
				refreshStations(plotVisual)
				refreshStatus(plotVisual)
				return
			end
		end
	end)
	Net.on("ScriptStatus", function(status: any)
		if status ~= "line" and status ~= "running" then
			return
		end
		for _, plotVisual in visuals do
			if plotVisual.own then
				updateDroneTarget(plotVisual, false)
			end
		end
	end)
end

--[[
	Weather tint for PROCEDURAL crops (WeatherFxController: Drought = 0.25, otherwise 0): every
	crop colour leans `amount` toward dry straw #C9C27A, tweened over 1.5 s on plots with full
	effects. Artist models are skipped: tinting their textures brown looks wrong. Crops still
	mid-animation are re-tinted once they come to rest, so their pose tween isn't cut short.
]]
function PlotRenderer:SetCropTint(amount: number)
	if amount == cropTint then
		return
	end
	cropTint = amount
	local function retint(plotVisual: PlotVisual, visual: CropVisual)
		if plotVisual.crops[visual.tile] ~= visual or visual.model ~= nil then
			return
		end
		if visual.proxy then
			visual.parts[1].Color = roleColor("main", visual.mainColor) -- MID proxies: instant
			return
		end
		for index, spec in visual.specs do
			local part = visual.parts[index]
			local color = partColor(spec, visual.mainColor)
			if plotVisual.fullFx then
				playTracked(TweenService:Create(part, TINT_FADE, { Color = color }))
			else
				part.Color = color
			end
		end
	end
	local now = os.clock()
	for _, plotVisual in visuals do
		for _, visual in plotVisual.crops do
			local wait = visual.restAt - now
			if wait > 0 and wait < math.huge then
				task.delay(wait, retint, plotVisual, visual)
			else
				retint(plotVisual, visual)
			end
		end
	end
end

return PlotRenderer
