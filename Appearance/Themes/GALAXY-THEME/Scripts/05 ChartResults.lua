-- 05 ChartResults.lua — Per-chart, per-profile custom result storage
-- Stores combo lamp (FC type) and flare result (best gauge cleared + points)
-- per difficulty for each song, per player profile.
--
-- Data is persisted as a Lua table in <ProfileDir>/GALAXY/ChartResults.lua
-- Loaded once when the profile is loaded; saved when gameplay results finalize.
--
-- Combo lamp values: "MFC","PFC","GFC","FC","LIFE4","Clear",nil
-- Flare gauge values: "Normal","Flare1"..."Flare9","FlareEX","FloatingFlare",nil
--
-- The engine's SaveProfileCustom/LoadProfileCustom hooks in 03 ProfilePrefs.lua
-- call into this module automatically.

-- ===== GLOBALS =====
-- ChartResultsData[pn]["Songs/Pack/Dir/Difficulty_Hard"] = { lamp, flareGauge, flarePoints }
ChartResultsData = ChartResultsData or {}

-- ===== FLARE POINT TABLE =====
-- Index 1 = Clear (Normal gauge), 2 = Flare I, ... 11 = Flare EX
-- Row index = chart meter level (clamped to 1..19)
local FlarePointTable = {
	[1]  = { 145, 155, 170, 185, 200, 230, 260, 290, 320, 350, 400 },
	[2]  = { 155, 165, 180, 195, 210, 240, 270, 300, 330, 360, 410 },
	[3]  = { 170, 180, 195, 210, 225, 255, 285, 315, 345, 375, 425 },
	[4]  = { 185, 195, 210, 225, 240, 270, 300, 330, 360, 390, 440 },
	[5]  = { 200, 210, 225, 240, 255, 285, 315, 345, 375, 405, 455 },
	[6]  = { 230, 240, 255, 270, 285, 315, 345, 375, 405, 435, 485 },
	[7]  = { 260, 270, 285, 300, 315, 345, 375, 405, 435, 465, 515 },
	[8]  = { 290, 300, 315, 330, 345, 375, 405, 435, 465, 495, 545 },
	[9]  = { 320, 330, 345, 360, 375, 405, 435, 465, 495, 525, 575 },
	[10] = { 350, 360, 375, 390, 405, 435, 465, 495, 525, 555, 605 },
	[11] = { 400, 410, 425, 440, 455, 485, 515, 545, 575, 605, 655 },
	[12] = { 440, 450, 465, 480, 495, 525, 555, 585, 615, 645, 695 },
	[13] = { 480, 490, 505, 520, 535, 565, 595, 625, 655, 685, 735 },
	[14] = { 520, 530, 545, 560, 575, 605, 635, 665, 695, 725, 775 },
	[15] = { 560, 570, 585, 600, 615, 645, 675, 705, 735, 765, 815 },
	[16] = { 614, 624, 639, 654, 669, 699, 729, 759, 789, 819, 869 },
	[17] = { 668, 678, 693, 708, 723, 753, 783, 813, 843, 873, 923 },
	[18] = { 722, 732, 747, 762, 777, 807, 837, 867, 897, 927, 977 },
	[19] = { 764, 774, 789, 804, 819, 849, 879, 909, 939, 969, 1064 },
}

-- Map gauge string to flare point column index (1 = Clear/Normal, 2..11 = Flare I..EX)
local GaugeToFlareCol = {
	Normal        = 1,
	Flare1        = 2,
	Flare2        = 3,
	Flare3        = 4,
	Flare4        = 5,
	Flare5        = 6,
	Flare6        = 7,
	Flare7        = 8,
	Flare8        = 9,
	Flare9        = 10,
	FlareEX       = 11,
	FloatingFlare = nil,  -- resolved from floatingCurrent at end of play
}

-- Ordered gauge strength (higher index = harder gauge)
local GaugeStrength = {
	Normal   = 1,
	Flare1   = 2, Flare2  = 3, Flare3  = 4, Flare4  = 5,
	Flare5   = 6, Flare6  = 7, Flare7  = 8, Flare8  = 9,
	Flare9   = 10, FlareEX = 11,
}

-- Lamp strength ordering (higher = better)
local LampStrength = {
	Clear = 1,
	LIFE4 = 2,
	FC    = 3,
	GFC   = 4,
	PFC   = 5,
	MFC   = 6,
}

-- ===== CHART KEY =====
-- Unique per song + difficulty. Uses song directory + difficulty enum string.
function GetChartKey(song, steps)
	if not song or not steps then return nil end
	local dir = song:GetSongDir()   -- e.g. "Songs/Pack/SongTitle/"
	local diff = ToEnumShortString(steps:GetDifficulty())  -- e.g. "Hard"
	return dir .. diff
end

-- ===== FLARE POINT LOOKUP =====
function LookupFlarePoints(chartLevel, gaugeStr)
	local col = GaugeToFlareCol[gaugeStr]
	if not col then return 0 end
	local level = math.max(1, math.min(19, chartLevel))
	local row = FlarePointTable[level]
	return row and row[col] or 0
end

-- Resolve a Floating Flare result to a concrete gauge string
-- floatingCurrent is the lowest flare index the player dropped to (1-10)
local function ResolveFloatingFlare(floatingCurrent)
	if not floatingCurrent or floatingCurrent < 1 then return "Normal" end
	local names = { "Flare1","Flare2","Flare3","Flare4","Flare5",
	                "Flare6","Flare7","Flare8","Flare9","FlareEX" }
	return names[math.min(floatingCurrent, 10)]
end

-- ===== COMBO LAMP DETECTION =====
-- Determine the combo lamp from a HighScore object or from live judgment counts
function DetectComboLamp(counts, failed, gaugeUsed)
	if failed then return nil end

	local misses = (counts.Miss or 0) + (counts.LetGo or 0) + (counts.HitMine or 0)
	local goods  = counts.W4 or 0
	local greats = counts.W3 or 0
	local perfs  = counts.W2 or 0

	if misses == 0 and goods == 0 and greats == 0 and perfs == 0 then
		return "MFC"
	elseif misses == 0 and goods == 0 and greats == 0 then
		return "PFC"
	elseif misses == 0 and goods == 0 then
		return "GFC"
	elseif misses == 0 then
		return "FC"
	end

	-- Cleared but not full combo
	if gaugeUsed == "LIFE4" then
		return "LIFE4"
	end
	return "Clear"
end

-- ===== DATA ACCESS =====

-- Get stored result for a chart, or nil
function GetChartResult(pn, chartKey)
	if not ChartResultsData[pn] then return nil end
	return ChartResultsData[pn][chartKey]
end

-- Record a result after gameplay. Only upgrades — never overwrites with worse data.
-- gaugeStr: the effective gauge (resolved floating flare already)
-- lamp: combo lamp string
-- flarePoints: numeric points
function RecordChartResult(pn, chartKey, lamp, gaugeStr, flarePoints)
	if not chartKey then return end
	if not ChartResultsData[pn] then ChartResultsData[pn] = {} end

	local existing = ChartResultsData[pn][chartKey]
	if not existing then
		ChartResultsData[pn][chartKey] = {
			lamp        = lamp,
			flareGauge  = gaugeStr,
			flarePoints = flarePoints or 0,
		}
		return
	end

	-- Upgrade lamp if better
	local newLampStr = (LampStrength[lamp] or 0) > (LampStrength[existing.lamp] or 0)
	if newLampStr then
		existing.lamp = lamp
	end

	-- Upgrade flare if better points
	if (flarePoints or 0) > (existing.flarePoints or 0) then
		existing.flareGauge  = gaugeStr
		existing.flarePoints = flarePoints
	end
end

-- After gameplay finishes, call this to compute and record the result.
-- pn: PlayerNumber, song: Song, steps: Steps
-- The function reads from GaugeState and ScoreState (already computed by gameplay).
function FinalizeChartResult(pn, song, steps)
	if not song or not steps then return end
	local chartKey = GetChartKey(song, steps)
	if not chartKey then return end

	-- Get gauge info
	local gs = GaugeState[pn]
	if not gs then return end

	local failed = gs.failed
	local gaugeStr = gs.gaugeType
	if gaugeStr == "Flare" then
		-- Convert to specific flare level string
		local names = {"Flare1","Flare2","Flare3","Flare4","Flare5",
		               "Flare6","Flare7","Flare8","Flare9","FlareEX"}
		gaugeStr = names[gs.flareIndex] or "Normal"
	elseif gaugeStr == "FloatingFlare" then
		gaugeStr = ResolveFloatingFlare(gs.floatingCurrent)
	elseif gaugeStr == "LIFE4" or gaugeStr == "Risky" then
		gaugeStr = gaugeStr  -- keep as-is; LIFE4 is a combo lamp, not flare
	end

	-- Build judgment counts from the live ScoreState
	local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
	local counts = {
		W1   = pss:GetTapNoteScores('TapNoteScore_W1'),
		W2   = pss:GetTapNoteScores('TapNoteScore_W2'),
		W3   = pss:GetTapNoteScores('TapNoteScore_W3'),
		W4   = pss:GetTapNoteScores('TapNoteScore_W4'),
		Miss = pss:GetTapNoteScores('TapNoteScore_Miss'),
		Held = pss:GetHoldNoteScores('HoldNoteScore_Held'),
		LetGo = pss:GetHoldNoteScores('HoldNoteScore_LetGo'),
		HitMine = pss:GetTapNoteScores('TapNoteScore_HitMine'),
	}

	local gaugeForLamp = (gs.gaugeType == "LIFE4" and not failed) and "LIFE4" or nil
	local lamp = DetectComboLamp(counts, failed, gaugeForLamp or gaugeStr)

	-- Flare points: only if cleared (not failed), and gauge is a flare or normal type
	local flarePoints = 0
	if not failed then
		local effectiveGauge = gaugeStr
		if effectiveGauge == "LIFE4" or effectiveGauge == "Risky" then
			effectiveGauge = "Normal"  -- battery gauges earn Normal-level flare points
		end
		flarePoints = LookupFlarePoints(steps:GetMeter(), effectiveGauge)
	else
		-- Failed: don't credit any flare gauge — downgrade to Normal
		gaugeStr = "Normal"
	end

	RecordChartResult(pn, chartKey, lamp, gaugeStr, flarePoints)
	Trace("[GALAXY] FinalizeChartResult: " .. tostring(pn) .. " key=" .. chartKey
		.. " lamp=" .. tostring(lamp) .. " gauge=" .. tostring(gaugeStr)
		.. " fp=" .. tostring(flarePoints))
end

-- ===== DISPLAY HELPERS =====

-- Get a short display string for the best flare gauge cleared
function GetFlareGradeDisplay(gaugeStr)
	if not gaugeStr then return "---" end
	local map = {
		Normal = "---",
		Flare1 = "I", Flare2 = "II", Flare3 = "III", Flare4 = "IV",
		Flare5 = "V", Flare6 = "VI", Flare7 = "VII", Flare8 = "VIII",
		Flare9 = "IX", FlareEX = "EX",
		LIFE4 = "---", Risky = "---",
	}
	return map[gaugeStr] or "---"
end

-- ===== PERSISTENCE =====
-- Serialize ChartResultsData[pn] to a Lua file in the profile directory.

local RESULTS_FILE = "GALAXY/ChartResults.lua"

local function SerializeTable(tbl)
	local lines = { "return {" }
	-- Sort keys for deterministic output
	local keys = {}
	for k in pairs(tbl) do keys[#keys+1] = k end
	table.sort(keys)
	for _, k in ipairs(keys) do
		local v = tbl[k]
		local lampStr   = v.lamp and ('"'..v.lamp..'"') or "nil"
		local gaugeStr  = v.flareGauge and ('"'..v.flareGauge..'"') or "nil"
		local fpStr     = tostring(v.flarePoints or 0)
		lines[#lines+1] = string.format('  [%q] = { lamp=%s, flareGauge=%s, flarePoints=%s },',
			k, lampStr, gaugeStr, fpStr)
	end
	lines[#lines+1] = "}"
	return table.concat(lines, "\n")
end

function SaveChartResults(pn, dir)
	if not ChartResultsData[pn] then return end
	local data = ChartResultsData[pn]
	if not next(data) then return end  -- nothing to save

	local content = SerializeTable(data)
	local path = dir .. RESULTS_FILE

	local f = RageFileUtil.CreateRageFile()
	if f:Open(path, 2) then
		f:Write(content)
		f:Close()
		Trace("[GALAXY] Saved ChartResults for " .. tostring(pn) .. " to " .. path)
	else
		Warn("[GALAXY] Failed to save ChartResults to " .. path)
	end
	f:destroy()
end

function LoadChartResults(pn, dir)
	ChartResultsData[pn] = {}
	local path = dir .. RESULTS_FILE

	-- Read via RageFile (works with SM virtual filesystem paths)
	local f = RageFileUtil.CreateRageFile()
	if not f:Open(path, 1) then  -- 1 = read mode
		f:destroy()
		Trace("[GALAXY] No ChartResults file for " .. tostring(pn) .. " (new profile)")
		return
	end
	local content = f:Read()
	f:Close()
	f:destroy()

	if not content or content == "" then
		Trace("[GALAXY] Empty ChartResults file for " .. tostring(pn))
		return
	end

	local fn, err = loadstring(content, path)
	if fn then
		local ok, result = pcall(fn)
		if ok and type(result) == "table" then
			ChartResultsData[pn] = result
			local count = 0
			for _ in pairs(result) do count = count + 1 end
			Trace("[GALAXY] Loaded ChartResults for " .. tostring(pn) .. " (" .. count .. " entries)")
		else
			Warn("[GALAXY] Error parsing ChartResults: " .. tostring(result))
		end
	else
		Warn("[GALAXY] Error loading ChartResults: " .. tostring(err))
	end
end
