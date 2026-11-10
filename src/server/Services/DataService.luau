--!strict
--[[
	DataService
	===========
	Roblox glue around SessionStore: loads, autosaves and releases every player's profile,
	and is the only place other services read or change saved data.

	LIFECYCLE
	  PlayerAdded     -> (wait if this user's previous session in THIS server is still releasing)
	                     -> SessionStore:LoadAsync (session-locked)
	                     -> failure: kick with a friendly message (never play on unsaved data)
	                     -> player left during load / server shutting down: release at once
	                     -> success: replicate + fire ProfileLoaded
	  every 90 s      -> SaveAsync (spread out: each profile autosaves 90 s after its last one)
	  PlayerRemoving  -> ReleaseAsync (final save + unlock)
	  BindToClose     -> release everyone in parallel, wait up to ShutdownTimeout seconds
	  lock lost       -> kick (another server owns the data now; stops dupes)

	STUDIO
	  Without "Enable Studio Access to API Services" (or on an unpublished place) a
	  MockDataStore is used and a loud warning is printed: everything works, nothing persists.
	  Live servers never use the mock.

	REPLICATION
	  Values the client UI needs are mirrored as player attributes and in leaderstats
	  (Harvested, Wheat). Call DataService:Replicate(player) after changing data.
	    Cur_<currencyId>    number   every currency (Cur_hay, Cur_biomass, Cur_batteries, ...)
	    Tech_<nodeId>       boolean  researched Tech Tree nodes
	    Owned_<cosmeticId>  boolean  premium cosmetics bought in the Shop
	    Equipped_paint, Equipped_hat  string  equipped cosmetic ids
	    CropsHarvested, GridSize (from research), GrowthBoostUntil, YieldBoostUntil, DataLoaded
	  Display only: the server always re-reads the saved data before acting.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local CosmeticConfig = require(ReplicatedStorage.Shared.Config.CosmeticConfig)
local Currencies = require(ReplicatedStorage.Shared.Config.Currencies)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local MonetizationConfig = require(ReplicatedStorage.Shared.Config.MonetizationConfig)
local ScriptNames = require(ReplicatedStorage.Shared.DroneScript.ScriptNames)
local Tech = require(ReplicatedStorage.Shared.Progression.Tech)
local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Text = require(ReplicatedStorage.Shared.Util.Text)
local Data = script.Parent.Parent.Data
local DataTemplate = require(Data.DataTemplate)
local MockDataStore = require(Data.MockDataStore)
local Sanitize = require(Data.Sanitize)
local SessionStore = require(Data.SessionStore)

export type Profile = SessionStore.Profile
export type PlayerData = DataTemplate.PlayerData

local KICK_MESSAGES: { [string]: string } = {
	Locked = "Your data is still being saved on another server. Please rejoin in a minute.",
	Corrupt = "We couldn't read your save data. It has NOT been changed - please contact support.",
	Failed = "Roblox data servers are having trouble right now. Please rejoin in a moment.",
}

local DataService = {
	-- Fired as (player: Player, profile: Profile) once a player's data is ready.
	ProfileLoaded = Signal.new(),
}

local sessionStore: SessionStore.SessionStore
local profiles: { [Player]: Profile } = {}
local lastAutosave: { [Profile]: number } = {}
local releasingCount: { [number]: number? } = {} -- userId -> releases in progress
-- Called (synchronously) right before every save of a player's data: autosave, leaving and
-- shutdown. GridService writes the field snapshot here, so a save is never stale.
local beforeSave: { (player: Player, data: any) -> () } = {}

local function runBeforeSave(player: Player, profile: Profile)
	for _, callback in beforeSave do
		local ok, err = pcall(callback :: any, player, profile.data)
		if not ok then
			warn("[DataService] before-save hook failed: " .. tostring(err))
		end
	end
end
local shuttingDown = false
local usingMock = false

local function log(level: SessionStore.LogLevel, message: string)
	if level == "info" then
		if RunService:IsStudio() then
			print(message)
		end
	else
		warn(message)
	end
end

-- Picks the backing store: the real DataStore, or the mock in Studio when it's unavailable.
local function chooseStore(): SessionStore.Store
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.Data.StoreName)
	end)

	if RunService:IsStudio() then
		local usable = ok
		if ok then
			usable = pcall(function()
				(result :: DataStore):GetAsync("__studio_probe")
			end)
		end
		if not usable then
			usingMock = true
			warn(
				"[DataService] DataStores are unavailable in this Studio session (publish the place and enable "
					.. "'Studio Access to API Services' in Game Settings > Security). Using an in-memory "
					.. "MockDataStore - NOTHING WILL BE SAVED."
			)
			return MockDataStore.new() :: any
		end
	end

	if not ok then
		warn(
			"[DataService] GetDataStore failed: "
				.. tostring(result)
				.. " - players can't load until it recovers"
		)
		-- A store that always fails: loads fail and players are kicked instead of playing unsaved.
		return {
			UpdateAsync = function()
				error("DataStore unavailable")
			end,
		}
	end
	return result :: any
end

local function releaseProfile(userId: number, profile: Profile)
	releasingCount[userId] = (releasingCount[userId] or 0) + 1
	lastAutosave[profile] = nil
	local ok = profile:ReleaseAsync()
	if not ok and not profile:IsLost() then
		warn(
			string.format(
				"[DataService] Final save for user %d failed; the newest changes may be lost",
				userId
			)
		)
	end
	local remaining = (releasingCount[userId] or 1) - 1
	releasingCount[userId] = if remaining > 0 then remaining else nil
end

local function setupReplication(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local harvested = Instance.new("IntValue")
	harvested.Name = "Harvested"
	harvested.Parent = leaderstats
	local biomass = Instance.new("IntValue")
	biomass.Name = "Biomass"
	biomass.Parent = leaderstats
	leaderstats.Parent = player

	DataService:Replicate(player)
	player:SetAttribute("DataLoaded", true)
end

local function onPlayerAdded(player: Player)
	-- Same-server rejoin: don't race our own release of this user's previous session.
	local waitStart = os.clock()
	while releasingCount[player.UserId] ~= nil and os.clock() - waitStart < GameConfig.Data.ShutdownTimeout do
		task.wait(0.2)
	end
	if player.Parent ~= Players then
		return
	end

	local key = GameConfig.Data.KeyPrefix .. tostring(player.UserId)
	local profile, err = sessionStore:LoadAsync(key, { player.UserId })

	if profile == nil then
		warn(
			string.format(
				"[DataService] Could not load %s (%d): %s",
				player.Name,
				player.UserId,
				tostring(err)
			)
		)
		if player.Parent == Players then
			player:Kick(KICK_MESSAGES[err or "Failed"] or KICK_MESSAGES.Failed)
		end
		return
	end

	if player.Parent ~= Players or shuttingDown then
		releaseProfile(player.UserId, profile)
		return
	end

	profile.onLost = function()
		if player.Parent == Players then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
	end

	profiles[player] = profile
	lastAutosave[profile] = os.clock()
	setupReplication(player)
	DataService.ProfileLoaded:Fire(player, profile)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return -- never loaded, or a load is still running (it releases itself when it finishes)
	end
	runBeforeSave(player, profile)
	profiles[player] = nil
	releaseProfile(player.UserId, profile)
end

local function autosaveLoop()
	while true do
		task.wait(1)
		local now = os.clock()
		for player, profile in profiles do
			local last = lastAutosave[profile]
			if last ~= nil and now - last >= GameConfig.Data.AutosaveSeconds then
				lastAutosave[profile] = now
				runBeforeSave(player, profile)
				task.spawn(function()
					profile:SaveAsync()
				end)
			end
		end
	end
end

local function onClose()
	shuttingDown = true
	local toRelease: { { userId: number, profile: Profile } } = {}
	for player, profile in profiles do
		runBeforeSave(player, profile)
		table.insert(toRelease, { userId = player.UserId, profile = profile })
	end
	table.clear(profiles)

	for _, entry in toRelease do
		task.spawn(releaseProfile, entry.userId, entry.profile)
	end

	local start = os.clock()
	while next(releasingCount) ~= nil and os.clock() - start < GameConfig.Data.ShutdownTimeout do
		task.wait(0.1)
	end
	if next(releasingCount) ~= nil then
		warn("[DataService] Shutdown timeout: some profiles may not have been saved")
	end
end

function DataService:Init()
	sessionStore = SessionStore.new({
		store = chooseStore(),
		sessionId = HttpService:GenerateGUID(false),
		jobId = if game.JobId ~= "" then game.JobId else "studio",
		now = os.time,
		wait = task.wait,
		sanitize = Sanitize.run,
		log = log,
		lockStaleSeconds = GameConfig.Data.LockStaleSeconds,
		loadRetries = GameConfig.Data.LoadRetries,
		loadRetryDelay = GameConfig.Data.LoadRetryDelay,
		writeRetries = GameConfig.Data.WriteRetries,
	})
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	game:BindToClose(onClose)
	task.spawn(autosaveLoop)
end

-------------------------------------------------------------------------------
-- Public API
-------------------------------------------------------------------------------

function DataService:IsUsingMock(): boolean
	return usingMock
end

-- Registers a hook that runs right before each save of a player's data (see beforeSave).
function DataService:OnBeforeSave(callback: (player: Player, data: any) -> ())
	table.insert(beforeSave, callback)
end

function DataService:GetProfile(player: Player): Profile?
	return profiles[player]
end

-- Returns the live data table only while the profile may still be changed.
function DataService:GetData(player: Player): PlayerData?
	local profile = profiles[player]
	if profile == nil or not profile:IsActive() then
		return nil
	end
	return profile.data :: PlayerData
end

-- Yields until the player's profile is loaded, the player leaves, or `timeout` passes.
function DataService:WaitForProfile(player: Player, timeout: number): Profile?
	local start = os.clock()
	while player.Parent == Players and os.clock() - start < timeout do
		local profile = profiles[player]
		if profile ~= nil then
			return profile
		end
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService:GetLoadedPlayers(): { Player }
	local list = {}
	for player in profiles do
		table.insert(list, player)
	end
	return list
end

function DataService:Replicate(player: Player)
	local profile = profiles[player]
	if profile == nil then
		return
	end
	local data = profile.data :: PlayerData
	for _, id in Currencies.Ids do
		player:SetAttribute("Cur_" .. id, data.currencies[id] or 0)
	end
	for nodeId in data.techUnlocks do
		if Tech.Nodes[nodeId] ~= nil then
			player:SetAttribute("Tech_" .. nodeId, true)
		end
	end
	for _, item in CosmeticConfig.List do
		if item.unlock.kind == "premium" then
			player:SetAttribute("Owned_" .. item.id, data.cosmetics.owned[item.id] == true)
		end
	end
	for _, slot in CosmeticConfig.Slots do
		player:SetAttribute("Equipped_" .. slot, data.cosmetics.equipped[slot])
	end
	player:SetAttribute("CropsHarvested", data.cropsHarvested)
	player:SetAttribute("GridSize", Tech.stats(data.techUnlocks).gridSize)
	player:SetAttribute("GrowthBoostUntil", data.boosts.growthUntil)
	player:SetAttribute("YieldBoostUntil", data.boosts.yieldUntil)

	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats ~= nil then
		local biomass = leaderstats:FindFirstChild("Biomass")
		if biomass ~= nil and biomass:IsA("IntValue") then
			biomass.Value = data.currencies.biomass or 0
		end
		local harvested = leaderstats:FindFirstChild("Harvested")
		if harvested ~= nil and harvested:IsA("IntValue") then
			harvested.Value = data.cropsHarvested
		end
	end
end

-- Adds (or with a negative amount, spends) a currency. Fails instead of going below zero.
function DataService:AddCurrency(player: Player, currency: string, amount: number): boolean
	local data = DataService:GetData(player)
	if data == nil or Currencies.ById[currency] == nil or amount ~= amount or amount % 1 ~= 0 then
		return false
	end
	local newValue = (data.currencies[currency] or 0) + amount
	if newValue < 0 then
		return false
	end
	data.currencies[currency] = newValue
	DataService:Replicate(player)
	return true
end

function DataService:AddCropsHarvested(player: Player, count: number): boolean
	local data = DataService:GetData(player)
	if data == nil or count < 0 or count % 1 ~= 0 then
		return false
	end
	data.cropsHarvested += count
	DataService:Replicate(player)
	return true
end

-- Stores a script in a slot (in memory; persisted by the next autosave / release).
function DataService:SetScript(player: Player, slot: number, source: string): boolean
	local data = DataService:GetData(player)
	if data == nil or slot < 1 or slot > GameConfig.Script.Slots or slot % 1 ~= 0 then
		return false
	end
	if type(source) ~= "string" or utf8.len(source) == nil then
		return false
	end
	data.scripts[slot] = Text.truncateUtf8(source, GameConfig.Script.MaxSourceBytes)
	return true
end

function DataService:GetScripts(player: Player): { string }?
	local data = DataService:GetData(player)
	if data == nil then
		return nil
	end
	return table.clone(data.scripts)
end

-- Module names of the script slots (what `import` and simulate() look up).
function DataService:GetScriptNames(player: Player): { string }?
	local data = DataService:GetData(player)
	if data == nil then
		return nil
	end
	return table.clone(data.scriptNames)
end

-- Renames a slot. Returns (true) or (false, player-facing reason).
function DataService:RenameScript(player: Player, slot: number, name: string): (boolean, string?)
	local data = DataService:GetData(player)
	if data == nil then
		return false, "Your save data is still loading."
	end
	if slot < 1 or slot > GameConfig.Script.Slots or slot % 1 ~= 0 then
		return false, "That script slot doesn't exist."
	end
	local ok, reason = ScriptNames.validate(name, data.scriptNames, slot)
	if not ok then
		return false, reason
	end
	data.scriptNames[slot] = name
	return true
end

-- Current (growth, yield) multipliers from timed boosts.
function DataService:GetBoostMultipliers(player: Player): (number, number)
	local data = DataService:GetData(player)
	if data == nil then
		return 1, 1
	end
	local now = os.time()
	local growth = if now < data.boosts.growthUntil then MonetizationConfig.Boosts.growth.multiplier else 1
	local yield = if now < data.boosts.yieldUntil then MonetizationConfig.Boosts.yield.multiplier else 1
	return growth, yield
end

return DataService
