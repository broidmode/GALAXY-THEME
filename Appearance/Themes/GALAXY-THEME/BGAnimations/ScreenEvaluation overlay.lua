-- ScreenEvaluation overlay — GALAXY
-- Full results display: scoring breakdown, judgments with early/late,
-- combo, flare. Supports 1P and 2P versus (each player gets half).
--
-- Data persistence (FinalizeChartResult + SaveChartResults) runs in
-- OnCommand before text is populated, so chart result data is fresh.

-- ===== CONSTANTS =====
local PANEL_W = 800
local PAD     = 32          -- horizontal padding inside panel

-- Difficulty colors (matching music select score panel)
local DiffColors = {
	Beginner  = color("#1ed6ff"),
	Easy      = color("#ffaa19"),
	Medium    = color("#ff1e3c"),
	Hard      = color("#32eb19"),
	Challenge = color("#eb1eff"),
	Edit      = color("#aaaaaa"),
}

-- Difficulty display labels (DDR-style)
local DiffLabels = {
	Beginner  = "BEGINNER",
	Easy      = "BASIC",
	Medium    = "DIFFICULT",
	Hard      = "EXPERT",
	Challenge = "CHALLENGE",
	Edit      = "EDIT",
}

-- Combo-lamp colours (matching music select)
local LampColors = {
	MFC   = color("#00ccff"),
	PFC   = color("#ffcc00"),
	GFC   = color("#00ff66"),
	FC    = color("#ffffff"),
	LIFE4 = color("#ff66cc"),
	Clear = color("#888888"),
}

-- Judgment rows: label, counts-key, display colour
local JudgmentDefs = {
	{ label = "MARVELOUS", key = "W1",   clr = color("#00ccff") },
	{ label = "PERFECT",   key = "W2",   clr = color("#ffcc00") },
	{ label = "GREAT",     key = "W3",   clr = color("#00ff66") },
	{ label = "GOOD",      key = "W4",   clr = color("#66aaff") },
	{ label = "MISS",      key = "Miss", clr = color("#ff4444") },
}

-- ===== SMALL HELPERS =====

-- Number → comma-separated string  (1234567 → "1,234,567")
local function commify(n)
	local s = tostring(math.floor(n))
	local pos = #s % 3
	if pos == 0 then pos = 3 end
	local parts = { s:sub(1, pos) }
	for i = pos + 1, #s, 3 do
		parts[#parts + 1] = s:sub(i, i + 2)
	end
	return table.concat(parts, ",")
end

-- Shorthand: create a Def.Text{} with standard GALAXY styling.
--   p.x, p.y        — position
--   p.size           — FontS / FontM / FontL  (default FontS)
--   p.halign         — 0=left 0.5=center 1=right (default 0)
--   p.color          — diffuse colour (default white)
--   p.maxwidth       — virtual-px maxwidth (optional)
--   p.text           — initial text string
local function T(p)
	return Def.Text{
		Font = RodinPath("db"),
		Size = p.size or FontS("db"),
		Text = p.text or "",
		InitCommand = function(self)
			self:xy(p.x or 0, p.y or 0)
				:zoom(FONT_ZOOM)
				:halign(p.halign or 0)
				:diffuse(p.color or Color.White)
				:shadowlength(0)
				:SetTextureFiltering(false)
			if p.maxwidth then self:maxwidth(FontMaxWidth(p.maxwidth)) end
		end,
	}
end

-- ===== EARLY / LATE COMPUTATION =====
-- Uses pss:GetOffsetData() (OutFox-exclusive) to build per-judgment-window
-- early / late counts.  Negative offset = early, positive = late.
local function ComputeEarlyLate(pss)
	local r = {
		W1 = { e = 0, l = 0 },
		W2 = { e = 0, l = 0 },
		W3 = { e = 0, l = 0 },
		W4 = { e = 0, l = 0 },
	}

	local ok, offsets = pcall(function() return pss:GetOffsetData() end)
	if not ok or not offsets then return r end

	for _, entry in ipairs(offsets) do
		local offset = entry[2]
		local tns    = entry[3]
		local isFake = entry[4]
		if not isFake and type(offset) == "number" then
			local key
			if     tns == "TapNoteScore_W1" then key = "W1"
			elseif tns == "TapNoteScore_W2" then key = "W2"
			elseif tns == "TapNoteScore_W3" then key = "W3"
			elseif tns == "TapNoteScore_W4" then key = "W4"
			end
			if key then
				if offset < 0 then r[key].e = r[key].e + 1
				elseif offset > 0 then r[key].l = r[key].l + 1 end
			end
		end
	end
	return r
end

-- ===== RESOLVE GAUGE STRING (same logic as FinalizeChartResult) =====
local function ResolveGaugeStr(pn)
	local gs = GaugeState and GaugeState[pn]
	if not gs then return "Normal" end
	local g = gs.gaugeType
	if g == "Flare" then
		local names = { "Flare1","Flare2","Flare3","Flare4","Flare5",
		                "Flare6","Flare7","Flare8","Flare9","FlareEX" }
		return names[gs.flareIndex] or "Normal"
	elseif g == "FloatingFlare" then
		local fc = gs.floatingCurrent
		if not fc or fc < 1 then return "Normal" end
		local names = { "Flare1","Flare2","Flare3","Flare4","Flare5",
		                "Flare6","Flare7","Flare8","Flare9","FlareEX" }
		return names[math.min(fc, 10)]
	end
	return g or "Normal"  -- Normal / LIFE4 / Risky
end

-- ===== BUILD ONE PLAYER'S PANEL =====
-- All data is read here (the file loads after gameplay is complete,
-- so pss, ScoreState, GaugeState are fully populated).
-- Returns an ActorFrame to be positioned by the caller.

local function MakePlayerPanel(pn)
	-- --- data sources ---
	local song  = GAMESTATE:GetCurrentSong()
	local steps = GAMESTATE:GetCurrentSteps(pn)
	local pss   = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)

	-- judgment counts
	local counts = {
		W1    = pss:GetTapNoteScores("TapNoteScore_W1"),
		W2    = pss:GetTapNoteScores("TapNoteScore_W2"),
		W3    = pss:GetTapNoteScores("TapNoteScore_W3"),
		W4    = pss:GetTapNoteScores("TapNoteScore_W4"),
		Miss  = pss:GetTapNoteScores("TapNoteScore_Miss"),
		Held  = pss:GetHoldNoteScores("HoldNoteScore_Held"),
		LetGo = pss:GetHoldNoteScores("HoldNoteScore_LetGo"),
		HitMine = pss:GetTapNoteScores("TapNoteScore_HitMine"),
	}

	local failed   = pss:GetFailed()
	local ddrScore = GetDisplayScore(pn)
	local grade    = GetCurrentGrade(pn)
	local exRaw    = GetEXRaw(pn)
	local exMax    = GetEXMax(pn)
	local exPct    = GetEXPercent(pn)
	local maxCombo = pss:MaxCombo()

	-- early / late per judgment window
	local el = ComputeEarlyLate(pss)

	-- combo lamp (computed from live counts)
	local gs = GaugeState and GaugeState[pn]
	local gaugeForLamp = (gs and gs.gaugeType == "LIFE4" and not failed) and "LIFE4" or nil
	local gaugeStr = ResolveGaugeStr(pn)
	local lamp = DetectComboLamp(counts, failed, gaugeForLamp or gaugeStr)

	-- flare points (only if cleared)
	local flarePoints = 0
	if not failed and steps then
		local effective = gaugeStr
		if effective == "LIFE4" or effective == "Risky" then effective = "Normal" end
		flarePoints = LookupFlarePoints(steps:GetMeter(), effective)
	end
	local flareDisplay = GetFlareGradeDisplay(gaugeStr)

	-- song / diff info
	local songTitle = song and song:GetDisplayMainTitle() or "Unknown"
	local diffShort = steps and ToEnumShortString(steps:GetDifficulty()) or "?"
	local meter     = steps and steps:GetMeter() or 0
	local diffColor = DiffColors[diffShort] or Color.White
	local diffLabel = DiffLabels[diffShort] or diffShort

	-- ===== actor tree =====
	local af = Def.ActorFrame{}

	-- panel background + border
	local panelH = 580
	af[#af+1] = Def.Quad{
		InitCommand = function(self)
			self:zoomto(PANEL_W + 2, panelH + 2)
				:diffuse(color("#334466")):diffusealpha(0.4)
		end,
	}
	af[#af+1] = Def.Quad{
		InitCommand = function(self)
			self:zoomto(PANEL_W, panelH)
				:diffuse(color("#0a0a18")):diffusealpha(0.85)
		end,
	}

	local y = -panelH/2 + 24   -- start near top edge

	-- ----- song title -----
	af[#af+1] = T{ x = 0, y = y, size = FontM("db"), halign = 0.5,
		maxwidth = PANEL_W - 60, text = songTitle }
	y = y + 28

	-- ----- difficulty + level -----
	af[#af+1] = T{ x = 0, y = y, size = FontS("db"), halign = 0.5,
		color = diffColor, text = diffLabel .. "  Lv." .. tostring(meter) }
	y = y + 42

	-- ----- DDR score (left)  /  grade (right) -----
	af[#af+1] = T{ x = -PANEL_W/2 + PAD, y = y, size = FontL("db"), halign = 0,
		text = commify(ddrScore) }
	af[#af+1] = T{ x = PANEL_W/2 - PAD, y = y, size = FontL("db"), halign = 1,
		color = failed and color("#ff4444") or Color.White,
		text = grade }
	y = y + 38

	-- ----- EX score -----
	local exText = string.format("EX  %d / %d  (%.2f%%)", exRaw, exMax, exPct)
	af[#af+1] = T{ x = 0, y = y, size = FontM("db"), halign = 0.5,
		color = color("#aaeeff"), text = exText }
	y = y + 36

	-- ----- separator -----
	af[#af+1] = Def.Quad{
		InitCommand = function(self)
			self:xy(0, y):zoomto(PANEL_W - 60, 1)
				:diffuse(color("#334466")):diffusealpha(0.5)
		end,
	}
	y = y + 18

	-- ----- judgment table header -----
	local hdrClr = color("#667788")
	local colCountX = 80
	local colEarlyX = 210
	local colLateX  = 340
	af[#af+1] = T{ x = -PANEL_W/2 + PAD, y = y, halign = 0, color = hdrClr, text = "JUDGMENT" }
	af[#af+1] = T{ x = colCountX,         y = y, halign = 1, color = hdrClr, text = "COUNT" }
	af[#af+1] = T{ x = colEarlyX,         y = y, halign = 1, color = hdrClr, text = "EARLY" }
	af[#af+1] = T{ x = colLateX,          y = y, halign = 1, color = hdrClr, text = "LATE" }
	y = y + 26

	-- ----- judgment rows -----
	for _, jd in ipairs(JudgmentDefs) do
		local count    = counts[jd.key] or 0
		local earlyStr = "-"
		local lateStr  = "-"
		if el[jd.key] then
			earlyStr = tostring(el[jd.key].e)
			lateStr  = tostring(el[jd.key].l)
		end

		af[#af+1] = T{ x = -PANEL_W/2 + PAD, y = y, halign = 0, color = jd.clr,  text = jd.label }
		af[#af+1] = T{ x = colCountX,         y = y, halign = 1,                    text = tostring(count) }
		af[#af+1] = T{ x = colEarlyX,         y = y, halign = 1, color = color("#aaaacc"), text = earlyStr }
		af[#af+1] = T{ x = colLateX,          y = y, halign = 1, color = color("#aaaacc"), text = lateStr }
		y = y + 26
	end
	y = y + 6

	-- ----- separator -----
	af[#af+1] = Def.Quad{
		InitCommand = function(self)
			self:xy(0, y):zoomto(PANEL_W - 60, 1)
				:diffuse(color("#334466")):diffusealpha(0.5)
		end,
	}
	y = y + 16

	-- ----- holds -----
	af[#af+1] = T{ x = -PANEL_W/2 + PAD, y = y, halign = 0, color = hdrClr, text = "HOLDS" }
	af[#af+1] = T{ x = colCountX,  y = y, halign = 0, color = color("#00ff66"),
		text = "OK  " .. tostring(counts.Held or 0) }
	af[#af+1] = T{ x = colEarlyX,  y = y, halign = 0, color = color("#ff4444"),
		text = "NG  " .. tostring(counts.LetGo or 0) }
	y = y + 32

	-- ----- max combo -----
	af[#af+1] = T{ x = -PANEL_W/2 + PAD, y = y, halign = 0, color = hdrClr,
		size = FontM("db"), text = "MAX COMBO" }
	af[#af+1] = T{ x = PANEL_W/2 - PAD, y = y, halign = 1,
		size = FontM("db"), text = commify(maxCombo) }
	y = y + 32

	-- ----- combo lamp -----
	local lampClr  = LampColors[lamp] or color("#555555")
	local lampText = lamp or "---"
	af[#af+1] = T{ x = -PANEL_W/2 + PAD, y = y, halign = 0, color = hdrClr, text = "COMBO LAMP" }
	af[#af+1] = T{ x = PANEL_W/2 - PAD, y = y, halign = 1, color = lampClr, text = lampText }
	y = y + 28

	-- ----- flare -----
	local fpText  = (flarePoints > 0) and (tostring(flarePoints) .. " pts") or "---"
	local fpColor = (flarePoints > 0) and color("#ffcc66") or color("#555555")
	af[#af+1] = T{ x = -PANEL_W/2 + PAD, y = y, halign = 0, color = hdrClr, text = "FLARE" }
	af[#af+1] = T{ x = 0,               y = y, halign = 0.5, color = fpColor, text = flareDisplay }
	af[#af+1] = T{ x = PANEL_W/2 - PAD, y = y, halign = 1,   color = fpColor, text = fpText }

	return af
end

-- ===================================================================
-- MAIN OVERLAY
-- ===================================================================
local t = Def.ActorFrame{ Name = "EvalOverlay" }

-- Data persistence: finalize chart result & save to profile.
-- Runs in OnCommand (after InitCommand of all actors).
t[#t+1] = Def.Actor{
	OnCommand = function(self)
		local song = GAMESTATE:GetCurrentSong()
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			local steps = GAMESTATE:GetCurrentSteps(pn)
			if song and steps and FinalizeChartResult then
				FinalizeChartResult(pn, song, steps)
			end
			if PROFILEMAN:IsPersistentProfile(pn) and SaveChartResults then
				local slot = (pn == PLAYER_1) and "ProfileSlot_Player1" or "ProfileSlot_Player2"
				local dir  = PROFILEMAN:GetProfileDir(slot)
				if dir and dir ~= "" then
					SaveChartResults(pn, dir)
				end
			end
		end
	end,
}

-- Player panels — P1 at left quarter, P2 at right quarter.
for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
	local panelX = (pn == PLAYER_1) and (SCREEN_WIDTH * 0.25)
	                                  or (SCREEN_WIDTH * 0.75)
	local panel = MakePlayerPanel(pn)
	panel.InitCommand = function(self) self:xy(panelX, SCREEN_CENTER_Y) end
	t[#t+1] = panel
end

return t
