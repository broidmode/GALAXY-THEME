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
local POOL_CARDS   = 30    -- enough to fill screen + margin
local POOL_HEADERS = 8

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

local function ComputeVisibleItems()
	local n = #FlatList
	if n == 0 then return {} end

	local result = {}

	-- === Find the start of cursor's row ===
	-- Walk backwards from cursor to find the first item in this row
	-- (either col==1 or a group header or beginning)
	local rowStart = Cursor
	while true do
		local prevWi = Wrap(rowStart - 1)
		if not IsSong(prevWi) then break end
		if GetSongColLocal(prevWi) >= GetSongColLocal(Wrap(rowStart)) then break end
		if rowStart - 1 == Cursor - n then break end
		rowStart = rowStart - 1
	end

	-- === Walk FORWARD from row start ===
	local y = 0
	local visited = 0
	local idx = rowStart
	while y < RENDER_MARGIN and visited < n do
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

	while (-y) < RENDER_MARGIN and visited < n do
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
local function Refresh()
	if #FlatList == 0 then return end

	local items = ComputeVisibleItems()

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
	Cursor = Wrap(Cursor + delta)
	if IsSong(Cursor) then
		GAMESTATE:SetCurrentSong(FlatList[Cursor][1])
	end
	SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
	Refresh()
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
	if OpenGroup == grp then
		if Cursor < #FlatList and IsSong(Cursor + 1) then
			Cursor = Cursor + 1
			GAMESTATE:SetCurrentSong(FlatList[Cursor][1])
		end
	end
	Refresh()
end

local function ConfirmSong()
	if Accepted or not IsSong(Cursor) then return end
	local entry = FlatList[Cursor]
	GAMESTATE:SetCurrentSong(entry[1])
	GAMESTATE:SetCurrentPlayMode("PlayMode_Regular")
	for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
		GAMESTATE:SetCurrentSteps(pn, entry[2])
	end
	Accepted = true
	SOUND:PlayOnce(THEME:GetPathS("Common","Start"))
	SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
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

-- ===== BUILD ACTOR TREE =====
local t = Def.ActorFrame{
	Name = "GridBrowser",
	OnCommand = function(self)
		for i = 1, POOL_CARDS do
			CardPool[i] = self:GetChild("Card"..i)
		end
		for i = 1, POOL_HEADERS do
			HeaderPool[i] = self:GetChild("Header"..i)
		end

		FlatList = BuildFlatList()
		Cursor = 1
		OpenGroup = ""
		Accepted = false
		SCREENMAN:GetTopScreen():AddInputCallback(InputHandler)
		Refresh()
	end,
	OffCommand = function(self)
		SCREENMAN:GetTopScreen():RemoveInputCallback(InputHandler)
	end,
}

for i = 1, POOL_CARDS do
	t[#t+1] = MakeSongCard("Card"..i)
end
for i = 1, POOL_HEADERS do
	t[#t+1] = MakeGroupHeader("Header"..i)
end

return t
