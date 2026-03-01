-- ScreenSelectProfile overlay (GALAXY)
-- Minimal white-on-black profile picker. Same interaction model as _fallback.
local lockSeconds = THEME:GetMetric(Var "LoadingScreen", "LockInputSecs") or 0
local readyforInput = false

-- Build scroller items: Guest first, then local profiles
function GetLocalProfiles()
	local t = {}
	-- Guest entry (always first — scroller item 0)
	t[#t+1] = Def.ActorFrame{
		LoadFont("Common Normal") .. {
			Text = "Guest",
			InitCommand = function(self)
				self:zoom(0.75):y(-6):shadowlength(1):diffuse(color("#66aaff")):ztest(true)
			end,
		},
		LoadFont("Common Normal") .. {
			Text = "Play without saving",
			InitCommand = function(self)
				self:zoom(0.45):y(10):shadowlength(1):diffuse(color("#888888")):ztest(true)
			end,
		},
	}
	-- Local profiles (scroller items 1..N)
	for p = 0, PROFILEMAN:GetNumLocalProfiles()-1 do
		local profile = PROFILEMAN:GetLocalProfileFromIndex(p)
		local numSongs = profile:GetNumTotalSongsPlayed()
		local songStr = numSongs == 1
			and numSongs.." song played"
			or  numSongs.." songs played"

		t[#t+1] = Def.ActorFrame{
			LoadFont("Common Normal") .. {
				Text = profile:GetDisplayName(),
				InitCommand = function(self)
					self:zoom(0.75):y(-6):shadowlength(1):diffuse(Color.White):ztest(true)
				end,
			},
			LoadFont("Common Normal") .. {
				Text = songStr,
				InitCommand = function(self)
					self:zoom(0.45):y(10):shadowlength(1):diffuse(color("#888888")):ztest(true)
				end,
			},
		}
	end
	return t
end

function LoadPlayerStuff(Player)
	local t = {}

	-- "Press START to join" frame (shown when player not joined)
	t[#t+1] = Def.ActorFrame{
		Name = "JoinFrame",
		LoadFont("Common Normal") .. {
			Text = "Press START to join",
			InitCommand = function(self)
				self:shadowlength(1):zoom(0.7):diffuse(color("#888888"))
			end,
			OnCommand = function(self)
				self:diffuseshift():effectcolor1(color("#888888")):effectcolor2(color("#444444"))
			end,
		},
	}

	-- Profile scroller
	t[#t+1] = Def.ActorScroller{
		Name = "Scroller",
		NumItemsToDraw = 7,
		OnCommand = function(self)
			self:y(0):SetFastCatchup(true):SetMask(400, 50):SetSecondsPerItem(0.1)
		end,
		TransformFunction = function(self, offset, itemIndex, numItems)
			self:y(math.floor(offset * 36))
			local focus = scale(math.abs(offset), 0, 2, 1, 0)
			self:diffusealpha(clamp(focus + 0.3, 0, 1))
		end,
		children = GetLocalProfiles(),
	}

	-- Selected profile name shown below
	t[#t+1] = LoadFont("Common Normal") .. {
		Name = "SelectedProfileText",
		InitCommand = function(self)
			self:y(130):shadowlength(1):zoom(0.6):diffuse(color("#888888"))
		end,
	}

	return t
end

-- Profile index mapping (with Guest at scroller item 0):
--   index  0 = Guest      (scroller item 0)
--   index  1 = profile #1  (scroller item 1)
--   index  k = profile #k  (scroller item k)
function UpdateInternal3(self, Player)
	local pn = (Player == PLAYER_1) and 1 or 2
	local frame = self:GetChild(string.format("P%uFrame", pn))
	local scroller = frame:GetChild("Scroller")
	local seltext = frame:GetChild("SelectedProfileText")
	local joinframe = frame:GetChild("JoinFrame")

	if GAMESTATE:IsHumanPlayer(Player) then
		frame:visible(true)
		if MEMCARDMAN:GetCardState(Player) == "MemoryCardState_none" then
			joinframe:visible(false)
			seltext:visible(true)
			scroller:visible(true)
			local ind = SCREENMAN:GetTopScreen():GetProfileIndex(Player)
			if ind == 0 then
				-- Guest selected
				scroller:SetDestinationItem(0)
				seltext:settext("Guest")
			elseif ind > 0 then
				-- Profile selected (scroller item = ind because Guest is item 0)
				scroller:SetDestinationItem(ind)
				seltext:settext(PROFILEMAN:GetLocalProfileFromIndex(ind - 1):GetDisplayName())
			else
				-- Just joined, no selection yet (-1); auto-select first profile
				if PROFILEMAN:GetNumLocalProfiles() > 0 then
					if SCREENMAN:GetTopScreen():SetProfileIndex(Player, 1) then
						scroller:SetDestinationItem(1)
						self:queuecommand("UpdateInternal2")
					end
				else
					-- No profiles: default to Guest
					SCREENMAN:GetTopScreen():SetProfileIndex(Player, 0)
					scroller:SetDestinationItem(0)
					seltext:settext("Guest")
				end
			end
		else
			scroller:visible(false)
			seltext:settext("Memory Card")
			SCREENMAN:GetTopScreen():SetProfileIndex(Player, 0)
		end
	else
		joinframe:visible(true)
		scroller:visible(false)
		seltext:visible(false)
	end
end

local t = Def.ActorFrame{
	StorageDevicesChangedMessageCommand = function(self)
		self:queuecommand("UpdateInternal2")
	end,

	CodeMessageCommand = function(self, params)
		if not readyforInput then return end
		if PREFSMAN:GetPreference("OnlyDedicatedMenuButtons") and not params.IsMenu then
			return
		end

		if params.Name == "Start" or params.Name == "Center" then
			MESSAGEMAN:Broadcast("StartButton")
			if not GAMESTATE:IsHumanPlayer(params.PlayerNumber) then
				SCREENMAN:GetTopScreen():SetProfileIndex(params.PlayerNumber, -1)
			else
				local success = SCREENMAN:GetTopScreen():Finish()
				if not success then
					-- Finish() may fail when a player is Guest (index 0, no memory card).
					-- Check if all human players have made a choice and force transition.
					local allReady = true
					for _, pn in ipairs(GAMESTATE:GetEnabledPlayers()) do
						local idx = SCREENMAN:GetTopScreen():GetProfileIndex(pn)
						if idx < 0 then allReady = false end
					end
					if allReady then
						SCREENMAN:GetTopScreen():StartTransitioningScreen("SM_GoToNextScreen")
					end
				end
			end
		end

		if params.Name == "Up" or params.Name == "Up2" or params.Name == "DownLeft" then
			if GAMESTATE:IsHumanPlayer(params.PlayerNumber) then
				local ind = SCREENMAN:GetTopScreen():GetProfileIndex(params.PlayerNumber)
				if ind > 0 then
					if SCREENMAN:GetTopScreen():SetProfileIndex(params.PlayerNumber, ind - 1) then
						MESSAGEMAN:Broadcast("DirectionButton")
						self:queuecommand("UpdateInternal2")
					end
				end
			end
		end

		if params.Name == "Down" or params.Name == "Down2" or params.Name == "DownRight" then
			if GAMESTATE:IsHumanPlayer(params.PlayerNumber) then
				local ind = SCREENMAN:GetTopScreen():GetProfileIndex(params.PlayerNumber)
				if ind >= 0 then
					if SCREENMAN:GetTopScreen():SetProfileIndex(params.PlayerNumber, ind + 1) then
						MESSAGEMAN:Broadcast("DirectionButton")
						self:queuecommand("UpdateInternal2")
					end
				end
			end
		end

		if params.Name == "Back" then
			if GAMESTATE:GetNumPlayersEnabled() == 0 then
				SCREENMAN:GetTopScreen():Cancel()
			else
				MESSAGEMAN:Broadcast("BackButton")
				SCREENMAN:GetTopScreen():SetProfileIndex(params.PlayerNumber, -2)
			end
		end
	end,

	PlayerJoinedMessageCommand = function(self)
		self:queuecommand("UpdateInternal2")
	end,
	PlayerUnjoinedMessageCommand = function(self)
		self:queuecommand("UpdateInternal2")
	end,
	OnCommand = function(self)
		self:queuecommand("UpdateInternal2")
	end,
	UpdateInternal2Command = function(self)
		UpdateInternal3(self, PLAYER_1)
		UpdateInternal3(self, PLAYER_2)
	end,

	children = {
		-- Player 1 frame
		Def.ActorFrame{
			Name = "P1Frame",
			InitCommand = function(self)
				self:x(SCREEN_CENTER_X - 160):y(SCREEN_CENTER_Y)
			end,
			OnCommand = function(self)
				self:zoom(0):bounceend(0.25):zoom(1)
			end,
			OffCommand = function(self)
				self:bouncebegin(0.25):zoom(0)
			end,
			PlayerJoinedMessageCommand = function(self, param)
				if param.Player == PLAYER_1 then
					self:zoom(1.1):bounceend(0.15):zoom(1)
				end
			end,
			children = LoadPlayerStuff(PLAYER_1),
		},
		-- Player 2 frame
		Def.ActorFrame{
			Name = "P2Frame",
			InitCommand = function(self)
				self:x(SCREEN_CENTER_X + 160):y(SCREEN_CENTER_Y)
			end,
			OnCommand = function(self)
				self:zoom(0):bounceend(0.25):zoom(1)
			end,
			OffCommand = function(self)
				self:bouncebegin(0.25):zoom(0)
			end,
			PlayerJoinedMessageCommand = function(self, param)
				if param.Player == PLAYER_2 then
					self:zoom(1.1):bounceend(0.15):zoom(1)
				end
			end,
			children = LoadPlayerStuff(PLAYER_2),
		},
		-- Sounds
		LoadActor(THEME:GetPathS("Common", "start")) .. {
			StartButtonMessageCommand = function(self) self:play() end,
		},
		LoadActor(THEME:GetPathS("Common", "cancel")) .. {
			BackButtonMessageCommand = function(self) self:play() end,
		},
		LoadActor(THEME:GetPathS("Common", "value")) .. {
			DirectionButtonMessageCommand = function(self) self:play() end,
		},
		-- Input lock delay
		Def.Actor{
			OnCommand = function(self)
				self:sleep(lockSeconds):queuecommand("UnlockInput")
			end,
			UnlockInputCommand = function(self)
				readyforInput = true
			end,
		},
	},
}

return t
