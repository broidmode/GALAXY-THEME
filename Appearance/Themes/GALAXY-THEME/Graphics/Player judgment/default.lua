-- GALAXY Player judgment — custom judgment + fast/slow sprites
-- Reads GalaxyOptions[pn] for FastSlow, Scroll (reverse), JudgePosition, JudgePriority

local player = Var "Player"

-- ===== SIZE TUNING =====
-- Adjust these multipliers to scale the judgment and fast/slow sprites.
-- A value of 1.0 = original art size; 0.5 = half size, etc.
local JUDGE_SCALE  = 0.30   -- judgment sprite base scale
local FS_SCALE     = 0.30   -- fast/slow sprite base scale

-- Animation commands per judgment (zoom values are relative to JUDGE_SCALE)
local JudgeCmds = {
	TapNoteScore_W1   = function(s) s:diffusealpha(1):zoom(JUDGE_SCALE*1.03):linear(0.036):zoom(JUDGE_SCALE):sleep(0.434):diffusealpha(0) end,
	TapNoteScore_W2   = function(s) s:diffusealpha(1):zoom(JUDGE_SCALE*1.03):linear(0.036):zoom(JUDGE_SCALE):sleep(0.434):diffusealpha(0) end,
	TapNoteScore_W3   = function(s) s:diffusealpha(1):zoom(JUDGE_SCALE*1.03):linear(0.036):zoom(JUDGE_SCALE):sleep(0.434):diffusealpha(0) end,
	TapNoteScore_W4   = function(s) s:diffusealpha(1):zoom(JUDGE_SCALE*1.03):linear(0.036):zoom(JUDGE_SCALE):sleep(0.434):diffusealpha(0) end,
	TapNoteScore_W5   = function(s) s:diffusealpha(1):zoom(JUDGE_SCALE*0.94):sleep(0.5):diffusealpha(0) end,
	TapNoteScore_Miss = function(s) s:diffusealpha(1):zoom(JUDGE_SCALE*0.94):sleep(0.5):diffusealpha(0) end,
}

-- Map TapNoteScore → spritesheet frame index (0-based)
-- Marvelous=0, Perfect=1, Great=2, Good=3, Miss=4
local TNSFrames = {
	TapNoteScore_W1   = 0,
	TapNoteScore_W2   = 1,
	TapNoteScore_W3   = 2,
	TapNoteScore_W4   = 3,
	TapNoteScore_W5   = 4,
	TapNoteScore_Miss = 4,
}

-- Helper: is this player in reverse scroll?
local function IsReverse()
	local opts = GalaxyOptions and GalaxyOptions[player]
	if opts and opts.Scroll == 2 then return true end
	-- Also check engine state as fallback
	return GAMESTATE:GetPlayerState(player):GetPlayerOptions("ModsLevel_Current"):Reverse() == 1
end

-- Helper: is fast/slow display enabled for this player?
local function ShowFastSlow()
	local opts = GalaxyOptions and GalaxyOptions[player]
	if opts then return opts.FastSlow == 1 end  -- 1=On, 2=Off
	return true
end

-- Helper: judgment Y offset based on JudgePosition (Near=closer to receptors)
local function GetJudgeY()
	local opts = GalaxyOptions and GalaxyOptions[player]
	local pos = opts and opts.JudgePosition or 1  -- 1=Near, 2=Far
	if pos == 2 then
		-- Far: further from receptors
		return IsReverse() and -100 or 100
	end
	-- Near: default (at receptors)
	return 0
end

local c

local t = Def.ActorFrame{}

t[#t+1] = Def.ActorFrame{
	InitCommand = function(self)
		c = self:GetChildren()
	end,

	-- ===== JUDGMENT SPRITE (drawn first = behind fast/slow) =====
	LoadActor("Judgment") .. {
		Name = "Judgment",
		InitCommand = function(self)
			self:pause():visible(false):draworder(-1)
		end,
		OnCommand = function(self)
			self:y(GetJudgeY())
		end,
		ResetCommand = cmd(finishtweening;stopeffect;visible,false),
	},

	-- ===== FAST / SLOW INDICATOR (drawn second = in front of judgment) =====
	LoadActor("FastSlow") .. {
		InitCommand = function(self)
			self:diffusealpha(0):animate(false)
		end,
		OnCommand = function(self)
			local fsY = IsReverse() and -50 or 50
			self:xy(0, GetJudgeY() + fsY)
		end,
		JudgmentMessageCommand = function(self, params)
			if not ShowFastSlow() then return end
			if params.Player ~= player then return end
			-- No fast/slow for Marvelous, W5, Miss, mines, or holds
			if params.TapNoteScore == "TapNoteScore_W1"
				or params.TapNoteScore == "TapNoteScore_W5"
				or params.TapNoteScore == "TapNoteScore_Miss"
				or params.TapNoteScore == "TapNoteScore_HitMine"
				or params.TapNoteScore == "TapNoteScore_AvoidMine"
				or params.HoldNoteScore
			then return end

			self:finishtweening()
			-- Early = Fast (frame 0), Late = Slow (frame 1)
			if params.Early then
				self:setstate(0)
			else
				self:setstate(1)
			end
			self:diffusealpha(1):zoom(FS_SCALE * 1.08)
				:linear(0.05):zoom(FS_SCALE)
				:sleep(0.4):diffusealpha(0)
		end,
	},

	-- ===== JUDGMENT MESSAGE HANDLER =====
	JudgmentMessageCommand = function(self, params)
		if params.Player ~= player then return end
		if params.HoldNoteScore then return end

		local iFrame = TNSFrames[params.TapNoteScore]
		if not iFrame then return end

		self:playcommand("Reset")

		c.Judgment:visible(true)
		c.Judgment:setstate(iFrame)
		JudgeCmds[params.TapNoteScore](c.Judgment)
	end,
}

return t
