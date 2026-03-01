-- GALAXY Theme Preferences
-- Stores machine-wide preferences that persist across sessions via Save/ThemePrefs.ini
-- Per-player settings (speed, gauge, turn, scroll) are in 03 ProfilePrefs.lua instead.

local Prefs = {
	-- Scoring / timing (machine-wide)
	FlareGaugeLevel = { Default = 0 },         -- 0 = off, 1-10 = flare skill levels
	ScoringMode     = { Default = "DDR" },      -- "DDR" or "OutFox"
	TimingMode      = { Default = "DDR" },      -- "DDR" or "OutFox"
}

ThemePrefs.Init(Prefs, true)

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
