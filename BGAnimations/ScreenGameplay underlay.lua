-- ScreenGameplay underlay — Lane visibility filter & guideline beat bars
-- Drawn behind the notefield.  Reads GalaxyOptions[pn] for settings.

local t = Def.ActorFrame{ Name = "GalaxyUnderlay" }

-- Apply per-player timing options (DDR Modern disables W5)
t[#t+1] = Def.Actor{
	OnCommand = function(self) ApplyPerPlayerTimingOptions() end,
}

-- Lane visibility values: index → percentage (0–100)
local LaneVisValues = { [1]=0, [2]=10, [3]=20, [4]=30, [5]=40, [6]=50,
                         [7]=60, [8]=70, [9]=80, [10]=90, [11]=100 }

-- Guideline options: 1=On, 2=Off
-- Uses engine NoteField:SetBeatBars for beat-aligned guideline bars.

for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local opts = GalaxyOptions[pn] or {}

	-- ===== LANE VISIBILITY (screen filter) =====
	local visIdx = opts.LaneVis or 1
	local filterAlpha = (LaneVisValues[visIdx] or 0) / 100

	-- Compute notefield width for the filter
	local style = GAMESTATE:GetCurrentStyle(pn)
	local numCols = style:ColumnsPerPlayer()
	local styleW = style:GetWidth(pn)
	-- Scale width to cover columns with a bit of padding
	local filterW = styleW * (numCols / 1.7)

	-- Only add the filter quad if visibility > 0%
	if filterAlpha > 0 then
		t[#t+1] = Def.Quad{
			Name = "LaneFilter_" .. ToEnumShortString(pn),
			InitCommand = function(self)
				-- Start hidden; position is set in OnCommand once Player actor exists
				self:zoomto(filterW, SCREEN_HEIGHT)
					:diffuse(color("#000000"))
					:diffusealpha(filterAlpha)
					:fadeleft(1/32):faderight(1/32)
					:visible(false)
			end,
			OnCommand = function(self)
				-- Read the actual Player actor X position from the engine
				local screen = SCREENMAN:GetTopScreen()
				if not screen then return end
				local playerActor = screen:GetChild("Player" .. ToEnumShortString(pn))
				if not playerActor then return end
				local px = playerActor:GetX()
				self:xy(px, SCREEN_CENTER_Y):visible(true)
			end,
		}
	end

	-- ===== GUIDELINE (beat bars) =====
	local guideIdx = opts.Guideline or 1  -- 1=On, 2=Off

	if guideIdx == 1 then
		t[#t+1] = Def.Actor{
			Name = "GuidelineControl_" .. ToEnumShortString(pn),
			OnCommand = function(self)
				local screen = SCREENMAN:GetTopScreen()
				if not screen then return end
				local playerActor = screen:GetChild("Player" .. ToEnumShortString(pn))
				if not playerActor then return end
				local notefield = playerActor:GetChild("NoteField")
				if not notefield then return end

				notefield:SetBeatBars(true)
				notefield:SetBeatBarsAlpha(1, 0.25, 0, 0)
			end,
		}
	end
	-- ===== STEP ZONE (receptor visibility via Dark mod) =====
	-- StepZone: 1=On (show receptors), 2=Off (hide receptors)
	local stepZone = opts.StepZone or 1
	if stepZone == 2 then
		t[#t+1] = Def.Actor{
			Name = "StepZoneOff_" .. ToEnumShortString(pn),
			OnCommand = function(self)
				GAMESTATE:GetPlayerState(pn)
					:GetPlayerOptions("ModsLevel_Song"):Dark(1)
				GAMESTATE:GetPlayerState(pn)
					:GetPlayerOptions("ModsLevel_Current"):Dark(1)
			end,
		}
	end
end

return t
