-- ScreenEvaluation background
return Def.ActorFrame{
	Def.Quad{
		InitCommand=function(self)
			self:FullScreen():diffuse(color("#0a0a2e"))
		end,
	},
}
