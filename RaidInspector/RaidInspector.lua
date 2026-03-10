local addonName = ...

RaidInspector = RaidInspector or {}
RaidInspectorDB = RaidInspectorDB or {}
RaidInspectorBridgeInbox = RaidInspectorBridgeInbox or {}

local addon = RaidInspector
addon.name = addonName or "RaidInspector"
addon.version = "0.10.1-alpha"

local events = CreateFrame("Frame")
local FRESHNESS_TTL_SECONDS = 30 * 60
local RAID_HISTORY_RETENTION_SECONDS = 30 * 24 * 60 * 60
local INSPECT_THROTTLE_SECONDS = 2
local INSPECT_TIMEOUT_SECONDS = 8
local ACHIEVEMENT_COMPARE_THROTTLE_SECONDS = 2
local ACHIEVEMENT_COMPARE_TIMEOUT_SECONDS = 8
local REPORT_SNAPSHOT_LIMIT = 200
local OVERVIEW_ROW_HEIGHT = 18
local DETAIL_ROW_HEIGHT = 18
local WINDOW_WIDTH = 1000
local WINDOW_HEIGHT = 500
local PANEL_SIDE_MARGIN = 24
local RIGHT_PANEL_X = 474

local RAID_ACHIEVEMENT_KEYS = { "icc10", "icc25", "toc10", "toc25", "rs10", "rs25" }
local RAID_CATEGORY_MATCHERS = {
    icc10 = { raid = "icecrown citadel", size = "10" },
    icc25 = { raid = "icecrown citadel", size = "25" },
    toc10 = { raid = "trial of the crusader", altRaid = "trial of the grand crusader", size = "10" },
    toc25 = { raid = "trial of the crusader", altRaid = "trial of the grand crusader", size = "25" },
    rs10 = { raid = "ruby sanctum", size = "10" },
    rs25 = { raid = "ruby sanctum", size = "25" },
}

local SORT_MODES = { "recent", "gs", "issues", "name" }
local FILTER_MODES = { "all", "snapshot", "ready", "queued", "issues" }
local ITEM_LIST_FILTER_MODES = { "all", "issues", "missing-enchant", "missing-gems" }
local BUTTON_MODES = { "advanced", "easy" }

local BUTTON_MODE_LABELS = {
    advanced = "Advanced",
    easy = "Easy",
}

local SORT_LABELS = {
    recent = "Recent",
    gs = "GS",
    issues = "Issues",
    name = "Name",
}

local FILTER_LABELS = {
    all = "All",
    snapshot = "Snapshot",
    ready = "Ready",
    queued = "Queued",
    issues = "Issues",
}

local ITEM_LIST_FILTER_LABELS = {
    all = "All Slots",
    issues = "Issues Only",
    ["missing-enchant"] = "Missing Enchant",
    ["missing-gems"] = "Missing Gems",
}

local SLOT_ORDER = {
    "HeadSlot",
    "NeckSlot",
    "ShoulderSlot",
    "BackSlot",
    "ChestSlot",
    "WristSlot",
    "HandsSlot",
    "WaistSlot",
    "LegsSlot",
    "FeetSlot",
    "Finger0Slot",
    "Finger1Slot",
    "Trinket0Slot",
    "Trinket1Slot",
    "MainHandSlot",
    "SecondaryHandSlot",
    "RangedSlot",
}

local INSPECT_SLOT_MAP = {
    { id = 1, slot = "HeadSlot" },
    { id = 2, slot = "NeckSlot" },
    { id = 3, slot = "ShoulderSlot" },
    { id = 15, slot = "BackSlot" },
    { id = 5, slot = "ChestSlot" },
    { id = 9, slot = "WristSlot" },
    { id = 10, slot = "HandsSlot" },
    { id = 6, slot = "WaistSlot" },
    { id = 7, slot = "LegsSlot" },
    { id = 8, slot = "FeetSlot" },
    { id = 11, slot = "Finger0Slot" },
    { id = 12, slot = "Finger1Slot" },
    { id = 13, slot = "Trinket0Slot" },
    { id = 14, slot = "Trinket1Slot" },
    { id = 16, slot = "MainHandSlot" },
    { id = 17, slot = "SecondaryHandSlot" },
    { id = 18, slot = "RangedSlot" },
}

local SLOT_LABELS = {
    HeadSlot = "Head",
    NeckSlot = "Neck",
    ShoulderSlot = "Shoulder",
    BackSlot = "Back",
    ChestSlot = "Chest",
    WristSlot = "Wrist",
    HandsSlot = "Hands",
    WaistSlot = "Waist",
    LegsSlot = "Legs",
    FeetSlot = "Feet",
    Finger0Slot = "Ring 1",
    Finger1Slot = "Ring 2",
    Trinket0Slot = "Trinket 1",
    Trinket1Slot = "Trinket 2",
    MainHandSlot = "Main Hand",
    SecondaryHandSlot = "Off Hand",
    RangedSlot = "Ranged/Relic",
}

local SLOT_ALIASES = {
    head = "HeadSlot",
    headslot = "HeadSlot",
    neck = "NeckSlot",
    neckslot = "NeckSlot",
    shoulder = "ShoulderSlot",
    shoulders = "ShoulderSlot",
    shoulderslot = "ShoulderSlot",
    back = "BackSlot",
    cloak = "BackSlot",
    backslot = "BackSlot",
    chest = "ChestSlot",
    chestslot = "ChestSlot",
    wrist = "WristSlot",
    wrists = "WristSlot",
    wristslot = "WristSlot",
    hands = "HandsSlot",
    handslot = "HandsSlot",
    handsslot = "HandsSlot",
    gloves = "HandsSlot",
    gloveslot = "HandsSlot",
    waist = "WaistSlot",
    beltslot = "WaistSlot",
    waistslot = "WaistSlot",
    legs = "LegsSlot",
    legslot = "LegsSlot",
    legsslot = "LegsSlot",
    feet = "FeetSlot",
    footslot = "FeetSlot",
    feetslot = "FeetSlot",
    boots = "FeetSlot",
    finger0 = "Finger0Slot",
    finger0slot = "Finger0Slot",
    finger1 = "Finger1Slot",
    finger1slot = "Finger1Slot",
    trinket0 = "Trinket0Slot",
    trinket0slot = "Trinket0Slot",
    trinket1 = "Trinket1Slot",
    trinket1slot = "Trinket1Slot",
    mainhand = "MainHandSlot",
    mainhandslot = "MainHandSlot",
    secondaryhand = "SecondaryHandSlot",
    offhand = "SecondaryHandSlot",
    offhandslot = "SecondaryHandSlot",
    secondaryhandslot = "SecondaryHandSlot",
    ranged = "RangedSlot",
    rangedslot = "RangedSlot",
    relic = "RangedSlot",
}

local ENCHANTABLE_SLOTS = {
    HeadSlot = true,
    ShoulderSlot = true,
    BackSlot = true,
    ChestSlot = true,
    WristSlot = true,
    HandsSlot = true,
    LegsSlot = true,
    FeetSlot = true,
    MainHandSlot = true,
    SecondaryHandSlot = true,
    RangedSlot = true,
}

local OPTIONAL_ENCHANT_SLOTS = {
    SecondaryHandSlot = true,
    RangedSlot = true,
}

local GS_SCALE = 1.8618
local GS_FORMULA_A = {
    [4] = { A = 91.45, B = 0.65 },
    [3] = { A = 81.375, B = 0.8125 },
    [2] = { A = 73.0, B = 1.0 },
}
local GS_FORMULA_B = {
    [4] = { A = 26.0, B = 1.2 },
    [3] = { A = 0.75, B = 1.8 },
    [2] = { A = 8.0, B = 2.0 },
    [1] = { A = 0.0, B = 2.25 },
}
local GS_SLOT_CONFIG = {
    HeadSlot = { slotMod = 1.0, enchantable = true },
    NeckSlot = { slotMod = 0.5625, enchantable = false },
    ShoulderSlot = { slotMod = 0.75, enchantable = true },
    BackSlot = { slotMod = 0.5625, enchantable = true },
    ChestSlot = { slotMod = 1.0, enchantable = true },
    WristSlot = { slotMod = 0.5625, enchantable = true },
    HandsSlot = { slotMod = 0.75, enchantable = true },
    WaistSlot = { slotMod = 0.75, enchantable = false },
    LegsSlot = { slotMod = 1.0, enchantable = true },
    FeetSlot = { slotMod = 0.75, enchantable = true },
    Finger0Slot = { slotMod = 0.5625, enchantable = false },
    Finger1Slot = { slotMod = 0.5625, enchantable = false },
    Trinket0Slot = { slotMod = 0.5625, enchantable = false },
    Trinket1Slot = { slotMod = 0.5625, enchantable = false },
    MainHandSlot = { slotMod = 1.0, enchantable = true },
    SecondaryHandSlot = { slotMod = 1.0, enchantable = false },
    RangedSlot = { slotMod = 0.3164, enchantable = false },
}

local GS_EQUIPLOC_CONFIG = {
    INVTYPE_RELIC = { slotMod = 0.3164, enchantable = false },
    INVTYPE_TRINKET = { slotMod = 0.5625, enchantable = false },
    INVTYPE_2HWEAPON = { slotMod = 2.0, enchantable = true },
    INVTYPE_WEAPONMAINHAND = { slotMod = 1.0, enchantable = true },
    INVTYPE_WEAPONOFFHAND = { slotMod = 1.0, enchantable = true },
    INVTYPE_RANGED = { slotMod = 0.3164, enchantable = true },
    INVTYPE_THROWN = { slotMod = 0.3164, enchantable = false },
    INVTYPE_RANGEDRIGHT = { slotMod = 0.3164, enchantable = false },
    INVTYPE_SHIELD = { slotMod = 1.0, enchantable = true },
    INVTYPE_WEAPON = { slotMod = 1.0, enchantable = true },
    INVTYPE_HOLDABLE = { slotMod = 1.0, enchantable = false },
    INVTYPE_HEAD = { slotMod = 1.0, enchantable = true },
    INVTYPE_NECK = { slotMod = 0.5625, enchantable = false },
    INVTYPE_SHOULDER = { slotMod = 0.75, enchantable = true },
    INVTYPE_CHEST = { slotMod = 1.0, enchantable = true },
    INVTYPE_ROBE = { slotMod = 1.0, enchantable = true },
    INVTYPE_WAIST = { slotMod = 0.75, enchantable = false },
    INVTYPE_LEGS = { slotMod = 1.0, enchantable = true },
    INVTYPE_FEET = { slotMod = 0.75, enchantable = true },
    INVTYPE_WRIST = { slotMod = 0.5625, enchantable = true },
    INVTYPE_HAND = { slotMod = 0.75, enchantable = true },
    INVTYPE_FINGER = { slotMod = 0.5625, enchantable = false },
    INVTYPE_CLOAK = { slotMod = 0.5625, enchantable = true },
}

local function GetFauxScrollOffset(scrollFrame)
    if not scrollFrame then
        return 0
    end
    if FauxScrollFrame_GetOffset then
        return tonumber(FauxScrollFrame_GetOffset(scrollFrame)) or 0
    end
    return 0
end

local function SetFauxScrollOffset(scrollFrame, offset, lineHeight)
    if not scrollFrame then
        return
    end
    local normalized = math.max(0, tonumber(offset) or 0)
    if FauxScrollFrame_SetOffset then
        FauxScrollFrame_SetOffset(scrollFrame, normalized)
    else
        local row = tonumber(lineHeight) or 14
        scrollFrame:SetVerticalScroll(normalized * row)
    end
end

local function ColorText(text, color)
    return "|cff" .. color .. tostring(text) .. "|r"
end

local function EscapeChatMessage(text)
    local value = tostring(text or "")
    return string.gsub(value, "|", "||")
end

local function SetFontStringBold(fontString, enabled)
    if not fontString or not fontString.GetFont or not fontString.SetFont then
        return
    end

    local fontName, fontHeight = fontString:GetFont()
    if not fontName or not fontHeight then
        return
    end

    if enabled then
        fontString:SetFont(fontName, fontHeight, "OUTLINE")
    else
        fontString:SetFont(fontName, fontHeight, "")
    end
end

local GS_LITE_QUALITY = {
    [1000] = {
        Red = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Green = { A = 0.55, B = 0, C = 0.00045, D = 1 },
        Blue = { A = 0.55, B = 0, C = 0.00045, D = 1 },
    },
    [2000] = {
        Red = { A = 1.00, B = 1000, C = 0.00088, D = -1 },
        Green = { A = 1.00, B = 0, C = 0.0, D = 0 },
        Blue = { A = 1.00, B = 1000, C = 0.001, D = -1 },
    },
    [3000] = {
        Red = { A = 0.12, B = 2000, C = 0.00012, D = -1 },
        Green = { A = 1.00, B = 2000, C = 0.00050, D = -1 },
        Blue = { A = 0.00, B = 2000, C = 0.001, D = 1 },
    },
    [4000] = {
        Red = { A = 0.00, B = 3000, C = 0.00069, D = 1 },
        Green = { A = 0.50, B = 3000, C = 0.00022, D = -1 },
        Blue = { A = 1.00, B = 3000, C = 0.00003, D = -1 },
    },
    [5000] = {
        Red = { A = 0.69, B = 4000, C = 0.00025, D = 1 },
        Green = { A = 0.28, B = 4000, C = 0.00019, D = 1 },
        Blue = { A = 0.97, B = 4000, C = 0.00096, D = -1 },
    },
    [6000] = {
        Red = { A = 0.94, B = 5000, C = 0.00006, D = 1 },
        Green = { A = 0.47, B = 5000, C = 0.00047, D = -1 },
        Blue = { A = 0.00, B = 0, C = 0.0, D = 0 },
    },
}

local function Clamp01(value)
    if value < 0 then
        return 0
    end
    if value > 1 then
        return 1
    end
    return value
end

local function GetGearScoreLiteColorRGB(score)
    local itemScore = tonumber(score)
    if not itemScore then
        return 0.1, 0.1, 0.1
    end

    if itemScore > 5999 then
        itemScore = 5999
    end

    local i
    for i = 0, 6 do
        local minScore = i * 1000
        local maxScore = (i + 1) * 1000
        if itemScore > minScore and itemScore <= maxScore then
            local q = GS_LITE_QUALITY[maxScore]
            if not q then
                break
            end

            -- Preserve GearScoreLite channel math/order for visual parity.
            local red = q.Red.A + (((itemScore - q.Red.B) * q.Red.C) * q.Red.D)
            local blue = q.Green.A + (((itemScore - q.Green.B) * q.Green.C) * q.Green.D)
            local green = q.Blue.A + (((itemScore - q.Blue.B) * q.Blue.C) * q.Blue.D)
            return Clamp01(red), Clamp01(green), Clamp01(blue)
        end
    end

    return 0.1, 0.1, 0.1
end

local function GetGearScoreColorCode(score)
    local red, green, blue = GetGearScoreLiteColorRGB(score)
    local r = math.floor((red * 255) + 0.5)
    local g = math.floor((green * 255) + 0.5)
    local b = math.floor((blue * 255) + 0.5)
    return string.format("%02x%02x%02x", r, g, b)
end

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Raid Inspector|r: " .. tostring(msg))
end

local function SafeInvoke(label, fn)
    local ok, err = pcall(fn)
    if not ok then
        Print((label or "operation") .. " failed: " .. tostring(err))
    end
    return ok
end

local function Trim(s)
    return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

local function GetNow()
    return time()
end

local function CanInspectUnit(unit)
    if not CanInspect then
        return false
    end

    -- 3.3.5 clients commonly expose CanInspect(unit) only.
    local ok, result = pcall(CanInspect, unit, false)
    if ok then
        return result and true or false
    end

    local okLegacy, resultLegacy = pcall(CanInspect, unit)
    if okLegacy then
        return resultLegacy and true or false
    end

    return false
end

local function SetAchievementComparisonUnitSafe(unit)
    if type(SetAchievementComparisonUnit) ~= "function" then
        return false
    end

    local ok, result = pcall(SetAchievementComparisonUnit, unit)
    if not ok then
        return false
    end

    if result == nil then
        return true
    end

    return result and true or false
end

local function ClearAchievementComparisonUnitSafe()
    if type(ClearAchievementComparisonUnit) ~= "function" then
        return
    end
    pcall(ClearAchievementComparisonUnit)
end

local function GetComparisonAchievementPointsSafe()
    if type(GetComparisonAchievementPoints) ~= "function" then
        return nil
    end

    local ok, points = pcall(GetComparisonAchievementPoints)
    if not ok then
        return nil
    end

    local numeric = tonumber(points)
    if not numeric or numeric < 0 then
        return nil
    end

    return math.floor(numeric + 0.5)
end

local function GetCategoryListSafe()
    if type(GetCategoryList) ~= "function" then
        return {}
    end

    local out = {}
    local ok = pcall(GetCategoryList, out)
    if ok and #out > 0 then
        return out
    end

    local okRet, a1, a2, a3, a4, a5 = pcall(GetCategoryList)
    if okRet then
        if tonumber(a1) then table.insert(out, tonumber(a1)) end
        if tonumber(a2) then table.insert(out, tonumber(a2)) end
        if tonumber(a3) then table.insert(out, tonumber(a3)) end
        if tonumber(a4) then table.insert(out, tonumber(a4)) end
        if tonumber(a5) then table.insert(out, tonumber(a5)) end
    end

    return out
end

local function GetCategoryNameSafe(categoryId)
    if type(GetCategoryInfo) ~= "function" then
        return nil
    end

    local ok, name = pcall(GetCategoryInfo, categoryId)
    if ok and type(name) == "string" and name ~= "" then
        return name
    end

    return nil
end

local function CategoryMatchesRaidFlag(categoryName, raidKey)
    local matcher = RAID_CATEGORY_MATCHERS[raidKey]
    if not matcher or type(categoryName) ~= "string" then
        return false
    end

    local lowered = string.lower(categoryName)
    if not string.find(lowered, matcher.raid, 1, true)
        and (not matcher.altRaid or not string.find(lowered, matcher.altRaid, 1, true)) then
        return false
    end

    if not string.find(lowered, matcher.size, 1, true) then
        return false
    end

    return true
end

local function GetCategoryAchievementIds(categoryId)
    if type(GetCategoryNumAchievements) ~= "function" or type(GetAchievementInfo) ~= "function" then
        return {}
    end

    local okCount, num = pcall(GetCategoryNumAchievements, categoryId, true)
    if (not okCount) or (not tonumber(num)) then
        okCount, num = pcall(GetCategoryNumAchievements, categoryId)
    end

    local count = tonumber(num) or 0
    if count <= 0 then
        return {}
    end

    local out = {}
    local index
    for index = 1, count do
        local okInfo, achievementId = pcall(GetAchievementInfo, categoryId, index)
        if not okInfo or not tonumber(achievementId) then
            okInfo, achievementId = pcall(GetAchievementInfo, categoryId, index, true)
        end
        if okInfo and tonumber(achievementId) then
            table.insert(out, tonumber(achievementId))
        end
    end

    return out
end

local function GetComparisonAchievementCompletedSafe(achievementId)
    if type(GetComparisonAchievementInfo) ~= "function" then
        return nil
    end

    local ok, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 = pcall(GetComparisonAchievementInfo, achievementId)
    if not ok then
        return nil
    end

    local values = { a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 }
    local i
    for i = 1, #values do
        if type(values[i]) == "boolean" then
            return values[i]
        end
    end

    return nil
end

local function GetInspectTalentTabCount()
    if not GetNumTalentTabs then
        return 0
    end

    local ok, count = pcall(GetNumTalentTabs, true, false)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    ok, count = pcall(GetNumTalentTabs, true)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    ok, count = pcall(GetNumTalentTabs)
    if ok and tonumber(count) and tonumber(count) > 0 then
        return tonumber(count)
    end

    return 0
end

local function GetInspectTalentTabInfo(index)
    if not GetTalentTabInfo then
        return nil, 0
    end

    local ok, name, _, points = pcall(GetTalentTabInfo, index, true, false)
    if ok and name then
        return name, tonumber(points) or 0
    end

    ok, name, _, points = pcall(GetTalentTabInfo, index, true)
    if ok and name then
        return name, tonumber(points) or 0
    end

    ok, name, _, points = pcall(GetTalentTabInfo, index)
    if ok and name then
        return name, tonumber(points) or 0
    end

    return nil, 0
end

local function DetectUnitSpecFromTalents(unit)
    if not UnitExists(unit) then
        return nil
    end

    local numTabs = GetInspectTalentTabCount()
    if numTabs <= 0 then
        return nil
    end

    local points = {}
    local bestName = nil
    local bestPoints = -1
    local i
    for i = 1, numTabs do
        local name, spent = GetInspectTalentTabInfo(i)
        spent = tonumber(spent) or 0
        points[#points + 1] = tostring(spent)
        if name and spent > bestPoints then
            bestName = tostring(name)
            bestPoints = spent
        end
    end

    if not bestName or bestPoints <= 0 then
        return nil
    end

    return bestName .. " (" .. table.concat(points, "/") .. ")"
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

local function SafeText(value)
    if value == nil then
        return "?"
    end
    return tostring(value)
end

local function FormatStatusReason(reason)
    local map = {
        ["queued-manual"] = "queued",
        ["queued-target"] = "target queued",
        ["queued-snapshot"] = "raid queued",
        ["queued-refresh"] = "refresh queued",
        ["waiting-inspect"] = "waiting inspect",
        ["inspecting"] = "inspecting",
        ["cannot-inspect"] = "not inspectable",
        ["unit-not-found"] = "unit not found",
        ["unit-changed"] = "unit changed",
        ["inspect-timeout"] = "inspect timeout",
        ["inspect-build-failed"] = "inspect build failed",
        ["bridge-error"] = "bridge error",
        ["bridge-pending"] = "bridge pending",
    }
    if not reason or reason == "" then
        return ""
    end
    return map[reason] or tostring(reason)
end

local function FlagText(value)
    if value == true then
        return "Y"
    end
    if value == false then
        return "N"
    end
    return "?"
end

local function HasCompleteRaidAchievementFlags(raid)
    if type(raid) ~= "table" then
        return false
    end

    local rk
    for _, rk in ipairs(RAID_ACHIEVEMENT_KEYS) do
        local v = raid[rk]
        if v ~= true and v ~= false then
            return false
        end
    end

    return true
end

local function HasAnyKnownRaidAchievementFlags(raid)
    if type(raid) ~= "table" then
        return false
    end

    local rk
    for _, rk in ipairs(RAID_ACHIEVEMENT_KEYS) do
        local v = raid[rk]
        if v == true or v == false then
            return true
        end
    end

    return false
end

local function ResolveAchievementPointsSource(result)
    if type(result) ~= "table" then
        return "-"
    end

    if result.achievementPointsSource and tostring(result.achievementPointsSource) ~= "" then
        return tostring(result.achievementPointsSource)
    end

    if result.achievementPoints == nil then
        return "-"
    end

    if result.source and tostring(result.source) ~= "" then
        return tostring(result.source)
    end

    return "unknown"
end

local function ResolveRaidAchievementsSource(result)
    if type(result) ~= "table" then
        return "-"
    end

    local raid = result.raidAchievements
    if type(raid) == "table" and raid.source and tostring(raid.source) ~= "" then
        return tostring(raid.source)
    end

    if HasAnyKnownRaidAchievementFlags(raid) then
        return "unknown"
    end

    return "-"
end

local function FormatRaidAchievements(ach)
    if type(ach) ~= "table" then
        return "ICC10:? ICC25:? TOC10:? TOC25:? RS10:? RS25:?"
    end

    return "ICC10:" .. FlagText(ach.icc10)
        .. " ICC25:" .. FlagText(ach.icc25)
        .. " TOC10:" .. FlagText(ach.toc10)
        .. " TOC25:" .. FlagText(ach.toc25)
        .. " RS10:" .. FlagText(ach.rs10)
        .. " RS25:" .. FlagText(ach.rs25)
end

local function NormalizeSlot(slot)
    local raw = string.lower((slot or "")):gsub("_", "")
    return SLOT_ALIASES[raw]
end

local function IsLowTierEnchant(item)
    local enchantId = tonumber(item.enchantId)
    local ilvl = tonumber(item.ilvl) or 0
    if not enchantId then
        return false
    end

    -- Heuristic: very low enchant IDs on high ilvl items are usually outdated enchants.
    return ilvl >= 200 and enchantId < 3000
end

local function ParseItemLinkData(link)
    local itemString = string.match(link or "", "item:([%-%d:]+)")
    if not itemString then
        return nil, nil, {}
    end

    local fields = {}
    local part
    for part in string.gmatch(itemString, "([^:]+)") do
        table.insert(fields, part)
    end

    local itemId = tonumber(fields[1] or "")
    local enchantId = tonumber(fields[2] or "")
    local gems = {}
    local i
    for i = 3, 6 do
        local gemId = tonumber(fields[i] or "")
        if gemId and gemId > 0 then
            table.insert(gems, gemId)
        end
    end

    return itemId, enchantId, gems
end

local function GetSocketCountFromItemLink(link)
    if not GetItemStats then
        return 0
    end

    local stats = GetItemStats(link)
    if type(stats) ~= "table" then
        return 0
    end

    local total = 0
    local k
    for k in pairs(stats) do
        if type(k) == "string" and string.find(k, "EMPTY_SOCKET_") then
            total = total + (tonumber(stats[k]) or 0)
        end
    end
    return total
end

local function EstimateGearScoreLiteItem(item)
    local slot = item.slot
    local cfg = slot and GS_SLOT_CONFIG[slot]
    local ilvl = tonumber(item.ilvl)
    if not cfg or not ilvl or ilvl <= 0 then
        return nil
    end

    local rarity = tonumber(item.quality or item.rarity)
    if not rarity then
        rarity = 4
    end

    local qualityScale = 1.0
    if rarity == 5 then
        qualityScale = 1.3
        rarity = 4
    elseif rarity == 0 or rarity == 1 then
        qualityScale = 0.005
        rarity = 2
    elseif rarity == 7 then
        rarity = 3
        ilvl = 187.05
    end

    local tableRef = ilvl > 120 and GS_FORMULA_A or GS_FORMULA_B
    local formula = tableRef[rarity]
    if not formula then
        return nil
    end

    local score = math.floor((((ilvl - formula.A) / formula.B) * cfg.slotMod * GS_SCALE * qualityScale) + 0.5)
    if score < 0 then
        score = 0
    end

    if cfg.enchantable and not tonumber(item.enchantId) then
        local percent = 1 + ((-2 * cfg.slotMod) / 100)
        score = math.floor((score * percent) + 0.5)
    end

    if score < 0 then
        score = 0
    end
    return score
end

local function GetGearScoreLiteEnchantPercent(itemLink, itemEquipLoc)
    local cfg = GS_EQUIPLOC_CONFIG[itemEquipLoc]
    if not cfg or not cfg.enchantable then
        return 1
    end

    local _, enchantId = ParseItemLinkData(itemLink)
    if enchantId and enchantId > 0 then
        return 1
    end

    -- Mirror GearScoreLite percent rounding exactly.
    local percent = math.floor((-2 * cfg.slotMod) * 100) / 100
    return 1 + (percent / 100)
end

local function EstimateGearScoreLiteFromItemLink(itemLink)
    if not itemLink or itemLink == "" then
        return nil
    end

    local _, _, itemRarity, itemLevel, _, _, _, _, itemEquipLoc = GetItemInfo(itemLink)
    local cfg = itemEquipLoc and GS_EQUIPLOC_CONFIG[itemEquipLoc]
    if not cfg or not itemRarity or not itemLevel then
        return nil
    end

    local rarity = tonumber(itemRarity)
    local ilvl = tonumber(itemLevel)
    if not rarity or not ilvl then
        return nil
    end

    local qualityScale = 1
    if rarity == 5 then
        qualityScale = 1.3
        rarity = 4
    elseif rarity == 1 or rarity == 0 then
        qualityScale = 0.005
        rarity = 2
    elseif rarity == 7 then
        rarity = 3
        ilvl = 187.05
    end

    if rarity < 2 or rarity > 4 then
        return nil
    end

    local tableRef = ilvl > 120 and GS_FORMULA_A or GS_FORMULA_B
    local formula = tableRef[rarity]
    if not formula then
        return nil
    end

    local score = math.floor(((ilvl - formula.A) / formula.B) * cfg.slotMod * GS_SCALE * qualityScale)
    if score < 0 then
        score = 0
    end

    local enchantPercent = GetGearScoreLiteEnchantPercent(itemLink, itemEquipLoc)
    score = math.floor(score * enchantPercent)
    if score < 0 then
        score = 0
    end

    return score
end

local function EstimateGearScoreFromUnit(unit, classToken)
    if not UnitExists(unit) then
        return nil, "none"
    end

    local isHunter = string.lower(tostring(classToken or "")) == "hunter"
    local total = 0
    local itemCount = 0
    local titanGrip = 1

    local mhLink = GetInventoryItemLink(unit, 16)
    local ohLink = GetInventoryItemLink(unit, 17)

    if mhLink and ohLink then
        local _, _, _, _, _, _, _, _, mhEquipLoc = GetItemInfo(mhLink)
        if mhEquipLoc == "INVTYPE_2HWEAPON" then
            titanGrip = 0.5
        end
    end

    if ohLink then
        local _, _, _, _, _, _, _, _, ohEquipLoc = GetItemInfo(ohLink)
        if ohEquipLoc == "INVTYPE_2HWEAPON" then
            titanGrip = 0.5
        end

        local offScore = EstimateGearScoreLiteFromItemLink(ohLink)
        if offScore then
            local score = offScore
            if isHunter then
                score = score * 0.3164
            end
            total = total + (score * titanGrip)
            itemCount = itemCount + 1
        end
    end

    local slotId
    for slotId = 1, 18 do
        if slotId ~= 4 and slotId ~= 17 then
            local itemLink = GetInventoryItemLink(unit, slotId)
            if itemLink then
                local itemScore = EstimateGearScoreLiteFromItemLink(itemLink)
                if itemScore then
                    local score = itemScore
                    if slotId == 16 and isHunter then
                        score = score * 0.3164
                    elseif slotId == 18 and isHunter then
                        score = score * 5.3224
                    end
                    if slotId == 16 then
                        score = score * titanGrip
                    end
                    total = total + score
                    itemCount = itemCount + 1
                end
            end
        end
    end

    if itemCount <= 0 then
        return nil, "none"
    end

    return math.floor(total), "estimated-gearscorelite"
end

local function EstimateGearScoreFromItems(items, classToken)
    local classLower = string.lower(tostring(classToken or ""))
    local isHunter = classLower == "hunter"
    local totalLite = 0
    local liteCount = 0
    local ilvls = {}
    local i

    for i = 1, #items do
        local item = items[i]
        local lite = EstimateGearScoreLiteItem(item)
        if lite then
            local score = lite
            if isHunter and item.slot == "MainHandSlot" then
                score = score * 0.3164
            elseif isHunter and item.slot == "RangedSlot" then
                score = score * 5.3224
            end
            totalLite = totalLite + score
            liteCount = liteCount + 1
        end

        local ilvl = tonumber(item.ilvl)
        if ilvl and ilvl > 0 then
            table.insert(ilvls, ilvl)
        end
    end

    if liteCount > 0 then
        return math.floor(totalLite + 0.5), "estimated-gearscorelite"
    end

    if #ilvls == 0 then
        return nil, "none"
    end

    local sum = 0
    for i = 1, #ilvls do
        sum = sum + ilvls[i]
    end

    local avg = sum / #ilvls
    return math.floor(avg * 20 + 0.5), "estimated-ilvl"
end

local function AnalyzeItemIssues(items)
    local missingEnchant = 0
    local missingGems = 0
    local itemsWithoutSlot = 0
    local itemsWithSockets = 0
    local totalSockets = 0
    local filledSockets = 0
    local i

    for i = 1, #items do
        local item = items[i]
        local slot = item.slot
        local socketCount = tonumber(item.socketCount) or 0
        local gemCount = type(item.gems) == "table" and #item.gems or 0

        if not slot or slot == "" then
            itemsWithoutSlot = itemsWithoutSlot + 1
        elseif ENCHANTABLE_SLOTS[slot] and not OPTIONAL_ENCHANT_SLOTS[slot] and not tonumber(item.enchantId) then
            missingEnchant = missingEnchant + 1
        end

        if socketCount > 0 then
            itemsWithSockets = itemsWithSockets + 1
            totalSockets = totalSockets + socketCount
            filledSockets = filledSockets + math.min(socketCount, gemCount)
            if gemCount < socketCount then
                missingGems = missingGems + (socketCount - gemCount)
            end
        end
    end

    return {
        missingEnchant = missingEnchant,
        missingGems = missingGems,
        itemsWithoutSlot = itemsWithoutSlot,
        itemsAnalyzed = #items,
        itemsWithSockets = itemsWithSockets,
        totalSockets = totalSockets,
        filledSockets = filledSockets,
    }
end

function addon:InitInspectRuntime()
    addon.inspectQueue = addon.inspectQueue or {}
    addon.inspectQueuedKeys = addon.inspectQueuedKeys or {}
    addon.inspectCurrent = nil
    addon.inspectLastRequestAt = addon.inspectLastRequestAt or 0
    addon.inspectTickAccum = 0

    addon.achievementQueue = addon.achievementQueue or {}
    addon.achievementQueuedKeys = addon.achievementQueuedKeys or {}
    addon.achievementCurrent = nil
    addon.achievementLastRequestAt = addon.achievementLastRequestAt or 0
end

function addon:GetInspectLinkCount(unit)
    local count = 0
    local i
    for i = 1, #INSPECT_SLOT_MAP do
        if GetInventoryItemLink(unit, INSPECT_SLOT_MAP[i].id) then
            count = count + 1
        end
    end
    return count
end

function addon:FinalizeInspectCurrent(success, failureReason)
    if not addon.inspectCurrent then
        return
    end

    local current = addon.inspectCurrent
    addon.inspectCurrent = nil

    local req = addon:GetLatestRequestForKey(current.key)
    if success and UnitExists(current.unit) then
        local ok, resultOrErr = pcall(addon.BuildLocalInspectResult, addon, current.unit, current.key, current.name, current.realm)
        if ok and type(resultOrErr) == "table" then
            local previous = RaidInspectorDB.results[current.key]
            if type(previous) == "table" then
                if (not resultOrErr.spec or resultOrErr.spec == "") and previous.spec and previous.spec ~= "" then
                    resultOrErr.spec = previous.spec
                end
                if resultOrErr.achievementPoints == nil and previous.achievementPoints ~= nil then
                    resultOrErr.achievementPoints = previous.achievementPoints
                    resultOrErr.achievementPointsSource = previous.achievementPointsSource
                end
                if (type(resultOrErr.raidAchievements) ~= "table" or next(resultOrErr.raidAchievements) == nil)
                    and type(previous.raidAchievements) == "table" then
                    resultOrErr.raidAchievements = CopyTable(previous.raidAchievements)
                end
            end
            RaidInspectorDB.results[current.key] = resultOrErr
            if req then
                req.status = "ready"
                req.statusReason = nil
                req.updatedAt = GetNow()
            end

            addon:RefreshActiveRaidHistoryEntry()

            addon:QueueAchievementCompareUnit(current.unit, current.key, current.name, current.realm, current.guid)
        else
            Print("inspect build failed: " .. tostring(resultOrErr))
            if req then
                req.status = "error"
                req.statusReason = "inspect-build-failed"
                req.updatedAt = GetNow()
            end
        end
    elseif req then
        if not RaidInspectorDB.results[current.key] then
            req.status = "error"
            req.statusReason = failureReason or "inspect-timeout"
        else
            req.status = "ready"
            req.statusReason = nil
        end
        req.updatedAt = GetNow()
    end

    addon:RefreshActiveRaidHistoryEntry()

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end

    addon:RefreshMainWindow()
end

function addon:QueueAchievementCompareUnit(unit, key, name, realm, guid)
    if type(SetAchievementComparisonUnit) ~= "function" or type(GetComparisonAchievementPoints) ~= "function" then
        return false, "unsupported"
    end

    if not UnitExists(unit) then
        return false, "unit-not-found"
    end

    if not CanInspectUnit(unit) then
        return false, "cannot-inspect"
    end

    if addon.achievementQueuedKeys[key] then
        return false, "already-queued"
    end

    if addon.achievementCurrent and addon.achievementCurrent.key == key then
        return false, "already-active"
    end

    table.insert(addon.achievementQueue, {
        unit = unit,
        guid = guid or UnitGUID(unit),
        key = key,
        name = name,
        realm = realm,
        queuedAt = GetNow(),
    })
    addon.achievementQueuedKeys[key] = true

    return true
end

function addon:ProcessAchievementCompareQueue(force)
    if addon.achievementCurrent then
        return
    end

    if not addon.achievementQueue or #addon.achievementQueue == 0 then
        return
    end

    local now = GetNow()
    if not force and (now - (addon.achievementLastRequestAt or 0)) < ACHIEVEMENT_COMPARE_THROTTLE_SECONDS then
        return
    end

    local entry = table.remove(addon.achievementQueue, 1)
    if not entry then
        return
    end

    addon.achievementQueuedKeys[entry.key] = nil

    if not UnitExists(entry.unit) then
        return
    end

    if entry.guid and UnitGUID(entry.unit) ~= entry.guid then
        return
    end

    if not CanInspectUnit(entry.unit) then
        return
    end

    ClearAchievementComparisonUnitSafe()
    if not SetAchievementComparisonUnitSafe(entry.unit) then
        return
    end

    addon.achievementCurrent = {
        unit = entry.unit,
        guid = entry.guid,
        key = entry.key,
        name = entry.name,
        realm = entry.realm,
        startedAt = now,
        lastPollAt = 0,
    }
    addon.achievementLastRequestAt = now
end

function addon:BuildRaidAchievementFlagsFromComparison()
    if type(GetCategoryList) ~= "function"
        or type(GetCategoryInfo) ~= "function"
        or type(GetCategoryNumAchievements) ~= "function"
        or type(GetAchievementInfo) ~= "function"
        or type(GetComparisonAchievementInfo) ~= "function" then
        return nil
    end

    local categories = GetCategoryListSafe()
    if #categories == 0 then
        return nil
    end

    local categoryBuckets = {}
    local raidKey
    for _, raidKey in ipairs(RAID_ACHIEVEMENT_KEYS) do
        categoryBuckets[raidKey] = {}
    end

    local i
    for i = 1, #categories do
        local categoryId = tonumber(categories[i])
        if categoryId then
            local categoryName = GetCategoryNameSafe(categoryId)
            if categoryName then
                for _, raidKey in ipairs(RAID_ACHIEVEMENT_KEYS) do
                    if CategoryMatchesRaidFlag(categoryName, raidKey) then
                        table.insert(categoryBuckets[raidKey], categoryId)
                    end
                end
            end
        end
    end

    local flags = {
        icc10 = nil,
        icc25 = nil,
        toc10 = nil,
        toc25 = nil,
        rs10 = nil,
        rs25 = nil,
        source = "inspect-achievement-compare",
    }

    local knownCount = 0
    local achievementCache = {}
    for _, raidKey in ipairs(RAID_ACHIEVEMENT_KEYS) do
        local anyKnown = false
        local anyCompleted = false
        local bucket = categoryBuckets[raidKey]
        local bi

        for bi = 1, #bucket do
            local categoryId = bucket[bi]
            local ids = GetCategoryAchievementIds(categoryId)
            local ai
            for ai = 1, #ids do
                local achievementId = ids[ai]
                local completed = achievementCache[achievementId]
                if completed == nil then
                    completed = GetComparisonAchievementCompletedSafe(achievementId)
                    achievementCache[achievementId] = completed
                end

                if completed ~= nil then
                    anyKnown = true
                    if completed == true then
                        anyCompleted = true
                        break
                    end
                end
            end

            if anyCompleted then
                break
            end
        end

        if anyCompleted then
            flags[raidKey] = true
            knownCount = knownCount + 1
        elseif anyKnown then
            flags[raidKey] = false
            knownCount = knownCount + 1
        end
    end

    if knownCount <= 0 then
        return nil
    end

    return flags
end

function addon:FinalizeAchievementCompareCurrent(success, points, raidFlags)
    if not addon.achievementCurrent then
        return
    end

    local current = addon.achievementCurrent
    addon.achievementCurrent = nil
    ClearAchievementComparisonUnitSafe()

    if not success or points == nil then
        return
    end

    local result = RaidInspectorDB.results[current.key]
    if type(result) ~= "table" then
        return
    end

    result.achievementPoints = tonumber(points) or points
    result.achievementPointsSource = "inspect-achievement-compare"

    if type(raidFlags) == "table" then
        if type(result.raidAchievements) ~= "table" then
            result.raidAchievements = {}
        end

        local rk
        for _, rk in ipairs(RAID_ACHIEVEMENT_KEYS) do
            local value = raidFlags[rk]
            if value == true or value == false then
                result.raidAchievements[rk] = value
            end
        end

        if raidFlags.source then
            result.raidAchievements.source = raidFlags.source
        end
    end

    result.updatedAt = GetNow()
    addon:RefreshActiveRaidHistoryEntry()
end

function addon:QueueLiveInspectUnit(unit, queueRequest)
    if not UnitExists(unit) then
        return false, "unit-not-found"
    end

    if not CanInspectUnit(unit) then
        return false, "cannot-inspect"
    end

    local unitName, unitRealm = UnitName(unit)
    if not unitName or unitName == "" then
        return false, "bad-unit-name"
    end

    local realm = unitRealm
    if not realm or realm == "" then
        realm = GetRealmName() or ""
    end
    if realm == "" then
        return false, "bad-realm"
    end

    if queueRequest ~= false then
        addon:QueueInspect(unitName, realm, { allowDuplicate = false, silent = true })
    end

    local key = MakePlayerKey(unitName, realm)
    if addon.inspectQueuedKeys[key] then
        return false, "already-queued"
    end
    if addon.inspectCurrent and addon.inspectCurrent.key == key then
        return false, "already-active"
    end

    table.insert(addon.inspectQueue, {
        unit = unit,
        guid = UnitGUID(unit),
        key = key,
        name = unitName,
        realm = realm,
        queuedAt = GetNow(),
    })
    addon.inspectQueuedKeys[key] = true

    local req = addon:GetLatestRequestForKey(key)
    if req then
        req.status = "queued"
        req.statusReason = "waiting-inspect"
        req.updatedAt = GetNow()
    end

    return true
end

function addon:BuildLocalInspectResult(unit, key, name, realm)
    local items = {}
    local enchants = {}
    local gemsBySlot = {}
    local i

    for i = 1, #INSPECT_SLOT_MAP do
        local slotMap = INSPECT_SLOT_MAP[i]
        local itemLink = GetInventoryItemLink(unit, slotMap.id)
        if itemLink then
            local itemId, enchantId, gems = ParseItemLinkData(itemLink)
            local itemName, _, itemQuality, ilvl = GetItemInfo(itemLink)
            local socketCount = GetSocketCountFromItemLink(itemLink)

            local item = {
                slot = slotMap.slot,
                name = itemName,
            }
            if itemId then
                item.itemId = itemId
            end
            if ilvl and ilvl > 0 then
                item.ilvl = ilvl
            end
            if itemQuality and itemQuality >= 0 then
                item.quality = itemQuality
            end
            if enchantId and enchantId > 0 then
                item.enchantId = enchantId
                enchants[slotMap.slot] = enchantId
            end
            if socketCount and socketCount > 0 then
                item.socketCount = socketCount
            end
            if gems and #gems > 0 then
                item.gems = gems
                gemsBySlot[slotMap.slot] = gems
            end

            table.insert(items, item)
        end
    end

    local now = GetNow()
    local issueSummary = AnalyzeItemIssues(items)
    local localizedClass, englishClass = UnitClass(unit)
    local detectedSpec = DetectUnitSpecFromTalents(unit)
    local estimatedGS, estimatedSource = EstimateGearScoreFromUnit(unit, englishClass)
    if not estimatedGS then
        estimatedGS, estimatedSource = EstimateGearScoreFromItems(items, englishClass)
    end

    return {
        name = name,
        realm = realm,
        class = localizedClass,
        spec = detectedSpec,
        guild = GetGuildInfo(unit),
        level = UnitLevel(unit),
        items = items,
        enchants = enchants,
        gems = gemsBySlot,
        gearScore = estimatedGS,
        gearScoreSource = estimatedSource,
        estimatedGearScore = estimatedGS,
        achievementPoints = nil,
        achievementPointsSource = nil,
        raidAchievements = {},
        issuesCount = issueSummary.missingEnchant + issueSummary.missingGems,
        issueSummary = issueSummary,
        source = "local-inspect",
        fetchedAt = now,
        updatedAt = now,
    }
end

function addon:ProcessInspectQueue(force)
    if addon.inspectCurrent then
        return
    end

    if not addon.inspectQueue or #addon.inspectQueue == 0 then
        return
    end

    if not force and (GetNow() - (addon.inspectLastRequestAt or 0)) < INSPECT_THROTTLE_SECONDS then
        return
    end

    local entry = table.remove(addon.inspectQueue, 1)
    if not entry then
        return
    end

    addon.inspectQueuedKeys[entry.key] = nil

    if not UnitExists(entry.unit) then
        local reqMissing = addon:GetLatestRequestForKey(entry.key)
        if reqMissing and not RaidInspectorDB.results[entry.key] then
            reqMissing.status = "error"
            reqMissing.statusReason = "unit-not-found"
            reqMissing.updatedAt = GetNow()
        end
        return
    end

    if entry.guid and UnitGUID(entry.unit) ~= entry.guid then
        local reqGuid = addon:GetLatestRequestForKey(entry.key)
        if reqGuid and not RaidInspectorDB.results[entry.key] then
            reqGuid.status = "error"
            reqGuid.statusReason = "unit-changed"
            reqGuid.updatedAt = GetNow()
        end
        return
    end

    if not CanInspectUnit(entry.unit) then
        local reqInspect = addon:GetLatestRequestForKey(entry.key)
        if reqInspect and not RaidInspectorDB.results[entry.key] then
            reqInspect.status = "error"
            reqInspect.statusReason = "cannot-inspect"
            reqInspect.updatedAt = GetNow()
        end
        return
    end

    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
    NotifyInspect(entry.unit)
    addon.inspectCurrent = {
        unit = entry.unit,
        guid = entry.guid,
        key = entry.key,
        name = entry.name,
        realm = entry.realm,
        startedAt = GetNow(),
        lastPollAt = 0,
    }
    addon.inspectLastRequestAt = GetNow()

    local req = addon:GetLatestRequestForKey(entry.key)
    if req then
        req.status = "queued"
        req.statusReason = "inspecting"
        req.updatedAt = GetNow()
    end
end

function addon:OnInspectReady(guid)
    if not addon.inspectCurrent then
        return
    end

    if guid and addon.inspectCurrent.guid and guid ~= addon.inspectCurrent.guid then
        return
    end

    addon:FinalizeInspectCurrent(true, nil)
end

function addon:OnUpdate(elapsed)
    addon.inspectTickAccum = (addon.inspectTickAccum or 0) + (elapsed or 0)
    if addon.inspectTickAccum < 0.2 then
        return
    end
    addon.inspectTickAccum = 0

    if addon.inspectCurrent then
        local now = GetNow()
        if UnitExists(addon.inspectCurrent.unit) and (now - (addon.inspectCurrent.lastPollAt or 0)) >= 1 then
            addon.inspectCurrent.lastPollAt = now
            if addon:GetInspectLinkCount(addon.inspectCurrent.unit) > 0 then
                addon:FinalizeInspectCurrent(true, nil)
                addon:ProcessInspectQueue(false)
                return
            end
        end

        if (now - addon.inspectCurrent.startedAt) > INSPECT_TIMEOUT_SECONDS then
            addon:FinalizeInspectCurrent(false, "inspect-timeout")
        end
    end

    addon:ProcessInspectQueue(false)

    if addon.achievementCurrent then
        local now = GetNow()
        if UnitExists(addon.achievementCurrent.unit) and (now - (addon.achievementCurrent.lastPollAt or 0)) >= 1 then
            addon.achievementCurrent.lastPollAt = now
            local points = GetComparisonAchievementPointsSafe()
            if points ~= nil then
                local raidFlags = addon:BuildRaidAchievementFlagsFromComparison()
                addon:FinalizeAchievementCompareCurrent(true, points, raidFlags)
                addon:ProcessAchievementCompareQueue(false)
                return
            end
        end

        if (now - addon.achievementCurrent.startedAt) > ACHIEVEMENT_COMPARE_TIMEOUT_SECONDS then
            addon:FinalizeAchievementCompareCurrent(false, nil)
        end
    end

    addon:ProcessAchievementCompareQueue(false)
end

function addon:InitDatabase()
    EnsureTable(RaidInspectorDB, "meta", {})
    EnsureTable(RaidInspectorDB, "settings", {})
    EnsureTable(RaidInspectorDB.settings, "window", {})
    EnsureTable(RaidInspectorDB.settings.window, "point", "CENTER")
    EnsureTable(RaidInspectorDB.settings.window, "x", 0)
    EnsureTable(RaidInspectorDB.settings.window, "y", 0)

    EnsureTable(RaidInspectorDB.settings, "overview", {})
    EnsureTable(RaidInspectorDB.settings.overview, "sortMode", "recent")
    EnsureTable(RaidInspectorDB.settings.overview, "filterMode", "all")

    EnsureTable(RaidInspectorDB, "state", {})
    EnsureTable(RaidInspectorDB.state, "nextRequestId", 1)
    EnsureTable(RaidInspectorDB.state, "lastSnapshot", {})
    EnsureTable(RaidInspectorDB.state.lastSnapshot, "at", 0)
    EnsureTable(RaidInspectorDB.state.lastSnapshot, "historyId", 0)
    EnsureTable(RaidInspectorDB.state.lastSnapshot, "members", {})
    EnsureTable(RaidInspectorDB.state, "ui", {})
    EnsureTable(RaidInspectorDB.state.ui, "selectedKey", "")
    EnsureTable(RaidInspectorDB.state.ui, "itemListFilterMode", "all")
    EnsureTable(RaidInspectorDB.state.ui, "buttonMode", "advanced")
    EnsureTable(RaidInspectorDB.state.ui, "minimap", {})
    EnsureTable(RaidInspectorDB.state.ui.minimap, "angle", 220)
    EnsureTable(RaidInspectorDB.state.ui, "exportChannels", {})
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "raid", true)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "say", false)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "whisper", false)

    EnsureTable(RaidInspectorDB, "requests", {})
    EnsureTable(RaidInspectorDB, "results", {})
    EnsureTable(RaidInspectorDB, "reportSnapshots", {})
    EnsureTable(RaidInspectorDB.reportSnapshots, "nextId", 1)
    EnsureTable(RaidInspectorDB.reportSnapshots, "items", {})
    EnsureTable(RaidInspectorDB, "raidScanHistory", {})
    EnsureTable(RaidInspectorDB.raidScanHistory, "nextId", 1)
    EnsureTable(RaidInspectorDB.raidScanHistory, "scans", {})

    RaidInspectorDB.meta.schemaVersion = 2
    RaidInspectorDB.meta.lastLoadedAt = GetNow()
    EnsureTable(RaidInspectorDB.meta, "lastImportedBridgeGeneratedAt", 0)
    addon:PruneRaidScanHistory()
end

function addon:GetSortMode()
    local mode = RaidInspectorDB.settings.overview.sortMode
    if SORT_LABELS[mode] then
        return mode
    end
    RaidInspectorDB.settings.overview.sortMode = "recent"
    return "recent"
end

function addon:GetFilterMode()
    local mode = RaidInspectorDB.settings.overview.filterMode
    if FILTER_LABELS[mode] then
        return mode
    end
    RaidInspectorDB.settings.overview.filterMode = "all"
    return "all"
end

function addon:GetItemListFilterMode()
    local mode = RaidInspectorDB.state.ui.itemListFilterMode
    if ITEM_LIST_FILTER_LABELS[mode] then
        return mode
    end
    RaidInspectorDB.state.ui.itemListFilterMode = "all"
    return "all"
end

function addon:GetButtonMode()
    local mode = RaidInspectorDB.state.ui.buttonMode
    if BUTTON_MODE_LABELS[mode] then
        return mode
    end
    RaidInspectorDB.state.ui.buttonMode = "advanced"
    return "advanced"
end

function addon:GetExportChannels()
    EnsureTable(RaidInspectorDB.state.ui, "exportChannels", {})
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "raid", true)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "say", false)
    EnsureTable(RaidInspectorDB.state.ui.exportChannels, "whisper", false)
    return RaidInspectorDB.state.ui.exportChannels
end

function addon:SetExportChannel(channel, enabled)
    if channel ~= "raid" and channel ~= "say" and channel ~= "whisper" then
        return false
    end

    local channels = addon:GetExportChannels()
    channels[channel] = enabled and true or false
    return true
end

function addon:GetReportSnapshots()
    EnsureTable(RaidInspectorDB, "reportSnapshots", {})
    EnsureTable(RaidInspectorDB.reportSnapshots, "nextId", 1)
    EnsureTable(RaidInspectorDB.reportSnapshots, "items", {})
    return RaidInspectorDB.reportSnapshots
end

function addon:GetRaidScanHistory()
    EnsureTable(RaidInspectorDB, "raidScanHistory", {})
    EnsureTable(RaidInspectorDB.raidScanHistory, "nextId", 1)
    EnsureTable(RaidInspectorDB.raidScanHistory, "scans", {})
    return RaidInspectorDB.raidScanHistory
end

function addon:PruneRaidScanHistory()
    local history = addon:GetRaidScanHistory()
    local cutoff = GetNow() - RAID_HISTORY_RETENTION_SECONDS
    local kept = {}
    local activeHistoryId = tonumber(RaidInspectorDB.state.lastSnapshot and RaidInspectorDB.state.lastSnapshot.historyId) or 0
    local activeKept = false
    local i

    for i = 1, #history.scans do
        local entry = history.scans[i]
        local snapshotAt = tonumber(entry and entry.snapshotAt) or tonumber(entry and entry.updatedAt) or 0
        if snapshotAt >= cutoff then
            kept[#kept + 1] = entry
            if activeHistoryId > 0 and tonumber(entry.id) == activeHistoryId then
                activeKept = true
            end
        end
    end

    history.scans = kept
    if activeHistoryId > 0 and not activeKept and RaidInspectorDB.state.lastSnapshot then
        RaidInspectorDB.state.lastSnapshot.historyId = 0
    end
end

function addon:BuildStoredSummaryPayload(key, req, result, state, statusReason)
    local nameFromKey, realmFromKey = ParseKey(key or "")
    local payload = {
        key = key,
        name = (req and req.name) or (result and result.name) or nameFromKey or "Unknown",
        realm = (req and req.realm) or (result and result.realm) or realmFromKey or "Unknown",
        state = state or (req and req.status) or "queued",
        statusReason = statusReason or (req and req.statusReason) or nil,
        requestId = req and tonumber(req.id) or nil,
        requestedAt = req and tonumber(req.requestedAt) or nil,
        updatedAt = req and tonumber(req.updatedAt) or 0,
    }

    if type(result) == "table" then
        payload.class = result.class
        payload.spec = result.spec
        payload.guild = result.guild
        payload.level = result.level
        payload.source = result.source
        payload.error = result.error
        payload.gearScore = result.gearScore
        payload.gearScoreSource = result.gearScoreSource
        payload.estimatedGearScore = result.estimatedGearScore
        payload.issuesCount = tonumber(result.issuesCount) or 0
        payload.issueSummary = CopyTable(result.issueSummary or {})
        payload.achievementPoints = result.achievementPoints
        payload.achievementPointsSource = result.achievementPointsSource
        payload.raidAchievements = CopyTable(result.raidAchievements or {})
        payload.updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or payload.updatedAt or 0
    end

    return payload
end

function addon:BuildRaidHistoryPayloadForKey(key)
    local req = addon:GetLatestRequestForKey(key)
    local result = RaidInspectorDB.results[key]
    local state = req and req.status or "queued"

    if state ~= "error" and type(result) == "table" then
        state = "ready"
    end

    return addon:BuildStoredSummaryPayload(key, req, result, state, req and req.statusReason or nil)
end

function addon:FindRaidHistoryEntryById(historyId)
    if not historyId or historyId == 0 then
        return nil
    end

    local history = addon:GetRaidScanHistory()
    local i
    for i = #history.scans, 1, -1 do
        local entry = history.scans[i]
        if tonumber(entry.id) == tonumber(historyId) then
            return entry
        end
    end

    return nil
end

function addon:RefreshRaidHistoryEntry(entry)
    if type(entry) ~= "table" then
        return false
    end

    local members = type(entry.members) == "table" and entry.members or {}
    local roster = {}
    local key

    for key in pairs(members) do
        roster[#roster + 1] = key
    end

    table.sort(roster)
    entry.members = members
    entry.roster = roster
    entry.summaryPayloads = {}

    local i
    for i = 1, #roster do
        local rosterKey = roster[i]
        entry.summaryPayloads[rosterKey] = addon:BuildRaidHistoryPayloadForKey(rosterKey)
    end

    entry.updatedAt = GetNow()
    return true
end

function addon:RefreshActiveRaidHistoryEntry()
    local snapshot = RaidInspectorDB.state.lastSnapshot
    if type(snapshot) ~= "table" then
        return false
    end

    local historyId = tonumber(snapshot.historyId) or 0
    if historyId <= 0 then
        return false
    end

    addon:PruneRaidScanHistory()
    local entry = addon:FindRaidHistoryEntryById(historyId)
    if not entry then
        snapshot.historyId = 0
        return false
    end

    entry.members = CopyTable(snapshot.members or {})
    entry.snapshotAt = tonumber(snapshot.at) or entry.snapshotAt or GetNow()
    return addon:RefreshRaidHistoryEntry(entry)
end

function addon:CreateRaidHistoryEntry(snapshotAt, members)
    if type(members) ~= "table" or next(members) == nil then
        return nil
    end

    addon:PruneRaidScanHistory()

    local history = addon:GetRaidScanHistory()
    local id = tonumber(history.nextId) or 1
    history.nextId = id + 1

    local entry = {
        id = id,
        snapshotAt = tonumber(snapshotAt) or GetNow(),
        updatedAt = tonumber(snapshotAt) or GetNow(),
        members = CopyTable(members),
        roster = {},
        summaryPayloads = {},
    }

    history.scans[#history.scans + 1] = entry
    RaidInspectorDB.state.lastSnapshot.historyId = id
    addon:RefreshRaidHistoryEntry(entry)
    return entry
end

function addon:ResolveOverviewEntry(arg)
    local entries = addon:GetOverviewEntries()
    if #entries == 0 then
        return nil, "no entries available"
    end

    local targetKey = Trim(arg or "")
    if targetKey == "" then
        targetKey = addon:GetSelectedKey()
    elseif not string.find(targetKey, "%-") then
        targetKey = MakePlayerKey(targetKey, GetRealmName() or "")
    else
        targetKey = string.lower(targetKey)
    end

    local selected = nil
    local i
    for i = 1, #entries do
        if entries[i].key == targetKey then
            selected = entries[i]
            break
        end
    end

    if not selected and targetKey ~= "" then
        return nil, "target not found in current overview: " .. targetKey
    end

    if not selected then
        selected = entries[1]
    end

    return selected
end

function addon:StoreReportSnapshot(entry, sourceTag)
    if type(entry) ~= "table" or type(entry.req) ~= "table" then
        return nil
    end

    local reports = addon:GetReportSnapshots()
    local id = tonumber(reports.nextId) or 1
    local payload = addon:BuildStoredSummaryPayload(entry.key, entry.req, entry.result, entry.state, entry.statusReason)
    local snapshot = {
        id = id,
        savedAt = GetNow(),
        source = sourceTag or "manual",
        key = payload.key,
        name = payload.name,
        realm = payload.realm,
        payload = payload,
        message = addon:BuildExportSummaryFromPayload(payload),
    }

    reports.nextId = id + 1
    reports.items[#reports.items + 1] = snapshot

    while #reports.items > REPORT_SNAPSHOT_LIMIT do
        table.remove(reports.items, 1)
    end

    return snapshot
end

function addon:FindSavedReport(arg)
    local reports = addon:GetReportSnapshots()
    if #reports.items == 0 then
        return nil, "no saved reports"
    end

    local target = string.lower(Trim(arg or ""))
    if target == "" or target == "latest" then
        return reports.items[#reports.items]
    end

    local targetId = tonumber(target)
    if targetId then
        local i
        for i = #reports.items, 1, -1 do
            if tonumber(reports.items[i].id) == targetId then
                return reports.items[i]
            end
        end
        return nil, "saved report not found: #" .. tostring(targetId)
    end

    if not string.find(target, "%-") then
        target = MakePlayerKey(target, GetRealmName() or "")
    end

    local i
    for i = #reports.items, 1, -1 do
        if reports.items[i].key == target then
            return reports.items[i]
        end
    end

    return nil, "saved report not found: " .. target
end

function addon:SetButtonMode(mode)
    if not BUTTON_MODE_LABELS[mode] then
        return false
    end

    RaidInspectorDB.state.ui.buttonMode = mode
    if addon.ApplyButtonModeLayout then
        addon:ApplyButtonModeLayout()
    end
    addon:RefreshMainWindow()
    return true
end

function addon:SetItemListFilterMode(mode)
    if not ITEM_LIST_FILTER_LABELS[mode] then
        return false
    end
    RaidInspectorDB.state.ui.itemListFilterMode = mode
    addon:RefreshMainWindow()
    return true
end

function addon:GetLatestRequestForKey(key)
    local i
    for i = #RaidInspectorDB.requests, 1, -1 do
        local req = RaidInspectorDB.requests[i]
        if req.key == key then
            return req
        end
    end
    return nil
end

function addon:GetLatestRequestMap()
    local latestByKey = {}
    local i
    local requestCount = 0

    for i = 1, #RaidInspectorDB.requests do
        local req = RaidInspectorDB.requests[i]
        if type(req) == "table" and req.key and req.key ~= "" then
            latestByKey[req.key] = req
            requestCount = requestCount + 1
        end
    end

    -- Only synthesize rows from raw results when there are no requests at all.
    -- This keeps old unrelated results from reappearing while actively inspecting others.
    if requestCount == 0 then
        local key
        for key in pairs(RaidInspectorDB.results) do
            if not latestByKey[key] then
                local result = RaidInspectorDB.results[key] or {}
                local n, r = ParseKey(key)
                latestByKey[key] = {
                    id = 0,
                    name = result.name or n or "Unknown",
                    realm = result.realm or r or "Unknown",
                    key = key,
                    status = result.error and "error" or "ready",
                    statusReason = result.error and tostring(result.error) or nil,
                    requestedAt = tonumber(result.fetchedAt) or tonumber(result.updatedAt) or 0,
                    updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0,
                }
            end
        end
    end

    return latestByKey
end

function addon:SetLatestRequestState(key, status, reason)
    local req = addon:GetLatestRequestForKey(key)
    if not req then
        return nil
    end

    req.status = status or req.status or "queued"
    req.statusReason = reason
    req.updatedAt = GetNow()
    return req
end

function addon:InitBridgeInbox()
    EnsureTable(RaidInspectorBridgeInbox, "schemaVersion", 1)
    EnsureTable(RaidInspectorBridgeInbox, "generatedAt", 0)
    EnsureTable(RaidInspectorBridgeInbox, "lastConsumedAt", 0)
    EnsureTable(RaidInspectorBridgeInbox, "results", {})
end

function addon:GetCounts()
    local queued, ready, errorCount = 0, 0, 0
    local latestByKey = addon:GetLatestRequestMap()
    local key

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
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

function addon:GetIssueTotals()
    local playersWithIssues, totalIssues = 0, 0
    local latestByKey = addon:GetLatestRequestMap()
    local key

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
        local result = RaidInspectorDB.results[req.key]
        if result and tonumber(result.issuesCount or 0) and tonumber(result.issuesCount or 0) > 0 then
            playersWithIssues = playersWithIssues + 1
            totalIssues = totalIssues + tonumber(result.issuesCount)
        end
    end

    return playersWithIssues, totalIssues
end

function addon:GetFreshnessCounts(ttlSeconds)
    local fresh, stale = 0, 0
    local now = GetNow()
    local latestByKey = addon:GetLatestRequestMap()
    local key

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
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

function addon:QueueInspect(name, realm, opts)
    opts = opts or {}
    local allowDuplicate = opts.allowDuplicate ~= false
    local silent = opts.silent == true
    local queueReason = opts.reason or "queued-manual"

    local normalizedName = Trim(name)
    local normalizedRealm = Trim(realm)

    if normalizedName == "" then
        if not silent then
            Print("missing player name. usage: /ri inspect <name> <realm>")
        end
        return false
    end

    if normalizedRealm == "" then
        normalizedRealm = GetCVar("realmName") or ""
    end

    if normalizedRealm == "" then
        if not silent then
            Print("missing realm. usage: /ri inspect <name> <realm>")
        end
        return false
    end

    local key = MakePlayerKey(normalizedName, normalizedRealm)
    if not allowDuplicate and addon:GetLatestRequestForKey(key) then
        return false
    end

    local id = RaidInspectorDB.state.nextRequestId

    table.insert(RaidInspectorDB.requests, {
        id = id,
        name = normalizedName,
        realm = normalizedRealm,
        key = key,
        status = "queued",
        statusReason = queueReason,
        requestedAt = GetNow(),
        updatedAt = GetNow(),
    })

    RaidInspectorDB.state.nextRequestId = id + 1
    if not silent then
        Print("queued: " .. normalizedName .. "-" .. normalizedRealm .. " (#" .. id .. ")")
    end

    if addon.RefreshMainWindow then
        addon:RefreshMainWindow()
    end

    return true
end

function addon:QueueRaidSnapshot()
    if not GetNumRaidMembers or GetNumRaidMembers() <= 0 then
        Print("not in a raid")
        return
    end

    local count = GetNumRaidMembers()
    local queued = 0
    local skipped = 0
    local liveQueued = 0
    local liveSkipped = 0
    local members = {}
    local i

    for i = 1, count do
        local rosterName = GetRaidRosterInfo(i)
        if rosterName and rosterName ~= "" then
            local name = rosterName
            local explicitRealm = GetRealmName() or ""
            local splitName, splitRealm = string.match(rosterName, "^([^%-]+)%-(.+)$")
            if splitName and splitRealm then
                name = splitName
                explicitRealm = splitRealm
            end

            local key = MakePlayerKey(name, explicitRealm)
            members[key] = true
            if addon:QueueInspect(name, explicitRealm, { allowDuplicate = false, silent = true, reason = "queued-snapshot" }) then
                queued = queued + 1
            else
                skipped = skipped + 1
            end

            local unit = "raid" .. tostring(i)
            local okLive, liveReason = addon:QueueLiveInspectUnit(unit, false)
            if okLive then
                liveQueued = liveQueued + 1
            else
                liveSkipped = liveSkipped + 1
                if liveReason == "cannot-inspect" or liveReason == "unit-not-found" then
                    addon:SetLatestRequestState(key, "queued", liveReason)
                end
            end
        end
    end

    local snapshotAt = GetNow()
    RaidInspectorDB.state.lastSnapshot.at = snapshotAt
    RaidInspectorDB.state.lastSnapshot.members = members
    addon:CreateRaidHistoryEntry(snapshotAt, members)

    addon:ProcessInspectQueue(true)
    Print("raid snapshot: queued=" .. queued .. ", skipped=" .. skipped .. ", total=" .. count .. " | live=" .. liveQueued .. ", liveSkipped=" .. liveSkipped)
    addon:RefreshMainWindow()
end

function addon:QueueStaleRefresh(minAgeMinutes)
    local minMinutes = tonumber(minAgeMinutes) or 30
    if minMinutes < 1 then
        minMinutes = 1
    end

    local now = GetNow()
    local queued = 0
    local seen = {}
    local i

    for i = #RaidInspectorDB.requests, 1, -1 do
        local req = RaidInspectorDB.requests[i]
        if not seen[req.key] then
            seen[req.key] = req
        end
    end

    local key
    for key in pairs(seen) do
        local req = seen[key]
        local result = RaidInspectorDB.results[key]
        if result then
            local updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
            local ageMinutes = math.floor(math.max(0, now - updatedAt) / 60)
            if updatedAt <= 0 or ageMinutes >= minMinutes then
                if addon:QueueInspect(req.name, req.realm, { allowDuplicate = true, silent = true, reason = "queued-refresh" }) then
                    queued = queued + 1
                end
            end
        end
    end

    Print("stale refresh: queued " .. queued .. " player(s), threshold=" .. minMinutes .. "m")
    addon:RefreshMainWindow()
end

function addon:GetSnapshotProgress()
    local snapshot = RaidInspectorDB.state.lastSnapshot
    if type(snapshot) ~= "table" or type(snapshot.members) ~= "table" then
        return nil
    end

    local total = 0
    local ready = 0
    local stale = 0
    local missing = 0
    local now = GetNow()
    local key

    for key in pairs(snapshot.members) do
        total = total + 1
        local result = RaidInspectorDB.results[key]
        if not result then
            missing = missing + 1
        else
            local updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
            if updatedAt > 0 and (now - updatedAt) <= FRESHNESS_TTL_SECONDS then
                ready = ready + 1
            else
                stale = stale + 1
            end
        end
    end

    if total == 0 then
        return nil
    end

    return {
        total = total,
        ready = ready,
        stale = stale,
        missing = missing,
        at = tonumber(snapshot.at) or 0,
    }
end

function addon:QueueTarget()
    if not UnitExists("target") then
        Print("no target selected")
        return
    end

    local name, targetRealm = UnitName("target")
    local realm = targetRealm
    if not realm or realm == "" then
        realm = GetRealmName() or ""
    end

    if not name or name == "" then
        Print("target has no valid name")
        return
    end

    if realm == "" then
        Print("target has no valid realm")
        return
    end

    local key = MakePlayerKey(name, realm)

    addon:QueueInspect(name, realm, { allowDuplicate = false, silent = true, reason = "queued-target" })
    addon:SetSelectedKey(key)
    local okLive, reason = addon:QueueLiveInspectUnit("target", false)
    addon:ProcessInspectQueue(true)
    addon:RefreshMainWindow()

    if reason == "cannot-inspect" or reason == "unit-not-found" then
        addon:SetLatestRequestState(key, "queued", reason)
    end

    if okLive then
        Print("target queued + live inspect: " .. name .. "-" .. realm)
    elseif reason == "cannot-inspect" then
        Print("target queued, but not inspectable right now (range/permissions)")
    else
        Print("target queued: " .. name .. "-" .. realm)
    end
end

function addon:ApplyBridgeResult(key, payload)
    if type(payload) ~= "table" then
        return false
    end

    local nameFromKey, realmFromKey = ParseKey(key)
    local normalizedKey = string.lower(key)
    local previous = RaidInspectorDB.results[normalizedKey]

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
    result.estimatedGearScore = payload.estimatedGearScore
    result.achievementPoints = payload.achievementPoints
    result.achievementPointsSource = payload.achievementPointsSource or ((payload.achievementPoints ~= nil) and (payload.source or "bridge") or nil)
    result.raidAchievements = CopyTable(payload.raidAchievements or {})
    result.issuesCount = tonumber(payload.issuesCount) or 0
    result.issueSummary = CopyTable(payload.issueSummary or {})
    result.error = payload.error
    result.source = payload.source or "bridge"
    result.raw = CopyTable(payload.raw)
    result.fetchedAt = tonumber(payload.fetchedAt) or GetNow()
    result.updatedAt = tonumber(payload.updatedAt) or GetNow()

    if type(previous) == "table" then
        if (not result.spec or result.spec == "") and previous.spec and previous.spec ~= "" then
            result.spec = previous.spec
        end

        if result.achievementPoints == nil and previous.achievementPoints ~= nil then
            result.achievementPoints = previous.achievementPoints
            result.achievementPointsSource = previous.achievementPointsSource
        elseif (not result.achievementPointsSource or result.achievementPointsSource == "")
            and previous.achievementPoints ~= nil and previous.achievementPointsSource then
            result.achievementPointsSource = previous.achievementPointsSource
        end

        if type(result.raidAchievements) ~= "table" then
            result.raidAchievements = {}
        end

        local hasKnownNew = false
        local rk
        for _, rk in ipairs(RAID_ACHIEVEMENT_KEYS) do
            local v = result.raidAchievements[rk]
            if v == true or v == false then
                hasKnownNew = true
                break
            end
        end

        if type(previous.raidAchievements) == "table" then
            if not hasKnownNew then
                result.raidAchievements = CopyTable(previous.raidAchievements)
            else
                for _, rk in ipairs(RAID_ACHIEVEMENT_KEYS) do
                    if result.raidAchievements[rk] == nil then
                        local pv = previous.raidAchievements[rk]
                        if pv == true or pv == false then
                            result.raidAchievements[rk] = pv
                        end
                    end
                end
                if (not result.raidAchievements.source or result.raidAchievements.source == "")
                    and previous.raidAchievements.source then
                    result.raidAchievements.source = previous.raidAchievements.source
                end
            end
        end
    end

    RaidInspectorDB.results[normalizedKey] = result

    local i
    for i = 1, #RaidInspectorDB.requests do
        local req = RaidInspectorDB.requests[i]
        if req.key == normalizedKey then
            req.status = result.error and "error" or "ready"
            req.statusReason = result.error and (result.error or "bridge-error") or nil
            req.updatedAt = GetNow()
        end
    end

    addon:RefreshActiveRaidHistoryEntry()

    return true
end

function addon:ApplyBridgeAchievementEnrichment(key, payload)
    if type(payload) ~= "table" then
        return false
    end

    local normalizedKey = string.lower(key or "")
    local existing = RaidInspectorDB.results[normalizedKey]
    if type(existing) ~= "table" then
        return false
    end

    local payloadHasAP = payload.achievementPoints ~= nil
    local payloadHasRaid = HasCompleteRaidAchievementFlags(payload.raidAchievements)
    if not payloadHasAP and not payloadHasRaid then
        return false
    end

    local existingHasAP = existing.achievementPoints ~= nil
    local existingHasRaid = HasCompleteRaidAchievementFlags(existing.raidAchievements)
    if existingHasAP and existingHasRaid then
        return false
    end

    local changed = false

    if not existingHasAP and payload.achievementPoints ~= nil then
        local apValue = tonumber(payload.achievementPoints)
        existing.achievementPoints = apValue or payload.achievementPoints
        existing.achievementPointsSource = payload.achievementPointsSource or payload.source or "bridge"
        changed = true
    end

    if type(payload.raidAchievements) == "table" then
        if type(existing.raidAchievements) ~= "table" then
            existing.raidAchievements = {}
        end

        local rk
        for _, rk in ipairs(RAID_ACHIEVEMENT_KEYS) do
            if existing.raidAchievements[rk] == nil then
                local v = payload.raidAchievements[rk]
                if v == true or v == false then
                    existing.raidAchievements[rk] = v
                    changed = true
                end
            end
        end

        if (not existing.raidAchievements.source or existing.raidAchievements.source == "")
            and payload.raidAchievements.source then
            existing.raidAchievements.source = payload.raidAchievements.source
            changed = true
        end
    end

    if not changed then
        return false
    end

    existing.updatedAt = GetNow()

    local req = addon:GetLatestRequestForKey(normalizedKey)
    if req then
        req.status = "ready"
        req.statusReason = nil
        req.updatedAt = GetNow()
    end

    addon:RefreshActiveRaidHistoryEntry()

    return true
end

function addon:ConsumeBridgeInbox(silent, force)
    addon:InitBridgeInbox()

    if type(RaidInspectorBridgeInbox.results) ~= "table" or next(RaidInspectorBridgeInbox.results) == nil then
        return 0
    end

    local generatedAt = tonumber(RaidInspectorBridgeInbox.generatedAt) or 0
    local lastImported = tonumber(RaidInspectorDB.meta.lastImportedBridgeGeneratedAt) or 0
    local staleEnrichmentOnly = (not force and generatedAt > 0 and generatedAt <= lastImported)

    local imported = 0
    local key
    for key in pairs(RaidInspectorBridgeInbox.results) do
        local payload = RaidInspectorBridgeInbox.results[key]
        local normalizedKey = string.lower(key)
        local applied = false

        if staleEnrichmentOnly then
            if type(RaidInspectorDB.results[normalizedKey]) == "table" then
                applied = addon:ApplyBridgeAchievementEnrichment(normalizedKey, payload)
            else
                applied = addon:ApplyBridgeResult(normalizedKey, payload)
            end
        else
            applied = addon:ApplyBridgeResult(normalizedKey, payload)
        end

        if applied then
            imported = imported + 1
        end
    end

    if staleEnrichmentOnly and imported == 0 then
        return 0
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

function addon:GetOverviewEntries()
    local latestByKey = addon:GetLatestRequestMap()

    local entries = {}
    local key
    local now = GetNow()

    for key in pairs(latestByKey) do
        local req = latestByKey[key]
        local result = RaidInspectorDB.results[key]
        local state = req.status or "queued"
        local updatedAt = 0

        if state ~= "error" and result then
            state = "ready"
        end

        if result then
            updatedAt = tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0
        end

        table.insert(entries, {
            key = key,
            req = req,
            result = result,
            state = state,
            statusReason = req.statusReason,
            updatedAt = updatedAt,
            ageMinutes = updatedAt > 0 and math.floor(math.max(0, now - updatedAt) / 60) or -1,
            isFresh = updatedAt > 0 and (now - updatedAt) <= FRESHNESS_TTL_SECONDS,
        })
    end

    local filterMode = addon:GetFilterMode()
    local filtered = {}
    for i = 1, #entries do
        local entry = entries[i]
        local include = true
        local issuesCount = entry.result and tonumber(entry.result.issuesCount or 0) or 0

        if filterMode == "snapshot" then
            local snapshot = RaidInspectorDB.state.lastSnapshot
            include = type(snapshot) == "table"
                and type(snapshot.members) == "table"
                and snapshot.members[entry.key] == true
        elseif filterMode == "ready" then
            include = entry.state == "ready"
        elseif filterMode == "queued" then
            include = entry.state == "queued"
        elseif filterMode == "issues" then
            include = issuesCount > 0
        end

        if include then
            table.insert(filtered, entry)
        end
    end

    local sortMode = addon:GetSortMode()
    table.sort(filtered, function(a, b)
        local aIssues = a.result and tonumber(a.result.issuesCount or 0) or 0
        local bIssues = b.result and tonumber(b.result.issuesCount or 0) or 0
        local aGs = a.result and tonumber(a.result.gearScore or -1) or -1
        local bGs = b.result and tonumber(b.result.gearScore or -1) or -1
        local aId = tonumber(a.req.id) or 0
        local bId = tonumber(b.req.id) or 0

        if sortMode == "gs" then
            if aGs ~= bGs then
                return aGs > bGs
            end
            return aId > bId
        end

        if sortMode == "issues" then
            if aIssues ~= bIssues then
                return aIssues > bIssues
            end
            return aId > bId
        end

        if sortMode == "name" then
            local aName = string.lower((a.req.name or "") .. "-" .. (a.req.realm or ""))
            local bName = string.lower((b.req.name or "") .. "-" .. (b.req.realm or ""))
            return aName < bName
        end

        return aId > bId
    end)

    return filtered
end

function addon:SetSelectedKey(key)
    RaidInspectorDB.state.ui.selectedKey = key or ""
end

function addon:GetSelectedKey()
    return RaidInspectorDB.state.ui.selectedKey or ""
end

function addon:CycleSortMode()
    local mode = addon:GetSortMode()
    local i
    for i = 1, #SORT_MODES do
        if SORT_MODES[i] == mode then
            local nextIndex = i + 1
            if nextIndex > #SORT_MODES then
                nextIndex = 1
            end
            RaidInspectorDB.settings.overview.sortMode = SORT_MODES[nextIndex]
            addon:RefreshMainWindow()
            return
        end
    end
    RaidInspectorDB.settings.overview.sortMode = SORT_MODES[1]
    addon:RefreshMainWindow()
end

function addon:CycleFilterMode()
    local mode = addon:GetFilterMode()
    local i
    for i = 1, #FILTER_MODES do
        if FILTER_MODES[i] == mode then
            local nextIndex = i + 1
            if nextIndex > #FILTER_MODES then
                nextIndex = 1
            end
            RaidInspectorDB.settings.overview.filterMode = FILTER_MODES[nextIndex]
            addon:RefreshMainWindow()
            return
        end
    end
    RaidInspectorDB.settings.overview.filterMode = FILTER_MODES[1]
    addon:RefreshMainWindow()
end

function addon:SetSortMode(mode)
    if not SORT_LABELS[mode] then
        return false
    end
    RaidInspectorDB.settings.overview.sortMode = mode
    addon:RefreshMainWindow()
    return true
end

function addon:SetFilterMode(mode)
    if not FILTER_LABELS[mode] then
        return false
    end
    RaidInspectorDB.settings.overview.filterMode = mode
    addon:RefreshMainWindow()
    return true
end

function addon:BuildOverviewRows(container, rowCount)
    container.rows = container.rows or {}
    local i
    local rowWidth = tonumber(container:GetWidth()) or 432

    for i = 1, rowCount do
        local row = CreateFrame("Button", nil, container)
        row:SetWidth(rowWidth)
        row:SetHeight(OVERVIEW_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * OVERVIEW_ROW_HEIGHT)
        row:SetFrameStrata("DIALOG")
        row:SetFrameLevel(40)
        row:RegisterForClicks("LeftButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", row, "LEFT", 2, 0)
        text:SetWidth(rowWidth - 4)
        text:SetHeight(OVERVIEW_ROW_HEIGHT)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("MIDDLE")
        text:SetText("")
        text:Show()

        row.text = text
        row.key = nil
        row:SetScript("OnClick", function(self)
            if self.key then
                addon:SetSelectedKey(self.key)
                addon:RefreshMainWindow()
            end
        end)

        container.rows[i] = row
    end
end

function addon:BuildDetailRows(container, rowCount)
    container.rows = container.rows or {}
    local i
    local rowWidth = tonumber(container:GetWidth()) or 442

    for i = 1, rowCount do
        local row = CreateFrame("Button", nil, container)
        row:SetWidth(rowWidth)
        row:SetHeight(DETAIL_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(i - 1) * DETAIL_ROW_HEIGHT)
        row:EnableMouse(true)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", row, "LEFT", 0, 0)
        text:SetWidth(rowWidth)
        text:SetHeight(DETAIL_ROW_HEIGHT)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("MIDDLE")
        text:SetText("")

        row.text = text
        row.data = nil
        row:SetScript("OnEnter", function(self)
            addon:ShowDetailRowTooltip(self)
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)

        container.rows[i] = row
    end
end

function addon:ApplyButtonModeLayout()
    if not addon.ui or not addon.ui.actionPanel then
        return
    end

    local mode = addon:GetButtonMode()
    local buttons = {
        sort = addon.ui.sortButton,
        filter = addon.ui.filterButton,
        target = addon.ui.targetButton,
        raid = addon.ui.raidButton,
        sync = addon.ui.syncButton,
        force = addon.ui.forceSyncButton,
        export = addon.ui.exportButton,
        stale = addon.ui.staleButton,
        status = addon.ui.statusButton,
        clear = addon.ui.clearButton,
    }

    local visible = {
        sort = true,
        filter = true,
        target = true,
        raid = true,
        sync = true,
        force = true,
        export = true,
        stale = true,
        status = true,
        clear = true,
    }

    local order = { "sort", "filter", "target", "raid", "sync", "force", "export", "stale", "status", "clear" }
    if mode == "easy" then
        visible.sync = false
        visible.force = false
        visible.stale = false
        order = { "sort", "filter", "target", "raid", "status", "export", "clear" }
    end

    local key, button
    for key, button in pairs(buttons) do
        if button then
            if visible[key] then
                button:Show()
            else
                button:Hide()
            end
        end
    end

    if buttons.status then
        if mode == "easy" then
            buttons.status:SetText("|cffffaa33Display|r")
        else
            buttons.status:SetText("|cffffaa33Status|r")
        end
    end

    local index = 0
    local i
    for i = 1, #order do
        key = order[i]
        button = buttons[key]
        if button and visible[key] then
            local col = index % 2
            local row = math.floor(index / 2)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", addon.ui.actionPanel, "TOPLEFT", col * 106, -(row * 26))
            index = index + 1
        end
    end
end

local function BuildInspectItemHyperlink(item)
    local itemId = tonumber(item and item.itemId)
    if not itemId then
        return nil
    end

    local enchantId = tonumber(item.enchantId) or 0
    local gem1, gem2, gem3 = 0, 0, 0
    if type(item.gems) == "table" then
        gem1 = tonumber(item.gems[1]) or 0
        gem2 = tonumber(item.gems[2]) or 0
        gem3 = tonumber(item.gems[3]) or 0
    end

    return "item:" .. tostring(itemId)
        .. ":" .. tostring(enchantId)
        .. ":" .. tostring(gem1)
        .. ":" .. tostring(gem2)
        .. ":" .. tostring(gem3)
        .. ":0:0:0"
end

function addon:ShowDetailRowTooltip(row)
    if not row or type(row.data) ~= "table" or type(row.data.item) ~= "table" or not GameTooltip then
        return
    end

    local data = row.data
    local item = data.item
    local slotLabel = SLOT_LABELS[data.slotKey or ""] or tostring(data.slotKey or "Item")
    local itemLink = BuildInspectItemHyperlink(item)

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if itemLink then
        GameTooltip:SetHyperlink(itemLink)
    else
        local itemName = item.name or (item.itemId and ("item:" .. tostring(item.itemId))) or "Unknown item"
        GameTooltip:ClearLines()
        GameTooltip:AddLine(slotLabel .. ": " .. itemName, 1, 1, 1)
    end

    local enchantText = "n/a"
    if ENCHANTABLE_SLOTS[data.slotKey] then
        local enchantId = tonumber(item.enchantId)
        if not enchantId then
            if OPTIONAL_ENCHANT_SLOTS[data.slotKey] then
                enchantText = "optional"
            else
                enchantText = "missing"
            end
        elseif IsLowTierEnchant(item) then
            enchantText = "low tier (" .. tostring(enchantId) .. ")"
        else
            enchantText = "ok (" .. tostring(enchantId) .. ")"
        end
    end

    local socketCount = tonumber(item.socketCount) or 0
    local gems = type(item.gems) == "table" and item.gems or {}
    local gemCount = #gems

    if ENCHANTABLE_SLOTS[data.slotKey] or socketCount > 0 then
        GameTooltip:AddLine(" ")
        if ENCHANTABLE_SLOTS[data.slotKey] then
            GameTooltip:AddLine("Enchant: " .. enchantText, 0.9, 0.9, 0.9)
        end
        if socketCount > 0 then
            GameTooltip:AddLine("Sockets: " .. tostring(gemCount) .. "/" .. tostring(socketCount), 0.9, 0.9, 0.9)
            local idx
            for idx = 1, socketCount do
                local gemId = tonumber(gems[idx])
                if gemId and gemId > 0 then
                    local gemName = GetItemInfo(gemId)
                    if not gemName or gemName == "" then
                        gemName = "item:" .. tostring(gemId)
                    end
                    GameTooltip:AddLine("  Gem " .. tostring(idx) .. ": " .. tostring(gemName), 0.5, 1, 0.5)
                else
                    GameTooltip:AddLine("  Gem " .. tostring(idx) .. ": missing", 1, 0.3, 0.3)
                end
            end
        end
    end

    GameTooltip:Show()
end

function addon:CreateMainWindow()
    if addon.ui and addon.ui.frame then
        return
    end

    addon.ui = addon.ui or {}

    local f = CreateFrame("Frame", "RaidInspectorMainFrame", UIParent)
    f:SetWidth(WINDOW_WIDTH)
    f:SetHeight(WINDOW_HEIGHT)
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

    local modeDropDown = CreateFrame("Frame", "RaidInspectorButtonModeDropDown", f, "UIDropDownMenuTemplate")
    modeDropDown:SetPoint("LEFT", title, "RIGHT", 18, -2)
    UIDropDownMenu_SetWidth(modeDropDown, 120)
    UIDropDownMenu_JustifyText(modeDropDown, "LEFT")
    UIDropDownMenu_Initialize(modeDropDown, function(_, level)
        if level ~= 1 then
            return
        end

        local i
        for i = 1, #BUTTON_MODES do
            local mode = BUTTON_MODES[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = BUTTON_MODE_LABELS[mode] or mode
            info.value = mode
            info.checked = (addon:GetButtonMode() == mode)
            info.func = function(btn)
                local selectedMode = btn.value
                addon:SetButtonMode(selectedMode)
                UIDropDownMenu_SetSelectedValue(modeDropDown, selectedMode)
                UIDropDownMenu_SetText(modeDropDown, BUTTON_MODE_LABELS[selectedMode] or selectedMode)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local selectedButtonMode = addon:GetButtonMode()
    UIDropDownMenu_SetSelectedValue(modeDropDown, selectedButtonMode)
    UIDropDownMenu_SetText(modeDropDown, BUTTON_MODE_LABELS[selectedButtonMode] or selectedButtonMode)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("Raid overview + selected player details")

    local closeButton = CreateFrame("Button", "RaidInspectorCloseButton", f, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)

    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -10)
    statusText:SetJustifyH("LEFT")
    statusText:SetWidth(WINDOW_WIDTH - (PANEL_SIDE_MARGIN * 2))
    statusText:SetText("")

    local function SetActionButtonLabel(button, colorCode, plainText)
        button:SetText("|c" .. colorCode .. plainText .. "|r")
    end

    local function ActivateActionButton(button)
        button:EnableMouse(true)
        button:SetFrameStrata("DIALOG")
        button:SetFrameLevel(80)
    end

    local exportChannelsRow = CreateFrame("Frame", nil, f)
    exportChannelsRow:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -8)
    exportChannelsRow:SetWidth(320)
    exportChannelsRow:SetHeight(20)

    local exportChannelsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    exportChannelsLabel:SetPoint("LEFT", exportChannelsRow, "LEFT", 0, 0)
    exportChannelsLabel:SetText("Export:")

    local exportRaidCheck = CreateFrame("CheckButton", "RaidInspectorExportRaidCheck", f, "UICheckButtonTemplate")
    exportRaidCheck:SetPoint("LEFT", exportChannelsLabel, "RIGHT", 6, -1)
    local exportRaidText = _G["RaidInspectorExportRaidCheckText"]
    if exportRaidText then
        exportRaidText:SetText("Raid")
    end

    local exportSayCheck = CreateFrame("CheckButton", "RaidInspectorExportSayCheck", f, "UICheckButtonTemplate")
    exportSayCheck:SetPoint("LEFT", exportRaidCheck, "RIGHT", 42, 0)
    local exportSayText = _G["RaidInspectorExportSayCheckText"]
    if exportSayText then
        exportSayText:SetText("Say")
    end

    local exportWhisperCheck = CreateFrame("CheckButton", "RaidInspectorExportWhisperCheck", f, "UICheckButtonTemplate")
    exportWhisperCheck:SetPoint("LEFT", exportSayCheck, "RIGHT", 38, 0)
    local exportWhisperText = _G["RaidInspectorExportWhisperCheckText"]
    if exportWhisperText then
        exportWhisperText:SetText("Whisper")
    end

    local exportChannels = addon:GetExportChannels()
    exportRaidCheck:SetChecked(exportChannels.raid and true or false)
    exportSayCheck:SetChecked(exportChannels.say and true or false)
    exportWhisperCheck:SetChecked(exportChannels.whisper and true or false)

    exportRaidCheck:SetScript("OnClick", function(self)
        addon:SetExportChannel("raid", self:GetChecked() and true or false)
    end)
    exportSayCheck:SetScript("OnClick", function(self)
        addon:SetExportChannel("say", self:GetChecked() and true or false)
    end)
    exportWhisperCheck:SetScript("OnClick", function(self)
        addon:SetExportChannel("whisper", self:GetChecked() and true or false)
    end)

    local actionPanel = CreateFrame("Frame", nil, f)
    actionPanel:SetPoint("TOPLEFT", exportChannelsRow, "BOTTOMLEFT", 0, -6)
    actionPanel:SetWidth(214)
    actionPanel:SetHeight(130)

    local sortButton = CreateFrame("Button", "RaidInspectorSortButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(sortButton)
    sortButton:SetWidth(100)
    sortButton:SetHeight(20)
    sortButton:SetPoint("TOPLEFT", actionPanel, "TOPLEFT", 0, 0)
    SetActionButtonLabel(sortButton, "ff66ff66", "S:recent")
    sortButton:SetScript("OnClick", function()
        SafeInvoke("sort", function()
            addon:CycleSortMode()
        end)
    end)

    local filterButton = CreateFrame("Button", "RaidInspectorFilterButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(filterButton)
    filterButton:SetWidth(100)
    filterButton:SetHeight(20)
    filterButton:SetPoint("LEFT", sortButton, "RIGHT", 6, 0)
    SetActionButtonLabel(filterButton, "ff66ff66", "F:all")
    filterButton:SetScript("OnClick", function()
        SafeInvoke("filter", function()
            addon:CycleFilterMode()
        end)
    end)

    local targetButton = CreateFrame("Button", "RaidInspectorTargetButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(targetButton)
    targetButton:SetWidth(100)
    targetButton:SetHeight(20)
    targetButton:SetPoint("TOPLEFT", sortButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(targetButton, "ff66ff66", "Target")
    targetButton:SetScript("OnClick", function()
        SafeInvoke("target", function()
            addon:QueueTarget()
        end)
    end)

    local raidButton = CreateFrame("Button", "RaidInspectorRaidButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(raidButton)
    raidButton:SetWidth(100)
    raidButton:SetHeight(20)
    raidButton:SetPoint("LEFT", targetButton, "RIGHT", 6, 0)
    SetActionButtonLabel(raidButton, "ff66ff66", "Raid")
    raidButton:SetScript("OnClick", function()
        SafeInvoke("raid", function()
            addon:QueueRaidSnapshot()
        end)
    end)

    local syncButton = CreateFrame("Button", "RaidInspectorSyncButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(syncButton)
    syncButton:SetWidth(100)
    syncButton:SetHeight(20)
    syncButton:SetPoint("TOPLEFT", targetButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(syncButton, "ff66ff66", "Sync")
    syncButton:SetScript("OnClick", function()
        SafeInvoke("sync", function()
            local imported = addon:ConsumeBridgeInbox(false, false)
            if imported == 0 then
                Print("sync complete: no new bridge results found")
            end
        end)
    end)

    local forceSyncButton = CreateFrame("Button", "RaidInspectorForceSyncButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(forceSyncButton)
    forceSyncButton:SetWidth(100)
    forceSyncButton:SetHeight(20)
    forceSyncButton:SetPoint("LEFT", syncButton, "RIGHT", 6, 0)
    SetActionButtonLabel(forceSyncButton, "ff66ff66", "Force")
    forceSyncButton:SetScript("OnClick", function()
        SafeInvoke("forcesync", function()
            local imported = addon:ConsumeBridgeInbox(false, true)
            if imported == 0 then
                Print("force sync complete: no bridge results found")
            end
        end)
    end)

    local exportButton = CreateFrame("Button", "RaidInspectorExportButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(exportButton)
    exportButton:SetWidth(100)
    exportButton:SetHeight(20)
    exportButton:SetPoint("TOPLEFT", syncButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(exportButton, "ff66ff66", "Export")
    exportButton:SetScript("OnClick", function()
        SafeInvoke("export", function()
            addon:ExportSummary("")
        end)
    end)

    local staleButton = CreateFrame("Button", "RaidInspectorStaleButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(staleButton)
    staleButton:SetWidth(100)
    staleButton:SetHeight(20)
    staleButton:SetPoint("LEFT", exportButton, "RIGHT", 6, 0)
    SetActionButtonLabel(staleButton, "ffffaa33", "Stale")
    staleButton:SetScript("OnClick", function()
        SafeInvoke("stale", function()
            addon:QueueStaleRefresh("15")
        end)
    end)

    local statusButton = CreateFrame("Button", "RaidInspectorStatusButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(statusButton)
    statusButton:SetWidth(100)
    statusButton:SetHeight(20)
    statusButton:SetPoint("TOPLEFT", exportButton, "BOTTOMLEFT", 0, -6)
    SetActionButtonLabel(statusButton, "ffffaa33", "Status")
    statusButton:SetScript("OnClick", function()
        SafeInvoke("status", function()
            addon:PrintStatus()
            addon:RefreshMainWindow()
        end)
    end)

    local clearButton = CreateFrame("Button", "RaidInspectorClearButton", f, "UIPanelButtonTemplate")
    ActivateActionButton(clearButton)
    clearButton:SetWidth(100)
    clearButton:SetHeight(20)
    clearButton:SetPoint("LEFT", statusButton, "RIGHT", 6, 0)
    SetActionButtonLabel(clearButton, "ffffaa33", "Clear")
    clearButton:SetScript("OnClick", function()
        SafeInvoke("clear", function()
            addon:RequestClearQueue()
        end)
    end)

    local rowsContainer = CreateFrame("Frame", nil, f)
    rowsContainer:SetPoint("TOPLEFT", actionPanel, "BOTTOMLEFT", 0, -10)
    rowsContainer:SetWidth(432)
    rowsContainer:SetHeight(300)
    if rowsContainer.SetClipsChildren then
        rowsContainer:SetClipsChildren(true)
    end
    addon:BuildOverviewRows(rowsContainer, 18)

    local overviewScroll = CreateFrame("ScrollFrame", "RaidInspectorOverviewScroll", rowsContainer, "FauxScrollFrameTemplate")
    overviewScroll:SetPoint("TOPLEFT", rowsContainer, "TOPRIGHT", 0, -1)
    overviewScroll:SetPoint("BOTTOMLEFT", rowsContainer, "BOTTOMRIGHT", 0, 1)
    overviewScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, OVERVIEW_ROW_HEIGHT, function()
            addon:RefreshMainWindow()
        end)
    end)

    rowsContainer:EnableMouseWheel(true)
    rowsContainer:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, (addon.ui.overviewEntryCount or 0) - #rowsContainer.rows)
        local current = GetFauxScrollOffset(overviewScroll)
        local nextOffset = math.max(0, math.min(maxOffset, current - delta))
        if nextOffset ~= current then
            SetFauxScrollOffset(overviewScroll, nextOffset, OVERVIEW_ROW_HEIGHT)
            addon:RefreshMainWindow()
        end
    end)

    local rightPanelWidth = WINDOW_WIDTH - RIGHT_PANEL_X - PANEL_SIDE_MARGIN

    local detailHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailHeader:SetPoint("TOPLEFT", f, "TOPLEFT", RIGHT_PANEL_X, -136)
    detailHeader:SetWidth(rightPanelWidth)
    detailHeader:SetJustifyH("LEFT")
    detailHeader:SetText("Selected: none")

    local detailScore = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailScore:SetPoint("TOPLEFT", detailHeader, "BOTTOMLEFT", 0, -6)
    detailScore:SetWidth(rightPanelWidth)
    detailScore:SetJustifyH("LEFT")
    detailScore:SetText("")

    local detailMeta = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailMeta:SetPoint("TOPLEFT", detailScore, "BOTTOMLEFT", 0, -4)
    detailMeta:SetWidth(rightPanelWidth)
    detailMeta:SetJustifyH("LEFT")
    detailMeta:SetText("")
    if detailMeta.GetFont and detailMeta.SetFont then
        local fontName, fontHeight = detailMeta:GetFont()
        if fontName and fontHeight then
            detailMeta:SetFont(fontName, fontHeight, "OUTLINE")
        end
    end

    local detailAudit = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    detailAudit:SetPoint("TOPLEFT", detailMeta, "BOTTOMLEFT", 0, -4)
    detailAudit:SetWidth(rightPanelWidth)
    detailAudit:SetJustifyH("LEFT")
    detailAudit:SetText("")

    local itemFilterLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemFilterLabel:SetPoint("TOPLEFT", detailAudit, "BOTTOMLEFT", 0, -10)
    itemFilterLabel:SetWidth(70)
    itemFilterLabel:SetJustifyH("LEFT")
    itemFilterLabel:SetText("Item List:")

    local itemFilterDropDown = CreateFrame("Frame", "RaidInspectorItemListDropDown", f, "UIDropDownMenuTemplate")
    itemFilterDropDown:SetPoint("TOPLEFT", itemFilterLabel, "TOPLEFT", 62, 10)
    UIDropDownMenu_SetWidth(itemFilterDropDown, 170)
    UIDropDownMenu_JustifyText(itemFilterDropDown, "LEFT")
    UIDropDownMenu_Initialize(itemFilterDropDown, function(_, level)
        if level ~= 1 then
            return
        end

        local i
        for i = 1, #ITEM_LIST_FILTER_MODES do
            local mode = ITEM_LIST_FILTER_MODES[i]
            local info = UIDropDownMenu_CreateInfo()
            info.text = ITEM_LIST_FILTER_LABELS[mode] or mode
            info.value = mode
            info.checked = (addon:GetItemListFilterMode() == mode)
            info.func = function(btn)
                local selectedMode = btn.value
                addon:SetItemListFilterMode(selectedMode)
                UIDropDownMenu_SetSelectedValue(itemFilterDropDown, selectedMode)
                UIDropDownMenu_SetText(itemFilterDropDown, ITEM_LIST_FILTER_LABELS[selectedMode] or selectedMode)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    local selectedItemFilter = addon:GetItemListFilterMode()
    UIDropDownMenu_SetSelectedValue(itemFilterDropDown, selectedItemFilter)
    UIDropDownMenu_SetText(itemFilterDropDown, ITEM_LIST_FILTER_LABELS[selectedItemFilter] or selectedItemFilter)

    local detailContainer = CreateFrame("Frame", nil, f)
    detailContainer:SetPoint("TOPLEFT", itemFilterLabel, "BOTTOMLEFT", 0, -10)
    detailContainer:SetWidth(rightPanelWidth)
    detailContainer:SetHeight(250)
    if detailContainer.SetClipsChildren then
        detailContainer:SetClipsChildren(true)
    end
    addon:BuildDetailRows(detailContainer, 13)

    local detailScroll = CreateFrame("ScrollFrame", "RaidInspectorDetailScroll", detailContainer, "FauxScrollFrameTemplate")
    detailScroll:SetPoint("TOPLEFT", detailContainer, "TOPRIGHT", 0, -1)
    detailScroll:SetPoint("BOTTOMLEFT", detailContainer, "BOTTOMRIGHT", 0, 1)
    detailScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, DETAIL_ROW_HEIGHT, function()
            if addon.ui.lastDetailEntry then
                addon:RefreshDetailPanel(addon.ui.lastDetailEntry)
            end
        end)
    end)

    detailContainer:EnableMouseWheel(true)
    detailContainer:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, (addon.ui.detailLineCount or 0) - #detailContainer.rows)
        local current = GetFauxScrollOffset(detailScroll)
        local nextOffset = math.max(0, math.min(maxOffset, current - delta))
        if nextOffset ~= current then
            SetFauxScrollOffset(detailScroll, nextOffset, DETAIL_ROW_HEIGHT)
            if addon.ui.lastDetailEntry then
                addon:RefreshDetailPanel(addon.ui.lastDetailEntry)
            end
        end
    end)

    addon.ui.frame = f
    addon.ui.modeDropDown = modeDropDown
    addon.ui.statusText = statusText
    addon.ui.actionPanel = actionPanel
    addon.ui.sortButton = sortButton
    addon.ui.filterButton = filterButton
    addon.ui.targetButton = targetButton
    addon.ui.raidButton = raidButton
    addon.ui.syncButton = syncButton
    addon.ui.forceSyncButton = forceSyncButton
    addon.ui.exportButton = exportButton
    addon.ui.staleButton = staleButton
    addon.ui.statusButton = statusButton
    addon.ui.clearButton = clearButton
    addon.ui.exportChannelsLabel = exportChannelsLabel
    addon.ui.exportRaidCheck = exportRaidCheck
    addon.ui.exportSayCheck = exportSayCheck
    addon.ui.exportWhisperCheck = exportWhisperCheck
    addon.ui.overviewRows = rowsContainer.rows
    addon.ui.overviewScroll = overviewScroll
    addon.ui.overviewEntryCount = 0
    addon.ui.detailHeader = detailHeader
    addon.ui.detailScore = detailScore
    addon.ui.detailMeta = detailMeta
    addon.ui.detailAudit = detailAudit
    addon.ui.itemFilterDropDown = itemFilterDropDown
    addon.ui.detailRows = detailContainer.rows
    addon.ui.detailScroll = detailScroll
    addon.ui.detailLineCount = 0
    addon.ui.lastDetailKey = ""
    addon.ui.lastDetailEntry = nil

    addon:ApplyButtonModeLayout()

    f:Hide()
end

function addon:CreateMinimapButton()
    if addon.ui and addon.ui.minimapButton then
        addon.ui.minimapButton:Hide()
        addon.ui.minimapButton = nil
    end

    if RaidInspectorMinimapButton then
        RaidInspectorMinimapButton:Hide()
    end
end

function addon:BuildOverviewRowText(entry)
    local req = entry.req
    local result = entry.result
    local state = entry.state
    local reqId = tonumber(req.id) or 0
    local reqName = req.name or "Unknown"
    local reqRealm = req.realm or "Unknown"

    local gsText = "-"
    if result and result.gearScore then
        gsText = ColorText(tostring(result.gearScore), GetGearScoreColorCode(result.gearScore))
    end

    local ageText = ""
    if entry.ageMinutes >= 0 then
        ageText = " Scanned=" .. tostring(entry.ageMinutes) .. "m"
    end

    local issueSummary = result and result.issueSummary or {}
    local missingEnchant = tonumber(issueSummary.missingEnchant or 0) or 0
    local missingGems = tonumber(issueSummary.missingGems or 0) or 0
    local auditText = ""
    if missingEnchant > 0 or missingGems > 0 then
        auditText = " E" .. tostring(missingEnchant) .. " G" .. tostring(missingGems)
    end

    local reasonText = ""
    if (state == "queued" or state == "error") and entry.statusReason and entry.statusReason ~= "" then
        reasonText = " | " .. FormatStatusReason(entry.statusReason)
    end

    return "#" .. tostring(reqId)
        .. " " .. SafeText(reqName)
        .. "-" .. SafeText(reqRealm)
        .. " [" .. state .. "] GS=" .. gsText
        .. auditText
        .. reasonText
        .. ageText
end

local function EntryHasMissingAuditIssues(entry)
    if type(entry) ~= "table" or type(entry.result) ~= "table" then
        return false
    end

    local summary = entry.result.issueSummary or {}
    local missingEnchant = tonumber(summary.missingEnchant or 0) or 0
    local missingGems = tonumber(summary.missingGems or 0) or 0
    return missingEnchant > 0 or missingGems > 0
end

function addon:BuildSlotLine(slotKey, item)
    local slotLabel = SLOT_LABELS[slotKey] or slotKey
    if not item then
        return ColorText(slotLabel .. ": -", "bbbbbb")
    end

    local itemName = item.name
    if not itemName or itemName == "" then
        local itemId = tonumber(item.itemId)
        if itemId then
            itemName = "item:" .. tostring(itemId)
        else
            itemName = "Unknown item"
        end
    end

    local ilvl = tonumber(item.ilvl)
    local ilvlText = ""
    if ilvl and ilvl > 0 then
        ilvlText = " i" .. tostring(ilvl)
    end

    local enchantText = "E:n/a"
    local missingEnchant = false
    if ENCHANTABLE_SLOTS[slotKey] then
        local enchantId = tonumber(item.enchantId)
        if not enchantId then
            if OPTIONAL_ENCHANT_SLOTS[slotKey] then
                enchantText = "E:OPT"
            else
                enchantText = "E:MISS"
                missingEnchant = true
            end
        elseif IsLowTierEnchant(item) then
            enchantText = "E:LOW"
        else
            enchantText = "E:OK"
        end
    end

    local socketCount = tonumber(item.socketCount) or 0
    local gemCount = 0
    local missingGems = false
    if type(item.gems) == "table" then
        gemCount = #item.gems
    end

    local gemText = "G:n/a"
    if socketCount > 0 then
        if gemCount < socketCount then
            gemText = "G:" .. tostring(gemCount) .. "/" .. tostring(socketCount) .. " MISS"
            missingGems = true
        else
            gemText = "G:" .. tostring(socketCount) .. "/" .. tostring(socketCount)
        end
    end

    local line = slotLabel .. ": " .. itemName .. ilvlText .. " | " .. enchantText .. " | " .. gemText
    if missingEnchant or missingGems then
        return ColorText(line, "ff6666")
    end

    if ENCHANTABLE_SLOTS[slotKey] or socketCount > 0 then
        return ColorText(line, "66ff66")
    end

    return ColorText(line, "dddddd")
end

local function ItemMatchesListFilter(mode, slotKey, item)
    if mode == "all" then
        return true
    end

    if type(item) ~= "table" then
        return false
    end

    local missingEnchant = false
    if ENCHANTABLE_SLOTS[slotKey] then
        local enchantId = tonumber(item.enchantId)
        if not enchantId and not OPTIONAL_ENCHANT_SLOTS[slotKey] then
            missingEnchant = true
        end
    end

    local socketCount = tonumber(item.socketCount) or 0
    local gemCount = (type(item.gems) == "table") and #item.gems or 0
    local missingGems = socketCount > 0 and gemCount < socketCount

    if mode == "issues" then
        return missingEnchant or missingGems
    end

    if mode == "missing-enchant" then
        return missingEnchant
    end

    if mode == "missing-gems" then
        return missingGems
    end

    return true
end

function addon:RefreshDetailPanel(selectedEntry)
    if not addon.ui or not addon.ui.detailHeader then
        return
    end

    addon.ui.lastDetailEntry = selectedEntry

    if not selectedEntry then
        addon.ui.detailHeader:SetText("Selected: none")
        addon.ui.detailScore:SetText("Select a player from the left overview.")
        if addon.ui.detailMeta then
            addon.ui.detailMeta:SetText("")
        end
        addon.ui.detailAudit:SetText("")
        addon.ui.detailLineCount = 0
        if addon.ui.detailScroll then
            SetFauxScrollOffset(addon.ui.detailScroll, 0, DETAIL_ROW_HEIGHT)
            FauxScrollFrame_Update(addon.ui.detailScroll, 0, #addon.ui.detailRows, DETAIL_ROW_HEIGHT)
        end
        local i
        for i = 1, #addon.ui.detailRows do
            addon.ui.detailRows[i].text:SetText("")
            addon.ui.detailRows[i].data = nil
        end
        return
    end

    local req = selectedEntry.req
    local result = selectedEntry.result
    addon.ui.detailHeader:SetText("Selected: " .. SafeText(req.name) .. "-" .. SafeText(req.realm) .. " [" .. selectedEntry.state .. "]")

    if not result then
        local reason = FormatStatusReason(req.statusReason)
        if reason == "bridge pending" then
            addon.ui.detailScore:SetText("No result yet (bridge pending). For name-only targets, run bridge fetch after logout/reload, then /ri sync.")
        elseif reason ~= "" then
            addon.ui.detailScore:SetText("No result yet (" .. reason .. "). Use Target/Raid for live inspect, or Sync/Force for bridge data.")
        else
            addon.ui.detailScore:SetText("No result yet. Use Target/Raid for live inspect, or Sync/Force for bridge data.")
        end
        if addon.ui.detailMeta then
            addon.ui.detailMeta:SetText("")
        end
        addon.ui.detailAudit:SetText("")
        addon.ui.detailLineCount = 0
        if addon.ui.detailScroll then
            SetFauxScrollOffset(addon.ui.detailScroll, 0, DETAIL_ROW_HEIGHT)
            FauxScrollFrame_Update(addon.ui.detailScroll, 0, #addon.ui.detailRows, DETAIL_ROW_HEIGHT)
        end
        local i
        for i = 1, #addon.ui.detailRows do
            addon.ui.detailRows[i].text:SetText("")
            addon.ui.detailRows[i].data = nil
        end
        return
    end

    local classText = result.class and tostring(result.class) or "?"
    local specText = result.spec and tostring(result.spec) or "?"
    local guildText = result.guild and tostring(result.guild) or "-"
    local levelText = result.level and tostring(result.level) or "?"
    local scoreValue = result.gearScore and tostring(result.gearScore) or "N/A"
    local scoreColored = result.gearScore and ColorText(scoreValue, GetGearScoreColorCode(result.gearScore)) or scoreValue
    local specColored = ColorText(specText, "ff9933")

    addon.ui.detailScore:SetText(
        "GS: " .. scoreColored .. " | Character: Lvl " .. levelText .. " | " .. classText .. " | Guild: " .. guildText
    )

    if addon.ui.detailMeta then
        addon.ui.detailMeta:SetText("Talent: " .. specColored)
    end

    local summary = result.issueSummary or {}
    local missingEnchant = tonumber(summary.missingEnchant or 0) or 0
    local missingGems = tonumber(summary.missingGems or 0) or 0
    local itemsAnalyzed = tonumber(summary.itemsAnalyzed or 0) or 0
    local socketsFilled = tonumber(summary.filledSockets or 0) or 0
    local socketsTotal = tonumber(summary.totalSockets or 0) or 0

    local missingEnchantText = "missingEnchant=" .. tostring(missingEnchant)
    local missingGemsText = "missingGems=" .. tostring(missingGems)
    local socketsText = "sockets=" .. tostring(socketsFilled) .. "/" .. tostring(socketsTotal)

    if missingEnchant > 0 then
        missingEnchantText = ColorText(missingEnchantText, "ff6666")
    end

    if missingGems > 0 then
        missingGemsText = ColorText(missingGemsText, "ff6666")
    end

    if socketsTotal > 0 and socketsFilled < socketsTotal then
        socketsText = ColorText(socketsText, "ff6666")
    end

    local auditText = "Audit: " .. missingEnchantText
        .. " | " .. missingGemsText
        .. " | " .. socketsText
        .. " | items=" .. tostring(itemsAnalyzed)

    addon.ui.detailAudit:SetText(auditText)

    local itemsBySlot = {}
    local detailLines = {}
    local unslotted = 0
    local filterMode = addon:GetItemListFilterMode()
    local i

    for i = 1, #(result.items or {}) do
        local item = result.items[i]
        local slot = NormalizeSlot(item.slot)
        if slot and not itemsBySlot[slot] then
            itemsBySlot[slot] = item
        else
            unslotted = unslotted + 1
        end
    end

    for i = 1, #SLOT_ORDER do
        local slotKey = SLOT_ORDER[i]
        local slotItem = itemsBySlot[slotKey]
        if ItemMatchesListFilter(filterMode, slotKey, slotItem) then
            table.insert(detailLines, {
                text = addon:BuildSlotLine(slotKey, slotItem),
                item = slotItem,
                slotKey = slotKey,
            })
        end
    end

    if unslotted > 0 and filterMode == "all" then
        table.insert(detailLines, {
            text = ColorText("Other: " .. tostring(unslotted) .. " unslotted item(s)", "ffcc66"),
        })
    end

    if #detailLines == 0 then
        table.insert(detailLines, {
            text = ColorText("No items match selected filter.", "ffcc66"),
        })
    end

    if addon.ui.lastDetailKey ~= selectedEntry.key then
        addon.ui.lastDetailKey = selectedEntry.key
        if addon.ui.detailScroll then
            SetFauxScrollOffset(addon.ui.detailScroll, 0, DETAIL_ROW_HEIGHT)
        end
    end

    addon.ui.detailLineCount = #detailLines

    local offset = 0
    if addon.ui.detailScroll then
        local maxOffset = math.max(0, #detailLines - #addon.ui.detailRows)
        local currentOffset = GetFauxScrollOffset(addon.ui.detailScroll)
        if currentOffset > maxOffset then
            SetFauxScrollOffset(addon.ui.detailScroll, maxOffset, DETAIL_ROW_HEIGHT)
            currentOffset = maxOffset
        end
        FauxScrollFrame_Update(addon.ui.detailScroll, #detailLines, #addon.ui.detailRows, DETAIL_ROW_HEIGHT)
        offset = currentOffset
    end

    local rowIndex
    for rowIndex = 1, #addon.ui.detailRows do
        local lineData = detailLines[rowIndex + offset]
        local row = addon.ui.detailRows[rowIndex]
        if lineData then
            row.text:SetText(lineData.text or "")
            row.data = lineData
        else
            row.text:SetText("")
            row.data = nil
        end
    end
end

function addon:RefreshMainWindow()
    if not addon.ui or not addon.ui.frame then
        return
    end

    addon:ApplyButtonModeLayout()

    local queued, ready, errorCount = addon:GetCounts()
    local fresh, stale = addon:GetFreshnessCounts(FRESHNESS_TTL_SECONDS)
    local playersWithIssues, totalIssues = addon:GetIssueTotals()

    addon.ui.statusText:SetText(
        "Queue: " .. queued
            .. "  |  Ready: " .. ready
            .. "  |  Fresh: " .. fresh
            .. "  |  Stale: " .. stale
            .. "  |  Issues: " .. totalIssues .. " (" .. playersWithIssues .. ")"
            .. "  |  Errors: " .. errorCount
    )

    if addon.ui.sortButton then
        addon.ui.sortButton:SetText("|cff66ff66S:" .. addon:GetSortMode() .. "|r")
    end

    if addon.ui.filterButton then
        addon.ui.filterButton:SetText("|cff66ff66F:" .. addon:GetFilterMode() .. "|r")
    end

    if addon.ui.modeDropDown then
        local selectedMode = addon:GetButtonMode()
        UIDropDownMenu_SetSelectedValue(addon.ui.modeDropDown, selectedMode)
        UIDropDownMenu_SetText(addon.ui.modeDropDown, BUTTON_MODE_LABELS[selectedMode] or selectedMode)
    end

    if addon.ui.itemFilterDropDown then
        local selectedMode = addon:GetItemListFilterMode()
        UIDropDownMenu_SetSelectedValue(addon.ui.itemFilterDropDown, selectedMode)
        UIDropDownMenu_SetText(addon.ui.itemFilterDropDown, ITEM_LIST_FILTER_LABELS[selectedMode] or selectedMode)
    end

    local entries = addon:GetOverviewEntries()
    if #entries == 0 then
        local latestByKey = addon:GetLatestRequestMap()
        local key
        for key in pairs(latestByKey) do
            local req = latestByKey[key]
            local result = RaidInspectorDB.results[key]
            table.insert(entries, {
                key = key,
                req = req,
                result = result,
                state = (result and not result.error) and "ready" or (req.status or "queued"),
                statusReason = req.statusReason,
                updatedAt = result and (tonumber(result.updatedAt) or tonumber(result.fetchedAt) or 0) or 0,
                ageMinutes = -1,
                isFresh = false,
            })
        end
        table.sort(entries, function(a, b)
            return string.lower(tostring(a.key or "")) < string.lower(tostring(b.key or ""))
        end)
    end
    addon.ui.overviewEntryCount = #entries
    local overviewOffset = 0
    if addon.ui.overviewScroll then
        local maxOverviewOffset = math.max(0, #entries - #addon.ui.overviewRows)
        local currentOverviewOffset = GetFauxScrollOffset(addon.ui.overviewScroll)
        if currentOverviewOffset > maxOverviewOffset then
            SetFauxScrollOffset(addon.ui.overviewScroll, maxOverviewOffset, OVERVIEW_ROW_HEIGHT)
            currentOverviewOffset = maxOverviewOffset
        end
        FauxScrollFrame_Update(addon.ui.overviewScroll, #entries, #addon.ui.overviewRows, OVERVIEW_ROW_HEIGHT)
        overviewOffset = currentOverviewOffset
    end

    local selectedKey = addon:GetSelectedKey()
    local selectedEntry = nil
    local i

    for i = 1, #entries do
        if entries[i].key == selectedKey then
            selectedEntry = entries[i]
            break
        end
    end

    if selectedKey == "" or not addon:GetLatestRequestForKey(selectedKey) then
        if #entries > 0 then
            selectedKey = entries[1].key
            addon:SetSelectedKey(selectedKey)
        else
            selectedKey = ""
            addon:SetSelectedKey("")
        end
    end

    if not selectedEntry and #entries > 0 then
        selectedEntry = entries[1]
        selectedKey = entries[1].key
        addon:SetSelectedKey(selectedKey)
    end

    local rowIndex
    for rowIndex = 1, #addon.ui.overviewRows do
        local row = addon.ui.overviewRows[rowIndex]
        local entry = entries[rowIndex + overviewOffset]
        if entry then
            row.key = entry.key
            row.text:SetText(addon:BuildOverviewRowText(entry))
            local hasAuditIssues = EntryHasMissingAuditIssues(entry)
            if hasAuditIssues then
                row.text:SetTextColor(1.0, 0.20, 0.20)
            else
                row.text:SetTextColor(0.35, 1.0, 0.35)
            end
            SetFontStringBold(row.text, entry.key == selectedKey)
            row:Show()
        else
            row.key = nil
            row.text:SetText("")
            row.text:SetTextColor(1.0, 1.0, 1.0)
            SetFontStringBold(row.text, false)
        end
    end

    addon:RefreshDetailPanel(selectedEntry)
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

function addon:FindUnitByName(name)
    local wanted = string.lower(name or "")
    if wanted == "" then
        return nil
    end

    local function MatchUnit(unit)
        if not UnitExists(unit) then
            return false
        end
        local unitName = UnitName(unit)
        return unitName and string.lower(unitName) == wanted
    end

    if MatchUnit("target") then
        return "target"
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        local i
        for i = 1, GetNumRaidMembers() do
            local raidUnit = "raid" .. tostring(i)
            if MatchUnit(raidUnit) then
                return raidUnit
            end
        end
    end

    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        local i
        for i = 1, GetNumPartyMembers() do
            local partyUnit = "party" .. tostring(i)
            if MatchUnit(partyUnit) then
                return partyUnit
            end
        end
    end

    return nil
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

    addon:QueueInspect(name, realm, { reason = "queued-manual" })

    local foundUnit = addon:FindUnitByName(name)
    if foundUnit then
        local okLive = addon:QueueLiveInspectUnit(foundUnit, false)
        if okLive then
            addon:ProcessInspectQueue(true)
        end
    else
        local resolvedRealm = Trim(realm)
        if resolvedRealm == "" then
            resolvedRealm = GetCVar("realmName") or ""
        end
        if resolvedRealm ~= "" then
            addon:SetLatestRequestState(MakePlayerKey(name, resolvedRealm), "queued", "bridge-pending")
        end
    end
end

function addon:BuildExportSummaryFromPayload(payload)
    if type(payload) ~= "table" then
        return nil
    end

    local score = payload.gearScore and tostring(payload.gearScore) or "N/A"
    local talent = Trim(payload.spec or "")
    local summary = payload.issueSummary or {}
    local missingEnchant = tonumber(summary.missingEnchant or 0) or 0
    local missingGems = tonumber(summary.missingGems or 0) or 0

    return "RI " .. tostring(payload.name or "Unknown")
        .. "-" .. tostring(payload.realm or "Unknown")
        .. " | GS:" .. score
        .. " | Talent:" .. (talent ~= "" and talent or "?")
        .. " | MissingGems/Enchants:" .. tostring(missingGems) .. "/" .. tostring(missingEnchant)
end

function addon:BuildExportSummary(entry)
    if not entry then
        return nil
    end

    local payload = addon:BuildStoredSummaryPayload(entry.key, entry.req, entry.result, entry.state, entry.statusReason)
    return addon:BuildExportSummaryFromPayload(payload)
end

function addon:SendSummaryMessage(message, whisperTarget)
    local chatMessage = EscapeChatMessage(message)
    local channels = addon:GetExportChannels()
    local attempted = 0
    local sent = 0

    if channels.raid then
        attempted = attempted + 1
        if GetNumRaidMembers and GetNumRaidMembers() > 0 then
            SendChatMessage(chatMessage, "RAID")
            sent = sent + 1
        else
            Print("export: RAID checked, but you are not in a raid")
        end
    end

    if channels.say then
        attempted = attempted + 1
        SendChatMessage(chatMessage, "SAY")
        sent = sent + 1
    end

    if channels.whisper then
        attempted = attempted + 1
        local targetName = Trim(whisperTarget or "")
        if targetName ~= "" then
            SendChatMessage(chatMessage, "WHISPER", nil, targetName)
            sent = sent + 1
        else
            Print("export: WHISPER checked, but selected player name is missing")
        end
    end

    if attempted == 0 then
        Print("export: no channels selected (Raid/Say/Whisper)")
        return 0, 0, chatMessage
    end

    if sent == 0 then
        Print(chatMessage)
    end

    return attempted, sent, chatMessage
end

function addon:SaveReportSnapshot(arg)
    local entry, err = addon:ResolveOverviewEntry(arg)
    if not entry then
        Print(err)
        return nil
    end

    local snapshot = addon:StoreReportSnapshot(entry, "manual")
    if not snapshot then
        Print("could not save report snapshot")
        return nil
    end

    Print("saved report #" .. tostring(snapshot.id) .. ": " .. tostring(snapshot.name) .. "-" .. tostring(snapshot.realm))
    return snapshot
end

function addon:ExportSavedReport(arg)
    local snapshot, err = addon:FindSavedReport(arg)
    if not snapshot then
        Print(err)
        return
    end

    local message = addon:BuildExportSummaryFromPayload(snapshot.payload) or snapshot.message
    if not message then
        Print("saved report is empty")
        return
    end

    addon:SendSummaryMessage(message, snapshot.name)
end

function addon:ExportSummary(arg)
    local selected, err = addon:ResolveOverviewEntry(arg)
    if not selected then
        Print(err)
        return
    end

    local message = addon:BuildExportSummary(selected)
    if not message then
        Print("nothing to export")
        return
    end

    addon:StoreReportSnapshot(selected, "export")
    addon:SendSummaryMessage(message, selected and selected.req and selected.req.name)
end

function addon:PrintStatus()
    addon:PruneRaidScanHistory()
    local queued, ready, errorCount = addon:GetCounts()
    local fresh, stale = addon:GetFreshnessCounts(FRESHNESS_TTL_SECONDS)
    local playersWithIssues, totalIssues = addon:GetIssueTotals()
    local bridge = addon:GetBridgeInboxStats()
    local reports = addon:GetReportSnapshots()
    local history = addon:GetRaidScanHistory()
    local livePending = addon.inspectQueue and #addon.inspectQueue or 0
    local liveActive = addon.inspectCurrent and (addon.inspectCurrent.name .. "-" .. addon.inspectCurrent.realm) or "-"
    local achievementPending = addon.achievementQueue and #addon.achievementQueue or 0
    local achievementActive = addon.achievementCurrent and (addon.achievementCurrent.name .. "-" .. addon.achievementCurrent.realm) or "-"
    local achievementSupported = (type(SetAchievementComparisonUnit) == "function" and type(GetComparisonAchievementPoints) == "function") and "yes" or "no"

    Print("schema v" .. tostring(RaidInspectorDB.meta.schemaVersion))
    Print("requests: " .. tostring(#RaidInspectorDB.requests))
    Print("queued=" .. queued .. ", ready=" .. ready .. ", fresh=" .. fresh .. ", stale=" .. stale .. ", errors=" .. errorCount)
    Print("issues: total=" .. totalIssues .. ", playersWithIssues=" .. playersWithIssues)
    Print("overview mode: sort=" .. addon:GetSortMode() .. ", filter=" .. addon:GetFilterMode())
    Print("live inspect: pending=" .. tostring(livePending) .. ", active=" .. tostring(liveActive))
    Print("achievement compare: supported=" .. achievementSupported .. ", pending=" .. tostring(achievementPending) .. ", active=" .. tostring(achievementActive))
    Print("saved reports=" .. tostring(#reports.items) .. ", raid scan history=" .. tostring(#history.scans))
    Print("bridge inbox: count=" .. bridge.resultCount .. ", generatedAt=" .. bridge.generatedAt .. ", lastConsumedAt=" .. bridge.lastConsumedAt)
    Print("bridge import marker: lastImportedGeneratedAt=" .. bridge.lastImportedBridgeGeneratedAt)

    local progress = addon:GetSnapshotProgress()
    if progress then
        Print("snapshot: fresh=" .. progress.ready .. "/" .. progress.total .. ", stale=" .. progress.stale .. ", missing=" .. progress.missing)
    end

    Print("bridge status: optional for remote/name-only data; close WoW before running bridge writer, then relog/reload")
end

function addon:ClearQueue()
    RaidInspectorDB.requests = {}
    RaidInspectorDB.results = {}
    RaidInspectorDB.state.lastSnapshot = { at = 0, historyId = 0, members = {} }
    RaidInspectorDB.state.nextRequestId = 1
    RaidInspectorDB.meta.lastImportedBridgeGeneratedAt = 0

    addon:InitBridgeInbox()
    RaidInspectorBridgeInbox.results = {}
    RaidInspectorBridgeInbox.generatedAt = 0
    RaidInspectorBridgeInbox.lastConsumedAt = GetNow()

    addon.inspectQueue = {}
    addon.inspectQueuedKeys = {}
    addon.inspectCurrent = nil
    addon.inspectTickAccum = 0
    addon.achievementQueue = {}
    addon.achievementQueuedKeys = {}
    addon.achievementCurrent = nil
    addon.achievementLastRequestAt = 0
    if ClearInspectPlayer then
        ClearInspectPlayer()
    end
    ClearAchievementComparisonUnitSafe()
    addon:SetSelectedKey("")
    Print("queue + results + bridge inbox cleared")
    addon:RefreshMainWindow()
end

function addon:RequestClearQueue()
    if type(StaticPopup_Show) ~= "function" or type(StaticPopupDialogs) ~= "table" then
        addon:ClearQueue()
        return
    end

    StaticPopup_Hide("RAIDINSPECTOR_CONFIRM_CLEAR")
    StaticPopup_Show("RAIDINSPECTOR_CONFIRM_CLEAR")
end

if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs["RAIDINSPECTOR_CONFIRM_CLEAR"] = {
        text = "Clear queued requests, cached results, and bridge inbox data?",
        button1 = "Clear",
        button2 = CANCEL or "Cancel",
        OnAccept = function()
            addon:ClearQueue()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

function addon:OnAddonLoaded(loadedName)
    if loadedName ~= addon.name then
        return
    end

    addon:InitDatabase()
    addon:InitBridgeInbox()
    addon:InitInspectRuntime()
    addon:CreateMainWindow()
end

function addon:OnPlayerLogin()
    addon:InitInspectRuntime()
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
    SafeInvoke("slash", function()
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
            Print("/ri inspecttarget - queue + live inspect current target")
            Print("/ri inspectraid - snapshot + live inspect current raid members")
            Print("/ri inspecttarget and /ri inspectraid also attempt in-game AP comparison (inspectable targets)")
            Print("/ri sync - import bridge inbox results")
            Print("/ri forcesync - re-import bridge inbox ignoring generatedAt")
            Print("/ri sort [recent|gs|issues|name] - set or cycle sort")
            Print("/ri filter [all|snapshot|ready|queued|issues] - set or cycle filter")
            Print("/ri savereport [name-realm] - save current or selected report snapshot")
            Print("/ri export [name-realm] - quick summary to raid/party chat")
            Print("/ri exportsaved [latest|id|name-realm] - export saved snapshot")
            Print("/ri status - show queue summary")
            Print("/ri refreshstale [minutes] - queue refresh for stale results")
            Print("/ri clearqueue [confirm] - clear queue/results with confirmation")
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

        if command == "inspectraid" then
            addon:QueueRaidSnapshot()
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

        if command == "sort" then
            local mode = string.lower(Trim(args))
            if mode == "" then
                addon:CycleSortMode()
            elseif not addon:SetSortMode(mode) then
                Print("invalid sort mode. use: recent, gs, issues, name")
            end
            return
        end

        if command == "filter" then
            local mode = string.lower(Trim(args))
            if mode == "" then
                addon:CycleFilterMode()
            elseif not addon:SetFilterMode(mode) then
                Print("invalid filter mode. use: all, snapshot, ready, queued, issues")
            end
            return
        end

        if command == "savereport" then
            addon:SaveReportSnapshot(args)
            return
        end

        if command == "export" then
            addon:ExportSummary(args)
            return
        end

        if command == "exportsaved" then
            addon:ExportSavedReport(args)
            return
        end

        if command == "status" then
            addon:PrintStatus()
            addon:RefreshMainWindow()
            return
        end

        if command == "refreshstale" then
            addon:QueueStaleRefresh(args)
            return
        end

        if command == "clearqueue" then
            local mode = string.lower(Trim(args or ""))
            if mode == "confirm" or mode == "force" or mode == "yes" then
                addon:ClearQueue()
            else
                addon:RequestClearQueue()
            end
            return
        end

        if command == "reload" then
            ReloadUI()
            return
        end

        Print("unknown command. use /ri help")
    end)
end

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("INSPECT_READY")
events:SetScript("OnEvent", function(_, event, ...)
    local arg1 = select(1, ...)
    SafeInvoke("event " .. tostring(event), function()
        if event == "ADDON_LOADED" then
            addon:OnAddonLoaded(arg1)
        elseif event == "PLAYER_LOGIN" then
            addon:OnPlayerLogin()
        elseif event == "INSPECT_READY" then
            addon:OnInspectReady(arg1)
        end
    end)
end)
events:SetScript("OnUpdate", function(_, elapsed)
    SafeInvoke("onupdate", function()
        addon:OnUpdate(elapsed)
    end)
end)
