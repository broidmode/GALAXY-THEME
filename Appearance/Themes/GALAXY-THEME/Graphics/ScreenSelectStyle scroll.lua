-- ScreenSelectStyle scroll item
-- Matches ScreenTitleMenu style: white text, all items visible.
local gc = Var("GameCommand")

local t = Def.ActorFrame{}

t[#t+1] = Def.Text{ Font = RodinPath("db"), Size = FONT_L, Text = gc:GetText(),
	InitCommand = function(self)
		self:zoom(FONT_ZOOM):diffuse(color("#888888"))
		self:shadowlength(0)
	end,
	GainFocusCommand = function(self)
		self:stoptweening():linear(0.1):diffuse(Color.White):zoom(FONT_ZOOM * 1.1)
	end,
	LoseFocusCommand = function(self)
		self:stoptweening():linear(0.1):diffuse(color("#888888")):zoom(FONT_ZOOM)
	end,
}

return t
