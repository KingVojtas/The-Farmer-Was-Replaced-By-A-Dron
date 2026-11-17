--[[
	apply_parts.luau: finishes a model that Roblox imported from FBX through Open Cloud.

	    lune run tools/apply_parts <model.rbxm> <model.parts.json>

	Open Cloud imports keep the geometry, the part names and the scale, but NOT what FBX can't
	express for Roblox: every MeshPart comes back plain grey, the Model's pivot sits wherever
	the importer put it, the model is TURNED (180 deg about Y), and it is wrapped as a package. The part sheet is written by
	tools/blender/_common.export (part_sheet) next to each FBX. This script:
	  * sets each MeshPart's Color, Material, Transparency and attributes (PaintSlot, ...)
	  * puts Model.WorldPivot back on the Blender scene origin (the contract pivot: tile top
	    for crops, station top for stations, body centre for the drone), found from the
	    offset between each part's centre in the sheet and in the file
	  * makes every part Anchored, with CanCollide / CanQuery from the sheet (collide, query) and
    Box collision fidelity
	  * removes the PackageLink
	It rewrites the .rbxm in place and fails (exit 1) when a part in the file has no entry in
	the sheet, or the parts disagree on the pivot offset by more than 0.05 studs.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Color3, CFrame, Vector3, Enum = roblox.Color3, roblox.CFrame, roblox.Vector3, roblox.Enum

local rbxmPath, sheetPath = process.args[1], process.args[2]
if rbxmPath == nil or sheetPath == nil then
	print("usage: lune run tools/apply_parts <model.rbxm> <model.parts.json>")
	process.exit(2)
end

local sheet = serde.decode("json", fs.readFile(sheetPath))
local roots = roblox.deserializeModel(fs.readFile(rbxmPath))
local problems = {}

local function hexColor(hex: string)
	return Color3.fromRGB(tonumber(string.sub(hex, 2, 3), 16), tonumber(string.sub(hex, 4, 5), 16), tonumber(string.sub(hex, 6, 7), 16))
end

local model = nil
for _, root in roots do
	if root:IsA("Model") then
		model = root
	end
end
if model == nil then
	print("no Model at the root of " .. rbxmPath)
	process.exit(1)
end

local parts = {}
local seen = {}
for _, inst in model:GetDescendants() do
	if inst.ClassName == "PackageLink" then
		inst:Destroy()
	elseif inst:IsA("BasePart") then
		local entry = sheet.parts[inst.Name]
		if entry == nil then
			table.insert(problems, "no part sheet entry for " .. inst.Name)
		else
			seen[inst.Name] = true
			inst.Color = hexColor(entry.color)
			inst.Material = (Enum.Material :: any)[entry.material]
			-- A detail MaterialVariant (materials.project.json): tinted by Color, so the hue stays.
			inst.MaterialVariant = entry.variant or ""
			inst.Transparency = entry.transparency
			for key, value in entry.attributes do
				inst:SetAttribute(key, value)
			end
			inst.Anchored = true
			-- Collision from the sheet (trunks, rocks, buildings, the soil tile); everything else
			-- is decoration. Box fidelity: cheap, and right for these chunky shapes.
			inst.CanCollide = entry.collide == true
			inst.CanQuery = entry.collide == true or entry.query == true
			inst.CanTouch = false
			if inst:IsA("MeshPart") then
				inst.CollisionFidelity = Enum.CollisionFidelity.Box
			end
			local c = entry.center
			table.insert(parts, { part = inst, center = Vector3.new(c[1], c[2], c[3]) })
		end
	end
end
for name in sheet.parts do
	if not seen[name] then
		table.insert(problems, "part " .. name .. " is in the sheet but not in the file")
	end
end

--[[
	Open Cloud's FBX import TURNS the model (seen: 180 degrees about Y, so the drone's eye faced
	backwards). Find the yaw and offset that map the sheet's part centres onto the file's
	(file = T * sheet), then move every part back into sheet space with T^-1: the model ends
	up exactly in the contract orientation, its pivot on the scene origin. 180 is tried FIRST
	and wins whenever it fits: a one-part or symmetric model fits several turns (its centres
	can't tell them apart), and the importer's turn is the same for every file.
]]
local IMPORT_TURN = 180
local yawUsed = 0
if #parts > 0 then
	local best, bestSpread, bestT = 0, math.huge, Vector3.new()
	for _, degrees in { IMPORT_TURN, 0, 90, 270 } do
		local turn = CFrame.Angles(0, math.rad(degrees), 0)
		local first, spread = nil, 0
		local sum = Vector3.new()
		for _, entry in parts do
			local t = entry.part.CFrame.Position - turn * entry.center
			first = first or t
			spread = math.max(spread, (t - first).Magnitude)
			sum += t
		end
		if spread < bestSpread then
			best, bestSpread, bestT = degrees, spread, sum / #parts
		end
		if bestSpread <= 0.05 then
			break -- the first turn that fits (IMPORT_TURN first)
		end
	end
	if bestSpread > 0.05 then
		table.insert(problems, string.format("no turn fits the part sheet (best %d deg, %.3f studs off)", best, bestSpread))
	end
	local undo = (CFrame.new(bestT) * CFrame.Angles(0, math.rad(best), 0)):Inverse()
	for _, entry in parts do
		entry.part.CFrame = undo * entry.part.CFrame
	end
	local p = sheet.pivot
	model.WorldPivotData = CFrame.new(p[1], p[2], p[3])
	yawUsed = best
end

if #problems > 0 then
	print(rbxmPath .. ":\n  " .. table.concat(problems, "\n  "))
	process.exit(1)
end
fs.writeFile(rbxmPath, roblox.serializeModel(roots))
print(string.format("%s: %d parts coloured, turned back %d deg, pivot on the origin", rbxmPath, #parts, yawUsed))
