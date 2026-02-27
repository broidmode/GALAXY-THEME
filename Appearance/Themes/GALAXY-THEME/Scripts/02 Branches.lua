-- GALAXY Theme Branches
-- Extends _fallback's Branch table via rawset() to preserve all inherited keys.
-- Only override the routing functions that differ from _fallback.

function SelectMusicOrCourse()
	if IsNetSMOnline() then
		return "ScreenNetSelectMusic"
	elseif GAMESTATE:IsCourseMode() then
		return "ScreenSelectCourse"
	else
		return "ScreenGalaxyMusic"
	end
end

-- Override: always show profile select after title menu
rawset(Branch, "AfterTitleMenu", function()
	if SONGMAN:GetNumSongs() == 0 and SONGMAN:GetNumAdditionalSongs() == 0 then
		return "ScreenHowToInstallSongs"
	end
	return "ScreenSelectProfile"
end)

-- Override: skip ProfileLoad and PlayMode screens
rawset(Branch, "AfterSelectStyle", function()
	return SelectMusicOrCourse()
end)
