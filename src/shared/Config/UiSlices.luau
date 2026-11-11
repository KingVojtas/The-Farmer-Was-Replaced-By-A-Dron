--!strict
--[[
	UiSlices
	========
	The 9-slice UI chrome (ASSETS-6): art/ui/<name>.png, drawn by tools/build_ui_slices.py.
	Client.UI.Theme.skin(object, name) puts a slice behind a panel / button. Until a slice is
	uploaded (assetId 0) or while Enabled is false, NOTHING changes: the code-built look
	(colour + UICorner + UIStroke) stays the fallback. Pure data: the offline tests check it
	against the PNGs (tests/spec/UiSlices.spec.luau).

	  size    the PNG's pixel size (drawn at 2x)
	  center  SliceCenter {x0, y0, x1, y1} in those pixels: what stretches; outside = corners
	  scale   SliceScale (0.5: the 2x art shows at its 1x size, crisp on high-DPI)
	  tint    true: ImageColor3 follows the object's BackgroundColor3 (one light image serves
	          every button colour, and hover / press colour tweens keep working)

	UPLOAD: Studio Asset Manager -> Import art/ui/*.png, paste each IMAGE id below.
]]

export type Slice = {
	assetId: number,
	size: { number },
	center: { number },
	scale: number,
	tint: boolean,
}

local UiSlices = {}

-- Master switch: false = always the code-built look, even with uploaded slices.
UiSlices.Enabled = true

UiSlices.List = {
	panel = {
		assetId = 71234864559639,
		size = { 64, 64 },
		center = { 24, 24, 40, 40 },
		scale = 0.5,
		tint = false,
	},
	panel_raised = {
		assetId = 125527694578856,
		size = { 64, 64 },
		center = { 24, 24, 40, 40 },
		scale = 0.5,
		tint = false,
	},
	button_primary = {
		assetId = 130947479507092,
		size = { 64, 64 },
		center = { 14, 14, 50, 46 },
		scale = 0.5,
		tint = true,
	},
	button_secondary = {
		assetId = 132145751526912,
		size = { 64, 64 },
		center = { 14, 14, 50, 50 },
		scale = 0.5,
		tint = false,
	},
	button_danger = {
		assetId = 97912749381870,
		size = { 64, 64 },
		center = { 14, 14, 50, 46 },
		scale = 0.5,
		tint = false,
	},
	tab_on = {
		assetId = 138361535416806,
		size = { 64, 48 },
		center = { 14, 14, 50, 44 },
		scale = 0.5,
		tint = false,
	},
	tab_off = {
		assetId = 139054084268412,
		size = { 64, 48 },
		center = { 14, 14, 50, 44 },
		scale = 0.5,
		tint = false,
	},
	meter_track = {
		assetId = 131501624954044,
		size = { 48, 24 },
		center = { 12, 11, 36, 13 },
		scale = 0.5,
		tint = false,
	},
	meter_cap = {
		assetId = 109685872050737,
		size = { 24, 24 },
		center = { 11, 11, 13, 13 },
		scale = 0.5,
		tint = false,
	},
	toast = {
		assetId = 70604590024042,
		size = { 64, 64 },
		center = { 24, 24, 40, 40 },
		scale = 0.5,
		tint = false,
	},
	modal_header = {
		assetId = 88439635007101,
		size = { 64, 64 },
		center = { 24, 22, 40, 60 },
		scale = 0.5,
		tint = false,
	},
} :: { [string]: Slice }

-- The slice to draw, or nil (unknown, not uploaded, or switched off).
function UiSlices.get(name: string): Slice?
	local slice = UiSlices.List[name]
	if not UiSlices.Enabled or slice == nil or slice.assetId <= 0 then
		return nil
	end
	return slice
end

-- Checks the table (used by the tests). Returns { problem, ... }.
function UiSlices.validate(): { string }
	local problems: { string } = {}
	for name, slice in UiSlices.List do
		local w, h = slice.size[1], slice.size[2]
		local c = slice.center
		if type(slice.assetId) ~= "number" or slice.assetId < 0 or slice.assetId % 1 ~= 0 then
			table.insert(problems, name .. ": assetId must be a whole number >= 0")
		end
		if #c ~= 4 or c[1] < 0 or c[2] < 0 or c[3] > w or c[4] > h or c[1] >= c[3] or c[2] >= c[4] then
			table.insert(
				problems,
				name .. ": center must be {x0, y0, x1, y1} inside the image, x0 < x1, y0 < y1"
			)
		end
		if slice.scale <= 0 then
			table.insert(problems, name .. ": scale must be > 0")
		end
	end
	return problems
end

return UiSlices
