-- GALAXY custom combo display — digit sprites only (no "COMBO" label).
-- Spritesheet: "combo 10x1.png" (1280×128, ten 128×128 digit frames 0-9).
-- Digit colour is multiplied by current full-combo performance tier.
-- We self-track the worst judgment in the current combo because
-- UseInternalScoring=false prevents the engine from setting FullComboW1-W4.

local player      = Var "Player"
local ShowComboAt = THEME:GetMetric("Combo", "ShowComboAt")

local MAX_DIGITS  = 5          -- supports up to 99 999
local DIGIT_ZOOM  = 0.28       -- display scale (matches judgment size)
local DIGIT_GAP   = 20         -- horizontal spacing between digit centres (px)
local DIGIT_RISE  = -0.15      -- vertical rise per digit (fraction of DIGIT_GAP; negative = up)
local PULSE_MULT  = 1.10       -- pop-in scale factor on each hit

-- Performance colours  (black-and-white digits are multiplied by these)
local ComboColors = {
	W1     = color("#FFE9F6"),  -- Marvelous  (184, 239, 237)
	W2     = color("#F5E349"),  -- Perfect    (245, 227, 73)
	W3     = color("#0DFD74"),  -- Great      (13,  253, 116)
	W4     = color("#4593FF"),  -- Good       (63, 143, 255)
	Normal = color("#FFFFFF"),  -- White (no FC tier)
}

-- Judgment tier tracking (1=W1 best .. 4=W4 worst, 0=not yet set)
local JudgeTierMap = {
	TapNoteScore_W1 = 1,
	TapNoteScore_W2 = 2,
	TapNoteScore_W3 = 3,
	TapNoteScore_W4 = 4,
}
local TierColors = { ComboColors.W1, ComboColors.W2, ComboColors.W3, ComboColors.W4 }

local worstTier = 0   -- worst judgment tier seen in current combo run

---------------------------------------------------------------------------

local digits = {}   -- digit sprite references (1-indexed)

local t = Def.ActorFrame {}

-- Create digit sprites (reused every frame)
for i = 1, MAX_DIGITS do
	t[#t + 1] = Def.Sprite {
		Name    = "Digit" .. i,
		Texture = "combo 10x1.png",
		InitCommand = function(self)
			digits[i] = self
			self:visible(false)
			self:animate(false)   -- manual frame control only
			self:zoom(DIGIT_ZOOM)
		end,
	}
end

---------------------------------------------------------------------------
-- JudgmentMessageCommand — track the worst judgment in the current combo.
-- Fires before ComboCommand each tap, so worstTier is up-to-date.
---------------------------------------------------------------------------
t.JudgmentMessageCommand = function(self, param)
	if param.Player ~= player then return end
	local tier = JudgeTierMap[param.TapNoteScore]
	if tier then
		if worstTier == 0 or tier > worstTier then
			worstTier = tier
		end
	end
end

---------------------------------------------------------------------------
-- ComboCommand — fired by the engine after every tap judgement.
-- param.Combo / param.Misses  (unsigned int, mutually exclusive)
---------------------------------------------------------------------------
t.ComboCommand = function(self, param)
	local iCombo = param.Combo
	if not iCombo or iCombo < ShowComboAt then
		-- Combo broken or below threshold — reset tracker and hide
		worstTier = 0
		for i = 1, MAX_DIGITS do
			if digits[i] then digits[i]:visible(false) end
		end
		return
	end

	-- Pick colour from our self-tracked tier
	local col = TierColors[worstTier] or ComboColors.Normal

	-- Break number into individual digit characters
	local str = tostring(iCombo)
	local n   = #str
	local totalW = (n - 1) * DIGIT_GAP
	local x0    = -totalW / 2
	local yStep = DIGIT_GAP * DIGIT_RISE   -- vertical shift per digit

	for i = 1, MAX_DIGITS do
		if i <= n then
			local spr = digits[i]
			spr:visible(true)
			spr:setstate(tonumber(str:sub(i, i)))
			spr:x(x0 + (i - 1) * DIGIT_GAP)
			spr:y((i - 1) * yStep)
			spr:diffuse(col)
			-- Pulse: quick zoom-in then settle
			spr:stoptweening()
			spr:zoom(DIGIT_ZOOM * PULSE_MULT)
			spr:linear(0.05)
			spr:zoom(DIGIT_ZOOM)
		else
			digits[i]:visible(false)
		end
	end
end

return t
