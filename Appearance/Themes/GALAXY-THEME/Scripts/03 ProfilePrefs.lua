-- GALAXY Per-Profile Preferences
-- Saves & loads player options (speed, gauge, turn, scroll) per profile.
-- The engine calls LoadProfileCustom/SaveProfileCustom automatically
-- via the [Profile] CustomLoadFunction/CustomSaveFunction metrics.

local GALAXY_DIR = "GALAXY/"
local SETTINGS_FILE = "Settings.ini"
local SECTION = "GALAXY"

-- Default values for new profiles / guests
local Defaults = {
	SpeedMode  = "Real",
	SpeedValue = 200,
	Turn       = 1,
	Scroll     = 1,
	Gauge      = "Normal",
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

	Trace("[GALAXY] Loaded profile prefs for " .. tostring(pn) .. " from " .. path)
end

-- Write GalaxyOptions[pn] into Settings.ini in a profile directory
local function SaveGalaxySettings(pn, dir)
	EnsurePlayerOptions(pn)
	if not IniFile then return end

	local opts = GalaxyOptions[pn]
	local tbl = {
		[SECTION] = {
			SpeedMode  = opts.SpeedMode  or Defaults.SpeedMode,
			SpeedValue = opts.SpeedValue or Defaults.SpeedValue,
			Turn       = opts.Turn       or Defaults.Turn,
			Scroll     = opts.Scroll     or Defaults.Scroll,
			Gauge      = opts.Gauge      or Defaults.Gauge,
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
	end
end

-- Called by the engine when saving a profile to disk.
-- Args: profile (Profile object), dir (string path ending in /)
function SaveProfileCustom(profile, dir)
	local pn = ProfileToPlayerNumber(profile)
	if pn then
		SaveGalaxySettings(pn, dir)
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
