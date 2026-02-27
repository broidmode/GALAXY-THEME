-- ScreenSelectStyle scroll item
-- Matches ScreenTitleMenu style: white text, all items visible.
local gc = Var("GameCommand")

local t = Def.ActorFrame{}

t[#t+1] = LoadFont("Common Normal") .. {
	Text = gc:GetText(),
	InitCommand = function(self)
		self:zoom(0.75):diffuse(color("#888888")):shadowlength(1)
	end,
	GainFocusCommand = function(self)
		self:stoptweening():linear(0.1):diffuse(Color.White):zoom(0.85)
	end,
	LoseFocusCommand = function(self)
		self:stoptweening():linear(0.1):diffuse(color("#888888")):zoom(0.75)
	end,
}

return t
