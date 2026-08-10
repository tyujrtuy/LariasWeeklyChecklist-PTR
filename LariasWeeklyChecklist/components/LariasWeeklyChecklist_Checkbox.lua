local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

-- ── Checkbox control ──────────────────────────────────────────────────────────
--
--   Addon.Controls.NewCheckBox(parent [, onToggle [, boxSize]])
--       Fully custom checkbox: dark square, gold ✓ glyph, no Blizzard art.
--       cb.text/cb._label = label FontString; cb._box = visual frame; cb._hit = hit area.
--       cb:GetChecked() / cb:SetChecked(bool). onToggle(checked:bool) fires on click.

Addon.Controls = Addon.Controls or {}
local C = Addon.Controls

-- ── Checkbox ──────────────────────────────────────────────────────────────────
-- Fully addon-themed checkbox — no Blizzard UICheckButtonTemplate used.
--
-- Visual:  dark bordered square (_box) with a gold ✓ glyph when checked.
-- Layout:  label FontString (.text / ._label) anchored LEFT of the box.
--          No right anchor set — caller adds cb._label:SetPoint("RIGHT",...)
--          or calls textLabel:SetWidth(w) for multi-line row use.
--
-- Pooling: _box, _label/_tick are children of cb → survive SetParent() safely.
-- Hit:     _hit is an unsized Button (child of cb at parent's frame level).
--          Caller positions + sizes it for full-row click coverage.
--
-- API shims (CheckButton-compatible):
--   cb:GetChecked()     → bool
--   cb:SetChecked(val)  → sets _checked, shows/hides tick
--   cb:RefreshTint()    → no-op (no Blizzard textures to re-tint)
--
-- onToggle(checked:bool) fires after every click via cb or _hit (NOT SetChecked).
-- boxSize defaults to 16.
function C.NewCheckBox(parent, onToggle, boxSize)
    boxSize = boxSize or 16

    local T  = Addon.THEME or {}
    local th = T.check  or T.header or { r = 0.19, g = 0.83, b = 0.19, a = 1 }
    local tc = T.text   or { r = 1,    g = 1,    b = 1,    a = 1 }

    -- Outer button: interaction container.
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(boxSize, boxSize)

    -- Visual box: fixed size, vertically centered within cb's height.
    local box = CreateFrame("Frame", nil, cb)
    box:SetSize(boxSize, boxSize)
    box:SetPoint("LEFT", cb, "LEFT", 0, 0)
    Addon:ApplyTheme(box)
    cb._box = box

    -- HIGHLIGHT anchored to the box area.
    local hl = cb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT",     box, "TOPLEFT",     0, 0)
    hl:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    hl:SetColorTexture(1, 1, 1, 0.15)

    -- Gold checkmark using Blizzard's UI-CheckBox-Check texture tinted gold.
    local tick = box:CreateTexture(nil, "OVERLAY")
    tick:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    tick:SetAllPoints(box)
    tick:SetVertexColor(th.r, th.g, th.b, 1)
    tick:Hide()
    cb._tick = tick

    -- Label FontString: child of cb so it survives SetParent / pool reuse.
    local lbl = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", box, "RIGHT", 4, 0)
    lbl:SetJustifyH("LEFT")
    if lbl.SetWordWrap then lbl:SetWordWrap(true) end
    lbl:SetTextColor(tc.r, tc.g, tc.b, tc.a or 1)
    cb._label = lbl
    cb.text   = lbl   -- compat: code reads checkbox.text or checkbox.Text

    -- Hit area: unsized Button child of cb; caller positions and sizes it.
    local hit = CreateFrame("Button", nil, cb)
    hit:SetFrameLevel(parent:GetFrameLevel())
    local hitHl = hit:CreateTexture(nil, "HIGHLIGHT")
    hitHl:SetAllPoints(hit)
    hitHl:SetColorTexture(1, 1, 1, 0.06)
    cb._hit = hit

    -- State API ---------------------------------------------------------------
    cb._checked = false

    function cb:GetChecked()
        return self._checked
    end

    function cb:SetChecked(val)
        self._checked = val and true or false
        if self._checked then tick:Show() else tick:Hide() end
    end

    function cb:RefreshTint()
        -- No-op: compat shim for callers that still invoke it.
    end

    -- Clicks ------------------------------------------------------------------
    cb:SetScript("OnClick", function(self_)
        self_:SetChecked(not self_._checked)
        if onToggle then onToggle(self_._checked) end
    end)
    hit:SetScript("OnClick", function()
        local newVal = not cb._checked
        cb:SetChecked(newVal)
        if onToggle then onToggle(newVal) end
    end)

    return cb
end
