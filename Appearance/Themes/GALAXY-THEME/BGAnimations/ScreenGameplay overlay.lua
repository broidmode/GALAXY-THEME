-- ScreenGameplay overlay — GALAXY gameplay system
-- Wires up 04 Scoring.lua and 04 GaugeState.lua to the engine.
-- Provides HUD: score, EX%, grade, and visual life bar.
-- Handles fail via PostScreenMessage("SM_BeginFailed").

-- ===== GAUGE BAR COLORS =====
-- Based on DDR-A3 Flare gauge textures (gold → coral → pink → magenta gradient)
local GaugeBarColors = {
	Normal        = color("#FFF200"),
	Flare1        = color("#0066FF"),
	Flare2        = color("#00FFFF"),
	Flare3        = color("#48FF00"),
	Flare4        = color("#FFBB00"),
	Flare5        = color("#EF5E36"),
	Flare6        = color("#CC0CDD"),
	Flare7        = color("#A9A9A9"),
	Flare8        = color("#DFDFDF"),
	Flare9        = color("#8F8686"),
	FlareEX       = color("#E89FEC"),
	FloatingFlare = color("#A7BFF4"),
	LIFE4         = color("#3399ff"),
	Risky         = color("#ff3333"),
}
local GaugeDangerColor = color("#8F8F8F")  -- gray when in danger
local GaugeFailColor   = color("#ff2222")  -- red on fail

-- Bar dimensions (width is computed per-player from style data to match play area)
local BAR_H      = 36     -- bar height (doubled from 18)
local BAR_Y      = 24     -- from top of screen
local BAR_BORDER = 2

-- Get the gauge key string for color lookup.
-- For FloatingFlare, returns the color for the *current* flare level
-- so the bar dynamically changes color as the player drops levels.
local function GetGaugeColorKey(pn)
	local gs = GaugeState[pn]
	if not gs then return "Normal" end
	if gs.gaugeType == "Normal" then return "Normal" end
	if gs.gaugeType == "LIFE4" then return "LIFE4" end
	if gs.gaugeType == "Risky" then return "Risky" end
	if gs.gaugeType == "FloatingFlare" then
		local cur = gs.floatingCurrent or 10
		if cur == 10 then return "FlareEX" end
		return "Flare" .. cur
	end
	if gs.gaugeType == "Flare" and gs.flareIndex then
		if gs.flareIndex == 10 then return "FlareEX" end
		return "Flare" .. gs.flareIndex
	end
	return "Normal"
end

local t = Def.ActorFrame{ Name = "GalaxyGameplay" }

-- ===== SYSTEM ACTOR =====
-- Invisible actor that hooks engine messages for scoring + gauge
t[#t+1] = Def.Actor{
	Name = "GameplaySystem",

	-- Initialize scoring + gauge state before notes start
	DoneLoadingNextSongMessageCommand = function(self)
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			InitScoreState(pn)
			InitGauge(pn)
		end
	end,

	-- Process every judgment: update score + gauge, handle fail
	JudgmentMessageCommand = function(self, params)
		local pn = params.Player
		if not pn then return end

		UpdateGauge(params, pn)

		-- When Fail is "Never" and gauge is depleted, freeze the score
		local failMode = (GalaxyOptions[pn] or {}).Fail or 1
		local gaugeDead = (failMode == 2) and GetGaugeFailed(pn)

		if not gaugeDead then
			UpdateScore(params, pn)
		end

		-- Broadcast score update for HUD
		MESSAGEMAN:Broadcast("GalaxyScoreChanged", {
			Player    = pn,
			Score     = GetDisplayScore(pn),
			EXPercent = GetEXPercent(pn),
		})

		-- Handle fail based on Fail setting
		local failMode = (GalaxyOptions[pn] or {}).Fail or 1  -- 1=Gauge,2=Never,3=Miss
		local shouldFail = false

		if failMode == 1 then
			-- Gauge: fail when gauge is depleted
			shouldFail = GetGaugeFailed(pn)
		elseif failMode == 3 then
			-- Miss: fail on any miss or dropped hold
			local tns = params.TapNoteScore
			local hns = params.HoldNoteScore
			if tns == 'TapNoteScore_Miss' then
				shouldFail = true
			elseif hns == 'HoldNoteScore_LetGo' then
				shouldFail = true
			end
		end
		-- failMode == 2 (Never): never trigger fail

		if shouldFail then
			-- Mark gauge as failed so evaluation/chart results see it
			if GaugeState[pn] then GaugeState[pn].failed = true end
			local screen = SCREENMAN:GetTopScreen()
			if screen then
				screen:PostScreenMessage('SM_BeginFailed', 0)
			end
		end
	end,
}

-- ===== COVER PERCENT LOOKUP =====
-- CoverPercent index → actual percentage: 1=0%, 2=5%, 3=10%, … 11=50%
local CoverPctValues = {}
do
	local idx = 1
	for i = 0, 50, 5 do
		CoverPctValues[idx] = i
		idx = idx + 1
	end
end

-- ===== LANE COVER QUADS (drawn ON TOP of notefield, behind HUD) =====
-- Hidden+ = top cover, Sudden+ = bottom cover, HidSud+ = both.
-- Cover % controls how much of the notefield height each cover takes.
for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local opts = GalaxyOptions[pn] or {}
	local coverType = opts.LaneCover or 1        -- 1=Off 2=Hidden+ 3=Sudden+ 4=HidSud+
	local pctIdx    = opts.CoverPercent or 1      -- index into CoverPctValues
	local pct       = (CoverPctValues[pctIdx] or 0) / 100  -- 0.0 – 0.5

	local style    = GAMESTATE:GetCurrentStyle(pn)
	local numCols  = style:ColumnsPerPlayer()
	local styleW   = style:GetWidth(pn)
	local coverW   = styleW * (numCols / 1.7)    -- same width as lane filter
	local coverH   = SCREEN_HEIGHT * pct

	local needHidden = (coverType == 2 or coverType == 4)  -- Hidden+ or HidSud+
	local needSudden = (coverType == 3 or coverType == 4)  -- Sudden+ or HidSud+

	if needHidden and coverH > 0 then
		t[#t+1] = Def.Quad{
			Name = "CoverHidden_" .. ToEnumShortString(pn),
			InitCommand = function(self)
				self:zoomto(coverW, coverH)
					:diffuse(color("#000000"))
					:diffusealpha(1)
					:visible(false)
			end,
			OnCommand = function(self)
				local screen = SCREENMAN:GetTopScreen()
				if not screen then return end
				local playerActor = screen:GetChild("Player" .. ToEnumShortString(pn))
				if not playerActor then return end
				local px = playerActor:GetX()
				-- Top cover: align top edge to top of screen
				self:xy(px, coverH / 2):visible(true)
			end,
		}
	end

	if needSudden and coverH > 0 then
		t[#t+1] = Def.Quad{
			Name = "CoverSudden_" .. ToEnumShortString(pn),
			InitCommand = function(self)
				self:zoomto(coverW, coverH)
					:diffuse(color("#000000"))
					:diffusealpha(1)
					:visible(false)
			end,
			OnCommand = function(self)
				local screen = SCREENMAN:GetTopScreen()
				if not screen then return end
				local playerActor = screen:GetChild("Player" .. ToEnumShortString(pn))
				if not playerActor then return end
				local px = playerActor:GetX()
				-- Bottom cover: align bottom edge to bottom of screen
				self:xy(px, SCREEN_HEIGHT - coverH / 2):visible(true)
			end,
		}
	end
end

-- ===== CONSTANT MODE ARROW VISIBILITY COVERS =====
-- When ArrowVis == 2 (Constant), a black cover hides notes that are more than
-- ConstantMs milliseconds away from the judgment line.  The cover edge is
-- recomputed every frame using the song's TimingData so it correctly handles
-- BPM changes, stops, and delays.
--
-- Layout (Normal / upscroll):
--   Receptor near top (Y~216).  Notes enter from bottom, scroll upward.
--     visible zone:  receptor → cutoffY
--     gradient fade: cutoffY  → fadeEndY   (transparent → opaque)
--     solid cover:   fadeEndY → SCREEN_HEIGHT
--
-- Layout (Reverse):
--   Receptor near bottom (Y~864).  Notes enter from top, scroll downward.
--     solid cover:   0        → fadeEndY
--     gradient fade: fadeEndY → cutoffY    (opaque → transparent)
--     visible zone:  cutoffY  → receptor
--
-- Per-frame Y offset calculation:
--   XMod / Real  → beat-based: TimingData:GetBeatFromElapsedTime converts
--                  the ConstantMs time window into a beat delta, accounting
--                  for all stops and BPM changes within that window.
--   CMod / MMod  → time-based: constant pixels-per-second, so the offset
--                  is a fixed screen distance for a given ConstantMs.

local ARROW_SPACING         = 64    -- NF pixels per beat ([ArrowEffects] metric)
local NF_ZOOM               = SCREEN_HEIGHT / 480  -- Player actor zoom (2.25 @1080p)
local RECEPTOR_NF_Y_NORMAL  = -161  -- ReceptorArrowsYStandard (NF coords, DDR-A3 value)
local RECEPTOR_NF_Y_REVERSE =  156  -- ReceptorArrowsYReverse  (NF coords, DDR-A3 value)
local CONST_FADE_MS         = 50    -- width of the gradient band in ms

-- Shared per-player: the cover zone boundaries (screen Y coords).
-- Written by the cover's SetUpdateFunction, read by the judgment mirror.
-- coverTop/coverBottom define the opaque region; if coverTop >= coverBottom, no cover.
local ConstantCoverZone = {}
for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	ConstantCoverZone[pn] = { active = false, coverTop = 0, coverBottom = 0 }
end

for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local style  = GAMESTATE:GetCurrentStyle(pn)
	local coverW = style:GetWidth(pn) * (style:ColumnsPerPlayer() / 1.7)

	-- Upvalues shared between setup and the per-frame update function
	local timingData = nil
	local cachedX    = 0
	local solidQuad  = nil   -- references set in InitCommand
	local fadeQuad   = nil

	----------------------------------------------------------------
	-- ComputeNFOffset(timeDeltaSec)
	-- Returns the NoteField-coordinate Y distance from the receptor
	-- to a note that is timeDeltaSec seconds in the future.
	--   CMod / MMod → constant pixels-per-second (scrollBPM / 60 * ARROW_SPACING)
	--   XMod / Real → beat-based via TimingData (handles stops & BPM changes)
	----------------------------------------------------------------
	local function ComputeNFOffset(timeDeltaSec)
		local po = GAMESTATE:GetPlayerState(pn)
			:GetPlayerOptions("ModsLevel_Current")

		if po:TimeSpacing() > 0 then
			-- CMod / MMod: constant scroll speed
			local scrollBPM = math.max(1, po:ScrollBPM())
			return timeDeltaSec * (scrollBPM / 60) * ARROW_SPACING
		else
			-- XMod / Real: beat-based positioning
			if not timingData then return 0 end
			local curTime   = GAMESTATE:GetCurMusicSeconds()
			local curBeat   = GAMESTATE:GetSongBeat()
			local cutBeat   = timingData:GetBeatFromElapsedTime(
								curTime + timeDeltaSec)
			local beatDelta = cutBeat - curBeat
			local xmod      = math.max(0.01, po:ScrollSpeed())
			return beatDelta * ARROW_SPACING * xmod
		end
	end

	t[#t+1] = Def.ActorFrame{
		Name = "ConstantCoverFrame_" .. ToEnumShortString(pn),

		OnCommand = function(self)
			-- Cache player X and timing data
			local screen = SCREENMAN:GetTopScreen()
			if not screen then return end
			local pa = screen:GetChild("Player" .. ToEnumShortString(pn))
			if not pa then return end
			cachedX = pa:GetX()
			local song = GAMESTATE:GetCurrentSong()
			if song then timingData = song:GetTimingData() end

			-- Grab child quad references
			solidQuad = self:GetChild("ConstantSolid_" .. ToEnumShortString(pn))
			fadeQuad  = self:GetChild("ConstantFade_" .. ToEnumShortString(pn))
			if solidQuad then solidQuad:x(cachedX) end
			if fadeQuad  then fadeQuad:x(cachedX)  end

			-- Per-frame update via SetUpdateFunction
			self:SetUpdateFunction(function(af, dt)
				if not solidQuad then return end

				local curOpts = GalaxyOptions[pn] or {}
				if (curOpts.ArrowVis or 1) ~= 2 then
					solidQuad:visible(false)
					if fadeQuad then fadeQuad:visible(false) end
					return
				end

				local constMs = math.max(0, curOpts.ConstantMs or 1000)
				local isRev = GAMESTATE:GetPlayerState(pn)
					:GetPlayerOptions("ModsLevel_Current"):Reverse() == 1

				-- Receptor screen Y
				local recNF = isRev and RECEPTOR_NF_Y_REVERSE
				                     or RECEPTOR_NF_Y_NORMAL
				local recY  = SCREEN_CENTER_Y + recNF * NF_ZOOM

				-- NF offset → screen pixels for the visibility window edge
				local mainPx   = ComputeNFOffset(constMs / 1000) * NF_ZOOM
				local fadePx   = ComputeNFOffset((constMs + CONST_FADE_MS) / 1000) * NF_ZOOM
				local fadeBand = math.max(0, fadePx - mainPx)

				local solidH, solidY, fadeH, fadeY

				if isRev then
					local cutY     = recY - mainPx
					local fadeEndY = cutY - fadeBand
					solidH = math.max(0, fadeEndY)
					solidY = solidH / 2
					fadeH  = math.max(0, cutY - fadeEndY)
					fadeY  = fadeEndY + fadeH / 2

					-- Cover zone includes gradient band: top of solid → cutY
					if solidH > 0 or fadeH > 0 then
						ConstantCoverZone[pn].active      = true
						ConstantCoverZone[pn].coverTop    = 0
						ConstantCoverZone[pn].coverBottom = cutY
					else
						ConstantCoverZone[pn].active = false
					end
				else
					local cutY     = recY + mainPx
					local fadeEndY = cutY + fadeBand
					solidH = math.max(0, SCREEN_HEIGHT - fadeEndY)
					solidY = fadeEndY + solidH / 2
					fadeH  = math.max(0, fadeEndY - cutY)
					fadeY  = cutY + fadeH / 2

					-- Cover zone includes gradient band: cutY → bottom of solid
					if solidH > 0 or fadeH > 0 then
						ConstantCoverZone[pn].active      = true
						ConstantCoverZone[pn].coverTop    = cutY
						ConstantCoverZone[pn].coverBottom = SCREEN_HEIGHT
					else
						ConstantCoverZone[pn].active = false
					end
				end

				-- Solid cover
				if solidH <= 0 then
					solidQuad:visible(false)
				else
					solidQuad:visible(true)
						:zoomto(coverW, solidH)
						:y(solidY)
				end

				-- Gradient fade
				if fadeQuad then
					if fadeH <= 0 then
						fadeQuad:visible(false)
					else
						fadeQuad:visible(true)
							:zoomto(coverW, fadeH)
							:y(fadeY)
						if isRev then
							fadeQuad:diffuseupperleft({0,0,0,1}):diffuseupperright({0,0,0,1})
								:diffuselowerleft({0,0,0,0}):diffuselowerright({0,0,0,0})
						else
							fadeQuad:diffuseupperleft({0,0,0,0}):diffuseupperright({0,0,0,0})
								:diffuselowerleft({0,0,0,1}):diffuselowerright({0,0,0,1})
						end
					end
				end
			end)
		end,

		DoneLoadingNextSongMessageCommand = function(self)
			local song = GAMESTATE:GetCurrentSong()
			if song then timingData = song:GetTimingData() end
		end,

		-- Solid cover child
		Def.Quad{
			Name = "ConstantSolid_" .. ToEnumShortString(pn),
			InitCommand = function(self)
				self:diffuse(color("#000000")):visible(false)
			end,
		},

		-- Gradient fade child
		Def.Quad{
			Name = "ConstantFade_" .. ToEnumShortString(pn),
			InitCommand = function(self)
				self:visible(false)
			end,
		},
	}
end

-- ===== JUDGMENT / COMBO OVERLAY MIRROR (Constant Mode) =====
-- When the constant cover hides notes beyond the visibility window, the
-- engine's judgment and combo (drawn within the Player actor) are also
-- occluded.  These overlay copies mirror the engine graphics and are
-- cropped per-frame to only appear within the covered zone.
--
-- The engine's built-in judgment/combo remain visible in the uncovered zone.
-- Together the two copies create a seamless display across both zones.

-- Scale factors: engine uses 0.28 in NF coords → overlay uses 0.28 × NF_ZOOM
local OV_JUDGE_ZOOM   = 0.28 * NF_ZOOM
local OV_FS_ZOOM      = 0.28 * NF_ZOOM
local OV_DIGIT_ZOOM   = 0.28 * NF_ZOOM
local OV_DIGIT_GAP    = 20 * NF_ZOOM    -- DIGIT_GAP in screen px
local OV_DIGIT_RISE   = -0.15           -- vertical rise per digit (fraction)
local OV_PULSE_MULT   = 1.10            -- combo pop-in scale factor

-- Texture frame heights (source-art pixels)
local OV_JUDGE_FRAME_H = 256  -- Judgment 1x5: each frame is 256 px tall
local OV_FS_FRAME_H    = 256  -- FastSlow 1x2: each frame is 256 px tall
local OV_DIGIT_FRAME_H = 128  -- combo 10x1:   each digit is 128 px tall

-- Texture paths (absolute so the engine doesn't resolve relative to BGAnimations)
local _td          = THEME:GetCurrentThemeDirectory()
local OV_JUDGE_TEX = _td .. "Graphics/Player judgment/Judgment 1x5.png"
local OV_FS_TEX    = _td .. "Graphics/Player judgment/FastSlow 1x2.png"
local OV_COMBO_TEX = _td .. "Graphics/Player combo/combo 10x1.png"

-- TNS → spritesheet frame index (mirrors engine judgment)
local OvTNS = {
	TapNoteScore_W1 = 0, TapNoteScore_W2 = 1, TapNoteScore_W3 = 2,
	TapNoteScore_W4 = 3, TapNoteScore_W5 = 4, TapNoteScore_Miss = 4,
}

-- TNS → overlay animation (zoom is in screen space)
local OvJAnims = {
	TapNoteScore_W1 = function(s)
		s:finishtweening():diffusealpha(1)
		 :zoom(OV_JUDGE_ZOOM*1.03):linear(0.036)
		 :zoom(OV_JUDGE_ZOOM):sleep(0.434):diffusealpha(0) end,
	TapNoteScore_W2 = function(s)
		s:finishtweening():diffusealpha(1)
		 :zoom(OV_JUDGE_ZOOM*1.03):linear(0.036)
		 :zoom(OV_JUDGE_ZOOM):sleep(0.434):diffusealpha(0) end,
	TapNoteScore_W3 = function(s)
		s:finishtweening():diffusealpha(1)
		 :zoom(OV_JUDGE_ZOOM*1.03):linear(0.036)
		 :zoom(OV_JUDGE_ZOOM):sleep(0.434):diffusealpha(0) end,
	TapNoteScore_W4 = function(s)
		s:finishtweening():diffusealpha(1)
		 :zoom(OV_JUDGE_ZOOM*1.03):linear(0.036)
		 :zoom(OV_JUDGE_ZOOM):sleep(0.434):diffusealpha(0) end,
	TapNoteScore_W5 = function(s)
		s:finishtweening():diffusealpha(1)
		 :zoom(OV_JUDGE_ZOOM*0.94):sleep(0.5):diffusealpha(0) end,
	TapNoteScore_Miss = function(s)
		s:finishtweening():diffusealpha(1)
		 :zoom(OV_JUDGE_ZOOM*0.94):sleep(0.5):diffusealpha(0) end,
}

-- Combo tier colours (mirrors engine combo)
local OvTierColors = {
	[1] = color("#FFE9F6"),  -- W1 Marvelous
	[2] = color("#F5E349"),  -- W2 Perfect
	[3] = color("#0DFD74"),  -- W3 Great
	[4] = color("#4593FF"),  -- W4 Good
}
local OvTierMap = {
	TapNoteScore_W1 = 1, TapNoteScore_W2 = 2,
	TapNoteScore_W3 = 3, TapNoteScore_W4 = 4,
}

--- Crop a sprite to the intersection of its bounds and the cover zone.
--- @param spr    Sprite actor
--- @param scrY   Sprite center screen Y
--- @param texH   Source-art frame height (px)
--- @param covTop Cover zone top edge (screen Y)
--- @param covBot Cover zone bottom edge (screen Y)
local function CropSpriteToZone(spr, scrY, texH, covTop, covBot)
	local z = spr:GetZoomY()
	if z <= 0 then z = 0.001 end
	local h   = texH * z
	local top = scrY - h / 2
	local bot = scrY + h / 2
	local ct  = math.max(0, (covTop - top) / h)
	local cb  = math.max(0, (bot - covBot) / h)
	if ct + cb >= 1 then
		spr:croptop(0):cropbottom(1)   -- fully outside → hide
	else
		spr:croptop(ct):cropbottom(cb)
	end
end

local OV_MAX_DIGITS = 5
local OvShowComboAt = THEME:GetMetric("Combo", "ShowComboAt")

for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local shortPN = ToEnumShortString(pn)

	-- Sprite references (set during InitCommand of children)
	local jSpr   = nil   -- judgment overlay sprite
	local fSpr   = nil   -- fast/slow overlay sprite
	local dSprs  = {}    -- combo digit sprites [1..OV_MAX_DIGITS]
	local ovWorst = 0    -- worst judgment tier in current combo run

	-- Cached screen-Y positions (set in OnCommand, constant during play)
	local jScrY = 0
	local fScrY = 0
	local cScrY = 0   -- combo base screen Y

	-- Read JudgePosition → NF offset (0 for Near, ±100 for Far)
	local function OvJudgeNfOff()
		local opts = GalaxyOptions and GalaxyOptions[pn]
		local pos  = opts and opts.JudgePosition or 1
		local isRev = GAMESTATE:GetPlayerState(pn)
			:GetPlayerOptions("ModsLevel_Current"):Reverse() == 1
		if pos == 2 then return isRev and -100 or 100 end
		return 0
	end

	-- Read FastSlow toggle for this player
	local function OvShowFS()
		local opts = GalaxyOptions and GalaxyOptions[pn]
		if opts then return opts.FastSlow == 1 end
		return true
	end

	local ovFrame = Def.ActorFrame{
		Name = "OverlayMirror_" .. shortPN,

		OnCommand = function(self)
			-- Match Player actor X; frame Y stays 0 (children use screen Y)
			local screen = SCREENMAN:GetTopScreen()
			local pp = screen and screen:GetChild("Player" .. shortPN)
			self:x(pp and pp:GetX() or SCREEN_CENTER_X)

			-- Cache screen-Y positions (account for reverse)
			local isRev = GAMESTATE:GetPlayerState(pn)
				:GetPlayerOptions("ModsLevel_Current"):Reverse() == 1
			local judgeNf = (isRev and 30 or -30) + OvJudgeNfOff()
			local fsOff   = isRev and -25 or 25
			local comboNf = isRev and -30 or 30

			jScrY = SCREEN_CENTER_Y + judgeNf * NF_ZOOM
			fScrY = SCREEN_CENTER_Y + (judgeNf + fsOff) * NF_ZOOM
			cScrY = SCREEN_CENTER_Y + comboNf * NF_ZOOM

			if jSpr then jSpr:y(jScrY) end
			if fSpr then fSpr:y(fScrY) end
			-- (combo digits are positioned when ComboChanged fires)

			-- Per-frame crop update
			self:SetUpdateFunction(function()
				local zone = ConstantCoverZone[pn]
				if not zone or not zone.active then
					-- No cover → crop everything to invisible
					if jSpr then jSpr:croptop(0):cropbottom(1) end
					if fSpr then fSpr:croptop(0):cropbottom(1) end
					for i = 1, OV_MAX_DIGITS do
						if dSprs[i] then dSprs[i]:croptop(0):cropbottom(1) end
					end
					return
				end

				local cT, cB = zone.coverTop, zone.coverBottom
				if jSpr then CropSpriteToZone(jSpr, jScrY, OV_JUDGE_FRAME_H, cT, cB) end
				if fSpr then CropSpriteToZone(fSpr, fScrY, OV_FS_FRAME_H,    cT, cB) end
				for i = 1, OV_MAX_DIGITS do
					local d = dSprs[i]
					if d and d:GetVisible() then
						-- d:GetY() is screen Y (frame y = 0)
						CropSpriteToZone(d, d:GetY(), OV_DIGIT_FRAME_H, cT, cB)
					end
				end
			end)
		end,

		-- Mirror judgment display on JudgmentMessage (globally broadcast)
		JudgmentMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			if params.HoldNoteScore then return end

			-- Track worst tier for combo colouring
			local tier = OvTierMap[params.TapNoteScore]
			if tier then
				if ovWorst == 0 or tier > ovWorst then ovWorst = tier end
			end

			-- Mirror judgment sprite
			local fr = OvTNS[params.TapNoteScore]
			if not fr or not jSpr then return end
			jSpr:visible(true):setstate(fr)
			OvJAnims[params.TapNoteScore](jSpr)

			-- Mirror fast/slow indicator
			if fSpr and OvShowFS()
				and params.TapNoteScore ~= "TapNoteScore_W1"
				and params.TapNoteScore ~= "TapNoteScore_W5"
				and params.TapNoteScore ~= "TapNoteScore_Miss"
				and params.TapNoteScore ~= "TapNoteScore_HitMine"
				and params.TapNoteScore ~= "TapNoteScore_AvoidMine"
			then
				fSpr:finishtweening():visible(true)
				fSpr:setstate(params.Early and 0 or 1)
				fSpr:diffusealpha(1):zoom(OV_FS_ZOOM * 1.08)
					:linear(0.05):zoom(OV_FS_ZOOM)
					:sleep(0.4):diffusealpha(0)
			end
		end,

		-- Mirror combo display on ComboChanged (globally broadcast)
		ComboChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end

			local pss   = params.PlayerStageStats
			local combo = pss and pss:GetCurrentCombo() or 0

			if combo < OvShowComboAt then
				-- Combo broken or below threshold
				ovWorst = 0
				for i = 1, OV_MAX_DIGITS do
					if dSprs[i] then dSprs[i]:visible(false) end
				end
				return
			end

			local col   = OvTierColors[ovWorst] or color("#FFFFFF")
			local str   = tostring(combo)
			local n     = #str
			local totalW = (n - 1) * OV_DIGIT_GAP
			local x0    = -totalW / 2
			local yStep = OV_DIGIT_GAP * OV_DIGIT_RISE

			for i = 1, OV_MAX_DIGITS do
				local d = dSprs[i]
				if not d then break end
				if i <= n then
					d:visible(true)
					d:setstate(tonumber(str:sub(i, i)))
					d:x(x0 + (i - 1) * OV_DIGIT_GAP)
					d:y(cScrY + (i - 1) * yStep)
					d:diffuse(col)
					d:stoptweening()
					d:zoom(OV_DIGIT_ZOOM * OV_PULSE_MULT)
					d:linear(0.05)
					d:zoom(OV_DIGIT_ZOOM)
				else
					d:visible(false)
				end
			end
		end,

		-- Judgment overlay sprite
		Def.Sprite{
			Name    = "OvJudge_" .. shortPN,
			InitCommand = function(self)
				jSpr = self
				self:Load(OV_JUDGE_TEX)
				self:animate(false):visible(false):diffusealpha(0)
			end,
		},

		-- Fast/slow overlay sprite
		Def.Sprite{
			Name    = "OvFS_" .. shortPN,
			InitCommand = function(self)
				fSpr = self
				self:Load(OV_FS_TEX)
				self:animate(false):visible(false):diffusealpha(0)
			end,
		},
	}

	-- Combo digit overlay sprites
	for i = 1, OV_MAX_DIGITS do
		ovFrame[#ovFrame + 1] = Def.Sprite{
			Name    = "OvDigit" .. i .. "_" .. shortPN,
			InitCommand = function(self)
				dSprs[i] = self
				self:Load(OV_COMBO_TEX)
				self:animate(false):visible(false):zoom(OV_DIGIT_ZOOM)
			end,
		}
	end

	t[#t + 1] = ovFrame
end

-- ===== HUD ELEMENTS (per player) =====
for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local isP1 = (pn == PLAYER_1)
	-- Compute play-area width from style data (same formula as lane filter/covers)
	local style  = GAMESTATE:GetCurrentStyle(pn)
	local barW   = style:GetWidth(pn) * (style:ColumnsPerPlayer() / 1.7)
	-- Score text
	local scoreX = isP1 and 40 or (SCREEN_WIDTH - 40)
	local sideSign = isP1 and 1 or -1

	-- ===== LIFE BAR =====
	-- Wrapped in an ActorFrame centered on the player's notefield.
	local barFrame = Def.ActorFrame{
		Name = "LifeBar_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:y(BAR_Y)
		end,
		OnCommand = function(self)
			local screen = SCREENMAN:GetTopScreen()
			if not screen then return end
			local playerActor = screen:GetChild("Player" .. ToEnumShortString(pn))
			if not playerActor then return end
			self:x(playerActor:GetX())
		end,
	}
	-- Background (dark border)
	barFrame[#barFrame+1] = Def.Quad{
		Name = "BarBorder_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:zoomto(barW + BAR_BORDER*2, BAR_H + BAR_BORDER*2)
				:diffuse(color("#222233"))
		end,
	}
	-- Empty track
	barFrame[#barFrame+1] = Def.Quad{
		Name = "BarTrack_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:zoomto(barW, BAR_H)
				:diffuse(color("#0a0a12"))
		end,
	}
	-- Fill bar (left-aligned within the track)
	barFrame[#barFrame+1] = Def.Quad{
		Name = "BarFill_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:x(-barW/2)
				:halign(0)
				:zoomto(barW, BAR_H)
				:diffuse(GaugeBarColors.Normal)
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			-- Reset bar to initial state for this stage.
			-- InitGauge already ran (GameplaySystem handles DoneLoadingNextSong
			-- first in tree order) so GaugeState[pn] is valid here.
			local gs = GaugeState[pn]
			local key = GetGaugeColorKey(pn)
			local c = GaugeBarColors[key] or GaugeBarColors.Normal
			-- Set initial bar width from starting life
			local life = gs and gs.life or 0.5
			local gType = gs and gs.gaugeType or "Normal"
			if gType == "LIFE4" or gType == "Risky" then
				local maxL = gs.maxLives or 1
				life = maxL > 0 and (gs.life / maxL) or 0
			end
			local fillW = math.max(0, math.min(1, life)) * barW
			self:stoptweening():zoomto(fillW, BAR_H):diffuse(c)
		end,
		GalaxyLifeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			if params.Failed then
				self:stoptweening():linear(0.2)
					:zoomto(0, BAR_H)
					:diffuse(GaugeFailColor)
				return
			end
			-- Battery modes: map lives to bar width
			local life = params.Life or 0
			local gType = params.GaugeType
			if gType == "LIFE4" or gType == "Risky" then
				local maxL = params.MaxLives or 1
				life = maxL > 0 and (params.Life / maxL) or 0
			end
			local fillW = math.max(0, math.min(1, life)) * barW

			-- Color: use gauge color, but shift to gray in danger
			local key = GetGaugeColorKey(pn)
			local c = GaugeBarColors[key] or GaugeBarColors.Normal
			if life < 0.2 then
				c = GaugeDangerColor
			end

			self:stoptweening():linear(0.05)
				:zoomto(fillW, BAR_H)
				:diffuse(c)
		end,
	}

	-- Gauge type label (small text below the bar)
	barFrame[#barFrame+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
		Name = "GaugeLabel_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:y(BAR_H/2 + 12)
				:zoom(FONT_ZOOM):diffuse(color("#aaaaaa"))
			self:shadowlength(0)
			self:SetTextureFiltering(false)
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			self:settext(GetGaugeDisplayName(pn)):Regen()
		end,
		GalaxyLifeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			-- Always refresh the label so gauge type changes between stages are visible
			self:settext(GetGaugeDisplayName(pn)):Regen()
		end,
	}

	-- Life percentage text (overlaid on bar)
	barFrame[#barFrame+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
		Name = "BarPct_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:zoom(FONT_ZOOM):diffuse(Color.White)
			self:shadowlength(0)
			self:SetTextureFiltering(false)
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			-- Show initial life value (covers the gap before first judgment)
			local gs = GaugeState[pn]
			if not gs then return end
			local gType = gs.gaugeType
			if gType == "LIFE4" or gType == "Risky" then
				local lives = math.floor(gs.life)
				self:settext(lives .. " / " .. (gs.maxLives or 0)):Regen()
			else
				local pct = math.floor((gs.life or 0) * 100 + 0.5)
				self:settext(pct .. "%"):Regen()
			end
		end,
		GalaxyLifeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			if params.Failed then
				self:settext("FAILED"):Regen()
				return
			end
			local gType = params.GaugeType
			if gType == "LIFE4" or gType == "Risky" then
				local lives = math.floor(params.Life)
				self:settext(lives .. " / " .. (params.MaxLives or 0)):Regen()
			else
				local pct = math.floor((params.Life or 0) * 100 + 0.5)
				self:settext(pct .. "%"):Regen()
			end
		end,
	}
	t[#t+1] = barFrame

	-- Score display
	t[#t+1] = Def.Text{ Font = RodinPath("db"), Size = FontL("db"), Text = "",
		Name = "Score_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(scoreX, BAR_Y)
				:zoom(FONT_ZOOM):diffuse(Color.White)
			self:halign(isP1 and 0 or 1):settext("0"):Regen():shadowlength(0)
			self:SetTextureFiltering(false)
		end,
		GalaxyScoreChangedMessageCommand = function(self, params)
			if params.Player == pn then
				self:settext(string.format("%d", params.Score)):Regen()
			end
		end,
	}

	-- EX Score display
	t[#t+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
		Name = "EX_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(scoreX, BAR_Y + 24)
				:zoom(FONT_ZOOM):diffuse(color("#aaaaff"))
			self:halign(isP1 and 0 or 1):settext("EX 0.00%"):Regen():shadowlength(0)
			self:SetTextureFiltering(false)
		end,
		GalaxyScoreChangedMessageCommand = function(self, params)
			if params.Player == pn then
				self:settext(string.format("EX %.2f%%", params.EXPercent)):Regen()
			end
		end,
	}

	-- Grade display
	t[#t+1] = Def.Text{ Font = RodinPath("db"), Size = FontM("db"), Text = "",
		Name = "Grade_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(scoreX + sideSign * 120, BAR_Y)
				:zoom(FONT_ZOOM):diffuse(color("#ffcc00"))
			self:halign(0.5):shadowlength(0)
			self:SetTextureFiltering(false)
		end,
		GalaxyScoreChangedMessageCommand = function(self, params)
			if params.Player == pn then
				self:settext(GetCurrentGrade(pn)):Regen()
			end
		end,
	}
end

return t
