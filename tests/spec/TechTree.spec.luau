--[[
	Pins the Tech Tree to the designed hierarchy, so a config edit can't silently change it:

	  Root:   while loop -> basic grid expansions + Wheat
	  Botany: Carrots -> Water Tanks & Trees -> Sunflowers & Pumpkins -> Watering Cans -> Cacti
	          -> Bones/Fossils
	  System: set_speed() & get_time() -> simulate() -> drone hardware / clothing
	          (print() is free from the start: debugging is not prestige)
	  Logic:  1 + 1 -> [1, 2, 3] & def F() -> {1: 2}, import, random(), get_cost()
	          (a = 2 comes with Loops, (x, y) with Grid Expansion I: pacing)
]]
return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local Tech = Loader.get("ReplicatedStorage.Shared.Progression.Tech")
	local TechTree = Loader.get("ReplicatedStorage.Shared.Config.TechTree")
	local Currencies = Loader.get("ReplicatedStorage.Shared.Config.Currencies")

	local function requires(id)
		local node = TechTree.Nodes[id]
		if node == nil then
			error("missing node " .. id, 2)
		end
		local list = table.clone(node.requires)
		table.sort(list)
		return table.concat(list, ",")
	end

	local function unlocks(id, feature)
		for _, f in TechTree.Nodes[id].unlocks or {} do
			if f == feature then
				return true
			end
		end
		return false
	end

	local function expectBranch(ids, branch)
		for _, id in ids do
			if TechTree.Nodes[id].branch ~= branch then
				error(string.format("%s should be in %s, is in %s", id, branch, TechTree.Nodes[id].branch), 2)
			end
		end
	end

	describe("TechTree hierarchy", function()
		it("starts with the while loop, then grid expansions and Wheat", function()
			expect(requires("loops")).toBe("")
			expect(unlocks("loops", "while")).toBe(true)
			expect(requires("wheat")).toBe("loops")
			expect(unlocks("wheat", "crop:wheat")).toBe(true)
			expect(requires("grid_1")).toBe("loops")
			expect(requires("grid_2")).toBe("grid_1,wheat")
			expect(requires("grid_3")).toBe("grid_2")
			expectBranch({ "loops", "wheat", "grid_1", "grid_2", "grid_3" }, "Root")
		end)

		it("has the Botany branch in order", function()
			expect(requires("carrots")).toBe("wheat")
			expect(requires("water_tanks")).toBe("carrots")
			expect(requires("trees")).toBe("carrots")
			expect(requires("sunflowers")).toBe("water_tanks")
			expect(requires("pumpkins")).toBe("trees")
			expect(requires("watering_cans")).toBe("pumpkins,sunflowers")
			expect(requires("cacti")).toBe("watering_cans")
			expect(requires("fossils")).toBe("cacti")
			expect(unlocks("trees", "crop:tree")).toBe(true)
			expect(unlocks("cacti", "crop:cactus")).toBe(true)
			expect(unlocks("fossils", "dig")).toBe(true)
			expectBranch({
				"carrots",
				"water_tanks",
				"trees",
				"sunflowers",
				"pumpkins",
				"watering_cans",
				"cacti",
				"fossils",
			}, "Botany")
		end)

		it("has the System & Drone branch in order", function()
			expect(requires("set_speed")).toBe("wheat")
			expect(requires("get_time")).toBe("wheat")
			expect(requires("simulate")).toBe("get_time,set_speed")
			for _, id in { "battery_1", "motors_1", "cargo_1", "paint_shop" } do
				expect(requires(id)).toBe("simulate")
			end
			expect(requires("wardrobe")).toBe("paint_shop")
			expect(unlocks("paint_shop", "cosmetic:paint")).toBe(true)
			expect(unlocks("wardrobe", "cosmetic:hat")).toBe(true)
			expectBranch(
				{ "set_speed", "get_time", "simulate", "battery_1", "battery_3", "wardrobe" },
				"System"
			)
		end)

		it("has the Logic & Data branch in order", function()
			expect(requires("math")).toBe("wheat")
			expect(TechTree.Nodes.coordinates).toBeNil() -- now on Grid Expansion I
			expect(TechTree.Nodes.variables).toBeNil() -- now on Loops
			expect(requires("arrays")).toBe("math")
			expect(requires("functions")).toBe("math")
			expect(unlocks("loops", "variables")).toBe(true)
			for _, feature in { "get_x", "get_y", "get_size" } do
				expect(unlocks("grid_1", feature)).toBe(true)
			end
			expect(requires("dictionaries")).toBe("arrays")
			expect(requires("import")).toBe("functions")
			expect(requires("random")).toBe("functions")
			expect(requires("get_cost")).toBe("arrays,functions")
			expect(TechTree.Nodes.math.code).toBe("1 + 1")
			expect(TechTree.Nodes.arrays.code).toBe("[1, 2, 3]")
			expect(TechTree.Nodes.functions.code).toBe("def F():")
			expect(TechTree.Nodes.dictionaries.code).toBe("{1: 2}")
			expectBranch({
				"math",
				"arrays",
				"functions",
				"dictionaries",
				"import",
				"random",
				"get_cost",
			}, "Logic")
		end)

		it("costs at least one currency per node and never premium currency", function()
			for id, node in TechTree.Nodes do
				local count = 0
				for currency in node.cost do
					count += 1
					expect(Currencies.ById[currency].kind ~= "premium").toBe(true)
				end
				if count == 0 then
					error(id .. " has no cost")
				end
			end
		end)

		it("lays out every node with prerequisites drawn above or beside it", function()
			for _, edge in Tech.Edges do
				local from, to = TechTree.Nodes[edge.from], TechTree.Nodes[edge.to]
				expect(from.tier <= to.tier).toBe(true)
			end
			expect(#Tech.NodeIds).toBe(#TechTree.List)
		end)
	end)
end
