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
local CARD_W       = 160
local CARD_H       = 190
local COL_GAP      = 12
local ROW_GAP      = 12
local HEADER_H     = 44
local POOL_CARDS   = 42    -- enough to fill screen + animation margin
local POOL_HEADERS = 12

local GRID_X       = SCREEN_CENTER_X
local CENTER_Y     = SCREEN_CENTER_Y  -- cursor item is pinned here

local totalColW    = CARD_W + COL_GAP
local totalRowH    = CARD_H + ROW_GAP

-- How far above/below center we render (pixels)
local RENDER_MARGIN = SCREEN_HEIGHT / 2 + CARD_H + 60

-- ===== STATE =====
local FlatList     = {}
local Cursor       = 1
local OpenGroup    = ""
local Accepted     = false

local CardPool     = {}
local HeaderPool   = {}
local GridFrame    = nil   -- reference to GridBrowser ActorFrame

-- ===== ANIMATION STATE =====
local VisualOffset = 0     -- current pixel offset (ActorFrame y-shift)
local AnimActive   = false
local AnimTime     = 0     -- seconds into current animation
local ANIM_DUR     = 0.15  -- animation duration in seconds
-- Cubic coefficients: f(s) = As³ + Bs² + Cs + D, s ∈ [0,1]
local AnimA, AnimB, AnimC, AnimD = 0, 0, 0, 0

-- ===== SIDE MENU CONSTANTS =====
local MENU_W       = 380
local MENU_X       = SCREEN_WIDTH - MENU_W/2 - 30  -- build-time reference (right side)
local MENU_X_LEFT  = MENU_W/2 + 30                 -- left side for P1
local MENU_ROW_H   = 50
local MENU_PAD     = 16

-- ===== SIDE MENU STATE =====
local MenuOpen     = false
local MenuRow      = 1
local MenuFrame    = nil

-- ===== DIFFICULTY PICKER STATE =====
local DiffPickOpen = false
local DiffPickIdx  = 1       -- selected index in DiffSteps[]
local DiffSteps    = {}      -- array of Steps objects for chosen song
local DiffFrame    = nil     -- reference to DiffPicker ActorFrame
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
GalaxyOptions = GalaxyOptions or {}
for _, pn in ipairs({PLAYER_1, PLAYER_2}) do
	GalaxyOptions[pn] = GalaxyOptions[pn] or { Gauge = "Normal", SpeedMode = "XMod", SpeedValue = 2.0 }
	-- Ensure speed fields exist for tables created before this version
	if not GalaxyOptions[pn].SpeedMode then GalaxyOptions[pn].SpeedMode = "XMod" end
	if not GalaxyOptions[pn].SpeedValue then GalaxyOptions[pn].SpeedValue = 2.0 end
end

-- Cursor persistence across screen transitions
GalaxyCursorState = GalaxyCursorState or {}

-- ===== SIDE MENU OPTION DEFINITIONS =====
local OptionRows    -- forward-declare so SyncSpeedValueChoices can close over it

local SpeedModes = {
	{ label = "XMod",  value = "XMod" },
	{ label = "CMod",  value = "CMod" },
	{ label = "MMod",  value = "MMod" },
	{ label = "Real",  value = "Real" },
}

local XModValues = {}
do
	for v = 25, 800, 25 do  -- 0.25x to 8.00x in 0.25 increments (DDR-style)
		XModValues[#XModValues+1] = { label = string.format("x%.2f", v/100), value = v/100 }
	end
end

local BPMValues = {}  -- shared for CMod, MMod, Real Speed
do
	for v = 50, 1200, 25 do
		BPMValues[#BPMValues+1] = { label = tostring(v), value = v }
	end
end

-- Swap Speed Value row choices based on current Speed Mode
local function SyncSpeedValueChoices()
	local modeRow = OptionRows and OptionRows[1]
	local valRow  = OptionRows and OptionRows[2]
	if not modeRow or not valRow then return end
	local mode = SpeedModes[modeRow.selected].value
	local oldVal = valRow.choices[valRow.selected] and valRow.choices[valRow.selected].value
	if mode == "XMod" then
		valRow.choices = XModValues
	else
		valRow.choices = BPMValues
	end
	-- Find closest value in new choices
	if oldVal then
		local bestIdx, bestDist = 1, 999999
		for i, c in ipairs(valRow.choices) do
			local d = math.abs(c.value - oldVal)
			if d < bestDist then bestIdx, bestDist = i, d end
		end
		valRow.selected = bestIdx
	else
		valRow.selected = 1
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

OptionRows = {
	{ name = "Mode",   choices = SpeedModes,    selected = 1 },   -- XMod default
	{ name = "Speed",  choices = XModValues,    selected = 8 },   -- x2.00 default
	{ name = "Turn",   choices = TurnChoices,   selected = 1 },
	{ name = "Scroll", choices = ScrollChoices,  selected = 1 },
	{ name = "Gauge",  choices = GaugeChoices,  selected = 1 },
}

-- ===== SIDE MENU FUNCTIONS =====
local function ReadCurrentSpeed()
	local pn = GAMESTATE:GetMasterPlayerNumber()
	local opts = GalaxyOptions[pn]
	local mode = opts and opts.SpeedMode or "XMod"
	local val  = opts and opts.SpeedValue or 2.0

	-- Set Speed Mode row
	for i, c in ipairs(SpeedModes) do
		if c.value == mode then
			OptionRows[1].selected = i
			break
		end
	end

	-- Set Speed Value row choices and find closest value
	if mode == "XMod" then
		OptionRows[2].choices = XModValues
	else
		OptionRows[2].choices = BPMValues
	end
	local bestIdx, bestDist = 1, 999999
	for i, c in ipairs(OptionRows[2].choices) do
		local d = math.abs(c.value - val)
		if d < bestDist then bestIdx, bestDist = i, d end
	end
	OptionRows[2].selected = bestIdx
end

local function ReadCurrentGauge()
	local pn = GAMESTATE:GetMasterPlayerNumber()
	local current = GalaxyOptions[pn] and GalaxyOptions[pn].Gauge or "Normal"
	for i, c in ipairs(GaugeChoices) do
		if c.value == current then
			OptionRows[5].selected = i
			return
		end
	end
	OptionRows[5].selected = 1
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
	local val  = opts.SpeedValue or 2.0

	if mode == "XMod" then
		GAMESTATE:ApplyPreferredModifiers(pn, string.format("%.2fx", val))
	elseif mode == "CMod" then
		GAMESTATE:ApplyPreferredModifiers(pn, string.format("C%d", val))
	elseif mode == "MMod" then
		GAMESTATE:ApplyPreferredModifiers(pn, string.format("M%d", val))
	elseif mode == "Real" then
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

local function ApplyMenuOptions()
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		-- Speed: store mode/value in GalaxyOptions, then apply
		local mode = SpeedModes[OptionRows[1].selected].value
		local val  = OptionRows[2].choices[OptionRows[2].selected].value
		GalaxyOptions[pn].SpeedMode  = mode
		GalaxyOptions[pn].SpeedValue = val
		ApplySpeedMod(pn)

		-- Turn: clear all, then apply
		GAMESTATE:ApplyPreferredModifiers(pn, "NoMirror,NoLeft,NoRight,NoShuffle,NoSuperShuffle")
		local turnMod = TurnChoices[OptionRows[3].selected].mod
		if turnMod ~= "" then
			GAMESTATE:ApplyPreferredModifiers(pn, turnMod)
		end

		-- Scroll
		local scrollMod = ScrollChoices[OptionRows[4].selected].mod
		if scrollMod == "Reverse" then
			GAMESTATE:ApplyPreferredModifiers(pn, "Reverse")
		else
			GAMESTATE:ApplyPreferredModifiers(pn, "NoReverse")
		end

		-- Gauge: store in global table for GaugeState to read
		GalaxyOptions[pn].Gauge = GaugeChoices[OptionRows[5].selected].value
	end
end

local function RefreshMenu()
	if not MenuFrame then return end
	MenuFrame:playcommand("Refresh")
end

local function OpenMenu(playerNum)
	ReadCurrentSpeed()
	ReadCurrentGauge()
	MenuOpen = true
	MenuRow = 1
	if MenuFrame then
		-- Position based on which player opened the menu
		local isP1 = (playerNum == PLAYER_1)
		MenuFrame:x(isP1 and (MENU_X_LEFT - MENU_X) or 0)
		MenuFrame:visible(true)
		RefreshMenu()
	end
end

local function CloseMenu(apply)
	if apply then ApplyMenuOptions() end
	MenuOpen = false
	if MenuFrame then MenuFrame:visible(false) end
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
	if not DiffFrame then return end
	DiffFrame:playcommand("RefreshDiff")
end

local function OpenDiffPicker(song, stepsArray)
	DiffSong = song
	DiffSteps = stepsArray
	DiffPickIdx = 1
	-- Try to default to preferred difficulty or middle entry
	local pn = GAMESTATE:GetMasterPlayerNumber()
	local pref = GAMESTATE:GetPreferredDifficulty(pn)
	if pref then
		for i, st in ipairs(DiffSteps) do
			if st:GetDifficulty() == pref then
				DiffPickIdx = i
				break
			end
		end
	end
	DiffPickOpen = true
	if DiffFrame then DiffFrame:visible(true) end
	RefreshDiffPicker()
end

local function CloseDiffPicker()
	DiffPickOpen = false
	if DiffFrame then DiffFrame:visible(false) end
end

local function ConfirmDifficulty()
	if Accepted then return end
	local steps = DiffSteps[DiffPickIdx]
	if not steps then return end
	GAMESTATE:SetCurrentSong(DiffSong)
	GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		GAMESTATE:SetCurrentSteps(pn, steps)
		GAMESTATE:SetPreferredDifficulty(pn, steps:GetDifficulty())
		-- Re-apply speed mod now that song is set (important for Real Speed)
		ApplySpeedMod(pn)
	end
	SaveCursorState()
	Accepted = true
	CloseDiffPicker()
	SOUND:PlayOnce(THEME:GetPathS("Common","Start"))
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

-- ===== DATA LAYER =====

local function BuildFlatList()
	local list = {}
	local groups = SONGMAN:GetSongGroupNames()
	for _, grp in ipairs(groups) do
		list[#list+1] = grp
		if grp == OpenGroup then
			local songs = SONGMAN:GetSongsInGroup(grp)
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

	-- Hide everything
	for i = 1, POOL_CARDS do CardPool[i]:visible(false) end
	for i = 1, POOL_HEADERS do HeaderPool[i]:visible(false) end

	local ci = 1
	local hi = 1

	for _, item in ipairs(items) do
		local screenY = CENTER_Y + item.y

		if item.type == "group" and hi <= POOL_HEADERS then
			local a = HeaderPool[hi]
			a:visible(true)
			a:xy(GRID_X, screenY)
			a:playcommand("SetHeader", {
				Text = FlatList[item.flatIdx],
				HasFocus = (item.flatIdx == Cursor),
				IsOpen = (FlatList[item.flatIdx] == OpenGroup),
			})
			hi = hi + 1
		elseif item.type == "song" and ci <= POOL_CARDS then
			local a = CardPool[ci]
			a:visible(true)
			local xOff = (item.col - 2) * totalColW
			a:xy(GRID_X + xOff, screenY)
			local entry = FlatList[item.flatIdx]
			a:playcommand("SetCard", {
				Song = entry[1],
				Steps = entry[2],
				HasFocus = (item.flatIdx == Cursor),
			})
			ci = ci + 1
		end
	end
end

-- ===== NAVIGATION =====
local function MoveCursor(delta)
	if Accepted or #FlatList == 0 then return end
	local oldCursor = Cursor
	Cursor = Wrap(Cursor + delta)
	if IsSong(Cursor) then
		GAMESTATE:SetCurrentSong(FlatList[Cursor][1])
	end
	SOUND:PlayOnce(THEME:GetPathS("","_switch down"))

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
	for i = 1, #FlatList do
		if IsGroup(i) and FlatList[i] == grp then
			Cursor = i
			break
		end
	end
	ResetAnim()
	Refresh()
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
		SOUND:PlayOnce(THEME:GetPathS("Common","Start"))
		SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
	else
		-- Multiple difficulties: open picker
		SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
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
	if event.type == "InputEventType_Release" then return false end
	if Accepted then return true end

	local btn = event.GameButton
	if not btn then return false end
	if not GAMESTATE:IsPlayerEnabled(event.PlayerNumber) then return false end

	-- Select button toggles the side menu
	if btn == "Select" then
		if DiffPickOpen then return true end  -- block Select during diff pick
		if not MenuOpen then
			OpenMenu(event.PlayerNumber)
		else
			CloseMenu(true)
		end
		return true
	end

	-- When difficulty picker is open, route input there
	if DiffPickOpen then
		if btn == "MenuUp" or btn == "MenuLeft" then
			DiffPickIdx = DiffPickIdx - 1
			if DiffPickIdx < 1 then DiffPickIdx = #DiffSteps end
			SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
			RefreshDiffPicker()
		elseif btn == "MenuDown" or btn == "MenuRight" then
			DiffPickIdx = DiffPickIdx + 1
			if DiffPickIdx > #DiffSteps then DiffPickIdx = 1 end
			SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
			RefreshDiffPicker()
		elseif btn == "Start" then
			ConfirmDifficulty()
		elseif btn == "Back" then
			CloseDiffPicker()
			SOUND:PlayOnce(THEME:GetPathS("Common","Cancel"))
		end
		return true
	end

	-- When menu is open, route all input to menu
	if MenuOpen then
		if btn == "MenuUp" then
			MenuRow = MenuRow - 1
			if MenuRow < 1 then MenuRow = #OptionRows end
			SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
			RefreshMenu()
		elseif btn == "MenuDown" then
			MenuRow = MenuRow + 1
			if MenuRow > #OptionRows then MenuRow = 1 end
			SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
			RefreshMenu()
		elseif btn == "MenuLeft" then
			local row = OptionRows[MenuRow]
			row.selected = row.selected - 1
			if row.selected < 1 then row.selected = #row.choices end
			-- When Speed Mode changes, update Speed Value choices
			if MenuRow == 1 then SyncSpeedValueChoices() end
			SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
			RefreshMenu()
		elseif btn == "MenuRight" then
			local row = OptionRows[MenuRow]
			row.selected = row.selected + 1
			if row.selected > #row.choices then row.selected = 1 end
			-- When Speed Mode changes, update Speed Value choices
			if MenuRow == 1 then SyncSpeedValueChoices() end
			SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
			RefreshMenu()
		elseif btn == "Start" then
			CloseMenu(true)
		elseif btn == "Back" then
			CloseMenu(false)
		end
		return true  -- eat all input when menu is open
	end

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
		if OpenGroup ~= "" then
			local grp = OpenGroup
			OpenGroup = ""
			FlatList = BuildFlatList()
			for i = 1, #FlatList do
				if IsGroup(i) and FlatList[i] == grp then
					Cursor = i
					break
				end
			end
			ResetAnim()
			Refresh()
		else
			SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToPrevScreen")
		end
		return true
	end

	return false
end

-- ===== ACTOR FACTORIES =====

local function MakeSongCard(name)
	return Def.ActorFrame{
		Name = name,
		InitCommand = function(self) self:visible(false) end,
		SetCardCommand = function(self, params)
			self:GetChild("Border"):visible(params.HasFocus)
			self:GetChild("BG"):diffuse(params.HasFocus and color("#333333") or color("#1a1a1a"))
			local jacket = self:GetChild("Jacket")
			if params.Song then
				jacket:LoadFromCached("Jacket", GetJacketPath(params.Song))
			end
			jacket:setsize(CARD_W - 16, CARD_W - 16)
			local title = self:GetChild("Title")
			if params.Song then
				title:settext(params.Song:GetDisplayMainTitle())
			else
				title:settext("")
			end
			title:diffuse(params.HasFocus and Color.White or color("#888888"))
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
			InitCommand = function(self) self:y(-18) end,
		},
		LoadFont("Common Normal") .. {
			Name = "Title",
			InitCommand = function(self)
				self:y(CARD_H/2 - 24):zoom(0.55):maxwidth(CARD_W/0.55 - 20):shadowlength(1)
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
			txt:settext(params.Text or "")
			txt:diffuse(params.HasFocus and Color.White or
				(params.IsOpen and color("#aaaacc") or color("#888888")))
			arrow:settext(params.IsOpen and "v " or "> ")
			arrow:diffuse(txt:GetDiffuse())
		end,

		Def.Quad{
			Name = "BG",
			InitCommand = function(self)
				self:zoomto(COLS * totalColW - COL_GAP, HEADER_H):diffuse(color("#1a1a1a"))
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "Text",
			InitCommand = function(self)
				self:zoom(0.65):maxwidth((COLS * totalColW - 60) / 0.65):shadowlength(1)
			end,
		},
		LoadFont("Common Normal") .. {
			Name = "Arrow",
			InitCommand = function(self)
				self:x((COLS * totalColW) / 2 - 20):zoom(0.6)
			end,
		},
	}
end

-- ===== SIDE MENU ACTOR =====
local function MakeMenu()
	local numRows = #OptionRows
	local totalH = MENU_PAD + 36 + numRows * MENU_ROW_H + MENU_PAD + 28 + MENU_PAD
	local topY = SCREEN_CENTER_Y - totalH/2
	local centerY = topY + totalH/2

	local m = Def.ActorFrame{
		Name = "SideMenu",
		InitCommand = function(self)
			MenuFrame = self
			self:visible(false)
		end,
		RefreshCommand = function(self)
			for i, row in ipairs(OptionRows) do
				local rowBG = self:GetChild("RowBG"..i)
				local label = self:GetChild("Label"..i)
				local value = self:GetChild("Value"..i)
				if rowBG then
					rowBG:diffuse(i == MenuRow and color("#333366") or color("#00000000"))
				end
				if label then
					label:diffuse(i == MenuRow and Color.White or color("#888888"))
				end
				if value then
					local ch = row.choices[row.selected]
					value:settext(ch and ch.label or "")
					value:diffuse(i == MenuRow and Color.White or color("#aaaaaa"))
				end
			end
		end,

		-- Border
		Def.Quad{
			InitCommand = function(self)
				self:xy(MENU_X, centerY)
					:zoomto(MENU_W + 2, totalH + 2)
					:diffuse(color("#444466"))
			end,
		},
		-- Background
		Def.Quad{
			InitCommand = function(self)
				self:xy(MENU_X, centerY)
					:zoomto(MENU_W, totalH)
					:diffuse(color("#0a0a18"))
					:diffusealpha(0.95)
			end,
		},
		-- Title
		LoadFont("Common Normal") .. {
			InitCommand = function(self)
				self:xy(MENU_X, topY + MENU_PAD + 14)
					:zoom(0.7)
					:settext("OPTIONS")
					:diffuse(Color.White)
					:shadowlength(1)
			end,
		},
		-- Divider line under title
		Def.Quad{
			InitCommand = function(self)
				self:xy(MENU_X, topY + MENU_PAD + 32)
					:zoomto(MENU_W - 24, 1)
					:diffuse(color("#444466"))
			end,
		},
	}

	-- Option rows
	for i, row in ipairs(OptionRows) do
		local rowY = topY + MENU_PAD + 36 + (i - 1) * MENU_ROW_H + MENU_ROW_H/2

		-- Row highlight
		m[#m+1] = Def.Quad{
			Name = "RowBG"..i,
			InitCommand = function(self)
				self:xy(MENU_X, rowY)
					:zoomto(MENU_W - 8, MENU_ROW_H - 4)
					:diffuse(color("#00000000"))
			end,
		}
		-- Label
		m[#m+1] = LoadFont("Common Normal") .. {
			Name = "Label"..i,
			InitCommand = function(self)
				self:xy(MENU_X - MENU_W/2 + MENU_PAD + 8, rowY)
					:zoom(0.6)
					:halign(0)
					:settext(row.name)
					:diffuse(color("#888888"))
					:shadowlength(1)
			end,
		}
		-- Value with arrows
		m[#m+1] = LoadFont("Common Normal") .. {
			Name = "Value"..i,
			InitCommand = function(self)
				self:xy(MENU_X + MENU_W/2 - MENU_PAD - 8, rowY)
					:zoom(0.55)
					:halign(1)
					:settext(row.choices[row.selected].label)
					:maxwidth(220/0.55)
					:diffuse(color("#aaaaaa"))
					:shadowlength(1)
			end,
		}
	end

	-- Arrow indicators
	m[#m+1] = LoadFont("Common Normal") .. {
		Name = "ArrowL",
		InitCommand = function(self)
			self:xy(MENU_X + 40, 0):zoom(0.6):settext("<"):diffuse(color("#666688"))
		end,
		RefreshCommand = function(self)
			local rowY = topY + MENU_PAD + 36 + (MenuRow - 1) * MENU_ROW_H + MENU_ROW_H/2
			self:y(rowY)
		end,
	}
	m[#m+1] = LoadFont("Common Normal") .. {
		Name = "ArrowR",
		InitCommand = function(self)
			self:xy(MENU_X + MENU_W/2 - MENU_PAD + 4, 0):zoom(0.6):settext(">"):diffuse(color("#666688"))
		end,
		RefreshCommand = function(self)
			local rowY = topY + MENU_PAD + 36 + (MenuRow - 1) * MENU_ROW_H + MENU_ROW_H/2
			self:y(rowY)
		end,
	}

	-- Footer hint
	m[#m+1] = LoadFont("Common Normal") .. {
		InitCommand = function(self)
			local footY = topY + MENU_PAD + 36 + numRows * MENU_ROW_H + MENU_PAD + 8
			self:xy(MENU_X, footY)
				:zoom(0.38)
				:settext("Select/Start: Confirm   Back: Cancel")
				:diffuse(color("#555566"))
				:shadowlength(1)
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

		-- Restore cursor state from previous visit
		if GalaxyCursorState.OpenGroup then
			OpenGroup = GalaxyCursorState.OpenGroup
		end

		FlatList = BuildFlatList()

		-- Try to restore cursor position
		local restored = false
		if GalaxyCursorState.SongDir then
			for i, item in ipairs(FlatList) do
				if type(item) == "table" and item[1]:GetSongDir() == GalaxyCursorState.SongDir then
					Cursor = i
					restored = true
					break
				end
			end
		elseif GalaxyCursorState.GroupName then
			for i, item in ipairs(FlatList) do
				if type(item) == "string" and item == GalaxyCursorState.GroupName then
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

		-- Per-frame animation: shift ActorFrame y along cubic curve
		self:SetUpdateFunction(function(af, dt)
			if not AnimActive then return end
			AnimTime = AnimTime + dt
			if AnimTime >= ANIM_DUR then
				VisualOffset = 0
				AnimActive = false
				af:y(0)
				return
			end
			local s = AnimTime / ANIM_DUR
			VisualOffset = EvalCubic(s)
			af:y(VisualOffset)
		end)
	end,
	OffCommand = function(self)
		SaveCursorState()
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
outer[#outer+1] = MakeMenu()

-- ===== DIFFICULTY PICKER ACTOR =====
-- Centered overlay showing all available difficulties for the chosen song.
-- Max 6 difficulties (Beginner/Easy/Medium/Hard/Challenge/Edit).
local DIFF_ROW_H = 52
local DIFF_W     = 350
local MAX_DIFFS  = 6

local diffPicker = Def.ActorFrame{
	Name = "DiffPicker",
	InitCommand = function(self)
		DiffFrame = self
		self:visible(false)
	end,
	RefreshDiffCommand = function(self)
		local n = #DiffSteps
		local totalH = n * DIFF_ROW_H + 60
		local topY = SCREEN_CENTER_Y - totalH/2

		-- Update background size
		local bg = self:GetChild("DiffBG")
		local border = self:GetChild("DiffBorder")
		if bg then bg:y(SCREEN_CENTER_Y):zoomto(DIFF_W, totalH) end
		if border then border:y(SCREEN_CENTER_Y):zoomto(DIFF_W + 2, totalH + 2) end

		-- Update title
		local title = self:GetChild("DiffTitle")
		if title then
			local songName = DiffSong and DiffSong:GetDisplayMainTitle() or ""
			title:y(topY + 20):settext(songName)
		end

		-- Update rows
		for i = 1, MAX_DIFFS do
			local rowBG   = self:GetChild("DiffRowBG"..i)
			local label   = self:GetChild("DiffLabel"..i)
			local meter   = self:GetChild("DiffMeter"..i)
			if i <= n then
				local st = DiffSteps[i]
				local dc = GetDiffColor(st)
				local rowY = topY + 40 + (i - 1) * DIFF_ROW_H + DIFF_ROW_H/2
				if rowBG then
					rowBG:visible(true):y(rowY)
					rowBG:diffuse(i == DiffPickIdx and color("#333366") or color("#00000000"))
				end
				if label then
					label:visible(true):y(rowY)
					local short = ToEnumShortString(st:GetDifficulty())
					label:settext(short)
					label:diffuse(i == DiffPickIdx and dc or color("#888888"))
				end
				if meter then
					meter:visible(true):y(rowY)
					meter:settext(tostring(st:GetMeter()))
					meter:diffuse(i == DiffPickIdx and dc or color("#666666"))
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
			self:x(SCREEN_CENTER_X):zoomto(DIFF_W + 2, 200):diffuse(color("#444466"))
		end,
	},
	-- Background
	Def.Quad{
		Name = "DiffBG",
		InitCommand = function(self)
			self:x(SCREEN_CENTER_X):zoomto(DIFF_W, 200)
				:diffuse(color("#0a0a18")):diffusealpha(0.97)
		end,
	},
	-- Song title
	LoadFont("Common Normal") .. {
		Name = "DiffTitle",
		InitCommand = function(self)
			self:x(SCREEN_CENTER_X):zoom(0.6)
				:maxwidth(DIFF_W / 0.6 - 40)
				:diffuse(Color.White):shadowlength(1)
		end,
	},
}

-- Difficulty rows
for i = 1, MAX_DIFFS do
	-- Row highlight
	diffPicker[#diffPicker+1] = Def.Quad{
		Name = "DiffRowBG"..i,
		InitCommand = function(self)
			self:x(SCREEN_CENTER_X):zoomto(DIFF_W - 8, DIFF_ROW_H - 6)
				:visible(false)
		end,
	}
	-- Difficulty name
	diffPicker[#diffPicker+1] = LoadFont("Common Normal") .. {
		Name = "DiffLabel"..i,
		InitCommand = function(self)
			self:x(SCREEN_CENTER_X - DIFF_W/2 + 20):zoom(0.65)
				:halign(0):shadowlength(1):visible(false)
		end,
	}
	-- Meter number
	diffPicker[#diffPicker+1] = LoadFont("Common Normal") .. {
		Name = "DiffMeter"..i,
		InitCommand = function(self)
			self:x(SCREEN_CENTER_X + DIFF_W/2 - 20):zoom(0.7)
				:halign(1):shadowlength(1):visible(false)
		end,
	}
end

outer[#outer+1] = diffPicker
return outer
