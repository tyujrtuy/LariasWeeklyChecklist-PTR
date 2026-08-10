-- Addon communications + update notice logic.
--
-- Message format:
-- - "Q" query
-- - "V\taddonVersion\tsheetVersion" version reply
--
-- Performance:
-- - Broadcast/query/reply are throttled (timers) to avoid chat spam.
local addonName = ...
local Addon = _G[addonName]
if not Addon then return end

Addon.COMM_PREFIX = Addon.COMM_PREFIX or "LWMC"

local BROADCAST_THROTTLE_SECONDS = 30
local REPLY_THROTTLE_SECONDS = 5

local broadcastTimerActive = false
local replyTimerActive = false
local queryTimerActive = false
local commFrame

local function RunLater(delay, callback)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, callback)
    else
        callback()
    end
end

-- Trim helper for metadata/version parsing.
local function Trim(s)
    return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- Version handling notes:
-- - We only care about prompting updates for "live" releases.
-- - Remote prerelease versions (e.g. "1.0.18-alpha") are ignored for prompting.
-- - Numeric comparison is required (string compare breaks: "1.0.10" vs "1.0.2").
local function NormalizeVersionString(v)
    v = Trim(v)
    -- Drop any trailing metadata after whitespace (e.g., "1.0.0 (foo)").
    v = v:gsub("%s.*$", "")
    -- Common tag prefix.
    if v:match("^[vV]%d") then
        v = v:sub(2)
    end
    return v
end

local function StripBuildAndPrerelease(v)
    v = NormalizeVersionString(v)
    if v == "" then return "" end
    -- Ignore build metadata and prerelease suffixes for ordering.
    v = v:match("^([^+]+)") or v
    local main = v:match("^(.-)%-") or v
    return main
end

local function IsLiveVersion(v)
    v = NormalizeVersionString(v)
    if v == "" then return false end
    v = v:match("^([^+]+)") or v
    return not v:find("%-")
end

local function ParseVersionNumbers(v)
    local main = StripBuildAndPrerelease(v)
    if main == "" then return nil end
    local nums = {}
    for n in tostring(main):gmatch("%d+") do
        nums[#nums + 1] = tonumber(n) or 0
    end
    if #nums == 0 then return nil end
    return nums
end

local function CompareVersions(versionA, versionB)
    -- Compare only numeric components of the *live* versions.
    -- (Prereleases are filtered out earlier, and build metadata is ignored.)
    local aNums = ParseVersionNumbers(versionA)
    local bNums = ParseVersionNumbers(versionB)
    if not aNums and not bNums then return 0 end
    if not aNums then return -1 end
    if not bNums then return 1 end

    local maxLen = (#aNums > #bNums) and #aNums or #bNums
    for i = 1, maxLen do
        local av = aNums[i] or 0
        local bv = bNums[i] or 0
        if av ~= bv then
            return (av > bv) and 1 or -1
        end
    end
    return 0
end

local function SerializeCommMessage(tbl)
    if type(tbl) ~= "table" then return nil end
    if tbl.t == "Q" then
        return "Q"
    elseif tbl.t == "V" then
        return table.concat({ "V", tostring(tbl.v or ""), tostring(tbl.sv or "") }, "\t")
    end
    return nil
end

local function DeserializeCommMessage(message)
    if type(message) ~= "string" then return nil end
    if message == "Q" then return { t = "Q" } end

    local msgType, version, sheetVersion = strsplit("\t", message)
    if msgType == "V" then
        return { t = "V", v = version or "", sv = sheetVersion or "" }
    end
    return nil
end

local function SafeSendCommMessage(msg, channel)
    -- Guarded send: comms should never hard-error.
    if not channel or channel == "" then return end
    if C_ChatInfo and C_ChatInfo.SendAddonMessage then
        pcall(C_ChatInfo.SendAddonMessage, Addon.COMM_PREFIX, msg, channel)
    elseif SendAddonMessage then
        pcall(SendAddonMessage, Addon.COMM_PREFIX, msg, channel)
    end
end

local function GetGroupChannel()
    -- Prefer instance chat when applicable; otherwise raid/party.
    local instCat = (LE_PARTY_CATEGORY_INSTANCE ~= nil) and LE_PARTY_CATEGORY_INSTANCE or 2
    if IsInGroup and IsInGroup(instCat) then return "INSTANCE_CHAT" end
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    return nil
end

local function GetAddonVersion(name)
    -- Read version from addon metadata.
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return tostring(C_AddOns.GetAddOnMetadata(name, "Version") or "")
    end
    if GetAddOnMetadata then
        return tostring(GetAddOnMetadata(name, "Version") or "")
    end
    return ""
end

local LOCALE_REGISTRY_KEY_COMMS = Addon.LOCALE_REGISTRY_KEY

local function GetMySheetVersion()
    local reg = _G[LOCALE_REGISTRY_KEY_COMMS]
    return (reg and type(reg.sheet_version) == "string" and reg.sheet_version) or ""
end

-- Extract the last integer found in a freeform sheet-version string.
-- e.g. "Week 5 - Apr 14" → 5,  "Pre-Season Week 2" → 2
local function SheetVersionToNum(s)
    local n = 0
    for m in tostring(s or ""):gmatch("%d+") do n = tonumber(m) or n end
    return n
end

local function IsStaleSheetVersionAfterReset(mySheetVersion, remoteSheetVersion)
    local myNum = SheetVersionToNum(mySheetVersion)
    local remoteNum = SheetVersionToNum(remoteSheetVersion)
    return myNum > 0 and myNum <= 5 and (remoteNum - myNum) >= 10
end

function Addon:GetMyVersion()
    -- Cached in CommsOnEnable.
    return self._myVersion or ""
end

function Addon:ShouldShowSheetUpdateNotice()
    -- Returns true when a group/guild member has broadcast a newer sheet version.
    local database = self:EnsureDB()
    local myVer = self:GetMyVersion()
    if myVer == "" or not IsLiveVersion(myVer) then return false end
    local newestSV = tostring(database._newestSeenRemoteSheetVersion or "")
    if newestSV == "" then return false end
    if IsStaleSheetVersionAfterReset(GetMySheetVersion(), newestSV) then
        database._newestSeenRemoteSheetVersion = ""
        return false
    end
    return SheetVersionToNum(newestSV) > SheetVersionToNum(GetMySheetVersion())
end

function Addon:ShouldShowUpdateNotice()
    -- Update notice is driven by the newest *live* version seen on comms.
    local database = self:EnsureDB()
    local myVersion = self:GetMyVersion()
    -- If the user is on a prerelease build, don't nag about updates.
    if myVersion == "" or not IsLiveVersion(myVersion) then return false end
    local newestSeenVersion = tostring(database._newestSeenRemoteVersion or "")
    if newestSeenVersion == "" or myVersion == "" then return false end
    if CompareVersions(newestSeenVersion, myVersion) <= 0 then return false end
    return true
end

function Addon:BroadcastVersion(force)
    -- Broadcast our version to group/guild.
    -- force=true bypasses the broadcast throttle.
    if not force then
        if broadcastTimerActive then
            return
        end
    end

    local myVersion = self:GetMyVersion()
    if myVersion == "" then return end
    local payloadStructured = SerializeCommMessage({ t = "V", v = myVersion, sv = GetMySheetVersion() })
    if not payloadStructured then return end

    local channel = GetGroupChannel()
    if channel then
        SafeSendCommMessage(payloadStructured, channel)
    end
    if IsInGuild and IsInGuild() then
        SafeSendCommMessage(payloadStructured, "GUILD")
    end

    if not force then
        broadcastTimerActive = true
        RunLater(BROADCAST_THROTTLE_SECONDS, function() broadcastTimerActive = false end)
    end
end

function Addon:RequestVersions(force)
    -- Ask others to reply with their version (they reply after a small random delay).
    if not force then
        if queryTimerActive then
            return
        end
    end

    local payloadStructured = SerializeCommMessage({ t = "Q" })
    if not payloadStructured then return end

    local channel = GetGroupChannel()
    if channel then
        SafeSendCommMessage(payloadStructured, channel)
    end
    if IsInGuild and IsInGuild() then
        SafeSendCommMessage(payloadStructured, "GUILD")
    end

    if not force then
        queryTimerActive = true
        RunLater(BROADCAST_THROTTLE_SECONDS, function() queryTimerActive = false end)
    end
end

function Addon:OnAddonMessage(prefix, message, sender)
    -- Native addon-message entry point.
    -- We ignore unknown messages to avoid legacy/backcompat complexity.
    if prefix ~= self.COMM_PREFIX then return end
    if type(message) ~= "string" then return end

    local decoded = DeserializeCommMessage(message)
    if not decoded then
        return
    end

    if decoded.t == "Q" then
        -- Query received: reply with version (throttled; delay jitter to avoid bursts).
        if replyTimerActive then
            return
        end

        replyTimerActive = true
        RunLater(REPLY_THROTTLE_SECONDS, function() replyTimerActive = false end)

        local delay = (math.random() * 2.0)
        RunLater(delay, function()
            self:BroadcastVersion(true)
        end)
        return
    end

    if decoded.t ~= "V" then
        return
    end

    local remoteVersion = NormalizeVersionString(decoded.v)
    if remoteVersion == "" then return end

    -- Only consider live (non-prerelease) remote versions for update prompting.
    if not IsLiveVersion(remoteVersion) then
        return
    end

    local myVersion = self:GetMyVersion()
    if myVersion == "" then return end

    if sender and sender ~= "" and UnitName then
        -- Ignore our own messages ("player" name can be realm-qualified).
        local me = UnitName("player")
        if me and me ~= "" then
            local senderName = sender
            if Ambiguate then
                senderName = Ambiguate(sender, "none")
            end
            if senderName == me then
                return
            end
        end
    end

    if CompareVersions(remoteVersion, myVersion) > 0 then
        local database = self:EnsureDB()
        local newestSeenVersion = tostring(database._newestSeenRemoteVersion or "")
        if newestSeenVersion == "" or CompareVersions(remoteVersion, newestSeenVersion) > 0 then
            database._newestSeenRemoteVersion = remoteVersion
            database._newestSeenRemoteSender = tostring(sender or "")
            -- Immediately refresh the status banner so the update notice appears.
            if Addon.UpdateStatusBanner then Addon:UpdateStatusBanner() end
        end
    end

    -- Track remote sheet version for spreadsheet-update notices.
    local remoteSV = (type(decoded.sv) == "string" and decoded.sv ~= "") and decoded.sv or nil
    if remoteSV then
        local database = self:EnsureDB()
        local mySV = GetMySheetVersion()
        if not IsStaleSheetVersionAfterReset(mySV, remoteSV)
        and SheetVersionToNum(remoteSV) > SheetVersionToNum(mySV) then
            local storedSV = tostring(database._newestSeenRemoteSheetVersion or "")
            if storedSV == "" or SheetVersionToNum(remoteSV) > SheetVersionToNum(storedSV) then
                database._newestSeenRemoteSheetVersion = remoteSV
                if Addon.UpdateStatusBanner then Addon:UpdateStatusBanner() end
            end
        end
    end
end

function Addon:OnCommReceived(prefix, messageText, _, sender)
    -- Backward-compatible wrapper for callers that still use the old shape.
    self:OnAddonMessage(prefix, messageText, sender)
end

function Addon:CommsOnEnable()
    -- Called from Addon:OnEnable.
    self._myVersion = GetAddonVersion(addonName)

    -- Auto-clear a stale _newestSeenRemoteVersion if our version has caught up
    -- (e.g. the user installed an update since the last session, or a dev build
    -- wrote a higher version string that is now obsolete).  This prevents the
    -- update notice from firing forever on a version that is already installed.
    local database = self:EnsureDB()
    local myVer    = self._myVersion
    if myVer ~= "" and IsLiveVersion(myVer) then
        local stored = tostring(database._newestSeenRemoteVersion or "")
        if stored ~= "" and CompareVersions(stored, myVer) <= 0 then
            database._newestSeenRemoteVersion = ""
            database._newestSeenRemoteSender  = ""
        end
    end

    local mySheetVersion = GetMySheetVersion()
    local storedSheetVersion = tostring(database._newestSeenRemoteSheetVersion or "")
    if storedSheetVersion ~= "" and IsStaleSheetVersionAfterReset(mySheetVersion, storedSheetVersion) then
        database._newestSeenRemoteSheetVersion = ""
    end

    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, self.COMM_PREFIX)
    elseif RegisterAddonMessagePrefix then
        pcall(RegisterAddonMessagePrefix, self.COMM_PREFIX)
    end

    if not commFrame then
        commFrame = CreateFrame("Frame")
        commFrame:RegisterEvent("CHAT_MSG_ADDON")
        commFrame:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
            Addon:OnAddonMessage(prefix, message, sender)
        end)
    end

    self:BroadcastVersion(true)
end
