--[[
	SoundConfig (ASSETS-8): the sound table must match the OGGs tools/build_sfx.py writes, and a
	sound must stay SILENT until it's uploaded (assetId 0) or while the master switch is off.
]]
local fs = require("@lune/fs")

return function(T, Loader)
	local describe, it, expect = T.describe, T.it, T.expect
	local SoundConfig = Loader.get("ReplicatedStorage.Shared.Config.SoundConfig")

	describe("SoundConfig", function()
		it("has a valid table", function()
			local problems = SoundConfig.validate()
			if #problems > 0 then
				error(table.concat(problems, "\n"))
			end
		end)

		it("has an Ogg file in art/audio for every sound, and a sound for every file", function()
			for name in SoundConfig.List do
				local path = "art/audio/" .. name .. ".ogg"
				expect(fs.isFile(path)).toBe(true)
				expect(string.sub(fs.readFile(path), 1, 4)).toBe("OggS")
			end
			for _, entry in fs.readDir("art/audio") do
				local name = string.match(entry, "^(.+)%.ogg$")
				if name ~= nil then
					expect(SoundConfig.List[name] ~= nil).toBe(true)
				end
			end
		end)

		it("stays silent until uploaded, and obeys the master switch", function()
			local hop = SoundConfig.List.hop
			local savedId, savedEnabled = hop.assetId, SoundConfig.Enabled
			hop.assetId = 0
			expect(SoundConfig.get("hop")).toBe(nil)
			hop.assetId = 123
			expect(SoundConfig.get("hop")).toBe(hop)
			SoundConfig.Enabled = false
			expect(SoundConfig.get("hop")).toBe(nil)
			hop.assetId, SoundConfig.Enabled = savedId, savedEnabled
			expect(SoundConfig.get("nope")).toBe(nil)
		end)

		it("only marks the two beds as loops", function()
			for name, sound in SoundConfig.List do
				expect(sound.looped).toBe(name == "charge" or name == "ambient")
			end
		end)
	end)
end
