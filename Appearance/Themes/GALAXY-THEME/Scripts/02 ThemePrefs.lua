-- GALAXY Theme Preferences
-- Stores theme-level preferences that persist across sessions via Save/ThemePrefs.ini

local Prefs = {
	-- Scoring / timing
	FlareGaugeLevel = { Default = 0 },         -- 0 = off, 1-10 = flare skill levels
	ScoringMode     = { Default = "DDR" },      -- "DDR" or "OutFox"
	TimingMode      = { Default = "DDR" },      -- "DDR" or "OutFox"
	-- Side menu options (per-machine, not per-player)
	SpeedMode       = { Default = "Real" },     -- XMod / CMod / MMod / Real
	SpeedValue      = { Default = 500 },        -- multiplier (XMod) or BPM target
	Turn            = { Default = 1 },          -- index into TurnChoices
	Scroll          = { Default = 1 },          -- index into ScrollChoices
	Gauge           = { Default = "Normal" },   -- gauge type string
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
