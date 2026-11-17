--!strict
--[[
	SoundConfig
	===========
	Every sound the game can play (ASSETS-8): event -> file -> volume. The files are
	art/audio/<name>.ogg, synthesised by tools/build_sfx.py. Client.Controllers.SoundController
	plays them. A sound with assetId 0 (not uploaded yet) is SILENT: play() is a no-op, so the
	game runs the same with or without audio. Pure data; tests/spec/SoundConfig.spec.luau
	checks it against art/audio.

	  assetId      Roblox audio id (tools/roblox_upload.py audio writes it here)
	  volume       Sound.Volume (the files are all peak-normalised to -1 dBFS)
	  group        SoundGroup: SFX (world), UI (buttons, toasts), Ambient (beds and loops)
	  pitchJitter  random +-fraction on PlaybackSpeed per play (0 = always the same)
	  minGap       seconds before the same sound may start again (spam guard)
	  looped       a loop, started and stopped with SoundController.setLoop

	WHEN EACH PLAYS (only for YOUR plot and your own UI):
	  hop      your drone steps one tile          land     it touches down on the charger
	  plant    plant() under your drone           water    water() (never rain)
	  harvest  a ripe harvest                     unripe   an unripe harvest (nothing gained)
	  dig      a tile becomes dug                 fossil   your Fossils go up
	  deposit  cargo into the Bioreactor          unload   cargo banked at the charger
	  refine   your Biofuel goes up               charge   loop while the charger fills you
	  research / purchase / error   the matching toast (Notify kind)
	  click / hover                 any GuiButton    ambient   the calm field bed, always on
]]

export type Group = "SFX" | "UI" | "Ambient"
export type Sound = {
	assetId: number,
	volume: number,
	group: string, -- a Group (plain string: the old solver widens singletons in tables)
	pitchJitter: number,
	minGap: number,
	looped: boolean,
}

local SoundConfig = {}

-- Master switch: false = silence, even with uploaded ids.
SoundConfig.Enabled = true

-- SoundGroup volumes (the player-facing mix).
SoundConfig.Groups = {
	SFX = 0.8,
	UI = 0.6,
	Ambient = 0.5,
} :: { [string]: number }

SoundConfig.List = {
	hop = {
		assetId = 133437677566894,
		volume = 0.3,
		group = "SFX",
		pitchJitter = 0.08,
		minGap = 0.08,
		looped = false,
	},
	land = {
		assetId = 89064459348248,
		volume = 0.45,
		group = "SFX",
		pitchJitter = 0.04,
		minGap = 0.3,
		looped = false,
	},
	plant = {
		assetId = 136375164993905,
		volume = 0.5,
		group = "SFX",
		pitchJitter = 0.08,
		minGap = 0.08,
		looped = false,
	},
	water = {
		assetId = 88923676276226,
		volume = 0.45,
		group = "SFX",
		pitchJitter = 0.08,
		minGap = 0.08,
		looped = false,
	},
	harvest = {
		assetId = 130086974350436,
		volume = 0.5,
		group = "SFX",
		pitchJitter = 0.06,
		minGap = 0.06,
		looped = false,
	},
	unripe = {
		assetId = 110044469643217,
		volume = 0.45,
		group = "SFX",
		pitchJitter = 0.05,
		minGap = 0.1,
		looped = false,
	},
	dig = {
		assetId = 82527451388906,
		volume = 0.55,
		group = "SFX",
		pitchJitter = 0.08,
		minGap = 0.1,
		looped = false,
	},
	fossil = {
		assetId = 99147665758035,
		volume = 0.5,
		group = "SFX",
		pitchJitter = 0,
		minGap = 0.3,
		looped = false,
	},
	deposit = {
		assetId = 83569891644810,
		volume = 0.5,
		group = "SFX",
		pitchJitter = 0.05,
		minGap = 0.3,
		looped = false,
	},
	unload = {
		assetId = 84465051508567,
		volume = 0.45,
		group = "SFX",
		pitchJitter = 0.05,
		minGap = 0.3,
		looped = false,
	},
	refine = {
		assetId = 87190890184841,
		volume = 0.4,
		group = "SFX",
		pitchJitter = 0.05,
		minGap = 0.5,
		looped = false,
	},
	charge = {
		assetId = 96372285494734,
		volume = 0.15,
		group = "SFX",
		pitchJitter = 0,
		minGap = 0,
		looped = true,
	},
	research = {
		assetId = 130060828786274,
		volume = 0.4,
		group = "UI",
		pitchJitter = 0,
		minGap = 0.3,
		looped = false,
	},
	purchase = {
		assetId = 103635677731633,
		volume = 0.5,
		group = "UI",
		pitchJitter = 0,
		minGap = 0.3,
		looped = false,
	},
	click = {
		assetId = 86251483589180,
		volume = 0.3,
		group = "UI",
		pitchJitter = 0.03,
		minGap = 0.04,
		looped = false,
	},
	hover = {
		assetId = 130193113100028,
		volume = 0.12,
		group = "UI",
		pitchJitter = 0.03,
		minGap = 0.05,
		looped = false,
	},
	error = {
		assetId = 88262049590710,
		volume = 0.35,
		group = "UI",
		pitchJitter = 0,
		minGap = 0.4,
		looped = false,
	},
	ambient = {
		assetId = 95329956277982,
		volume = 0.25,
		group = "Ambient",
		pitchJitter = 0,
		minGap = 0,
		looped = true,
	},
} :: { [string]: Sound }

-- The sound to play, or nil (unknown, not uploaded, or switched off).
function SoundConfig.get(name: string): Sound?
	local sound = SoundConfig.List[name]
	if not SoundConfig.Enabled or sound == nil or sound.assetId <= 0 then
		return nil
	end
	return sound
end

-- Checks the table (used by the tests). Returns { problem, ... }.
function SoundConfig.validate(): { string }
	local problems: { string } = {}
	for name, sound in SoundConfig.List do
		if type(sound.assetId) ~= "number" or sound.assetId < 0 or sound.assetId % 1 ~= 0 then
			table.insert(problems, name .. ": assetId must be a whole number >= 0")
		end
		if type(sound.volume) ~= "number" or sound.volume <= 0 or sound.volume > 1 then
			table.insert(problems, name .. ": volume must be in (0, 1]")
		end
		if SoundConfig.Groups[sound.group] == nil then
			table.insert(problems, name .. ": unknown group " .. tostring(sound.group))
		end
		if sound.pitchJitter < 0 or sound.pitchJitter > 0.25 then
			table.insert(problems, name .. ": pitchJitter must be in [0, 0.25]")
		end
		if sound.minGap < 0 then
			table.insert(problems, name .. ": minGap must be >= 0")
		end
	end
	return problems
end

return SoundConfig
