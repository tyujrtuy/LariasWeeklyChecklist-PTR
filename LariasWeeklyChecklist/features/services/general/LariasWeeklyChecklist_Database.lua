-- LariasWeeklyChecklist_Database.lua
-- SavedVariables and per-character/account-wide database helpers.
--
-- This module owns AceDB setup, display preferences, and hidden-row state used
-- by the tracking panels.

local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local type, tostring = type, tostring
local pairs = pairs
local table_sort = table.sort

local MAX_TRACKED_CURRENCIES = 12

-- Default values applied to each character's data block on first access.
-- Display-preference defaults live in db.global so they are shared across all
-- characters; keys with false/nil defaults are intentionally omitted.
local CHAR_DEFAULTS = {
    startAtSectionId = "",
}

local function MigrateProfileDataToGlobalChars(self)
    if not (self and self.db and self.db.global) then return end

    local ownKey = self:GetCurrentProfileKey()
    if ownKey == "" then return end

    local chars = self.db.global.chars
    if type(chars) ~= "table" then return end

    chars[ownKey] = chars[ownKey] or {}
    local cdb = chars[ownKey]
    if cdb._migrated then return end
    cdb._migrated = true

    local oldProf = self.db and self.db.profile
    Addon.CoreLogic.MigrateLegacyProfile(oldProf, cdb)
end

local function BuildActiveTrackedCurrencyIDSet(self)
    local tracking = self and self.TRACKING or {}
    local activeIDs = {}

    local function addCurrency(value)
        local id = tonumber(value)
        if id and id > 0 then activeIDs[id] = true end
    end

    local function addCurrencyList(values)
        if type(values) ~= "table" then return end
        for i = 1, #values do
            addCurrency(values[i])
        end
    end

    addCurrencyList(tracking.crestCurrencyIDs)
    addCurrency(tracking.catalystCurrencyID)
    addCurrency(tracking.sparkCurrencyID)
    addCurrency(tracking.cofferKeysCurrencyID)
    addCurrency(tracking.cofferKeysDisplayCurrencyID)

    local bonusRollValue = tracking.bonusRollCurrencyID or tracking.bonusRollCurrencyIDs or tracking.miscCurrencyIDs
    if type(bonusRollValue) == "table" then
        addCurrencyList(bonusRollValue)
    else
        addCurrency(bonusRollValue)
    end

    return activeIDs
end

local function PruneStaleTrackedCurrencies(self, globalDb)
    if type(globalDb) ~= "table" then return end

    local activeCurrencyIDs = BuildActiveTrackedCurrencyIDSet(self)
    if not next(activeCurrencyIDs) then return end

    local removedStaleTrackedEntry = false
    local config = globalDb.trackedCurrencyConfig
    if type(config) == "table" then
        for i = #config, 1, -1 do
            local entry = config[i]
            local id = type(entry) == "table" and tonumber(entry.id or entry.currencyID) or tonumber(entry)
            local source = type(entry) == "table" and entry.source or nil
            if id and not activeCurrencyIDs[id] and source ~= "custom" then
                table.remove(config, i)
                removedStaleTrackedEntry = true
            end
        end
    end

    if removedStaleTrackedEntry then
        globalDb._trackedCurrencyConfigNeedsActiveSeasonReset = true
    end

    local chars = globalDb.chars
    if type(chars) == "table" then
        for _, charDb in pairs(chars) do
            local hidden = type(charDb) == "table" and charDb.hiddenCurrencies or nil
            if type(hidden) == "table" then
                for idStr in pairs(hidden) do
                    local id = tonumber(idStr)
                    if id and not activeCurrencyIDs[id] then
                        hidden[idStr] = nil
                    end
                end
            end
        end
    end
end

function Addon:SetupAddonDB()
    if self.db then return end

    local defaults = {
        profile = {},  -- intentionally empty; all data lives in global
        global = {
            _newestSeenRemoteVersion = "",
            _newestSeenRemoteSender  = "",
            -- Account-wide UI state (shared across all characters on this account).
            mainFramePos  = false,
            mainFrameWin  = false,  -- LibWindow-1.1 position+scale storage
            mainFrameSize = false,
            ilvlRefPos    = false,
            ilvlRefSize   = false,
            uiScalePct    = 100,
            uiOpacityPct  = 65,
            themeColors   = {},  -- { bgR, bgG, bgB, textR, textG, textB }
            minimap       = {},  -- LibDBIcon position/hide state
            charClasses   = {},  -- [profileKey] = classToken (e.g. "WARRIOR")
            charLevels    = {},  -- [profileKey] = player level at last login
            hiddenChars   = {},  -- [profileKey] = true
            trackedLootChars = {}, -- [profileKey] = true
            altSummaryCharOrder = {}, -- ordered profileKeys for manual Alt Summary priority
            altSummarySectionOrder = {}, -- ordered section keys for Alt Summary categories
            altSummaryRowOrder = {}, -- [sectionKey] = ordered row keys for Alt Summary rows
            altSummaryWin = false, -- LibWindow-1.1 position storage
            currencyConfigWin = false, -- LibWindow-1.1 position storage
            crestConvertWin = false, -- LibWindow-1.1 position storage
            -- Account-wide display preferences.
            hideCompletedSections = true,
            showGreatVault        = true,
            showCurrency          = true,
            showChangeWeekBtn     = false,
            showIlvlRefBtn        = true,
            showCharPickerBtn     = true,
            showAltSummaryBtn     = true,
            showScaleSlider       = true,
            showOpacitySlider     = true,
            hideUpdateNotice      = false,
            _seenGuideDocUrl      = "",
            _seenFutureGuideAnnouncements = {},
            localeOverride        = "",  -- "" = auto
            -- Per-character data, keyed by "CharName - Realm".
            chars = {},
        },
    }

    -- AceDB still gives each character a profile slot for profileKeys
    -- enumeration, but all actual addon data lives in global.chars.
    self.db = LibStub("AceDB-3.0"):New(addonName .. "DB", defaults)
    MigrateProfileDataToGlobalChars(self)
    PruneStaleTrackedCurrencies(self, self.db and self.db.global)

    local gdb = self.db and self.db.global
    if gdb and not gdb._raidBonusRollReminderReenabled then
        gdb._raidBonusRollReminderReenabled = true
        gdb.raidBonusRollReminderDisabled = nil
    end
end

local function RefreshAfterHiddenChange(self)
    if self.RequestTrackingUpdate then self:RequestTrackingUpdate() end
    if self.RequestRefresh then self:RequestRefresh()
    elseif self.Refresh then self:Refresh() end
    if self.RefreshAltsSummary    then self:RefreshAltsSummary()    end
    if self.SyncGearPopup         then self:SyncGearPopup()         end
    if self._restoreHiddenFrame and self._restoreHiddenFrame:IsShown() then
        self:OpenRestoreHiddenCurrencies(nil)
    end
end

local function RefreshAfterTrackedLootChange(self)
    if self.RequestRefresh then self:RequestRefresh()
    elseif self.Refresh then self:Refresh() end
    if self.RefreshAltsSummary then self:RefreshAltsSummary() end
end

local function RefreshAfterTrackedCurrencyConfigChange(self)
    if self.RequestTrackingUpdate then self:RequestTrackingUpdate() end
    if self.RequestRefresh then self:RequestRefresh()
    elseif self.Refresh then self:Refresh() end
    if self.RefreshAltsSummary      then self:RefreshAltsSummary()      end
    if self.SyncGearPopup           then self:SyncGearPopup()           end
    if self.RefreshCurrencyConfigPopup then self:RefreshCurrencyConfigPopup() end
end

local function GetBuiltInTrackedItemEntries(self)
    -- Weapon/trinket upgrade reminders were removed. Keep this hook returning an
    -- empty list so the broader item-row plumbing can stay available if needed.
    return {}
end

local function IsRemovedBuiltInTrackedItemID(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end

    local tracking = Addon and Addon.TRACKING or {}
    local weaponUpgrade = tracking and tracking.weaponUpgrade
    local combinedItemID = tonumber(weaponUpgrade and weaponUpgrade.combinedItemID)
    if combinedItemID and combinedItemID > 0 and itemID == combinedItemID then
        return true
    end

    -- Previous Midnight Season 1 combined weapon/trinket upgrade item.
    return itemID == 268552
end

local function GetBuiltInTrackedConfigEntries(self)
    local tracking = self and self.TRACKING or {}
    local out = {}
    local seen = {}

    local function pushCurrency(id)
        id = tonumber(id)
        if not (id and id > 0) then return false end
        local key = "currency:" .. id
        if seen[key] then return false end
        seen[key] = true
        out[#out + 1] = { id = id, enabled = true, source = "builtin" }
        if #out >= MAX_TRACKED_CURRENCIES then return true end
        return false
    end

    local crestIDs = tracking and tracking.crestCurrencyIDs
    if type(crestIDs) == "table" then
        for i = 1, #crestIDs do
            if pushCurrency(crestIDs[i]) then return out end
        end
    end

    if pushCurrency(tracking and tracking.catalystCurrencyID) then return out end
    if pushCurrency(tracking and tracking.sparkCurrencyID)    then return out end
    if pushCurrency(tracking and tracking.cofferKeysDisplayCurrencyID) then return out end

    local bonusRollValue = tracking and (tracking.bonusRollCurrencyID or tracking.bonusRollCurrencyIDs or tracking.miscCurrencyIDs)
    if type(bonusRollValue) == "table" then
        for i = 1, #bonusRollValue do
            if pushCurrency(bonusRollValue[i]) then return out end
        end
    else
        if pushCurrency(bonusRollValue) then return out end
    end

    local builtInItems = GetBuiltInTrackedItemEntries(self)
    for i = 1, #builtInItems do
        local entry = builtInItems[i]
        local itemID = tonumber(entry and entry.itemID)
        if itemID then
            local key = "item:" .. itemID
            if not seen[key] then
                seen[key] = true
                out[#out + 1] = {
                    itemID = itemID,
                    enabled = entry.enabled ~= false,
                    source = entry.source or "builtin-item",
                    kind = entry.kind or "item",
                }
            end
        end
    end

    return out
end

local NormalizeTrackedCurrencyConfig

local function BuildDefaultTrackedCurrencyConfig(self)
    return GetBuiltInTrackedConfigEntries(self)
end

local function ResetTrackedCurrencyConfigForActiveSeason(self, gdb)
    if type(gdb) ~= "table" then return end

    local entries = BuildDefaultTrackedCurrencyConfig(self)
    local seen = {}
    for i = 1, #entries do
        local entry = entries[i]
        local id = tonumber(entry and entry.id)
        local itemID = tonumber(entry and entry.itemID)
        if id and id > 0 then
            seen["currency:" .. id] = true
        elseif itemID and itemID > 0 then
            seen["item:" .. itemID] = true
        end
    end

    local existing = gdb.trackedCurrencyConfig
    if type(existing) == "table" then
        for i = 1, #existing do
            local entry = existing[i]
            local id = type(entry) == "table" and tonumber(entry.id or entry.currencyID) or tonumber(entry)
            local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil
            local source = type(entry) == "table" and entry.source or nil
            if source == "custom" and id and id > 0 and not seen["currency:" .. id] then
                entries[#entries + 1] = entry
                seen["currency:" .. id] = true
            elseif source == "custom-item" and itemID and itemID > 0 and not seen["item:" .. itemID] then
                entries[#entries + 1] = entry
                seen["item:" .. itemID] = true
            end
        end
    end

    gdb.trackedCurrencyConfig = NormalizeTrackedCurrencyConfig(self, entries, false)
end

function Addon:ResetTrackedCurrencyConfigForActiveSeason()
    local gdb = self:EnsurePrefs()
    ResetTrackedCurrencyConfigForActiveSeason(self, gdb)
end

local function IsBuiltInTrackedCurrencyID(self, currencyID)
    local id = tonumber(currencyID)
    if not id then return false end

    local tracking = self and self.TRACKING or {}
    local crestIDs = tracking.crestCurrencyIDs
    if type(crestIDs) == "table" then
        for i = 1, #crestIDs do
            if tonumber(crestIDs[i]) == id then return true end
        end
    end

    if tonumber(tracking.catalystCurrencyID) == id then return true end
    if tonumber(tracking.sparkCurrencyID) == id then return true end
    if tonumber(tracking.cofferKeysDisplayCurrencyID) == id then return true end

    local bonusRollValue = tracking.bonusRollCurrencyID or tracking.bonusRollCurrencyIDs or tracking.miscCurrencyIDs
    if type(bonusRollValue) == "table" then
        for i = 1, #bonusRollValue do
            if tonumber(bonusRollValue[i]) == id then return true end
        end
    elseif tonumber(bonusRollValue) == id then
        return true
    end

    return false
end

local function IsBuiltInTrackedItemID(self, itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    local builtInItems = GetBuiltInTrackedItemEntries(self)
    for i = 1, #builtInItems do
        if tonumber(builtInItems[i].itemID) == itemID then
            return true
        end
    end
    return false
end

function Addon:IsBuiltInTrackedCurrencyID(currencyID)
    return IsBuiltInTrackedCurrencyID(self, currencyID)
end

NormalizeTrackedCurrencyConfig = function(self, entries, allowEmpty)
    local out = {}
    local seen = {}

    if type(entries) == "table" then
        for i = 1, #entries do
            local entry = entries[i]
            local id = type(entry) == "table" and tonumber(entry.id or entry.currencyID) or tonumber(entry)
            local itemID = type(entry) == "table" and tonumber(entry.itemID) or nil

            if itemID and itemID > 0 then
                local key = "item:" .. itemID
                if not seen[key] then
                    seen[key] = true
                    out[#out + 1] = {
                        itemID = itemID,
                        enabled = not (type(entry) == "table" and entry.enabled == false),
                        source = (type(entry) == "table" and entry.source) or (IsBuiltInTrackedItemID(self, itemID) and "builtin-item") or "custom-item",
                        kind = (type(entry) == "table" and entry.kind) or "item",
                    }
                end
            elseif id and id > 0 then
                local key = "currency:" .. id
                if not seen[key] then
                    seen[key] = true
                    local source = "custom"
                    if type(entry) == "table" and entry.source == "custom" then
                        source = "custom"
                    elseif IsBuiltInTrackedCurrencyID(self, id) then
                        source = "builtin"
                    end
                    out[#out + 1] = {
                        id = id,
                        enabled = not (type(entry) == "table" and entry.enabled == false),
                        source = source,
                    }
                end
            end
        end
    end

    if #out == 0 and not allowEmpty then
        return BuildDefaultTrackedCurrencyConfig(self)
    end

    return out
end

local function RestoreMissingBuiltInTrackedCurrencies(self, entries)
    if type(entries) ~= "table" then return entries end

    local seen = {}
    for i = 1, #entries do
        local entry = entries[i]
        local id = tonumber(entry and entry.id)
        local itemID = tonumber(entry and entry.itemID)
        if id and id > 0 then
            seen["currency:" .. id] = true
        elseif itemID and itemID > 0 then
            seen["item:" .. itemID] = true
        end
    end

    local builtIns = GetBuiltInTrackedConfigEntries(self)
    for i = 1, #builtIns do
        local entry = builtIns[i]
        local id = tonumber(entry and entry.id)
        local itemID = tonumber(entry and entry.itemID)
        if id and id > 0 and not seen["currency:" .. id] then
            entries[#entries + 1] = {
                id = id,
                enabled = false,
                source = "builtin",
            }
            seen["currency:" .. id] = true
        elseif itemID and itemID > 0 and not seen["item:" .. itemID] then
            entries[#entries + 1] = {
                itemID = itemID,
                enabled = false,
                source = entry.source or "builtin-item",
                kind = entry.kind or "item",
            }
            seen["item:" .. itemID] = true
        end
    end

    return entries
end

local function HasEnabledBuiltInTrackedCurrency(self, entries)
    if type(entries) ~= "table" then return false end

    for i = 1, #entries do
        local entry = entries[i]
        local id = tonumber(entry and entry.id)
        if id and entry.enabled ~= false and IsBuiltInTrackedCurrencyID(self, id) then
            return true
        end
    end

    return false
end

local function RefreshAfterAltSummaryOrderChange(self)
    if self.MarkAltsSummaryDirty then
        self:MarkAltsSummaryDirty(true)
        return
    end
    if self.RefreshAltsSummary then
        self:RefreshAltsSummary()
    elseif self.RequestRefresh then
        self:RequestRefresh()
    elseif self.Refresh then
        self:Refresh()
    end
end

local function GetActiveCharKey(self)
    return self._viewingChar or self:GetCurrentProfileKey()
end

local function ReadCharDB(self)
    local key = GetActiveCharKey(self)
    local gdb = self.db and self.db.global
    return gdb and gdb.chars and gdb.chars[key]
end

local function GetOrCreateCharDB(self)
    local key = GetActiveCharKey(self)
    if not (key and key ~= "") then return nil end
    local gdb = self.db and self.db.global
    if not gdb then
        return nil
    end
    gdb.chars      = gdb.chars      or {}
    gdb.chars[key] = gdb.chars[key] or {}
    return gdb.chars[key]
end

function Addon:IsCurrencyHidden(currencyID)
    if not currencyID then return false end
    local cdb = ReadCharDB(self)
    return cdb and cdb.hiddenCurrencies and cdb.hiddenCurrencies[tostring(currencyID)] == true
end

function Addon:SetCurrencyHidden(currencyID, hidden)
    local cdb = GetOrCreateCharDB(self)
    if not cdb then return end
    cdb.hiddenCurrencies = cdb.hiddenCurrencies or {}
    cdb.hiddenCurrencies[tostring(currencyID)] = hidden or nil
    RefreshAfterHiddenChange(self)
end

function Addon:IsQuestHidden(questKey)
    if not questKey then return false end
    local cdb = ReadCharDB(self)
    if not (cdb and cdb.hiddenQuests) then return false end
    if cdb.hiddenQuests[questKey] == true then return true end
    if questKey == "delveBoss" and cdb.hiddenQuests.nullaeusSpoils == true then return true end
    return false
end

function Addon:SetQuestHidden(questKey, hidden)
    local cdb = GetOrCreateCharDB(self)
    if not cdb then return end
    cdb.hiddenQuests = cdb.hiddenQuests or {}
    cdb.hiddenQuests[questKey] = hidden or nil
    if questKey == "delveBoss" then
        cdb.hiddenQuests.nullaeusSpoils = hidden or nil
    end
    RefreshAfterHiddenChange(self)
end

function Addon:IsItemHidden(itemID)
    itemID = tonumber(itemID)
    if not itemID then return false end
    local cdb = ReadCharDB(self)
    return cdb and cdb.hiddenItems and cdb.hiddenItems[tostring(itemID)] == true
end

function Addon:SetItemHidden(itemID, hidden)
    itemID = tonumber(itemID)
    if not itemID then return end
    local cdb = GetOrCreateCharDB(self)
    if not cdb then return end
    cdb.hiddenItems = cdb.hiddenItems or {}
    cdb.hiddenItems[tostring(itemID)] = hidden or nil
    RefreshAfterHiddenChange(self)
end

function Addon:IsCrestAchievementHidden(tierIdx)
    tierIdx = tonumber(tierIdx)
    if not tierIdx then return false end
    local gdb = self.db and self.db.global
    return gdb and gdb.hiddenCrestAchievements and gdb.hiddenCrestAchievements[tostring(tierIdx)] == true
end

function Addon:SetCrestAchievementHidden(tierIdx, hidden)
    tierIdx = tonumber(tierIdx)
    if not tierIdx then return end
    local gdb = self.db and self.db.global
    if not gdb then return end
    gdb.hiddenCrestAchievements = gdb.hiddenCrestAchievements or {}
    gdb.hiddenCrestAchievements[tostring(tierIdx)] = hidden or nil
    RefreshAfterHiddenChange(self)
end

function Addon:GetHiddenQuestList()
    local cdb = ReadCharDB(self)
    local hidden = cdb and cdb.hiddenQuests
    if not hidden then return {} end
    local L = self.L or {}
    local questNames = {
        delversBounty  = L.TRACKING_QUEST_DELVERS_BOUNTY  or "Trovehunter's Bounty",
        weeklyPrey     = L.TRACKING_QUEST_WEEKLY_PREY     or "Weekly Prey",
        delveBoss      = L.TRACKING_QUEST_DELVE_BOSS      or L.TRACKING_QUEST_NULLAEUS_SPOILS or "Delve Boss",
        nullaeusSpoils = L.TRACKING_QUEST_DELVE_BOSS      or L.TRACKING_QUEST_NULLAEUS_SPOILS or "Delve Boss",
    }
    local result = {}
    for qKey in pairs(hidden) do
        result[#result + 1] = { key = qKey, name = questNames[qKey] or qKey }
    end
    table_sort(result, function(a, b) return a.name < b.name end)
    return result
end

function Addon:GetHiddenCrestAchievementList()
    local gdb = self.db and self.db.global
    local hidden = gdb and gdb.hiddenCrestAchievements
    if not hidden then return {} end
    local result = {}
    for tierStr in pairs(hidden) do
        local tierIdx = tonumber(tierStr)
        if tierIdx then
            local name = self.GetCrestAchievementName and self:GetCrestAchievementName(tierIdx)
                or ("Tier " .. tierIdx)
            result[#result + 1] = { tierIdx = tierIdx, name = name }
        end
    end
    table_sort(result, function(a, b) return a.name < b.name end)
    return result
end

function Addon:GetHiddenCurrencyList()
    local cdb = ReadCharDB(self)
    local hidden = cdb and cdb.hiddenCurrencies
    if not hidden then return {} end
    local result = {}
    for idStr in pairs(hidden) do
        local id = tonumber(idStr)
        if id then
            local name = idStr
            if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local info = C_CurrencyInfo.GetCurrencyInfo(id)
                if info and info.name then name = info.name end
            end
            result[#result + 1] = { id = id, name = name }
        end
    end
    table_sort(result, function(a, b) return a.name < b.name end)
    return result
end

function Addon:GetHiddenItemList()
    local cdb = ReadCharDB(self)
    local hidden = cdb and cdb.hiddenItems
    if not hidden then return {} end
    local result = {}
    for idStr in pairs(hidden) do
        local id = tonumber(idStr)
        if id then
            local name = idStr
            local itemName = GetItemInfo and GetItemInfo(id)
            if itemName then name = itemName end
            result[#result + 1] = { id = id, name = name }
        end
    end
    table_sort(result, function(a, b) return a.name < b.name end)
    return result
end

function Addon:IsLootCharTracked(profileKey)
    if not profileKey then return false end
    local gdb = self.db and self.db.global
    return gdb and gdb.trackedLootChars and gdb.trackedLootChars[profileKey] == true or false
end

function Addon:SetLootCharTracked(profileKey, tracked)
    if type(profileKey) ~= "string" or profileKey == "" then return end
    local ownKey = self.GetCurrentProfileKey and self:GetCurrentProfileKey() or nil
    if ownKey and profileKey:lower() == ownKey:lower() then return end
    local gdb = self.db and self.db.global
    if not gdb then return end
    gdb.trackedLootChars = gdb.trackedLootChars or {}
    gdb.trackedLootChars[profileKey] = tracked and true or nil
    RefreshAfterTrackedLootChange(self)
end

function Addon:GetTrackedLootCharKeys()
    local gdb = self.db and self.db.global
    local tracked = gdb and gdb.trackedLootChars
    if type(tracked) ~= "table" then return {} end

    local ownKey = self.GetCurrentProfileKey and self:GetCurrentProfileKey() or nil
    local keys = {}
    for profileKey, enabled in pairs(tracked) do
        if enabled == true and (not ownKey or profileKey:lower() ~= ownKey:lower()) then
            keys[#keys + 1] = profileKey
        end
    end

    table_sort(keys, function(a, b)
        local aDb = gdb and gdb.chars and gdb.chars[a]
        local bDb = gdb and gdb.chars and gdb.chars[b]
        local aIlvl = tonumber(aDb and aDb.ilvl) or 0
        local bIlvl = tonumber(bDb and bDb.ilvl) or 0
        if aIlvl ~= bIlvl then return aIlvl > bIlvl end
        return tostring(a) < tostring(b)
    end)

    return keys
end

function Addon:GetTrackedCurrencyLimit()
    return MAX_TRACKED_CURRENCIES
end

function Addon:GetTrackedCurrencyEnabledCount(entries)
    local cfg = entries
    if type(cfg) ~= "table" then
        cfg = self:GetTrackedCurrencyConfig()
    end

    local count = 0
    for i = 1, #cfg do
        if cfg[i] and cfg[i].enabled ~= false then
            count = count + 1
        end
    end
    return count
end

function Addon:GetTrackedCurrencyConfig()
    local gdb = self:EnsurePrefs()
    if gdb._trackedCurrencyConfigNeedsActiveSeasonReset then
        gdb._trackedCurrencyConfigNeedsActiveSeasonReset = nil
        ResetTrackedCurrencyConfigForActiveSeason(self, gdb)
    elseif type(gdb.trackedCurrencyConfig) ~= "table" then
        gdb.trackedCurrencyConfig = NormalizeTrackedCurrencyConfig(self, nil, false)
    else
        gdb.trackedCurrencyConfig = NormalizeTrackedCurrencyConfig(self, gdb.trackedCurrencyConfig, true)
        gdb.trackedCurrencyConfig = RestoreMissingBuiltInTrackedCurrencies(self, gdb.trackedCurrencyConfig)
    end

    if not gdb._trackedCurrencyConfigActiveBuiltInsEnabled then
        gdb._trackedCurrencyConfigActiveBuiltInsEnabled = true
        if #GetBuiltInTrackedConfigEntries(self) > 0
            and not HasEnabledBuiltInTrackedCurrency(self, gdb.trackedCurrencyConfig) then
            ResetTrackedCurrencyConfigForActiveSeason(self, gdb)
        end
    end

    if not gdb._trackedCurrencyConfigMigratedCofferKeys then
        gdb._trackedCurrencyConfigMigratedCofferKeys = true
        local cofferID = tonumber(self.TRACKING and self.TRACKING.cofferKeysDisplayCurrencyID)
        if cofferID and cofferID > 0 then
            local found = false
            for i = 1, #gdb.trackedCurrencyConfig do
                if tonumber(gdb.trackedCurrencyConfig[i].id) == cofferID then
                    found = true
                    break
                end
            end
            if not found then
                local insertAt = math.min(#gdb.trackedCurrencyConfig + 1, 8)
                table.insert(gdb.trackedCurrencyConfig, insertAt, {
                    id = cofferID,
                    enabled = true,
                })
            end
        end
    end

    if not gdb._trackedCurrencyConfigRemovedWeaponUpgrade then
        gdb._trackedCurrencyConfigRemovedWeaponUpgrade = true
        for i = #gdb.trackedCurrencyConfig, 1, -1 do
            local entry = gdb.trackedCurrencyConfig[i]
            if IsRemovedBuiltInTrackedItemID(entry and entry.itemID) then
                table.remove(gdb.trackedCurrencyConfig, i)
            end
        end
    end

    local out = {}
    for i = 1, #gdb.trackedCurrencyConfig do
        local entry = gdb.trackedCurrencyConfig[i]
        out[i] = {
            id = entry.id,
            itemID = entry.itemID,
            enabled = entry.enabled ~= false,
            source = entry.source,
            kind = entry.kind,
        }
    end
    return out
end

function Addon:SetTrackedCurrencyConfig(entries)
    local gdb = self:EnsurePrefs()
    gdb.trackedCurrencyConfig = NormalizeTrackedCurrencyConfig(self, entries, true)
    RefreshAfterTrackedCurrencyConfigChange(self)
end

function Addon:GetAltSummaryCharOrder()
    local gdb = self.db and self.db.global
    local order = gdb and gdb.altSummaryCharOrder
    if type(order) ~= "table" then return {} end

    local seen = {}
    local result = {}
    for i = 1, #order do
        local key = order[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            result[#result + 1] = key
        end
    end
    return result
end

function Addon:SetAltSummaryCharOrder(orderKeys)
    if type(orderKeys) ~= "table" then return end
    local gdb = self.db and self.db.global
    if not gdb then return end

    local seen = {}
    local nextOrder = {}

    for i = 1, #orderKeys do
        local key = orderKeys[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            nextOrder[#nextOrder + 1] = key
        end
    end

    local existing = gdb.altSummaryCharOrder
    if type(existing) == "table" then
        for i = 1, #existing do
            local key = existing[i]
            if type(key) == "string" and key ~= "" and not seen[key] then
                seen[key] = true
                nextOrder[#nextOrder + 1] = key
            end
        end
    end

    gdb.altSummaryCharOrder = nextOrder
    RefreshAfterAltSummaryOrderChange(self)
end

function Addon:GetAltSummarySectionOrder()
    local gdb = self.db and self.db.global
    local order = gdb and gdb.altSummarySectionOrder
    if type(order) ~= "table" then return {} end

    local seen = {}
    local result = {}
    for i = 1, #order do
        local key = order[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            result[#result + 1] = key
        end
    end
    return result
end

function Addon:SetAltSummarySectionOrder(orderKeys)
    if type(orderKeys) ~= "table" then return end
    local gdb = self.db and self.db.global
    if not gdb then return end

    local seen = {}
    local nextOrder = {}

    for i = 1, #orderKeys do
        local key = orderKeys[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            nextOrder[#nextOrder + 1] = key
        end
    end

    local existing = gdb.altSummarySectionOrder
    if type(existing) == "table" then
        for i = 1, #existing do
            local key = existing[i]
            if type(key) == "string" and key ~= "" and not seen[key] then
                seen[key] = true
                nextOrder[#nextOrder + 1] = key
            end
        end
    end

    gdb.altSummarySectionOrder = nextOrder
    RefreshAfterAltSummaryOrderChange(self)
end

function Addon:GetAltSummaryRowOrder(sectionKey)
    sectionKey = tostring(sectionKey or "")
    if sectionKey == "" then return {} end

    local gdb = self.db and self.db.global
    local orderMap = gdb and gdb.altSummaryRowOrder
    local order = type(orderMap) == "table" and orderMap[sectionKey] or nil
    if type(order) ~= "table" then return {} end

    local seen = {}
    local result = {}
    for i = 1, #order do
        local key = order[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            result[#result + 1] = key
        end
    end
    return result
end

function Addon:SetAltSummaryRowOrder(sectionKey, orderKeys)
    sectionKey = tostring(sectionKey or "")
    if sectionKey == "" or type(orderKeys) ~= "table" then return end

    local gdb = self.db and self.db.global
    if not gdb then return end
    gdb.altSummaryRowOrder = gdb.altSummaryRowOrder or {}

    local seen = {}
    local nextOrder = {}

    for i = 1, #orderKeys do
        local key = orderKeys[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            nextOrder[#nextOrder + 1] = key
        end
    end

    local existing = gdb.altSummaryRowOrder[sectionKey]
    if type(existing) == "table" then
        for i = 1, #existing do
            local key = existing[i]
            if type(key) == "string" and key ~= "" and not seen[key] then
                seen[key] = true
                nextOrder[#nextOrder + 1] = key
            end
        end
    end

    gdb.altSummaryRowOrder[sectionKey] = nextOrder
    RefreshAfterAltSummaryOrderChange(self)
end

local GV_BLOCK_NAMES = { "Raid", "Dungeons", "World" }

function Addon:IsGVBlockHidden(blockIdx)
    if not blockIdx then return false end
    local cdb = ReadCharDB(self)
    return cdb and cdb.hiddenGVBlocks and cdb.hiddenGVBlocks[tostring(blockIdx)] == true
end

function Addon:SetGVBlockHidden(blockIdx, hidden)
    local cdb = GetOrCreateCharDB(self)
    if not cdb then return end
    cdb.hiddenGVBlocks = cdb.hiddenGVBlocks or {}
    cdb.hiddenGVBlocks[tostring(blockIdx)] = hidden or nil
    RefreshAfterHiddenChange(self)
end

function Addon:GetHiddenGVBlockList()
    local cdb = ReadCharDB(self)
    local hidden = cdb and cdb.hiddenGVBlocks
    if not hidden then return {} end
    local result = {}
    for idxStr in pairs(hidden) do
        local idx = tonumber(idxStr)
        if idx and GV_BLOCK_NAMES[idx] then
            result[#result + 1] = { idx = idx, name = GV_BLOCK_NAMES[idx] }
        end
    end
    table_sort(result, function(a, b) return a.idx < b.idx end)
    return result
end

function Addon:EnsureDB()
    if not self.db then
        self:SetupAddonDB()
    end

    local key = GetActiveCharKey(self)
    local chars = self.db.global.chars
    if not chars[key] then chars[key] = {} end

    local cdb = chars[key]
    if not cdb._lariasDefaultsApplied then
        for k, v in pairs(CHAR_DEFAULTS) do
            if cdb[k] == nil then cdb[k] = v end
        end
        if cdb.checked           == nil then cdb.checked           = {} end
        if cdb.collapsedSections == nil then cdb.collapsedSections = {} end
        if cdb.trackingSnapshot  == nil then cdb.trackingSnapshot  = {} end
        if cdb.sectionCompleted  == nil then cdb.sectionCompleted  = {} end
        cdb._lariasDefaultsApplied = true
    end

    return cdb
end

function Addon:EnsurePrefs()
    if not self.db then
        self:SetupAddonDB()
    end

    return self.db.global
end
