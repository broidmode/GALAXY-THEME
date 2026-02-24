-- GALAXY Theme Preferences
-- Stores theme-level preferences that persist across sessions

local defaultPrefs = {
	FlareGaugeLevel = 0,      -- 0 = off, 1-10 = flare skill levels
	ScoringMode     = "DDR",  -- "DDR" or "OutFox"
	TimingMode      = "DDR",  -- "DDR" or "OutFox"
}

-- Initialize theme preferences on load
function InitGalaxyPrefs()
	for k, v in pairs(defaultPrefs) do
		if GetThemePref(k) == nil then
			SetThemePref(k, v)
		end
	end
end

function GetGalaxyPref(key)
	local val = GetThemePref(key)
	if val == nil then
		return defaultPrefs[key]
	end
	return val
end

function SetGalaxyPref(key, value)
	SetThemePref(key, value)
end
