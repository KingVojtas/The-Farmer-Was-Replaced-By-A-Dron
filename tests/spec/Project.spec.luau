--[[
	default.project.json (docs/BUGS.md BUG-26): `rojo build` only writes SERIALISED properties.
	A Part's "Position" / "Orientation" are not (the file stores "CFrame"), so they were dropped:
	the 16-stud Baseplate landed at the origin, its top at y = 8, and buried every plot (tiles at
	y = 1.3, stations, the hovering drone). `rojo serve` hid it, because the plugin sets Position
	live. Instances in the project must place themselves with CFrame.
]]
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local NOT_SERIALISED = { "Position", "Orientation", "Rotation" }

return function(T, _Loader)
	local describe, it, expect = T.describe, T.it, T.expect

	local project = serde.decode("json", fs.readFile("default.project.json"))

	-- Every { path, properties } node in the project tree.
	local function nodes(tree, path, out)
		for key, value in tree do
			if type(value) == "table" and string.sub(key, 1, 1) ~= "$" then
				nodes(value, path .. "." .. key, out)
			end
		end
		if tree["$properties"] ~= nil then
			table.insert(out, { path = path, properties = tree["$properties"] })
		end
		return out
	end

	describe("default.project.json", function()
		it("never sets a property rojo build would drop (Position, Orientation, Rotation)", function()
			local bad = {}
			for _, node in nodes(project.tree, "game", {}) do
				for _, name in NOT_SERIALISED do
					if node.properties[name] ~= nil then
						table.insert(bad, node.path .. "." .. name)
					end
				end
			end
			if #bad > 0 then
				error("use CFrame instead: " .. table.concat(bad, ", "))
			end
		end)

		it("keeps the Baseplate top at y = 0 and the spawn on it", function()
			local workspace = project.tree.Workspace
			local base = workspace.Baseplate["$properties"]
			local y = base.CFrame.CFrame.position[2]
			expect(y + base.Size[2] / 2).toBe(0)
			local spawn = workspace.SpawnLocation["$properties"]
			expect(spawn.CFrame.CFrame.position[2] - spawn.Size[2] / 2).toBe(0)
		end)
	end)
end
