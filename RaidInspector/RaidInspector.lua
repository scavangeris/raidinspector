local addonName = ...

RaidInspector = RaidInspector or {}
RaidInspectorDB = RaidInspectorDB or {}
RaidInspectorBridgeInbox = RaidInspectorBridgeInbox or {}

local addon = RaidInspector
addon.name = addonName or "RaidInspector"
addon.version = "0.3.0-alpha"

local events = CreateFrame("Frame")
local FRESHNESS_TTL_SECONDS = 30 * 60

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Raid Inspector|r: " .. tostring(msg))
end

local function Trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function GetNow()
    return time()
end

local function MakePlayerKey(name, realm)
    return string.lower(name .. "-" .. realm)
end

local function EnsureTable(tbl, key, defaultValue)
    if tbl[key] == nil then
        tbl[key] = defaultValue
    end
end

local function CopyTable(src)
    if type(src) ~= "table" then
        return src
    end

    local out = {}
    local k
    for k in pairs(src) do
        if type(src[k]) == "table" then
            out[k] = CopyTable(src[k])
        else
            out[k] = src[k]
        end
    end
    return out
end

local function ParseKey(key)
    local name, realm = string.match(key or "", "^(.+)%-(.+)$")
    return name, realm
end

function addon:InitDatabase()
    EnsureTable(RaidInspectorDB, "meta", {})
    EnsureTable(RaidInspectorDB, "settings", {})
    EnsureTable(RaidInspectorDB.settings, "window", {})
    EnsureTable(RaidInspectorDB.settings.window, "point", "CENTER")
    EnsureTable(RaidInspectorDB.settings.window, "x", 0)
    EnsureTable(RaidInspectorDB.settings.window, "y", 0)

    EnsureTable(RaidInspectorDB, "state", {})
    EnsureTable(RaidInspectorDB.state, "nextRequestId", 1)

    EnsureTable(RaidInspectorDB, "requests", {})
    EnsureTable(RaidInspectorDB, "results", {})

    RaidInspectorDB.meta.schemaVersion = 1
    RaidInspectorDB.meta.lastLoadedAt = GetNow()
    EnsureTable(RaidInspectorDB.meta, "lastImportedBridgeGeneratedAt", 0)
end

function addon:InitBridgeInbox()
    EnsureTable(RaidInspectorBridgeInbox, "schemaVersion", 1)
    EnsureTable(RaidInspectorBridgeInbox, "generatedAt", 0)
    EnsureTable(RaidInspectorBridgeInbox, "lastConsumedAt", 0)
    EnsureTable(RaidInspectorBridgeInbox, "results", {})
end

function addon:GetCounts()
    local queued, ready, errorCount = 0, 0, 0
    local i

    for i = 1, #RaidInspectorDB.requests do
        local req = RaidInspectorDB.requests[i]
        local result = RaidInspectorDB.results[req.key]
        if req.status == "error" then
            errorCount = errorCount + 1
        elseif result then
            ready = ready + 1
        else
            queued = queued + 1
        end
    end

    return queued, ready, errorCount
end

function addon:GetFreshnessCounts(ttlSeconds)
    local fresh, stale = 0, 0
    local now = GetNow()
    local i

    for i = 1, #RaidInspectorDB.requests do
        local req = RaidInspectorDB.requests[i]
        local result = RaidInspectorDB.results[req.key]
        if result then
            local updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
            if updatedAt > 0 and (now - updatedAt) <= ttlSeconds then
                fresh = fresh + 1
            else
                stale = stale + 1
            end
        end
    end

    return fresh, stale
end

function addon:GetBridgeInboxStats()
    addon:InitBridgeInbox()
    local count = 0
    local _
    for _ in pairs(RaidInspectorBridgeInbox.results) do
        count = count + 1
    end
    return {
        generatedAt = tonumber(RaidInspectorBridgeInbox.generatedAt) or 0,
        lastConsumedAt = tonumber(RaidInspectorBridgeInbox.lastConsumedAt) or 0,
        resultCount = count,
        lastImportedBridgeGeneratedAt = tonumber(RaidInspectorDB.meta.lastImportedBridgeGeneratedAt) or 0,
    }
end

function addon:QueueInspect(name, realm)
    local normalizedName = Trim(name)
    local normalizedRealm = Trim(realm)

    if normalizedName == "" then
        Print("missing player name. usage: /ri inspect <name> <realm>")
        return
    end

    if normalizedRealm == "" then
        normalizedRealm = GetCVar("realmName") or ""
    end

    if normalizedRealm == "" then
        Print("missing realm. usage: /ri inspect <name> <realm>")
        return
    end

    local key = MakePlayerKey(normalizedName, normalizedRealm)
    local id = RaidInspectorDB.state.nextRequestId

    table.insert(RaidInspectorDB.requests, {
        id = id,
        name = normalizedName,
        realm = normalizedRealm,
        key = key,
        status = "queued",
        requestedAt = GetNow(),
        updatedAt = GetNow(),
    })

    RaidInspectorDB.state.nextRequestId = id + 1
    Print("queued: " .. normalizedName .. "-" .. normalizedRealm .. " (#" .. id .. ")")

    if addon.RefreshMainWindow then
        addon:RefreshMainWindow()
    end
end

function addon:QueueTarget()
    if not UnitExists("target") then
        Print("no target selected")
        return
    end

    local name = UnitName("target")
    local realm = GetRealmName()

    if not name or name == "" then
        Print("target has no valid name")
        return
    end

    addon:QueueInspect(name, realm)
end

function addon:ApplyBridgeResult(key, payload)
    if type(payload) ~= "table" then
        return false
    end

    local nameFromKey, realmFromKey = ParseKey(key)
    local normalizedKey = string.lower(key)

    local result = {}
    result.name = payload.name or nameFromKey or "Unknown"
    result.realm = payload.realm or realmFromKey or "Unknown"
    result.class = payload.class
    result.spec = payload.spec
    result.guild = payload.guild
    result.level = payload.level
    result.items = CopyTable(payload.items or {})
    result.enchants = CopyTable(payload.enchants or {})
    result.gems = CopyTable(payload.gems or {})
    result.gearScore = payload.gearScore
    result.gearScoreSource = payload.gearScoreSource
    result.error = payload.error
    result.source = payload.source or "bridge"
    result.raw = CopyTable(payload.raw)
    result.fetchedAt = tonumber(payload.fetchedAt) or GetNow()
    result.updatedAt = tonumber(payload.updatedAt) or GetNow()

    RaidInspectorDB.results[normalizedKey] = result

    local i
    for i = 1, #RaidInspectorDB.requests do
        local req = RaidInspectorDB.requests[i]
        if req.key == normalizedKey then
            req.status = result.error and "error" or "ready"
            req.updatedAt = GetNow()
        end
    end

    return true
end

function addon:ConsumeBridgeInbox(silent, force)
    addon:InitBridgeInbox()

    if type(RaidInspectorBridgeInbox.results) ~= "table" or next(RaidInspectorBridgeInbox.results) == nil then
        return 0
    end

    local generatedAt = tonumber(RaidInspectorBridgeInbox.generatedAt) or 0
    local lastImported = tonumber(RaidInspectorDB.meta.lastImportedBridgeGeneratedAt) or 0
    if not force and generatedAt > 0 and generatedAt <= lastImported then
        return 0
    end

    local imported = 0
    local key
    for key in pairs(RaidInspectorBridgeInbox.results) do
        local payload = RaidInspectorBridgeInbox.results[key]
        if addon:ApplyBridgeResult(string.lower(key), payload) then
            imported = imported + 1
        end
    end

    RaidInspectorBridgeInbox.lastConsumedAt = GetNow()
    if generatedAt > 0 then
        RaidInspectorDB.meta.lastImportedBridgeGeneratedAt = generatedAt
    else
        RaidInspectorDB.meta.lastImportedBridgeGeneratedAt = GetNow()
    end

    if imported > 0 and not silent then
        Print("sync complete: imported " .. imported .. " result(s)")
    end

    addon:RefreshMainWindow()
    return imported
end

function addon:BuildRows(container, rowCount)
    container.rows = container.rows or {}
    local i

    for i = 1, rowCount do
        local row = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetJustifyH("LEFT")
        row:SetWidth(560)
        row:SetHeight(14)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * 14)
        row:SetText("")
        container.rows[i] = row
    end
end

function addon:CreateMainWindow()
    if addon.ui and addon.ui.frame then
        return
    end

    addon.ui = addon.ui or {}

    local f = CreateFrame("Frame", "RaidInspectorMainFrame", UIParent)
    f:SetWidth(620)
    f:SetHeight(330)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        local point, _, _, x, y = self:GetPoint(1)
        self:StopMovingOrSizing()
        RaidInspectorDB.settings.window.point = point or "CENTER"
        RaidInspectorDB.settings.window.x = math.floor(x or 0)
        RaidInspectorDB.settings.window.y = math.floor(y or 0)
    end)

    f:SetPoint(
        RaidInspectorDB.settings.window.point,
        UIParent,
        RaidInspectorDB.settings.window.point,
        RaidInspectorDB.settings.window.x,
        RaidInspectorDB.settings.window.y
    )

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
    title:SetText("Raid Inspector")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Queue + bridge results view")

    local closeButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    statusText:SetJustifyH("LEFT")
    statusText:SetWidth(580)
    statusText:SetText("")

    local helpText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    helpText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -8)
    helpText:SetWidth(580)
    helpText:SetJustifyH("LEFT")
    helpText:SetText("/ri inspect <name> <realm>  |  /ri inspecttarget  |  /ri sync")

    local rowsContainer = CreateFrame("Frame", nil, f)
    rowsContainer:SetPoint("TOPLEFT", helpText, "BOTTOMLEFT", 0, -10)
    rowsContainer:SetWidth(580)
    rowsContainer:SetHeight(220)

    addon:BuildRows(rowsContainer, 14)

    addon.ui.frame = f
    addon.ui.statusText = statusText
    addon.ui.rows = rowsContainer.rows

    f:Hide()
end

function addon:RefreshMainWindow()
    if not addon.ui or not addon.ui.frame then
        return
    end

    local queued, ready, errorCount = addon:GetCounts()
    local fresh, stale = addon:GetFreshnessCounts(FRESHNESS_TTL_SECONDS)
    addon.ui.statusText:SetText(
        "Queue: " .. queued .. "  |  Ready: " .. ready .. "  |  Fresh: " .. fresh .. "  |  Stale: " .. stale .. "  |  Errors: " .. errorCount
    )

    local rows = addon.ui.rows
    local total = #RaidInspectorDB.requests
    local maxRows = #rows
    local startIndex = total - maxRows + 1
    local rowIndex = 1

    if startIndex < 1 then
        startIndex = 1
    end

    local now = GetNow()
    local i
    for i = startIndex, total do
        local req = RaidInspectorDB.requests[i]
        local result = RaidInspectorDB.results[req.key]
        local state = req.status or "queued"

        if state ~= "error" and result then
            state = "ready"
        end

        local gsText = ""
        if result and result.gearScore then
            gsText = "  GS=" .. tostring(result.gearScore)
        end

        local ageText = ""
        if result then
            local updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
            if updatedAt > 0 then
                local ageMinutes = math.floor(math.max(0, now - updatedAt) / 60)
                ageText = "  age=" .. tostring(ageMinutes) .. "m"
            end
        end

        rows[rowIndex]:SetText(
            "#" .. req.id .. "  " .. req.name .. "-" .. req.realm .. "  [" .. state .. "]" .. gsText .. ageText
        )
        rowIndex = rowIndex + 1
    end

    for i = rowIndex, maxRows do
        rows[i]:SetText("")
    end
end

function addon:ToggleWindow(forceShow)
    if not addon.ui or not addon.ui.frame then
        return
    end

    if forceShow == true then
        addon.ui.frame:Show()
    elseif forceShow == false then
        addon.ui.frame:Hide()
    elseif addon.ui.frame:IsShown() then
        addon.ui.frame:Hide()
    else
        addon.ui.frame:Show()
    end

    addon:RefreshMainWindow()
end

function addon:HandleInspectCommand(args)
    if args == "" then
        Print("usage: /ri inspect <name> <realm>")
        return
    end

    local arg1, rest = string.match(args, "^(%S+)%s*(.-)$")
    if not arg1 then
        Print("usage: /ri inspect <name> <realm>")
        return
    end

    local name = arg1
    local realm = rest or ""

    local splitName, splitRealm = string.match(name, "^([^%-]+)%-(.+)$")
    if splitName and splitRealm and realm == "" then
        name = splitName
        realm = splitRealm
    end

    addon:QueueInspect(name, realm)
end

function addon:PrintStatus()
    local queued, ready, errorCount = addon:GetCounts()
    local fresh, stale = addon:GetFreshnessCounts(FRESHNESS_TTL_SECONDS)
    local bridge = addon:GetBridgeInboxStats()
    Print("schema v" .. tostring(RaidInspectorDB.meta.schemaVersion))
    Print("requests: " .. tostring(#RaidInspectorDB.requests))
    Print("queued=" .. queued .. ", ready=" .. ready .. ", fresh=" .. fresh .. ", stale=" .. stale .. ", errors=" .. errorCount)
    Print("bridge inbox: count=" .. bridge.resultCount .. ", generatedAt=" .. bridge.generatedAt .. ", lastConsumedAt=" .. bridge.lastConsumedAt)
    Print("bridge import marker: lastImportedGeneratedAt=" .. bridge.lastImportedBridgeGeneratedAt)
    Print("bridge status: close WoW before running bridge writer, then relog/reload")
end

function addon:ClearQueue()
    RaidInspectorDB.requests = {}
    RaidInspectorDB.state.nextRequestId = 1
    Print("queue cleared")
    addon:RefreshMainWindow()
end

function addon:OnAddonLoaded(loadedName)
    if loadedName ~= addon.name then
        return
    end

    addon:InitDatabase()
    addon:InitBridgeInbox()
    addon:CreateMainWindow()
end

function addon:OnPlayerLogin()
    local imported = addon:ConsumeBridgeInbox(true)
    Print("loaded (" .. addon.version .. ")")
    if imported > 0 then
        Print("imported " .. imported .. " bridge result(s) on login")
    end
    Print("type /ri help for commands")
    addon:RefreshMainWindow()
end

SLASH_RAIDINSPECTOR1 = "/ri"
SLASH_RAIDINSPECTOR2 = "/raidinspector"
SlashCmdList["RAIDINSPECTOR"] = function(message)
    local raw = Trim(message or "")
    local command, args = string.match(raw, "^(%S+)%s*(.-)$")
    command = string.lower(command or "")
    args = args or ""

    if command == "" or command == "help" then
        Print("commands:")
        Print("/ri show - open main window")
        Print("/ri hide - close main window")
        Print("/ri inspect <name> <realm> - queue character")
        Print("/ri inspect <name-realm> - queue character")
        Print("/ri inspecttarget - queue current target")
        Print("/ri sync - import bridge inbox results")
        Print("/ri forcesync - re-import bridge inbox ignoring generatedAt")
        Print("/ri status - show queue summary")
        Print("/ri clearqueue - remove all queued entries")
        return
    end

    if command == "show" then
        addon:ToggleWindow(true)
        return
    end

    if command == "hide" then
        addon:ToggleWindow(false)
        return
    end

    if command == "toggle" then
        addon:ToggleWindow()
        return
    end

    if command == "inspect" then
        addon:HandleInspectCommand(args)
        return
    end

    if command == "inspecttarget" then
        addon:QueueTarget()
        return
    end

    if command == "sync" then
        local imported = addon:ConsumeBridgeInbox(false, false)
        if imported == 0 then
            Print("sync complete: no new bridge results found")
        end
        return
    end

    if command == "forcesync" then
        local imported = addon:ConsumeBridgeInbox(false, true)
        if imported == 0 then
            Print("force sync complete: no bridge results found")
        end
        return
    end

    if command == "status" then
        addon:PrintStatus()
        addon:RefreshMainWindow()
        return
    end

    if command == "clearqueue" then
        addon:ClearQueue()
        return
    end

    if command == "reload" then
        ReloadUI()
        return
    end

    Print("unknown command. use /ri help")
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        addon:OnAddonLoaded(...)
    elseif event == "PLAYER_LOGIN" then
        addon:OnPlayerLogin()
    end
end)
