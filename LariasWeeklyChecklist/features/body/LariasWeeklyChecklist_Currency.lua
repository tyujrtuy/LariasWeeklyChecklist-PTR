-- LariasWeeklyChecklist_Currency.lua
-- Currency data module.  Computes crest/catalyst/sparks/currency rows from
-- WoW APIs and exposes them to the Overlay for rendering.
--
-- Public methods
--   Addon:GetCurrencyPanelRows()         {label,value,iconID,currencyID}[]
--   Addon:FillCurrencySnapshot(snap)     writes snap.rightRows
--   Addon:RenderCurrencySnapshotRow(r)   label, value
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local L = Addon.L or {}
local NA = L.TRACKING_NA or (Addon.PLACEHOLDER_DASH or "\226\128\148")

local tonumber, tostring, type = tonumber, tostring, type
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local tinsert, tconcat = table.insert, table.concat

-- No hard display cap: Overlay.lua grows its row pool and panel height as needed.
local RIGHT_LINE_COUNT = math.huge

-- Per-session cache for static currency fields (name, iconFileID, quality).
-- These never change within a session, so we avoid repeated C_CurrencyInfo calls.
local _currencyStaticCache = {}  -- [id] = { name, iconFileID, quality } or false

-- Cache for BuildCrestLabels output; invalidated only when crest IDs change.
local _crestLabelsCache = { key = nil, labels = nil }

-- ── Snapshot row type constants ─────────────────────────────────────────────
-- Single source of truth for all type-tag strings used in snap.rightRows.
-- AltsSummary.lua reads these via Addon.SNAP_TYPES so both sides stay in sync.
Addon.SNAP_TYPES = {
    CREST      = "crest",
    CATALYST   = "catalyst",
    SPARKS     = "sparks",
    COFFERKEYS = "cofferkeys",
    MISC       = "misc",
    QUEST      = "quest",
    WEAPUPG    = "weapupg",  -- weapon/trinket upgrade items (289→298)
}
local SNAP_TYPES = Addon.SNAP_TYPES
local GetCatalystRawQtyCap

-- Weapon-upgrade config is season data; keep it in TRACKING constants instead
-- of hard-coding IDs in code paths.
local function GetWeaponUpgradeConfig()
    local cfg = Addon.TRACKING and Addon.TRACKING.weaponUpgrade
    return type(cfg) == "table" and cfg or nil
end

function Addon:GetWeaponUpgradeCombinedItemID()
    local cfg = GetWeaponUpgradeConfig()
    return tonumber(cfg and cfg.combinedItemID) or 0
end

function Addon:GetWeaponUpgradeShardItemID()
    local cfg = GetWeaponUpgradeConfig()
    return tonumber(cfg and cfg.shardItemID) or 0
end

function Addon:GetWeaponUpgradeMaxItemLevel()
    local cfg = GetWeaponUpgradeConfig()
    return tonumber(cfg and cfg.maxItemLevel) or 0
end

function Addon:GetWeaponUpgradeShardsPerCombined()
    local cfg = GetWeaponUpgradeConfig()
    local value = tonumber(cfg and cfg.shardsPerCombined)
    return (value and value > 0) and value or 1
end

function Addon:GetWeaponUpgradeSlotIDs()
    local cfg = GetWeaponUpgradeConfig()
    local slotIDs = cfg and cfg.slotIDs
    return type(slotIDs) == "table" and slotIDs or {}
end

local GEAR_SLOT_IDS        = (Addon.TRACKING and Addon.TRACKING.gearSlotIDs)

-- Returns the number of weapon/trinket slots the current character still needs
-- to upgrade (ilvl > 0 and ilvl < WEAP_UPG_MAX_ILVL, slot 17 only counted when
-- there is a real item link — i.e. dual-wield rather than 2H).
function Addon:GetUpgradeGearSlots(snap)
    if type(snap) ~= "table" then return nil end
    if type(snap.bestGearSlots) == "table" then return snap.bestGearSlots end
    if type(snap.gearSlots) == "table" then return snap.gearSlots end
    return nil
end

function Addon:GetEquippedUpgradeGearSlots(snap)
    if type(snap) ~= "table" then return nil end
    if type(snap.gearSlots) == "table" then return snap.gearSlots end
    if type(snap.bestGearSlots) == "table" then return snap.bestGearSlots end
    return nil
end

local function GetWeaponUpgradeNeedFromGearSlots(gearSlots)
    if type(gearSlots) ~= "table" then return nil end
    local maxIlvl = Addon:GetWeaponUpgradeMaxItemLevel()
    local slotIDs = Addon:GetWeaponUpgradeSlotIDs()
    if maxIlvl <= 0 or #slotIDs == 0 then return nil end
    local count = 0
    local sawGear = false
    for _, sid in ipairs(slotIDs) do
        local slotData = gearSlots[sid]
        local ilvl = type(slotData) == "table" and tonumber(slotData.ilvl) or 0
        if ilvl > 0 then sawGear = true end
        if ilvl > 0 and ilvl < maxIlvl then
            count = count + 1
        end
    end
    return sawGear and count or nil
end

local function GetWeaponUpgradeNeedCount(snap)
    local snapshotNeed = GetWeaponUpgradeNeedFromGearSlots(Addon:GetUpgradeGearSlots(snap))
    if snapshotNeed ~= nil then return snapshotNeed end

    if not (GetInventoryItemLink and GetDetailedItemLevelInfo) then return 0 end
    local maxIlvl = Addon:GetWeaponUpgradeMaxItemLevel()
    local slotIDs = Addon:GetWeaponUpgradeSlotIDs()
    if maxIlvl <= 0 or #slotIDs == 0 then return 0 end
    local count = 0
    for _, sid in ipairs(slotIDs) do
        local link = GetInventoryItemLink("player", sid)
        if link then
            local ilvl = tonumber((GetDetailedItemLevelInfo(link))) or 0
            if ilvl > 0 and ilvl < maxIlvl then
                count = count + 1
            end
        end
    end
    return count
end

--  Shared mini-utilities (from Addon.AddonUtils) 
local AU             = Addon.AddonUtils
local COLORS         = AU.COLORS
local ColorWrap      = AU.ColorWrap
local Wipe           = AU.Wipe
local IsNonEmptyText = AU.IsNonEmptyText
local FormatXY       = AU.FormatXY
local ColorForXY     = AU.ColorForXY

local function IsAchievementCompleteSafe(achievementID)
    if not achievementID then return false end
    if GetAchievementInfo then
        local _, _, _, completed, _, _, _, _, _, _, _, _, wasEarnedByMe = GetAchievementInfo(achievementID)
        return completed == true or wasEarnedByMe == true
    end
    return false
end

local function IsAchievementEarnedByMeSafe(achievementID)
    if not achievementID then return false end
    if GetAchievementInfo then
        local _, _, _, _, _, _, _, _, _, _, _, _, wasEarnedByMe = GetAchievementInfo(achievementID)
        return wasEarnedByMe == true
    end
    return false
end

--  Currency API helpers 
local QUALITY_HEX = {
    [0] = "ff9d9d9d", [1] = "ffffffff", [2] = "ff1eff00",
    [3] = "ff0070dd", [4] = "ffa335ee", [5] = "ffff8000",
    [6] = "ffe6cc80", [7] = "ff00ccff",
}

-- Some Midnight currencies/items currently report common quality through the
-- runtime APIs even though they should read as epic in the UI.
local function GetCurrencyQualityOverrides()
    local overrides = Addon.TRACKING and Addon.TRACKING.currencyQualityOverrides
    return type(overrides) == "table" and overrides or {}
end

local function GetItemQualityOverrides()
    local overrides = Addon.TRACKING and Addon.TRACKING.itemQualityOverrides
    return type(overrides) == "table" and overrides or {}
end

local function GetQualityHex(quality, fallbackHex)
    return QUALITY_HEX[tonumber(quality) or 0] or fallbackHex or COLORS.white
end

local function GetItemDisplayQuality(itemID)
    local quality = nil
    if GetItemInfo and itemID then
        quality = select(3, GetItemInfo(itemID))
    end
    quality = tonumber(quality)
    if quality and quality > 1 then
        return quality
    end
    return GetItemQualityOverrides()[tonumber(itemID) or 0] or quality
end

local function FormatCurrencyProgressParts(currencyID)
    if not currencyID or not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
    if not info then return nil end
    local held     = tonumber(info.quantity)    or 0
    local wkAmount = tonumber(info.maxWeeklyQuantity) or 0
    local walletCap= tonumber(info.maxQuantity) or 0
    -- If the currency has a weekly earn cap, display weekly-earned / weekly-cap so
    -- that spending the currency doesn't reset the display back to 0 (e.g. 0/2
    -- after spending 2 earned → should show 2/2).  Use >= so this also catches
    -- currencies where wallet cap equals weekly cap.
    if info.hasWeeklyLimit and wkAmount > 0 and wkAmount >= walletCap then
        local weeklyEarned = tonumber(info.quantityEarnedThisWeek) or tonumber(info.weeklyQuantity) or 0
        return weeklyEarned, wkAmount
    end
    -- For season-capped currencies (crests, sparks, misc weekly-track currencies)
    -- use total earned toward the cap for the default X/Y display.
    -- Floor earnedSoFar at held: some currencies (e.g. Catalyst) don't populate
    -- totalEarned, returning 0 even when the wallet is full, which would
    -- incorrectly inflate the earnable amount.
    local earnedSoFar = math.max(tonumber(info.totalEarned) or 0, held)
    local seasonMax   = walletCap
    if seasonMax > 0 then
        return earnedSoFar, math.max(seasonMax, earnedSoFar)
    end
    return held, 0
end

local function IsConfiguredTrackedCurrencyID(currencyID)
    local id = tonumber(currencyID)
    if not (id and id > 0) then return false end

    local tracking = Addon.TRACKING or {}
    local crestIDs = tracking.crestCurrencyIDs
    if type(crestIDs) == "table" then
        for i = 1, #crestIDs do
            if tonumber(crestIDs[i]) == id then return true end
        end
    end

    if tonumber(tracking.catalystCurrencyID) == id then return true end
    if tonumber(tracking.sparkCurrencyID) == id then return true end
    if tonumber(tracking.cofferKeysCurrencyID) == id then return true end
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

local function GetCurrentCurrencySnapshotCap(rowType, currencyID)
    if rowType == SNAP_TYPES.CATALYST then
        local _, cap = GetCatalystRawQtyCap()
        return tonumber(cap) or 0, true
    end

    if rowType == SNAP_TYPES.COFFERKEYS then
        local tracking = Addon.TRACKING or {}
        local shardsID = tonumber(tracking.cofferKeysCurrencyID)
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
            and shardsID and shardsID > 0 and C_CurrencyInfo.GetCurrencyInfo(shardsID)
        return floor((info and tonumber(info.maxWeeklyQuantity) or 0) / 100), true
    end

    local id = tonumber(currencyID)
    if not (id and id > 0) then return 0, false end
    local _, cap = FormatCurrencyProgressParts(id)
    cap = tonumber(cap) or 0
    return cap, cap > 0 or IsConfiguredTrackedCurrencyID(id)
end

local function ClampSnapshotAmountToCurrentCap(amount, cap, hasCurrentCap)
    amount = tonumber(amount) or 0
    cap = tonumber(cap) or 0
    if hasCurrentCap then
        return min(amount, max(0, cap))
    end
    return amount
end

local function FormatSigilAmount(value)
    value = tonumber(value) or 0
    if value == math.floor(value) then
        return tostring(math.floor(value))
    end
    return ("%.1f"):format(value)
end

-- Returns a cached table of static currency fields {name, iconFileID, quality}.
-- Call this instead of GetCurrencyInfo when you only need data that never
-- changes within a session.  FormatCurrencyProgressParts must still go direct
-- because quantity/totalEarned are dynamic.
local function GetCurrencyStaticInfo(currencyID)
    local id = tonumber(currencyID)
    if not (id and id > 0) then return nil end
    local cached = _currencyStaticCache[id]
    if cached ~= nil then return cached or nil end
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then return nil end
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not info then return nil end
    local s = { name = info.name, iconFileID = info.iconFileID, quality = tonumber(info.quality) }
    _currencyStaticCache[id] = s
    return s
end

local function GetCurrencyIconID(currencyID)
    local s = GetCurrencyStaticInfo(currencyID)
    return s and s.iconFileID or nil
end

local function GetCurrencyName(currencyID)
    local s = GetCurrencyStaticInfo(currencyID)
    return s and s.name or nil
end

local function GetCurrencyQualityColor(currencyID)
    local s = GetCurrencyStaticInfo(currencyID)
    local id = tonumber(currencyID) or 0
    local q = s and tonumber(s.quality) or nil
    if q and q > 1 then
        return GetQualityHex(q, COLORS.gold)
    end
    local overrideQ = GetCurrencyQualityOverrides()[id]
    if overrideQ then
        return GetQualityHex(overrideQ, COLORS.gold)
    end
    if not s then return COLORS.dim end
    -- Quality 0 (junk) and 1 (common/white) have no meaningful color for currency
    -- labels; fall back to gold so they read well on the panel background.
    return COLORS.gold
end

-- Returns (r, g, b) floats for SetTextColor from a currency's quality colour.
-- hex from GetCurrencyQualityColor is aarrggbb; the leading aa is skipped.
function Addon:GetCurrencyQualityColorRGB(id)
    local hex = GetCurrencyQualityColor(id)
    return (tonumber(hex:sub(3,4), 16) or 204) / 255,
           (tonumber(hex:sub(5,6), 16) or 154) / 255,
           (tonumber(hex:sub(7,8), 16) or 40)  / 255
end

function Addon:GetItemQualityColorRGB(itemID)
    local hex = GetQualityHex(GetItemDisplayQuality(itemID), COLORS.white)
    return (tonumber(hex:sub(3,4), 16) or 255) / 255,
           (tonumber(hex:sub(5,6), 16) or 255) / 255,
           (tonumber(hex:sub(7,8), 16) or 255) / 255
end

-- Builds a table (keyed by currency ID) of the shortest distinguishing label
-- for each crest tier.  Words shared by every name are stripped; what remains
-- is the tier-unique portion (e.g. "Adventurer", "Veteran", …).  Falls back
-- to the first word when nothing distinguishes (e.g. only one crest defined).
-- Result is cached in _crestLabelsCache; rebuilt only when crest IDs change.
local function BuildCrestLabels(ids, crestCount)
    -- Build a single key string so cache validity is one comparison instead of a loop.
    local keyParts = {}
    for i = 1, crestCount do keyParts[i] = tostring(ids[i] or 0) end
    local key = crestCount .. ":" .. tconcat(keyParts, ",")
    if _crestLabelsCache.labels and _crestLabelsCache.key == key then
        return _crestLabelsCache.labels
    end

    -- Collect per-name word lists and a global word frequency count.
    local wordLists = {}
    local wordCount = {}
    for i = 1, crestCount do
        local id = ids[i]
        local name = (id and GetCurrencyName(id)) or ""
        wordLists[i] = {}
        local seen = {}
        for w in name:gmatch("%S+") do
            tinsert(wordLists[i], w)
            if not seen[w] then
                seen[w] = true
                wordCount[w] = (wordCount[w] or 0) + 1
            end
        end
    end
    -- Words present in every name are common; keep only the unique ones.
    local labels = {}
    for i = 1, crestCount do
        local id = ids[i]
        if id then
            local unique = {}
            for _, w in ipairs(wordLists[i]) do
                if (wordCount[w] or 0) < crestCount then
                    tinsert(unique, w)
                end
            end
            if #unique > 0 then
                labels[id] = tconcat(unique, " ")
            else
                -- All words are shared (or only one crest) – fall back to first word.
                labels[id] = wordLists[i][1] or ("Crest " .. tostring(id))
            end
        end
    end

    -- Store result in the cache for subsequent calls this session.
    _crestLabelsCache.key    = key
    _crestLabelsCache.labels = labels
    return labels
end

local function GetCrestDisplayName(tracking, tierIdx, currencyID, crestLabels)
    local displayByTier = tracking and tracking.crestDisplayNamesByTier
    if type(displayByTier) == "table" then
        local override = displayByTier[tonumber(tierIdx) or 0]
        if IsNonEmptyText(override) then
            return override
        end
    end

    local displayByID = tracking and tracking.crestDisplayNamesByID
    if type(displayByID) == "table" then
        local override = displayByID[tonumber(currencyID) or 0]
        if IsNonEmptyText(override) then
            return override
        end
    end

    -- Locale companion can supply translated names via numeric currency-ID keys
    -- (e.g. L[3383] = "Aventurero" in esMX).  Check before falling back to the
    -- game API, which may return identical names for all tiers in some locales.
    local localeOverride = currencyID and L[tonumber(currencyID)]
    if IsNonEmptyText(localeOverride) then
        return localeOverride
    end

    return (crestLabels and crestLabels[currencyID]) or GetCurrencyName(currencyID) or tostring(currencyID)
end

--  Crest achievement helpers 
local function GetCrestAchievementID(i)
    local ach = Addon.TRACKING and Addon.TRACKING.crestAchievementIDs
    if type(ach) ~= "table" then return nil end
    local idx = tonumber(i)
    return idx and ach[idx] or nil
end

local function GetCrestTradeupAchievementID(i)
    local tracking = Addon.TRACKING
    local ach = tracking and tracking.crestTradeupAchievementIDs
    if type(ach) ~= "table" then
        ach = tracking and tracking.crestAchievementIDs
    end
    if type(ach) ~= "table" then return nil end
    local idx = tonumber(i)
    return idx and ach[idx] or nil
end

function Addon:GetCrestAchievementID(tierIdx)
    return GetCrestAchievementID(tierIdx)
end

function Addon:GetCrestAchievementName(tierIdx)
    local achievementID = GetCrestAchievementID(tierIdx)
    if achievementID and GetAchievementInfo then
        local _, name = GetAchievementInfo(achievementID)
        if type(name) == "string" and name ~= "" then return name end
    end

    local trackName = self.IlvlUtils and self.IlvlUtils.GetCrestTrackName
        and self.IlvlUtils.GetCrestTrackName(tierIdx)
    return trackName and (trackName .. " Achievement") or nil
end

function Addon:GetCrestAchievementTooltipInfo(tierIdx)
    local achievementID = GetCrestAchievementID(tierIdx)
    if not (achievementID and GetAchievementInfo) then return nil end

    local _, name, _, completed, _, _, _, description, _, icon, rewardText = GetAchievementInfo(achievementID)
    if type(name) ~= "string" or name == "" then return nil end

    return {
        id = achievementID,
        name = name,
        description = (type(description) == "string" and description ~= "") and description or nil,
        rewardText = (type(rewardText) == "string" and rewardText ~= "") and rewardText or nil,
        completed = completed and true or false,
        icon = icon,
    }
end

--  Quest helpers 
local function GetTrackedQuestID(key)
    local questIDs = Addon.TRACKING and Addon.TRACKING.questIDs
    local q = questIDs and questIDs[key]
    if (tonumber(q) or 0) <= 0 and key == "delveBoss" then
        q = questIDs and questIDs.nullaeusSpoils
    end
    q = tonumber(q) or 0
    if q <= 0 then return nil end
    return q
end

local function GetTrackedQuestItemID(key)
    local itemIDs = Addon.TRACKING and Addon.TRACKING.questItemIDs
    local itemID = itemIDs and itemIDs[key]
    if (tonumber(itemID) or 0) <= 0 and key == "delveBoss" then
        itemID = itemIDs and itemIDs.nullaeusSpoils
    end
    itemID = tonumber(itemID) or 0
    return itemID > 0 and itemID or 0
end

local function GetQuestDoneRaw(questKey)
    local qid = GetTrackedQuestID(questKey)
    if not qid then return nil end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(qid) and true or false
    end
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(qid) and true or false
    end
    return nil
end

local function GetQuestDoneParts(labelText, questKey, opts)
    local qid = GetTrackedQuestID(questKey)
    if not qid then return "", "" end
    local label = ColorWrap(COLORS.dim, labelText)
    local done
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        done = C_QuestLog.IsQuestFlaggedCompleted(qid)
    elseif IsQuestFlaggedCompleted then
        done = IsQuestFlaggedCompleted(qid)
    end
    if done == nil then
        return label, ColorWrap(COLORS.red, NA)
    end
    if opts and opts.as01 then
        return label, done and ColorWrap(COLORS.green, "1/1") or ColorWrap(COLORS.red, "0/1")
    end
    return label, done and ColorWrap(COLORS.green, L.TRACKING_DONE or "Done") or ColorWrap(COLORS.red, NA)
end

local function GetDelversBountyParts()
    if not GetTrackedQuestID("delversBounty") then return "", "" end
    return GetQuestDoneParts(L.TRACKING_QUEST_DELVERS_BOUNTY or "", "delversBounty", { as01 = true })
end

local function GetWeeklyPreyParts()
    if not GetTrackedQuestID("weeklyPrey") then return "", "" end
    return GetQuestDoneParts(L.TRACKING_QUEST_WEEKLY_PREY or "", "weeklyPrey", { as01 = true })
end

local function GetDelveBossParts()
    if not GetTrackedQuestID("delveBoss") then return "", "" end
    return GetQuestDoneParts(L.TRACKING_QUEST_DELVE_BOSS or L.TRACKING_QUEST_NULLAEUS_SPOILS or "", "delveBoss", { as01 = true })
end

--  Sparks 
local function GetSparksParts()
    local id = Addon.TRACKING and Addon.TRACKING.sparkCurrencyID
    if not (id and tonumber(id) and tonumber(id) > 0) then return "", "" end
    local name  = GetCurrencyName(id) or L.TRACKING_SPARKS_LABEL or ""
    local label = ColorWrap(GetCurrencyQualityColor(id), name)
    local earned, cap = FormatCurrencyProgressParts(id)
    earned = tonumber(earned) or 0
    cap = tonumber(cap) or 0
    local rawInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    local held = (rawInfo and tonumber(rawInfo.quantity)) or 0

    -- Build tooltip lines from the currency cap only.
    local tipLines = {}
    if cap > 0 then
        local earnable = math.max(0, cap - earned)
        tipLines[#tipLines + 1] = { text = (L.TRACKING_EARNED_FMT or "Earned: %d/%d"):format(earned, cap) }
        tipLines[#tipLines + 1] = { text = (L.TRACKING_HELD_FMT or "Held: %d"):format(held), r = 0.75, g = 0.75, b = 0.75 }
        if earnable > 0 then
            tipLines[#tipLines + 1] = { text = (L.TRACKING_STILL_EARNABLE_FMT or "Still earnable: %d"):format(earnable), r = 1.0, g = 0.82, b = 0.0 }
        else
            tipLines[#tipLines + 1] = { text = L.TRACKING_SEASON_CAP_REACHED or "Season cap reached", r = 0.3, g = 1.0, b = 0.3 }
        end
    end
    local tooltip = (#tipLines > 0) and tipLines or nil

    if cap > 0 then
        local sparkColor = (earned >= cap) and COLORS.green
                        or (earned > 0) and COLORS.yellow
                        or COLORS.dim
        return label, ColorWrap(sparkColor, tostring(held)), tooltip
    end
    -- cap unavailable — show quantity in normal text color (no false green "done" signal)
    local th = Addon.THEME and Addon.THEME.text
    local dimHex = (th and th.r) and
        string.format("ff%02x%02x%02x", math.floor(th.r*255), math.floor(th.g*255), math.floor(th.b*255))
        or COLORS.dim
    return label, ColorWrap(dimHex, tostring(held)), tooltip
end

local function GetCofferKeysParts()
    local tracking = Addon.TRACKING
    local shardsID = tracking and tonumber(tracking.cofferKeysCurrencyID)
    local displayID = tracking and tonumber(tracking.cofferKeysDisplayCurrencyID)
    if not (shardsID and shardsID > 0) then return "", "" end

    local displayName = (displayID and displayID > 0 and GetCurrencyName(displayID))
        or L.TRACKING_COFFER_KEYS_LABEL
        or "Coffer Keys"
    local displayColorID = (displayID and displayID > 0) and displayID or shardsID
    local label = ColorWrap(GetCurrencyQualityColor(displayColorID), displayName)

    local getCurrency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
    local shardInfo = getCurrency and getCurrency(shardsID)
    local keyInfo = (getCurrency and displayID and displayID > 0) and getCurrency(displayID) or nil
    local earnedShards = (shardInfo and tonumber(shardInfo.quantityEarnedThisWeek)) or 0
    local weeklyCapShards = (shardInfo and tonumber(shardInfo.maxWeeklyQuantity)) or 0
    local current = floor(earnedShards / 100)
    local total = floor(weeklyCapShards / 100)
    local wholeKeys = (keyInfo and tonumber(keyInfo.quantity)) or 0
    local rawShards = (shardInfo and tonumber(shardInfo.quantity)) or 0
    local balance = wholeKeys + floor(rawShards / 100)
    local bonus = max(0, balance - current)

    local tipLines = {}
    if total > 0 then
        local earnable = max(0, total - current)
        tipLines[#tipLines + 1] = {
            text = (L.TRACKING_EARNED_FMT or "Earned: %d/%d"):format(current, total),
        }
        if earnable > 0 then
            tipLines[#tipLines + 1] = {
                text = (L.TRACKING_STILL_EARNABLE_FMT or "Still earnable: %d"):format(earnable),
                r = 1.0, g = 0.82, b = 0.0,
            }
        else
            tipLines[#tipLines + 1] = {
                text = L.TRACKING_WEEKLY_CAP_REACHED or "Weekly cap reached",
                r = 0.3, g = 1.0, b = 0.3,
            }
        end
    end
    if bonus > 0 then
        tipLines[#tipLines + 1] = {
            text = (L.TRACKING_BONUS_KEYS_FMT or "Bonus keys: +%d"):format(bonus),
            r = 0.65, g = 0.85, b = 1.0,
        }
    end

    local valColor = (total > 0 and current >= total) and COLORS.green
        or (balance > 0 and COLORS.yellow)
        or COLORS.red
    return label, ColorWrap(valColor, tostring(balance)), (#tipLines > 0) and tipLines or nil
end

--  Crest computation 
local function GetCrestTradeBatches(profile)
    local p = profile or Addon.TRACKING or {}
    local batch = p.crestTradeBatch
    local lower, higher
    if type(batch) == "table" then
        lower  = tonumber(batch[1] or batch.lower)
        higher = tonumber(batch[2] or batch.higher)
    end
    if not lower  or lower  <= 0 then lower  = 45 end
    if not higher or higher <= 0 then
        higher = floor(lower / 3)
        if higher <= 0 then higher = 1 end
    end
    return lower, higher
end

local function GetCrestIDsAndCount(tracking)
    local ids = tracking.crestCurrencyIDs or {}
    local crestCount
    if type(ids) == "table" and ids[1] ~= nil then
        crestCount = #ids
    else
        ids = {}; crestCount = 0
    end
    if crestCount <= 0 then crestCount = 4 end
    return ids, crestCount
end

local function GetTrackedCurrencyType(tracking, currencyID)
    currencyID = tonumber(currencyID)
    if not currencyID then return SNAP_TYPES.MISC end

    local crestIDs, crestCount = GetCrestIDsAndCount(tracking or {})
    for i = 1, crestCount do
        if tonumber(crestIDs[i]) == currencyID then
            return SNAP_TYPES.CREST, i
        end
    end

    if tonumber(tracking and tracking.catalystCurrencyID) == currencyID then
        return SNAP_TYPES.CATALYST
    end
    if tonumber(tracking and tracking.sparkCurrencyID) == currencyID then
        return SNAP_TYPES.SPARKS
    end
    if tonumber(tracking and tracking.cofferKeysDisplayCurrencyID) == currencyID then
        return SNAP_TYPES.COFFERKEYS
    end
    return SNAP_TYPES.MISC
end


local _trackedEntryBuf = {}
local _trackedEntryPool = {}

local function AcquireSnapshotRow(rows, index)
    local row = rows[index]
    if not row then
        row = {}
        rows[index] = row
    else
        Wipe(row)
    end
    return row
end

function Addon:GetTrackedCurrencyEntries(includeDisabled)
    local cfg = self.GetTrackedCurrencyConfig and self:GetTrackedCurrencyConfig() or {}
    local tracking = self.TRACKING or {}
    local out = _trackedEntryBuf
    local n = 0
    for i = 1, #cfg do
        local entry = cfg[i]
        local id = tonumber(entry and entry.id)
        local itemID = tonumber(entry and entry.itemID)
        if itemID and itemID > 0 then
            local isHidden = Addon.IsItemHidden and Addon:IsItemHidden(itemID)
            if not isHidden and (includeDisabled or entry.enabled ~= false) then
                n = n + 1
                local row = _trackedEntryPool[n]
                if not row then
                    row = {}
                    _trackedEntryPool[n] = row
                end
                row.id = nil
                row.itemID = itemID
                row.enabled = entry.enabled ~= false
                row.type = (itemID == Addon:GetWeaponUpgradeCombinedItemID()) and SNAP_TYPES.WEAPUPG or nil
                row.kind = entry.kind or "item"
                row.crestIdx = nil
                out[n] = row
            end
        elseif id and id > 0 and (includeDisabled or entry.enabled ~= false) then
            local rowType, crestIdx = GetTrackedCurrencyType(tracking, id)
            n = n + 1
            local row = _trackedEntryPool[n]
            if not row then
                row = {}
                _trackedEntryPool[n] = row
            end
            row.id = id
            row.itemID = nil
            row.enabled = entry.enabled ~= false
            row.type = rowType
            row.kind = nil
            row.crestIdx = crestIdx
            out[n] = row
        end
    end
    for i = n + 1, #out do
        out[i] = nil
    end
    return out
end

local function EnsureCrestCache(tracking, crestCount)
    local cache = tracking._crestCache
    if not cache or cache.count ~= crestCount then
        cache = {
            count     = crestCount,
            out       = {}, label     = {}, value    = {},
            name      = {},
            -- cur[i]      : wallet balance (held crests, may exceed earned if bonus-capped)
            -- earned[i]   : totalEarned toward the season cap (used for X/Y display)
            -- cap[i]      : season wallet cap == weekly soft cap (maxQuantity)
            -- weeklyMax[i]: same value as cap[i] (kept for legacy callers)
            cur       = {}, cap       = {},
            unlocked  = {}, effective = {}, gained  = {},
            earned    = {}, weeklyMax = {},
        }
        tracking._crestCache = cache
    end
    return cache
end

local function ResetCrestOutput(cache, crestCount)
    local out, labelOut, valueOut = cache.out, cache.label, cache.value
    for i = 1, crestCount do out[i] = ""; labelOut[i] = ""; valueOut[i] = "" end
    return out, labelOut, valueOut
end

local function PopulateCrestCurCap(cache, ids, crestCount)
    local getCurrency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
    for i = 1, crestCount do
        local id = ids[i]
        if id then
            local info      = getCurrency and getCurrency(id)
            local held      = info and tonumber(info.quantity)    or 0
            local weeklyCap = info and tonumber(info.maxQuantity) or 0  -- weekly soft cap for crests
            local earned    = info and tonumber(info.totalEarned) or 0  -- earned toward weekly cap
            cache.cur[i]       = held
            cache.cap[i]       = weeklyCap
            cache.earned[i]    = earned
            cache.weeklyMax[i] = weeklyCap
        else
            cache.cur[i] = 0; cache.cap[i] = 0
            cache.earned[i] = 0; cache.weeklyMax[i] = 0
        end
    end
end

local function PopulateCrestUnlocked(cache, crestCount)
    for i = 1, crestCount do
        local achID = GetCrestTradeupAchievementID(i)
        cache.unlocked[i] = achID and IsAchievementEarnedByMeSafe(achID) or false
    end
end

function Addon:IsCrestDiscountUnlocked(tierIdx)
    local achID = GetCrestAchievementID(tierIdx)
    return achID and IsAchievementCompleteSafe(achID) or false
end

function Addon:GetItemUpgradeHighWatermark(itemLink)
    if not (itemLink and C_ItemUpgrade and C_ItemUpgrade.GetHighWatermarkForItem) then
        return 0
    end
    local ok, characterHighWatermark, accountHighWatermark =
        pcall(C_ItemUpgrade.GetHighWatermarkForItem, itemLink)
    if not ok then return 0 end
    return math.max(tonumber(characterHighWatermark) or 0,
                    tonumber(accountHighWatermark) or 0)
end

-- Returns the highest crest tier present in an upgrade-cost list. Upgrade
-- responses can contain multiple currencies, so consumers must not assume the
-- first entry identifies the item's track.
function Addon:GetCrestTierFromCosts(costs)
    if type(costs) ~= "table" then return nil end

    local crestIDs = self.TRACKING and self.TRACKING.crestCurrencyIDs
    if type(crestIDs) ~= "table" then return nil end

    local bestTier, bestCurrencyID, bestCost
    for _, costInfo in ipairs(costs) do
        local currencyID = costInfo and tonumber(costInfo.currencyID)
        if currencyID then
            for tierIdx, crestID in ipairs(crestIDs) do
                if tonumber(crestID) == currencyID and (not bestTier or tierIdx > bestTier) then
                    bestTier = tierIdx
                    bestCurrencyID = currencyID
                    bestCost = tonumber(costInfo.cost) or 0
                    break
                end
            end
        end
    end
    return bestTier, bestCurrencyID, bestCost
end

local function ResolveTierCost(value, tierIdx, fallback)
    if type(value) == "table" then
        local n = tonumber(value[tierIdx])
        if n ~= nil then return n end
    else
        local n = tonumber(value)
        if n ~= nil then return n end
    end
    return fallback
end

local WATERMARK_TWOHAND_SLOT = 12
local WATERMARK_MAINHAND_SLOT = 13
local WATERMARK_ONEHAND_SLOT = 14
local WATERMARK_ONEHAND_SECOND_SLOT = 15
local WATERMARK_OFFHAND_SLOT = 16

local function HasCompleteItemUpgradeWatermarks(watermarks)
    if type(watermarks) ~= "table" then return false end
    for slot = 0, 16 do
        if tonumber(watermarks[slot]) == nil then return false end
    end
    return true
end

local function CalcWatermarkUpgradeCost(watermark, breakpoints, minimumWatermark, costPerStep)
    watermark = tonumber(watermark) or 0
    if watermark < minimumWatermark then return nil end

    local cost = 0
    for _, breakpoint in ipairs(breakpoints) do
        if watermark < breakpoint then
            cost = cost + costPerStep
        end
    end
    return cost
end

local WATERMARK_WEAPON_SLOTS = {
    WATERMARK_TWOHAND_SLOT,
    WATERMARK_MAINHAND_SLOT,
    WATERMARK_ONEHAND_SLOT,
    WATERMARK_ONEHAND_SECOND_SLOT,
    WATERMARK_OFFHAND_SLOT,
}

local function GetPreferredWatermarkWeaponSlots(watermarks, minimumWatermark)
    local minimum = tonumber(minimumWatermark) or 0
    local twoHandWatermark = tonumber(watermarks[WATERMARK_TWOHAND_SLOT]) or 0
    local highestWeaponWatermark = twoHandWatermark

    for _, slot in ipairs(WATERMARK_WEAPON_SLOTS) do
        local watermark = tonumber(watermarks[slot]) or 0
        if watermark > highestWeaponWatermark then
            highestWeaponWatermark = watermark
        end
    end

    if twoHandWatermark >= minimum and twoHandWatermark >= highestWeaponWatermark then
        return { WATERMARK_TWOHAND_SLOT }
    end

    local ranked = {}
    for _, slot in ipairs(WATERMARK_WEAPON_SLOTS) do
        local watermark = tonumber(watermarks[slot]) or 0
        if watermark >= minimum then
            ranked[#ranked + 1] = { slot = slot, watermark = watermark }
        end
    end
    table.sort(ranked, function(a, b)
        if a.watermark == b.watermark then
            return a.slot < b.slot
        end
        return a.watermark > b.watermark
    end)

    local weaponSlots = {}
    for i = 1, math.min(2, #ranked) do
        weaponSlots[#weaponSlots + 1] = ranked[i].slot
    end
    return weaponSlots
end

local function ForEachAchievementWatermark(watermarks, minimumWatermark, weaponSlots, fn)
    for slot = 0, 11 do
        local watermark = tonumber(watermarks[slot]) or 0
        if watermark >= minimumWatermark then
            fn(watermark)
        end
    end

    for _, slot in ipairs(weaponSlots or {}) do
        local watermark = tonumber(watermarks[slot]) or 0
        if watermark >= minimumWatermark then
            fn(watermark)
        end
    end
end

local function CalcWatermarkAchievementCost(watermarks, breakpoints, minimumWatermark, costPerStep)
    local totalCost = 0
    local weaponSlots = GetPreferredWatermarkWeaponSlots(watermarks, minimumWatermark)
    ForEachAchievementWatermark(watermarks, minimumWatermark, weaponSlots, function(watermark)
        totalCost = totalCost + (CalcWatermarkUpgradeCost(watermark, breakpoints, minimumWatermark, costPerStep) or 0)
    end)

    return totalCost
end

function Addon:GetCrestAchievementBreakpoints(tierIdx)
    local tracking = self.TRACKING or {}
    tierIdx = tonumber(tierIdx)
    local base = tonumber(tracking.ilvlBase)
    local step = tonumber(tracking.ilvlTrackStep)
    local offsets = tracking.ilvlRankOffsets
    local crestIDs = tracking.crestCurrencyIDs
    if not (tierIdx and tierIdx >= 1 and base and step and type(offsets) == "table"
            and #offsets > 0 and type(crestIDs) == "table") then
        return nil
    end

    local startRank = 3
    local targetRank = #offsets
    if tierIdx == #crestIDs and targetRank > startRank then
        targetRank = targetRank - 1
    end
    if targetRank < startRank then return nil end

    local tierBase = base + step * (tierIdx - 1)
    local breakpoints = {}
    for rank = startRank, targetRank do
        local offset = tonumber(offsets[rank])
        if offset then
            breakpoints[#breakpoints + 1] = tierBase + offset
        end
    end
    return (#breakpoints > 0) and breakpoints or nil
end

function Addon:GetCrestAchievementTargetItemLevel(tierIdx)
    local breakpoints = self:GetCrestAchievementBreakpoints(tierIdx)
    return type(breakpoints) == "table" and tonumber(breakpoints[#breakpoints]) or nil
end

function Addon:GetMinimumDisplayedItemLevel()
    local tracking = self.TRACKING or {}
    local base = tonumber(tracking.ilvlBase)
    return base and base > 0 and base or 0
end

function Addon:CalcCrestAchievementAverageItemLevel(snap, tierIdx)
    local watermarks = type(snap) == "table" and snap.itemUpgradeWatermarks or nil
    if type(watermarks) ~= "table" or not snap.itemUpgradeWatermarksCaptured
            or not HasCompleteItemUpgradeWatermarks(watermarks) then
        return nil
    end

    local minimumWatermark = self:GetMinimumDisplayedItemLevel()
    local total, count = 0, 0

    for slot = 0, 16 do
        local watermark = tonumber(watermarks[slot]) or 0
        if watermark >= minimumWatermark then
            total = total + watermark
            count = count + 1
        end
    end

    if count == 0 then return nil end
    return total / count
end

function Addon:GetCrestAchievementStepCost(tierIdx)
    local tracking = self.TRACKING or {}
    local normalCost = ResolveTierCost(tracking.crestUpgradeCostPerStep, tierIdx, 20)
    if not self:IsCrestDiscountUnlocked(tierIdx) then
        return normalCost
    end

    return ResolveTierCost(tracking.crestUpgradeCostReduced, tierIdx,
        math.max(1, math.floor(normalCost / 2)))
end

function Addon:GetCrestSlotUpgradeCost(_slotID, slotData, snap, tierIdx, effectiveMax)
    if not (type(slotData) == "table" and slotData.rank and effectiveMax) then return 0 end
    local rank = tonumber(slotData.rank)
    if not rank or rank >= effectiveMax then return 0 end

    local capturedCost = tonumber(slotData.upgradeCostRemaining)
    if capturedCost ~= nil then
        -- Prefer WoW's exact per-item remaining crest total when it is available.
        return capturedCost
    end

    local tracking = self.TRACKING or {}

    local normalList  = tracking.crestUpgradeCostPerStep
    local reducedList = tracking.crestUpgradeCostReduced
    local normalCost  = (snap and snap.upgradeCostPerStep and snap.upgradeCostPerStep[tierIdx])
                     or ResolveTierCost(normalList, tierIdx, 20)
    local reducedCost = ResolveTierCost(reducedList, tierIdx, math.max(1, math.floor(normalCost / 2)))
    local bestSlot = type(snap) == "table" and type(snap.bestGearSlots) == "table"
        and snap.bestGearSlots[_slotID] or nil
    local bestRank = 0
    if type(bestSlot) == "table" and tonumber(bestSlot.tierIdx) == tonumber(tierIdx) then
        bestRank = tonumber(bestSlot.rank) or 0
    end
    local hasDiscount = self:IsCrestDiscountUnlocked(tierIdx)

    local computedCost = 0
    for nextRank = rank + 1, effectiveMax do
        local stepCost = normalCost
        if hasDiscount and bestRank >= nextRank then
            stepCost = reducedCost
        end
        computedCost = computedCost + stepCost
    end

    return computedCost
end

function Addon:GetSlotEffectiveMax(slotData)
    if type(slotData) ~= "table" then return nil end
    if slotData.trueMaxRank ~= nil then
        if slotData.trueMaxRank >= (slotData.rank or 0) then return slotData.trueMaxRank end
        slotData.trueMaxRank = nil
    end
    return slotData.maxRank
end

function Addon:IsSlotLimitedCrafted(slotData, effectiveMax)
    if type(slotData) ~= "table" then return false end
    if slotData.isEmbellished then return true end
    effectiveMax = effectiveMax or self:GetSlotEffectiveMax(slotData)
    return effectiveMax and slotData.maxRank and effectiveMax < slotData.maxRank
end

function Addon:ShouldCountSlotUpgradeCost(slotID, slotData, snap, tierIdx, effectiveMax)
    if not (type(slotData) == "table" and slotData.rank and effectiveMax) then return false end
    if slotData.rank >= effectiveMax then return false end
    if self:IsSlotLimitedCrafted(slotData, effectiveMax) then return false end

    local bestSlot = type(snap) == "table" and type(snap.bestGearSlots) == "table"
        and snap.bestGearSlots[slotID] or nil
    if type(bestSlot) == "table" then
        local bestTier = tonumber(bestSlot.tierIdx)
        local bestRank = tonumber(bestSlot.rank) or 0
        if bestTier and bestTier > tonumber(tierIdx) then return false end
        if bestTier == tonumber(tierIdx) and bestRank >= effectiveMax then return false end
    end

    return true
end

function Addon:CalcTierUpgradeCost(snap, tierIdx)
    if self.IsTrackingSnapshotCurrentSeason and not self:IsTrackingSnapshotCurrentSeason(snap) then
        return 0
    end

    local gearSlots = self:GetEquippedUpgradeGearSlots(snap)
    if type(gearSlots) ~= "table" then return 0 end

    local totalCost = 0
    local function addSlotCost(slotID)
        local slotData = gearSlots[slotID]
        local effectiveMax = self:GetSlotEffectiveMax(slotData)
        if type(slotData) == "table" and slotData.tierIdx == tierIdx
                and self:ShouldCountSlotUpgradeCost(slotID, slotData, snap, tierIdx, effectiveMax) then
            totalCost = totalCost + self:GetCrestSlotUpgradeCost(slotID, slotData, snap, tierIdx, effectiveMax)
        end
    end

    if type(GEAR_SLOT_IDS) == "table" then
        for _, slotID in ipairs(GEAR_SLOT_IDS) do addSlotCost(slotID) end
    else
        for slotID in pairs(gearSlots) do addSlotCost(slotID) end
    end
    return totalCost
end

function Addon:CalcTierAchievementCost(snap, tierIdx)
    if self.IsTrackingSnapshotCurrentSeason and not self:IsTrackingSnapshotCurrentSeason(snap) then
        return 0
    end

    local watermarks = type(snap) == "table" and snap.itemUpgradeWatermarks or nil
    if type(watermarks) == "table" and snap.itemUpgradeWatermarksCaptured
            and HasCompleteItemUpgradeWatermarks(watermarks) then
        local breakpoints = self:GetCrestAchievementBreakpoints(tierIdx)
        if type(breakpoints) ~= "table" then return 0 end

        local costPerStep = self:GetCrestAchievementStepCost(tierIdx)
        local minimumWatermark = self:GetMinimumDisplayedItemLevel()
        return CalcWatermarkAchievementCost(watermarks, breakpoints, minimumWatermark, costPerStep)
    end

    local gearSlots = self:GetUpgradeGearSlots(snap)
    if type(gearSlots) ~= "table" then return 0 end

    local breakpoints = self:GetCrestAchievementBreakpoints(tierIdx)
    if type(breakpoints) ~= "table" then return 0 end

    local costPerStep = self:GetCrestAchievementStepCost(tierIdx)
    local minimumWatermark = self:GetMinimumDisplayedItemLevel()
    local totalCost = 0
    local function addSlotCost(slotID)
        local slotData = gearSlots[slotID]
        local ilvl = type(slotData) == "table" and tonumber(slotData.ilvl) or 0
        if ilvl >= minimumWatermark then
            for _, breakpoint in ipairs(breakpoints) do
                if ilvl < breakpoint then
                    totalCost = totalCost + costPerStep
                end
            end
        end
    end

    if type(GEAR_SLOT_IDS) == "table" then
        for _, slotID in ipairs(GEAR_SLOT_IDS) do addSlotCost(slotID) end
    else
        for slotID in pairs(gearSlots) do addSlotCost(slotID) end
    end
    return totalCost
end

function Addon:GetCrestAvailabilityForTier(snap, tierIdx)
    local tracking = self.TRACKING
    local crestID = tracking and tracking.crestCurrencyIDs and tracking.crestCurrencyIDs[tierIdx]
    local heldQty, tradeupQty, earnableQty = 0, 0, 0
    if crestID and snap and type(snap.rightRows) == "table" then
        for _, row in ipairs(snap.rightRows) do
            if row.type == SNAP_TYPES.CREST and row.id == crestID then
                heldQty    = tonumber(row.qty) or 0
                tradeupQty = tonumber(row.tradeup) or 0
                local earned = tonumber(row.earned) or 0
                local cap = tonumber(row.cap) or 0
                earnableQty = math.max(0, cap - earned)
                break
            end
        end
    end
    return heldQty, tradeupQty, heldQty + tradeupQty + earnableQty, earnableQty
end

function Addon:CalcCrestAchievementCapWeeksNeeded(requiredQty, heldQty, tradeupQty, earnableQty)
    local required = tonumber(requiredQty) or 0
    local current = (tonumber(heldQty) or 0) + (tonumber(tradeupQty) or 0)
    local earnable = tonumber(earnableQty) or 0
    local remainingAfterThisWeek = math.max(0, required - current - earnable)
    return math.ceil(remainingAfterThisWeek / 100)
end

local function ComputeCrestTradeup(cache, crestCount, batchLower, batchHigher)
    local highestTradeTarget
    for i = crestCount, 2, -1 do
        if cache.unlocked[i - 1] then highestTradeTarget = i; break end
    end
    local effective, gained = cache.effective, cache.gained
    effective[1] = cache.cur[1] or 0; gained[1] = 0
    for i = 2, crestCount do
        local tradeFromPrev = 0
        if cache.unlocked[i - 1] then
            -- Always cascade using the effective (potentially traded-up) amount from
            -- the previous tier.  Crest trading at the vendor is based on wallet
            -- balance, not weekly earn caps, so the weekly-cap check was removed.
            tradeFromPrev = floor((effective[i - 1] or 0) / batchLower) * batchHigher
        end
        gained[i]    = tradeFromPrev
        effective[i] = (cache.cur[i] or 0) + tradeFromPrev
    end
    return highestTradeTarget, gained
end

local _crestConvertTooltipTexts = {}
local _crestAmountTooltipTexts = {}
local _crestConvertTooltipPool = {}
local _crestAmountTooltipPool = {}
local _catalystTooltipPool = {}
local _miscTooltipPool = {}

local function ClearTooltipRefs(refs, count)
    for i = 1, max(#refs, count or 0) do
        refs[i] = nil
    end
    return refs
end

local function BeginTooltipTable(pool, key)
    local t = pool[key]
    if not t then
        t = {}
        pool[key] = t
    end
    local oldCount = t._count or #t
    for i = 1, oldCount do
        local line = t[i]
        if line then
            line.text = nil
            line.r = nil
            line.g = nil
            line.b = nil
            line.a = nil
        end
    end
    t._count = 0
    return t
end

local function AddTooltipLine(t, text, r, g, b, a)
    local n = (t._count or 0) + 1
    local line = t[n]
    if not line then
        line = {}
        t[n] = line
    end
    line.text = text
    line.r = r
    line.g = g
    line.b = b
    line.a = a
    t._count = n
end

local function FinishTooltipTable(t)
    local count = t._count or 0
    for i = count + 1, #t do
        t[i] = nil
    end
    return t
end

local function GetCrestLines()
    local tracking = Addon.TRACKING
    if not tracking then return { "", "", "", "" } end
    local ids, crestCount = GetCrestIDsAndCount(tracking)
    local cache = EnsureCrestCache(tracking, crestCount)
    local out, labelOut, valueOut = ResetCrestOutput(cache, crestCount)
    local batchLower, batchHigher = GetCrestTradeBatches(tracking)
    PopulateCrestCurCap(cache, ids, crestCount)
    PopulateCrestUnlocked(cache, crestCount)
    local highestTradeTarget, gained = ComputeCrestTradeup(cache, crestCount, batchLower, batchHigher)
    local crestLabels = BuildCrestLabels(ids, crestCount)
    local convertTooltipTexts = ClearTooltipRefs(_crestConvertTooltipTexts, crestCount)
    local amountTooltipTexts  = ClearTooltipRefs(_crestAmountTooltipTexts, crestCount)
    for i = 1, crestCount do
        local id = ids[i]
        if id then
            local name = GetCrestDisplayName(tracking, i, id, crestLabels)
            if name then
                local earned = cache.earned[i]    or 0  -- totalEarned toward weekly cap
                local wkMax  = cache.weeklyMax[i] or 0  -- weekly soft cap
                local held   = cache.cur[i]       or 0  -- wallet balance
                -- Main: current held amount; tooltip breaks out earned and remaining.
                local xy    = tostring(held)
                local color
                if wkMax > 0 then
                    color = (earned >= wkMax) and COLORS.dim or (cache.unlocked[i] and COLORS.green or COLORS.red)
                else
                    color = (held > 0) and COLORS.green or COLORS.dim
                end
                local tipBonus = math.max(0, held - earned)
                local tipTbl   = BeginTooltipTable(_crestAmountTooltipPool, i)
                if wkMax > 0 then
                    local earnable = math.max(0, wkMax - earned)
                    AddTooltipLine(tipTbl, (L.TRACKING_EARNED_FMT or "Earned: %d/%d"):format(earned, wkMax))
                    AddTooltipLine(tipTbl, (L.TRACKING_HELD_FMT or "Held: %d"):format(held), 0.75, 0.75, 0.75)
                    if earnable > 0 then
                        AddTooltipLine(tipTbl, (L.TRACKING_STILL_EARNABLE_FMT or "Still earnable: %d"):format(earnable), 1.0, 0.82, 0.0)
                    else
                        AddTooltipLine(tipTbl, L.TRACKING_WEEKLY_CAP_REACHED or "Weekly cap reached", 0.3, 1.0, 0.3)
                    end
                else
                    AddTooltipLine(tipTbl, L.TRACKING_NOT_EARNABLE_YET or "Not earnable yet", 1.0, 0.82, 0.0)
                    AddTooltipLine(tipTbl, (L.TRACKING_HELD_FMT or "Held: %d"):format(held), 0.75, 0.75, 0.75)
                end
                if tipBonus > 0 then
                    AddTooltipLine(tipTbl, (L.TRACKING_BONUS_TRADEUP_FMT or "Bonus (trade-up): +%d"):format(tipBonus), 0.6, 0.8, 1.0)
                end
                if (tipTbl._count or 0) == 0 then AddTooltipLine(tipTbl, (L.TRACKING_HELD_FMT or "Held: %d"):format(held)) end
                amountTooltipTexts[i] = FinishTooltipTable(tipTbl)
                local tradeUp = ""
                if highestTradeTarget and i == highestTradeTarget then
                    local n = tonumber(gained[i]) or 0
                    if n > 0 then
                        tradeUp = " " .. ColorWrap("ff4da6ff", "+" .. tostring(n))
                        local thisEarned = cache.earned[i]    or 0
                        local thisWkMax  = cache.weeklyMax[i] or 0
                        local cappedN    = (thisWkMax > 0) and math.min(n, math.max(0, thisWkMax - thisEarned)) or n
                        local tipTbl     = BeginTooltipTable(_crestConvertTooltipPool, i)
                        if thisWkMax <= 0 then
                            AddTooltipLine(tipTbl, L.TRACKING_NOT_EARNABLE_YET or "Not earnable yet", 1.0, 0.82, 0.0)
                            AddTooltipLine(tipTbl, (L.TRACKING_TRADEUP_UNCAPPED_FMT or "Uncapped: %d"):format(n))
                        elseif cappedN ~= n then
                            AddTooltipLine(tipTbl, (L.TRACKING_TRADEUP_CURRENTLY_EARNABLE_FMT or "Currently earnable: %d"):format(cappedN))
                            AddTooltipLine(tipTbl, (L.TRACKING_TRADEUP_UNCAPPED_FMT           or "Uncapped: %d"):format(n))
                        else
                            AddTooltipLine(tipTbl, (L.TRACKING_TRADEUP_EARNABLE_FMT           or "Earnable: %d"):format(n))
                        end
                        local convertTip = L.TRACKING_CONVERT_TOOLTIP or ""
                        if convertTip ~= "" then
                            AddTooltipLine(tipTbl, convertTip, 0.7, 0.7, 0.7)
                        end
                        convertTooltipTexts[i] = FinishTooltipTable(tipTbl)
                    end
                end
                local lbl = ColorWrap(GetCurrencyQualityColor(id), tostring(name)) .. tradeUp
                local val = ColorWrap(color, xy)
                labelOut[i] = lbl; valueOut[i] = val; out[i] = lbl .. " " .. val
            end
        else
            local lbl = ColorWrap(COLORS.dim, L.TRACKING_CREST_LABEL or "")
            local val = ColorWrap(COLORS.red, L.TRACKING_NO_ID or "")
            labelOut[i] = lbl; valueOut[i] = val; out[i] = lbl .. " " .. val
        end
    end
    return out, labelOut, valueOut, crestCount, convertTooltipTexts, amountTooltipTexts
end

--  Catalyst 
-- Returns current qty and cap for Catalyst charges, trying currency ID then
-- C_Catalyst APIs. Extracted so FillCurrencySnapshot can reuse the same logic
-- as GetCatalystParts without duplicating the fallback chain.
GetCatalystRawQtyCap = function()
    local cur, cap
    local id    = Addon.TRACKING and Addon.TRACKING.catalystCurrencyID
    local hasID = (id and tonumber(id) and tonumber(id) > 0) and true or false
    if hasID then
        local q, c = FormatCurrencyProgressParts(tonumber(id))
        cur = tonumber(q); cap = tonumber(c)
    end
    if cur == nil and C_Catalyst then
        if C_Catalyst.GetCharges then
            local charges = C_Catalyst.GetCharges()
            if type(charges) == "table" then
                cur = tonumber(charges.currentCharges or charges.numCharges or charges.charges)
                cap = tonumber(charges.maxCharges or charges.maximumCharges)
            end
        end
        if cur == nil and C_Catalyst.GetNumCharges then cur = tonumber(C_Catalyst.GetNumCharges()) end
        if cap == nil and C_Catalyst.GetMaxCharges  then cap = tonumber(C_Catalyst.GetMaxCharges())  end
    end
    return cur, cap
end

local function GetCatalystParts()
    local id    = Addon.TRACKING and Addon.TRACKING.catalystCurrencyID
    local hasID = (id and tonumber(id) and tonumber(id) > 0) and true or false
    local catName  = (hasID and GetCurrencyName(tonumber(id))) or L.TRACKING_CATALYST_LABEL or ""
    local catColor = (hasID and GetCurrencyQualityColor(tonumber(id))) or COLORS.dim
    local cur, cap = GetCatalystRawQtyCap()
    cur = tonumber(cur)
    cap = tonumber(cap)
    if not cur then
        if not hasID then return "", "", nil end
        return ColorWrap(catColor, catName), ColorWrap(COLORS.red, NA), nil
    end
    local catTip
    if cap and cap > 0 then
        catTip = BeginTooltipTable(_catalystTooltipPool, id or "catalyst")
        AddTooltipLine(catTip, (L.TRACKING_CHARGES_XY_FMT or "Charges: %d/%d"):format(cur, cap))
        if cur < cap then
            AddTooltipLine(catTip, (L.TRACKING_STILL_EARNABLE_FMT or "Still earnable: %d"):format(cap - cur), 1.0, 0.82, 0.0)
        else
            AddTooltipLine(catTip, L.TRACKING_WEEKLY_CAP_REACHED or "Weekly cap reached", 0.3, 1.0, 0.3)
        end
        catTip = FinishTooltipTable(catTip)
    end
    local catValColor = (cap and cap > 0 and cur >= cap) and COLORS.green
                     or (cur > 0)                         and COLORS.yellow
                     or COLORS.red
    return ColorWrap(catColor, catName), ColorWrap(catValColor, ("%d"):format(cur)), catTip
end

local function GetGenericCurrencyParts(id)
    id = tonumber(id)
    if not (id and id > 0) then return "", "" end

    local earned, cap = FormatCurrencyProgressParts(id)
    earned = tonumber(earned) or 0
    cap = tonumber(cap) or 0
    local rawInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    local held    = (rawInfo and tonumber(rawInfo.quantity)) or 0
    local name = GetCurrencyName(id) or tostring(id)
    local lbl = ColorWrap(GetCurrencyQualityColor(id), name)
    local canEarnMore = cap > 0 and earned < cap
    local miscColor = canEarnMore and COLORS.yellow
                   or (cap > 0 and earned >= cap) and COLORS.green
                   or (held > 0)                  and COLORS.yellow
                   or COLORS.dim
    local val = ColorWrap(miscColor, tostring(held))
    local miscTip
    if cap > 0 then
        local earnable = math.max(0, cap - earned)
        miscTip = BeginTooltipTable(_miscTooltipPool, id)
        AddTooltipLine(miscTip, (L.TRACKING_EARNED_FMT or "Earned: %d/%d"):format(earned, cap))
        AddTooltipLine(miscTip, (L.TRACKING_HELD_FMT or "Held: %d"):format(held), 0.75, 0.75, 0.75)
        if earnable > 0 then
            AddTooltipLine(miscTip, (L.TRACKING_STILL_EARNABLE_FMT or "Still earnable: %d"):format(earnable), 1.0, 0.82, 0.0)
        else
            AddTooltipLine(miscTip, L.TRACKING_WEEKLY_CAP_REACHED or "Weekly cap reached", 0.3, 1.0, 0.3)
        end
        miscTip = FinishTooltipTable(miscTip)
    end
    return lbl, val, miscTip
end

--  Public API 

-- Reusable buffers for GetCurrencyPanelRows – avoids allocating new tables on
-- every tracking update (which fires on bag updates, currency changes, etc.).
local _panelRowBuf  = {}  -- result array, returned and reused each call
local _panelRowPool = {}  -- pool of row sub-tables, one slot per max possible row
local function FillRow(n, lbl, val, iconID, currencyID, tooltipText, amountTooltipText, itemID, questKey)
    if not _panelRowPool[n] then _panelRowPool[n] = {} end
    local r             = _panelRowPool[n]
    r.label             = lbl
    r.value             = val
    r.iconID            = iconID
    r.currencyID        = currencyID
    r.tooltipText       = tooltipText or nil
    r.amountTooltipText = amountTooltipText or nil
    r.itemID            = itemID or nil
    r.questKey          = questKey or nil
    _panelRowBuf[n] = r
end

function Addon:ReleaseCurrencyRuntimeCaches()
    Wipe(_crestConvertTooltipTexts)
    Wipe(_crestAmountTooltipTexts)
    Wipe(_crestConvertTooltipPool)
    Wipe(_crestAmountTooltipPool)
    Wipe(_catalystTooltipPool)
    Wipe(_miscTooltipPool)
    Wipe(_panelRowBuf)
    Wipe(_panelRowPool)
    Wipe(_trackedEntryBuf)
    Wipe(_trackedEntryPool)
    -- Currency quantities are read live each render, but label/icon/quality are
    -- cached per ID. Clear those static caches whenever tracking is reinitialized
    -- so season overrides or ID table edits refresh display metadata immediately.
    Wipe(_currencyStaticCache)
    _crestLabelsCache.key = nil
    _crestLabelsCache.labels = nil
end

--- Returns an ordered list of currency rows ready to display in the right column.
--- Each entry: { label, value, iconID, currencyID }.  Empty rows are omitted.
--- The returned table is reused across calls – do not hold a reference past the
--- next tracking update.
function Addon:GetCurrencyPanelRows()
    local n        = 0
    local tracking = self.TRACKING

    local _, labelLines, valueLines, crestCount, crestConvertTooltips, crestAmountTooltips = GetCrestLines()
    local entries = self:GetTrackedCurrencyEntries(false)
    for _, entry in ipairs(entries) do
        if n >= RIGHT_LINE_COUNT then break end
        local id = entry.id
        if entry.type == SNAP_TYPES.CREST then
            local i = entry.crestIdx
            local lbl = i and (labelLines and labelLines[i]) or ""
            local val = i and (valueLines and valueLines[i]) or ""
            if IsNonEmptyText(lbl) or IsNonEmptyText(val) then
                n = n + 1
                FillRow(n, lbl, val, GetCurrencyIconID(id), id,
                    i and crestConvertTooltips and crestConvertTooltips[i],
                    i and crestAmountTooltips  and crestAmountTooltips[i])
            end
        elseif entry.type == SNAP_TYPES.CATALYST then
            local cLbl, cVal, cTip = GetCatalystParts()
            if IsNonEmptyText(cLbl) or IsNonEmptyText(cVal) then
                n = n + 1
                FillRow(n, cLbl, cVal, GetCurrencyIconID(id), id, nil, cTip)
            end
        elseif entry.type == SNAP_TYPES.SPARKS then
            local sLbl, sVal, sTip = GetSparksParts()
            if IsNonEmptyText(sLbl) or IsNonEmptyText(sVal) then
                n = n + 1
                FillRow(n, sLbl, sVal, GetCurrencyIconID(id), id, nil, sTip)
            end
        elseif entry.type == SNAP_TYPES.COFFERKEYS then
            local kLbl, kVal, kTip = GetCofferKeysParts()
            if IsNonEmptyText(kLbl) or IsNonEmptyText(kVal) then
                n = n + 1
                FillRow(n, kLbl, kVal, GetCurrencyIconID(id), id, nil, kTip)
            end
        elseif entry.type == SNAP_TYPES.WEAPUPG then
            local shardItemID = Addon:GetWeaponUpgradeShardItemID()
            local combinedItemID = Addon:GetWeaponUpgradeCombinedItemID()
            local shardsPerCombined = Addon:GetWeaponUpgradeShardsPerCombined()
            local shardHeld    = (shardItemID > 0 and GetItemCount and GetItemCount(shardItemID)) or 0
            local combinedHeld = (combinedItemID > 0 and GetItemCount and GetItemCount(combinedItemID)) or 0
            local needCount    = GetWeaponUpgradeNeedCount()
            local total        = combinedHeld + shardHeld / shardsPerCombined
            local iName, iQuality, iTex
            if combinedItemID > 0 and GetItemInfo then
                iName, _, iQuality, _, _, _, _, _, _, iTex = GetItemInfo(combinedItemID)
            end
            if not iTex and C_Item and C_Item.GetItemIconByID then
                iTex = combinedItemID > 0 and C_Item.GetItemIconByID(combinedItemID) or nil
            end
            local lbl
            if iName then
                local qhex = GetQualityHex(GetItemDisplayQuality(combinedItemID) or iQuality, COLORS.white)
                lbl = ColorWrap(qhex, iName)
            else
                lbl = ColorWrap(COLORS.gold, L.TRACKING_UPGRADE_SIGIL or "Upgrade Sigil")
            end
            local val
            if needCount > 0 then
                local valStr = FormatSigilAmount(total) .. "/" .. needCount
                val = ColorWrap(ColorForXY(total, needCount), valStr)
            else
                val = ColorWrap(COLORS.green, FormatSigilAmount(total))
            end
            n = n + 1
            FillRow(n, lbl, val, iTex, nil, nil, nil, combinedItemID > 0 and combinedItemID or nil)
        else
            local lbl, val, tip = GetGenericCurrencyParts(id)
            if IsNonEmptyText(lbl) or IsNonEmptyText(val) then
                n = n + 1
                FillRow(n, lbl, val, GetCurrencyIconID(id), id, nil, tip)
            end
        end
    end

    -- Delver's Bounty (quest)
    if n < RIGHT_LINE_COUNT and not Addon:IsQuestHidden("delversBounty") then
        local bLbl, bVal = GetDelversBountyParts()
        if IsNonEmptyText(bLbl) or IsNonEmptyText(bVal) then
            local bItemID = tracking and tracking.questItemIDs and tonumber(tracking.questItemIDs.delversBounty) or 0
            if not (bItemID > 0 and Addon:IsItemHidden(bItemID)) then
                n = n + 1
                local bIcon, bLblFinal = nil, bLbl
                if bItemID > 0 then
                    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(bItemID)
                    if itemTexture then bIcon = itemTexture end
                    if itemName then
                        local qhex = GetQualityHex(itemQuality, COLORS.white)
                        bLblFinal = ColorWrap(qhex, itemName)
                    end
                end
                FillRow(n, bLblFinal, bVal, bIcon, nil, nil, nil, bItemID > 0 and bItemID or nil, "delversBounty")
            end
        end
    end

    -- Delve Boss (quest)
    if n < RIGHT_LINE_COUNT and not Addon:IsQuestHidden("delveBoss") then
        local sLbl, sVal = GetDelveBossParts()
        if IsNonEmptyText(sLbl) or IsNonEmptyText(sVal) then
            local sItemID = GetTrackedQuestItemID("delveBoss")
            if not (sItemID > 0 and Addon:IsItemHidden(sItemID)) then
                n = n + 1
                local sIcon, sLblFinal = nil, sLbl
                if sItemID > 0 then
                    local itemName, _, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(sItemID)
                    if itemTexture then sIcon = itemTexture end
                    if itemName then
                        local qhex = GetQualityHex(itemQuality, COLORS.white)
                        sLblFinal = ColorWrap(qhex, itemName)
                    end
                end
                FillRow(n, sLblFinal, sVal, sIcon, nil, nil, nil, sItemID > 0 and sItemID or nil, "delveBoss")
            end
        end
    end

    -- Weekly Prey (quest)
    if n < RIGHT_LINE_COUNT and not Addon:IsQuestHidden("weeklyPrey") then
        local pLbl, pVal = GetWeeklyPreyParts()
        if IsNonEmptyText(pLbl) or IsNonEmptyText(pVal) then
            n = n + 1
            FillRow(n, pLbl, pVal, nil, nil, nil, nil, nil, "weeklyPrey")
        end
    end

    -- Trim stale entries from a previous call that had more rows.
    for i = n + 1, #_panelRowBuf do _panelRowBuf[i] = nil end

    return _panelRowBuf
end

--- Populates snap.rightRows with structured (type-tagged) snapshot data.
--- Called from Overlay's BuildTrackingSnapshot API.
function Addon:FillCurrencySnapshot(snap)
    if type(snap.rightRows) ~= "table" then snap.rightRows = {} end
    local rows = snap.rightRows
    local rowCount = 0
    local tracking = self.TRACKING
    local crestCache, crestTradeups
    if tracking then
        local ids, crestCount = GetCrestIDsAndCount(tracking)
        crestCache = EnsureCrestCache(tracking, crestCount)
        local batchLower, batchHigher = GetCrestTradeBatches(tracking)
        PopulateCrestCurCap(crestCache, ids, crestCount)
        PopulateCrestUnlocked(crestCache, crestCount)
        _, crestTradeups = ComputeCrestTradeup(crestCache, crestCount, batchLower, batchHigher)
    end

    local catQty = GetCatalystRawQtyCap()
    local sparkID = tracking and tonumber(tracking.sparkCurrencyID)
    local sQty, sHeld
    if sparkID and sparkID > 0 then
        sQty = FormatCurrencyProgressParts(sparkID)
        local sparkInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(sparkID)
        sHeld = (sparkInfo and tonumber(sparkInfo.quantity)) or 0
    end

    for _, entry in ipairs(self:GetTrackedCurrencyEntries(true)) do
        local id = tonumber(entry.id)
        if entry.type == SNAP_TYPES.WEAPUPG then
            local shardItemID = Addon:GetWeaponUpgradeShardItemID()
            local combinedItemID = Addon:GetWeaponUpgradeCombinedItemID()
            rowCount = rowCount + 1
            local row = AcquireSnapshotRow(rows, rowCount)
            row.type        = SNAP_TYPES.WEAPUPG
            row.shardQty    = (shardItemID > 0 and GetItemCount and GetItemCount(shardItemID)) or 0
            row.combinedQty = (combinedItemID > 0 and GetItemCount and GetItemCount(combinedItemID)) or 0
            row.need        = GetWeaponUpgradeNeedCount(snap)
        elseif id and id > 0 then
            if entry.type == SNAP_TYPES.CREST and crestCache and entry.crestIdx then
                local i = entry.crestIdx
                local tradeup = crestTradeups and crestTradeups[i]
                rowCount = rowCount + 1
                local row = AcquireSnapshotRow(rows, rowCount)
                row.type = SNAP_TYPES.CREST
                row.id = id
                row.qty = crestCache.cur[i] or 0
                row.earned = crestCache.earned[i] or 0
                row.cap = crestCache.weeklyMax[i] or 0
                row.tradeup = (tradeup and tradeup > 0) and tradeup or nil
            elseif entry.type == SNAP_TYPES.CATALYST then
                rowCount = rowCount + 1
                local row = AcquireSnapshotRow(rows, rowCount)
                row.type = SNAP_TYPES.CATALYST
                row.id = id
                row.qty = catQty or 0
            elseif entry.type == SNAP_TYPES.SPARKS then
                rowCount = rowCount + 1
                local row = AcquireSnapshotRow(rows, rowCount)
                row.type = SNAP_TYPES.SPARKS
                row.id = id
                row.qty = tonumber(sQty) or 0
                row.held = tonumber(sHeld) or 0
            elseif entry.type == SNAP_TYPES.COFFERKEYS then
                local shardsID = tracking and tonumber(tracking.cofferKeysCurrencyID)
                local getCurrency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo
                local shardInfo = (getCurrency and shardsID and shardsID > 0) and getCurrency(shardsID) or nil
                local earnedShards = (shardInfo and tonumber(shardInfo.quantityEarnedThisWeek)) or 0
                local displayInfo = getCurrency and getCurrency(id) or nil
                rowCount = rowCount + 1
                local row = AcquireSnapshotRow(rows, rowCount)
                row.type = SNAP_TYPES.COFFERKEYS
                row.id = id
                row.qty = floor(earnedShards / 100)
                row.held = (displayInfo and tonumber(displayInfo.quantity)) or 0
            else
                local qty = FormatCurrencyProgressParts(id)
                local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
                rowCount = rowCount + 1
                local row = AcquireSnapshotRow(rows, rowCount)
                row.type = SNAP_TYPES.MISC
                row.id = id
                row.qty = tonumber(qty) or 0
                row.held = (info and tonumber(info.quantity)) or 0
            end
        end
    end
    local bDone = GetQuestDoneRaw("delversBounty")
    if bDone ~= nil then
        rowCount = rowCount + 1
        local row = AcquireSnapshotRow(rows, rowCount)
        row.type = SNAP_TYPES.QUEST
        row.key = "delversBounty"
        row.done = bDone
    end
    local sDone = GetQuestDoneRaw("delveBoss")
    if sDone ~= nil then
        rowCount = rowCount + 1
        local row = AcquireSnapshotRow(rows, rowCount)
        row.type = SNAP_TYPES.QUEST
        row.key = "delveBoss"
        row.done = sDone
    end
    local pDone = GetQuestDoneRaw("weeklyPrey")
    if pDone ~= nil then
        rowCount = rowCount + 1
        local row = AcquireSnapshotRow(rows, rowCount)
        row.type = SNAP_TYPES.QUEST
        row.key = "weeklyPrey"
        row.done = pDone
    end
    for i = rowCount + 1, #rows do
        rows[i] = nil
    end
end

--- Converts a single typed snapshot row into a (label, value) display string pair.
--- Used by the Overlay when rendering another character's stored snapshot.
function Addon:RenderCurrencySnapshotRow(row)
    local t = row.type
    if t == "crest" then
        local id  = row.id
        local qty = tonumber(row.qty) or 0
        local tracking = self.TRACKING
        local crestIDs, crestCount = GetCrestIDsAndCount(tracking or {})
        local crestLabels = BuildCrestLabels(crestIDs, crestCount)
        local tierIdx
        for i = 1, crestCount do
            if tonumber(crestIDs[i]) == tonumber(id) then
                tierIdx = i
                break
            end
        end
        local name  = GetCrestDisplayName(tracking, tierIdx, id, crestLabels)
        local lbl   = ColorWrap(GetCurrencyQualityColor(id), tostring(name))
        local cap, hasCurrentCap = GetCurrentCurrencySnapshotCap(SNAP_TYPES.CREST, id)
        qty = ClampSnapshotAmountToCurrentCap(qty, cap, hasCurrentCap)
        if cap > 0 then
            return lbl, ColorWrap(ColorForXY(qty, cap), tostring(qty))
        end
        return lbl, ColorWrap((qty <= 0) and COLORS.dim or COLORS.green, tostring(qty))
    elseif t == "catalyst" then
        local qty = tonumber(row.qty) or 0
        local tracking = self.TRACKING
        local catID = tracking and tonumber(tracking.catalystCurrencyID)
        local catLabel = (catID and catID > 0 and GetCurrencyName(catID)) or L.TRACKING_CATALYST_LABEL or ""
        local lbl = ColorWrap(GetCurrencyQualityColor(catID), catLabel)
        local cap, hasCurrentCap = GetCurrentCurrencySnapshotCap(SNAP_TYPES.CATALYST, catID)
        qty = ClampSnapshotAmountToCurrentCap(qty, cap, hasCurrentCap)
        if cap > 0 then
            return lbl, ColorWrap(ColorForXY(qty, cap), tostring(qty))
        end
        return lbl, ColorWrap((qty <= 0) and COLORS.red or COLORS.green, ("%d"):format(qty))
    elseif t == "sparks" then
        local qty = tonumber(row.qty) or 0
        local id  = self.TRACKING and tonumber(self.TRACKING.sparkCurrencyID) or tonumber(row.id)
        local name  = (id and id > 0 and GetCurrencyName(id)) or L.TRACKING_SPARKS_LABEL or ""
        local lbl   = ColorWrap(GetCurrencyQualityColor(id), name)
        local cap, hasCurrentCap = GetCurrentCurrencySnapshotCap(SNAP_TYPES.SPARKS, id)
        qty = ClampSnapshotAmountToCurrentCap(qty, cap, hasCurrentCap)
        local held = ClampSnapshotAmountToCurrentCap(tonumber(row.held) or qty, cap, hasCurrentCap)
        if cap > 0 then
            local color = (qty >= cap) and COLORS.green
                       or (qty > 0) and COLORS.yellow
                       or COLORS.dim
            return lbl, ColorWrap(color, tostring(held))
        end
        return lbl, ColorWrap((qty <= 0) and COLORS.dim or COLORS.yellow, tostring(held))
    elseif t == "cofferkeys" then
        local qty = tonumber(row.qty) or 0
        local held = tonumber(row.held)
        local id  = tonumber(row.id)
            or (self.TRACKING and tonumber(self.TRACKING.cofferKeysDisplayCurrencyID))
            or (self.TRACKING and tonumber(self.TRACKING.cofferKeysCurrencyID))
        local cap, hasCurrentCap = GetCurrentCurrencySnapshotCap(SNAP_TYPES.COFFERKEYS, id)
        qty = ClampSnapshotAmountToCurrentCap(qty, cap, hasCurrentCap)
        local name = (id and id > 0 and GetCurrencyName(id)) or L.TRACKING_COFFER_KEYS_LABEL or "Coffer Keys"
        local lbl = ColorWrap(GetCurrencyQualityColor(id), name)
        local displayHeld = ClampSnapshotAmountToCurrentCap(held or qty, cap, hasCurrentCap)
        if cap > 0 then
            local color = (qty >= cap) and COLORS.green
                or (displayHeld > 0 and COLORS.yellow)
                or COLORS.red
            return lbl, ColorWrap(color, tostring(displayHeld))
        end
        return lbl, ColorWrap((displayHeld <= 0) and COLORS.red or COLORS.yellow, tostring(displayHeld))
    elseif t == "misc" then
        local id  = tonumber(row.id)
        local qty = tonumber(row.qty) or 0
        local name = (id and id > 0 and GetCurrencyName(id)) or tostring(id or "?")
        local lbl  = ColorWrap(GetCurrencyQualityColor(id), name)
        local cap, hasCurrentCap = GetCurrentCurrencySnapshotCap(SNAP_TYPES.MISC, id)
        qty = ClampSnapshotAmountToCurrentCap(qty, cap, hasCurrentCap)
        local held = ClampSnapshotAmountToCurrentCap(tonumber(row.held) or qty, cap, hasCurrentCap)
        if cap > 0 then
            local color = (qty < cap) and COLORS.yellow or COLORS.green
            return lbl, ColorWrap(color, ("%d"):format(held))
        end
        return lbl, ColorWrap((held <= 0) and COLORS.dim or COLORS.yellow, tostring(held))
    elseif t == "quest" then
        local key  = row.key
        local done = row.done
        local labelText = ""
        if key == "delversBounty" then labelText = L.TRACKING_QUEST_DELVERS_BOUNTY or ""
        elseif key == "delveBoss" or key == "nullaeusSpoils" then labelText = L.TRACKING_QUEST_DELVE_BOSS or L.TRACKING_QUEST_NULLAEUS_SPOILS or ""
        elseif key == "weeklyPrey" then labelText = L.TRACKING_QUEST_WEEKLY_PREY or "" end
        if not IsNonEmptyText(labelText) then return "", "" end
        local lbl = ColorWrap(COLORS.dim, labelText)
        if done == nil then return lbl, ColorWrap(COLORS.red, NA)
        elseif done   then return lbl, ColorWrap(COLORS.green, "1/1")
        else               return lbl, ColorWrap(COLORS.red,   "0/1") end
    elseif t == "weapupg" then
        local combinedItemID = Addon:GetWeaponUpgradeCombinedItemID()
        local shardsPerCombined = Addon:GetWeaponUpgradeShardsPerCombined()
        local shardQty    = tonumber(row.shardQty)    or 0
        local combinedQty = tonumber(row.combinedQty) or 0
        local need        = tonumber(row.need)        or 0
        local total       = combinedQty + shardQty / shardsPerCombined
        local iName, iQuality
        if combinedItemID > 0 and GetItemInfo then
            iName, _, iQuality = GetItemInfo(combinedItemID)
        end
        local lbl
        if iName then
            local qhex = GetQualityHex(GetItemDisplayQuality(combinedItemID) or iQuality, COLORS.white)
            lbl = ColorWrap(qhex, iName)
        else
            lbl = ColorWrap(COLORS.gold, L.TRACKING_UPGRADE_SIGIL or "Upgrade Sigil")
        end
        if need > 0 then
            local valStr = FormatSigilAmount(total) .. "/" .. need
            return lbl, ColorWrap(ColorForXY(total, need), valStr)
        end
        return lbl, ColorWrap(COLORS.green, FormatSigilAmount(total))
    end
    return "", ""
end

--- Expose icon/name helpers for use by the Overlay snapshot renderer.
function Addon:GetCurrencyIcon(id) return GetCurrencyIconID(id) end
function Addon:GetCurrencyName(id) return GetCurrencyName(id) end
function Addon:GetCurrentCurrencySnapshotCap(rowType, currencyID)
    return GetCurrentCurrencySnapshotCap(rowType, currencyID)
end

--- Expose crest ordering so consumers don't duplicate the fallback logic.
function Addon:GetCrestIDsAndCount()
    return GetCrestIDsAndCount(self.TRACKING or {})
end
