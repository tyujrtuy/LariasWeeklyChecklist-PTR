--[[
    LariasWeeklyChecklist_ListData.lua
    features/body/

    List-content layer: retrieves the weekly checklist dataset from the shared
    locale registry and prunes any stale SavedVariables keys that no longer
    correspond to known sections or items.
]]

local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local LOCALE_REGISTRY_KEY = Addon.LOCALE_REGISTRY_KEY

local TRACKED_ALT_LOOT_SECTION_ID = "larias_tracked_alt_loot"

local function BuildTrackedAltLootSection(self)
    if type(self.GetTrackedLootCharKeys) ~= "function" then return nil, "" end

    local L = self.L or {}
    local trackedKeys = self:GetTrackedLootCharKeys()
    if #trackedKeys == 0 then return nil, "" end

    local gdb = self.db and self.db.global
    local items = {}
    local sigParts = {
        tostring(L.TRACKED_ALT_LOOT_SECTION_TITLE or "Tracked Alt Loot"),
        tostring(L.TRACKED_ALT_LOOT_ITEM_ILVL_FMT or "Max loot on %s (ilvl %d)"),
        tostring(L.TRACKED_ALT_LOOT_ITEM_FMT or "Max loot on %s"),
    }

    for _, profileKey in ipairs(trackedKeys) do
        local cdb = gdb and gdb.chars and gdb.chars[profileKey]
        local charName = (profileKey:match("^(.-)%s*%-") or profileKey):gsub("^%s+", ""):gsub("%s+$", "")
        if charName == "" then charName = profileKey end
        local ilvl = tonumber(cdb and cdb.ilvl) or 0
        sigParts[#sigParts + 1] = profileKey .. ":" .. tostring(math.floor(ilvl))

        local text
        if ilvl > 0 then
            text = (L.TRACKED_ALT_LOOT_ITEM_ILVL_FMT or "Max loot on %s (ilvl %d)"):format(charName, math.floor(ilvl))
        else
            text = (L.TRACKED_ALT_LOOT_ITEM_FMT or "Max loot on %s"):format(charName)
        end

        items[#items + 1] = {
            id = profileKey,
            text = text,
        }
    end

    if #items == 0 then return nil, "" end

    return {
        id = TRACKED_ALT_LOOT_SECTION_ID,
        title = L.TRACKED_ALT_LOOT_SECTION_TITLE or "Tracked Alt Loot",
        items = items,
    }, table.concat(sigParts, "|")
end

local function MergeTrackedAltLootSection(self, data, trackedSection, trackedSig)
    if not trackedSection then return data end
    if self._cachedListMergedBase == data
            and self._cachedListMergedTrackedSig == trackedSig
            and type(self._cachedListMergedData) == "table" then
        return self._cachedListMergedData
    end

    local merged = {}
    for i, section in ipairs(data) do
        merged[i] = section
    end
    merged[#merged + 1] = trackedSection

    self._cachedListMergedBase = data
    self._cachedListMergedTrackedSig = trackedSig
    self._cachedListMergedData = merged
    return merged
end

-- Return the checklist dataset for the current effective locale.
-- Cached by locale code because the dataset is static per session.
function Addon:GetListData()
    local reg = _G[LOCALE_REGISTRY_KEY]
    local dataByLocale = reg and reg.data
    if type(dataByLocale) ~= "table" then return {} end

    local localeCode = self:GetEffectiveLocaleCode()

    if self._cachedListLocaleCode == localeCode and type(self._cachedListData) == "table" then
        local trackedSection, trackedSig = BuildTrackedAltLootSection(self)
        return MergeTrackedAltLootSection(self, self._cachedListData, trackedSection, trackedSig)
    end

    local data = dataByLocale[localeCode]
    if type(data) == "table" then
        self._cachedListLocaleCode = localeCode
        self._cachedListData = data
        local trackedSection, trackedSig = BuildTrackedAltLootSection(self)
        return MergeTrackedAltLootSection(self, data, trackedSection, trackedSig)
    end

    data = dataByLocale.enUS
    if type(data) == "table" then
        self._cachedListLocaleCode = "enUS"
        self._cachedListData = data
        local trackedSection, trackedSig = BuildTrackedAltLootSection(self)
        return MergeTrackedAltLootSection(self, data, trackedSection, trackedSig)
    end

    return {}
end

-- Walks the saved checked/collapsed tables and removes any keys that no longer
-- correspond to a section or item in the current dataset. Runs once per session.
function Addon:PruneObsoleteSavedState()
    if self._svPrunedThisSession then return end

    local db = self:EnsureDB()
    if type(db) ~= "table" then return end
    if type(db.checked) ~= "table" and type(db.collapsedSections) ~= "table" then
        return
    end

    if type(self.GetListData) ~= "function" then return end
    local data = self:GetListData()
    -- Missing or partially loaded locale data must never authorize deletion of
    -- SavedVariables. A later call can retry once a real dataset is available.
    local validSections, validItemKeys = Addon.CoreLogic.BuildValidChecklistKeys(data)
    if not validSections then return end
    self._svPrunedThisSession = true

    -- Backfill: seed sectionCompleted for sections that were fully checked in
    -- db.checked, so the sticky flag works after upgrades.  Re-runs whenever
    -- the sheet version changes so renamed items (which regenerate hash IDs
    -- via sheet_to_lua) don't break already-completed weeks.
    --
    -- Two signals are combined to handle the three common update patterns:
    --   (a) items renamed: old IDs pruned, new IDs added. checkedCount stays
    --       the same but matchCount drops.  checkedCount >= currentCount catches
    --       this when item counts don't change net, and the 90% threshold below
    --       helps when a couple of new items were also added.
    --   (b) items removed: currentCount shrinks, so checkedCount >= currentCount
    --       still holds.
    --   (c) items added to an already-complete section (e.g. items moved in
    --       from a deleted section): checkedCount < currentCount but the ratio
    --       is still high; the 90% threshold catches this.
    local currentSheetVer = (function()
        local r = Addon.GetLocaleRegistry and Addon.GetLocaleRegistry()
        return r and tostring(r.sheet_version or "") or ""
    end)()
    -- v2 sentinel: forces one extra run for saves that already had the v1
    -- sentinel written (which used strict >= and missed the 90% threshold).
    if (db._sectionCompletedSeedVer2 or "") ~= currentSheetVer and
       type(db.checked) == "table" then
        db._sectionCompletedSeedVer2 = currentSheetVer
        if type(db.sectionCompleted) ~= "table" then db.sectionCompleted = {} end
        -- Count checked entries per section prefix (format: "sectionId:itemId").
        local checkedBySection = {}
        for key in pairs(db.checked) do
            local colonPos = string.find(key, ":", 1, true)
            if colonPos and colonPos > 1 then
                local sid = string.sub(key, 1, colonPos - 1)
                checkedBySection[sid] = (checkedBySection[sid] or 0) + 1
            end
        end
        for _, section in ipairs(data) do
            local sid = section.id
            if type(sid) == "string" and type(section.items) == "table" and
               #section.items > 0 then
                local currentCount = #section.items
                local checkedCount = checkedBySection[sid] or 0
                if checkedCount == 0 then
                    -- Nothing was ever checked in this section; skip.
                else
                    -- Threshold: 90% of current items must be covered by old
                    -- checked entries.  math.max(1, ...) avoids a zero floor for
                    -- single-item sections.  This is intentionally slightly
                    -- lenient so that a section completed at the previous
                    -- version survives even if 1-2 new items were added to it.
                    local threshold = math.max(1, math.floor(currentCount * 0.9))
                    if checkedCount >= threshold then
                        db.sectionCompleted[sid] = true
                    end
                end
            end
        end
    end

    local removedChecked   = 0
    local removedCollapsed = 0

    if type(db.checked) == "table" then
        for k in pairs(db.checked) do
            if not validItemKeys[k] then
                db.checked[k] = nil
                removedChecked = removedChecked + 1
            end
        end
    end

    if type(db.collapsedSections) == "table" then
        for k in pairs(db.collapsedSections) do
            if not validSections[k] then
                db.collapsedSections[k] = nil
                removedCollapsed = removedCollapsed + 1
            end
        end
    end

    if type(db.sectionCompleted) == "table" then
        for k in pairs(db.sectionCompleted) do
            if not validSections[k] then
                db.sectionCompleted[k] = nil
            end
        end
    end

end
