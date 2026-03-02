-- ScreenTitleMenu scroll item
-- White text, all items visible. Focused item highlighted.
local gc = Var("GameCommand")

local t = Def.ActorFrame{}

t[#t+1] = Def.Text{ Font = RodinPath("db"), Size = FontL("db"), Text = gc:GetText(),
	InitCommand = function(self)
		self:zoom(FONT_ZOOM):diffuse(color("#888888"))
		self:shadowlength(0)
		self:SetTextureFiltering(false)
	end,
	GainFocusCommand = function(self)
		self:stoptweening():linear(0.1):diffuse(Color.White):zoom(FONT_ZOOM * 1.1)
	end,
	LoseFocusCommand = function(self)
		self:stoptweening():linear(0.1):diffuse(color("#888888")):zoom(FONT_ZOOM)
	end,
}

return t
