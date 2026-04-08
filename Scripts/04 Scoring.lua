-- 04 Scoring.lua — GALAXY DDR Score Translation Layer
-- Canonical DDR A/WORLD per-note scoring + EX Score.
-- Single source of truth: one formula used everywhere.
--
-- During gameplay: hooks JudgmentMessage via actor in decorations.
-- Outside gameplay: ComputeDDRScore()/ComputeEXScore() recompute from saved data.
--
-- The engine saves scores natively (judgment counts always in Stats.xml).
-- We do NOT call pss:SetScore() — DDR scores are a pure function of judgments.

-- ===== SCORE STATE (per player, per song) =====
ScoreState = {}

-- ===== GRADE TABLE =====
local GradeThresholds = {
	{ 990000, "AAA" },
	{ 950000, "AA+" },
	{ 900000, "AA"  },
	{ 890000, "AA-" },
	{ 850000, "A+"  },
	{ 800000, "A"   },
	{ 790000, "A-"  },
	{ 750000, "B+"  },
	{ 700000, "B"   },
	{ 690000, "B-"  },
	{ 650000, "C+"  },
	{ 600000, "C"   },
	{ 590000, "C-"  },
	{ 550000, "D+"  },
	{      0, "D"   },
}

-- ===== INITIALIZATION =====
-- Call once per song via DoneLoadingNextSongMessage
function InitScoreState(pn)
	local steps = GAMESTATE:GetCurrentSteps(pn)
	if not steps then return end

	local rv = steps:GetRadarValues(pn)
	local numPanels = GAMESTATE:GetCurrentStyle():ColumnsPerPlayer()

	local tapsAndHolds = rv:GetValue('RadarCategory_TapsAndHolds')
	local holds = rv:GetValue('RadarCategory_Holds')
	local rolls = rv:GetValue('RadarCategory_Rolls')
	local mines = rv:GetValue('RadarCategory_Mines')
	local shockRows = math.floor(mines / math.max(numPanels, 1))

	local N = tapsAndHolds + holds + rolls + shockRows
	N = math.max(N, 1)

	local tails = holds + rolls

	ScoreState[pn] = {
		N                = N,
		U                = 1000000 / N,
		score            = 0,
		exRaw            = 0,
		exMax            = 3 * (N + tails),
		shockMinesJudged = 0,
		numPanels        = numPanels,
		failed           = false,
	}
end

-- ===== PER-JUDGMENT UPDATE =====
-- Call on every JudgmentMessage from gameplay decorations actor
function UpdateScore(params, pn)
	local st = ScoreState[pn]
	if not st then return end

	-- Stop accumulating after fail
	if st.failed then return end

	local pss = STATSMAN:GetCurStageStats():GetPlayerStageStats(pn)
	if pss:GetFailed() then
		st.failed = true
		return
	end

	local U = st.U
	local addScore = 0
	local addEX = 0

	if params.HoldNoteScore then
		local hns = params.HoldNoteScore
		if hns == 'HoldNoteScore_Held' then
			addScore = U
			addEX = 3
		end
		-- NG / MissedHold: 0, 0

	elseif params.TapNoteScore then
		local tns = params.TapNoteScore
		if tns == 'TapNoteScore_W1' then
			addScore = U
			addEX = 3
		elseif tns == 'TapNoteScore_W2' then
			addScore = U - 10
			addEX = 2
		elseif tns == 'TapNoteScore_W3' then
			addScore = math.floor(0.6 * U) - 10
			addEX = 1
		elseif tns == 'TapNoteScore_W4' then
			addScore = math.floor(0.2 * U) - 10
			addEX = 0
		elseif tns == 'TapNoteScore_AvoidMine' then
			st.shockMinesJudged = st.shockMinesJudged + 1
			if st.shockMinesJudged >= st.numPanels then
				addScore = U
				addEX = 3
				st.shockMinesJudged = 0
			end
		end
		-- Miss / HitMine / W5: 0, 0
	end

	st.score = st.score + addScore
	st.exRaw = st.exRaw + addEX
end

-- ===== ACCESSORS (Global) =====

-- Display score: truncated to nearest 10 (floor, not round)
function GetDisplayScore(pn)
	local st = ScoreState[pn]
	if not st then return 0 end
	return math.max(0, math.floor(st.score / 10) * 10)
end

function GetInternalScore(pn)
	local st = ScoreState[pn]
	return st and st.score or 0
end

function GetEXRaw(pn)
	local st = ScoreState[pn]
	return st and st.exRaw or 0
end

function GetEXMax(pn)
	local st = ScoreState[pn]
	return st and st.exMax or 0
end

function GetEXPercent(pn)
	local st = ScoreState[pn]
	if not st or st.exMax == 0 then return 0 end
	return math.floor(st.exRaw / st.exMax * 10000) / 100
end

-- DDR grade from display score
function GetDDRGrade(score, failed)
	if failed then return "E" end
	for _, entry in ipairs(GradeThresholds) do
		if score >= entry[1] then return entry[2] end
	end
	return "D"
end

-- Current grade for a player during gameplay
function GetCurrentGrade(pn)
	return GetDDRGrade(GetDisplayScore(pn), ScoreState[pn] and ScoreState[pn].failed)
end

-- ===== RECOMPUTATION FROM SAVED DATA =====
-- For music select / evaluation: rebuild DDR score from HighScore judgment counts.

function ComputeDDRScore(counts, N)
	N = math.max(N or 1, 1)
	local U = 1000000 / N
	local score = (counts.W1 or 0) * U
	            + (counts.W2 or 0) * (U - 10)
	            + (counts.W3 or 0) * (math.floor(0.6 * U) - 10)
	            + (counts.W4 or 0) * (math.floor(0.2 * U) - 10)
	            + (counts.Held or 0) * U
	            + (counts.ShockRows or 0) * U
	return math.max(0, math.floor(score / 10) * 10)
end

function ComputeEXScore(counts, N, tails)
	local raw = (counts.W1 or 0) * 3
	          + (counts.W2 or 0) * 2
	          + (counts.W3 or 0) * 1
	          + (counts.Held or 0) * 3
	          + (counts.ShockRows or 0) * 3
	local maxRaw = 3 * (math.max(N or 1, 1) + (tails or 0))
	if maxRaw == 0 then return 0 end
	return math.floor(raw / maxRaw * 10000) / 100
end

-- Build counts table from a HighScore object
function GetCountsFromHighScore(hs)
	return {
		W1   = hs:GetTapNoteScore('TapNoteScore_W1'),
		W2   = hs:GetTapNoteScore('TapNoteScore_W2'),
		W3   = hs:GetTapNoteScore('TapNoteScore_W3'),
		W4   = hs:GetTapNoteScore('TapNoteScore_W4'),
		Miss = hs:GetTapNoteScore('TapNoteScore_Miss'),
		Held = hs:GetHoldNoteScore('HoldNoteScore_Held'),
		LetGo = hs:GetHoldNoteScore('HoldNoteScore_LetGo'),
		HitMine = hs:GetTapNoteScore('TapNoteScore_HitMine'),
		AvoidMine = hs:GetTapNoteScore('TapNoteScore_AvoidMine'),
		ShockRows = 0,  -- approximate: can't perfectly reconstruct from AvoidMine count
	}
end

-- ===== MUSIC SELECT SCORE DATA HELPER =====
-- Returns a table of score data for display, or nil if no score exists.
-- { score, grade, exRaw, exPct, counts }
-- Reads from engine HighScoreList (judgment counts) and recomputes DDR scores.
function GetScoreDataForSteps(pn, song, steps)
	if not song or not steps then return nil end

	-- Get profile
	local profile
	if PROFILEMAN:IsPersistentProfile(pn) then
		profile = PROFILEMAN:GetProfile(pn)
	else
		profile = PROFILEMAN:GetMachineProfile()
	end
	if not profile then return nil end

	-- Get high score list
	local hsl = profile:GetHighScoreList(song, steps)
	if not hsl then return nil end
	local scores = hsl:GetHighScores()
	if not scores or not scores[1] then return nil end

	local hs = scores[1]
	local counts = GetCountsFromHighScore(hs)

	-- Compute N (total scorable objects) from steps radar
	local rv = steps:GetRadarValues(pn)
	local numPanels = GAMESTATE:GetCurrentStyle():ColumnsPerPlayer()
	local tapsAndHolds = rv:GetValue('RadarCategory_TapsAndHolds')
	local holds = rv:GetValue('RadarCategory_Holds')
	local rolls = rv:GetValue('RadarCategory_Rolls')
	local mines = rv:GetValue('RadarCategory_Mines')
	local shockRows = math.floor(mines / math.max(numPanels, 1))
	local N = math.max(tapsAndHolds + holds + rolls + shockRows, 1)
	local tails = holds + rolls

	local ddrScore = ComputeDDRScore(counts, N)
	local failed = (hs:GetGrade() == 'Grade_Failed')
	local grade = GetDDRGrade(ddrScore, failed)

	-- EX score
	local exRaw = (counts.W1 or 0) * 3 + (counts.W2 or 0) * 2 + (counts.W3 or 0) * 1
	            + (counts.Held or 0) * 3
	local exMax = 3 * (N + tails)
	local exPct = 0
	if exMax > 0 then
		exPct = math.floor(exRaw / exMax * 10000) / 100
	end

	return {
		score  = ddrScore,
		grade  = grade,
		failed = failed,
		exRaw  = exRaw,
		exPct  = exPct,
		counts = counts,
	}
end
