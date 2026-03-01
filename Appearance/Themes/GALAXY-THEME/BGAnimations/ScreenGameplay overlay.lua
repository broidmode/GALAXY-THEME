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

		UpdateScore(params, pn)
		UpdateGauge(params, pn)

		-- Broadcast score update for HUD
		MESSAGEMAN:Broadcast("GalaxyScoreChanged", {
			Player    = pn,
			Score     = GetDisplayScore(pn),
			EXPercent = GetEXPercent(pn),
		})

		-- Handle fail
		if GetGaugeFailed(pn) then
			local screen = SCREENMAN:GetTopScreen()
			if screen then
				screen:PostScreenMessage('SM_BeginFailed', 0)
			end
		end
	end,
}

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
	t[#t+1] = LoadFont("Common Normal") .. {
		Name = "GaugeLabel_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(barX, BAR_Y + BAR_H/2 + 12)
				:zoom(0.32)
				:settext("")
				:diffuse(color("#aaaaaa"))
				:shadowlength(1)
		end,
		DoneLoadingNextSongMessageCommand = function(self)
			self:settext(GetGaugeDisplayName(pn))
		end,
		GalaxyLifeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			if params.GaugeType == "FloatingFlare" and params.FloatingCurrent then
				local roman = {"I","II","III","IV","V","VI","VII","VIII","IX","EX"}
				self:settext("Float " .. (roman[params.FloatingCurrent] or "?"))
			end
		end,
	}

	-- Life percentage text (overlaid on bar)
	t[#t+1] = LoadFont("Common Normal") .. {
		Name = "BarPct_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(barX, BAR_Y)
				:zoom(0.35)
				:settext("")
				:diffuse(Color.White)
				:shadowlength(1)
		end,
		GalaxyLifeChangedMessageCommand = function(self, params)
			if params.Player ~= pn then return end
			if params.Failed then
				self:settext("FAILED")
				return
			end
			local gType = params.GaugeType
			if gType == "LIFE4" or gType == "Risky" then
				local lives = math.floor(params.Life)
				self:settext(lives .. " / " .. (params.MaxLives or 0))
			else
				local pct = math.floor((params.Life or 0) * 100 + 0.5)
				self:settext(pct .. "%")
			end
		end,
	}

	-- Score display
	t[#t+1] = LoadFont("Common Normal") .. {
		Name = "Score_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(scoreX, BAR_Y)
				:zoom(0.7)
				:halign(isP1 and 0 or 1)
				:settext("0")
				:diffuse(Color.White)
				:shadowlength(1)
		end,
		GalaxyScoreChangedMessageCommand = function(self, params)
			if params.Player == pn then
				self:settext(string.format("%d", params.Score))
			end
		end,
	}

	-- EX Score display
	t[#t+1] = LoadFont("Common Normal") .. {
		Name = "EX_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(scoreX, BAR_Y + 24)
				:zoom(0.38)
				:halign(isP1 and 0 or 1)
				:settext("EX 0.00%")
				:diffuse(color("#aaaaff"))
				:shadowlength(1)
		end,
		GalaxyScoreChangedMessageCommand = function(self, params)
			if params.Player == pn then
				self:settext(string.format("EX %.2f%%", params.EXPercent))
			end
		end,
	}

	-- Grade display
	t[#t+1] = LoadFont("Common Normal") .. {
		Name = "Grade_" .. ToEnumShortString(pn),
		InitCommand = function(self)
			self:xy(scoreX + sideSign * 120, BAR_Y)
				:zoom(0.55)
				:halign(0.5)
				:settext("")
				:diffuse(color("#ffcc00"))
				:shadowlength(1)
		end,
		GalaxyScoreChangedMessageCommand = function(self, params)
			if params.Player == pn then
				self:settext(GetCurrentGrade(pn))
			end
		end,
	}
end

return t
