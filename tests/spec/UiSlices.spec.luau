--[[
	UiSlices (ASSETS-6): the 9-slice table must match the PNGs tools/build_ui_slices.py writes,
	and a slice must stay OFF (code-built look) until it's uploaded.
]]
local fs = require("@lune/fs")

return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local UiSlices = Loader.get("ReplicatedStorage.Shared.Config.UiSlices")

	-- Width and height from a PNG's IHDR chunk (big-endian, bytes 17..24).
	local function pngSize(path)
		local data = fs.readFile(path)
		local b = { string.byte(data, 17, 24) }
		local w = ((b[1] * 256 + b[2]) * 256 + b[3]) * 256 + b[4]
		local h = ((b[5] * 256 + b[6]) * 256 + b[7]) * 256 + b[8]
		return w, h
	end

	describe("UiSlices", function()
		it("has a valid table", function()
			local problems = UiSlices.validate()
			if #problems > 0 then
				error(table.concat(problems, "\n"))
			end
		end)

		it("matches every PNG in art/ui (size and existence)", function()
			for name, slice in UiSlices.List do
				local path = "art/ui/" .. name .. ".png"
				expect(fs.isFile(path)).toBe(true)
				local w, h = pngSize(path)
				expect(w).toBe(slice.size[1])
				expect(h).toBe(slice.size[2])
			end
		end)

		it("stays off until a slice is uploaded, and obeys the master switch", function()
			local panel = UiSlices.List.panel
			local savedId, savedEnabled = panel.assetId, UiSlices.Enabled
			panel.assetId = 0
			expect(UiSlices.get("panel")).toBeNil() -- assetId 0: code-built look
			expect(UiSlices.get("nope")).toBeNil()
			panel.assetId = 123
			expect(UiSlices.get("panel")).toBe(panel)
			UiSlices.Enabled = false
			expect(UiSlices.get("panel")).toBeNil()
			panel.assetId, UiSlices.Enabled = savedId, savedEnabled
		end)
	end)
end
