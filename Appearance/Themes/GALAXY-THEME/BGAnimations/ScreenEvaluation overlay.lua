-- ScreenEvaluation overlay — GALAXY
-- Finalizes per-chart results (combo lamp, flare grade, flare points)
-- and explicitly saves them to the profile directory.

local t = Def.ActorFrame{ Name = "EvalOverlay" }

t[#t+1] = Def.Actor{
	OnCommand = function(self)
		local song = GAMESTATE:GetCurrentSong()
		for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
			local steps = GAMESTATE:GetCurrentSteps(pn)
			if song and steps and FinalizeChartResult then
				FinalizeChartResult(pn, song, steps)
			end
			-- Explicitly save chart results to profile directory
			if PROFILEMAN:IsPersistentProfile(pn) and SaveChartResults then
				local slot = (pn == PLAYER_1) and "ProfileSlot_Player1" or "ProfileSlot_Player2"
				local dir = PROFILEMAN:GetProfileDir(slot)
				if dir and dir ~= "" then
					SaveChartResults(pn, dir)
				end
			end
		end
	end,
}

return t
