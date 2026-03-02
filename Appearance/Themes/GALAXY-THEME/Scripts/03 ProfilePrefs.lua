-- GALAXY Per-Profile Preferences
-- Saves & loads player options (speed, gauge, turn, scroll) per profile.
-- The engine calls LoadProfileCustom/SaveProfileCustom automatically
-- via the [Profile] CustomLoadFunction/CustomSaveFunction metrics.

local GALAXY_DIR = "GALAXY/"
local SETTINGS_FILE = "Settings.ini"
local SECTION = "GALAXY"

-- Default values for new profiles / guests
local Defaults = {
	SpeedMode      = "Real",
	SpeedValue     = 200,
	Turn           = 1,
	Scroll         = 1,
	Gauge          = "Normal",
	NoteSkin       = "",       -- empty = engine default
	Accel          = 1,        -- index: 1=Normal 2=Boost 3=Brake 4=Wave
	LaneCover      = 1,        -- index: 1=Off 2=Hidden+ 3=Sudden+ 4=HidSud+
	CoverPercent   = 1,        -- index: 1=0% 2=5% … 11=50%
	LaneVis        = 1,        -- index: 1=0% … 11=100% (0 = no darkening)
	Guideline      = 1,        -- index: 1=Center 2=Border 3=Off
	StepZone       = 1,        -- index: 1=On 2=Off
	FastSlow       = 1,        -- index: 1=On 2=Off
	ComboPriority  = 1,        -- index: 1=Low 2=High
	JudgePriority  = 1,        -- index: 1=Low 2=High
	JudgePosition  = 1,        -- index: 1=Near 2=Far
	-- Music select cursor persistence
	MusicSelectGroup   = "",   -- last opened group name
	MusicSelectSongDir = "",   -- last selected song directory
	MusicSelectSort    = "",   -- last sort mode (reserved for future)
}

-- Ensure GalaxyOptions global exists
GalaxyOptions = GalaxyOptions or {}

local function EnsurePlayerOptions(pn)
	if not GalaxyOptions[pn] then
		GalaxyOptions[pn] = {}
	end
	local opts = GalaxyOptions[pn]
	for k, v in pairs(Defaults) do
		if opts[k] == nil then opts[k] = v end
	end
end

-- Read Settings.ini from a profile directory into GalaxyOptions[pn]
local function LoadGalaxySettings(pn, dir)
	EnsurePlayerOptions(pn)
	local path = dir .. GALAXY_DIR .. SETTINGS_FILE
	if not IniFile then return end

	local tbl = IniFile.ReadFile(path)
	if not tbl or not tbl[SECTION] then return end

	local sec = tbl[SECTION]
	local opts = GalaxyOptions[pn]
	if sec.SpeedMode  then opts.SpeedMode  = tostring(sec.SpeedMode) end
	if sec.SpeedValue then opts.SpeedValue = tonumber(sec.SpeedValue) or Defaults.SpeedValue end
	if sec.Turn       then opts.Turn       = tonumber(sec.Turn) or Defaults.Turn end
	if sec.Scroll     then opts.Scroll     = tonumber(sec.Scroll) or Defaults.Scroll end
	if sec.Gauge      then opts.Gauge      = tostring(sec.Gauge) end
	if sec.NoteSkin       then opts.NoteSkin       = tostring(sec.NoteSkin) end
	if sec.Accel          then opts.Accel          = tonumber(sec.Accel)          or Defaults.Accel end
	if sec.LaneCover      then opts.LaneCover      = tonumber(sec.LaneCover)      or Defaults.LaneCover end
	if sec.CoverPercent   then opts.CoverPercent   = tonumber(sec.CoverPercent)   or Defaults.CoverPercent end
	if sec.LaneVis        then opts.LaneVis        = tonumber(sec.LaneVis)        or Defaults.LaneVis end
	if sec.Guideline      then opts.Guideline      = tonumber(sec.Guideline)      or Defaults.Guideline end
	if sec.StepZone       then opts.StepZone       = tonumber(sec.StepZone)       or Defaults.StepZone end
	if sec.FastSlow       then opts.FastSlow       = tonumber(sec.FastSlow)       or Defaults.FastSlow end
	if sec.ComboPriority  then opts.ComboPriority  = tonumber(sec.ComboPriority)  or Defaults.ComboPriority end
	if sec.JudgePriority  then opts.JudgePriority  = tonumber(sec.JudgePriority)  or Defaults.JudgePriority end
	if sec.JudgePosition  then opts.JudgePosition  = tonumber(sec.JudgePosition)  or Defaults.JudgePosition end
	-- Music select cursor
	if sec.MusicSelectGroup   then opts.MusicSelectGroup   = tostring(sec.MusicSelectGroup) end
	if sec.MusicSelectSongDir then opts.MusicSelectSongDir = tostring(sec.MusicSelectSongDir) end
	if sec.MusicSelectSort    then opts.MusicSelectSort    = tostring(sec.MusicSelectSort) end

	Trace("[GALAXY] Loaded profile prefs for " .. tostring(pn) .. " from " .. path)
end

-- Write GalaxyOptions[pn] into Settings.ini in a profile directory
local function SaveGalaxySettings(pn, dir)
	EnsurePlayerOptions(pn)
	if not IniFile then return end

	local opts = GalaxyOptions[pn]
	local tbl = {
		[SECTION] = {
			SpeedMode      = opts.SpeedMode      or Defaults.SpeedMode,
			SpeedValue     = opts.SpeedValue     or Defaults.SpeedValue,
			Turn           = opts.Turn           or Defaults.Turn,
			Scroll         = opts.Scroll         or Defaults.Scroll,
			Gauge          = opts.Gauge          or Defaults.Gauge,
			NoteSkin       = opts.NoteSkin       or Defaults.NoteSkin,
			Accel          = opts.Accel          or Defaults.Accel,
			LaneCover      = opts.LaneCover      or Defaults.LaneCover,
			CoverPercent   = opts.CoverPercent   or Defaults.CoverPercent,
			LaneVis        = opts.LaneVis        or Defaults.LaneVis,
			Guideline      = opts.Guideline      or Defaults.Guideline,
			StepZone       = opts.StepZone       or Defaults.StepZone,
			FastSlow       = opts.FastSlow       or Defaults.FastSlow,
			ComboPriority  = opts.ComboPriority  or Defaults.ComboPriority,
			JudgePriority  = opts.JudgePriority  or Defaults.JudgePriority,
			JudgePosition  = opts.JudgePosition  or Defaults.JudgePosition,
			-- Music select cursor
			MusicSelectGroup   = opts.MusicSelectGroup   or Defaults.MusicSelectGroup,
			MusicSelectSongDir = opts.MusicSelectSongDir or Defaults.MusicSelectSongDir,
			MusicSelectSort    = opts.MusicSelectSort    or Defaults.MusicSelectSort,
		}
	}

	-- Ensure directory exists (RageFile creates files but not intermediate dirs)
	-- IniFile.WriteFile creates the file; the GALAXY/ subdir should exist.
	-- We attempt to create the directory by writing a temp marker.
	local dirPath = dir .. GALAXY_DIR
	local f = RageFileUtil.CreateRageFile()
	if f:Open(dirPath .. "_init", 2) then
		f:Write("")
		f:Close()
	end
	f:destroy()

	local path = dirPath .. SETTINGS_FILE
	IniFile.WriteFile(path, tbl)
	Trace("[GALAXY] Saved profile prefs for " .. tostring(pn) .. " to " .. path)
end

-- Resolve which PlayerNumber a profile belongs to
local function ProfileToPlayerNumber(profile)
	for i = 0, NUM_PLAYERS - 1 do
		local pn = PlayerNumber[i + 1]
		if pn and PROFILEMAN:GetProfile(pn) == profile then
			return pn
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- Engine hooks (overrides _fallback versions)
---------------------------------------------------------------------------

-- Called by the engine after loading a profile from disk.
-- Args: profile (Profile object), dir (string path ending in /), pn (PlayerNumber or nil)
function LoadProfileCustom(profile, dir, pn)
	-- Determine player number if not provided
	if not pn then
		pn = ProfileToPlayerNumber(profile)
	end
	if pn then
		LoadGalaxySettings(pn, dir)
		-- Load per-chart results (combo lamp, flare grade, flare points)
		if LoadChartResults then
			LoadChartResults(pn, dir)
		end
	end
end

-- Called by the engine when saving a profile to disk.
-- Args: profile (Profile object), dir (string path ending in /)
function SaveProfileCustom(profile, dir)
	local pn = ProfileToPlayerNumber(profile)
	if pn then
		SaveGalaxySettings(pn, dir)
		-- Save per-chart results (combo lamp, flare grade, flare points)
		if SaveChartResults then
			SaveChartResults(pn, dir)
		end
	end
end

-- Public API for forcing a save from Lua (e.g., when closing the menu)
function SaveGalaxyPlayerPrefs(pn)
	if not PROFILEMAN:IsPersistentProfile(pn) then
		Trace("[GALAXY] Skipping save for non-persistent profile (guest) " .. tostring(pn))
		return
	end
	local slot = (pn == PLAYER_1) and "ProfileSlot_Player1" or "ProfileSlot_Player2"
	local dir = PROFILEMAN:GetProfileDir(slot)
	if dir and dir ~= "" then
		SaveGalaxySettings(pn, dir)
	end
end

-- Initialize defaults for all players on script load
for i = 1, NUM_PLAYERS do
	local pn = PlayerNumber[i]
	if pn then EnsurePlayerOptions(pn) end
end
