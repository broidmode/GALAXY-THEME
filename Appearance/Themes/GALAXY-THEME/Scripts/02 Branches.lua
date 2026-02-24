-- GALAXY Theme Branches
-- Controls screen flow / navigation routing

function SMOnlineScreen()
	for pn in ivalues(GAMESTATE:GetHumanPlayers()) do
		if not IsSMOnlineLoggedIn(pn) then
			return "ScreenSMOnlineLogin"
		end
	end
	return "ScreenNetRoom"
end

function SelectMusicOrCourse()
	if IsNetSMOnline() then
		return "ScreenNetSelectMusic"
	elseif GAMESTATE:IsCourseMode() then
		return "ScreenSelectCourse"
	else
		return "ScreenSelectMusic"
	end
end

Branch = {
	Init = function()
		return "ScreenInit"
	end,
	AfterInit = function()
		if GAMESTATE:GetCoinMode() == "CoinMode_Home" then
			return Branch.TitleMenu()
		else
			return "ScreenLogo"
		end
	end,
	TitleMenu = function()
		if GAMESTATE:GetCoinMode() == "CoinMode_Home" then
			return "ScreenTitleMenu"
		end
		return "ScreenTitleMenu"
	end,
	AfterTitleMenu = function()
		return "ScreenSelectProfile"
	end,
	AfterSelectProfile = function()
		if GAMESTATE:GetCurrentStyle() then
			return SelectMusicOrCourse()
		else
			return "ScreenSelectStyle"
		end
	end,
	AfterSelectStyle = function()
		return SelectMusicOrCourse()
	end,
	AfterSelectMusic = function()
		return "ScreenStageInformation"
	end,
	AfterStageInformation = function()
		return "ScreenGameplay"
	end,
	AfterGameplay = function()
		return "ScreenEvaluation"
	end,
	AfterEvaluation = function()
		-- Check if we need to continue for another stage
		if STATSMAN:GetStagesPlayed() < PREFSMAN:GetPreference("SongsPerPlay") then
			return SelectMusicOrCourse()
		end
		return "ScreenEvaluationSummary"
	end,
	AfterEvaluationSummary = function()
		return "ScreenProfileSave"
	end,
	AfterProfileSave = function()
		return Branch.TitleMenu()
	end,
}
