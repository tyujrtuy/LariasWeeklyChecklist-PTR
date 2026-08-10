local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

-- Local dev deploys can stamp this file with a timestamp via scripts/deploy_to_wow.ps1.
-- Release/source builds keep it empty.
Addon.DEV_DEPLOY_TIMESTAMP = nil
