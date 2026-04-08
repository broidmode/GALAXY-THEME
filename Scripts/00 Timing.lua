TimingWindow = {}

TimingWindow[#TimingWindow+1] = function()
	return {
		Name = "DDR Modern",
		Timings = {
			['TapNoteScore_W1']=0.0170, -- Marvelous
			['TapNoteScore_W2']=0.0340, -- Perfect
			['TapNoteScore_W3']=0.0840, -- Great
			['TapNoteScore_W4']=0.1240, -- Good
			['TapNoteScore_HitMine']=0.0900,
			['TapNoteScore_Attack']=0.1350,
			['TapNoteScore_Hold']=0.2500,
			['TapNoteScore_Roll']=0.5000,
			['TapNoteScore_Checkpoint']=0.1664,
		}
	}
end

TimingWindow[#TimingWindow+1] = function()
	return {
		Name = "DDR Extreme",
		Timings = {
			['TapNoteScore_W1']=0.0133, -- Marvelous
			['TapNoteScore_W2']=0.0266, -- Perfect
			['TapNoteScore_W3']=0.0800, -- Great
			['TapNoteScore_W4']=0.1200, -- Good
			['TapNoteScore_W5']=0.1666, -- Boo
			['TapNoteScore_HitMine']=0.0900,
			['TapNoteScore_Attack']=0.1350,
			['TapNoteScore_Hold']=0.2500,
			['TapNoteScore_Roll']=0.5000,
			['TapNoteScore_Checkpoint']=0.1664,
		}
	}
end

function GetWindowSeconds(TimingWindow, Scale, Add)
	local fSecs = TimingWindow
	fSecs = fSecs * (Scale or 1.0)
	fSecs = fSecs + (Add or 0)
	return fSecs
end



function TimingOrder(TimTab)
	local con = {}
	local availableJudgments = {
		"ProW1","ProW2","ProW3","ProW4","ProW5",
		"W1","W2","W3","W4","W5",
		"HitMine","Attack","Hold","Roll","Checkpoint"
	}
	for k,v in pairs(TimTab) do
		for a,s in pairs( availableJudgments ) do
			if k == ('TapNoteScore_' .. s)  then
				con[ #con+1 ] = {k,v,a}
				break
			end
		end
	end
	table.sort( con, function(a,b) return a[3] < b[3] end )
	return con
end
