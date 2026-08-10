-- Localization companion: early-init.
-- Runs before locale files so the LOAD_ALL_LOCALES guard works at load time.
do
    local _GetMeta = C_AddOns and C_AddOns.GetAddOnMetadata
    if _GetMeta then
        local mainVer   = _GetMeta("LariasWeeklyChecklist", "Version") or ""
        local localeVer = _GetMeta("LariasWeeklyChecklist_Localization", "Version") or ""
        if mainVer:find("%-") or localeVer:find("%-") then
            _G["LARIASWEEKLYCHECKLIST_LOAD_ALL_LOCALES"] = true
        end
    end
end
