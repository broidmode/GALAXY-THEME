-- GALAXY Theme Branches
-- Extends _fallback's Branch table via rawset() to preserve all inherited keys.
-- Only override the routing functions that differ from _fallback.

function SelectMusicOrCourse()
	if type(IsNetSMOnline) == "function" and IsNetSMOnline() then
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

-- Override: after profile select, route based on player count
-- Two players → auto-set Versus style, skip style select
-- One player  → show style select (Single / Double)
-- Apply active timing preset before entering music select flow.
rawset(Branch, "AfterSelectProfile", function()
	ApplyTimingPreset(GetGalaxyPref("TimingMode"))
	LoadGuestDefaults()
	if GAMESTATE:GetNumPlayersEnabled() >= 2 then
		GAMESTATE:SetCurrentStyle("versus")
		return SelectMusicOrCourse()
	end
	return "ScreenSelectStyle"
end)

-- Override: skip ProfileLoad and PlayMode screens
-- Also apply timing for the 1-player path (profile → style → here).
rawset(Branch, "AfterSelectStyle", function()
	ApplyTimingPreset(GetGalaxyPref("TimingMode"))
	return SelectMusicOrCourse()
end)
