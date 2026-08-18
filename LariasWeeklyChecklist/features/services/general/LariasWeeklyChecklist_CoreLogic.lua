-- Pure decision logic shared by runtime modules and the standalone test suite.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

local Core = {}
Addon.CoreLogic = Core

Core.EVENT_DIRTY_DOMAINS = {
    WEEKLY_REWARDS_UPDATE = { vault = true },
    PLAYER_EQUIPMENT_CHANGED = { gear = true, currency = true },
    UNIT_INVENTORY_CHANGED = { gear = true, currency = true },
    CURRENCY_DISPLAY_UPDATE = { currency = true },
    BAG_UPDATE_DELAYED = { currency = true },
    QUEST_TURNED_IN = { currency = true },
    CATALYST_CHARGES_UPDATED = { currency = true },
    CATALYST_UPDATE = { currency = true },
    ITEM_INTERACTION_ITEM_SELECTION_UPDATED = { gear = true, currency = true },
}

function Core.MergeDirtyDomains(target, eventName)
    local domains = Core.EVENT_DIRTY_DOMAINS[eventName]
    if eventName == nil or eventName == "PLAYER_ENTERING_WORLD" or not domains then
        target.full = true
        return target
    end
    for domain in pairs(domains) do
        target[domain] = true
    end
    return target
end

function Core.GetSnapshotRefreshPlan(dirtyDomains)
    local refreshAll = type(dirtyDomains) ~= "table" or dirtyDomains.full == true
    local refreshVault = refreshAll or dirtyDomains.vault == true
    local refreshGear = refreshAll or dirtyDomains.gear == true
    local refreshCurrency = refreshAll or refreshGear or dirtyDomains.currency == true
    return refreshVault, refreshGear, refreshCurrency
end

function Core.BuildValidChecklistKeys(data)
    if type(data) ~= "table" or #data == 0 then return nil, nil end

    local validSections = {}
    local validItemKeys = {}
    for _, section in ipairs(data) do
        if type(section) == "table" and type(section.id) == "string" then
            validSections[section.id] = true
            if type(section.items) == "table" then
                for _, item in ipairs(section.items) do
                    if type(item) == "table" and type(item.id) == "string" then
                        validItemKeys[tostring(section.id) .. ":" .. tostring(item.id)] = true
                    end
                end
            end
        end
    end

    if not next(validSections) or not next(validItemKeys) then return nil, nil end
    return validSections, validItemKeys
end

local function Trim(value)
    return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function Core.NormalizeVersionString(version)
    local value = Trim(version)
    value = value:gsub("%s.*$", "")
    if value:match("^[vV]%d") then value = value:sub(2) end
    return value
end

local function StripBuildAndPrerelease(version)
    local value = Core.NormalizeVersionString(version)
    if value == "" then return "" end
    value = value:match("^([^+]+)") or value
    return value:match("^(.-)%-") or value
end

function Core.IsLiveVersion(version)
    local value = Core.NormalizeVersionString(version)
    if value == "" then return false end
    value = value:match("^([^+]+)") or value
    return not value:find("%-")
end

function Core.ParseLiveVersion(version, maxLength)
    if type(version) ~= "string" then return nil end
    local value = Trim(version)
    maxLength = tonumber(maxLength) or 32
    if value == "" or #value > maxLength or value:find("%s") then return nil end
    if value:match("^[vV]%d") then value = value:sub(2) end

    local main, build = value, nil
    local plusAt = value:find("+", 1, true)
    if plusAt then
        main = value:sub(1, plusAt - 1)
        build = value:sub(plusAt + 1)
        if build == "" or build:find("+", 1, true) or build:find("[^%w%.%-]") then
            return nil
        end
    end

    if main == "" or main:find("[^%d%.]") or main:find("..", 1, true)
            or main:sub(1, 1) == "." or main:sub(-1) == "." then
        return nil
    end

    local componentCount = 0
    for component in main:gmatch("[^.]+") do
        componentCount = componentCount + 1
        if #component > 6 then return nil end
    end
    if componentCount == 0 or componentCount > 6 then return nil end
    return value
end

local function ParseVersionNumbers(version)
    local main = StripBuildAndPrerelease(version)
    if main == "" then return nil end
    local numbers = {}
    for number in tostring(main):gmatch("%d+") do
        numbers[#numbers + 1] = tonumber(number) or 0
    end
    if #numbers == 0 then return nil end
    return numbers
end

function Core.CompareVersions(versionA, versionB)
    local aNumbers = ParseVersionNumbers(versionA)
    local bNumbers = ParseVersionNumbers(versionB)
    if not aNumbers and not bNumbers then return 0 end
    if not aNumbers then return -1 end
    if not bNumbers then return 1 end

    local maxLength = (#aNumbers > #bNumbers) and #aNumbers or #bNumbers
    for index = 1, maxLength do
        local aValue = aNumbers[index] or 0
        local bValue = bNumbers[index] or 0
        if aValue ~= bValue then return (aValue > bValue) and 1 or -1 end
    end
    return 0
end

local LEGACY_PREFERENCE_KEYS = {
    "showGreatVault", "showCurrency",
    "showChangeWeekBtn", "showIlvlRefBtn", "debug",
}

function Core.HasLegacyProfilePayload(profile)
    if type(profile) ~= "table" then return false end
    if type(profile.checked) == "table" and next(profile.checked) then return true end
    if type(profile.collapsedSections) == "table" and next(profile.collapsedSections) then return true end
    if type(profile.trackingSnapshot) == "table" and next(profile.trackingSnapshot) then return true end
    if type(profile.startAtSectionId) == "string" and profile.startAtSectionId ~= "" then return true end
    for _, key in ipairs(LEGACY_PREFERENCE_KEYS) do
        if profile[key] ~= nil then return true end
    end
    return false
end

local function CopyTable(source)
    local result = {}
    for key, value in pairs(source) do result[key] = value end
    return result
end

function Core.MigrateLegacyProfile(profile, destination)
    if type(destination) ~= "table" or not Core.HasLegacyProfilePayload(profile) then return false end

    if type(profile.checked) == "table" and next(profile.checked) then
        destination.checked = CopyTable(profile.checked)
    end
    if type(profile.collapsedSections) == "table" and next(profile.collapsedSections) then
        destination.collapsedSections = CopyTable(profile.collapsedSections)
    end
    if type(profile.startAtSectionId) == "string" and profile.startAtSectionId ~= "" then
        destination.startAtSectionId = profile.startAtSectionId
    end
    if type(profile.trackingSnapshot) == "table" and next(profile.trackingSnapshot) then
        destination.trackingSnapshot = CopyTable(profile.trackingSnapshot)
    end
    for _, key in ipairs(LEGACY_PREFERENCE_KEYS) do
        if profile[key] ~= nil then destination[key] = profile[key] end
    end

    profile.checked = nil
    profile.collapsedSections = nil
    profile.startAtSectionId = nil
    profile.trackingSnapshot = nil
    for _, key in ipairs(LEGACY_PREFERENCE_KEYS) do profile[key] = nil end
    return true
end

function Core.BuildCascadingConversionPlan(actions, getBalance)
    local ordered = {}
    local balances = {}
    local readBalance = type(getBalance) == "function" and getBalance or function() return 0 end
    for index, action in ipairs(type(actions) == "table" and actions or {}) do
        ordered[index] = action
        if balances[action.sourceTier] == nil then
            balances[action.sourceTier] = tonumber(readBalance(action.sourceTier)) or 0
        end
        if balances[action.destTier] == nil then
            balances[action.destTier] = tonumber(readBalance(action.destTier)) or 0
        end
    end
    table.sort(ordered, function(a, b)
        return (tonumber(a.sourceTier) or 0) < (tonumber(b.sourceTier) or 0)
    end)

    local plan = {}
    for _, action in ipairs(ordered) do
        local costPer = tonumber(action.costPer) or 0
        local gainPer = tonumber(action.gainPer) or 0
        local held = tonumber(balances[action.sourceTier]) or 0
        local count = costPer > 0 and math.floor(held / costPer) or 0
        if count > 0 then
            balances[action.sourceTier] = held - count * costPer
            balances[action.destTier] = (tonumber(balances[action.destTier]) or 0) + count * gainPer
            plan[#plan + 1] = { action = action, count = count }
        end
    end
    return plan
end

function Core.RunConversionPlan(plan, options)
    options = type(options) == "table" and options or {}
    local schedule = type(options.schedule) == "function"
        and options.schedule or function(_, callback) callback() end
    local isCancelled = type(options.isCancelled) == "function"
        and options.isCancelled or function() return false end
    local isActionValid = type(options.isActionValid) == "function"
        and options.isActionValid or function() return true end
    local getAvailableCount = type(options.getAvailableCount) == "function"
        and options.getAvailableCount or function() return 0 end
    local buy = type(options.buy) == "function" and options.buy or function() end
    local maxRetries = math.max(0, tonumber(options.maxRetries) or 3)
    local retryDelay = math.max(0, tonumber(options.retryDelay) or 0.2)
    local stepDelay = math.max(0, tonumber(options.stepDelay) or 0.4)
    local currentIndex = 1

    local function finish(kind, action)
        local callback = kind == "complete" and options.onComplete or options.onAbort
        if type(callback) == "function" then callback(kind, action) end
    end

    local runStep
    runStep = function(retryCount)
        if isCancelled() then return end

        local step = type(plan) == "table" and plan[currentIndex] or nil
        if not step then
            finish("complete")
            return
        end

        local action = step.action
        if type(action) ~= "table" or not isActionValid(action) then
            finish("invalid_action", action)
            return
        end

        local plannedCount = math.max(0, tonumber(step.count) or 0)
        local availableCount = math.max(0, tonumber(getAvailableCount(action)) or 0)
        local count = math.min(plannedCount, availableCount)
        if count <= 0 and retryCount < maxRetries then
            schedule(retryDelay, function() runStep(retryCount + 1) end)
            return
        end

        if count > 0 then buy(action, count) end
        currentIndex = currentIndex + 1
        schedule(stepDelay, function() runStep(0) end)
    end

    runStep(0)
end
