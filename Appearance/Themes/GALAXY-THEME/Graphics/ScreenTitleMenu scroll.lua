-- ScreenTitleMenu scroll item
-- White text, all items visible. Focused item highlighted.
local gc = Var("GameCommand")

local t = Def.ActorFrame{}

t[#t+1] = Def.Text{ Font = RodinPath("db"), Size = 40, Text = gc:GetText(),
	InitCommand = function(self)
		self:zoom(0.75):diffuse(color("#888888"))
		self:shadowlength(1)
	end,
	GainFocusCommand = function(self)
		self:stoptweening():linear(0.1):diffuse(Color.White):zoom(0.85)
	end,
	LoseFocusCommand = function(self)
		self:stoptweening():linear(0.1):diffuse(color("#888888")):zoom(0.75)
	end,
}

return t
