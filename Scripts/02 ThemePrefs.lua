-- GALAXY Theme Preferences
-- Stores machine-wide preferences that persist across sessions via Save/ThemePrefs.ini
-- Per-player settings (speed, gauge, turn, scroll) are in 03 ProfilePrefs.lua instead.
-- InitAll registers both prefs AND OptionRow handlers (ThemePrefRow).

local Prefs = {
	-- Scoring / timing (machine-wide)
	FlareGaugeLevel = {
		Default = 0,
		Choices = { "Off","1","2","3","4","5","6","7","8","9","10" },
		Values  = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 },
		Params  = { ExportOnChange = true },
	},
	ScoringMode = {
		Default = "DDR",
		Choices = { "DDR", "OutFox" },
		Values  = { "DDR", "OutFox" },
		Params  = { ExportOnChange = true },
	},
	TimingMode = {
		Default = "DDR Modern",
		Choices = { "StepMania", "ITG", "DDR Extreme", "DDR Modern" },
		Values  = { "StepMania", "ITG", "DDR Extreme", "DDR Modern" },
		Params  = { ExportOnChange = true },
	},
	-- Sorting — two-letter codes set first/last priority; the unlisted
	-- category fills the middle.  L = Latin, J = Japanese, N = Numbers.
	-- Display strings show the full order for clarity.
	JapaneseSorting = {
		Default = "jn",
		Choices = { "J,N,L", "L,N,J", "J,L,N", "N,L,J", "L,J,N", "N,J,L", "Romaji" },
		Values  = { "jl",   "lj",    "jn",    "nj",    "ln",    "nl",    "romaji" },
		Params  = { ExportOnChange = true },
	},
	-- Music select jacket art quality
	JacketQuality = {
		Default = "incremental",
		Choices = { "Low", "Incremental", "Unlimited" },
		Values  = { "low", "incremental", "full" },
		Params  = { ExportOnChange = true },
	},
}

ThemePrefs.InitAll(Prefs)

-- Ensure the file exists on disk so defaults persist across sessions.
-- ForceSave writes the current (possibly default) values even if nothing changed.
if not FILEMAN:DoesFileExist("Save/ThemePrefs.ini") then
	ThemePrefs.ForceSave()
end

-- Convenience wrappers
function GetGalaxyPref(key)
	return ThemePrefs.Get(key)
end

function SetGalaxyPref(key, value)
	ThemePrefs.Set(key, value)
end

function SaveGalaxyPrefs()
	ThemePrefs.Save()
end
