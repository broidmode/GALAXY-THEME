-- 00 Timing.lua — Timing window presets for GALAXY
-- Applies engine-level timing via PREFSMAN:SetPreference(), following the
-- same approach as Simply Love's SetGameModePreferences().
-- The active preset is stored in ThemePrefs as "TimingMode".

-- All PREFSMAN keys managed by the timing system.
local TimingPrefKeys = {
	"TimingWindowSecondsW1",
	"TimingWindowSecondsW2",
	"TimingWindowSecondsW3",
	"TimingWindowSecondsW4",
	"TimingWindowSecondsW5",
	"TimingWindowSecondsHold",
	"TimingWindowSecondsMine",
	"TimingWindowSecondsRoll",
	"TimingWindowAdd",
	"RegenComboAfterMiss",
	"MaxRegenComboAfterMiss",
}

-- Preset definitions. Maps PREFSMAN key names to values.
-- "StepMania" resets to engine defaults instead of applying a table.
TimingPresets = {
	["ITG"] = {
		TimingWindowSecondsW1   = 0.0215,
		TimingWindowSecondsW2   = 0.0430,
		TimingWindowSecondsW3   = 0.1020,
		TimingWindowSecondsW4   = 0.1350,
		TimingWindowSecondsW5   = 0.1800,
		TimingWindowSecondsHold = 0.3200,
		TimingWindowSecondsMine = 0.0700,
		TimingWindowSecondsRoll = 0.3500,
		TimingWindowAdd         = 0.0015,
		RegenComboAfterMiss     = 5,
		MaxRegenComboAfterMiss  = 10,
	},
	["DDR Extreme"] = {
		TimingWindowSecondsW1   = 0.0133,
		TimingWindowSecondsW2   = 0.0266,
		TimingWindowSecondsW3   = 0.0800,
		TimingWindowSecondsW4   = 0.1200,
		TimingWindowSecondsW5   = 0.1666,
		TimingWindowSecondsHold = 0.2500,
		TimingWindowSecondsMine = 0.0900,
		TimingWindowSecondsRoll = 0.5000,
		TimingWindowAdd         = 0,
		RegenComboAfterMiss     = 0,
		MaxRegenComboAfterMiss  = 0,
	},
	["DDR Modern"] = {
		TimingWindowSecondsW1   = 0.01667,
		TimingWindowSecondsW2   = 0.03333,
		TimingWindowSecondsW3   = 0.09167,
		TimingWindowSecondsW4   = 0.14167,
		TimingWindowSecondsW5   = 0.14167, -- matches W4; Way Off effectively disabled
		TimingWindowSecondsHold = 0.2500,
		TimingWindowSecondsMine = 0.0900,
		TimingWindowSecondsRoll = 0.5000,
		TimingWindowAdd         = 0,
		RegenComboAfterMiss     = 0,
		MaxRegenComboAfterMiss  = 0,
	},
}

-- Apply the named timing preset to the engine.
-- "StepMania" (or nil) resets all keys to SM5 stock defaults.
function ApplyTimingPreset(name)
	if not name or name == "StepMania" then
		ResetTimingToDefaults()
		return
	end
	local preset = TimingPresets[name]
	if not preset then return end
	for key, val in pairs(preset) do
		PREFSMAN:SetPreference(key, val)
	end
end

-- Reset all timing-related PREFSMAN keys to SM5 stock values.
function ResetTimingToDefaults()
	for _, key in ipairs(TimingPrefKeys) do
		PREFSMAN:SetPreferenceToDefault(key)
	end
end

-- Apply per-player timing options at gameplay start.
-- DDR Modern disables the Way Off (W5) window per player.
function ApplyPerPlayerTimingOptions()
	local mode = GetGalaxyPref and GetGalaxyPref("TimingMode") or "DDR Modern"
	for _, pn in ipairs(GAMESTATE:GetHumanPlayers()) do
		local po = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred")
		if mode == "DDR Modern" then
			po:DisableTimingWindow("TimingWindow_W5")
		end
	end
end
