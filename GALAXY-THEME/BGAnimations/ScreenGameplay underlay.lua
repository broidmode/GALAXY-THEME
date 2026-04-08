-- ScreenGameplay underlay — Lane visibility filter & guideline beat bars
-- Drawn behind the notefield.  Reads GalaxyOptions[pn] for settings.

local t = Def.ActorFrame{ Name = "GalaxyUnderlay" }

-- Lane visibility values: index → percentage (0–100)
local LaneVisValues = { [1]=0, [2]=10, [3]=20, [4]=30, [5]=40, [6]=50,
                         [7]=60, [8]=70, [9]=80, [10]=90, [11]=100 }

-- Guideline options: 1=Center, 2=Border, 3=Off
-- We use engine NoteField:SetBeatBars for "Center" style guidelines.
-- "Border" draws thin lines at the edges of the notefield.

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
	local guideIdx = opts.Guideline or 1  -- 1=Center, 2=Border, 3=Off

	if guideIdx == 1 or guideIdx == 2 then
		-- Enable engine beat bars on the NoteField after it's loaded
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
				notefield:SetStopBars(true)
				notefield:SetBpmBars(true)

				-- Set alpha values: measure lines prominent, 4th subtle, 8th/16th off
				if guideIdx == 1 then
					-- Center: lines through the center of notes
					notefield:SetBeatBarsAlpha(1, 0.25, 0, 0)
				else
					-- Border: shift bars up so thick line sits just above the on-beat
					-- This frames notes between lines rather than bisecting them.
					-- -30 at 720p, scaled proportionally for the actual display height.
					local offset = -30 * (DISPLAY:GetDisplayHeight() / 720)
					notefield:SetBeatBarOffset(offset)
					notefield:SetBeatBarsAlpha(1, 0.25, 0, 0)
				end
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
