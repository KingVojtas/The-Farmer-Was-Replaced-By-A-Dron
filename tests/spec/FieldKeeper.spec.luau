--[[
	FieldKeeper (docs/BUGS.md BUG-02): the field saved on leave must be the LIVE field, whichever
	PlayerRemoving handler Roblox runs first. The two handlers are replayed here in both orders:

	  DataService's: runBeforeSave(player, data) (-> keeper:beforeSave), then the profile is
	                 released (GetData returns nil from then on), then the final write
	  GridService's: removePlot (-> keeper:detach), then the plot is gone
]]
return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local FieldKeeper = Loader.get("ServerScriptService.Server.Progression.FieldKeeper")
	local Growth = Loader.get("ServerScriptService.Server.Progression.Growth")

	local function newField(size)
		local tiles = {}
		for y = 0, size - 1 do
			for x = 0, size - 1 do
				tiles[y * size + x + 1] = Growth.newTile(x, y, true)
			end
		end
		return tiles
	end

	-- A fake DataService: the data stays reachable until release(); `written` is what the final
	-- write after release() carries (a copy of data.field at that moment).
	local function newSession()
		local player = { Name = "p" }
		local data = { field = { savedAt = 1, tiles = { { 0, 0, "", "empty", 0, false, 0 } } } } -- stale autosave
		local loaded = true
		local session = { player = player, data = data, written = nil }
		session.keeper = FieldKeeper.new(function(who)
			return if who == player and loaded then data else nil
		end, function()
			return 1000
		end)
		function session.dataServiceLeave()
			session.keeper:beforeSave(player, data) -- runBeforeSave
			loaded = false -- profiles[player] = nil
			session.written = data.field -- ReleaseAsync commits profile.data
		end
		function session.gridServiceLeave()
			session.keeper:detach(player) -- removePlot
		end
		return session
	end

	local function plantWheat(tiles)
		Growth.plant(tiles[1], "wheat")
	end

	describe("FieldKeeper (BUG-02)", function()
		it("saves the live field when DataService's handler runs first", function()
			local s = newSession()
			local tiles = newField(3)
			s.keeper:attach(s.player, function()
				return tiles
			end)
			plantWheat(tiles)
			s.dataServiceLeave()
			s.gridServiceLeave()
			expect(s.written.savedAt).toBe(1000)
			expect(#s.written.tiles).toBe(9)
			expect(s.written.tiles[1][3]).toBe("wheat")
		end)

		it("saves the live field when GridService's handler runs first", function()
			local s = newSession()
			local tiles = newField(3)
			s.keeper:attach(s.player, function()
				return tiles
			end)
			plantWheat(tiles)
			s.gridServiceLeave()
			s.dataServiceLeave()
			expect(s.written.savedAt).toBe(1000)
			expect(#s.written.tiles).toBe(9)
			expect(s.written.tiles[1][3]).toBe("wheat")
		end)

		it("snapshots the current tiles after a Grid Expansion swapped the table", function()
			local s = newSession()
			local plot = { tiles = newField(3) }
			s.keeper:attach(s.player, function()
				return plot.tiles
			end)
			plot.tiles = newField(4)
			s.keeper:beforeSave(s.player, s.data)
			expect(#s.data.field.tiles).toBe(16)
		end)

		it("forgets a detached player (no snapshot of a removed plot)", function()
			local s = newSession()
			local tiles = newField(3)
			s.keeper:attach(s.player, function()
				return tiles
			end)
			s.keeper:detach(s.player)
			expect(s.keeper:isAttached(s.player)).toBe(false)
			local other = { field = "untouched" }
			s.keeper:beforeSave(s.player, other)
			expect(other.field).toBe("untouched")
		end)

		it("does nothing for a player that never had a plot", function()
			local s = newSession()
			s.keeper:detach(s.player)
			s.keeper:beforeSave(s.player, s.data)
			expect(s.data.field.savedAt).toBe(1)
		end)
	end)
end
