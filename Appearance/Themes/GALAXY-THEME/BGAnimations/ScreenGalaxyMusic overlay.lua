-- ScreenGalaxyMusic overlay — Custom 3-column grid song browser
-- Infinite-scroll illusion: cursor stays near screen center,
-- the list wraps circularly above and below.
--
-- Data model: flat mixed-type array.
--   string  = group header
--   table   = { Song, Steps1, Steps2, ... }
-- Only one group open at a time. Rebuilt on toggle.

-- ===== CONSTANTS =====
local COLS         = 3
local CARD_W       = 240
local CARD_H       = 285
local COL_GAP      = 18
local ROW_GAP      = 18
local HEADER_H     = 66
local POOL_CARDS   = 60    -- generous pool: ~15 visible + ~45 cached off-screen
local POOL_HEADERS = 12

local GRID_X       = SCREEN_CENTER_X
local CENTER_Y     = SCREEN_CENTER_Y  -- cursor item is pinned here

local totalColW    = CARD_W + COL_GAP
local totalRowH    = CARD_H + ROW_GAP

-- How far above/below center we render (pixels)
local RENDER_MARGIN = SCREEN_HEIGHT / 2 + CARD_H + 60

-- Direction debounce: only load new images after 2 consecutive moves same direction
local LastMoveDir  = 0     -- +1 = down/right, -1 = up/left, 0 = none
local SameDirCount = 2     -- start at threshold so initial Refresh() loads cards
local DEBOUNCE_THRESHOLD = 2  -- need this many same-dir moves before loading new cards

-- ===== STATE =====
local FlatList     = {}
local Cursor       = 1
local OpenGroup    = ""
local Accepted     = false

local CardPool     = {}
local HeaderPool   = {}
local GridFrame    = nil   -- reference to GridBrowser ActorFrame

-- Pool assignment tracking: keeps cards stable so songs don't reload images
local CardAssign   = {}    -- CardAssign[poolIdx] = flatIdx currently shown
local CardByFlat   = {}    -- CardByFlat[flatIdx] = poolIdx (reverse lookup)

-- Deferred jacket loading: when a Refresh caps at MAX_LOADS_PER_FRAME,
-- this flag tells the per-frame update to schedule another Refresh pass.
local DeferredLoadPending = false

-- ===== ANIMATION STATE =====
local VisualOffset = 0     -- current pixel offset (ActorFrame y-shift)
local AnimActive   = false
local AnimTime     = 0     -- seconds into current animation
local ANIM_DUR     = 0.15  -- animation duration in seconds
-- Cubic coefficients: f(s) = As³ + Bs² + Cs + D, s ∈ [0,1]
local AnimA, AnimB, AnimC, AnimD = 0, 0, 0, 0

-- ===== SIDE MENU CONSTANTS =====
local MENU_W       = 760
local MENU_X       = SCREEN_WIDTH - MENU_W/2 - 30  -- build-time reference (right side)
local MENU_X_LEFT  = MENU_W/2 + 30                 -- left side for P1
local MENU_ROW_H   = 38
local MENU_PAD     = 12

-- ===== SIDE MENU STATE =====
-- Per-player: each player has their own menu, option rows, and cursor
local MenuOpen     = {}    -- MenuOpen[pn] = true/false
local MenuRow      = {}    -- MenuRow[pn] = current row index
local MenuFrame    = {}    -- MenuFrame[pn] = ActorFrame reference
local PlayerOptionRows = {} -- PlayerOptionRows[pn] = { {name,choices,selected}, ... }

-- Confirm-hold state: track Select/Start held + whether L/R was used
local _confirmHeld = {}    -- _confirmHeld[pn] = true while Select/Start is held in menu
local _confirmDirty = {}   -- _confirmDirty[pn] = true if L/R pressed during hold

-- Fast-step sizes when confirm is held + L/R per row index (nil = normal step)
local FAST_STEP = {
	[2] = 10,  -- Speed: jump 10 choices per press (100 BPM or x0.50)
	[18] = 10, -- Visual Delay: jump 10 choices (50ms) per press
	[19] = 10, -- Audio Sync: jump 10 choices (50ms) per press
	[20] = 10, -- Pitch: jump 10 choices (0.50x) per press
	[22] = 10, -- Constant: jump 10 choices (100ms) per press
}

-- Special fast-jump targets for specific rows (by row index)
-- When confirm-held, L jumps to first target, R jumps to second target
-- These are looked up by value field in the row's choices
local FAST_JUMP = {
	[5] = { left = "Normal", right = "Risky" },  -- Gauge: L=Normal, R=Risky
}

-- ===== DIFFICULTY PICKER STATE =====
local DiffPickOpen = false
local DiffPickIdx  = {}      -- DiffPickIdx[pn] = selected index in DiffSteps[]
local DiffSteps    = {}      -- array of Steps objects for chosen song
local DiffFrame    = {}      -- DiffFrame[pn] = ActorFrame reference (per-player boxes)
local DiffSong     = nil     -- the Song being difficulty-picked

-- DDR-A3 difficulty colors
local DiffColors = {
	Difficulty_Beginner  = color("#1ed6ff"),
	Difficulty_Easy      = color("#ffaa19"),
	Difficulty_Medium    = color("#ff1e3c"),
	Difficulty_Hard      = color("#32eb19"),
	Difficulty_Challenge = color("#eb1eff"),
	Difficulty_Edit      = color("#afafaf"),
}

-- Global options table — read by 04 GaugeState.lua and gameplay decorations
-- Per-player settings are loaded from profile by 03 ProfilePrefs.lua.
-- GalaxyOptions[pn] = { SpeedMode, SpeedValue, Turn, Scroll, Gauge }
-- 03 ProfilePrefs.lua guarantees defaults exist via EnsurePlayerOptions.

-- ===== SONG INFO PANEL STATE =====
local InfoFrame = nil   -- reference set in InitCommand

-- ===== SCORE PANEL STATE =====
local ScorePanelFrame = {}  -- ScorePanelFrame[pn] = ActorFrame reference

-- ===== SONG PREVIEW STATE =====
local PreviewActor = nil
local _currentPreviewPath = nil  -- path of the OGG currently playing/loading
local _previewGen = 0            -- generation counter: invalidates stale DoPreview callbacks

-- ===== CACHED SOUND PATHS =====
local SND_SWITCH = THEME:GetPathS("","_switch down")
local SND_START  = THEME:GetPathS("Common","Start")
local SND_CANCEL = THEME:GetPathS("Common","Cancel")

-- Precached ActorSound references (set in InitCommand).
-- These play through the main audio path, NOT the music thread,
-- so they are never blocked by a long OGG preview load.
local SfxSwitch = nil
local SfxStart  = nil
local SfxCancel = nil

-- Cursor persistence across screen transitions
GalaxyCursorState = GalaxyCursorState or {}

-- ===== SIDE MENU OPTION DEFINITIONS =====

local SpeedModes = {
	{ label = "Real",        value = "Real" },
	{ label = "Speed Rate",  value = "XMod" },
	{ label = "MMod",        value = "MMod" },
	{ label = "CMod",        value = "CMod" },
}

local XModValues = {}
do
	for v = 25, 800, 5 do  -- x0.25 to x8.00 in 0.05 increments
		XModValues[#XModValues+1] = { label = string.format("x%.2f", v/100), value = v/100 }
	end
end

local BPMValues = {}  -- shared for CMod, MMod, Real Speed
do
	for v = 10, 1000, 10 do
		BPMValues[#BPMValues+1] = { label = tostring(v), value = v }
	end
end

local TurnChoices = {
	{ label = "Off",     mod = "" },
	{ label = "Mirror",  mod = "Mirror" },
	{ label = "Left",    mod = "Left" },
	{ label = "Right",   mod = "Right" },
	{ label = "Shuffle", mod = "Shuffle" },
}

local ScrollChoices = {
	{ label = "Normal",  mod = "" },
	{ label = "Reverse", mod = "Reverse" },
}

local GaugeChoices = {
	{ label = "Normal",     value = "Normal" },
	{ label = "Flare I",    value = "Flare1" },
	{ label = "Flare II",   value = "Flare2" },
	{ label = "Flare III",  value = "Flare3" },
	{ label = "Flare IV",   value = "Flare4" },
	{ label = "Flare V",    value = "Flare5" },
	{ label = "Flare VI",   value = "Flare6" },
	{ label = "Flare VII",  value = "Flare7" },
	{ label = "Flare VIII", value = "Flare8" },
	{ label = "Flare IX",   value = "Flare9" },
	{ label = "Flare EX",   value = "FlareEX" },
	{ label = "Floating",   value = "FloatingFlare" },
	{ label = "LIFE4",      value = "LIFE4" },
	{ label = "Risky",      value = "Risky" },
}

local FailChoices = {
	{ label = "Gauge", value = "Gauge" },
	{ label = "Never", value = "Never" },
	{ label = "Miss",  value = "Miss" },
}

local AccelChoices = {
	{ label = "Normal", mod = "" },
	{ label = "Boost",  mod = "Boost" },
	{ label = "Brake",  mod = "Brake" },
	{ label = "Wave",   mod = "Wave" },
}

local LaneCoverChoices = {
	{ label = "Off",      value = "Off" },
	{ label = "Hidden+",  value = "Hidden" },
	{ label = "Sudden+",  value = "Sudden" },
	{ label = "HidSud+",  value = "HidSud" },
}

local CoverPercentChoices = {}
do
	for i = 0, 50, 5 do
		CoverPercentChoices[#CoverPercentChoices+1] = { label = i.."%", value = i }
	end
end

local LaneVisChoices = {}
do
	for i = 0, 100, 10 do
		LaneVisChoices[#LaneVisChoices+1] = { label = i.."%", value = i }
	end
end

local GuidelineChoices = {
	{ label = "Center", value = "Center" },
	{ label = "Border", value = "Border" },
	{ label = "Off",    value = "Off" },
}

local StepZoneChoices = {
	{ label = "On",  value = "On" },
	{ label = "Off", value = "Off" },
}

local FastSlowChoices = {
	{ label = "On",  value = "On" },
	{ label = "Off", value = "Off" },
}

local ComboPriorityChoices = {
	{ label = "Low",  value = "Low" },
	{ label = "High", value = "High" },
}

local JudgePriorityChoices = {
	{ label = "Low",  value = "Low" },
	{ label = "High", value = "High" },
}

local JudgePositionChoices = {
	{ label = "Near", value = "Near" },
	{ label = "Far",  value = "Far" },
}

-- Visual Delay: -500ms to +500ms in 5ms steps
local VisualDelayChoices = {}
do
	for ms = -500, 500, 5 do
		local lbl = (ms >= 0 and "+" or "") .. ms .. "ms"
		VisualDelayChoices[#VisualDelayChoices+1] = { label = lbl, value = ms }
	end
end

-- Audio Sync: -500ms to +500ms in 5ms steps
local AudioSyncChoices = {}
do
	for ms = -500, 500, 5 do
		local lbl = (ms >= 0 and "+" or "") .. ms .. "ms"
		AudioSyncChoices[#AudioSyncChoices+1] = { label = lbl, value = ms }
	end
end

-- Pitch (music rate): 0.50x to 2.00x in 0.05 steps (stored as int*100)
local PitchChoices = {}
do
	for r = 50, 200, 5 do
		local lbl = string.format("x%.2f", r / 100)
		PitchChoices[#PitchChoices+1] = { label = lbl, value = r }
	end
end

-- Arrow Visibility: Normal or Constant
local ArrowVisChoices = {
	{ label = "Normal",   value = 1 },
	{ label = "Constant", value = 2 },
}

-- Constant Mode visibility window: 0ms to 1000ms in 10ms steps
local ConstantMsChoices = {}
do
	for ms = 0, 1000, 10 do
		ConstantMsChoices[#ConstantMsChoices+1] = { label = ms.."ms", value = ms }
	end
end

local NUM_OPTION_ROWS = 22

-- Helper: find index in a choices array where c[field] == val
local function FindChoiceIdx(choices, field, val, fallback)
	for i, c in ipairs(choices) do
		if c[field] == val then return i end
	end
	return fallback
end

-- Helper: find closest numeric value in a choices array
local function FindClosestIdx(choices, val)
	local bestIdx, bestDist = 1, 999999
	for i, c in ipairs(choices) do
		local d = math.abs(c.value - val)
		if d < bestDist then bestIdx, bestDist = i, d end
	end
	return bestIdx
end

-- Build an OptionRows table for a specific player from GalaxyOptions[pn]
local function BuildOptionRowsForPlayer(pn)
	local opts = GalaxyOptions[pn] or {}
	local mode  = opts.SpeedMode  or "Real"
	local bpm   = opts.SpeedValue or 200
	local rate  = (opts.SpeedRate or 100) / 100  -- stored as int*100, convert to float
	local turn  = opts.Turn       or 1
	local scroll= opts.Scroll     or 1
	local gauge = opts.Gauge      or "Normal"

	local modeIdx  = FindChoiceIdx(SpeedModes, "value", mode, 4)
	local speedChoices, speedIdx
	if mode == "XMod" then
		speedChoices = XModValues
		speedIdx = FindClosestIdx(speedChoices, rate)
	else
		speedChoices = BPMValues
		speedIdx = FindClosestIdx(speedChoices, bpm)
	end
	local gaugeIdx = FindChoiceIdx(GaugeChoices, "value", gauge, 1)

	local fail     = opts.Fail           or 1

	-- NoteSkin: build choices dynamically from engine
	local nsNames = NOTESKIN:GetNoteSkinNames()
	local nsChoices = {}
	for _, name in ipairs(nsNames) do
		nsChoices[#nsChoices+1] = { label = name, value = name }
	end
	local currentNS = opts.NoteSkin or ""
	if currentNS == "" then
		local po = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred")
		currentNS = po:NoteSkin() or ""
	end
	local nsIdx = FindChoiceIdx(nsChoices, "value", currentNS, 1)

	local accel    = opts.Accel          or 1
	local cover    = opts.LaneCover      or 1
	local coverPct = opts.CoverPercent   or 1
	local vis      = opts.LaneVis        or 1
	local guide    = opts.Guideline      or 1
	local stepzone = opts.StepZone       or 1
	local fastslow = opts.FastSlow       or 1
	local combop   = opts.ComboPriority  or 1
	local judgep   = opts.JudgePriority  or 1
	local judgepos = opts.JudgePosition  or 1

	local vdelay   = opts.VisualDelay    or 0
	local async    = opts.AudioSync      or 0
	local pitch    = opts.Pitch          or 100

	local vdelayIdx = FindClosestIdx(VisualDelayChoices, vdelay)
	local asyncIdx  = FindClosestIdx(AudioSyncChoices, async)
	local pitchIdx  = FindClosestIdx(PitchChoices, pitch)

	local arrowvis   = opts.ArrowVis   or 1
	local constms    = opts.ConstantMs or 1000
	local constmsIdx = FindClosestIdx(ConstantMsChoices, constms)

	return {
		{ name = "Mode",      choices = SpeedModes,          selected = modeIdx },
		{ name = "Speed",     choices = speedChoices,         selected = speedIdx },
		{ name = "Turn",      choices = TurnChoices,          selected = math.max(1, math.min(turn, #TurnChoices)) },
		{ name = "Scroll",    choices = ScrollChoices,        selected = math.max(1, math.min(scroll, #ScrollChoices)) },
		{ name = "Gauge",     choices = GaugeChoices,         selected = gaugeIdx },
		{ name = "Fail",      choices = FailChoices,          selected = math.max(1, math.min(fail, #FailChoices)) },
		{ name = "NoteSkin",  choices = nsChoices,            selected = nsIdx },
		{ name = "Accel",     choices = AccelChoices,         selected = math.max(1, math.min(accel, #AccelChoices)) },
		{ name = "Cover",     choices = LaneCoverChoices,     selected = math.max(1, math.min(cover, #LaneCoverChoices)) },
		{ name = "Cover %",   choices = CoverPercentChoices,  selected = math.max(1, math.min(coverPct, #CoverPercentChoices)) },
		{ name = "Lane Vis",  choices = LaneVisChoices,       selected = math.max(1, math.min(vis, #LaneVisChoices)) },
		{ name = "Guideline", choices = GuidelineChoices,     selected = math.max(1, math.min(guide, #GuidelineChoices)) },
		{ name = "StepZone",  choices = StepZoneChoices,      selected = math.max(1, math.min(stepzone, #StepZoneChoices)) },
		{ name = "Fast/Slow", choices = FastSlowChoices,      selected = math.max(1, math.min(fastslow, #FastSlowChoices)) },
		{ name = "Combo",     choices = ComboPriorityChoices, selected = math.max(1, math.min(combop, #ComboPriorityChoices)) },
		{ name = "JudgePri",  choices = JudgePriorityChoices, selected = math.max(1, math.min(judgep, #JudgePriorityChoices)) },
		{ name = "JudgePos",  choices = JudgePositionChoices, selected = math.max(1, math.min(judgepos, #JudgePositionChoices)) },
		{ name = "V.Delay",   choices = VisualDelayChoices,   selected = vdelayIdx },
		{ name = "AudioSync", choices = AudioSyncChoices,     selected = asyncIdx },
		{ name = "Pitch",     choices = PitchChoices,         selected = pitchIdx },
		{ name = "Arrow Vis", choices = ArrowVisChoices,      selected = math.max(1, math.min(arrowvis, #ArrowVisChoices)) },
		{ name = "Constant",  choices = ConstantMsChoices,   selected = constmsIdx },
	}
end

-- Save the current speed row value to GalaxyOptions immediately.
-- Called whenever the speed value (row 2) or mode (row 1) changes.
local function SaveSpeedValueNow(pn)
	local rows = PlayerOptionRows[pn]
	if not rows then return end
	local mode = SpeedModes[rows[1].selected].value
	local val  = rows[2].choices[rows[2].selected]
	if not val then return end
	if mode == "XMod" then
		GalaxyOptions[pn].SpeedRate = math.floor(val.value * 100 + 0.5)
	else
		GalaxyOptions[pn].SpeedValue = val.value
	end
end

-- Swap Speed Value row choices based on current Speed Mode (per-player).
-- Saves the current value first, then restores the saved value for the new mode.
local function SyncSpeedValueChoices(pn)
	local rows = PlayerOptionRows[pn]
	if not rows then return end
	local valRow  = rows[2]

	-- Determine OLD mode from the choices still on the row (not from row 1,
	-- which has already been updated to the new mode by the input handler).
	local oldVal = valRow.choices[valRow.selected]
	if oldVal then
		if valRow.choices == XModValues then
			-- Was XMod — save rate
			GalaxyOptions[pn].SpeedRate = math.floor(oldVal.value * 100 + 0.5)
		else
			-- Was BPM mode — save BPM
			GalaxyOptions[pn].SpeedValue = oldVal.value
		end
	end

	-- Now switch to the new mode's choices and restore saved value
	local mode = SpeedModes[rows[1].selected].value
	local opts = GalaxyOptions[pn] or {}
	if mode == "XMod" then
		valRow.choices = XModValues
		-- Restore saved rate (stored as int*100)
		local savedRate = (opts.SpeedRate or 100) / 100
		valRow.selected = FindClosestIdx(valRow.choices, savedRate)
	else
		valRow.choices = BPMValues
		-- Restore saved BPM
		local savedBPM = opts.SpeedValue or 200
		valRow.selected = FindClosestIdx(valRow.choices, savedBPM)
	end
end

-- Calculate the dominant BPM of a song (statistical mode weighted by time).
-- Walks all BPM change points, accumulates wall-clock seconds spent at each
-- BPM value (rounded to 1 decimal to merge near-identical values), and returns
-- the BPM that occupies the most total time.
local function GetDominantBPM(song)
	local td = song:GetTimingData()
	if not td then return nil end

	local segments = td:GetBPMsAndTimes(true)  -- {{beat, bpm}, ...}
	if not segments or #segments == 0 then return nil end

	local lastBeat = song:GetLastBeat()
	if not lastBeat or lastBeat <= 0 then return nil end

	-- Accumulate seconds spent at each BPM (rounded to 0.1 for bucketing)
	local timeAtBPM = {}  -- key = rounded BPM string, value = {seconds, bpm}
	for i, seg in ipairs(segments) do
		local beatStart = seg[1]
		local bpm       = seg[2]
		local beatEnd   = (segments[i+1] and segments[i+1][1]) or lastBeat
		local beatSpan  = beatEnd - beatStart
		if beatSpan > 0 and bpm > 0 then
			local seconds = beatSpan / bpm * 60.0
			local key = string.format("%.1f", bpm)
			if not timeAtBPM[key] then
				timeAtBPM[key] = { seconds = 0, bpm = bpm }
			end
			timeAtBPM[key].seconds = timeAtBPM[key].seconds + seconds
		end
	end

	-- Find the BPM with the most accumulated time
	local bestBPM, bestTime = nil, 0
	for _, entry in pairs(timeAtBPM) do
		if entry.seconds > bestTime then
			bestTime = entry.seconds
			bestBPM  = entry.bpm
		end
	end

	return bestBPM
end

-- Apply a speed mod to a single player based on GalaxyOptions
local function ApplySpeedMod(pn)
	local opts = GalaxyOptions[pn]
	local mode = opts.SpeedMode or "XMod"

	if mode == "XMod" then
		local rate = (opts.SpeedRate or 100) / 100  -- stored as int*100
		GAMESTATE:ApplyPreferredModifiers(pn, string.format("%.2fx", rate))
	elseif mode == "CMod" then
		local val = opts.SpeedValue or 200
		GAMESTATE:ApplyPreferredModifiers(pn, string.format("C%d", val))
	elseif mode == "MMod" then
		local val = opts.SpeedValue or 200
		GAMESTATE:ApplyPreferredModifiers(pn, string.format("M%d", val))
	elseif mode == "Real" then
		local val = opts.SpeedValue or 200
		-- Compute the largest 0.05-increment XMod where dominantBPM * mult < targetBPM
		local song = GAMESTATE:GetCurrentSong()
		if song then
			local songBPM = GetDominantBPM(song)
			-- Fallback to max display BPM if dominant calculation fails
			if not songBPM or songBPM <= 0 then
				local bpms = song:GetDisplayBpms()
				songBPM = bpms[2]
			end
			if songBPM and songBPM > 0 then
				local mult = math.floor(val / songBPM / 0.05) * 0.05
				-- Ensure strict less-than (handle exact division)
				if songBPM * mult >= val then
					mult = mult - 0.05
				end
				mult = math.max(0.25, math.min(mult, 20.0))
				Trace("[GALAXY] Real Speed: dominant BPM="..string.format("%.1f", songBPM)
					.." target="..tostring(val).." mult="..string.format("%.2f", mult))
				GAMESTATE:ApplyPreferredModifiers(pn, string.format("%.2fx", mult))
			else
				GAMESTATE:ApplyPreferredModifiers(pn, "1.00x")
			end
		else
			-- No song selected yet — store target, will re-apply at confirm time
			GAMESTATE:ApplyPreferredModifiers(pn, "1.00x")
		end
	end
end

-- ===== SIDE MENU FUNCTIONS =====

-- Apply the options from a player's OptionRows into GalaxyOptions and game state
local function ApplyMenuOptions(pn)
	local rows = PlayerOptionRows[pn]
	if not rows then return end

	-- Speed: store mode + value in GalaxyOptions, then apply
	local mode = SpeedModes[rows[1].selected].value
	GalaxyOptions[pn].SpeedMode = mode
	SaveSpeedValueNow(pn)
	ApplySpeedMod(pn)

	-- Turn: clear all, then apply
	GAMESTATE:ApplyPreferredModifiers(pn, "no mirror,no left,no right,no shuffle,no supershuffle")
	local turnMod = TurnChoices[rows[3].selected].mod
	if turnMod ~= "" then
		GAMESTATE:ApplyPreferredModifiers(pn, turnMod)
	end

	-- Scroll
	local scrollMod = ScrollChoices[rows[4].selected].mod
	if scrollMod == "Reverse" then
		GAMESTATE:ApplyPreferredModifiers(pn, "Reverse")
	else
		GAMESTATE:ApplyPreferredModifiers(pn, "no reverse")
	end

	-- Gauge: store in global table for GaugeState to read
	GalaxyOptions[pn].Gauge = GaugeChoices[rows[5].selected].value

	-- Fail (row 6): when the song auto-fails
	GalaxyOptions[pn].Fail = rows[6].selected

	-- Turn/Scroll indices stored in GalaxyOptions for profile save
	GalaxyOptions[pn].Turn   = rows[3].selected
	GalaxyOptions[pn].Scroll = rows[4].selected

	-- NoteSkin (row 7)
	local nsValue = rows[7].choices[rows[7].selected].value
	local po = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Preferred")
	po:NoteSkin(nsValue)
	GalaxyOptions[pn].NoteSkin = nsValue

	-- Accel (row 8): clear all acceleration mods, then apply selected
	GAMESTATE:ApplyPreferredModifiers(pn, "no boost,no brake,no wave")
	local accelMod = AccelChoices[rows[8].selected].mod
	if accelMod ~= "" then
		GAMESTATE:ApplyPreferredModifiers(pn, accelMod)
	end
	GalaxyOptions[pn].Accel = rows[8].selected

	-- Lane Cover (row 9): save type (drawing handled in gameplay overlay)
	GAMESTATE:ApplyPreferredModifiers(pn, "no hidden,no sudden")
	GalaxyOptions[pn].LaneCover = rows[9].selected

	-- Cover % (row 10): save percentage index
	GalaxyOptions[pn].CoverPercent = rows[10].selected

	-- Lane Visibility (row 11): theme-level setting for gameplay overlay
	GalaxyOptions[pn].LaneVis = rows[11].selected

	-- Guideline (row 12): theme-level setting
	GalaxyOptions[pn].Guideline = rows[12].selected

	-- Step Zone (row 13): theme-level setting
	GalaxyOptions[pn].StepZone = rows[13].selected

	-- Fast/Slow (row 14): theme-level setting
	GalaxyOptions[pn].FastSlow = rows[14].selected

	-- Combo Priority (row 15): theme-level setting
	GalaxyOptions[pn].ComboPriority = rows[15].selected

	-- Judge Priority (row 16): theme-level setting
	GalaxyOptions[pn].JudgePriority = rows[16].selected

	-- Judge Position (row 17): theme-level setting
	GalaxyOptions[pn].JudgePosition = rows[17].selected

	-- Visual Delay (row 18): ms offset applied to engine before gameplay
	GalaxyOptions[pn].VisualDelay = VisualDelayChoices[rows[18].selected].value

	-- Audio Sync (row 19): ms offset applied to engine before gameplay
	GalaxyOptions[pn].AudioSync = AudioSyncChoices[rows[19].selected].value

	-- Pitch (row 20): music rate applied to engine before gameplay
	GalaxyOptions[pn].Pitch = PitchChoices[rows[20].selected].value

	-- Arrow Visibility (row 21): Normal or Constant
	GalaxyOptions[pn].ArrowVis = ArrowVisChoices[rows[21].selected].value

	-- Constant Value (row 22): millisecond visibility window for Constant mode
	GalaxyOptions[pn].ConstantMs = ConstantMsChoices[rows[22].selected].value

	-- Apply engine-level settings (PREFSMAN / SongOptions)
	PREFSMAN:SetPreference("VisualDelaySeconds", GalaxyOptions[pn].VisualDelay / 1000)
	PREFSMAN:SetPreference("GlobalOffsetSeconds", GalaxyOptions[pn].AudioSync / 1000)
	local so = GAMESTATE:GetSongOptionsObject("ModsLevel_Preferred")
	if so then so:MusicRate(GalaxyOptions[pn].Pitch / 100) end
end

local function RefreshMenu(pn)
	if not MenuFrame[pn] then return end
	MenuFrame[pn]:playcommand("Refresh")
end

local function OpenMenu(pn)
	-- Build fresh OptionRows from this player's saved options
	PlayerOptionRows[pn] = BuildOptionRowsForPlayer(pn)
	MenuOpen[pn] = true
	MenuRow[pn] = 1
	if MenuFrame[pn] then
		MenuFrame[pn]:visible(true)
		RefreshMenu(pn)
	end
end

local function CloseMenu(pn, apply)
	if apply then
		ApplyMenuOptions(pn)
		-- Persist to profile (no-op for guest players)
		SaveGalaxyPlayerPrefs(pn)
	end
	MenuOpen[pn] = false
	PlayerOptionRows[pn] = nil
	_confirmHeld[pn] = false
	_confirmDirty[pn] = false
	if MenuFrame[pn] then MenuFrame[pn]:visible(false) end
end

-- Check if ANY player's menu is open (blocks grid navigation)
local function AnyMenuOpen()
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if MenuOpen[pn] then return true end
	end
	return false
end

-- ===== SONG PREVIEW =====
local function PlaySongPreview()
	if PreviewActor then
		-- Do NOT call StopMusic here.  The old preview should keep playing
		-- during the debounce period so the user doesn't hear silence on
		-- every cursor move.  PlayMusicPart in DoPreview will replace it
		-- atomically (one queue entry instead of two).
		_currentPreviewPath = nil  -- clear guard so DoPreview won't skip
		_previewGen = _previewGen + 1
		PreviewActor:stoptweening()
		PreviewActor:queuecommand("StartPreview")
	end
end

local function StopSongPreview()
	_previewGen = _previewGen + 1  -- invalidate any queued DoPreview
	_currentPreviewPath = nil
	if PreviewActor then PreviewActor:stoptweening() end
	SOUND:StopMusic()
end

local function SaveCursorState()
	GalaxyCursorState.OpenGroup = OpenGroup
	local item = FlatList[Cursor]
	if type(item) == "table" then
		GalaxyCursorState.SongDir = item[1]:GetSongDir()
		GalaxyCursorState.GroupName = nil
	elseif type(item) == "string" then
		GalaxyCursorState.GroupName = item
		GalaxyCursorState.SongDir = nil
	end

	-- Persist to each enabled player's profile so it survives game restarts
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if GalaxyOptions and GalaxyOptions[pn] then
			GalaxyOptions[pn].MusicSelectGroup   = OpenGroup or ""
			GalaxyOptions[pn].MusicSelectSongDir  = GalaxyCursorState.SongDir or ""
			GalaxyOptions[pn].MusicSelectSort     = ""  -- reserved for future sort modes
			SaveGalaxyPlayerPrefs(pn)
		end
	end
end

-- ===== DIFFICULTY PICKER FUNCTIONS =====
local function GetDiffColor(steps)
	local d = steps:GetDifficulty()
	return DiffColors[d] or color("#aaaaaa")
end

local function GetDiffLabel(steps)
	local d = steps:GetDifficulty()
	local short = ToEnumShortString(d)
	return short .. " " .. tostring(steps:GetMeter())
end

local function RefreshDiffPicker()
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if DiffFrame[pn] then DiffFrame[pn]:playcommand("RefreshDiff") end
	end
	-- Also update score panel highlight to follow diff picker cursor
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if ScorePanelFrame[pn] and DiffSteps and DiffPickIdx[pn] then
			local steps = DiffSteps[DiffPickIdx[pn]]
			if steps then
				ScorePanelFrame[pn]:playcommand("HighlightDiffByEnum", {
					Difficulty = steps:GetDifficulty()
				})
			end
		end
	end
end

local function OpenDiffPicker(song, stepsArray)
	DiffSong = song
	DiffSteps = stepsArray
	-- Initialize each enabled player's cursor to their preferred difficulty
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		DiffPickIdx[pn] = 1
		local pref = GAMESTATE:GetPreferredDifficulty(pn)
		if pref then
			for i, st in ipairs(DiffSteps) do
				if st:GetDifficulty() == pref then
					DiffPickIdx[pn] = i
					break
				end
			end
		end
	end
	DiffPickOpen = true
	for _, p in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if DiffFrame[p] then DiffFrame[p]:visible(true) end
	end
	RefreshDiffPicker()
end

local function CloseDiffPicker()
	DiffPickOpen = false
	for _, p in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if DiffFrame[p] then DiffFrame[p]:visible(false) end
	end
end

local function ConfirmDifficulty()
	if Accepted then return end
	GAMESTATE:SetCurrentSong(DiffSong)
	GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		local idx = DiffPickIdx[pn] or 1
		local steps = DiffSteps[idx]
		if not steps then return end
		GAMESTATE:SetCurrentSteps(pn, steps)
		GAMESTATE:SetPreferredDifficulty(pn, steps:GetDifficulty())
		-- Re-apply speed mod now that song is set (important for Real Speed)
		ApplySpeedMod(pn)
	end
	SaveCursorState()
	Accepted = true
	StopSongPreview()
	CloseDiffPicker()
	SfxStart:play()
	SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
end

-- ===== HELPERS =====

-- Wrap an index into [1, #FlatList]
local function Wrap(idx)
	local n = #FlatList
	if n == 0 then return 1 end
	return ((idx - 1) % n) + 1
end

local function IsGroup(idx)
	return type(FlatList[idx]) == "string"
end

local function IsSong(idx)
	return type(FlatList[idx]) == "table"
end

-- ===== SONG INFO PANEL =====
local function RefreshInfoPanel()
	if not InfoFrame then return end
	local song = nil
	if IsSong(Cursor) then
		song = FlatList[Cursor][1]
	end
	InfoFrame:playcommand("SetSong", { Song = song })
	-- Also refresh score panels
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		if ScorePanelFrame[pn] then
			ScorePanelFrame[pn]:playcommand("SetSong", { Song = song })
		end
	end
end

-- ===== DATA LAYER =====

-- Japanese-title sorting -------------------------------------------------
-- A song "has a Japanese title" when its display title STARTS with a
-- CJK / Hiragana / Katakana / fullwidth character. We check the first
-- non-whitespace byte: if it's in a multi-byte UTF-8 sequence starting
-- at U+3000 or above, it's Japanese/CJK.  Songs with stylized Latin
-- characters (e.g. "Blφφdy Cφncertφ", "COSMIC V3LOCITY") start with
-- ASCII letters, so they won't be flagged.
--
-- UTF-8 ranges we care about:
--   U+3000–U+9FFF  → 3-byte sequences starting with 0xE3..0xE9
--   U+F900–U+FAFF  → CJK compat ideographs (0xEF)
--   U+FF00–U+FFEF  → fullwidth forms (0xEF)
-- Any first byte >= 0xE3 (227) covers all of these.
--
-- JapaneseSorting pref values:
--   "first"        → numbers, then Japanese, then English
--   "last"         → numbers, then English, then Japanese
--   "alphabetical" → pure alphabetical on transliterated title (default engine order)

local function HasJapaneseTitle(song)
	local title = song:GetDisplayMainTitle()
	-- skip leading whitespace
	local start = title:match("^%s*()")  or 1
	local b = title:byte(start)
	if not b then return false end
	-- Multi-byte UTF-8: first byte >= 0xE3 covers Hiragana, Katakana, CJK, fullwidth
	return b >= 0xE3
end

local function StartsWithDigit(s)
	local b = s:byte(1)
	return b and b >= 48 and b <= 57   -- '0'..'9'
end

-- Returns a sort-key string that groups songs by category bucket first,
-- then alphabetically within each bucket.
-- Bucket prefixes: "0" = numeric, "1" = first priority, "2" = second priority.
local function SortKey(song)
	local translit = song:GetTranslitMainTitle():lower()
	local jpMode = GetGalaxyPref("JapaneseSorting") or "alphabetical"

	if jpMode == "alphabetical" then
		return translit
	end

	local isJP = HasJapaneseTitle(song)
	local isNum = StartsWithDigit(translit)

	if isNum then
		return "0" .. translit          -- numbers always first
	elseif jpMode == "first" then
		return (isJP and "1" or "2") .. translit
	else -- "last"
		return (isJP and "2" or "1") .. translit
	end
end

local function SortSongs(songs)
	-- Build keyed copy so we only compute sort keys once
	local keyed = {}
	for i, song in ipairs(songs) do
		keyed[i] = { song = song, key = SortKey(song) }
	end
	table.sort(keyed, function(a, b) return a.key < b.key end)
	local out = {}
	for i, v in ipairs(keyed) do out[i] = v.song end
	return out
end
-- -------------------------------------------------------------------------

local function BuildFlatList()
	local list = {}
	local groups = SONGMAN:GetSongGroupNames()
	for _, grp in ipairs(groups) do
		list[#list+1] = grp
		if grp == OpenGroup then
			local songs = SortSongs(SONGMAN:GetSongsInGroup(grp))
			for _, song in ipairs(songs) do
				local stType = GAMESTATE:GetCurrentStyle():GetStepsType()
				local allSteps = song:GetStepsByStepsType(stType)
				if #allSteps > 0 then
					local entry = { song }
					for _, st in ipairs(allSteps) do
						entry[#entry+1] = st
					end
					list[#list+1] = entry
				end
			end
		end
	end
	return list
end

-- ===== LAYOUT ENGINE =====
-- Walk forward and backward from cursor, wrapping around the list.
-- Cursor item is at y=0 (mapped to CENTER_Y on screen).
-- Returns array of { flatIdx, y, type, col } entries.

local function GetSongColLocal(idx)
	-- Count backwards to nearest group header to get ordinal
	local count = 0
	local i = idx
	while i >= 1 and IsSong(i) do
		count = count + 1
		i = i - 1
	end
	return ((count - 1) % COLS) + 1
end

-- Center-to-center distance between two vertically adjacent items.
-- Since actors are center-aligned, we need half-heights of both items plus the gap.
local function CenterAdvance(typeA, typeB)
	local hA = (typeA == "group") and HEADER_H or CARD_H
	local hB = (typeB == "group") and HEADER_H or CARD_H
	return hA / 2 + ROW_GAP + hB / 2
end

-- ===== SCROLL ANIMATION =====
-- Cubic Hermite: f(s) from startOffset to 0, f'(1)=0.
-- If starting mid-scroll, initial derivative carries over for continuity.
-- f(s) = As³ + Bs² + Cs + D,  s ∈ [0, 1]

local function EvalCubic(s)
	return AnimA*s*s*s + AnimB*s*s + AnimC*s + AnimD
end

local function GetCurrentAnimVelNorm()
	if not AnimActive then return 0 end
	local s = math.min(AnimTime / ANIM_DUR, 1)
	return 3*AnimA*s*s + 2*AnimB*s + AnimC
end

local function StartScrollAnim(startOffset, velNorm)
	local P = startOffset
	local V = velNorm
	AnimA = V + 2*P
	AnimB = -2*V - 3*P
	AnimC = V
	AnimD = P
	AnimTime = 0
	AnimActive = true
	VisualOffset = P
end

local function ResetAnim()
	VisualOffset = 0
	AnimActive = false
	if GridFrame then GridFrame:y(0) end
end

local function ComputeVisibleItems(renderMargin)
	renderMargin = renderMargin or RENDER_MARGIN
	local n = #FlatList
	if n == 0 then return {} end

	local result = {}

	-- === Find the start of cursor's row ===
	-- Groups always start their own row; only songs need row-start search.
	local rowStart = Cursor
	if IsSong(Cursor) then
		while true do
			local prevWi = Wrap(rowStart - 1)
			if not IsSong(prevWi) then break end
			if GetSongColLocal(prevWi) >= GetSongColLocal(Wrap(rowStart)) then break end
			if rowStart - 1 == Cursor - n then break end
			rowStart = rowStart - 1
		end
	end

	-- === Walk FORWARD from row start ===
	local y = 0
	local visited = 0
	local idx = rowStart
	while y < renderMargin and visited < n do
		local wi = Wrap(idx)
		if IsGroup(wi) then
			result[#result+1] = { flatIdx = wi, y = y, type = "group", col = 0 }
			local nextType = IsSong(Wrap(idx + 1)) and "song" or "group"
			y = y + CenterAdvance("group", nextType)
		else
			local col = GetSongColLocal(wi)
			result[#result+1] = { flatIdx = wi, y = y, type = "song", col = col }
			local nextWi = Wrap(idx + 1)
			if col == COLS or not IsSong(nextWi) then
				local nextType = IsSong(nextWi) and "song" or "group"
				y = y + CenterAdvance("song", nextType)
			end
		end
		visited = visited + 1
		idx = idx + 1
	end

	-- === Walk BACKWARD from row start ===
	-- Track what type of item sits just below our walk position
	-- so we can compute correct center-to-center distances.
	local lastBelowType = IsGroup(Wrap(rowStart)) and "group" or "song"
	y = 0
	visited = 0
	idx = rowStart - 1
	local pendingRow = {}

	local function FlushPending()
		if #pendingRow == 0 then return end
		y = y - CenterAdvance("song", lastBelowType)
		for _, p in ipairs(pendingRow) do
			result[#result+1] = { flatIdx = p.fi, y = y, type = "song", col = p.col }
		end
		pendingRow = {}
		lastBelowType = "song"
	end

	while (-y) < renderMargin and visited < n do
		local wi = Wrap(idx)
		if IsGroup(wi) then
			FlushPending()
			y = y - CenterAdvance("group", lastBelowType)
			result[#result+1] = { flatIdx = wi, y = y, type = "group", col = 0 }
			lastBelowType = "group"
		else
			local col = GetSongColLocal(wi)
			pendingRow[#pendingRow+1] = { fi = wi, col = col }
			if col == 1 then
				FlushPending()
			end
		end
		visited = visited + 1
		idx = idx - 1
	end
	FlushPending()

	return result
end

-- ===== RENDER =====
local function Refresh(preItems)
	if #FlatList == 0 then return end

	local items = preItems or ComputeVisibleItems(RENDER_MARGIN + math.abs(VisualOffset))

	-- Collect which flatIdx values we need cards for, and where
	local neededSongs = {}    -- { flatIdx -> {screenY, col, hasFocus} }
	local neededHeaders = {}  -- sequential list for headers (no stable-pool needed)

	for _, item in ipairs(items) do
		if item.type == "song" then
			neededSongs[item.flatIdx] = {
				screenY = CENTER_Y + item.y,
				col = item.col,
				hasFocus = (item.flatIdx == Cursor),
			}
		elseif item.type == "group" then
			neededHeaders[#neededHeaders+1] = {
				screenY = CENTER_Y + item.y,
				flatIdx = item.flatIdx,
			}
		end
	end

	-- Phase 1: Hide off-screen cards but KEEP their pool assignment as cache
	for ci = 1, POOL_CARDS do
		local fi = CardAssign[ci]
		if fi and not neededSongs[fi] then
			CardPool[ci]:visible(false)
			-- Don't clear CardAssign/CardByFlat — the image stays loaded in memory
		end
	end

	-- Phase 2: Update already-assigned cards (just reposition + restyle, no image load)
	for fi, info in pairs(neededSongs) do
		local ci = CardByFlat[fi]
		if ci then
			local a = CardPool[ci]
			a:visible(true)
			local xOff = (info.col - 2) * totalColW
			a:xy(GRID_X + xOff, info.screenY)
			local entry = FlatList[fi]
			a:playcommand("SetCard", {
				Song = entry[1],
				Steps = entry[2],
				HasFocus = info.hasFocus,
			})
		end
	end

	-- Phase 3: Assign cards to newly visible songs that aren't cached
	-- Only load new images if we've moved consistently in one direction
	-- (debounce prevents stutter when user bounces up/down)
	local allowNewLoads = (SameDirCount >= DEBOUNCE_THRESHOLD)
	-- Jacket quality (theme pref) controls loading strategy:
	--   low: LoadFromCached thumbnails — fast, no cap needed
	--   incremental: full-res, 3 per frame (default)
	--   full: full-res, no cap, bypass debounce
	local _jq = GetGalaxyPref("JacketQuality") or "incremental"
	if _jq == "full" then allowNewLoads = true end
	local MAX_LOADS_PER_FRAME = (_jq == "incremental") and 3 or math.huge
	local loadsThisFrame = 0
	local skippedAny = false

	for fi, info in pairs(neededSongs) do
		if not CardByFlat[fi] then
			if not allowNewLoads or loadsThisFrame >= MAX_LOADS_PER_FRAME then
				-- Skip loading — card stays invisible until next frame/debounce
				skippedAny = true
			else
				-- First try a truly free (unassigned) pool slot
				local ci = nil
				for k = 1, POOL_CARDS do
					if not CardAssign[k] then
						ci = k
						break
					end
				end
				-- No free slot — evict an off-screen cached card
				if not ci then
					for k = 1, POOL_CARDS do
						local cachedFi = CardAssign[k]
						if cachedFi and not neededSongs[cachedFi] then
							CardByFlat[cachedFi] = nil
							CardAssign[k] = nil
							ci = k
							break
						end
					end
				end
				if not ci then break end  -- pool exhausted (shouldn't happen)

				CardAssign[ci] = fi
				CardByFlat[fi] = ci
				local a = CardPool[ci]
				a:visible(true)
				local xOff = (info.col - 2) * totalColW
				a:xy(GRID_X + xOff, info.screenY)
				local entry = FlatList[fi]
				a:playcommand("SetCard", {
					Song = entry[1],
					Steps = entry[2],
					HasFocus = info.hasFocus,
				})
				loadsThisFrame = loadsThisFrame + 1
			end
		end
	end

	-- Signal deferred loading if we skipped any cards
	DeferredLoadPending = skippedAny and allowNewLoads

	-- Headers: simple sequential assignment (cheap, no images)
	for i = 1, POOL_HEADERS do HeaderPool[i]:visible(false) end
	for i, hdr in ipairs(neededHeaders) do
		if i > POOL_HEADERS then break end
		local a = HeaderPool[i]
		a:visible(true)
		a:xy(GRID_X, hdr.screenY)
		a:playcommand("SetHeader", {
			Text = FlatList[hdr.flatIdx],
			HasFocus = (hdr.flatIdx == Cursor),
			IsOpen = (FlatList[hdr.flatIdx] == OpenGroup),
		})
	end
end

-- ===== NAVIGATION =====
local function MoveCursor(delta)
	if Accepted or #FlatList == 0 then return end
	local oldCursor = Cursor
	Cursor = Wrap(Cursor + delta)
	if IsSong(Cursor) then
		GAMESTATE:SetCurrentSong(FlatList[Cursor][1])
	else
		StopSongPreview()
	end
	SfxSwitch:play()

	-- Track direction for debounce
	local dir = (delta > 0) and 1 or -1
	if dir == LastMoveDir then
		SameDirCount = SameDirCount + 1
	else
		LastMoveDir = dir
		SameDirCount = 1
	end

	-- Compute layout with extended margin for animation headroom
	local extMargin = RENDER_MARGIN + math.abs(VisualOffset) + 400
	local items = ComputeVisibleItems(extMargin)

	-- Find where old cursor sits in the new layout.
	-- With wrapping, oldCursor may appear multiple times;
	-- pick the occurrence closest to center (smallest |y|).
	local oldY = nil
	for _, item in ipairs(items) do
		if item.flatIdx == oldCursor then
			if oldY == nil or math.abs(item.y) < math.abs(oldY) then
				oldY = item.y
			end
		end
	end

	-- Carry over velocity if already mid-scroll
	local curVelNorm = GetCurrentAnimVelNorm()
	local newOffset = oldY and (VisualOffset - oldY) or 0

	if math.abs(newOffset) > 0.5 then
		StartScrollAnim(newOffset, curVelNorm)
	else
		VisualOffset = 0
		AnimActive = false
	end

	Refresh(items)
	if GridFrame then GridFrame:y(VisualOffset) end
	RefreshInfoPanel()
	if IsSong(Cursor) then
		PlaySongPreview()
	end
end

local function ToggleGroup()
	if not IsGroup(Cursor) then return end
	local grp = FlatList[Cursor]
	if OpenGroup == grp then
		OpenGroup = ""
	else
		OpenGroup = grp
	end
	FlatList = BuildFlatList()
	-- Reset pool assignments since flatIdx mapping changed
	for ci = 1, POOL_CARDS do
		CardPool[ci]:visible(false)
		CardAssign[ci] = nil
	end
	CardByFlat = {}
	-- Reset debounce so the fresh list loads immediately
	LastMoveDir = 0
	SameDirCount = DEBOUNCE_THRESHOLD
	for i = 1, #FlatList do
		if IsGroup(i) and FlatList[i] == grp then
			Cursor = i
			break
		end
	end
	ResetAnim()
	Refresh()
	RefreshInfoPanel()
end

local function ConfirmSong()
	if Accepted or not IsSong(Cursor) then return end
	local entry = FlatList[Cursor]
	local song = entry[1]
	-- Gather all available Steps for this song
	local stepsArray = {}
	for i = 2, #entry do
		stepsArray[#stepsArray+1] = entry[i]
	end
	if #stepsArray == 0 then return end
	if #stepsArray == 1 then
		-- Only one difficulty: skip picker, go straight
		GAMESTATE:SetCurrentSong(song)
		GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			GAMESTATE:SetCurrentSteps(pn, stepsArray[1])
			-- Apply speed mod now that song is set (important for Real Speed)
			ApplySpeedMod(pn)
		end
		SaveCursorState()
		Accepted = true
		StopSongPreview()
		SfxStart:play()
		SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
	else
		-- Multiple difficulties: open picker
		SfxSwitch:play()
		OpenDiffPicker(song, stepsArray)
	end
end

-- Row navigation helpers for songs
local function FindGroupStart(idx)
	local i = idx
	while i > 1 and IsSong(Wrap(i - 1)) do
		i = i - 1
	end
	return i
end

local function FindGroupEnd(idx)
	local i = idx
	local n = #FlatList
	while IsSong(Wrap(i + 1)) do
		i = i + 1
		if i - idx > n then break end  -- safety
	end
	return i
end

local function InputHandler(event)
	local isRelease = (event.type == "InputEventType_Release")
	-- Allow release events through only for Select/Start when tracking a confirm-hold
	if isRelease then
		local pn = event.PlayerNumber
		local btn = event.GameButton
		if pn and _confirmHeld[pn] and (btn == "Select" or btn == "Start") then
			-- fall through so the release logic below can fire
		else
			return false
		end
	end
	if Accepted then return true end

	local btn = event.GameButton
	if not btn then return false end
	if not event.PlayerNumber then return false end
	if not GAMESTATE:IsPlayerEnabled(event.PlayerNumber) then return false end

	local pn = event.PlayerNumber

	-- Select button toggles the side menu for the pressing player
	if btn == "Select" then
		if DiffPickOpen then return true end  -- block Select during diff pick
		if not MenuOpen[pn] then
			OpenMenu(pn)
		elseif isRelease then
			-- Release: close menu only if no L/R was pressed during hold
			if not _confirmDirty[pn] then
				CloseMenu(pn, true)
			end
			_confirmHeld[pn] = false
			_confirmDirty[pn] = false
		else
			-- First press while menu open: start tracking hold
			_confirmHeld[pn] = true
			_confirmDirty[pn] = false
		end
		return true
	end

	-- When difficulty picker is open, route input per-player
	if DiffPickOpen then
		if AnyMenuOpen() then return true end
		if btn == "MenuUp" or btn == "MenuLeft" then
			DiffPickIdx[pn] = (DiffPickIdx[pn] or 1) - 1
			if DiffPickIdx[pn] < 1 then DiffPickIdx[pn] = #DiffSteps end
			SfxSwitch:play()
			RefreshDiffPicker()
		elseif btn == "MenuDown" or btn == "MenuRight" then
			DiffPickIdx[pn] = (DiffPickIdx[pn] or 1) + 1
			if DiffPickIdx[pn] > #DiffSteps then DiffPickIdx[pn] = 1 end
			SfxSwitch:play()
			RefreshDiffPicker()
		elseif btn == "Start" then
			ConfirmDifficulty()
		elseif btn == "Back" then
			CloseDiffPicker()
			SfxCancel:play()
		end
		return true
	end

	-- When this player's menu is open, route their input to their menu
	if MenuOpen[pn] then
		local rows = PlayerOptionRows[pn]
		if btn == "MenuUp" then
			MenuRow[pn] = MenuRow[pn] - 1
			if MenuRow[pn] < 1 then MenuRow[pn] = #rows end
			SfxSwitch:play()
			RefreshMenu(pn)
		elseif btn == "MenuDown" then
			MenuRow[pn] = MenuRow[pn] + 1
			if MenuRow[pn] > #rows then MenuRow[pn] = 1 end
			SfxSwitch:play()
			RefreshMenu(pn)
		elseif btn == "MenuLeft" then
			local rowIdx = MenuRow[pn]
			local row = rows[rowIdx]
			if _confirmHeld[pn] then
				_confirmDirty[pn] = true
				-- Check for a jump target first
				local jump = FAST_JUMP[rowIdx]
				if jump and jump.left then
					local jIdx = FindChoiceIdx(row.choices, "value", jump.left, nil)
					if jIdx then row.selected = jIdx end
				elseif FAST_STEP[rowIdx] then
					local step = FAST_STEP[rowIdx]
					row.selected = math.max(1, row.selected - step)
				else
					-- Default hold behavior: jump to first
					row.selected = 1
				end
			else
				-- Normal step, clamp at minimum (no cycling)
				row.selected = math.max(1, row.selected - 1)
			end
			-- When Speed Mode changes, update Speed Value choices
			if rowIdx == 1 then SyncSpeedValueChoices(pn) end
			-- Immediately persist speed value when row 2 changes
			if rowIdx == 2 then SaveSpeedValueNow(pn) end
			SfxSwitch:play()
			RefreshMenu(pn)
		elseif btn == "MenuRight" then
			local rowIdx = MenuRow[pn]
			local row = rows[rowIdx]
			if _confirmHeld[pn] then
				_confirmDirty[pn] = true
				-- Check for a jump target first
				local jump = FAST_JUMP[rowIdx]
				if jump and jump.right then
					local jIdx = FindChoiceIdx(row.choices, "value", jump.right, nil)
					if jIdx then row.selected = jIdx end
				elseif FAST_STEP[rowIdx] then
					local step = FAST_STEP[rowIdx]
					row.selected = math.min(#row.choices, row.selected + step)
				else
					-- Default hold behavior: jump to last
					row.selected = #row.choices
				end
			else
				-- Normal step, clamp at maximum (no cycling)
				row.selected = math.min(#row.choices, row.selected + 1)
			end
			-- When Speed Mode changes, update Speed Value choices
			if rowIdx == 1 then SyncSpeedValueChoices(pn) end
			-- Immediately persist speed value when row 2 changes
			if rowIdx == 2 then SaveSpeedValueNow(pn) end
			SfxSwitch:play()
			RefreshMenu(pn)
		elseif btn == "Start" then
			if isRelease then
				-- Release: close menu only if no L/R was pressed during hold
				if not _confirmDirty[pn] then
					CloseMenu(pn, true)
				end
				_confirmHeld[pn] = false
				_confirmDirty[pn] = false
			else
				-- First press: start tracking hold
				_confirmHeld[pn] = true
				_confirmDirty[pn] = false
			end
		elseif btn == "Back" then
			CloseMenu(pn, false)
			_confirmHeld[pn] = false
			_confirmDirty[pn] = false
		end
		return true  -- eat all input when this player's menu is open
	end

	-- Block grid navigation while any player has their menu open
	if AnyMenuOpen() then return true end

	if btn == "MenuRight" then
		MoveCursor(1)
		return true
	elseif btn == "MenuLeft" then
		MoveCursor(-1)
		return true
	elseif btn == "MenuDown" then
		if IsSong(Cursor) then
			local target = Cursor + COLS
			-- Check if target is still a song in the same group
			local groupEnd = FindGroupEnd(Cursor)
			if target <= groupEnd and IsSong(target) then
				MoveCursor(COLS)
			else
				-- Jump to next group header (wrapping)
				MoveCursor(groupEnd - Cursor + 1)
			end
		else
			MoveCursor(1)
		end
		return true
	elseif btn == "MenuUp" then
		if IsSong(Cursor) then
			local groupStart = FindGroupStart(Cursor)
			local target = Cursor - COLS
			if target >= groupStart then
				MoveCursor(-COLS)
			else
				-- Go to group header
				MoveCursor(groupStart - Cursor - 1)
			end
		else
			MoveCursor(-1)
		end
		return true
	elseif btn == "Start" then
		if IsGroup(Cursor) then
			ToggleGroup()
		elseif IsSong(Cursor) then
			ConfirmSong()
		end
		return true
	elseif btn == "Back" then
		SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToPrevScreen")
		return true
	end

	return false
end

-- ===== ACTOR FACTORIES =====

local function MakeSongCard(name)
	local _loadedSongDir = nil   -- track which song is loaded on this card
	return Def.ActorFrame{
		Name = name,
		InitCommand = function(self) self:visible(false) end,
		SetCardCommand = function(self, params)
			self:GetChild("Border"):visible(params.HasFocus)
			self:GetChild("BG"):diffuse(params.HasFocus and color("#333333") or color("#1a1a1a"))

			local title = self:GetChild("Title")
			if params.Song then
				title:settext(params.Song:GetDisplayMainTitle()):Regen()
			else
				title:settext(""):Regen()
			end
			title:diffuse(params.HasFocus and Color.White or color("#888888"))

			-- Only reload the jacket if the song actually changed
			local songDir = params.Song and params.Song:GetSongDir() or nil
			if songDir ~= _loadedSongDir then
				_loadedSongDir = songDir
				local jacket = self:GetChild("Jacket")
				if params.Song then
					local path = GetJacketPath(params.Song)
					-- Low quality: use engine thumbnail cache (small, fast)
					-- Incremental / Full: load full-res from disk
					local q = GetGalaxyPref("JacketQuality") or "incremental"
					if q == "low" then
						jacket:LoadFromCached("Jacket", path)
					else
						jacket:Load(path)
					end
				end
				local targetSz = CARD_W - 16
				jacket:scaletoclipped(targetSz, targetSz)
			end
		end,

		Def.Quad{
			Name = "Border",
			InitCommand = function(self)
				self:zoomto(CARD_W + 4, CARD_H + 4):diffuse(Color.White)
			end,
		},
		Def.Quad{
			Name = "BG",
			InitCommand = function(self)
				self:zoomto(CARD_W, CARD_H):diffuse(color("#1a1a1a"))
			end,
		},
		Def.Sprite{
			Name = "Jacket",
			InitCommand = function(self) self:y(-27) end,
		},
		Def.Text{
			Font = RodinPath("db"), Size = FontM("db"), Text = "",
			Name = "Title",
			InitCommand = function(self)
				self:y(CARD_H/2 - 36):zoom(FONT_ZOOM)
				self:maxwidth(FontMaxWidth(CARD_W - 10)):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		},
	}
end

local function MakeGroupHeader(name)
	return Def.ActorFrame{
		Name = name,
		InitCommand = function(self) self:visible(false) end,
		SetHeaderCommand = function(self, params)
			local bg = self:GetChild("BG")
			local txt = self:GetChild("Text")
			local arrow = self:GetChild("Arrow")
			if params.HasFocus then
				bg:diffuse(color("#333366"))
			elseif params.IsOpen then
				bg:diffuse(color("#222244"))
			else
				bg:diffuse(color("#1a1a1a"))
			end
			txt:settext(params.Text or ""):Regen()
			txt:diffuse(params.HasFocus and Color.White or
				(params.IsOpen and color("#aaaacc") or color("#888888")))
			arrow:settext(params.IsOpen and "v " or "> "):Regen()
			arrow:diffuse(txt:GetDiffuse())
		end,

		Def.Quad{
			Name = "BG",
			InitCommand = function(self)
				self:zoomto(COLS * totalColW - COL_GAP, HEADER_H):diffuse(color("#1a1a1a"))
			end,
		},
		Def.Text{
			Font = RodinPath("db"), Size = FontM("db"), Text = "",
			Name = "Text",
			InitCommand = function(self)
				self:zoom(FONT_ZOOM)
				self:maxwidth(FontMaxWidth(COLS * totalColW - 60)):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{
			Font = RodinPath("db"), Size = FontM("db"), Text = "",
			Name = "Arrow",
			InitCommand = function(self)
				self:x((COLS * totalColW) / 2 - 20):zoom(FONT_ZOOM)
				self:SetTextureFiltering(false)
			end,
		},
	}
end

-- ===== SIDE MENU ACTOR =====
local MENU_ROW_NAMES = {
	"Mode", "Speed", "Turn", "Scroll", "Gauge", "Fail",
	"NoteSkin", "Accel", "Cover", "Cover %", "Lane Vis",
	"Guideline", "StepZone", "Fast/Slow", "Combo",
	"JudgePri", "JudgePos", "V.Delay", "AudioSync", "Pitch",
	"Arrow Vis", "Constant",
}
local MENU_NUM_ROWS  = #MENU_ROW_NAMES

local function MakeMenu(pn)
	local numRows = MENU_NUM_ROWS
	local totalH = MENU_PAD + 36 + numRows * MENU_ROW_H + MENU_PAD + 28 + MENU_PAD
	local topY = 40
	local centerY = topY + totalH/2
	-- P1 always left, P2 always right
	local menuX = (pn == PLAYER_1) and MENU_X_LEFT or MENU_X

	local m = Def.ActorFrame{
		Name = "SideMenu_"..ToEnumShortString(pn),
		InitCommand = function(self)
			MenuFrame[pn] = self
			self:visible(false)
		end,
		RefreshCommand = function(self)
			local rows = PlayerOptionRows[pn]
			if not rows then return end
			for i = 1, numRows do
				local row = rows[i]
				local rowBG = self:GetChild("RowBG"..i)
				local label = self:GetChild("Label"..i)
				local value = self:GetChild("Value"..i)
				if rowBG then
					rowBG:diffuse(i == MenuRow[pn] and color("#333366") or color("#00000000"))
				end
				if label then
					label:settext(row and row.name or MENU_ROW_NAMES[i])
					label:diffuse(i == MenuRow[pn] and Color.White or color("#888888"))
				end
				if value then
					local ch = row and row.choices[row.selected]
					value:settext(ch and ch.label or "")
					value:diffuse(i == MenuRow[pn] and Color.White or color("#aaaaaa"))
				end
			end

			-- Update speed BPM preview below the Speed row
			local preview = self:GetChild("SpeedPreview")
			if preview and rows[1] and rows[2] then
				local song = GAMESTATE:GetCurrentSong()
				if not song then
					preview:settext("")
				else
					local mode = SpeedModes[rows[1].selected].value
					local val  = rows[2].choices[rows[2].selected].value
					local bpms = song:GetDisplayBpms()
					local minB = math.floor(bpms[1] + 0.5)
					local maxB = math.floor(bpms[2] + 0.5)
					local domB = GetDominantBPM(song)
					if not domB or domB <= 0 then domB = maxB end
					domB = math.floor(domB + 0.5)

					local eMin, eMode, eMax
					if mode == "XMod" then
						eMin  = math.floor(minB * val + 0.5)
						eMode = math.floor(domB * val + 0.5)
						eMax  = math.floor(maxB * val + 0.5)
					elseif mode == "CMod" then
						eMin = val; eMode = val; eMax = val
					elseif mode == "MMod" then
						-- MMod caps at the target; effective = min(bpm*mult, target)
						-- The engine picks mult so maxBPM*mult = target
						local mult = val / maxB
						eMin  = math.floor(math.min(minB * mult, val) + 0.5)
						eMode = math.floor(math.min(domB * mult, val) + 0.5)
						eMax  = val
					elseif mode == "Real" then
						-- Real Speed: pick XMod so dominant*mult < target
						local mult = math.floor(val / domB / 0.05) * 0.05
						if domB * mult >= val then mult = mult - 0.05 end
						mult = math.max(0.25, mult)
						eMin  = math.floor(minB * mult + 0.5)
						eMode = math.floor(domB * mult + 0.5)
						eMax  = math.floor(maxB * mult + 0.5)
					end

					if eMin == eMax then
						preview:settext(eMin .. " BPM")
					else
						preview:settext(eMin .. " - " .. eMode .. " - " .. eMax)
					end
				end
			end
		end,

		-- Border
		Def.Quad{
			InitCommand = function(self)
				self:xy(menuX, centerY)
					:zoomto(MENU_W + 2, totalH + 2)
					:diffuse(color("#444466"))
			end,
		},
		-- Background
		Def.Quad{
			InitCommand = function(self)
				self:xy(menuX, centerY)
					:zoomto(MENU_W, totalH)
					:diffuse(color("#0a0a18"))
					:diffusealpha(0.95)
			end,
		},
		-- Title
		Def.Text{
			Font = RodinPath("db"), Size = FontM("db"),
			Text = "OPTIONS",
			InitCommand = function(self)
				self:xy(menuX, topY + MENU_PAD + 14)
					:zoom(FONT_ZOOM)
					:diffuse(Color.White)
				self:shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		},
		-- Divider line under title
		Def.Quad{
			InitCommand = function(self)
				self:xy(menuX, topY + MENU_PAD + 32)
					:zoomto(MENU_W - 24, 1)
					:diffuse(color("#444466"))
			end,
		},
	}

	-- Option rows (static layout; values filled by RefreshCommand)
	for i = 1, numRows do
		local rowY = topY + MENU_PAD + 36 + (i - 1) * MENU_ROW_H + MENU_ROW_H/2

		-- Row highlight
		m[#m+1] = Def.Quad{
			Name = "RowBG"..i,
			InitCommand = function(self)
				self:xy(menuX, rowY)
					:zoomto(MENU_W - 8, MENU_ROW_H - 4)
					:diffuse(color("#00000000"))
			end,
		}
		-- Label
		m[#m+1] = Def.Text{
			Font = RodinPath("db"), Size = FontM("db"),
			Name = "Label"..i,
			Text = MENU_ROW_NAMES[i],
			InitCommand = function(self)
				self:xy(menuX - MENU_W/2 + MENU_PAD + 8, rowY)
					:zoom(FONT_ZOOM)
					:diffuse(color("#888888"))
				self:halign(0):maxwidth(FontMaxWidth(MENU_W/2 - MENU_PAD)):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- Value (populated by Refresh)
		m[#m+1] = Def.Text{
			Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "Value"..i,
			InitCommand = function(self)
				self:xy(menuX + MENU_W/2 - MENU_PAD - 8, rowY)
					:zoom(FONT_ZOOM)
					:diffuse(color("#aaaaaa"))
				self:halign(1):maxwidth(FontMaxWidth(MENU_W/2 - MENU_PAD)):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
	end

	-- Speed BPM preview (displayed below the Speed row)
	local speedRowY = topY + MENU_PAD + 36 + (2 - 1) * MENU_ROW_H + MENU_ROW_H/2
	m[#m+1] = Def.Text{
		Font = RodinPath("db"), Size = FontS("db"), Text = "",
		Name = "SpeedPreview",
		InitCommand = function(self)
			self:xy(menuX + MENU_W/2 - MENU_PAD - 8, speedRowY + 13)
				:zoom(FONT_ZOOM)
				:diffuse(color("#66aaff"))
			self:halign(1):shadowlength(0)
			self:SetTextureFiltering(false)
		end,
	}

	-- Arrow indicators
	m[#m+1] = Def.Text{
		Font = RodinPath("db"), Size = FontS("db"),
		Name = "ArrowL",
		Text = "<",
		InitCommand = function(self)
			self:xy(menuX + 40, 0):zoom(FONT_ZOOM):diffuse(color("#666688"))
			self:SetTextureFiltering(false)
		end,
		RefreshCommand = function(self)
			local mr = MenuRow[pn] or 1
			local rowY = topY + MENU_PAD + 36 + (mr - 1) * MENU_ROW_H + MENU_ROW_H/2
			self:y(rowY)
		end,
	}
	m[#m+1] = Def.Text{
		Font = RodinPath("db"), Size = FontS("db"),
		Name = "ArrowR",
		Text = ">",
		InitCommand = function(self)
			self:xy(menuX + MENU_W/2 - MENU_PAD + 4, 0):zoom(FONT_ZOOM):diffuse(color("#666688"))
			self:SetTextureFiltering(false)
		end,
		RefreshCommand = function(self)
			local mr = MenuRow[pn] or 1
			local rowY = topY + MENU_PAD + 36 + (mr - 1) * MENU_ROW_H + MENU_ROW_H/2
			self:y(rowY)
		end,
	}

	-- Footer hint
	m[#m+1] = Def.Text{
		Font = RodinPath("db"), Size = FontS("db"),
		Text = "Select/Start: Confirm   Back: Cancel",
		InitCommand = function(self)
			local footY = topY + MENU_PAD + 36 + numRows * MENU_ROW_H + MENU_PAD + 8
			self:xy(menuX, footY)
				:zoom(FONT_ZOOM)
				:diffuse(color("#555566"))
			self:shadowlength(0)
			self:SetTextureFiltering(false)
		end,
	}

	return m
end

-- ===== BUILD ACTOR TREE =====
local t = Def.ActorFrame{
	Name = "GridBrowser",
	OnCommand = function(self)
		GridFrame = self
		for i = 1, POOL_CARDS do
			CardPool[i] = self:GetChild("Card"..i)
		end
		for i = 1, POOL_HEADERS do
			HeaderPool[i] = self:GetChild("Header"..i)
		end

		-- Restore cursor state: prefer in-session global, fall back to profile prefs
		-- (profile prefs survive game restarts; GalaxyCursorState only survives screen transitions)
		local restoreGroup   = GalaxyCursorState.OpenGroup
		local restoreSongDir = GalaxyCursorState.SongDir
		local restoreGroupName = GalaxyCursorState.GroupName

		if not restoreGroup or restoreGroup == "" then
			-- Try loading from first enabled player's profile
			for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
				if GalaxyOptions and GalaxyOptions[pn] then
					local opts = GalaxyOptions[pn]
					if opts.MusicSelectGroup and opts.MusicSelectGroup ~= "" then
						restoreGroup = opts.MusicSelectGroup
					end
					if opts.MusicSelectSongDir and opts.MusicSelectSongDir ~= "" then
						restoreSongDir = opts.MusicSelectSongDir
						restoreGroupName = nil
					end
					break  -- use first player's state
				end
			end
		end

		if restoreGroup and restoreGroup ~= "" then
			OpenGroup = restoreGroup
		end

		FlatList = BuildFlatList()

		-- Try to restore cursor position
		local restored = false
		if restoreSongDir and restoreSongDir ~= "" then
			for i, item in ipairs(FlatList) do
				if type(item) == "table" and item[1]:GetSongDir() == restoreSongDir then
					Cursor = i
					restored = true
					break
				end
			end
		elseif restoreGroupName and restoreGroupName ~= "" then
			for i, item in ipairs(FlatList) do
				if type(item) == "string" and item == restoreGroupName then
					Cursor = i
					restored = true
					break
				end
			end
		end
		if not restored then
			Cursor = 1
		end

		-- Set current song if restored to a song entry
		if IsSong(Cursor) then
			GAMESTATE:SetCurrentSong(FlatList[Cursor][1])
		end

		Accepted = false
		ResetAnim()
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		Refresh()
		RefreshInfoPanel()
		PlaySongPreview()

		-- Per-frame animation: shift ActorFrame y along cubic curve
		self:SetUpdateFunction(function(af, dt)
			if AnimActive then
				AnimTime = AnimTime + dt
				if AnimTime >= ANIM_DUR then
					VisualOffset = 0
					AnimActive = false
					af:y(0)
				else
					local s = AnimTime / ANIM_DUR
					VisualOffset = EvalCubic(s)
					af:y(VisualOffset)
				end
			end
			-- Deferred jacket loading: load a few more cards each frame
			if DeferredLoadPending then
				Refresh()
			end
		end)
	end,
	OffCommand = function(self)
		SaveCursorState()
		StopSongPreview()
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
	end,
}

for i = 1, POOL_CARDS do
	t[#t+1] = MakeSongCard("Card"..i)
end
for i = 1, POOL_HEADERS do
	t[#t+1] = MakeGroupHeader("Header"..i)
end

-- Wrap in outer frame so menu is not affected by grid scroll animation
local outer = Def.ActorFrame{ Name = "MusicSelectRoot" }
outer[#outer+1] = t
outer[#outer+1] = MakeMenu(PLAYER_1)
outer[#outer+1] = MakeMenu(PLAYER_2)

-- ===== DIFFICULTY PICKER ACTOR =====
-- Per-player difficulty picker boxes.
-- 1-player: single centered box.  2-player: two side-by-side boxes.
local DIFF_ROW_H = 52
local DIFF_W     = 320
local MAX_DIFFS  = 6

local DIFF_PLAYER_COLORS = {
	[PLAYER_1] = { border = color("#334488"), highlight = color("#333366"), label = "P1" },
	[PLAYER_2] = { border = color("#883344"), highlight = color("#663333"), label = "P2" },
}

local function MakeDiffPicker(pn)
	local isVersus = GAMESTATE:GetNumPlayersEnabled() > 1
	-- X position: centered for solo, offset for versus
	local boxX
	if isVersus then
		boxX = (pn == PLAYER_1) and (SCREEN_CENTER_X - DIFF_W/2 - 20)
		                           or (SCREEN_CENTER_X + DIFF_W/2 + 20)
	else
		boxX = SCREEN_CENTER_X
	end
	local pColors = DIFF_PLAYER_COLORS[pn]

	local m = Def.ActorFrame{
		Name = "DiffPicker_"..ToEnumShortString(pn),
		InitCommand = function(self)
			DiffFrame[pn] = self
			self:visible(false)
		end,
		RefreshDiffCommand = function(self)
			local n = #DiffSteps
			local totalH = n * DIFF_ROW_H + 60
			local topY = SCREEN_CENTER_Y - totalH/2

			-- Background / border sizing
			local bg     = self:GetChild("DiffBG")
			local border = self:GetChild("DiffBorder")
			if bg     then bg:y(SCREEN_CENTER_Y):zoomto(DIFF_W, totalH) end
			if border then border:y(SCREEN_CENTER_Y):zoomto(DIFF_W + 2, totalH + 2) end

			-- Title
			local title = self:GetChild("DiffTitle")
			if title then
				local songName = DiffSong and DiffSong:GetDisplayMainTitle() or ""
				local heading = isVersus and (pColors.label.." - "..songName) or songName
				title:y(topY + 20)
			title:settext(heading):Regen()
			end

			local selIdx = DiffPickIdx[pn] or 1

			-- Rows
			for i = 1, MAX_DIFFS do
				local rowBG = self:GetChild("DiffRowBG"..i)
				local label = self:GetChild("DiffLabel"..i)
				local meter = self:GetChild("DiffMeter"..i)
				if i <= n then
					local st  = DiffSteps[i]
					local dc  = GetDiffColor(st)
					local rowY = topY + 40 + (i - 1) * DIFF_ROW_H + DIFF_ROW_H/2
					local sel = (i == selIdx)
					if rowBG then
						rowBG:visible(true):y(rowY)
						rowBG:diffuse(sel and pColors.highlight or color("#00000000"))
					end
					if label then
						label:visible(true):y(rowY)
						label:settext(ToEnumShortString(st:GetDifficulty())):Regen()
						label:diffuse(sel and dc or color("#888888"))
					end
					if meter then
						meter:visible(true):y(rowY)
						meter:settext(tostring(st:GetMeter())):Regen()
						meter:diffuse(sel and dc or color("#666666"))
					end
				else
					if rowBG then rowBG:visible(false) end
					if label then label:visible(false) end
					if meter then meter:visible(false) end
				end
			end
		end,

		-- Border
		Def.Quad{
			Name = "DiffBorder",
			InitCommand = function(self)
				self:x(boxX):zoomto(DIFF_W + 2, 200)
					:diffuse(isVersus and pColors.border or color("#444466"))
			end,
		},
		-- Background
		Def.Quad{
			Name = "DiffBG",
			InitCommand = function(self)
				self:x(boxX):zoomto(DIFF_W, 200)
					:diffuse(color("#0a0a18")):diffusealpha(0.97)
			end,
		},
		-- Title / player heading
		Def.Text{
			Font = RodinPath("db"), Size = FontM("db"), Text = "",
			Name = "DiffTitle",
			InitCommand = function(self)
				self:x(boxX):zoom(FONT_ZOOM)
					:diffuse(Color.White)
				self:maxwidth(FontMaxWidth(DIFF_W - 16)):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		},
	}

	-- Difficulty rows
	for i = 1, MAX_DIFFS do
		m[#m+1] = Def.Quad{
			Name = "DiffRowBG"..i,
			InitCommand = function(self)
				self:x(boxX):zoomto(DIFF_W - 8, DIFF_ROW_H - 6):visible(false)
			end,
		}
		m[#m+1] = Def.Text{
			Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "DiffLabel"..i,
			InitCommand = function(self)
				self:x(boxX - DIFF_W/2 + 20):zoom(FONT_ZOOM)
					:visible(false)
				self:halign(0):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		m[#m+1] = Def.Text{
			Font = RodinPath("db"), Size = FontM("db"), Text = "",
			Name = "DiffMeter"..i,
			InitCommand = function(self)
				self:x(boxX + DIFF_W/2 - 20):zoom(FONT_ZOOM)
					:visible(false)
				self:halign(1):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
	end

	return m
end

outer[#outer+1] = MakeDiffPicker(PLAYER_1)
outer[#outer+1] = MakeDiffPicker(PLAYER_2)

-- ===== SONG INFO BAR =====
-- Displays jacket, title, artist, BPM in a centered bar at the top of the screen.
local INFO_BAR_W = 850
local INFO_BAR_H = 80
local INFO_BAR_Y = 55
local _loadedInfoSongDir = nil   -- guard: skip jacket:Load when same song

local infoPanel = Def.ActorFrame{
	Name = "SongInfoPanel",
	InitCommand = function(self)
		InfoFrame = self
		self:xy(SCREEN_CENTER_X, INFO_BAR_Y)
	end,
	SetSongCommand = function(self, params)
		local song = params.Song
		local title  = self:GetChild("InfoTitle")
		local artist = self:GetChild("InfoArtist")
		local bpmText= self:GetChild("InfoBPM")
		local jacket = self:GetChild("InfoJacket")
		local bg     = self:GetChild("InfoBG")
		local border = self:GetChild("InfoBorder")

		if song then
			bg:visible(true)
			border:visible(true)
			title:visible(true)
			title:settext(song:GetDisplayMainTitle()):Regen()
			artist:visible(true)
			artist:settext(song:GetDisplayArtist()):Regen()
			local songDir = song:GetSongDir()
			if songDir ~= _loadedInfoSongDir then
				_loadedInfoSongDir = songDir
				jacket:Load(GetJacketPath(song))
				jacket:scaletoclipped(60, 60)
			end
			jacket:visible(true)

			-- BPM breakdown: [Min - Mode - Max]
			local bpms = song:GetDisplayBpms()
			local minBPM = math.floor(bpms[1] + 0.5)
			local maxBPM = math.floor(bpms[2] + 0.5)
			local modeBPM = GetDominantBPM(song)
			if modeBPM then
				modeBPM = math.floor(modeBPM + 0.5)
			else
				modeBPM = maxBPM
			end

			if minBPM == maxBPM then
				bpmText:visible(true)
				bpmText:settext(tostring(minBPM) .. " BPM"):Regen()
			else
				bpmText:visible(true)
				bpmText:settext(minBPM .. " - " .. modeBPM .. " - " .. maxBPM .. " BPM"):Regen()
			end
		else
			bg:visible(false)
			border:visible(false)
			title:visible(false)
			title:settext(""):Regen()
			artist:visible(false)
			artist:settext(""):Regen()
			bpmText:visible(false)
			bpmText:settext(""):Regen()
			jacket:visible(false)
			_loadedInfoSongDir = nil
		end
	end,

	-- Border
	Def.Quad{
		Name = "InfoBorder",
		InitCommand = function(self)
			self:zoomto(INFO_BAR_W + 2, INFO_BAR_H + 2)
				:diffuse(color("#334466")):diffusealpha(0.5):visible(false)
		end,
	},
	-- Background
	Def.Quad{
		Name = "InfoBG",
		InitCommand = function(self)
			self:zoomto(INFO_BAR_W, INFO_BAR_H)
				:diffuse(color("#0a0a18")):diffusealpha(0.92):visible(false)
		end,
	},
	-- Jacket
	Def.Sprite{
		Name = "InfoJacket",
		InitCommand = function(self)
			self:x(-INFO_BAR_W/2 + 42):visible(false)
		end,
	},
	-- Song title
	Def.Text{
		Font = RodinPath("db"), Size = FontM("db"), Text = "",
		Name = "InfoTitle",
		InitCommand = function(self)
			self:xy(-INFO_BAR_W/2 + 82, -12)
				:zoom(FONT_ZOOM)
				:diffuse(Color.White)
				:visible(false)
			self:halign(0):valign(0.5):maxwidth(FontMaxWidth(INFO_BAR_W - 130)):shadowlength(0)
			self:SetTextureFiltering(false)
		end,
	},
	-- Artist
	Def.Text{
		Font = RodinPath("db"), Size = FontS("db"), Text = "",
		Name = "InfoArtist",
		InitCommand = function(self)
			self:xy(-INFO_BAR_W/2 + 82, 12)
				:zoom(FONT_ZOOM)
				:diffuse(color("#aaaaaa"))
				:visible(false)
			self:halign(0):valign(0.5):maxwidth(FontMaxWidth(INFO_BAR_W - 130)):shadowlength(0)
			self:SetTextureFiltering(false)
		end,
	},
	-- BPM
	Def.Text{
		Font = RodinPath("db"), Size = FontS("db"), Text = "",
		Name = "InfoBPM",
		InitCommand = function(self)
			self:xy(INFO_BAR_W/2 - 15, 0)
				:zoom(FONT_ZOOM)
				:diffuse(color("#66aaff"))
				:visible(false)
			self:halign(1):valign(0.5):shadowlength(0)
			self:SetTextureFiltering(false)
		end,
	},
}
outer[#outer+1] = infoPanel

-- ===== SONG PREVIEW ACTOR =====
-- Invisible actor that handles debounced preview playback.
-- Uses stoptweening + sleep + queuecommand to debounce rapid scrolling.
local PREVIEW_DELAY = 0.2  -- seconds; debounce only — just long enough to skip
                           -- songs the user scrolls past.  The music thread may
                           -- still block on OGG seek (engine limitation).

outer[#outer+1] = Def.Actor{
	Name = "SongPreview",
	InitCommand = function(self)
		PreviewActor = self
	end,
	StartPreviewCommand = function(self)
		local gen = _previewGen
		self:stoptweening():sleep(PREVIEW_DELAY):queuecommand("DoPreview")
		-- Stash the generation so DoPreview can check it
		self._gen = gen
	end,
	DoPreviewCommand = function(self)
		-- If generation changed since StartPreview, a stop or new play
		-- was issued in the meantime — discard this stale callback.
		if self._gen ~= _previewGen then return end

		local song = GAMESTATE:GetCurrentSong()
		if song then
			local path = song:GetPreviewMusicPath()
			if path and path ~= "" then
				-- Skip if this exact file is already playing/loading.
				-- PlayMusicPart internally queues a stop+play on the music
				-- thread; calling StopMusic separately doubles the queue
				-- entries and can starve PlayOnce SFX.
				if path == _currentPreviewPath then return end
				_currentPreviewPath = path
				SOUND:PlayMusicPart(
					path,
					song:GetSampleStart(),
					song:GetSampleLength(),
					0,    -- fadeIn
					0,    -- fadeOut (no fade — avoids lingering sound objects)
					true, -- loop
					false,-- applyRate
					false -- alignBeat
				)
			end
		else
			-- Cursor is on a group header, not a song — stop music
			if _currentPreviewPath then
				_currentPreviewPath = nil
				SOUND:StopMusic()
			end
		end
	end,
	OffCommand = function(self)
		SOUND:StopMusic()
	end,
}

-- ===== SCORE PANEL =====
-- Per-player panel showing scores for all 5 difficulties of the selected song.
-- P1 left, P2 right. Rows grayed out if difficulty doesn't exist.
-- Columns: Diff | Meter | Grade | Score | Lamp | EX Raw | EX% | Flare | FP

local PANEL_W     = 520
local PANEL_H     = 400
local PANEL_ROW_H = 60
local PANEL_Y     = SCREEN_CENTER_Y
local PANEL_DIFFS = {
	"Difficulty_Beginner",
	"Difficulty_Easy",
	"Difficulty_Medium",
	"Difficulty_Hard",
	"Difficulty_Challenge",
}
local PANEL_DIFF_LABELS = { "BEG", "BSC", "DIF", "EXP", "CHA" }

local PANEL_DIFF_COLORS = {
	Difficulty_Beginner  = color("#1ed6ff"),
	Difficulty_Easy      = color("#ffaa19"),
	Difficulty_Medium    = color("#ff1e3c"),
	Difficulty_Hard      = color("#32eb19"),
	Difficulty_Challenge = color("#eb1eff"),
}

local function commify(n)
	local s = tostring(n)
	local pos = #s % 3
	if pos == 0 then pos = 3 end
	local parts = { s:sub(1, pos) }
	for i = pos + 1, #s, 3 do
		parts[#parts+1] = s:sub(i, i + 2)
	end
	return table.concat(parts, ",")
end

-- Lamp display colors
local LampColors = {
	MFC   = color("#00ccff"),  -- cyan
	PFC   = color("#ffcc00"),  -- gold
	GFC   = color("#00ff66"),  -- green
	FC    = color("#ffffff"),  -- white
	LIFE4 = color("#ff66cc"),  -- pink
	Clear = color("#888888"),  -- gray
}

local function MakeScorePanel(pn)
	local isVersus = GAMESTATE:GetNumPlayersEnabled() > 1
	local panelX
	if isVersus then
		panelX = (pn == PLAYER_1) and 275 or (SCREEN_WIDTH - 275)
	else
		panelX = 275
	end

	local pnShort = ToEnumShortString(pn)
	local curHighlightIdx = 0  -- which row is highlighted (1-5, 0 = none)

	local panel = Def.ActorFrame{
		Name = "ScorePanel_" .. pnShort,
		DrawOrder = -1,
		InitCommand = function(self)
			self:draworder(-1)
			self:xy(panelX, PANEL_Y)
			self:visible(GAMESTATE:IsPlayerEnabled(pn))
			ScorePanelFrame[pn] = self
		end,

		-- === Refresh all rows when song changes ===
		SetSongCommand = function(self, params)
			local song = params and params.Song or nil
			local st = GAMESTATE:GetCurrentStyle():GetStepsType()

			for i = 1, 5 do
				local diff = PANEL_DIFFS[i]
				local rowBG    = self:GetChild("SPRowBG" .. i)
				local diffText = self:GetChild("SPDiff" .. i)
				local meterText= self:GetChild("SPMeter" .. i)
				local gradeText= self:GetChild("SPGrade" .. i)
				local scoreText= self:GetChild("SPScore" .. i)
				local lampText = self:GetChild("SPLamp" .. i)
				local exRawText= self:GetChild("SPExRaw" .. i)
				local exPctText= self:GetChild("SPExPct" .. i)
				local flareText= self:GetChild("SPFlare" .. i)
				local fpText   = self:GetChild("SPFp" .. i)

				local dc = PANEL_DIFF_COLORS[diff] or color("#888888")
				local hasDiff = song and song:HasStepsTypeAndDifficulty(st, diff)

				if hasDiff then
					local steps = song:GetOneSteps(st, diff)
					local data = GetScoreDataForSteps(pn, song, steps)
					local chartKey = GetChartKey(song, steps)
					local cr = chartKey and GetChartResult(pn, chartKey)

					-- Diff label
					if diffText then
						diffText:settext(PANEL_DIFF_LABELS[i]):Regen()
						diffText:diffuse(dc):diffusealpha(1)
					end
					-- Meter
					if meterText then
						meterText:settext(tostring(steps:GetMeter())):Regen()
						meterText:diffuse(dc):diffusealpha(1)
					end

					if data then
						if gradeText then
							gradeText:settext(data.grade):Regen()
							gradeText:diffuse(Color.White):diffusealpha(1)
						end
						if scoreText then
							scoreText:settext(commify(data.score)):Regen()
							scoreText:diffuse(Color.White):diffusealpha(1)
						end
						if exRawText then
							exRawText:settext(tostring(data.exRaw)):Regen()
							exRawText:diffuse(color("#aaeeff")):diffusealpha(1)
						end
						if exPctText then
							exPctText:settext(string.format("%.2f%%", data.exPct)):Regen()
							exPctText:diffuse(color("#aaeeff")):diffusealpha(1)
						end
					else
						if gradeText then gradeText:settext("---"):Regen(); gradeText:diffuse(color("#555555")):diffusealpha(0.6) end
						if scoreText then scoreText:settext("---"):Regen(); scoreText:diffuse(color("#555555")):diffusealpha(0.6) end
						if exRawText then exRawText:settext("---"):Regen(); exRawText:diffuse(color("#555555")):diffusealpha(0.6) end
						if exPctText then exPctText:settext("---"):Regen(); exPctText:diffuse(color("#555555")):diffusealpha(0.6) end
					end

					-- Combo lamp + flare from custom save data
					if cr then
						if lampText then
							local lampStr = cr.lamp or "---"
							lampText:settext(lampStr):Regen()
							lampText:diffuse(LampColors[lampStr] or color("#555555"))
							lampText:diffusealpha(1)
						end
						if flareText then
							local fg = GetFlareGradeDisplay(cr.flareGauge)
							flareText:settext(fg):Regen()
							flareText:diffuse(color("#ffcc66")):diffusealpha(fg == "---" and 0.4 or 1)
						end
						if fpText then
							local fp = cr.flarePoints or 0
							fpText:settext(fp > 0 and tostring(fp) or "---"):Regen()
							fpText:diffuse(color("#ffcc66")):diffusealpha(fp > 0 and 1 or 0.4)
						end
					else
						if lampText then lampText:settext("---"):Regen(); lampText:diffuse(color("#555555")):diffusealpha(0.6) end
						if flareText then flareText:settext("---"):Regen(); flareText:diffuse(color("#555555")):diffusealpha(0.4) end
						if fpText then fpText:settext("---"):Regen(); fpText:diffuse(color("#555555")):diffusealpha(0.4) end
					end

					if rowBG then rowBG:diffusealpha(0) end
				else
					-- Difficulty doesn't exist — gray out entire row
					if diffText then diffText:settext(PANEL_DIFF_LABELS[i]):Regen(); diffText:diffuse(color("#333333")):diffusealpha(0.35) end
					if meterText then meterText:settext("--"):Regen(); meterText:diffuse(color("#333333")):diffusealpha(0.35) end
					if gradeText then gradeText:settext(""):Regen(); gradeText:diffusealpha(0) end
					if scoreText then scoreText:settext(""):Regen(); scoreText:diffusealpha(0) end
					if lampText then lampText:settext(""):Regen(); lampText:diffusealpha(0) end
					if exRawText then exRawText:settext(""):Regen(); exRawText:diffusealpha(0) end
					if exPctText then exPctText:settext(""):Regen(); exPctText:diffusealpha(0) end
					if flareText then flareText:settext(""):Regen(); flareText:diffusealpha(0) end
					if fpText then fpText:settext(""):Regen(); fpText:diffusealpha(0) end
					if rowBG then rowBG:diffusealpha(0) end
				end
			end

			-- Re-apply highlight
			self:playcommand("HighlightDiff")
		end,

		-- === Highlight the currently selected difficulty ===
		HighlightDiffCommand = function(self)
			local steps = GAMESTATE:GetCurrentSteps(pn)
			local newIdx = 0
			if steps then
				local d = steps:GetDifficulty()
				for i, diff in ipairs(PANEL_DIFFS) do
					if diff == d then newIdx = i; break end
				end
			end
			for i = 1, 5 do
				local rowBG = self:GetChild("SPRowBG" .. i)
				if rowBG then
					if i == newIdx then
						rowBG:diffuse(color("#ffffff")):diffusealpha(0.12)
					else
						rowBG:diffusealpha(0)
					end
				end
			end
			curHighlightIdx = newIdx
		end,

		-- === Highlight by explicit difficulty enum (from diff picker) ===
		HighlightDiffByEnumCommand = function(self, params)
			local d = params and params.Difficulty
			local newIdx = 0
			if d then
				for i, diff in ipairs(PANEL_DIFFS) do
					if diff == d then newIdx = i; break end
				end
			end
			for i = 1, 5 do
				local rowBG = self:GetChild("SPRowBG" .. i)
				if rowBG then
					if i == newIdx then
						rowBG:diffuse(color("#ffffff")):diffusealpha(0.12)
					else
						rowBG:diffusealpha(0)
					end
				end
			end
			curHighlightIdx = newIdx
		end,

		-- Background panel
		Def.Quad{
			InitCommand = function(self)
				self:zoomto(PANEL_W, PANEL_H):diffuse(color("#0a0a18")):diffusealpha(0.85)
			end,
		},
		-- Border
		Def.Quad{
			InitCommand = function(self)
				self:zoomto(PANEL_W + 2, PANEL_H + 2):diffuse(color("#334466")):diffusealpha(0.5)
			end,
		},
		-- Column headers
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "DIFF",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 12, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(0)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "LV",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 65, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(0.5)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "GRD",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 100, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(0.5)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "SCORE",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 185, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(1)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "LAMP",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 235, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(0.5)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "EX",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 310, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(1)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "EX%",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 375, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(1)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "FLARE",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 435, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(0.5)
				self:SetTextureFiltering(false)
			end,
		},
		Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "FP",
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 500, -PANEL_H/2 + 12):zoom(FONT_ZOOM):diffuse(color("#667788"))
				self:halign(1)
				self:SetTextureFiltering(false)
			end,
		},
	}

	-- Build 5 difficulty rows
	local rowStartY = -PANEL_H/2 + 35
	for i = 1, 5 do
		local rowY = rowStartY + (i - 1) * PANEL_ROW_H + PANEL_ROW_H/2

		-- Row highlight background
		panel[#panel+1] = Def.Quad{
			Name = "SPRowBG" .. i,
			InitCommand = function(self)
				self:y(rowY):zoomto(PANEL_W - 6, PANEL_ROW_H - 4):diffusealpha(0)
			end,
		}
		-- Difficulty label
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPDiff" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 12, rowY):zoom(FONT_ZOOM)
				self:halign(0):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- Meter
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPMeter" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 65, rowY):zoom(FONT_ZOOM)
				self:halign(0.5):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- Grade
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPGrade" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 100, rowY):zoom(FONT_ZOOM)
				self:halign(0.5):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- Score
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPScore" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 185, rowY):zoom(FONT_ZOOM)
				self:halign(1):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- Combo Lamp
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPLamp" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 235, rowY):zoom(FONT_ZOOM)
				self:halign(0.5):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- EX Raw
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPExRaw" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 310, rowY):zoom(FONT_ZOOM)
				self:halign(1):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- EX %
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPExPct" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 375, rowY):zoom(FONT_ZOOM)
				self:halign(1):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- Flare Grade
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPFlare" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 435, rowY):zoom(FONT_ZOOM)
				self:halign(0.5):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
		-- Flare Points
		panel[#panel+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
			Name = "SPFp" .. i,
			InitCommand = function(self)
				self:xy(-PANEL_W/2 + 500, rowY):zoom(FONT_ZOOM)
				self:halign(1):shadowlength(0)
				self:SetTextureFiltering(false)
			end,
		}
	end

	return panel
end

outer[#outer+1] = MakeScorePanel(PLAYER_1)
outer[#outer+1] = MakeScorePanel(PLAYER_2)

-- ===== PRECACHED SFX ACTORS =====
-- Def.Sound uses its own RageSound instance, bypassing the GameSoundManager
-- music thread queue. This ensures cursor/confirm/cancel SFX play instantly
-- even while a long OGG preview is loading on the music thread.
outer[#outer+1] = Def.Sound{
	File = SND_SWITCH,
	IsAction = true,
	InitCommand = function(self) SfxSwitch = self end,
}
outer[#outer+1] = Def.Sound{
	File = SND_START,
	IsAction = true,
	InitCommand = function(self) SfxStart = self end,
}
outer[#outer+1] = Def.Sound{
	File = SND_CANCEL,
	IsAction = true,
	InitCommand = function(self) SfxCancel = self end,
}

return outer
