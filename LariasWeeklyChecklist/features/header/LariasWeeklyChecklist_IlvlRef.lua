-- IlvlRef module: standalone popup window with Midnight Season 1 item-level reference tables.
-- Opened/closed via the "Item Levels" button in the main frame.

local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local CreateFrame = CreateFrame
local max = math.max

local WIN_W    = 620   -- popup window width
local WIN_H    = 540   -- popup window height
local PAD      = 14    -- outer content padding
local ROW_H    = 18    -- height of one data row
local SEC_GAP  = 14    -- gap between sections
local HDR_H    = 22    -- section heading height
local SUBHDR_H = 18    -- column sub-header height
local SCROLLTOP = 32   -- pixels from win top to scroll frame

local ADV   = Addon.IlvlUtils.GetEscapePrefix(1)  -- Adventurer  (green)
local VET   = Addon.IlvlUtils.GetEscapePrefix(2)  -- Veteran     (blue)
local CHAMP = Addon.IlvlUtils.GetEscapePrefix(3)  -- Champion    (purple)
local HERO  = Addon.IlvlUtils.GetEscapePrefix(4)  -- Hero        (orange)
local MYTH  = Addon.IlvlUtils.GetEscapePrefix(5)  -- Myth/Gilded (gold)
local COLOR_RESET = "|r"

local function GetIlvlRefWindowTitle(locale)
    locale = locale or {}
    local baseTitle = locale.ILVLREF_WINDOW_TITLE or "Midnight Season 1 Item Level Reference"
    local tracking = Addon.TRACKING or {}

    local seasonName = tracking._activeSeasonName
    local seasonNum = tonumber(tracking._activeSeasonNumber)
    if (type(seasonName) ~= "string" or seasonName == "") and seasonNum then
        local seasonFmt = locale.ILVLREF_SEASON_LABEL_FMT or "Season %d"
        seasonName = seasonFmt:format(seasonNum)
    end

    if type(seasonName) == "string" and seasonName ~= "" then
        local titleFmt = locale.ILVLREF_WINDOW_TITLE_FMT
        if type(titleFmt) == "string" and titleFmt ~= "" then
            return titleFmt:format(seasonName)
        end
        if not baseTitle:find(seasonName, 1, true) then
            return baseTitle .. " (" .. seasonName .. ")"
        end
    end

    return baseTitle
end

-- Create a FontString anchored at (x, posY) from parent's TOPLEFT.
-- fontObj, r/g/b/a, w, align are optional.
local function FS(parent, x, posY, text, fontObj, r, g, b, a, w, align)
    local fs = parent:CreateFontString(nil, "ARTWORK", fontObj or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, posY)
    if w     then fs:SetWidth(w) end
    if align then fs:SetJustifyH(align) end
    if r     then fs:SetTextColor(r, g, b, a or 1) end
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetText(text ~= nil and tostring(text) or "")
    return fs
end

-- Draw a 1 px horizontal rule and return the new posY.
local function HRule(parent, posY)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    local vs = Addon.VISUAL_STYLE or {}
    tex:SetColorTexture(
        Addon.THEME.border.r, Addon.THEME.border.g,
        Addon.THEME.border.b, vs.strongDividerA or (Addon.THEME.border.a * 0.6))
    tex:SetHeight(1)
    tex:SetPoint("TOPLEFT",  parent, "TOPLEFT",  0,  posY)
    tex:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0,  posY)
    return posY - 4
end

-- Draw a gold section heading and return the new posY.
local function SecHead(parent, posY, text)
    local headerColor = Addon.THEME.header
    FS(parent, 0, posY, text, "GameFontNormal", headerColor.r, headerColor.g, headerColor.b, headerColor.a)
    return posY - HDR_H
end

-- Draw a dim column-header row and return the new posY.
-- cols = array of { x, w, t, align }
local function ColHead(parent, posY, cols)
    local dimColor = Addon.THEME.textDim
    for _, col in ipairs(cols) do
        FS(parent, col.x, posY, col.t, "GameFontHighlightSmall",
           dimColor.r, dimColor.g, dimColor.b, dimColor.a, col.w, col.align)
    end
    return posY - SUBHDR_H
end

-- Draw a data row and return the new posY.
-- cols = array of { x, w, t, align, r, g, b, a }
local function DataRow(parent, posY, cols)
    for _, col in ipairs(cols) do
        FS(parent, col.x, posY, col.t, nil,
           col.r, col.g, col.b, col.a, col.w, col.align)
    end
    return posY - ROW_H
end

-- Measure visible pixel width of a string (strips WoW colour codes).
local _mfs
local function MeasureStr(text, fontObj)
    if not _mfs then
        _mfs = UIParent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        _mfs:Hide()
    end
    if fontObj then _mfs:SetFontObject(fontObj) end
    local plain = (text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    _mfs:SetText(plain)
    return _mfs:GetStringWidth()
end

-- Given cols ({t=header, [align=]}) and a rows 2-D array,
-- measures each column's max content width and fills col.w + col.x in-place.
local CELL_PAD = 10  -- 4 px left inset + right margin + buffer
local function AutoFitCols(cols, rows)
    for ci, col in ipairs(cols) do
        local maxW = MeasureStr(col.t or "", "GameFontHighlightSmall")
        for _, row in ipairs(rows) do
            local cellW = MeasureStr(row[ci] or "")
            if cellW > maxW then maxW = cellW end
        end
        col.w = math.ceil(maxW) + CELL_PAD
    end
    local colX = 0
    for _, col in ipairs(cols) do col.x = colX; colX = colX + col.w end
    return cols
end

-- Color the two halves of a "Tier A / Tier B" track name independently.
local function DualTrack(str, c1, c2)
    local leftPart, rightPart = str:match("^(.+) / (.+)$")
    if leftPart and rightPart then return c1..leftPart..COLOR_RESET.." / "..c2..rightPart..COLOR_RESET end
    return c1..str..COLOR_RESET
end

-- Draw a bordered grid table (header + data rows with column separators).
-- cols = { {x, w, t, [align]} }  (x/w are cell boundaries; t = header text)
-- rows = { {cell1, cell2, ...}, ... }
-- Returns new posY.
local GBOR = (Addon.VISUAL_STYLE and Addon.VISUAL_STYLE.trackingBorderA) or 0.55
local GLIN = (Addon.VISUAL_STYLE and Addon.VISUAL_STYLE.trackingInnerA) or 0.18
local function GridTable(parent, posY, cols, rows)
        local borderColor = Addon.THEME.border
        local dimColor    = Addon.THEME.textDim
        -- compute right edge of the table
        local rightX = 0
        for _, col in ipairs(cols) do
            local edge = (col.x or 0) + (col.w or 60)
            if edge > rightX then rightX = edge end
        end
        local nRows  = #rows
        local totalH = SUBHDR_H + ROW_H * nRows
        local startY = posY

        local function hline(y, mul)
            local tex = parent:CreateTexture(nil, "ARTWORK")
            tex:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, math.min(1, borderColor.a * mul))
            tex:SetSize(rightX, 1)
            tex:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
        end
        local function vline(vx)
            local tex = parent:CreateTexture(nil, "ARTWORK")
            tex:SetColorTexture(borderColor.r, borderColor.g, borderColor.b, math.min(1, borderColor.a * GBOR))
            tex:SetSize(1, totalH)
            tex:SetPoint("TOPLEFT", parent, "TOPLEFT", vx, startY)
        end
    hline(startY, GBOR)
    -- header cells (4 px left inset)
    for _, col in ipairs(cols) do
        FS(parent, (col.x or 0) + 4, startY - 2, col.t or "",
           "GameFontHighlightSmall", dimColor.r, dimColor.g, dimColor.b, dimColor.a, (col.w or 60) - 6, col.align)
    end
    posY = startY - SUBHDR_H
    hline(posY, GBOR)  -- strong line under header

    -- data rows
    local txt = Addon.THEME.text
    for ri, row in ipairs(rows) do
        for ci, col in ipairs(cols) do
            FS(parent, (col.x or 0) + 4, posY - 2, row[ci] or "",
               nil, txt.r, txt.g, txt.b, txt.a, (col.w or 60) - 6, col.align)
        end
        posY = posY - ROW_H
        hline(posY, ri == nRows and GBOR or GLIN)
    end

    -- vertical borders: left edge of every column + right edge of last
    for _, col in ipairs(cols) do vline(col.x or 0) end
    vline(rightX)  -- right edge

    return posY
end

local function BuildIlvlRefWindow()
    local Locale = Addon.L

    -- ilvl at rank r = ilvlBase + RANK_OFFSETS[r]
    -- Starting points and rank offsets are defined in LariasWeeklyChecklist_Constants.lua
    -- and loaded into Addon.TRACKING. The literals below are fallbacks only.
    local tracking     = Addon.TRACKING or {}
    local ilvlBase      = tracking.ilvlBase      or 220
    local ilvlTrackStep = tracking.ilvlTrackStep or 13
    local RANK_OFFSETS  = tracking.ilvlRankOffsets or { 0, 4, 7, 10, 13, 17 }
    local MYTH_EXTRA_ILVLS = (type(tracking.ilvlMythExtraLevels) == "table") and tracking.ilvlMythExtraLevels or {}

    local TIERS = {
        { id="ADV",   color=ADV,   ilvlBase=ilvlBase + ilvlTrackStep * 0,
                    trackName  = (Addon.IlvlUtils and Addon.IlvlUtils.GetCrestTrackName and Addon.IlvlUtils.GetCrestTrackName(1)) or "Adventurer",
          crest      = Locale.ILVLREF_CREST_ADV,
          crestShort = Locale.ILVLREF_CREST_ADV },
        { id="VET",   color=VET,   ilvlBase=ilvlBase + ilvlTrackStep * 1,
                    trackName  = (Addon.IlvlUtils and Addon.IlvlUtils.GetCrestTrackName and Addon.IlvlUtils.GetCrestTrackName(2)) or "Veteran",
          crest      = Locale.ILVLREF_CREST_VET,
          crestShort = Locale.ILVLREF_CREST_VET },
        { id="CHAMP", color=CHAMP, ilvlBase=ilvlBase + ilvlTrackStep * 2,
                    trackName  = (Addon.IlvlUtils and Addon.IlvlUtils.GetCrestTrackName and Addon.IlvlUtils.GetCrestTrackName(3)) or "Champion",
          crest      = Locale.ILVLREF_CREST_CHAMP,
          crestShort = Locale.ILVLREF_CREST_CHAMP },
        { id="HERO",  color=HERO,  ilvlBase=ilvlBase + ilvlTrackStep * 3,
                    trackName  = (Addon.IlvlUtils and Addon.IlvlUtils.GetCrestTrackName and Addon.IlvlUtils.GetCrestTrackName(4)) or "Hero",
          crest      = Locale.ILVLREF_CREST_HERO,
          crestShort = Locale.ILVLREF_CREST_HERO },
        { id="MYTH",  color=MYTH,  ilvlBase=ilvlBase + ilvlTrackStep * 4,
                    trackName  = (Addon.IlvlUtils and Addon.IlvlUtils.GetCrestTrackName and Addon.IlvlUtils.GetCrestTrackName(5)) or "Myth",
          crest      = Locale.ILVLREF_CREST_MYTH,
          crestShort = Locale.ILVLREF_CREST_MYTH },
    }

    local function IC(tier, rank)
        local tierData = TIERS[tier]
        return tierData.color .. (tierData.ilvlBase + RANK_OFFSETS[rank]) .. COLOR_RESET
    end

    local function makeTrackRow(tier, rank, nextTier)
        local ilvl      = tier.ilvlBase + RANK_OFFSETS[rank]
        local isOverlap = (rank >= 5) and (nextTier ~= nil)

        local ilvlCell = (isOverlap and nextTier.color or tier.color) .. ilvl .. COLOR_RESET

        local nameCell
        if isOverlap then
            local nextRank = rank - 4
            local fb = tier.trackName .. " " .. rank .. "/6" .. " / " .. nextTier.trackName .. " " .. nextRank .. "/6"
            nameCell = DualTrack(fb, tier.color, nextTier.color)
        else
            nameCell = tier.color .. tier.trackName .. " " .. rank .. "/6" .. COLOR_RESET
        end

        local crestCell
        if isOverlap and (rank - 4) == 2 then
            crestCell = tier.color .. tier.crestShort .. COLOR_RESET
                     .. " - (|cFFFF2020" .. (Locale.ILVLREF_DO_NOT_USE_CRESTS_FMT or "DO NOT USE %s CRESTS"):format(nextTier.crest) .. "|r)"
        else
            crestCell = tier.color .. tier.crest .. COLOR_RESET
        end

        return { ilvlCell, nameCell, crestCell }
    end

    local DEFAULT_TRACKS_TABLE = {
        {
            Locale.ILVLREF_COL_ILVL,
            Locale.ILVLREF_COL_TRACK,
            Locale.ILVLREF_COL_CREST_NEEDED,
        },
    }
    for ti, tier in ipairs(TIERS) do
        local nextTier  = TIERS[ti + 1]
        local startRank = (ti == 1) and 1 or 3
        for rank = startRank, 6 do
            table.insert(DEFAULT_TRACKS_TABLE, makeTrackRow(tier, rank, nextTier))
        end
    end
    if #MYTH_EXTRA_ILVLS > 0 then
        local ilvl = MYTH_EXTRA_ILVLS[#MYTH_EXTRA_ILVLS]
        table.insert(DEFAULT_TRACKS_TABLE, {
            MYTH .. ilvl .. COLOR_RESET,
            MYTH .. TIERS[5].trackName .. " 9/6" .. COLOR_RESET,
            MYTH .. TIERS[5].crest .. COLOR_RESET,
        })
    end

    -- Crafted item levels  (quality n = tier base + RANK_OFFSETS[n])
    local rawIcons = tracking.craftingQualityIcons or {}
    local function QIcon(n)
        local atlas = rawIcons[n] or ("Professions-Icon-Quality-Tier" .. n)
        return "|A:" .. atlas .. ":14:14|a"
    end
    local DEFAULT_CRAFTED_TABLE = {
        {
            Locale.ILVLREF_COL_QUALITY,
            ADV .. Locale.ILVLREF_CREST_ADV .. COLOR_RESET,
            VET .. Locale.ILVLREF_CREST_VET .. COLOR_RESET,
            CHAMP .. Locale.ILVLREF_CREST_CHAMP .. COLOR_RESET,
            HERO .. Locale.ILVLREF_CREST_HERO .. COLOR_RESET,
            MYTH .. Locale.ILVLREF_CREST_MYTH .. COLOR_RESET,
        },
        { QIcon(1), IC(1,1), IC(2,1), IC(3,1), IC(4,1), IC(5,1) },
        { QIcon(2), IC(1,2), IC(2,2), IC(3,2), IC(4,2), IC(5,2) },
        { QIcon(3), IC(1,3), IC(2,3), IC(3,3), IC(4,3), IC(5,3) },
        { QIcon(4), IC(1,4), IC(2,4), IC(3,4), IC(4,4), IC(5,4) },
        { QIcon(5), IC(1,5), IC(2,5), IC(3,5), IC(4,5), IC(5,5) },
    }

    -- Dungeon item levels
    local DEFAULT_DUNGEONS_TABLE = {
        {
            Locale.ILVLREF_COL_SOURCE,
            Locale.ILVLREF_COL_END_LOOT,
            Locale.ILVLREF_COL_GREAT_VAULT,
        },
        { Locale.ILVLREF_DUNGEON_HEROIC,     IC(1,4), IC(2,4)  },
        { Locale.ILVLREF_DUNGEON_MYTHIC,     IC(3,1), IC(3,4)  },
        { "M2",  IC(3,2), IC(4,1) },
        { "M3",  IC(3,2), IC(4,1) },
        { "M4",  IC(3,3), IC(4,2) },
        { "M5",  IC(3,4), IC(4,2) },
        { "M6",  IC(4,1), IC(4,3) },
        { "M7",  IC(4,1), IC(4,4) },
        { "M8",  IC(4,2), IC(4,4) },
        { "M9",  IC(4,2), IC(4,4) },
        { "M10", IC(4,3), IC(5,1) },
        { "M11", IC(4,3), IC(5,1) },
        { "M12", IC(4,3), IC(5,1) },
    }

    -- Raid item levels  (each difficulty = one tier across boss columns 1–4)
    local DEFAULT_RAID_TABLE = {
        {
            Locale.ILVLREF_COL_DIFFICULTY,
            Locale.ILVLREF_COL_BOSS1,
            Locale.ILVLREF_COL_BOSS2,
            Locale.ILVLREF_COL_BOSS3,
            Locale.ILVLREF_COL_BOSS4,
        },
        { Locale.ILVLREF_RAID_LFR,    IC(2,1), IC(2,2), IC(2,3), IC(2,4) },
        { Locale.ILVLREF_RAID_NORMAL,  IC(3,1), IC(3,2), IC(3,3), IC(3,4) },
        { Locale.ILVLREF_RAID_HEROIC,  IC(4,1), IC(4,2), IC(4,3), IC(4,4) },
        { Locale.ILVLREF_RAID_MYTHIC,  IC(5,1), IC(5,2), IC(5,3), IC(5,4) },
    }

    -- Bountiful Delve item levels
    local tFmt = Locale.ILVLREF_DELVE_TIER_FMT
    local DEFAULT_DELVES_TABLE = {
        {
            Locale.ILVLREF_COL_TIER,
            Locale.ILVLREF_COL_END_LOOT,
            Locale.ILVLREF_COL_MAP_DROP,
            Locale.ILVLREF_COL_GREAT_VAULT,
        },
        { tFmt:format(1),  IC(1,1), "-",     IC(2,1) },
        { tFmt:format(2),  IC(1,2), "-",     IC(2,2) },
        { tFmt:format(3),  IC(1,3), "-",     IC(2,3) },
        { tFmt:format(4),  IC(1,4), IC(2,2), IC(2,4) },
        { tFmt:format(5),  IC(2,1), IC(2,4), IC(3,1) },
        { tFmt:format(6),  IC(2,2), IC(3,2), IC(3,3) },
        { tFmt:format(7),  IC(3,2), IC(3,4), IC(3,4) },
        { tFmt:format(8),  IC(3,2), IC(4,1), IC(4,1) },
        { tFmt:format(9),  IC(3,2), IC(4,1), IC(4,1) },
        { tFmt:format(10), IC(3,2), IC(4,1), IC(4,1) },
        { tFmt:format(11), IC(3,2), IC(4,1), IC(4,1) },
    }

    local function ResolveLocaleToken(value)
        if type(value) == "string" and Locale[value] then
            return Locale[value]
        end
        return value
    end

    local function ResolveHeaderCell(value)
        if type(value) == "string" then
            local crestTier = value:match("^CREST_(%d)$")
            if crestTier then
                local tier = tonumber(crestTier)
                local tierData = TIERS[tier]
                if tierData then
                    return tierData.color .. tierData.crest .. COLOR_RESET
                end
            end
        end
        return ResolveLocaleToken(value)
    end

    local function ColorizeIlvlNumber(ilvl)
        if type(ilvl) ~= "number" then return ilvl end
        local hex = (Addon.IlvlUtils and Addon.IlvlUtils.GetColorHex and Addon.IlvlUtils.GetColorHex(ilvl)) or "ffffffff"
        return "|c" .. hex .. tostring(ilvl) .. COLOR_RESET
    end

    local function ResolvePairCell(cell)
        if type(cell) == "number" then
            return ColorizeIlvlNumber(cell)
        end
        if type(cell) == "table" and type(cell[1]) == "number" and type(cell[2]) == "number" then
            return IC(cell[1], cell[2])
        end
        return ResolveLocaleToken(cell)
    end

    local function BuildTracksTableFromSpec(spec)
        if type(spec) ~= "table" or #spec < 2 then return nil end

        local out = {}
        local header = spec[1]
        if type(header) ~= "table" then return nil end
        out[1] = {
            ResolveHeaderCell(header[1]),
            ResolveHeaderCell(header[2]),
            ResolveHeaderCell(header[3]),
        }

        local function FindRankForIlvl(tierData, ilvl)
            if not (tierData and type(ilvl) == "number") then return nil end
            for r = 1, #RANK_OFFSETS do
                if (tierData.ilvlBase + (RANK_OFFSETS[r] or 0)) == ilvl then
                    return r
                end
            end
            return nil
        end

        for i = 2, #spec do
            local row = spec[i]
            if type(row) == "table" then
                local tierIndex = tonumber(row.tier or row[1])
                local rank = tonumber(row.rank or row[2])
                local explicitNextTierIndex = tonumber(row.nextTier or row[3]) or 0
                local explicitNextRank = tonumber(row.nextRank)
                local explicitIlvl = tonumber(row.ilvl or row[4])

                local tier = tierIndex and TIERS[tierIndex]
                if tier and rank and (rank <= 6 or (tierIndex == #TIERS and rank == 9)) then
                    local ilvl = explicitIlvl or (tier.ilvlBase + (RANK_OFFSETS[rank] or 0))
                    local inferredNextTierIndex = 0
                    local inferredNextRank = nil
                    local nextTierByOrder = TIERS[(tierIndex or 0) + 1]
                    if nextTierByOrder then
                        inferredNextRank = FindRankForIlvl(nextTierByOrder, ilvl)
                        if inferredNextRank then
                            inferredNextTierIndex = (tierIndex or 0) + 1
                        end
                    end

                    local nextTierIndex = (explicitNextTierIndex > 0) and explicitNextTierIndex or inferredNextTierIndex
                    local nextTier = (nextTierIndex > 0) and TIERS[nextTierIndex] or nil
                    local nextRank = explicitNextRank or inferredNextRank
                    if not (nextRank and nextRank > 0) and nextTier then
                        nextRank = FindRankForIlvl(nextTier, ilvl) or (rank - 4)
                    end

                    local isOverlap = (nextTier ~= nil) and (nextRank ~= nil)

                    local ilvlCell = (isOverlap and nextTier.color or tier.color) .. ilvl .. COLOR_RESET
                    local nameCell
                    if isOverlap then
                        local fb = tier.trackName .. " " .. rank .. "/6" .. " / " .. nextTier.trackName .. " " .. nextRank .. "/6"
                        nameCell = DualTrack(fb, tier.color, nextTier.color)
                    else
                        nameCell = tier.color .. tier.trackName .. " " .. rank .. "/6" .. COLOR_RESET
                    end

                    local crestCell
                    if isOverlap and nextRank == 2 then
                        crestCell = tier.color .. tier.crestShort .. COLOR_RESET
                            .. " - (|cFFFF2020" .. (Locale.ILVLREF_DO_NOT_USE_CRESTS_FMT or "DO NOT USE %s CRESTS"):format(nextTier.crest) .. "|r)"
                    else
                        crestCell = tier.color .. tier.crest .. COLOR_RESET
                    end

                    out[#out + 1] = { ilvlCell, nameCell, crestCell }
                end
            end
        end

        return (#out >= 2) and out or nil
    end

    local function BuildCraftedTableFromSpec(spec)
        if type(spec) ~= "table" or #spec < 2 then return nil end
        local out = {}
        local header = spec[1]
        if type(header) ~= "table" then return nil end
        out[1] = {
            ResolveHeaderCell(header[1]),
            ResolveHeaderCell(header[2]),
            ResolveHeaderCell(header[3]),
            ResolveHeaderCell(header[4]),
            ResolveHeaderCell(header[5]),
            ResolveHeaderCell(header[6]),
        }
        for i = 2, #spec do
            local row = spec[i]
            if type(row) == "table" then
                local quality = tonumber(row[1])
                if quality then
                    out[#out + 1] = {
                        QIcon(quality),
                        ResolvePairCell(row[2]),
                        ResolvePairCell(row[3]),
                        ResolvePairCell(row[4]),
                        ResolvePairCell(row[5]),
                        ResolvePairCell(row[6]),
                    }
                end
            end
        end
        return (#out >= 2) and out or nil
    end

    local function BuildGenericTableFromSpec(spec, firstColFormatter)
        if type(spec) ~= "table" or #spec < 2 then return nil end
        local out = {}
        local header = spec[1]
        if type(header) ~= "table" then return nil end

        local headerOut = {}
        for i = 1, #header do
            headerOut[i] = ResolveHeaderCell(header[i])
        end
        out[1] = headerOut

        for i = 2, #spec do
            local row = spec[i]
            if type(row) == "table" then
                local rowOut = {}
                for ci = 1, #row do
                    local cell = row[ci]
                    if ci == 1 and firstColFormatter then
                        rowOut[ci] = firstColFormatter(cell)
                    else
                        rowOut[ci] = ResolvePairCell(cell)
                    end
                end
                out[#out + 1] = rowOut
            end
        end

        return (#out >= 2) and out or nil
    end

    local seasonTables = type(tracking.ilvlRefTables) == "table" and tracking.ilvlRefTables or nil
    local TRACKS_TABLE = (seasonTables and BuildTracksTableFromSpec(seasonTables.tracks)) or DEFAULT_TRACKS_TABLE
    local CRAFTED_TABLE = (seasonTables and BuildCraftedTableFromSpec(seasonTables.crafted)) or DEFAULT_CRAFTED_TABLE
    local DUNGEONS_TABLE = (seasonTables and BuildGenericTableFromSpec(seasonTables.dungeons)) or DEFAULT_DUNGEONS_TABLE
    local RAID_TABLE = (seasonTables and BuildGenericTableFromSpec(seasonTables.raid)) or DEFAULT_RAID_TABLE
    local DELVES_TABLE = (seasonTables and BuildGenericTableFromSpec(seasonTables.delves, function(cell)
        if type(cell) == "number" then
            return tFmt:format(cell)
        end
        return ResolveLocaleToken(cell)
    end)) or DEFAULT_DELVES_TABLE

    local function MatrixToColsRows(matrix)
        local headers = matrix[1] or {}
        local rows = {}
        for i = 2, #matrix do
            rows[#rows + 1] = matrix[i]
        end
        local cols = {}
        for i, header in ipairs(headers) do
            cols[i] = { t = header }
        end
        return AutoFitCols(cols, rows), rows
    end

    -- Pre-fit column widths and compute dynamic window width ----------------
    local trackCols, trackRows = MatrixToColsRows(TRACKS_TABLE)
    local craftCols, craftRows = MatrixToColsRows(CRAFTED_TABLE)
    local dungCols, dungRows = MatrixToColsRows(DUNGEONS_TABLE)
    local raidCols, raidRows = MatrixToColsRows(RAID_TABLE)
    local delveCols, delveRows = MatrixToColsRows(DELVES_TABLE)
    local function tblW(cols) return cols[#cols].x + cols[#cols].w end

    local win = Addon:NewThemedFrame("LariasIlvlRefFrame", UIParent)

    -- Default width = 2-col layout (Tracks | everything else).  Set after
    -- BuildSection calls (wTracks/wRight2 not yet available here).
    win:SetSize(WIN_W, WIN_H)
    local _savedIlvlPos = Addon.db and Addon.db.global and Addon.db.global.ilvlRefPos
    if _savedIlvlPos and _savedIlvlPos.x and _savedIlvlPos.y then
        win:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", _savedIlvlPos.x, _savedIlvlPos.y)
    else
        -- Default: snap to the right edge of the main checklist frame, same Y.
        local mf = Addon._mainFrame
        if mf then
            win:SetPoint("TOPLEFT", mf, "TOPRIGHT", 4, 0)
        else
            win:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
        end
    end
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function()
        win:StopMovingOrSizing()
        local _gdb = Addon.db and Addon.db.global
        if _gdb then
            _gdb.ilvlRefPos = { x = win:GetLeft(), y = win:GetBottom() }
        end
    end)
    win:SetFrameStrata("DIALOG")
    win:SetFrameLevel(100)
    win:Hide()

    -- Opaque popup without the shared header-color surface tint.
    Addon:RegisterWindowSurface(win, { opacityMode = "opaque", borderStyle = "popup", surfaceTopA = 0 })

    -- Title (centered, leaves room for close button on the right)
    local titleFS = win:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    titleFS:SetPoint("TOPLEFT",  win, "TOPLEFT",  PAD,  -10)
    -- Leave room for two (SCROLLTOP-4)=28px buttons + 2px gaps + 2px right margin = 64px.
    titleFS:SetPoint("TOPRIGHT", win, "TOPRIGHT", -64,  -10)
    titleFS:SetJustifyH("CENTER")
    local titleHeaderColor = Addon.THEME.header
    titleFS:SetTextColor(titleHeaderColor.r, titleHeaderColor.g, titleHeaderColor.b, titleHeaderColor.a)
    titleFS:SetText(GetIlvlRefWindowTitle(Locale))

    -- Close button: branded ✕ matching the addon theme.
    local closeBtn = Addon.Controls.NewCloseButton(win, function() win:Hide() end)
    closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -2, -2)
    closeBtn:SetSize(SCROLLTOP - 4, SCROLLTOP - 4)
    closeBtn:SetBackdropBorderColor(0, 0, 0, 0)

    -- Register with UISpecialFrames so ESC closes this window via Blizzard's
    -- secure ESC chain rather than the protected SetPropagateKeyboardInput.
    tinsert(UISpecialFrames, "LariasIlvlRefFrame")

    -- Scroll frame (auto-adapts to win size; content reflows instead of scaling)
    local sf = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT",     win, "TOPLEFT",  PAD,     -SCROLLTOP)
    sf:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -(PAD + 22), PAD)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetSize(1, 1)
    sf:SetScrollChild(sc)

    -- Build each section into its own sub-frame so ReflowIlvlSections can
    -- reposition them without redrawing any content.
    local COL_GAP = 20  -- horizontal gap between two columns when side-by-side

    local function BuildSection(headText, cols, rows)
        local secFrame = CreateFrame("Frame", nil, sc)
        local sectionY = 0
        sectionY = SecHead(secFrame, sectionY, headText)
        sectionY = GridTable(secFrame, sectionY, cols, rows)
        local secHeight = -sectionY
        local secWidth  = tblW(cols)
        secFrame:SetSize(secWidth, secHeight)
        return secFrame, secWidth, secHeight
    end

    local secTracks,  wTracks,  hTracks  = BuildSection(Locale.ILVLREF_SEC_TRACKS,   trackCols, trackRows)
    local secCrafted, wCrafted, hCrafted = BuildSection(Locale.ILVLREF_SEC_CRAFTED,   craftCols, craftRows)
    local secDungs,   wDungs,   hDungs   = BuildSection(Locale.ILVLREF_SEC_DUNGEONS,  dungCols,  dungRows)
    local secRaid,    wRaid,    hRaid    = BuildSection(Locale.ILVLREF_SEC_RAID,       raidCols,  raidRows)
    local secDelves,  wDelves,  hDelves  = BuildSection(Locale.ILVLREF_SEC_DELVES,    delveCols, delveRows)

    -- Natural column widths for multi-column layouts
    local wMid    = math.max(wCrafted, wDungs)        -- 3-col: middle column
    local wRight3 = math.max(wRaid,    wDelves)        -- 3-col: right column
    local wSingle = math.max(wTracks, wCrafted, wDungs, wRaid, wDelves)  -- 1-col: widest table

    -- Maximized = 3-col, auto-height, no scroll.
    -- Minimized = 1-col stacked, fixed WIN_H, scrollable.
    local _isMaximized = (Addon.db and Addon.db.global and Addon.db.global.ilvlRefMaximized) and true or false
    local _reflowing   = false

    local function ReflowIlvlSections()
        if _reflowing then return end
        _reflowing = true

        local sb = sf.ScrollBar

        if _isMaximized then
            -- ── Three-column layout (maximized) ───────────────────────────────
            local col3W = wTracks + wMid + wRight3 + COL_GAP * 2
            sc:SetWidth(max(1, col3W))

            secTracks:ClearAllPoints()
            secTracks:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, 0)

            local midX   = wTracks + COL_GAP
            local rightX = midX + wMid + COL_GAP

            local my = 0
            for i, s in ipairs({ secCrafted, secDungs }) do
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", sc, "TOPLEFT", midX, my)
                my = my - ({ hCrafted, hDungs })[i] - SEC_GAP
            end

            local ry = 0
            for i, s in ipairs({ secRaid, secDelves }) do
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", sc, "TOPLEFT", rightX, ry)
                ry = ry - ({ hRaid, hDelves })[i] - SEC_GAP
            end

            sc:SetHeight(max(1, math.max(hTracks, -my, -ry) + PAD))

            -- Auto-fit height so no scrollbar is needed.
            local idealH = SCROLLTOP + math.ceil(sc:GetHeight()) + PAD
            win:SetHeight(idealH)
            -- +1 extra pixel so the scroll viewport (win_w - 2*PAD - 22) is wide
            -- enough to include the 1px right-border vline drawn at x=col3W.
            win:SetWidth(col3W + PAD * 2 + 22 + 1)
            if sb then sb:Hide() end

        else
            -- ── Single-column layout (minimized / default) ────────────────────
            sc:SetWidth(max(1, wSingle))

            local allSecs = { secTracks, secCrafted, secDungs, secRaid,  secDelves }
            local allHs   = { hTracks,  hCrafted,   hDungs,   hRaid,    hDelves   }
            local y = 0
            for i, s in ipairs(allSecs) do
                s:ClearAllPoints()
                s:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, y)
                y = y - allHs[i] - SEC_GAP
            end
            sc:SetHeight(max(1, -y + PAD))

            -- Fixed window height; scroll frame handles overflow.
            win:SetHeight(WIN_H)
            if sb then sb:Show() end
        end

        -- The outer window (win) is scaled uniformly via win:SetScale() in
        -- ApplyUIScale, so no separate content scale is needed here.

        _reflowing = false
    end

    win._ilvlReflow = ReflowIlvlSections

    -- Toggle button: branded expand/shrink icon matching the header button row.
    local toggleBtn = Addon.Controls.NewExpandButton(win,
        nil,  -- OnClick wired below
        not _isMaximized,  -- shrunk = expanded=true shows the ▼ ("click to shrink") glyph
        Locale.ILVLREF_TOGGLE_EXPAND or "Expand",
        Locale.ILVLREF_TOGGLE_SHRINK or "Shrink")
    -- Sit immediately left of the close button, vertically aligned.
    toggleBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -2, 0)
    toggleBtn:SetSize(SCROLLTOP - 4, SCROLLTOP - 4)
    toggleBtn:SetBackdropBorderColor(0, 0, 0, 0)

    local function UpdateToggleTexture()
        -- expanded=true means the window IS maximized (down arrow, click to shrink).
        toggleBtn:SetExpanded(_isMaximized)
    end
    UpdateToggleTexture()

    toggleBtn:SetScript("OnClick", function()
        _isMaximized = not _isMaximized
        local _gdb = Addon.db and Addon.db.global
        if _gdb then _gdb.ilvlRefMaximized = _isMaximized end
        UpdateToggleTexture()
        -- Freeze the horizontal center so the window grows/shrinks
        -- symmetrically left and right from its current position.
        local pinCX  = win:GetLeft() + win:GetWidth() / 2
        local pinTop = win:GetTop()
        if _isMaximized then
            -- Widen to fit 3-col before reflow so layout branch is chosen correctly.
            -- +1 for the right-border pixel on the last table (see ReflowIlvlSections).
            win:SetWidth(wTracks + wMid + wRight3 + COL_GAP * 2 + PAD * 2 + 22 + 1)
        else
            win:SetWidth(wSingle + PAD * 2 + 22)
        end
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pinCX - win:GetWidth() / 2, pinTop)
        ReflowIlvlSections()
    end)

    -- Initial state: apply saved maximized state (defaults to minimized/1-col scrollable).
    if _isMaximized then
        win:SetWidth(wTracks + wMid + wRight3 + COL_GAP * 2 + PAD * 2 + 22 + 1)
    else
        win:SetWidth(wSingle + PAD * 2 + 22)
    end
    ReflowIlvlSections()

    return win
end

function Addon:ToggleIlvlRefWindow()
    if self._ilvlRefWindow then
        if self._ilvlRefWindow:IsShown() then
            self._ilvlRefWindow:Hide()
        else
            self._ilvlRefWindow:Show()
        end
        return
    end

    -- Build on first use
    self._ilvlRefWindow = BuildIlvlRefWindow()
    self._ilvlRefWindow:Show()
end

-- Called from UpdateLocalizedUI after a locale switch.
-- Destroys the cached window so the next open rebuilds it with the new locale.
function Addon:RebuildIlvlRefWindow()
    if not self._ilvlRefWindow then return end
    local wasShown = self._ilvlRefWindow:IsShown()
    self._ilvlRefWindow:Hide()
    self._ilvlRefWindow = nil
    -- Remove the old global frame name so CreateFrame doesn't collide.
    if _G["LariasIlvlRefFrame"] then
        _G["LariasIlvlRefFrame"] = nil
    end
    if wasShown then
        self._ilvlRefWindow = BuildIlvlRefWindow()
        self._ilvlRefWindow:Show()
    end
end
