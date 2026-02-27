-- ScreenSelectMusic overlay — Custom 3-column grid song browser
-- No MusicWheel. Pure Lua with SONGMAN/GAMESTATE APIs.
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
local POOL_CARDS   = 24    -- max visible song cards
local POOL_HEADERS = 6     -- max visible group headers

local GRID_X       = SCREEN_CENTER_X
local GRID_TOP     = 120

local totalColW    = CARD_W + COL_GAP
local totalRowH    = CARD_H + ROW_GAP

-- ===== STATE =====
local FlatList     = {}
local Cursor       = 1
local OpenGroup    = ""
local ScrollOffset = 0
local Accepted     = false

-- Actor pool references (filled in OnCommand)
local CardPool     = {}
local HeaderPool   = {}
local RootActor    = nil

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

local function IsGroup(idx)
	return type(FlatList[idx]) == "string"
end

local function IsSong(idx)
	return type(FlatList[idx]) == "table"
end

-- ===== LAYOUT =====
-- Returns layoutInfo[i] = { y, type, col } for every item.
-- y is in grid-local coordinates (before scrolling).
local function ComputeLayout()
	local layout = {}
	local y = 0
	local songCount = 0

	for i = 1, #FlatList do
		if IsGroup(i) then
			if songCount > 0 then
				y = y + totalRowH
				songCount = 0
			end
			layout[i] = { y = y, type = "group", col = 0 }
			y = y + HEADER_H + ROW_GAP
		else
			songCount = songCount + 1
			local col = ((songCount - 1) % COLS) + 1
			layout[i] = { y = y, type = "song", col = col }
			if col == COLS then
				y = y + totalRowH
				songCount = 0
			end
		end
	end
	return layout
end

-- ===== SCROLL =====
local function UpdateScroll(layout)
	if not layout[Cursor] then return end
	local curY = layout[Cursor].y
	local viewH = 5 * totalRowH
	local target = curY - viewH / 2 + totalRowH / 2
	ScrollOffset = math.max(0, target)
end

-- ===== RENDER =====
local function Refresh()
	local layout = ComputeLayout()
	UpdateScroll(layout)

	-- Hide everything
	for i = 1, POOL_CARDS do
		CardPool[i]:visible(false)
	end
	for i = 1, POOL_HEADERS do
		HeaderPool[i]:visible(false)
	end

	local ci = 1  -- card pool index
	local hi = 1  -- header pool index

	for i = 1, #FlatList do
		local info = layout[i]
		if not info then break end
		local screenY = GRID_TOP + info.y - ScrollOffset

		-- Cull items outside viewport
		if screenY > -(CARD_H + 50) and screenY < SCREEN_HEIGHT + CARD_H then
			if info.type == "group" and hi <= POOL_HEADERS then
				local a = HeaderPool[hi]
				a:visible(true)
				a:xy(GRID_X, screenY)
				a:playcommand("SetHeader", {
					Text = FlatList[i],
					HasFocus = (i == Cursor),
					IsOpen = (FlatList[i] == OpenGroup),
				})
				hi = hi + 1
			elseif info.type == "song" and ci <= POOL_CARDS then
				local a = CardPool[ci]
				a:visible(true)
				local xOff = (info.col - 2) * totalColW
				a:xy(GRID_X + xOff, screenY)
				local entry = FlatList[i]
				a:playcommand("SetCard", {
					Song = entry[1],
					Steps = entry[2],
					HasFocus = (i == Cursor),
				})
				ci = ci + 1
			end
		end
	end
end

-- ===== NAVIGATION =====
local function MoveCursor(delta)
	if Accepted then return end
	local newPos = Cursor + delta
	newPos = math.max(1, math.min(#FlatList, newPos))
	if newPos ~= Cursor then
		Cursor = newPos
		if IsSong(Cursor) then
			GAMESTATE:SetCurrentSong(FlatList[Cursor][1])
		end
		SOUND:PlayOnce(THEME:GetPathS("","_switch down"))
		Refresh()
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
	-- Find the header again
	for i = 1, #FlatList do
		if IsGroup(i) and FlatList[i] == grp then
			Cursor = i
			break
		end
	end
	-- If opened, move cursor to first song
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
			-- Try to jump one row down (3 items)
			local target = Cursor + COLS
			if target <= #FlatList and IsSong(target) then
				MoveCursor(COLS)
			else
				-- Move to last song in this group
				local last = Cursor
				while last < #FlatList and IsSong(last + 1) do
					last = last + 1
				end
				if last > Cursor then
					MoveCursor(last - Cursor)
				else
					-- Move to next group header
					MoveCursor(1)
				end
			end
		else
			MoveCursor(1)
		end
		return true
	elseif btn == "MenuUp" then
		if IsSong(Cursor) then
			-- Find start of songs in this group
			local groupStart = Cursor
			while groupStart > 1 and IsSong(groupStart - 1) do
				groupStart = groupStart - 1
			end
			local target = Cursor - COLS
			if target >= groupStart then
				MoveCursor(-COLS)
			else
				-- Move to first song in group
				if Cursor > groupStart then
					MoveCursor(-(Cursor - groupStart))
				else
					-- On first row already, go to group header
					MoveCursor(-1)
				end
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
			InitCommand = function(self)
				self:y(-18)
			end,
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
		-- Collect pool references by name
		for i = 1, POOL_CARDS do
			CardPool[i] = self:GetChild("Card"..i)
		end
		for i = 1, POOL_HEADERS do
			HeaderPool[i] = self:GetChild("Header"..i)
		end

		-- Initialize
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
