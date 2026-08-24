-- LariasWeeklyChecklist_Snapshot.lua
-- Captures tracking data without depending on tracking-panel UI state.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local API = Addon.TrackingSnapshotAPI or {}
Addon.TrackingSnapshotAPI = API

local API_DEFAULTS = {
    TooltipInfo = function() return C_TooltipInfo end,
    MythicPlus = function() return C_MythicPlus end,
    ChallengeMode = function() return C_ChallengeMode end,
    ItemUpgrade = function() return C_ItemUpgrade end,
    ItemLocation = function() return ItemLocation end,
    Item = function() return C_Item end,
    GetInventoryItemLink = function() return GetInventoryItemLink end,
    GetDetailedItemLevelInfo = function() return GetDetailedItemLevelInfo end,
    GetInventoryItemLevel = function() return GetInventoryItemLevel end,
}

-- Tests can assign any API field directly. Missing fields resolve against the
-- live WoW globals on access, including APIs loaded on demand after login.
setmetatable(API, {
    __index = function(_, key)
        local provider = API_DEFAULTS[key]
        return provider and provider() or nil
    end,
})

local function IsItemEmbellished(itemLink)
    if not itemLink then return false end

    -- Primary check: bonus ID 8836 is the "Embellishment (2 Maximum)" restriction
    -- marker embedded in crafted item links across Dragonflight, TWW, and Midnight.
    -- Checking the raw link is locale-independent; the tooltip text approach below
    -- only matches English clients and misses every other WoW client language.
    if itemLink:find(":8836[:|]") then return true end

    -- Fallback: tooltip text scan for English clients and forward compatibility
    -- in case the bonus ID ever changes in a future patch.
    if not (API.TooltipInfo and API.TooltipInfo.GetHyperlink) then
        return false
    end

    local data = API.TooltipInfo.GetHyperlink(itemLink)
    if not (data and data.lines) then return false end

    for _, line in ipairs(data.lines) do
        local leftText = line and line.leftText
        local rightText = line and line.rightText
        if leftText and tostring(leftText):lower():find("embellish", 1, true) then
            return true
        end
        if rightText and tostring(rightText):lower():find("embellish", 1, true) then
            return true
        end
    end

    return false
end

-- C_ChallengeMode.GetDungeonScoreRarityColor(dungeonScore) returns a
-- ColorMixin (a table exposing plain .r/.g/.b fields) for the same rarity
-- color Blizzard's own Mythic+ Rating UI uses for that score value. It's a
-- pure function of the score number, not of "my own" live state, so it's
-- safe to call here for any character's score, including a breakdown entry
-- for a dungeon the snapshotted character hasn't run. Returns nil (render
-- side falls back to the theme's default text color) if the API is missing
-- or returns something unexpected.
local function CaptureDungeonScoreColor(API, score)
    if not (API.ChallengeMode and type(API.ChallengeMode.GetDungeonScoreRarityColor) == "function") then
        return nil
    end
    local ok, color = pcall(API.ChallengeMode.GetDungeonScoreRarityColor, score)
    if ok and type(color) == "table" and type(color.r) == "number" then
        return { color.r, color.g, color.b }
    end
    return nil
end

local function WipeArray(t)
    if type(t) ~= "table" then return {} end
    for i = #t, 1, -1 do
        t[i] = nil
    end
    return t
end

local function WipeTable(t)
    if type(t) ~= "table" then return {} end
    for key in pairs(t) do
        t[key] = nil
    end
    return t
end

local _checkedTiers = {}

local ITEM_REDUNDANCY_SLOT_IDS = {
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
}

local TRACK_NAME_TO_TIER = {
    adventurer = 1,
    explorer = 1,
    veteran = 2,
    champion = 3,
    hero = 4,
    myth = 5,
    mythic = 5,
}

local function NormalizeTrackName(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    value = value:match("^%s*(.-)%s*$")
    if value == "" then return nil end
    return value:lower():match("^(%S+)")
end

local function GetTierFromTrackString(trackString)
    local key = NormalizeTrackName(trackString)
    if not key then return nil end

    local direct = TRACK_NAME_TO_TIER[key]
    if direct then return direct end

    if Addon.IlvlUtils and Addon.IlvlUtils.GetCrestTrackName then
        for tierIdx = 1, 5 do
            local name = NormalizeTrackName(Addon.IlvlUtils.GetCrestTrackName(tierIdx))
            if name and name == key then return tierIdx end
        end
    end

    return nil
end

local function ParseUpgradeTrackLine(text)
    if type(text) ~= "string" then return nil end

    local cleaned = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    cleaned = cleaned:match("^%s*(.-)%s*$")
    if cleaned == "" then return nil end

    local track, rank, maxRank = cleaned:match("^(%S+)%s+(%d+)%s*/%s*(%d+)")
    if not track then
        track, rank, maxRank = cleaned:match("^(%S+)%s+%((%d+)%s*/%s*(%d+)%)")
    end
    if not track then
        for trackName in pairs(TRACK_NAME_TO_TIER) do
            local patternName = trackName:gsub("^%l", string.upper)
            rank, maxRank = cleaned:match(patternName .. "%s+(%d+)%s*/%s*(%d+)")
            if rank and maxRank then
                track = patternName
                break
            end
            rank, maxRank = cleaned:match(patternName .. "%s+%((%d+)%s*/%s*(%d+)%)")
            if rank and maxRank then
                track = patternName
                break
            end
        end
    end
    if not track then return nil end

    local tierIdx = GetTierFromTrackString(track)
    rank = tonumber(rank)
    maxRank = tonumber(maxRank)
    if not (tierIdx and rank and maxRank) then return nil end
    if rank <= 0 or maxRank <= 0 then return nil end

    return tierIdx, rank, maxRank, track
end

local function GetTooltipUpgradeTrackInfo(itemLink)
    if not (itemLink and API.TooltipInfo and API.TooltipInfo.GetHyperlink) then return nil end

    local data = API.TooltipInfo.GetHyperlink(itemLink)
    if not (data and type(data.lines) == "table") then return nil end

    for _, line in ipairs(data.lines) do
        local tierIdx, rank, maxRank, track = ParseUpgradeTrackLine(line and line.leftText)
        if tierIdx then return tierIdx, rank, maxRank, track end
        tierIdx, rank, maxRank, track = ParseUpgradeTrackLine(line and line.rightText)
        if tierIdx then return tierIdx, rank, maxRank, track end
    end

    return nil
end

local function GetItemUpgradeTrackInfo(itemLink)
    if not itemLink then return nil end

    if not (API.Item and API.Item.GetItemUpgradeInfo) then
        return GetTooltipUpgradeTrackInfo(itemLink)
    end

    local ok, upgradeInfo = pcall(API.Item.GetItemUpgradeInfo, itemLink)
    if not (ok and type(upgradeInfo) == "table") then
        return GetTooltipUpgradeTrackInfo(itemLink)
    end

    local tierIdx = GetTierFromTrackString(upgradeInfo.trackString)
    local rank = tonumber(upgradeInfo.currentLevel)
    local maxRank = tonumber(upgradeInfo.maxLevel)
    if not (tierIdx and rank and maxRank) then
        return GetTooltipUpgradeTrackInfo(itemLink)
    end
    if rank <= 0 or maxRank <= 0 then return nil end

    return tierIdx, rank, maxRank, upgradeInfo.trackString
end

local function CopyTableFields(dst, src)
    if type(dst) ~= "table" then dst = {} end
    for k in pairs(dst) do
        dst[k] = nil
    end
    if type(src) == "table" then
        for k, v in pairs(src) do
            dst[k] = v
        end
    end
    return dst
end

local function GetSlotWatermarkScore(slotData)
    if type(slotData) ~= "table" then
        return 0, 0, 0, 0, 0
    end

    local ilvl = tonumber(slotData.ilvl) or 0
    local tierIdx = tonumber(slotData.tierIdx) or 0
    local rank = tonumber(slotData.rank) or 0
    local trueMaxRank = tonumber(slotData.trueMaxRank) or 0
    local maxRank = tonumber(slotData.maxRank) or 0
    return ilvl, tierIdx, rank, trueMaxRank, maxRank
end

local function HasSlotStateChanged(current, previous)
    if type(current) ~= "table" or type(previous) ~= "table" then return false end
    if (current.link or "") ~= (previous.link or "") then return true end
    if (current.isEmbellished and true or false) ~= (previous.isEmbellished and true or false) then return true end
    if current.upgradeCostRemaining ~= nil
            and tonumber(current.upgradeCostRemaining) ~= tonumber(previous.upgradeCostRemaining) then
        return true
    end
    if previous.upgradeInfoUnavailable and not current.upgradeInfoUnavailable then return true end
    return false
end

local function ShouldReplaceWatermarkSlot(current, previous)
    if type(current) ~= "table" then return false end
    if type(previous) ~= "table" then return true end

    local ci, ct, cr, ctm, cm = GetSlotWatermarkScore(current)
    local pi, pt, pr, ptm, pm = GetSlotWatermarkScore(previous)
    if ci ~= pi then return ci > pi end
    if ct ~= pt then return ct > pt end
    if cr ~= pr then return cr > pr end
    if ctm ~= ptm then return ctm > ptm end
    if cm ~= pm then return cm > pm end
    if HasSlotStateChanged(current, previous) then return true end
    if current.link and not previous.link then return true end
    return false
end

function Addon:GetTrackingSeasonKey()
    local tracking = self.TRACKING or {}
    local seasonNumber = tonumber(tracking._activeSeasonNumber)
    if seasonNumber then
        return "mplus:" .. tostring(seasonNumber)
    end

    local startsAt = tonumber(tracking._activeSeasonStartsAt)
    if startsAt then
        return "start:" .. tostring(startsAt)
    end

    local name = tracking._activeSeasonName
    if type(name) == "string" and name ~= "" then
        return "name:" .. name
    end

    return nil
end

function Addon:IsTrackingSnapshotCurrentSeason(snap)
    if type(snap) ~= "table" then return false end

    local currentKey = self.GetTrackingSeasonKey and self:GetTrackingSeasonKey() or nil
    if not currentKey then return true end

    if snap.seasonKey ~= nil then
        return snap.seasonKey == currentKey
    end

    local tracking = self.TRACKING or {}
    local activeCrests = tracking.crestCurrencyIDs
    local rows = snap.rightRows
    if type(activeCrests) ~= "table" or type(rows) ~= "table" then return false end

    local activeByID = {}
    for i = 1, #activeCrests do
        local id = tonumber(activeCrests[i])
        if id and id > 0 then activeByID[id] = true end
    end

    local sawCrest = false
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" and row.type == "crest" then
            local id = tonumber(row.id)
            if id and id > 0 then
                sawCrest = true
                if not activeByID[id] then
                    return false
                end
            end
        end
    end

    return sawCrest
end

function Addon:BuildTrackingSnapshot(snap, dirtyDomains)
    local tracking = Addon.TRACKING or {}
    local refreshVault, refreshGear, refreshCurrency = Addon.CoreLogic.GetSnapshotRefreshPlan(dirtyDomains)
    snap.seasonKey = Addon.GetTrackingSeasonKey and Addon:GetTrackingSeasonKey() or nil
    snap.seasonName = tracking._activeSeasonName
    snap.seasonNumber = tracking._activeSeasonNumber
    snap.seasonStartsAt = tracking._activeSeasonStartsAt

    if refreshVault then
    -- Left column: Great Vault via the GreatVault module API.
    local gridBlocks, gvLines = Addon:GetGVData()

    snap.leftLines = snap.leftLines or {}
    for i = 1, 9 do snap.leftLines[i] = (gvLines and gvLines[i]) or "" end

    if gridBlocks then
        snap.leftGrid = snap.leftGrid or {{},{},{}}
        for bi = 1, 3 do
            local src = gridBlocks[bi]
            local dst = snap.leftGrid[bi]
            if src and dst then
                dst.available = src.available
                dst.complete  = src.complete
                dst.maxIlvl   = src.maxIlvl
                dst.slots     = dst.slots or {{},{},{}}
                for si = 1, 3 do
                    if src.slots and src.slots[si] and dst.slots[si] then
                        dst.slots[si].thresh = src.slots[si].thresh
                        dst.slots[si].ilvl   = src.slots[si].ilvl
                    end
                end
            end
        end
    end

    -- Keystone: current M+ key held by the logged-in character.
    do
        local ksLevel = API.MythicPlus
                        and type(API.MythicPlus.GetOwnedKeystoneLevel) == "function"
                        and API.MythicPlus.GetOwnedKeystoneLevel() or nil
        local ksMapID = API.MythicPlus
                        and type(API.MythicPlus.GetOwnedKeystoneChallengeMapID) == "function"
                        and API.MythicPlus.GetOwnedKeystoneChallengeMapID() or nil
        local ksName
        if ksMapID and API.ChallengeMode and type(API.ChallengeMode.GetMapUIInfo) == "function" then
            ksName = API.ChallengeMode.GetMapUIInfo(ksMapID)
        end
        snap.keystone = snap.keystone or {}
        snap.keystone.level = tonumber(ksLevel) or 0
        snap.keystone.name  = ksName or ""

        -- Weekly/season run counts: number of Mythic+ dungeons run since the
        -- weekly reset, and since the season started. C_MythicPlus.GetRunHistory's
        -- real signature is (includePreviousWeeks, includeIncompleteRuns,
        -- currentSeasonOnly) -- there is no "thisSeason" field on each entry,
        -- only "thisWeek". So: ask for every week this season (includePreviousWeeks),
        -- including abandoned/depleted attempts (includeIncompleteRuns = true --
        -- matches how other addons (BigWigs, ExwindTools, atrocityEssentials)
        -- count "runs this week", so this number lines up with what players see
        -- elsewhere), scoped to the current season (currentSeasonOnly). The
        -- season total is then just the number of runs returned; the weekly
        -- total is the subset flagged thisWeek.
        local weeklyRuns, seasonRuns = 0, 0
        if API.MythicPlus and type(API.MythicPlus.GetRunHistory) == "function" then
            local ok, runs = pcall(API.MythicPlus.GetRunHistory, true, true, true)
            if ok and type(runs) == "table" then
                for i = 1, #runs do
                    local run = runs[i]
                    if run then
                        seasonRuns = seasonRuns + 1
                        if run.thisWeek then
                            weeklyRuns = weeklyRuns + 1
                        end
                    end
                end
            end
        end
        snap.keystone.weeklyRuns = weeklyRuns
        snap.keystone.seasonRuns = seasonRuns

        -- Overall Mythic+ Rating ("IO score"), Blizzard's own rarity color for
        -- that score, and a per-dungeon breakdown (name, best level this
        -- season, and that dungeon's own score/color) for the Alt Summary
        -- tooltip. All three come from C_ChallengeMode and were verified
        -- against warcraft.wiki.gg -- GetMapScoreInfo() takes no arguments
        -- and already returns every dungeon in the current season's pool.
        local ioScore = 0
        if API.ChallengeMode and type(API.ChallengeMode.GetOverallDungeonScore) == "function" then
            local ok, score = pcall(API.ChallengeMode.GetOverallDungeonScore)
            if ok and type(score) == "number" then
                ioScore = score
            end
        end
        snap.keystone.ioScore = ioScore
        snap.keystone.ioColor = CaptureDungeonScoreColor(API, ioScore)

        local ioBreakdown = {}
        if API.ChallengeMode and type(API.ChallengeMode.GetMapScoreInfo) == "function" then
            local ok, scores = pcall(API.ChallengeMode.GetMapScoreInfo)
            if ok and type(scores) == "table" then
                for i = 1, #scores do
                    local entry = scores[i]
                    if entry and entry.mapChallengeModeID then
                        local name
                        if type(API.ChallengeMode.GetMapUIInfo) == "function" then
                            name = API.ChallengeMode.GetMapUIInfo(entry.mapChallengeModeID)
                        end
                        local entryScore = tonumber(entry.dungeonScore) or 0
                        ioBreakdown[#ioBreakdown + 1] = {
                            name  = name or "",
                            level = tonumber(entry.level) or 0,
                            score = entryScore,
                            color = CaptureDungeonScoreColor(API, entryScore),
                        }
                    end
                end
            end
        end
        snap.keystone.ioBreakdown = ioBreakdown
    end
    end

    if refreshGear then
    snap.itemUpgradeWatermarks = WipeTable(snap.itemUpgradeWatermarks)
    snap.itemUpgradeWatermarksCaptured = false
    if API.ItemUpgrade and type(API.ItemUpgrade.GetHighWatermarkForSlot) == "function" then
        local capturedCount = 0
        for _, redundancySlot in ipairs(ITEM_REDUNDANCY_SLOT_IDS) do
            local ok, watermark = pcall(API.ItemUpgrade.GetHighWatermarkForSlot, redundancySlot)
            watermark = ok and tonumber(watermark) or nil
            if watermark then
                snap.itemUpgradeWatermarks[redundancySlot] = watermark
                capturedCount = capturedCount + 1
            end
        end
        snap.itemUpgradeWatermarksCaptured = capturedCount == #ITEM_REDUNDANCY_SLOT_IDS
    end

    -- Equipment slots: full item data for the gear popup and upgrade-cost rows.
    -- tier and rank are derived from the equipped item's ilvl using IlvlUtils.
    local previousBestGearSlots = type(snap.bestGearSlots) == "table" and snap.bestGearSlots or nil
    local previousGearSlots = type(snap.gearSlots) == "table" and snap.gearSlots or nil
    if not previousBestGearSlots then
        previousBestGearSlots = previousGearSlots
    end
    snap.gearSlots = snap.gearSlots or {}
    local gearSlots = snap.gearSlots
    local snapSlotIDs = (Addon.TRACKING and Addon.TRACKING.gearSlotIDs)
                        or {1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17}
    local maxRankCount = Addon.TRACKING and Addon.TRACKING.ilvlRankOffsets
                         and #Addon.TRACKING.ilvlRankOffsets or 6
    for _, sid in ipairs(snapSlotIDs) do
        local link = API.GetInventoryItemLink and API.GetInventoryItemLink("player", sid)
        -- API.GetDetailedItemLevelInfo parses upgrade bonus IDs from the link directly;
        -- it is more reliable than API.GetInventoryItemLevel for upgraded items.
        local ilvl = 0
        if link and API.GetDetailedItemLevelInfo then
            local effIlvl = API.GetDetailedItemLevelInfo(link)
            ilvl = tonumber(effIlvl) or 0
        end
        -- Only fall back to API.GetInventoryItemLevel when we have a real item link.
        -- Without this guard, API.GetInventoryItemLevel("player", 17) echoes the 2H
        -- weapon ilvl for an empty off-hand slot, causing double upgrade cost.
        if ilvl == 0 and link then
            local rawIlvl = API.GetInventoryItemLevel and API.GetInventoryItemLevel("player", sid)
            ilvl = tonumber(rawIlvl) or 0
        end
        local itemUpgradeHighWatermark = 0
        if link and API.ItemUpgrade and type(API.ItemUpgrade.GetHighWatermarkForItem) == "function" then
            local ok, characterHighWatermark, accountHighWatermark =
                pcall(API.ItemUpgrade.GetHighWatermarkForItem, link)
            if ok then
                itemUpgradeHighWatermark = math.max(tonumber(characterHighWatermark) or 0,
                                                    tonumber(accountHighWatermark) or 0)
            end
        end

        local tierIdx, rank, maxRank, upgradeTrackString
        local trackTierConfirmed = false
        local trackTierIdx, trackRank, trackMaxRank, trackName = GetItemUpgradeTrackInfo(link)
        if trackTierIdx and trackRank and trackMaxRank then
            tierIdx = trackTierIdx
            rank = trackRank
            maxRank = trackMaxRank
            upgradeTrackString = trackName
            trackTierConfirmed = true
        end

        if ilvl > 0 and Addon.IlvlUtils then
            local ilvlTierIdx = Addon.IlvlUtils.GetTier(ilvl)
            if not tierIdx then
                tierIdx = ilvlTierIdx
            end
            if not rank and tierIdx then
                rank = Addon.IlvlUtils.GetRank(ilvl, tierIdx)
            end
            if not maxRank and tierIdx then
                maxRank = maxRankCount
            end
        end

        local slotData = gearSlots[sid]
        if not slotData then
            slotData = {}
            gearSlots[sid] = slotData
        end
        slotData.link = link
        slotData.ilvl = ilvl
        slotData.itemUpgradeHighWatermark = itemUpgradeHighWatermark
        slotData.rank = rank
        slotData.maxRank = maxRank
        slotData.tierIdx = tierIdx
        slotData.upgradeTrackString = upgradeTrackString
        slotData.trackTierConfirmed = trackTierConfirmed or nil
        slotData.isEmbellished = IsItemEmbellished(link) or nil
        slotData.trueMaxRank = nil
        slotData.upgradeInfoUnavailable = nil
        slotData.upgradeCostRemaining = nil
    end
    for sid in pairs(gearSlots) do
        local keep = false
        for _, wantedSid in ipairs(snapSlotIDs) do
            if wantedSid == sid then
                keep = true
                break
            end
        end
        if not keep then
            gearSlots[sid] = nil
        end
    end

    -- Weapon slot comparison: prefer 2H (slot 16 only) over dual-wield (slots 16+17)
    -- when the 2H ilvl is >= the off-hand ilvl, OR when slot 17 has no real item.
    -- The link-gated fallback above already keeps slot 17 at ilvl=0 for 2H users;
    -- this block is a safety net in case any stray ilvl bled through.
    do
        local ws16 = gearSlots[16]
        local ws17 = gearSlots[17]
        if ws16 and ws17 then
            local ilvl16 = ws16.ilvl or 0
            local ilvl17 = ws17.ilvl or 0
            -- If 2H is highest (slot 17 has no real link but echoed an ilvl), clear it.
            if ilvl16 > 0 and ilvl16 >= ilvl17 and not ws17.link then
                local cleared = gearSlots[17] or {}
                gearSlots[17] = cleared
                cleared.link = nil
                cleared.ilvl = 0
                cleared.rank = nil
                cleared.maxRank = nil
                cleared.tierIdx = nil
                cleared.upgradeTrackString = nil
                cleared.trackTierConfirmed = nil
                cleared.isEmbellished = nil
                cleared.trueMaxRank = nil
                cleared.upgradeInfoUnavailable = nil
                cleared.upgradeCostRemaining = nil
            end
        end
    end

    -- Auto-detect per-tier upgrade cost and true max rank via API.ItemUpgrade.
    -- WoW only returns reliable upgrade details in some contexts, so missing or
    -- empty API data must not mark an item as capped.  When details are missing,
    -- Alt Summary falls back to rank math and default crest costs.
    snap.upgradeCostPerStep = WipeArray(snap.upgradeCostPerStep)
    snap.upgradeDetailsAvailable = false
    if API.ItemUpgrade and API.ItemUpgrade.SetItemUpgradeFromLocation
            and API.ItemUpgrade.GetItemUpgradeItemInfo and API.ItemLocation then
        local TRACKING = Addon.TRACKING
        local crestIDs = TRACKING and TRACKING.crestCurrencyIDs
        local checkedTiers = WipeArray(_checkedTiers)
        for _, sid in ipairs(snapSlotIDs) do
            local gs = gearSlots[sid]
            if gs and gs.link and gs.tierIdx and gs.rank and gs.maxRank then
                local tierIdx = gs.tierIdx
                local crestID = crestIDs and crestIDs[tierIdx]
                local upgradeReadOK = pcall(function()
                    API.ItemUpgrade.SetItemUpgradeFromLocation(
                        API.ItemLocation:CreateFromEquipmentSlot(sid))
                    local info = API.ItemUpgrade.GetItemUpgradeItemInfo()
                    if info and type(info.upgradeLevelInfos) == "table" then
                        snap.upgradeDetailsAvailable = true
                        -- Read the next upgrade step once; reused for tier correction,
                        -- embellished detection, and cost capture below.
                        -- NOTE: #upgradeLevelInfos is REMAINING levels from current rank,
                        -- not an absolute index.  The nextLevel index may be out of range
                        -- if currUpgrade counts from the track start; the [1] fallback
                        -- always gives us the next remaining upgrade.
                        local currentUpgrade = tonumber(info.currUpgrade) or 0
                        local maxUpgrade = tonumber(info.maxUpgrade) or 0
                        local nextLevel = currentUpgrade + 1
                        local levelInfo = info.upgradeLevelInfos[nextLevel]
                                      or info.upgradeLevelInfos[1]
                        local costs = levelInfo and levelInfo.currencyCostsToUpgrade
                        local remainingCrestCost, sawRemainingCrestCost = 0, false

                        -- Correct tier BEFORE computing trueMaxRank.
                        -- Items at rank 5/6 of tier N share ilvl values with rank 1/2
                        -- of tier N+1, so GetTier() can assign the wrong tier.  A
                        -- Champion rank-5 item (ilvl 259) appears as Hero rank-1 and
                        -- would be falsely flagged embellished (trueMaxRank = 1+1 = 2 < 6)
                        -- without this correction.  The upgrade currency resolves the
                        -- ambiguity definitively.
                        if costs and crestIDs and not gs.trackTierConfirmed then
                            local actualTierIdx = Addon:GetCrestTierFromCosts(costs)
                            if actualTierIdx and actualTierIdx ~= tierIdx then
                                local newRank = Addon.IlvlUtils
                                    and Addon.IlvlUtils.GetRank(gs.ilvl, actualTierIdx)
                                if newRank then
                                    gearSlots[sid].tierIdx = actualTierIdx
                                    gearSlots[sid].rank    = newRank
                                    gs.tierIdx = actualTierIdx
                                    gs.rank    = newRank
                                    tierIdx    = actualTierIdx
                                    crestID    = crestIDs[actualTierIdx]
                                end
                            end
                        end

                        -- Detect embellished/crafted caps using the now-corrected rank.
                        -- Empty upgradeLevelInfos is not enough proof of a cap; WoW can
                        -- return that when upgrade details are temporarily unavailable.
                        local nLevels     = #info.upgradeLevelInfos
                        if info.itemUpgradeable == false then
                            gearSlots[sid].trueMaxRank = gs.rank
                            gearSlots[sid].upgradeCostRemaining = 0
                            return
                        end

                        local trueMaxRank = (nLevels > 0) and (gs.rank + nLevels) or nil
                        if trueMaxRank and trueMaxRank < gs.maxRank then
                            gearSlots[sid].trueMaxRank = trueMaxRank
                        end
                        -- Void-upgraded / otherwise capped items can share ilvls with the
                        -- first ranks of the next crest track. When WoW reports the item
                        -- is already at its upgrade cap, trust that over ilvl-derived
                        -- track math so the item does not appear crest-upgradeable.
                        if maxUpgrade > 0 and currentUpgrade > 0 and currentUpgrade >= maxUpgrade and nLevels == 0 then
                            gearSlots[sid].trueMaxRank = gs.rank
                            gearSlots[sid].upgradeCostRemaining = 0
                        end

                        if crestID and nLevels > 0 then
                            -- Sum the exact remaining crest cost reported by WoW for
                            -- this slot. This captures crest discounts per item/tier,
                            -- including fully discounted steps where no crest is due.
                            for _, upgradeInfo in ipairs(info.upgradeLevelInfos) do
                                local stepCosts = upgradeInfo and upgradeInfo.currencyCostsToUpgrade
                                local stepHasCrest = false
                                if stepCosts then
                                    for _, ce in ipairs(stepCosts) do
                                        if ce.currencyID == crestID then
                                            stepHasCrest = true
                                            sawRemainingCrestCost = true
                                            remainingCrestCost = remainingCrestCost + (tonumber(ce.cost) or 0)
                                            break
                                        end
                                    end
                                end
                                -- If WoW gives remaining upgrade levels but omits the
                                -- crest currency on a step, treat that step as discounted
                                -- to zero crests rather than capping the item.
                                if not stepHasCrest then sawRemainingCrestCost = true end
                            end
                        end
                        if sawRemainingCrestCost then
                            gearSlots[sid].upgradeCostRemaining = remainingCrestCost
                        end

                        -- Capture per-tier cost from the first upgradable slot found.
                        if crestID and not checkedTiers[tierIdx]
                                and gearSlots[sid].rank < gearSlots[sid].maxRank then
                            if levelInfo and levelInfo.currencyCostsToUpgrade then
                                for _, ce in ipairs(levelInfo.currencyCostsToUpgrade) do
                                    if ce.currencyID == crestID then
                                        snap.upgradeCostPerStep[tierIdx] = ce.cost
                                        checkedTiers[tierIdx] = true
                                        break
                                    end
                                end
                            end
                        end
                    else
                        -- No reliable item-upgrade details for this slot. Leave
                        -- trueMaxRank unset so display code uses the normal tier cap.
                        gearSlots[sid].upgradeInfoUnavailable = true
                    end
                end)
                if not upgradeReadOK then
                    gearSlots[sid].upgradeInfoUnavailable = true
                end
            end
        end
        if API.ItemUpgrade.ClearItemUpgrade then API.ItemUpgrade.ClearItemUpgrade() end
    end

    snap.bestGearSlots = snap.bestGearSlots or {}
    local bestGearSlots = snap.bestGearSlots
    for _, sid in ipairs(snapSlotIDs) do
        local currentSlot = gearSlots[sid]
        local previousSlot = previousBestGearSlots and previousBestGearSlots[sid]
        local sourceSlot = ShouldReplaceWatermarkSlot(currentSlot, previousSlot) and currentSlot
            or previousSlot or currentSlot
        if sourceSlot ~= bestGearSlots[sid] then
            bestGearSlots[sid] = CopyTableFields(bestGearSlots[sid], sourceSlot)
        end
    end
    for sid in pairs(bestGearSlots) do
        local keep = false
        for _, wantedSid in ipairs(snapSlotIDs) do
            if wantedSid == sid then
                keep = true
                break
            end
        end
        if not keep then
            bestGearSlots[sid] = nil
        end
    end
    end

    -- Right-column rows can depend on the gear watermark, so save them last.
    -- Be defensive here: snapshot capture can be requested during partial init,
    -- and we never want a missing currency hook to break the whole addon.
    if refreshCurrency and type(Addon.FillCurrencySnapshot) == "function" then
        Addon:FillCurrencySnapshot(snap)
    elseif refreshCurrency then
        snap.rightRows = snap.rightRows or {}
        for i = #snap.rightRows, 1, -1 do
            snap.rightRows[i] = nil
        end
    end
end
