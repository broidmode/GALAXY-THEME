-- GALAXY helper functions
-- Compatibility layer for ITGmania (no runtime FreeType/Def.Text support).
-- See !Docs/outline.md for architecture overview.

-- ===== PER-WEIGHT FONT SIZE TABLE =====
-- These values were used by OutFox's Def.Text (runtime FreeType rendering).
-- ITGmania uses pre-rendered bitmap fonts, so the Size parameter is ignored.
-- We keep the table and helpers so existing code doesn't break; the values
-- are simply unused at runtime until proper bitmap fonts are generated.

local _FontBase = {
--              S    M    L          -- tier usage
	l  = { S = 14, M = 20, L = 30 },  -- Light
	m  = { S = 14, M = 20, L = 30 },  -- Medium
	db = { S = 14, M = 20, L = 30 },  -- DemiBold
	b  = { S = 14, M = 20, L = 30 },  -- Bold
	eb = { S = 14, M = 20, L = 30 },  -- ExtraBold
	ub = { S = 14, M = 20, L = 30 },  -- UltraBold
}

local _displayH = PREFSMAN:GetPreference("DisplayHeight") or 1080
local _scale    = _displayH / SCREEN_HEIGHT   -- display px per virtual px

FONT_ZOOM = 1 / _scale   -- apply to every BitmapText to keep virtual-coord layout

-- ---------------------------------------------------------------------------
-- Scaled size getters (retained for API compat; values unused by BitmapText)
-- ---------------------------------------------------------------------------
function FontS(w)  return math.floor(_FontBase[w].S * _scale + 0.5) end
function FontM(w)  return math.floor(_FontBase[w].M * _scale + 0.5) end
function FontL(w)  return math.floor(_FontBase[w].L * _scale + 0.5) end

function FontMaxWidth(virtualPx)
	return virtualPx / FONT_ZOOM
end

-- ===== FONT NAMES FOR ITGMANIA =====
-- ITGmania uses pre-rendered bitmap fonts referenced by name.
-- These map GALAXY weight keys to _fallback bitmap font names.
-- TODO: Generate dedicated Rodin bitmap fonts with Texture Font Generator.
local _BitmapFontMap = {
	l  = "Common Normal",     -- Light → Open Sans Semibold 24px
	m  = "Common Normal",     -- Medium
	db = "Common Bold",       -- DemiBold → Roboto Black Bold 24px
	b  = "Common Bold",       -- Bold
	eb = "Common Bold",       -- ExtraBold
	ub = "Common Bold",       -- UltraBold
}

-- ---------------------------------------------------------------------------
-- RodinPath(weight) → returns a BitmapText-compatible font name.
-- In OutFox this returned an OTF file path; now it returns a font
-- definition name that BitmapText can load.
-- ---------------------------------------------------------------------------
function RodinPath(weight)
	weight = weight or "m"
	if weight == "db" then weight = "b" end
	return _BitmapFontMap[weight] or "Common Normal"
end

-- ===== DEF.TEXT COMPATIBILITY SHIM =====
-- OutFox provided Def.Text{} for runtime FreeType text rendering.
-- ITGmania only has Def.BitmapText{}.  This shim allows existing code
-- to use Def.Text{} unchanged — the Size parameter is silently stripped,
-- and Font is passed through (now returns a bitmap font name via
-- RodinPath above).
rawset(Def, "Text", function(params)
	params.Size = nil           -- BitmapText doesn't support Size
	params.Class = "BitmapText"
	-- Apply DefMetatable so the concat operator (..) still works
	setmetatable(params, DefMetatable)
	return params
end)

-- ===== BITMAPTEXT COMPAT: Regen() =====
-- OutFox's Def.Text had a :Regen() method to force text relayout.
-- ITGmania's BitmapText does this automatically in settext().
-- Add a no-op so chained calls like self:settext("x"):Regen() don't crash.
do
	local bmt_mt = getmetatable(Def.BitmapText{Font="Common Normal",Text=""})
	if bmt_mt and not bmt_mt.Regen then
		-- Can't always get the C++ metatable; fall back to a global shim.
	end
end
-- Fallback: patch via Actor base class if available.
-- If the engine exposes no metatable, we rely on Lua's pcall-safe approach
-- in each call site, which is impractical.  Instead, we monkey-patch later
-- at actor creation time via InitCommand.  But simpler: just define a
-- global function on the Actor class table.
if Actor and Actor.Regen == nil then
	Actor.Regen = function(self) return self end
end

-- Resolve a jacket image path for a song or course, with fallback chain
function GetJacketPath(item, fallback)
	if item:HasJacket() then
		return item:GetJacketPath()
	elseif item:HasBackground() then
		return item:GetBackgroundPath()
	elseif item:HasBanner() then
		return item:GetBannerPath()
	else
		return fallback or THEME:GetPathG("Common", "fallback jacket")
	end
end
