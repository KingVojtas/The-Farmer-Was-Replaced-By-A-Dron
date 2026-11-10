--!strict
--[[
	PlotGuardService
	================
	Keeps guests off other players' farms. SERVER-AUTHORITATIVE: the client is never trusted.
	(Crops stay per player and drones stay client-side, non-colliding visuals; nothing here
	changes that.)

	COLLISION GROUPS (GameConfig.Collision, registered in Init)
	  Players      every character part (assigned here on spawn, and to parts added later)
	  PlotTiles    every field tile (GridService)
	  PlotBarrier  4 invisible walls just outside each plot's Zone (GridService)

	  pair                    collides  why
	  Players  - PlotTiles    no        nobody stands on a farm's tiles; feet stay on the Base
	  Players  - PlotBarrier  yes       a character can't walk or jump into a plot (16 studs)
	  Default  - PlotBarrier  no        walls never stop loose parts or anything that isn't a player
	  PlotTiles - PlotBarrier no        (static, never meet)
	  everything else         default

	OWNER VS GUEST without 2 groups per plot (Roblox allows only 32 groups in total, too few
	for a full server): characters are simulated by their own client, so the OWNER's client
	sets its own 4 walls CanCollide = false locally (ControlModeController). Only that player
	passes; every other client still collides with them.

	THE AUTHORITY is the sweep below: every GameConfig.PlotGuard.CheckSeconds the server puts
	any non-owner whose HumanoidRootPart is inside another plot's Zone back outside, across
	the nearest side (Shared.Util.PlotFraming.exitPoint). A client that deletes the walls
	gains nothing. A plot with the attribute AllowVisitors = true (default false) opens its
	walls (GridService) and is skipped here.
]]

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local PlotFraming = require(ReplicatedStorage.Shared.Util.PlotFraming)
local GridService = require(script.Parent.GridService)

local COLLISION = GameConfig.Collision
local GUARD = GameConfig.PlotGuard

local PlotGuardService = {}

local function setGroup(part: Instance)
	if part:IsA("BasePart") then
		part.CollisionGroup = COLLISION.Players
	end
end

local function onCharacter(character: Model)
	for _, descendant in character:GetDescendants() do
		setGroup(descendant)
	end
	character.DescendantAdded:Connect(setGroup) -- accessories, tools, layered clothing
end

-- Puts a guest back outside `zone`, across the nearest side, at their current height.
local function eject(character: Model, root: BasePart, zone: BasePart)
	local localPoint = zone.CFrame:PointToObjectSpace(root.Position)
	local x, z =
		PlotFraming.exitPoint(localPoint.X, localPoint.Z, zone.Size.X, zone.Size.Z, GUARD.EjectClearance)
	local outside = zone.CFrame:PointToWorldSpace(Vector3.new(x, localPoint.Y, z))
	local height = math.max(root.Position.Y, 3) -- never under the ground
	character:PivotTo(CFrame.new(outside.X, height, outside.Z) * character:GetPivot().Rotation)
	root.AssemblyLinearVelocity = Vector3.zero
end

local function sweep()
	local plots = GridService:GetPlots()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
		if character == nil or root == nil or not root:IsA("BasePart") then
			continue
		end
		for _, plot in plots do
			if plot.owner == player or plot.destroyed or plot.model:GetAttribute("AllowVisitors") == true then
				continue
			end
			local zone = plot.zone
			local p = zone.CFrame:PointToObjectSpace(root.Position)
			if PlotFraming.inside(p.X, p.Y, p.Z, zone.Size.X, zone.Size.Y, zone.Size.Z, 0) then
				eject(character, root, zone)
				break
			end
		end
	end
end

function PlotGuardService:Init()
	-- Registered in Init: GridService only builds plots (and assigns groups) from Start on.
	for _, name in { COLLISION.Players, COLLISION.Tiles, COLLISION.Barrier } do
		PhysicsService:RegisterCollisionGroup(name)
	end
	PhysicsService:CollisionGroupSetCollidable(COLLISION.Players, COLLISION.Tiles, false)
	PhysicsService:CollisionGroupSetCollidable(COLLISION.Players, COLLISION.Barrier, true)
	PhysicsService:CollisionGroupSetCollidable("Default", COLLISION.Barrier, false)
	PhysicsService:CollisionGroupSetCollidable(COLLISION.Tiles, COLLISION.Barrier, false)
	PhysicsService:CollisionGroupSetCollidable(COLLISION.Barrier, COLLISION.Barrier, false)
end

function PlotGuardService:Start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(onCharacter)
		if player.Character ~= nil then
			onCharacter(player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, player in Players:GetPlayers() do
		hook(player)
	end

	task.spawn(function()
		while true do
			task.wait(GUARD.CheckSeconds)
			local ok, err = pcall(sweep :: any)
			if not ok then
				warn("[PlotGuardService] sweep failed: " .. tostring(err))
			end
		end
	end)
end

return PlotGuardService
