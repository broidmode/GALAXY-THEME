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
	},
	ScoringMode = {
		Default = "DDR",
		Choices = { "DDR", "OutFox" },
		Values  = { "DDR", "OutFox" },
	},
	TimingMode = {
		Default = "DDR",
		Choices = { "DDR", "OutFox" },
		Values  = { "DDR", "OutFox" },
	},
	-- Sorting
	JapaneseSorting = {
		Default = "first",
		Choices = { "First", "Last", "Alphabetical" },
		Values  = { "first", "last", "alphabetical" },
	},
}

ThemePrefs.InitAll(Prefs)

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
