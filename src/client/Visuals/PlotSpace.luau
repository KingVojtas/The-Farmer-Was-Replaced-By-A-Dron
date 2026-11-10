--!strict
--[[
	PlotSpace
	=========
	Small client helpers shared by the visual layers (PlotRenderer crop FX and dressing,
	WeatherFxController): "where am I?", "how far is that plot?" and "which plot is mine?".
	Plots are Workspace.Plots.Plot_N models built by Server.Services.GridService; each has an
	invisible `Zone` box (the base footprint + margin) and an `OwnerUserId` attribute.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlotSpace = {}

-- Where "near" is measured from: the character, else the camera.
function PlotSpace.referencePoint(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character ~= nil then character:FindFirstChild("HumanoidRootPart") else nil
	if root ~= nil and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera ~= nil then camera.CFrame.Position else nil
end

-- Distance from a point to the plot's Zone box (0 inside it).
function PlotSpace.distanceToPlot(plot: Model, point: Vector3): number
	local zone = plot:FindFirstChild("Zone")
	if zone ~= nil and zone:IsA("BasePart") then
		local p = zone.CFrame:PointToObjectSpace(point)
		local half = zone.Size / 2
		local clamped = Vector3.new(
			math.clamp(p.X, -half.X, half.X),
			math.clamp(p.Y, -half.Y, half.Y),
			math.clamp(p.Z, -half.Z, half.Z)
		)
		return (p - clamped).Magnitude
	end
	local origin = plot:GetAttribute("Origin")
	return if typeof(origin) == "Vector3" then (origin - point).Magnitude else math.huge
end

function PlotSpace.isOwn(plot: Instance): boolean
	return plot:GetAttribute("OwnerUserId") == Players.LocalPlayer.UserId
end

-- The local player's plot, if it exists yet.
function PlotSpace.ownPlot(): Model?
	local plots = Workspace:FindFirstChild("Plots")
	if plots == nil then
		return nil
	end
	for _, plot in plots:GetChildren() do
		if plot:IsA("Model") and PlotSpace.isOwn(plot) then
			return plot
		end
	end
	return nil
end

-- The plot's Zone part (sized by GridService to the base footprint + margin), if present.
function PlotSpace.zone(plot: Model): BasePart?
	local zone = plot:FindFirstChild("Zone")
	return if zone ~= nil and zone:IsA("BasePart") then zone else nil
end

-- The weather this plot sees: its own "Weather" attribute if it has one, else Workspace's.
function PlotSpace.weather(plot: Model?): string
	local fromPlot = if plot ~= nil then plot:GetAttribute("Weather") else nil
	local name = if type(fromPlot) == "string" then fromPlot else Workspace:GetAttribute("Weather")
	return if type(name) == "string" then name else "Sunny"
end

return PlotSpace
