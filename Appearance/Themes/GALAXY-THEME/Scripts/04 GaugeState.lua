-- 04 GaugeState.lua — GALAXY Gauge State Machine
-- Manages life meters entirely in Lua. The engine's LifeMeterBar is
-- neutralized (all LifePercentChange = 0), so it sits inert.
--
-- Supports: Normal, Flare I-EX, Floating Flare, LIFE4, Risky.
-- Reads gauge selection from GalaxyOptions[pn].Gauge (set by music select menu).
-- Broadcasts GalaxyLifeChangedMessage for HUD actors.

-- ===== GAUGE STATE (per player) =====
GaugeState = {}

-- ===== NORMAL GAUGE RATES =====
-- From _fallback/metrics.ini [LifeMeterBar]
local NormalRates = {
	W1        =  0.008,
	W2        =  0.008,
	W3        =  0.004,
	W4        =  0.000,
	W5        = -0.040,
	Miss      = -0.080,
	HitMine   = -0.160,
	Held      =  0.008,
	LetGo     = -0.080,
	MissedHold = 0.000,
}

-- ===== FLARE DRAIN TABLES =====
-- From !Forks/stepmania-ddr-5_1-new/src/LifeMeterBar.h
-- Index 1 = Flare I, Index 10 = Flare EX
local FlareTap = {
	W1   = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	W2   = { 0, 0, 0, 0, 0, 0, 0, 0, 0, -0.01 },
	W3   = { -0.001, -0.001, -0.001, -0.0029, -0.0074, -0.0092, -0.0128, -0.0164, -0.02, -0.02 },
	W4   = { -0.0063, -0.0063, -0.0075, -0.0145, -0.038, -0.045, -0.064, -0.082, -0.1, -0.1 },
	Miss = { -0.015, -0.03, -0.045, -0.11, -0.16, -0.18, -0.22, -0.26, -0.3, -0.3 },
}

local FlareHold = {
	Held       = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	MissedHold = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	LetGo      = { -0.015, -0.03, -0.045, -0.11, -0.16, -0.18, -0.22, -0.26, -0.3, -0.3 },
}

-- Map gauge string to Flare index (1-10)
local FlareIndexMap = {
	Flare1 = 1, Flare2 = 2, Flare3 = 3, Flare4 = 4, Flare5 = 5,
	Flare6 = 6, Flare7 = 7, Flare8 = 8, Flare9 = 9, FlareEX = 10,
	FloatingFlare = 10,  -- starts at EX
}

-- ===== INITIALIZATION =====
function InitGauge(pn)
	local gaugeStr = "Normal"
	if GalaxyOptions and GalaxyOptions[pn] then
		gaugeStr = GalaxyOptions[pn].Gauge or "Normal"
	end
	Trace("[GALAXY] InitGauge: pn=" .. tostring(pn) .. " gaugeStr=" .. gaugeStr)

	local gs = {
		gaugeType       = "Normal",
		flareIndex      = nil,
		life            = 0.5,
		maxLives        = nil,
		failed          = false,
		floatingCurrent = nil,
		flareBars       = nil,   -- parallel bars for FloatingFlare (index 1-10)
	}

	if gaugeStr == "Normal" then
		gs.gaugeType = "Normal"
		gs.life = 0.5

	elseif gaugeStr == "FloatingFlare" then
		gs.gaugeType = "FloatingFlare"
		gs.flareIndex = 10
		gs.life = 1.0
		gs.floatingCurrent = 10
		gs.flareBars = { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }

	elseif gaugeStr == "LIFE4" then
		gs.gaugeType = "LIFE4"
		gs.life = 4
		gs.maxLives = 4

	elseif gaugeStr == "Risky" then
		gs.gaugeType = "Risky"
		gs.life = 1
		gs.maxLives = 1

	elseif FlareIndexMap[gaugeStr] then
		gs.gaugeType = "Flare"
		gs.flareIndex = FlareIndexMap[gaugeStr]
		gs.life = 1.0
	end

	GaugeState[pn] = gs

	-- Broadcast initial state so HUD shows gauge immediately
	MESSAGEMAN:Broadcast("GalaxyLifeChanged", {
		Player         = pn,
		Life           = gs.life,
		MaxLives       = gs.maxLives,
		Failed         = gs.failed,
		GaugeType      = gs.gaugeType,
		FlareIndex     = gs.flareIndex,
		FloatingCurrent = gs.floatingCurrent,
	})
end

-- ===== DELTA LOOKUP =====

-- Get the delta for a tap note score on a Flare gauge
local function GetFlareTapDelta(tns, idx)
	if tns == 'TapNoteScore_W1' or tns == 'TapNoteScore_AvoidMine' then
		return FlareTap.W1[idx]
	elseif tns == 'TapNoteScore_W2' then
		return FlareTap.W2[idx]
	elseif tns == 'TapNoteScore_W3' then
		return FlareTap.W3[idx]
	elseif tns == 'TapNoteScore_W4' then
		return FlareTap.W4[idx]
	elseif tns == 'TapNoteScore_Miss' or tns == 'TapNoteScore_HitMine' then
		return FlareTap.Miss[idx]
	end
	return 0
end

-- Get the delta for a hold note score on a Flare gauge
local function GetFlareHoldDelta(hns, idx)
	if hns == 'HoldNoteScore_Held' then
		return FlareHold.Held[idx]
	elseif hns == 'HoldNoteScore_LetGo' then
		return FlareHold.LetGo[idx]
	elseif hns == 'HoldNoteScore_MissedHold' then
		return FlareHold.MissedHold[idx]
	end
	return 0
end

-- Get the delta for a Normal gauge event
local function GetNormalDelta(params)
	if params.HoldNoteScore then
		local hns = params.HoldNoteScore
		if hns == 'HoldNoteScore_Held' then return NormalRates.Held end
		if hns == 'HoldNoteScore_LetGo' then return NormalRates.LetGo end
		if hns == 'HoldNoteScore_MissedHold' then return NormalRates.MissedHold end
	elseif params.TapNoteScore then
		local tns = params.TapNoteScore
		if tns == 'TapNoteScore_W1' then return NormalRates.W1 end
		if tns == 'TapNoteScore_W2' then return NormalRates.W2 end
		if tns == 'TapNoteScore_W3' then return NormalRates.W3 end
		if tns == 'TapNoteScore_W4' then return NormalRates.W4 end
		if tns == 'TapNoteScore_W5' then return NormalRates.W5 end
		if tns == 'TapNoteScore_Miss' then return NormalRates.Miss end
		if tns == 'TapNoteScore_HitMine' then return NormalRates.HitMine end
		if tns == 'TapNoteScore_AvoidMine' then return 0 end
	end
	return 0
end

-- Get the Flare delta for any judgment event
local function GetFlareDelta(params, idx)
	if params.HoldNoteScore then
		return GetFlareHoldDelta(params.HoldNoteScore, idx)
	elseif params.TapNoteScore then
		return GetFlareTapDelta(params.TapNoteScore, idx)
	end
	return 0
end

-- ===== FLOATING FLARE ALGORITHM =====
-- Track 10 parallel bars (Flare I through EX) simultaneously.
-- Each judgment drains every bar at its own rate. The displayed bar is
-- the highest-indexed bar still above 0%.
local function ApplyFloatingFlare(gs, params)
	local bars = gs.flareBars
	for i = 1, 10 do
		if bars[i] > 0 then
			local delta = GetFlareDelta(params, i)
			bars[i] = math.max(0, math.min(1, bars[i] + delta))
		end
	end

	-- Find highest surviving bar
	local best = 0
	for i = 10, 1, -1 do
		if bars[i] > 0 then
			best = i
			break
		end
	end

	gs.floatingCurrent = best
	gs.life = best > 0 and bars[best] or 0
end

-- ===== MAIN UPDATE =====
-- Call on every JudgmentMessage from gameplay decorations
function UpdateGauge(params, pn)
	local gs = GaugeState[pn]
	if not gs or gs.failed then return end

	local gType = gs.gaugeType

	if gType == "Normal" then
		local delta = GetNormalDelta(params)
		gs.life = math.max(0, math.min(1, gs.life + delta))
		if gs.life <= 0 then
			gs.failed = true
		end

	elseif gType == "Flare" then
		local delta = GetFlareDelta(params, gs.flareIndex)
		gs.life = math.max(0, math.min(1, gs.life + delta))
		if gs.life <= 0 then
			gs.failed = true
		end

	elseif gType == "FloatingFlare" then
		ApplyFloatingFlare(gs, params)
		if gs.life <= 0 then
			gs.failed = true
		end

	elseif gType == "LIFE4" or gType == "Risky" then
		-- Battery mode: lose a life on bad judgments
		local loseLife = false
		if params.TapNoteScore then
			local tns = params.TapNoteScore
			if tns == 'TapNoteScore_Miss' or tns == 'TapNoteScore_HitMine' then
				loseLife = true
			end
		elseif params.HoldNoteScore then
			if params.HoldNoteScore == 'HoldNoteScore_LetGo' then
				loseLife = true
			end
		end
		if loseLife then
			gs.life = gs.life - 1
			if gs.life <= 0 then
				gs.life = 0
				gs.failed = true
			end
		end
	end

	-- Broadcast for HUD
	MESSAGEMAN:Broadcast("GalaxyLifeChanged", {
		Player         = pn,
		Life           = gs.life,
		MaxLives       = gs.maxLives,
		Failed         = gs.failed,
		GaugeType      = gs.gaugeType,
		FlareIndex     = gs.flareIndex,
		FloatingCurrent = gs.floatingCurrent,
	})
end

-- ===== ACCESSORS =====

function GetGaugeLife(pn)
	local gs = GaugeState[pn]
	return gs and gs.life or 0
end

function GetGaugeFailed(pn)
	local gs = GaugeState[pn]
	return gs and gs.failed or false
end

function GetGaugeType(pn)
	local gs = GaugeState[pn]
	return gs and gs.gaugeType or "Normal"
end

function GetGaugeFlareIndex(pn)
	local gs = GaugeState[pn]
	return gs and gs.flareIndex or nil
end

function GetFloatingFlareCurrent(pn)
	local gs = GaugeState[pn]
	return gs and gs.floatingCurrent or nil
end

-- Summary string for display
function GetGaugeDisplayName(pn)
	local gs = GaugeState[pn]
	if not gs then return "Normal" end
	if gs.gaugeType == "Normal" then return "Normal" end
	if gs.gaugeType == "LIFE4" then return "LIFE4" end
	if gs.gaugeType == "Risky" then return "Risky" end
	if gs.gaugeType == "FloatingFlare" then
		local roman = {"I","II","III","IV","V","VI","VII","VIII","IX","EX"}
		local cur = gs.floatingCurrent or 0
		if cur < 1 then return "Float ---" end
		return "Float " .. (roman[cur] or "?")
	end
	if gs.gaugeType == "Flare" then
		local roman = {"I","II","III","IV","V","VI","VII","VIII","IX","EX"}
		return "Flare " .. (roman[gs.flareIndex] or "?")
	end
	return "Normal"
end
