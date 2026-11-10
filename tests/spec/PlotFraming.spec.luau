return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local PlotFraming = Loader.get("ReplicatedStorage.Shared.Util.PlotFraming")
	local GameConfig = Loader.get("ReplicatedStorage.Shared.Config.GameConfig")

	local PITCH = GameConfig.Grid.TileSize + GameConfig.Grid.TileGap
	local FOV = 70 -- Roblox default (vertical)
	local RESERVE = 0.38
	local MARGIN = 1.12

	local function near(a, b)
		return math.abs(a - b) < 1e-6
	end

	describe("PlotFraming", function()
		describe("inside (zone test with hysteresis)", function()
			it("accepts points inside and on the edge of the box", function()
				expect(PlotFraming.inside(0, 0, 0, 10, 30, 10, 0)).toBe(true)
				expect(PlotFraming.inside(5, 0, -5, 10, 30, 10, 0)).toBe(true) -- exactly on the edge
				expect(PlotFraming.inside(0, 15, 0, 10, 30, 10, 0)).toBe(true)
			end)

			it("rejects points outside the box without a margin", function()
				expect(PlotFraming.inside(5.1, 0, 0, 10, 30, 10, 0)).toBe(false)
				expect(PlotFraming.inside(0, 15.5, 0, 10, 30, 10, 0)).toBe(false)
				expect(PlotFraming.inside(0, 0, -6, 10, 30, 10, 0)).toBe(false)
			end)

			it("keeps a player 'inside' until they are past the exit margin", function()
				-- 1 stud outside the edge: out when entering, still in while already inside
				expect(PlotFraming.inside(6, 0, 0, 10, 30, 10, 0)).toBe(false)
				expect(PlotFraming.inside(6, 0, 0, 10, 30, 10, 1.5)).toBe(true)
				expect(PlotFraming.inside(6.6, 0, 0, 10, 30, 10, 1.5)).toBe(false)
			end)
		end)

		describe("center", function()
			it("matches GridService's plot layout (field + station row)", function()
				for _, n in { 3, 6, 10 } do
					local x, z = PlotFraming.center(100, 200, n, PITCH)
					-- columns 0 .. n-1 -> middle column (n-1)/2
					expect(near(x, 100 + (n - 1) / 2 * PITCH)).toBe(true)
					-- rows -1 (stations) .. n-1 -> middle row (n-2)/2, grid +y = world -Z
					expect(near(z, 200 - (n - 2) / 2 * PITCH)).toBe(true)
				end
			end)
		end)

		describe("solve (bird's-eye camera distance)", function()
			it("fits the station row and the field vertically", function()
				for _, n in { 3, 6, 10 } do
					local distance = PlotFraming.solve(n, PITCH, FOV, 16 / 9, RESERVE, MARGIN, 90)
					local _, depth = PlotFraming.extent(n, PITCH)
					local visibleHalfHeight = distance * math.tan(math.rad(FOV) / 2)
					expect(visibleHalfHeight + 1e-6 >= depth / 2 * MARGIN).toBe(true)
				end
			end)

			it("fits the field into the screen area right of the terminal", function()
				for _, aspect in { 16 / 9, 4 / 3, 19.5 / 9 } do
					local distance, shift = PlotFraming.solve(10, PITCH, FOV, aspect, RESERVE, MARGIN, 90)
					local width = PlotFraming.extent(10, PITCH)
					local halfScreenWidth = distance * aspect * math.tan(math.rad(FOV) / 2)
					local freeWidth = 2 * halfScreenWidth * (1 - RESERVE)
					expect(freeWidth + 1e-6 >= width * MARGIN).toBe(true)
					-- the free area's centre sits RESERVE / 2 of the screen right of the middle
					expect(near(shift, RESERVE * halfScreenWidth)).toBe(true)
				end
			end)

			it("moves further away for bigger fields and narrower screens", function()
				local small = PlotFraming.solve(3, PITCH, FOV, 16 / 9, RESERVE, MARGIN, 90)
				local big = PlotFraming.solve(10, PITCH, FOV, 16 / 9, RESERVE, MARGIN, 90)
				expect(big > small).toBe(true)
				local wide = PlotFraming.solve(10, PITCH, FOV, 21 / 9, RESERVE, MARGIN, 90)
				local narrow = PlotFraming.solve(10, PITCH, FOV, 4 / 3, RESERVE, MARGIN, 90)
				expect(narrow >= wide).toBe(true)
			end)

			it("doesn't shift the camera when no space is reserved", function()
				local _, shift = PlotFraming.solve(6, PITCH, FOV, 16 / 9, 0, MARGIN, 90)
				expect(shift).toBe(0)
				local _, shifted = PlotFraming.solve(6, PITCH, FOV, 16 / 9, RESERVE, MARGIN, 90)
				expect(shifted > 0).toBe(true)
			end)

			it("survives silly inputs", function()
				local distance, shift = PlotFraming.solve(3, PITCH, 0, 0, 2, 1, 10)
				expect(distance == distance and distance > 0 and distance < math.huge).toBe(true)
				expect(shift == shift).toBe(true)
			end)
		end)

		describe("exitPoint (guest eject)", function()
			it("pushes out across the nearest side, clearance studs past it", function()
				-- Box 40 x 60: a point near the +X side leaves through +X.
				local x, z = PlotFraming.exitPoint(18, 5, 40, 60, 4)
				expect(x).toBe(24)
				expect(z).toBe(5)
				-- Near the -Z side: leaves through -Z, keeping its X.
				x, z = PlotFraming.exitPoint(-3, -28, 40, 60, 4)
				expect(x).toBe(-3)
				expect(z).toBe(-34)
				-- Dead centre: still lands outside the box.
				x, z = PlotFraming.exitPoint(0, 0, 40, 60, 4)
				expect(PlotFraming.inside(x, 0, z, 40, 10, 60, 0)).toBe(false)
			end)

			it("always ends outside the box", function()
				for _, point in { { 19.9, 29.9 }, { -19.9, 0 }, { 0, -29.9 }, { 7, 7 } } do
					local x, z = PlotFraming.exitPoint(point[1], point[2], 40, 60, 1)
					expect(PlotFraming.inside(x, 0, z, 40, 10, 60, 0)).toBe(false)
				end
			end)
		end)
	end)
end
