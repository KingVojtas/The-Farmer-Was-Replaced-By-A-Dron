--!strict
--[[
	SoundController
	===============
	Plays the game's sounds (ASSETS-8). The table of sounds, volumes and WHEN each plays is
	Shared.Config.SoundConfig; the files are art/audio/*.ogg (tools/build_sfx.py).

	  SoundController.play(name)          one-shot, 2D (only YOUR plot's events call it)
	  SoundController.setLoop(name, on)   start / stop a looped sound (0.35 s fades)

	Safe to call from any controller at any time: a sound that isn't uploaded yet (assetId 0)
	is a no-op, and nothing here yields or errors. Each one-shot is a fresh clone that destroys
	itself; at most VOICES copies of one sound play at once, and SoundConfig.minGap spaces
	repeats, so a fast script can't stack hundreds of hops.

	Hooks: PlotRenderer (hop, land, plant, water, harvest, unripe, dig, deposit, unload,
	charge loop), NotifyController (research, purchase, error), and here: every GuiButton
	under PlayerGui (click, hover), the Biofuel / Fossil counters (refine, fossil) and the
	ambient bed.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local SoundConfig = require(ReplicatedStorage.Shared.Config.SoundConfig)

local VOICES = 4 -- copies of one sound playing at once
local ONE_SHOT_LIFETIME = 3 -- s; cleanup if Ended never fires (asset failed to load)
local LOOP_FADE = TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local SoundController = {}

local folder: Folder? = nil
local groups: { [string]: SoundGroup } = {}
local templates: { [string]: Sound } = {}
local lastPlayed: { [string]: number } = {}
local playing: { [string]: number } = {}
local loops: { [string]: Sound } = {}
local loopWanted: { [string]: boolean } = {}
local random = Random.new()

-- The folder + SoundGroups, made on first use (so play() works even before Init).
local function ensure(): Folder
	local existing = folder
	if existing ~= nil then
		return existing
	end
	local created = Instance.new("Folder")
	created.Name = "DroneFarmSounds"
	for name, volume in SoundConfig.Groups do
		local group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = volume
		group.Parent = created
		groups[name] = group
	end
	created.Parent = SoundService
	folder = created
	return created
end

local function template(name: string, config: SoundConfig.Sound): Sound
	local cached = templates[name] :: Sound?
	if cached ~= nil then
		return cached
	end
	ensure()
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = "rbxassetid://" .. tostring(config.assetId)
	sound.Volume = config.volume
	sound.Looped = config.looped
	sound.SoundGroup = groups[config.group]
	templates[name] = sound
	return sound
end

function SoundController.play(name: string)
	local config = SoundConfig.get(name)
	if config == nil or config.looped then
		return
	end
	local now = os.clock()
	local last = lastPlayed[name]
	if last ~= nil and now - last < config.minGap then
		return
	end
	if (playing[name] or 0) >= VOICES then
		return
	end
	lastPlayed[name] = now
	playing[name] = (playing[name] or 0) + 1

	local sound = template(name, config):Clone()
	if config.pitchJitter > 0 then
		sound.PlaybackSpeed = 1 + random:NextNumber(-config.pitchJitter, config.pitchJitter)
	end
	local done = false
	local function finish()
		if done then
			return
		end
		done = true
		playing[name] = math.max(0, (playing[name] or 1) - 1)
		sound:Destroy()
	end
	sound.Ended:Once(finish)
	task.delay(ONE_SHOT_LIFETIME, finish)
	sound.Parent = ensure()
	sound:Play()
end

function SoundController.setLoop(name: string, on: boolean)
	local config = SoundConfig.get(name)
	if config == nil or not config.looped then
		return
	end
	if loopWanted[name] == on then
		return
	end
	loopWanted[name] = on
	local sound = loops[name] :: Sound?
	if on then
		if sound == nil then
			local created = template(name, config):Clone()
			created.Volume = 0
			created.Parent = ensure()
			loops[name] = created
			sound = created
		end
		local loop = sound :: Sound
		if not loop.IsPlaying then
			loop:Play()
		end
		TweenService:Create(loop, LOOP_FADE, { Volume = config.volume }):Play()
	elseif sound ~= nil then
		local loop = sound
		local fade = TweenService:Create(loop, LOOP_FADE, { Volume = 0 })
		fade.Completed:Once(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and loopWanted[name] ~= true then
				loop:Stop()
			end
		end)
		fade:Play()
	end
end

-- click / hover on every GuiButton under PlayerGui (once per button, weak so it can go).
local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function hookButton(instance: Instance)
	if not instance:IsA("GuiButton") or hooked[instance] then
		return
	end
	hooked[instance] = true
	instance.Activated:Connect(function()
		SoundController.play("click")
	end)
	instance.MouseEnter:Connect(function()
		SoundController.play("hover")
	end)
end

-- A counter that goes UP plays `sound` (the first value, the data load, never does).
local function onRise(player: Player, attribute: string, sound: string)
	local before = player:GetAttribute(attribute)
	player:GetAttributeChangedSignal(attribute):Connect(function()
		local now = player:GetAttribute(attribute)
		if type(before) == "number" and type(now) == "number" and now > before then
			SoundController.play(sound)
		end
		before = now
	end)
end

function SoundController:Init()
	ensure()
end

function SoundController:Start()
	local player = Players.LocalPlayer
	SoundController.setLoop("ambient", true)
	onRise(player, "Cur_biofuel", "refine")
	onRise(player, "Cur_fossil", "fossil")
	local playerGui = player:WaitForChild("PlayerGui")
	for _, descendant in playerGui:GetDescendants() do
		hookButton(descendant)
	end
	playerGui.DescendantAdded:Connect(hookButton)
end

return SoundController
