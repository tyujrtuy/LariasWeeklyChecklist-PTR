-- AddonUtils: general-purpose utilities shared across body and other feature modules.
-- Must be loaded before any feature module that references Addon.AddonUtils.
--
-- Exposes Addon.AddonUtils:
--   COLORS              - palette table { red, yellow, green, white, dim, gold }
--   ColorWrap(hex, txt) - wraps text in a WoW color escape.
--   Wipe(t)             - empties table t in-place (nil-safe).
--   IsNonEmptyText(txt) - true when string contains visible characters.
--   FormatXY(cur, cap)  - formats progress as "cur/cap" or "cur".
--   ColorForXY(cur, cap)- returns red/yellow/green hex based on progress
--                          (green at/above cap, yellow from 50%, else red).
--   ColorForXYRGB(cur, cap) - same rule, returns r,g,b 0-1 floats instead.
--   GetCurrencyName(id) - safe currency name lookup.
--   GetCurrencyIcon(id) - safe currency icon lookup.
--   GetItemName(id)     - safe item name lookup.
--   MoveArrayEntry(t, fromIdx, toIdx) - reorders one entry within an array table.
--   GetFrameCursorOffset(frame, axis) - cursor offset relative to frame left/top.
--   CreateDragReorderController(frame, opts) - generic 1D drag/reorder state machine.
--
-- Also exposes Addon.RIGHT_LINE_COUNT (initial right-panel row count used by Overlay).

local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local AddonUtils = {}
Addon.AddonUtils = AddonUtils
local abs, max, min = math.abs, math.max, math.min

-- Shared WoW color-escape palette used by tracking rows and tooltips.
AddonUtils.COLORS = {
    red    = "ffff4040",
    yellow = "ffffd34d",
    green  = "ff40ff40",
    white  = "ffffffff",
    dim    = "ff808080",
    gold   = "ffcc9a28",  -- warm WoW gold for currency labels
}
local COLORS = AddonUtils.COLORS

-- Wraps text in a precomputed WoW ARGB color code (for example "ffff4040").
function AddonUtils.ColorWrap(hex, txt)
    return "|c" .. hex .. tostring(txt or "") .. "|r"
end

function AddonUtils.Wipe(t)
    if not t then return end
    if wipe then wipe(t); return end
    for k in pairs(t) do t[k] = nil end
end

function AddonUtils.IsNonEmptyText(text)
    if type(text) ~= "string" then return false end
    text = text:gsub("|[cr][%x]*", "")
    return text:match("%S") ~= nil
end

function AddonUtils.FormatXY(cur, cap)
    cur = tonumber(cur) or 0
    cap = tonumber(cap) or 0
    if cap > 0 then return ("%d/%d"):format(cur, cap) end
    return tostring(cur)
end

-- Shared currency progress rule: green once at/above cap, yellow from 50% up
-- to (not including) cap, red below 50%. Used for every currency readout
-- (crests, catalyst, sparks, coffer keys, misc) so they all read consistently.
-- When no cap is known, falls back to a simple "have any / have none" split.
local function CurrencyProgressState(cur, cap)
    cur = tonumber(cur) or 0
    cap = tonumber(cap) or 0
    if cap > 0 then
        if cur >= cap then return "green" end
        if cur >= cap * 0.5 then return "yellow" end
        return "red"
    end
    return (cur > 0) and "yellow" or "red"
end

function AddonUtils.ColorForXY(cur, cap)
    return COLORS[CurrencyProgressState(cur, cap)]
end

-- Same rule as ColorForXY, but as 0-1 RGB floats for widgets that set
-- SetTextColor directly instead of using a WoW color-escape string.
local function HexPairToUnit(hex, pos)
    return (tonumber(hex:sub(pos, pos + 1), 16) or 255) / 255
end
AddonUtils.COLOR_RGB = {}
for name, hex in pairs(COLORS) do
    -- hex format is "aarrggbb" (WoW color-escape byte order).
    AddonUtils.COLOR_RGB[name] = { HexPairToUnit(hex, 3), HexPairToUnit(hex, 5), HexPairToUnit(hex, 7) }
end

function AddonUtils.ColorForXYRGB(cur, cap)
    local rgb = AddonUtils.COLOR_RGB[CurrencyProgressState(cur, cap)]
    return rgb[1], rgb[2], rgb[3]
end

function AddonUtils.GetCurrencyInfo(id)
    id = tonumber(id)
    if not (id and id > 0) then return nil end
    return C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
end

function AddonUtils.GetCurrencyName(id)
    local info = AddonUtils.GetCurrencyInfo(id)
    return info and info.name
end

function AddonUtils.GetCurrencyIcon(id)
    local info = AddonUtils.GetCurrencyInfo(id)
    return info and info.iconFileID
end

function AddonUtils.GetItemName(id)
    id = tonumber(id)
    if not (id and id > 0) then return nil end
    return GetItemInfo and GetItemInfo(id) or nil
end

function AddonUtils.SetTooltip(frame, text, anchor)
    GameTooltip:SetOwner(frame, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
end

function AddonUtils.HideTooltip()
    GameTooltip:Hide()
end

-- Safe frame visibility check.  Works on any object shape (frames, regions, etc).
function AddonUtils.IsFrameShown(f)
    return f and f.IsShown and f:IsShown()
end

-- Multi-line tooltip.  lines = array of strings or {text, r, g, b} tables.
-- First entry uses SetText; subsequent entries use AddLine.
function AddonUtils.SetTooltipLines(frame, lines, anchor)
    GameTooltip:SetOwner(frame, anchor or "ANCHOR_RIGHT")
    for i, line in ipairs(lines) do
        local text = type(line) == "table" and (line.text or line[1]) or tostring(line)
        local r    = type(line) == "table" and (line.r    or line[2] or 1) or 1
        local g    = type(line) == "table" and (line.g    or line[3] or 1) or 1
        local b    = type(line) == "table" and (line.b    or line[4] or 1) or 1
        if i == 1 then
            GameTooltip:SetText(text, r, g, b)
        else
            GameTooltip:AddLine(text, r, g, b, true)
        end
    end
    GameTooltip:Show()
end

function AddonUtils.MoveArrayEntry(items, fromIdx, toIdx)
    if type(items) ~= "table" then return items end
    local count = #items
    if count <= 0 then return items end

    fromIdx = max(1, min(count, tonumber(fromIdx) or 1))
    local moved = table.remove(items, fromIdx)
    if moved == nil then return items end

    local insertMax = #items + 1
    toIdx = max(1, min(insertMax, tonumber(toIdx) or fromIdx))
    table.insert(items, toIdx, moved)
    return items
end

function AddonUtils.GetFrameCursorOffset(frame, axis)
    if not (frame and GetCursorPosition and frame.GetEffectiveScale) then return nil end
    local scale = frame:GetEffectiveScale()
    if not scale or scale == 0 then scale = 1 end

    if axis == "y" then
        local cursorY = select(2, GetCursorPosition())
        local top = frame:GetTop()
        if not (cursorY and top) then return nil end
        return top - (cursorY / scale)
    end

    local cursorX = select(1, GetCursorPosition())
    local left = frame:GetLeft()
    if not (cursorX and left) then return nil end
    return (cursorX / scale) - left
end

function AddonUtils.CreateDragReorderController(frame, opts)
    opts = opts or {}
    local controller = { frame = frame, opts = opts, state = nil }

    function controller:GetState()
        return self.state
    end

    function controller:Clear()
        local state = self.state
        if state and opts.restoreDragVisual then
            opts.restoreDragVisual(state, self.frame)
        end
        self.state = nil
        if opts.hideIndicator then
            opts.hideIndicator(self.frame)
        end
        if opts.setUpdating then
            opts.setUpdating(self.frame, false)
        end
    end

    function controller:Begin(state)
        if type(state) ~= "table" then return false end
        local cursorValue = opts.getCursorValue and opts.getCursorValue(self.frame)
        if cursorValue == nil then return false end
        self:Clear()
        state.active = false
        state.startCursor = cursorValue
        state.targetIdx = state.targetIdx or state.sourceIdx
        self.state = state
        if opts.setUpdating then
            opts.setUpdating(self.frame, true)
        end
        return true
    end

    function controller:Finish()
        local state = self.state
        if not state then return nil, false end

        local targetIdx = state.targetIdx or state.sourceIdx
        local shouldCommit = state.active and targetIdx and targetIdx ~= state.sourceIdx and opts.onCommit
        if shouldCommit then
            local commitState = state
            self:Clear()
            opts.onCommit(self.frame, commitState, targetIdx)
            return commitState, true
        end

        self:Clear()
        return state, false
    end

    function controller:Update()
        local state = self.state
        if not state then return end

        local leftDown = opts.isDragButtonDown and opts.isDragButtonDown()
        if leftDown == nil then
            leftDown = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
        end
        if not leftDown then
            self:Finish()
            return
        end

        local cursorValue = opts.getCursorValue and opts.getCursorValue(self.frame)
        if cursorValue == nil then return end

        if not state.active then
            if abs(cursorValue - (state.startCursor or cursorValue)) < (tonumber(opts.threshold) or 0) then
                return
            end
            state.active = true
            if opts.onActivate then
                opts.onActivate(self.frame, state)
            end
            if opts.applyDragVisual then
                opts.applyDragVisual(state, self.frame)
            end
        end

        state.targetIdx = (opts.getDropIndex and opts.getDropIndex(cursorValue, state, self.frame))
            or state.sourceIdx
        if opts.showIndicator then
            opts.showIndicator(state.targetIdx, state, self.frame)
        end
    end

    return controller
end

-- Initial rows in the right column; Overlay grows beyond this when more rows exist.
Addon.RIGHT_LINE_COUNT = 10
