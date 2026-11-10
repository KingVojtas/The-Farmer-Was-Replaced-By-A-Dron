return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local IconConfig = Loader.get("ReplicatedStorage.Shared.Config.IconConfig")
	local Currencies = Loader.get("ReplicatedStorage.Shared.Config.Currencies")
	local TechTree = Loader.get("ReplicatedStorage.Shared.Config.TechTree")
	local MonetizationConfig = Loader.get("ReplicatedStorage.Shared.Config.MonetizationConfig")
	local CosmeticConfig = Loader.get("ReplicatedStorage.Shared.Config.CosmeticConfig")

	local function exists(key)
		return IconConfig.Icons[key] ~= nil
	end

	describe("IconConfig", function()
		it("is well-formed (ids, emoji fallbacks, colours)", function()
			local problems = IconConfig.validate()
			if #problems > 0 then
				error(table.concat(problems, "\n"))
			end
		end)

		it("has an icon for every currency, the battery and every status badge", function()
			for _, currency in Currencies.List do
				expect(IconConfig.forCurrency(currency.id)).toBe(currency.id)
			end
			for _, key in { "energy", "water", "cargo", "lock", "check", "star", "unknown" } do
				expect(exists(key)).toBe(true)
			end
		end)

		it("has an icon for every Tech Tree node", function()
			for id, node in TechTree.Nodes do
				if not exists(node.icon) then
					error(id .. " uses missing icon " .. tostring(node.icon))
				end
			end
		end)

		it("has an icon for every Gamepass and Developer Product", function()
			for key, pass in MonetizationConfig.GamePasses do
				if not exists(pass.icon) then
					error("pass " .. key .. " uses missing icon " .. tostring(pass.icon))
				end
			end
			for key, product in MonetizationConfig.Products do
				if not exists(product.icon) then
					error("product " .. key .. " uses missing icon " .. tostring(product.icon))
				end
			end
		end)

		it("has an icon for every hat style", function()
			for _, item in CosmeticConfig.List do
				if item.slot == "hat" and item.style ~= nil then
					expect(exists("hat_" .. item.style)).toBe(true)
				end
			end
		end)

		it("turns asset ids into rbxassetid:// strings and placeholders into ''", function()
			local def = IconConfig.Icons.wheat
			local saved = def.assetId
			def.assetId = 0
			expect(IconConfig.image("wheat")).toBe("")
			def.assetId = 1234567
			expect(IconConfig.image("wheat")).toBe("rbxassetid://1234567")
			def.assetId = saved
		end)

		it("falls back safely for unknown keys and weather", function()
			expect(IconConfig.get("nope").emoji).toBe(IconConfig.Icons.unknown.emoji)
			expect(IconConfig.get(nil).emoji).toBe(IconConfig.Icons.unknown.emoji)
			expect(IconConfig.forWeather("Rainy")).toBe("weather_Rainy")
			expect(IconConfig.forWeather("Snow")).toBe("weather_Sunny")
		end)

		describe("icon atlas", function()
			local Atlas = IconConfig.Atlas

			-- Runs fn with the atlas "uploaded" as `id` and `cells`, then restores the real data.
			local function withAtlas(id, cells, fn)
				local savedId, savedCells = Atlas.assetId, Atlas.cells
				Atlas.assetId, Atlas.cells = id, cells
				local ok, err = pcall(fn)
				Atlas.assetId, Atlas.cells = savedId, savedCells
				if not ok then
					error(err, 0)
				end
			end

			it("is ONE texture: 8 x 128 px columns, big enough for the whole order", function()
				expect(Atlas.cell).toBe(128)
				expect(Atlas.columns).toBe(8)
				expect(Atlas.width).toBe(Atlas.cell * Atlas.columns)
				local rows = math.ceil(#IconConfig.AtlasOrder / Atlas.columns)
				expect(Atlas.height).toBeAtLeast(rows * Atlas.cell)
			end)

			it("covers weather, currencies, stations and the drone", function()
				local listed = {}
				for _, key in IconConfig.AtlasOrder do
					listed[key] = true
				end
				for _, key in
					{
						"weather_Sunny",
						"weather_Rainy",
						"weather_Drought",
						"hay",
						"wheat",
						"biofuel",
						"charger",
						"factory",
						"drone",
					}
				do
					if not listed[key] then
						error(key .. " is missing from IconConfig.AtlasOrder")
					end
				end
			end)

			it("maps a cell index to its pixel rect (row-major, 8 per row)", function()
				withAtlas(999, { hay = 0, wheat = 1, grid = 12, drone = 32 }, function()
					local hay = IconConfig.atlasRect("hay")
					expect(hay and hay.x).toBe(0)
					expect(hay and hay.y).toBe(0)
					expect(hay and hay.size).toBe(128)
					local wheat = IconConfig.atlasRect("wheat")
					expect(wheat and wheat.x).toBe(128)
					expect(wheat and wheat.y).toBe(0)
					local grid = IconConfig.atlasRect("grid")
					expect(grid and grid.x).toBe(4 * 128)
					expect(grid and grid.y).toBe(128)
					local drone = IconConfig.atlasRect("drone")
					expect(drone and drone.x).toBe(0)
					expect(drone and drone.y).toBe(4 * 128)
				end)
			end)

			it("keeps the emoji while the atlas isn't uploaded or a key has no art", function()
				withAtlas(0, { hay = 0 }, function()
					expect(IconConfig.atlasRect("hay")).toBeNil()
					expect(IconConfig.image("hay")).toBe("")
				end)
				withAtlas(999, { hay = 0 }, function()
					expect(IconConfig.atlasRect("carrot")).toBeNil()
					expect(IconConfig.image("carrot")).toBe("")
					expect(IconConfig.atlasRect(nil)).toBeNil()
					expect(IconConfig.image("hay")).toBe("rbxassetid://999")
				end)
			end)

			it("lets a dedicated per-icon upload win over the atlas", function()
				local def = IconConfig.Icons.hay
				local saved = def.assetId
				def.assetId = 4242
				local ok, err = pcall(function()
					withAtlas(999, { hay = 0 }, function()
						expect(IconConfig.image("hay")).toBe("rbxassetid://4242")
					end)
				end)
				def.assetId = saved
				if not ok then
					error(err, 0)
				end
			end)

			it("validate() catches a cell that doesn't match AtlasOrder", function()
				withAtlas(999, { wheat = 0 }, function()
					local problems = table.concat(IconConfig.validate(), "\n")
					expect(problems).toContain("wheat is not in its AtlasOrder cell")
				end)
			end)
		end)

		it("uses Roblox's built-in Robux icon", function()
			expect(string.sub(IconConfig.ROBUX_IMAGE, 1, 11)).toBe("rbxasset://")
		end)
	end)
end
