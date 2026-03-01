-- Transparent Sprite hold judgment — replaces _fallback's _blank redir.
-- Must return a Sprite (not ActorFrame) because the engine calls
-- Sprite-specific methods (SetState) on the HoldJudgment actor.
-- GALAXY handles gauge display entirely in the gameplay overlay.
return LoadActor(THEME:GetPathG("", "_blank"))
