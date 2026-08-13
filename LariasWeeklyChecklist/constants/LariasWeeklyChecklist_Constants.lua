-- Constants for Larias' Weekly Checklist.
--
-- This file is the single source of truth for tracking IDs.
-- Edit values here as you discover new IDs; the addon reads them during startup.
--
-- The addon looks for:  _G["<addonName>_CONSTANTS"]
--
-- Notes:
-- - Use 0 for "unknown / disabled" IDs.
-- - Array-like tables (e.g. crestCurrencyIDs lists) are replaced as a whole.

local addonName = ...
local constantsKey = tostring(addonName or "") .. "_CONSTANTS"

-- Active season data: update these every new season.
local tracking = {
    supportLinks = {
        doc       = "https://lariasguide.com",
        checklist = "https://lariasguide.com/checklist",
        discord   = "https://discord.gg/postnerfclarity",
    },
    -- NPCs that should show the crest conversion side panel.
    crestExchangeNpcIDs = {
        239676, -- Vaskarn <Crest Exchange>, Silvermoon City (Midnight)
        219226, -- Vaskarn <Undermine Crest Exchange>, Dornogal
        216449, -- Vaskarn <Awakened Crest Exchange>
        203404, -- Vaskarn <Shadowflame Crest Exchange>
    },
    _activeSeasonName = "Season 2",
    _activeSeasonNumber = 2,
    crestCurrencyIDs = { 3442, 3443, 3444, 3445, 3446 },
    crestConvertItemIDs = { 269867, 26986, 269865, 269866 },
    crestAchievementIDs = { [2] = 62411, [3] = 62412, [4] = 62414, [5] = 62416 },
    crestTradeupAchievementIDs = { 62410, 62411, 62412, 62414, 62416 },
    sparkCurrencyID = 3509,
    sparkItemID = 274476,
    catalystCurrencyID = 3465,
    cofferKeysCurrencyID = 0,
    cofferKeysDisplayCurrencyID = 0,
    bonusRollCurrencyID = 3418,
    ilvlBase = 266,
    ilvlTrackStep = 13,
    ilvlRankOffsets = { 0, 3, 6, 10, 13, 16 },
    ilvlMythExtraLevels = { 337, 341, 344 },
    crestTradeBatch = { 30, 10 },
    crestUpgradeCostPerStep = 20,
    crestUpgradeCostReduced = 10,
    ilvlRefTables = {
                    -- tracks row schema:
                    -- { tier = <1-5>, rank = <1-9>, ilvl = <number> }
                    -- Overlap is auto-inferred when ilvl also exists on the next tier (e.g. T1 R6 == T2 R1).
                    tracks = {
                        { "ILVLREF_COL_ILVL", "ILVLREF_COL_TRACK", "ILVLREF_COL_CREST_NEEDED" },
                        { tier = 1, rank = 1, ilvl = 266 }, { tier = 1, rank = 2, ilvl = 269 },
                        { tier = 1, rank = 3, ilvl = 272 }, { tier = 1, rank = 4, ilvl = 276 },
                        { tier = 1, rank = 5, ilvl = 279 }, { tier = 1, rank = 6, ilvl = 282 },
                        { tier = 2, rank = 3, ilvl = 285 }, { tier = 2, rank = 4, ilvl = 289 },
                        { tier = 2, rank = 5, ilvl = 292 }, { tier = 2, rank = 6, ilvl = 295 },
                        { tier = 3, rank = 3, ilvl = 298 }, { tier = 3, rank = 4, ilvl = 302 },
                        { tier = 3, rank = 5, ilvl = 305 }, { tier = 3, rank = 6, ilvl = 308 },
                        { tier = 4, rank = 3, ilvl = 311 }, { tier = 4, rank = 4, ilvl = 315 },
                        { tier = 4, rank = 5, ilvl = 318 }, { tier = 4, rank = 6, ilvl = 321 },
                        { tier = 5, rank = 3, ilvl = 324 }, { tier = 5, rank = 4, ilvl = 328 },
                        { tier = 5, rank = 5, ilvl = 331 }, { tier = 5, rank = 6, ilvl = 334 },
                        { tier = 5, rank = 7, ilvl = 337 },
                        { tier = 5, rank = 8, ilvl = 341 },
                        { tier = 5, rank = 9, ilvl = 344 },
                    },
                    -- crafted row schema: { quality, crest1Ilvl, crest2Ilvl, crest3Ilvl, crest4Ilvl, crest5Ilvl }
                    crafted = {
                        { "ILVLREF_COL_QUALITY", "CREST_1", "CREST_2", "CREST_3", "CREST_4", "CREST_5" },
                        { 1, 266, 279, 292, 305, 318 },
                        { 2, 269, 282, 295, 308, 321 },
                        { 3, 272, 285, 298, 311, 324 },
                        { 4, 276, 289, 302, 315, 328 },
                        { 5, 279, 292, 305, 318, 331 },
                    },
                    -- dungeons row schema: { sourceLabel, endLootIlvl, greatVaultIlvl }
                    dungeons = {
                        { "ILVLREF_COL_SOURCE", "ILVLREF_COL_END_LOOT", "ILVLREF_COL_GREAT_VAULT" },
                        { "ILVLREF_DUNGEON_HEROIC", 276, "-" },
                        { "ILVLREF_DUNGEON_MYTHIC", 292, 298 },
                        { "M2",  295, 305 },
                        { "M3",  295, 305 },
                        { "M4",  298, 308 },
                        { "M5",  302, 308 },
                        { "M6",  305, 311 },
                        { "M7",  305, 315 },
                        { "M8",  308, 315 },
                        { "M9",  308, 315 },
                        { "M10", 311, 318 },
                        { "M11", 311, 318 },
                        { "M12", 311, 318 },
                    },
                    -- raid row schema: { difficultyLabel, boss1Ilvl, boss2Ilvl, boss3Ilvl, boss4Ilvl }
                    raid = {
                        { "ILVLREF_COL_DIFFICULTY", "Boss 1", "Bosses 2/3", "Bosses 4/5/6", "Bosses 7/8" },
                        { "ILVLREF_RAID_LFR",    279, 282, 285, 289 },
                        { "ILVLREF_RAID_NORMAL", 292, 295, 298, 302 },
                        { "ILVLREF_RAID_HEROIC", 305, 308, 311, 315 },
                        { "ILVLREF_RAID_MYTHIC", 318, 321, 324, 344 },
                    },
                    -- delves row schema: { delveTierNumber, endLootIlvl, mapDropIlvlOrDash, greatVaultIlvl }
                    delves = {
                        { "ILVLREF_COL_TIER", "ILVLREF_COL_END_LOOT", "ILVLREF_COL_MAP_DROP", "ILVLREF_COL_GREAT_VAULT" },
                        { 1,  266, "-", 279 },
                        { 2,  269, "-", 282 },
                        { 3,  272, "-", 285 },
                        { 4,  276, 282, 289 },
                        { 5,  279, 289, 292 },
                        { 6,  282, 292, 298 },
                        { 7,  292, 295, 302 },
                        { 8,  295, 305, 305 },
                        { 9,  295, 305, 305 },
                        { 10, 295, 305, 305 },
                        { 11, 295, 305, 305 },
                    },
    },
    -- questIDs = {
    --     delversBounty = 0,
    --     weeklyPrey = 0,
    --     delveBoss = 0,
    -- },
    questItemIDs = {
        delversBounty = 0,
        weeklyPrey = 0,
        delveBoss = 0,
    },
    weaponUpgrade = {
        shardItemID = 0,
        combinedItemID = 0,
        maxItemLevel = 0,
        shardsPerCombined = 0,
        slotIDs = {},
    },
    currencyQualityOverrides = {},
    itemQualityOverrides = {},
    -- Equipment slot IDs captured for the gear popup and upgrade-cost rows.
    -- Slot 4 (shirt) and ranged/ammo slots are intentionally excluded.
    gearSlotIDs = {1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17},

    -- Crest tier display colors as 6-digit hex RGB (index-matched to crest tier order).
    -- Used by the ilvl reference window to color each tier's rows.
    crestColors = {
        "1EFF00",  -- Adventurer  (green)
        "0070DD",  -- Veteran     (blue)
        "A335EE",  -- Champion    (purple)
        "FF8000",  -- Hero        (orange)
        "FFD100",  -- Myth/Gilded (gold)
    },
    -- Atlas names for the crafting quality tier icons (Tier1 = lowest, Tier5 = highest).
    -- IlvlRef wraps these in |A:name:14:14|a when rendering the crafted ilvl table.
    craftingQualityIcons = {
        "Professions-Icon-Quality-Tier1",
        "Professions-Icon-Quality-Tier2",
        "Professions-Icon-Quality-Tier3",
        "Professions-Icon-Quality-Tier4",
        "Professions-Icon-Quality-Tier5",
    },
    -- Master switches for optional UI features.  Set a flag to false to
    -- completely disable that feature (no button, no gear-popup checkbox).
    featureFlags = {
    },
}

_G[constantsKey] = tracking
