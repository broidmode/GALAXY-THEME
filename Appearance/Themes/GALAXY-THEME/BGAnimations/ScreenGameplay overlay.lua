-- ScreenGameplay overlay — GALAXY gameplay system
-- Wires up 04 Scoring.lua and 04 GaugeState.lua to the engine.
-- Provides HUD: score, EX%, grade, and visual life bar.
-- Handles fail via PostScreenMessage("SM_BeginFailed").

-- ===== GAUGE BAR COLORS =====
-- Based on DDR-A3 Flare gauge textures (gold → coral → pink → magenta gradient)
local GaugeBarColors = {
	Normal        = color("#22cc44"),   -- green
	Flare1        = color("#C1A62B"),   -- gold
	Flare2        = color("#C9A033"),   -- warm gold
	Flare3        = color("#D49842"),   -- amber
	Flare4        = color("#DD9152"),   -- gold-orange
	Flare5        = color("#E8866C"),   -- coral
	Flare6        = color("#EF7E89"),   -- pink-coral
	Flare7        = color("#ED7AA2"),   -- rose
	Flare8        = color("#EB73CA"),   -- hot pink
	Flare9        = color("#E86FE9"),   -- magenta-violet
	FlareEX       = color("#FFD700"),   -- bright gold (rainbow in A3)
	FloatingFlare = color("#FFD700"),   -- same bright gold
	LIFE4         = color("#3399ff"),   -- blue
	Risky         = color("#ff3333"),   -- red
}
local GaugeDangerColor = color("#8F8F8F")  -- gray when in danger
local GaugeFailColor   = color("#ff2222")  -- red on fail

-- Bar dimensions and position (similar to A3: top of screen, near notefield)
local BAR_W      = 300
local BAR_H      = 18
local BAR_Y      = 24     -- from top of screen
local BAR_BORDER = 2

-- Get the gauge key string for color lookup
local function GetGaugeColorKey(pn)
	local gs = GaugeState[pn]
	if not gs then return "Normal" end
	if gs.gaugeType == "Normal" then return "Normal" end
	if gs.gaugeType == "LIFE4" then return "LIFE4" end
	if gs.gaugeType == "Risky" then return "Risky" end
	if gs.gaugeType == "FloatingFlare" then return "FloatingFlare" end
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
-- When ArrowVis == 2 (Constant), notes are hidden above a time-based threshold.
-- A solid black cover hides the "far" zone; a gradient quad fades notes in over
-- a 10ms window just before the threshold. Updates each frame via UpdateCommand.
-- The cover height is derived from the user's ConstantMs setting and the current
-- effective display BPM (CMod value or XMod * current song BPS * 60).
-- 4 display-beats are assumed to fill the full screen at the given speed,
-- matching the DDR reference: fullScreenMs = 240000 / displayBPM.
for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local opts = GalaxyOptions[pn] or {}
	if (opts.ArrowVis or 1) == 2 then
		local style  = GAMESTATE:GetCurrentStyle(pn)
		local coverW = style:GetWidth(pn) * (style:ColumnsPerPlayer() / 1.7)

		-- Shared state populated by the solid cover's UpdateCommand each frame,
		-- then consumed by the gradient quad's UpdateCommand (runs immediately after).
		local coverState = { coverH = 0, fadeH = 0, isReverse = false }
		local cachedX = 0  -- player center X; set once in OnCommand

		-- Solid cover: fully opaque, hides notes outside the constant window
		t[#t+1] = Def.Quad{
			Name = "ConstantSolid_" .. ToEnumShortString(pn),
			InitCommand = function(self)
				self:diffuse(color("#000000")):visible(false)
			end,
			OnCommand = function(self)
				local screen = SCREENMAN:GetTopScreen()
				if not screen then return end
				local pa = screen:GetChild("Player" .. ToEnumShortString(pn))
				if not pa then return end
				cachedX = pa:GetX()
				self:x(cachedX):visible(true)
			end,
			UpdateCommand = function(self, dt)
				local curOpts  = GalaxyOptions[pn] or {}
				local mode     = curOpts.SpeedMode or "Real"
				local displayBPM
				if mode == "XMod" then
					local curBPS = GAMESTATE:GetSongBPS()
					local rate   = (curOpts.SpeedRate or 100) / 100
					displayBPM   = curBPS * 60 * rate
				else
					-- Real, CMod, MMod: SpeedValue is the target BPM
					displayBPM = curOpts.SpeedValue or 200
				end
				displayBPM = math.max(1, displayBPM)

				-- 4 display-beats at displayBPM = total screen travel time in ms
				local fullScreenMs = 240000 / displayBPM
				local constMs      = math.max(0, curOpts.ConstantMs or 1000)
				local FADE_MS      = 10

				local visibleFrac = math.min(1, constMs / fullScreenMs)
				local hiddenFrac  = 1 - visibleFrac
				local fadeFrac    = math.min(visibleFrac, FADE_MS / fullScreenMs)

				local cH = SCREEN_HEIGHT * hiddenFrac
				local fH = SCREEN_HEIGHT * fadeFrac

				local isRev = GAMESTATE:GetPlayerState(pn):GetPlayerOptions("ModsLevel_Current"):Reverse() == 1
				coverState.coverH    = cH
				coverState.fadeH     = fH
				coverState.isReverse = isRev

				if cH <= 0 then
					self:visible(false)
				else
					self:visible(true):zoomto(coverW, cH)
					if isRev then
						-- Reverse: judgment at top, notes from bottom — cover the bottom
						self:y(SCREEN_HEIGHT - cH / 2)
					else
						-- Normal: judgment at bottom, notes from top — cover the top
						self:y(cH / 2)
					end
				end
			end,
		}

		-- Gradient fade zone: fades smoothly from the solid cover into the visible zone
		t[#t+1] = Def.Quad{
			Name = "ConstantFade_" .. ToEnumShortString(pn),
			InitCommand = function(self)
				self:visible(false)
			end,
			OnCommand = function(self)
				-- cachedX is already set by the solid cover's OnCommand (runs first)
				self:x(cachedX):visible(true)
			end,
			UpdateCommand = function(self, dt)
				local cH = coverState.coverH
				local fH = coverState.fadeH
				if fH <= 0 then
					self:visible(false)
					return
				end
				self:visible(true):zoomto(coverW, fH)
				if coverState.isReverse then
					-- Reverse: solid cover is at bottom; fade zone is above it
					-- Transparent at top (toward center of field), opaque at bottom (into cover)
					self:diffuseupperleft({0,0,0,0}):diffuseupperright({0,0,0,0})
						:diffuselowerleft({0,0,0,1}):diffuselowerright({0,0,0,1})
					self:y(SCREEN_HEIGHT - cH - fH / 2)
				else
					-- Normal: solid cover is at top; fade zone is below it
					-- Opaque at top (into cover), transparent at bottom (into visible zone)
					self:diffuseupperleft({0,0,0,1}):diffuseupperright({0,0,0,1})
						:diffuselowerleft({0,0,0,0}):diffuselowerright({0,0,0,0})
					self:y(cH + fH / 2)
				end
			end,
		}
	end
end

-- ===== HUD ELEMENTS (per player) =====
for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local isP1 = (pn == PLAYER_1)
	-- Bar X: left side for P1, right side for P2 (similar to A3's cx±231)
	local barX = isP1 and (SCREEN_CENTER_X - 231) or (SCREEN_CENTER_X + 231)
	-- Score text
	local scoreX = isP1 and 40 or (SCREEN_WIDTH - 40)
	local sideSign = isP1 and 1 or -1

	-- ===== LIFE BAR =====
	-- Background (dark track)
	t[#t+1] = Def.Quad{
		Name = "BarBorder_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(barX, BAR_Y)
				:zoomto(BAR_W + BAR_BORDER*2, BAR_H + BAR_BORDER*2)
				:diffuse(color("#222233"))
		end,
	}
	-- Empty track
	t[#t+1] = Def.Quad{
		Name = "BarTrack_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(barX, BAR_Y)
				:zoomto(BAR_W, BAR_H)
				:diffuse(color("#0a0a12"))
		end,
	}
	-- Fill bar (left-aligned within the track)
	t[#t+1] = Def.Quad{
		Name = "BarFill_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(barX - BAR_W/2, BAR_Y)
				:halign(0)
				:zoomto(BAR_W, BAR_H)
				:diffuse(color("#22cc44"))
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			-- Set initial color based on gauge type
			local key = GetGaugeColorKey(pn)
			local c = GaugeBarColors[key] or GaugeBarColors.Normal
			self:diffuse(c)
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
			local fillW = math.max(0, math.min(1, life)) * BAR_W

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
	t[#t+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
		Name = "GaugeLabel_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(barX, BAR_Y + BAR_H/2 + 12)
				:zoom(FONT_ZOOM):diffuse(color("#aaaaaa"))
			self:shadowlength(0)
			self:SetTextureFiltering(false)
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			self:settext(GetGaugeDisplayName(pn)):Regen()
		end,
		GalaxyLifeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			if params.GaugeType == "FloatingFlare" and params.FloatingCurrent then
				local roman = {"I","II","III","IV","V","VI","VII","VIII","IX","EX"}
				self:settext("Float " .. (roman[params.FloatingCurrent] or "?")):Regen()
			end
		end,
	}

	-- Life percentage text (overlaid on bar)
	t[#t+1] = Def.Text{ Font = RodinPath("db"), Size = FontS("db"), Text = "",
		Name = "BarPct_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(barX, BAR_Y)
				:zoom(FONT_ZOOM):diffuse(Color.White)
			self:shadowlength(0)
			self:SetTextureFiltering(false)
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
